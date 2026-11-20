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
    scripts/architecture.py --write-duck-typing
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
DUCK_TYPING = ARCH / "duck_typing.json"

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
    "context.pose.leave_pose_start()",
    "context.presentation.clear_presentation()",
    "context.camera.end_lean_action()",
    "context.hands.reset()",
    "context.kiss.reset()",
    "context.integrations.reset()",
    "context.audio.reset_excitement_hold()",
    "context.standing_anon.remove()",
    "context.pose.leave_pose_body()",
    "context.audio.restore_voice_policy()",
    "context.reactions.end_act()",
    "context.pose.release_pose()",
)
POSE_FANOUT_ORDER = (
    "context.pose",
    "context.camera",
    "context.hands",
    "context.kiss",
    "context.anatomy",
    "context.audio",
)
# The start ledger's recipe, in the order the act depends on: the presentation guard, the stool,
# the borrows, the pose build, the player frame, the camera open, the audio,
# POSING_IN and the HUD card. `begin_pose_in()` precedes `show_act()` because the HUD reads the
# live state it sets.
START_LEDGER_ORDER = (
    'POSE_SPECS.start_setup(pose) == "standing_place"',
    "session.reset_stool_state()",
    "session.posture_owned = false",
    "session.profile = SETTINGS.template_for(",
    "session.bed = context.gate.resolve_bed(",
    "var setup_name := POSE_SPECS.start_setup(pose)",
    "_build_pose()",
    "context.frame.begin(",
    "context.camera.begin_act(",
    "context.audio.start(",
    "session.begin_pose_in()",
    "HUD.instance.show_act(context.facts)",
)
# The pose ledger's callers: the one act exit, the new-act prep and the body-swap suspension.
# A new caller is a design decision, so the set is exact and compared both ways.
POSE_LEDGER_CALLERS = {
    ("act/exit.gd", "run"),
    ("act/start.gd", "_build_pose"),
    ("act/swap.gd", "release_pose"),
}
# Rule 1, full form: only the entry names the entry. A service that needs another service
# preloads its facade, one that needs the scene reads `WORLD`, and one that needs a callback takes
# a host parameter. `tests/` and the prose literal `main.gd` are allowed.
ENTRY_MEMBER = re.compile(r"(?<![\w.])main\.(?!gd\b)[A-Za-z_]\w*")
ENTRY_DECLARATION = re.compile(r"^\s*(?:var|const)\s+main\b", re.MULTILINE)
ENTRY_PRELOAD = re.compile(r'(?:preload|load)\(\s*"[^"]*main\.gd"')
ENTRY_ARGUMENT = re.compile(r"[(,]\s*main\s*[:,)]")
# The world facade is the scene read surface: the game, the player rig and the shared modules.
WORLD_ALLOWED = ("res://world/", "res://player/", "res://mods/unfplap/shared/",
                 "res://mods/unfplap/world/")
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
# runtime.gd is the per-pony Node host: it owns lifetime and node operations and implements no
# system's rules. The state-writer rule, the fixed public surface and the settings/child-node
# allow-lists are the invariant. The allow-lists are compared both ways, so a new read or node
# fails and a row that no longer exists fails too.
RUNTIME_STATE_WRITER = "act/session.gd:_set_state"
RUNTIME_STATE_OWNER = ROOT / "act" / "session.gd"
# Every `SETTINGS.<member>` read, keyed by its enclosing function (`<module>` for the field block)
# and the reason it is a snapshot boundary rather than a per-frame read. A new read is a new row,
# added on purpose with the service that owns the value; removing a read removes its row.
RUNTIME_SETTINGS_READS = {}
# The act session's settings owner holds the one snapshot, so its boundaries are checked the same
# way: the bulk snapshot and the pre-edit preference refresh, never a per-frame read.
ACT_SETTINGS_OWNER = ROOT / "act" / "settings.gd"
ACT_SETTINGS_READS = {
    ("<module>", "ActSnapshot"): "the typed `snapshot` field's zeroed default",
    ("snapshot_values", "act_snapshot"): "the act's one bulk snapshot",
    ("live_preferences", "preferences"): "the live preference refresh",
}
# The runtime node parents no child: the act audio node and the pose-scope tail tuck are created by
# their owners. A row is added only for a system-owned node the host itself must add.
RUNTIME_CHILD_NODES = {}
# The runtime node's public functions: the entry's lifetime ops. `act`, `gate` and `pony` are
# properties, not rows. A new public function is a facade regrowth; the comparison runs both ways.
NODE_SURFACE = {
    "live_id": "the stable pony id the entry and ponies read",
    "attach_to_body": "the handover's reparent off the old body",
    "adopt_body": "the handover's reparent onto the new body",
}
# The runtime node's public properties: the two handles and the presented body. They are properties
# rather than rows because the entry reads them without a call; the comparison runs both ways.
NODE_PROPERTIES = {
    "act": "the act's one session handle",
    "gate": "the offer-facing act gate handle",
    "pony": "the presented body; its setter rebinds the bundle",
}
# A file over this many lines is reported as a smell, never as a failure. Size is a hint that a
# module may be mixing concerns; the ownership and boundary rules below are the hard gates.
LARGE_FILE_LINES = 1000
# One sink and one profiler: every other shipped script reaches them through `LOG` and `PERF`. A
# hand-written print, warning, timestamp or engine monitor is a second one.
LOG_MODULES = {"shared/log.gd", "shared/perf.gd"}
LOG_BLEED = (
    "print(",
    "printerr(",
    "push_warning(",
    "push_error(",
    '"[unfplap] "',
    "get_ticks_usec() -",
    "Performance.get_monitor",
    "Engine.get_frames_per_second",
    "RenderingServer.get_rendering_info",
)

RUNTIME_RAW_INPUT = (
    re.compile(r"\bInput\."),
    re.compile(r"\bInputMap\."),
    re.compile(r"\bInputEvent\w*"),
    re.compile(r"\bKEY_[A-Z0-9_]+\b"),
    re.compile(r"\bMOUSE_MODE_[A-Z0-9_]+\b"),
    re.compile(r"^func\s+_(?:unhandled_|gui_)?input\(", re.MULTILINE),
)
# Service files another owner may extend or preload as a documented extension point. The source
# base is a provider contract, not a second facade; the anatomy body binding is the attachment
# contract the body-change service constructs from the anatomy facade it is handed.
PUBLIC_SERVICE_FILES = {"body_change/source.gd", "anatomy/body_binding.gd", "world/game.gd"}
# A public accessor module outside a `service.gd` facade joins the weak-signature scan.
TYPING_EXTRA = ("world/game.gd",)
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
    # The act modules are the runtime's own files: they may preload services, and a service that
    # preloads them is a host import, not a service edge.
    if path.startswith("act/"):
        return Owner("runtime", path, False, "orchestrator")
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
    "shared/log.gd": "log sink",
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
    "shared/perf.gd": "one profiler",
    "shared/pose_catalog.gd": "pose ids and schema",
    "shared/pose_offer.gd": "typed act offer",
    "shared/pose_specs.gd": "pose capability table",
    "shared/pose_view.gd": "pose read model",
    "shared/relationship_cue.gd": "relationship prompt note",
    "shared/rump_cone.gd": "standing offer zone",
    "shared/settings_change.gd": "settings change notification",
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
    "offer": ("world", "the entry's service list", "`on_world(host)`", "`on_world_closed()`", "yes"),
    "ponies": ("world", "static initialization", "the entry binds its factory and services", "`shutdown()`", "yes"),
    "settings": ("world", "static initialization", "registry load", "process exit", "yes"),
    "registry": ("process", "static initialization", "none", "`reset()`", "yes"),
    "eligibility": ("world", "the entry's service list", "`on_world(host)`", "`shutdown()`", "yes"),
    "scene_gate": ("per-pony", "`runtime._init()`", "`bind()`/`configure()`", "act teardown", "yes"),
    "scene_hold": ("per-pony", "`runtime._init()`", "`bind()`/`claim_nav()`", "runtime free", "yes"),
    "rest": ("per-act", "`runtime._init()`", "`bind()`", "act teardown", "yes"),
    "hands": ("per-act", "`runtime`", "`bind()`/`begin()`", "act teardown", "yes"),
    "anatomy": ("world + per-act bridge", "the entry's service list", "`setup()`/`new_act()`", "`on_world_closed()`/`shutdown()`", "yes"),
    "vr": ("per-act", "`anatomy` act bridge", "act start", "act end", "yes"),
    "initiation": ("world", "the entry's service list", "`setup()`", "`on_world_closed()`", "yes"),
    "negotiation": ("world", "the entry's service list", "`bind()`/`on_world(host)`", "`on_world_closed()`", "yes"),
    "memory": ("world", "the entry's service list", "none", "freed with the entry", "yes"),
    "dialogue": ("per-act", "`runtime`", "`setup()`/`configure()`", "`reset()`/act end", "yes"),
    "readiness": ("per-act", "`runtime._init()`", "`configure()`", "`reset()`", "yes"),
    "poses": ("per-act", "`runtime._init()`", "`bind()`/`begin()`", "`release_pose()`", "yes"),
    "camera": ("per-act", "`runtime._init()`", "`bind()`/`begin_act()`", "`finish_act()`/act teardown", "yes"),
    "kiss": ("per-act", "`runtime`", "`bind()`", "act teardown", "yes"),
    "integrations": ("per-act", "`runtime._integrations_controller()`", "`begin()`", "`reset()`", "yes"),
    "summary": ("per-act", "`runtime._init()`", "`reset_act()`", "act teardown", "yes"),
    "afterglow": ("per-act", "`runtime._init()`", "`begin()`", "`reset()`", "yes"),
    "face": ("per-act", "`runtime._init()`", "`bind()`", "`shutdown()`", "yes"),
    "reactions": ("per-act", "`runtime._init()`", "`bind_scene()`/`begin_act()`", "`end_act()`", "yes"),
    "stool": ("world + per-act handle", "the entry's service list", "`setup()`/`new_act()`", "`on_world_closed()`/`shutdown()`", "yes"),
    "audio": ("per-pony", "`runtime`", "`begin()`", "`end()`", "yes"),
    "hud": ("world", "the entry's service list", "`on_world(host)`", "`on_world_closed()`; freed with the entry", "yes"),
    "input": ("world", "the entry's service list", "`_ready()`", "freed with the entry", "yes"),
    "debug": ("process", "static initialization", "none", "none", "yes"),
}


def render_lifecycle(sid: str) -> str:
    scope, constructed, begin, end, idem = LIFECYCLES.get(
        sid, ("world", "the entry's service list", "none", "world close", "yes"))
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


def file_public_functions(service: str, path: Path) -> list[dict[str, str]]:
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


def public_functions(service: str) -> list[dict[str, str]]:
    return file_public_functions(service, ROOT / service / "service.gd")


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
    for name in TYPING_EXTRA:
        owner = owner_of(name)
        label = owner.id if owner is not None else name
        for row in file_public_functions(label, ROOT / name):
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


DUCK_CALL = re.compile(r'\.call\("[A-Za-z_]')
DUCK_SET = re.compile(r'\.set\("')


def duck_sites(text: str) -> int:
    """Non-comment lines that dispatch by string: `.call("name"` or `.set("`."""
    return sum(
        1 for line in text.splitlines()
        if not line.lstrip().startswith("#")
        and (DUCK_CALL.search(line) or DUCK_SET.search(line))
    )


def duck_config() -> dict:
    return load_json(DUCK_TYPING, {"allowed": [], "baseline": []})


def duck_typing() -> list[dict[str, object]]:
    """The current string-dispatch count per shipped file, with the accessors left out."""
    allowed = {str(name) for name in duck_config().get("allowed", [])}
    rows: list[dict[str, object]] = []
    for path in shipped_sources():
        name = rel(path)
        if name in allowed:
            continue
        count = duck_sites(path.read_text(encoding="utf-8"))
        if count:
            rows.append({"file": name, "count": count})
    rows.sort(key=lambda row: str(row["file"]))
    return rows


def check_duck_typing(failure: Failure) -> None:
    """String dispatch may only shrink outside the allowlisted accessor modules.

    A new file, a grown file and a stale baseline row all fail, so a reflection site is either
    removed, moved into an accessor, or added on purpose with a fresh baseline.
    """
    config = duck_config()
    allowed = {str(name) for name in config.get("allowed", [])}
    baseline = {
        str(row.get("file", "")): int(row.get("count", 0))
        for row in config.get("baseline", [])
    }
    current = {str(row["file"]): int(row["count"]) for row in duck_typing()}
    for name in sorted(current):
        if name not in baseline:
            failure.add("%s has new string dispatch (%d sites): use a typed accessor or add a "
                        "baseline row" % (name, current[name]))
        elif current[name] > baseline[name]:
            failure.add("%s grew its string dispatch (%d sites, baseline %d)" % (
                name, current[name], baseline[name]))
    for name in sorted(baseline):
        if name in allowed:
            failure.add("duck-typing baseline row for an allowlisted accessor: %s" % name)
        elif name not in current:
            failure.add("stale duck-typing baseline row (remove it): %s" % name)


def write_duck_typing() -> None:
    ARCH.mkdir(exist_ok=True)
    config = duck_config()
    rows = duck_typing()
    payload = {
        "allowed": list(config.get("allowed", [])),
        "baseline": rows,
    }
    DUCK_TYPING.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print("ARCH_DUCK_TYPING_WRITTEN files=%d sites=%d allowed=%d" % (
        len(rows), sum(int(row["count"]) for row in rows), len(payload["allowed"])))


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


def function_offsets(text: str) -> list[tuple[int, str]]:
    """Every top-level function's start offset and name, in source order."""
    return [(match.start(), match.group(1)) for match in
            re.finditer(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE)]


CALLABLE_TARGET = re.compile(
    r"Callable\(\s*([A-Za-z_]\w*)\s*,\s*\"([A-Za-z_]\w*)\"\s*\)")
PRELOAD_CONST = re.compile(
    r"^const\s+(\w+)\s*(?::\s*[\w.\[\]]+\s*)?(?::=|=)\s*preload\(\s*\"(res://[^\"]+\.gd)\"\s*\)",
    re.MULTILINE)
TYPED_VAR = re.compile(r"^var\s+(\w+)\s*:\s*([A-Za-z_]\w*)", re.MULTILINE)
INFERRED_VAR = re.compile(r"^var\s+(\w+)\s*:=\s*([A-Za-z_]\w*)\.new\(", re.MULTILINE)
MOD_EXTENDS = re.compile(r'^extends\s+"(res://mods/unfplap/[^"]+\.gd)"', re.MULTILINE)


def _code_lines(text: str) -> str:
    """Source with comment lines and end-of-line comments removed, so a doc example is not a
    binding. A `#` inside a string can truncate a line, which only makes the scan miss a site."""
    lines = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        cut = line.find("#")
        lines.append(line if cut < 0 else line[:cut])
    return "\n".join(lines)


def _script_methods(path: Path, seen: set[Path]) -> tuple[bool, set[str]]:
    """(fully_scanned, functions) for one mod script and its mod ancestors."""
    if path in seen or not path.is_file():
        return False, set()
    seen.add(path)
    text = _code_lines(path.read_text(encoding="utf-8"))
    names = set(re.findall(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE))
    parent = MOD_EXTENDS.search(text)
    if parent:
        target = ROOT / parent.group(1).replace("res://mods/unfplap/", "")
        nested, inherited = _script_methods(target, seen)
        return nested, names | inherited
    if re.search(r"^extends\b", text, re.MULTILINE):
        return False, names
    return True, names


def check_callable_targets(failure: Failure) -> None:
    """A named callback must name a method that exists.

    `Callable(self, "name")` is checked against the same file. `Callable(obj, "name")` is checked
    when `obj` is a module-level field or constant whose declared or inferred type is one of the
    mod's preloaded scripts; an unresolvable receiver is skipped. This is the guard that keeps a
    renamed helper from silently returning its fallback forever.
    """
    cache: dict[Path, tuple[bool, set[str]]] = {}
    for path in shipped_sources():
        text = _code_lines(path.read_text(encoding="utf-8"))
        funcs = set(re.findall(r"^(?:static\s+)?func\s+(\w+)\(", text, re.MULTILINE))
        consts = {m.group(1): m.group(2) for m in PRELOAD_CONST.finditer(text)}
        types: dict[str, str] = {}
        for match in TYPED_VAR.finditer(text):
            name, declared = match.group(1), match.group(2)
            if declared in consts:
                types[name] = consts[declared]
        for match in INFERRED_VAR.finditer(text):
            name, declared = match.group(1), match.group(2)
            if declared in consts:
                types.setdefault(name, consts[declared])
        for match in CALLABLE_TARGET.finditer(text):
            receiver, method = match.group(1), match.group(2)
            line = line_of(text, match.start())
            if receiver == "self":
                if method not in funcs:
                    failure.add("%s:%d binds Callable(self, \"%s\") but defines no %s()" % (
                        rel(path), line, method, method))
                continue
            target = types.get(receiver)
            if not target:
                continue
            script = ROOT / target.replace("res://mods/unfplap/", "")
            if not script.is_file():
                continue
            if script not in cache:
                cache[script] = _script_methods(script, set())
            scanned, names = cache[script]
            if scanned and method not in names:
                failure.add("%s:%d binds Callable(%s, \"%s\") but %s defines no %s()" % (
                    rel(path), line, receiver, method, rel(script), method))

    # The composition root receives the runtime node as a parameter, so its node callables have no
    # typed field to resolve against. They name methods on `runtime.gd`; check them there, or a
    # renamed host method silently returns its fallback forever.
    builder = ROOT / "act" / "build.gd"
    runtime_path = ROOT / "runtime.gd"
    if builder.is_file() and runtime_path.is_file():
        runtime_funcs = set(re.findall(
            r"^(?:static\s+)?func\s+(\w+)\(",
            _code_lines(runtime_path.read_text(encoding="utf-8")), re.MULTILINE))
        builder_text = _code_lines(builder.read_text(encoding="utf-8"))
        for match in CALLABLE_TARGET.finditer(builder_text):
            if match.group(1) != "node":
                continue
            if match.group(2) not in runtime_funcs:
                failure.add(
                    "act/build.gd:%d binds Callable(node, \"%s\") but runtime.gd defines no %s()" % (
                        line_of(builder_text, match.start()), match.group(2), match.group(2)))



def enclosing_function(offsets: list[tuple[int, str]], at: int) -> str:
    """The top-level function around `at`, or `<module>` for the field and constant block."""
    name = "<module>"
    for start, function in offsets:
        if start > at:
            break
        name = function
    return name


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
    exit_path = ROOT / "act" / "exit.gd"
    if not exit_path.is_file():
        failure.add("missing act/exit.gd: it owns the one teardown and the pose ledger")
        exit_text = ""
    else:
        exit_text = exit_path.read_text(encoding="utf-8")

    # One teardown: `act/exit.gd:run()` is the only scene-restoring body, and the exit's own
    # routes plus the consent stop are its only callers. No route repeats a teardown step.
    if exit_text and len(re.findall(r"^func run\(", exit_text, re.MULTILINE)) != 1:
        failure.add("act/exit.gd must define exactly one run()")
    for name in ("finish_restore", "restore_now", "force_stop"):
        body = function_body(exit_text, name)
        if not body:
            failure.add("act/exit.gd is missing %s()" % name)
            continue
        if "run(" not in body:
            failure.add("act/exit.gd:%s() must end through run()" % name)
        for call in TEARDOWN_STEPS:
            if call in body:
                failure.add("act/exit.gd:%s() must not call %s directly" % (name, call))
    if "restore_now()" not in function_body(exit_text, "force_stop"):
        failure.add("act/exit.gd:force_stop() must restore through restore_now()")
    teardown_callers: set[tuple[str, str]] = set()
    for path in shipped_sources():
        text = path.read_text(encoding="utf-8")
        offsets = function_offsets(text)
        for match in re.finditer(r"(?<![\w])run\((?:true|false|rejoin_cuddle)\)", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            if line.lstrip().startswith(("#", "func ")):
                continue
            teardown_callers.add((rel(path), enclosing_function(offsets, match.start())))
    expected_callers = {("act/exit.gd", "abort"), ("act/exit.gd", "finish_restore"),
                        ("act/exit.gd", "restore_now"), ("act/exit.gd", "force_stop"),
                        ("act/consent.gd", "stop_with_her")}
    for caller in sorted(teardown_callers - expected_callers):
        failure.add("the one teardown has an unexpected caller: %s:%s" % caller)
    for caller in sorted(expected_callers - teardown_callers):
        failure.add("the one teardown is missing its caller: %s:%s" % caller)
    # The act session keeps the one-line stop delegate for the entry, `ponies` and the suites.
    session_path = ROOT / "act" / "session.gd"
    session_text = session_path.read_text(encoding="utf-8") if session_path.is_file() else ""
    stop_body = function_body(session_text, "force_stop")
    stop_lines = [line.strip() for line in stop_body.splitlines()[1:]
                  if line.strip() and not line.strip().startswith("#")]
    if stop_lines != ["exit.force_stop()"]:
        failure.add("act/session.gd:force_stop() must be the one-line exit.force_stop() delegate")

    # The start ledger's recipe keeps its order; the checker reads the tokens, not the prose.
    start_path = ROOT / "act" / "start.gd"
    if not start_path.is_file():
        failure.add("missing act/start.gd: it owns the ordered start")
    else:
        run_body = function_body(start_path.read_text(encoding="utf-8"), "run")
        cursor = 0
        for step in START_LEDGER_ORDER:
            at = run_body.find(step, cursor)
            if at < 0:
                failure.add("act/start.gd run() must keep %s at its position" % step)
                break
            cursor = at + len(step)

    # The pose ledger keeps its pose-scope steps and act-scope resets in their current order, and
    # only the act exit, the new-act prep and the body-swap suspension call it.
    free = function_body(exit_text, "free_pose")
    cursor = 0
    for call in POSE_LEDGER_ORDER:
        at = free.find(call, cursor)
        if at < 0:
            failure.add("act/exit.gd free_pose() must keep %s at its position" % call)
            break
        cursor = at + len(call)
    ledger_callers: set[tuple[str, str]] = set()
    for path in shipped_sources():
        text = path.read_text(encoding="utf-8")
        offsets = function_offsets(text)
        for match in re.finditer(r"(?<![\w])free_pose\(\)", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            if line.lstrip().startswith(("#", "func ")):
                continue
            ledger_callers.add((rel(path), enclosing_function(offsets, match.start())))
    for caller in sorted(ledger_callers):
        if caller not in POSE_LEDGER_CALLERS:
            failure.add("the pose ledger has an unexpected caller: %s:%s" % caller)
    for caller in sorted(POSE_LEDGER_CALLERS):
        if caller not in ledger_callers:
            failure.add("the pose ledger is missing its caller: %s:%s" % caller)
    release_calls = set()
    for path in shipped_sources():
        for line in path.read_text(encoding="utf-8").splitlines():
            if "release_pose()" in line and not line.lstrip().startswith(("#", "func ")):
                release_calls.add(rel(path))
    if release_calls != {"act/exit.gd"} or "release_pose()" not in free:
        failure.add("release_pose() must be called only from the pose ledger")

    # The frame schedule advances the pose edge before the view refresh, then fans the change out;
    # the fixed owner order is the seam, and neither body is a second teardown. The schedule is
    # `act/tick.gd`'s; `act/session.gd` is the entry that forwards one frame to it.
    tick_path = ROOT / "act" / "tick.gd"
    session_path = ROOT / "act" / "session.gd"
    if not tick_path.is_file():
        failure.add("missing act/tick.gd: it owns the ordered frame schedule")
        tick_text = ""
    else:
        tick_text = tick_path.read_text(encoding="utf-8")
    if session_path.is_file():
        for name in ("tick", "render"):
            body = function_body(session_path.read_text(encoding="utf-8"), name)
            if "ticker." not in body:
                failure.add("act/session.gd:%s() must forward to the frame schedule" % name)
    tick = function_body(tick_text, "_tick")
    tick_at = tick.find("context.pose.tick(delta)")
    facts_at = tick.find("session.refresh_view()")
    fanout_at = tick.find("_fanout()", facts_at if facts_at >= 0 else 0)
    if tick_at < 0 or facts_at < 0 or tick_at > facts_at:
        failure.add("act/tick.gd:_tick() must tick the pose before the view refresh")
    if facts_at < 0 or fanout_at < facts_at:
        failure.add("act/tick.gd:_tick() must fan the pose change out after the view refresh")
    fanout = function_body(tick_text, "_fanout")
    cursor = 0
    for owner in POSE_FANOUT_ORDER:
        at = fanout.find(owner, cursor)
        if at < 0:
            failure.add("act/tick.gd:_fanout() must name %s in order" % owner)
            break
        cursor = at + len(owner)
    for name, body in (("_tick", tick), ("_fanout", fanout)):
        for call in ACT_EXIT_CALLS:
            if call in body:
                failure.add("act/tick.gd:%s() must not call %s" % (name, call))

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

    # One resume: the swap module keeps the only resume path, and adoption never resumes itself.
    swap_path = ROOT / "act" / "swap.gd"
    if not swap_path.is_file():
        failure.add("missing act/swap.gd: it owns the body-swap seams and the one resume")
        swap_text = ""
    else:
        swap_text = swap_path.read_text(encoding="utf-8")
    if len(re.findall(r"^func resume\(", swap_text, re.MULTILINE)) != 1:
        failure.add("act/swap.gd must define exactly one resume()")
    for path in shipped_sources():
        if path == swap_path:
            continue
        if "_swap.resume(" in path.read_text(encoding="utf-8"):
            failure.add("%s must not resume a body swap" % rel(path))
    if ".resume(" in function_body(runtime, "adopt_body"):
        failure.add("adopt_body() must not resume; the watcher owns the one resume")

    # The provider policy owns the offer prompt and the reveal magnitudes. The act handover only
    # asks the typed policy and executes its generic effects.
    handover = (ROOT / "body_change" / "act.gd").read_text(encoding="utf-8")
    for name in ("FORM_OFFER_PROMPT", "FORM_REVEAL_HEAT", "FORM_REVEAL_PEAK_SCORE"):
        if name in runtime or name in handover:
            failure.add("the act handover must not own the provider policy value %s" % name)
    offer = function_body(handover, "offer_tick")
    for needle in (".should_offer(", ".offer_prompt()"):
        if needle not in offer:
            failure.add("body_change/act.gd offer_tick() must ask the typed policy for %s" % needle)
    if ".on_reveal(" not in function_body(handover, "_commit_form_reveal"):
        failure.add("_commit_form_reveal() must execute the typed policy's on_reveal()")
    if ".on_offer_accepted(" not in function_body(handover, "_apply_offer_accepted"):
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
        if len(re.findall(r"^func %s\(" % name, session_text, re.MULTILINE)) != 1:
            failure.add("act/session.gd must define exactly one %s()" % name)

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
        # `act/settings.gd` is the act's snapshot owner, not a declaration module: it holds the
        # one bulk copy of the act tunables and the live apply. Any other `settings.gd` outside
        # `settings/` is a second declaration surface.
        if path.name == "settings.gd" and path.parent.name not in ("settings", "act"):
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
    """The composition-root rules: nothing but the entry names the entry, no reach-in into the
    entry, and a scene-only world facade."""
    # A private reach-in is `get("_name")`/`call("_name")` through the entry or a runtime. A
    # public member reached by string is still a locator, and naming the entry by member is the
    # same locator without the string, so both are refused outside `main.gd` and `tests/`.
    reach_in = re.compile(r'\b(?:main|runtime)\.(?:call|get)\("_')
    entry_rules = (
        (ENTRY_MEMBER, "a preloaded facade, a `WORLD` read or a host parameter"),
        (ENTRY_DECLARATION, "a preloaded facade, a `WORLD` read or a host parameter"),
        (ENTRY_PRELOAD, "the facade it needs or `WORLD`"),
        (ENTRY_ARGUMENT, "a typed host parameter"),
    )
    for path in shipped_sources():
        if path == ROOT / "main.gd":
            continue
        text = path.read_text(encoding="utf-8")
        for match in reach_in.finditer(text):
            failure.add("%s:%d reaches into a private member: %s" % (
                rel(path), line_of(text, match.start()), match.group(0)))
        for pattern, instead in entry_rules:
            for match in pattern.finditer(text):
                failure.add(
                    "%s:%d names the entry (%s): use %s; only main.gd and tests/ may name `main`"
                    % (rel(path), line_of(text, match.start()), match.group(0).strip(), instead))

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


def check_runtime_shape(failure: Failure) -> None:
    """The thin-runtime invariant: a host composes and orders; it implements no system's rules.

    Four shapes a regression cannot hide: one `state` writer, no raw input decoding, settings at
    the act's snapshot boundaries only, and only the documented system-owned child nodes. The
    allow-lists are compared both ways so a new use and a stale row both fail.
    """
    path = ROOT / "runtime.gd"
    if not path.is_file():
        failure.add("missing runtime.gd")
        return
    text = path.read_text(encoding="utf-8")
    offsets = function_offsets(text)

    # The act state has one owner: `act/session.gd` declares it and only `_set_state()` writes it.
    # The runtime node keeps a read-only forward and must contain no assignment at all.
    session_path = RUNTIME_STATE_OWNER
    if not session_path.is_file():
        failure.add("missing act/session.gd: it owns the act state")
    else:
        session_text = session_path.read_text(encoding="utf-8")
        session_offsets = function_offsets(session_text)
        if len(re.findall(r"^func _set_state\(", session_text, re.MULTILINE)) != 1:
            failure.add("act/session.gd must define exactly one _set_state()")
        if not re.search(r"^var state:\s*int\b", session_text, re.MULTILINE):
            failure.add("act/session.gd must declare the typed `state` field once")
        for match in re.finditer(r"^\s*(?:self\.)?state\s*=(?!=)", session_text,
                                 re.MULTILINE):
            if enclosing_function(session_offsets, match.start()) != "_set_state":
                failure.add(
                    "act/session.gd:%d assigns `state` outside %s(); it is the one writer" % (
                        line_of(session_text, match.start()), RUNTIME_STATE_WRITER))
    for match in re.finditer(r"^\s*(?:self\.)?state\s*=(?!=)", text, re.MULTILINE):
        failure.add("runtime.gd:%d assigns `state`; %s is the one writer" % (
            line_of(text, match.start()), RUNTIME_STATE_WRITER))

    # The node's public surface is the entry's lifetime ops; a new public function is a facade
    # regression. The allow-list is compared both ways.
    public_funcs = set(re.findall(r"^func ([A-Za-z]\w*)\(", text, re.MULTILINE))
    for name in sorted(public_funcs - set(NODE_SURFACE)):
        failure.add("runtime.gd:%s() is a new public function; the node surface is fixed" % name)
    for name, reason in sorted(NODE_SURFACE.items()):
        if name not in public_funcs:
            failure.add("the node surface allow-list row %s is stale (%s)" % (name, reason))

    # The same both-ways rule for the node's properties: `act`, `gate` and `pony` only.
    properties = set(re.findall(r"^var ([A-Za-z]\w*)\s*:", text, re.MULTILINE))
    for name in sorted(properties - set(NODE_PROPERTIES)):
        failure.add("runtime.gd:%s is a new public property; the node surface is fixed" % name)
    for name, reason in sorted(NODE_PROPERTIES.items()):
        if name not in properties:
            failure.add("the node property allow-list row %s is stale (%s)" % (name, reason))

    # Raw input has one owner: input/service.gd decodes keys, buttons, motion and capture.
    for pattern in RUNTIME_RAW_INPUT:
        for match in pattern.finditer(text):
            failure.add("runtime.gd:%d decodes raw input (%s); input/service.gd owns it" % (
                line_of(text, match.start()), match.group(0).strip()))

    # Settings arrive once per act and again on apply_live_settings(), never per frame.
    reads: dict[tuple[str, str], int] = {}
    for match in re.finditer(r"SETTINGS\.(\w+)", text):
        key = (enclosing_function(offsets, match.start()), match.group(1))
        reads.setdefault(key, line_of(text, match.start()))
    for key, line in sorted(reads.items()):
        if key not in RUNTIME_SETTINGS_READS:
            failure.add(
                "runtime.gd:%d reads SETTINGS.%s in %s(); take a snapshot value or add an "
                "allow-list row only at an act boundary" % (line, key[1], key[0]))
    for key, reason in sorted(RUNTIME_SETTINGS_READS.items()):
        if key not in reads:
            failure.add("the runtime settings allow-list row %s -> %s is stale (%s)" % (
                key[0], key[1], reason))

    # The act's settings owner holds the one snapshot; its boundary reads are checked the same
    # way, so a new per-frame settings read there fails too.
    settings_path = ACT_SETTINGS_OWNER
    if not settings_path.is_file():
        failure.add("missing act/settings.gd: it owns the act's settings snapshot")
    else:
        settings_source = settings_path.read_text(encoding="utf-8")
        settings_offsets = function_offsets(settings_source)
        settings_reads: dict[tuple[str, str], int] = {}
        for match in re.finditer(r"SETTINGS\.(\w+)", settings_source):
            key = (enclosing_function(settings_offsets, match.start()), match.group(1))
            settings_reads.setdefault(key, line_of(settings_source, match.start()))
        for key, line in sorted(settings_reads.items()):
            if key not in ACT_SETTINGS_READS:
                failure.add(
                    "act/settings.gd:%d reads SETTINGS.%s in %s(); take a snapshot value or add "
                    "an allow-list row only at an act boundary" % (line, key[1], key[0]))
        for key, reason in sorted(ACT_SETTINGS_READS.items()):
            if key not in settings_reads:
                failure.add("the act settings allow-list row %s -> %s is stale (%s)" % (
                    key[0], key[1], reason))

    # The runtime parents only the nodes a system owns; it constructs no scene of its own.
    children: dict[str, int] = {}
    for match in re.finditer(r"\badd_child\(", text):
        owner = enclosing_function(offsets, match.start())
        children.setdefault(owner, line_of(text, match.start()))
    for owner, line in sorted(children.items()):
        if owner not in RUNTIME_CHILD_NODES:
            failure.add("runtime.gd:%d creates a child node in %s(); only the documented "
                        "system-owned nodes are parented here" % (line, owner))
    for owner, reason in sorted(RUNTIME_CHILD_NODES.items()):
        if owner not in children:
            failure.add("the runtime child-node allow-list row %s is stale (%s)" % (owner, reason))


# The act's player frame and its view each have one writer. Each row is a write token and the files
# allowed to carry it, and the scan is compared both ways: a second writer fails, and a row no file
# carries any more is stale. The momentary control lock in the base-game accessor and the standing
# kiss is a base-game hold with his controls released, not the act's frame lock.
ACT_STATE_WRITES = {
    'set("_stand_eye"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'set("_eye_height"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'call("_set_eye_y"': {"world/game.gd": "the eye-line accessor writes through the rig's setter"},
    'set("controls_locked"': {
        "world/game.gd": "a base-game call with his controls released",
        "kiss/service.gd": "the standing kiss call, restored at once",
    },
    'set("_pitch"': {
        "world/game.gd": "the pitch accessor writes his own look",
    },
    'body.global_position = ': {"act/frame.gd": "the frame places him"},
    'body.rotation.y = ': {
        "act/frame.gd": "the base facing",
        "camera/view.gd": "the live lean turns his own look",
    },
    '_player.rotation.y = ': {"act/frame.gd": "the frame restores his captured look"},
    'host.pony.global_transform = ': {"act/frame.gd": "the frame restores the scene it found"},
    'rig.pony.reset_motion(': {"act/frame.gd": "the player-pony start places her"},
    'context.pose.render_write(': {"act/frame.gd": "the frame places the act body once"},
    'context.pose.write_render_frame(': {"act/view.gd": "the render-time act body write"},
    '_missionary_view.global_position = ': {"camera/view.gd": "the one act view"},
    '_missionary_view.global_basis = ': {"camera/view.gd": "the one act view"},
    '_missionary_view.current = ': {"camera/view.gd": "the one act view"},
    'camera.position = ': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.y = ': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.z -=': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.x +=': {"camera/view.gd": "the player camera's live offset"},
    'camera.rotation.z = ': {"camera/view.gd": "the live lean roll"},
    'camera.rotation.x = ': {"camera/view.gd": "the live lean pitch"},
    'view.rotation.x = ': {
        "act/frame.gd": "the base aim and its restore",
        "camera/view.gd": "the live lean pitch on the player camera",
    },
}


def check_act_owners(failure: Failure) -> None:
    """The act's player frame and its view have one writer each.

    The frame places, stances and restores Anon; the view applies the live look and writes the act
    view node. One owner per state is the property the scattered camera setup lost, so the write
    tokens are checked as an allow-list in both directions.
    """
    found: dict[str, set[str]] = {token: set() for token in ACT_STATE_WRITES}
    for path in shipped_sources():
        text = _code_lines(path.read_text(encoding="utf-8"))
        for token in ACT_STATE_WRITES:
            if token in text:
                found[token].add(rel(path))
    for token, owners in ACT_STATE_WRITES.items():
        for name in sorted(found[token] - set(owners)):
            failure.add(
                "%s writes the act's player/view state (%s); %s owns it" % (
                    name, token, ", ".join(sorted(owners))))
        for name, reason in sorted(owners.items()):
            if name not in found[token]:
                failure.add("the act write row %s (%s) is stale for %s" % (token, reason, name))


def report_large_files() -> None:
    """Report files over the smell threshold. Size is information, not a gate."""
    for path in sorted(shipped_sources()):
        lines = len(path.read_text(encoding="utf-8").splitlines())
        if lines > LARGE_FILE_LINES:
            print("SMELL large file: %s (%d lines)" % (rel(path), lines))


def check_entry_shape(failure: Failure) -> None:
    """The entry constructs and binds; it never dispatches by string or assigns a service's fields."""
    main_path = ROOT / "main.gd"
    if not main_path.is_file():
        failure.add("missing main.gd")
        return
    text = main_path.read_text(encoding="utf-8")
    for needle in (".call(", '.get("', '.set("'):
        for match in re.finditer(re.escape(needle), text):
            failure.add(
                "main.gd:%d dispatches by string (%s); name the typed member"
                % (line_of(text, match.start()), needle))
    for match in re.finditer(r"\baction_[A-Za-z0-9_]", text):
        failure.add(
            "main.gd:%d registers an action handler; the debug service owns its actions"
            % line_of(text, match.start()))


def check_log_bleed(failure: Failure) -> None:
    """Only the log sink prints and only the profiler reads a clock or an engine monitor."""
    for path in shipped_sources():
        name = rel(path)
        if name in LOG_MODULES:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.lstrip().startswith("#"):
                continue
            for needle in LOG_BLEED:
                if needle in line:
                    failure.add("%s:%d writes outside the one sink (%s): use LOG or PERF" % (
                        name, number, needle))


def check() -> int:
    failure = Failure()
    violations = scan_violations()
    exceptions = check_exceptions(failure, violations)
    check_docs(failure)
    check_typing(failure)
    check_duck_typing(failure)
    check_sources(failure)
    check_callable_targets(failure)
    check_boundaries(failure)
    check_runtime_shape(failure)
    check_entry_shape(failure)
    check_log_bleed(failure)
    check_act_owners(failure)
    check_owners(failure)
    check_tests(failure)
    failures = len(failure.messages)
    for message in failure.messages:
        print("FAIL", message)
    report_large_files()
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
    parser.add_argument("--write-duck-typing", action="store_true")
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
    if args.write_duck_typing:
        write_duck_typing()
        return 0
    if args.graph:
        graph()
        return 0
    return check()


if __name__ == "__main__":
    sys.exit(main())
