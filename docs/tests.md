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
the `Tests` column of `docs/README.md`.

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
  `user://` settings, saves and logs can never change a default-value assertion.
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

## What not to assert

- Setting defaults and bounds belong to `tests/test_settings.gd`. A suite names a setting and its
  behaviour, not a copied number.
- Pass counts are never copied into a doc; the suite path is.
- A regression test stays after the fix. Deleting it re-opens the bug.
- A suite does not assert another service's private state; it calls that service's facade.

## Related docs

- `docs/README.md` — the suite-to-service map, the doc template and the verification matrix.
- `docs/debug.md` — the lab roster and keys.
- `WORKFLOW.md` — the commands and the release flow.
