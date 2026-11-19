#!/usr/bin/env python3
"""Architecture gate for unfplap.

The service docs are the dependency manifest. This script compares each service's
``### Uses`` table with the preload graph, enforces the layer, owner and privacy
rules, and tracks temporary boundary/typing debt.

Every shipped ``.gd`` must resolve to an owner — a service, ``shared/`` or one of the
three orchestrators — so a directory without a ``service.gd`` cannot add code whose
edges the boundary rules would classify as external and allow.

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

SOURCE_SKIP_DIRS = {
    ".git", "dist", "assets", "sources", "tests", "tools", "scripts", "docs", ".godot",
}
RELEASE_FILES = (
    ".opencode/skills/release/SKILL.md",
    ".opencode/commands/release.md",
    "scripts/prepare_release.sh",
    "scripts/check_release.sh",
    "scripts/check_release_metadata.py",
    "scripts/build_manifest.py",
    "scripts/asset_pack.py",
    "scripts/pack_assets.sh",
    "scripts/fetch_assets.sh",
    "scripts/asset_pack.json",
    "assets/README.md",
)
SHELL_ENTRIES = ("build.sh", "lab.sh", "lab-stress.sh", "lab-vr.sh")
ACT_EXIT_CALLS = (
    "_end_session(",
    "_free_pose(",
    "release_pose(",
    "_unlock_player(",
    "_restore_pony_bones(",
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
)
TEARDOWN_STEPS = (
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
    "_free_pose(",
    "_unlock_player(",
)
POSE_ACT_EXIT_CALLS = (
    "_end_session(",
    "_unlock_player(",
    "_restore_pony_bones(",
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
    "_free_pose(",
)
POSE_LEDGER_ORDER = (
    "_pose_service().leave_pose_start()",
    "clear_presentation()",
    '_camera_service().call("end_lean_action")',
    "_hand_controller().reset()",
    "_kiss_controller().reset()",
    "_integrations_controller().reset()",
    "_reset_excitement_hold()",
    '_camera_service().call("release_free_camera_lock")',
    "_standing_anon_controller().remove()",
    "_pose_service().leave_pose_body()",
    "_restore_voice_volume()",
    "_reactions.end_act()",
    "_pose_service().release_pose()",
)
POSE_FANOUT_ORDER = (
    "_pose_service()",
    "_camera_service()",
    "_hand_controller()",
    "_kiss_controller()",
    "_anatomy_bridge",
    "_act_audio",
)
# The world facade is the scene read surface: the game, the player rig and the shared modules.
WORLD_ALLOWED = ("res://world/", "res://player/", "res://mods/unfplap/shared/")
WORLD_IMPORT = re.compile(r'(?:preload|load)\("(res://[^"]+\.gd)"\)')
WORLD_EXTENDS = re.compile(r'^extends\s+"(res://[^"]+)"', re.MULTILINE)
SETTINGS_DECLARATION = re.compile(
    r"^\s*static var \w+.*:=\s*(?:flag|num|choice|list|color)\(", re.MULTILINE)

TESTS = ROOT / "tests"
TEST_SUITE_CHECK = re.compile(r"^func check\(", re.MULTILINE)
TEST_SUITE_RESULT = re.compile(r"_RESULT checks=")
TEST_TRUE_CALL = re.compile(r"\bcheck\(\s*true\b")
TEST_NUMERIC_LITERAL = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])")
TEST_SETTING_DEFAULT = re.compile(r"[A-Za-z_][\w.]*\.default\b")

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

# The base mechanism never names the installed provider's characters or its mesh marker. The
# provider and its policy are the only source files that may; the base roster catalog names a
# base-game mare and is game data, not integration vocabulary.
CHANGELINGS_VOCAB = re.compile(
    r"chrysalis|shoeshine|queen_chrysalis|chrysalis_own", re.IGNORECASE)
CHANGELINGS_SOURCE = "integrations/changelings"
CHANGELINGS_CATALOG = {"shared/character_preferences.gd"}

ORCHESTRATORS = {"main.gd", "runtime.gd", "api.gd"}
# Service files another owner may extend or preload as a documented extension point. The source
# base is a provider contract, not a second facade; the anatomy body binding is the attachment
# contract the body-change service constructs from the anatomy facade it is handed.
PUBLIC_SERVICE_FILES = {"body_change/source.gd", "anatomy/body_binding.gd"}
# The five body-bound systems `body_change.wire()` builds and registers. The entry names none of
# them: a new binding adds a preload to the service, not to the composition root.
BODY_BINDINGS = (
    "anatomy/body_binding.gd",
    "body_change/runtime_binding.gd",
    "body_change/lod_binding.gd",
    "body_change/garment_binding.gd",
    "body_change/smack_binding.gd",
)
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
        if tgt in PUBLIC_SERVICE_FILES:
            return "service", so, to
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
    "world/service.gd": "live scene reads",
    "offer/service.gd": "idle act offer and hint",
    "ponies/service.gd": "per-pony runtime registry",
    "settings/service.gd": "settings declarations and live values",
    "registry/service.gd": "provider layers and stable ids",
    "eligibility/service.gd": "adult and consent gate",
    "memory/service.gd": "act memory and witness pass",
    "dialogue/service.gd": "act dialogue and prompt notes",
    "face/service.gd": "act face and mood",
    "rest/service.gd": "bed anchor and cuddle rejoin",
    "scene_gate/service.gd": "live scene gate rows",
    "scene_hold/service.gd": "navigator, player and attention ownership",
    "summary/service.gd": "act grade and history rows",
    "afterglow/service.gd": "afterglow timers and close window",
    "readiness/service.gd": "readiness and auto stroke",
    "poses/service.gd": "pose and skeleton",
    "camera/service.gd": "act camera and shot",
    "hands/service.gd": "hand contact and smack",
    "kiss/service.gd": "kiss control",
    "integrations/service.gd": "optional mod reaction bridge",
    "anatomy/service.gd": "anatomy and tail seat",
    "vr/service.gd": "VR act controls",
    "initiation/service.gd": "proactive offers",
    "reactions/service.gd": "jiggle, blush and hearts",
    "audio/service.gd": "act audio layers",
    "hud/service.gd": "act HUD card",
    "stool/service.gd": "footstool supply",
    "debug/service.gd": "debug action registry",
    "input/service.gd": "act input policy",
    "shared/preferences.gd": "profile schema and math",
    "shared/character_preferences.gd": "roster and catalog templates",
    "shared/act_history.gd": "stored history rows",
    "shared/log.gd": "log sink and perf entry",
    "shared/act_face.gd": "face beat data",
    "shared/act_facts.gd": "typed act read model",
    "shared/act_commands.gd": "act command vocabulary",
    "shared/act_motion.gd": "lean and travel math",
    "shared/anatomy_placement.gd": "placement schema and merge",
    "shared/defaults_data.gd": "shipped settings and catalog documents",
    "shared/integrations.gd": "supported mod catalog",
    "shared/consent.gd": "consent defaults",
    "shared/cycle.gd": "estrus cycle",
    "shared/hands_reach_plan.gd": "reach planning math",
    "shared/hands_scale.gd": "palm scale",
    "shared/participation.gd": "participation defaults",
    "shared/perf.gd": "perf probe",
    "shared/perf_idle.gd": "idle perf aggregate",
    "shared/perf_tree.gd": "perf tree layout",
    "shared/perf_view.gd": "perf panel",
    "shared/pose_catalog.gd": "pose ids and schema",
    "shared/pose_offer.gd": "typed act offer",
    "shared/pose_specs.gd": "pose capability table",
    "shared/pose_view.gd": "pose read model",
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
    "world": ("world", "static initialization", "`bind_world()`/`bind_player()`", "`unbind()`/world close", "yes"),
    "offer": ("world", "`main._ready()`", "`on_world()`", "`reset()`/world close", "yes"),
    "ponies": ("world", "static initialization", "the entry binds its factory and services", "`shutdown()`", "yes"),
    "settings": ("world", "`main._ready()`", "registry load", "process exit", "yes"),
    "registry": ("process", "static initialization", "none", "`reset()`", "yes"),
    "eligibility": ("world", "`main._ready()`", "`setup()`", "`clear()`", "yes"),
    "scene_gate": ("per-pony", "`runtime._init()`", "`bind()`/`configure()`", "act teardown", "yes"),
    "scene_hold": ("per-pony", "`runtime._init()`", "`bind()`/`claim_nav()`", "runtime free", "yes"),
    "rest": ("per-act", "`runtime._init()`", "`bind()`", "act teardown", "yes"),
    "hands": ("per-act", "`runtime`", "`bind()`/`begin()`", "act teardown", "yes"),
    "anatomy": ("world + per-act bridge", "`main._ready()`", "`setup()`/`new_act()`", "`shutdown()`", "yes"),
    "vr": ("per-act", "`anatomy` act bridge", "act start", "act end", "yes"),
    "initiation": ("world", "`main._ready()`", "`setup()`", "`reset()`/world close", "yes"),
    "negotiation": ("world", "`main._ready()`", "`setup(host)`", "`reset()`/world close", "yes"),
    "memory": ("world", "`main._ready()`", "`setup()`", "`clear()`", "yes"),
    "dialogue": ("per-act", "`runtime`", "`setup()`/`configure()`", "`reset()`/act end", "yes"),
    "readiness": ("per-act", "`runtime._init()`", "`configure()`", "`reset()`", "yes"),
    "poses": ("per-act", "`runtime._init()`", "`bind()`/`begin()`", "`release_pose()`", "yes"),
    "camera": ("per-act", "`runtime._init()`", "`bind()`/`begin_session()`", "act teardown", "yes"),
    "kiss": ("per-act", "`runtime`", "`bind()`", "act teardown", "yes"),
    "integrations": ("per-act", "`runtime._integrations_controller()`", "`begin()`", "`reset()`", "yes"),
    "summary": ("per-act", "`runtime._init()`", "`reset_act()`", "act teardown", "yes"),
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


def shipped_sources() -> list[Path]:
    return sorted(
        path for path in ROOT.rglob("*.gd")
        if not (set(path.relative_to(ROOT).parts) & SOURCE_SKIP_DIRS)
    )


def function_body(text: str, name: str) -> str:
    match = re.search(r"^(?:static\s+)?func %s\(" % re.escape(name), text, re.MULTILINE)
    if not match:
        return ""
    rest = text[match.end():]
    next_func = re.search(r"^(?:static\s+)?func ", rest, re.MULTILINE)
    return rest[:next_func.start()] if next_func else rest


def call_lines(text: str, needle: str) -> list[str]:
    return [
        line for line in text.splitlines()
        if needle in line and not line.lstrip().startswith(("#", "func "))
    ]


def doc_tests_section(text: str) -> str | None:
    heading = re.search(r"^## Tests[^\n]*\n", text, re.MULTILINE)
    if not heading:
        return None
    rest = text[heading.end():]
    next_heading = re.search(r"^## ", rest, re.MULTILINE)
    return rest[:next_heading.start()] if next_heading else rest


def project_game_version() -> str:
    if ROOT.parent.name != "mods":
        return ""
    project = ROOT.parent.parent / "project.godot"
    if not project.is_file():
        return ""
    match = re.search(r'^config/version="([^"]+)"', project.read_text(encoding="utf-8"),
                      re.MULTILINE)
    return match.group(1) if match else ""


def is_lab(path: Path) -> bool:
    return path.name.startswith("test_lab") or path.name == "test_stress_lab.gd"


def test_suites() -> list[Path]:
    """The runner's discovery: tests/<name>.gd and tests/<dir>/<name>.gd, no manual labs."""
    return sorted(
        path for path in TESTS.rglob("test_*.gd")
        if len(path.relative_to(TESTS).parts) <= 2 and not is_lab(path)
    )


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


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


def check_tests(failure: Failure) -> None:
    # The runner contract: a suite defines the check() helper and prints its result line.
    for path in test_suites():
        text = path.read_text(encoding="utf-8")
        name = rel(path)
        if not TEST_SUITE_CHECK.search(text):
            failure.add("%s does not define a check() helper" % name)
        if not TEST_SUITE_RESULT.search(text):
            failure.add("%s does not print a _RESULT check summary" % name)

    for path in sorted(TESTS.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        name = rel(path)
        # check(true, ...) cannot fail, whatever the text says.
        for match in TEST_TRUE_CALL.finditer(text):
            failure.add("%s:%d calls check(true, ...): assert the observed value" % (
                name, line_of(text, match.start())))
        # The settings schema check owns the one read of the shipped defaults document.
        if name != "tests/test_settings.gd":
            for match in re.finditer(r"defaults\.json|DEFAULTS_FILE", text):
                failure.add("%s:%d reads the shipped defaults outside test_settings.gd" % (
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


def check_sources(failure: Failure) -> None:
    runtime = (ROOT / "runtime.gd").read_text(encoding="utf-8")

    # One teardown: every exit route goes through _end_session, and no stop path repeats a
    # borrowed-state restore itself.
    if len(re.findall(r"^func _end_session\(", runtime, re.MULTILINE)) != 1:
        failure.add("runtime.gd must define exactly one _end_session()")
    for name in ("_abort_start", "_finish_restore", "_restore_now", "force_stop"):
        body = function_body(runtime, name)
        if not body:
            failure.add("runtime.gd is missing %s()" % name)
            continue
        if "_end_session(" not in body:
            failure.add("%s must end through _end_session()" % name)
        for call in TEARDOWN_STEPS:
            if call in body:
                failure.add("%s must not call %s directly" % (name, call))
    if "_restore_now()" not in function_body(runtime, "force_stop"):
        failure.add("force_stop must restore through _restore_now()")

    # The pose ledger keeps its pose-scope steps and act-scope resets in their current order, and
    # only the act exit, the new-act prep and the body-swap suspension call it.
    free = function_body(runtime, "_free_pose")
    cursor = 0
    for call in POSE_LEDGER_ORDER:
        at = free.find(call, cursor)
        if at < 0:
            failure.add("_free_pose() must keep %s at its position" % call)
            break
        cursor = at + len(call)
    ledger_calls = call_lines(runtime, "_free_pose()")
    if len(ledger_calls) != 3:
        failure.add("the pose ledger must have exactly three callers (found %d)" % len(ledger_calls))
    for name in ("_end_session", "_build_pose", "_suspend_for_body_swap"):
        if "_free_pose()" not in function_body(runtime, name):
            failure.add("%s must call the pose ledger" % name)
    release_calls = call_lines(runtime, "_pose_service().release_pose()")
    if len(release_calls) != 1 or "_pose_service().release_pose()" not in free:
        failure.add("release_pose() must be called only from the pose ledger")

    # The physics tick advances the pose edge before the facts sync, then fans the change out; the
    # fixed owner order is the seam, and neither body is a second teardown.
    tick = function_body(runtime, "_physics_tick")
    tick_at = tick.find("_pose_service().tick(delta)")
    facts_at = tick.find("_sync_act_facts()")
    fanout_at = tick.find("_pose_fanout()", facts_at if facts_at >= 0 else 0)
    if tick_at < 0 or facts_at < 0 or tick_at > facts_at:
        failure.add("_physics_tick() must tick the pose before the first facts sync")
    if facts_at < 0 or fanout_at < facts_at:
        failure.add("_physics_tick() must fan the pose change out after the facts sync")
    fanout = function_body(runtime, "_pose_fanout")
    cursor = 0
    for owner in POSE_FANOUT_ORDER:
        at = fanout.find(owner, cursor)
        if at < 0:
            failure.add("_pose_fanout() must name %s in order" % owner)
            break
        cursor = at + len(owner)
    for name, body in (("_physics_tick", tick), ("_pose_fanout", fanout)):
        for call in ACT_EXIT_CALLS:
            if call in body:
                failure.add("%s() must not call %s" % (name, call))

    # The pose system never reaches an act exit; its scope is the live pose and its own release.
    for path in (ROOT / "poses").rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        for call in POSE_ACT_EXIT_CALLS:
            if call in text:
                failure.add("%s must not reach the act exit: %s" % (rel(path), call))

    # One body-change fan-out: only the service dispatches to registered body bindings, through
    # its one bind/refresh/unbind loop each. A second dispatcher would bypass the form store.
    for needle in ("binding.bind_body(", "binding.refresh_body(", "binding.unbind_body("):
        callers = [rel(path) for path in shipped_sources()
                   if needle in path.read_text(encoding="utf-8")]
        if callers != ["body_change/service.gd"]:
            failure.add("%s must only be dispatched from body_change/service.gd (found %s)" % (
                needle, ", ".join(callers) or "none"))
    service = (ROOT / "body_change" / "service.gd").read_text(encoding="utf-8")
    for name in ("_notify_bind", "_notify_refresh"):
        if service.count("func %s(" % name) != 1:
            failure.add("body_change/service.gd must define one %s()" % name)

    # One resume: the runtime keeps the only resume path, and adoption never resumes by itself.
    resumes = re.findall(r"^func _resume_after_body_swap\(", runtime, re.MULTILINE)
    if len(resumes) != 1:
        failure.add("runtime.gd must define exactly one _resume_after_body_swap()")
    for path in shipped_sources():
        if path == ROOT / "runtime.gd":
            continue
        if "_resume_after_body_swap(" in path.read_text(encoding="utf-8"):
            failure.add("%s must not resume a body swap" % rel(path))
    if "_resume_after_body_swap(" in function_body(runtime, "adopt_body"):
        failure.add("adopt_body() must not resume; the watcher owns the one resume")

    # The provider policy owns the offer prompt and the reveal magnitudes. The runtime only asks
    # the typed policy and executes its generic effects.
    for name in ("FORM_OFFER_PROMPT", "FORM_REVEAL_HEAT", "FORM_REVEAL_PEAK_SCORE"):
        if name in runtime:
            failure.add("runtime.gd must not own the provider policy value %s" % name)
    offer = function_body(runtime, "_shape_offer_tick")
    for needle in (".should_offer(", ".offer_prompt()"):
        if needle not in offer:
            failure.add("_shape_offer_tick() must ask the typed policy for %s" % needle)
    if ".on_reveal(" not in function_body(runtime, "_commit_form_reveal"):
        failure.add("_commit_form_reveal() must execute the typed policy's on_reveal()")
    if ".on_offer_accepted(" not in function_body(runtime, "_apply_offer_accepted"):
        failure.add("_apply_offer_accepted() must execute the typed policy's on_offer_accepted()")

    # One runtime binding: the body-change service builds it with the rest of the chain, the
    # runtime exposes the two typed hooks, and the binding never runs the act exit or a second
    # resume.
    binding_path = ROOT / "body_change" / "runtime_binding.gd"
    if not binding_path.is_file():
        failure.add("missing body_change/runtime_binding.gd")
    else:
        binding = binding_path.read_text(encoding="utf-8")
        if 'extends "res://mods/unfplap/shared/body_binding.gd"' not in binding:
            failure.add("body_change/runtime_binding.gd must extend the typed body binding")
        if 'return "runtime"' not in binding:
            failure.add('body_change/runtime_binding.gd must name itself "runtime"')
        for needle in ("_end_session(", "_resume_after_body_swap("):
            if call_lines(binding, needle):
                failure.add("body_change/runtime_binding.gd must not call %s" % needle)
    # The service builds every binding from the facades the entry hands it, so a new body-bound
    # system adds a preload and a register call to the service and no line to the entry.
    service_source = (ROOT / "body_change" / "service.gd").read_text(encoding="utf-8")
    if "func wire(" not in service_source:
        failure.add("body_change/service.gd must build its bindings in wire()")
    for needle in BODY_BINDINGS:
        if service_source.count(needle) != 1:
            failure.add("body_change/service.gd must name the body binding %s once" % needle)
    main_source = (ROOT / "main.gd").read_text(encoding="utf-8")
    for number, line in enumerate(main_source.splitlines(), start=1):
        if "_binding.gd" in line or "register_binding" in line:
            failure.add(
                "main.gd:%d builds a body binding; body_change.wire() owns the chain" % number)
    for name in ("bind_body_services", "refresh_body_services"):
        if len(re.findall(r"^func %s\(" % name, runtime, re.MULTILINE)) != 1:
            failure.add("runtime.gd must define exactly one %s()" % name)

    # The base mechanism never names the installed provider's characters or its mesh marker.
    for path in shipped_sources():
        name = rel(path)
        if name.startswith(CHANGELINGS_SOURCE) or name in CHANGELINGS_CATALOG:
            continue
        match = CHANGELINGS_VOCAB.search(path.read_text(encoding="utf-8"))
        if match:
            failure.add("%s names changelings vocabulary outside its provider: %s" % (
                name, match.group(0)))

    # Every bash entry point runs under errexit, so a failing tool stops it.
    shell_paths = [ROOT / name for name in SHELL_ENTRIES]
    shell_paths += sorted((ROOT / "scripts").glob("*.sh"))
    for path in shell_paths:
        lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines()]
        if "set -euo pipefail" not in lines:
            failure.add("%s must run under 'set -euo pipefail'" % rel(path))

    # The release and asset tooling ships with the mod.
    for name in RELEASE_FILES:
        if not (ROOT / name).is_file():
            failure.add("missing release file: %s" % name)

    # The manifest is the entry contract: one known id, a dotted version and the project's game.
    try:
        manifest = json.loads((ROOT / "mod.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        failure.add("mod.json does not parse: %s" % error)
        manifest = {}
    if not isinstance(manifest, dict):
        failure.add("mod.json must contain an object")
        manifest = {}
    if manifest.get("id") != "unfplap":
        failure.add('mod.json id must be "unfplap"')
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("version", ""))):
        failure.add("mod.json version must be MAJOR.MINOR.PATCH")
    if "extends" in manifest:
        failure.add("mod.json must declare an entry, not an extends")
    if manifest.get("entry") != "res://mods/unfplap/main.gd":
        failure.add("mod.json entry must be res://mods/unfplap/main.gd")
    game_version = project_game_version()
    if game_version and str(manifest.get("game_version", "")) != game_version:
        failure.add("mod.json game_version %s does not match the project (%s)" % (
            manifest.get("game_version", ""), game_version))

    # One settings declaration module, one facade per assignment and no root composition shim.
    settings = (ROOT / "settings" / "service.gd").read_text(encoding="utf-8")
    if "static func all_settings() -> Array[Setting]" not in settings:
        failure.add("settings/service.gd must expose all_settings() -> Array[Setting]")
    declaring: list[str] = []
    for path in shipped_sources():
        source = path.read_text(encoding="utf-8")
        if SETTINGS_DECLARATION.search(source):
            declaring.append(rel(path))
        if path.name == "settings.gd" and path.parent.name != "settings":
            failure.add("no per-service settings module: %s" % rel(path))
    if declaring != ["settings/service.gd"]:
        failure.add("only settings/service.gd may declare settings (found %s)" % declaring)
    for name in ("settings_page.gd", "settings_layout.gd"):
        if (ROOT / name).exists():
            failure.add("no root settings composition file: %s" % name)

    # A service contract names its facade and at least one test path that exists. Indexing and the
    # remaining headings are check_docs()' job.
    for sid in SERVICES:
        path = doc_path(sid)
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if f"{sid}/service.gd" not in text:
            failure.add("docs/%s.md does not name %s/service.gd" % (sid, sid))
        section = doc_tests_section(text)
        if section is None:
            failure.add("docs/%s.md has no ## Tests section" % sid)
            continue
        paths = {
            p.rstrip(".,;:)") for p in re.findall(r"tests/[A-Za-z0-9_./*-]+", section)
        }
        if not any((ROOT / path).exists() for path in paths if "*" not in path):
            failure.add("docs/%s.md names no test path that exists" % sid)


def check_owners(failure: Failure) -> None:
    """Every shipped `.gd` has an owner: a service, `shared/` or an orchestrator.

    `owner_of()` answers None for any other path, and every edge to or from an unowned file is
    classified "external" and allowed. A directory without a `service.gd` therefore grows code
    outside the boundary rules; the mod root's former `runtime/` did exactly that.
    """
    orphans = [rel(path) for path in shipped_sources() if owner_of(rel(path)) is None]
    for name in orphans:
        failure.add("%s has no owner: a shipped .gd belongs to a service, to shared/ or to "
                    "main.gd, runtime.gd, api.gd" % name)


def check_boundaries(failure: Failure) -> None:
    """The composition-root rules: no reach-in into the entry, and a scene-only world facade."""
    # A private reach-in is `get("_name")`/`call("_name")` through the entry or a runtime. A
    # public member reached by string is still a locator; the full rule lands with the last
    # owner (the service list replaces the string lookups).
    reach_in = re.compile(r'\b(?:main|runtime)\.(?:call|get)\("_')
    for path in shipped_sources():
        if path == ROOT / "main.gd":
            continue
        text = path.read_text(encoding="utf-8")
        for match in reach_in.finditer(text):
            failure.add("%s:%d reaches into a private member: %s" % (
                rel(path), line_of(text, match.start()), match.group(0)))

    # The world facade answers where and what from the scene alone: it imports the game and the
    # shared pure modules, never a service facade, the runtime or the entry.
    world = ROOT / "world" / "service.gd"
    if not world.is_file():
        failure.add("missing world/service.gd")
        return
    source = "\n".join(
        line for line in world.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("#"))
    text = source
    imports = [(m.group(1), m.start()) for m in WORLD_IMPORT.finditer(text)]
    imports += [(m.group(1), m.start()) for m in WORLD_EXTENDS.finditer(text)]
    for target, at in imports:
        if target.startswith(WORLD_ALLOWED):
            continue
        failure.add("world/service.gd:%d may not import %s" % (line_of(text, at), target))


def check() -> int:
    failure = Failure()
    violations = scan_violations()
    exceptions = check_exceptions(failure, violations)
    check_docs(failure)
    check_typing(failure)
    check_sources(failure)
    check_boundaries(failure)
    check_owners(failure)
    check_tests(failure)
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
