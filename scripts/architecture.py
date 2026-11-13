#!/usr/bin/env python3
"""Architecture gate for unfplap.

The service docs are the dependency manifest. This script compares each service's
``### Uses`` table with the preload graph, enforces the layer and privacy rules, and
tracks temporary boundary/typing debt.

Usage:
    scripts/architecture.py --check
    scripts/architecture.py --graph
    scripts/architecture.py --write-docs
    scripts/architecture.py --write-exceptions
    scripts/architecture.py --write-debt
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
ARCH = ROOT / "architecture"
EXCEPTIONS = ARCH / "exceptions.json"
TYPING_DEBT = ARCH / "typing_debt.json"

ORCHESTRATORS = {"main.gd", "runtime.gd", "api.gd"}
SHARED_KINDS = {
    "act_history.gd": "store",
    "act_facts.gd": "read model",
}
DOC_REQUIRED = ["## Lifecycle", "## Dependencies", "## Tests"]
SERVICE_IGNORE_DOCS = {"README.md", "api.md", "runtime.md"}


class Failure:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, text: str) -> None:
        self.messages.append(text)

    def extend(self, texts: list[str]) -> None:
        self.messages.extend(texts)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def service_ids() -> list[str]:
    return sorted(
        p.parent.name
        for p in ROOT.glob("*/service.gd")
        if not p.parent.name.startswith(".")
    )


SERVICES = service_ids()


@dataclass(frozen=True)
class Owner:
    id: str
    path: str
    private: bool
    kind: str


def owner_of(path: str) -> Owner | None:
    path = path.strip().lstrip("./")
    if path in ORCHESTRATORS:
        return Owner(path[:-3], path, False, "orchestrator")
    if path.startswith("shared/"):
        name = path.split("/")[-1]
        kind = SHARED_KINDS.get(name, "shared")
        return Owner("shared:" + name, path, False, kind)
    for sid in SERVICES:
        if path == f"{sid}/service.gd":
            return Owner(sid, path, False, "service")
        if path.startswith(f"{sid}/"):
            return Owner(sid, path, True, "service")
    return None


def is_game(path: str) -> bool:
    return path.startswith("res://world/") or path.startswith("res://player/")


def game_rel(path: str) -> str:
    return path


def scan_edges() -> set[tuple[str, str]]:
    edges: set[tuple[str, str]] = set()
    preload = re.compile(r'(?:preload|load)\("(res://mods/unfplap/[^"]+\.gd)"\)')
    extends = re.compile(r'^extends\s+"(res://[^"]+)"', re.MULTILINE)
    skip_dirs = {".git", "dist", "assets", "sources", "tests", "tools", "scripts", "docs", ".godot"}
    for path in ROOT.rglob("*.gd"):
        parts = set(path.relative_to(ROOT).parts)
        if parts & skip_dirs:
            continue
        text = path.read_text(encoding="utf-8")
        src = rel(path)
        for match in preload.finditer(text):
            target = match.group(1).replace("res://mods/unfplap/", "")
            edges.add((src, target))
        for match in extends.finditer(text):
            target = match.group(1)
            if target.startswith("res://mods/unfplap/"):
                edges.add((src, target.replace("res://mods/unfplap/", "")))
    return edges


def edge_kind(src: str, tgt: str) -> tuple[str, Owner | None, Owner | None]:
    so = owner_of(src)
    to = owner_of(tgt)
    if is_game(tgt):
        return "game", so, None
    if to is None:
        return "external", so, None
    if so and to and so.id == to.id:
        return "self", so, to
    if to.kind == "service":
        return ("service-private" if to.private else "service"), so, to
    if to.kind in ("shared", "store", "read model"):
        return to.kind, so, to
    if to.kind == "orchestrator":
        return "host", so, to
    return "external", so, to


def is_allowed(src: str, tgt: str) -> tuple[bool, str, Owner | None, Owner | None]:
    kind, so, to = edge_kind(src, tgt)
    if so is None or to is None:
        return True, kind, so, to
    if so.kind == "orchestrator":
        return True, kind, so, to
    if so.kind == "shared":
        if kind in ("shared", "store", "read model", "self", "game"):
            return True, kind, so, to
        # A shared store may read settings; a pure/read-model module may not.
        if so.kind == "store" and to.id == "settings" and kind == "service":
            return True, kind, so, to
        return False, kind, so, to
    if so.kind == "service":
        if kind in ("self", "service", "shared", "store", "read model", "game"):
            # The settings service is infrastructure and must not depend upward on a domain
            # service. The current registry dependency is recorded as migration debt.
            if so.id == "settings" and to.kind == "service" and to.id != "settings":
                return False, "layer", so, to
            return True, kind, so, to
        return False, kind, so, to
    return True, kind, so, to


def scan_violations() -> list[dict[str, str]]:
    found: dict[tuple[str, str, str], dict[str, str]] = {}
    for src, tgt in sorted(scan_edges()):
        ok, kind, so, to = is_allowed(src, tgt)
        if ok:
            continue
        found[(src, tgt, kind)] = {
            "from": src,
            "to": tgt,
            "kind": kind,
            "owner": so.id if so else "",
            "reason": "migration baseline; fix in the boundary-cleanup phase",
            "expires": "phase-2",
        }
    return [found[key] for key in sorted(found)]


def load_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def exception_key(row: dict) -> tuple[str, str, str]:
    return (str(row.get("from", "")), str(row.get("to", "")), str(row.get("kind", "")))


def check_exceptions(failure: Failure, violations: list[dict[str, str]]) -> int:
    rows = load_json(EXCEPTIONS, {"exceptions": []}).get("exceptions", [])
    allowed = {exception_key(row) for row in rows}
    current = {exception_key(row) for row in violations}
    for key in sorted(allowed - current):
        failure.add("stale architecture exception: %s -> %s (%s)" % key)
    for key in sorted(current - allowed):
        failure.add("new architecture violation: %s -> %s (%s)" % key)
    return len(rows)


def doc_path(sid: str) -> Path:
    return DOCS / f"{sid}.md"


def parse_uses(text: str) -> set[tuple[str, str]]:
    stack = re.search(r"^## Dependencies\s*$", text, re.MULTILINE)
    if not stack:
        return set()
    section = text[stack.end():]
    next_h = re.search(r"^## ", section, re.MULTILINE)
    if next_h:
        section = section[:next_h.start()]
    uses = re.search(r"^### Uses\s*$", section, re.MULTILINE)
    if not uses:
        return set()
    table = section[uses.end():]
    next_sub = re.search(r"^### ", table, re.MULTILINE)
    if next_sub:
        table = table[:next_sub.start()]
    rows: set[tuple[str, str]] = set()
    for line in table.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 3:
            continue
        if cells[0].lower() == "kind" or set(cells[0]) <= {"-", ":"}:
            continue
        kind = cells[0].strip("`").lower()
        if kind not in ("service", "shared", "store", "read model"):
            continue
        entry = cells[2].strip().strip("`")
        if not entry:
            target = cells[1].strip().strip("`").split("|")[0].strip()
            if kind == "service" and target in SERVICES:
                entry = f"{target}/service.gd"
            elif target.startswith("shared/"):
                entry = target
        if entry.endswith(".gd"):
            rows.add((kind, entry))
    return rows


def allowed_service_edges() -> dict[str, set[tuple[str, str]]]:
    result: dict[str, set[tuple[str, str]]] = {sid: set() for sid in SERVICES}
    for src, tgt in scan_edges():
        so = owner_of(src)
        to = owner_of(tgt)
        if so is None or so.kind != "service":
            continue
        ok, kind, _, _ = is_allowed(src, tgt)
        if not ok or so.id == (to.id if to else ""):
            continue
        if kind not in ("service", "shared", "store", "read model"):
            continue
        result[so.id].add(("service" if kind == "service" else kind, tgt))
    return result


def check_docs(failure: Failure) -> int:
    failures = 0
    index = (DOCS / "README.md").read_text(encoding="utf-8")
    for path in sorted(DOCS.glob("*.md")):
        if path.name == "README.md":
            continue
        if path.name not in index:
            failure.add("docs/README.md does not index docs/%s" % path.name)
            failures += 1
    expected = allowed_service_edges()
    for sid in SERVICES:
        path = doc_path(sid)
        if not path.exists():
            failure.add("missing service contract: docs/%s.md" % sid)
            failures += 1
            continue
        text = path.read_text(encoding="utf-8")
        for heading in DOC_REQUIRED:
            if heading not in text:
                failure.add("docs/%s.md is missing %s" % (sid, heading))
                failures += 1
        if "## Ownership" not in text and "## Ownership and boundary" not in text \
                and "## Scope" not in text:
            failure.add("docs/%s.md is missing ## Ownership" % sid)
            failures += 1
        actual = parse_uses(text)
        want = expected.get(sid, set())
        for kind, target in sorted(want - actual):
            failure.add("%s doc is missing dependency: %s %s" % (sid, kind, target))
            failures += 1
        for kind, target in sorted(actual - want):
            failure.add("%s doc lists a dependency not in the code graph: %s %s" % (
                sid, kind, target))
            failures += 1
    return failures


PURPOSE = {
    "settings/service.gd": "settings declarations and live values",
    "registry/service.gd": "provider layers and stable ids",
    "eligibility/service.gd": "adult and consent gate",
    "memory/service.gd": "act memory and witness pass",
    "lines/service.gd": "cue and reaction lines",
    "face/service.gd": "act face and mood",
    "rest/service.gd": "bed anchor and cuddle rejoin",
    "scene_gate/service.gd": "live scene gate rows",
    "scene_hold/service.gd": "navigator, player and attention ownership",
    "history/service.gd": "act summary and history rows",
    "afterglow/service.gd": "afterglow timers and close window",
    "readiness/service.gd": "readiness and auto stroke",
    "poses/service.gd": "pose and skeleton",
    "camera/service.gd": "act camera and shot",
    "hands/service.gd": "hand contact and smack",
    "kiss/service.gd": "kiss control",
    "anatomy/service.gd": "anatomy and tail seat",
    "vr/service.gd": "VR act controls",
    "initiation/service.gd": "proactive offers",
    "reactions/service.gd": "jiggle, blush and hearts",
    "audio/service.gd": "act audio layers",
    "hud/service.gd": "act HUD card",
    "stool/service.gd": "footstool supply",
    "debug/service.gd": "debug action registry",
    "input/service.gd": "act input policy",
    "shared/preferences.gd": "profile math and defaults",
    "shared/character_preferences.gd": "character templates",
    "shared/act_history.gd": "stored history rows",
    "shared/act_face.gd": "face beat data",
    "shared/act_facts.gd": "typed act read model",
    "shared/act_motion.gd": "lean and travel math",
    "shared/anatomy_placement.gd": "placement defaults",
    "shared/consent.gd": "consent defaults",
    "shared/cycle.gd": "estrus cycle",
    "shared/hands_reach_plan.gd": "reach planning math",
    "shared/hands_scale.gd": "palm scale",
    "shared/participation.gd": "participation defaults",
    "shared/perf.gd": "perf probe",
    "shared/pose_catalog.gd": "pose ids and defaults",
    "shared/relationship_cue.gd": "relationship prompt note",
    "shared/rump_cone.gd": "standing offer zone",
}


def target_label(kind: str, path: str) -> str:
    if kind == "service":
        return path.split("/")[0]
    return path.split("/")[-1].removesuffix(".gd")


def purpose_for(path: str) -> str:
    if path in PURPOSE:
        return PURPOSE[path]
    if path.startswith("shared/"):
        return "shared data"
    return "service dependency"


def render_uses(edges: set[tuple[str, str]]) -> str:
    lines = [
        "### Uses",
        "",
        "| Kind | Target | Entry point | Purpose |",
        "|---|---|---|---|",
    ]
    for kind, path in sorted(edges, key=lambda e: (e[0], e[1])):
        lines.append("| %s | %s | `%s` | %s |" % (
            kind, target_label(kind, path), path, purpose_for(path)))
    return "\n".join(lines) + "\n"


def replace_uses(text: str, block: str) -> str:
    deps = re.search(r"^## Dependencies\s*$", text, re.MULTILINE)
    if not deps:
        insert = text.find("\n## Tests")
        if insert < 0:
            insert = text.find("\n## Related docs")
        if insert < 0:
            insert = len(text)
        return text[:insert] + "\n## Dependencies\n\n" + block + "\n" + text[insert:]
    section_start = deps.end()
    next_h = re.search(r"^## ", text[section_start:], re.MULTILINE)
    section_end = section_start + next_h.start() if next_h else len(text)
    section = text[section_start:section_end]
    uses = re.search(r"^### Uses\s*$", section, re.MULTILINE)
    if not uses:
        return text[:section_end].rstrip() + "\n\n" + block + "\n" + text[section_end:]
    uses_start = section_start + uses.start()
    tail_start = section_start + uses.end()
    while True:
        next_sub = re.search(r"^### ", text[tail_start:], re.MULTILINE)
        if not next_sub:
            uses_end = section_end
            break
        heading_line = text[tail_start + next_sub.start():].splitlines()[0].strip()
        if heading_line == "### Uses":
            tail_start = tail_start + next_sub.end()
            continue
        uses_end = tail_start + next_sub.start()
        break
    return text[:uses_start] + block + "\n" + text[uses_end:]


LIFECYCLES = {
    "settings": ("world", "`main._ready()`", "registry load", "process exit", "yes"),
    "registry": ("process", "static initialization", "none", "`reset()`", "yes"),
    "eligibility": ("world", "`main._ready()`", "`setup()`", "`clear()`", "yes"),
    "scene_gate": ("per-pony", "`runtime._init()`", "`bind()`/`configure()`", "act teardown", "yes"),
    "scene_hold": ("per-act", "`runtime._init()`", "`bind()`/`claim_nav()`", "act teardown", "yes"),
    "rest": ("per-act", "`runtime._init()`", "`bind()`", "act teardown", "yes"),
    "hands": ("per-act", "`runtime`", "`bind()`/`begin()`", "act teardown", "yes"),
    "anatomy": ("world + per-act bridge", "`main._ready()`", "`setup()`/`new_act()`", "`shutdown()`", "yes"),
    "vr": ("per-act", "`anatomy` act bridge", "act start", "act end", "yes"),
    "initiation": ("world", "`main._ready()`", "`setup()`", "`reset()`/world close", "yes"),
    "memory": ("world", "`main._ready()`", "`setup()`", "`clear()`", "yes"),
    "lines": ("per-act", "`runtime`", "`setup()`/`configure()`", "`reset()`/act end", "yes"),
    "readiness": ("per-act", "`runtime._init()`", "`configure()`", "`reset()`", "yes"),
    "poses": ("per-act", "`runtime._init()`", "`bind()`/`begin()`", "`release_pose()`", "yes"),
    "camera": ("per-act", "`runtime._init()`", "`bind()`/`begin_session()`", "act teardown", "yes"),
    "kiss": ("per-act", "`runtime`", "`bind()`", "act teardown", "yes"),
    "history": ("per-act", "`runtime._init()`", "`reset_act()`", "act teardown", "yes"),
    "afterglow": ("per-act", "`runtime._init()`", "`begin()`", "`reset()`", "yes"),
    "face": ("per-act", "`runtime._init()`", "`bind()`", "`shutdown()`", "yes"),
    "reactions": ("per-act", "`runtime._init()`", "`bind_scene()`/`begin_act()`", "`end_act()`", "yes"),
    "stool": ("world + per-act handle", "`main._ready()`", "`setup()`/`new_act()`", "`shutdown()`", "yes"),
    "audio": ("per-pony", "`runtime`", "`begin()`", "`end()`", "yes"),
    "hud": ("world", "`main._ready()`", "`_ready()`", "freed with main", "yes"),
    "input": ("world", "`main._ready()`", "`_ready()`", "freed with main", "yes"),
    "debug": ("process", "static initialization", "none", "none", "yes"),
}


def render_lifecycle(sid: str) -> str:
    scope, constructed, begin, end, idem = LIFECYCLES.get(
        sid, ("world", "`main`", "none", "world close", "yes"))
    return (
        "## Lifecycle\n\n"
        f"- Scope: {scope}\n"
        f"- Constructed by: {constructed}\n"
        f"- Begin: {begin}\n"
        f"- End: {end}\n"
        f"- Idempotent: {idem}\n"
    )


def insert_lifecycle(text: str, sid: str) -> str:
    if "## Lifecycle" in text:
        return text
    block = render_lifecycle(sid)
    for needle in ("\n## Settings", "\n## Tests", "\n## Related docs"):
        pos = text.find(needle)
        if pos >= 0:
            return text[:pos] + "\n" + block + "\n" + text[pos:]
    return text.rstrip() + "\n\n" + block


def write_docs() -> None:
    expected = allowed_service_edges()
    for sid in SERVICES:
        path = doc_path(sid)
        if not path.exists():
            print("missing doc, skipped: docs/%s.md" % sid, file=sys.stderr)
            continue
        text = path.read_text(encoding="utf-8")
        text = replace_uses(text, render_uses(expected.get(sid, set())))
        text = insert_lifecycle(text, sid)
        path.write_text(text, encoding="utf-8")
    print("ARCH_DOCS_WRITTEN services=%d" % len(SERVICES))


def public_functions(service: str) -> list[dict[str, str]]:
    path = ROOT / service / "service.gd"
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[dict[str, str]] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^(static )?func ([A-Za-z0-9_]+)\(", line)
        if not m or m.group(2).startswith("_"):
            i += 1
            continue
        name = m.group(2)
        signature = line.rstrip()
        while not signature.rstrip().endswith(":") and i + 1 < len(lines):
            i += 1
            signature += " " + lines[i].strip()
        out.append({"service": service, "func": name, "signature": signature.strip()})
        i += 1
    return out


def weak_signature(signature: str) -> bool:
    m = re.search(r"func\s+[A-Za-z0-9_]+\((.*?)\)\s*(?:->\s*([^:]+))?:", signature)
    if not m:
        return True
    params, ret = m.group(1), (m.group(2) or "").strip()
    if not ret:
        return True
    if ret.split("[")[0] in ("Variant", "Dictionary", "Callable"):
        return True
    if ret == "Array":
        return True
    for param in params.split(","):
        param = param.strip()
        if not param:
            continue
        if ":" not in param:
            return True
        typ = param.split(":", 1)[1].strip().split("=")[0].strip()
        if typ.split("[")[0] in ("Variant", "Dictionary", "Callable"):
            return True
        if typ == "Array":
            return True
    return False


def typing_debt() -> list[dict[str, str]]:
    debt = []
    for sid in SERVICES:
        for row in public_functions(sid):
            if weak_signature(row["signature"]):
                debt.append(row)
    return sorted(debt, key=lambda r: (r["service"], r["func"]))


def write_debt() -> None:
    ARCH.mkdir(exist_ok=True)
    TYPING_DEBT.write_text(json.dumps({"debt": typing_debt()}, indent=2) + "\n", encoding="utf-8")
    print("ARCH_TYPING_DEBT_WRITTEN entries=%d" % len(typing_debt()))


def check_typing(failure: Failure) -> int:
    saved = load_json(TYPING_DEBT, {"debt": []}).get("debt", [])
    saved_keys = {(r["service"], r["func"], r["signature"]) for r in saved}
    current = typing_debt()
    current_keys = {(r["service"], r["func"], r["signature"]) for r in current}
    for key in sorted(current_keys - saved_keys):
        failure.add("new weak public signature: %s.%s" % (key[0], key[1]))
    for key in sorted(saved_keys - current_keys):
        failure.add("stale typing debt (remove it): %s.%s" % (key[0], key[1]))
    return 0


def write_exceptions() -> None:
    ARCH.mkdir(exist_ok=True)
    rows = scan_violations()
    EXCEPTIONS.write_text(json.dumps({"exceptions": rows}, indent=2) + "\n", encoding="utf-8")
    print("ARCH_EXCEPTIONS_WRITTEN entries=%d" % len(rows))
    for row in rows:
        print("  %s -> %s (%s)" % (row["from"], row["to"], row["kind"]))


def graph() -> None:
    print("graph TD")
    for sid in SERVICES:
        print('  %s["%s"]' % (sid, sid))
    for src, tgt in sorted(scan_edges()):
        so = owner_of(src)
        to = owner_of(tgt)
        if so is None or to is None or so.kind != "service" or to.kind != "service":
            continue
        if so.id == to.id:
            continue
        print("  %s --> %s" % (so.id, to.id))


def check() -> int:
    failure = Failure()
    violations = scan_violations()
    exceptions = check_exceptions(failure, violations)
    check_docs(failure)
    check_typing(failure)
    failures = len(failure.messages)
    for message in failure.messages:
        print("FAIL", message)
    print("ARCH_RESULT services=%d shared=%d exceptions=%d typing_debt=%d failures=%d" % (
        len(SERVICES),
        len(list((ROOT / "shared").glob("*.gd"))),
        exceptions,
        len(load_json(TYPING_DEBT, {"debt": []}).get("debt", [])),
        failures,
    ))
    if failures:
        print("ARCH_FAIL")
        return 1
    print("ARCH_PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--graph", action="store_true")
    parser.add_argument("--write-docs", action="store_true")
    parser.add_argument("--write-exceptions", action="store_true")
    parser.add_argument("--write-debt", action="store_true")
    args = parser.parse_args()
    if args.write_docs:
        write_docs()
        return 0
    if args.write_exceptions:
        write_exceptions()
        return 0
    if args.write_debt:
        write_debt()
        return 0
    if args.graph:
        graph()
        return 0
    return check()


if __name__ == "__main__":
    sys.exit(main())
