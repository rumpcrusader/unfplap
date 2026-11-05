#!/usr/bin/env bash
# Run every headless test suite. Prints each RESULT line and a final pass/fail line.
# Usage: scripts/test_all.sh
#        GODOT=/path/to/godot scripts/test_all.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
GODOT="${GODOT:-godot}"

TESTS=(
	test_catalog
	test_settings
	test_source_hygiene
	test_rotation
	test_thrust
	test_auto_thrust
	test_preferences
	test_memory
	test_utterance
	test_utterance_scheduler
	test_utterance_lines
	test_relationship_cue
	test_runtime_thrust
	test_runtime_teardown
	test_sex_bond
	test_afterglow
	test_voice
	test_actions
	test_hud
	test_initiation
	test_rump_cone
	test_act_audio
)

failed=0
for test_name in "${TESTS[@]}"; do
	test_path="$MOD_DIR/tests/$test_name.gd"
	if [[ ! -f "$test_path" ]]; then
		printf 'MISSING %s\n' "$test_name"
		failed=1
		continue
	fi
	output="$(
		timeout 90 "$GODOT" --headless --xr-mode off --path "$PROJECT_ROOT" \
			--script "res://mods/unfplap/tests/$test_name.gd" 2>&1
	)"
	result="$(printf '%s\n' "$output" | grep -E '_RESULT checks=' | tail -n 1)"
	if [[ -z "$result" ]]; then
		printf 'FAIL %s (no result)\n' "$test_name"
		printf '%s\n' "$output" | tail -n 20
		failed=1
		continue
	fi
	if [[ "$result" == *"failures=0"* ]]; then
		printf 'PASS %s\n' "$result"
	else
		printf 'FAIL %s\n' "$result"
		printf '%s\n' "$output" | grep -E '^FAIL|SCRIPT ERROR|Parse Error|Invalid|ERROR' || true
		failed=1
	fi
done

if [[ "$failed" -ne 0 ]]; then
	printf 'TEST_ALL_FAIL\n'
	exit 1
fi
printf 'TEST_ALL_PASS\n'
