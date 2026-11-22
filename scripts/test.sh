#!/usr/bin/env bash
# Run headless test suites, in parallel, each with its own throwaway data dir.
# Prints only the failing suites, then one status line naming them if any failed.
# Usage: scripts/test.sh                  # every suite (same as --all)
#        scripts/test.sh <suite|dir>...   # poses/test_pose_asset | kiss | poses
#        scripts/test.sh --all            # every suite: the full headless gate
#        scripts/test.sh --list           # the discovered suites, then exit
#        scripts/test.sh --self-test      # the harness self-test (a hung fixture must fail), then exit
#        scripts/test.sh --smoke          # boot the game from source and fail on script errors
#        scripts/test.sh --quick ...      # skip the static prechecks: iteration only, never the gate
#        scripts/test.sh --verbose ...    # also print one PASS line per suite
# Godot 4.5 must be on PATH.
# TEST_JOBS overrides the parallelism: the default is one job per core, capped at 12.
# KEEP=1 keeps the temporary per-suite data and logs and prints the directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
JOBS_DEFAULT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
JOBS_DEFAULT="${JOBS_DEFAULT:-12}"
if [[ "$JOBS_DEFAULT" -gt 12 ]]; then
	JOBS_DEFAULT=12
fi
JOBS="${TEST_JOBS:-$JOBS_DEFAULT}"
VERBOSE="${TEST_VERBOSE:-0}"
ALL=0
LIST=0
SELF_TEST=0
SMOKE=0
QUICK=0
REQUESTED=()

for arg in "$@"; do
	case "$arg" in
		--all) ALL=1 ;;
		--list) LIST=1 ;;
		--self-test) SELF_TEST=1 ;;
		--smoke) SMOKE=1 ;;
		--quick) QUICK=1 ;;
		-v | --verbose) VERBOSE=1 ;;
		--*)
			printf 'Unknown option %s\n' "$arg" >&2
			printf 'Usage: scripts/test.sh [<suite|dir>...] | --all | --list | --self-test | --smoke [--quick] [--verbose]\n' >&2
			printf 'No argument runs --all.\n' >&2
			exit 2
			;;
		*) REQUESTED+=("$arg") ;;
	esac
done

if [[ "${#REQUESTED[@]}" -eq 0 && "$LIST" -eq 0 && "$SELF_TEST" -eq 0 && "$SMOKE" -eq 0 ]]; then
	ALL=1
fi
if [[ "$ALL" -eq 1 && "${#REQUESTED[@]}" -gt 0 ]]; then
	printf 'Usage: scripts/test.sh --all takes no suite names\n' >&2
	exit 2
fi
if [[ "$SMOKE" -eq 1 && ( "$ALL" -eq 1 || "$LIST" -eq 1 || "$SELF_TEST" -eq 1 || "${#REQUESTED[@]}" -gt 0 ) ]]; then
	printf 'Usage: scripts/test.sh --smoke takes no suite names or other modes\n' >&2
	exit 2
fi

# Suites live in tests/ and tests/<system>/; the gate owns the discovery, so the list, the runner
# and the static checks cannot drift. The manual labs need a live world and are not in the gate.
mapfile -t TESTS < <(python3 "$MOD_DIR/scripts/architecture.py" --list-suites)

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

# The source smoke: boot the real game from the mod source and fail on a script or parse error.
# The game keeps running, so the timeout exit (124) is the expected success status.
run_smoke() {
	local seconds="${SMOKE_SECONDS:-20}"
	if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
		printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
		return 1
	fi
	local log_file status=0
	log_file="$(mktemp "${TMPDIR:-/tmp}/unfplap-smoke.XXXXXX")"
	if timeout "$seconds" godot --headless --xr-mode off --path "$PROJECT_ROOT" \
			-- --mod-src unfplap --skip-title >"$log_file" 2>&1; then
		status=0
	else
		status=$?
	fi
	if grep -qE 'SCRIPT ERROR|Parse Error|Invalid|ERROR' "$log_file"; then
		printf 'SMOKE_FAIL\n'
		grep -E 'SCRIPT ERROR|Parse Error|Invalid|ERROR' "$log_file" | head -n 20
		rm -f "$log_file"
		return 1
	fi
	if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
		printf 'SMOKE_FAIL exit=%s\n' "$status"
		tail -n 20 "$log_file"
		rm -f "$log_file"
		return 1
	fi
	rm -f "$log_file"
	printf 'SMOKE_PASS\n'
}

# The same prechecks the full gate runs, so a local subset cannot disagree with it.
if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH (need the Godot 4.5 executable).\n' >&2
	exit 1
fi
if [[ "$SMOKE" -eq 1 ]]; then
	run_smoke || exit 1
	exit 0
fi
if [[ "$SELF_TEST" -eq 1 ]]; then
	run_self_test || exit 1
	exit 0
fi
# --quick keeps the Godot probe and discovery for the inner loop and skips the static gates; --all
# always runs them.
PRECHECK=1
if [[ "$QUICK" -eq 1 && "$ALL" -eq 0 ]]; then
	PRECHECK=0
fi
if [[ "$PRECHECK" -eq 1 ]]; then
	if ! python3 "$MOD_DIR/scripts/asset_pack.py" verify --root "$MOD_DIR"; then
		printf 'Run scripts/fetch_assets.sh once in this checkout.\n' >&2
		exit 1
	fi
	if ! "$MOD_DIR/scripts/check.sh" --static; then
		printf 'ARCHITECTURE_FAIL\n' >&2
		exit 1
	fi
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
KEEP="${KEEP:-0}"
if [[ "$KEEP" -ne 1 ]]; then
	trap 'rm -rf "$work_dir"' EXIT
fi

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
	# The status is kept beside the log: a suite that never writes a result still has a verdict.
	local started status=0
	started="$(date +%s%3N)"
	XDG_DATA_HOME="$work_dir/data-$safe" UNFPLAP_SUITE_RESULT="$work_dir/$safe.result" \
		UNFPLAP_SUITE_DATA="$work_dir/data-$safe" \
		timeout -k 5 90 godot --headless --xr-mode off --path "$PROJECT_ROOT" \
		--script "res://mods/unfplap/tests/$test_name.gd" \
		>"$work_dir/$safe.out" 2>&1 || status=$?
	printf '%s\n' "$status" >"$work_dir/$safe.status"
	printf '%s\n' "$(( $(date +%s%3N) - started ))" >"$work_dir/$safe.ms"
}
export -f run_one
export MOD_DIR PROJECT_ROOT work_dir

printf '%s\n' "${SELECTED[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

failed=0
failed_names=()
total_checks=0
for test_name in "${SELECTED[@]}"; do
	safe="${test_name//\//_}"
	out="$work_dir/$safe.out"
	status="$(cat "$work_dir/$safe.status" 2>/dev/null || true)"
	if [[ "$status" == "MISSING" ]]; then
		printf 'FAIL %s (suite file is missing)\n' "$test_name"
		failed_names+=("$test_name")
		failed=1
		continue
	fi
	result="$(cat "$work_dir/$safe.result" 2>/dev/null || true)"
	if [[ -z "$result" ]]; then
		result="$(grep -E '_RESULT checks=' "$out" 2>/dev/null | tail -n 1 || true)"
	fi
	checks_n=""
	failures_n=""
	if [[ "$result" =~ checks=([0-9]+)\ failures=([0-9]+) ]]; then
		checks_n="${BASH_REMATCH[1]}"
		failures_n="${BASH_REMATCH[2]}"
		total_checks=$((total_checks + checks_n))
	fi
	ms=""
	if [[ "$result" =~ seconds=([0-9.]+) ]]; then
		ms="$(awk -v s="${BASH_REMATCH[1]}" 'BEGIN { printf "%d", s * 1000 }')"
	elif [[ -s "$work_dir/$safe.ms" ]]; then
		ms="$(cat "$work_dir/$safe.ms")"
	fi
	if [[ -z "$failures_n" ]]; then
		# No file and no printed line: the exit status is the only verdict there is.
		why="no result, exit ${status:-?}"
		if [[ "$status" == "124" ]]; then
			why="no result, exit 124, timed out"
		fi
		printf 'FAIL %s (%s)\n' "$test_name" "$why"
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
	if [[ "$failures_n" -eq 0 ]]; then
		if [[ "$VERBOSE" -eq 1 ]]; then
			printf 'PASS %s %s ms (checks=%s)\n' "$test_name" "${ms:-?}" "$checks_n"
		fi
		continue
	fi
	printf 'FAIL %s (checks=%s failures=%s, exit %s)\n' "$test_name" "$checks_n" \
		"$failures_n" "${status:-?}"
	grep -E '^FAIL|SCRIPT ERROR|Parse Error|Invalid|ERROR' \
		"$out" 2>/dev/null | head -n 20 | sed 's/^/  /' || true
	failed_names+=("$test_name")
	failed=1
done

if [[ "$KEEP" -eq 1 ]]; then
	printf 'kept: %s\n' "$work_dir"
fi

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
