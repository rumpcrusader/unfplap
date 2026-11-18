# Test suites

The headless gate: what a suite is, how it is discovered, how it is isolated and how to run a
subset without disagreeing with `scripts/test_all.sh`.

Suites are not services. They have no facade, no contract entry in the service index and no
lifecycle; this doc owns their shape and their runner.

## Scope

- `tests/` holds every headless suite. The full gate runs all 124 of them.
- A suite is a scene-free `SceneTree` script that prints one machine-readable result line.
- Anything that needs a live world, a person at the keyboard, a headset or the HUD belongs to a
  manual lab, not here.
- The static source and test-file invariants are `scripts/architecture.py --check`, not a suite.

## Suite layout

| Path | Holds |
|---|---|
| `tests/<service>/test_<topic>.gd` | the suites for one service's facade or internals |
| `tests/test_<topic>.gd` | a root suite that crosses services, or a shared/pure module's suite |
| `tests/<topic>/test_<topic>.gd` | a cross-service concern with its own name; `handover/` is the act body swap |

One suite per file, and the directory mirrors the facade it exercises. A small pure module folds
into the suite that owns its facade instead of adding a file of its own. The suite-to-service map
is the `Tests` column of `docs/README.md`. A pure module's suite uses plain values: for example
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
| `tests/poses/test_pose_scale.gd` | `tests/poses/test_pose_asset_v7.gd` |
| `tests/anatomy/test_facts.gd` | `tests/act_facts/test_act_facts.gd` |
| `tests/anatomy/test_appearance.gd` | `tests/anatomy/test_coat.gd` |
| `tests/anatomy/test_tail_hide.gd` | `tests/anatomy/test_placement.gd` |
| `tests/privacy_rules/test_privacy_rules.gd` | `tests/privacy/test_privacy.gd` |
| `tests/stool/test_stool_api.gd` | `tests/stool/test_gate.gd` |
| `tests/memory/test_facts.gd` | `tests/memory/test_text.gd` |
| `tests/dialogue/test_history_scan.gd` | `tests/dialogue/test_act_dialogue.gd` |
| `tests/face/test_mood_face.gd` | `tests/face/test_act_face.gd` |
| `tests/readiness/test_auto_panel.gd` | `tests/readiness/test_readiness_auto.gd` |
| `tests/summary/test_history.gd` | `tests/summary/test_act_flow.gd` |
| `tests/integrations/test_hold.gd` | `tests/integrations/test_service.gd` |
| `tests/test_source_hygiene.gd` | `scripts/architecture.py --check` |

## Writing a suite

A suite is `extends SceneTree` with no scene and no autoload beyond `Mods` and `Settings`:

```gdscript
extends SceneTree
## What this suite pins. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_x.gd

const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	check(CLEARANCE.evaluate(true, true, true).ok(), "Base clearance passes when every row holds")
	print("X_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
```

- `_initialize()` defers `run()` so the tree is up before the checks touch a node.
- `check(ok, text)` prints only failures; the text names the rule, not the value.
- The final `…_RESULT checks=%d failures=%d` line is the runner's result input. A suite that never
  prints it is reported as `FAIL … (no result)`.
- The runner also scans the suite log for `SCRIPT ERROR` and `Parse Error`; a suite that logs one
  fails even when the result line reports `failures=0`, so a script error cannot hide behind a
  passing check count.
- `quit(0)` on success and `quit(1)` on failure; the runner reads the result line and the log, but
  the exit code keeps a direct `godot … --script` run honest.
- The header comment carries the direct command, so a suite can be run without the runner while
  debugging.

## Isolation

- Each suite gets its own `XDG_DATA_HOME` under the runner's temporary directory, so the player's
  `user://` settings, saves and logs can never change a behaviour assertion or the shipped-defaults
  schema check.
- Never write a fixed path under `user://` and never depend on another suite having run first.
- A suite must pass on a fresh checkout, with no settings file and no save.
- Parallel runs are the default; two suites must never touch the same file.

## Running

| Command | Runs |
|---|---|
| `scripts/test.sh <suite>...` | the named suites, or every suite under a directory (`scripts/test.sh poses`) |
| `scripts/test.sh --list` | the discovered suites, then exits |
| `scripts/test.sh --all` | every suite; this is what `scripts/test_all.sh` runs |
| `scripts/test_all.sh` | the full gate: every suite, once per task |

`scripts/test.sh` runs the same prechecks as the gate (Godot on `PATH`, the fetched asset set,
`scripts/architecture.py --check`), uses the same discovery and the same per-suite invocation, so a
subset cannot disagree with the full gate. A subset ends in `TEST_PASS <n> suites`; `--all` ends in
`TEST_ALL_PASS`, which is the marker the release check greps. Every suite must also leave no
`SCRIPT ERROR` or `Parse Error` in its log.

Discovery is `tests/**/test_*.gd`, two levels deep, excluding the manual labs (`test_lab*.gd`,
`test_stress_lab.gd`). `TEST_JOBS` sets the parallelism (default 6).

`scripts/check.sh` is a parse check, not a test run: use it for the files you touched, and
`scripts/check.sh --all` before you report the task done.

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
profile lives only in the session's test seam, and the live `refresh_modifiers()` edit swaps the
feature flags into the same reconcile. The hook suites are
`tests/act_camera/test_camera.gd`, `tests/act_camera/test_kiss.gd`, `tests/hands/test_caress.gd`,
`tests/hands/test_actions.gd`, `tests/anatomy/test_act_bridge.gd` and
`tests/act_audio/test_audio.gd`. The pose ledger's order and its three callers, the
`_pose_fanout()` owner order (pose service first, then camera, hands, kiss, anatomy and audio), the
pose-before-facts order in `_physics_tick` and the ban on act-exit names under `poses/` are static
rules in `scripts/architecture.py --check`. The contract is `docs/poses.md`; this doc only names
the gate.

The body-swap handover is `tests/handover/test_body_swap.gd`: suspend → adopt → resume with the
act state, depth, climaxes and event id intact, the old runtime still alive, the new anatomy and
pose bound, adoption binding without resuming until the named form reports its target, the target
completing as the form, a missing form restoring the offer on the new body, the watchdog with a
body resuming as a failed form, a change the provider started on its own, a repeated change, the
debug form-state label clearing at each state change while the HUD string stays empty, a failed
named change restoring the offer, her own change keeping the player's offer, a late body adopted
once after the grace, a change during restore finishing through the one exit, a held body refusing
the request, the part's old pelvis handshake cleared on resume, and the no-body watchdog,
ineligible-form and world-close paths ending through the one exit. The suite fakes the entry
because `main.gd` names the `Mods` autoload, which a `--script` suite cannot load; the entry's own
adopt-before-create and LOD-refresh order is review-only. The contract is `docs/runtime.md`.

The body-change contract is `docs/body_change.md`. Its suites are
`tests/body_change/test_service.gd` (the typed data, default form, form store, legacy mirror,
binding order, same-node revisions, source registry and provider notification) and
`tests/integrations/test_changelings.gd` (the shipped provider's forms and policy); the handover
paragraph above is the act-side half. The base invariants — one body-change fan-out, one resume,
one teardown and no provider vocabulary in the core — are static rules in
`scripts/architecture.py --check`, not a suite.

The pose suites are `tests/poses/test_pose_state.gd`, `test_pose_edge.gd`,
`test_pose_registry.gd`, `test_pose_spec.gd`, `test_pose_view.gd`, `test_session.gd`,
`test_pose_blend.gd`, `test_pose_teardown.gd`, `test_oral_turn.gd`, `test_face_contact.gd`,
`tests/test_face_sit_action.gd` (the debug action and its refusal helper),
`test_modifier_profile.gd`, `test_pose_asset.gd`, `test_pose_asset_v7.gd`, `test_pose_bake.gd`,
`test_rotation.gd`, `test_pose_sway.gd` and `test_act_body.gd`; `docs/poses.md` says what each
pins. `tests/test_act_commands.gd` pins the pure command vocabulary: unique lower_snake_case ids,
the continuous/discrete partition of `ALL`, the helpers and the reserved `end`.
`tests/poses/test_session.gd` reads those ids against the real `CONTROL_SETS` profiles, and
`tests/test_input.gd` pins the `V`/`N`/`B` dispatch through `runtime.command()` (ready, refused and
non-ready) plus the unchanged shield. The hook suites `tests/act_camera/test_camera.gd` and
`tests/act_camera/test_kiss.gd` pin the view-only config; the pose-view contact and facing reads
are review rules (`docs/act_facts.md`), and the `pose_tick`/`pose_fanout` order around the facts
sync in `_physics_tick` is a static rule in `scripts/architecture.py --check`.

## What not to assert

- **Test the API once.** One suite owns the contract for a facade; a feature suite calls the facade
  and does not restate its contract. The settings schema, the character catalog and the pose table
  each have one owner.
- **Never assert a shipped default.** A suite names a setting and its behaviour and reads the live
  value as input. It never copies the default into an expectation or compares a
  `Setting.default` to a numeric literal. The shipped `settings/defaults.json` is the only source
  of the value; `scripts/architecture.py --check` rejects a default-vs-literal comparison, with
  one allow-listed fallback-to-default call in `tests/poses/test_session.gd`.
- **Never grep source text.** A suite does not read production source or docs to assert their text.
  Source invariants belong to `scripts/architecture.py --check`, and `FileAccess.get_file_as_string`
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

`scripts/architecture.py --check` enforces these rules over `tests/`:

- every discovered `tests/**/test_*.gd` defines a `check(` helper and prints a line containing
  `_RESULT checks=`;
- no suite calls `check(true, …)`;
- only `tests/test_settings.gd` reads `settings/defaults.json` (or names `DEFAULTS_FILE`);
- no `check(` call places a declaration `.default` next to a numeric literal, except the
  allow-listed `tests/poses/test_session.gd` fallback for `SETTINGS.chin_up_deg.default`;
- `FileAccess.get_file_as_string` is limited to the allow-list below, so no suite scans production
  source or docs for text;
- the manual labs (`tests/test_lab*.gd`, `tests/test_stress_lab.gd`) are exempt from the helper,
  result-line and file-read rules.

The file-read allow-list, and the document each read is for:

| Suite | Reads |
|---|---|
| `tests/test_settings.gd` | the shipped defaults document and its backups |
| `tests/test_api.gd` | `docs/api.md` |
| `tests/poses/test_pose_bake.gd` | the shipped standing asset bytes |
| `tests/poses/test_pose_edge.gd` | the pose edge JSON fixtures |
| `tests/hands/test_caress.gd` | the areas JSON fixture |
| `tests/anatomy/test_geometry.gd` | the coat shader's sample count |
| `tests/integrations/test_pantyhose.gd` | the copied shader includes |

A new read is a review of the checker's map, not a copy-paste in a suite.

## Related docs

- `docs/README.md` — the suite-to-service map, the doc template and the verification matrix.
- `docs/quality.md` — the static gates and tooling policy.
- `docs/debug.md` — the lab roster and keys.
- `WORKFLOW.md` — the commands and the release flow.
