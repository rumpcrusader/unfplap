# Test suites

The headless gate: what a suite is, how it is discovered, how it is isolated and how to run a
subset without disagreeing with the full gate.

Suites are not services: no facade, no contract entry, no service lifecycle. This doc owns their
shape and their runner; the static checks over the suite tree belong to the gate, and anything that
needs a live world, a keyboard, a headset or the HUD is a manual lab, not a suite.

## What a suite is

A suite is a scene-free script on the shared base that implements `run()`; the base owns the
assertion helpers, the run/finish lifecycle and the one machine-readable result line. It defers the
run so the tree is up before a check touches a node, fails a suite that asserted nothing, runs the
teardown once, and arms a watchdog so a `run()` that never returns still reports. The header
comment carries the suite's direct command; the result label is derived from the path and is
cosmetic, because the runner reports it and never parses it.

A suite is its own root. Every node it builds is freed by the suite, and a runtime — or the body
that holds it — is attached under the suite's root before it is freed, so composition runs
and releases on its one path. A detached free is a defect, not a shortcut.

## Where a suite lives

The directory is the map: a suite under `tests/<id>/` exercises `<id>/`, and a root-level suite
crosses services or covers a shared pure module. One suite per file, named after the rule it pins;
each rule has exactly one suite, and a small pure module folds its checks into the suite of the
facade that owns it instead of adding a file of its own.

The project's autoloads do boot, so a suite fakes the node it needs under the root and restores any
autoload node it renames.

## Isolation

Each suite gets its own data home under the runner's temporary directory, so the player's settings,
saves and logs can never change an assertion. The runner hands it down and the base refuses to run
when the resolved user directory is outside it; a direct run is not checked.

A fixed path under the user directory is safe only because the suite owns that directory: keep it
unique to the suite, remove what it writes, and never depend on another suite. A suite passes on a
fresh checkout with no settings file and no save, and parallel suites never touch the same file.

## Running

With no argument `scripts/test.sh` runs every suite. A suite name, or a directory, runs that subset
through the same discovery and the same per-suite invocation as the full gate, so a subset cannot
disagree with it. `--quick` drops the static prechecks for iteration and is never the gate, and
`--all` always runs them; `--list` prints what discovery found, `--self-test` proves the watchdog
and `--smoke` boots the game from the source and fails on a script or parse error.

Discovery collects the test scripts two levels deep and skips the manual labs. The parallelism is
one job per core, capped, and the runner reads `TEST_JOBS` for an override.

A run prints only the suites that failed, each with its failure lines, and ends in one status line
naming every failing suite, preceded by a `rerun:` line for the next attempt. A suite that leaves no
result fails with its exit status, and one the timeout killed says it timed out.

Every suite must also leave no script error, no parse error and no leaked object or resource in its
log; the runner prints those lines under the suite's name. There is no leak allowlist: a suite that
builds a node owns its release.

## What not to assert

- **Test the API once.** One suite owns a facade's contract; a feature suite calls the facade and
  never restates it.
- **Never assert a shipped default.** A suite names a setting and its behaviour and reads the live
  value as input; the shipped document is the only source of a default.
- **Never grep source text.** A suite does not read production source or docs to assert their text;
  source invariants belong to the static gate. A suite that must read a shipped document or a
  fixture is a review of the gate's read map, not a copy-paste.
- **No tautologies.** A check that compares a value with itself, re-reads what it just wrote or
  counts the keys it just iterated proves nothing.
- **A suite does not assert another service's private state**; it calls that service's facade.
- A regression test stays after the fix, and pass counts never reach a doc.

## Manual labs

The manual labs need a live world and are not in the headless gate. Run the phase's lab and record
the result in the phase notes; when it cannot run in the current environment, say so instead of
claiming it passed. The commands are in `WORKFLOW.md`.
