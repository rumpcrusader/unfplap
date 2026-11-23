"""The gate's command line: run every rule, or one group, and the maintenance modes."""
from __future__ import annotations

import argparse
import sys

from .act import check_act_owners
from .context import ROOT, SERVICES, TYPING_DEBT, load_json
from .docs import (
    audit_surface,
    check_api_docs,
    check_docs,
    check_facade_notes,
    check_index_scopes,
)
from .entry import (
    check_boundaries,
    check_callable_targets,
    check_entry_shape,
    check_log_bleed,
    check_owners,
    check_runtime_shape,
    check_service_bases,
    check_static_instances,
    report_large_files,
)
from .failure import Failure, rel
from .graph import check_exceptions, graph, scan_violations, write_exceptions
from .preloads import check_autoloads, check_game_layer, check_preloads
from .scope import (
    check_scope_attachment,
    check_scope_bases,
    check_scope_construction,
    check_scope_cross,
    check_scope_declarations,
    check_scope_groups,
)
from .sources import check_sources
from .tests_rules import check_tests, test_suites
from .typing import check_duck_typing, check_typing, write_debt, write_duck_typing


def _graph_group(failure: Failure) -> int:
    return check_exceptions(failure, scan_violations())


def _docs_group(failure: Failure) -> None:
    check_docs(failure)
    check_facade_notes(failure)
    check_api_docs(failure)
    check_index_scopes(failure)


def _scope_group(failure: Failure) -> None:
    check_scope_declarations(failure)
    check_scope_bases(failure)
    check_scope_construction(failure)
    check_scope_attachment(failure)
    check_scope_groups(failure)
    check_scope_cross(failure)


def _typing_group(failure: Failure) -> None:
    check_typing(failure)
    check_duck_typing(failure)


def _entry_group(failure: Failure) -> None:
    check_entry_shape(failure)
    check_service_bases(failure)
    check_static_instances(failure)


def _preloads_group(failure: Failure) -> None:
    check_preloads(failure)
    check_game_layer(failure)
    check_autoloads(failure)


STEPS = (
    ("graph", _graph_group),
    ("docs", _docs_group),
    ("typing", _typing_group),
    ("sources", check_sources),
    ("callables", check_callable_targets),
    ("boundaries", check_boundaries),
    ("runtime", check_runtime_shape),
    ("entry", _entry_group),
    ("sink", check_log_bleed),
    ("act", check_act_owners),
    ("owners", check_owners),
    ("scope", _scope_group),
    ("tests", check_tests),
    ("preloads", _preloads_group),
)
GROUPS = tuple(name for name, _step in STEPS)


def check(groups: tuple[str, ...] | None = None) -> int:
    failure = Failure()
    selected = set(groups) if groups else None
    exceptions = 0
    for name, step in STEPS:
        if selected is not None and name not in selected:
            continue
        result = step(failure)
        if name == "graph":
            exceptions = result or 0
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--list-suites", action="store_true")
    parser.add_argument("--graph", action="store_true")
    parser.add_argument("--audit-surface", action="store_true")
    parser.add_argument("--write-exceptions", action="store_true")
    parser.add_argument("--write-debt", action="store_true")
    parser.add_argument("--write-duck-typing", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--group", default="")
    args = parser.parse_args(argv)
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
    if args.self_test:
        from .fixtures import main as fixtures_main

        return fixtures_main()
    if args.group:
        requested = tuple(name.strip() for name in args.group.split(",") if name.strip())
        unknown = [name for name in requested if name not in GROUPS]
        if unknown:
            print("ARCH_FAIL unknown group: %s" % ", ".join(unknown), file=sys.stderr)
            return 2
        return check(requested)
    return check()


if __name__ == "__main__":
    sys.exit(main())
