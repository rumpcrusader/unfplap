#!/usr/bin/env bash
# Run the manual unfplap lab and tee the session to ./last-run.log.
# Usage: ./lab.sh
# Godot 4.5 and python3 must be on PATH.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT/../.." && pwd)"

# A local contract is an explicit opt-in by `pack_assets.sh --local`; the manual labs use it
# automatically so an unuploaded mesh can be tested without prefixing every lab command.
LOCAL_ASSET_CONTRACT="$ROOT/dist/asset_pack.local.json"
if [ -z "${UNFPLAP_ASSET_CONTRACT:-}" ] && [ -f "$LOCAL_ASSET_CONTRACT" ]; then
	export UNFPLAP_ASSET_CONTRACT="$LOCAL_ASSET_CONTRACT"
	printf 'Using local asset contract: %s\n' "$LOCAL_ASSET_CONTRACT"
fi

python3 "$ROOT/scripts/asset_pack.py" verify --root "$ROOT"

display="${DISPLAY_DRIVER:-}"
if [[ -z "$display" ]]; then
	if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then display=wayland; else display=x11; fi
fi

printf 'Lab log: %s\n' "$ROOT/last-run.log"

# typing_lock is an installed mod outside this repo; its per-frame lines bury the lab log.
godot --xr-mode off \
	--display-driver "$display" \
	--path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title \
	--world-id unfplap-test \
	--lab res://mods/unfplap/tests/test_lab.gd \
	--season=summer \
	2>&1 | sed -u '/^\[typing_lock\]/d' | tee "$ROOT/last-run.log"
