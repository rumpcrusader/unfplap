#!/usr/bin/env python3
"""Gate comment shape: block size, private names, doc pointers, copied doc prose.

Blocks are runs of line-leading comments, so a shape failure is reported once per block.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_PREFIXES = ("tests/", "tools/")
ENGINE_VIRTUALS = frozenset(
    {
        "_ready",
        "_init",
        "_enter_tree",
        "_exit_tree",
        "_process",
        "_physics_process",
        "_input",
        "_unhandled_input",
        "_unhandled_key_input",
        "_shortcut_input",
        "_draw",
        "_notification",
        "_to_string",
    }
)
GRAM = 6
MIN_SENTENCE_WORDS = 8
HEADER_MAX = 5
DOC_MAX = 2
INLINE_MAX = 3

COMMENT_RE = re.compile(r"^\s*#")
DOC_LINE_RE = re.compile(r"^\s*##")
DECLARATION_RE = re.compile(r"^(?:extends\b|@tool\b|class_name\b)")
BODY_RE = re.compile(r"^\s*#+ ?")
POINTER_RE = re.compile(r"`(docs/[A-Za-z0-9_./-]+\.md)`")
PRIVATE_SPAN_RE = re.compile(r"`(_[a-z][a-z0-9_]*(?:\(\))?)`")
SENTENCE_RE = re.compile(r"(?<=[.!?])\s+")
CODE_SPAN_RE = re.compile(r"`[^`]*`")
NON_WORD_RE = re.compile(r"[^a-z0-9]+")


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    text: str


@dataclass(frozen=True)
class Block:
    line: int
    first: str
    lines: list[str]
    doc: bool
    header: bool


@dataclass(frozen=True)
class Docs:
    texts: dict[str, str]
    gram_docs: dict[str, set[str]]


def is_scanned(path: str) -> bool:
    return path.endswith(".gd") and not path.startswith(SKIP_PREFIXES)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def normalise_words(text: str) -> list[str]:
    # Code spans become one token so identifiers neither match nor dominate word counts.
    text = CODE_SPAN_RE.sub(" x ", text.lower())
    return NON_WORD_RE.sub(" ", text).split()


def grams_of(tokens: list[str]) -> set[str]:
    return {" ".join(tokens[i : i + GRAM]) for i in range(len(tokens) - GRAM + 1)}


def docs_from_texts(texts: dict[str, str]) -> Docs:
    gram_docs: dict[str, set[str]] = {}
    for name, content in texts.items():
        for gram in grams_of(normalise_words(content)):
            gram_docs.setdefault(gram, set()).add(name)
    return Docs(texts, gram_docs)


def load_docs(root: Path) -> Docs:
    paths = sorted((root / "docs").glob("*.md"))
    paths.append(root / "ARCHITECTURE.md")
    texts = {
        path.relative_to(root).as_posix(): read_text(path)
        for path in paths
        if path.is_file()
    }
    return docs_from_texts(texts)


def is_comment(line: str) -> bool:
    return COMMENT_RE.match(line) is not None


def is_code(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not is_comment(line) and DECLARATION_RE.match(stripped) is None


def comment_body(line: str) -> str:
    return BODY_RE.sub("", line)


def comment_blocks(text: str) -> list[Block]:
    lines = text.splitlines()
    blocks: list[Block] = []
    code_seen = False
    header_taken = False
    index = 0
    while index < len(lines):
        if not is_comment(lines[index]):
            code_seen = code_seen or is_code(lines[index])
            index += 1
            continue
        end = index
        while end < len(lines) and is_comment(lines[end]):
            end += 1
        raw = lines[index:end]
        doc = DOC_LINE_RE.match(raw[0]) is not None
        header = doc and not code_seen and not header_taken
        header_taken = header_taken or header
        blocks.append(
            Block(
                index + 1,
                raw[0].strip(),
                [comment_body(line) for line in raw],
                doc,
                header,
            )
        )
        index = end
    return blocks


def private_name_in(block: Block) -> bool:
    for line in block.lines:
        for match in PRIVATE_SPAN_RE.finditer(line):
            name = match.group(1).removesuffix("()")
            if name not in ENGINE_VIRTUALS:
                return True
    return False


def pointer_broken(block: Block, docs: Docs) -> bool:
    """A `docs/...md` pointer must name a doc that exists. A heading in the same span is prose."""
    text = "\n".join(block.lines)
    pointers = POINTER_RE.findall(text)
    return any(relative not in docs.texts for relative in pointers)


def duplicate_of_docs(block: Block, docs: Docs) -> bool:
    prose = " ".join(block.lines)
    for sentence in SENTENCE_RE.split(prose):
        if len(sentence.split()) < MIN_SENTENCE_WORDS:
            continue
        tokens = normalise_words(sentence)
        hits: dict[str, int] = {}
        for gram in grams_of(tokens):
            for name in docs.gram_docs.get(gram, ()):
                hits[name] = hits.get(name, 0) + 1
        if any(count >= 2 for count in hits.values()):
            return True
    return False


def block_rules(block: Block, docs: Docs) -> list[str]:
    rules: list[str] = []
    size = len(block.lines)
    if block.header and size > HEADER_MAX:
        rules.append("R1")
    elif block.doc and not block.header and size > DOC_MAX:
        rules.append("R2")
    elif not block.doc and size > INLINE_MAX:
        rules.append("R3")
    if private_name_in(block):
        rules.append("R4")
    if pointer_broken(block, docs):
        rules.append("R5")
    if duplicate_of_docs(block, docs):
        rules.append("R6")
    return rules


def scan_text(text: str, path: str, docs: Docs) -> list[Finding]:
    return [
        Finding(path, block.line, rule, block.first[:80])
        for block in comment_blocks(text)
        for rule in block_rules(block, docs)
    ]


def tracked_files(root: Path) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "*.gd"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"COMMENTS_FAIL cannot list tracked files: {error}") from error
    return sorted(line for line in result.stdout.splitlines() if is_scanned(line))


def header_fixture(lines: int) -> str:
    body = "".join(f"## note {index}\n" for index in range(1, lines + 1))
    return body + "extends Node\n"


def block_fixture(lines: int, before: str = "extends Node", marker: str = "#") -> str:
    body = "".join(f"{marker} note {index}\n" for index in range(1, lines + 1))
    return f"{before}\n{body}"


def named_comment(name: str) -> str:
    return f"extends Node\n# mention `{name}` in prose\n"


def pointer_comment(text: str) -> str:
    return f"extends Node\n# {text}\n"


TEST_DOC = """# Face

## Some Heading

The runtime schedules every pony action through the shared act facts dictionary before the camera tick.
"""


def self_test() -> int:
    docs = docs_from_texts(
        {
            "docs/face.md": TEST_DOC,
            "docs/extra.md": "# Extra\n\n## Other Section\n\nUnrelated material.\n",
        }
    )
    copied = (
        "The runtime schedules every pony action through the shared act facts "
        "dictionary before the camera tick."
    )
    distinct = (
        "Measured wording about unrelated topics keeps these fixtures apart "
        "from the whole corpus entirely."
    )
    crlf_indented = "extends Node\r\n" + "".join(f"    # note {i}\r\n" for i in range(1, 5))
    cases: list[tuple[str, str, str, set[str]]] = [
        ("R1", "6-line header fires", header_fixture(6), {"R1"}),
        ("R1", "5-line header passes", header_fixture(5), set()),
        ("R2", "3-line doc block fires", block_fixture(3, "const X = 1", "##"), {"R2"}),
        ("R2", "2-line doc block passes", block_fixture(2, "const X = 1", "##"), set()),
        ("R3", "4-line implementation block fires", block_fixture(4), {"R3"}),
        ("R3", "3-line implementation block passes", block_fixture(3), set()),
        ("R4", "private name fires", named_comment("_private"), {"R4"}),
        ("R4", "engine virtual passes", named_comment("_ready"), set()),
        ("R4", "virtual with call passes", named_comment("_ready()"), set()),
        ("R4", "public name passes", named_comment("public_name"), set()),
        ("R4", "bare underscore passes", named_comment("_"), set()),
        ("R5", "missing doc fires", pointer_comment("see `docs/missing.md` for more"), {"R5"}),
        ("R5", "existing doc passes", pointer_comment("see `docs/face.md` for more"), set()),
        (
            "R5",
            "heading-shaped span is prose",
            pointer_comment("see `docs/face.md` `## No Such Heading`"),
            set(),
        ),
        (
            "R5",
            "one missing doc among several fires",
            pointer_comment("see `docs/face.md` and `docs/missing.md`"),
            {"R5"},
        ),
        ("R6", "copied sentence fires", f"extends Node\n# {copied}\n", {"R6"}),
        ("R6", "distinct sentence passes", f"extends Node\n# {distinct}\n", set()),
        ("R1", "CRLF header fires", header_fixture(6).replace("\n", "\r\n"), {"R1"}),
        ("R3", "indented CRLF block fires", crlf_indented, {"R3"}),
    ]
    failures = 0
    for rule, label, text, expected in cases:
        actual = {finding.rule for finding in scan_text(text, "fixture.gd", docs)}
        if actual == expected:
            print(f"ok   {rule} {label}")
            continue
        failures += 1
        print(f"FAIL {rule} {label}: expected {sorted(expected)} got {sorted(actual)}")
    filter_cases = (
        ("tests/test_x.gd", False),
        ("tools/gen_x.gd", False),
        ("scripts/app.gd", True),
        ("tests_extra/app.gd", True),
        ("scripts/comments.py", False),
    )
    for path, expected in filter_cases:
        if is_scanned(path) == expected:
            print(f"ok   FILTER {path} -> {expected}")
            continue
        failures += 1
        print(f"FAIL FILTER {path}: expected {expected}")
    if failures:
        print(f"SELF_TEST_FAIL {failures}")
        return 1
    print(f"SELF_TEST_PASS {len(cases) + len(filter_cases)}")
    return 0


def audit(paths: int, findings: list[Finding]) -> None:
    counts = {f"R{index}": 0 for index in range(1, 7)}
    for finding in findings:
        counts[finding.rule] += 1
    payload = {
        "files": paths,
        "counts": counts,
        "findings": [
            {"path": finding.path, "line": finding.line, "rule": finding.rule}
            for finding in findings
        ],
    }
    print(json.dumps(payload, indent=2))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Comment shape gate.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="list violating blocks")
    mode.add_argument("--audit", action="store_true", help="print every finding as JSON")
    mode.add_argument("--self-test", action="store_true", help="run in-memory fixtures")
    parser.add_argument("--root", default=str(ROOT), help="repository root")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()

    root = Path(args.root).resolve()
    docs = load_docs(root)
    paths = tracked_files(root)
    findings = [
        finding
        for path in paths
        for finding in scan_text(read_text(root / path), path, docs)
    ]
    findings.sort(key=lambda finding: (finding.path, finding.line, finding.rule))

    if args.audit:
        audit(len(paths), findings)
        return 0
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}: {finding.text}")
    if findings:
        print(f"COMMENTS_FAIL {len(findings)}")
        return 1
    print(f"COMMENTS_PASS files={len(paths)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
