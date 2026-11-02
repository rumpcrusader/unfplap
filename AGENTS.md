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
| Pose, skeleton, camera, act actions | `ROTATION.md`, `poses/` |
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
  posture) and moves them to a row on the path in front of Golden Oak Library. The rest of the
  world's context and inventory persist.

Tests:

```bash
for t in test_catalog test_settings test_source_hygiene test_rotation \
         test_pump test_preferences test_utterance test_runtime_pump test_voice \
         test_actions; do
  godot --headless --xr-mode off --path <project> \
    --script res://mods/unfplap/tests/$t.gd
done
```

- Current passing state: `CATALOG` 13, `SETTINGS` 48, `SOURCE_HYGIENE` 43 checks / 46 files,
  `ROTATION` 8, `PUMP` 25, `PREFERENCES` 37, `UTTERANCE` 23, `RUNTIME_PUMP` 5, `VOICE` 9,
  `ACTIONS` 46.
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
                    DEBUG LOGS toggle, settings-tab injection, F8/F9/F10 debug helpers
  runtime.gd        per-pony state machine, gates, start, pump scoring/strength,
                    act camera lean, pose actions/smack, climax, afterglow,
                    restore, aftercare
  pump.gd           pure stroke tracker: reversal, timeout, speed, peak speed, strength
  preferences.gd    pure depth profiles, speed zones, shape classification, bands
  utterance.gd      pure act-line schedule and prompt formatting
  anon_thrust.gd    wraps the desktop Anon pose driver for the pose-2 hip thrust
  body_sway.gd      depth-driven pose-2 upper-body sway with planted forehooves
  ear_twitch.gd     eased random pump ear twitch on the head skeleton
  chin_debug.gd     always-on debug head pitch for Alt+7 / Alt+8
  debug_skeleton.gd F10 skeleton line/circle overlay with hover and joint inspection
  voice_status.gd   pure character-voice/Ponese classification
  poses/            skeleton driver, rig cache, rotation helpers, recipes, catalog
  hud.gd            three meters, hints and debug-gated satisfaction
  hud_pump.gd       vertical depth bar
  hud_bar.gd        satisfaction/stamina fill bars
  input.gd          Y start/end, right-click smack routing, key consumption, debug keys
  settings.gd       persisted DEBUG LOGS, pump controls and per-character templates
  memory.gd         world_context events, climax impression, witnesses, reactions
  rest_control.gd   release pony_seating and shared_bed/couch without standing
  aftercare.gd      10 s post-act tail-up/flick, navigator hold, sex_aftercare gate
  outdoor_bed.gd    installs a usable bed outside Golden Oak Library
  ext/shared_bed.gd lifts the stock 1.05 body-scale cap for bed cuddles
  tail_pose.gd      tail aside/lift/flick + pump jiggle on the hair skeleton
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
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`.
- Body facing is locked every physics tick at priority 100; the navigator must not turn her.
- Glances use `pony.secondary.look_toward` plus optional `head_back`; pupils follow Anon through
  `eye_motion.target_world`.
- Tail aside/lift/flick is applied down the hair chain; the side is randomized per act.
  `poses.<pose>.tail_lift` defaults to `0.42` and is inherited/overridable per mare.
- Pose 2 enters the same held `AFTERGLOW` state after climax. Lean and A/D caress stay live
  there; hold Y ends it. Her tail lifts and flicks twice, and the inside event/reaction is
  recorded on entry. No automatic withdrawal/restore.

## Critical: camera work

### Modes and lean

- Desktop human Anon always uses the mod-controlled act camera.
- AnonPony and headset/VR keep the stock camera; they do not receive lean or act actions.
- Mouse motion does not turn the view; vertical mouse motion still pumps.
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
  Canon (`0.66`) is `1.34` (+34%). Pose-1 Canon camera height is also multiplied by `0.9`.
- Pose-2 Anon body lean: the camera/head moves forward or sideways, and `apply_anon_lean()`
  cancels the same translation on the pelvis. The hips stay planted behind her rump while the
  torso hinges over her, instead of the whole body sliding forward and clipping. Pull-back
  still moves the whole body away.
- Experiment: `ANON_PUMP_SWAY_M = 0.02` moves the pelvis back on the inward stroke, so Anon's
  chest/upper body travels forward and back with the pump.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- `camera_inertia` smooths the displayed lean at `CAMERA_INERTIA_SMOOTH = 5.0`.
- `Q`/`E` fire their pose action at `LEAN_FIRE = 0.75` and release at
  `LEAN_RELEASE = 0.60`. The action is latched while above release.
- `lean_return` (default `true`) gates the slow automatic return to neutral. With it off, a
  released lean holds its position until the player leans the other way or the act ends.
- `H` toggles the same return mode during an act. In hold mode the camera lean gets a small,
  slow rocking offset (`0.015` forward / `0.0125` side, clamped inside `-1…1`) so Anon never
  becomes fully static or leaves the normal lean range.
- Lean and actions are available in both `ACTIVE` and `CLIMAX`; every other state ends them.
- The lean camera owns `player.controls_locked = true` for both poses. Save and restore the
  prior value at act end.
- `F` is not an act control in pose 1. In pose 2, holding `F` at a full side lean
  (`abs(side) >= POSE2_KISS_LEAN = 0.90`) starts the same base-game kiss; outside an act it
  remains the game's flight key.

### Pose 1 shot

- Mod-owned `UnfplapPose1View`, top-level, anchored at
  `root + up * (0.45 + POSE1_CAMERA_LIFT_M(0.10)) - back * 0.22`, then pulled
  `POSE1_CAMERA_PULLBACK_M = 0.20` back along its own frozen view axis. Canon height is `0.9×`.
  The view copies and restores the source camera's `fov`, `near`, `far` and `cull_mask`.
  Do not bake the pullback into the world-space anchor; that moved the shot vertically and
  broke the aim. The aim basis is always rebuilt from `_pose1_camera`, never the already moved
  view, to avoid a start-up feedback flicker.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) during the 1 s
  blend, then freeze. The live snout can end up behind the bed camera, so it is no longer used.
- A forward-dot check re-aims the view if the cached basis points away from the target.
- Lean is applied on top of the frozen base basis. `Q` also starts the act kiss; `E` has no
  extra action. Pose 1 uses the same pump bob and roll/pitch rock as pose 2.

### Pose 2 shot

- Uses the player's eye camera. Pose-2 height still comes through
  `_stand_eye`/`_eye_height`; do not teleport the rig.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) during the 1 s blend,
  then freeze. Lean yaw/pitch are applied on top.
- Pose-2 camera has a smoother, stronger roll-plus-pitch rock on each pump:
  `CAMERA_ROCK_IMPULSE = 0.20`, `CAMERA_ROCK_LIMIT = 0.026`, stiffness `45`, damping `8.0`;
  pitch is `0.45×` the roll.
- Lean owns `controls_locked` for pose 2 too, so Anon does not walk while the camera moves.
- On restore, restore the player yaw/pitch to the **captured start values**, not the act base
  aim, and reset `camera.rotation.x` and `.z`.

### Pose 2 body language

- `body_sway.gd` translates `pony_spine1` with a damped spring driven by raw `depth`. It is
  inverted for this pass: the upper body rocks **back** on the inward stroke and **forward** on
  the outward stroke. The chest, neck and head follow; `pony_upperArm_L/R` origins are restored
  afterward so the forehooves stay planted. `BODY_SWAY_MAX_M = 0.035` is deliberately exaggerated
  for review; park it near `0.012`.
- Strong pumps (`strength >= 0.55`) build a subtle rump blush decal by `0.035` per pump, capped
  at `0.25` (the smack decal uses `0.8`). It decays slowly and is removed at act end.
- Base posture adds `chin_up_deg = 30` (head) and `neck_down_deg = 15` total (neck1/neck2), giving
  the chin-up, snout-reaching S-curve. The debug chin modifier remains additive.
- `foreleg_spread` is the absolute outward half-angle from the body centreline. The default
  `0.172 rad` matches the current rest placement; `_spread_fore()` measures the current hoof line
  and rotates the upper arms only by the difference.
- `poses.horse.hind_spread` defaults to `0.32`; Rarity no longer needs an override.
- Ears keep the current fluster/pinned baseline. `ear_twitch.gd` flicks **both** ear roots
  together: a shared forward/back pitch plus a sideways twitch that moves both ears outward or
  both toward the head. The per-ear sign is derived from the ear root's lateral offset, never a
  shared world-side rotation.
- `tail_pose.gd` also rocks the tail on the same pump cadence: a damped spring from raw `depth`
  drives a sagittal swing (`ROCK_PITCH = 0.12`) and a smaller lateral wag (`ROCK_YAW = 0.08`).
  Pump jiggle strength and the pose-2 camera height scale with pony size: Canon gets
  `_jiggle_size_scale() = 0.66`, a `CANON_POSE2_CAMERA_DROP_M = 0.10` lower eye line, and
  `_pose2_lean_scale()` multiplied by `0.8`.
  Every pump also calls `tail.pump(strength)`: a short `JIGGLE_DECAY = 3.6` /
  `JIGGLE_FREQ = 18` wave with the same strength as the rump shader, strongest at the dock
  (`mTail1`) and lagging down the chain (`JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`). This is
  the cheapest way to make rump jiggle and tail read as one motion; the shader itself stays
  native.
- Look-back glances clamp yaw to `GLANCE_BACK_YAW = 1.62` and add 20% to
  `glance_back_pitch` (base `1.2`, boosted to `1.44`).

### Act actions

Pose support lives in `lean_action_kind()` in `runtime.gd`:

| Input | Missionary | Horse |
|---|---|---|
| `Q` | kiss | left-hand reach to her left shoulder |
| `E` | none (lean only) | right-hand reach to her right shoulder |
| `A` / `D` | none | slow left/right flank caress |
| `F` (hold) | none | kiss at a full shoulder lean |
| Mouse right | left/right cheek opposite the lean | same |

- The kiss reuses the game's own path: temporarily clear `controls_locked` for
  `pony_kisser.begin_from_pony()`, move `AffectionPose` last in the skeleton so its IK layers on
  the act pose, and call `Affection.end()` on release. This gives the normal face, mouth,
  deep-kiss and soft-kiss audio behaviour. The fallback custom head-aim path only runs if the
  base kiss cannot start. Like a base kiss it may stop the pony's current speech, but it does
  not interrupt pumping or stats. `_check_running()` treats the act's own `Affection`-driven
  `kiss` as part of the act instead of an interruption.
- The shoulder reach uses `desktop_anon.set_hold_target(..., "rub")` through `anon_thrust.gd`,
  so it does not need `request_action()` and does not fight `controls_locked`. `rub` keeps the
  hand open. Hand-marker convention: local `-Z` is the fingers, `+Y` is the thumb/up, and the
  palm normal is `-X` on the right hand / `+X` on the left. The shoulder target uses the pony's
  body basis, so fingers continue straight forward, thumbs up and palms inward. It interpolates
  from the current rest hand over `REACH_HAND_BLEND_S = 0.35`, and release blends back to that
  rest frame over `REACH_HAND_RELEASE_S = 0.35` before the hold is cleared. A one-shot
  `reach hand side=... x=... y=... z=... fingers=... palm=...` log prints the convention.
- A/D caress uses the same hold-target path with an oval rub (`CARESS_RADIUS_M = 0.055`,
  `CARESS_SPEED_RAD_S = 4.5`) lifted `CARESS_SURFACE_LIFT_M = 0.085` off the coat. The oval is
  `CARESS_OVAL_ACROSS = 1.30` along the body and `CARESS_OVAL_UP = 0.70` vertically, so it reads
  as a stroke rather than a perfect circle. Point offsets are per size in `CARESS_PROFILES`:
  Canon `up 0.08`, JRHNBR `up 0.16 / out 0.02` (both hands 4 cm wider), Same Height and Hoers
  step up from there. Both A and D can run at once, one hand per side. The centre interpolates
  with the lean: backward lean moves it toward the rump top as soon as it passes zero
  (`CARESS_RUMP_LEAN = 0.5`), no lean = flank, half forward lean = side/belly, full lean = the
  exact same shoulder point used by the Q/E reach. The circle radius scales with pony size;
  the point offsets are already per size. It is horse-only.
- While a shoulder reach is held, `_forced_glance` locks the pony's glance over that shoulder
  and suppresses the random glance scheduler; release clears it.
- Smack calls the native `FlankTouch.impact(index, at)` with `index 0 = left cheek`,
  `1 = right cheek`. `at` shifts the mark centre `0.08 m` up and `0.08 m` back, then jitters
  within `SMACK_ZONE_RADIUS_M = 0.035` around that point. The hand swings in/out over
  `SMACK_SWING_SECONDS = 0.20`, impacts at `SMACK_CONTACT_PHASE = 0.45`, and has a
  `SMACK_COOLDOWN_MS = 200` gate.
- It reuses the slap sound/decal/blush/jiggle. The pony's `physical_reaction` connections are
  temporarily disconnected around the call, so `flank_smack` cannot trigger the game's
  buck/fidget/hoof shuffle or a bond/context/memory/satisfaction/stamina event.
- A right lean (`side > 0`) selects the left cheek; a left lean selects the right cheek; exactly
  centered picks one of the two real cheek points at random. There is no rump target.

### Bob and restore

- Climax bob is untouched by camera mode.
- Pump bobs are opt-in through `pump.bobs` (default `false`); both pump and climax bob are
  skipped when off.
- Vertical bob intensity is doubled: `BOB_PUMP_IMPULSE = 2.30 / 3` and
  `BOB_CLIMAX_AMPLITUDE = 0.025 / 3`; forward bob is unchanged.
- Pose 1 and pose 2 use the same vertical bob and pump camera rock.
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

- Strength drives jiggle (`_start_jiggle` clamp `0.30–1.0`, then `JIGGLE_RUMP_SCALE = 2.8`)
  and wing flick (`0.10→0.24`). Jiggle amount is also multiplied by
  `_jiggle_size_scale() = clamp(size_scale, 0.5, 1.2)`; Canon (`0.66`) is `0.66×`. It does not
  drive the pose-2 hip.
- Pose-2 thrust follows raw `depth` directly: `THRUST_MAX_M = 0.045 m` forward at full depth,
  no spring, no return animation. `anon_thrust.gd` wraps the desktop Anon
  `desktop_pose_driver`, forwards the original torso/rest-hand methods plus hold targets, then
  offsets `%HipsTarget` forward. Restore the original driver at act end.
- Wing motion is deliberately slow during an act: fade `2.20 s`, flick decay `1.80 s`,
  spread `8 s`, droop `40 s`, jitter `1.6–4.0 s` with a `0.8 s` fade. The game's `flutter()`
  is rate-limited to `1.80 s` between calls, and the fallback spread timer is `2 s`. Pose 2
  starts from `WING_POSE2_HOLD = 0.65` (about `60°` above the ground) and opens by
  `WING_POSE2_SPREAD = 0.25` as satisfaction rises. Pose 1 keeps the stock spread progression.
- Climax hearts use three pulses with at least `1 s` between them:
  - pulse 1 at `t = 0`: four `celebrate()` bursts;
  - pulse 2 at `t >= 1 s`: two bursts;
  - pulse 3 at least `1 s` after pulse 2: one burst.
  Each burst is five hearts, no boop count or squeak.
- A separate `celebrate()` burst starts from her dock (`mTail1`) at the exact climax start.
- Pose 1 keeps the bed avatar hidden and uses the strength-scaled jiggle for now.
- Current plap audio is unchanged, but its emitter is the rump point (`_rump_point()`) in both
  poses. Future mod-owned plap clips should select from the result's `strength`, `travel`,
  `depth`, `speed`, `speed_zone` and `shape`.
- Do **not** add a pump debug sub-gate. The per-stroke/pump log is the scoring view.

Read `PREFERENCES.md` for the exact depth profiles, speed windows, shape curves, bands,
multiplier rules, phases and character profiles.

## Act flow, gates and controls

- Eligibility: adult, not filly/colt, player not young, love level ≥ 2, and
  `bonds.welcomes(id, "kiss")`.
- Pose 1: Human Anon uses the seated/lying bed path; AnonPony uses the already-lying path. Pose 2:
  standing/settled.
- Start only when free/idle; another pony's conversation, active task or conflicting navigator
  lease blocks. Player conversation is free. The `cuddle_override` flag (default `true`) lets an
  act start through an active stock cuddle session; the start path ends that session first.
- The runtime's automatic cuddle suppression runs only outside `IDLE`, so the stock bed/couch
  cuddle still works when no act is running.
- During the act the quick-slot inventory HUD is hidden and restored at end.
- `kiss_hold` owns movement hold; `pony_kisser` physics is paused so it cannot remove it.
- Act actions: `W`/`S` lean forward/back, `Q`/`E` side lean plus pose reaction, `A`/`D` caress,
  `F` hold kiss in pose 2, mouse right smacks, `H` toggles lean hold. They are available in
  `ACTIVE`, `CLIMAX`, and the horse `AFTERGLOW`; `Y` is the context start/end control.
- `Y` starts an act when idle and is a `0.35 s` hold to cancel/end while active, matching
  bridal-carry initiation. A tap does nothing. Hold Y cancels before climax and ends pose-1
  afterglow; Y is ignored in `CLIMAX` and `RESTORE` except for event consumption.
  `T` remains the game's talk key and is not consumed. `Q` is free for future left/right
  actions; during an act it is still consumed so the game's stand-up action cannot interrupt
  the scene.
- States: `IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE` for both poses.
- Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.
- Aftercare starts only at final satisfaction ≥ 10; it holds navigator ownership for 10 s and
  keeps the tail raised straight with reduced flicks.
- Memory uses the game's second-person phrasing. Witnesses are nearby awake adults; sleeping
  ponies and fillies/colts are skipped.
- AI offer is strictly private and house-only.

## Dialogue utterances

- `min_utterances`/`max_utterances` are clamped `0…3`; `min ≤ max`; the act picks one count.
  This is a global chattiness cap even if a saved profile asks for more.
- Scheduled points are satisfaction thresholds over `8–92%` of `climax_at`, jittered with a
  minimum gap. They are generated on demand, not prefetched.
- One mod line may be pending at a time. A new line needs an idle director and pony, plus
  `UTTERANCE_MIN_GAP_S = 6 s` since the previous line started.
- The pending slot stays reserved until speech actually stops and a 1 s release hold passes.
  A queued line has a 60 s safety timeout only if it never starts; in-progress speech is never
  invalidated.
- Points crossed while a line is pending are skipped and accepted. `max_utterances` caps scheduled
  points only; reactive `speed_perfect`, `shape_like`/`shape_dislike`, `depth_deep` and `bored`
  lines are extra. Speed slow/fast and depth-shallow reactions were removed.
- Climax drops queued act lines but keeps an in-progress one, then queues the climax reaction.
  End and inside reactions always queue. Only the cached “Mm.” is used; generated moans are parked.
- Cancelling the act with `Y` does **not** cancel a line that is already being thought or
  spoken. `_drop_queued_utterance()` keeps the active authored line and drops only queued ones;
  it runs at climax, afterglow and restore. Act-line validity is tied to the pony/event id, not
  `State.ACTIVE`.

## HUD and rewards

- The native offer hint uses the game's `button_y` icon plus `· sex`; the HUD fallback text is
  `Y · sex`, matching the game's small-dot separator.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`; the previous state is restored at end.
- Three vertical meters, left to right: penetration, satisfaction, stamina.
- Depth is shown only during `ACTIVE`; satisfaction/stamina remain through `CLIMAX`;
  afterglow hides all meters. Satisfaction is hidden unless DEBUG LOGS is on.
- The HUD reads raw `depth`; there is no smoothing spring.
- Love XP and happy mood are granted only by `MEMORY.commit_climax()` on a completed climax.
  Afterglow grants no extra reward.

## Debug and testing

Keep this section concise; do not rebuild the removed debug-key catalogue.

- `Ctrl+Shift+D`: master DEBUG LOGS toggle; default ON; persists in
  `user://mods/data/unfplap/settings.json`.
- `F8`: offer/gate/bed report plus target pump data.
- `F9`: pose-1 floating preview and one-shot `POSE1` dump.
- `F10`: toggle the skeleton overlay for nearby ponies. Lines are thin
  (`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible;
  hover a joint to turn it red, then click to print its bone name, parent, world/local origin,
  rotation, scale and rest.
- `Alt+7` / `Alt+8`: raise/lower the debug chin pitch by `5°` and log head/chin/snout world
  positions. The `chin_debug.gd` modifier works while idle, lying, standing or during an act;
  when nothing is under the crosshair it targets the nearest mare within `8 m`.
- `Ctrl+Shift+V`: log a `VOICES` block for loaded ponies (generated vs effective Ponese).
- Lab: `-`/`=` romance tier, `9`/`0` anger mood, Mouse4 invite to bed, Mouse5 sex-ready. Mouse4
  moves a mare farther than `8 m` (or on another floor) to the guest-bed approach before inviting,
  then waits for Anon's recline blend before the snuggle invite. Backtick (`` ` ``) toggles the
  debug console with a temporary control-lock release, so it also opens while Anon is lying down.
- The lab teleports the four mares in front of Golden Oak Library at startup. Its startup log lists
  every setup action (opening/tutorial handling, population restriction/prune, AI/time pauses,
  per-mare friendship/romance/dating/mood/idle setup, no spawned bed).
- Multi-line diagnostics are one entry: identification line first, then tab-indented rows.
- Do not document or reintroduce removed debug keys or historical debug modes.
- Test every pose start, climax, afterglow, restore, hold-Y and cuddle path in the lab
  after changing camera, pose or scoring code.

## Voice routing and settings tab

- `voice_status.gd` classifies a profile with the game's own routing:
  `CHATTER.use_chatter(profile, tts.voice_mode)`. It reports `generated` (a character/openai
  voice exists) separately from `effective_ponese` (what will actually play now). A character
  voice still counts as effective Ponese when the global mode is `ponese`, TTS is off, or no
  server is configured.
- `Ctrl+Shift+V` logs a `VOICES` block for loaded ponies; `F8` includes the target's voice line.
- `act_text_only_ponese` mutes only the partner's `Voice` audio player for an act while keeping
  the generated text/HUD flow. It does not suppress dialogue.
- The Unfplap settings tab is **runtime-injected** with
  `Mods.on_node("res://world/ui/settings_page.gd", ...)`, not a `mod.json` extension. If
  `settings_tab` is false it returns before touching the page. If the page's private fields are
  unavailable it logs and skips. This avoids the old release-breaking extension attempt.
- Injected pages/buttons are tracked and removed in `_exit_tree()`. Do not add `extends` for the
  settings page.

## Settings and persistence

- `settings.json` path: `user://mods/data/unfplap/settings.json`
  (`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).
- Top level: `debug_logs`, `features`, `pump`, `default` template, `characters` overrides.
- Experimental feature flags live in `SETTINGS.FEATURE_DEFAULTS`; the runtime caches
  `SETTINGS.features()` at act start. Keep these documented here when adding one:

| Flag | Default | Gates |
|---|---|---|
| `settings_tab` | `true` | runtime-injected Unfplap settings tab; false = no page mutation |
| `lean_return` | `true` | auto-return the lean channel when keys are released; false holds position |
| `camera_inertia` | `true` | smoothed lean look/settle |
| `camera_rock` | `true` | pose-2 pump roll/pitch rock |
| `body_sway` | `true` | pose-2 upper-body sway modifier |
| `rump_blush` | `true` | strong-pump rump blush decal |
| `ear_twitch` | `true` | pose-2 pump ear-twitch modifier |
| `cuddle_override` | `true` | allow starting an act while the stock cuddle session is active |
| `act_text_only_ponese` | `false` | mute a Ponese-only act voice but keep its text |
- `pump.orientation`: `"up"` (default) means mouse up deepens and the top of the bar is
  deep/orange; `"down"` flips both. `pump.pixels_per_full` defaults to `600`; `pump.bobs`
  defaults to `false`.
- `debug_logs` defaults to `true`.
- Character entries inherit unspecified fields from `default`.
- Key fields: `min_utterances`, `max_utterances`, `smack_zone_radius`, `climax_at` (`1…100`), `aftercare_min`,
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

- Pose-1 camera sits at `camera_height = 0.45 + 0.10` / `camera_forward = 0.22`, then pulls
  `0.20 m` back along its own view axis and uses the middle of the neck. Debug logs every
  `100 ms` for the first `2.5 s` show anchor, view, basis, target, dot, bed, pose amount, lean
  and size.
- Pose-2 neck aim, body sway amplitude, camera inertia/rock and ear twitch still need a visual pass.
- Lean amounts, side yaw (`3°`), forced shoulder look and the base-kiss reuse are first-pass
  values; tune in the lab. Verify the pose-2 `60°` wing start and the per-size caress points
  visually.
- Verify `foreleg_spread = 0.172` preserves the current foreleg stance in the lab; tune if needed.
- `BODY_SWAY_MAX_M` is intentionally exaggerated at `0.035 m`; reduce toward `0.012 m`.
- `outdoor_bed.gd` installs `UnfplapOutdoorBed` beside Golden Oak Library on world ready (retry
  deferred if the house group is not populated yet). It is a normal pony bed; aim at it to let
  Seating install the shared-bed rest. Verify its spot is pathable and does not block the door.
- `ext/shared_bed.gd` lifts the stock `1.05` bed-cuddle body-scale cap. It lowers the numeric
  `body_scale` only for the synchronous `eligible()` check, then restores it, so JRHNBR, Same
  Height and Hoers mares can share a bed. It also tries the bed's authored `side_local` approach
  before the generic side, which the Golden Oak guest nook needs. Verify the built pack still
  logs `unfplap extends res://world/relationships/shared_bed.gd`.
- The stock bed captures a snuggle guest's rest transform at invite time from the player's
  reclined hip/head targets. Inviting before that blend settles puts the target at standing
  height, so `hop_clear` fails and the guest never climbs on. The lab waits `1.2 s` after lying
  down before inviting.
- Slow-stroke plap audio and custom plap clips are future work.
- `runtime.gd` still contains the deferred structural cleanup (splitting the missionary and
  horse state, and consolidating start/restore paths); no third pose is planned.
- `README.md` is user-maintained except CONTROLS and FEATURES.
