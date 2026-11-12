# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file
adds the working knowledge for `unfplap` only. Keep it current; it is the source of truth for
agents, not a design diary.

## Required reading by task

Do not start implementation until you have read the required files for the area you are touching.

| Task | Read first |
|---|---|
| Any task | `res://mods/AGENTS.md`, then this file, then `WORKFLOW.md` |
| Any hands, caress or smack task | `docs/hands.md` |
| Any eligibility, consent, offer or relationship-level task | `docs/eligibility.md` |
| Any anatomy, player-part, tail-seat or dock task | `docs/anatomy.md` |
| Any proactive request, privacy, offer-flow or consent-classifier task | `docs/initiation.md` |
| Any standing footstool or stool-supply task | `docs/stool.md` |
| ACTIVE readiness, preference, strength | `PREFERENCES.md`, `thrust.gd`, `auto_thrust.gd`, `preferences.gd`, `utterance.gd`, `utterance_scheduler.gd` |
| Act summary, long-term history, reluctance | `HISTORY.md`, `preferences.gd`, `act_summary.gd`, `act_history.gd`, `runtime.gd` |
| Any act face, mood or voice emotion | `act_face.gd`, `mood_face.gd`, `runtime.gd` (`_act_face_beat`, `_eyes_tick`), `settings.gd` prompts |
| Pose, skeleton, camera, act actions | `ROTATION.md`, `poses/` |
| Controls or features | `README.md` (edit only CONTROLS and FEATURES) |
| Any setting, flag or debug control | `TUNING.md`, `settings.gd`, `settings_ui.gd` |
| Character profiles or preference | `character_preferences.gd`, `settings.gd`, `poses/catalog.gd`, `PREFERENCES.md` |
| Cross-mod API | `docs/api.md`, `api.gd`, `mare_registry.gd` |
| Act audio or sound assets | `act_audio.gd`, `act_sound.gd`, `audio/act/catalogue.gd`, `audio/act/smack/catalogue.gd`, `AUDIO_CREDITS.md`, `assets/README.md`, `scripts/asset_pack.py` |
| Release | `.opencode/skills/release/SKILL.md` |
| Sync local settings to shipped defaults | `.opencode/skills/sync-settings/SKILL.md` |

## Identity and scope

- Mod id `unfplap`; the current public version and target game are the `version` and
  `game_version` in `mod.json`.
- Adult mares only. Human Anon and AnonPony.
- All eligibility, consent, lover-bond and relationship-level gates are in `docs/eligibility.md`.
  That file is the single contract; do not restate its rules here.
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
- The user-facing summary is `README.md`. The per-system contracts are indexed in
  `## Architecture: isolated systems`.

## Architecture: isolated systems

Unfplap is built from isolated systems. A system owns one responsibility and exposes it through
one mod-internal API; other systems talk to it only through that API.

| Part | Rule |
|---|---|
| `<system>.gd` | the facade: the only file another system may preload or call. It owns lifecycle and the system's stored state; in-system scene adapters are listed in the contract and only the facade calls them. |
| `<system>/` | private implementation: pure modules, paths, data and resources. Nothing outside the system preloads these files. |
| `docs/<system>.md` | the system's one technical contract. `AGENTS.md` links to it and does not restate it. |
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
  `preferences`) -> game. `main` and `runtime` compose systems and
  keep orchestration, state and ordering; they never hold a system's implementation.
- One contract per system under `docs/`. `AGENTS.md` holds project-wide rules and the index only.
- Every system ships its contract, its tests and its source-hygiene boundary in the same change
  that introduces it.
- Migrate one system at a time: extract the pure core, add the facade, route callers, move the
  tests and the contract, then delete the old path. No mixed-state commits.

A system is not the right unit for a tiny pure helper or a data table. `settings.gd`,
`poses/catalog.gd`, `preferences.gd`, `cycle.gd` and `anatomy_placement.gd` stay shared pure
modules; a system is for behavior with lifecycle, scene access or stored state.

### Systems

| System | Entry | Contract | Status |
|---|---|---|---|
| Eligibility and consent | `eligibility.gd` | `docs/eligibility.md` | migrated |
| Hands | `hand_control.gd` | `docs/hands.md` | migrated; facade still reads host state |
| Anatomy | `anatomy.gd` | `docs/anatomy.md` | migrated |
| Proactive requests | `initiation.gd` | `docs/initiation.md` | migrated |
| Act memory and lines | `memory.gd` | `docs/memory.md` | migrated |
| Footstool | `stool.gd` | `docs/stool.md` | new; facade owns the supplied world drops |
| Poses and cameras | `poses/skeleton_pose.gd` | `ROTATION.md` | partial |
| Act readiness and thrust | `thrust.gd` | `PREFERENCES.md` | pure core; runtime hosts the act |
| Act summary and history | `act_summary.gd` | `HISTORY.md` | partial |
| Cross-mod API | `api.gd` | `docs/api.md` | stable |

Hands, eligibility, anatomy, initiation and memory use `tests/<system>/`. The remaining suites are
still flat (`tests/test_*.gd`) and move when their system is next touched.

### Docs

| Doc | Owns |
|---|---|
| `docs/api.md` | cross-mod API only |
| `docs/eligibility.md` | eligibility and consent |
| `docs/hands.md` | hands, caress and smack |
| `docs/anatomy.md` | anatomy, player part and tail seating |
| `docs/initiation.md` | proactive requests, privacy, consent classification |
| `docs/memory.md` | act memory, witnesses, peak memory and the mod's own line channel |
| `docs/stool.md` | standing footstool rule, act prop and world supply |
| `ROTATION.md` | pose, skeleton and camera |
| `PREFERENCES.md` | readiness, preference and strength |
| `HISTORY.md` | act summary and long-term history |
| `TUNING.md` | settings framework |
| `WORKFLOW.md` | commands, lab and release flow |

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

A fresh checkout needs the external assets once (`scripts/fetch_assets.sh`), before source runs,
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
script. `godot` must be on `PATH`.

- The lab starts with only Twilight, Fluttershy, Rarity, Derpy, Applejack, Tempest Shadow, Lily
  Valley and Colgate, pauses world scheduling and background AI, and uses the Golden Oak guest
  bed. It does not spawn a test bed. Applejack starts as a stranger: friendship 0, no romance
  tier and no dating record.
- Before the loading screen's furnishing wait the lab sets `furnish = false` on every generated
  house. Authored homes (the library) keep their furniture and bed, so the 200 ms-per-house
  furnishing stagger never runs.
- `worlds/unfplap-test/` is the isolated lab world; `worlds/default/` is untouched. Delete only
  the test world to reset it.
- The lab re-seeds its eight test ponies on every startup (friendship and mood, idle posture;
  romance tier and dating record only for the adults that are not strangers). Each pony is moved
  to the position and yaw in `TEST_SPAWNS` (`tests/test_lab.gd`), a snapshot of the world save
  from 2026-11-07 20:53, so she stands where the last session left her; a pony with no snapshot
  row falls back to the library row (`_place_front`, or `_place_stranger` for a stranger). A
  downward raycast snaps her to the floor only when the hit is within `0.6 m` of the saved
  height, so a roof above the spot cannot lift her. Before the loading screen spawns the town,
  the in-memory population config assigns every missing test pony to Ponyville, then removes all
  other residents; `population.json` is not saved. It also lifts the player's Max nearby ponies
  cap in memory for the loading screen (a value of four would leave a test pony out) and restores
  it once population is paused. A test pony whose home sits beyond the 240 m activation radius
  gets a session-only saved spawn at the library front. The rest of the world's context and
  inventory persist.
- `Shift+[` / `Shift+]` cycles every adult mare the population catalogue can spawn. The eight
  starters stay live and the previous starter returns to her saved spot; a non-starter is
  spawned through the population streamer on demand, made idle in front of Anon in a 3/4 rear
  view (slightly to his right and turned 35°), and the previous non-starter is despawned before
  the next one loads, so only one extra stays live. The streamer is paused, so the lab ticks its
  `reconcile()` by hand and removes the extra's in-memory assignment when she leaves. The keys
  work with the mouse released and while the settings/pause menu is open (the posture settles when
  it closes), but not while a text field owns the keyboard; `Ctrl+[` / `Ctrl+]` is kept as an
  alias where the bracket key arrives (on many systems Ctrl+[ is the historical Escape control
  code and never reaches the game).
- The lab normalizes a mare's saved actor rotation to yaw-only in `_upright()` during setup and
  after bed transport. A tilted saved transform otherwise makes support recovery fight the
  collider every frame and print endless `re-seated on the floor` lines.

Stress lab:

```bash
./lab-stress.sh
```

- Uses the separate `unfplap-stress` world and writes `last-run-stress.log`.
- Forces every stress ID into Ponyville for the session and gives every non-live id a
  session-only spawn on a 3.2 m grid in front of Golden Oak Library. The final line is 0.8 m
  apart; the wider pre-spawn grid is what the base spawner's 3 m separation check accepts.
- Spawns every ID in `SETTINGS.CHARACTER_ORDER` that the population catalogue can create, in one
  line in front of Golden Oak Library, all facing away from the building and standing idle after
  the teleport. That roster excludes the profile-marked schoolfilly/stallion entries (Twist,
  Fiddly Twang) and includes the adult specials (Sunset Shimmer).
- Reuses the normal lab's world loading, pause and idle setup; it does not use the five-mare
  roster or the library bed.
- Life, needs, schedulers and time pause as soon as the loading screen ends; population keeps
  running until the whole roster is live, then it pauses too. A 60 s no-progress watchdog lists
  the missing ids and proceeds instead of waiting the full 420 s in silence.
- It logs the target count, the anatomy/action flags, missing mares and each placement. Use it
  with **Enable debug** and **Print perf logs** on for the anatomy stress pass.

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
  The printed output is the current state; do not copy counts into docs.
- `check.sh --all` parses every mod script. It is a quick subset of `test_all.sh`, not a
  replacement for the full gate.
- Build only when the user asks:
  ```bash
  ./build.sh [--out <file.pck>]
  ```
  Success prints `PACK_VERIFY`, `PCK_SHA256` and `MOD_BUILT <path>`. `build.sh` verifies the
  fetched runtime set with `scripts/asset_pack.py`, generates the required runtime list with
  `scripts/build_manifest.py`, and `pack.gd` requires the packed files to match it, rejects
  development files, rejects broken `.import` data and writes a `.sha256` beside the pck. The
  manifest reads `git ls-files` plus the resource contract, so build from the git checkout with the
  fetched assets. A failed check removes the pack. The mod has no script extension.
- The PPP anatomy meshes, textures and act audio live in the external resource archive described
  by `scripts/asset_pack.json`; the V2 `mare_bits_v2.scn` variant is one of the eight required
  anatomy files. The V2 Blender source lives in `sources/anatomy/mare_bits_v2.blend`, is uploaded
  in the archive's `sources/` tree and is never packed. Every build includes the runtime assets.
- Change assets with `scripts/pack_assets.sh --upload`, then commit `scripts/asset_pack.json`. The
  archive is one combined runtime/source zip; `runtime/` goes into the pack and `sources/` does
  not. An unchanged asset set reuses the committed URL and hash. See `assets/README.md`.
- `build.sh` stages only the runtime tree selected by `.pckignore`, imports the assets, packs the
  `.import` sidecars and verifies the result. Repository docs, tests, scripts, tools, skills and
  `.git` do not ship; `AUDIO_CREDITS.md` and `changelog.txt` do.
- CI builds on pushes and pull requests; only a `v*` tag publishes a release. Release preparation,
  versioning, tagging and store steps are in the release skill, not here.
- The official `tools/modding/build_mod.gd` command is not a release path: it ignores
  `.pckignore` and recurses the whole mod folder, including `.git`, `.godot`, `dist/`, `sources/`
  and local-only assets. Use `build.sh` for anything you ship.
- Do not leave a `.pck` in the source project's live mods folder while testing `--mod-src`; it
  shadows source edits.

## Important files

```text
mods/unfplap/
  mod.json          id, version, game_version, entry
  changelog.txt     player-facing release history; ships in the pack
  main.gd           Mods hooks, runtime attachment, offers, HUD/input creation,
                    settings-tab injection with guard, Characters preference editor, debug actions,
                    skeleton debug helper
  runtime.gd        per-pony state machine, scene gate composition, start,
                    ACTIVE readiness/talk, act camera lean, pose actions/smack,
                    act face beats, climax, afterglow/close window, restore,
                    bed cuddle rejoin, aftercare
  eligibility.gd    internal eligibility API and the only scene adapter; see
                    docs/eligibility.md
  anatomy.gd        world facade: per-pony controllers, player part, tail seat/visibility and
                    placement editor; contract in `docs/anatomy.md`
  anatomy/controller.gd  persistent per-mare shell: placement, shapes, coat, appearance and
                    heat forwards; owns the act lifecycle; attach/visibility/fluid in
                    `anatomy/attach.gd`
  anatomy/attach.gd persistent mesh/anchor/dock, visibility, dock restore, fluid and idle discharge
  anatomy/facts.gd  typed runtime context: state, pose, depth, bed frame, cycle and callbacks
  anatomy/coat_follow.gd  sampled body-coat leg weights and the per-frame pelvis-relative
                    anatomy shell matrices
  anatomy/          identity, geometry, shapes, coat, coat follow, appearance, heat, facts, attach,
                    placement; act state and oral/finish/debug; player part; fluid, teats, still
                    zones and the anatomy shader
  anatomy/act.gd    per-act hole/oral/finish, shape driving, winking, fluid and pose keys; reads
                    the typed `anatomy/facts.gd` context and returns pose/facing values
  anatomy/player.gd player anatomy mesh, placement, girth/head/length shaping and throb;
                    `player_prepare()` builds it hidden for the footstool measurement
  anatomy_placement.gd  shared pure placement schema, shipped per-mare defaults and migration
  stool.gd          footstool facade: reach rule, case item, act prop and world supply
  stool/            pure gap/item helpers, the static act prop and the house supply
  docs/stool.md     standing footstool contract; never packed
  missionary_anon.gd the act's Anon body, placed in bed space and posed from the asset, with the
                    caress hand hold and shared two-bone palm solve
  consent.gd        pure per-mare public/anal/oral defaults and merge; a
                    dependency of the eligibility API, not a gate by itself
  participation.gd  pure per-mare capability layer (acts, anatomy, tail); a
                    subtractive opt-out, not a gate by itself
  vr_act.gd         optional VR standing act; last and gated by the anatomy master
  thrust.gd         pure stroke tracker: reversal hysteresis, timeout, travel, speed, strength,
                    and the bottom-of-stroke impact event
  auto_thrust.gd    pure auto-thrust depth generator: pace, band, stroke shape
  auto_panel.gd     pure hold-X auto settings layer: tap toggle, hold, grace, key repeats
  preferences.gd    pure preference profile, intensity/rhythm and talk classification
  cycle.gd          pure per-mare estrus phase: heat, diestrus, normal; idle wink burst roll
  settings.gd       every global setting declared once, the typed accessors, the settings file and
                    the per-mare profiles
  settings_ui.gd    the only file that builds settings widgets: declaration rows as the page's rows
  debug_actions.gd  the Debug block's action buttons and their hotkeys
  utterance.gd      pure prompt formatting
  utterance_scheduler.gd  pure cue selection and line admission: stability, gaps, demand
                    budget, one slot for cues and reactions
  relationship_cue.gd pure relationship/tone formatting and peak-memory gate
  act_motion.gd    pure lean travel/step, pose action, glance fade and hip smoothing
  hand_control.gd  act hand controller: caress, reach and smack; details in docs/hands.md
  hands/            placement engine, paths, marked area data, anchors, contact, palm, reach, scale and smack; docs/hands.md
  kiss_control.gd   missionary/standing kiss, base AffectionPose bridge and foreleg pin
  missionary_camera.gd  authored shot blend, live aim, free look, avatar hiding and start snapshot
  standing_camera.gd  standing look, glance, facing lock and camera offsets
  standing_anon.gd  standing hip thrust wrapper, planted lower body and palm scale
  standing_presentation.gd  idle standing invitation, turn and request face
  anon_thrust.gd    wraps the desktop Anon pose driver for the standing hip thrust
  hands/scale.gd     shared caress hand-bone scale, restored when the act ends
  body_sway.gd      depth-driven standing body sway with planted hooves and Anon follow
  kiss_legs.gd      standing kiss hoof-tip pin after AffectionPose's chest flex
  prone_sway.gd     missionary lying torso slide and head nod on the thrust
  ear_twitch.gd     eased random thrust ear twitch on the head skeleton
  wing_control.gd   wing hold/spread/flutter, afterglow fold and wing-sweep lifetime
  wing_sweep.gd     standing wing root sweep after the game's WingTuck modifier
  chin_debug.gd     debug head-pitch skeleton modifier
  debug_skeleton.gd F10 skeleton line/circle overlay with hover and joint inspection
  voice_status.gd   pure character-voice/Ponese classification
  act_sound.gd      base-game breath and climax players
  act_audio.gd      pack foley/vocal/wet layers
  act_summary.gd    pure per-act action checklist, grade, reward and summary text
  act_history.gd    per-mare hurt/comfort, tiers, offer weight, prompts and repair
  act_tolerance.gd  pure per-act distress, warning stages and stop thresholds
  audio/act/smack/  fetched OpenNSFW hand-smack variants installed on FlankTouch
  poses/            skeleton driver, rig cache, rotation helpers, recipes, catalog
  poses/authored_pose.gd  bed-space loader for the hand-authored missionary base pose
  poses/missionary_pose.json  the authored pose; exported from the pose lab, never hand-edited
  hud.gd            bottom-left controls list, combined status line, readiness line, close cue
                    and afterglow summary
  input.gd          Y start/end, right-click smack routing, key consumption, action hotkeys
  settings.gd       settings.json IO and cache, legacy migration, provider and per-character merge
  api.gd            stable cross-mod facade; see docs/api.md
  mare_registry.gd  in-memory provider layers for modded and base-game mare templates
  character_preferences.gd  display names, selector order and every spawnable mare's preference
  memory.gd         act memory facade: world_context events, grade-aware impression,
                    peak memory, witnesses, cue facts and the mod's own line channel;
                    contract in docs/memory.md
  memory/           pure text/facts and the world, dialogue, perception and store adapters
  rest_control.gd   release pony_seating and shared_bed/couch without standing
  aftercare.gd      10 s post-act tail-up/flick, navigator hold, sex_aftercare gate
  act_face.gd       pure act face beats, live climax style, blush levels and prompt hints
  mood_face.gd      300 s post-act base-game mood face, light blush, yields to line faces
  tail_pose.gd      tail aside/lift/flick + thrust jiggle on the hair skeleton
  tail_tuck.gd      20 s tucked-tail posture hinged at mTail1 after a partner stop; no nav hold
  anatomy/tail/     tail seat, dock skin/seat, debug tail hide/visibility; contract in
                    docs/anatomy.md
  initiation.gd     proactive requests service (facade and `initiation/` internals);
                    contract in `docs/initiation.md`
  consent_classifier.gd  one shared classifier client/queue for offer and lover dialogue
  dialogue_consent.gd    lover-bond accept, decline and withdrawal from player dialogue
  sex_bond.gd       per-world lover-bond storage and stage maintenance; gate
                    policy is in docs/eligibility.md
  HISTORY.md        act score, history points, tiers, offer weighting and repair contract
  scripts/          asset_pack.py (pack/fetch/verify the resource archive), pack_assets.sh,
                    fetch_assets.sh, asset_pack.json (committed URL/hash/manifest),
                    build_manifest.py, prepare_release.sh, check_release.sh,
                    check_release_metadata.py and other scripts
  assets/README.md  resource-pack layout and asset-change workflow; never packed
  .opencode/        release and sync-settings skills/commands; never packed
  tests/            unit/source-hygiene tests + manual test_lab.gd
  PREFERENCES.md    preference/readiness/strength contract
  ROTATION.md       pose, skeleton and camera positioning contract
  docs/api.md       cross-mod API contract; never packed
  docs/eligibility.md  eligibility and consent contract; never packed
  docs/hands.md     hands, caress and smack contract; never packed
  docs/anatomy.md   anatomy, player part and tail seating contract; never packed
```

Entry script only. No script extensions, game-file edits or JSON merges. The bed-size extension
was removed after the 0.3.0 stock bed made its eligibility and approach rules size-aware; release
builds ship compiled `.gdc` scripts that the mod loader cannot subclass anyway.

## Critical: poses and skeleton work

Read `poses/` and `ROTATION.md` before changing a pose. Rotate bones, never stretch them, and do
not leave the pony outside her joint limits. Use `pose_rig.gd` for the bone cache and
body-relative axes.

### Missionary

The pose **is** `poses/missionary_pose.json`, placed in the real bed's space, with the nuzzle and
gaze overlays on top. There is no correction stack and no second pose: the act's `pose_asset` gate
refuses the start (no Y hint) with `missionary pose unavailable: <reason>` when the asset cannot be
loaded.

**The act is its own state.** Neither of them is in the game's lying state while it runs: Anon is
stood up (`force_stand_up()` before the snapshot and the lock), the game's desktop presentation is
parked, and his own `AnonBody` is placed in bed space and posed from the asset's `anon` block by
`missionary_anon.gd`; the attached alignment's `hip_offset_wanted` moves only his pelvis, so his
pelvis rides the stroke and the shaft stays in his crotch (the same `_aim_attached()` logic the
standing act uses). She is released
from the bed rest and asked to `stand`, so the solver keeps a neutral pose instead of the lie clip;
her body is placed and posed by the act. The bed supplies only
the frame (`bed_frame`) and the offer/eligibility path. The end restores the scene
(`restore_scene()`: player, pony and camera) and stands her; a normal end of a bed act then returns
to the cuddle (`_rejoin_bed_cuddle()`): Anon sits back on the bed's player seat and lies back, and
she is invited into its guest seat, where the stock `CuddleSession` picks her up. A forced stop, a
bad summary or a stock closeness refusal leaves her standing. The snapshot is
re-read at ACTIVE (`resnapshot()`): at `prepare()` it catches him mid stand-up, and restoring that
reclined eye height left the camera wrong after the act.

- The asset is bed-space data: origin at the middle of the mattress top, the bed's axes, `+Z` her
  head direction. `poses/authored_pose.gd` maps it onto the real bed with
  `bed_frame = Transform3D(bed basis * Basis(UP, PI), Vector3(bed x, drawn mattress top, bed z))`
  and places `bed_frame * (pony_frame × body_scale)`.
- **The bed frame follows the bed.** `_bed_pose_frame` is updated each tick by the bed's rigid
  delta, so a moving bed (the Cloudominium's CloudDrift) carries the authored pose, the act body and
  the shot. The snapshot stores the bed transform, and `restore_scene()` applies the same delta to
  the player, pony and camera so the cuddle rejoin starts beside the current bed.
- **The act owns the render.** The game re-poses the rig after our modifier pass (the clip tier's
  `enter`/`leave`, the posture, the terrain solver), so the runtime runs the same recipe again from
  `_process` after every other writer: `skeleton_pose.apply_render()`, same weight, no ramp or clock
  advance. The physics-pass write stays for the game's own contacts and pose layers.
- Only the body bones in `PONY_BONES` and the skeleton root are written. The actor node is never
  moved, so the capsule, bed support and posture recovery are untouched. The head bone, lids, eyes,
  ears, wings, feathers, mane and tail are never baked; the game and the act own them.
- The file must carry **all 30** body bones, rest bones included: the runtime writes only what it
  holds and never resets the rig, so a missing bone keeps the game's pose and breaks its chain (that
  was the v5 bug; `MIN_VERSION` is 6). The lab reads bed-space transforms for every file from
  `BED_SPACE_VERSION` 4 up, never tied to the current version.
- **Own the scale too.** `FillyProportions` and the hiders *multiply* the pose scale every pass and
  rely on the animation to reset it; the act must write the rest scale for every bone it poses, or the
  factor compounds (0.92^N collapses, >1^N explodes) and the body stretches to `inf`.
- **Never invert a scaled parent basis.** The stock hiders collapse a bone by scaling it to `0.001`,
  and `set_bone_global_pose()` inverts the parent's full basis on every write — a 1000× multiplier
  that compounds until the pose is `inf` (the body pulled away, then flickering; the anatomy part
  follows). Every act write goes through `pose_rig.set_global()`, which uses the parent's
  **orthonormalized** rotation and origin only and rejects non-finite targets. The hiders stay on;
  only `BodyIK` (the standing pose driver) is parked for the act.
- **Anon's own process is parked.** `missionary_anon.install()` stops `AnonBody._process`: it drives
  `LegHide` from the mattress-height act camera (the eye reads as `seated`, so the legs collapse),
  rewrites the authored fingers every frame (`_update_fists`), and feeds `model_scale` from that
  camera. `LegHide.influence` is zeroed for the act (the modifier stays active), the desktop pose
  driver is nulled and the desktop presentation's `advance()` is stopped, so only the act writes his
  bones. The skeleton and its other modifiers keep updating.
- **The head mesh is never hidden.** `head_smd` holds the head **and the hands**; hiding it removes
  the palms. The game's `HeadHide` collapses only the head bone. `apply()` caches the authored eye
  after the bone write and the lean, before `HeadHide` runs, so `eye_transform()` never reads the
  collapsed bone.
- **His palms are planted.** `_place_hands()` keeps both wrists at the authored world height while
  their X/Z follow the stroke and lean, so the hands slide along the mattress instead of lifting; a
  two-bone arm solve reaches the wrist and the hand keeps its authored world orientation, so the
  palms stay flat.
- **The caress.** Both hands use the shared caress system; see `docs/hands.md`. The pose only
  supplies the missionary path and the bed-space palm holder on `missionary_anon.gd`.
- **Her tail is laid on the bed.** The hair tail is not in the authored body pose: every tail rig
  differs. `tail_lay.gd` is installed on the hair skeleton for the missionary act and turns whichever
  `mTail1..6` bones exist onto the bed plane toward her rump, straightening the chain; the root stays
  where the rig put it. The chain's pre-act local poses are restored before the modifier is freed, so
  the game's own tail motion resumes from the normal pose. The same restore runs for the standing
  tail and its post-stop tuck.
- **The exit restores the avatar.** The act writes his world placement every frame; `remove()` puts
  back `avatar.transform`, its process state, `process_mode`, visibility, the pose driver, `BodyIK`,
  the `LegHide` influence and **every bone's pre-act local transform**. The authored pose keeps
  deliberately stretched bone positions; the game re-poses rotations but not every position, so
  restoring the whole bone snapshot is what keeps his limbs from staying stretched outside the act.
- **The player part is fully reset.** `anon_part.encounter(true)` and `encounter(false)` both call
  `reset_state()`: parent/home, base placement, aim normal/opening/pitch, both hip offsets, the
  smoothed penetration seed, bend/squash, shader squish/compress, throb and the ready tween. A
  following standing act or carry therefore never inherits the missionary part's transform or
  pelvis offset.
- **The pony gets a bone snapshot too.** `_snapshot_pony_bones()` saves every body and hair skeleton
  local pose at act start; `_restore_pony_bones()` puts them back after `_free_pose()`, before the
  game's animation re-poses her, so an act scale/position cannot survive as a zeroed or stretched
  bone.
- **Space rule.** Rotate a bone by writing its **global pose** with the axis converted once into
  skeleton space (`pose_rig.rotate_free`). Pre-multiplying the *local* pose applies the axis in the
  parent's frame; his hips are rotated about 90° in this pose, and that made the W/S lean yaw the
  view sideways instead of nodding it.
- Body bones carry a rotation **and** a position, and both are applied: a lengthened neck or a
  displaced flank root can be deliberate. Only the root carries the absolute placement.
- The head bone is reset to rest; the gaze solve owns the face. The pose lab has no head mesh, so
  baked head rotations are rejected.
- The overlays use `rig.rotate_free` on this path: the authored pose can sit outside the joint
  limits the game derives from its own motion library, and `constrain()` would snap it back.
- No asset, a version below 6 or no bed frame applies no pose at all: the `pose_asset` gate refuses
  the act start and logs the reason. The `pose_rig` gate refuses it when the live rig is missing
  any authored body bone, naming the first few. The old stack keys
  `pelvis_curl_deg`/`legs_wrap`/`bed_lift_m` are gone.
- The shot's camera positions and the body are both bed-relative, so they move together on any bed.
- The pose is authored at canon size. The placement scales its origin and basis by `body_scale`, so
  the rig's own pivot scale makes it a uniform scale about the mattress centre: Canon, JRHNBR, Same
  Height and the stallion multiplier all work. Hoers is untested.
- The JSON is exported, never hand-edited: pose `tools/pose_lab.tscn` in the editor, save the
  scene, then **Save pose** (or run `tools/pose_export.gd` headless). The exporter also checks a
  load round trip and the runtime application path, and `tools/` never ships. The lab's
  **Preview size** scales the pony, the Anons and the shot cameras about the mattress centre the
  way the runtime scales the body, so a JRHNBR or Same Height body can be inspected; **Save pose**
  refuses while it is not 1, so the JSON stays canon.
- The act's shot transforms are authored in the same scene: `ShotStart` (neutral), `ShotBack` (S),
  `ShotFront` (W), `ShotLeft` and `ShotRight`. Their bed-relative **position and direction** are
  exported: a pure axis lean meets the authored transform exactly, and everything between is
  interpolated. The lab's **Add shot cameras** button creates a first guess for any that are
  missing; a missing shot falls back to a fixed bed-relative point aimed at her live face.
- **The scene stores only the rig roots and the shot cameras.** Godot discards instance-child
  overrides when it saves a scene, so the pose is never stored in `pose_lab.tscn`; opening it always
  applies `poses/missionary_pose.json` (pose and shot positions). **Save pose** is what writes the
  JSON back, and it refuses to write an empty pose. Save the scene only when adding or removing
  nodes.

### Overlays and bed context

- `_aim_gaze()` is a true shortest-arc solve from her current face direction to Anon, using the
  current `pony_head` frame plus `HybridNeckLink`'s fixed `pony_head → mHead` offset. Do not
  replace it with absolute yaw/pitch from the body axis: that assumed a standing rest
  orientation and left the missionary head aimed at the ceiling. The nuzzle offsets the target
  by a few degrees rather than adding a second absolute aim.
- After the aim, `_level_head()` rolls the neck chain about its own forward (shares 0.30/0.36/0.34,
  so no single joint kinks) until her up matches the world's: the aim only sets the face direction,
  and a pose that rolls the neck otherwise leaves her looking at Anon sideways. The settled dump
  prints `head aim=…° roll=…°` and `body up=…°` (pelvis up against the world up), so a sideways gaze
  or a rolled pose is measurable.
- `MISSIONARY_RUMP_DROP_DEG` pitches the whole body about the shoulders; `MISSIONARY_HIND_SPREAD` sets
  hind-leg spread.
- Bed context is not optional: the lie pose, mattress surface and shared-bed transform all
  affect the result. The floating pose preview has no lie pose, so use the lab bed for the real
  check.
- The act bed is resolved through `main.real_bed()`. A cuddling `SharedTorsoSupport` is a
  temporary child of the bed with `soft_support`; using it as the bed leaves the act holding a
  freed node once the cuddle ends, which makes the anchor, camera and pose fall back differently
  on every bed. `real_bed()` walks to the actual `mattress_top` bed (or the support's parent).
- Do not disable or ignore the bed's collider while the missionary act runs. The game's posture
  uses it for `_measure_soft()`, `soft_sink`, support recovery and Anon's seat; collision
  exceptions let her sink and trigger the fall/re-seat loop. The bed anchor fix above is the
  supported way to keep the pose stable.
- Start waits for player rest ≥ 0.99 and the pony's `lie_down` to settle.

### Tail seating

The reference seat, dock skin, per-mare placement and debug actions are in `docs/anatomy.md`.

### Standing

- Stance: `STANDING_BOW = 2.4`, `STANDING_FORELEG = 2.0`,
  `STANDING_FORELEG_SPREAD = 0.172`, `STANDING_HIND_SPREAD = 0.32`.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`.
- A live reach gap over `presentation.standing.stool_gap_m` needs enough `goods:footstool`
  stacks of `presentation.standing.stool_height_m`; the rule, prop and supply are in
  `docs/stool.md`.
- Body facing is locked every physics tick at priority 100; the navigator must not turn her.
  `stay()` alone does not stop conversation facing, so `face_point` and the conversation target
  are cleared late each tick and `face_turn_rate` is held at `0` for the act. This stops the
  player-conversation turn steps without pausing locomotion or emotions. Conversation is also
  not an interruption: `_check_running()` does not stop for it, and `_keep_act_attention()`
  clears her listener every tick, so another character addressing Anon can talk while the act
  keeps running.
- The player's lower body stays planted during a forward or kiss lean: the hip is counter-shifted
  and both foot targets are captured and held at their neutral transforms until the lean/kiss
  ends.
- Glances use `pony.secondary.look_toward` plus optional `head_back`; pupils follow Anon through
  `eye_motion.target_world`. A full forward `W` lean with no side lean forces `head_back = 1.0`
  and the upward look toward Anon instead of waiting for the random glance scheduler.
- Tail aside/lift/flick is applied down the hair chain; the side is randomized per act.
  `presentation.standing.tail.yaw_deg` (default `35°`) and `pitch_deg` (default `25°`) set
  how far it sweeps aside and lifts, in degrees, and apply live through
  `_sync_standing_pose_config()`; the tail modifier is created from that pose config.
- Standing enters the same held `AFTERGLOW` state when the player chooses it or the configured
  pony climax limit forces it. Lean and A/D caress stay live there; hold Y ends it. Her tail lifts and
  flicks twice. Normal dialogue resumes; a live `pony_prompt_notes` line keeps the just-intimate
  moment present and reports caressing/leaning. After 16 s she may choose to end the
  afterglow; an accepted `[stay: SECONDS]` pauses that roll. The 8 s HUD close window counts
  active caress time. No automatic withdrawal/restore.

## Critical: camera work

### Modes and lean

- Desktop human Anon always uses the mod-controlled act camera.
- AnonPony and headset/VR keep the stock camera; they do not receive lean or act actions.
- Mouse motion does not turn the view; vertical mouse motion still thrusts.
- `Q`/`E` plus `W`/`S` form one continuous lean vector, not a press-to-fire key event:

  ```text
  side    = E - Q
  forward = W - S + abs(side), clamped -1…1
  ```

- `LEAN_RAMP_SECONDS = 0.5`, `LEAN_RETURN_SECONDS = 1.6`.
- Camera mapping: forward `0.24 m`; backward `0.08 m` (half); side `0.18 m`; pitch is `6°`
  downward in **both** directions, plus `8°` outward side roll, `3°` side yaw and `1.5°`
  forward roll.
- Lean distances, pitch, yaw and roll scale with pony size:
  `lean_size_scale_for(size) = clamp(2.0 - size, 0.75, 1.5)`. JRHNBR (`1.0`) is the reference;
  Canon (`0.66`) is `1.34` (+34%).
- Standing Anon body lean: `apply_anon_lean()` freezes the whole lower body (hip target and both
  foot targets) at its act-start pose. The camera/head moves forward, sideways or down, so the
  torso hinges over her while the legs keep their pose instead of walking into the shot.
  Pulling back translates the hips and both feet together, so the whole lower body moves away
  without changing the leg pose.
- The hip is **depth-driven**. `_hip_phase` is the mouse `depth` low-passed by
  `HIP_SMOOTH_S = 0.04 s`. The fixed rump point is the base HipsTarget plus
  `THRUST_MAX_M = 0.045 × body_scale` toward her; `anon_hip_thrust.gd` moves only the Hips bone
  by `THRUST_MAX_M × (1 - thrust.travel × (1 - phase))`, so depth 0 is the full backset and
  depth 1 reaches the rump point. `thrust.travel` defaults to `2.0`. The modifier restores the
  Spine and both UpperLegs to their pre-offset global poses, so the torso, head and legs do not
  follow. There is no speed/strength attack and no return spring.
- With `standing_plant_feet` on (default), the standing controller captures both foot targets on
  the first act frame, moves them `PLANT_FEET_BACK_M = 0.15 m` behind Anon so they are not
  between her hind legs, and captures the hip target. Every frame after the body places them it
  rewrites all three to that capture. The torso, camera lean, hands, kiss and hip thrust still
  move; the lower body does not. Off restores the game's stepping and lean foot motion; the
  capture clears at act end.
- The camera is **speed-driven**, never an impulse. The physics tick filters the signed depth
  speed (`CAM_SPEED_SMOOTH_S = 0.06`) and `_camera_thrust_tick()` follows it with one critically
  damped response (`CAM_RESPONSE_S = 0.12`). `CAM_SPEED_REF = 4.0` depth/s reaches full travel;
  outward strokes use `CAM_BACK_RATIO = 0.5`. The bob target is negative, so the camera dips
  toward her on the inward stroke and rises on the return.
- `presentation.standing.torso_angle_deg` (default `5`, experimental/unbounded) hinges Anon's
  upper body forward over her. `apply_anon_lean()` keeps the lower body planted;
  `apply_camera_motion()` moves the head/camera along the spine arc
  (`ANON_TORSO_LEN_M = 0.65`). It applies live.
- Palm scale is a shared caress setting; see `docs/hands.md`. `hands/scale.gd` runs after the
  pose's hand solve and restores the cached bone scales on every act exit.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- The displayed lean is always smoothed at `CAMERA_INERTIA_SMOOTH = 5.0`.
- `Q`/`E` fire their pose action at `LEAN_FIRE = 0.75` and release at
  `LEAN_RELEASE = 0.60`. The action is latched while above release.
- The lean always holds a released position. `_lean_step()` only ramps toward a pressed target;
  the explicit `S` shoulder recentre uses `return_to_zero`. The act end and paused paths still
  return the lean over `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default on) the camera lean gets a small, slow forward rock
  (`0.010`). It is a **separate offset** (`runtime.shot_lean_forward()`), never added into
  `_lean_view_forward`: folded in, the inertia smoother amplified it about twelvefold and the shot
  crept while nobody was leaning. There is no side sway. Caress input is in `docs/hands.md`.
  Pressing `S` arms a gradual side return, so the shoulder roll decays to neutral without
  leaning the other way.
- Lean and actions are available in both `ACTIVE` and `CLIMAX`; every other state ends them.
- The lean camera owns `player.controls_locked = true` for both poses. Save and restore the
  prior value at act end.
- `F` is not an act control in missionary. In standing, holding `F` at a full side lean
  (`abs(side) >= STANDING_KISS_LEAN = 0.90`) starts the same base-game kiss; outside an act it
  remains the game's flight key.

### Missionary camera

`presentation.missionary.camera_mode` (debug) picks the eye. **Authored shots** is the default and
uses the shot trajectory below. **Anon eyes** keeps the view at `missionary_anon.gd`'s
`eye_transform()` — his posed `Head` bone with the game's eye offset, read from the transform
`apply()` caches for the frame before `HeadHide` collapses the head bone. The lean is one hinge at
the **`Spine`** joint: chest, neck, head, shoulders, arms and hands tilt as a unit, while his hips,
thighs and legs stay on the authored pose and keep the thrust. W tips the hinge forward/down toward
her, S back/up, and Q/E add the side lean. The camera is written after the pose write in the same
frame. Her gaze and the kiss target his authored eye and mouth (`eye_point()` / `mouth_point()`),
never the game camera on his standing player rig; the game's eye modifier is pointed at the same
target, with `presentation.missionary.size.<preset>.gaze_offset_mm` (debug, signed, unclamped)
raising or lowering it. The vulva trims and the fold/hug hacks are missionary-only anatomy values;
see `docs/anatomy.md`. The camera itself is kept outside her live skull and muzzle by
`head_clearance_mm` (debug: 50 mm on Canon and JRHNBR, 100 mm on Same Height and Hoers) in both
views, so a close cheek or muzzle lean cannot enter her head as she turns it. The skull and muzzle
radii scale with her body size; the clearance is an absolute pad on top. The six values are per
pony size, stored under `presentation.missionary.size.<preset>` and edited through one **Size**
dropdown.

### Missionary shot

With the authored base pose in charge the shot is a **blend of the five authored camera transforms**
from the pose lab: `shots.start` (neutral), `shots.back` (S), `shots.front` (W, the kiss framing),
`shots.left`/`shots.right` (Q/E; the asset names are from her side, so Q reads `right` and E reads
`left` to match the screen). Both position and direction are used; the origin scales with
`body_scale`. The weights are `max(0, 1 - |forward| - |side|)` for start, `|forward|` for the
forward/back shot and `|side|` for the side shot, normalised. A pure axis lean has a single weight of
one, so with no stroke speed the eye meets the authored transform exactly; everything between is a
position average and a quaternion average. The speed-driven surge/bob from standing is added on top
(along the camera forward and world up) and settles to zero at rest. A kiss does not move the
authored shot — the `front` transform is the framing.
The `KISS_CLEARANCE_M` lean-in applies only in **Anon eyes**. A missing shot falls back to a fixed
bed-relative point aimed at her live face and is named in the log. There is no live offset, no frozen
anchor and no framing nudge.
**Third-person views** (`presentation.missionary.third_person`, debug, off by default) is the only way
off the trajectory: with it on, the lean tilts the eye and the side-lean travel and kiss
lateral/drop are added. Off, the authored transform plus the surge/bob is the whole shot. The
bullets below cover the rest of the shot's behaviour.

- Missionary body motion is `prone_sway` (`missionary_body_motion`), not the standing `body_sway`
  (`standing_body_sway`): the spine slides a little along the bed with raw depth and the head/neck
  nod `±3°`. The hooves are not pinned the way the standing sway pins them.
- Eyes: `ACT_LIDS = 0.45` during `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` only in `CLIMAX`, and
  sleepier afterglow `0.90`/`0.95`. A late `_eyes_tick()` reasserts the stare every tick so a
  climax return or fluster peek cannot leave her wide-eyed. While a kiss is active it releases
  the act's stare once and stops touching the eyes, so the game's own fluster/deep-kiss eyelids
  run; the custom kiss's `touch("affection", ..., 0.95)` lid layer is not overridden.
- Missionary parks the desktop presentation for the act (process off, disabled) and re-shows the
  act's own `AnonBody`; `missionary_anon.remove()` restores the presentation, the avatar transform
  and its process at end, so the rotated bed body cannot appear inside the camera shot and the rig
  is back on the player afterwards.

### Standing shot

- Uses the player's eye camera. Standing height still comes through
  `_stand_eye`/`_eye_height`; do not set the eye line by teleporting the rig.
- Act start keeps her where she stands. `_begin_standing_placement()` builds the act transform
  from her current facing and, for desktop human Anon, places him at
  `pony_position - forward * _standing_gap()` and **sets his yaw along her forward**, so a standing
  act after a missionary restore does not inherit the old view and put his body off to one side. That stance is only the starting point: with the
  anatomy part showing, the measured aim pulls his pelvis to `opening - normal × (shaft - depth)`,
  so `gap_offset_m` sets the pre-act view rather than the contacting distance. The 1.2 m Y cone
  means the correction is small, and `_smooth_penetration()` blends the pull-in through
  `POSING_IN`. The act end leaves him there and leaves his yaw/pitch at the last act aim instead of
  snapping the pre-act view back. AnonPony and headset/VR keep the old `_standing_transform()`
  placement (she moves in front of the camera rig), because their rig is the camera or another body.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) once at pose start,
  then freeze. Lean yaw/pitch are applied on top.
- Standing has no separate thrust rock spring. The shared speed-driven surge/bob handles the
  thrust camera; lean yaw/pitch stays on top.
- Lean owns `controls_locked` for standing too, so Anon does not walk while the camera moves.
- On restore, missionary restores the captured player yaw/pitch and resets `camera.rotation.x`
  and `.z`; standing leaves Anon facing where the act ended.

### Standing body language

- `body_sway.gd` translates `pony_hips` with a damped spring driven by raw `depth`, so her rump,
  chest, neck and head all follow. It is inverted for this pass: her body rocks **back** on the
  inward stroke and **forward** on the outward stroke. Both hind-femur and fore upper-arm origins
  are restored afterward so the hooves stay planted. The modifier also publishes the world-space
  offset; the standing Anon controller adds it to the pinned hip, so his part rocks with her and
  the aligned contact stays together. `BODY_SWAY_MAX_M = 0.035` is deliberately exaggerated for
  review; park it near `0.012`.
- Strong thrusts (`strength >= 0.55`) build a subtle rump blush decal by `0.0525` per thrust,
  capped at `0.375` (the smack decal uses `0.8`). It decays at `0.006`/s and is removed at act
  end.
- Base posture adds `chin_up_deg = 30` (head) and `neck_down_deg = 15` total (neck1/neck2), giving
  the chin-up, snout-reaching S-curve. The debug chin modifier remains additive.
- `foreleg_spread` is the absolute outward half-angle from the body centreline. The default
  `0.172 rad` matches the current rest placement; `_spread_fore()` measures the current hoof line
  and rotates the upper arms only by the difference.
- Ears keep the current fluster/pinned baseline. `ear_twitch.gd` flicks **both** ear roots
  together: a shared forward/back pitch plus a sideways twitch that moves both ears outward or
  both toward the head. The per-ear sign is derived from the ear root's lateral offset, never a
  shared world-side rotation.
- `tail_pose.gd` also rocks the tail on the same thrust cadence: a damped spring from raw `depth`
  drives a sagittal swing (`ROCK_PITCH = 0.12`) and a smaller lateral wag (`ROCK_YAW = 0.08`).
  Thrust jiggle strength and the standing camera height scale with pony size: Canon gets
  `_jiggle_size_scale() = 0.66`, a `CANON_STANDING_CAMERA_DROP_M = 0.10` lower eye line, and
  `_standing_lean_scale()` multiplied by `0.8`; JRHNBR gets a
  `MOUNTING_STANDING_CAMERA_LIFT_M = 0.10` higher eye line.
  Every thrust calls `tail.thrust(jiggle)` with the same `jiggle_amount` as the rump shader: a
  short `JIGGLE_DECAY = 3.6` / `JIGGLE_FREQ = 18` wave, strongest at the tail root
  (`mTail1`) and lagging down the chain (`JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`). A smack
  calls the same tail impulse through `_on_smack_impact()` at
  `1.0 × _jiggle_size_scale() × smack_intensity`; the thrust tail impulse also scales with
  `jiggle.intensity`. A debug line reports the resulting amount. This is the cheapest way to
  make rump jiggle and tail read as one motion; the shader itself stays native.
  `FlankTouch._start_jiggle()` clamps its own impulse to `0.3…1.0`, so `_thrust_jiggle()` passes
  `1.0`, scales the resolved `_jiggle_amount` by the travel-led `jiggle_amount ×
  JIGGLE_RUMP_SCALE = 2.8 × size × jiggle.intensity`, and re-runs `_process(0.0)` once so a soft
  stroke cannot flash at full amplitude.
  The game's tail anchor pins the first 12–67 mm of the `DevkitTail` root cap to the hair
  `mPelvis`, so rotating `mTail1..6` alone cannot move the base. `tail_pose` also translates the
  hair `mPelvis` by `JIGGLE_BASE_M = 0.02 m` using the rump shader's thrust wave, restoring
  `mChest`/`mNeck`/`mHead` so only the tail base and chain move.
- The rump shader wobble is tuned by the `jiggle` block: `radius` (default `0.26 m`) spreads it
  across the whole flank, `intensity` (default `0.25×`) scales the thrust amount, and
  `smack_intensity` (default `0.45×`) scales the act smack amount. The runtime
  sets `jiggle_radius` on every active `_flank._jiggle_targets` material and restores the override
  at act end, so stock smacks keep the shader default `0.12 m`. `apply_live_settings()` updates
  the radius on an active wobble.
- The visible body coat is the rig `MareBody`, not the `NearBody` merge (which holds only the
  cutie-mark patches). With `body_coat_deform` on, `anatomy.gd` takes the per-pony body material
  from `FlankTouch._own_body_materials()`, then `anatomy/body_coat_patch.gd` duplicates the game
  `Shader`, swaps the `flank_jiggle.gdshaderinc` include for
  `anatomy/body_coat_deform.gdshaderinc` and the `VERTEX += flank_jiggle(VERTEX);` call for the
  deform call. No game source is edited and no cel shader is copied. The patched material and its
  outline are no longer in `JIGGLE_SHADERS`, so `runtime._attach_body_coat_jiggle_target()` adds
  them back after every `_start_jiggle()`; the anatomy's `physical_reaction("flank_smack")` hook
  covers stock smacks outside the act. The two still zones are in `docs/anatomy.md`.
- At act start the runtime hides and ages every stock `FlankTouch.mark`, so a redness mark from
  a regular smack before the act cannot linger and look like a stale jiggle point. The act's
  own rump blush and act-smack mark take over. Regular smacks outside the act keep their native
  marks, blush and decal duration.
- A mod-owned `wing_sweep.gd` modifier runs last on the skeleton while standing holds the wings,
  yawing `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°` in opposite directions to sweep the spread
  wings slightly backwards. It is removed with the wing hold.
- Entering `AFTERGLOW` starts a slow fold instead of holding the spread until restore. The
  runtime releases the hold, disables the wing node's own 0.3 s fold, and drives `tuck` toward
  `1.0` / `half` toward `0` over `WING_AFTERGLOW_RETURN_SECONDS = 6.0`. At completion the wing
  node's process is re-enabled so `WingTuck` hides the open meshes and shows the folded ones.
  Leaving afterglow early re-enables the node and lets it finish immediately.
- Look-back glances clamp yaw to `GLANCE_BACK_YAW = 1.62` and add 20% to
  `glance_back_pitch` (base `1.2`, boosted to `1.44`). The `head_back` ease uses
  `GLANCE_BACK_FADE / glance_back_speed`; `glance_back_speed` defaults to `2.0` and is live in
  the settings tab.

### Act actions

Pose support lives in `lean_action_kind()` in `runtime.gd`:

| Input | Missionary | Standing |
|---|---|---|
| `Q` | lean only | left-hand reach to her left shoulder |
| `E` | lean only | right-hand reach to her right shoulder |
| `A` / `D` | left/right chest/belly caress (A left, D right; both can run) | slow left/right flank caress |
| `Z` / `C` | toggle the active hand's caress oval | toggle left/right caress oval movement |
| `F` (hold) | kiss at a full forward lean (W) | kiss at a full shoulder lean |
| Mouse right | left/right cheek opposite the lean | same |

`lean_action_kind()` only fires the standing shoulder reach now; kissing is not a lean action any
more. `kiss_control.lean_kiss_tick()` runs every act tick for both poses and starts the same kiss
when F is held at a full lean: `|lean_side| >= STANDING_KISS_LEAN` in standing, or
`lean_forward >= MISSIONARY_KISS_LEAN` with W held in missionary (`lean_targets` adds `|side|` to
forward, so W is required or a pure side lean would pull the kiss). Missionary kisses use the
custom head-aim path below.

- Standing reuses the game's own kiss path: temporarily clear `controls_locked` for
  `pony_kisser.begin_from_pony()`, move `AffectionPose` last in the skeleton so its IK layers on
  the act pose, and call `Affection.end()` on release. This gives the normal face, mouth,
  deep-kiss and soft-kiss audio behaviour. Missionary always uses the custom head-aim path: the
  stock kiss pose is authored for a standing pony and its chest/neck give lifts the lying body
  and turns her head across the mattress. The custom path still sets the mouth expressions and
  repeats the mouth kiss sound. Its look point blends from his eyes to his mouth by the kiss's
  `0.35 s` fade (`kiss.amount()`), so the head leans in with the kiss instead of snapping to the
  mouth on the first frame. Either path may stop the pony's current speech, but it does not
  interrupt thrusting or stats. `_check_running()` treats the act's own `Affection`-driven
  `kiss` as part of the act instead of an interruption.
- `pony_kisser` physics is paused for the whole act, so the runtime feeds a base kiss the live
  `target`/`eye`/`face` from Anon's real mouth camera and repeats the mouth kiss sound itself.
  Missionary's custom kiss aims at the authored Anon's mouth (`mouth_point()`), never at the game
  camera on his standing player rig. The
  excitement Beat timer is paused for the kiss so the stock unicorn horn sparkle does not fire.
- Standing reads `presentation.standing.kiss`: `mouth_right`, `mouth_drop` and `mouth_forward` place
  Anon's mouth target; `camera_yaw_deg` is the over-the-shoulder kiss yaw; `lean_side`,
  `lean_forward` and `lean_drop` are his kiss lean. Missionary keeps the `KISS_LEAN_*` /
  `KISS_CAMERA_YAW_DEG` constants. All standing values apply live from the settings tab.
- `presentation.standing.kiss` has no foreleg choice: the act always saves the game's
  `AffectionPose.kiss_settings()` `rear` and `hooves` values, sets both to zero before the base
  kiss and restores them when the release pose is removed. `kiss_legs.gd` then captures both
  foreleg tips before the base kiss and runs last to CCD them back to those positions, because
  the base kiss's chest flex would otherwise drag the legs after `body_sway`'s upper-arm pin.
- While a kiss is active, Anon leans in by the standing `lean_forward` (default `0.03`), shifts to
  the shoulder side by `lean_side` (default `0.46`) and drops by `lean_drop` (default `0.08`)
  lower over `0.35 s`; the standing camera also yaws by `camera_yaw_deg` (default `12°`) toward her.
  Missionary keeps `KISS_LEAN_M = 0.27`, side `0.18`, drop `0.035` and camera `10°`. The kiss side is latched at
  the start from the input lean (`_lean_side`, falling back to `_lean_action_side`), not the
  lagging camera view, and `_pin_base_kiss_side()` pins her head tilt to the
  complementary side (`KISS_PONY_SIDE_SIGN = 1`) so their heads interlock instead of colliding;
  the deep-kiss side switch is disabled for the act. The pin writes AffectionPose's private
  `_side`/`_side_now`/`_side_wait` each tick and is skipped if those fields disappear. The
  lateral offset crossfades from the
  lean's `0.18 m` to the kiss's `0.18 m` instead of adding both.
  Standing applies it to the act camera and pelvis counter-lean, so the hips stay planted; missionary
  applies it to the framing view and offsets the virtual mouth by the kiss distance. During the
  kiss and its `Affection` release the forced over-the-shoulder glance is cleared and `head_back`
  eases to zero, so the kiss head pose is not fought by the reach glance. The camera lean is held
  until the release has retracted (`Affection.amount > 0.2`) before easing out, and a completed
  kiss has a `KISS_RESTART_COOLDOWN_MS = 500` before another kiss can start. The side latch and
  the pose lock are cleared when the kiss lean reaches zero.
- Shoulder reach and palm basis: see `docs/hands.md`.
- A/D caress uses the shared caress system; see `docs/hands.md`. The pose supplies the standing
  flank -> shoulder -> neck path, the rump fallback and the standing palm holder.
- While a shoulder reach is held, `_forced_glance` locks the pony's glance over that shoulder
  and suppresses the random glance scheduler; release clears it.
- Smack: see `docs/hands.md`.

### Caress

The caress paths, marked area chain, contact, smoothing, settings and debug controls are in
`docs/hands.md`.

### Thrust camera and restore

- The camera thrust is two amounts in `camera_thrust`: `surge` and `bob`, both `0…1`; defaults
  `1.0` and `0.35`. They scale `CAM_SURGE_M = 0.06 m` and `CAM_BOB_M = 0.02 m`.
- Both follow the filtered signed depth speed with one critically damped response. No impulses,
  no per-stroke kick and no camera rock.
- Climax uses `CAM_CLIMAX_SURGE_M = 0.02` and `CAM_CLIMAX_BOB_M = 0.008`, scaled by the sliders.
- Missionary and standing use the same surge/bob. Both send the surge along the camera forward and
  the bob along world up; in the authored shot they are the only motion off the authored transform,
  and they settle to zero when the stroke stops.
- Teardown is one function. `_end_session(rejoin_cuddle)` gives back, in order: the inventory HUD,
  request face, kiss forelegs, face-turn rate, eye override, face and wings, player lock, camera,
  `sex_active`, navigator, player look, posture/cuddle, pose, audio, HUD and the active runtime.
  Every step checks the ownership flag it restores (`_camera_owned`, `_look_captured`,
  `_posture_owned`, `_locked_player`, `_eye_override`, `_face_turn_rate_owned`,
  `_inventory_hud_hidden`, `_nav`, the controller flags), so a failed start runs the same
  function and restores only what it took. The back-to-IDLE tail schedules the bed cuddle rejoin
  when `rejoin_cuddle` is true and the act qualifies; it is deferred so `_finalize_session()` has
  started aftercare first. `_finalize_session(real_act)` runs the post-act
  bookkeeping (`_reset_after_act`: thrust reset, satisfaction fade, aftercare) once and is
  idempotent. Never add a second exit sequence; add a step and a flag.
- `_end_act_lines()` is deliberately outside the teardown. `cancel()` queues the early-stop
  reaction after `_restore_begin()`, so `_finish_restore()` must not cancel director rows. It runs
  from `cancel`, `_climax`, `_afterglow_begin`, `_restore_begin`, `_restore_now`, `_abort_start`
  and `apply_live_settings` when `act_lines` is switched off. The utterance scheduler is reset by
  `_reset_thrust_state()`, not by the session.
- Order inside the camera step stays load-bearing: free-camera lock, Anon wrapper and palm scale,
  eye override and avatar, missionary view, standing camera, then player look. `_restore_look()`
  only runs when it captured the player (`_look_captured`), so a forced stop at `IDLE` cannot
  reset the player's facing.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act
  (`bed_side`) that did not go badly re-seats Anon on the bed's own player seat and re-invites her
  through the bed rest's `invite(pony, seats[1])`; the retry waits out aftercare's navigator hold
  and the guest cooldown, and every failure is logged before she is left standing. The act restores
  her standing on the mattress, so the rejoin first moves her to the clear floor beside the bed
  (`COUCH_EXIT.find_exit`): `_front_for()` rejects a floor more than 0.5 m below her feet.
- Missionary snapshots camera + current camera, player transform and pony transform/posture. Keep
  that snapshot exact; the re-seat starts from the standing spot it restores.

## Critical: ACTIVE readiness and strength

`thrust.gd` is pure and has no scene access. It tracks the public 0..1 depth and closes a stroke on
a real direction reversal or `STROKE_TIMEOUT_S = 0.18 s`.

- **Depth is measured penetration.** The runtime keeps `penetration_m`, how far the tip has passed
  her lips, and `depth = clamp(penetration_m, 0, reach) / reach`. Mouse motion is hip travel in
  metres (`THRUST.pixels_to_metres`, `thrust.pixels_per_cm`), not a percentage, and the back-out
  standoff is negative penetration, so it never counts towards depth.
- `penetration_reach()` is the deepest the tip can reach: `shaft length - Pelvis gap`, because both
  poses carry his body on the stroke and the gap keeps his pelvis behind her rear surface; a detached
  placement would be limited by the shaft alone.
  `shaft_length_m()` comes from the placed part, so `Size`, `Length` and the body preset move the
  stroke length with it; `NOMINAL_SHAFT_M = 0.20` is used while the part is not showing.
- `anon_part.track()` takes the penetration in metres and places the tip exactly that far past her
  lips in every path: the attached aim moves his pelvis to `opening - normal × (shaft - penetration)`,
  the sliding aim puts the tip there, and the bed holder sits `shaft - penetration` behind her.
  `_smooth_penetration()` eases the applied value (0.06 s) and starts from the stance's own
  penetration, so the act-start contact pull-in blends instead of snapping.
- A **stroke** is continuous movement in one direction.
- A **thrust** is an inward stroke with `travel >= THRUST_MIN_TRAVEL = 0.12` and
  `duration >= MIN_THRUST_DURATION = 0.04 s`.
- A reversal must travel `REVERSAL_HYSTERESIS = 0.06` from the stroke peak before it closes.
  Tiny pullbacks stay inside the same stroke.
- The tracker reports two event kinds. `impact` is the **bottom of the inward stroke**: it fires
  the moment the direction reverses or, when the bottom is held, after `IMPACT_STALL_S = 0.04 s`.
  Its stall clock follows the peak and only a `IMPACT_STALL_MIN_TRAVEL = 0.001` real gain resets
  it, so mouse jitter at the bottom cannot postpone it; it is latched once per stroke
  (`_impact_fired`). `strength` and `duration` come from the peak (`_progress_time`), so a dwell
  does not dilute the speed. `stroke` is the close, with the full stroke numbers.
  `runtime._on_impact()` owns all presentation (foley, base plap, vocal, jiggle, wings, tail rock,
  rump blush, ear twitch, thrust rate). `_on_stroke()` owns `_act_thrusts`, the intensity/pattern
  window, the log and `_score_thrust()`. Never move the plap back to the close: that is the
  180 ms delay the deep thrust used to have.
- The **body slap needs contact**, and only the slap. `THRUST.contact_amount(end_depth × reach,
  reach)` is 1 at the model's deepest point and 0 once the stroke stopped
  `CONTACT_COMPRESSION_M = 0.025 m` short of it, so it is derived from the shaft length, the
  `Pelvis gap` and the pose's reach rather than a fixed depth. `play_impact(..., contact)` skips
  the plap at zero contact and fades it in by `plap_contact_db` (-14 dB to 0 dB); the base
  foley-off plap uses the same gate. `slide_in`, the bed fabric, jiggle and every body reaction
  still fire on every real thrust: they come from the motion, not from skin meeting coat.
- Every stroke carries `direction`, `start_depth`, `end_depth`, `travel`, `duration`, `speed`,
  `peak_speed`, `thrust` and `strength`. There is no base gain and no per-stroke multiplier.
- Physical strength is `strength = clamp(travel × clamp(speed / 8.0, 0.15, 1.5), 0, 1)`.
  The `0.15` floor lets a slow full-depth stroke stay soft on the physical axis. Average speed
  drives strength; peak speed is logged and capped at `2 × average speed`, but one fast sample
  cannot saturate the score. The intensity preference is travel-led, not strength-led.
- Visual impact is `min(1, strength × THRUST_IMPACT_GAIN)` with `THRUST_IMPACT_GAIN = 2.0`,
  preserving the tuned normal/fast response while slow and shallow strokes stay lighter. It
  drives wings, ear twitch and rump blush; the foley scales from `strength` directly. The
  rump/tail wobble uses `THRUST.jiggle_amount(travel, strength)` instead: travel sets the
  amount, so a full stroke wobbles the same at any speed, and the soft band fades the gentlest
  strokes to `0.04`.
- Only real thrusts update the axes and score. Outward strokes, tiny jitter and pullbacks are
  presentation only.
- The ACTIVE stage reads two axes from the last real thrusts:
  - **intensity**: `soft` (`travel < 0.35`), `firm` (`travel < 0.65`), `rough`;
  - **pattern**: `steady`, `teasing` (`mean duration > 0.45 s`) or `quick`
    (`mean duration < 0.30 s`), classified over the last 3–4 real thrusts. Fewer than 3 has no
    pattern yet. Pattern is tempo only: depth does not decide the rhythm. The depth and tempo
    axes are independent, so all nine intensity × pattern combinations are reachable. The physical
    strength formula above is the plap/foley/wobble value, not the preference axis.
- Auto thrust (`X`) feeds this tracker, never a parallel score. `auto_thrust.gd` advances
  `wave(shape, phase)` at `pace` thrusts per second between `min_depth` and `max_depth`;
  `_auto_thrust_tick()` sends the per-frame depth delta through `_thrust_move()`, so readiness,
  intensity, pattern, audio, camera, jiggle and presentation keep their existing paths. The wheel
  nudges pace; the band and shape come from the hold-X layer, and the mouse does nothing while
  auto runs. The band is smoothed over `DEPTH_SMOOTH_S = 0.18 s`. `max_depth` is the peak, not the
  tracker travel: after the first stroke `REVERSAL_HYSTERESIS` makes travel
  `max_depth - min_depth - 0.06`, so the minimum band is `0.20` and its `0.14` travel still counts
  as a real soft thrust. The pace range reaches every pattern at any depth, and the depth range
  reaches every intensity at any pace.
  `auto_thrust.curve` (`Auto shape`, debug) picks the stroke waveform: `cosine` (the `Normal`
  panel value, a symmetric ease), `thrust` (35 % duty, fast in and slow out, the default),
  `tease` (65 % duty), `saw` (constant speed, no easing), `hold` (quick in, a dwell at full depth,
  quick out). Every shape starts at the bottom and returns to it, so the tracker only ever sees
  depth deltas; `phase_for()` is a numeric inverse so turning auto on never snaps. The stroke
  travels
  `max_depth - min_depth`, and the band stays at least `MIN_BAND = 0.18` wide (0.12 travel plus
  the 0.06 hysteresis) because a narrower one silently stops scoring; `nudge_min` and
  `nudge_depth` push the other end instead of closing it. `X` is live in `ACTIVE`/`CLIMAX`;
  `_afterglow_begin()`, `_restore_begin()` and `_end_session()` stop it, and
  `_reset_thrust_state()` restores the act-start defaults (off, configured pace, depth, min and
  shape) for the next act. Pace, depth and min are per-act starting values; `Auto shape` applies
  live and the hold-X `Z` writes it to settings.
- `satisfaction` is **readiness 0–100**, not a stroke score. Each real thrust adds
  `THRUST_HEAT_BOTH = 1.4`, `THRUST_HEAT_ONE = 0.7` or `THRUST_HEAT_NONE = 0`, times warmth;
  scoring is limited to one thrust every `THRUST_SCORE_MIN_INTERVAL = 0.2 s`. There is no
  passive match rate.
- Touch/talk are assist only: one chunk up to `ASSIST_CAP = 60`; touch and talk use the
  **Talk & cues** cooldowns (`talk.touch_cooldown_seconds` default `4 s`,
  `talk.talk_cooldown_seconds` default `8 s`). A liked touch/talk opens
  `talk.receptive_seconds` (default `8 s`) of `RECEPTIVE_BOOST = 1.25`. A disliked one subtracts
  and briefly sets `overwhelmed` for `cues.overwhelmed_seconds` (default `1.2 s`).
- `CLOSE_AT = 65` is only the “she is close” cue. `PONY_CLIMAX_AT = 100` triggers a pony
  climax. `satisfaction` is still the public HUD value.
- Each pony climax lasts `CLIMAX_SECONDS = 5`; the player can keep thrusting, but those thrusts
  do not score. After it, readiness resets to `0`. The user-facing
  `thrust.max_pony_climaxes` setting (default `3`, `0` unlimited) decides when the act
  auto-enters afterglow.
- Hold `Y` in `ACTIVE` with 0 climaxes cancels; with 1+ it enters afterglow. Hold `Y` in
  `CLIMAX` enters afterglow. `Y` in `AFTERGLOW` ends it.
- `mood` is `warming`, `wanting`, `close`, `climax` or `overwhelmed`; `cue` is the short HUD
  line. `hud_readouts` gates the cue segment and the `Wants`/`You` segment.
- Readiness never decays passively. Only a disliked touch or talk subtracts; neutral and quiet
  input leave it unchanged.
- Talk is scored when the player actually speaks. The game's `T` text/mic turn is detected
  through `conversation_director._turn_id` / `_player_text`; the AI still writes her reply.
  There is no act talk-invitation line or HUD hint.
- Do **not** add a thrust debug sub-gate. The per-thrust log is the scoring view.

Read `PREFERENCES.md` for the exact preference schema, readiness rates, cue rules and character
examples.

## Critical: act expression and mood

The act uses the game's own expression vocabulary; it never adds a second emotion stat. `act_face.gd`
is pure and owns every face/beat decision; `mood_face.gd` holds one post-act face; `runtime.gd`
owns the timing and the line-face yield.

### Vocabularies

- **Faces** (`[face:NAME]`): 22 names from `face_poses.gd` (`LINE_FACES`). The director applies
  them on speech start, holds them for 3 s after speech, and strips them from the words.
- **Mood** (`[mood:NAME]`): 10 names in `pony_impressions.gd`, fresh for 300 s. Its gate effect
  is in `docs/eligibility.md`; it feeds prompts/profile. The base game has no mood→face bridge.
- **Voice** (`[emotion]`): 11 TTS tags. They are audio only. `shy`, `affectionate`, `ooo` and
  `anticipation` are faces, not voices; `calm`, `fearful`, `whispering` and `shouting` are voices,
  not faces.
- **Gaze moods** (`openpony_eye_motion.gd`): set from the active face/fluster; the act still points
  `eye_motion.target_world` at Anon.

### One face owner

`_act_face` tracks the face the act set. `_set_act_face(face, hold_s)` refuses to override a
director line (`dialogue_face` non-empty and not `_act_face`). A face with `hold_s > 0` calls
`finish_dialogue(hold_s)`; `_end_act_face()` clears only if `dialogue_face == _act_face`. The act
face is cleared in `_restore_begin()`/`_end_session()`; the post-act mood face starts after it at
`_begin_aftercare()`.

### Beats

| Moment | Face | Hold |
|---|---|---|
| start, first time | `shy` | 2.5 s |
| start, repeat | `relaxed` | 2.5 s |
| readiness reaches `CLOSE_AT` (65) | `anticipation` | 3 s |
| climax, `fluster` | `shy` + `fluster(5.0)` | 5 s |
| climax, `ooo` | `ooo` | 5 s |
| climax, `wide` | none | — |
| afterglow, positive | `affectionate` | 3 s |
| afterglow, neutral non-early | `relaxed` | 3 s |
| afterglow, bad | `sad`/`annoyed` | 3 s |
| warning / overwhelmed | `sad` for forgiving, else `annoyed` | 3 s / 2.5 s |

`_first_time` is one `main.memory.cue_facts()` call at start. `warning` is `_tolerance_warn`;
`overwhelmed` is the disliked touch/talk path. Both are one-shot, so a cue line can replace them.

### Auto climax style

`climax_mode` (`wide` default, or `auto`/`fluster`/`ooo`) picks the climax expression. In
`auto`, `act_face.climax_style()` scores the live act from the same counters the summary uses:

```text
motion     = avg(intensity match rate, pattern match rate)       # 0.5 with no data
both       = both_matches / max(3, intensity_total)
affection  = min(1, (liked_touch + liked_talk) / 3)
engagement = 0.5 * min(1, intensity_total / 6)
           + 0.5 if any liked touch/talk
penalty    = min(0.8,
               dislikes_total * 0.20
             + tolerance_distress * 0.05
             + 0.10 if she seeks touch and got none
             + 0.10 if she seeks talk and got none
             + 0.20 if overwhelmed)
score      = clamp(0.35*motion + 0.25*both + 0.25*affection + 0.15*engagement - penalty, 0, 1)
```

`score >= 0.70` → `fluster`; `>= 0.40` → `ooo`; otherwise `wide`. This is presentation only; the act
summary still owns the grade, history, mood and rewards. `face_debug` logs the style and all parts
once per climax.

### Blush and lids

`blush_for()`: POSING_IN `0.60`; ACTIVE `0.55 + 0.45 × readiness/100`; CLIMAX `1.0`; AFTERGLOW
`0.40`. `blush_arc` off restores full blush for the whole act. A line face with `blush` overrides
the decal; the beats choose blush-free faces at low readiness.

`stare()` still owns the eyelids: ACTIVE `0.45`, CLIMAX `0.0`, AFTERGLOW `0.9`. The only act-time
release is the climax `fluster` (and the existing kiss path). `_stare_release_until` is cleared by
`_finish_climax`, `_afterglow_begin` and `_restore_begin`. `act_ear_pin` still pins ears through
`fluster`; it also forces full blush through the base game, so it conflicts with the blush arc.

### Prompts

Default `cue`/`utterance` prompts carry `{face_note}`. The runtime fills it with
`ACT_FACE.prompt_note("cue", mood)` and appends it to a saved prompt that lacks the placeholder.
`main.memory.line()` appends the event note for `climax`, `end_early`, `tolerance_warning`,
`tolerance_stop` and `history_refusal`. The offer ask/invite and the bystander prompt get their own
notes. A note is skipped when the prompt already contains `[face`. The note never suggests
`[mood:...]` in an act line.

### Post-act mood face

`mood_face.gd` holds one post-act face for 300 s, yields to
spoken line faces, ends when the impression mood changes, and clears only its own face. It starts
from `_begin_aftercare()` for a normal act and from `_start_upset()` for a refusal/stop. Positive
and non-early neutral acts use `relaxed` and set `_warm_note` for the warm prompt note; a bad act
uses `sad`/`annoyed`; a stop uses `angry`/`annoyed`. The face survives the deferred
`_rejoin_bed_cuddle()`. A positive act's afterglow has the short `affectionate` beat; the held face
is deliberately blush-free so the 0.35 decal stays light.

### Settings and debug

- `features.act_faces` (default on) gates the beats and prompt notes; the post-act mood face stays.
- `presentation.act.climax_mode` (debug, `auto`/`fluster`/`ooo`/`wide`).
- `features.blush_arc` (debug, default on) and `features.face_debug` (debug, default off).
- Actions **Force act face** (`Next`) and **Show act face** (`Inspect`) in General's Debug block.
- `face_debug` logs one line per face change, the climax score parts and the mood-face start/end.

### Guardrails

- A face tag cannot close the eyes while `stare` is on; only `fluster`/kiss release it on purpose.
- Never use `[mood:...]` in act lines; the summary owns the impression mood.
- Do not use `pain`/`fearful` for consensual intensity; reserve them for real distress/stop.
- `angry`/`ponyrage` carry `brace`; a standing cue line with one can trigger `expression_stance`.
- Pair `fluster` with `shy`/`relaxed`, not a frown or round mouth: it brings its own `.55` smile.
- Custom prompts may use `{face_note}`; the runtime appends the note when it is absent.

## Act flow, gates and controls

- Eligibility, willingness, the lover bond, history refusal, cycle and per-mare consent are in
  `docs/eligibility.md`. Scene gates (state, navigator, pose, bed, player position) stay in
  `runtime.gd`.
- Missionary: Human Anon uses the seated/lying bed path; AnonPony uses the already-lying path. Standing:
  standing/settled.
- Start only when free/idle; another pony's conversation, active task or conflicting navigator
  lease blocks. Player conversation is free. The `allow_act_during_cuddle` flag (default
  `true`) lets an act start through an active stock cuddle session; the start path ends that
  session first.
- The runtime's automatic cuddle suppression runs only outside `IDLE`, so the stock bed/couch
  cuddle still works when no act is running.
- During the act the quick-slot inventory HUD is hidden and restored at end.
- `kiss_hold` owns movement hold; `pony_kisser` physics is paused so it cannot remove it.
- The mod keeps the mouse captured during an act: `input.gd` recaptures it every physics frame while
  an act is active, the window is focused and `menu_panel_open()` is false. The base game's own
  click-to-recapture is skipped while `controls_locked` owns the act, so a pause menu, map,
  inventory or alt-tab that leaves the cursor visible cannot kill thrust or the offer. `menu_open()`
  remains "paused, a panel is open, or the mouse is visible"; `menu_panel_open()` is the panel-only
  check the recapture uses.
- Act actions: `W`/`S` lean forward/back, `Q`/`E` side lean plus pose reaction, `A`/`D` caress
  (standing: left/right flank; missionary: both hands independently on her chest/belly),
  `Z`/`C` toggle caress movement,
  `F` hold kiss in standing, mouse right **or `G`** smacks. `X` taps to toggle auto thrust; while
  it is on **the mouse no longer sets the depth** (only the wheel sets pace; the hold-X layer sets
  the band and shape). They are available in `ACTIVE`, `CLIMAX`, and the `AFTERGLOW` of both poses;
  `Y` is the context start/end control. `H` is the game's hug/deep-kiss key; the act consumes it
  without binding it so a hug cannot end the act's kiss.
- **Hold `X`** (`auto_panel.gd`, pure) while auto is on opens the auto settings layer: it stays
  open while X is pressed, survives a re-press inside `GRACE_S = 0.28 s` after release, and closes
  otherwise. `Q`/`A` min depth ±5 %, `W`/`S` max depth ±5 %, `E`/`D` pace ±0.25/s, `Z` cycles
  `Auto shape` and writes the setting; keys step on press then repeat after 0.4 s at 0.08 s.
  `R`/`F` are reserved for a future tail control. A press that ever opened the layer can never
  toggle, so a short tap remains the only toggle. While the layer is open the lean is frozen
  (rather than returning to centre) and the camera view is frozen with it: never copy
  `_lean_forward` into `_lean_view_forward` there, because the idle sway leaves the view ahead of
  the base value and the copy snaps the shot. The caress ignores A/D and Z/C, the kiss ignores F,
  and the HUD card swaps to the four live rows. The layer only exists while auto is on (tap X to
  enable it). X is consumed in every act state, so AnonPony's X lie-down still cannot fire.
- Anatomy actions are additive and gated: `V`, `N`, `B` and their shape, winking and fluid
  behavior are in `docs/anatomy.md`. Enter opens the game chat during an act. With every anatomy
  flag off these keys are not consumed and the act is exactly the master act.
- `Y` starts an act on a single press when idle. During an act, `Y` is a `0.35 s` hold, matching
  bridal-carry initiation; a tap does nothing there. In `ACTIVE`, hold Y cancels with 0 pony
  climaxes and enters afterglow with 1+; in `CLIMAX`, hold Y enters afterglow. Hold Y ends
  afterglow; Y is ignored in `RESTORE` except for event consumption. `T` remains the game's talk
  key and is not consumed; the runtime watches player turns as a scoring input. `Q`/`E` are the
  side lean; during an act the interaction keys are still consumed so the game's stand-up action
  cannot interrupt the scene.
- States: `IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE` for both poses.
- Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.
- Aftercare starts only at final readiness ≥ 10; it holds navigator ownership for 10 s. Its
  positive tail-up/flick body language is used only after a good act; a bad act keeps the 10 s
  hold without it.
- Every completed act starts `mood_face.gd` for 300 s, matching the impression mood freshness. A
  positive or non-early neutral act uses a relaxed face, a light 0.35 blush and the warm prompt note
  ("still warm and relaxed after making love with Anon"); a bad act uses `sad`/`annoyed` instead. The
  face does not hold the navigator or block another act; a new act clears it. The positive
  afterglow also gets a short `affectionate` beat before the held face takes over.
- The first pony climax records one memory event; every climax gets its reaction. At afterglow
  `_commit_summary()` scores the act once and `main.memory.commit()` writes the grade-aware romance
  and mood; there is no flat `commit_climax()` reward. The witness pass commits once at afterglow.
  The standing afterglow also runs the 8 s close window and keeps its stay-close reward
  impression. Its stay-close reward is grade-aware: a bad act gets a one-point hurt repair when
  Anon stays and caresses, not romance.
- A peak act keeps one strongest memory per mare in `Mods.state("unfplap").peak_memories`.
  It is written only after a positive summary, with no disliked touch/talk and either peak
  satisfaction >= 90 or six both-axis thrust matches; a higher score replaces it. The stored text
  is the last player exchange, or a generic warm beat when he did not speak. The cue prompt
  prefers this memory.
- The afterglow HUD shows the summary: missionary in the cue line, standing on the readiness line
  under its close prompt. Early end shows no HUD summary. `prompt_note()` carries one short random
  afterglow beat (`ACT_SUMMARY.afterglow_beat()`, 40% silence) and a private relationship note in
  afterglow, the relationship note during the act, the 300 s warm note after a good or non-early
  neutral act (`_warm_note` on the mood face), or the history note while a hurt history is active.
  `lover_prompt_note()`
  adds the neutral lover fact (`You and Anon are lovers.` / `You are not Anon's lover.`) when no
  other prompt note is present. It does not recite the summary or append “Next time you want…”
  stroke mechanics.
- One act writes one summary event and one climax event. The old start, afterglow and inside
  events are not recorded; the standing close reward is an impression only. The summary keeps
  “made love”, so the act is still a clear memory rather than a euphemism.
- Memory uses the game's second-person phrasing. A witness must actually perceive the act:
  `pony_awareness.visible()` (24 m, facing, clear line) or `can_hear()` (12 m, clear line);
  sleeping ponies are skipped. Each observer gets her own event (`witnesses = [observer]`, place =
  the region id from `place_at`), never a shared one. Adults get `witnessed_intimacy` with the
  explicit text and thought; fillies and colts get `witnessed_scene`, a perception with an
  indoors/outdoors prefix and no conclusion, and mood only, so the game's per-pony story summary
  forms a memory they could hold. Young witnesses can retell it; the game propagates that through
  speech and town rumours.
- Proactive requests are a separate controller; see `docs/initiation.md`.

### Act summary and long-term history

- Every act commits one summary through `_commit_summary()` at afterglow or intentional early
  end; forced stops never commit. `act_summary.gd` scores the weighted action checklist and
  `ACT_HISTORY.commit()` stores hurt/comfort.
- The summary has two voices: `text` is the profile-safe world event recorded in world context,
  and `thought` is the first-person private impression shown as Last impression. Event text may
  start with `You and Anon ` (the profile rewrites that prefix to the pony's name) but uses no
  second-person pronouns for the pony after it; the thought does not go through that rewrite.
  Reason sentences keep the same rule, and an early end is stated once.
- An intentional early end or a partner stop records one event: the summary, or the basic
  `cancel`/`stop` event when history is off or the summary was skipped.
- A summary is good at `>= 0.80`, bad at `<= 0.20`, neutral between. A neutral early end adds
  one mild hurt. A partner stop is always severe. The grade decides romance, mood, the post-act
  face and aftercare; there is no flat `commit_climax()` reward.
- The history tiers and their offer/refusal effects are in `docs/eligibility.md`. Good acts repair
  hurt, time decays it and an apology repairs it once per in-game day. There is no break-up path.
  A tier-1 hint is deterministic per act and appears only about one time in four; tier 2/3 keep the
  clear hurt/space line, and an early-end act suppresses the later history line for that act.
- The afterglow HUD shows the summary. The debug log prints the grade, quality, checks, reasons,
  hurt and comfort. See `HISTORY.md`.

### Mid-act neglect-tolerance stop

- `preferences.tolerance` is per mare: `forgiving`, `normal` or `strict`; the Characters sub-tab edits
  **Neglect tolerance**. Default normal; Rarity is strict and Fluttershy is forgiving. The old
  `timid`/`neutral` values still resolve to `forgiving`/`normal`.
- A pure `act_tolerance.gd` meter runs in `POSING_IN`/`ACTIVE`. Every actual disliked touch/talk
  adds 1, every actual liked touch/talk subtracts 1, and passive decay removes 1 every 25 s.
  A held caress is a discrete action; its five-second meter is in `docs/hands.md`, so it cannot
  erase distress every frame.
- Warnings are one-shot per act: forgiving at 4, normal at 1 and 4, strict at 1. They set a HUD cue
  and queue one short spoken warning even when `features.act_lines` is off.
- Stop thresholds: forgiving never; normal 10; strict 3. A stop is not `cancel()`. It forces a severe
  bad summary (`stopped_by_her`, no romance, `+2` hurt), records
  `main.memory.note(MEMORY.NoteKind.STOPPED, ..., MEMORY.StopReason.WITHDREW)`,
  ends with no afterglow/cuddle rejoin and no aftercare, and starts a 20 s `tail_tuck.gd` that owns
  no navigator. The tuck hinges the tail at `mTail1` (the rest of the chain follows rigidly), not
  down the middle of the chain.
- Normal stops with a stern line, no buck and a `300 s` sex-only cooldown. Strict stops with a
  stern line, `request_space()`, a buck/kick from bed and a `600 s` sex-only cooldown. The history
  `stop_until` gate is in `docs/eligibility.md`. A new stop replaces the old cooldown.
- A stop also holds the refusal mood face: `annoyed` for normal, `angry` for strict
  (`mood_face.gd`), matching the summary impression that `main.memory.commit()` already wrote. With
  `features.act_history` off, or a skipped summary, the stop path keeps its old no-face guard.
- The **Neglect tolerance** debug settings sit in World's Debug block; the Debug actions have **Force neglect warning**
  and **Force neglect stop**. See `HISTORY.md`.

### Proactive requests

- The proactive-request service is specified in `docs/initiation.md`.

### Estrus cycle

- `features.estrus_cycle` (default off) gives mares a derived 30-day cycle. `cycle.gd` is
  pure: `MONTH_DAYS = 30`, `HEAT_DAYS = 7`, `DIESTRUS_DAYS = 2`; the mare's id hash sets her
  offset, so the town is not in step. The phase is recomputed from `relationship.bonds.day()` and
  `_id`, never saved.
- `runtime.cycle_phase()` returns `normal` when the flag is off or no relationship runtime is
  present. A debug override wins over both, so the lab can force a phase.
- In diestrus the gate hides both the Y hint and proactive offers; the exact rule and heat's
  offer/consent effects are in `docs/eligibility.md`.
- In heat each real thrust chunk is multiplied by `HEAT_READINESS = 1.6`, the readiness line appends
  `| In heat`, and `cycle_note()` adds the heat text to `main.prompt_note()` outside and during acts.
- The offer cooldown, privacy override and ask-prompt heat sentence are in
  `docs/eligibility.md`; the readiness and dialogue effects stay below.
- Outside an active act, the idle heat wink and drip are in `docs/anatomy.md`. The cycle phase
  and its gameplay effects stay here.
- The debug Actions **Force heat**, **Force diestrus** and **Clear forced cycle** set a session-only
  `_cycle_override` on the aimed or nearest mare.

### Act start and aim zone

- `main.try_start()` is the only act-start path. The start hint, start attempt, buck refusal,
  history refusal and offer gates are in `docs/eligibility.md`.
- Standing Y uses `rump_cone.gd`: Anon must stand within 45° of her backward axis (90° total)
  and 1.2 m of her rump anchor. The crosshair is not used, so looking away does not hide the
  hint. Missionary bed offers stay contextual.
- `dialogue_consent.gd` classifies every player line with a pony reply through the shared
  classifier. It never arms an act and never starts one; the lover-bond gate is in
  `docs/eligibility.md`.
- `consent_classifier.gd` is one shared service: one LLM client, one queue and scoped
  cancellation for `offer:` and `dialogue:` jobs. It never runs two mod classifier requests at
  the same time.

## Dialogue utterances

- Cues are event-driven: a touch/talk result, an overwhelmed state, or a ready state.
- `utterance_scheduler.gd` is the pure admission policy: it owns `mood_for`, `base_cue`, the
  stability clock, `cue_gap` (default `12 s`, clamped `8..30`, per character), the shared
  utterance gap, the demand budget and the single pending slot. `runtime.gd` builds the prompt and
  calls the director.
- The **Talk & cues** debug settings push the pacing values into the scheduler: override lifetime
  (`cues.override_seconds`, default `10 s`), base and override stability, shared line gap, demand
  gap/repeat, cue/reaction max age and the release hold. `runtime._snapshot_settings()` and
  `apply_live_settings()` re-read them.
- A base cue must stay unchanged for `cues.base_stable_seconds` (default `2 s`). A live
  touch/talk override only needs `cues.override_stable_seconds` (default `0.5 s`), so an event
  cue can speak inside its 10 s HUD lifetime; if the override ends while the row is still queued,
  it is dropped. It is fine if the line is lost.
- Demand cues (`She wants it…`, `She wants a…`, `She wants to be teased…`, `She needs…`) have
  their own `cues.demand_gap_seconds` budget and `cues.demand_repeat_seconds` lock for the same
  text, so a flapping preference cannot become a stream of commands. The trend fallback
  `She wants you to keep going.` is not a demand. The same text as the last queued cue is not
  repeated; it can return after a different cue has been queued.
- The runtime logs the cue text and the admission decision on a change, adds the cue text to
  `utterance kind=...`, and logs cancel age/line/director state plus delivered/absent rows. Use
  these when a cue seems lost; there is no per-tick cue log.
- The HUD cue is third-person shorthand (`She wants it firmer.`). The prompt does not use it as the
  line's content: `UTTERANCE.line_seed()` turns the same facts into a private second-person seed
  (“You would rather he be firmer.”), says it is not a script, and the default templates use
  `{seed}`. The state line contains pose, mood, preference-axis motion, last touch, last talk,
  pony climax count and act time; it contains no speed or depth units. The cue prompt gets
  `CUE_REACTION_NOTE`, which tells the model to phrase the private moment as a reaction or
  preference rather than a repeated command. Custom prompts may use `{state}` or `{cue}`.
- Mandatory cue context is code-owned: `UTTERANCE.context_note()` appends the state,
  relationship, tone and memory blocks that a saved prompt does not reference, plus the privacy
  guard. A legacy or custom template therefore cannot silently drop the relationship note.
- Every cue line carries a private relationship note and tone. The note uses the friendship/love
  level names, a human stage phrase, first-time/repeat (durable act history plus world context)
  and current mood. The tone is `guarded`, `friendly`, `tender`, `warm`, `ardent`, `open` or
  `careful`: no romance with an acquaintance is guarded, no romance with a friend is friendly,
  a first time with romance or a crush/new couple is tender, a marefriend is warm, and the higher
  love levels are ardent/open.
  The functional cue text is unchanged. The prompt tells her not to say the labels, levels or
  numbers.
- The cue prompt may include one unused shared memory. `main.memory.shared_memory()` prefers the
  stored peak memory, then the story journal: a cue-word match, then the most recent player
  exchange. It falls back to the world-context events. Intimacy events and private brain notes
  are not used as the hint. The memory is marked used only after the line is queued. The peak
  memory quotes her answer only when she actually spoke during the act (a start-of-act
  `last_spoken_at` baseline).
- One mod line owns the slot at a time, cue or reaction. A new line needs an idle director and
  pony and `cues.utterance_gap_seconds` (default `18 s`) since the last line was accepted.
  Reactions take the slot without the cue-stability/gap gates but reset the shared clock, so a
  cue cannot follow immediately.
- The pending slot stays reserved until speech stops and `cues.release_hold_seconds` (default
  `1 s`) passes. A row that reaches `cues.max_age_seconds` (default `20 s`, cue) or
  `cues.reaction_max_age_seconds` (default `30 s`, reaction) while still
  `queued` or `generating` is cancelled; a `speaking` row is never cut by age. The runtime observes
  `main.memory.line_state()` (a `MEMORY.LineState`: `ABSENT`, `QUEUED`, `GENERATING`,
  `SPEAKING`, `DELIVERED`, `UNKNOWN`) and
  frees the slot when the director drops or delivers the row. The old 60 s watchdog is gone.
- Cue `valid` remains tied to the pony/event id, not `State.ACTIVE`: cancelling the act must not
  invalidate a line that is already generating or speaking. Act boundaries still cancel queued and
  generating rows through `_end_act_lines()`. Reaction lines additionally carry their 30 s expiry,
  because they can outlive the act slot; a speaking reaction is kept past that expiry.
- The repeat hint contains the last four generated lines. There is no talk-cue line.
- Each pony climax drops queued act lines but keeps an in-progress one, then queues a unique
  climax reaction through the same slot. The standing afterglow queues no line. Only the cached
  “Mm.” is used; generated moans are parked.
- `_end_act_lines()` cancels every mod-owned line for the act except one that is already
  **speaking**. Queued and still-thinking lines are dropped. It runs at climax, afterglow, every
  act end (`cancel`, `_restore_begin`, `_restore_now`, `_abort_start`) and when
  `features.act_lines` is switched off mid-act. The intentional early-stop line is queued after
  the restore begins, and `_finish_restore()` never calls it.
- The early-stop line is a 50% chance, not a guaranteed summary. When it fires, it asks for one
  short feeling or a quiet hurt line, never a review or a next-time list. The early-end act then
  marks its pending history reminder/complaint announced, so the same act cannot produce a second
  post-act speech.
- `features.act_lines` (default on) gates cue lines and climax/early-end reactions. Off keeps
  normal dialogue and the HUD cue.
- The standing afterglow queues no `inside` or `stay_close` lines. Normal dialogue resumes with
  the live afterglow note; the HUD close timer owns the invitation. The prompt note provider
  (`main.gd` → runtime) reports caressing/leaning, and `[stay: SECONDS]` extends the no-self-end
  hold.

## HUD and rewards

- Buttons and words copy the game's own prompt row (`world/ui/interaction_hints.gd`) and carry card
  (`player/cradle_controls.gd`): the game's `prompts/<name>.png` icons where it has one, a dark
  drawn key cap (`CAP_BG`/`CAP_EDGE`) for keys it does not (W/S/A/D/Z, `↕`), ink words in
  `#f4f1ff` with a `#1a1624` outline instead of a drop shadow, and muted `#f4f1ff` at 60% for
  modifiers. `hud.gd` exposes `text_label()`, `keycap()`, `button_icon()` and `prompt_row()` as the
  one style source.
- The offer hint is `OFFER_HINT = "Make love"` in the game's own prompt row: a `button_y` icon at
  the row's 52 px scale beside 30 px words, placed by `hud.prompt_row()` so it sits beside base
  prompts. A single Y press starts the act (`input.gd` calls `try_start()`), so the hint is a tap
  prompt like `G · Carry`, not a hold. The action uses `ACCENT` (`#ffa8c7`, the same pink as the
  readiness fill). Without that row (VR or no `InteractionHints`) the same row is built into the
  HUD's own centered prompt above the caption line.
- The act controls are a bottom-left, top-down list: one row per key or key pair, each with
  keycaps/controller icons and one description; only a row with a modifier renders the muted
  `Hold` column. Rows list `↕` (`Thrust`, manual only), X (`Switch to auto` / `Switch to
  manual`), X (`Hold`, `Auto settings`, auto only), W S (`Lean`), Q E (`Reach`), A D (`Caress`),
  Z C (`Caress movement`), F (`Hold`, `Kiss`, standing only), `RMB` and `G` (`Smack`), the anatomy
  rows, and Y (`Hold`; `End early` before her first climax, then `End`) at the bottom. Every card
  row uses the drawn dark key cap, including Q/E/C/F/Y, RMB and G. The `Finish: in/out` row is
  built but hidden: the `B` key still toggles the runtime state, and re-showing the row is all it
  needs once the finish has a visible effect.
  While the hold-X layer is open the card is replaced by `X` (`Hold`, `Auto settings`), Q A
  (`Min depth N%`), W S (`Max depth N%`), E D (`Pace N/s`) and Z (`Shape: …`), so the live values
  are visible while adjusting.
  The card has no separate title. The `End` label is shaded from ink toward `ACCENT` by
  `runtime.hud_y_pink()`: one step per pony climax, capped at `Y_END_TINT_MAX = 0.75`, and fully
  pink only after the standing afterglow close window earned its caress reward. The cue line's
  hearts read `❤ N/limit`, or `❤ N/∞` when the climax limit is 0.
- The control card stays at full opacity while Anon leans or kisses; only `act_controls` hides
  it.
- `act_controls` (default on) hides the whole control card without touching the cue, readiness
  line or close prompt, so the pony state readouts can stay while the hints are off.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`; `_end_session()` restores it on every exit path, and
  `_physics_process` also restores it if `IDLE` is ever reached while still marked hidden. The
  inventory's `_place_hotbar()` re-evaluates the state after restoring, so a stale pre-act layer
  flag cannot leave it hidden.
- The bottom-left stack reads, top to bottom: cue line `❤ N/3 | cue`, readiness line
  `Wants: intensity & pattern | You: intensity & pattern`, auto readout
  `Auto · 20–80% · 1.50/s · Normal` while auto is on, blank separator, controls.
- The `Wants`/`You` line and cue segment are gated by `hud_readouts`
  (default `true`). The hearts remain when readouts are off.
- Afterglow shows `❤ N/3 | close hint` instead of `Wants`/`You`. Missionary keeps lean, caress,
  caress movement and Y; standing keeps lean, reach, caress, caress movement, kiss and Y, while
  thrust, auto, smack and talk are hidden. The standing close hint is independent of
  `hud_readouts`.
- The afterglow summary is always shown and independent of `hud_readouts`: missionary puts it in
  the cue line, standing puts it on the readiness line under its close prompt. Early end shows no
  HUD summary.
- Love XP and happy mood are granted once by `main.memory.commit()` at afterglow, using the
  summary grade. `main.memory.commit()` (the `STAY_CLOSE` slot) may add a small extra romance,
  happy mood and private
  thought when the standing close window is completed on a good or non-early neutral act; after a
  bad act it repairs one point of history hurt instead. No other afterglow reward is granted.
- `captions_on_top`, default `true`, moves the game's desktop bottom caption to the top only
  when `access/speech_text` is the explicit bottom-caption mode; overhead and auto are untouched.

## Debug and testing

- The backtick command console is gated by `DEV.enabled()`. Source/editor runs have it; a
  player build unlocks it with **Settings → Updates** pressed five times. Acts own
  `controls_locked`, so the console is not available while an act is running.
- Debug actions live in `debug_actions.gd` and render as buttons in the **Debug** block of the tab
  their `tab` names (`general` by default, `anatomy` or `world`). Adding an
  action is one entry; give it a `hotkey` only when it must fire while the world is unpaused and
  you are looking at the scene. A hotkey-less action is the default.
- **Placement** (anatomy), **Placement tail**, **Placement dock**, **Placement tail tilt** and
  **Placement file**: edit, save, reset or log the selected placement target (global default or
  pointed mare). See `docs/anatomy.md`.
- **Trigger bed offer** / **Trigger standing offer**: force a proactive ask for the aimed (or
  nearest) test mare. They bypass the quiet, cooldown and AI-usage checks, but keep the eligibility
  gate (`docs/eligibility.md`), pose and free-bed gates; use them in the lab, which runs with
  `ai_usage=talk`. A rejected offer reports the failing gate (`relation`, `sex_bond`, `no_free_bed`,
  `standing:region`, and so on) in the status label and the debug log. Because the settings page
  pauses the tree, an offer advances after it closes.
- **Grant lover bond** / **Clear lover bond**: grant or clear the mod bond for the aimed (or
  nearest) mare. Grant uses the eligibility service, so it fails outside the adult, Promiscuity
  and kiss-willingness gates; clear always works. The gate is in `docs/eligibility.md`.
- **Reset act history**: clear the aimed or nearest mare's `act_history` row, including hurt and
  comfort. Use it in the lab between escalation runs.
- **Show act history**: print the aimed or nearest mare's stored row to the debug log, including
  tier, hurt/comfort, streaks, last grade and reasons, last text/wants, any stop cooldown, pending
  reminder/complaint and the recent entries. It does not modify the row.
- **Show prompt context**: print the aimed or nearest mare's `prompt_note()`,
  `lover_prompt_note()`, `cycle_note()`, history note, recent world-context events and the game's
  `standing_line()`. It does not modify anything; use it to see what the model actually receives
  when a line reads too eager or too quiet.
- **Force neglect warning** / **Force neglect stop**: act on the live act. The request is
  consumed on the next unpaused frame, so close the settings panel to apply it.
- **Force heat** / **Force diestrus** / **Clear forced cycle**: set the aimed or nearest mare's
  session-only estrus override. They work even when `features.estrus_cycle` is off, so the lab can
  test both phases without waiting in-game days.
- **Reload posed base**: re-read the hand-authored missionary base pose in place. A live act picks
  it up on its next frame; a bad file leaves the previous pose and reports the reason.
- **Show pose state**: print whether the pose asset is loaded (and why not), the asset
  version/bone count/shot block, the bed frame, where the live pose put the hips, neck, head and
  hooves in world and bed space, and the rig diagnostics: which skeleton the modifier drives, which
  skeleton every mesh is bound to, whether the pose survives to the next frame (`readback`), the
  posture state and every pony within 4 m. At the settled pose the act also prints two `pose trace`
  lines: the armature bone the placement is written to, and its world pose at the start of the
  modifier pass, right after the write and again at render time, against the authored target in the
  live bed frame.
- **Force act face** / **Show act face**: cycle the 22 base-game faces on the active act or the
  aimed/nearest mare for 3 s, and print the live act face, director face, climax mode, blush arc,
  fluster and mood face. The cycle never overrides a speaking line; the status label says so.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act while **Enable debug** is on. Neglect events log their warning/stop,
  tier, distress and dislike.
- `F4` (**Reload posed base**): re-read `poses/missionary_pose.json` without restarting. It works
  while an act runs, so export → reload tunes the pose live. Also a button in General's Debug block.
- `F10` (**Skeleton overlay**): toggle the skeleton overlay for nearby ponies. Lines are thin
  (`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible; hover a joint to turn it red,
  then left-click to print its bone name, parent, world/local origin, rotation, scale and rest.
- Logging follows **Enable debug** (General's last row); there is no separate log switch
  and no hotkey. It controls logging only.
- **Print perf logs** is a separate debug toggle, OFF by default. With **Enable debug** and
  **Print perf logs** on, an act prints one `perf` block a second: pony, pose, state, fps, frame
  time, `near_mesh`, sim tier, wing hold, then the per-second cost of every timed chunk (runtime
  process/physics, pose recipe, tail pose, body sway, ear twitch, caress, wings, kiss, camera
  motion, HUD). A chunk calls
  `runtime.perf_note()`, and `_perf_tick()` prints; use it to attribute a pony-specific stall
  instead of guessing. The window clears whenever the runtime is `IDLE`, so nothing prints
  outside an act. **Print perf logs** also prints `tail perf attach`/`tail perf refresh` one-shot
  lines and a once-per-second `tail perf seats=… skinned=… builds=…/s` line aggregating every live
  dock; steady state is `builds=0/s` because the blend runs on the GPU.
- **Hide tails** is the Anatomy debug tail-collapse toggle; see `docs/anatomy.md`.
- **Give footstool** and **Show stool state** are General debug actions; see `docs/stool.md`.
- `act_ear_pin` is one of General's ungrouped debug rows and defaults off. On, it pins the ears
  through `expressions.fluster()` for the whole act; off leaves the ears to the face beats and the
  climax fluster. It also forces full blush through the base fluster path, so it conflicts with
  `blush_arc`.
- Lab: `Shift+[` / `Shift+]` moves the previous/next adult mare in front of Anon, facing away,
  standing idle; non-starters are spawned on demand and the previous extra is despawned. `-`/`=`
  romance tier, `9`/`0` anger mood (the impression and its held face), Mouse4 bed invite, Mouse5
  sex-ready. Mouse5 grants the lover bond after the neutral mood reset, so the default gate is
  satisfied; startup leaves bonds unset. Mouse4 moves a mare farther than `8 m` (or on another
  floor) to the guest-bed approach before inviting, then waits for Anon's recline blend before the
  snuggle invite. Backtick (`` ` ``) toggles the debug console with a temporary control-lock
  release, so it also opens while Anon is lying down.
- The lab moves every test pony to her snapshot spot (`TEST_SPAWNS`) at startup, so they stand
  where the save left them; the library row is only a fallback. Its startup log lists every setup
  action (opening/tutorial handling, population restriction/prune, AI/time pauses, per-pony
  friendship/mood/idle, romance/dating, no spawned bed) and each pony's resulting position with
  `spawn=saved` or `spawn=row`.
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.

VR lab:

```bash
./lab-vr.sh [--no-service] [--vr-lab-autostart]
```

- Runs the same lab in room-scale XR under Monado and writes `last-run-vr.log`;
  `last-run-vr-monado.log` holds the runtime's log. The script starts `monado-service` with its
  qwerty driver (virtual HMD plus both hand controllers); `--no-service` uses one you started.
  The Monado window owns the keyboard while focused, so pose the headset there and keep the game
  focused for the lab keys. Seated VR cannot run this lab: that rig has no controllers. The
  cursor stays free for the Monado window; click the game window to capture it if you want the
  desktop lab's own mouse hotkeys.
- `tests/test_lab_vr.gd` adds a fake `waist` XRPositionalTracker, which `vr_act._tracked_hips()`
  accepts as body tracking: `[`/`]` move it 5 mm, `;` toggles a 1.1 Hz stroke, `F9` places Anon
  behind the aimed (or nearest) adult test mare. `--vr-lab-autostart` qualifies the nearest mare,
  starts the standing act and turns the stroke on for a scripted smoke run. The log prints state,
  thrust count, readiness and both preference axes once a second.
- A headset session has no desktop pointer: `headset_view()` stands in for a captured mouse in
  the start gate, the offer refresh, refusal and Y. A headset rig also has neither a
  `controls_locked` nor a `flying` property, so those reads compare against `true` rather than
  going through `bool()`. Only the standing act is supported in VR; it keeps the mare in place,
  so it never needs Anon's ground position from the rig root, which stays at the spawn anchor.

- Test every pose start, climax, afterglow, restore, hold-Y and cuddle path in the lab
  after changing camera, pose or scoring code.

## Voice routing and settings tab

- `voice_status.gd` classifies a profile with the game's own routing:
  `CHATTER.use_chatter(profile, tts.voice_mode)`. It reports `generated` (a character/openai
  voice exists) separately from `effective_ponese` (what will actually play now). A character
  voice still counts as effective Ponese when the global mode is `ponese`, TTS is off, or no
  server is configured.
- `runtime.debug_line()` includes the target's voice line.
- `mute_ponese_audio` mutes only the partner's `Voice` audio player for an act while keeping
  the generated text/HUD flow. It does not suppress dialogue.
- The Unfplap settings tab is **runtime-injected** with
  `Mods.on_node("res://world/ui/settings_page.gd", ...)`, not a `mod.json` extension. If the
  page's private fields are unavailable it logs and skips, so the settings page is never
  required for the mod to load.
- The injected tab also owns the per-mare **Characters** sub-tab: one pony selector with a name
  filter, enum controls from `preferences.gd`, neglect tolerance
  (`forgiving`/`normal`/`strict`), one Dislikes / No preference / Likes pill row per touch and talk
  action, one **Takes part in** row of `Acts` / `Anatomy` / `Tail` checks, and editable notes. The
  selector lists `SETTINGS.CHARACTER_ORDER` first, then any live
  adult mare with the mod's runtime that is not in that roster under an **Other mares** separator;
  an off-roster id uses her provider template when registered (`docs/api.md`), otherwise the
  global default profile, until a preset is saved. Preference edits are
  staged in the form and written only by **Save preset**, which applies live; **Reset to default**
  restores her built-in template plus any provider layer. The participation row shows the resolved
  values and a provider hint when a provider layer is in effect; a provider's `adult` assertion is
  shown read-only and only when it overrides the identity. Custom `event_prompts` and `poses` on the
  character entry must survive both actions.
- Injected pages/buttons are tracked and removed in `_exit_tree()`. Do not add `extends` for the
  settings page.

## Settings and persistence

**Every global setting is declared once, in `settings.gd`.** One declaration line names it, its JSON
path, label, help, tab, group, default and bounds; call sites use the typed accessor on the named
setting (`SETTINGS.act_vocals.get_bool()`, `SETTINGS.raise_m.set(0.2)`) and never a string path.
`settings_ui.gd` draws the panels from the declarations. Never add a widget, a defaults constant or
a save function for a setting anywhere else. A setting becomes a debug setting with `.as_debug()`,
which also removes its clamp. The full contract is `TUNING.md`.

- **Naming.** A declaration's identifier is its JSON path's last segment (`thrust.travel` →
  `travel`). Only on a collision with another setting does it gain the parent segment as a prefix
  (`jiggle.intensity` → `intensity`, but a second `intensity` would become `jiggle_intensity`). Keep
  names short; the group in the panel carries the context. Agents must not add group prefixes
  pre-emptively.

- `settings.json` path: `user://mods/data/unfplap/settings.json`
  (`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).
- The file is read once per process into memory (`SETTINGS._cache`) and written only when a value
  changes. Opening the Unfplap settings tab calls `SETTINGS.reload_file()`, so a hand-edited
  file applies when the tab opens; otherwise it needs a restart.
- Top level: `version`, `debug_mode`, `debug_perf`, `debug_hide_tails`, `features`,
  `relationship`, `thrust`, `auto_thrust`, `jiggle`, `camera_thrust`, `presentation`, `history`,
  `tolerance`, `cues`, `talk`, `player`, `anatomy`, `ui` (section open state), `default` template,
  `characters` overrides.
- Feature flags are declared under `features.*` in `settings.gd` and read through their typed
  accessor; the runtime snapshots them with every other act value in
  `_snapshot_settings()` at act start, and `apply_live_settings()` re-runs that snapshot after any
  settings edit. Keep these documented here when adding one:

| Flag | Default | Gates |
|---|---|---|
| `hud_readouts` | `true` | mood cue and `Wants`/`You` segments; hearts and the close prompt stay |
| `act_controls` | `true` | act control card; the cue and close prompt stay |
| `act_lines` | `true` | cue lines and climax/early-end reactions; off keeps normal dialogue and the HUD cue |
| `act_faces` | `true` | act face beats and `{face_note}` prompt hints; off keeps the current act faces; the blush arc and post-act mood face are separate |
| `blush_arc` | `true` | readiness-ramped act blush; off restores full blush from the first frame |
| `face_debug` | `false` | print act face changes, the climax score and the mood-face start/end |
| `act_history` | `true` | per-act summary, hurt/comfort, reminders and offer weighting; the history gate is in `docs/eligibility.md`; off keeps the old aftercare behaviour |
| `idle_camera_sway` | `true` | slow idle breathing when not leaning; false removes the drift |
| `captions_on_top` | `true` | move the explicit bottom caption to the top; applies immediately |
| `standing_body_sway` | `true` | standing body sway modifier; Anon's pinned hip follows the same offset |
| `missionary_body_motion` | `true` | missionary torso slide and head nod on the thrust |
| `thrust_ear_twitch` | `true` | standing thrust ear-twitch modifier |
| `standing_plant_feet` | `false` | hold Anon's hip and both foot targets at their act-start positions, feet 15 cm behind; true enables it |
| `standing_stool` | `true` | a live reach gap over `stool_gap_m` needs enough `goods:footstool` stacks of `stool_height_m`; the shop or house drops supply them |
| `act_ear_pin` | `false` | General debug rows: pin act ears |
| `estrus_cycle` | `false` | 30-day heat/diestrus cycle: heat warms faster, offers sooner and ignores privacy; diestrus blocks sex |
| `act_bystanders` | `true` | adult witness lines using the modern perception |
| `act_line_angles` | `true` | fresh cue-line angle and shared-history hint; widens recent-line recall to eight |
| `act_speech_feel` | `false` | thrust-paced interjection instruction in cue lines |
| `act_public_offer` | `true` | per-mare public consent affects offers; see `docs/eligibility.md` |
| `allow_act_during_cuddle` | `true` | allow starting an act while the stock cuddle session is active |
| `mute_ponese_audio` | `true` | mute a Ponese-only act voice but keep its text |
| `act_vocals` | `false` | pack climax moan only |
| `act_climax` | `false` | pack wet finish layer |

Always on: standing afterglow stay-close window, lean-camera inertia smoothing and strong-thrust
rump blush. Unknown settings keys are ignored. Caress feature flags and debug values are in
`docs/hands.md`; anatomy feature flags and debug values are in `docs/anatomy.md`.
- `anatomy` settings (mode, teats, strip, fluid, coat deform, dock/seat, mare bits, placement,
  player part, heat, fluid and their debug values) are declared once in `settings.gd`. Their
  behavior is in `docs/anatomy.md`; the declarations are the source for defaults and bounds.
  `anatomy_placement.gd` is the shared pure placement schema.
- `relationship.promiscuity` is a `choice`, default `any`; values `soulmates`,
  `head_over_hooves`, `marefriend`, `new_couple`, `crush` and `any` (label `Any Adult`).
- `relationship.sex_start` is a `choice`, default `try_luck` (label `Try Your Luck`); the other
  value is `when_available` (label `When Available`). Both store only the choice; the gate
  semantics and the corrected Try Your Luck rule are in `docs/eligibility.md`.
- The lover bond is stored in `Mods.state("unfplap").sex_bonds`. It never expires.
  `lover_accept` grants it; `lover_end` clears it. `main.gd` runs the stale-bond check every 2 s
  while idle. Bond validity and gate effects are in `docs/eligibility.md`.
- The per-mare act history is stored in `Mods.state("unfplap").act_history`; the score, points,
  tiers and repair rules are `HISTORY.md`. It never changes the base relationship stage and never
  calls `break_up`; the tier gate is in `docs/eligibility.md`.
- `thrust.orientation`: `"up"` (default) means mouse up deepens; `"down"` flips it.
  `thrust.pixels_per_cm` is the player's sensitivity, default `50` and clamped to `20…400`: mouse
  travel per centimetre of hip movement, so his shaft length sets one full stroke and a longer part
  needs proportionally more travel. `thrust.travel` is the non-anatomy hip backset multiplier,
  default `0.5`, clamped to `0.25…2.0×`. The old `pixels_per_full` is retired and mapped as
  `value / 20`.
- `auto_thrust` stores `pace` (thrusts/s, default `1.0`, clamped `1.0…3.75`), `min_depth`
  (bottom, default `0`, clamped `0…0.82`) and `max_depth` (peak, default `0.5`, clamped
  `0.20…1`), plus `curve` (`Auto shape`, default `thrust`, one of the five waveforms). They are
  act-start defaults; the wheel, mouse and hold-X layer changes are per-act, except `curve`, which
  applies live and is written by the layer's `Z`. The wheel and `E`/`D` step is the fixed
  `0.25/s`; the depth step is a fixed 5 %. `thrust.contact_gap_m` (Contact gap, default `0 cm`,
  `0…12 cm`) is how close the stroke must get to its deepest point for the body slap.
- `jiggle` stores the shared rump wobble `radius` in metres (default `0.26`), the thrust
  `intensity` multiplier (default `0.2`) and the act-smack `smack_intensity` multiplier
  (default `0.45`). The center is the hind-femur midpoint plus `center_height_m` (default
  `0.10 m`) and `center_back_m` (default `0.15 m`). It is read live with the other thrust
  controls.
- `camera_thrust` stores `surge` and `bob`, both `0…1`; defaults `1.0` and `0.35`. They scale the
  speed-driven camera travel and apply live during an act.
- `anatomy.placement` and `anatomy.placement_target` are the shared placement block and editor
  target. Their structure and migration are in `TUNING.md`; their behavior is in
  `docs/anatomy.md`.
- `presentation` is split per pose:
  - Top-level `presentation.lean_back_m` (default `0.08 m`) is the player-facing back-lean
    distance used by both cameras and the planted lower body.
  - `act`: `climax_mode` (debug choice `auto`/`fluster`/`ooo`/`wide`, default `wide`) picks the
    climax expression from the live act quality when it is `auto`.
  - `missionary`: `camera_mode`, `third_person`, `free_look` and the debug `anon_size_match`
    (0 keeps Anon human-sized, 1 scales him uniformly with her). The per-size block under
    `size.<preset>` keys `canon`, `mounting`, `same height` and `hoers` and holds
    `head_clearance_mm` and `gaze_offset_mm` for the shot. The anatomy values
    (`disable_fold_coloring`, `part_inset_m` and the vulva trims/hug) are in `docs/anatomy.md`.
  - `standing`: `glance_back_speed`, `torso_angle_deg`,
    `neck_down_deg` (default `30°`), `chin_up_deg` (default `30°`), `tail` with `yaw_deg`
    (default `35°`) and `pitch_deg` (default `25°`), and `smack` with `raise_m` (default
    `0.30 m`), `hind_m` (default `0.09 m`), `height_m`
    (default `0.05 m`, signed), `arc_m` (default `0.10 m`), `pitch_deg` (default `0°`),
    `raise_speed` (default `1.5 m/s`) and `return_speed` (default `3.0 m/s`). The smack values
    are experimental/unbounded.
  - Caress settings are in `docs/hands.md`.
  - The legacy flat presentation block migrates once in `_normalize_presentation()`; its
    obsolete camera key is dropped.
- **Never clamp a debug setting.** A debug `num` (`.as_debug()`) is stored and returned verbatim;
  its `with_range` bounds only limit the spin box arrows, so a hand-edited out-of-range value still
  applies. A player-facing `num` clamps to its `with_range` bounds, and only because that bound is
  part of the contract (sensitivity `240…1200`, hip back-off `0.25…2.0×`, auto pace
  `1.0…3.75/s`, auto depth `0.20…1`, camera surge/bob `0…1`, glance speed `0.25…3×`, genital tone
  `0…1`). Do not add a clamp in a consumer "to be safe": if a value must be bounded to stay
  playable, give it `with_range` and say so in the help text.
  No consumer clamps a setting-derived value today; the jiggle radius, smack raise,
  smack arc and caress oval radii are applied as stored. A consumer may only guard a value that
  would otherwise divide by zero (the anon part base/mid/head/length/girth scales); that guard is
  a math floor, not a user-facing bound. The only other bounds are the smack
  animation duration (`0.12–0.30 s` raise, `0.06–0.20 s` return), which bound the slide, not the
  setting.
- Feature flags are ordinary settings under `features.`; their tab and `.as_debug()` decide where
  they appear. Label, help and section all come from the declaration; there is no separate feature
  info table.
- The injected tab has nested **General**, **Anatomy**, **World** and **Characters** sub-tabs, in
  that order. General, Anatomy and World are drawn from the declarations by `settings_ui.gd`: one
  row per setting, grouped into click-to-collapse sections from its `group` (`"Standing › Smack"`
  is a subheading under `Standing`). A section name draws exactly one heading; declarations that
  interleave another group fold back into their first heading. Player-facing settings come first;
  when **Enable debug** (General's last row) is on, the tab ends with one **Debug** section holding
  that tab's debug
  settings under the same group names, with its own `Debug/<group>` collapse state. Every section
  remembers whether it is open in `settings.json` under `ui.sections`, keyed `tab/group`. The panel
  is built from the game's own menu pieces, so it reads as part of the page rather than beside it:
  `main.gd` imports `world/ui/menu_style.gd`, the sub-tabs are Segment-look pills set on the
  `TabContainer`'s inner **TabBar** (an override on the container does not reach the bar) with the
  container's own `panel` and `tabbar_background` emptied, and a section heading is the `Tab`
  variation, whose pink accent shows the section is open.
  `settings_ui.gd` draws each setting as the page's own `_row_idle`/`_row_hover` card (falling back
  to the same `menu_style` box), keeps the help text on a `Faint` label, shows a boolean as a switch
  with its Off/On state, and renders a choice of at most four short labels as a pill track; longer
  choices keep the themed dropdown. Number rows get a double-width spin box so large values and
  units are not clipped; a declaration with `.with_slider()` draws a themed HSlider with its value
  beside it instead. The sidebar row sits under an **Add-ons** caption, and the injected page has no
  second title. Settings with no group render at the top of the tab without a heading; a group
  needs at least three related settings to earn one. **General** is one ungrouped list in this
  order: Starting Sex, Show controls, Show HUD readouts, Show captions on top, Mute Ponese audio,
  Allow act lines, Show act expressions, Use precise caress, Caress quality, Remember acts, Climax limit, Sensitivity, Thrust direction,
  Use Anon bed body, Use VR act, Use footstool, Allow hole switch, Allow oral, Allow finish control, then the
  **Enable debug** switch. Its Debug block holds the perf-log and act-ear switches, the **Act face**
  section (climax face, blush arc, face log), auto thrust (pace, bottom, peak,
  shape), the contact gap, the hip back-off and acts
  during cuddles, then **Camera**, **Talk & cues**, **Missionary** (body motion, Anon size
  match, Cock base inset, a **Size** dropdown over the six per-size vulva/clearance/gaze values,
  fold/hug hacks, Use free look), **Standing** (with **Motion**, **Kiss** and **Smack**
  subheadings) and **Thrust jiggle** sections. Caress controls are in `docs/hands.md`.
  **Anatomy**
  opens with its ungrouped switches, then **Holes**, **Heat**, **Anon part**, **Placement** and
  **Actions**.
  **World** opens with Promiscuity and the estrus switch, and its Debug block holds the witnesses,
  ponies, the two
  cue-line switches, per-mare **History** and **Neglect tolerance**. **Characters** holds
  the hand-built **Character preference** form (a per-mare profile, not a global setting). The
  **Actions** buttons sit at the bottom of each tab's **Debug** section, in compact rows; an action
  appears only in its own tab. The declaration-drawn pages have no Save buttons: each edit writes
  its setting and
  calls `main._apply_settings_changed()`, which refreshes the flags, the caption position and the
  active act. The hand-built Characters form is the exception: it stages edits and writes them only
  when **Save preset** is pressed.
- `debug_mode` and `debug_perf` default to `false`.
- `characters.<id>` stores only the player's differences from her resolved template; the built-in
  templates are not materialized in the file. A known mare's base is her template in
  `character_preferences.gd`, then any mod provider layer (see `docs/api.md`), then `default`; so
  removing her saved override restores that chain rather than the global default.
- `characters.<id>.profile` is a sparse per-mare participation layer. `profile.participation`
  holds `acts`, `anatomy` and `tail`; only differences from the resolved default are stored. A
  provider's `adult` assertion is top-level and never a player value. The `characters` block is the
  same per-mare block as the preference, consent, prompt and pose overrides.
- `participation.gd` resolves the per-mare participation block: the built-in default, the provider
  layer, then the player's `characters.<id>.profile.participation` differences. The gate semantics
  are in `docs/eligibility.md`; the attachment and tail gates are in `docs/anatomy.md`.
- Key fields: `smack_zone_radius`, `aftercare_min`, `cue_gap`, `preferences`, `consent`, `profile`,
  `act_prompts`, `event_prompts` (`climax`, `end_early`),
  `poses.missionary`, `poses.standing`. `cue_gap` is a per-character JSON value, not a settings-tab
  control. The global default preference note is `Open to affection.`; every character template
  carries its own note. `act_prompts` stores only overrides: the built-ins live in
  `DEFAULT_ACT_PROMPTS` and `_fill_prompts()` supplies them at read time. Known legacy values and
  obsolete keys are removed on load; the **Reset act prompts** debug action clears overrides.
- The settings editor lists `SETTINGS.CHARACTER_ORDER` (103 IDs: every spawnable mare in
  the base game, the original sixteen first) and uses `CHARACTER_NAMES` for display labels. Every
  base ID has a preference template in `character_preferences.gd`; add a pony there when expanding
  the roster. Live adult mares outside that roster are appended under **Other mares**; a mare
  registered by another mod uses her provider template (`docs/api.md`), an unregistered one uses
  the global default profile until a preset is saved. Their `characters.<id>` block is preserved
  like any other.
- Pose defaults live in `poses/catalog.gd`; preference defaults and validation live in
  `character_preferences.gd`, `preferences.gd` and `settings.gd`.

## Settings authoring rules for agents

- Add a setting with one declaration line in `settings.gd` and read it with its typed accessor;
  never add a widget, a default constant, a path-keyed read or a save function anywhere else.
- `SETTINGS.block(prefix)` is the only bulk read. Per-act snapshots stay in
  `runtime._snapshot_settings()`; do not add another cache.
- **Do not add per-setting tests.** A declaration is compile-checked (name, accessor and kind), so
  the only assertions are the ones in `tests/test_settings.gd`: registry integrity, defaults, the
  file round-trip, clamping versus debug bypass, validation, section state, the panel drawing every
  declaration, migration and the per-mare merge. Extend that file only for new API behaviour.
- A retired setting is one `deprecated()` entry in `settings.gd` with its mapping; bump
  `SCHEMA_VERSION` only for a structural change in `_migrate()`. Neither needs a manual file edit.
- **A group needs at least three related settings.** Fewer, and the setting goes directly in the
  tab (or its Debug block) with `group` empty and no heading; a subgroup that small merges into its
  parent section. `tests/test_settings.gd` enforces the rule.
- The Debug block is gated by `debug_mode` and toggles live: `settings_ui.build()` returns the
  block and `main.gd` keeps it to show or hide. Put new debug-only settings behind `.as_debug()`;
  the Actions buttons live inside the Debug block of the action's tab.
- A debug action that belongs with others shares a `row` caption and a `short` label in
  `debug_actions.gd`; consecutive entries with the same row render on one line.
- The Anatomy Actions block starts with the **Placement target** pill (`Default` / `Pointed
  mare`), backed by the persisted hidden `anatomy.placement_target` setting. The Placement
  buttons then edit the selected target; Default stages a preview until Save, and Save writes the
  ten `anatomy.placement.default.*` settings.
- **A boolean label starts with a verb**: Show, Allow, Use, Play, Print, Hide, Pin, Sway, Twitch,
  Remember, Mute. Label the action the switch performs, not the noun it controls
  (“Show controls”, “Allow act lines”, “Remember acts”, “Use VR act”). Choices and numbers keep
  their noun label. Push back if a verb label reads worse than the noun; say so in the review
  rather than forcing it.

## Documentation discipline

This is mandatory.

- Update the contract in the same commit as behavior, settings or controls. Put rationale,
  measurements and tuning history in the code comment or the contract doc; commits are one line.
- Never leave stale paths, removed controls, obsolete constants or incorrect claims. Remove
  obsolete documentation instead of keeping historical notes.
- A system contract lives only in its owning doc (`docs/hands.md`, `docs/eligibility.md`,
  `docs/anatomy.md`, `PREFERENCES.md`, `HISTORY.md`, `ROTATION.md`, `TUNING.md`). Other docs link
  there and do not restate its paths, contact, settings or debug controls.
- `AGENTS.md` holds project-wide practices, the architecture rules and the docs index; a system
  detail belongs in its contract, not here.
- Verify every claim against code before writing it. If docs and code disagree, fix the docs or
  the code in the same change.
- `README.md` rule:
  - Only update **CONTROLS** and **FEATURES** unless the user explicitly asks for another
    section.
  - Do not list debug controls in README.
  - Features are concise, high-level and one sentence each. No history, implementation detail
    or architectural reasoning.
  - Do not rewrite or reformat the rest of README.
- Keep `AGENTS.md`, `README.md`, `PREFERENCES.md`, `ROTATION.md`, `TUNING.md`, `WORKFLOW.md`,
  `docs/hands.md`, `docs/eligibility.md`, `docs/anatomy.md`, `assets/README.md` and the release
  skill consistent.

## Known constraints

- The stock 0.3.0 bed is size-aware: `eligible()` accepts up to `1.05 * Settings.pony_scale()`
  and `_mare_fits` scales her half of the lane and her length with her size. A bed too short for
  a Hoers or Same Height mare is refused; that is stock behavior, not a mod override.
- `[go_to_bed]` keeps a `sleep:` navigator lease even while she lies awake by day. A bed-side
  offer through that lease is valid only for `bed_side`/`already_lying` when she is not sleeping
  and `posture_status().requested == "lie_down"`; walking to bed or sleeping is not.
- "Same Height as Anon" now follows Anon's `player/height_cm`. The mod's lean scale, standing gap
  and caress offsets follow the same multiplier; see `docs/hands.md`. Other size presets keep
  their authored values.
- Standing kiss offsets, the missionary virtual mouth and kiss lean distances scale with Anon's chosen
  height (`Settings.anon_height_scale()`), matching `player/player_mouth.gd`.
- `captions_on_top` is mod-owned: `main.gd` finds `SpeechCaption` through `Mods.on_node`, then
  moves its private `_card` to the top margin after the caption's own layout pass. It skips the
  settings-page preview and quietly does nothing if the card fields disappear.
- The stock bed captures a snuggle guest's rest transform at invite time from the player's
  reclined hip/head targets. Inviting before that blend settles puts the target at standing
  height, so `hop_clear` fails and the guest never climbs on. The lab waits `1.2 s` after lying
  down before inviting; the rejoin waits `CUDDLE_REJOIN_SETTLE_S`.
- `SharedBed.accept()` is dead code in this game version: it calls `invite(actor, null)` and
  `invite()` rejects a null seat. Re-invite a mare into a bed with `invite(actor, seats[1])`.
- The talk classifier in `preferences.gd` is a small keyword map, not an LLM call. Expand it
  only from real playtest phrasing, and keep `talk` empty for mares who should not score it.
- A mare from another mod needs the game's pony locomotion and hybrid rig: an adult identity, a
  stable id, `pony_hips` for the anatomy mesh, `MareBody` for teats/strip/body-coat deform, and
  `hair_skeleton` plus `OpenPonyDock` for tail seating. Acts still need the eligibility runtime
  described in `docs/eligibility.md`.
