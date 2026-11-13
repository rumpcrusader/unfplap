# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file adds
the working knowledge for `unfplap` only. It holds project-wide rules and the path router; the
concepts are in `ARCHITECTURE.md`, the service index is `docs/README.md`, and the per-service
contracts are under `docs/`.

## Required reading by path

Do not start implementation until you have read the owning doc for the files you will touch. The
table is the router: a doc not listed here is reached from `docs/README.md`, and this file does not
restate a contract.

| Paths | Read |
|---|---|
| `main.gd` | `ARCHITECTURE.md`, `docs/runtime.md` |
| `runtime.gd` | `docs/runtime.md` |
| `api.gd` | `docs/api.md` |
| `tests/**` | `docs/tests.md` |
| `shared/act_facts.gd` | `docs/act_facts.md` |
| `shared/act_face.gd` | `docs/face.md` |
| `shared/act_history.gd` | `docs/summary.md` |
| `shared/act_motion.gd` | `docs/camera.md` |
| `shared/anatomy_placement.gd` | `docs/anatomy.md` |
| `shared/character_preferences.gd`, `shared/preferences.gd` | `docs/preferences.md` |
| `shared/hands_*.gd` | `docs/hands.md` |
| `shared/perf.gd`, `shared/perf_idle.gd` | `docs/perf.md` |
| `shared/pose_catalog.gd` | `docs/poses.md` |
| `shared/relationship_cue.gd` | `docs/lines.md` |
| `shared/rump_cone.gd` | `docs/scene_gate.md` |
| `afterglow/**` | `docs/afterglow.md` |
| `anatomy/**` | `docs/anatomy.md` |
| `audio/**` | `docs/audio.md` |
| `camera/**` | `docs/camera.md` |
| `debug/**` | `docs/debug.md` |
| `eligibility/**` | `docs/eligibility.md` |
| `face/**` | `docs/face.md` |
| `hands/**` | `docs/hands.md` |
| `hud/**` | `docs/hud.md` |
| `initiation/**` | `docs/initiation.md` |
| `input/**` | `docs/input.md` |
| `kiss/**` | `docs/kiss.md` |
| `lines/**` | `docs/lines.md` |
| `memory/**` | `docs/memory.md` |
| `poses/**` | `docs/poses.md` |
| `reactions/**` | `docs/reactions.md` |
| `readiness/**` | `docs/readiness.md` |
| `registry/**` | `docs/registry.md` |
| `rest/**` | `docs/rest.md` |
| `scene_gate/**` | `docs/scene_gate.md` |
| `scene_hold/**` | `docs/scene_hold.md` |
| `settings/**` | `docs/settings.md` |
| `stool/**` | `docs/stool.md` |
| `summary/**` | `docs/summary.md` |
| `vr/**` | `docs/vr.md` |
| `assets/**`, `scripts/asset_pack*` | `assets/README.md`, `CREDITS.md` |
| any | `res://mods/AGENTS.md`, this file, `ARCHITECTURE.md`, `WORKFLOW.md` |

Non-code tasks:

| Task | Read |
|---|---|
| Architecture, boundary or dependency edge | `ARCHITECTURE.md`, `docs/README.md` |
| Release | `.opencode/skills/release/SKILL.md` |
| Sync local settings to shipped defaults | `.opencode/skills/sync-settings/SKILL.md` |
| Player-facing summary | `README.md` is human-owned; do not edit, report the change |

## Identity and scope

- Mod id `unfplap`; the current public version and target game are the `version` and
  `game_version` in `mod.json`.
- Adult mares only. Human Anon and AnonPony.
- All eligibility, consent and relationship-level gates are in `docs/eligibility.md`.
- Exactly two poses: `missionary` on a bed/couch and `standing` standing.
- No pregnancy, conception, content warning, new character or body models. Estrus is an optional,
  off-by-default cycle (`features.estrus_cycle`) that changes timing, willingness and dialogue
  only; it never adds pregnancy or a body model. The anatomy is an optional, feature-gated
  addition; it never replaces a pony's body or rig. The anatomy meshes/textures and the act
  audio are fetched from one external resource pack before a build and packed with the mod; they
  are not tracked and the mod does not run without them. The act stays off-camera by framing.
  Modelled accessories are allowed.
- Anatomy attaches to every adult identity with `pony_hips`, including mares added by other mods;
  the base-game roster is not an attachment whitelist. Tail seating follows the same rule. Acts
  still need the game's relationship runtime and adult bond.
- Desktop first. VR and seated VR are deferred except the optional standing VR act behind the
  anatomy master; desktop human Anon owns the free act camera.
- The user-facing summary is `README.md`. The per-system contracts are under `docs/`.

## Architecture: services

Read `ARCHITECTURE.md` before changing a service boundary. It defines the layers, the
`service_name/service.gd` layout, lifecycle ownership, typed boundaries, shared modules and the
enforcement gate.

The service index, facades, contracts and test paths are in `docs/README.md`; this file does not
duplicate the table. A service facade is the internal API. The stable external contract is `api.gd`
and `docs/api.md`; internal APIs never go there by accident.

Key project rules that apply to every change:

- one service owns one piece of mutable state and exposes it through `service_name/service.gd`;
- nothing outside the service imports its private files;
- a service never reads another service's private fields or calls its `_` helpers;
- services depend on other facades or `shared/` modules, not on a host dictionary service locator;
- `main.gd` and `runtime.gd` compose and order services; they do not implement their rules;
- `runtime._end_session` remains the only act exit path and the one teardown ledger;
- per-act services receive their values once per act and again on `apply_live_settings()`;
- no per-frame allocation in a facade or read model;
- no game-file edits and no JSON merges into game data.

Use `scripts/architecture.py --check` before the full gate when a change touches a facade, a
service directory, a shared module or a dependency edge.

## Workflow

Read `WORKFLOW.md` before any task. Commit in small, testable units; never push.

Work the change in one batch:

- Settle the design before touching files. Once it is settled, apply every edit first, then check
  the change. Gate once per task, not per commit: `scripts/test.sh <touched>` and
  `scripts/check.sh` before each commit, `scripts/test_all.sh` once when the task is done.
- Use one whole-file write for a file that changes heavily, and send independent edits together in
  one turn. A chain of single-line edits costs a round trip each.
- Start a fresh session once the context has grown past a few hundred thousand tokens; carry a
  short plan forward instead of appending to a long conversation.
- A fresh checkout needs the external assets once (`scripts/fetch_assets.sh`), before source runs,
  tests, labs or builds. The pack ships them and the mod requires them; there is no runtime
  fallback. The script also accepts `--sources` for the V2 Blender file and `--force` to overwrite
  local changes.

Run from source:

```bash
godot --xr-mode off --path <project> -- --mod-src unfplap
```

Manual lab:

```bash
./lab.sh
```

It runs the isolated `unfplap-test` world and writes the session to `last-run.log` beside the
script. `godot` must be on `PATH`. The lab's roster, spawn snapshot, population/pause rules, the
`Shift+[`/`Shift+]` mare cycle and the lab keys are in `docs/debug.md` and `WORKFLOW.md`.

Stress lab:

```bash
./lab-stress.sh
```

VR lab:

```bash
./lab-vr.sh [--no-service] [--vr-lab-autostart]
```

Touched suites, before each commit:

```bash
scripts/test.sh <suite>...
```

Every suite, once per task:

```bash
scripts/test_all.sh
```

Source smoke:

```bash
scripts/smoke.sh
```

Fast parse check for changed scripts:

```bash
scripts/check.sh
```

- `test.sh` runs the named suites, or every suite under a directory (`scripts/test.sh poses`), with
  each suite's own throwaway `user://` and the gate's own prechecks. `--list` prints the suites.
- `test_all.sh` runs every suite and ends in `TEST_ALL_PASS`.
- `check.sh --all` parses every mod script. It is a quick subset of the gate, not a replacement for
  it.
- Build only when the user asks:
  ```bash
  ./build.sh [--out <file.pck>]
  ```
  Success prints `PACK_VERIFY`, `PCK_SHA256` and `MOD_BUILT <path>`. `build.sh` verifies the
  fetched runtime set with `scripts/asset_pack.py`, generates the required runtime list with
  `scripts/build_manifest.py`, and `pack.gd` requires the packed files to match it. Build from the
  git checkout with the fetched assets. A failed check removes the pack. The mod has no script
  extension.
- The anatomy meshes, textures and act audio live in the external resource archive described by
  `scripts/asset_pack.json`; the mare bits mesh is one of the seven required anatomy files. The
  V2 Blender source lives in `sources/anatomy/mare_bits_v2.blend`, is uploaded in the archive's
  `sources/` tree and is never packed. They are required at runtime; see `CREDITS.md` for the
  sources.
- Change assets with `scripts/pack_assets.sh --upload`, then commit `scripts/asset_pack.json`. See
  `assets/README.md`.
- CI builds on pushes and pull requests; only a `v*` tag publishes a release. Release preparation,
  versioning, tagging and store steps are in the release skill.
- The official `tools/modding/build_mod.gd` command is not a release path: it ignores
  `.pckignore` and recurses the whole mod folder. Use `build.sh` for anything you ship.
- Do not leave a `.pck` in the source project's live mods folder while testing `--mod-src`; it
  shadows source edits.

## Cross-cutting invariants

- **Order is load-bearing.** `_physics_tick`, `_process_tick` (render-time pose write), the start
  sequence, `_end_session` and the impact fan-out keep their call order until a change deliberately
  moves one call.
- **One teardown.** `_end_session` stays in `runtime.gd` and is the only exit path;
  `tests/test_source_hygiene.gd` enforces one `_end_session`. Do not add a second exit sequence.
- **Settings snapshot.** Services receive values once per act; `apply_live_settings()` pushes
  changes. No per-frame `Settings` reads in new code. `SETTINGS.act_snapshot(pose_id)` is the only
  bulk read.
- **No reach-ins.** A system must not preload `runtime.gd` or `main.gd`, and must not call
  `runtime.get("_…")` / `runtime.call("_…")`. Presentation modules read `shared/act_facts.gd` or the
  owning facade.
- **No allocation churn.** Reuse `act_facts` and event dictionaries; do not allocate per frame in
  a facade.
- **No game-file edits and no JSON merges.** Everything lives under `res://mods/unfplap/`.
- **No new settings without a declaration.** One line in `settings/service.gd`, one typed read; see
  `docs/settings.md`.
- **Tests move with the code.** A change is not done while its suite reads the old private path,
  unless it is explicitly retargeted to the facade.
- **Build stays valid.** New `.gd` files must be tracked before a build; the pack manifest reads
  `git ls-files`.
- **Do not chase line count.** A correct service boundary is more important than the size of
  `runtime.gd`; report size only as information.
- **No global debug hotkeys.** `debug/service.gd` declares no hotkey; the game's dev keys
  (`F4` render breakdown, `F9` trace, `F10` FPS overlay, `F11` free camera) stay the game's. A
  debug action is a button in its Debug block.
- **Performance check.** With **Enable debug** + **Print perf logs**, compare one act and one idle
  window (outside an act) before and after a phase that touches the tick, the pose or the camera;
  the extracted chunks must not add a per-frame cost. See `docs/perf.md`.

## Documentation discipline

This is mandatory.

- Every service has exactly one doc under `docs/`, linked from `docs/README.md`. That doc is the
  single source of truth for the service's purpose, ownership, API, state, settings, controls,
  debug actions, dependencies, tests and lab check.
- `AGENTS.md` holds project-wide rules, the path router and the service index. It links to the
  service docs and does not restate them.
- `docs/README.md` is the documentation index and the doc template.
- Root-level docs are for players and agents: `README.md`, `AGENTS.md`, `WORKFLOW.md`,
  `assets/README.md`, `CREDITS.md`. Service contracts do not live at the root.
- Update the owning doc in the same commit as behaviour, settings, controls, debug actions or
  tests. Remove obsolete claims instead of keeping historical notes.
- `README.md` is human-owned. Do not edit it; report needed player-facing changes to the user
  instead.
- `docs/api.md` is the only cross-mod API contract. Internal service APIs never go there by
  accident.
- A system contract lives only in its owning doc. Other docs link to it and do not restate its
  paths, contact, settings or debug controls.
- A doc names settings and behaviour, not copied numeric defaults; the declaration in
  `settings/service.gd` is the source for the default and bounds.

## Settings authoring

The full contract is `docs/settings.md`. The short version:

- Add a setting with one declaration line in `settings/service.gd`, read it with its typed accessor, and
  run `scripts/test_all.sh`.
- A service contributes a setting by editing the central catalog literally and documenting the
  behavior in its own contract; there is no per-service settings module or registration list.
- Never add a widget, a default constant, a path-keyed read or a save function anywhere else.
- A group needs at least three related settings; otherwise leave `group` empty.
- A debug setting uses `.as_debug()` and is never clamped.
- A retired setting is one `deprecated()` entry; bump `SCHEMA_VERSION` only for a structural
  change.
- Do not add per-setting tests; `tests/test_settings.gd` is the API contract.
- Keep the feature-flag table in `docs/settings.md` current.

## Important files

```text
mods/unfplap/
  mod.json          id, version, game_version, entry
  changelog.txt     player-facing release history; ships in the pack
  main.gd           Mods hooks, runtime attachment, offers, HUD/input creation,
                    debug action implementations
  runtime.gd        per-pony act orchestrator: state machine, tick order, start,
                    teardown, service composition
  api.gd            stable cross-mod facade; docs/api.md
  registry/service.gd  in-memory provider layers for modded and base-game mares
  settings/service.gd       every global setting declared once; docs/settings.md
  settings/ui.gd    declaration rows, Debug block and settings-tab injection
  settings/characters_ui.gd  the interim Characters preference form
  debug/service.gd  Debug block actions; docs/debug.md
  debug/ui.gd       the Debug block's action buttons
  hud/service.gd            the act card; docs/hud.md
  input/service.gd          Y start/end, smack routing, key consumption
  docs/             one contract per service; docs/README.md is the index
  tests/            unit/source-hygiene tests and the manual labs
  scripts/          asset pack, build manifest, release checks, test runners
  assets/           fetched runtime media (audio/, anatomy/) and the asset-pack README
  sources/          editable originals; never tracked, never packed
  shared/           pure modules, shared stores and read models
  poses/            pose session, skeleton driver, rig cache, recipes, body adapters
  anatomy/          anatomy internals, act bridge, tail seat
  hands/            caress, reach and smack internals
  stool/            the per-act stool handle and supply
  lines/            line scheduler and prompt formatting internals
  <service>/        the remaining service facades and private internals
  CREDITS.md        external credits; ships
  README.md         player-facing summary; human-owned, do not edit
  WORKFLOW.md       commands, labs and release flow
```

The per-file service map with contracts and suites is `docs/README.md`.

## Debug and testing

- The backtick console is gated by `DEV.enabled()`; a player build unlocks it with **Settings →
  Updates** pressed five times. Acts own `controls_locked`, so it is not available during an act.
- The Debug block, actions, skeleton overlay and lab keys are in `docs/debug.md`.
- The perf probe is in `docs/perf.md`.
- Run the full gate and the phase's manual lab before a commit. If a lab cannot run in the current
  environment, say so in the phase notes rather than claiming it passed.
