#!/usr/bin/env python3
"""Architecture gate for unfplap.

This script scans the preload graph, enforces the layer, owner, game-boundary and
re-export rules, checks the documentation index and facade notes, and tracks
temporary boundary/typing debt.

Every shipped ``.gd`` must resolve to an owner — a service, ``shared/`` or one of the
three orchestrators — so a directory without a facade cannot add code whose
edges the boundary rules would classify as external and allow. ``api.gd`` is the
preferred public entry; ``service.gd`` is the legacy name.

Usage:
    scripts/architecture.py --check
    scripts/architecture.py --graph
    scripts/architecture.py --audit-surface
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
    "context.hold.release_all_beats()",
    "context.standing_anon.remove()",
    "context.pose.leave_pose_body()",
    "context.reactions.end_act()",
    "context.pose.release_pose()",
)
POSE_FANOUT_ORDER = (
    "context.pose",
    "context.camera",
    "context.hands",
    "context.kiss",
    "context.anatomy",
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
    "context.audio.begin_act(",
    "session.begin_pose_in()",
    "context.hud.show_act(context.facts)",
)
# The pose ledger's callers: the one act exit, the new-act prep and the body-swap suspension.
# A new caller is a design decision, so the set is exact and compared both ways.
POSE_LEDGER_CALLERS = {
    ("act/exit.gd", "run"),
    ("act/start.gd", "_build_pose"),
    ("act/swap.gd", "release_swap_pose"),
}
# Rule 1, full form: only the entry names the entry. A service that needs another service
# preloads its facade, one that needs the scene reads `WORLD`, and one that needs a callback takes
# a host parameter. `tests/` and the prose literal `main.gd` are allowed.
MAIN_CONST = re.compile(
    r'^const\s+([A-Z][A-Z0-9_]*)\s*:=\s*preload\("(res://[^"]+)"\)', re.MULTILINE)
MAIN_ADD = re.compile(r"_add\(\s*([A-Z][A-Z0-9_]*)\.new\(")
MAIN_ADD_HUD = re.compile(r"_add_hud\(\s*([A-Z][A-Z0-9_]*)\.new\(")
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
    "scene": "the per-pony scene gate handle",
    "start": "the per-pony start handle",
    "presentation": "the per-pony presentation handle",
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
PUBLIC_SERVICE_FILES = {"body_change/source.gd", "world/game.gd"}
# The lifecycle base is a no-behaviour contract: every world service extends it, so it is not a
# dependency edge.
SERVICE_BASE = "shared/service.gd"
HUD_FACADE = "hud/service.gd"
# A public accessor module outside a `service.gd` facade joins the weak-signature scan.
TYPING_EXTRA = ("world/game.gd",)
# The five body-bound systems `body_change.wire()` builds and registers. The entry names none of
# them: a new binding adds a preload to the service, not to the composition root.
BODY_BINDINGS = (
    "body_change/anatomy_binding.gd",
    "body_change/runtime_binding.gd",
    "body_change/lod_binding.gd",
    "body_change/garment_binding.gd",
    "body_change/smack_binding.gd",
)
SHARED_KINDS = {
    "act_history.gd": "store",
    "act_facts.gd": "read model",
}
# The index's service table is the one router: a row names the contract and the tests. The table
# row is parsed, not a section in the contract.
SERVICE_INDEX = "## Services"
TABLE_ROW = re.compile(r"^\|(.*)\|\s*$", re.MULTILINE)
SERVICE_IGNORE_DOCS = {"README.md", "api.md", "runtime.md"}
# A facade's public types carry a `##` note; api.gd's public members are the strict surface.
PUBLIC_TYPE = re.compile(r"^(?:class|enum)\s+([A-Za-z_]\w*)\b", re.MULTILINE)
API_MEMBER = re.compile(
    r"^(?:const\s+([A-Z][A-Z0-9_]*)|(?:static\s+)?func\s+([A-Za-z_]\w*)|var\s+([A-Za-z_]\w*))")
GAME_SOURCE = "world/game.gd"


class Failure:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, text: str) -> None:
        self.messages.append(text)

    def extend(self, texts: list[str]) -> None:
        self.messages.extend(texts)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


# A service facade is `api.gd` when present, otherwise the legacy `service.gd`. The preference
# is explicit here so a non-facade `api.gd` is never mistaken for a service entry point.
FACADE_NAMES = ("api.gd", "service.gd")
# A store holds a resolved document another service reads directly, with no scene work of its
# own. Its facade keeps the file name but its edges are store edges.
STORE_SERVICES = {"registry"}


def facade_for(sid: str) -> str:
    for name in FACADE_NAMES:
        if (ROOT / sid / name).is_file():
            return name
    return "service.gd"


def service_ids() -> list[str]:
    found: set[str] = set()
    for name in FACADE_NAMES:
        found.update(
            p.parent.name
            for p in ROOT.glob(f"*/{name}")
            if not p.parent.name.startswith(".") and p.parent.name != "shared"
        )
    return sorted(found)


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
        if path == f"{sid}/{facade_for(sid)}":
            kind = "store" if sid in STORE_SERVICES else "service"
            return Owner(sid, path, False, kind)
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
    game = re.compile(r'(?:preload|load)\("(res://(?:world|player)/[^"]+\.gd)"\)')
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
        for match in game.finditer(text):
            edges.add((src, match.group(1)))
        for match in extends.finditer(text):
            target = match.group(1)
            if target.startswith("res://mods/unfplap/"):
                edges.add((src, target.replace("res://mods/unfplap/", "")))
            elif target.startswith("res://world/") or target.startswith("res://player/"):
                edges.add((src, target))
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


ANATOMY_FACADE = "anatomy/api.gd"
ELIGIBILITY_SCENE = "eligibility/scene.gd"


def is_allowed(src: str, tgt: str) -> tuple[bool, str, Owner | None, Owner | None]:
    kind, so, to = edge_kind(src, tgt)
    # One game boundary: only the accessor preloads a base-game module; every other module reads
    # the game through `GAME`.
    if kind == "game" and src != GAME_SOURCE:
        return False, kind, so, to
    if so is None or to is None:
        return True, kind, so, to
    if so.kind == "orchestrator":
        return True, kind, so, to

    # Anatomy is a presentation leaf: every anatomy file reads the game through `GAME`; only the
    # facade asks eligibility or another mod service, and outside files may preload only api.gd.
    if src.startswith("anatomy/"):
        if tgt == GAME_SOURCE:
            return True, kind, so, to
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None:
            if to.id in ("anatomy", "settings"):
                return True, kind, so, to
            if to.id == "eligibility" and src == ANATOMY_FACADE:
                return True, kind, so, to
        return False, kind, so, to
    # Eligibility is a leaf: identity, shared data, the registry store and its scene boundary.
    # The dynamic rows and every other service edge belong to act_gate.
    if src.startswith("eligibility/"):
        if src == ELIGIBILITY_SCENE and kind == "service" and to is not None:
            return to.id == "world", kind, so, to
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None and to.id == "settings":
            return True, kind, so, to
        return False, kind, so, to
    # The dynamic gate reads the identity answer; it never reads anatomy or estrus.
    if so.id == "act_gate" and to is not None and to.id in ("anatomy", "estrus"):
        return False, kind, so, to
    if to is not None and to.id == "anatomy":
        return tgt == ANATOMY_FACADE, kind, so, to
    if so.kind == "shared":
        # The accessor module is the game boundary, so a shared module may read it like the scene.
        if tgt == "world/game.gd":
            return True, kind, so, to
        if kind in ("shared", "store", "read model", "self", "game"):
            return True, kind, so, to
        # A shared store may read settings; a pure/read-model module may not.
        if so.kind == "store" and to.id == "settings" and kind == "service":
            return True, kind, so, to
        return False, kind, so, to
    if so.kind == "store":
        # A store reads shared data and settings, and the accessor game boundary.
        if tgt == "world/game.gd":
            return True, kind, so, to
        if kind in ("self", "shared", "store", "read model"):
            return True, kind, so, to
        if kind == "service" and to is not None and to.id == "settings":
            return True, kind, so, to
        return False, kind, so, to
    if so.kind == "service":
        if kind in ("self", "service", "shared", "store", "read model", "game"):
            # The settings service is infrastructure and must not depend upward on a domain
            # service. The current registry dependency is recorded as migration debt.
            # The settings layer may read the base-game accessor module: it is the game boundary,
            # not a domain service, so the upward-edge rule does not apply to it.
            if so.id == "settings" and tgt == "world/game.gd":
                return True, kind, so, to
            if so.id == "settings" and to.kind == "service" and to.id != "settings":
                return False, "layer", so, to
            return True, kind, so, to
        return False, kind, so, to
    return True, kind, so, to


def scan_reexports() -> list[dict[str, str]]:
    """Cross-module preload-const reach-throughs: ``ALIAS.CONST`` where CONST is a preload in ALIAS's target.

    Enums, nested classes and plain consts stay reachable; only a preload const is a re-export.
    ``GAME.HOUSE`` is the one allowed game handle and rides the exception ledger.
    """
    text_of: dict[str, str] = {}
    aliases: dict[str, dict[str, str]] = {}
    for path in shipped_sources():
        name = rel(path)
        text = _code_lines(path.read_text(encoding="utf-8"))
        text_of[name] = text
        aliases[name] = {match.group(1): match.group(2) for match in PRELOAD_CONST.finditer(text)}
    found: dict[tuple[str, str, str], dict[str, str]] = {}
    for src, consts in aliases.items():
        for alias, target in consts.items():
            if not target.startswith("res://mods/unfplap/"):
                continue
            target = target.removeprefix("res://mods/unfplap/")
            for const, const_target in aliases.get(target, {}).items():
                if not re.search(r"(?<![\w.])%s\.%s\b" % (re.escape(alias), re.escape(const)),
                                 text_of[src]):
                    continue
                owner = owner_of(src)
                to = const_target.removeprefix("res://mods/unfplap/")
                found[(src, to, "re-export")] = {
                    "from": src,
                    "to": to,
                    "kind": "re-export",
                    "owner": owner.id if owner else "",
                    "reason": "separation of concerns; deferred",
                    "expires": "phase-2",
                }
    return [found[key] for key in sorted(found)]


def scan_violations() -> list[dict[str, str]]:
    found: dict[tuple[str, str, str], dict[str, str]] = {}
    for src, tgt in sorted(scan_edges()):
        ok, kind, so, to = is_allowed(src, tgt)
        if ok:
            continue
        row_kind = "game-import" if kind == "game" else kind
        row = {
            "from": src,
            "to": tgt,
            "kind": row_kind,
            "owner": so.id if so else "",
            "reason": "migration baseline; fix in the boundary-cleanup phase",
            "expires": "phase-2",
        }
        if row_kind == "game-import":
            row["reason"] = "base-game import; drain through the GAME accessor in Task B"
            row.pop("expires", None)
            row["task"] = "B"
        found[(src, tgt, row_kind)] = row
    for row in scan_reexports():
        found[exception_key(row)] = row
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
    for sid in sorted(set(rows) - set(services)):
        failure.add("docs/README.md indexes a Services row for an unknown service: %s" % sid)


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
    return file_public_functions(service, ROOT / service / facade_for(service))


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
# The per-pony handles are read through `runtime.get("...")`; a new site is a locator a typed
# accessor should replace.
DUCK_GET = re.compile(r'\b(?:runtime|main)\.get\("')


def duck_sites(text: str) -> int:
    """Non-comment lines that dispatch by string: `.call("`, `.set("` or a runtime `.get("`."""
    return sum(
        1 for line in text.splitlines()
        if not line.lstrip().startswith("#")
        and (DUCK_CALL.search(line) or DUCK_SET.search(line) or DUCK_GET.search(line))
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


# Every `.gd` in the repository, tests and tools included. Only the generated and fetched trees
# are out of scope; they are not source.
ALL_SOURCE_SKIP_DIRS = {".git", ".godot", "dist", "assets", "sources"}


def all_sources() -> list[Path]:
    return sorted(
        path for path in ROOT.rglob("*.gd")
        if not (set(path.relative_to(ROOT).parts) & ALL_SOURCE_SKIP_DIRS)
    )


PRELOAD_CALL = re.compile(r"(?<![\w.])preload\(")
LOAD_CALL = re.compile(r"(?<![\w.])load\(")
GD_CONST = re.compile(
    r'^const\s+([A-Za-z_]\w*)\s*(?::\s*[\w.\[\]]+\s*)?(?::=|=)\s*'
    r'(?:preload\(\s*)?"([^"]+\.gd)"',
    re.MULTILINE,
)
GD_LITERAL = re.compile(r'^"([^"]+\.gd)"')


def _code_part(line: str) -> str:
    """The line up to an end-of-line comment, quotes respected."""
    quote = ""
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in ("\"", "'"):
            quote = char
        elif char == "#":
            return line[:index]
        index += 1
    return line


def _bracket_delta(line: str) -> int:
    """Open minus close brackets on a line, ignoring strings and comments."""
    depth = 0
    quote = ""
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
        elif char in ("\"", "'"):
            quote = char
        elif char == "#":
            break
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        index += 1
    return depth


def preload_block_problems(text: str) -> list[tuple[int, str]]:
    """Where a script breaks the top preload block: a late or nested ``preload()`` and a script
    ``load()``. The block is the contiguous top-level const region below the doc header.

    Asset ``load(path)``, ``ANATOMY.MEMBER`` and a `.load()` method stay legal: only a script is a
    dependency the preload graph must carry.
    """
    lines = text.splitlines()
    out: list[tuple[int, str]] = []
    cursor = 0
    while cursor < len(lines) and (not lines[cursor].strip() or lines[cursor].startswith("@")):
        cursor += 1
    if cursor < len(lines) and lines[cursor].startswith("extends "):
        cursor += 1
    # The first `##` block before any other declaration is the file's doc header. A preload
    # above it is outside the block even though it is a top-level const.
    probe = cursor
    header_at = None
    while probe < len(lines):
        line = lines[probe]
        if not line.strip() or line.lstrip().startswith("#"):
            probe += 1
            continue
        if line.startswith("const "):
            probe += 1
            continue
        break
    for at in range(cursor, probe):
        if lines[at].startswith("##"):
            header_at = at
            break
    if header_at is not None:
        cursor = header_at
        while cursor < len(lines) and lines[cursor].startswith("##"):
            cursor += 1

    allowed: set[int] = set()
    while cursor < len(lines):
        line = lines[cursor]
        if not line.strip() or line.lstrip().startswith("#"):
            cursor += 1
            continue
        if not line.startswith("const "):
            break
        start = cursor
        depth = _bracket_delta(line)
        while depth > 0 or lines[cursor].rstrip().endswith("\\"):
            if cursor + 1 >= len(lines):
                break
            cursor += 1
            depth += _bracket_delta(lines[cursor])
        if not any(PRELOAD_CALL.search(_code_part(lines[at])) for at in range(start, cursor + 1)):
            break
        allowed.update(range(start, cursor + 1))
        cursor += 1

    for number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for _match in PRELOAD_CALL.finditer(code):
            if number - 1 not in allowed:
                out.append((number, "preload() outside the leading const block: declare every "
                                   "script dependency directly below the doc header"))

    scripts = {match.group(1) for match in GD_CONST.finditer(text)}
    for number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for match in LOAD_CALL.finditer(code):
            argument = code[match.end():].strip()
            literal = GD_LITERAL.match(argument)
            if literal:
                out.append((number, "load() of the script %s: preload it as a top-level const"
                            % literal.group(1)))
                continue
            name = re.match(r"([A-Za-z_]\w*)\s*[,)]", argument)
            if name and name.group(1) in scripts:
                out.append((number, "load() of the script const %s: preload it and call new()"
                            % name.group(1)))
    return out


def check_preloads(failure: Failure) -> None:
    for path in all_sources():
        for number, message in preload_block_problems(path.read_text(encoding="utf-8")):
            failure.add("%s:%d %s" % (rel(path), number, message))


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


def suite_result_failures(name: str, text: str) -> list[str]:
    """A suite never prints the result line: the base owns it."""
    return ["%s:%d prints the result line: the base owns it" % (name, line_of(text, match.start()))
            for match in TEST_SUITE_RESULT.finditer(text)]


def check_tests(failure: Failure) -> None:
    # The base owns the helpers, the lifecycle, the result line and the exit: a suite only
    # extends it, implements run() and asserts.
    for path in test_suites():
        text = path.read_text(encoding="utf-8")
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
        base_text = TEST_SUITE_BASE_PATH.read_text(encoding="utf-8")
        if not TEST_SUITE_CHECK.search(base_text):
            failure.add("%s does not define a check() helper" % rel(TEST_SUITE_BASE_PATH))
        if not TEST_SUITE_RESULT.search(base_text):
            failure.add("%s does not print a _RESULT check summary" % rel(TEST_SUITE_BASE_PATH))

    for path in sorted(TESTS.rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
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

    # A service contract names its facade. The index row owns the contract and test router.
    for sid in SERVICES:
        path = doc_path(sid)
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if f"{sid}/{facade_for(sid)}" not in text:
            failure.add("docs/%s.md does not name %s/%s" % (sid, sid, facade_for(sid)))


def check_owners(failure: Failure) -> None:
    """Every shipped `.gd` has an owner: a service, `shared/` or an orchestrator.

    `owner_of()` answers None for any other path, and every edge to or from an unowned file is
    classified "external" and allowed. A directory without a facade therefore grows code
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
    world = ROOT / "world" / "api.gd"
    if not world.is_file():
        failure.add("missing world/api.gd")
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
        failure.add("world/api.gd:%d may not import %s" % (line_of(text, at), target))


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
# carries any more is stale. The accessor's momentary control lock is a base-game hold, not the frame.
ACT_STATE_WRITES = {
    'set("_stand_eye"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'set("_eye_height"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'call("_set_eye_y"': {"world/game.gd": "the eye-line accessor writes through the rig's setter"},
    'set("controls_locked"': {
        "world/game.gd": "a base-game call with his controls released",
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


def check_static_instances(failure: Failure) -> None:
    """A service is injected, never reached through a static `instance` handle."""
    pattern = re.compile(r"^\s*static var\s+instance\b", re.MULTILINE)
    for path in shipped_sources():
        if pattern.search(path.read_text(encoding="utf-8")):
            failure.add("%s declares a static service instance; pass the facade instead" % rel(path))


def check_service_bases(failure: Failure) -> None:
    """Every service the entry adds is a `shared/service.gd` descendant; the HUD is the exception."""
    main_path = ROOT / "main.gd"
    if not main_path.is_file():
        return
    text = main_path.read_text(encoding="utf-8")
    consts = {
        match.group(1): match.group(2).replace("res://mods/unfplap/", "")
        for match in MAIN_CONST.finditer(text)
    }

    def chain(name: str) -> set[str]:
        seen: set[str] = set()
        while name and name not in seen:
            seen.add(name)
            current = ROOT / name
            if not current.is_file():
                break
            match = MOD_EXTENDS.search(current.read_text(encoding="utf-8"))
            name = match.group(1).replace("res://mods/unfplap/", "") if match else ""
        return seen

    for match in MAIN_ADD.finditer(text):
        const = match.group(1)
        name = consts.get(const, "")
        if not name:
            failure.add("main.gd adds %s but no preloaded const resolves it" % const)
        elif name == HUD_FACADE:
            failure.add("main.gd adds the HUD with _add(); use _add_hud()")
        elif SERVICE_BASE not in chain(name):
            failure.add("%s does not extend %s; the typed service list requires it" % (
                name, SERVICE_BASE))
    for match in MAIN_ADD_HUD.finditer(text):
        const = match.group(1)
        if consts.get(const, "") != HUD_FACADE:
            failure.add("main.gd adds %s with _add_hud(); only the HUD uses it" % const)
    hud_path = ROOT / HUD_FACADE
    if hud_path.is_file():
        hud_text = hud_path.read_text(encoding="utf-8")
        for hook in ("on_world", "on_world_closed", "on_player", "shutdown"):
            if not re.search(r"^func %s\(" % hook, hud_text, re.MULTILINE):
                failure.add(
                    "hud/service.gd is missing %s(); it is the one non-base list service" % hook)


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
    check_facade_notes(failure)
    check_api_docs(failure)
    check_typing(failure)
    check_duck_typing(failure)
    check_sources(failure)
    check_callable_targets(failure)
    check_boundaries(failure)
    check_runtime_shape(failure)
    check_entry_shape(failure)
    check_service_bases(failure)
    check_static_instances(failure)
    check_log_bleed(failure)
    check_act_owners(failure)
    check_owners(failure)
    check_tests(failure)
    check_preloads(failure)
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
    parser.add_argument("--list-suites", action="store_true")
    parser.add_argument("--graph", action="store_true")
    parser.add_argument("--audit-surface", action="store_true")
    parser.add_argument("--write-exceptions", action="store_true")
    parser.add_argument("--write-debt", action="store_true")
    parser.add_argument("--write-duck-typing", action="store_true")
    args = parser.parse_args()
    if args.list_suites:
        # The runner's discovery: `tests/` relative paths, without the extension, sorted.
        for path in test_suites():
            print(rel(path).removeprefix("tests/").removesuffix(".gd"))
        return 0
    if args.audit_surface:
        audit_surface()
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
