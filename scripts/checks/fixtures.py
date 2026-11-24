"""Fixture checks for the static gate's rules.

The real tree is checked by ``architecture.py --check``; these fixtures pin the two directions of
the anatomy and game boundaries, the re-export scan, the facade note rules and the doc index rows
with synthetic fixtures, so the gate fails when a rule silently disappears.
"""
from __future__ import annotations

import tempfile
from pathlib import Path

from .context import ROOT
from .docs import (
    check_docs,
    index_scope_failures,
    member_note_failures,
    type_note_failures,
    unknown_index_rows,
)
from .failure import Failure
from .graph import is_allowed, scan_reexports
from .preloads import check_game_layer, preload_block_problems
from .scope import (
    attach_failures,
    construction_failures,
    cross_scope_failures,
    declaration_failures,
    entry_name_failures,
    fixed_name_failures,
    group_failures,
    node_base_failures,
    static_state_failures,
    world_alias_failures,
)
from .tests_rules import suite_result_failures
from .wiring import (
    injection_failures,
    peer_field_failures,
    peer_param_failures,
    root_purity_failures,
    wire_call_failures,
    wire_purity_failures,
    wire_sites_failures,
)

ALLOWED = (
    ("anatomy/controller.gd", "shared/act_state.gd"),
    ("anatomy/controller.gd", "settings/service.gd"),
    ("anatomy/rig.gd", "world/api.gd"),
    ("anatomy/rig.gd", "shared/dock_fit.gd"),
    ("anatomy/rig.gd", "shared/act_state.gd"),
    ("anatomy/rig.gd", "anatomy/controller.gd"),
    ("anatomy/api.gd", "eligibility/service.gd"),
    ("ponies/service.gd", "anatomy/api.gd"),
    ("eligibility/service.gd", "eligibility/policy.gd"),
    ("eligibility/service.gd", "shared/participation.gd"),
    ("eligibility/service.gd", "registry/service.gd"),
    ("eligibility/service.gd", "settings/service.gd"),
    ("eligibility/scene.gd", "world/api.gd"),
    ("act_gate/service.gd", "eligibility/service.gd"),
    ("settings/service.gd", "registry/service.gd"),
    ("settings/service.gd", "settings/game.gd"),
    ("settings/ui.gd", "settings/game.gd"),
    ("settings/game.gd", "res://world/ui/menu_style.gd"),
    ("debug/ui.gd", "debug/game.gd"),
    ("hud/service.gd", "hud/game.gd"),
    ("world/views/pony.gd", "world/game.gd"),
    ("act/tick.gd", "settings/service.gd"),
)
FORBIDDEN = (
    ("anatomy/controller.gd", "ponies/service.gd"),
    ("anatomy/controller.gd", "eligibility/service.gd"),
    ("anatomy/controller.gd", "res://world/life/player_form.gd"),
    ("anatomy/rig.gd", "world/game.gd"),
    ("anatomy/controller.gd", "world/game.gd"),
    ("anatomy/rig.gd", "ponies/service.gd"),
    ("anatomy/x.gd", "settings/game.gd"),
    ("shared/x.gd", "world/game.gd"),
    ("shared/act_face.gd", "res://world/characters/hybrid_mare/face_poses.gd"),
    ("debug/x.gd", "world/game.gd"),
    ("ponies/service.gd", "anatomy/controller.gd"),
    ("ponies/service.gd", "anatomy/rig.gd"),
    ("eligibility/service.gd", "estrus/service.gd"),
    ("eligibility/service.gd", "anatomy/api.gd"),
    ("eligibility/service.gd", "world/game.gd"),
    ("eligibility/scene.gd", "estrus/service.gd"),
    ("act_gate/service.gd", "anatomy/api.gd"),
    ("act_gate/service.gd", "estrus/service.gd"),
    ("settings/service.gd", "summary/service.gd"),
    ("settings/service.gd", "world/game.gd"),
    ("world/api.gd", "settings/service.gd"),
    ("settings/service.gd", "act/tick.gd"),
    ("act/start.gd", "res://world/life/player_form.gd"),
)
GAME_ALLOWED = (
    ("world/game.gd", "res://world/life/player_form.gd"),
    ("debug/game.gd", "res://world/ui/menu_style.gd"),
)
REEXPORTS = (
    ("camera/service.gd", "poses/skeleton_pose.gd"),
    ("initiation/service.gd", "negotiation/adapter.gd"),
    ("kiss/service.gd", "poses/missionary_anon.gd"),
)
NOTE_CASES = (
    ("noted type", "## A note.\nclass Noted:\n\tpass\n", 0),
    ("unnoted type", "class Unnoted:\n\tpass\n", 1),
    ("underscore type", "class _Private:\n\tpass\n", 0),
)
MEMBER_CASES = (
    ("noted member", "## A note.\nconst PUBLIC := 1\n", 0),
    ("unnoted member", "const PUBLIC := 1\n", 1),
    ("preload const", "const SCRIPT := preload(\"res://a.gd\")\n", 0),
)
SUITE_RESULT_CASES = (
    ("quiet suite", "func run() -> void:\n\tcheck(1 == 1, \"x\")\n", 0),
    ("printed result line", "func run() -> void:\n\tprint(\"X_RESULT checks=1 failures=0\")\n", 1),
)
SCOPE_DECL_CASES = (
    ("scope declaration valid", "extends Node\n## Service: alpha\n## Scope: world\n"
     "## Contract: docs/alpha.md\n## A purpose.\n", "alpha", None),
    ("scope declaration missing field", "extends Node\n## Service: alpha\n## Scope: world\n",
     "alpha", "missing the ## Contract: field"),
    ("scope declaration wrong service", "extends Node\n## Service: beta\n## Scope: world\n"
     "## Contract: docs/alpha.md\n", "alpha", "expected its directory alpha"),
    ("scope declaration bad scope", "extends Node\n## Service: alpha\n## Scope: other\n"
     "## Contract: docs/alpha.md\n", "alpha", "expected one of process|world|pony"),
    ("scope declaration extra field", "extends Node\n## Service: alpha\n## Scope: world\n"
     "## Contract: docs/alpha.md\n## Import: shared/x.gd\n", "alpha",
     "unknown field ## Import:"),
    ("scope declaration non-facade", "extends Node\n## Service: alpha\n## Scope: world\n"
     "## Contract: docs/alpha.md\n", None, "non-facade carries a declaration field"),
    ("scope declaration prose", "extends RefCounted\n## Pure: reads only what it is given.\n",
     None, None),
)
SCOPE_BASE_CASES = (
    ("scope base world service", "alpha/api.gd", "world", ["shared/service.gd", "Node"], None),
    ("scope base world canvas", "alpha/api.gd", "world", ["CanvasLayer"], None),
    ("scope base pony node", "alpha/api.gd", "pony", ["Node"], None),
    ("scope base process refcounted", "alpha/api.gd", "process", ["RefCounted"], None),
    ("scope base world refcounted", "alpha/api.gd", "world", ["RefCounted"],
     "must extend Node"),
    ("scope base static world", "world/api.gd", "world", ["RefCounted"], None),
)
STATIC_CASES = (
    ("world static var", "alpha/service.gd", "world",
     "static var anatomy: Node = null\n", "declares `static var anatomy`"),
    ("pony static var", "alpha/service.gd", "pony",
     "static var peer: Node = null\n", "declares `static var peer`"),
    ("process static var", "alpha/service.gd", "process",
     "static var instance: Node = null\n", None),
    ("read facade static var", "world/api.gd", "world",
     "static var _game: Node = null\n", None),
    ("instance facade clean", "alpha/service.gd", "world",
     "var peer: Node = null\n", None),
)
WORLD_ALIAS_CASES = (
    ("read facade alias", "alpha/service.gd",
     'const WORLD := preload("res://mods/unfplap/world/api.gd")\n', None),
    ("wrong alias", "alpha/service.gd",
     'const WORLD := preload("res://mods/unfplap/ponies/service.gd")\n',
     "is the one static read facade"),
    ("string const", "alpha/service.gd", 'const WORLD := "world"\n', None),
)
CONSTRUCTION_CASES = (
    ("construction in world root", "main.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n",
     {"alpha/api.gd": "world"}, None),
    ("construction outside its root", "hud/service.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _ready() -> void:\n\talpha = ALPHA.new()\n",
     {"alpha/api.gd": "world"}, "only main.gd constructs a world service"),
    ("cross-scope construction", "world/x.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _ready() -> void:\n\talpha = ALPHA.new()\n",
     {"alpha/api.gd": "pony"}, "only runtime.gd constructs a pony service"),
    ("construction of an other helper", "hud/service.gd",
     'const RECORD := preload("res://mods/unfplap/world/handles.gd")\n'
     "func _ready() -> void:\n\tvar record := RECORD.new()\n",
     {"alpha/api.gd": "world"}, None),
)
ATTACH_CASES = (
    ("attach valid", "main.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n"
     '\t_attach(alpha, "UnfplapAlpha")\n', {"ALPHA": "alpha"}, None),
    ("attach missing", "main.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n",
     {"ALPHA": "alpha"}, "does not attach the alpha service"),
    ("attach outside its root", "main.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n"
     '\t_attach(alpha, "UnfplapAlpha")\n'
     "func _ready() -> void:\n\t_attach(alpha, \"UnfplapAlpha\")\n",
     {"ALPHA": "alpha"}, "attaches a service in _ready()"),
    ("attach missing construction", "main.gd",
     'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
     "func _build_world() -> void:\n\tpass\n",
     {"ALPHA": "alpha"}, "does not construct the alpha facade"),
)
ENTRY_NAME_CASES = (
    ("entry keeps its name", "func _ready() -> void:\n\tservice.name = \"UnfplapX\"\n", None),
    ("entry renames itself", "func _ready() -> void:\n\tself.name = \"UnfplapEntry\"\n",
     "renames the entry"),
)
FIXED_NAME_CASES = (
    ("fixed child names",
     'runtime.name = "UnfplapRuntime"\n_add_node(API.new(), "UnfplapApi")\n', None),
    ("fixed child name missing", 'runtime.name = "UnfplapRuntime"\n',
     "UnfplapApi is never assigned"),
)
GROUP_CASES = (
    ("group in the helper", 'const GROUP := "unfplap_world"\n'
     "func _attach(service: Node) -> void:\n\tservice.add_to_group(GROUP)\n",
     "unfplap_world", "_attach", None),
    ("group outside the helper", 'const GROUP := "unfplap_world"\n'
     "func _ready() -> void:\n\tadd_to_group(GROUP)\n",
     "unfplap_world", "_attach", "adds the unfplap_world scope group in _ready()"),
    ("group never added", "func _attach(service: Node) -> void:\n\tpass\n",
     "unfplap_world", "_attach", "never adds the unfplap_world scope group"),
)
CROSS_CASES = (
    ("cross-scope pony to world facade", "camera/service.gd",
     {"camera/service.gd": "pony", "world/api.gd": "world"},
     'const WORLD := preload("res://mods/unfplap/world/api.gd")\n',
     {"world/api.gd": "world"}, None),
    ("cross-scope public record", "offer/service.gd",
     {"offer/service.gd": "world", "world/handles.gd": "world"},
     'const HANDLES := preload("res://mods/unfplap/world/handles.gd")\n',
     {}, None),
    ("cross-scope private preload", "offer/service.gd",
     {"offer/service.gd": "world", "poses/skeleton_pose.gd": "pony"},
     'const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")\n',
     {}, "preloads the pony file poses/skeleton_pose.gd from the world scope"),
    ("cross-scope process private", "debug/x.gd",
     {"debug/x.gd": "process", "eligibility/policy.gd": "world"},
     'const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")\n',
     {}, "preloads the world file eligibility/policy.gd from the process scope"),
)
INDEX_SCOPE_CASES = (
    ("index scope valid", "world", {"alpha": "world"}, None),
    ("index scope missing", "", {"alpha": "world"}, "has no Scope for alpha"),
    ("index scope mismatch", "pony", {"alpha": "world"}, "the facade declares world"),
    ("index scope unknown", "other", {"alpha": "world"}, "unknown Scope for alpha: other"),
)
OTHER_INDEX_CASES = (
    ("other index valid", ["alpha"], None),
    ("other index row", ["alpha", "gamma"], "unknown service: gamma"),
)
# The wiring fixtures share one synthetic world: `alpha/api.gd` is the only facade, `main.gd` its
# root. Each rule is driven in both directions so a gutted rule fails the self-test.
WIRE_FACADES = {"alpha/api.gd": "alpha"}
WIRE_SCOPES = {"alpha/api.gd": "world"}
WIRE_ROOTS = {"world": "main.gd", "pony": "runtime.gd"}
ALPHA_IMPORT = 'const ALPHA := preload("res://mods/unfplap/alpha/api.gd")\n'
WIRE_CALL_CASES = (
    ("wire in its root", "main.gd", "world",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n\talpha.wire()\n", None),
    ("wire outside its root", "hud/service.gd", "world",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _ready() -> void:\n\talpha.wire()\n", "only main.gd wires a world service"),
    ("wire in the pony root", "runtime.gd", "pony",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _compose() -> void:\n\talpha = ALPHA.new()\n\talpha.wire()\n", None),
    ("wire outside the pony root", "main.gd", "pony",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _build_world() -> void:\n\talpha.wire()\n", "only runtime.gd wires a pony service"),
    ("wire on a local in its root", "main.gd", "world",
     ALPHA_IMPORT + "func _build_world() -> void:\n"
     "\tvar alpha: ALPHA = ALPHA.new()\n\talpha.wire()\n", None),
    ("wire on a local outside its root", "hud/service.gd", "world",
     ALPHA_IMPORT + "func _ready() -> void:\n"
     "\tvar alpha: ALPHA = ALPHA.new()\n\talpha.wire()\n", "only main.gd wires a world service"),
)
WIRE_SITE_CASES = (
    ("wire called once by its root", {"alpha/api.gd": ["main.gd"]}, ["alpha/api.gd"], None),
    ("wire never called", {}, ["alpha/api.gd"], "no composition root calls it"),
    ("wire called twice", {"alpha/api.gd": ["main.gd", "main.gd"]}, ["alpha/api.gd"],
     "must be called once by main.gd"),
    ("wire called by another file", {"alpha/api.gd": ["hud/service.gd"]}, ["alpha/api.gd"],
     "must be called once by main.gd"),
    ("wire called but undefined", {"alpha/api.gd": ["main.gd"]}, [], "is wired but defines no"),
)
PEER_PARAM_CASES = (
    ("peers only in wire", ALPHA_IMPORT + "var _a: ALPHA\nvar _b: ALPHA\n"
     "func wire(a: ALPHA, b: ALPHA) -> void:\n\t_a = a\n\t_b = b\n"
     "func on_world(host: Node) -> void:\n\tpass\n"
     "func shutdown() -> void:\n\t_a = null\n", None),
    ("a second peer member", ALPHA_IMPORT + "var _a: ALPHA\nvar _b: ALPHA\n"
     "func wire(a: ALPHA, b: ALPHA) -> void:\n\t_a = a\n\t_b = b\n"
     "func bind(a: ALPHA) -> void:\n\t_b = a\n", "takes a peer outside wire()"),
    ("a peer in a query", ALPHA_IMPORT + "var _a: ALPHA\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "func rows(a: ALPHA) -> Array:\n\treturn a.rows()\n", "takes a peer outside wire()"),
)
INJECTION_CASES = (
    ("an injection member named bind", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func bind(a: ALPHA) -> void:\n\t_a = a\n", "the one peer-injection member is wire()"),
    ("the same facade with wire", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n", None),
    ("wire and a bind that stores a peer", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "var _b: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "func bind_act(a: ALPHA) -> void:\n\t_b = a\n", "the one peer-injection member is wire()"),
    ("a bind that takes a host", ALPHA_IMPORT + "var _host: Host = null\n"
     "func bind(host: Host) -> void:\n\t_host = host\n", None),
    ("a peer passed to a query", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "func rows(a: ALPHA) -> Array:\n\treturn a.rows()\n", None),
)
ROOT_PURITY_CASES = (
    ("root constructs and wires", "_build_world",
     ALPHA_IMPORT + "var alpha: ALPHA\nvar status: ALPHA\n"
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n\talpha.wire()\n"
     "\t_attach(alpha, \"UnfplapAlpha\")\n\tstatus.status.connect(Callable(self, \"_on\"))\n", None),
    ("root runs behaviour", "_build_world",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _build_world() -> void:\n\talpha.apply_settings()\n", "calls apply_settings()"),
    ("root reads a scene static", "_build_world",
     "func _build_world() -> void:\n\tLOG.debug(\"boot\")\n", "reads LOG in _build_world()"),
    ("pony root binds the record", "_compose",
     ALPHA_IMPORT + "func _compose() -> void:\n\t_act.bind(_host, _context)\n\t_attach(_pose)\n",
     None),
    ("peer extraction in a wire argument", "_build_world",
     ALPHA_IMPORT + "var alpha: ALPHA\nvar beta: ALPHA\n"
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n"
     "\tbeta.wire(alpha.pantyhose())\n", None),
    ("peer extraction outside wire", "_build_world",
     ALPHA_IMPORT + "var alpha: ALPHA\n"
     "func _build_world() -> void:\n\talpha = ALPHA.new()\n"
     "\tvar read := alpha.pantyhose()\n", "calls pantyhose()"),
)
WIRE_PURITY_CASES = (
    ("wire assigns its peers", "func wire(a: ALPHA, b: ALPHA) -> void:\n\t_a = a\n\t_b = b\n"
     "\tassert(_a != null and _b != null)\n", None),
    ("wire builds a child", "func wire(a: ALPHA) -> void:\n\t_a = a\n\tadd_child(a)\n",
     "calls add_child() in wire()"),
    ("wire reads the world", "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "\tvar rig: Node = WORLD.player_rig()\n", "reads WORLD in wire()"),
)
PEER_FIELD_CASES = (
    ("wire sets, shutdown clears", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n\tassert(_a != null)\n"
     "func shutdown() -> void:\n\t_a = null\n", None),
    ("a second writer", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "func _ready() -> void:\n\t_a = null\n", "assigns the peer field _a in _ready()"),
    ("a second clear", ALPHA_IMPORT + "var _a: ALPHA = null\n"
     "func wire(a: ALPHA) -> void:\n\t_a = a\n"
     "func on_world_closed() -> void:\n\t_a = null\n",
     "assigns the peer field _a in on_world_closed()"),
)
PRELOAD_CASES = (
    ("preload block", "extends RefCounted\n## Header.\n\n"
     "const A := preload(\"res://a.gd\")\nconst B := preload(\"res://b.gd\")\n\nvar x := 1\n", 0),
    ("preload array", "extends RefCounted\n## Header.\n\nconst A := [\n"
     "\tpreload(\"res://a.gd\"),\n\tpreload(\"res://b.gd\"),\n]\n", 0),
    ("preload after const", "extends RefCounted\n## Header.\n\nconst A := 1\n"
     "const B := preload(\"res://b.gd\")\n", 1),
    ("preload after var", "extends RefCounted\n## Header.\n\nvar x := 1\n"
     "const A := preload(\"res://a.gd\")\n", 1),
    ("preload in class", "extends RefCounted\n## Header.\n\nclass Inner:\n"
     "\tconst A := preload(\"res://a.gd\")\n", 1),
    ("preload above header", "extends RefCounted\n"
     "const A := preload(\"res://a.gd\")\n## Header.\n\nvar x := 1\n", 1),
    ("load literal", "extends RefCounted\n## Header.\n\nfunc make():\n"
     "\treturn load(\"res://a.gd\")\n", 1),
    ("load const", "extends RefCounted\n## Header.\n\nconst PATH := \"res://a.gd\"\n\n"
     "func make():\n\treturn load(PATH)\n", 1),
    ("dynamic asset load", "extends RefCounted\n## Header.\n\nfunc make(path):\n"
     "\treturn load(path)\n", 0),
)
# The two checks that build their cases in the function body: the doc index's six and the
# game layer accessor's two.
INLINE_CASE_COUNT = 6 + 2


def index_row(sid: str, tests: str | None = None) -> str:
    return "| %s | `%s/service.gd` | `docs/%s.md` | `%s` |" % (
        sid, sid, sid, tests or "tests/%s/" % sid)


def docs_fixture(root: Path, services: list[str], rows: list[str],
                 extra_docs: tuple[str, ...] = ()) -> Path:
    docs = root / "docs"
    docs.mkdir(parents=True)
    for sid in services:
        (docs / f"{sid}.md").write_text("# %s\n\n## Scope\n" % sid, encoding="utf-8")
        (root / "tests" / sid).mkdir(parents=True, exist_ok=True)
    for name in extra_docs:
        (docs / name).write_text("# extra\n", encoding="utf-8")
    table = "\n".join(rows)
    (docs / "README.md").write_text(
        "# docs\n\n## Services\n\n| Service | Facade | Contract | Tests |\n"
        "|---|---|---|---|\n%s\n" % table, encoding="utf-8")
    return docs


def expect(label: str, failures: list[str], wanted: str | None) -> int:
    if wanted is None:
        if failures:
            print("FAIL %s: unexpected %s" % (label, failures))
            return 1
        return 0
    if any(wanted in message for message in failures):
        return 0
    print("FAIL %s: %s not in %s" % (label, wanted, failures))
    return 1


def index_cases() -> int:
    cases = (
        ("index valid", ["alpha", "beta"], [index_row("alpha"), index_row("beta")], (), None),
        ("index missing row", ["alpha", "beta"], [index_row("alpha")], (),
         "no Services row for beta"),
        ("index dead test path", ["alpha"], [index_row("alpha", "tests/gone/")], (),
         "names no test path that exists"),
        ("index doc not indexed", ["alpha"], [index_row("alpha")], ("stray.md",),
         "does not index docs/stray.md"),
        ("index extra row", ["alpha"], [index_row("alpha"), index_row("gamma")], (),
         "unknown service: gamma"),
        ("index duplicate row", ["alpha"], [index_row("alpha"), index_row("alpha")], (),
         "2 Services rows for alpha"),
    )
    failures = 0
    for label, services, rows, extra, wanted in cases:
        with tempfile.TemporaryDirectory() as tmp:
            docs = docs_fixture(Path(tmp), services, rows, extra)
            failure = Failure()
            check_docs(failure, docs=docs, services=services)
            failures += expect(label, failure.messages, wanted)
    return failures


def preload_cases() -> int:
    failures = 0
    for label, text, wanted in PRELOAD_CASES:
        actual = len(preload_block_problems(text))
        if actual != wanted:
            print("FAIL preload %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    return failures


def rule_cases() -> int:
    failures = 0
    for src, tgt in GAME_ALLOWED:
        ok, _kind, _so, _to = is_allowed(src, tgt)
        if not ok:
            print("FAIL game allowed edge refused: %s -> %s" % (src, tgt))
            failures += 1
    found = {(row["from"], row["to"]) for row in scan_reexports()}
    for src, to in REEXPORTS:
        if (src, to) not in found:
            print("FAIL re-export not detected: %s -> %s" % (src, to))
            failures += 1
    for label, text, wanted in NOTE_CASES:
        actual = len(type_note_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL note %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    for label, text, wanted in MEMBER_CASES:
        actual = len(member_note_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL member %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    for label, text, wanted in SUITE_RESULT_CASES:
        actual = len(suite_result_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL suite result %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    return failures


def services_table(rows: list[str]) -> str:
    return (
        "# docs\n\n## Services\n\n| Service | Facade | Contract | Tests | Scope |\n"
        "|---|---|---|---|---|\n%s\n" % "\n".join(rows)
    )


def scoped_row(sid: str, scope: str) -> str:
    cell = "`%s`" % scope if scope else ""
    return "| %s | `%s/service.gd` | `docs/%s.md` | `tests/%s/` | %s |" % (
        sid, sid, sid, sid, cell)


def statics_cases() -> int:
    """Both directions for the class rule: no static state on a world or pony facade, and `WORLD`
    names only the read facade."""
    failures = 0
    for label, path, scope, text, wanted in STATIC_CASES:
        failures += expect(label, static_state_failures(path, scope, text), wanted)
    for label, path, text, wanted in WORLD_ALIAS_CASES:
        failures += expect(label, world_alias_failures(path, text), wanted)
    return failures


def scope_cases() -> int:
    """Both directions for every scope rule: a passing fixture and a failing message."""
    failures = 0
    for label, text, sid, wanted in SCOPE_DECL_CASES:
        failures += expect(label, declaration_failures("fixture.gd", text, sid), wanted)
    for label, path, scope, chain, wanted in SCOPE_BASE_CASES:
        failures += expect(label, node_base_failures(path, scope, chain), wanted)
    for label, path, text, scopes, wanted in CONSTRUCTION_CASES:
        failures += expect(label, construction_failures(path, text, scopes), wanted)
    for label, path, text, expected, wanted in ATTACH_CASES:
        failures += expect(
            label, attach_failures(path, text, expected, "_attach", "_build_world"), wanted)
    for label, text, wanted in ENTRY_NAME_CASES:
        failures += expect(label, entry_name_failures("main.gd", text), wanted)
    failures += statics_cases()
    for label, text, wanted in FIXED_NAME_CASES:
        failures += expect(label, fixed_name_failures("main.gd", text), wanted)
    for label, text, group, helper, wanted in GROUP_CASES:
        failures += expect(label, group_failures("main.gd", text, group, helper), wanted)
    for label, path, scope_map, text, facades, wanted in CROSS_CASES:
        failures += expect(
            label, cross_scope_failures(path, text, scope_map.get, facades), wanted)
    for label, scope, scopes, wanted in INDEX_SCOPE_CASES:
        text = services_table([scoped_row("alpha", scope)])
        failures += expect(label, index_scope_failures(text, scopes), wanted)
    for label, sids, wanted in OTHER_INDEX_CASES:
        text = services_table([index_row(sid) for sid in sids])
        failures += expect(label, unknown_index_rows(text, ["alpha"]), wanted)
    return failures


def wiring_cases() -> int:
    """Both directions for every wiring rule: the real tree's shape passes, a break is reported."""
    failures = 0
    for label, path, scope, text, wanted in WIRE_CALL_CASES:
        scopes = {"alpha/api.gd": scope}
        failures += expect(
            label, wire_call_failures(path, text, scopes, WIRE_ROOTS), wanted)
    for label, sites, definitions, wanted in WIRE_SITE_CASES:
        failures += expect(
            label, wire_sites_failures(sites, definitions, WIRE_SCOPES, WIRE_ROOTS), wanted)
    for label, text, wanted in PEER_PARAM_CASES:
        failures += expect(
            label, peer_param_failures("alpha/api.gd", text, WIRE_FACADES), wanted)
    for label, text, wanted in INJECTION_CASES:
        failures += expect(label, injection_failures("alpha/api.gd", text, WIRE_FACADES), wanted)
    for label, function, text, wanted in ROOT_PURITY_CASES:
        failures += expect(
            label, root_purity_failures("main.gd", text, function, facades=WIRE_FACADES), wanted)
    for label, text, wanted in WIRE_PURITY_CASES:
        failures += expect(label, wire_purity_failures("alpha/api.gd", text), wanted)
    for label, text, wanted in PEER_FIELD_CASES:
        failures += expect(label, peer_field_failures("alpha/api.gd", text), wanted)
    return failures


def wiring_case_count() -> int:
    return sum(len(cases) for cases in (
        WIRE_CALL_CASES,
        WIRE_SITE_CASES,
        PEER_PARAM_CASES,
        INJECTION_CASES,
        ROOT_PURITY_CASES,
        WIRE_PURITY_CASES,
        PEER_FIELD_CASES,
    ))


def scope_case_count() -> int:
    return sum(len(cases) for cases in (
        SCOPE_DECL_CASES,
        SCOPE_BASE_CASES,
        STATIC_CASES,
        WORLD_ALIAS_CASES,
        CONSTRUCTION_CASES,
        ATTACH_CASES,
        ENTRY_NAME_CASES,
        FIXED_NAME_CASES,
        GROUP_CASES,
        CROSS_CASES,
        INDEX_SCOPE_CASES,
        OTHER_INDEX_CASES,
    ))


def game_layer_cases() -> int:
    """A game.gd lives only in a whitelisted service directory."""
    failures = 0
    failure = Failure()
    check_game_layer(failure, [ROOT / "hud" / "game.gd", ROOT / "world" / "game.gd"])
    failures += expect("game layer accessors", failure.messages, None)
    failure = Failure()
    check_game_layer(failure, [ROOT / "camera" / "game.gd"])
    failures += expect("game layer stray accessor", failure.messages,
                       "game.gd belongs to a game-layer service")
    return failures


def main() -> int:
    failures = 0
    for src, tgt in ALLOWED:
        ok, _kind, _so, _to = is_allowed(src, tgt)
        if not ok:
            print("FAIL allowed edge refused: %s -> %s" % (src, tgt))
            failures += 1
    for src, tgt in FORBIDDEN:
        ok, _kind, _so, _to = is_allowed(src, tgt)
        if ok:
            print("FAIL forbidden edge allowed: %s -> %s" % (src, tgt))
            failures += 1
    failures += index_cases()
    failures += rule_cases()
    failures += preload_cases()
    failures += game_layer_cases()
    failures += scope_cases()
    failures += wiring_cases()
    if failures:
        print("ARCH_RULES_FAIL %d" % failures)
        return 1
    print("ARCH_RULES_PASS %d" % (
        len(ALLOWED) + len(FORBIDDEN) + len(GAME_ALLOWED) + len(REEXPORTS)
        + len(NOTE_CASES) + len(MEMBER_CASES) + len(SUITE_RESULT_CASES) + len(PRELOAD_CASES)
        + INLINE_CASE_COUNT + scope_case_count() + wiring_case_count()))
    return 0
