# Static gates and tooling

The source-only gates that run outside the game project. The behavioural suites are `docs/tests.md`;
the commands are `WORKFLOW.md`.

## Parse check

`scripts/check.sh` loads every `.gd` file — tests and tools included — once, in one headless engine
boot through `tools/parse_all.gd`, and reports the files that do not load. The default run also runs
the static gate; `--parse` loads only the changed and untracked `.gd` files without the gate, and
`--static` runs the gate without Godot or the fetched assets. The cost is that boot plus each
script's preload closure once, so it must not return to one boot per file. A run that ends without
the tool's `PARSED` line is a failure, never a pass.

## Formatting

Formatting. No formatter is run. gdformat is intentionally not adopted: it is configurable only by
line length and indentation, and it conflicts with the adopted style of the repo — two blank lines
around every function, trailing commas, parenthesized method chains. This unifies the style with
the widely accepted conventions, but doesn't meaningfully improve quality or readability, and in
some cases worsens it. Additionally, it is written in pure Python and slow. Keep the current layout
by review; do not add a formatter gate.

## Linting

`gdlint` 4.5.0 lints the shipped `.gd` files and the test suites. The shipped config is the root
`.gdlintrc`; `tests/.gdlintrc` keeps the same structural disables and adds `unnecessary-pass`,
`unused-argument`, `comparison-with-itself` and `sub-class-name` for test syntax. `tools/` stays
excluded from both.

The structural rules are disabled because they conflict with the service layout: the repo
interleaves public and private state by subsystem, a correct boundary beats a line count, the
facades intentionally expose many methods, and the act code uses guard clauses. The remaining
rules catch naming drift, unused arguments, duplicate loads, self-comparisons, unassigned
expressions and whitespace.

Install the pinned toolchain with `python3 -m pip install -r scripts/requirements-lint.txt`, then
run `scripts/lint.sh`. The source-checks CI job runs the same command and blocks the build on a
finding. The tree is clean; a new finding fails. Pin gdtoolkit 4.5.0; bump it deliberately with a
Godot upgrade and re-run the gate.

## Comments

Comments are shape-gated, not prose-reviewed. `scripts/comments.py --check` runs inside
`scripts/lint.sh` and in the source-checks CI job; tests and tools are excluded like gdlint. The
rules:

- a facade header is at most five `##` lines: `Service:`/`Scope:`/`Contract:` plus one
  purpose sentence; a module header is its purpose sentence and nothing else;
- any other `##` block is at most two lines: the promise, then one clause of why;
- a `#` block is at most three lines;
- no backticked private `_member` (Godot engine virtuals excepted);
- every backticked `docs/x.md` must exist; heading anchors are not resolved, so a heading rename
  never edits a comment;
- a comment sentence may not copy a sentence from `docs/*.md` or `ARCHITECTURE.md`.

`--audit` prints every finding as JSON and `--self-test` runs the rule fixtures that `lint.sh`
executes first. The gate checks shape and rename-safety only; whether a comment earns its place is
review, under `AGENTS.md`. The reason for
the caps is churn: a comment that names a member, a count or a doc sentence must be edited on every
rename or refactor, and a two-line block cannot grow back into a second copy of the owning doc.

## Complexity

Complexity. gdradon cc is not used. It converts GDScript to Python and cannot parse some of the
valid GDScript code, discards every expression so and/or are not counted, has no threshold or JSON
options, and exits 0 on failure. Use a parser-based baseline ratchet if complexity gating is
wanted.

## Architecture gate

The static gate (`scripts/check.sh --static`) scans the preload graph and enforces the layer, owner,
game-boundary and re-export rules. These rules exist so code cannot grow back outside the gate:

- **Every mod path has an owner.** A shipped `.gd` must resolve through `owner_of()` to a service
  (`<id>/service.gd`, or `anatomy/api.gd` for the anatomy package, and everything under
  `<id>/`), `shared/`, or one of the three orchestrators `main.gd`, `runtime.gd` and `api.gd`. Any other path has no owner, so every edge to and from it
  is classified external and allowed; the mod root's former `runtime/` grew a file that way.
- **Every anatomy file reads the game through `GAME`.** No anatomy file may preload a base-game
  module; no anatomy file may preload another mod service except `settings/service.gd`; and no
  outside file may preload an anatomy file except `anatomy/api.gd`. The two directions are
  synthetic fixtures in the gate's self-test, run by `scripts/test.sh`.
- **Every script dependency is a top-level preload.** In every `.gd`, `tests/` and `tools/`
  included, each `const … := preload(...)` sits in the contiguous block directly below the doc
  header. A preload after another declaration or inside a class or function fails, and so does a
  `load()` of a script path or a const that resolves to one; a runtime `load(path)` for an asset
  stays allowed.
- **The entry builds no binding.** `main.gd` may not name a `*_binding.gd` or call
  `register_binding`: the body-change service constructs and registers its chain from the facades
  the entry hands it, so a new body-bound system adds no line to the composition root.
- **The two roots are pure.** `main.gd` may not contain `.call(`, `.get("` or `.set("`, nor
  register an `action_*` handler: `_build_process()` and `_build_world()` construct, `wire`, name
  and attach, and each service builds its own children and settings in `_ready()`. Neither root
  reads `WORLD`, `SETTINGS`, `LOG` or `PERF`, starts behaviour or dispatches by string; the gate
  fails on the first string dispatch.
- **Wiring is single-place.** Each facade declares at most one `wire()`, and a facade that declares
  one has the scope's root (`_build_world()`, `_compose()`) call it once, and no other file calls
  `wire()`. The Pony facades' `bind`-family is the named exception while the rename is pending: the
  gate accepts it as the facade's one peer-injection member and `_compose()` is its caller.
  Construction is root-only. A facade has one peer-injection member, `wire` takes a peer parameter
  nowhere else, and the lifecycle hooks and `_init` are the only exceptions. The root calls only
  the composition verbs (construct, wire, name, `add_child`, `add_to_group`, `connect`, register a
  source) and reads no `WORLD`/`SETTINGS`/`LOG`/`PERF`; a `wire()` body takes no tree access and
  reads no scene. A field set from a `wire()` parameter is written only by `wire()` and cleared
  only by `shutdown()`, and both directions of every rule are synthetic fixtures in the self-test.
- **The two debug assertions.** The entry logs one error per direct child outside `unfplap_world`
  (the API node is the named exception); the runtime logs one per direct child outside
  `unfplap_pony_service`. Both run behind `LOG.enabled` and return the offender count.
- **The scope tree is static.** Every facade declares `Service:`/`Scope:`/`Contract:` and the
  Services table repeats the scope; a non-facade declares nothing except the frozen
  `shared/log.gd` and `shared/perf.gd` headers. A `world` or `pony` facade is a Node,
  `CanvasLayer` or `shared/service.gd` (`world/api.gd` is the `WORLD_STATIC` exception). Only
  `main.gd` and `runtime.gd` construct and attach their scopes, through their attach helpers and
  their `unfplap_world`/`unfplap_pony_service` groups; a cross-scope private preload or
  construction fails.
- **Only the entry names the entry.** No shipped `.gd` outside `main.gd` may contain
  `main.<member>`, `var main`, a `main.gd` preload or a `main` argument; `tests/` is exempt. A
  consumer preloads the facade it needs, reads `WORLD` for the scene, or takes a typed host
  parameter.
- **The runtime is a host, not a system.** `runtime.gd` declares no `state` field and assigns no
  `state` (the one writer is `act/session.gd:_set_state()`), decodes no raw input (`Input.`,
  `InputMap.`, `InputEvent*`, `KEY_*`, `MOUSE_MODE_*`, an input callback), reads no `SETTINGS.`
  value, and parents only the Pony services: `_attach()` is the one `add_child()` site, `_compose()`
  its one caller, and the child allow-list is compared both ways. Its public functions and
  properties are fixed by `NODE_SURFACE` and `NODE_PROPERTIES`. The act's settings reads live in
  `act/settings.gd` at its two snapshot boundaries (`snapshot_values`, `live_preferences`), each
  with a named allow-list row; the world audio service's pool and the pose-scope tail tuck are
  created by their owners. Both allow-lists live in the checker and are compared in both
  directions, so a new settings read or node fails the gate and a row whose code is gone fails as
  stale. File size is reported as `SMELL large file`, never as a cap.

The rest — one body-change fan-out, one `act/swap.gd:resume()`, one `act/exit.gd:run()`, the
schedule's tick and fan-out order in `act/tick.gd`, the scene-only world facade and the suite
allow-lists — is the checker's own source of truth; read `scripts/architecture.py` before changing
the tree it guards. Its maintenance modes — `--group <name>` for one rule group, `--graph`,
`--audit-surface`, `--write-exceptions`, `--write-debt` and `--write-duck-typing` — run directly on
that module, not through the gate. The graph is for review and is not checked in.

## Shell scripts

Every bash entry point starts with `set -euo pipefail`; the static gate pins that
prelude for every root and `scripts/*.sh`. Rely on the options instead of probing dependencies: a
script that needs `godot` or `python3` calls it; `set -e` stops at the failing command and the shell
or tool prints the reason. A `command -v` guard is only for a failure that would otherwise continue
or act unsafely: the parse gate keeps its Godot probe so a missing interpreter cannot report a
false pass with an empty log, and `lab-vr.sh` keeps its Monado-service and runtime-manifest guards
because it starts that service itself and would otherwise run a VR lab without a runtime.

A script that must observe a failure captures the status at that call (`if cmd; then ...; else
status=$?; fi`) and keeps `-e`; it does not drop `-e` so a loop can continue. The gate runners read
a tool's output after an expected non-zero exit, so `scripts/check.sh` and `scripts/test.sh` allow
exactly that call (`|| true` or the if/else capture) and stay under `-e`.

The manual labs pick the session display driver: `DISPLAY_DRIVER` first, then Wayland when
`WAYLAND_DISPLAY` is set, else X11. `lab-vr.sh` additionally sets its own XR runtime. The labs rely
on `-e` for the Godot and asset checks instead of repeating a dependency probe.

More than 25 non-empty, non-comment lines is a smell: extract a shared prelude or move the logic
into the tool the script wraps. The threshold is a review prompt, not a gate.

## Pack report

`scripts/pack_report.py` reports what ships and how big it is. It is a report, not a gate: no gate
script runs it, and only `--strict` turns a pck diff into a failure. With no argument it reads the
source tree; `--pck FILE` reads a built pack's own directory, and there is no pack discovery. A
tree report counts source bytes; a pck report counts packed bytes, where imported textures and
audio appear as their imported artifacts.

Code lines still carry code after a comment is removed, so blank lines, `#`/`##` blocks and tail
comments do not count. Comment stripping is string-aware: `#` inside a string is data, and JSON
and shaders use `//` and `/* */` with the same awareness. The categories are gdscript, gdshader,
json, other, binary and sidecar; sizes are printed per category and as a binary and sidecar split,
and no other section repeats a size. `--min-lines`, `--top-json` and `--list-other` bound the
listings.

`--scope` chooses what a tree report counts: `shipped` (the manifest and asset contract's runtime
files), `non-shipped` (tracked but not packed) and `total` (both). A pck report diffs the entries
it reads against the manifest plus the imported artifacts and `mod.built.json`, printing the
missing and extra entries; `--strict` fails on drift and `--no-manifest` skips the diff.
`--format markdown` prints one value per cell for a job summary.

`--self-test` runs the parser fixtures, and the source-checks CI job runs it before the build so a
broken parser fails in seconds. The build job runs the pck report between `Build` and `Release` and
appends it to the run's job summary, so every run, release or not, shows the composition of the
pack it produced.
