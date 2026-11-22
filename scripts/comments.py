#!/usr/bin/env python3
"""Gate comment shape: block size, private names, doc pointers, copied doc prose.

The rules live in ``checks/comments.py``; this module keeps the command line.

Usage:
    scripts/comments.py --check
    scripts/comments.py --audit
    scripts/comments.py --self-test
"""
from __future__ import annotations

import argparse
import sys

from checks.comments import audit, load_docs, scan_paths, scanned_paths, self_test


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Comment shape gate.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="list violating blocks")
    mode.add_argument("--audit", action="store_true", help="print every finding as JSON")
    mode.add_argument("--self-test", action="store_true", help="run in-memory fixtures")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()

    docs = load_docs()
    paths = scanned_paths()
    findings = scan_paths(paths, docs)

    if args.audit:
        audit(len(paths), findings)
        return 0
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}: {finding.text}")
    if findings:
        print(f"COMMENTS_FAIL {len(findings)}")
        return 1
    print(f"COMMENTS_PASS files={len(paths)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
