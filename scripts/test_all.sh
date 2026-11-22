#!/usr/bin/env bash
# Run every headless test suite, in parallel, each with its own throwaway data dir.
# Prints only the failing suites, then one status line naming them if any failed.
# Usage: scripts/test_all.sh
# Godot 4.5 must be on PATH.
# TEST_JOBS overrides the parallelism; the default is one job per core, capped at 12.
# The runner is scripts/test.sh; use it directly for a subset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/test.sh" --all
