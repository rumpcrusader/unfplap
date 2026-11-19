# Static gates and tooling

The source-only gates that run outside the game project. The behavioural suites are `docs/tests.md`;
the commands are `WORKFLOW.md`.

## Formatting

Formatting. No formatter is run. gdformat is intentionally not adopted: it is configurable only by
line length and indentation, and it conflicts with the adopted style of the repo — two blank lines
around every function, trailing commas, parenthesized method chains. This unifies the style with
the widely accepted conventions, but doesn't meaningfully improve quality or readability, and in
some cases worsens it. Additionally, it is written in pure Python and slow. Keep the current layout
by review; do not add a formatter gate.

## Linting

`gdlint` 4.5.0 lints the shipped `.gd` files only. Tests and tools are excluded because
gdtoolkit's parser rejects some valid test syntax. The config is `.gdlintrc`.

The structural rules are disabled because they conflict with the service layout: the repo
interleaves public and private state by subsystem, a correct boundary beats a line count, the
facades intentionally expose many methods, and the act code uses guard clauses. The remaining
rules catch naming drift, unused arguments, duplicate loads, self-comparisons, unassigned
expressions and whitespace.

Install the pinned toolchain with `python3 -m pip install -r scripts/requirements-lint.txt`, then
run `scripts/lint.sh`. The source-checks CI job runs the same command and blocks the build on a
finding. The tree is clean; a new finding fails. Pin gdtoolkit 4.5.0; bump it deliberately with a
Godot upgrade and re-run the gate.

## Complexity

Complexity. gdradon cc is not used. It converts GDScript to Python and cannot parse some of the
valid GDScript code, discards every expression so and/or are not counted, has no threshold or JSON
options, and exits 0 on failure. Use a parser-based baseline ratchet if complexity gating is
wanted.

## Architecture gate

`scripts/architecture.py --check` compares each service's `docs/` `### Uses` table with the preload
graph and enforces the layer and privacy rules. These rules exist so code cannot grow back outside
the gate:

- **Every mod path has an owner.** A shipped `.gd` must resolve through `owner_of()` to a service
  (`<id>/service.gd` and everything under `<id>/`), `shared/`, or one of the three orchestrators
  `main.gd`, `runtime.gd` and `api.gd`. Any other path has no owner, so every edge to and from it
  is classified external and allowed; the mod root's former `runtime/` grew a file that way.
- **The entry builds no binding.** `main.gd` may not name a `*_binding.gd` or call
  `register_binding`: the body-change service constructs and registers its chain from the facades
  the entry hands it, so a new body-bound system adds no line to the composition root.
- **The entry constructs and binds.** `main.gd` may not contain `.call(`, `.get("` or `.set("`, nor
  register an `action_*` handler: the entry constructs one service per line and calls its `bind()`,
  and a service dispatches its own typed members. The gate fails on the first string dispatch.
- **Only the entry names the entry.** No shipped `.gd` outside `main.gd` may contain
  `main.<member>`, `var main`, a `main.gd` preload or a `main` argument; `tests/` is exempt. A
  consumer preloads the facade it needs, reads `WORLD` for the scene, or takes a typed host
  parameter.
- **The runtime is a host, not a system.** `runtime.gd` assigns `state` only inside `_set_state()`,
  decodes no raw input (`Input.`, `InputMap.`, `InputEvent*`, `KEY_*`, `MOUSE_MODE_*`, an input
  callback), reads `SETTINGS.` only at the act's snapshot boundaries — `act/session.gd:snapshot_settings()`,
  `apply_live_settings()`, the start and resume paths, the `_snapshot` field's typed default and
  `_shape_name()`'s static character-name lookup — and calls `add_child()` only for the two
  system-owned nodes: the act audio node and the tail tuck. Both allow-lists live in the checker
  and are compared in both directions, so a new settings read or node fails the gate and a row
  whose code is gone fails as stale.

The rest — one body-change fan-out, one body-swap resume, one `_end_session()`, the runtime's tick
and fan-out order, the scene-only world facade and the suite allow-lists — is the checker's own
source of truth; read `scripts/architecture.py` before changing the tree it guards.

## Shell scripts

Every bash entry point starts with `set -euo pipefail`; `scripts/architecture.py --check` pins that
prelude for every root and `scripts/*.sh`. Rely on the options instead of probing dependencies: a
script that needs `godot` or `python3` calls it; `set -e` stops at the failing command and the shell
or tool prints the reason. A `command -v` guard is only for a failure that would otherwise continue
or act unsafely: the parallel gate keeps its Godot probe so a missing interpreter cannot report a
false pass with empty logs, and `lab-vr.sh` keeps its Monado-service and runtime-manifest guards
because it starts that service itself and would otherwise run a VR lab without a runtime.

A script that must observe a failure captures the status at that call (`if cmd; then ...; else
status=$?; fi`) and keeps `-e`; it does not drop `-e` so a loop can continue. The gate runners read
a tool's output after an expected non-zero exit, so `scripts/check.sh`, `scripts/test.sh` and
`scripts/smoke.sh` allow exactly that call (`|| true` or the if/else capture) and stay under `-e`.

The manual labs pick the session display driver: `DISPLAY_DRIVER` first, then Wayland when
`WAYLAND_DISPLAY` is set, else X11. `lab-vr.sh` additionally sets its own XR runtime. The labs rely
on `-e` for the Godot and asset checks instead of repeating a dependency probe.

More than 25 non-empty, non-comment lines is a smell: extract a shared prelude or move the logic
into the tool the script wraps. The threshold is a review prompt, not a gate.

## Related docs

- `docs/tests.md` — the behavioural suites and the runner.
- `WORKFLOW.md` — the commands and the commit flow.
