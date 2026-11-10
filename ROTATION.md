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

### Act state

Missionary is its own state, not the game's bed rest:

- **Anon stands** before the act owns the camera (`force_stand_up()`, then the start snapshot and the
  player lock), and the game's desktop presentation is parked. His own `AnonBody` is placed from the
  asset's `anon` transform in bed space and posed from the `anon` bones by `missionary_anon.gd`, at
  render time. His body IK and desktop pose driver are switched off for the act.
- **She stands.** The bed rest is released and she is asked to `stand`, so the solver and the clip
  tier hold a neutral pose instead of `lie_down`; the act poses her body from the asset.
- **The bed is only a frame**: `bed_frame` (mattress top and axes) plus the offer/eligibility path.
- **The end restores the scene** (`restore_scene()`: player, pony and camera snapshot) and stands
  her. Nothing rejoins the bed or a cuddle. The snapshot is re-read once the pose settles
  (`resnapshot()` at ACTIVE): taken at `prepare()` it catches Anon mid stand-up and restores the
  reclined eye height. `resnapshot()` refreshes only the game camera's transform, never the act's own
  view.

### Base pose

- **Asset.** `poses/authored_pose.gd` reads version 6 of the JSON once per process and caches it.
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
- **What is written.** The 30 body bones in `PONY_BONES` (`tools/pose_lab.gd`) — hips, spine1–3,
  neck1–2, flanks, femurs, tibias, legLowers, tarsals, hooves, shoulders, upper/lower arms, wrists,
  hands and fingers — plus the skeleton **root** (the armature bone) for placement. The actor node
  is never moved or rotated, so the capsule, bed support and posture recovery are untouched. The
  head bone, lids, eyes, ears, wings, feathers, mane and tail are never baked: the game and the act
  own them.
- **The file carries every one of those bones, including the ones left at rest.** The runtime writes
  only what the file holds and never resets the rig, so a bone missing from the file keeps the
  game's own pose and breaks the chain it hangs from. Version 5 skipped rest bones; version 6 stores
  them, and `MIN_VERSION` is 6. The lab reads bed-space transforms for every version from
  `BED_SPACE_VERSION` 4 on, so an older file is never applied as lab world.
- **Own the scale too.** `FillyProportions` and the part hiders *multiply* a bone's pose scale every
  modifier pass (`set_bone_pose_scale(..., get_bone_pose_scale(...) * factor)`) and rely on the
  animation resetting it to rest each frame. The act replaces the animation, so every bone it writes
  also gets its rest scale back: without that the factor compounds (0.92^N collapses, >1^N explodes)
  and the neck, head or whole body stretches to `inf`. Parts the game hides stay hidden through its
  own hiders, never by leaving a bone collapsed in the asset.
- **Never invert a scaled parent basis.** The stock hiders collapse a bone by scaling it to `0.001`,
  and `set_bone_global_pose()` inverts the parent's *full* basis for every write — a 1000× multiplier
  that compounds each frame until the pose is `inf` (the body pulled away, then flickering) and the
  anatomy part follows it. Every act write goes through `pose_rig.set_global()`, which builds the
  local pose from the parent's **orthonormalized** rotation and origin only, and rejects a
  non-finite target. The stock hiders stay on: they only hide parts, and `BodyIK` (the standing pose
  driver, not a hider) is the one modifier parked for the act.
- **Anon's own process is parked.** `missionary_anon.install()` stops `AnonBody._process`: it drives
  `LegHide` from the height of the act camera (the mattress-height eye reads as `seated`, so the game
  collapses his legs), rewrites the authored fingers every frame (`_update_fists`), and feeds
  `model_scale` from that camera. `LegHide.influence` is set to zero for the act (the modifier stays
  active), the desktop pose driver is nulled and the desktop presentation's own `advance()` is
  stopped, so only the act writes his bones. The skeleton and the rest of its modifiers keep
  updating.
- **The head mesh is never hidden.** `head_smd` is the head **and the hands**; hiding it is what
  removes the palms. The game's `HeadHide` collapses only the head bone, which hides the head
  vertices. `apply()` caches the authored eye right after the bone write and the lean, before
  `HeadHide` runs, so `eye_transform()` never reads the collapsed bone.
- **His palms are planted.** `_place_hands()` holds both wrists at the authored world height and
  lets only their X/Z follow the stroke and lean: the hands slide along the mattress instead of
  lifting. A two-bone arm solve reaches each wrist; the hand keeps its authored world orientation so
  the palm stays flat on the bed.
- Caress: see `docs/hands.md`.

- **The exit restores the avatar.** The act writes his world placement every frame; `remove()` puts
  back `avatar.transform`, its process state, `process_mode`, visibility, the pose driver, `BodyIK`,
  the `LegHide` influence and every bone's pre-act local transform (the authored pose deliberately
  stretched positions, which the game does not re-pose for every bone).
- **The part and the pony are reset too.** `anon_part.reset_state()` clears its aim, hip offsets,
  penetration seed, bend/squash, shader and placement at both encounter start and end.
  `_snapshot_pony_bones()` / `_restore_pony_bones()` put every body and hair bone back after the
  act's pose is freed, so the game animation resumes from a sane rig.
- **Space rule.** Every act-space rotation is applied to a bone's **global pose** with the axis
  converted once into skeleton space (`pose_rig.rotate_free`). Pre-multiplying a bone's *local*
  pose applies the axis in the parent's frame — his hips are rotated ~90° here, and doing that made
  the W/S lean yaw the view instead of nodding it.
- **Positions are authored too.** A body bone stores a position next to its rotation, and it is
  applied: a lengthened neck or a displaced flank root is a deliberate part of the pose. Only the
  skeleton root carries the absolute placement; every other position is relative to its parent.
- **Placement** is `bed_frame * (pony_frame × body_scale)`, with the origin and the basis both
  scaled by `body_scale`. The rig's pivot already scales her body, so the authored pose becomes a
  uniform scale about the mattress centre: Canon, JRHNBR, Same Height and the stallion multiplier
  all render at their own size. The pose is authored at canon size; Hoers is untested.
- **Weight** comes from the pose modifier's `amount` ramp: each bone slerps from whatever the game's
  `lie_down` settle left to the authored rotation, and the root blends with `interpolate_with`, so
  POSING_IN still eases her in.
- **The head bone is reset to rest** on this path. The runtime owns the face: the gaze solve then
  aims `pony_head`'s frame (plus `HybridNeckLink`'s offset) at Anon. Baked head rotations were
  rejected because the pose lab has no head mesh.
- **Upright by default.** After the aim, `_level_head()` rolls the neck chain about its own forward
  axis (shares 0.30/0.36/0.34, so the neck does not kink at one joint) until her up matches the
  world's. The shortest-arc aim only sets the face *direction*; a pose that rolls the neck otherwise
  leaves her staring at Anon sideways. The settled `MISSIONARY` dump prints `head aim=…° roll=…°`
  and `body up=…°` (the pelvis up against the world up) so a sideways gaze or a rolled pose is
  measurable.
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

### Camera

`presentation.missionary.camera_mode` (debug) picks the eye:

- **Anon eyes**: the view is his posed head plus the game's own eye offset, read from the
  eye `missionary_anon.apply()` caches for the frame (the offset itself still comes from the rig's
  rest values). The lean is **one hinge at the `Spine` joint** (`LEAN_HINGE`): the whole upper body —
  chest, neck, head, shoulders, arms and hands — tilts as a unit around it, while the hips, thighs and
  legs stay exactly on the authored pose and keep the stroke. W tips the hinge forward/down toward her,
  S back/up, and Q/E add the side lean. The missionary vulva trims (`vulva_shift_mm`,
  `vulva_pitch_deg`, `vulva_depth_shift_mm`) move only the anatomy mesh; the depth one ramps in
  after 20% depth and reaches its signed millimetre value at full thrust. The fold-coloring and
  vulva-hug hacks are missionary-only too. The six values (`vulva_shift_mm`, `vulva_pitch_deg`,
  `vulva_depth_shift_mm`, `vulva_hug_mm`, `head_clearance_mm`, `gaze_offset_mm`) are per pony size,
  stored under `presentation.missionary.size.<preset>` and edited through one **Size** dropdown;
  the act reads the game's current preset. The camera is pushed out of her live skull sphere and
  muzzle capsule by `head_clearance_mm` (debug, default 100 mm), in both views, so a close cheek or
  muzzle lean cannot enter her head as she turns it. The skull and muzzle radii scale with her body
  size; the clearance is an absolute pad on top. The camera is written after the pose in the same
  frame, so it never trails his head. Her gaze and the kiss target his authored **eye and mouth**,
  never the game camera on his standing player rig; the game's eye modifier follows the same target,
  offset by `presentation.missionary.size.<preset>.gaze_offset_mm` (debug, signed). A kiss leans
  the eye in toward the aim but never closer than
  `KISS_CLEARANCE_M` (0.45 m) × her body scale from her face point; her muzzle extends past that
  point.
- **Authored shots** (default): the trajectory below, through the pose lab's camera transforms
  (position and direction).

### The shot

The eye blends between the five authored camera **transforms** and nothing else: `start` neutral,
`back` (S), `front` (W, the kiss framing), `left`/`right` (Q/E). Both position and direction are
used. A pure axis lean meets the saved transform exactly; everything between is interpolated. A
shot the asset does not carry falls back to a fixed bed-relative point aimed at her live face, and
the log names it. The speed-driven surge/bob from standing (camera forward and world up) is added and
settles to zero at rest. Free look turns this shot where it stands.

**Third-person views** (`presentation.missionary.third_person`, debug, default off) is the only thing
that takes the eye off that trajectory: with it on, the lean also tilts the eye and the speed-driven
tilt, side-lean travel and the kiss lateral/drop are added — the shot then drifts around the two
joined bodies. Off, the authored transform plus the surge/bob is the whole shot.

- Five camera transforms come from the pose lab, bed-relative, in the asset's `shots` block. Both
  origin and basis are used; the origin is scaled by `body_scale`, the basis is not.
- `_tick_authored()` blends them by the lean: start weight `max(0, 1 - |forward| - |side|)`, the
  forward/back weight `|forward|` and the side weight `|side|`, normalised to one. A pure axis
  (S, W, Q or E) has a single weight of one, so the eye meets the authored position **and**
  direction exactly; everything between is a position average and a quaternion average.
- The asset's `left`/`right` are named from her side, so Q reads `right` and E reads `left`; the
  keys match the screen.
- A missing shot falls back to a fixed bed-relative point — `back` `start + rump 0.45 − up 0.18`,
  `front` `start + head 1.60 − up 0.10`, `left`/`right` `start ∓ side 0.60` (all × `body_scale`) —
  aimed at her live face, and the log names it once per act.
- A kiss does **not** move the authored shot: the `front` transform is the kiss framing. The
  `KISS_CLEARANCE_M` lean-in applies only in **Anon eyes**.
- **His body keeps the authored placement.** There is no second stroke asset: the attached
  alignment moves his pelvis, never his whole body, so his head (the act camera) cannot swing on a
  thrust. He is a human, so only his placement follows her size; the debug
  `presentation.missionary.anon_size_match` (0…1) blends his body scale toward hers, 0 human and 1
  a uniform scale with her.
- **Both poses use the attached alignment.** `anon_part.gd`'s `_aim_attached()` turns the shaft about
  its base along her opening's normal and asks for `hip_offset_wanted`; the body that carries him
  applies that offset, so his pelvis follows the entrance and the shaft can never slide out of his
  crotch — the same logic the standing act uses. The detached bed holder (`_track_bed`) is no longer
  used by the act.
- **Her tail is laid on the bed.** The hair tail is not in the authored body pose: every tail rig
  differs. `tail_lay.gd` is installed on the hair skeleton for the missionary act and turns whichever
  `mTail1..6` bones exist onto the bed plane toward her rump, straightening the chain; the root stays
  where the rig put it. The chain's pre-act local poses are restored before the modifier is freed, so
  the game's own tail motion resumes from the normal pose.
- The speed-driven surge and bob (camera forward and world up, zero at rest) are always added. The
  third-person debug adds the lean basis (pitch, side yaw, roll), the side-lean travel and the kiss
  lateral/drop. There is no frozen anchor and no framing nudge, so nothing can accumulate.

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
  at `pony_position - forward * _standing_gap()`, then sets his yaw along her forward so a standing
  act after a missionary restore does not inherit the old view. The 1.2 m Y cone keeps that
  correction small. The act end leaves him there and leaves his yaw/pitch at the last act aim; it
  does not snap the pre-act view back. AnonPony and headset/VR still move her in front of the camera rig with
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
  caress latches as in `docs/hands.md`. Pressing `S` arms a gradual side
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
- Palm scale is a shared caress setting; see `docs/hands.md`. `hands/scale.gd` runs after the
  pose's hand solve and restores the cached scales on every act exit.
- Holding `F` at `abs(side) >= STANDING_KISS_LEAN = 0.90` starts the same base-game kiss used by
  missionary; releasing `F` or dropping the lean ends it. The side is latched from the input lean
  and `_pin_base_kiss_side()` keeps her on the complementary head tilt; the deep-kiss side
  switch is disabled for the act. During the `Affection` release the camera
  lean and glance suppression are held until the head has retracted, then ease out. A completed
  kiss has a `500 ms` restart cooldown.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`. The game's
  Same Height preset now follows Anon's `player/height_cm`, so that gap, the lean scale and the
  caress offsets follow `Settings.anon_height_scale()` as described in `docs/hands.md`.
  For desktop human Anon the gap is measured from her root along her backward axis after he is
  placed behind her.
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
  normal; `caress_hand.palm_basis()` keeps the fingers forward and the palm flat on the coat. It
  eases in over `0.35 s` and back to rest over another `0.35 s`. While held, `_forced_glance`
  overrides the random glance scheduler and locks her look over that shoulder; release clears it.
- Caress: see `docs/hands.md`.

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
  live; hold Y ends it. The close-window caress time is in `docs/hands.md`.
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
and `lean_action_kind()` only fires the standing shoulder reach. Instead of aiming at his mouth on
the first frame, the look point blends from his eyes to his mouth by the kiss's own `0.35 s` fade, so
her head leans in with the kiss rather than snapping. The solve still follows the moving point each
frame, but the base-game contact target is his authored mouth (`mouth_point()`).

## Free look (debug)

`presentation.missionary.free_look` (default off) turns the act view where it stands — his head in
**Anon eyes**, the authored shot otherwise — instead of holding the authored orientation: mouse look
works, and `runtime._input` stops feeding mouse motion into thrust. The pose and act keep running.
Standing has no separate view, so the standing camera controller simply leaves the player camera
alone. The setting is live through `apply_live_settings`; the settings page pauses the world, so it
takes effect when the panel closes.

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
