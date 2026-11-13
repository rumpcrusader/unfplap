#!/usr/bin/env bash
# Run headless test suites, in parallel, each with its own throwaway data dir.
# Prints each RESULT line and a final pass/fail line.
# Usage: scripts/test.sh <suite|dir>...   # poses/test_pose_asset | kiss | poses
#        scripts/test.sh --all            # every suite (what test_all.sh runs)
#        scripts/test.sh --list           # the discovered suites, then exit
# Godot 4.5 must be on PATH.
# TEST_JOBS sets the parallelism (default 6).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
JOBS="${TEST_JOBS:-6}"

if [[ "${1:-}" == "" ]]; then
	printf 'Usage: scripts/test.sh <suite|dir>... | --all | --list\n' >&2
	exit 2
fi
if [[ "$1" == "--all" && "$#" -gt 1 ]]; then
	printf 'Usage: scripts/test.sh --all takes no suite names\n' >&2
	exit 2
fi
if [[ "$1" == --* && "$1" != "--all" && "$1" != "--list" ]]; then
	printf 'Unknown option %s\n' "$1" >&2
	printf 'Usage: scripts/test.sh <suite|dir>... | --all | --list\n' >&2
	exit 2
fi

# Suites live in tests/ and tests/<system>/. The manual labs need a live world and are not part
# of the headless gate.
mapfile -t TESTS < <(
	cd "$MOD_DIR" && find tests -maxdepth 2 -name 'test_*.gd' \
		! -name 'test_lab*.gd' ! -name 'test_stress_lab.gd' \
		-printf '%P\n' | sed 's/\.gd$//' | sort
)

# A listing is not a run: no precheck output on stdout, so the list stays pipeable.
if [[ "$1" == "--list" ]]; then
	printf '%s\n' "${TESTS[@]}"
	exit 0
fi

# The same prechecks the full gate runs, so a local subset cannot disagree with it.
if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi
if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
	printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
	exit 1
fi
if ! python3 "$MOD_DIR/scripts/architecture.py" --check; then
	printf 'ARCHITECTURE_FAIL\n' >&2
	exit 1
fi

if [[ "$1" == "--all" ]]; then
	SELECTED=("${TESTS[@]}")
else
	SELECTED=()
	for arg in "$@"; do
		found=0
		for test_name in "${TESTS[@]}"; do
			if [[ "$test_name" == "$arg" || "$test_name" == "$arg"/* ]]; then
				SELECTED+=("$test_name")
				found=1
			fi
		done
		if [[ "$found" -eq 0 ]]; then
			printf 'No suite matches "%s".\n' "$arg" >&2
			near="$(printf '%s\n' "${TESTS[@]}" | grep -F "$arg" || true)"
			if [[ -n "$near" ]]; then
				printf 'Did you mean:\n%s\n' "$near" >&2
			fi
			printf 'Run scripts/test.sh --list for every suite.\n' >&2
			exit 2
		fi
	done
	mapfile -t SELECTED < <(printf '%s\n' "${SELECTED[@]}" | sort -u)
fi

if [[ "${#SELECTED[@]}" -eq 0 ]]; then
	printf 'No suites selected.\n' >&2
	exit 2
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/unfplap-tests.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

# One process per suite, each with a clean user:// so the player's settings and saves can never
# change a default-value assertion and parallel runs cannot race on the same files.
run_one() {
	local test_name="$1"
	local safe="${test_name//\//_}"
	if [[ ! -f "$MOD_DIR/tests/$test_name.gd" ]]; then
		printf 'MISSING\n' >"$work_dir/$safe.result"
		return
	fi
	XDG_DATA_HOME="$work_dir/data-$safe" mkdir -p "$work_dir/data-$safe"
	XDG_DATA_HOME="$work_dir/data-$safe" timeout 90 godot --headless --xr-mode off \
		--path "$PROJECT_ROOT" --script "res://mods/unfplap/tests/$test_name.gd" \
		>"$work_dir/$safe.out" 2>&1
	local result
	result="$(grep -E '_RESULT checks=' "$work_dir/$safe.out" | tail -n 1)"
	printf '%s\n' "$result" >"$work_dir/$safe.result"
}
export -f run_one
export MOD_DIR PROJECT_ROOT work_dir

printf '%s\n' "${SELECTED[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

failed=0
for test_name in "${SELECTED[@]}"; do
	safe="${test_name//\//_}"
	result="$(cat "$work_dir/$safe.result" 2>/dev/null || true)"
	if [[ "$result" == "MISSING" ]]; then
		printf 'MISSING %s\n' "$test_name"
		failed=1
		continue
	fi
	if [[ -z "$result" ]]; then
		printf 'FAIL %s (no result)\n' "$test_name"
		tail -n 20 "$work_dir/$safe.out" 2>/dev/null || true
		failed=1
		continue
	fi
	if [[ "$result" == *"failures=0"* ]]; then
		printf 'PASS %s\n' "$result"
	else
		printf 'FAIL %s\n' "$result"
		grep -E '^FAIL|SCRIPT ERROR|Parse Error|Invalid|ERROR' \
			"$work_dir/$safe.out" 2>/dev/null || true
		failed=1
	fi
done

if [[ "$failed" -ne 0 ]]; then
	if [[ "$1" == "--all" ]]; then
		printf 'TEST_ALL_FAIL\n'
	else
		printf 'TEST_FAIL %d suites\n' "${#SELECTED[@]}"
	fi
	exit 1
fi
if [[ "$1" == "--all" ]]; then
	printf 'TEST_ALL_PASS\n'
else
	printf 'TEST_PASS %d suites\n' "${#SELECTED[@]}"
fi
