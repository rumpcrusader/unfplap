#!/usr/bin/env bash
# Fast parse check for the mod's scripts. Compiles every changed .gd in parallel and reports the
# files that fail to parse. Seconds instead of a full game boot.
# Usage: scripts/check.sh            # changed files only (git)
#        scripts/check.sh --all      # every mod script
# Godot 4.5 must be on PATH.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
JOBS="${CHECK_JOBS:-8}"

if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi

mapfile -t files < <(
	if [[ "${1:-}" == "--all" ]]; then
		cd "$MOD_DIR" && find . -name '*.gd' -not -path './tests/_*' -printf '%P\n'
	else
		cd "$MOD_DIR" && git diff --name-only --diff-filter=ACMR HEAD -- '*.gd' \
			| sed 's#^mods/unfplap/##'
	fi | sort -u
)

if [[ "${#files[@]}" -eq 0 ]]; then
	printf 'CHECK_PASS (nothing to check)\n'
	exit 0
fi

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/unfplap-check.XXXXXX")"
trap 'rm -rf "$out_dir"' EXIT

export PROJECT_ROOT out_dir
check_one() {
	local file="$1"
	local log="$out_dir/$(printf '%s' "$file" | tr '/' '_').log"
	timeout 60 godot --headless --xr-mode off --path "$PROJECT_ROOT" \
		--check-only --script "res://mods/unfplap/$file" >"$log" 2>&1
	# Only parse failures matter here; a compile error about a game autoload (Mods, Settings…)
	# just means the file cannot be resolved standalone.
	# A missing game autoload (Mods, Settings) is a standalone-resolution artefact, not a bug.
	if grep -E 'Parse Error' "$log" | grep -qv 'Unicode parsing'; then
		printf 'FAIL %s\n' "$file"
		grep -E 'Parse Error|SCRIPT ERROR' "$log" | head -n 3
	elif grep -q 'Compile Error' "$log" && ! grep -q 'Identifier not found: \(Mods\|Settings\|AI_CONFIG\)' "$log"; then
		printf 'FAIL %s\n' "$file"
		grep -E 'Compile Error' "$log" | head -n 3
	fi
}
export -f check_one

printf '%s\n' "${files[@]}" \
	| xargs -P "$JOBS" -I{} bash -c 'check_one "$@"' _ {} >"$out_dir/report.txt"

if [[ -s "$out_dir/report.txt" ]]; then
	cat "$out_dir/report.txt"
	printf 'CHECK_FAIL\n'
	exit 1
fi
printf 'CHECK_PASS %d files\n' "${#files[@]}"
