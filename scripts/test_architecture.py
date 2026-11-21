#!/usr/bin/env python3
"""Fixture checks for the rules in :mod:`architecture`.

The real tree is checked by ``architecture.py --check``; this file pins the two directions of the
anatomy boundary rules and the doc index rows with synthetic fixtures, so the gate still fails when
a rule silently disappears.
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
    ("anatomy/rig.gd", "world/game.gd"),
    ("anatomy/api.gd", "eligibility/service.gd"),
    ("ponies/service.gd", "anatomy/api.gd"),
    ("eligibility/service.gd", "eligibility/policy.gd"),
    ("eligibility/service.gd", "shared/participation.gd"),
    ("eligibility/service.gd", "registry/service.gd"),
    ("eligibility/service.gd", "settings/service.gd"),
    ("eligibility/scene.gd", "world/service.gd"),
    ("act_gate/service.gd", "eligibility/service.gd"),
    ("settings/service.gd", "registry/service.gd"),
)
FORBIDDEN = (
    ("anatomy/controller.gd", "ponies/service.gd"),
    ("anatomy/controller.gd", "eligibility/service.gd"),
    ("anatomy/controller.gd", "world/game.gd"),
    ("anatomy/rig.gd", "shared/log.gd"),
    ("anatomy/rig.gd", "anatomy/controller.gd"),
    ("anatomy/rig.gd", "shared/act_state.gd"),
    ("ponies/service.gd", "anatomy/controller.gd"),
    ("ponies/service.gd", "anatomy/rig.gd"),
    ("eligibility/service.gd", "estrus/service.gd"),
    ("eligibility/service.gd", "anatomy/api.gd"),
    ("eligibility/service.gd", "world/game.gd"),
    ("eligibility/scene.gd", "estrus/service.gd"),
    ("act_gate/service.gd", "anatomy/api.gd"),
    ("act_gate/service.gd", "estrus/service.gd"),
    ("settings/service.gd", "summary/service.gd"),
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
        print("ok %s" % label)
        return 0
    if any(wanted in message for message in failures):
        print("ok %s" % label)
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


def main() -> int:
    failures = 0
    for src, tgt in ALLOWED:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if ok:
            print("ok allowed %s -> %s" % (src, tgt))
        else:
            print("FAIL allowed edge refused: %s -> %s" % (src, tgt))
            failures += 1
    for src, tgt in FORBIDDEN:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if not ok:
            print("ok forbidden %s -> %s" % (src, tgt))
        else:
            print("FAIL forbidden edge allowed: %s -> %s" % (src, tgt))
            failures += 1
    failures += index_cases()
    if failures:
        print("ARCH_RULES_FAIL %d" % failures)
        return 1
    print("ARCH_RULES_PASS %d" % (len(ALLOWED) + len(FORBIDDEN) + 6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
