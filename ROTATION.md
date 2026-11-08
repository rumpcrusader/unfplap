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

The pose is the **hand-authored asset** in `poses/missionary_pose.json`, placed in the real bed's
space, with the nuzzle and gaze overlays on top. There is no second implementation.

### Base pose

- **Asset.** `poses/authored_pose.gd` reads version 5 of the JSON once per process and caches it.
  Every transform is in **bed space**: origin at the middle of the mattress top, the bed's own
  axes, `+Z` the direction her head points. The runtime maps it onto the real bed with
  `bed_frame = Transform3D(bed basis * Basis(UP, PI), Vector3(bed x, drawn mattress top, bed z))`,
  so the pillow end (the shared bed frame's `-Z`) is where her head points.
- **The act owns the render.** The game re-poses the rig after our modifier pass (the clip tier's
  `enter`/`leave`, the posture and the terrain solver), so the modifier's write is not what the
  renderer sees. The runtime therefore applies the same recipe once more from `_process`, after every
  physics and process writer of the frame: `skeleton_pose.apply_render()`, same weight, no extra ramp
  and no clock advance. The physics-pass write stays because the game's own contacts and pose layers
  read the skeleton during the tick.
- **What is written.** The 24 body bones in `PONY_BONES` (`tools/pose_lab.gd`) — hips, spine1–3,
  neck1–2, flanks, femurs, tibias, legLowers, tarsals, hooves, shoulders, upper/lower arms, wrists,
  hands and fingers — plus the skeleton **root** (the armature bone) for placement. The actor node
  is never moved or rotated, so the capsule, bed support and posture recovery are untouched. The
  head bone, lids, eyes, ears, wings, feathers, mane and tail are never baked: the game and the act
  own them.
- **Placement** is `bed_frame * (pony_frame with its origin × body_scale)`. Scaling only the
  distance keeps a larger pony's body on the mattress instead of in it. The pose is authored at
  canon size; other sizes are not tuned yet.
- **Weight** comes from the pose modifier's `amount` ramp: each bone slerps from whatever the game's
  `lie_down` settle left to the authored rotation, and the root blends with `interpolate_with`, so
  POSING_IN still eases her in.
- **The head bone is reset to rest** on this path. The runtime owns the face: the gaze solve then
  aims `pony_head`'s frame (plus `HybridNeckLink`'s offset) at Anon, and the pitch/roll offsets run
  last. Baked head rotations were rejected because the pose lab has no head mesh.
- **Overlays skip the joint-limit clamp** (`rig.rotate_free`). The authored pose can sit outside
  the limits the game derives from its own motion library, and `constrain()` would snap it back on
  the first gaze correction.
- The shot's camera positions are bed-relative, so the body and the eye move together on any bed.
- **No fallback.** There is no second missionary pose. A missing/invalid asset, a version below 4
  or no bed frame (the floating pose preview) means no pose is applied, and the act's `pose_asset`
  gate refuses the start with `missionary pose unavailable: <reason>` in the log. The anatomy's
  `pelvis_curl_deg`/`legs_wrap`/`bed_lift_m` keys are gone with the stack.
- **Reload.** The asset is shared for the process; the **Reload posed base** debug action (and
  `F4`) re-reads the file in place, so the lab export → game reload loop works mid-act.

## Missionary camera

### The shot

The shot is a **blend of authored camera positions along her body**:

- Five camera positions come from the pose lab, bed-relative, in the asset's `shots` block:
  `start` (neutral), `back` (S, her pelvis), `front` (W, her face — where the kiss happens), and
  `left`/`right` (Q/E). Each is an **offset from `start`** scaled by that lean component, so
  diagonals blend additively. Until a position is authored it is derived from her live body:
  start `neck + up 0.35 + rump 0.75`; back `vulva + up 0.35 + rump 0.30`; front
  `face + rump 0.40 + up 0.15`; left/right the start shifted ±0.35 sideways (all × `body_scale`).
- The aim is `missionary_face_point()` (the head bone pushed 12 cm along neck2 → head); it slides to
  `missionary_vulva_point()` (the anatomy's `hole_point` when the part shows, otherwise the
  hind-femur midpoint lifted 10 cm) as `-lean_forward` grows. Sides and front keep the face.
- A kiss leans the eye in toward the aim by `kiss.lean_distance()`, but never closer than 0.30 m.
- The live offsets are **`shot_forward` / `shot_height` / `shot_side`** (default 0, applied every
  frame). There is no pullback or pitch knob: the authored positions are the shot.
- The lean basis (pitch, side yaw, roll), the speed-driven surge along the mattress toward her
  head, the side-lean travel, `_bob` and the kiss lateral offset/drop are the only extra motion.
  The view is kept at least 0.10 m over the bed surface. There is no frozen anchor and no framing
  nudge, so nothing can accumulate.

## Standing

- Facing lock every physics tick at priority 100:
  `pony.global_transform.basis = _facing_basis.scaled(scale)`. `stay()` alone does not stop
  conversation facing, so `face_point`/conversation target are cleared late each tick and
  `face_turn_rate` is held at `0` for the act; locomotion and emotions keep running.
  Conversation attention is not a stop condition: another character addressing Anon can talk
  while `_keep_act_attention()` clears her listener each tick.
- Camera height through player `_stand_eye` / `_eye_height`; do not set the eye line by
  teleporting the rig. Act start keeps her where she stands: for desktop human Anon,
  `_begin_standing_placement()` builds the act transform from her current facing and places him
  at `pony_position - forward * _standing_gap()`. The 1.2 m Y cone keeps that correction small.
  The act end leaves him there and leaves his yaw/pitch at the last act aim; it does not snap the
  pre-act view back. AnonPony and headset/VR still move her in front of the camera rig with
  `_standing_transform()`.
- The camera aims at the middle of her neck (`pony_neck1`/`pony_neck2` midpoint) once at pose
  start, then freezes. The same lean vector is applied on top: forward `0.24 m` /
  `-6°` pitch / `1.5°` roll; backward `presentation.lean_back_m` (default `0.08 m`) with the
  same downward pitch; side `0.18 m` /
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
- With `features.anatomy_oral` on and oral active, `oral_pitch`, `oral_yaw` and `oral_roll` swing
  the two neck bones and counter-rotate the head so her muzzle stays along the shaft. The keys are
  absent otherwise. `standing_camera.set_facing_override()` owns her turn while oral is active and
  clears when it ends; the normal facing lock resumes.
- A released lean always holds its position. `_lean_step()` ramps toward a pressed target; the
  explicit `S` shoulder recentre returns to zero. Act-end and paused paths still return over
  `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled (default on), a slow `0.010` forward rock keeps the
  camera/upper body from freezing completely; it is clamped inside `-1…1`. There is no side sway. A/D
  caress latches: a tap starts it and a second tap stops it. Pressing `S` arms a gradual side
  return so the shoulder roll decays to neutral.
- Standing has no separate thrust rock spring; the shared speed-driven surge/bob handles it.
- The hip is depth-driven. `_hip_phase` is `depth` low-passed by `HIP_SMOOTH_S = 0.04 s`.
  The fixed rump point is the base HipsTarget plus `THRUST_MAX_M = 0.045 × body_scale` toward
  her; `anon_hip_thrust.gd` moves only the Hips bone by
  `THRUST_MAX_M × (1 - thrust.travel × (1 - phase))`, so depth 0 is the full backset and depth 1
  reaches the rump point. `thrust.travel` defaults to `0.5`. The modifier restores the Spine
  and both UpperLegs to their pre-offset global poses, so the torso, head and legs do not
  follow. There is no attack or return spring.
- With `standing_plant_feet` on (off by default), the standing controller captures both foot targets on
  the first act frame, moves them `PLANT_FEET_BACK_M = 0.15 m` behind him so they are not
  between her hind legs, and captures the hip target. Every frame after the body places them it
  rewrites all three to that capture. The upper body, camera lean, hands, kiss and hip thrust
  still move; the lower body does not. Off restores the game's stepping and lean foot motion;
  the capture clears at act end.
- Standing palms scale absolutely per body preset from
  `presentation.standing.caress.palm_scale`: Canon `0.75`, JRHNBR `0.9`, same height/hoers `1.0`.
  The Caress section edits one row per preset. `palm_scale.gd` runs after BodyIK and restores
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
  keep their authored values. For desktop human Anon the gap is measured from her root along her
  backward axis after he is placed behind her.
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
  `presentation.standing.caress.palm_distance` (default `0.02 m`) at body scale `1.0`, scaled by
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
  `presentation.standing.caress.oval_across_m` (default `1.0 cm`) along the body and
  `oval_up_m` (default `2.0 cm`) vertically, both times the pony size scale. Point
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
- `body_sway.gd` translates `pony_hips` with an inverted damped spring: back on inward depth,
  forward on outward depth. All four limb-root origins are preserved so the hooves stay planted.
  The same world offset is added to Anon's pinned hip so the contact rocks together.
  `BODY_SWAY_MAX_M = 0.035`.
- Strong thrusts build a subtle rump blush decal up to `0.375` albedo mix (smack uses `0.8`).
- Mouse right calls `FlankTouch.impact(0, at)` for her left cheek or `impact(1, at)` for her
  right. Standing targets the flank patch: the live caress point when that hand's contact
  source is `flank`; a free-hand smack uses the chosen cheek, querying the mark centre offset by
  `smack.height_m` (default `0.05 m`, signed: positive is up) × body scale and
  `smack.hind_m` (default `0.09 m`) toward her rump, then snapping to the nearest
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
  her rump at `smack.raise_speed` (default `1.5 m/s`, clamped to `0.12–0.30 s`). The lift path
  bows toward her rump by `smack.arc_m` (default `0.10 m`, body-scaled) at mid-raise. A free-hand RAISE
  is a backswing from behind and below: `back × raise_m`, `down × (raise_m ×
  SMACK_SWING_DOWN_RATIO = 0.55)` and a small `outward × (raise_m × SMACK_SWING_OUT_RATIO =
  0.15)` clearance. Both raised bases are the straight contact basis pitched down by
  `smack.pitch_deg` (default `0°`) about the palm normal, so the wind-up is a pitch, not a roll
  around the arm. STRIKE travels straight to the contact with cubic acceleration at
  `smack.return_speed` (default `3.0 m/s`, clamped to `0.06–0.20 s`), pitching back to the
  straight contact basis. CONTACT holds the exact contact frame for
  `SMACK_CONTACT_HOLD_SECONDS = 0.03 s` and fires the native impact. RECOVER blends to the live
  caress oval over `CARESS_RETURN_SECONDS = 0.12 s` or to the captured rest hand over
  `SMACK_REST_RETURN_SECONDS = 0.20 s`, then clears the hold. Missionary keeps the hidden-hand
  `SMACK_SWING_SECONDS = 0.20` swing at `SMACK_CONTACT_PHASE = 0.45`. A `SMACK_COOLDOWN_MS = 200`
  gate remains, and a new smack waits for the current recovery. The native sound player gets a
  peak-normalised OpenNSFW hand-smack variant for that impact. The native impact still supplies
  the decal, blush, jiggle and `flank_smack`.
- `ear_twitch.gd` flicks both ear roots together on a thrust: a shared forward/back pitch and a
  sideways twitch that sends both ears outward or both toward the head. The per-ear sign comes
  from the root's lateral offset, with an eased envelope and cooldown.
- Base pose adds `chin_up_deg = 30` on the head and `neck_down_deg = 15` total on neck1/neck2.
- `foreleg_spread = 0.172 rad` is the absolute outward half-angle; the recipe measures the
  current hoof line and rotates the upper arms only by the difference.
- Tail aside/lift/flick on the hair skeleton; side randomized per act.
  `presentation.standing.tail.yaw_deg` (aside, default `32°`) and `pitch_deg` (lift, default
  `24°`) are the live amounts, in degrees. A damped spring driven by
  raw `depth` also rocks the tail with the thrust: sagittal `ROCK_PITCH = 0.12` and lateral
  `ROCK_YAW = 0.08`. Each thrust adds a short decaying wave (`JIGGLE_DECAY = 3.6`,
  `JIGGLE_FREQ = 18`, `JIGGLE_PITCH = 0.16`, `JIGGLE_YAW = 0.08`) at the same strength as the
  rump shader, strongest at the tail root and lagging down the chain. A smack adds the same wave
  through `_on_smack_impact()` at `1.0 × _jiggle_size_scale() × smack_intensity`; the thrust
  wave scales with `jiggle.intensity`. The `jiggle.radius` setting (default
  `0.26 m`) is applied to every active wobble material and restored at act end; `jiggle.intensity`
  (default `0.25×`) scales the thrust amount, and `jiggle.smack_intensity` (default `0.45×`)
  scales the act smack amount. Stock marks are hidden and aged at act start, so a
  mark from an earlier regular smack cannot linger as a stale jiggle point. The game's tail
  anchor pins the first 12–67 mm of the `DevkitTail` root cap to the hair `mPelvis`, so the
  `mTail1..6` wave alone cannot move the base; `tail_pose` also translates the hair `mPelvis` by
  `JIGGLE_BASE_M = 0.02 m` using the rump shader's thrust wave and restores the mane bones, so
  only the tail base and chain move.
- Standing wings start at `WING_STANDING_HOLD = 0.65` (about `60°` above the ground), then open by
  `WING_STANDING_SPREAD = 0.25` as satisfaction rises. Missionary keeps the stock spread progression.
  A mod-owned `wing_sweep.gd` runs last and yaws `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°`
  in opposite directions, sweeping the spread wings slightly backwards. Entering afterglow
  releases the hold and drives the same `WingTuck` blend to a full fold over
  `WING_AFTERGLOW_RETURN_SECONDS = 6.0`; early afterglow exit lets the node finish immediately.
- Standing enters a held `AFTERGLOW`: the tail lifts and flicks twice. Lean and A/D caress remain
  live; hold Y ends it. For the first 8 s the
  HUD shows `Stay close · 8s · caress`; 2.5 s of active caress completes the close reward.
  Missionary afterglow stays passive.

### Play-bow stance

`features.standing_play_bow` is off by default. When on, `standing_recipe.gd` runs
`_apply_play_bow()` instead of the base `_bow`/`_bend_forelegs`/`_chin_neck` chain. It is one
normal recipe pass, so every write still goes through `rig.rotate()` and the native joint
limits clamp it.

1. Rotate `pony_hips` by `-PLAY_BOW_PITCH_DEG` (`8°`) about the body right axis and both
   `pony_femur_L/R` by the same amount back, so the rump pitches down at the front while the
   hind legs stay under her.
2. `_spine_bow(PLAY_BOW_BOW = 3.0)` — the same per-bone spine angles as the standard bow, at a
   stronger scale.
3. Per foreleg: `pony_shoulder_*` `+35°`, `pony_upperArm_*` `+35°`, `pony_lowerArm_*` `+55°`,
   `pony_wrist_*` `+10°`, `pony_hand_*` `+10°` about the body right axis. The shoulder and upper
   arm sit on their `+35°` limits; the result is the chest down and both front hooves forward
   under her chin rather than tucked under the chest.
4. `_spread_fore(0.14)` and `_spread_hind(0.10)`.
5. `pony_neck1` `-30°`, `pony_neck2` `-22°`, `pony_head` `+10°`, hanging the snout near the
   ground. The neck values sit on the native `±30°` limit.
6. `_raise_head()` still runs on `head_back`, so a forward lean or a look-back lifts her face.

The recipe reads every value from the pose config first (`play_bow_bow`,
`play_bow_shoulder_deg`, `play_bow_upper_deg`, `play_bow_lower_deg`, `play_bow_wrist_deg`,
`play_bow_hand_deg`, `play_bow_neck1_deg`, `play_bow_neck2_deg`, `play_bow_head_deg`,
`play_bow_pitch_deg`, `play_bow_foreleg_spread`, `play_bow_hind_spread`), so a character pose
override can tune it without a new flag. The runtime writes only `play_bow` itself from
`_feature("standing_play_bow")` in `_sync_standing_pose_config()`.

### Missionary kiss

`kiss_control.lean_kiss_tick()` runs for both poses. Missionary kisses when F is held and
`_lean_forward >= MISSIONARY_KISS_LEAN` (0.90) **and** W is held: `lean_targets` adds `|side|` to
the forward lean, so without the W test a pure side lean would pull the kiss. The kiss itself uses
the custom head-aim path (the stock pose is authored for a standing pony); `Q`/`E` no longer kiss,
and `lean_action_kind()` only fires the standing shoulder reach.

## Free look (debug)

`presentation.missionary.free_look` (default off) copies the **player camera** into the act view
every frame instead of the frozen/authored shot: mouse look works, and `runtime._input` stops
feeding mouse motion into thrust. The pose and act keep running. Standing has no separate view, so
the standing camera controller simply leaves the player camera alone. The setting is live through
`apply_live_settings`; the settings page pauses the world, so it takes effect when the panel closes.

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
