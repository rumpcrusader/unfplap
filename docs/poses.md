# Poses and skeleton

This is the contract for the act's body pose: the skeleton driver, the authored missionary base,
the bed-frame placement, the standing body pose, the post-act posture and the timing domains that
write them. The act camera and shot are `docs/camera.md`; the anatomy part is `docs/anatomy.md`;
the caress paths and palm holders are `docs/hands.md`.

## Ownership

`poses/service.gd` is the pose session facade. It owns the skeleton pose modifier, the authored
missionary base, the bed frame and its follow, the extra modifiers (tail, tail lay, body sway,
prone sway, ear twitch, chin debug), the pony bone snapshots, the pose rig check and the pose
diagnostics. The runtime owns the act state, the start ordering and the one teardown ledger; it
binds the session and reads its `pose()`, `pose_config` and `bed_frame` directly. Presentation
modules read the same values from `shared/act_facts.gd`.

`poses/pose_rig.gd` is the bone cache and body-relative axes. `poses/authored_pose.gd` loads
`poses/missionary_pose.json`. `shared/pose_catalog.gd` holds the pose defaults; `poses/service.gd` owns
the live pose. `shared/act_motion.gd` is pure lean-travel and pose-action math; `camera/service.gd` owns the
camera and lean state.

## Typed view

The body wrappers that move with the pose (`poses/missionary_anon.gd`, `poses/standing_anon.gd`,
`poses/standing_presentation.gd`) and the pose modifiers the session installs (`poses/skeleton_pose.gd`,
`poses/tail_pose.gd`, `poses/tail_lay.gd`, `poses/body_sway.gd`, `poses/prone_sway.gd`, `poses/ear_twitch.gd`) read
`shared/act_facts.gd`, never the runtime node. The view carries the pose config, the presentation config,
the per-mare profile, the pose id and state, the live depth and bed frame, the scene handles, the
lean and thrust values and the callbacks they call back through. `poses/body_sway.gd` publishes its
world-space sway through `facts.standing_sway_offset`; that field is the one owner and the
runtime reads it from there. The session binds `facts`, `perf` and
`log` for the modifiers. The field and callback contract is `docs/act_facts.md`; a pose module
that reaches into the runtime fails `tests/test_source_hygiene.gd`.

## Spaces and axes

- Bone writes use `Skeleton3D` skeleton space via `get_bone_global_pose` /
  `set_bone_global_pose`.
- Axes are body-relative:
  - `right = sk.global_basis.inverse() * pony.global_basis.x`
  - `up = sk.global_basis.inverse() * pony.global_basis.y`
  - `forward = sk.global_basis.inverse() * -pony.global_basis.z`
- `up` is world gravity, not the pony's rolled dorsal axis.
- Never use raw world axes for bone posing.
- `pony_head.basis.z` is **not** the face axis. The head must not be rotated by straight-chain
  alignment; keep it in the bone list only as a direction target for `pony_neck2`. The head
  follows neck2 through its rest offset.

## Missionary

The pose is the **hand-authored asset** in `poses/missionary_pose.json`, placed in the real bed's
space, with the nuzzle and gaze overlays on top. There is no second implementation.

### Act state

Missionary is its own state, not the game's bed rest:

- **Anon stands** before the act owns the camera (`force_stand_up()`, then the start snapshot and
  the player lock), and the game's desktop presentation is parked. His own `AnonBody` is placed
  from the asset's `anon` transform in bed space and posed from the `anon` bones by
  `poses/missionary_anon.gd`, at render time. His body IK and desktop pose driver are switched off for
  the act.
- **She stands.** The bed rest is released and she is asked to `stand`, so the solver and the clip
  tier hold a neutral pose instead of `lie_down`; the act poses her body from the asset.
- **The bed is only a frame**: `bed_frame` (mattress top and axes) plus the offer/eligibility path.
- **The bed frame follows the bed.** The session's `bed_frame` (`facts.bed_frame` for
  presentation modules) is updated each tick by the bed's rigid delta; a moving bed (the
  Cloudominium's CloudDrift) carries the authored pose, the act body and the shot instead of
  leaving them at the world transform where the act started. The mattress top is not re-measured.
- **The end restores the scene relative to the bed** (`restore_scene()`: player, pony and camera
  snapshot plus the bed transform) and stands her. A moving bed applies the same rigid delta to all
  three, so the cuddle rejoin starts beside the current bed. A normal end of a bed act then returns
  to the cuddle: Anon sits on the bed's player seat and lies back, and she is invited into its guest
  seat, where the stock `CuddleSession` picks her up. A forced stop, a bad summary or a stock
  closeness refusal leaves her standing. The snapshot is re-read once the pose settles
  (`resnapshot()` at ACTIVE): taken at `prepare()` it catches Anon mid stand-up and restores the
  reclined eye height. `resnapshot()` refreshes only the game camera's transform, never the act's
  own view.

### Base pose

- **Asset.** `poses/authored_pose.gd` reads version 6 of the JSON once per process and caches it.
  Every transform is in **bed space**: origin at the middle of the mattress top, the bed's own
  axes, `+Z` the direction her head points. The runtime maps it onto the real bed with
  `bed_frame = Transform3D(bed basis * Basis(UP, PI), Vector3(bed x, drawn mattress top, bed z))`,
  so the pillow end (the shared bed frame's `-Z`) is where her head points.
- **The act owns the render.** The game re-poses the rig after our modifier pass (the clip tier's
  `enter`/`leave`, the posture and the terrain solver), so the modifier's write is not what the
  renderer sees. The runtime therefore applies the same recipe once more from `_process`, after
  every physics and process writer of the frame: `skeleton_pose.apply_render()`, same weight, no
  extra ramp and no clock advance. The physics-pass write stays because the game's own contacts and
  pose layers read the skeleton during the tick.
- **What is written.** The 30 body bones in `PONY_BONES` (`tools/pose_lab.gd`) — hips, spine1–3,
  neck1–2, flanks, femurs, tibias, legLowers, tarsals, hooves, shoulders, upper/lower arms, wrists,
  hands and fingers — plus the skeleton **root** (the armature bone) for placement. The actor node
  is never moved or rotated, so the capsule, bed support and posture recovery are untouched. The
  head bone, lids, eyes, ears, wings, feathers, mane and tail are never baked: the game and the act
  own them.
- **The file carries every one of those bones, including the ones left at rest.** The runtime
  writes only what the file holds and never resets the rig, so a bone missing from the file keeps
  the game's own pose and breaks the chain it hangs from. Version 5 skipped rest bones; version 6
  stores them, and `MIN_VERSION` is 6. The lab reads bed-space transforms for every version from
  `BED_SPACE_VERSION` 4 on, so an older file is never applied as lab world.
- **Own the scale too.** `FillyProportions` and the part hiders *multiply* a bone's pose scale
  every modifier pass (`set_bone_pose_scale(..., get_bone_pose_scale(...) * factor)`) and rely on
  the animation resetting it to rest each frame. The act replaces the animation, so every bone it
  writes also gets its rest scale back: without that the factor compounds (0.92^N collapses, >1^N
  explodes) and the neck, head or whole body stretches to `inf`. Parts the game hides stay hidden
  through its own hiders, never by leaving a bone collapsed in the asset.
- **Never invert a scaled parent basis.** The stock hiders collapse a bone by scaling it to
  `0.001`, and `set_bone_global_pose()` inverts the parent's *full* basis for every write — a
  1000× multiplier that compounds each frame until the pose is `inf` (the body pulled away, then
  flickering) and the anatomy part follows it. Every act write goes through `pose_rig.set_global()`,
  which builds the local pose from the parent's **orthonormalized** rotation and origin only, and
  rejects a non-finite target. The stock hiders stay on: they only hide parts, and `BodyIK` (the
  standing pose driver, not a hider) is the one modifier parked for the act.
- **Anon's own process is parked.** `missionary_anon.install()` stops `AnonBody._process`: it
  drives `LegHide` from the height of the act camera (the mattress-height eye reads as `seated`,
  so the game collapses his legs), rewrites the authored fingers every frame (`_update_fists`), and
  feeds `model_scale` from that camera. `LegHide.influence` is set to zero for the act (the
  modifier stays active), the desktop pose driver is nulled and the desktop presentation's own
  `advance()` is stopped, so only the act writes his bones. The skeleton and the rest of its
  modifiers keep updating.
- **The head mesh is never hidden.** `head_smd` is the head **and the hands**; hiding it is what
  removes the palms. The game's `HeadHide` collapses only the head bone, which hides the head
  vertices. `apply()` caches the authored eye right after the bone write and the lean, before
  `HeadHide` runs, so `eye_transform()` never reads the collapsed bone.
- **His palms are planted.** `_place_hands()` holds both wrists at the authored world height and
  lets only their X/Z follow the stroke and lean: the hands slide along the mattress instead of
  lifting. A two-bone arm solve reaches each wrist; the hand keeps its authored world orientation
  so the palm stays flat on the bed. Caress: see `docs/hands.md`.
- **The exit restores the avatar.** The act writes his world placement every frame; `remove()` puts
  back `avatar.transform`, its process state, `process_mode`, visibility, the pose driver, `BodyIK`,
  the `LegHide` influence and every bone's pre-act local transform (the authored pose deliberately
  stretched positions, which the game does not re-pose for every bone).
- **The part and the pony are reset too.** `anon_part.reset_state()` clears its aim, hip offsets,
  penetration seed, bend/squash, shader and placement at both encounter start and end. The pose
  session's `snapshot_bones()` / `restore_bones()` put every body and hair bone back after the
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
- **No fallback.** There is no second missionary pose. A missing/invalid asset, a version below 6
  or no bed frame (the floating pose preview) means no pose is applied, and the act's `pose_asset`
  gate refuses the start with `missionary pose unavailable: <reason>` in the log. The anatomy's
  `pelvis_curl_deg`/`legs_wrap`/`bed_lift_m` keys are gone with the stack.
- **Reload.** The asset is shared for the process; the **Reload posed base** Debug block action
  re-reads the file in place, so the lab export → game reload loop works mid-act.

## Standing

The standing body pose and placement. The camera, lean, glance and shot are `docs/camera.md`.

- Facing lock every physics tick at priority 100:
  `pony.global_transform.basis = _facing_basis.scaled(scale)`. `stay()` alone does not stop
  conversation facing, so `face_point`/conversation target are cleared late each tick and
  `face_turn_rate` is held at `0` for the act; locomotion and emotions keep running.
  Conversation attention is not a stop condition: another character addressing Anon can talk
  while `_keep_act_attention()` clears her listener each tick.
- Act start keeps her where she stands. For desktop human Anon, `_begin_standing_placement()`
  builds the act transform from her current facing and places him at
  `pony_position - forward * _standing_gap()`, then sets his yaw along her forward so a standing
  act after a missionary restore does not inherit the old view. The 1.2 m Y cone keeps that
  correction small. The act end leaves him there and leaves his yaw/pitch at the last act aim; it
  does not snap the pre-act view back. AnonPony and headset/VR still move her in front of the
  camera rig with `_standing_transform()`.
- `apply_anon_lean()` pins both foot targets at their live stepping pose while a lean moves the
  hip and camera/head forward, sideways or down, so the torso hinges over her instead of walking
  through the lean. With no lean the game's stepping feet are left alone; the capture clears on
  the next non-leaning frame.
- With `features.anatomy_oral` on and oral active, `oral_pitch`, `oral_yaw` and `oral_roll` swing
  the two neck bones and counter-rotate the head so her muzzle stays along the shaft. The keys are
  absent otherwise. `standing_camera.set_facing_override()` owns her turn while oral is active and
  clears when it ends; the normal facing lock resumes.
- Standing gaps: Same Height `0.55`, JRHNBR `0.45`, Canon `0.25`, Hoers `0.55`. The game's
  Same Height preset follows Anon's `player/height_cm`, so that gap, the lean scale and the
  caress offsets follow `Settings.anon_height_scale()` as described in `docs/hands.md`.
  For desktop human Anon the gap is measured from her root along her backward axis after he is
  placed behind her.
- A footstool may raise Anon's player root before the standing pose; the camera, feet and hips
  follow the raised floor. The rule, prop and supply are in `docs/stool.md`.
- `poses/body_sway.gd` translates `pony_hips` with an inverted damped spring: back on inward depth,
  forward on outward depth. All four limb-root origins are preserved so the hooves stay planted.
  The same world offset is added to Anon's pinned hip so the contact rocks together.
  `BODY_SWAY_MAX_M = 0.035`.
- Strong thrusts build a subtle rump blush decal up to `0.375` albedo mix (smack uses `0.8`).
  The reaction facade and the jiggle values are in `docs/reactions.md`.
- `poses/ear_twitch.gd` flicks both ear roots together on a thrust: a shared forward/back pitch and a
  sideways twitch that sends both ears outward or both toward the head. The per-ear sign comes
  from the root's lateral offset, with an eased envelope and cooldown.
- Base pose adds `chin_up_deg = 30` on the head and `neck_down_deg = 15` total on neck1/neck2.
- `foreleg_spread = 0.172 rad` is the absolute outward half-angle; the recipe measures the
  current hoof line and rotates the upper arms only by the difference.
- Tail aside/lift/flick on the hair skeleton; side randomized per act.
  `presentation.standing.tail.yaw_deg` (aside) and `pitch_deg` (lift) are the live amounts, in
  degrees. A damped spring driven by raw `depth` also rocks the
  tail with the thrust: sagittal `ROCK_PITCH = 0.12` and lateral `ROCK_YAW = 0.08`. Each thrust
  adds a short decaying wave (`JIGGLE_DECAY = 3.6`, `JIGGLE_FREQ = 18`, `JIGGLE_PITCH = 0.16`,
  `JIGGLE_YAW = 0.08`) at the same strength as the rump shader, strongest at the tail root and
  lagging down the chain. A smack adds the same wave through `reactions/service.gd` at
  `1.0 × _jiggle_size_scale() × smack_intensity`; the thrust wave scales with `jiggle.intensity`.
  The `jiggle` radius, intensity and smack amount, the stock-mark clear and the body-coat target
  are in `docs/reactions.md`. Stock marks are hidden and aged at act start, so a mark from an
  earlier regular smack cannot linger as a stale jiggle point. The game's tail anchor pins the
  first 12–67 mm of the `DevkitTail` root cap to the hair `mPelvis`, so the `mTail1..6` wave alone
  cannot move the base; `tail_pose` also translates the hair `mPelvis` by `JIGGLE_BASE_M = 0.02 m`
  using the rump shader's thrust wave and restores the mane bones, so only the tail base and chain
  move.
- Standing wings start at `WING_STANDING_HOLD = 0.65` (about `60°` above the ground), then open by
  `WING_STANDING_SPREAD = 0.25` as satisfaction rises. Missionary keeps the stock spread progression.
  A mod-owned `poses/wing_sweep.gd` runs last and yaws `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°`
  in opposite directions, sweeping the spread wings slightly backwards. Entering afterglow
  releases the hold and drives the same `WingTuck` blend to a full fold over
  `WING_AFTERGLOW_RETURN_SECONDS = 6.0`; early afterglow exit lets the node finish immediately.
- Standing enters a held `AFTERGLOW`: the tail lifts and flicks twice. Lean and A/D caress remain
  live; holding the act key ends it. The close-window caress time is in `docs/hands.md`.
  Missionary afterglow stays passive.

### Stretch (Idle Life)

The optional stretch is a standing pose style, not a new pose id. It is gated by the debug-only
`features.idle_life_stretch`, only applies while Idle Life is active, and stays dormant unless
**Enable debug** is on. It is currently broken: entering the act with it enabled makes Anon
undergo a transformation, so it must not be recommended.

- `poses/idle_stretch.gd` is the only file that names `res://mods/idle_life/idle_pose.gd`. It
  loads the installed script at call time, validates `mare`, `idle`, `side`, `time` and `fade`,
  and adds a `UnfplapIdleStretch` modifier to the body skeleton. Missing scripts or fields fail
  quietly; the act logs `stretch pose unavailable: idle_life` and keeps the normal recipe.
- One episode rolls `stretch` or `stretch_deep` and a side once, when the accepted presentation
  attaches. The choice lives on the pony's metadata, so the presentation and the act share it. A
  cancel or teardown clears it; a direct act rolls fresh. The ask itself is always the normal
  standing pose, so she can keep turning and talking to Anon while she asks.
- The external holder owns the body, the stance, the ground plant and the wings. The act's
  `UnfplapPose` (or `UnfplapPresentPose`) runs after it and, in stretch mode, applies only the oral
  neck offset and the head-back lift; the bow, chin/neck, foreleg bend and stance spread are
  skipped. `UnfplapBodySway` runs after both. The debug chin modifier stays last.
- The presentation attaches its full holder in `_attach_present_pose()`, after the navigator's
  `face_point` stepping turn away from Anon (the base-game conversation-circle turn). The turn
  settles within 60 degrees of directly away and never snaps; once the pose attaches its yaw is
  locked, so nothing rotates under the planted holder. It does not start during the ask or during
  the turn. `_process_tick`'s standing render write calls `sync_stretch()`; the runtime also calls
  it once after the act integrations begin, before body sway's first pass.
- `poses/body_sway.gd` recaches the hips origin and limb roots through `reset_base()` whenever the
  holder is installed or removed, so sway rocks the stretched plant instead of undoing it.
- The holder stays through the standing afterglow until `_end_session()` frees it. Teardown
  restores the normal pose and drops the stored episode choice.
- The presentation holder is owned by `poses/standing_presentation.gd`; the act holder is owned
  by `poses/service.gd`. The runtime forwards `clear_stretch_offer()` to the presentation
  controller for a cancel or close. The launching rules are in `docs/initiation.md`; the switch is
  in `docs/integrations.md`.

### Missionary kiss

`kiss_control.lean_kiss_tick()` runs for both poses. Missionary kisses when F is held and
`lean_forward >= MISSIONARY_KISS_LEAN` (0.90) **and** W is held: `lean_targets` adds `|side|` to
the forward lean, so without the W test a pure side lean would pull the kiss. The kiss itself uses
the custom head-aim path (the stock pose is authored for a standing pony); `Q`/`E` no longer kiss,
and `lean_action_kind()` only fires the standing shoulder reach. Instead of aiming at his mouth on
the first frame, the look point blends from his eyes to his mouth by the kiss's own `0.35 s` fade, so
her head leans in with the kiss rather than snapping. The solve still follows the moving point each
frame, but the base-game contact target is his authored mouth (`mouth_point()`).

## Aftercare

- No head lowering.
- Tail held raised straight (`aside_angle = 0`), with `flick_amplitude = 0.55` and a
  one-cycle flick every `1.4–2.4 s` on the hair skeleton.
- Navigator held for 10 s.

The aftercare lifetime, positive tail-up rule and the held mood face are in `docs/afterglow.md` and
`docs/face.md`.

## Timing domains

- `runtime._process`: view-depth travel, lean, climax wave, breath, look point, pose climax flag.
  `_process_tick` calls `poses/service.gd`'s `render_write()`, which owns the render-time order:
  park the game presentation and place the act's Anon body, write her pose, then the eye-shot
  camera tick. It then calls `camera/service.gd`'s `write_look_target()`, which owns the look
  point (the missionary gaze, the kissing-mouth blend and the authored-Anon fallback) and the
  pose's kiss and climax weights.
- `runtime._physics_process`: presentation, timers, facing lock, glances,
  auto-cuddle suppression.
- `main._process`: calls `active_runtime.apply_camera_motion()` every rendered frame.
  Keep this single owner.
- Do not merge these timing domains blindly.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_motion | `shared/act_motion.gd` | lean and travel math |
| shared | hands_reach_plan | `shared/hands_reach_plan.gd` | reach planning math |
| shared | hands_scale | `shared/hands_scale.gd` | palm scale |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `bind()`/`begin()`
- End: `release_pose()`
- Idempotent: yes


## Tests

- `tests/poses/test_session.gd` — pose build/free, bed frame follow, modifier installs, the
  standing stretch holder and the session API.
- `tests/poses/test_stretch.gd` — the external script validation, episode choice, ask ramp,
  modifier order, fallback and cleanup.
- `tests/test_standing_presentation.gd` — the offer gate, the navigator stepping turn and its away
  settle, a blocked turn aborting without a snap, the fallback rotation, and the
  ask-to-presentation stretch handoff including a live flag edit.
- `tests/poses/test_pose_asset.gd` — asset version, bone list and bed-space load.
- `tests/poses/test_pose_rig.gd` — bone cache, global write and non-finite rejection.
- `tests/poses/test_pose_scale.gd` — uniform scale and rest-scale ownership.
- `tests/poses/test_rotation.gd` — body-relative axes and the rotation helpers.

## Verification / lab

- Missionary on the Golden Oak guest bed: start, pose, a moving bed, the **Reload posed base**
  action, the **Show skeleton overlay** Anatomy Debug flag, hold-act-key end and the bone restore on the
  next animation frame.
- Standing: stance, foreleg spread, ears, tail, wings, afterglow fold and the pose at both Canon
  and Same Height sizes.
- Idle Life stretch: a private standing offer, the accept turn, the presentation, the act, a live
  flag toggle, a cancelled offer, a direct act, Idle Life removed, and both integrations at once.
  Check the forehooves stay planted through body sway, the oral/head-back overlays, anatomy and
  camera alignment, and the afterglow close window.

## Related docs

- `docs/camera.md` — shots, lean, glance, standing camera, free look.
- `docs/hands.md` — caress paths, palm holders, smack.
- `docs/anatomy.md` — the anatomy part and tail seating.
- `docs/reactions.md` — jiggle, rump blush, climax hearts.
- `docs/afterglow.md` — aftercare and the close window.
