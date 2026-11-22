#!/usr/bin/env python3
"""The static architecture gate's front door.

The rules live in ``checks/``; this module keeps the command line and the fixtures' import point.

Usage:
    scripts/architecture.py --check
    scripts/architecture.py --self-test
    scripts/architecture.py --graph
    scripts/architecture.py --audit-surface
    scripts/architecture.py --write-exceptions
    scripts/architecture.py --write-debt
    scripts/architecture.py --write-duck-typing
"""
from __future__ import annotations

import sys

from checks.cli import GROUPS, check, main
from checks.context import ROOT, SERVICES, Owner, owner_of, facade_for, service_ids
from checks.docs import (
    audit_surface,
    check_api_docs,
    check_docs,
    check_facade_notes,
    member_note_failures,
    type_note_failures,
)
from checks.failure import Failure, rel
from checks.graph import (
    is_allowed,
    scan_edges,
    scan_reexports,
    scan_violations,
    write_exceptions,
)
from checks.preloads import preload_block_problems, check_game_layer
from checks.tests_rules import suite_result_failures, test_suites
from checks.typing import typing_debt

__all__ = [
    "GROUPS",
    "ROOT",
    "SERVICES",
    "Owner",
    "Failure",
    "audit_surface",
    "check",
    "check_api_docs",
    "check_docs",
    "check_facade_notes",
    "check_game_layer",
    "facade_for",
    "is_allowed",
    "main",
    "member_note_failures",
    "owner_of",
    "preload_block_problems",
    "rel",
    "scan_edges",
    "scan_reexports",
    "scan_violations",
    "service_ids",
    "suite_result_failures",
    "test_suites",
    "type_note_failures",
    "typing_debt",
    "write_exceptions",
]


if __name__ == "__main__":
    sys.exit(main())
