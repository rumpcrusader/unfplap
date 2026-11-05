#!/usr/bin/env bash
# Start the game from the mod source and fail on script/parse errors.
# The game keeps running, so the timeout exit (124) is the expected success status.
# Usage: scripts/smoke.sh
# Godot 4.5 must be on PATH.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
SMOKE_SECONDS="${SMOKE_SECONDS:-20}"

if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi

log_file="$(mktemp "${TMPDIR:-/tmp}/unfplap-smoke.XXXXXX")"
trap 'rm -f "$log_file"' EXIT

timeout "$SMOKE_SECONDS" godot --headless --xr-mode off --path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title >"$log_file" 2>&1
status=$?

if grep -qE 'SCRIPT ERROR|Parse Error|Invalid|ERROR' "$log_file"; then
	printf 'SMOKE_FAIL\n'
	grep -E 'SCRIPT ERROR|Parse Error|Invalid|ERROR' "$log_file" | head -n 20
	exit 1
fi
if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
	printf 'SMOKE_FAIL exit=%s\n' "$status"
	tail -n 20 "$log_file"
	exit 1
fi
printf 'SMOKE_PASS\n'
