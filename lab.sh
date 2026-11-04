#!/usr/bin/env bash
# Run the manual unfplap lab and tee the session to ./last-run.log.
# Usage: ./lab.sh
#        GODOT=~/path/to/godot ./lab.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT/../.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/godot}"

if [ ! -x "$GODOT" ]; then
	printf 'Godot not found at %s. Set GODOT to the executable path.\n' "$GODOT" >&2
	exit 1
fi

printf 'Lab log: %s\n' "$ROOT/last-run.log"

"$GODOT" --xr-mode off \
	--display-driver wayland \
	--path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title \
	--world-id unfplap-test \
	--lab res://mods/unfplap/tests/test_lab.gd \
	2>&1 | tee "$ROOT/last-run.log"
