# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file adds
the working knowledge for `unfplap` only. It holds project-wide rules and the service index; the
per-service contracts are under `docs/` and `docs/README.md` is their index.

## Required reading by task

Do not start implementation until you have read the required files for the area you are touching.

| Task | Read first |
|---|---|
| Any task | `res://mods/AGENTS.md`, then this file, then `WORKFLOW.md` |
| Documentation or a service boundary | `docs/README.md`, the owning service doc |
| Hands, caress or smack | `docs/hands.md` |
| Eligibility, consent, offer or relationship level | `docs/eligibility.md` |
| Scene gate, refusal, bed/player/navigator gate | `docs/scene_gate.md` |
| Act scene ownership, navigator, player lock | `docs/scene_hold.md` |
| Bed anchor, cuddle rejoin or post-act restore | `docs/rest.md` |
| Anatomy, player part, tail seat or dock | `docs/anatomy.md` |
| Proactive request, privacy, offer flow or consent classifier | `docs/initiation.md` |
| Act cue line, reaction or bystander line | `docs/lines.md` |
| Jiggle, smack impact, rump blush or climax hearts | `docs/reactions.md` |
| Standing footstool or stool supply | `docs/stool.md` |
| Readiness, preference or strength | `docs/readiness.md`, `docs/preferences.md` |
| Act summary, long-term history, reluctance | `docs/history.md` |
| Act face, mood or voice emotion | `docs/face.md` |
| Pose, skeleton, camera, act actions | `docs/poses.md`, `docs/camera.md` |
| Kiss | `docs/kiss.md` |
| VR act | `docs/vr.md` |
| Controls or features | `README.md` (edit only CONTROLS and FEATURES) |
| Setting, flag or debug control | `docs/settings.md` |
| Character profiles or preference | `docs/preferences.md`, `docs/settings.md` |
| Cross-mod API | `docs/api.md`, `api.gd`, `mare_registry.gd` |
| Act audio or sound assets | `docs/audio.md`, `AUDIO_CREDITS.md`, `assets/README.md`, `scripts/asset_pack.py` |
| Act HUD text or `End` tint | `docs/hud.md` |
| Debug actions, console or overlay | `docs/debug.md` |
| Perf probe | `docs/perf.md` |
| Release | `.opencode/skills/release/SKILL.md` |
| Sync local settings to shipped defaults | `.opencode/skills/sync-settings/SKILL.md` |

## Identity and scope

- Mod id `unfplap`; the current public version and target game are the `version` and
  `game_version` in `mod.json`.
- Adult mares only. Human Anon and AnonPony.
- All eligibility, consent, lover-bond and relationship-level gates are in `docs/eligibility.md`.
- Exactly two poses: `missionary` on a bed/couch and `standing` standing.
- No pregnancy, conception, content warning, new character or body models. Estrus is an optional,
  off-by-default cycle (`features.estrus_cycle`) that changes timing, willingness and dialogue
  only; it never adds pregnancy or a body model. The anatomy is an optional, feature-gated
  addition; it never replaces a pony's body or rig. The PPP anatomy meshes/textures and the act
  audio are fetched from one external resource pack before a build and packed with the mod; they
  are not tracked. The act stays off-camera by framing. Modelled accessories are allowed.
- Anatomy attaches to every adult identity with `pony_hips`, including mares added by other mods;
  the base-game roster is not an attachment whitelist. Tail seating follows the same rule. Acts
  still need the game's relationship runtime and adult bond.
- Desktop first. VR and seated VR are deferred except the optional standing VR act behind the
  anatomy master; desktop human Anon owns the free act camera.
- The user-facing summary is `README.md`. The per-system contracts are under `docs/`.

## Architecture: isolated systems

Unfplap is built from isolated systems. A system owns one responsibility and exposes it through
one mod-internal API; other systems talk to it only through that API.

| Part | Rule |
|---|---|
| `<system>.gd` | the facade: the only file another system may preload or call. It owns lifecycle and the system's stored state; in-system scene adapters are listed in the contract and only the facade calls them. |
| `<system>/` | private implementation: pure modules, paths, data and resources. Nothing outside the system preloads these files. |
| `docs/<system>.md` | the system's one technical contract. This file links to it and does not restate it. |
| `tests/<system>/` | the system's suites: pure core tests and facade/API tests stay separate. |

The facade's public methods are the system's **internal API**. This is not the cross-mod API:
`docs/api.md` and `api.gd` are the stable contract another mod may call. Internal APIs change
freely with the mod and are never added to `docs/api.md` by accident.

Rules:

- One responsibility per system. If the description needs "and", split it.
- The facade is the only scene adapter. It reads Nodes, `Settings`, the tree and the game, then
  passes plain values to pure modules. A pure module has no `Node`, `Time`, `SceneTree`,
  `FileAccess`, game scene preload or another system's facade.
- A system never reads another system's private fields, `_` helpers, child nodes or raw scene
  state. It calls the other facade, or receives the values it needs as arguments.
- Exchange values, not Nodes. Use a typed `RefCounted` context, a plain dictionary or a
  documented handle at the boundary. `runtime` is a caller, not a service locator.
- Dependencies point one way: system -> shared pure data (`settings`, `poses/catalog`, `cycle`,
  `preferences`) -> game. `main` and `runtime` compose systems and keep orchestration, state and
  ordering; they never hold a system's implementation.
- Every system ships its contract, its tests and its source-hygiene boundary in the same change
  that introduces it.
- Migrate one system at a time: extract the pure core, add the facade, route callers, move the
  tests and the contract, then delete the old path. No mixed-state commits.

A system is not the right unit for a tiny pure helper or a data table. `settings.gd`,
`poses/catalog.gd`, `preferences.gd`, `cycle.gd`, `anatomy_placement.gd`, `act_facts.gd` and
`perf.gd` stay shared pure modules; a system is for behavior with lifecycle, scene access or
stored state. A shared module still gets its own doc when it is a stable contract
(`docs/act_facts.md`, `docs/perf.md`).

### Services

The full table with facades, contracts and suites is `docs/README.md`. The quick index:

| System | Entry | Contract |
|---|---|---|
| Eligibility and consent | `eligibility.gd` | `docs/eligibility.md` |
| Scene gate and refusal | `scene_gate.gd` | `docs/scene_gate.md` |
| Act scene hold | `scene_hold.gd` | `docs/scene_hold.md` |
| Bed rest and cuddle rejoin | `rest_rejoin.gd` | `docs/rest.md` |
| Hands | `hand_control.gd` | `docs/hands.md` |
| Anatomy | `anatomy.gd` | `docs/anatomy.md` |
| VR act | `vr_act.gd` | `docs/vr.md` |
| Proactive requests | `initiation.gd` | `docs/initiation.md` |
| Act memory | `memory.gd` | `docs/memory.md` |
| Act lines and prompt notes | `act_lines.gd` | `docs/lines.md` |
| Readiness, strength and auto | `readiness.gd` | `docs/readiness.md` |
| Preferences | `preferences.gd`, `character_preferences.gd` | `docs/preferences.md` |
| Poses and skeleton | `poses/session.gd` | `docs/poses.md` |
| Act camera and shots | `act_camera.gd` | `docs/camera.md` |
| Kiss | `kiss_control.gd` | `docs/kiss.md` |
| History and tolerance | `history.gd` | `docs/history.md` |
| Afterglow | `afterglow.gd` | `docs/afterglow.md` |
| Face and mood | `face_session.gd` | `docs/face.md` |
| Reactions | `act_reactions.gd` | `docs/reactions.md` |
| Stool | `stool.gd` | `docs/stool.md` |
| Audio and voice | `act_audio.gd` | `docs/audio.md` |
| HUD | `hud.gd` | `docs/hud.md` |
| Settings | `settings.gd` | `docs/settings.md` |
| Lover bond | `sex_bond.gd` | `docs/bond.md` |
| Typed act view | `act_facts.gd` | `docs/act_facts.md` |
| Perf probe | `perf.gd` | `docs/perf.md` |
| Debug tooling | `debug_actions.gd`, `debug_skeleton.gd` | `docs/debug.md` |

`runtime.gd` is the per-pony act orchestrator: state machine, tick order, start sequence, the one
teardown ledger and the composition of service calls. It is not a system and has no `runtime/`
private directory. `main.gd` owns the mod entry, the per-pony runtimes, the settings tab injection
and the top-level services.

## Workflow

Read `WORKFLOW.md` before any task. Commit in small, testable units; never push.

Work the change in one batch:

- Settle the design before touching files. Once it is settled, apply every edit first, then run
  only the touched suites, then `scripts/test_all.sh` once. Do not re-run the full gate after each
  file.
- Use one whole-file write for a file that changes heavily, and send independent edits together in
  one turn. A chain of single-line edits costs a round trip each.
- Start a fresh session once the context has grown past a few hundred thousand tokens; carry a
  short plan forward instead of appending to a long conversation.
- A fresh checkout needs the external assets once (`scripts/fetch_assets.sh`), before source runs,
  tests, labs or builds. The script also accepts `--sources` for the V2 Blender file and `--force`
  to overwrite local changes.

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

Tests (manual, before every commit):

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

- `test_all.sh` runs every suite, prints each `RESULT` line and exits nonzero on any failure.
- `check.sh --all` parses every mod script. It is a quick subset of `test_all.sh`, not a
  replacement for the full gate.
- Build only when the user asks:
  ```bash
  ./build.sh [--out <file.pck>]
  ```
  Success prints `PACK_VERIFY`, `PCK_SHA256` and `MOD_BUILT <path>`. `build.sh` verifies the
  fetched runtime set with `scripts/asset_pack.py`, generates the required runtime list with
  `scripts/build_manifest.py`, and `pack.gd` requires the packed files to match it. Build from the
  git checkout with the fetched assets. A failed check removes the pack. The mod has no script
  extension.
- The PPP anatomy meshes, textures and act audio live in the external resource archive described
  by `scripts/asset_pack.json`; the V2 `mare_bits_v2.scn` variant is one of the eight required
  anatomy files. The V2 Blender source lives in `sources/anatomy/mare_bits_v2.blend`, is uploaded
  in the archive's `sources/` tree and is never packed.
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
  changes. No per-frame `Settings` reads in new code. `SETTINGS.block(prefix)` is the only bulk
  read.
- **No reach-ins.** A system must not preload `runtime.gd` or `main.gd`, and must not call
  `runtime.get("_…")` / `runtime.call("_…")`. Presentation modules read `act_facts.gd` or the
  owning facade.
- **No allocation churn.** Reuse `act_facts` and event dictionaries; do not allocate per frame in
  a facade.
- **No game-file edits and no JSON merges.** Everything lives under `res://mods/unfplap/`.
- **No new settings without a declaration.** One line in `settings.gd`, one typed read; see
  `docs/settings.md`.
- **Tests move with the code.** A change is not done while its suite reads the old private path,
  unless it is explicitly retargeted to the facade.
- **Build stays valid.** New `.gd` files must be tracked before a build; the pack manifest reads
  `git ls-files`.
- **Do not chase line count.** A correct service boundary is more important than the size of
  `runtime.gd`; report size only as information.
- **Performance check.** With **Enable debug** + **Print perf logs**, compare one act before and
  after a phase that touches the tick, the pose or the camera; the extracted chunks must not add a
  per-frame cost. See `docs/perf.md`.

## Documentation discipline

This is mandatory.

- Every service has exactly one doc under `docs/`, linked from `docs/README.md`. That doc is the
  single source of truth for the service's purpose, ownership, API, state, settings, controls,
  debug actions, dependencies, tests and lab check.
- `AGENTS.md` holds project-wide rules, the reading table and the service index. It links to the
  service docs and does not restate them.
- `docs/README.md` is the documentation index and the doc template.
- Root-level docs are for players and agents: `README.md`, `AGENTS.md`, `WORKFLOW.md`,
  `assets/README.md`, `AUDIO_CREDITS.md`. Service contracts do not live at the root.
- Update the owning doc in the same commit as behaviour, settings, controls, debug actions or
  tests. Remove obsolete claims instead of keeping historical notes.
- `README.md` rule: only update **CONTROLS** and **FEATURES** unless the user explicitly asks for
  another section. Do not list debug controls. Features are concise, high-level and one sentence
  each. Do not rewrite or reformat the rest of README.
- `docs/api.md` is the only cross-mod API contract. Internal service APIs never go there by
  accident.
- A system contract lives only in its owning doc. Other docs link to it and do not restate its
  paths, contact, settings or debug controls.
- A doc names settings and behaviour, not copied numeric defaults; the declaration in
  `settings.gd` is the source for the default and bounds.

## Settings authoring

The full contract is `docs/settings.md`. The short version:

- Add a setting with one declaration line in `settings.gd`, read it with its typed accessor, and
  run `scripts/test_all.sh`.
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
                    settings-tab injection, Characters preference editor, debug actions
  runtime.gd        per-pony act orchestrator: state machine, tick order, start,
                    teardown, service composition
  api.gd            stable cross-mod facade; docs/api.md
  mare_registry.gd  in-memory provider layers for modded and base-game mares
  settings.gd       every global setting declared once; docs/settings.md
  settings_ui.gd    the only file that builds settings widgets
  debug_actions.gd  Debug block actions and hotkeys; docs/debug.md
  hud.gd            the act card; docs/hud.md
  input.gd          Y start/end, smack routing, key consumption, action hotkeys
  docs/             one contract per service; docs/README.md is the index
  tests/            unit/source-hygiene tests and the manual labs
  scripts/          asset pack, build manifest, release checks, test runners
  assets/           fetched runtime assets and the asset-pack README
  poses/            skeleton driver, rig cache, recipes, authored pose, catalog
  anatomy/          anatomy internals, act bridge, tail seat
  hands/            caress, reach and smack internals
  stool/            the per-act stool handle and supply
  act_lines/        prompt formatting internals
  AUDIO_CREDITS.md  audio credits; ships
  README.md         player-facing CONTROLS and FEATURES
  WORKFLOW.md       commands, labs and release flow
```

The per-file service map with contracts and suites is `docs/README.md`.

## Known cross-cutting constraints

- The stock 0.3.0 bed is size-aware: `eligible()` accepts up to `1.05 * Settings.pony_scale()` and
  `_mare_fits` scales her half of the lane and her length with her size. A bed too short for a
  Hoers or Same Height mare is refused; that is stock behavior, not a mod override.
- `[go_to_bed]` keeps a `sleep:` navigator lease even while she lies awake by day. A bed-side offer
  through that lease is valid only for `bed_side`/`already_lying` when she is not sleeping and
  `posture_status().requested == "lie_down"`; walking to bed or sleeping is not. See
  `docs/eligibility.md`.
- "Same Height as Anon" follows Anon's `player/height_cm`. The mod's lean scale, standing gap and
  caress offsets follow the same multiplier; see `docs/hands.md`.
- Standing kiss offsets, the missionary virtual mouth and kiss lean distances scale with Anon's
  chosen height (`Settings.anon_height_scale()`), matching `player/player_mouth.gd`. See
  `docs/kiss.md`.
- `captions_on_top` is mod-owned: `main.gd` finds `SpeechCaption` through `Mods.on_node`, then
  moves its private `_card` to the top margin after the caption's own layout pass. It skips the
  settings-page preview and quietly does nothing if the card fields disappear.
- The stock bed captures a snuggle guest's rest transform at invite time from the player's
  reclined hip/head targets. Inviting before that blend settles puts the target at standing
  height, so `hop_clear` fails and the guest never climbs on. The lab waits `1.2 s` after lying
  down before inviting; the rejoin waits `CUDDLE_REJOIN_SETTLE_S`. See `docs/rest.md`.
- `SharedBed.accept()` is dead code in this game version: it calls `invite(actor, null)` and
  `invite()` rejects a null seat. Re-invite a mare into a bed with `invite(actor, seats[1])`.
- A mare from another mod needs the game's pony locomotion and hybrid rig: an adult identity, a
  stable id, `pony_hips` for the anatomy mesh, `MareBody` for teats/strip/body-coat deform, and
  `hair_skeleton` plus `OpenPonyDock` for tail seating. Acts still need the eligibility runtime
  described in `docs/eligibility.md`.
- The act's quick-slot inventory HUD is hidden for the whole act and restored on every exit path;
  see `docs/hud.md`.

## Debug and testing

- The backtick console is gated by `DEV.enabled()`; a player build unlocks it with **Settings →
  Updates** pressed five times. Acts own `controls_locked`, so it is not available during an act.
- The Debug block, actions, hotkeys, skeleton overlay and lab keys are in `docs/debug.md`.
- The perf probe is in `docs/perf.md`.
- Run the full gate and the phase's manual lab before a commit. If a lab cannot run in the current
  environment, say so in the phase notes rather than claiming it passed.
