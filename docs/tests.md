# Test suites

The headless gate: what a suite is, how it is discovered, how it is isolated and how to run a
subset without disagreeing with `scripts/test.sh`.

Suites are not services. They have no facade, no contract entry in the service index and no service
lifecycle; this doc owns their shape and their runner.

## Scope

- `tests/` holds every headless suite. The full gate runs every one of them.
- A suite is a scene-free script on the shared `SceneTree` base that prints one machine-readable
  result line.
- Anything that needs a live world, a person at the keyboard, a headset or the HUD belongs to a
  manual lab, not here.
- The static source and test-file invariants are the static gate, not a suite.

## Suite layout

| Path | Holds |
|---|---|
| `tests/<service>/test_<topic>.gd` | the suites for one service's facade or internals |
| `tests/test_<topic>.gd` | a root suite that crosses services, or a shared/pure module's suite |
| `tests/<topic>/test_<topic>.gd` | a cross-service concern with its own name; `handover/` is the act body swap, `entry/` the entry's service list |
| `tests/support/suite.gd` | the shared base: the assertion helpers, the run/finish lifecycle and the result line |
| `tests/support/fixtures/<name>.gd` | a suite the runner starts by path, not by discovery: the self-test's hung fixture |
| `tests/support/fakes/<family>.gd` | shared fakes for byte-identical bodies; a suite keeps a local class when its fake differs |

`tests/act/test_session.gd` covers the runtime's own `act/` modules: the one state writer, the
phase timer verdicts, the clock and reset rules and the typed host/context seam.
`tests/act/test_tick.gd` covers the ordered render frame: the view refresh, the pose space follow,
the pose write and the render trace before the look and the shot.

`tests/act_gate/` covers the dynamic act gate: its pure truth table and Promiscuity floor, the
act-key readiness row, the typed verdict, the relationship row's two love-level sources, the
consent keys, the cycle note and the attach warm. `tests/eligibility/` covers the permanent
identity half and its profile layer.

One suite per file, and the directory mirrors the facade it exercises. A small pure module folds
into the suite that owns its facade instead of adding a file of its own. The directory is the map:
`tests/<id>/` exercises `<id>/`. A pure module's suite uses plain values: for example
`tests/poses/test_pose_state.gd` pins the pose transition table and the edge math with dictionaries
and no scene, node or autoload. `tests/poses/test_pose_blend.gd` builds a bare `Skeleton3D` and fake
drivers, so the pose evaluator's single/blend paths, capture buffers and non-finite guard are
pinned without a game file.

### Merged paths

These files are gone; their coverage lives in the suite on the right. The mapping is a routing
table, not a second owner: each rule has exactly one suite.

| Removed suite | Now covered by |
|---|---|
| `tests/test_catalog.gd` | `tests/poses/test_pose_registry.gd` |
| `tests/poses/test_pose_rig.gd` | `tests/poses/test_pose_asset.gd` |
| `tests/poses/test_body_sway.gd`, `tests/poses/test_prone_sway.gd` | `tests/poses/test_pose_sway.gd` |
| `tests/poses/test_pose_scale.gd` | `tests/poses/test_pose_asset_layout.gd` |
| `tests/anatomy/test_facts.gd` | `tests/act_facts/test_act_facts.gd` |
| `tests/anatomy/test_act_bridge.gd` | `tests/anatomy/test_api.gd` |
| `tests/anatomy/test_appearance.gd` | `tests/anatomy/test_coat.gd` |
| `tests/anatomy/test_tail_hide.gd` | `tests/anatomy/test_placement.gd` |
| `tests/privacy_rules/test_privacy_rules.gd` | `tests/privacy/test_privacy.gd` |
| `tests/stool/test_stool_api.gd` | `tests/stool/test_gate.gd` |
| `tests/memory/test_facts.gd` | `tests/memory/test_text.gd` |
| `tests/dialogue/test_history_scan.gd` | `tests/dialogue/test_act_dialogue.gd` |
| `tests/dialogue/test_prompt_notes.gd` | `tests/dialogue/test_act_dialogue.gd` |
| `tests/initiation/test_prompts.gd` | `tests/initiation/test_initiation_api.gd` |
| `tests/face/test_mood_face.gd` | `tests/face/test_act_face.gd` |
| `tests/readiness/test_auto_panel.gd` | `tests/readiness/test_readiness_auto.gd` |
| `tests/summary/test_history.gd` | `tests/summary/test_act_flow.gd` |
| `tests/integrations/test_hold.gd` | `tests/integrations/test_service.gd` |
| `tests/perf/test_log.gd`, `tests/perf/test_perf_idle.gd`, `tests/perf/test_perf_tree.gd`, `tests/test_perf_panel.gd` | `tests/perf/test_perf.gd` |
| `tests/test_source_hygiene.gd` | the static gate |

## Writing a suite

A suite extends the shared base and implements `run()`; the base drives the rest of the lifecycle.
It has no scene. The project's autoloads do boot, so a suite reads none of them directly: it
fakes the node it needs under `/root` and restores any autoload node it renames.

```gdscript
extends "res://mods/unfplap/tests/support/suite.gd"
## What this suite pins. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_x.gd

const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")

func run() -> void:
	check(CLEARANCE.evaluate(true, true, true).ok(), "Base clearance passes when every row holds")
```

The base owns the assertion helpers, the run/finish lifecycle and the result line. `_initialize()`
defers `_run_and_finish()`, which calls `before()`, then `run()`, then `finish()`; `finish()` runs
`teardown()` once and prints the result.

- The base defers the run so the tree is up before the checks touch a node.
- `check(ok, text)` prints only failures; the text names the rule, not the value.
- Because the base calls `finish()` after `run()` returns, a suite that returns early or never
  calls `finish()` still reports. `finish()` is idempotent, so the explicit call a suite keeps at
  the end of `run()`, and the private `X_PASS` line many suites print, are cosmetic for a direct
  run and are not part of the contract.
- `finish()` runs `teardown()` once, fails the suite when no assertion ran, prints the final
  `…_RESULT checks=%d failures=%d` line and quits. The printed line is the direct-run form; the
  runner reads the file the base writes when `UNFPLAP_SUITE_RESULT` names a path.
- The result file holds one `key=value` line: the suite path, its label, both counts, the elapsed
  seconds and what ended the run. A path the base cannot write leaves the printed line as the
  runner's fallback.
- `before()` returns, then a watchdog starts: a `run()` that never returns fails the suite and still
  tears down once. `scripts/test.sh --self-test` proves it with a fixture that hangs on purpose.
- The runner also scans the suite log for `SCRIPT ERROR` and `Parse Error`; a suite that logs one
  fails even when the result line reports `failures=0`, so a script error cannot hide behind a
  passing check count.
- The exit code is `0` on success and `1` on failure; the runner reads the result line and the log,
  but the exit code keeps a direct `godot … --script` run honest.
- The header comment carries the direct command, so a suite can be run without the runner while
  debugging.

### Fixtures

A suite is its own root: every `Node` it builds is freed by the suite, and a runtime — or the body
that holds it — is attached under the suite's `root` before it is freed, so `_ready` and `_exit_tree`
run and the composition is released on its one real path. A detached `free()` is a defect, not a
shortcut.

### Assertion helpers

| Helper | Pins |
|---|---|
| `check(ok, text)` | a boolean the suite computed |
| `check_eq(actual, expected, text)` | exact equality |
| `check_ne(actual, unexpected, text)` | inequality |
| `check_approx(actual, expected, text, eps := 0.0001)` | floats within a tolerance |
| `check_contains(haystack, needle, text)` | a key, a member or a substring |
| `check_empty(value, text)` | an empty string, array or dictionary |
| `check_size(value, expected, text)` | a string length or a container size |
| `check_same(actual, expected, text)` | object identity |
| `check_null(value, text)` | null |
| `check_not_null(value, text)` | non-null |
| `fail(text)` | an unconditional failure |
| `near(a, b, eps := 0.0001)` | a tolerance test the suite combines itself |

The helpers are additions: an existing `check(a == b, …)` call keeps working, and a new or touched
check uses the helper for its shape. `near` defaults to `0.0001`, and a suite that needs another
tolerance passes it explicitly: one default does not fit every call site, so a suite using `0.001`
or `0.00001` states it. A failure line carries the suite label and, when the stack still holds the
calling frame, the suite's source line, and a value helper prints the expected and the got value,
names the type when `check_empty` or `check_size` cannot measure its argument, and marks the offset
where two long strings first differ.

### Result label

The base derives the result label from the suite's path: a top-level `tests/test_<topic>.gd` prints
`<TOPIC>`, and `tests/<dir>/test_<topic>.gd` prints `<DIR>_<TOPIC>`. The topic is used alone when it
equals the directory or begins with `<dir>_`; a topic that is only a suffix keeps the directory
prefix, so the two act-audio suites stay distinct: `privacy/privacy` → `PRIVACY`,
`readiness/readiness_auto` → `READINESS_AUTO`, `act_audio/audio` → `ACT_AUDIO_AUDIO`,
`act_audio/act_audio` → `ACT_AUDIO`. The label is cosmetic: the runner reports it and never
parses it.

## Isolation

- Each suite gets its own `XDG_DATA_HOME` under the runner's temporary directory, so the player's
  `user://` settings, saves and logs can never change a behaviour assertion or the shipped-document
  schema check.
- The runner passes that directory as `UNFPLAP_SUITE_DATA` too, and the base refuses to run when the
  resolved `user://` is outside it. `XDG_DATA_HOME` separates the data on Linux only, so the gate is
  Linux-only until another platform gets a per-run data directory; a direct run sets no variable and
  is not checked.
- A fixed path under `user://` is safe only because the suite owns its data directory: keep the
  path unique to the suite, remove what you write, and never depend on another suite having run
  first.
- A suite must pass on a fresh checkout, with no settings file and no save.
- Parallel runs are the default; two suites must never touch the same file.

## Running

| Command | Runs |
|---|---|
| `scripts/test.sh` | every suite: the full headless gate (same as `--all`) |
| `scripts/test.sh <suite>...` | the named suites, or every suite under a directory (`scripts/test.sh poses`) |
| `scripts/test.sh --list` | the discovered suites, then exits |
| `scripts/test.sh --self-test` | the harness self-test: a hung fixture must fail from the watchdog, then exits |
| `scripts/test.sh --quick [<suite>...]` | the same selection without the static prechecks: iteration only |
| `scripts/test.sh --all` | every suite: the full headless gate, once per task |
| `scripts/test.sh --smoke` | boot the game from the mod source and fail on a script or parse error |

`scripts/test.sh` runs the same prechecks as the gate (Godot on `PATH`, the fetched asset set,
`scripts/check.sh --static`), uses the same discovery and the same per-suite invocation, so a
subset cannot disagree with the full gate. `--quick` drops the static prechecks for iteration and
is never the gate: no argument and `--all` always run them.

It prints only the suites that failed, each followed by its own failure lines, and ends in one
status line: `TEST_PASS <n> suites, <n> checks` for a subset and `TEST_ALL_PASS <n> suites, <n>
checks` for a full run. A failing run prints a `rerun:
scripts/test.sh ...` line and ends in `TEST_FAIL <k> of <n> suites: <names>` (or `TEST_ALL_FAIL
...`), so the last line names every failing suite and a trailing `tail` cannot hide the verdict.
`--verbose` (`TEST_VERBOSE=1`) adds one `PASS <suite> <ms> ms` line per suite for a local run.
`KEEP=1` keeps the temporary per-suite data and logs and prints their directory. A suite that
leaves no result fails with its exit status, and one the runner's timeout killed says it timed out.
A full run (`--all` or no argument) runs the self-test first, so the gate proves the base still
ends a hung suite.

Every suite must also leave no `SCRIPT ERROR` or `Parse Error` in its log, and no leak at exit: a log
that carries `ObjectDB instances leaked` or `resources still in use` fails the suite, and the runner
prints those lines under its name. There is no allowlist; a suite that builds a `Node` owns its
release.

Discovery has one implementation, `scripts/test.sh --list`: `tests/**/test_*.gd`,
two levels deep, excluding the manual labs (`test_lab*.gd`, `test_stress_lab.gd`). `TEST_JOBS` sets
the parallelism; the default is one job per core, capped at 12 because one heavy suite peaks at
roughly 370 MB.

`scripts/check.sh` parses every script and runs the static gate; `--parse` is the quick
changed-only loop. Run `scripts/check.sh` before you report the task done.

## Manual labs

`./lab.sh`, `./lab-stress.sh` and `./lab-vr.sh` need a live world and are not in the headless gate.
Run the phase's lab and record the result in the phase notes; if the lab cannot run in the current
environment, say so instead of claiming it passed. The lab roster, keys and pause rules are in
`docs/debug.md`, and the commands are in `WORKFLOW.md`.

## Teardown pins

`tests/poses/test_pose_teardown.gd` pins the pose-scope/act-scope split: the two leave steps keep
the pose node, the live config and the view, the final release clears them and repeats safely, and
no pose-scope step reaches an act exit. `tests/poses/test_modifier_profile.gd` is the synthetic
profile suite: a pose change keeps the shared modifier, installs the target-only owners and removes
the source-only ones, while `leave_pose_body()` keeps the act-exit full removal; its synthetic
profile lives only in the session's test seam, and the live `apply_live_settings()` edit swaps the
feature flags into the same reconcile. The hook suites are
`tests/act_camera/test_camera.gd`, `tests/act_camera/test_kiss.gd`, `tests/hands/test_caress.gd`,
`tests/hands/test_actions.gd`, `tests/anatomy/test_api.gd` and
`tests/act_audio/test_audio.gd`. The pose ledger's order and its three callers, the
`_fanout()` owner order in `act/tick.gd` (pose service first, then camera, hands, kiss and
anatomy), the pose-before-facts order in its `_tick()` and the ban on act-exit names under
`poses/` are static rules in the static gate. The anatomy allow-list and its
fixtures are in the static gate, run by `scripts/test.sh`. The contract is `docs/poses.md`; this doc
only names the gate.

The body-swap handover is `tests/handover/test_body_swap.gd`: suspend → adopt → resume with the
act state, depth, climaxes and event id intact, the old runtime still alive, the new anatomy and
pose bound, adoption binding without resuming until the named form reports its target, the target
completing as the form, a missing form restoring the offer on the new body, the watchdog with a
body resuming as a failed form, a change the provider started on its own, a repeated change, the
debug form-state label clearing at each state change while the HUD string stays empty, a failed
named change restoring the offer, her own change keeping the player's offer, a late body adopted
once after the grace, a change during restore finishing through the one exit, a held body refusing
the request, the part's old pelvis handshake cleared on resume, the presented form's `form_name`
driving the act facts while the stable id and event id survive and an empty form name falling back
to the identity's display name, the fake policy recording the six generic act milestones in order,
the late-revision eye staying at its true-base target, auto's pace/band/shape/on state surviving
the swap, the freed base-game vocal cache entry being pruned, and the no-body watchdog,
ineligible-form and world-close paths ending through the one exit. The suite fakes the entry
because `main.gd` names the `Mods` autoload, which a `--script` suite cannot load; the entry's own
adopt-before-create and LOD-refresh order is review-only. The contract is `docs/runtime.md`.

The body-change contract is `docs/body_change.md`. Its suites are
`tests/body_change/test_service.gd` (the typed data, default form, form store, legacy mirror,
binding order, same-node revisions, source registry and provider notification) and
`tests/integrations/test_changelings.gd` (the shipped provider's forms and policy); the handover
paragraph above is the act-side half. The base invariants — one body-change fan-out, one resume,
one teardown and no provider vocabulary in the core — are static rules in
the static gate, not a suite.

The pose suites are `tests/poses/test_pose_state.gd`, `test_pose_edge.gd`,
`test_pose_registry.gd`, `test_pose_spec.gd`, `test_pose_view.gd`, `test_session.gd`,
`test_pose_blend.gd`, `test_pose_teardown.gd`, `test_oral_turn.gd`, `test_face_contact.gd`,
`tests/test_face_sit_action.gd` (the debug action and its refusal helper),
`test_modifier_profile.gd`, `test_pose_asset.gd`, `test_pose_asset_layout.gd`, `test_pose_bake.gd`,
`test_rotation.gd`, `test_pose_sway.gd` and `test_act_body.gd`; `docs/poses.md` says what each
pins. `tests/test_act_commands.gd` pins the pure command vocabulary: unique lower_snake_case ids,
the continuous/discrete partition of `ALL`, the helpers and the reserved `end`.
`tests/poses/test_session.gd` reads those ids against the real `CONTROL_SETS` profiles, and
`tests/test_input.gd` pins the `V`/`N`/`B` dispatch through `act/input.gd:command()` (ready,
refused and non-ready) plus the unchanged shield. The hook suites `tests/act_camera/test_camera.gd` and
`tests/act_camera/test_kiss.gd` pin the view-only config; the pose-view contact and facing reads
are review rules (`docs/act_facts.md`), and the `pose_tick`/`pose_fanout` order around the facts
sync in `act/tick.gd` is a static rule in the static gate.

## What not to assert

- **Test the API once.** One suite owns the contract for a facade; a feature suite calls the facade
  and does not restate its contract. The settings schema, the characters document, the prompt graph
  and the pose table each have one owner.
- **Never assert a shipped default.** A suite names a setting and its behaviour and reads the live
  value as input. It never copies the default into an expectation or compares a
  `Setting.default` to a numeric literal. The shipped `settings/settings.json` is the only source
  of the value; the static gate rejects a default-vs-literal comparison, with
  one allow-listed fallback-to-default call in `tests/poses/test_session.gd`.
- **Never grep source text.** A suite does not read production source or docs to assert their text.
  Source invariants belong to the static gate, and `FileAccess.get_file_as_string`
  is limited to the allow-list below.
- **No tautologies.** `check(true, …)`, a count compared with the keys just iterated, and a
  read-back of the value just written prove nothing. A check compares a value the code produced
  with the behaviour the suite names.
- **Merge pure modules into their owning suite.** A pure helper or a small module adds its checks
  to the suite of the facade that owns it; do not add a file per module. The merged-path table
  above is the result.
- A regression test stays after the fix. Deleting it re-opens the bug.
- A suite does not assert another service's private state; it calls that service's facade.
- Pass counts are never copied into a doc; the suite path is.

### Test-file gate

The static gate enforces these rules over `tests/`:

- every discovered `tests/**/test_*.gd` extends `tests/support/suite.gd`;
- every suite defines `run()` and contains at least one assertion call (`check(`, `check_eq(`,
  `check_ne(`, `check_approx(`, `check_contains(`, `check_empty(`, `check_size(`, `check_same(`,
  `check_null(`, `check_not_null(` or `fail(`);
- a suite does not define a base-owned helper (`check`, `check_eq`, `check_ne`, `check_approx`,
  `check_contains`, `check_empty`, `check_size`, `check_same`, `check_null`, `check_not_null`,
  `fail`, `near`, `_initialize`, `finish`, `_result_prefix`) and does not call `quit(`;
- a suite does not print the result line (`_RESULT`): the base owns it;
- no suite calls `check(true, …)`;
- only `tests/test_settings.gd` and `tests/test_prompts.gd` name a shipped data document
  (`settings.json`, `characters.json`, `prompts.json`, or a loader's path constant); every other
  suite reaches a shipped value through a module's public API;
- no `check(` call places a declaration `.default` next to a numeric literal, except the
  allow-listed `tests/poses/test_session.gd` fallback for `SETTINGS.chin_up_deg.default`;
- `FileAccess.get_file_as_string` is limited to the allow-list below, so no suite scans production
  source or docs for text;
- the manual labs (`tests/test_lab*.gd`, `tests/test_stress_lab.gd`) are exempt from the base,
  `run()`, assertion and file-read rules.

The file-read allow-list, and the document each read is for:

| Suite | Reads |
|---|---|
| `tests/test_settings.gd` | the shipped settings and characters documents and their backups |
| `tests/test_api.gd` | `docs/api.md` |
| `tests/poses/test_pose_bake.gd` | the shipped standing asset bytes |
| `tests/poses/test_pose_edge.gd` | the pose edge JSON fixtures |
| `tests/hands/test_caress.gd` | the areas JSON fixture |
| `tests/anatomy/test_geometry.gd` | the coat shader's sample count |
| `tests/integrations/test_pantyhose.gd` | the copied shader includes |

A new read is a review of the checker's map, not a copy-paste in a suite.
