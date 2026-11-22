#!/usr/bin/env python3
"""Fixture checks for the rules in :mod:`architecture`.

The real tree is checked by ``architecture.py --check``; this file pins the two directions of the
anatomy boundary rules, the game boundary, the re-export scan, the facade note rules and the doc
index rows with synthetic fixtures, so the gate still fails when a rule silently disappears.
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import architecture  # noqa: E402


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
            failure = architecture.Failure()
            architecture.check_docs(failure, docs=docs, services=services)
            failures += expect(label, failure.messages, wanted)
    return failures


def preload_cases() -> int:
    failures = 0
    for label, text, wanted in PRELOAD_CASES:
        actual = len(architecture.preload_block_problems(text))
        if actual != wanted:
            print("FAIL preload %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    return failures


def rule_cases() -> int:
    failures = 0
    for src, tgt in GAME_ALLOWED:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if not ok:
            print("FAIL game allowed edge refused: %s -> %s" % (src, tgt))
            failures += 1
    found = {(row["from"], row["to"]) for row in architecture.scan_reexports()}
    for src, to in REEXPORTS:
        if (src, to) not in found:
            print("FAIL re-export not detected: %s -> %s" % (src, to))
            failures += 1
    for label, text, wanted in NOTE_CASES:
        actual = len(architecture.type_note_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL note %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    for label, text, wanted in MEMBER_CASES:
        actual = len(architecture.member_note_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL member %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    for label, text, wanted in SUITE_RESULT_CASES:
        actual = len(architecture.suite_result_failures("fixture.gd", text))
        if actual != wanted:
            print("FAIL suite result %s: wanted %d findings, got %d" % (label, wanted, actual))
            failures += 1
    return failures


def game_layer_cases() -> int:
    """A game.gd lives only in a whitelisted service directory."""
    failures = 0
    failure = architecture.Failure()
    architecture.check_game_layer(
        failure, [architecture.ROOT / "hud" / "game.gd",
                  architecture.ROOT / "world" / "game.gd"])
    failures += expect("game layer accessors", failure.messages, None)
    failure = architecture.Failure()
    architecture.check_game_layer(failure, [architecture.ROOT / "camera" / "game.gd"])
    failures += expect("game layer stray accessor", failure.messages,
                       "game.gd belongs to a game-layer service")
    return failures


def main() -> int:
    failures = 0
    for src, tgt in ALLOWED:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if not ok:
            print("FAIL allowed edge refused: %s -> %s" % (src, tgt))
            failures += 1
    for src, tgt in FORBIDDEN:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if ok:
            print("FAIL forbidden edge allowed: %s -> %s" % (src, tgt))
            failures += 1
    failures += index_cases()
    failures += rule_cases()
    failures += preload_cases()
    failures += game_layer_cases()
    if failures:
        print("ARCH_RULES_FAIL %d" % failures)
        return 1
    print("ARCH_RULES_PASS %d" % (
        len(ALLOWED) + len(FORBIDDEN) + len(GAME_ALLOWED) + len(REEXPORTS)
        + len(NOTE_CASES) + len(MEMBER_CASES) + len(SUITE_RESULT_CASES) + len(PRELOAD_CASES)
        + 8))
    return 0


if __name__ == "__main__":
    sys.exit(main())
