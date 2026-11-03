# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file
adds the working knowledge for `unfplap` only. Keep it current; it is the source of truth for
agents, not a design diary.

## Required reading by task

Do not start implementation until you have read the required files for the area you are touching.

| Task | Read first |
|---|---|
| Any task | `res://mods/AGENTS.md`, then this file, then `WORKFLOW.md` |
| ACTIVE readiness, taste, strength | `PREFERENCES.md`, `thrust.gd`, `preferences.gd`, `utterance.gd` |
| Pose, skeleton, camera, act actions | `ROTATION.md`, `poses/` |
| Controls or features | `README.md` (edit only CONTROLS and FEATURES) |
| Settings or character profiles | `settings.gd`, `poses/catalog.gd`, `PREFERENCES.md` |

## Identity and scope

- Mod id `unfplap`; current public version `0.0.3`; target game `0.1.1-maredev`
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

Read `WORKFLOW.md` before any task. Commit in small, testable units; never push.

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

Tests (manual, before every commit):

```bash
scripts/test_all.sh
```

Source smoke:

```bash
scripts/smoke.sh
```

- `test_all.sh` runs every suite, prints each `RESULT` line and exits nonzero on any failure.
  The printed output is the current state; do not copy counts into docs.
- Build only when the user asks:
  ```bash
  godot --headless --xr-mode off --path <project> \
    --script res://tools/modding/build_mod.gd -- unfplap --out <file.pck> [--no-extends]
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
                    DEBUG LOGS toggle, settings-tab injection with guard, thrust/camera-rock and
                    taste editors, F8/F9/F10 debug helpers
  runtime.gd        per-pony state machine, gates, start, ACTIVE readiness/talk,
                    act camera lean, pose actions/smack, climax, afterglow/close window,
                    restore, aftercare
  thrust.gd         pure stroke tracker: reversal hysteresis, timeout, travel, speed, strength
  preferences.gd    pure taste profile, intensity/rhythm and talk classification
  utterance.gd      pure prompt formatting
  relationship_cue.gd pure relationship/tone formatting and peak-memory gate
  anon_thrust.gd    wraps the desktop Anon pose driver for the pose-2 hip thrust
  palm_scale.gd     pose-2 hand-bone scale, restored when the act ends
  body_sway.gd      depth-driven pose-2 upper-body sway with planted forehooves
  prone_sway.gd     pose-1 lying torso slide and head nod on the thrust
  ear_twitch.gd     eased random thrust ear twitch on the head skeleton
  wing_sweep.gd     pose-2 wing root sweep after the game's WingTuck modifier
  chin_debug.gd     always-on debug head pitch for Alt+7 / Alt+8
  debug_skeleton.gd F10 skeleton line/circle overlay with hover and joint inspection
  voice_status.gd   pure character-voice/Ponese classification
  poses/            skeleton driver, rig cache, rotation helpers, recipes, catalog
  hud.gd            bottom-left controls list, combined status line, readiness meter and close cue
  readiness_bar.gd  pure short 0–100 readiness fill; no ticks
  input.gd          Y start/end, right-click smack routing, key consumption, debug keys
  settings.gd       persisted DEBUG LOGS, thrust/camera-rock controls and per-character taste
  memory.gd         world_context events, climax impression, witnesses, reactions
  rest_control.gd   release pony_seating and shared_bed/couch without standing
  aftercare.gd      10 s post-act tail-up/flick, navigator hold, sex_aftercare gate
  ext/shared_bed.gd lifts the stock 1.05 body-scale cap for bed cuddles
  tail_pose.gd      tail aside/lift/flick + thrust jiggle on the hair skeleton
  witness.gd        witness pass
  initiation.gd     proactive requests: privacy, approach, ask/reminders, horse invitation
  tests/            unit/source-hygiene tests + manual test_lab.gd
  PREFERENCES.md    taste/readiness/strength contract
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
- `_neck_lift(neck_lift_deg)` bends `pony_neck1`/`pony_neck2` about the body right axis and
  lifts her head off the mattress. Default `15°`. It runs **before** the gaze solve, so it
  changes head position without biasing the final face direction. In the standing model this
  bend is chin-down; the supine body turns it into an upward head lift.
- `_aim_gaze()` is a true shortest-arc solve from her current face direction to Anon, using the
  current `pony_head` frame plus `HybridNeckLink`'s fixed `pony_head → mHead` offset. Do not
  replace it with absolute yaw/pitch from the body axis: that assumed a standing rest
  orientation and left the missionary head aimed at the ceiling. The nuzzle offsets the target
  by a few degrees rather than adding a second absolute aim.
- `POSE1_RUMP_DROP_DEG` pitches the whole body about the shoulders; `POSE1_HIND_SPREAD` sets
  hind-leg spread.
- Bed context is not optional: the lie pose, mattress surface and shared-bed transform all
  affect the result. F9 has no lie pose, so use the lab bed for the real check.
- Start waits for player rest ≥ 0.99 and the pony's `lie_down` to settle.

### Pose 2: horse

- Stance: `STANDING_BOW = 2.4`, `STANDING_FORELEG = 2.0`, `STANDING_HIND_SPREAD = 0.16`.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`.
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
  `poses.<pose>.tail_lift` defaults to `0.42` and is inherited/overridable per mare.
- Pose 2 enters the same held `AFTERGLOW` state when the player chooses it or the third pony
  climax forces it. Lean and A/D caress stay live there; hold Y ends it. Her tail lifts and
  flicks twice, and the inside event/reaction is recorded on entry. A separate `stay_close`
  line follows the inside line, and the 8 s HUD close window counts active caress time. No
  automatic withdrawal/restore.

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
  Canon (`0.66`) is `1.34` (+34%). Pose-1 Canon camera height is also multiplied by `0.9`.
- Pose-2 Anon body lean: the camera/head moves forward or sideways, and `apply_anon_lean()`
  cancels the same translation on the pelvis. The hips stay planted behind her rump while the
  torso hinges over her, instead of the whole body sliding forward and clipping. Pull-back
  still moves the whole body away.
- `ANON_THRUST_SWAY_M = 0.02` moves the pelvis back on the inward stroke, so Anon's chest and
  upper body travel forward and back with the thrust.
- The hip is **depth-driven**. `_hip_phase` is the mouse `depth` low-passed by
  `HIP_SMOOTH_S = 0.04 s`; `apply_anon_thrust()` moves the hip by
  `THRUST_MAX_M = 0.045 * body_scale * phase`, and `apply_anon_lean()` counter-moves the pelvis
  by `ANON_THRUST_SWAY_M * phase * lean_scale`. There is no speed/strength attack and no return
  spring.
- The camera is **speed-driven**, never an impulse. The physics tick filters the signed depth
  speed (`CAM_SPEED_SMOOTH_S = 0.06`) and `_camera_thrust_tick()` follows it with one critically
  damped response (`CAM_RESPONSE_S = 0.12`). `CAM_SPEED_REF = 4.0` depth/s reaches full travel;
  outward strokes use `CAM_BACK_RATIO = 0.5`. The bob target is negative, so the camera dips
  toward her on the inward stroke and rises on the return.
- `presentation.horse.torso_angle_deg` (default `15`, experimental/unbounded) hinges Anon's
  upper body forward over her. `apply_anon_lean()` counters the hip and pins the feet;
  `apply_camera_motion()` moves the head/camera along the spine arc
  (`ANON_TORSO_LEN_M = 0.65`). It applies live.
- Pose-2 palms are scaled absolutely per body preset from
  `presentation.horse.caress.palm_scale`: Canon `0.85`, JRHNBR `0.95`, same height/hoers
  `1.0`. The settings tab edits the selected size. `palm_scale.gd` runs after BodyIK and
  restores the cached bone scales in `_remove_anon_thrust()` on every act exit. Marker scaling
  would be discarded by the IK solver.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- The displayed lean is always smoothed at `CAMERA_INERTIA_SMOOTH = 5.0`.
- `Q`/`E` fire their pose action at `LEAN_FIRE = 0.75` and release at
  `LEAN_RELEASE = 0.60`. The action is latched while above release.
- The lean always holds a released position. `_lean_step()` only ramps toward a pressed target;
  the explicit `S` shoulder recentre uses `return_to_zero`. The act end and paused paths still
  return the lean over `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default on) the camera lean gets a small, slow rocking offset
  (`0.010` forward / `0.0084` side, clamped inside `-1…1`). A/D caress always latches: tap once
  to keep rubbing after release, tap again to stop. Pressing `S` arms a gradual side return, so
  the shoulder roll decays to neutral without leaning the other way.
- Lean and actions are available in both `ACTIVE` and `CLIMAX`; every other state ends them.
- The lean camera owns `player.controls_locked = true` for both poses. Save and restore the
  prior value at act end.
- `F` is not an act control in pose 1. In pose 2, holding `F` at a full side lean
  (`abs(side) >= POSE2_KISS_LEAN = 0.90`) starts the same base-game kiss; outside an act it
  remains the game's flight key.

### Pose 1 shot

- Mod-owned `UnfplapPose1View`, top-level, anchored at
  `root + up * (0.45 + POSE1_CAMERA_LIFT_M(0.10)) * body_scale + back * 0.22 * body_scale`, then
  shifted by the **Act presentation → Missionary** axes and pulled by the **Missionary pullback**
  setting (`presentation.missionary.pullback`, default `0.22 m`, times body scale) back along its
  own frozen view axis. Canon height is `0.9×`; JRHNBR (`body_scale 1.35`) gets a proportionally
  higher, farther-back shot so the camera is not inside her neck. The anchor stays behind her
  neck, toward her rump, so the frozen aim looks forward along her body at her face. Anchoring
  ahead of the neck put the camera over her head and aimed back down her torso.
  The fine axes are `presentation.missionary.forward` (default `0.26`),
  `presentation.missionary.height` (default `-0.21`) and `presentation.missionary.side`
  (default `0`; positive is her right). `presentation.missionary.pitch_deg` (default `0`;
  positive looks up) tilts the frozen view about its local right axis after the aim. They are
  experimental/unbounded and applied live. The base view then adds
  `POSE1_START_LEAN = 1.0` (one full `LEAN_FORWARD_M` lean) along the view axis, so the shot
  starts at the old maximum
  W-lean point and W pushes further up her torso.
  The view copies and restores the source camera's `fov`, `near`, `far` and `cull_mask`.
  Do not bake the pullback into the world-space anchor; that moved the shot vertically and
  broke the aim. The aim basis is always rebuilt from `_pose1_camera`, never the already moved
  view, to avoid a start-up feedback flicker.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) during the first
  second while the act pose blends, then freeze. The live snout is not used; it can fall behind
  the bed camera. The look target is never derived from the moving view.
- The aim basis is built from `_pose1_camera` and updated only during that settle second; there
  is no forward-dot re-aim loop. A neck point behind the anchor is never accepted, so the shot
  cannot flip back down her torso. Rebuild only when the anchor is invalid, more than 3 m away, or
  genuinely below a **valid** bed top. `_bed_surface_top()` returns invalid (`INF`) when the bed
  reference is gone, so a missing bed cannot trigger a rebuild every frame.
- Her head aims at Anon's player camera, not the framing view, with a minimum
  `0.45 * body_scale` distance. The look point moves with the displayed lean's lateral shift and
  `presentation.missionary.side_lean` travel, so a side lean turns her toward the lean instead
  of away. Aiming at the shot camera (now behind her neck) demanded a half-turn and snapped her
  head side to side.
- Lean is applied on top of the frozen base basis. `Q` also starts the act kiss; `E` has no
  extra action. Pose 1 uses the same speed-driven surge/bob as pose 2; the surge runs along the
  mattress toward her head, while the bob moves the view up at her face on the inward stroke.
  The base already includes one full forward lean (`POSE1_START_LEAN`). Forward lean is clamped
  to stop `0.12 m` short of the neck target. A side lean also travels
  `presentation.missionary.side_lean` (default `0.20 m`, experimental/unbounded) along the
  mattress toward her head, outside the view-axis clamp; the side-lean roll remains separate.
  `presentation.missionary.pitch_deg` is applied as a local right-axis rotation after the base
  aim, before the lean basis.
- Pose 1 body motion is `prone_sway` (`pose1_body_motion`), not the standing `body_sway`
  (`pose2_body_sway`): the spine slides a little along the bed with raw depth and the head/neck
  nod `±3°`. The hooves are not pinned the way the standing sway pins them.
- Eyes: `ACT_LIDS = 0.45` during `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` only in `CLIMAX`, and
  sleepier afterglow `0.90`/`0.95`. A late `_eyes_tick()` reasserts the stare every tick so a
  kiss release, climax return or fluster peek cannot leave her wide-eyed.
- Pose 1 hides every `*AnonBody*` presentation node and disables the desktop presentation for
  the act, re-applying each tick because the stock rig can show itself again. Both are restored
  at end, so the rotated bed body cannot appear inside the camera shot.

### Pose 2 shot

- Uses the player's eye camera. Pose-2 height still comes through
  `_stand_eye`/`_eye_height`; do not teleport the rig.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) once at pose start,
  then freeze. Lean yaw/pitch are applied on top.
- Pose 2 has no separate thrust rock spring. The shared speed-driven surge/bob handles the
  thrust camera; lean yaw/pitch stays on top.
- Lean owns `controls_locked` for pose 2 too, so Anon does not walk while the camera moves.
- On restore, restore the player yaw/pitch to the **captured start values**, not the act base
  aim, and reset `camera.rotation.x` and `.z`.

### Pose 2 body language

- `body_sway.gd` translates `pony_spine1` with a damped spring driven by raw `depth`. It is
  inverted for this pass: the upper body rocks **back** on the inward stroke and **forward** on
  the outward stroke. The chest, neck and head follow; `pony_upperArm_L/R` origins are restored
  afterward so the forehooves stay planted. `BODY_SWAY_MAX_M = 0.035` is deliberately exaggerated
  for review; park it near `0.012`.
- Strong thrusts (`strength >= 0.55`) build a subtle rump blush decal by `0.035` per thrust, capped
  at `0.25` (the smack decal uses `0.8`). It decays slowly and is removed at act end.
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
  Thrust jiggle strength and the pose-2 camera height scale with pony size: Canon gets
  `_jiggle_size_scale() = 0.66`, a `CANON_POSE2_CAMERA_DROP_M = 0.10` lower eye line, and
  `_pose2_lean_scale()` multiplied by `0.8`; JRHNBR gets a
  `MOUNTING_POSE2_CAMERA_LIFT_M = 0.10` higher eye line.
  Every thrust also calls `tail.thrust(strength)`: a short `JIGGLE_DECAY = 3.6` /
  `JIGGLE_FREQ = 18` wave with the same strength as the rump shader, strongest at the dock
  (`mTail1`) and lagging down the chain (`JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`). This is
  the cheapest way to make rump jiggle and tail read as one motion; the shader itself stays
  native.
- A mod-owned `wing_sweep.gd` modifier runs last on the skeleton while pose 2 holds the wings,
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

| Input | Missionary | Horse |
|---|---|---|
| `Q` | kiss | left-hand reach to her left shoulder |
| `E` | none (lean only) | right-hand reach to her right shoulder |
| `A` / `D` | none | slow left/right flank caress |
| `Z` / `C` | none | toggle left/right caress oval movement |
| `F` (hold) | none | kiss at a full shoulder lean |
| Mouse right | left/right cheek opposite the lean | same |

- Pose 2 reuses the game's own kiss path: temporarily clear `controls_locked` for
  `pony_kisser.begin_from_pony()`, move `AffectionPose` last in the skeleton so its IK layers on
  the act pose, and call `Affection.end()` on release. This gives the normal face, mouth,
  deep-kiss and soft-kiss audio behaviour. Pose 1 always uses the custom head-aim path: the
  stock kiss pose is authored for a standing pony and its chest/neck give lifts the lying body
  and turns her head across the mattress. The custom path still sets the mouth expressions and
  repeats the mouth kiss sound. Either path may stop the pony's current speech, but it does not
  interrupt thrusting or stats. `_check_running()` treats the act's own `Affection`-driven
  `kiss` as part of the act instead of an interruption.
- `pony_kisser` physics is paused for the whole act, so the runtime feeds a base kiss the live
  `target`/`eye`/`face` from Anon's real mouth camera and repeats the mouth kiss sound itself.
  Pose 1's custom kiss also aims at the player camera, not the separate pose-1 framing view. The
  excitement Beat timer is paused for the kiss so the stock unicorn horn sparkle does not fire.
- While a kiss is active, Anon leans in by `KISS_LEAN_M = 0.27`, shifts to the shoulder side
  by `KISS_LEAN_SIDE_M = 0.18` and drops `KISS_LEAN_DROP_M = 0.035` lower over `0.35 s`; the
  pose-2 camera also yaws `KISS_CAMERA_YAW_DEG = 10°` toward her. The kiss side is latched at
  the start from the input lean (`_lean_side`, falling back to `_lean_action_side`), not the
  lagging camera view, and `AffectionPose.set_kiss_side()` pins her head tilt to the
  complementary side (`KISS_PONY_SIDE_SIGN = 1`) so their heads interlock instead of colliding;
  the deep-kiss side switch is disabled for the act. The lateral offset crossfades from the
  lean's `0.18 m` to the kiss's `0.18 m` instead of adding both.
  Pose 2 applies it to the act camera and pelvis counter-lean, so the hips stay planted; pose 1
  applies it to the framing view and offsets the virtual mouth by the kiss distance. During the
  kiss and its `Affection` release the forced over-the-shoulder glance is cleared and `head_back`
  eases to zero, so the kiss head pose is not fought by the reach glance. The camera lean is held
  until the release has retracted (`Affection.amount > 0.2`) before easing out, and a completed
  kiss has a `KISS_RESTART_COOLDOWN_MS = 500` before another kiss can start. The side latch and
  the pose lock are cleared when the kiss lean reaches zero.
- The shoulder reach uses `desktop_anon.set_hold_target(..., "rub")` through `anon_thrust.gd`,
  so it does not need `request_action()` and does not fight `controls_locked`. `rub` keeps the
  hand open. Hand-marker convention: local `-Z` is the fingers, `+Y` is the thumb/up, and the
  palm normal is `-X` on the right hand / `+X` on the left. The shoulder target uses the pony's
  surface contact for the palm position and outward normal; `palm_surface_basis()` keeps
  the fingers straight forward and the palm inward. It interpolates from the current rest hand
  over `REACH_HAND_BLEND_S = 0.35`, and release blends back to that rest frame over
  `REACH_HAND_RELEASE_S = 0.35` before the hold is cleared. A one-shot
  `reach hand side=... target=... x=... y=... z=... fingers=... palm=...` log prints the result.
- A/D caress uses the same hold-target path with an oval rub (`CARESS_RADIUS_M = 0.04125`,
  `CARESS_SPEED_RAD_S = 3.6`). Z/C toggle the left/right oval movement: the hand keeps its
  current coat contact and still scores, but the phase is frozen until toggled back on. During
  a smack the phase is frozen for the swinging hand. The palm is projected onto the coat every
  tick through
  `FlankSurface.contact`, falling back to `PonyTouchBody.nearest` outside the flank patch; its
  orientation is `palm_surface_basis()`, so the palm plane is perpendicular to the coat normal.
  The fallback uses `_nearest_touch()`, which skips
  `presentation.horse.caress.ignore` regions (default `tail`; UI also exposes mane, wings and
  legs). This prevents a tail flick after a smack from stealing the caress contact.
  The palm centre sits at `presentation.horse.caress.palm_distance` (default `0.04 m`) at body
  scale `1.0`, multiplied by the pony's actual `body_scale` (clamped `0.5…2.0`); the normal
  smoothing adds no extra lift.
  Contact is cached per hand with
  source hysteresis and short position/normal smoothing: a miss holds the last valid point, a
  flank↔body source change needs two hits, and a near-opposite normal (dot < -0.5) is rejected
  under the same source. `FlankSurface` precomputes a two-ring, area-weighted average of the
  patch's rest normals and skins those, so triangle and seam jitter is gone before the hand
  query. The final normal turns toward each new contact normal at
  `PALM_NORMAL_MAX_DEG_S = 120°/s` instead of snapping, and the palm basis is rebuilt from that
  final normal every frame. The torso-radial fallback only applies to a degenerate or inward
  normal. The rub centre is lifted
  `CARESS_UP_BIAS_M = 0.05` above each size profile's `up` point, and a 1 Hz log prints the rub
  and shoulder heights, source, misses, switches, normal step/out angle and driven-hand
  distance.
  The oval is `CARESS_OVAL_ACROSS = 1.30` along the body and
  `CARESS_OVAL_UP = 0.70` vertically, so it reads as a stroke rather than a perfect circle.
  Point offsets are per size in `CARESS_PROFILES`: Canon `up 0.08`, JRHNBR `up 0.16 / out 0.02`
  (both hands 4 cm wider), Same Height and Hoers step up from there; those choose where on the
  body to caress, then the contact query snaps the palm to the coat. Both A and D can run at
  once, one hand per side. An A/D tap latches that hand until the next tap. The
  centre interpolates with the lean: backward lean moves it toward the rump top as soon as it
  passes zero (`CARESS_RUMP_LEAN = 0.5`), no lean = flank, half forward lean = side/belly, full
  lean = the exact same shoulder contact point used by the Q/E reach. The circle radius scales
  with pony size; the point offsets are already per size. It is horse-only.
- While a shoulder reach is held, `_forced_glance` locks the pony's glance over that shoulder
  and suppresses the random glance scheduler; release clears it.
- Smack calls the native `FlankTouch.impact(index, at)` with `index 0 = left cheek`,
  `1 = right cheek`. `at` shifts the mark centre `0.08 m` up and `0.08 m` back, then jitters
  within `SMACK_ZONE_RADIUS_M = 0.035` around that point. The contact palm uses the same
  `palm_surface_basis()` and caress palm distance above. If a hand is already caressing,
  the smack uses that hand and its same-side cheek; if both are caressing, one is chosen at
  random. The caress oval is frozen for that hand during the swing. At the end the palm cache
  is reset, the current contact is reacquired (with caress ignore rules), and the hand returns
  over `CARESS_RETURN_SECONDS = 0.12` instead of clearing to rest. The hand swings in/out over
  `SMACK_SWING_SECONDS = 0.20`, impacts at `SMACK_CONTACT_PHASE = 0.45`, and has a
  `SMACK_COOLDOWN_MS = 200` gate.
- It reuses the slap sound/decal/blush/jiggle. The pony's `physical_reaction` connections are
  temporarily disconnected around the call, so `flank_smack` cannot trigger the game's
  buck/fidget/hoof shuffle or a bond/context/memory/satisfaction event.
- A right lean (`side > 0`) selects the left cheek; a left lean selects the right cheek; exactly
  centered picks one of the two real cheek points at random. There is no rump target.

### Thrust camera and restore

- The camera thrust is two amounts in `camera_thrust`: `surge` and `bob`, both `0…1`; defaults
  `1.0` and `0.35`. They scale `CAM_SURGE_M = 0.06 m` and `CAM_BOB_M = 0.02 m`.
- Both follow the filtered signed depth speed with one critically damped response. No impulses,
  no per-stroke kick and no camera rock.
- Climax uses `CAM_CLIMAX_SURGE_M = 0.02` and `CAM_CLIMAX_BOB_M = 0.008`, scaled by the sliders.
- Pose 1 and pose 2 use the same surge/bob. Pose 1 sends the surge along the mattress toward her
  head; pose 2 sends it along the camera forward.
- Restore order is load-bearing:
  1. release the free-camera control lock;
  2. remove the Anon thrust wrapper and restore any pose-2 palm scale;
  3. restore eye override and hidden avatar;
  4. free the pose-1 view;
  5. restore the pose-2 camera position;
  6. restore player look, then the pose-1 snapshot/cuddle.
- Pose 1 snapshots camera + current camera, player transform and pony transform/posture. Keep
  that snapshot exact; the bed cuddle re-invite depends on it.

## Critical: ACTIVE readiness and strength

`thrust.gd` is pure and has no scene access. It tracks raw depth and closes a stroke on a real
direction reversal or `STROKE_TIMEOUT_S = 0.18 s`.

- A **stroke** is continuous movement in one direction.
- A **thrust** is an inward stroke with `travel >= THRUST_MIN_TRAVEL = 0.25` and
  `duration >= MIN_THRUST_DURATION = 0.04 s`.
- A reversal must travel `REVERSAL_HYSTERESIS = 0.06` from the stroke peak before it closes.
  Tiny pullbacks stay inside the same stroke.
- Every stroke carries `direction`, `start_depth`, `end_depth`, `travel`, `duration`, `speed`,
  `peak_speed`, `thrust` and `strength`. There is no base gain and no per-stroke multiplier.
- Physical strength is `strength = clamp(travel × clamp(speed / 8.0, 0.15, 1.5), 0, 1)`.
  The `0.15` floor lets a slow full-depth stroke read as soft. Average speed drives intensity;
  peak speed is logged and capped at `2 × average speed`, but one fast sample cannot saturate
  the score.
- Visual impact is `min(1, strength × THRUST_IMPACT_GAIN)` with `THRUST_IMPACT_GAIN = 2.0`,
  preserving the tuned normal/fast response while slow and shallow strokes stay lighter. It
  drives jiggle (`_start_jiggle` clamp `0.30–1.0`, then `JIGGLE_RUMP_SCALE = 2.8`) and wing
  flick (`0.10→0.24`). Jiggle is also scaled by `_jiggle_size_scale()`.
- Only real thrusts update the axes and score. Outward strokes, tiny jitter and pullbacks are
  presentation only.
- The ACTIVE stage reads two axes from the last real thrusts:
  - **intensity**: `soft` (< 0.33), `firm` (< 0.66), `rough`;
  - **pattern**: `steady`, `teasing` or `quick`, classified over the last 3–4 real thrusts.
    Fewer than 3 has no pattern yet.
- `satisfaction` is **readiness 0–100**, not a stroke score. Each real thrust adds
  `THRUST_HEAT_BOTH = 1.4`, `THRUST_HEAT_ONE = 0.7` or `THRUST_HEAT_NONE = 0`, times warmth;
  scoring is limited to one thrust every `THRUST_SCORE_MIN_INTERVAL = 0.2 s`. There is no
  passive match rate.
- Touch/talk are assist only: one chunk up to `ASSIST_CAP = 60`; touch shares a 4 s cooldown,
  talk has 8 s. A liked touch/talk opens an 8 s receptive window (`RECEPTIVE_BOOST = 1.25`).
  A disliked one subtracts and briefly sets `overwhelmed`.
- `CLOSE_AT = 65` is only the “she's close” cue. `PONY_CLIMAX_AT = 100` triggers a pony
  climax. `satisfaction` is still the public HUD value.
- Each pony climax lasts `CLIMAX_SECONDS = 5`; the player can keep thrusting, but those thrusts
  do not score. After it, readiness resets to `taste.recovery`; the 3rd climax auto-enters
  afterglow. `MAX_PONY_CLIMAXES = 3`.
- Hold `Y` in `ACTIVE` with 0 climaxes cancels; with 1+ it enters afterglow. Hold `Y` in
  `CLIMAX` enters afterglow. `Y` in `AFTERGLOW` ends it.
- `mood` is `warming`, `wanting`, `close`, `climax` or `overwhelmed`; `cue` is the short HUD
  line. `hud_readouts` gates the cue segment, readiness bar and the `Wants`/`You` segments.
- Readiness never decays passively. Only a disliked touch or talk subtracts; neutral and quiet
  input leave it unchanged.
- A talk cue is an invitation, not a gate. It only appears for a mare with a non-empty
  `talk` taste; the HUD cue is “She needs to hear you.” The player's own text/speech is
  detected through `conversation_director._turn_id` / `_player_text`; the AI still writes her
  reply.
- Do **not** add a thrust debug sub-gate. The per-thrust log is the scoring view.

Read `PREFERENCES.md` for the exact taste schema, readiness rates, cue rules and character
examples.

## Act flow, gates and controls

- Eligibility: adult, not filly/colt, player not young, love level ≥ 2, and
  `bonds.welcomes(id, "kiss")`.
- Pose 1: Human Anon uses the seated/lying bed path; AnonPony uses the already-lying path. Pose 2:
  standing/settled.
- Start only when free/idle; another pony's conversation, active task or conflicting navigator
  lease blocks. Player conversation is free. The `allow_act_during_cuddle` flag (default
  `true`) lets an act start through an active stock cuddle session; the start path ends that
  session first.
- The runtime's automatic cuddle suppression runs only outside `IDLE`, so the stock bed/couch
  cuddle still works when no act is running.
- During the act the quick-slot inventory HUD is hidden and restored at end.
- `kiss_hold` owns movement hold; `pony_kisser` physics is paused so it cannot remove it.
- Act actions: `W`/`S` lean forward/back, `Q`/`E` side lean plus pose reaction, `A`/`D` caress,
  `Z`/`C` toggle caress movement,
  `F` hold kiss in pose 2, mouse right smacks. They are available in `ACTIVE`, `CLIMAX`, and the
  horse `AFTERGLOW`; `Y` is the context start/end control. `H` is the game's hug/deep-kiss key;
  the act consumes it without binding it so a hug cannot end the act's kiss.
- `Y` starts an act when idle and is a `0.35 s` hold while active, matching bridal-carry
  initiation. A tap does nothing. In `ACTIVE`, hold Y cancels with 0 pony climaxes and enters
  afterglow with 1+; in `CLIMAX`, hold Y enters afterglow. Hold Y ends afterglow; Y is ignored
  in `RESTORE` except for event consumption. `T` remains the game's talk key and is not
  consumed; the runtime watches player turns as a scoring input. `Q`/`E` are the side lean;
  during an act the interaction keys are still consumed so the game's stand-up action cannot
  interrupt the scene.
- States: `IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE` for both poses.
- Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.
- Aftercare starts only at final readiness ≥ 10; it holds navigator ownership for 10 s and
  keeps the tail raised straight with reduced flicks.
- Each pony climax records a unique memory event and reaction. The act-level romance impression
  and witness pass commit once at afterglow; pose 2 records the inside event at afterglow only.
  The horse afterglow also runs the 8 s close window and records its own stay-close memory.
- A peak act keeps one strongest memory per mare in `Mods.state("unfplap").peak_memories`.
  It is written only with no disliked touch/talk and either peak satisfaction >= 90 or six
  both-axis thrust matches; a higher score replaces it. The stored text is the last player
  exchange, or a generic warm beat when he did not speak. The cue prompt prefers this memory.
- Memory uses the game's second-person phrasing. Witnesses are nearby awake adults; sleeping
  ponies and fillies/colts are skipped.
- Proactive requests are a separate controller (`initiation.gd`), not an action tag. They never
  start the act; `Y` remains the only acceptance path.

### Proactive requests

- One request episode at a time. Automatic requests require AI usage Full
  (`AI_CONFIG.background_allowed`), an idle director, no group exchange, no hearing, and no
  character chat within 45 s. The lab runs in Talk, so use `F4`.
- Eligibility is the existing relationship/social gate (`can_start` for the pose), not the
  act-time readiness value. No anger bypass.
- Cuddle: requires an active cuddle and `can_start(MISSIONARY, "bed_side")` or
  `"already_lying"`. Indoor privacy is house-only solitude; outdoors it is nobody
  within 30 m. A cuddle rising edge clears that mare's cooldown and permits one ask per cuddle.
- Horse: requires `can_start(HORSE)`. She walks to a spot 2 m in front of Anon's view (same
  navigation region, ≤24 m, empty/`life:` navigator owner, 35 s deadline). The request starts
  only if the current `Y` offer actually targets her.
- Private for horse means alone in the house or nobody within 30 m. Private lets the AI choose
  direct or indirect wording and turns on the invitation; with others around she only hints.
- The horse invitation is IDLE-only: turn away over 2.4 rad/s, clear navigator `face_point` and
  conversation target late each physics tick, hold `face_turn_rate = 0`, then attach a pose-2
  modifier and tail-aside. It is not the act: no camera, lock, HUD or `sex_active`.
  `unfplap:request:` navigator ownership keeps `Y` valid until the episode ends.
- Initial ask uses `begin_player_greeting` with a situation prompt; the context event is recorded
  as `situation`. Reminders are generated at 12 s and 24 s, and a give-up line at 30 s. If the
  player speaks, reminders stop but `Y` remains until the deadline.
- Cooldown is 600 s per mare in `Mods.state("unfplap").request_times`. An approach or initial-ask
  failure sets a short 30 s retry instead; an ask, presentation or give-up sets the full
  cooldown. `Y` cancels the episode before `start()`.
- `F4` force-request bypasses quiet, cooldown and AI-usage checks for lab testing.

## Dialogue utterances

- Cues are event-driven: a touch/talk result, an overwhelmed state, or a ready state.
- A cue line is generated at most once per `cue_gap` (default `12 s`, clamped `8..30`,
  per character) after the previous cue line was queued. The cue still needs a changed cue text,
  the 6 s global utterance gap and a free director.
- A cue line uses the `cue` prompt; a talk invitation uses `talk_cue`. The state line contains
  pose, mood, taste-axis motion, last touch, last talk, pony climax count and act time; it
  contains no speed or depth units.
- Every cue line carries a private relationship note and tone. The note uses the friendship/love
  level names, relationship stage, first-time/repeat and current mood; the tone is `tender`,
  `warm`, `ardent`, `open` or `careful`. The functional cue text is unchanged. The prompt tells
  her not to say the labels, levels or numbers.
- The cue prompt may include one unused shared memory. `MEMORY.shared_memory()` prefers the
  stored peak memory, then the story journal: a cue-word match, then the most recent player
  exchange. It falls back to the world-context events. Intimacy events and private brain notes
  are not used as the hint. The memory is marked used only after the line is queued.
- One mod line may be pending at a time. A new line needs an idle director and pony, plus
  `UTTERANCE_MIN_GAP_S = 6 s` since the previous line started.
- The pending slot stays reserved until speech actually stops and a 1 s release hold passes.
  A queued line has a 60 s safety timeout only if it never starts; in-progress speech is never
  invalidated.
- A talk cue is an invitation, not a gate. If the player answers, the runtime drops the cue's
  pending line, scores the player's turn and lets the director's reply stand. If not, the
  invitation expires quietly.
- Each pony climax drops queued act lines but keeps an in-progress one, then queues a unique
  climax reaction. End and inside reactions always queue. Only the cached “Mm.” is used;
  generated moans are parked.
- `_end_act_lines()` cancels every mod-owned line for the act except one that is already
  **speaking**. Queued and still-thinking lines are dropped. It runs at climax, afterglow and
  every act end (`cancel`, `_restore_begin`, `_restore_now`, `_abort_start`). The intentional
  early-stop line is queued after the restore begins. Act-line validity is tied to the
  pony/event id, not `State.ACTIVE`.
- The horse afterglow queues a separate `stay_close` line after the `inside` line. The HUD
  close timer, not the line, owns the invitation.

## HUD and rewards

- The native offer hint uses the game's `button_y` icon plus `sex` (no leading dot); without the
  icon it falls back to `Y · sex`.
- The act controls are a bottom-left, top-down list: one row per button, each with a keycap or
  controller icon. Rows list mouse thrust, W/S, Q/E, A/D, Z/C caress movement, F, mouse right,
  T and Y; `Y` text
  changes by state.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`; the previous state is restored on every exit path:
  `_abort_start()`, `_restore_now()`, `_finish_restore()` (including the invalid-pony branch),
  and `force_stop()`. `_physics_process` also restores it if `IDLE` is ever reached while still
  marked hidden. The inventory's `_place_hotbar()` re-evaluates the state after restoring, so a
  stale pre-act layer flag cannot leave it hidden.
- The bottom-left controls list is one row per button with a keycap/controller icon. Top to
  bottom: cue line `❤ N/3 | cue`, readiness line
  `Wants: intensity & pattern | You: intensity & pattern`, readiness bar, blank separator,
  controls.
- The `Wants`/`You` line, short readiness bar and cue segment are all gated by `hud_readouts`
  (default `true`). The bar has no ticks. The hearts remain when readouts are off.
- Afterglow shows `❤ N/3 | close hint` instead of `Wants`/`You`. Missionary keeps only `Y`;
  horse keeps forward/back, Q/E reach, A/D caress, Z/C caress movement, F kiss and Y, while
  thrust, smack and talk
  are hidden. The horse close hint is independent of `hud_readouts`.
- Love XP and happy mood are granted once by `MEMORY.commit_climax()` at afterglow.
  `MEMORY.stay_close_reward()` may add a small extra romance, happy mood and private thought
  when the horse close window is completed; staying alone records the memory without the extra
  romance. No other afterglow reward is granted.
- `captions_on_top`, default `true`, moves the game's desktop bottom caption to the top only
  when `access/speech_text` is the explicit bottom-caption mode; overhead and auto are untouched.

## Debug and testing

- `Ctrl+Shift+D`: master DEBUG LOGS toggle; default ON; persists in
  `user://mods/data/unfplap/settings.json`.
- `F4`: force a proactive request for the aimed/nearest test mare. It bypasses the quiet,
  cooldown and AI-usage checks, but not relationship, consent or pose gates; use it in the lab,
  which runs with `ai_usage=talk`. F4 is otherwise the dev-only performance-capture key; the
  mod consumes it while DEBUG LOGS is on. (F7 is the game settings menu.)
- `F8`: offer/gate/bed report plus target thrust data.
- `F9`: pose-1 floating preview and one-shot `POSE1` dump.
- `F10`: toggle the skeleton overlay for nearby ponies. Lines are thin
  (`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible;
  hover a joint to turn it red, then click to print its bone name, parent, world/local origin,
  rotation, scale and rest.
- While `debug_logs` is on, **Settings → Unfplap → Debug** exposes a hidden
  **Trigger sex offer (F4)** button. It uses the aimed mare with the nearest fallback and
  calls the same `initiation.force()` path as F4; the status label reports the target or gate
  rejection. Because the settings page pauses the tree, the offer advances after it closes.
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
- Test every pose start, climax, afterglow, restore, hold-Y and cuddle path in the lab
  after changing camera, pose or scoring code.

## Voice routing and settings tab

- `voice_status.gd` classifies a profile with the game's own routing:
  `CHATTER.use_chatter(profile, tts.voice_mode)`. It reports `generated` (a character/openai
  voice exists) separately from `effective_ponese` (what will actually play now). A character
  voice still counts as effective Ponese when the global mode is `ponese`, TTS is off, or no
  server is configured.
- `Ctrl+Shift+V` logs a `VOICES` block for loaded ponies; `F8` includes the target's voice line.
- `mute_ponese_audio` mutes only the partner's `Voice` audio player for an act while keeping
  the generated text/HUD flow. It does not suppress dialogue.
- The Unfplap settings tab is **runtime-injected** with
  `Mods.on_node("res://world/ui/settings_page.gd", ...)`, not a `mod.json` extension. If
  `settings_tab` is false it returns before touching the page. If the page's private fields are
  unavailable it logs and skips, so the settings page is never required for the mod to load.
- The injected tab also owns the **Character taste** editor: one pony selector from
  `SETTINGS.CHARACTER_ORDER`, enum controls from `preferences.gd`, recovery `0…80`, touch/talk
  like and dislike checkboxes, and editable private notes. Taste edits save automatically and
  apply live; `Reset to default` removes only that taste override. Custom `event_prompts` and
  `poses` on the character entry must survive both actions.
- Injected pages/buttons are tracked and removed in `_exit_tree()`. Do not add `extends` for the
  settings page.

## Settings and persistence

- `settings.json` path: `user://mods/data/unfplap/settings.json`
  (`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).
- Top level: `debug_logs`, `features`, `thrust`, `camera_thrust`, `presentation`, `default`
  template, `characters` overrides.
- Feature flags live in `SETTINGS.FEATURE_DEFAULTS`; the runtime caches them at act start and
  `apply_live_settings()` refreshes them after any settings-tab edit. Keep these documented here
  when adding one:

| Flag | Default | Gates |
|---|---|---|
| `hud_readouts` | `true` | mood cue, readiness bar and `Wants`/`You` segments; hearts and the close prompt stay |
| `idle_camera_sway` | `true` | slow idle breathing when not leaning; false = no camera drift without input |
| `captions_on_top` | `true` | move the explicit bottom caption to the top; applies immediately |
| `pose2_body_sway` | `true` | pose-2 upper-body sway modifier |
| `pose1_body_motion` | `true` | pose-1 torso slide and head nod on the thrust |
| `thrust_ear_twitch` | `true` | pose-2 thrust ear-twitch modifier |
| `allow_act_during_cuddle` | `true` | allow starting an act while the stock cuddle session is active |
| `mute_ponese_audio` | `true` | mute a Ponese-only act voice but keep its text |
| `settings_tab` | `true` | runtime-injected Unfplap settings tab; false = no page mutation |

Always on: horse afterglow stay-close window, lean-camera inertia smoothing and strong-thrust
rump blush. Unknown settings keys are ignored.
- `thrust.orientation`: `"up"` (default) means mouse up deepens; `"down"` flips it.
  `thrust.pixels_per_full` defaults to `800`.
- `camera_thrust` stores `surge` and `bob`, both `0…1`; defaults `1.0` and `0.35`. They scale the
  speed-driven camera travel and apply live during an act.
- `presentation` is split per pose:
  - `missionary`: `forward`, `height`, `side`, `pullback`, `side_lean`, `pitch_deg`.
  - `horse`: `glance_back_speed`, `torso_angle_deg`, and `caress` with `palm_distance`,
    `palm_scale` keyed by `canon`/`mounting`/`same height`/`hoers`, and `ignore`.
  - The old flat `pose1_*`, `glance_back_speed` and `torso_angle_deg` block migrates once in
    `_normalize_presentation()`; obsolete `pose1_camera` is dropped.
- Only bound a settings control when the bound is part of the explicit user-facing contract
  (sensitivity, glance speed, percentages, taste). Experimental tuning controls stay unbounded.
- Feature flags are one ungrouped list. Each row uses `FEATURE_INFO` for a human label and a
  help line. Edits apply live during an act; `live` flags also apply immediately outside one.
  `FEATURE_INFO` must stay in sync with `FEATURE_DEFAULTS`.
- The injected settings tab has a **Thrust** section (orientation, sensitivity `240…1200`), a
  **Camera thrust** section (surge and bob, `0…100%`), an **Act presentation** section split
  into **Missionary** and **Horse** (horse includes caress palm distance, size-selected palm
  scale and body-part ignores), a hidden **Debug** block only while `debug_logs` is on, and
  **Character taste**. There are no Save buttons: each control writes its own block and calls
  `apply_live_settings()` so the active act updates
  immediately.
- `debug_logs` defaults to `true`.
- Character entries inherit unspecified fields from `default`.
- Key fields: `smack_zone_radius`, `aftercare_min`, `cue_gap`, `taste` (`recovery` included),
  `act_prompts`, `event_prompts` (`climax`, `end_early`, `inside`, `stay_close`),
  `poses.missionary`, `poses.horse`. `cue_gap` is a per-character JSON value, not a settings-tab
  control.
- The settings editor lists `SETTINGS.CHARACTER_ORDER` (16 IDs) and uses `CHARACTER_NAMES` for
  display labels. Add a pony to both and to `CHARACTER_TEMPLATES` when expanding the roster.
- Pose defaults live in `poses/catalog.gd`; taste defaults and validation live in
  `preferences.gd`/`settings.gd`.

## Documentation discipline

This is mandatory.

- Update the contract in the same commit as behavior, settings or controls. Put rationale,
  measurements and tuning history in the commit body.
- Never leave stale paths, removed controls, obsolete constants or incorrect claims. Remove
  obsolete documentation instead of keeping historical notes.
- Keep camera, pose, thrust and strength details here and in `PREFERENCES.md`/`ROTATION.md`.
  Summarize non-critical areas such as debug logs; do not build long catalogues.
- Verify every claim against code before writing it. If docs and code disagree, fix the docs or
  the code in the same change.
- `README.md` rule:
  - Only update **CONTROLS** and **FEATURES** unless the user explicitly asks for another
    section.
  - Do not list debug controls in README.
  - Features are concise, high-level and one sentence each. No history, implementation detail
    or architectural reasoning.
  - Do not rewrite or reformat the rest of README.
- Keep `AGENTS.md`, `README.md`, `PREFERENCES.md`, `ROTATION.md` and `WORKFLOW.md` consistent.

## Known constraints

- `ext/shared_bed.gd` lifts the stock `1.05` bed-cuddle body-scale cap and tries the bed's
  authored `side_local` approach before the generic side. It is intentionally kept even when a
  release build omits the extension.
- The stock bed captures a snuggle guest's rest transform at invite time from the player's
  reclined hip/head targets. Inviting before that blend settles puts the target at standing
  height, so `hop_clear` fails and the guest never climbs on. The lab waits `1.2 s` after lying
  down before inviting.
- The talk classifier in `preferences.gd` is a small keyword map, not an LLM call. Expand it
  only from real playtest phrasing, and keep `talk` empty for mares who should not score it.
