"""The documentation naming contract, facade notes and the cross-mod API surface."""
from __future__ import annotations

import re
from pathlib import Path

from .context import DOCS, ROOT, SERVICES, facade_for
from .failure import Failure, rel

# The docs that are not service contracts: the frozen cross-mod surface and the project docs.
PROJECT_DOCS = ("api", "kiss", "tests", "quality", "vr")
# A facade's public types carry a `##` note; api.gd's public members are the strict surface.
PUBLIC_TYPE = re.compile(r"^(?:class|enum)\s+([A-Za-z_]\w*)\b", re.MULTILINE)
API_MEMBER = re.compile(
    r"^(?:const\s+([A-Z][A-Z0-9_]*)|(?:static\s+)?func\s+([A-Za-z_]\w*)|var\s+([A-Za-z_]\w*))")


def doc_path(sid: str) -> Path:
    return DOCS / f"{sid}.md"


def check_docs(failure: Failure, docs: Path = DOCS, services: list[str] | None = None) -> int:
    """Every service ships a non-empty doc named for its directory, and nothing else is a doc."""
    failures = 0
    services = SERVICES if services is None else services
    allowed = set(services) | set(PROJECT_DOCS)
    if (docs / "README.md").exists():
        failure.add("docs/README.md must not exist; a doc is named after its subject")
        failures += 1
    for path in sorted(docs.glob("*.md")):
        if path.name == "README.md":
            continue
        if path.stem not in allowed:
            failure.add("docs/%s is not a service doc or a project doc" % path.name)
            failures += 1
    for sid in services:
        path = docs / f"{sid}.md"
        if not path.is_file():
            failure.add("missing service doc: docs/%s.md" % sid)
            failures += 1
            continue
        if not path.read_text(encoding="utf-8").strip():
            failure.add("empty service doc: docs/%s.md" % sid)
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
