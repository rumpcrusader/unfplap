#!/usr/bin/env bash
# Run every headless test suite, in parallel, each with its own throwaway data dir.
# Prints each RESULT line and a final pass/fail line.
# Usage: scripts/test_all.sh
# Godot 4.5 must be on PATH.
# TEST_JOBS sets the parallelism (default 6).
# The runner is scripts/test.sh; use it directly for a subset.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/test.sh" --all
