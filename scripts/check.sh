#!/usr/bin/env bash
# The static gate: parse the mod's scripts in one headless engine boot and run the architecture
# rules. A run that ends without the tool's PARSED line is a failure, so a timeout or a crash never
# reads as a pass.
# Usage: scripts/check.sh            # every .gd + the static gate (same as --all)
#        scripts/check.sh --all      # every .gd + the static gate
#        scripts/check.sh --static   # the static gate only: no Godot, no fetched assets
#        scripts/check.sh --parse    # parse only: changed and untracked .gd
#        scripts/check.sh --group G  # one static rule group (debugging only)
# Godot 4.5 must be on PATH for the parse modes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"

usage() {
	printf 'Usage: scripts/check.sh [--all | --static | --parse | --group GROUP]\n' >&2
	printf 'No argument runs --all.\n' >&2
}

MODE=all
GROUP=""
while [[ "$#" -gt 0 ]]; do
	case "$1" in
		--all) MODE=all; shift ;;
		--static) MODE=static; shift ;;
		--parse) MODE=parse; shift ;;
		--group)
			[[ "$#" -ge 2 ]] || { printf '--group needs a rule group\n' >&2; usage; exit 2; }
			MODE=group; GROUP="$2"; shift 2
			;;
		-h | --help) usage; exit 0 ;;
		*) printf 'Unknown option %s\n' "$1" >&2; usage; exit 2 ;;
	esac
done

run_static() {
	if [[ "$MODE" == "group" ]]; then
		python3 "$MOD_DIR/scripts/architecture.py" --group "$GROUP"
		return
	fi
	python3 "$MOD_DIR/scripts/architecture.py" --check
	python3 "$MOD_DIR/scripts/architecture.py" --self-test
}

run_parse() {
	if ! command -v godot >/dev/null 2>&1; then
		printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
		exit 1
	fi
	if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
		printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
		exit 1
	fi

	mapfile -t files < <(
		if [[ "$MODE" == "all" ]]; then
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
		return
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
}

case "$MODE" in
	static | group) run_static ;;
	parse) run_parse ;;
	all)
		run_parse
		run_static
		;;
esac
