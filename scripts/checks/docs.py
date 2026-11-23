"""The documentation index, facade notes and the cross-mod API surface."""
from __future__ import annotations

import re
from pathlib import Path

from .context import DOCS, ROOT, SCOPES, SERVICES, facade_for, facade_scope
from .failure import Failure, rel

# The index's service table is the one router: a row names the contract and the tests. The table
# row is parsed, not a section in the contract.
SERVICE_INDEX = "## Services"
TABLE_ROW = re.compile(r"^\|(.*)\|\s*$", re.MULTILINE)
SERVICE_IGNORE_DOCS = {"README.md", "api.md", "runtime.md"}
# A facade's public types carry a `##` note; api.gd's public members are the strict surface.
PUBLIC_TYPE = re.compile(r"^(?:class|enum)\s+([A-Za-z_]\w*)\b", re.MULTILINE)
API_MEMBER = re.compile(
    r"^(?:const\s+([A-Z][A-Z0-9_]*)|(?:static\s+)?func\s+([A-Za-z_]\w*)|var\s+([A-Za-z_]\w*))")


def doc_path(sid: str) -> Path:
    return DOCS / f"{sid}.md"


def parse_service_index(text: str) -> dict[str, list[dict[str, str]]]:
    """The docs/README.md Services table, keyed by service id.

    A row's Contract cell names the service's ``docs/<sid>.md``; its Tests cell is the router to
    the live suites. The table is the one index row a service owns.
    """
    heading = re.search(r"^%s\s*$" % re.escape(SERVICE_INDEX), text, re.MULTILINE)
    if not heading:
        return {}
    section = text[heading.end():]
    next_heading = re.search(r"^## ", section, re.MULTILINE)
    if next_heading:
        section = section[:next_heading.start()]
    rows: dict[str, list[dict[str, str]]] = {}
    for match in TABLE_ROW.finditer(section):
        cells = [cell.strip() for cell in match.group(1).split("|")]
        if len(cells) < 4 or set(cells[0]) <= {"-", ":"}:
            continue
        contract = cells[2].strip("`")
        found = re.fullmatch(r"docs/([a-z0-9_]+)\.md", contract)
        if not found:
            continue
        rows.setdefault(found.group(1), []).append({
            "contract": contract,
            "tests": cells[3].strip("`"),
            "scope": cells[4].strip("`") if len(cells) > 4 else "",
        })
    return rows


def check_service_index(failure: Failure, text: str, docs: Path, services: list[str]) -> None:
    """Every service owns exactly one index row whose contract and tests resolve."""
    rows = parse_service_index(text)
    for sid in services:
        found = rows.get(sid, [])
        if not found:
            failure.add("docs/README.md has no Services row for %s" % sid)
            continue
        if len(found) > 1:
            failure.add("docs/README.md has %d Services rows for %s" % (len(found), sid))
            continue
        row = found[0]
        if not (docs / row["contract"].removeprefix("docs/")).is_file():
            failure.add("docs/README.md row for %s names a missing contract: %s" % (
                sid, row["contract"]))
        paths = [path.strip(" `") for path in row["tests"].split(",")]
        if not any((docs.parent / path).exists() for path in paths if path):
            failure.add("docs/README.md row for %s names no test path that exists" % sid)
    failure.extend(unknown_index_rows(text, services))


def unknown_index_rows(text: str, services: list[str]) -> list[str]:
    """A Services row names a directory with a facade; `Other` is never indexed."""
    rows = parse_service_index(text)
    return [
        "docs/README.md indexes a Services row for an unknown service: %s" % sid
        for sid in sorted(set(rows) - set(services))
    ]


def index_scope_failures(text: str, scopes: dict[str, str]) -> list[str]:
    """Every Services row's Scope cell repeats its facade's declaration."""
    out: list[str] = []
    for sid, found in sorted(parse_service_index(text).items()):
        declared = scopes.get(sid, "")
        for row in found:
            cell = row["scope"]
            if not cell:
                out.append("docs/README.md has no Scope for %s" % sid)
            elif cell not in SCOPES:
                out.append("docs/README.md has an unknown Scope for %s: %s" % (sid, cell))
            elif declared and cell != declared:
                out.append(
                    "docs/README.md Scope for %s is %s, the facade declares %s" % (
                        sid, cell, declared))
    return out


def check_index_scopes(failure: Failure) -> None:
    index = (DOCS / "README.md").read_text(encoding="utf-8")
    scopes = {sid: facade_scope(sid) for sid in SERVICES}
    failure.extend(index_scope_failures(index, scopes))


def check_docs(failure: Failure, docs: Path = DOCS, services: list[str] | None = None) -> int:
    failures = 0
    services = SERVICES if services is None else services
    index = (docs / "README.md").read_text(encoding="utf-8")
    for path in sorted(docs.glob("*.md")):
        if path.name == "README.md":
            continue
        if path.name not in index:
            failure.add("docs/README.md does not index docs/%s" % path.name)
            failures += 1
    check_service_index(failure, index, docs, services)
    for sid in services:
        path = docs / f"{sid}.md"
        if not path.exists():
            failure.add("missing service contract: docs/%s.md" % sid)
            failures += 1
            continue
        text = path.read_text(encoding="utf-8")
        if "## Ownership" not in text and "## Ownership and boundary" not in text \
                and "## Scope" not in text:
            failure.add("docs/%s.md is missing ## Ownership" % sid)
            failures += 1
    return failures


def has_doc_note(lines: list[str], index: int) -> bool:
    """A `##` block directly above the declaration, blank lines ignored."""
    cursor = index - 1
    while cursor >= 0 and not lines[cursor].strip():
        cursor -= 1
    return cursor >= 0 and lines[cursor].lstrip().startswith("##")


def public_members(path: Path) -> list[tuple[int, str]]:
    """Top-level public declarations with their line number; preload consts are machinery."""
    out: list[tuple[int, str]] = []
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
        match = API_MEMBER.match(line)
        if not match:
            continue
        name = next((group for group in match.groups() if group), "")
        if not name or name.startswith("_") or "preload(" in line:
            continue
        out.append((index, name))
    return out


def type_note_failures(name: str, text: str) -> list[str]:
    """A facade's public type needs a `##` note."""
    lines = text.splitlines()
    out: list[str] = []
    for index, line in enumerate(lines):
        match = PUBLIC_TYPE.match(line)
        if not match or match.group(1).startswith("_"):
            continue
        if not has_doc_note(lines, index):
            out.append("%s:%d declares a public type without a ## note: %s" % (
                name, index + 1, match.group(1)))
    return out


def member_note_failures(name: str, text: str) -> list[str]:
    """Every public member of a strict surface needs a `##` note."""
    lines = text.splitlines()
    out: list[str] = []
    for index, line in enumerate(lines):
        match = API_MEMBER.match(line)
        if not match:
            continue
        member = next((group for group in match.groups() if group), "")
        if not member or member.startswith("_") or "preload(" in line:
            continue
        if not has_doc_note(lines, index):
            out.append("%s:%d declares a public member without a ## note: %s" % (
                name, index + 1, member))
    return out


def check_facade_notes(failure: Failure) -> None:
    """A facade's public type carries a `##` note; api.gd's public surface carries one too."""
    for sid in SERVICES:
        path = ROOT / sid / facade_for(sid)
        if not path.is_file():
            continue
        failure.extend(type_note_failures(rel(path), path.read_text(encoding="utf-8")))
    api = ROOT / "api.gd"
    if api.is_file():
        failure.extend(member_note_failures("api.gd", api.read_text(encoding="utf-8")))


def check_api_docs(failure: Failure) -> None:
    """Every public api.gd function is named in docs/api.md."""
    api = ROOT / "api.gd"
    doc = DOCS / "api.md"
    if not api.is_file() or not doc.is_file():
        return
    text = doc.read_text(encoding="utf-8")
    lines = api.read_text(encoding="utf-8").splitlines()
    for index, name in public_members(api):
        if not re.match(r"^(?:static\s+)?func\s", lines[index]):
            continue
        if name not in text:
            failure.add("docs/api.md does not name api.gd's public function %s" % name)


def audit_surface() -> None:
    """Print the facade public functions without a `##` note; advisory, never a gate."""
    for sid in SERVICES:
        path = ROOT / sid / facade_for(sid)
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            match = re.match(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\(", line)
            if not match or match.group(1).startswith("_"):
                continue
            if not has_doc_note(lines, index):
                print("%s:%d %s" % (rel(path), index + 1, match.group(1)))
