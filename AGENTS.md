# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file
adds the working knowledge for `unfplap` only. Keep it current; it is the source of truth for
agents, not a design diary.

## Required reading by task

Do not start implementation until you have read the required files for the area you are touching.

| Task | Read first |
|---|---|
| Any task | `res://mods/AGENTS.md`, then this file, then `WORKFLOW.md` |
| ACTIVE readiness, taste, strength | `PREFERENCES.md`, `thrust.gd`, `preferences.gd`, `utterance.gd`, `utterance_scheduler.gd` |
| Pose, skeleton, camera, act actions | `ROTATION.md`, `poses/` |
| Controls or features | `README.md` (edit only CONTROLS and FEATURES) |
| Any setting, flag or debug control | `TUNING.md`, `tunables_schema.gd`, `tunables.gd` |
| Character profiles or taste | `settings.gd`, `poses/catalog.gd`, `PREFERENCES.md` |
| Act audio or sound assets | `act_audio.gd`, `act_sound.gd`, `audio/act/catalogue.gd`, `audio/act/smack/catalogue.gd`, `AUDIO_CREDITS.md` |

## Identity and scope

- Mod id `unfplap`; current public version `0.1.2`; target game `0.3.0-maredev`.
- Adult mares and stallions only. Human Anon and AnonPony.
- Marefriend/Coltfriend or later. Consent is `bonds.welcomes(id, "kiss")`; refusal is real.
- Exactly two poses: `missionary` on a bed/couch and `standing` standing.
- No pregnancy, heat, estrus, conception, content warning, toggle, new character or body models,
  genitals or anatomy. The act stays off-camera by framing. Modelled accessories are allowed (the
  tail bow is one); they are accessories, never a replacement for a pony's body or rig.
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
./lab.sh
```

It runs the isolated `unfplap-test` world and writes the session to `last-run.log` beside the
script. Set `GODOT=~/path/to/godot` if the binary is not at `~/Downloads/godot`.

- The lab loads only Twilight, Fluttershy, Rarity and Derpy, pauses world scheduling and
  background AI, and uses the Golden Oak guest bed. It does not spawn a test bed.
- `worlds/unfplap-test/` is the isolated lab world; `worlds/default/` is untouched. Delete only
  the test world to reset it.
- The lab re-seeds its four mares on every startup (romance tier, dating record, mood, idle
  posture) and moves them to a row on the path in front of Golden Oak Library. The rest of the
  world's context and inventory persist.
- The lab normalizes a mare's saved actor rotation to yaw-only in `_upright()` during setup and
  after bed transport. A tilted saved transform otherwise makes support recovery fight the
  collider every frame and print endless `re-seated on the floor` lines.

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
  ./build.sh [--out <file.pck>]
  ```
  Success prints `MOD_BUILT <path>`. The mod has no script extension.
- `build.sh` stages only the runtime tree selected by `.pckignore`, imports the audio and packs
  the `.import` sidecars. Repository docs, tests, scripts, tools and `.git` do not ship;
  `AUDIO_CREDITS.md` does.
- `.github/workflows/build.yml` builds on pushes and pull requests; a `v*` tag publishes
  `dist/unfplap-<version>.pck` as a GitHub release asset.
- The official `tools/modding/build_mod.gd` command remains a fallback when the full game
  project is available, but it packs the whole folder.
- Do not leave a `.pck` in the source project's live mods folder while testing `--mod-src`; it
  shadows source edits.

## Architecture and important files

```text
mods/unfplap/
  mod.json          id, version, game_version, entry
  main.gd           Mods hooks, runtime attachment, offers, HUD/input creation,
                    settings-tab injection with guard, character taste editor, debug actions,
                    skeleton debug helper
  runtime.gd        per-pony state machine, gates, start, ACTIVE readiness/talk,
                    act camera lean, pose actions/smack, climax, afterglow/close window,
                    restore, aftercare
  thrust.gd         pure stroke tracker: reversal hysteresis, timeout, travel, speed, strength
  preferences.gd    pure taste profile, intensity/rhythm and talk classification
  tunables_schema.gd  every global setting: one schema entry per line, keyed by its JSON path
  tunables.gd       the one typed API for reading and writing those settings
  tunables_ui.gd    the only file that builds settings widgets: grouped Settings/Debug panels
  utterance.gd      pure prompt formatting
  utterance_scheduler.gd  pure cue selection and line admission: stability, gaps, demand
                    budget, one slot for cues and reactions
  relationship_cue.gd pure relationship/tone formatting and peak-memory gate
  act_motion.gd    pure lean travel/step, pose action, glance fade and hip smoothing
  standing_caress.gd  standing caress, shoulder reach, smack and palm-on-coat contact
  kiss_control.gd   missionary/standing kiss, base AffectionPose bridge and foreleg pin
  missionary_camera.gd  frozen missionary shot, aim, avatar hiding and start snapshot
  standing_camera.gd  standing look, glance, facing lock and camera offsets
  standing_anon.gd  standing hip thrust wrapper, planted lower body and palm scale
  standing_presentation.gd  idle standing invitation, turn and request face
  anon_thrust.gd    wraps the desktop Anon pose driver for the standing hip thrust
  palm_scale.gd     standing hand-bone scale, restored when the act ends
  body_sway.gd      depth-driven standing upper-body sway with planted forehooves
  kiss_legs.gd      standing kiss hoof-tip pin after AffectionPose's chest flex
  prone_sway.gd     missionary lying torso slide and head nod on the thrust
  ear_twitch.gd     eased random thrust ear twitch on the head skeleton
  wing_control.gd   wing hold/spread/flutter, afterglow fold and wing-sweep lifetime
  wing_sweep.gd     standing wing root sweep after the game's WingTuck modifier
  chin_debug.gd     debug head-pitch skeleton modifier
  debug_skeleton.gd F10 skeleton line/circle overlay with hover and joint inspection
  voice_status.gd   pure character-voice/Ponese classification
  act_sound.gd      base-game breath, plap, mouth-kiss and climax players
  act_audio.gd      optional pack foley/vocal/wet layers
  audio/act/smack/  OpenNSFW hand-smack variants installed on FlankTouch
  poses/            skeleton driver, rig cache, rotation helpers, recipes, catalog
  hud.gd            bottom-left controls list, combined status line, readiness meter and close cue
  readiness_bar.gd  pure short 0–100 readiness fill; no ticks
  input.gd          Y start/end, right-click smack routing, key consumption, action hotkeys
  settings.gd       settings.json IO and cache, legacy migration, per-character templates and taste
  memory.gd         world_context events, climax impression, witnesses, reactions
  rest_control.gd   release pony_seating and shared_bed/couch without standing
  aftercare.gd      10 s post-act tail-up/flick, navigator hold, sex_aftercare gate
  satisfied.gd      300 s post-act relaxed face, light blush and warm prompt note; no nav hold
  tail_pose.gd      tail aside/lift/flick + thrust jiggle on the hair skeleton
  tail_bow.gd       satin tail bow: mesh, worn record and the mTail1 accessory attachment
  tail_bow_gift.gd  tail bow in conversation (give/take), reconcile pass and prompt note
  witness.gd        witness pass
  initiation.gd     proactive requests: privacy, approach, ask, consent, standing invitation
  consent_classifier.gd  one shared classifier client/queue for offer and dialogue consent
  dialogue_consent.gd    verbal yes/now/here agreement from player dialogue
  tests/            unit/source-hygiene tests + manual test_lab.gd
  PREFERENCES.md    taste/readiness/strength contract
  ROTATION.md       pose, skeleton and camera positioning contract
```

Entry script only. No script extensions, game-file edits or JSON merges. The bed-size extension
was removed after the 0.3.0 stock bed made its eligibility and approach rules size-aware; release
builds ship compiled `.gdc` scripts that the mod loader cannot subclass anyway.

## Critical: poses and skeleton work

Read `poses/` and `ROTATION.md` before changing a pose. Rotate bones, never stretch them, and do
not leave the pony outside her joint limits. Use `pose_rig.gd` for the bone cache and
body-relative axes.

### Missionary

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
- `MISSIONARY_ROLL_TWEAK` (radians) offsets the pelvis correction if needed.
- `_neck_bend(neck1_deg, neck2_deg)` bends `pony_neck1`/`pony_neck2` about the body right axis.
  Presentation defaults are `0°` each; zero straightens the neck.
  `_neck_roll(neck_roll_deg)` rolls both neck bones about the body forward axis. Both run
  **before** the gaze solve, so they change head position without biasing the final face
  direction. After the gaze solve, `_head_pitch(head_pitch_deg)` tilts the head about the body
  right axis, and `_roll_head(head_roll)` stays last. This last one is a **degrees** value and
  must convert with `deg_to_rad()`; using it as radians turns a 1° control into ~57°. These are
  live presentation controls under Missionary → Neck angles.
- `_aim_gaze()` is a true shortest-arc solve from her current face direction to Anon, using the
  current `pony_head` frame plus `HybridNeckLink`'s fixed `pony_head → mHead` offset. Do not
  replace it with absolute yaw/pitch from the body axis: that assumed a standing rest
  orientation and left the missionary head aimed at the ceiling. The nuzzle offsets the target
  by a few degrees rather than adding a second absolute aim.
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

### Standing

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
  `presentation.standing.tail.yaw_deg` (default `31.5°`) and `pitch_deg` (default `24.1°`) set
  how far it sweeps aside and lifts, in degrees, and apply live through
  `_sync_standing_pose_config()`; the tail modifier is created from that pose config.
- Standing enters the same held `AFTERGLOW` state when the player chooses it or the third pony
  climax forces it. Lean and A/D caress stay live there; hold Y ends it. Her tail lifts and
  flicks twice, and the inside event is recorded on entry. Normal dialogue resumes; a
  world-context afterglow event keeps the just-intimate moment present, and a live
  `pony_prompt_notes` line reports caressing/leaning. After 16 s she may choose to end the
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
  Canon (`0.66`) is `1.34` (+34%). Missionary Canon camera height is also multiplied by `0.9`.
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
- `presentation.standing.torso_angle_deg` (default `6`, experimental/unbounded) hinges Anon's
  upper body forward over her. `apply_anon_lean()` keeps the lower body planted;
  `apply_camera_motion()` moves the head/camera along the spine arc
  (`ANON_TORSO_LEN_M = 0.65`). It applies live.
- Standing palms are scaled absolutely per body preset from
  `presentation.standing.caress.palm_scale`: Canon `0.75`, JRHNBR `0.9`, same height/hoers
  `1.0`. The Caress section edits one row per preset. `palm_scale.gd` runs after BodyIK and
  restores the cached bone scales in `_remove_anon_thrust()` on every act exit. Marker scaling
  would be discarded by the IK solver.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- The displayed lean is always smoothed at `CAMERA_INERTIA_SMOOTH = 5.0`.
- `Q`/`E` fire their pose action at `LEAN_FIRE = 0.75` and release at
  `LEAN_RELEASE = 0.60`. The action is latched while above release.
- The lean always holds a released position. `_lean_step()` only ramps toward a pressed target;
  the explicit `S` shoulder recentre uses `return_to_zero`. The act end and paused paths still
  return the lean over `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default off) the camera lean gets a small, slow rocking offset
  (`0.010` forward / `presentation.standing.idle_sway_side`, default `0.0`, clamped inside
  `-1…1`). A/D caress always latches: tap once
  to keep rubbing after release, tap again to stop. Pressing `S` arms a gradual side return, so
  the shoulder roll decays to neutral without leaning the other way.
- Lean and actions are available in both `ACTIVE` and `CLIMAX`; every other state ends them.
- The lean camera owns `player.controls_locked = true` for both poses. Save and restore the
  prior value at act end.
- `F` is not an act control in missionary. In standing, holding `F` at a full side lean
  (`abs(side) >= STANDING_KISS_LEAN = 0.90`) starts the same base-game kiss; outside an act it
  remains the game's flight key.

### Missionary shot

- Mod-owned `UnfplapMissionaryView`, top-level, anchored at
  `root + up * (0.45 + MISSIONARY_CAMERA_LIFT_M(0.10)) * body_scale + back * 0.22 * body_scale`, then
  shifted by the **Act presentation → Missionary** axes and pulled by the **Missionary pullback**
  setting (`presentation.missionary.pullback`, default `0.22 m`, times body scale) back along its
  own frozen view axis. Canon height is `0.9×`; JRHNBR (`body_scale 1.35`) gets a proportionally
  higher, farther-back shot so the camera is not inside her neck. The anchor stays behind her
  neck, toward her rump, so the frozen aim looks forward along her body at her face. Anchoring
  ahead of the neck put the camera over her head and aimed back down her torso.
  The fine axes are `presentation.missionary.forward` (default `0.30`),
  `presentation.missionary.height` (default `0.25`) and `presentation.missionary.side`
  (default `0`; positive is her right). `presentation.missionary.pitch_deg` (default `-15`;
  positive looks up) tilts the frozen view about its local right axis after the aim. They are
  experimental/unbounded and applied live. The base view then adds
  `MISSIONARY_START_LEAN = 1.0` (one full `LEAN_FORWARD_M` lean) along the view axis, so the shot
  starts at the old maximum
  W-lean point and W pushes further up her torso.
  The view copies and restores the source camera's `fov`, `near`, `far` and `cull_mask`.
  Do not bake the pullback into the world-space anchor; that moved the shot vertically and
  broke the aim. The aim basis is always rebuilt from `_missionary_camera`, never the already moved
  view, to avoid a start-up feedback flicker.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) during the first
  second while the act pose blends, then freeze. The live snout is not used; it can fall behind
  the bed camera. The look target is never derived from the moving view.
- The aim basis is built from `_missionary_camera` and updated only during that settle second; there
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
  extra action. Missionary uses the same speed-driven surge/bob as standing; the surge runs along the
  mattress toward her head, while the bob moves the view up at her face on the inward stroke.
  The base already includes one full forward lean (`MISSIONARY_START_LEAN`). Forward lean is clamped
  to stop `0.12 m` short of the neck target. A side lean also travels
  `presentation.missionary.side_lean` (default `0.10 m`, experimental/unbounded) along the
  mattress toward her head, outside the view-axis clamp; the side-lean roll remains separate.
  `presentation.missionary.pitch_deg` is applied as a local right-axis rotation after the base
  aim, before the lean basis.
- Missionary body motion is `prone_sway` (`missionary_body_motion`), not the standing `body_sway`
  (`standing_body_sway`): the spine slides a little along the bed with raw depth and the head/neck
  nod `±3°`. The hooves are not pinned the way the standing sway pins them.
- Eyes: `ACT_LIDS = 0.45` during `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` only in `CLIMAX`, and
  sleepier afterglow `0.90`/`0.95`. A late `_eyes_tick()` reasserts the stare every tick so a
  climax return or fluster peek cannot leave her wide-eyed. While a kiss is active it releases
  the act's stare once and stops touching the eyes, so the game's own fluster/deep-kiss eyelids
  run; the custom kiss's `touch("affection", ..., 0.95)` lid layer is not overridden.
- Missionary hides every `*AnonBody*` presentation node and disables the desktop presentation for
  the act, re-applying each tick because the stock rig can show itself again. Both are restored
  at end, so the rotated bed body cannot appear inside the camera shot.

### Standing shot

- Uses the player's eye camera. Standing height still comes through
  `_stand_eye`/`_eye_height`; do not teleport the rig.
- Aim: sample the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) once at pose start,
  then freeze. Lean yaw/pitch are applied on top.
- Standing has no separate thrust rock spring. The shared speed-driven surge/bob handles the
  thrust camera; lean yaw/pitch stays on top.
- Lean owns `controls_locked` for standing too, so Anon does not walk while the camera moves.
- On restore, restore the player yaw/pitch to the **captured start values**, not the act base
  aim, and reset `camera.rotation.x` and `.z`.

### Standing body language

- `body_sway.gd` translates `pony_spine1` with a damped spring driven by raw `depth`. It is
  inverted for this pass: the upper body rocks **back** on the inward stroke and **forward** on
  the outward stroke. The chest, neck and head follow; `pony_upperArm_L/R` origins are restored
  afterward so the forehooves stay planted. `BODY_SWAY_MAX_M = 0.035` is deliberately exaggerated
  for review; park it near `0.012`.
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
  Every thrust also calls `tail.thrust(strength)`: a short `JIGGLE_DECAY = 3.6` /
  `JIGGLE_FREQ = 18` wave with the same strength as the rump shader, strongest at the tail root
  (`mTail1`) and lagging down the chain (`JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`). A smack
  calls the same tail impulse through `_on_smack_impact()` at
  `1.0 × _jiggle_size_scale() × smack_intensity`; the thrust tail impulse also scales with
  `jiggle.intensity`. A debug line reports the resulting amount. This is the cheapest way to
  make rump jiggle and tail read as one motion; the shader itself stays native.
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
| `Q` | kiss | left-hand reach to her left shoulder |
| `E` | none (lean only) | right-hand reach to her right shoulder |
| `A` / `D` | none | slow left/right flank caress |
| `Z` / `C` | none | toggle left/right caress oval movement |
| `F` (hold) | none | kiss at a full shoulder lean |
| Mouse right | left/right cheek opposite the lean | same |

- Standing reuses the game's own kiss path: temporarily clear `controls_locked` for
  `pony_kisser.begin_from_pony()`, move `AffectionPose` last in the skeleton so its IK layers on
  the act pose, and call `Affection.end()` on release. This gives the normal face, mouth,
  deep-kiss and soft-kiss audio behaviour. Missionary always uses the custom head-aim path: the
  stock kiss pose is authored for a standing pony and its chest/neck give lifts the lying body
  and turns her head across the mattress. The custom path still sets the mouth expressions and
  repeats the mouth kiss sound. Either path may stop the pony's current speech, but it does not
  interrupt thrusting or stats. `_check_running()` treats the act's own `Affection`-driven
  `kiss` as part of the act instead of an interruption.
- `pony_kisser` physics is paused for the whole act, so the runtime feeds a base kiss the live
  `target`/`eye`/`face` from Anon's real mouth camera and repeats the mouth kiss sound itself.
  Missionary's custom kiss also aims at the player camera, not the separate missionary framing view. The
  excitement Beat timer is paused for the kiss so the stock unicorn horn sparkle does not fire.
- Standing reads `presentation.standing.kiss`: `mouth_right`, `mouth_drop` and `mouth_forward` place
  Anon's mouth target; `camera_yaw_deg` is the over-the-shoulder kiss yaw; `lean_side`,
  `lean_forward` and `lean_drop` are his kiss lean. Missionary keeps the `KISS_LEAN_*` /
  `KISS_CAMERA_YAW_DEG` constants. All standing values apply live from the settings tab.
- `presentation.standing.kiss.forelegs = "planted"` saves the game's `AffectionPose.kiss_settings()`
  `rear` and `hooves` values, sets both to zero before the base kiss and restores them when the
  release pose is removed. `kiss_legs.gd` then captures both foreleg tips before the base kiss
  and runs last to CCD them back to those positions, because the base kiss's chest flex would
  otherwise drag the legs after `body_sway`'s upper-arm pin. `"base"` keeps the stock both-up
  kiss animation.
- While a kiss is active, Anon leans in by the standing `lean_forward` (default `0.03`), shifts to
  the shoulder side by `lean_side` (default `0.46`) and drops by `lean_drop` (default `0.09`)
  lower over `0.35 s`; the standing camera also yaws by `camera_yaw_deg` (default `7°`) toward her.
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
  `presentation.standing.caress.ignore` regions (default `tail` and `wing`; UI also exposes mane and
  legs). This prevents a tail flick after a smack from stealing the caress contact.
  The palm centre sits at `presentation.standing.caress.palm_distance` (default `0.02 m`) at body
  scale `1.0`, multiplied by the pony's actual `body_scale` (clamped `0.5…2.0`); the normal
  smoothing adds no extra lift.
  Contact is cached per hand with
  source hysteresis and short position/normal smoothing: a miss holds the last valid point, a
  flank↔body source change needs two hits, and a near-opposite normal (dot < -0.5) is rejected
  under the same source. The final normal turns from the stock FlankSurface normal toward each
  new contact normal at
  `PALM_NORMAL_MAX_DEG_S = 120°/s` instead of snapping, and the palm basis is rebuilt from that
  final normal every frame. A stale normal is corrected toward the resolved contact normal, not
  the input hint, so a hull fallback at the shoulder cannot turn the palm edge-on. The
  torso-radial fallback only applies to a degenerate or inward normal. The rub centre is lifted
  `CARESS_UP_BIAS_M = 0.05` above each size profile's `up` point, and a 1 Hz log prints the rub
  and shoulder heights, source, misses, switches, normal step/out angle and driven-hand
  distance.
  The oval radii are `presentation.standing.caress.oval_across_m` (default `1.0 cm`) along the
  body and `oval_up_m` (default `2.0 cm`) vertically, both times the pony size scale; the old
  `CARESS_OVAL_ACROSS = 1.30` / `CARESS_OVAL_UP = 0.70` ratios are fallbacks. It reads as a
  stroke rather than a perfect circle.
  Point offsets are per size in `CARESS_PROFILES`: Canon `up 0.08`, JRHNBR `up 0.16 / out 0.02`
  (both hands 4 cm wider), Same Height and Hoers step up from there; those choose where on the
  body to caress, then the contact query snaps the palm to the coat. Both A and D can run at
  once, one hand per side. An A/D tap latches that hand until the next tap. The
  centre interpolates with the lean: backward lean moves it toward the rump top as soon as it
  passes zero (`CARESS_RUMP_LEAN = 0.5`), no lean = flank, half forward lean = side/belly, full
  lean = the exact same shoulder contact point used by the Q/E reach. The circle radius scales
  with pony size; the point offsets are already per size. It is standing-only.
- While a shoulder reach is held, `_forced_glance` locks the pony's glance over that shoulder
  and suppresses the random glance scheduler; release clears it.
- Smack calls the native `FlankTouch.impact(index, at)` with `index 0 = left cheek`,
  `1 = right cheek`. Standing targets the flank patch: if the striking hand is already
  caressing and its contact source is `flank`, that live point is used. A free-hand smack
  targets the chosen cheek: the mark centre offset vertically by `smack.height_m` (default
  `0.05 m`, positive up) × body scale and moved `smack.hind_m` (default `0.09 m`) × body scale
  toward her rump, snapped to the nearest `FlankSurface` point and jittered tangentially within
  `smack_zone_radius` (default `0.035 m`). That keeps a resting hand from
  reaching the leg and puts the contact on the hind of the flank.
  A forward lean therefore lands on the forward flank instead of reaching back to the cheek.
  The body hull is never the smack target and the rump centre is not used. Missionary keeps the
  old decal-centre target: `at` is the mark centre shifted `0.08 m` up and `0.08 m` back,
  jittered within the same zone. The contact palm uses the same `palm_surface_basis()` and
  caress palm distance above. If a hand is already caressing, the smack uses that hand; if both
  are caressing, one is chosen at random. The caress oval keeps moving through the smack, so the
  hand returns to the live point instead of the one it left.
- Standing plays four phases. The contact palm uses the caress finger hint (`-pony.global_basis.z`,
  forward) when caressing, and `Vector3.DOWN` for a free-hand smack, so the fingers stay in the
  right plane. A caress RAISE lifts the palm from its current frame to the contact plus
  `presentation.standing.smack.raise_m` (default `0.30 m`, body-scaled) along the coat normal and
  `SMACK_RAISE_BACK_M = 0.05 m` toward her rump. A free-hand RAISE is a backswing from behind and
  below: `back × raise_m`, `down × (raise_m × SMACK_SWING_DOWN_RATIO = 0.55)` and a small
  `outward × (raise_m × SMACK_SWING_OUT_RATIO = 0.15)` clearance. Both raised bases are the
  straight contact basis pitched down by `smack.pitch_deg` (default `0°`) about the palm normal,
  so the wind-up is a pitch, not a roll around the arm. The lift path bows toward her rump by
  `smack.arc_m` (default `0.10 m`, body-scaled) at the middle of the raise. Its speed is
  `smack.raise_speed` (default `1.5 m/s`), clamped to `0.12–0.30 s`. STRIKE travels straight to
  the contact with cubic acceleration and pitches back to the straight contact basis at
  `smack.return_speed` (default `3.0 m/s`), clamped to `0.06–0.20 s`. CONTACT holds for `SMACK_CONTACT_HOLD_SECONDS = 0.03 s`
  and fires `impact` and `_on_touch("smack")`. RECOVER blends to the live caress oval over
  `CARESS_RETURN_SECONDS = 0.12 s`, or to the captured rest hand over
  `SMACK_REST_RETURN_SECONDS = 0.20 s`, then clears the hold. Missionary keeps the old
  hidden-hand `SMACK_SWING_SECONDS = 0.20` swing, impacting at `SMACK_CONTACT_PHASE = 0.45`. A
  `SMACK_COOLDOWN_MS = 200` gate remains; a new smack waits for the current recovery.
- It reuses the decal, blush, jiggle and expression. With `act_foley` on, the act installs one
  peak-normalised OpenNSFW hand-smack variant from `audio/act/smack/` (two samples, never the
  same one twice in a row) on the native sound player immediately before the impact, with a
  small pitch jitter; `act_foley` off keeps the stock `flank_slap.wav`. The stock stream, level
  and pitch are restored at act end. The pony's `physical_reaction` connections are temporarily
  disconnected around the call, so `flank_smack` cannot trigger the game's buck/fidget/hoof
  shuffle or a bond/context/memory/satisfaction event.
- A right lean (`side > 0`) selects the left cheek index; a left lean selects the right; exactly
  centered picks one at random. The index chooses which cheek decal reddens; standing's contact
  point is the live caress point or the bottom of that cheek. There is no rump target.

### Thrust camera and restore

- The camera thrust is two amounts in `camera_thrust`: `surge` and `bob`, both `0…1`; defaults
  `1.0` and `0.35`. They scale `CAM_SURGE_M = 0.06 m` and `CAM_BOB_M = 0.02 m`.
- Both follow the filtered signed depth speed with one critically damped response. No impulses,
  no per-stroke kick and no camera rock.
- Climax uses `CAM_CLIMAX_SURGE_M = 0.02` and `CAM_CLIMAX_BOB_M = 0.008`, scaled by the sliders.
- Missionary and standing use the same surge/bob. Missionary sends the surge along the mattress toward her
  head; standing sends it along the camera forward.
- Restore order is load-bearing:
  1. release the free-camera control lock;
  2. remove the Anon thrust wrapper and restore any standing palm scale;
  3. restore eye override and hidden avatar;
  4. free the missionary view;
  5. restore the standing camera position;
  6. restore player look, then the missionary snapshot/cuddle.
- Missionary snapshots camera + current camera, player transform and pony transform/posture. Keep
  that snapshot exact; the bed cuddle re-invite depends on it.

## Critical: worn accessories (the tail bow)

The game's wardrobe (`pony_wardrobe.gd`, `pony_fitted_accessories.gd`, `shop_items.gd`) keeps its
`KINDS`, `WORN_NAMES`, slots and stock as script constants, so a mod cannot add a purchasable or
hand-giftable piece there without editing a game script. The tail bow is therefore mod-owned and
uses the game's own runtime accessory idiom (`background_pony.gd`, Braeburn's hat and Vinyl's
glasses).

- `tail_bow.gd` loads one modelled mesh, `assets/tail_bow/tail_bow.glb` (~3.8k triangles, one
  material, no textures): a gift bow with two dished ribbon loops, a rounded knot and two
  swallowtail tails hanging below it. `tools/tail_bow/build_bow.py` generates it parametrically
  and exports the `.glb`; that tool is never packed, and shape changes belong there, not in a
  hand-edit of the exported mesh.
- The mesh is authored with `+Y` up her tail and `+Z` out of its face, sitting on the tail's
  outer surface: the knot rests against the fur, the loops spread to her left and right, and the
  tails hang down the tail. The build tool's `orient()` turns Blender's `+Z`-up frame into that
  one, so the glTF export is already in the frame the runtime places.
- Attachment: a `BoneAttachment3D` on the hair rig's `mTail1`, the name added to a **duplicated**
  `identity.accessories` (typed `Array[String]`; an untyped array is rejected), then
  `refresh_geometry_variant("…|tail-bow")` so both merged meshes re-gather. The merged near mesh
  keeps unskinned BoneAttachment3D meshes apart, the far mesh welds them to the bone, so the bow
  survives every LOD and rides the tail springs and the act's `tail_pose`.
- A `BoneAttachment3D` follows `SkeletonModifier3D` output (verified headless), but
  `get_bone_global_pose()` **outside** a modifier pass returns the base pose. The placement is
  therefore computed once from the rest bone and stored as the child's local transform.
- The hair rig node is already scaled to her size (`body_scale`), so the mesh is modelled at unit
  size and only `presentation.tail_bow.size` and her tail radius scale it. Never multiply by
  `body_scale` again.
- Placement is entirely in the tail bone's rest frame, so the bow rides the tail and follows every
  swing: the origin sits on the bone's dorsal side at `along_m` down the tail, `+Z` is the bone's
  own `z` axis, `+Y` is `+y` (which runs up her tail in the rest pose) and `+X` closes the frame.
  The knot is therefore against the fur, not threaded on the tail, and the tails hang down it. No
  world-space body axes are involved.
- The knot stands off her tail by `tail_radius(pony) * FUR_SCALE` (`1.9`), and that radius is
  `identity.tail_segment_radii[1]`. Those are the springs the hair fan is drawn around, and the
  fur is much thicker than them, so a bow placed on the spring radius disappears inside the tail.
  A constant share is deliberate: measuring her visible tail mesh needed per-vertex skinning,
  cost ~150 ms per pony and produced unstable results.
- The bow's scale is her spring radius over `AUTHORED_RADIUS` (`0.06 m`) times `size`, so a thicker
  tail gets a bigger bow without re-authoring the mesh.
- `refresh()` re-applies the transform and the dye in place; the geometry never changes at runtime.
  Tying the bow on defers the `refresh_geometry_variant()` call (`call_deferred`) because that
  rebuilds both merged meshes; doing it inside the frame that ties the bow on, or inside an act,
  is a visible hitch. Settings edits must never detach and re-attach the piece for the same reason.
- The imported material is replaced with `satin()`, a matte cloth `StandardMaterial3D` whose albedo
  is the dye, so one mesh covers every colour. `presentation.tail_bow.*` tunes `size`, `along_m`,
  `tilt_deg` and the dye (red by default). `size` defaults to `1.5` and `along_m` to `0.06 m`,
  which puts the bow on the dock rather than up on her croup.
- `tests/bow_preview.gd` ties the bow on a loaded mare and writes `/tmp/opencode/bow_*.png` from
  behind, the side and close up. Run it with the real display driver; shape work is verified by
  looking at those images, never by guessing.
- Worn state is `Mods.state("unfplap").tail_bows`, keyed by pony id, saved with `Mods.save_changed()`.
  `tail_bow_gift.gd` reconciles once a second: a worn record without a mesh ties one on and a mesh
  without a record takes it off, so a bow survives world loads and late-spawning ponies.
- The gift is verbal: `offer_kind()` matches Anon's line locally ("I got you a tail bow", "take that
  bow off"), her answer goes through the shared classifier (`classify_agreement`, kind
  `agreement`, one queued job) with a local yes/no fallback, and the game's own gift willingness
  (anger ≥ 35 or an asked-for boundary) can refuse. An accepted gift flusters her, records a
  `gift` bond experience and a `gift` world-context line, then saves.
- `main.prompt_note()` reports the worn bow to her own dialogue prompt; the stock wardrobe line
  only knows its own kinds. `_exit_tree()` takes every bow off so a mid-game switch-off leaves no
  orphaned accessory.
- **Debug → Actions** has "Tie on a tail bow" and "Untie the tail bow" for the aimed or nearest
  mare, bypassing the conversation.

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
- Talk is scored when the player actually speaks. The game's `T` text/mic turn is detected
  through `conversation_director._turn_id` / `_player_text`; the AI still writes her reply.
  There is no act talk-invitation line or HUD hint.
- Do **not** add a thrust debug sub-gate. The per-thrust log is the scoring view.

Read `PREFERENCES.md` for the exact taste schema, readiness rates, cue rules and character
examples.

## Act flow, gates and controls

- Eligibility: adult, not filly/colt, player not young, love level ≥ 2, and
  `bonds.welcomes(id, "kiss")`.
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
- Act actions: `W`/`S` lean forward/back, `Q`/`E` side lean plus pose reaction, `A`/`D` caress,
  `Z`/`C` toggle caress movement,
  `F` hold kiss in standing, mouse right smacks. They are available in `ACTIVE`, `CLIMAX`, and the
  standing `AFTERGLOW`; `Y` is the context start/end control. `H` is the game's hug/deep-kiss key;
  the act consumes it without binding it so a hug cannot end the act's kiss.
- `Y` starts an act on a single press when idle. During an act, `Y` is a `0.35 s` hold, matching
  bridal-carry initiation; a tap does nothing there. In `ACTIVE`, hold Y cancels with 0 pony
  climaxes and enters afterglow with 1+; in `CLIMAX`, hold Y enters afterglow. Hold Y ends
  afterglow; Y is ignored in `RESTORE` except for event consumption. `T` remains the game's talk
  key and is not consumed; the runtime watches player turns as a scoring input. `Q`/`E` are the
  side lean; during an act the interaction keys are still consumed so the game's stand-up action
  cannot interrupt the scene.
- States: `IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE` for both poses.
- Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.
- Aftercare starts only at final readiness ≥ 10; it holds navigator ownership for 10 s and
  keeps the tail raised straight with reduced flicks.
- A positive act also starts `satisfied.gd` for 300 s, matching the impression mood freshness:
  a relaxed face, light blush and a warm prompt note. It does not hold the navigator or block
  another act; a new act clears it.
- Each pony climax records a unique memory event and reaction. The act-level romance impression
  and witness pass commit once at afterglow; standing records the inside event at afterglow only.
  The standing afterglow also runs the 8 s close window and records its own stay-close memory.
- A peak act keeps one strongest memory per mare in `Mods.state("unfplap").peak_memories`.
  It is written only with no disliked touch/talk and either peak satisfaction >= 90 or six
  both-axis thrust matches; a higher score replaces it. The stored text is the last player
  exchange, or a generic warm beat when he did not speak. The cue prompt prefers this memory.
- Memory uses the game's second-person phrasing. Witnesses are nearby awake adults; sleeping
  ponies and fillies/colts are skipped.
- Proactive requests are a separate controller (`initiation.gd`), not an action tag. They never
  start the act; `Y` remains the only act-start path.

### Proactive requests

- One request episode at a time. Automatic requests require AI usage Full
  (`AI_CONFIG.background_allowed`), an idle director, no group exchange, no hearing, and no
  character chat within 45 s. The lab runs in Talk, so trigger offers from **Debug → Actions**.
- Offer eligibility uses `runtime.can_offer(pose, source, bed)`, not `can_start`: an offer may
  exist before the pony is lying or Anon is in position. `Y` still calls `can_start` as the final
  gate.
- The mare chooses the pose. With both a usable bed and a standing offer, she picks one at
  random (`pick_offer_pose`); with one, she uses it. An active cuddle always offers missionary.
- Cuddle: requires an active cuddle and `can_offer(MISSIONARY, "bed_side")` or
  `"already_lying"`. Indoor privacy is house-only solitude; outdoors it is nobody
  within 30 m. A cuddle rising edge clears that mare's cooldown and permits one ask per cuddle.
- Bed: a free bed within `BED_SEARCH_M = 10 m` of Anon, same region and floor, with no other
  guest or sleeper. She walks to the bed front, asks him to come to bed, and waits up to
  `BED_WAIT_TIMEOUT_S = 90 s`. Once Anon lies on that bed, the native `SharedBedRest` seats her
  beside him; then she queues the invite line and `Y` becomes available. Lying down after the
  ask's `PHYSICAL_ACCEPT_GRACE_S = 2.5 s` grace counts as a physical yes. No free bed means she
  cannot choose missionary.
- Standing: requires `can_offer(STANDING)`. She walks to a spot 2 m in front of Anon's view (same
  navigation region, ≤24 m, empty/`life:` navigator owner, 35 s deadline). The ask is decoupled
  from the Y aim zone: it starts when she is still present and eligible, not only while the
  player aims at her flank.
- Private means alone in the house or nobody within 30 m. Private asks directly and makes the
  invitation available; with others around she only hints.
  A throttled `request privacy ...` log lists the player position, house, every mare in the
  house, every mare within 30 m separately labelled with the target, and the computed result.
  The offering mare is excluded from the other-pony checks, so the target label in the log is
  diagnostic only.
- Private offer order: she asks, Anon answers by text/voice, then the pose-specific invite.
  Clear yes/no uses `consent_classifier.local_intent()`; anything else is classified by a short
  provider request (one try, 16 tokens, 4 s) after the director is idle. The request includes an
  offer line so short answers like "right here" are understood. The controller does not run the
  classifier beside the director's own reply; that caused HTTP 429s. A decline cancels with the
  full cooldown and no presentation.
  - Standing accept re-checks privacy, presents, waits for `runtime.presentation_settled()`, queues
    one generated comment/invite line, then waits for `Y`.
  - Missionary cuddle accept queues the invite line in the existing bed.
  - Missionary bed accept walks her to the bed (`bed_lead`), waits for Anon to lie down
    (`bed_wait`), joins through the bed rest, then queues the invite line.
  - `Y` itself keeps its old behavior: pressing it during any phase cancels the episode and
    starts the act immediately.
- The private standing ask/presentation has a request face: full blush and half-lidded eyes while
  she asks and presents. It also sets the game's `affection_active` hold so an AI
  `[approach]`/`[follow]` from her reply cannot break the pose; `_nav_pose_gate` exempts that
  hold while `_request_face` is true. If movement still clears the presentation, the controller
  re-presents twice before ending the offer. The bed invite does not set the request face because
  `SharedBedRest.eligible()` rejects `affection_active`.
- The standing invitation is IDLE-only: turn away with `pony.face_direction()` at
  `PRESENT_FACE_TURN_RATE = 1.5`, clear navigator `face_point` and conversation target late each
  physics tick, then attach the standing modifier and tail-aside once the turn settles. Do not
  write the transform directly during the turn: that rotated the body under planted hooves and
  twisted her legs. After settling, hold `face_turn_rate = 0` and lock the body facing. It is not
  the act: no camera, lock, HUD or `sex_active`. `unfplap:request:` navigator ownership keeps
  `Y` valid until the episode ends.
- Initial ask uses `begin_player_greeting` with a situation prompt; the context event is recorded
  as `situation`. The ask must be phrased as a question. Reminders are generated at 12 s and
  24 s. A no-reply offer gives up at 60 s; after any answer the deadline is 45 s, and after a
  clarification 30 s. A pending classifier or a busy director extends the deadline instead of
  cancelling the line. An unclear answer gets one clarification. A give-up records an "offer is
  over" situation, queues a short give-up line even when he answered, and logs
  `request end ... reason=...`; the invite phase waits up to 60 s after the comment.
- Cooldown is 600 s per mare in `Mods.state("unfplap").request_times`. An approach, bed walk or
  initial-ask failure sets a short 30 s retry instead; an ask, presentation, invite or give-up
  sets the full cooldown. `Y` cancels the episode before `start()`; the act-start path keeps the
  bed rest so `runtime.start()` still sees her lying.
- The **Debug → Actions** offer buttons force a missionary or standing ask; they bypass quiet,
  cooldown and AI-usage checks for lab testing, but not relationship, consent, pose or free-bed
  gates.

### Y start gate and aim zone

- `features.press_y_starts_sex` defaults **off**. `main.try_start()` is the only act-start
  path; `runtime.start()` now takes an explicit `y_allowed` gate and refuses without it.
- `INITIATION.y_start_allowed(flag, source, scenario)`:
  - flag on: any valid offer;
  - flag off: `bed_side`, `already_lying`, an active proactive request, or a dialogue
    agreement. `ask`, `present`, `invite`, `bed_lead` and `bed_wait` all keep the request
    scenario.
- Standing offers use the base game’s smack-flank selection: crosshair on the flank and
  `TOUCH_REACH = 1.6 m`. This applies with the flag on or off. Missionary bed offers stay
  contextual.
- `dialogue_consent.gd` checks every player line with a pony reply through the shared
  classifier. `sex_accept` leaves a per-mare agreement until she moves, changes region or
  posture, refuses, the act starts, or the world closes. The Y hint still only appears in the
  smack-flank zone.
- `consent_classifier.gd` is one shared service: one LLM client, one queue and scoped
  cancellation for `offer:` and `dialogue:` jobs. It never runs two mod classifier requests at
  the same time.

## Dialogue utterances

- Cues are event-driven: a touch/talk result, an overwhelmed state, or a ready state.
- `utterance_scheduler.gd` is the pure admission policy: it owns `mood_for`, `base_cue`, the
  stability clock, `cue_gap` (default `12 s`, clamped `8..30`, per character), the shared 18 s
  utterance gap, the demand budget and the single pending slot. `runtime.gd` builds the prompt and
  calls the director.
- A base cue must stay unchanged for `CUE_STABLE_S = 2 s`. A live touch/talk override only needs
  `CUE_OVERRIDE_STABLE_S = 0.5 s`, so an event cue can speak inside its 2.5 s HUD lifetime; if the
  override ends while the row is still queued, it is dropped. It is fine if the line is lost.
- Demand cues ("She wants…"/"She needs…") have a separate `DEMAND_LINE_GAP_S = 28 s` budget
  and a `DEMAND_REPEAT_S = 45 s` lock for the same text, so a flapping preference cannot become
  a stream of commands. The same text as the last queued cue is not repeated; it can return after
  a different cue has been queued.
- A cue line uses the `cue` prompt. The state line contains pose, mood, taste-axis motion, last
  touch, last talk, pony climax count and act time; it contains no speed or depth units. The
  cue prompt gets `CUE_REACTION_NOTE`, which tells the model to phrase the cue as a reaction or
  preference rather than a repeated command. Custom prompts may use `{state}`.
- Every cue line carries a private relationship note and tone. The note uses the friendship/love
  level names, relationship stage, first-time/repeat and current mood; the tone is `tender`,
  `warm`, `ardent`, `open` or `careful`. The functional cue text is unchanged. The prompt tells
  her not to say the labels, levels or numbers.
- The cue prompt may include one unused shared memory. `MEMORY.shared_memory()` prefers the
  stored peak memory, then the story journal: a cue-word match, then the most recent player
  exchange. It falls back to the world-context events. Intimacy events and private brain notes
  are not used as the hint. The memory is marked used only after the line is queued. The peak
  memory quotes her answer only when she actually spoke during the act (a start-of-act
  `last_spoken_at` baseline).
- One mod line owns the slot at a time, cue or reaction. A new line needs an idle director and
  pony and `UTTERANCE_MIN_GAP_S = 18 s` since the last line was accepted. Reactions take the slot
  without the cue-stability/gap gates but reset the 18 s clock, so a cue cannot follow immediately.
- The pending slot stays reserved until speech stops and a 1 s release hold passes. A row that
  reaches `CUE_MAX_AGE_S = 20 s` (cue) or `REACTION_MAX_AGE_S = 30 s` (reaction) while still
  `queued` or `generating` is cancelled; a `speaking` row is never cut by age. The runtime observes
  `MEMORY.line_state()` (`absent`, `queued`, `generating`, `speaking`, `delivered`, `unknown`) and
  frees the slot when the director drops or delivers the row. The old 60 s watchdog is gone.
- Cue `valid` remains tied to the pony/event id, not `State.ACTIVE`: cancelling the act must not
  invalidate a line that is already generating or speaking. Act boundaries still cancel queued and
  generating rows through `_end_act_lines()`. Reaction lines additionally carry their 30 s expiry,
  because they can outlive the act slot; a speaking reaction is kept past that expiry.
- The repeat hint contains the last four generated lines. There is no talk-cue line.
- Each pony climax drops queued act lines but keeps an in-progress one, then queues a unique
  climax reaction through the same slot. The standing afterglow records its inside event without
  queuing a line. Only the cached “Mm.” is used; generated moans are parked.
- `_end_act_lines()` cancels every mod-owned line for the act except one that is already
  **speaking**. Queued and still-thinking lines are dropped. It runs at climax, afterglow and
  every act end (`cancel`, `_restore_begin`, `_restore_now`, `_abort_start`). The intentional
  early-stop line is queued after the restore begins.
- `features.act_lines` (default on) gates cue lines and climax/early-end reactions. Off keeps
  normal dialogue and the HUD cue.
- The standing afterglow no longer queues `inside` or `stay_close` lines. Normal dialogue resumes
  with the afterglow context event; the HUD close timer owns the invitation. The prompt note
  provider (`main.gd` → runtime) reports caressing/leaning, and `[stay: SECONDS]` extends the
  no-self-end hold.

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
- The act controls are a bottom-left, top-down list: one row per button, each with a keycap or
  controller icon, a muted `Hold`/blank modifier column, and one description. Rows list mouse
  thrust, W/S, Q/E, A/D, Z/C caress movement, F (`Hold`), mouse right and Y (`Hold`); the Y
  description is `Afterglow`, `Stop` or `Exit` by state. A muted `MAKE LOVE` title names the card,
  like the carry card's title.
- The quick-slot inventory HUD is hidden for the whole act via `inventory.hud_hidden` and the
  hotbar's `set_hud_visible(false)`; the previous state is restored on every exit path:
  `_abort_start()`, `_restore_now()`, `_finish_restore()` (including the invalid-pony branch),
  and `force_stop()`. `_physics_process` also restores it if `IDLE` is ever reached while still
  marked hidden. The inventory's `_place_hotbar()` re-evaluates the state after restoring, so a
  stale pre-act layer flag cannot leave it hidden.
- The bottom-left stack reads, top to bottom: cue line `❤ N/3 | cue`, readiness line
  `Wants: intensity & pattern | You: intensity & pattern`, readiness bar, blank separator,
  `MAKE LOVE` title, controls.
- The `Wants`/`You` line, short readiness bar and cue segment are all gated by `hud_readouts`
  (default `true`). The bar has no ticks. The hearts remain when readouts are off.
- Afterglow shows `❤ N/3 | close hint` instead of `Wants`/`You`. Missionary keeps only `Y`;
  standing keeps forward/back, Q/E reach, A/D caress, Z/C caress movement, F kiss and Y, while
  thrust, smack and talk
  are hidden. The standing close hint is independent of `hud_readouts`.
- Love XP and happy mood are granted once by `MEMORY.commit_climax()` at afterglow.
  `MEMORY.stay_close_reward()` may add a small extra romance, happy mood and private thought
  when the standing close window is completed; staying alone records the memory without the extra
  romance. No other afterglow reward is granted.
- `captions_on_top`, default `true`, moves the game's desktop bottom caption to the top only
  when `access/speech_text` is the explicit bottom-caption mode; overhead and auto are untouched.

## Debug and testing

- The backtick command console is gated by `DEV.enabled()`. Source/editor runs have it; a
  player build unlocks it with **Settings → Updates** pressed five times. Acts own
  `controls_locked`, so the console is not available while an act is running.
- Debug actions live in `TUNABLES.ACTIONS` and render as **Debug → Actions** buttons. Adding an
  action is one entry; give it a `hotkey` only when it must fire while the world is unpaused and
  you are looking at the scene. A hotkey-less action is the default.
- **Trigger bed offer** / **Trigger standing offer**: force a proactive ask for the aimed (or
  nearest) test mare. They bypass the quiet, cooldown and AI-usage checks, but not relationship,
  consent, pose or free-bed gates; use them in the lab, which runs with `ai_usage=talk`. The
  status label reports the target or gate rejection. Because the settings page pauses the tree,
  an offer advances after it closes.
- `F10` (the only hotkey action): toggle the skeleton overlay for nearby ponies. Lines are thin
  (`LINE_HALF_WIDTH = 0.0015`) and joint circles remain visible; hover a joint to turn it red,
  then left-click to print its bone name, parent, world/local origin, rotation, scale and rest.
- `debug_logs` is read from settings and defaults OFF. Toggle it with the **Debug logs**
  checkbox in **Debug → General**; there is no hotkey. It controls logging only.
- With `debug_logs` on, an act prints one `perf` block a second: pony, pose, state, fps, frame
  time, `near_mesh`, sim tier, wing hold, dock-follower state, then the per-second cost of every
  timed chunk (runtime process/physics, pose recipe, tail pose, body sway, ear twitch, dock
  fast/full/start, caress, wings, kiss, camera motion, HUD). A chunk calls
  `runtime.perf_note()`, and `_perf_tick()` prints; use it to attribute a pony-specific stall
  instead of guessing. The window clears whenever the runtime is `IDLE`, so nothing prints
  outside an act.
- `act_ear_pin` sits in **Debug → Act flow** and defaults off; when off the act skips
  `expressions.fluster()`, keeping normal ears while the blush, gaze and ear twitch remain.
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
- `runtime.debug_line()` includes the target's voice line.
- `mute_ponese_audio` mutes only the partner's `Voice` audio player for an act while keeping
  the generated text/HUD flow. It does not suppress dialogue.
- The Unfplap settings tab is **runtime-injected** with
  `Mods.on_node("res://world/ui/settings_page.gd", ...)`, not a `mod.json` extension. If the
  page's private fields are unavailable it logs and skips, so the settings page is never
  required for the mod to load.
- The injected tab also owns the **Character taste** editor: one pony selector from
  `SETTINGS.CHARACTER_ORDER`, enum controls from `preferences.gd`, recovery `0…80`, touch/talk
  like and dislike checkboxes, and editable private notes. Taste edits save automatically and
  apply live; `Reset to default` removes only that taste override. Custom `event_prompts` and
  `poses` on the character entry must survive both actions.
- Injected pages/buttons are tracked and removed in `_exit_tree()`. Do not add `extends` for the
  settings page.

## Settings and persistence

**Every global setting is a tunable.** Add, read and edit them only through `tunables_schema.gd`
(one line per entry) and `tunables.gd` (typed API); `tunables_ui.gd` draws the panels. Never add a
widget, a defaults constant or a save function for a setting anywhere else, and never clamp a
debug value. The full contract, including the three-step recipe, is `TUNING.md`.

- `settings.json` path: `user://mods/data/unfplap/settings.json`
  (`~/.local/share/home-equestria-public/mods/data/unfplap/settings.json`).
- The file is read once per process into memory (`SETTINGS._cache`) and written only when a value
  changes. Opening the Unfplap settings tab calls `TUNABLES.reload_settings()`, so a hand-edited
  file applies when the tab opens; otherwise it needs a restart.
- Top level: `debug_logs`, `features`, `thrust`, `jiggle`, `camera_thrust`, `presentation`,
  `default` template, `characters` overrides.
- Feature flags live in the tunable schema (`tunables_schema.gd`, paths `features.*`) and are read
  through `tunables.gd`; the runtime snapshots them with every other act value in
  `_snapshot_settings()` at act start, and `apply_live_settings()` re-runs that snapshot after any
  settings edit. Keep these documented here when adding one:

| Flag | Default | Gates |
|---|---|---|
| `hud_readouts` | `true` | mood cue, readiness bar and `Wants`/`You` segments; hearts and the close prompt stay |
| `act_lines` | `true` | cue lines and climax/early-end reactions; off keeps normal dialogue and the HUD cue |
| `idle_camera_sway` | `false` | slow idle breathing when not leaning; true adds the drift |
| `captions_on_top` | `true` | move the explicit bottom caption to the top; applies immediately |
| `standing_body_sway` | `true` | standing upper-body sway modifier |
| `missionary_body_motion` | `true` | missionary torso slide and head nod on the thrust |
| `thrust_ear_twitch` | `true` | standing thrust ear-twitch modifier |
| `standing_plant_feet` | `true` | hold Anon's hip and both foot targets at their act-start positions, feet 15 cm behind; off restores the game's stepping/lean foot motion |
| `act_ear_pin` | `false` | Act flow section: pin act ears |
| `allow_act_during_cuddle` | `true` | allow starting an act while the stock cuddle session is active |
| `press_y_starts_sex` | `false` | Y start gate: off restricts starts to requests, dialogue agreements and bed contexts |
| `mute_ponese_audio` | `true` | mute a Ponese-only act voice but keep its text |
| `act_foley` | `true` | pack thrust, slide, bed/fabric, mouth-kiss and flank-smack foley |
| `act_vocals` | `false` | pack climax moan only |
| `act_climax` | `false` | pack wet finish layer |
| `bed_creaks` | `false` | wooden `bed_wood_in` / `bed_wood_out` cues; plaps, slides and fabric stay |
| `tail_bow` | `false` | satin tail bow accessory and its conversation gift; off by default, off hides worn bows and keeps the record |

Always on: standing afterglow stay-close window, lean-camera inertia smoothing and strong-thrust
rump blush. Unknown settings keys are ignored.
- `thrust.orientation`: `"up"` (default) means mouse up deepens; `"down"` flips it.
  `thrust.pixels_per_full` defaults to `1000` and clamps to `240…1200`; `thrust.travel` is the
  hip backset multiplier, default `0.5`, clamped to `0.25…2.0×` as a player-facing contract.
- `jiggle` stores the shared rump wobble `radius` in metres (default `0.26`), the thrust
  `intensity` multiplier (default `0.25`) and the act-smack `smack_intensity` multiplier
  (default `0.45`). It is read live with the other thrust controls.
- `camera_thrust` stores `surge` and `bob`, both `0…1`; defaults `1.0` and `0.35`. They scale the
  speed-driven camera travel and apply live during an act.
- `presentation` is split per pose:
  - `missionary`: `forward`, `height`, `side`, `pullback`, `side_lean`, `pitch_deg`.
  - `standing`: `glance_back_speed`, `torso_angle_deg`, `idle_sway_side` (default `0.0`),
    `neck_down_deg` (default `30°`), `chin_up_deg` (default `30°`), `tail` with `yaw_deg`
    (default `31.5°`) and `pitch_deg` (default `24.1°`), `caress` with `palm_distance`,
    `oval_across_m` (default `1.0 cm`), `oval_up_m` (default
    `2.0 cm`), `palm_scale` keyed by `canon`/`mounting`/`same height`/`hoers`, and `ignore`,
    and `smack` with `raise_m` (default `0.30 m`), `hind_m` (default `0.09 m`), `height_m`
    (default `0.05 m`, signed), `arc_m` (default `0.10 m`), `pitch_deg` (default `0°`),
    `raise_speed` (default `1.5 m/s`) and `return_speed` (default `3.0 m/s`). The smack values
    are experimental/unbounded.
  - The legacy flat presentation block migrates once in `_normalize_presentation()`; its
    obsolete camera key is dropped.
- **Never clamp a debug setting.** A schema `num` entry is stored and returned verbatim; its
  `low`/`high` only limit the spin box arrows, so a hand-edited out-of-range value still applies.
  Only a `user_num` entry clamps, and only because its bound is part of the player-facing
  contract (sensitivity `240…1200`, hip back-off `0.25…2.0×`, camera surge/bob `0…1`, glance
  speed `0.25…3×`). Do not add a clamp in a consumer "to be safe": if a value must be bounded to
  stay playable, make it a `user_num` and say so in the help text.
  No consumer clamps a tunable-derived value today; the jiggle radius, idle sway, smack raise,
  smack arc and caress oval radii are applied as stored. The only other bounds are the smack
  animation duration (`0.12–0.30 s` raise, `0.06–0.20 s` return), which bound the slide, not the
  setting.
- Feature flags are split by the schema's `tab`: entries marked `"settings"` are the
  player-facing page, every other flag is in the Debug page. Label, help and section all come
  from the schema entry; there is no separate feature info table.
- The injected tab has nested **Settings** and **Debug** sub-tabs, both drawn from the schema by
  `tunables_ui.gd`: one row per entry, grouped into click-to-collapse sections from each entry's
  `group` (`"Standing › Smack"` is a subheading under `Standing`). **Settings** holds the
  player-facing flags, **Thrust**, and the hand-built **Character taste** form (a per-mare profile,
  not a global tunable). **Debug** holds every other entry plus the **Actions** buttons. There are
  no Save buttons: each edit writes its path and calls `main._apply_settings_changed()`, which
  refreshes the flags, the caption position and the active act.
- `debug_logs` defaults to `false`.
- Character entries inherit unspecified fields from `default`.
- Key fields: `smack_zone_radius`, `aftercare_min`, `cue_gap`, `taste` (`recovery` included),
  `act_prompts`, `event_prompts` (`climax`, `end_early`),
  `poses.missionary`, `poses.standing`. `cue_gap` is a per-character JSON value, not a settings-tab
  control.
- The settings editor lists `SETTINGS.CHARACTER_ORDER` (16 IDs) and uses `CHARACTER_NAMES` for
  display labels. Add a pony to both and to `CHARACTER_TEMPLATES` when expanding the roster.
- Pose defaults live in `poses/catalog.gd`; taste defaults and validation live in
  `preferences.gd`/`settings.gd`.

## Documentation discipline

This is mandatory.

- Update the contract in the same commit as behavior, settings or controls. Put rationale,
  measurements and tuning history in the code comment or the contract doc; commits are one line.
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
- Keep `AGENTS.md`, `README.md`, `PREFERENCES.md`, `ROTATION.md`, `TUNING.md` and `WORKFLOW.md`
  consistent.

## Known constraints

- The stock 0.3.0 bed is size-aware: `eligible()` accepts up to `1.05 * Settings.pony_scale()`
  and `_mare_fits` scales her half of the lane and her length with her size. A bed too short for
  a Hoers or Same Height mare is refused; that is stock behavior, not a mod override.
- `[go_to_bed]` keeps a `sleep:` navigator lease even while she lies awake by day. A bed-side
  offer through that lease is valid only for `bed_side`/`already_lying` when she is not sleeping
  and `posture_status().requested == "lie_down"`; walking to bed or sleeping is not.
- "Same Height as Anon" now follows Anon's `player/height_cm`. The mod's lean scale, standing gap
  and caress offsets follow the same multiplier; other size presets keep their authored values.
- Standing kiss offsets, the missionary virtual mouth and kiss lean distances scale with Anon's chosen
  height (`Settings.anon_height_scale()`), matching `player/player_mouth.gd`.
- `captions_on_top` is mod-owned: `main.gd` finds `SpeechCaption` through `Mods.on_node`, then
  moves its private `_card` to the top margin after the caption's own layout pass. It skips the
  settings-page preview and quietly does nothing if the card fields disappear.
- The stock bed captures a snuggle guest's rest transform at invite time from the player's
  reclined hip/head targets. Inviting before that blend settles puts the target at standing
  height, so `hop_clear` fails and the guest never climbs on. The lab waits `1.2 s` after lying
  down before inviting.
- The talk classifier in `preferences.gd` is a small keyword map, not an LLM call. Expand it
  only from real playtest phrasing, and keep `talk` empty for mares who should not score it.
