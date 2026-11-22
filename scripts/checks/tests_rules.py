"""The test-suite rules: discovery, base contract, assertions and shipped-file reads."""
from __future__ import annotations

import re
from pathlib import Path

from .context import TESTS, read_text
from .failure import Failure, rel
from .text import line_of

TEST_SUITE_CHECK = re.compile(r"^func check\(", re.MULTILINE)
TEST_SUITE_RESULT = re.compile(r"_RESULT checks=")
TEST_SUITE_BASE = re.compile(
    r'^extends\s+"res://mods/unfplap/tests/support/suite\.gd"', re.MULTILINE)
TEST_SUITE_BASE_PATH = TESTS / "support" / "suite.gd"
TEST_SUITE_RUN = re.compile(r"^func run\(", re.MULTILINE)
TEST_SUITE_ASSERTION = re.compile(
    r"\b(?:check|check_eq|check_ne|check_approx|check_contains|check_empty|check_size"
    r"|check_same|check_null|check_not_null|fail)\(")
TEST_SUITE_LOCAL = re.compile(
    r"^func (?:check|check_eq|check_ne|check_approx|check_contains|check_empty|check_size"
    r"|check_same|check_null|check_not_null|fail|near|_initialize|finish|_result_prefix)\(",
    re.MULTILINE)
TEST_SUITE_QUIT = re.compile(r"^\s*quit\(", re.MULTILINE)
TEST_TRUE_CALL = re.compile(r"\bcheck\(\s*true\b")
TEST_NUMERIC_LITERAL = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])")
TEST_SETTING_DEFAULT = re.compile(r"[A-Za-z_][\w.]*\.default\b")
# The suites that name a shipped data document, and the names a read must go through a loader for.
SHIPPED_DOCUMENT_TEST_READS = ("tests/test_settings.gd", "tests/test_prompts.gd")
SHIPPED_DOCUMENT_NAME = re.compile(
    r"DEFAULTS_FILE|SETTINGS_FILE|CHARACTERS_FILE|PROMPTS_FILE"
    r"|settings\.json|characters\.json|prompts\.json")

# The only suites that read a shipped file, and the document each reads: a data document with no
# loader, a fixture or a copied asset whose bytes are the contract. The map is the whole allow-list,
# so a new read is a review instead of a copy-paste, and no suite greps production source or docs.
TEST_FILE_READS = {
    "tests/test_settings.gd": "the shipped defaults document and its backups",
    "tests/test_api.gd": "docs/api.md",
    "tests/poses/test_pose_bake.gd": "the shipped standing asset bytes",
    "tests/poses/test_pose_edge.gd": "the pose edge JSON fixtures",
    "tests/hands/test_caress.gd": "the areas JSON fixture",
    "tests/anatomy/test_geometry.gd": "the coat shader's sample count",
    "tests/integrations/test_pantyhose.gd": "the copied shader includes",
}

# A fallback-to-default check is behaviour, not a copied default: the literal is the caller's
# fallback argument. Only this pair is allowed to name a declaration default next to a literal.
TEST_DEFAULT_FALLBACK = {
    ("tests/poses/test_session.gd", "SETTINGS.chin_up_deg.default"),
}


def is_lab(path: Path) -> bool:
    return path.name.startswith("test_lab") or path.name == "test_stress_lab.gd"


def test_suites() -> list[Path]:
    """The runner's discovery: tests/<name>.gd and tests/<dir>/<name>.gd, no manual labs."""
    return sorted(
        path for path in TESTS.rglob("test_*.gd")
        if len(path.relative_to(TESTS).parts) <= 2 and not is_lab(path)
    )


def check_calls(text: str) -> list[tuple[int, str]]:
    """Every check(...) call with its line, parentheses balanced across lines."""
    calls: list[tuple[int, str]] = []
    for match in re.finditer(r"\bcheck\(", text):
        depth = 1
        cursor = match.end()
        while cursor < len(text) and depth:
            if text[cursor] == "(":
                depth += 1
            elif text[cursor] == ")":
                depth -= 1
            cursor += 1
        calls.append((line_of(text, match.start()), text[match.start():cursor]))
    return calls


def suite_result_failures(name: str, text: str) -> list[str]:
    """A suite never prints the result line: the base owns it."""
    return ["%s:%d prints the result line: the base owns it" % (name, line_of(text, match.start()))
            for match in TEST_SUITE_RESULT.finditer(text)]


def check_tests(failure: Failure) -> None:
    # The base owns the helpers, the lifecycle, the result line and the exit: a suite only
    # extends it, implements run() and asserts.
    for path in test_suites():
        text = read_text(str(path))
        name = rel(path)
        if not TEST_SUITE_BASE.search(text):
            failure.add("%s:1 must extend %s" % (name, rel(TEST_SUITE_BASE_PATH)))
        if not TEST_SUITE_RUN.search(text):
            failure.add("%s:1 must implement run()" % name)
        if not TEST_SUITE_ASSERTION.search(text):
            failure.add("%s:1 must call an assertion helper" % name)
        failure.extend(suite_result_failures(name, text))
        for match in TEST_SUITE_LOCAL.finditer(text):
            failure.add("%s:%d defines a base-owned helper: %s" % (
                name, line_of(text, match.start()), match.group(0).removesuffix("(")))
        for match in TEST_SUITE_QUIT.finditer(text):
            failure.add("%s:%d calls quit(): the base owns the exit" % (
                name, line_of(text, match.start())))

    # The base carries the helper and the result line for every suite that extends it.
    if not TEST_SUITE_BASE_PATH.exists():
        failure.add("%s is missing" % rel(TEST_SUITE_BASE_PATH))
    else:
        base_text = read_text(str(TEST_SUITE_BASE_PATH))
        if not TEST_SUITE_CHECK.search(base_text):
            failure.add("%s does not define a check() helper" % rel(TEST_SUITE_BASE_PATH))
        if not TEST_SUITE_RESULT.search(base_text):
            failure.add("%s does not print a _RESULT check summary" % rel(TEST_SUITE_BASE_PATH))

    for path in sorted(TESTS.rglob("*.gd")):
        text = read_text(str(path))
        name = rel(path)
        # check(true, ...) cannot fail, whatever the text says.
        for match in TEST_TRUE_CALL.finditer(text):
            failure.add("%s:%d calls check(true, ...): assert the observed value" % (
                name, line_of(text, match.start())))
        # The schema test and the prompt graph test own the reads of the shipped documents.
        if name not in SHIPPED_DOCUMENT_TEST_READS:
            for match in SHIPPED_DOCUMENT_NAME.finditer(text):
                failure.add("%s:%d reads a shipped data document outside its own suite" % (
                    name, line_of(text, match.start())))
        # Reading a file is reading a document; source and doc purity scans are the gate's job.
        if not is_lab(path) and "get_file_as_string" in text and name not in TEST_FILE_READS:
            failure.add("%s reads a shipped file with FileAccess.get_file_as_string" % name)
        # A declaration default next to a numeric literal is a copied value, not a behaviour.
        for line, call in check_calls(text):
            if ".default" not in call or not TEST_NUMERIC_LITERAL.search(call):
                continue
            refs = set(TEST_SETTING_DEFAULT.findall(call))
            if any((name, ref) in TEST_DEFAULT_FALLBACK for ref in refs):
                continue
            failure.add("%s:%d compares a declaration default to a numeric literal" % (name, line))
