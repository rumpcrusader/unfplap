#!/usr/bin/env bash
# integration: stress lab. Every adult mare is placed in front of Golden Oak Library.
# Usage: ./lab-stress.sh
# Godot 4.5 must be on PATH. Writes last-run-stress.log beside this script.

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

printf 'Stress lab log: %s\n' "$ROOT/last-run-stress.log"

godot --xr-mode off \
	--display-driver "$display" \
	--path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title \
	--world-id unfplap-stress \
	--lab res://mods/unfplap/tests/test_stress_lab.gd \
	2>&1 | tee "$ROOT/last-run-stress.log"
