#!/usr/bin/env bash
# Fast parse check for the mod's scripts. Loads the changed and untracked .gd in one headless engine
# boot through tools/parse_all.gd and reports the files that fail. A run that ends without the
# tool's PARSED line is a failure, so a timeout or a crash never reads as a pass.
# Usage: scripts/check.sh            # changed and untracked files only (git)
#        scripts/check.sh --all      # every mod script
# Godot 4.5 must be on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"

if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi
if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
	printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
	exit 1
fi

mapfile -t files < <(
	if [[ "${1:-}" == "--all" ]]; then
		cd "$MOD_DIR" && find . -name '*.gd' -not -path './tests/_*' -printf '%P\n'
	else
		cd "$MOD_DIR" && {
			git diff --name-only --diff-filter=ACMR HEAD -- '*.gd'
			git ls-files --others --exclude-standard -- '*.gd'
		} | sed 's#^mods/unfplap/##'
	fi | sort -u
)

if [[ "${#files[@]}" -eq 0 ]]; then
	printf 'CHECK_PASS (nothing to check)\n'
	exit 0
fi

paths=()
for file in "${files[@]}"; do
	paths+=("res://mods/unfplap/$file")
done

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/unfplap-check.XXXXXX")"
trap 'rm -rf "$out_dir"' EXIT
log="$out_dir/check.log"

if timeout 180 godot --headless --xr-mode off --path "$PROJECT_ROOT" \
		--script res://mods/unfplap/tools/parse_all.gd -- "${paths[@]}" >"$log" 2>&1; then
	status=0
else
	status=$?
fi

mapfile -t failures < <(grep '^FAIL ' "$log" || true)
mapfile -t errors < <(
	grep -E 'Parse Error|Compile Error|SCRIPT ERROR|Failed loading|Failed to load' "$log" || true
)

if [[ "$status" -ne 0 ]] || [[ "${#failures[@]}" -gt 0 ]] || ! grep -q '^PARSED ' "$log"; then
	if [[ "${#failures[@]}" -gt 0 ]]; then
		printf '%s\n' "${failures[@]}"
	fi
	if [[ "${#errors[@]}" -gt 0 ]]; then
		printf '%s\n' "${errors[@]:0:20}"
	fi
	printf 'CHECK_FAIL\n'
	exit 1
fi
printf 'CHECK_PASS %d files\n' "${#files[@]}"
