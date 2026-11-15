# Test suites

The headless gate: what a suite is, how it is discovered, how it is isolated and how to run a
subset without disagreeing with `scripts/test_all.sh`.

Suites are not services. They have no facade, no contract entry in the service index and no
lifecycle; this doc owns their shape and their runner.

## Scope

- `tests/` holds every headless suite. The full gate runs them all.
- A suite is a scene-free `SceneTree` script that prints one machine-readable result line.
- Anything that needs a live world, a person at the keyboard, a headset or the HUD belongs to a
  manual lab, not here.

## Suite layout

| Path | Holds |
|---|---|
| `tests/<service>/test_<topic>.gd` | the suites for one service's facade or internals |
| `tests/test_<topic>.gd` | a root suite that crosses services, or a shared/pure module's suite |

One suite per file, and the directory mirrors the facade it exercises. The suite-to-service map is
the `Tests` column of `docs/README.md`. A pure module's suite uses plain values: for example
`tests/poses/test_pose_state.gd` pins the pose transition table and the edge math with dictionaries
and no scene, node or autoload. `tests/poses/test_pose_blend.gd` builds a bare `Skeleton3D` and fake
drivers, so the pose evaluator's single/blend paths, capture buffers and non-finite guard are
pinned without a game file.

## Writing a suite

A suite is `extends SceneTree` with no scene and no autoload beyond `Mods` and `Settings`:

```gdscript
extends SceneTree
## What this suite pins. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_x.gd

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
	check(true, "the first thing this suite pins")
	print("X_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
```

- `_initialize()` defers `run()` so the tree is up before the checks touch a node.
- `check(ok, text)` prints only failures; the text names the rule, not the value.
- The final `…_RESULT checks=%d failures=%d` line is the runner's only input. A suite that never
  prints it is reported as `FAIL … (no result)`.
- `quit(0)` on success and `quit(1)` on failure; the runner reads the result line, but the exit
  code keeps a direct `godot … --script` run honest.
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
`TEST_ALL_PASS`, which is the marker the release check greps.

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
`tests/act_audio/test_audio.gd`. `tests/test_source_hygiene.gd` pins the `_pose_fanout()` order
(pose service first, then camera, hands, kiss, anatomy and audio), the `_free_pose()` order and its
two callers, and keeps the act-exit names out of `poses/`. The contract is `docs/poses.md`; this doc
only names the gate.

The pose suites are `tests/poses/test_pose_state.gd`, `test_pose_edge.gd`,
`test_pose_registry.gd`, `test_pose_spec.gd`, `test_pose_view.gd`, `test_session.gd`,
`test_pose_blend.gd`, `test_pose_teardown.gd`, `test_oral_turn.gd`, `test_face_contact.gd`,
`test_face_sit_action.gd` (the debug action and its refusal helper),
`test_modifier_profile.gd`, `test_pose_asset.gd`, `test_pose_asset_v7.gd`, `test_pose_bake.gd`,
`test_pose_rig.gd`, `test_pose_scale.gd`, `test_rotation.gd`, `test_body_sway.gd` and
`test_stretch.gd`; `docs/poses.md` says what each pins.
`tests/test_act_commands.gd` pins the pure command vocabulary: unique lower_snake_case ids,
the continuous/discrete partition of `ALL`, the helpers and the reserved `end`.
`tests/poses/test_session.gd` reads those ids against the real `CONTROL_SETS` profiles, and
`tests/test_input.gd` pins the `V`/`N`/`B` dispatch through `runtime.command()` (ready, refused and
non-ready) plus the unchanged shield. The hook suites `tests/act_camera/test_camera.gd` and
`tests/act_camera/test_kiss.gd` pin the view-only config; `tests/test_source_hygiene.gd` pins the
pose-view contact and facing reads and the `pose_tick`/`pose_fanout` chunks around the facts sync
in `_physics_tick`.

## What not to assert

- The shipped defaults schema and the bounds belong to `tests/test_settings.gd`. A suite names a
  setting and its behaviour, not a copied number.
- Pass counts are never copied into a doc; the suite path is.
- A regression test stays after the fix. Deleting it re-opens the bug.
- A suite does not assert another service's private state; it calls that service's facade.
- `tests/test_source_hygiene.gd` carries the raw `pose_id` census. Its per-file budget ratchets
  down: a migrated consumer may not raise its entry, and a file that drops lowers it in the same
  commit. The remaining reads are the runtime's start identity, the pose session's begin key, the
  settings data API and the debug display line. No start-pose comparison or `oral_active` mirror
  survives outside the data modules.

## Related docs

- `docs/README.md` — the suite-to-service map, the doc template and the verification matrix.
- `docs/debug.md` — the lab roster and keys.
- `WORKFLOW.md` — the commands and the release flow.
