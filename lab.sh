#!/usr/bin/env bash
# Run the manual unfplap lab and tee the session to ./last-run.log.
# Usage: ./lab.sh
# Godot 4.5 must be on PATH.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT/../.." && pwd)"

if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH. Install Godot 4.5 or add it to PATH.\n' >&2
	exit 1
fi
if ! python3 "$ROOT/scripts/asset_pack.py" verify --root "$ROOT"; then
	printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
	exit 1
fi

printf 'Lab log: %s\n' "$ROOT/last-run.log"

godot --xr-mode off \
	--display-driver wayland \
	--path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title \
	--world-id unfplap-test \
	--lab res://mods/unfplap/tests/test_lab.gd \
	2>&1 | tee "$ROOT/last-run.log"
