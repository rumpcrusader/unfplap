# Rotation and positioning contract

This file records the brittle skeleton/pose logic. Keep it next to the code and update it
whenever a pose value or order changes.

## Spaces and axes

- Bone writes use `Skeleton3D` skeleton space via `get_bone_global_pose` /
  `set_bone_global_pose`.
- Axes are body-relative:
  - `right = sk.global_basis.inverse() * pony.global_basis.x`
  - `up = sk.global_basis.inverse() * pony.global_basis.y`
  - `forward = sk.global_basis.inverse() * -pony.global_basis.z`
- `up` is world gravity, not the pony's rolled dorsal axis.
- Never use raw world axes for bone posing.
- `pony_head.basis.z` is **not** the face axis. The head must not be rotated by
  straight-chain alignment; keep it in the bone list only as a direction target for
  `pony_neck2`. The head follows neck2 through its rest offset.

## Missionary (Pose 1)

Exact order:

1. `_roll_root(PI * weight)`
   - pivot: `pony_hips` origin
   - axis: `forward`
   - rotates root origin and basis, then adds `up * 0.03 * |angle|`.
2. `_lift_root(0.05 * weight)`.
3. `_straighten_spine_neck()`
   - bones: `pony_hips`, `pony_spine1..3`, `pony_neck1..2`, `pony_head`
   - slerps each local pose rotation toward its rest rotation by weight.
   - Including the pelvis removes the game's bed `lie_down` curl.
4. `_align_chain_straight()`
   - bones: spine1–3 and neck1–2; head is a direction target only.
   - target is `forward` with `y = 0`, normalized.
   - each bone direction is measured to the next bone's origin.
   - shortest-arc rotation directly written to the global pose; no joint-limit clamp.
5. `_level_body_roll()`
   - left/right hind-femur origins.
   - `_line_roll()` measures the lateral line; wrap the result into ±90°.
   - adds `POSE1_ROLL_TWEAK`.
   - rotates the root around `forward` at the hips pivot.
6. `_level_chest_roll()`
   - left/right upper-arm origins.
   - `_line_roll()`; rotates only `pony_spine1` around `forward`.
7. `_pitch_body_about_shoulders(POSE1_RUMP_DROP_DEG)`
   - pivot: midpoint of the two upper-arm origins.
   - rotates root origin and basis about `right`.
   - positive angle moves the pelvis/rump behind the pivot downward.
8. `_bend_forelegs(0.3)`.
9. `_raise_hind_legs()`
   - femur target `(up * 0.75 + forward * 0.45).normalized()`
   - knee bend `-0.55` around `right`.
10. `_hug_forelegs()`.
11. `_aim_head(POSE1_LOOK_SCALE)`
    - yaw/pitch from head origin to `look_point`.
    - neck shares `[0.30, 0.36, 0.34]`.
    - pitch clamp `±0.8`, yaw clamp `±1.1`.
12. Nuzzle
    - `_nuzzle_pulse()`: 0→1→0 over `NUZZLE_DURATION` every `NUZZLE_PERIOD`.
    - extra `_aim_head(pulse * POSE1_NUZZLE_SCALE)`.
    - during climax: `pulse = 0.75 + 0.25 * sin(_clock * 4.0)`.
13. Kiss aim: extra `_aim_head(weight * kiss, 1.0, look_point)`.
14. `_neck_lift(neck_lift_deg)` around the body right axis on `pony_neck1`/`pony_neck2` (half
    each). Default `15°`, applied after the aim so the lift is a fixed offset. Measured with the
    head aimed at Anon, the neck-to-body angle is ~13–15°; the lift takes it to ~30°. In the
    standing model this is the chin-down direction, which becomes an upward head lift on her back.
15. `_roll_head(head_roll)` around `forward`, head only.
16. Dump once at weight > 0.9 if debug is on.

The debug chin pitch lives in `chin_debug.gd`, a separate `SkeletonModifier3D` appended after
the pose modifier. It is not part of the missionary recipe, so `Alt+7` / `Alt+8` also work
while idle or standing.

`_line_roll` must always select the branch nearest level, in (−90°, +90°]. Without the
wrap, the correction can roll her belly-up to belly-down while still "levelling" the
legs.

### Head-back effect (reserved)

Positive `_lift_neck()` angles were `0.10 / 0.08 / 0.06` around the body's right axis.
They throw the neck/head back and were intentionally not applied in missionary. Keep
these values here if a future pose needs that effect.

## Pose-1 camera

- Anchor: `root + up * (0.45 + POSE1_CAMERA_LIFT_M 0.10) * body_scale + back * 0.22 * body_scale`,
  where `back = +pony.global_basis.z`. The anchor stays behind her neck, toward her rump, so the
  frozen aim looks forward along her body at her face; anchoring ahead of the neck aimed the shot
  back down her torso. Canon height is `0.9×`; JRHNBR (`1.35`) gets a proportionally higher,
  farther-back anchor. The **Act presentation → Missionary** axes move the frozen anchor:
  `pose1_forward` (default `0.10`), `pose1_height` (default `-0.10`) and `pose1_side`
  (default `0`; positive is her right). All are experimental and unbounded. The
  **Missionary pullback** setting (`pose1_pullback`, default `0.22 m`, times body scale) then
  pulls the shot back along `_pose1_view_basis.z` (its own view axis), and
  `POSE1_START_LEAN = 1.0` (one full
  `LEAN_FORWARD_M` lean) advances it along the same axis. The shot therefore starts at the old
  maximum W-lean point, and W pushes further up her torso toward the neck. The aim basis is
  computed once from the stable anchor, not the moved view, to prevent start-up flicker.
- Aim: sample the middle of the neck (`pony_neck1`/`pony_neck2` midpoint) during the first
  second while the pose blends, then freeze. The live snout is not used, and the target is never
  derived from the moving view.
- The aim basis comes from the stable anchor and is updated only during that settle second; no
  forward-dot re-aim loop. A neck point behind the anchor is rejected, so the shot cannot flip
  back down her torso. Rebuilds are limited to an invalid/too-far anchor or a genuinely
  below-valid-bed top. A missing bed returns `INF`, not `0.0`. Her head aims at Anon's player
  camera, not the framing view, and its look point keeps at least `0.45 * body_scale` from her
  head. The look point moves with the lean's lateral shift and `pose1_side_lean` travel, so a
  side lean turns her toward the lean. Aiming at the framing view (now behind her neck) demanded
  a half-turn and snapped her head side to side.
- Pose 1 hides every `*AnonBody*` presentation node and disables the desktop presentation for
  the act, re-applying each tick; both are restored at end. The stock bed body must never appear
  inside the shot with a different orientation.
- Pose-1 body motion is `prone_sway` (`pose1_body_motion`): the spine slides along the bed with
  raw thrust depth, and the neck/head nod about `3°`. It is separate from the standing
  `body_sway` (`pose2_body_sway`) and does not pin hooves like the standing pose.
- Eyes: `ACT_LIDS = 0.45` in `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` in `CLIMAX`, sleepier
  `0.90`/`0.95` in afterglow. `_eyes_tick()` reasserts the stare late each tick.
- Lean is clamped to stop `0.12 m` short of the neck target in both directions, so the camera
  can never cross its own look point and flip backwards.
- The camera has no mouse look. `W`/`S` lean forward/back and `Q`/`E` lean sideways:
  `side = E - Q`, `forward = W - S + abs(side)`.
- Lean ramps over `0.5 s` and returns over `1.6 s`. Forward lean translates `0.24 m`; backward
  lean is halved to `0.08 m`; side lean translates `0.18 m`. Both directions pitch `6°` down,
  and side lean rolls `8°` outward and yaws `3°`; forward adds `1.5°` roll. A side lean also
  travels `pose1_side_lean` (default `0.10 m`, experimental/unbounded) along the mattress toward her head,
  outside the view-axis clamp. The displayed lean is always smoothed at
  `CAMERA_INERTIA_SMOOTH = 5.0`.
- All lean distances/angles scale with pony size: `clamp(2.0 - size, 0.75, 1.5)`. JRHNBR (`1.0`)
  is the reference; Canon (`0.66`) is `1.34`. The pose-1 Canon camera height is also `0.9×`.
- The lean camera locks `player.controls_locked` for both poses and restores the previous value
  at act end.
- `Q` also starts the act kiss at `LEAN_FIRE = 0.75` and releases at `LEAN_RELEASE = 0.60`.
  The kiss aims her neck/head at Anon's mouth through the recipe `kiss` weight; `E` only leans.
  Pose 1 always uses that custom head aim: the stock kiss pose is authored for standing and its
  chest/neck give lifts the lying body and turns her head across the mattress. Pose 2 uses the
  base kiss, with the runtime writing its live mouth/eye/face targets from Anon's real mouth
  camera and repeating the mouth kiss sound because the player kisser's physics is paused for
  the act. The excitement Beat timer is paused so unicorn horns do not
  sparkle from the kiss. Anon leans in `KISS_LEAN_M = 0.27`, shifts to the shoulder side by
  `KISS_LEAN_SIDE_M = 0.18` and drops `KISS_LEAN_DROP_M = 0.035`; pose 2 applies it to the
  camera and pelvis counter-lean and yaws the camera `KISS_CAMERA_YAW_DEG = 10°` toward her,
  pose 1 to the framing view and virtual mouth. The kiss side is latched from the input lean at
  start (`_lean_side`, falling back to `_lean_action_side`, not the lagging camera view), and
  `AffectionPose.set_kiss_side()` pins her tilt to the complementary side in pose 2
  (`KISS_PONY_SIDE_SIGN = 1`) so their heads interlock instead of colliding; the deep-kiss side
  switch is disabled for the act. The lateral travel crossfades from the lean's `0.18 m` to the
  kiss's `0.18 m` rather than adding both, so the full kiss uses one offset.
- Camera thrust is speed-driven, not impulse-driven. `_process` filters the signed depth speed
  (`CAM_SPEED_SMOOTH_S = 0.06 s`); `_camera_thrust_tick()` follows it with one critically damped
  response (`CAM_RESPONSE_S = 0.12 s`). No per-stroke kick.
- `CAM_SPEED_REF = 4.0` depth/s reaches full travel; outward strokes use `CAM_BACK_RATIO = 0.5`.
- Two `camera_thrust` amounts (`surge`, `bob`, both `0…1`, defaults `1.0`/`0.35`) scale
  `CAM_SURGE_M = 0.06 m` and `CAM_BOB_M = 0.02 m`.
- The bob target is negative: an inward stroke dips the camera toward her, so the frozen aim
  moves up her body. The outward stroke rises back.
- Pose 1 sends the surge along the mattress toward her head; pose 2 sends it along the camera
  forward. Both use the same bob.
- Climax uses `CAM_CLIMAX_SURGE_M = 0.02` and `CAM_CLIMAX_BOB_M = 0.008`, scaled by the sliders.
- Restore order is load-bearing:
  1. player transform and yaw,
  2. pony transform and posture,
  3. camera transform + `make_current()`.
- Do not reorder: setting player yaw rotates a child camera.
- Pose-1 setup saves the source camera `fov`, `near`, `far` and `cull_mask`; freeing the
  mod-owned view restores those exact values and logs them before making the source current.
- After restore, re-invite the pony through the seat's couch; if that fails, restore
  the captured posture.

## Horse (Pose 2)

- Facing lock every physics tick at priority 100:
  `pony.global_transform.basis = _facing_basis.scaled(scale)`. `stay()` alone does not stop
  conversation facing, so `face_point`/conversation target are cleared late each tick and
  `face_turn_rate` is held at `0` for the act; locomotion and emotions keep running.
  Conversation attention is not a stop condition: another character addressing Anon can talk
  while `_keep_act_attention()` clears her listener each tick.
- Camera height through player `_stand_eye` / `_eye_height`; never teleport the rig.
- The camera aims at the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) once at pose
  start, then freezes. The same lean vector is applied on top: forward `0.24 m` /
  `-6°` pitch / `1.5°` roll; backward `0.08 m` with the same downward pitch; side `0.18 m` /
  `8°` outward roll / `3°` yaw. All scale with pony size. Canon lowers the pose-2 eye line by
  `0.20 m` and uses a `0.66×` thrust-jiggle scale.
- Anon's pelvis stays planted: `apply_anon_lean()` cancels the camera's forward/side lean
  translation on the hip target, so the torso hinges over her instead of the whole body sliding
  into her rump. Pull-back still moves the whole body away. Forward/kiss lean also captures and
  holds both foot targets at their neutral transforms, so his legs stay out of the camera.
  `ANON_THRUST_SWAY_M = 0.02` also moves the pelvis back on the inward stroke, so his upper body
  thrusts forward/back with depth.
- `presentation.torso_angle_deg` (default `0`, experimental/unbounded) hinges his upper body forward. The
  head/camera moves along the spine arc (`forward = 0.65 sin θ`, `drop = 0.65 (1 − cos θ)`);
  `apply_anon_lean()` counters the hip by the same forward amount and pins the feet.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- A released lean always holds its position. `_lean_step()` ramps toward a pressed target; the
  explicit `S` shoulder recentre returns to zero. Act-end and paused paths still return over
  `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default on), a slow `0.010` forward / `0.0084` side rock
  keeps the camera/upper body from freezing completely; both are clamped inside `-1…1`. A/D
  caress latches: a tap starts it and a second tap stops it. Pressing `S` arms a gradual side
  return so the shoulder roll decays to neutral.
- Pose 2 has no separate thrust rock spring; the shared speed-driven surge/bob handles it.
- The hip is depth-driven. `_hip_phase` is `depth` low-passed by `HIP_SMOOTH_S = 0.04 s`;
  `apply_anon_thrust()` moves the hip by `THRUST_MAX_M = 0.045 * body_scale * phase`, and
  `apply_anon_lean()` counter-moves the pelvis by `ANON_THRUST_SWAY_M * phase * lean_scale`.
  There is no attack or return spring.
- Pose-2 palms scale the `LeftHand`/`RightHand` bones: Canon `0.85`, JRHNBR `0.95`, others
  `1.0`. `palm_scale.gd` runs after BodyIK and restores the cached scales in
  `_remove_anon_thrust()` on every act exit.
- Holding `F` at `abs(side) >= POSE2_KISS_LEAN = 0.90` starts the same base-game kiss used by
  pose 1; releasing `F` or dropping the lean ends it. The side is latched from the input lean
  and passed to `AffectionPose.set_kiss_side()`, so she takes the complementary head tilt and
  the deep-kiss side switch is disabled for the act. During the `Affection` release the camera
  lean and glance suppression are held until the head has retracted, then ease out. A completed
  kiss has a `500 ms` restart cooldown.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`.
- Canon lowers the pose-2 eye line by `0.10 m` and multiplies lean travel by `0.8`; JRHNBR
  raises the pose-2 eye line by `MOUNTING_POSE2_CAMERA_LIFT_M = 0.10 m`.
- Glances use `pony.secondary.look_toward`; `head_back` is eased; pupils aim via
  `eye_motion.target_world` / `target_weight`. Look-back yaw clamps at
  `GLANCE_BACK_YAW = 1.62`; `glance_back_pitch` is multiplied by `1.2` (base `1.2`, boosted
  to `1.44`). The `head_back` ease uses `GLANCE_BACK_FADE / glance_back_speed`, with
  `glance_back_speed` defaulting to `2.0` and live in the settings tab. A full forward `W` lean
  with no side lean forces `head_back = 1.0` and an upward look at Anon.
- `Q`/`E` at `0.75` side lean reach Anon's same-side open palm to the shoulder through
  `desktop_anon.set_hold_target(..., "rub")`. Hand-marker axes are local `-Z` fingers, `+Y`
  thumb/up and palm normal `-X` right / `+X` left. The shoulder contact supplies the position and
  normal; `palm_surface_basis()` keeps the fingers forward and the palm flat on the coat. It
  eases in over `0.35 s` and back to rest over another `0.35 s`. While held, `_forced_glance`
  overrides the random glance scheduler and locks her look over that shoulder; release clears it.
- `A`/`D` in horse pose hold an oval caress (`CARESS_RADIUS_M = 0.04125`,
  `CARESS_SPEED_RAD_S = 3.6`). The palm is projected onto the coat each tick through
  `FlankSurface.contact` or `PonyTouchBody.nearest`, and `palm_surface_basis()` makes the palm
  plane perpendicular to the coat normal. Its centre sits at
  `PALM_ON_COAT_CLEARANCE_M = 0.04` at body scale `1.0`, scaled by the pony's actual
  `body_scale` (clamped `0.5…2.0`); normal smoothing adds no lift. Contact is cached per hand with source hysteresis and short position/normal
  smoothing, so a missed hit holds the last valid point instead of snapping; a near-opposite
  normal (dot < -0.5) is rejected under the same source. `FlankSurface` precomputes a two-ring,
  area-weighted average of the patch rest normals and skins those, removing triangle/seam
  jitter before the query. The final normal turns toward each new contact normal at
  `PALM_NORMAL_MAX_DEG_S = 120°/s`, and the palm basis is rebuilt from that final normal each
  frame so it cannot rotate into her. The rub centre is lifted
  `CARESS_UP_BIAS_M = 0.05` above the profile point; a 1 Hz log reports the rub/shoulder heights,
  source, misses, switches, normal step/out angle and hand distance. The path is
  `CARESS_OVAL_ACROSS = 1.30` along the body and `CARESS_OVAL_UP = 0.70` vertically. Point
  offsets come from `CARESS_PROFILES`: Canon `up 0.08`, JRHNBR `up 0.16 / out 0.02` (4 cm wider
  between hands), Same Height and Hoers step up from there; the contact query snaps those points
  to the coat. Both keys can run simultaneously; a tap latches that hand until the next tap.
  The centre moves from the flank (no lean) to the side/belly (half forward lean) to
  the exact Q/E shoulder contact point (full forward lean). Backward lean moves it toward the
  rump top immediately, reaching there at `CARESS_RUMP_LEAN = 0.5`. The circle radius scales with
  pony size; the point offsets are already per size.
- Anon's hip follows the lightly smoothed mouse `depth` (`HIP_SMOOTH_S = 0.04 s`):
  `THRUST_MAX_M = 0.045 m` forward at phase 1. Depth is the input, so the maximum travel is
  exactly the mouse travel.
- `body_sway.gd` translates `pony_spine1` with an inverted damped spring: back on inward depth,
  forward on outward depth. Upper-arm origins are preserved so the forehooves stay planted.
  `BODY_SWAY_MAX_M = 0.035`.
- Strong thrusts build a subtle rump blush decal up to `0.25` albedo mix (smack uses `0.8`).
- Mouse right calls `FlankTouch.impact(0, at)` for her left cheek or `impact(1, at)` for her
  right. `at` is the mark centre shifted `0.08 m` up and `0.08 m` back, jittered within
  `SMACK_ZONE_RADIUS_M = 0.035`. If a hand is already caressing, the slap uses that hand and its
  same-side cheek; if both caress, one is chosen at random. Otherwise a right lean selects the
  left cheek, a left lean the right, and centered picks randomly. The caress oval is frozen for
  the slapping hand during the swing and the hand returns to that caress point at the end. Anon's
  hand swings in/out over `0.20 s` (`SMACK_CONTACT_PHASE = 0.45`) with a `200 ms` cooldown. The
  native impact supplies sound, decal, blush, jiggle and `flank_smack`.
- `ear_twitch.gd` flicks both ear roots together on a thrust: a shared forward/back pitch and a
  sideways twitch that sends both ears outward or both toward the head. The per-ear sign comes
  from the root's lateral offset, with an eased envelope and cooldown.
- Base pose adds `chin_up_deg = 30` on the head and `neck_down_deg = 15` total on neck1/neck2.
- `foreleg_spread = 0.172 rad` is the absolute outward half-angle; the recipe measures the
  current hoof line and rotates the upper arms only by the difference.
- Tail aside/lift/flick on the hair skeleton; side randomized per act. `poses.<pose>.tail_lift`
  defaults to `0.42` and is per-mare/per-pose overridable. A damped spring driven by
  raw `depth` also rocks the tail with the thrust: sagittal `ROCK_PITCH = 0.12` and lateral
  `ROCK_YAW = 0.08`. Each thrust adds a short decaying wave (`JIGGLE_DECAY = 3.6`,
  `JIGGLE_FREQ = 18`, `JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`) at the same strength as the
  rump shader, strongest at the dock and lagging down the chain.
- Pose 2 wings start at `WING_POSE2_HOLD = 0.65` (about `60°` above the ground), then open by
  `WING_POSE2_SPREAD = 0.25` as satisfaction rises. Pose 1 keeps the stock spread progression.
  A mod-owned `wing_sweep.gd` runs last and yaws `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°`
  in opposite directions, sweeping the spread wings slightly backwards.
- Pose 2 enters a held `AFTERGLOW`: the tail lifts and flicks twice, and the inside event is
  recorded on entry. Lean and A/D caress remain live; hold Y ends it. For the first 8 s the
  HUD shows `Stay close · 8s · caress`; 2.5 s of active caress completes the close reward.
  Missionary afterglow stays passive.

## Aftercare

- No head lowering.
- Tail held raised straight (`aside_angle = 0`), with `flick_amplitude = 0.55` and a
  one-cycle flick every `1.4–2.4 s` on the hair skeleton.
- Navigator held for 10 s.

## Timing domains

- `runtime._process`: view-depth travel, lean, climax wave, breath, look point, pose climax flag.
- `runtime._physics_process`: presentation, timers, facing lock, glances,
  auto-cuddle suppression.
- `main._process`: calls `active_runtime.apply_camera_motion()` every rendered frame.
  Keep this single owner.
- Do not merge these timing domains blindly.
