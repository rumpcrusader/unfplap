# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file
adds the working knowledge for `unfplap` only. Keep it current; it is the source of truth for
agents, not a design diary.

## Required reading by task

Do not start implementation until you have read the required files for the area you are touching.

| Task | Read first |
|---|---|
| Any task | `res://mods/AGENTS.md`, then this file |
| Pump, scoring, preferences, strength | `PREFERENCES.md`, `pump.gd`, `preferences.gd` |
| Pose, skeleton, camera | `ROTATION.md`, `poses/` |
| Controls or features | `README.md` (edit only CONTROLS and FEATURES) |
| Settings or character profiles | `settings.gd`, `poses/catalog.gd`, `PREFERENCES.md` |

## Identity and scope

- Mod id `unfplap`; current public version `0.0.2`; target game `0.1.1-maredev`
  (`project.godot` reports `0.1.0-maredev`).
- Adult mares and stallions only. Human Anon and AnonPony.
- Marefriend/Coltfriend or later. Consent is `bonds.welcomes(id, "kiss")`; refusal is real.
- Exactly two poses: `missionary` on a bed/couch and `horse` standing.
- No pregnancy, heat, estrus, conception, content warning, toggle, new models, genitals or
  anatomy. The act stays off-camera by framing.
- Desktop first. VR and seated VR are deferred; desktop human Anon owns the free act camera.
- The user-facing summary is `README.md`. Technical contracts are `PREFERENCES.md` and
  `ROTATION.md`.

## Workflow

Run from source:

```bash
godot --xr-mode off --path <project> -- --mod-src unfplap
```

Manual lab:

```bash
godot --xr-mode off --path <project> -- \
  --mod-src unfplap --skip-title \
  --lab res://mods/unfplap/tests/test_lab.gd
```

Isolated test world:

```bash
godot --xr-mode off --path <project> -- \
  --mod-src unfplap --skip-title \
  --world-id unfplap-test \
  --lab res://mods/unfplap/tests/test_lab.gd
```

- The lab loads only Twilight, Fluttershy, Rarity and Derpy, pauses world scheduling and
  background AI, and uses the Golden Oak guest bed. It does not spawn a test bed.
- `worlds/unfplap-test/` is the isolated lab world; `worlds/default/` is untouched. Delete only
  the test world to reset it.
- The lab re-seeds its four mares on every startup (romance tier, dating record, mood, idle
  posture) but leaves them where the world spawned them. The rest of the world's context and
  inventory persist.

Tests:

```bash
for t in test_catalog test_settings test_source_hygiene test_rotation \
         test_pump test_preferences test_utterance test_runtime_pump; do
  godot --headless --xr-mode off --path <project> \
    --script res://mods/unfplap/tests/$t.gd
done
```

- Current passing state: `CATALOG` 13, `SETTINGS` 40, `SOURCE_HYGIENE` 37 checks / 39 files,
  `ROTATION` 8, `PUMP` 25, `PREFERENCES` 37, `UTTERANCE` 23, `RUNTIME_PUMP` 5.
- Update these counts when tests change. A stale count is a docs bug.
- Build only when the user asks:
  ```bash
  godot --headless --xr-mode off --path <project> \
    --script res://tools/modding/build_mod.gd -- unfplap --out <file.pck>
  ```
  Success prints `MOD_BUILT <path>`.
- Do not leave a `.pck` in the source project's live mods folder while testing `--mod-src`; it
  shadows source edits.
- `mods/unfplap/README.md` and `mods/unfplap/AGENTS.md` are excluded from the pack by the
  builder.

## Architecture and important files

```text
mods/unfplap/
  mod.json          id, version, game_version, entry
  main.gd           Mods hooks, runtime attachment, offers, HUD/input creation,
                    DEBUG LOGS toggle, F8/F9/F10 debug helpers
  runtime.gd        per-pony state machine, gates, start, pump scoring/strength,
                    free/legacy camera, climax, afterglow/withdrawal, restore, aftercare
  pump.gd           pure stroke tracker: reversal, timeout, speed, peak speed, strength
  preferences.gd    pure depth profiles, speed zones, shape classification, bands
  utterance.gd      pure act-line schedule and prompt formatting
  anon_thrust.gd    wraps the desktop Anon pose driver for the pose-2 hip thrust
  chin_debug.gd     always-on debug head pitch for Alt+7 / Alt+8
  debug_skeleton.gd F10 skeleton line/circle overlay with hover and joint inspection
  poses/            skeleton driver, rig cache, rotation helpers, recipes, catalog
  hud.gd            three meters, hints and debug-gated satisfaction
  hud_pump.gd       vertical depth bar
  hud_bar.gd        satisfaction/stamina fill bars
  input.gd          L, hold-Q, F camera toggle, key consumption, debug keys
  settings.gd       persisted DEBUG LOGS, pump controls and per-character templates
  memory.gd         world_context events, climax impression, witnesses, reactions
  rest_control.gd   release pony_seating and shared_bed/couch without standing
  aftercare.gd      10 s post-act tail-up/flick, navigator hold, sex_aftercare gate
  tail_pose.gd      tail aside/lift/flick on the hair skeleton
  witness.gd        witness pass
  ai_offer.gd       strictly private house-only spoken offer
  tests/            unit/source-hygiene tests + manual test_lab.gd
  PREFERENCES.md    pump/scoring/preference/strength contract
  ROTATION.md       pose, skeleton and camera positioning contract
```

Entry script only. No script extensions, game-file edits or JSON merges. The former bed-size
extension is parked because release builds ship compiled `.gdc` scripts that the mod loader
cannot subclass.

## Critical: poses and skeleton work

Read `poses/` and `ROTATION.md` before changing a pose. Rotate bones, never stretch them, and do
not leave the pony outside her joint limits. Use `pose_rig.gd` for the bone cache and
body-relative axes.

### Pose 1: missionary

- Recipe order is load-bearing:
  1. `_straighten_spine_neck()`
  2. `_align_chain_straight()`
  3. `_level_body_roll()`
  4. `_level_chest_roll()`
- `_straighten_spine_neck()` must reset the **pelvis** (`pony_hips`) as well as spine and neck.
  The bed's lie pose rotates the pelvis; leaving it alone tilts the rump while the shoulders are
  straight.
- `_align_chain_straight()` measures each bone toward the next bone's origin. Keep `pony_head`
  in the list so `pony_neck2` has a target direction, but **never rotate the head bone itself**:
  its `basis.z` is not the face axis and rotating it twists the face 90°.
- Pelvis roll and chest roll are separate. The pelvis uses the hind-femur line; the chest uses
  the front upper-arm line. Wrap measured left/right line angles into ±90° or the correction can
  roll her belly-down.
- `POSE1_ROLL_TWEAK` (radians) offsets the pelvis correction if needed.
- `POSE1_RUMP_DROP_DEG` pitches the whole body about the shoulders; `POSE1_HIND_SPREAD` sets
  hind-leg spread.
- Bed context is not optional: the lie pose, mattress surface and shared-bed transform all
  affect the result. F9 has no lie pose, so use the lab bed for the real check.
- Start waits for player rest ≥ 0.99 and the pony's `lie_down` to settle.

### Pose 2: horse

- Stance: `STANDING_BOW = 2.4`, `STANDING_FORELEG = 2.0`, `STANDING_HIND_SPREAD = 0.16`.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.35`, Hoers `0.55`.
- Body facing is locked every physics tick at priority 100; the navigator must not turn her.
- Glances use `pony.secondary.look_toward` plus optional `head_back`; pupils follow Anon through
  `eye_motion.target_world`.
- Tail aside/lift/flick is applied down the hair chain; the side is randomized per act.
- Withdrawal eases back, flicks twice, records the inside event, then restores automatically.
- Pose 2 has no afterglow.

## Critical: camera work

### Modes

- Free mode is the default for desktop human Anon.
- `F` toggles free/legacy during the act and logs the mode. Outside the act `F` is flight.
- Free mode: mouse does not turn the view; vertical mouse still pumps.
- Legacy mode: pose-1 `_pose1_free_yaw/pitch` and pose-2 `_act_look` with
  `ACT_LOOK_YAW_SCALE = 0.10`, `ACT_LOOK_PITCH_SCALE = 0.10`.
- AnonPony and headset/VR use legacy behavior; do not create a free camera there.

### Pose 1 shot

- Mod-owned `UnfplapPose1View`, top-level, at
  `root + up * 0.55 - back * 0.15`.
- Aim: sample `_snout()` during the 1 s blend, then freeze that point. Do not follow the live
  nose afterwards; she nuzzles.
- Free mode: WASD rotates the shot at `CAMERA_LOOK_SPEED = 1.0 rad/s`; W/S pitch
  (`±POSE1_FREE_PITCH_LIMIT = 1.0`), A/D yaw (`±POSE1_FREE_YAW_LIMIT = 1.2`). It never
  translates Anon.
- Free mode sets `player.controls_locked = true` for **both** poses, so WASD cannot walk, jump,
  shift on the bed, or start couch actions. Save and restore the prior value on legacy toggle
  and act end.
- Legacy mode adds mouse yaw/pitch offsets; no look cone.

### Pose 2 shot

- Uses the player's eye camera. Pose-2 height still comes through
  `_stand_eye`/`_eye_height`; do not teleport the rig.
- Aim: sample the joint that connects her head and neck (`pony_head` origin, then the
  `pony_neck2` fallback) during the 1 s blend, then freeze.
- Free mode: WASD rotates the player camera; W/S pitch and A/D yaw, clamped to the same
  `LOOK_YAW_LIMIT`/`LOOK_PITCH_LIMIT` 45° cone used by legacy look. It never translates Anon.
- Free mode owns `controls_locked` for pose 2 too, so Anon does not walk while the camera moves.
- Legacy mode: 45° look cone around the captured look yaw.
- On restore, restore the player yaw/pitch to the **captured start values**, not the act base
  aim, and reset `camera.rotation.x`.

### Bob and restore

- Climax bob is untouched by camera mode.
- Pump bobs are opt-in through `pump.bobs` (default `false`); both pump and climax bob are
  skipped when off.
- Pose-1 vertical bob uses `POSE1_BOB_SCALE = 0.35`; pose 2 uses the full value.
- Restore order is load-bearing:
  1. release the free-camera control lock;
  2. remove the Anon thrust wrapper;
  3. restore eye override and hidden avatar;
  4. free the pose-1 view;
  5. restore the pose-2 camera position;
  6. restore player look, then the pose-1 snapshot/cuddle.
- Pose 1 snapshots camera + current camera, player transform and pony transform/posture. Keep
  that snapshot exact; the bed cuddle re-invite depends on it.

## Critical: pump scoring and strength

`pump.gd` is pure and has no scene access. It tracks raw depth and closes a stroke on a
direction reversal or `STROKE_TIMEOUT_S = 0.18 s`.

- A **stroke** is continuous movement in one direction.
- A **pump** is an inward stroke with `travel >= PUMP_MIN_TRAVEL = 0.25`.
- Base gain is `Σ |Δd| × depth_weight(d)`. A full `0→1→0` at `steady` is exactly `2.0`.
- Inward strokes get the speed and shape multipliers; outward strokes score base gain only.
- Combined multiplier is capped to `0.40–1.80`.
- `climax_at` is per pony (`100` default). Stamina starts/resets at `400`, drains `1` per pump,
  and does not affect scoring.
- The HUD reads raw `depth` directly. There is no penetration inertia spring.

Every closed stroke becomes one result with:
`direction`, `start_depth`, `end_depth`, `travel`, `duration`, `speed`, `peak_speed`,
`base_gain`, `scaled_gain`, `pump`, `shape`, `speed_zone`, `multiplier`, `strength`.

Physical strength is independent of per-mare preference scoring:

```text
strength = clamp(travel × clamp(peak_speed / 1.0, 0.35, 1.5), 0, 1)
```

- Strength drives jiggle (`_start_jiggle` clamp `0.30–1.0`, then `JIGGLE_RUMP_SCALE = 3.5`)
  and wing flick (`0.10→0.24`). It does not drive the pose-2 hip.
- Pose-2 thrust follows raw `depth` directly: `THRUST_MAX_M = 0.045 m` forward at full depth,
  no spring, no return animation. `anon_thrust.gd` wraps the desktop Anon
  `desktop_pose_driver`, forwards the original torso/rest-hand methods, then offsets
  `%HipsTarget` forward. Restore the original driver at act end.
- Wing motion is deliberately slow during an act: fade `1.10 s`, flick decay `0.90 s`,
  spread `4 s`, droop `20 s`, jitter `0.8–2.0 s` with a `0.4 s` fade. A pump may not restart
  the game's `flutter()` before its complete `0.90 s` cycle.
- Climax hearts use three pulses with at least `1 s` between them:
  - pulse 1 at `t = 0`: four `celebrate()` bursts;
  - pulse 2 at `t >= 1 s`: two bursts;
  - pulse 3 at least `1 s` after pulse 2: one burst.
  Each burst is five hearts, no boop count or squeak.
- A separate `celebrate()` burst starts from her dock (`mTail1`) at the exact climax start.
- Pose 1 keeps the bed avatar hidden and uses the strength-scaled jiggle for now.
- Current plap audio is unchanged. Future mod-owned plap clips should select from the result's
  `strength`, `travel`, `depth`, `speed`, `speed_zone` and `shape`.
- Do **not** add a pump debug sub-gate. The per-stroke/pump log is the scoring view.

Read `PREFERENCES.md` for the exact depth profiles, speed windows, shape curves, bands,
multiplier rules, phases and character profiles.

## Act flow, gates and controls

- Eligibility: adult, not filly/colt, player not young, love level ≥ 2, and
  `bonds.welcomes(id, "kiss")`.
- Pose 1: Human Anon uses the seated/lying bed path; AnonPony uses the already-lying path. Pose 2:
  standing/settled.
- Start only when free/idle; another pony's conversation, active task or conflicting navigator
  lease blocks. Player conversation is free.
- `kiss_hold` owns movement hold; `pony_kisser` physics is paused so it cannot remove it.
- `Q` is a `0.35 s` hold, matching bridal-carry initiation. A tap does nothing. Hold Q cancels
  before climax and ends pose-1 afterglow; Q is ignored in `CLIMAX`, `WITHDRAW` and `RESTORE`.
- States: `IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW` (pose 1) or `WITHDRAW` (pose 2) →
  `RESTORE`.
- Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.
- Aftercare starts only at final satisfaction ≥ 10; it holds navigator ownership for 10 s and
  keeps the tail raised straight with reduced flicks.
- Memory uses the game's second-person phrasing. Witnesses are nearby awake adults; sleeping
  ponies and fillies/colts are skipped.
- AI offer is strictly private and house-only.

## Dialogue utterances

- `min_utterances`/`max_utterances` are clamped `0…8`; `min ≤ max`; the act picks one count.
- Scheduled points are satisfaction thresholds over `8–92%` of `climax_at`, jittered with a
  minimum gap. They are generated on demand, not prefetched.
- One mod line may be pending at a time. A new line needs an idle director and pony, plus
  `UTTERANCE_MIN_GAP_S = 6 s` since the previous line started.
- The pending slot stays reserved until speech actually stops and a 1 s release hold passes.
  A queued line has a 60 s safety timeout only if it never starts; in-progress speech is never
  invalidated.
- Points crossed while a line is pending are skipped and accepted. `max_utterances` caps scheduled
  points only; reactive speed/shape/depth/bored lines are extra.
- Climax logs and cancels an in-flight act line before queueing the climax reaction. End and
  inside reactions always queue. Only the cached “Mm.” is used; generated moans are parked.
- Cancelling the act with `Q` does **not** cancel the current utterance. Act-line validity is
  tied to the pony/event id, not `State.ACTIVE`, and `_restore_begin()` no longer clears the
  pending/release state. Explicit `_cancel_pending_utterance` calls still cancel at climax or
  afterglow boundaries.

## HUD and rewards

- Three vertical meters, left to right: penetration, satisfaction, stamina.
- Depth is shown only during `ACTIVE`; satisfaction/stamina remain through `CLIMAX`;
  afterglow/withdrawal hide all meters. Satisfaction is hidden unless DEBUG LOGS is on.
- The HUD reads raw `depth`; there is no smoothing spring.
- Love XP and happy mood are granted only by `MEMORY.commit_climax()` on a completed climax.
  Afterglow and withdrawal grant no extra reward.

## Debug and testing

Keep this section concise; do not rebuild the removed debug-key catalogue.

- `Ctrl+Shift+D`: master DEBUG LOGS toggle; default ON; persists in
  `user://mods/data/unfplap/settings.json`.
- `F8`: offer/gate/bed report plus target pump data.
- `F9`: pose-1 floating preview and one-shot `POSE1` dump.
- `F10`: toggle the skeleton overlay for nearby ponies. Lines and joint circles are visible;
  hover a joint to turn it red, then click to print its bone name, parent, world/local origin,
  rotation, scale and rest.
- `Alt+7` / `Alt+8`: raise/lower the debug chin pitch by `5°` and log head/chin/snout world
  positions. The `chin_debug.gd` modifier works while idle, lying, standing or during an act;
  when nothing is under the crosshair it targets the nearest mare within `8 m`.
- `F`: free/legacy camera toggle during an act.
- Lab: `-`/`=` romance tier, `9`/`0` anger mood, Mouse4 invite to bed, Mouse5 sex-ready.
- The lab never teleports mares; they stay at their world spawn positions. Its startup log lists
  every setup action (opening/tutorial handling, population restriction/prune, AI/time pauses,
  per-mare friendship/romance/dating/mood/idle setup, no spawned bed).
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.
- Do not document or reintroduce removed debug keys or historical debug modes.
- Test every pose start, climax, afterglow/withdraw, restore, hold-Q and cuddle path in the lab
  after changing camera, pose or scoring code.

## Settings and persistence

- `settings.json` path: `user://mods/data/unfplap/settings.json`
  (`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).
- Top level: `debug_logs`, `pump`, `default` template, `characters` overrides.
- `pump.orientation`: `"up"` (default) means mouse up deepens and the top of the bar is
  deep/orange; `"down"` flips both. `pump.pixels_per_full` defaults to `600`; `pump.bobs`
  defaults to `false`.
- `debug_logs` defaults to `true`.
- Character entries inherit unspecified fields from `default`.
- Key fields: `min_utterances`, `max_utterances`, `climax_at` (`1…100`), `aftercare_min`,
  `preferences.pump`, `act_prompts`, `event_prompts`, `poses.missionary`, `poses.horse`.
- Pose defaults live in `poses/catalog.gd`; pump defaults and validation live in
  `preferences.gd`/`settings.gd`.
- No migration shims. Pre-release dev keys are ignored, not translated.

## Documentation discipline

This is mandatory.

- Update documentation in the same change as behavior, settings, controls or test-count changes.
- Never leave stale paths, removed controls, obsolete constants, old test counts or incorrect
  claims. Remove obsolete documentation instead of keeping historical notes.
- Keep camera, pose, pump and strength details here and in `PREFERENCES.md`/`ROTATION.md`.
  Summarize non-critical areas such as debug logs; do not build long catalogues.
- Verify every claim against code before writing it. If docs and code disagree, fix the docs or
  the code in the same change.
- `README.md` rule:
  - Only update **CONTROLS** and **FEATURES** unless the user explicitly asks for another
    section.
  - Do not list debug controls in README.
  - Mark experimental controls `(experimental)`.
  - Features are concise, high-level and one sentence each. No history, implementation detail
    or architectural reasoning.
  - Do not rewrite or reformat the rest of README.
- Keep `AGENTS.md`, `README.md`, `PREFERENCES.md`, `ROTATION.md` and the test counts consistent.

## Open tuning and limitations

- Pose-2 head-neck aim pitch may need a visual pass at the default gap/size.
- Pose-1 camera and pose-1 Anon body/thrust visibility still need an in-game visual pass.
- Bed-cuddle size gate is the stock `1.05`; JRHNBR, Same Height and Hoers bed cuddles are out of
  scope in release packs because `ext/shared_bed.gd` is parked against compiled `.gdc` bases.
- Slow-stroke plap audio and custom plap clips are future work.
- `runtime.gd` still contains the deferred structural cleanup (splitting the missionary and
  horse state, and consolidating start/restore paths); no third pose is planned.
- `README.md` is user-maintained except CONTROLS and FEATURES.
