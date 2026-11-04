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

## Missionary

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
   - adds `MISSIONARY_ROLL_TWEAK`.
   - rotates the root around `forward` at the hips pivot.
6. `_level_chest_roll()`
   - left/right upper-arm origins.
   - `_line_roll()`; rotates only `pony_spine1` around `forward`.
7. `_pitch_body_about_shoulders(MISSIONARY_RUMP_DROP_DEG)`
   - pivot: midpoint of the two upper-arm origins.
   - rotates root origin and basis about `right`.
   - positive angle moves the pelvis/rump behind the pivot downward.
8. `_bend_forelegs(0.3)`.
9. `_raise_hind_legs()`
   - femur target `(up * 0.75 + forward * 0.45).normalized()`
   - knee bend `-0.55` around `right`.
10. `_hug_forelegs()`.
11. `_neck_bend(neck1_deg, neck2_deg)` about the body right axis on `pony_neck1`/`pony_neck2`.
    The presentation defaults are `7.5°` each (the old 15° split); zero straightens the neck.
    `_neck_roll(neck_roll_deg)` rolls both neck bones about the body forward axis. Both are
    posture offsets and run before the gaze solve, so they move her head off the mattress
    without tilting her final gaze.
12. Nuzzle
    - `_nuzzle_pulse()`: 0→1→0 over `NUZZLE_DURATION` every `NUZZLE_PERIOD`.
    - offsets the gaze target by the small angle `nuzzle_scale * 8°`; base gaze remains on Anon.
    - during climax: `pulse = 0.75 + 0.25 * sin(_clock * 4.0)`.
13. `_aim_gaze(look_point)` — the true gaze solve.
    - uses the current `pony_head` frame plus `HybridNeckLink`'s fixed `pony_head → mHead`
      offset, so it reads the face direction after the pose and neck lift.
    - shortest-arc rotation from her current face direction to Anon; no absolute yaw/pitch and
      no rest-orientation assumption. This is what keeps the lying missionary head off the
      ceiling.
    - neck shares `[0.30, 0.36, 0.34]`; `rig.rotate()` applies the native joint limits.
    - the kiss target is already the runtime's `look_point`, so the old extra kiss aim is gone.
    - after the solve, `_head_pitch(head_pitch_deg)` rotates the head about the body right axis.
      This intentionally trades a little exact aim for a natural head angle.
14. `_roll_head(head_roll)` around `forward`, head only.
15. Dump once at weight > 0.9 if debug is on.

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

## Missionary camera

- Anchor: `root + up * (0.45 + MISSIONARY_CAMERA_LIFT_M 0.10) * body_scale + back * 0.22 * body_scale`,
  where `back = +pony.global_basis.z`. The anchor stays behind her neck, toward her rump, so the
  frozen aim looks forward along her body at her face; anchoring ahead of the neck aimed the shot
  back down her torso. Canon height is `0.9×`; JRHNBR (`1.35`) gets a proportionally higher,
  farther-back anchor. The **Act presentation → Missionary** axes move the frozen anchor:
  `presentation.missionary.forward` (default `0.26`),
  `presentation.missionary.height` (default `-0.21`) and `presentation.missionary.side`
  (default `0`; positive is her right). `presentation.missionary.pitch_deg` (default `0`;
  positive looks up) tilts the view about its local right axis after the frozen neck aim; the
  anchor and neck settle target do not move. All are experimental and unbounded. The
  **Missionary pullback** setting (`presentation.missionary.pullback`, default `0.22 m`, times
  body scale) then
  pulls the shot back along `_missionary_view_basis.z` (its own view axis), and
  `MISSIONARY_START_LEAN = 1.0` (one full
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
  head. The look point moves with the lean's lateral shift and
  `presentation.missionary.side_lean` travel, so a side lean turns her toward the lean. Aiming
  at the framing view (now behind her neck) demanded
  a half-turn and snapped her head side to side.
- Missionary hides every `*AnonBody*` presentation node and disables the desktop presentation for
  the act, re-applying each tick; both are restored at end. The stock bed body must never appear
  inside the shot with a different orientation.
- Missionary body motion is `prone_sway` (`missionary_body_motion`): the spine slides along the bed with
  raw thrust depth, and the neck/head nod about `3°`. It is separate from the standing
  `body_sway` (`standing_body_sway`) and does not pin hooves like the standing pose.
- Eyes: `ACT_LIDS = 0.45` in `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` in `CLIMAX`, sleepier
  `0.90`/`0.95` in afterglow. `_eyes_tick()` reasserts the stare late each tick.
- Lean is clamped to stop `0.12 m` short of the neck target in both directions, so the camera
  can never cross its own look point and flip backwards.
- The camera has no mouse look. `W`/`S` lean forward/back and `Q`/`E` lean sideways:
  `side = E - Q`, `forward = W - S + abs(side)`.
- Lean ramps over `0.5 s` and returns over `1.6 s`. Forward lean translates `0.24 m`; backward
  lean is halved to `0.08 m`; side lean translates `0.18 m`. Both directions pitch `6°` down,
  and side lean rolls `8°` outward and yaws `3°`; forward adds `1.5°` roll. A side lean also
  travels `presentation.missionary.side_lean` (default `0.20 m`, experimental/unbounded) along
  the mattress toward her head, outside the view-axis clamp. The displayed lean is always
  smoothed at
  `CAMERA_INERTIA_SMOOTH = 5.0`.
- All lean distances/angles scale with pony size: `clamp(2.0 - size, 0.75, 1.5)`. JRHNBR (`1.0`)
  is the reference; Canon (`0.66`) is `1.34`. The missionary Canon camera height is also `0.9×`.
- The lean camera locks `player.controls_locked` for both poses and restores the previous value
  at act end.
- `Q` also starts the act kiss at `LEAN_FIRE = 0.75` and releases at `LEAN_RELEASE = 0.60`.
  The kiss aims her neck/head at Anon's mouth through the recipe `kiss` weight; `E` only leans.
  Missionary always uses that custom head aim: the stock kiss pose is authored for standing and its
  chest/neck give lifts the lying body and turns her head across the mattress. Standing uses the
  base kiss, with the runtime writing its live mouth/eye/face targets from Anon's real mouth
  camera and repeating the mouth kiss sound because the player kisser's physics is paused for
  the act. The excitement Beat timer is paused so unicorn horns do not
  sparkle from the kiss. Anon leans in `KISS_LEAN_M = 0.27`, shifts to the shoulder side by
  `KISS_LEAN_SIDE_M = 0.18` and drops `KISS_LEAN_DROP_M = 0.035`; standing applies it to the
  camera and pelvis counter-lean and yaws the camera `KISS_CAMERA_YAW_DEG = 10°` toward her,
  missionary to the framing view and virtual mouth. The kiss side is latched from the input lean at
  start (`_lean_side`, falling back to `_lean_action_side`, not the lagging camera view), and
  `_pin_base_kiss_side()` pins her tilt to the complementary side in standing
  (`KISS_PONY_SIDE_SIGN = 1`) so their heads interlock instead of colliding; the deep-kiss side
  switch is disabled for the act. The pin writes AffectionPose's private
  `_side`/`_side_now`/`_side_wait` each tick and skips quietly if they are unavailable. The lateral travel crossfades from the lean's `0.18 m` to the
  kiss's `0.18 m` rather than adding both, so the full kiss uses one offset.
- Camera thrust is speed-driven, not impulse-driven. `_process` filters the signed depth speed
  (`CAM_SPEED_SMOOTH_S = 0.06 s`); `_camera_thrust_tick()` follows it with one critically damped
  response (`CAM_RESPONSE_S = 0.12 s`). No per-stroke kick.
- `CAM_SPEED_REF = 4.0` depth/s reaches full travel; outward strokes use `CAM_BACK_RATIO = 0.5`.
- Two `camera_thrust` amounts (`surge`, `bob`, both `0…1`, defaults `1.0`/`0.35`) scale
  `CAM_SURGE_M = 0.06 m` and `CAM_BOB_M = 0.02 m`.
- The bob target is negative: an inward stroke dips the camera toward her, so the frozen aim
  moves up her body. The outward stroke rises back.
- Missionary sends the surge along the mattress toward her head; standing sends it along the camera
  forward. Both use the same bob.
- Climax uses `CAM_CLIMAX_SURGE_M = 0.02` and `CAM_CLIMAX_BOB_M = 0.008`, scaled by the sliders.
- Restore order is load-bearing:
  1. player transform and yaw,
  2. pony transform and posture,
  3. camera transform + `make_current()`.
- Do not reorder: setting player yaw rotates a child camera.
- Missionary setup saves the source camera `fov`, `near`, `far` and `cull_mask`; freeing the
  mod-owned view restores those exact values and logs them before making the source current.
- After restore, re-invite the pony through the seat's couch; if that fails, restore
  the captured posture.

## Standing

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
  `8°` outward roll / `3°` yaw. All scale with pony size. Canon lowers the standing eye line by
  `0.10 m` and uses a `0.66×` thrust-jiggle scale.
- Anon's lower body stays planted: `apply_anon_lean()` freezes the hip target and both foot
  targets at their first act frame pose. The camera/head moves forward, sideways or down, so the
  torso hinges over her instead of the whole body sliding into her rump. Pull-back translates
  the hips and feet together, so the whole lower body moves away with the same leg pose.
- `presentation.standing.torso_angle_deg` (default `6`, experimental/unbounded) hinges his upper
  body forward. The head/camera moves along the spine arc (`forward = 0.65 sin θ`,
  `drop = 0.65 (1 − cos θ)`); `apply_anon_lean()` keeps the lower body planted.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- A released lean always holds its position. `_lean_step()` ramps toward a pressed target; the
  explicit `S` shoulder recentre returns to zero. Act-end and paused paths still return over
  `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default on), a slow `0.010` forward /
  `presentation.standing.idle_sway_side` (default `0.0`) side rock keeps the camera/upper
  body from freezing completely; both are clamped inside `-1…1`. A/D
  caress latches: a tap starts it and a second tap stops it. Pressing `S` arms a gradual side
  return so the shoulder roll decays to neutral.
- Standing has no separate thrust rock spring; the shared speed-driven surge/bob handles it.
- The hip is depth-driven. `_hip_phase` is `depth` low-passed by `HIP_SMOOTH_S = 0.04 s`.
  The fixed rump point is the base HipsTarget plus `THRUST_MAX_M = 0.045 × body_scale` toward
  her; `anon_hip_thrust.gd` moves only the Hips bone by
  `THRUST_MAX_M × (1 - thrust.travel × (1 - phase))`, so depth 0 is the full backset and depth 1
  reaches the rump point. `thrust.travel` defaults to `2.0`. The modifier restores the Spine
  and both UpperLegs to their pre-offset global poses, so the torso, head and legs do not
  follow. There is no attack or return spring.
- With `standing_plant_feet` on (default), the standing controller captures both foot targets on
  the first act frame, moves them `PLANT_FEET_BACK_M = 0.15 m` behind him so they are not
  between her hind legs, and captures the hip target. Every frame after the body places them it
  rewrites all three to that capture. The upper body, camera lean, hands, kiss and hip thrust
  still move; the lower body does not. Off restores the game's stepping and lean foot motion;
  the capture clears at act end.
- Standing palms scale absolutely per body preset from
  `presentation.standing.caress.palm_scale`: Canon `0.75`, JRHNBR `0.9`, same height/hoers `1.0`.
  The settings size selector edits each preset. `palm_scale.gd` runs after BodyIK and restores
  the cached scales in `_remove_anon_thrust()` on every act exit.
- Holding `F` at `abs(side) >= STANDING_KISS_LEAN = 0.90` starts the same base-game kiss used by
  missionary; releasing `F` or dropping the lean ends it. The side is latched from the input lean
  and `_pin_base_kiss_side()` keeps her on the complementary head tilt; the deep-kiss side
  switch is disabled for the act. During the `Affection` release the camera
  lean and glance suppression are held until the head has retracted, then ease out. A completed
  kiss has a `500 ms` restart cooldown.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`. The game's
  Same Height preset now follows Anon's `player/height_cm`, so that gap, the lean scale and the
  same-height caress offsets are multiplied by `Settings.anon_height_scale()`; the other presets
  keep their authored values.
- Standing kiss mouth offsets, kiss lean distances and the missionary virtual mouth scale with
  `Settings.anon_height_scale()`, matching `player/player_mouth.gd`.
- Canon lowers the standing eye line by `0.10 m` and multiplies lean travel by `0.8`; JRHNBR
  raises the standing eye line by `MOUNTING_STANDING_CAMERA_LIFT_M = 0.10 m`.
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
- `A`/`D` in standing pose hold an oval caress (`CARESS_RADIUS_M = 0.04125`,
  `CARESS_SPEED_RAD_S = 3.6`). `Z`/`C` toggle the left/right oval movement; the palm stays on
  the coat and keeps scoring while the phase is frozen. The palm is projected onto the coat
  each tick through
  `FlankSurface.contact` or an exclusion-aware `PonyTouchBody.nearest` fallback, and
  `palm_surface_basis()` makes the palm plane perpendicular to the coat normal. The fallback
  skips `presentation.standing.caress.ignore` regions (default `tail`; UI also exposes mane, wings
  and legs), so a tail flick cannot steal the contact. Its centre sits at
  `presentation.standing.caress.palm_distance` (default `0.04 m`) at body scale `1.0`, scaled by
  the pony's actual `body_scale` (clamped `0.5…2.0`); normal smoothing adds no lift. Contact is
  cached per hand with source hysteresis and short position/normal
  smoothing, so a missed hit holds the last valid point instead of snapping; a near-opposite
  normal (dot < -0.5) is rejected under the same source. The final normal turns from the stock
  FlankSurface normal toward each new contact normal at
  `PALM_NORMAL_MAX_DEG_S = 120°/s`, and the palm basis is rebuilt from that final normal each
  frame so it cannot rotate into her. A stale normal is corrected toward the resolved contact
  normal, not the input hint, so a hull fallback at the shoulder cannot leave the palm edge-on.
  The rub centre is lifted
  `CARESS_UP_BIAS_M = 0.05` above the profile point; a 1 Hz log reports the rub/shoulder heights,
  source, misses, switches, normal step/out angle and hand distance. The path is
  `presentation.standing.caress.oval_across_m` (default `5.36 cm`) along the body and
  `oval_up_m` (default `2.89 cm`) vertically, both times the pony size scale. Point
  offsets come from `CARESS_PROFILES`: Canon `up 0.08`, JRHNBR `up 0.16 / out 0.02` (4 cm wider
  between hands), Same Height and Hoers step up from there; the contact query snaps those points
  to the coat. Both keys can run simultaneously; a tap latches that hand until the next tap.
  The centre moves from the flank (no lean) to the side/belly (half forward lean) to
  the exact Q/E shoulder contact point (full forward lean). Backward lean moves it toward the
  rump top immediately, reaching there at `CARESS_RUMP_LEAN = 0.5`. The circle radius scales with
  pony size; the point offsets are already per size.
- Anon's hip follows the lightly smoothed mouse `depth` (`HIP_SMOOTH_S = 0.04 s`):
  the fixed rump point is the base HipsTarget plus `THRUST_MAX_M = 0.045 m × body_scale`, and
  only the Hips bone moves by `THRUST_MAX_M × (1 - thrust.travel × (1 - phase))`, so phase 0 is
  the backset and phase 1 reaches the rump point. The Spine and both UpperLegs are restored, so
  the torso and legs stay planted.
- `body_sway.gd` translates `pony_spine1` with an inverted damped spring: back on inward depth,
  forward on outward depth. Upper-arm origins are preserved so the forehooves stay planted.
  `BODY_SWAY_MAX_M = 0.035`.
- Strong thrusts build a subtle rump blush decal up to `0.375` albedo mix (smack uses `0.8`).
- Mouse right calls `FlankTouch.impact(0, at)` for her left cheek or `impact(1, at)` for her
  right. Standing targets the flank patch: the live caress point when that hand's contact
  source is `flank`; a free-hand smack uses the chosen cheek, querying the mark centre offset by
  `smack.height_m` (default `-0.03 m`, signed: positive is up) × body scale and
  `smack.hind_m` (default `0.10 m`) toward her rump, then snapping to the nearest
  `FlankSurface` point. Both are jittered tangentially within `smack_zone_radius` (`0.035 m` by
  default). That keeps a resting hand from reaching the leg and puts the contact on the hind of
  the flank. A forward lean lands on the forward flank instead of reaching back to the cheek. The body hull is never the target and the rump
  centre is not used; `index` only chooses which cheek decal reddens. Missionary keeps the
  mark-centre target shifted `0.08 m` up and `0.08 m` back. If a hand is already caressing, the
  slap uses that hand; if both caress, one is chosen at random. Otherwise a right lean selects
  the left index, a left lean the right, and centered picks randomly. The caress oval keeps
  moving through the smack, so the hand returns to the live point.
- Standing smacks play four phases. The contact palm uses the caress forward finger hint
  (`-pony.global_basis.z`) when caressing, and `Vector3.DOWN` for a free-hand smack. A caress
  RAISE lifts from the current hand frame to the contact plus `presentation.standing.smack.raise_m`
  (default `0.30 m`, body-scaled) along the coat normal and `SMACK_RAISE_BACK_M = 0.05 m` toward
  her rump at `smack.raise_speed` (default `2.0 m/s`, clamped to `0.12–0.30 s`). The lift path
  bows toward her rump by `smack.arc_m` (default `0.06 m`, body-scaled) at mid-raise. A free-hand RAISE
  is a backswing from behind and below: `back × raise_m`, `down × (raise_m ×
  SMACK_SWING_DOWN_RATIO = 0.55)` and a small `outward × (raise_m × SMACK_SWING_OUT_RATIO =
  0.15)` clearance. Both raised bases are the straight contact basis pitched down by
  `smack.pitch_deg` (default `12°`) about the palm normal, so the wind-up is a pitch, not a roll
  around the arm. STRIKE travels straight to the contact with cubic acceleration at
  `smack.return_speed` (default `6.0 m/s`, clamped to `0.06–0.20 s`), pitching back to the
  straight contact basis. CONTACT holds the exact contact frame for
  `SMACK_CONTACT_HOLD_SECONDS = 0.03 s` and fires the native impact. RECOVER blends to the live
  caress oval over `CARESS_RETURN_SECONDS = 0.12 s` or to the captured rest hand over
  `SMACK_REST_RETURN_SECONDS = 0.20 s`, then clears the hold. Missionary keeps the hidden-hand
  `SMACK_SWING_SECONDS = 0.20` swing at `SMACK_CONTACT_PHASE = 0.45`. A `SMACK_COOLDOWN_MS = 200`
  gate remains, and a new smack waits for the current recovery. With `act_foley` on the native
  sound player gets a peak-normalised OpenNSFW hand-smack variant for that impact; off keeps the
  stock `flank_slap.wav`. The native impact still supplies the decal, blush, jiggle and
  `flank_smack`.
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
  rump shader, strongest at the dock and lagging down the chain. A smack adds the same wave
  through `_on_smack_impact()` at `1.0 × _jiggle_size_scale() × smack_intensity`, gated by
  `thrust_tail_dock_jiggle`; the thrust wave scales with `jiggle.intensity`. The same flag also
  includes the dock in the smack wobble and restores the near-mesh `jiggle_entry` masks at act
  end. The `jiggle.radius` setting (default
  `0.26 m`) is applied to every active wobble material and restored at act end; `jiggle.intensity`
  (default `0.25×`) scales the thrust amount, and `jiggle.smack_intensity` (default `0.55×`)
  scales the act smack amount. Stock marks are hidden and aged at act start, so a
  mark from an earlier regular smack cannot linger as a stale jiggle point. The game's tail
  anchor pins the first 12–67 mm of the `DevkitTail` root cap to the hair `mPelvis`, so the
  `mTail1..6` wave alone cannot move the base. `tail_pose` moves `mPelvis` itself: it applies
  `tail_base_share` (default `0.6`, per-pose overridable) of the aside/lift there, reduces the
  root bone's own share to keep the total sweep, translates it by `JIGGLE_BASE_M = 0.02 m` on
  the dock wave, and restores the mane bones, so the pinned tail base moves with the chain.
- `dock_tail_follow.gd` (default on) carries the dock with the hair `mPelvis` during the
  standing act. It measures the pelvis in the body `pony_hips` frame, baselines that at the act
  start and applies the change to `OpenPonyDock`, so the dock follows the base share of the
  aside/lift and the thrust base bob while the chain keeps its curl. The rump shader jiggle
  still applies. The acting pony's merged near mesh draws its own dock copy, so it is swapped
  for the rig (`set_near_mesh(false)`) while this runs and restored at act end. The standing
  invitation attaches the same follower to its presentation tail. The restore ends the
  base-game rump wobble and clears its cached `jiggle_twin` metadata first, since the near-mesh
  material comparison includes metadata and would otherwise reject the body group.
- Standing wings start at `WING_STANDING_HOLD = 0.65` (about `60°` above the ground), then open by
  `WING_STANDING_SPREAD = 0.25` as satisfaction rises. Missionary keeps the stock spread progression.
  A mod-owned `wing_sweep.gd` runs last and yaws `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°`
  in opposite directions, sweeping the spread wings slightly backwards. Entering afterglow
  releases the hold and drives the same `WingTuck` blend to a full fold over
  `WING_AFTERGLOW_RETURN_SECONDS = 6.0`; early afterglow exit lets the node finish immediately.
- Standing enters a held `AFTERGLOW`: the tail lifts and flicks twice, and the inside event is
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
