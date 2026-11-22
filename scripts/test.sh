#!/usr/bin/env bash
# Run headless test suites, in parallel, each with its own throwaway data dir.
# Prints only the failing suites, then one status line naming them if any failed.
# Usage: scripts/test.sh <suite|dir>...   # poses/test_pose_asset | kiss | poses
#        scripts/test.sh --all            # every suite (what test_all.sh runs)
#        scripts/test.sh --list           # the discovered suites, then exit
#        scripts/test.sh --self-test      # the harness self-test (a hung fixture must fail), then exit
#        scripts/test.sh --verbose ...    # also print one PASS line per suite
# Godot 4.5 must be on PATH.
# TEST_JOBS sets the parallelism (default 12). TEST_VERBOSE=1 is --verbose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
JOBS="${TEST_JOBS:-12}"
VERBOSE="${TEST_VERBOSE:-0}"
ALL=0
LIST=0
SELF_TEST=0
REQUESTED=()

for arg in "$@"; do
	case "$arg" in
		--all) ALL=1 ;;
		--list) LIST=1 ;;
		--self-test) SELF_TEST=1 ;;
		-v | --verbose) VERBOSE=1 ;;
		--*)
			printf 'Unknown option %s\n' "$arg" >&2
			printf 'Usage: scripts/test.sh <suite|dir>... | --all | --list | --self-test [--verbose]\n' >&2
			exit 2
			;;
		*) REQUESTED+=("$arg") ;;
	esac
done

if [[ "${#REQUESTED[@]}" -eq 0 && "$ALL" -eq 0 && "$LIST" -eq 0 && "$SELF_TEST" -eq 0 ]]; then
	printf 'Usage: scripts/test.sh <suite|dir>... | --all | --list | --self-test [--verbose]\n' >&2
	exit 2
fi
if [[ "$ALL" -eq 1 && "${#REQUESTED[@]}" -gt 0 ]]; then
	printf 'Usage: scripts/test.sh --all takes no suite names\n' >&2
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
if [[ "$LIST" -eq 1 ]]; then
	printf '%s\n' "${TESTS[@]}"
	exit 0
fi

# The harness self-test: a fixture that never returns from run() must fail from the base watchdog.
run_self_test() {
	local dir log status=0
	local want='^suite=support/fixtures/watchdog_hang label=[A-Z0-9_]+ checks=[0-9]+ failures=1 seconds=[0-9.]+ end=watchdog$'
	dir="$(mktemp -d "${TMPDIR:-/tmp}/unfplap-selftest.XXXXXX")"
	log="$dir/watchdog.out"
	UNFPLAP_SUITE_RESULT="$dir/watchdog.result" timeout 10 godot --headless --xr-mode off \
		--path "$PROJECT_ROOT" \
		--script res://mods/unfplap/tests/support/fixtures/watchdog_hang.gd >"$log" 2>&1 || true
	# The fixture exits 1 by design: the watchdog's line, its failure count and its result file are
	# the assertion, not the process status.
	if ! grep -qE '^FAIL .*run\(\) did not finish' "$log" \
		|| ! grep -qE '_RESULT checks=[0-9]+ failures=1$' "$log" \
		|| ! grep -qE "$want" "$dir/watchdog.result" 2>/dev/null; then
		printf 'TEST_SELFTEST_FAIL (the watchdog did not end the hung fixture)\n'
		tail -n 20 "$log" | sed 's/^/  /' || true
		status=1
	fi
	rm -rf "$dir"
	return "$status"
}

# The same prechecks the full gate runs, so a local subset cannot disagree with it.
if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi
if [[ "$SELF_TEST" -eq 1 ]]; then
	run_self_test || exit 1
	exit 0
fi
if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
	printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
	exit 1
fi
if ! python3 "$MOD_DIR/scripts/architecture.py" --check; then
	printf 'ARCHITECTURE_FAIL\n' >&2
	exit 1
fi
if ! python3 "$MOD_DIR/scripts/test_architecture.py"; then
	printf 'ARCHITECTURE_RULES_FAIL\n' >&2
	exit 1
fi

if [[ "$ALL" -eq 1 ]]; then
	run_self_test || exit 1
	SELECTED=("${TESTS[@]}")
else
	SELECTED=()
	for arg in "${REQUESTED[@]}"; do
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
# change a default-value assertion and parallel runs cannot race on the same files. The base writes
# the result file this loop reads; the stdout line is the fallback when there is no file.
run_one() {
	local test_name="$1"
	local safe="${test_name//\//_}"
	if [[ ! -f "$MOD_DIR/tests/$test_name.gd" ]]; then
		printf 'MISSING\n' >"$work_dir/$safe.result"
		return
	fi
	XDG_DATA_HOME="$work_dir/data-$safe" mkdir -p "$work_dir/data-$safe"
	XDG_DATA_HOME="$work_dir/data-$safe" UNFPLAP_SUITE_RESULT="$work_dir/$safe.result" \
		timeout 90 godot --headless --xr-mode off --path "$PROJECT_ROOT" \
		--script "res://mods/unfplap/tests/$test_name.gd" \
		>"$work_dir/$safe.out" 2>&1 || true
}
export -f run_one
export MOD_DIR PROJECT_ROOT work_dir

printf '%s\n' "${SELECTED[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

failed=0
failed_names=()
total_checks=0
total_failures=0
for test_name in "${SELECTED[@]}"; do
	safe="${test_name//\//_}"
	out="$work_dir/$safe.out"
	result="$(cat "$work_dir/$safe.result" 2>/dev/null || true)"
	if [[ "$result" != "MISSING" && -z "$result" ]]; then
		result="$(grep -E '_RESULT checks=' "$out" 2>/dev/null | tail -n 1 || true)"
	fi
	label=""
	if [[ "$result" =~ label=([A-Z0-9_]+) ]]; then
		label="${BASH_REMATCH[1]}"
	fi
	checks_n=""
	failures_n=""
	if [[ "$result" =~ checks=([0-9]+)\ failures=([0-9]+) ]]; then
		checks_n="${BASH_REMATCH[1]}"
		failures_n="${BASH_REMATCH[2]}"
		total_checks=$((total_checks + checks_n))
		total_failures=$((total_failures + failures_n))
	fi
	if [[ "$result" == "MISSING" ]]; then
		printf 'FAIL %s (suite file is missing)\n' "$test_name"
		failed_names+=("$test_name")
		failed=1
		continue
	fi
	if [[ -z "$result" ]]; then
		printf 'FAIL %s (no result)\n' "$test_name"
		tail -n 20 "$out" 2>/dev/null | sed 's/^/  /' || true
		failed_names+=("$test_name")
		failed=1
		continue
	fi
	# A suite can print a script error and still report failures=0; the log is part of the gate.
	if grep -qE 'SCRIPT ERROR|Parse Error' "$out" 2>/dev/null; then
		printf 'FAIL %s (script error in log)\n' "$test_name"
		grep -E 'SCRIPT ERROR|Parse Error' "$out" | head -n 10 | sed 's/^/  /'
		failed_names+=("$test_name")
		failed=1
		continue
	fi
	# A file result is key=value; the human line keeps the shape a direct run prints.
	describe="$result"
	if [[ -n "$label" ]]; then
		describe="${label}_RESULT checks=${checks_n} failures=${failures_n}"
	fi
	if [[ "$result" == *"failures=0"* ]]; then
		if [[ "$VERBOSE" -eq 1 ]]; then
			printf 'PASS %s\n' "$describe"
		fi
		continue
	fi
	printf 'FAIL %s\n' "$describe"
	grep -E '^FAIL|SCRIPT ERROR|Parse Error|Invalid|ERROR' \
		"$out" 2>/dev/null | head -n 20 | sed 's/^/  /' || true
	failed_names+=("$test_name")
	failed=1
done

# The status line is last and names the failing suites, so `| tail -n 20` cannot hide the verdict
# even when the details above it are cut.
if [[ "$failed" -ne 0 ]]; then
	printf 'rerun: scripts/test.sh %s\n' "${failed_names[*]}"
	if [[ "$ALL" -eq 1 ]]; then
		printf 'TEST_ALL_FAIL %d of %d suites: %s\n' \
			"${#failed_names[@]}" "${#SELECTED[@]}" "${failed_names[*]}"
	else
		printf 'TEST_FAIL %d of %d suites: %s\n' \
			"${#failed_names[@]}" "${#SELECTED[@]}" "${failed_names[*]}"
	fi
	exit 1
fi
if [[ "$ALL" -eq 1 ]]; then
	printf 'TEST_ALL_PASS %d suites, %d checks\n' "${#SELECTED[@]}" "$total_checks"
else
	printf 'TEST_PASS %d suites, %d checks\n' "${#SELECTED[@]}" "$total_checks"
fi
