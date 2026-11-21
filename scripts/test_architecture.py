#!/usr/bin/env python3
"""Fixture checks for the anatomy boundary rules in :mod:`architecture`.

The real tree is checked by ``architecture.py --check``; this file pins the two directions of the
anatomy rule with synthetic edges, so a broken predicate fails even when the tree happens to be
clean at that moment.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import architecture  # noqa: E402


ALLOWED = (
    ("anatomy/controller.gd", "shared/act_state.gd"),
    ("anatomy/controller.gd", "settings/service.gd"),
    ("anatomy/rig.gd", "world/game.gd"),
    ("ponies/service.gd", "anatomy/api.gd"),
)
FORBIDDEN = (
    ("anatomy/controller.gd", "ponies/service.gd"),
    ("anatomy/controller.gd", "eligibility/service.gd"),
    ("anatomy/controller.gd", "world/game.gd"),
    ("anatomy/rig.gd", "shared/log.gd"),
    ("anatomy/rig.gd", "anatomy/controller.gd"),
    ("ponies/service.gd", "anatomy/controller.gd"),
    ("ponies/service.gd", "anatomy/rig.gd"),
)


def main() -> int:
    failures = 0
    for src, tgt in ALLOWED:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if not ok:
            print("FAIL allowed edge rejected: %s -> %s" % (src, tgt))
            failures += 1
    for src, tgt in FORBIDDEN:
        ok, _kind, _so, _to = architecture.is_allowed(src, tgt)
        if ok:
            print("FAIL forbidden edge allowed: %s -> %s" % (src, tgt))
            failures += 1
    if failures:
        print("ARCH_RULES_FAIL %d" % failures)
        return 1
    print("ARCH_RULES_PASS %d allowed, %d forbidden" % (len(ALLOWED), len(FORBIDDEN)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
