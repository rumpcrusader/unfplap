# Act camera and shots

This is the contract for the act camera: the lean input and smoothing, the speed-driven surge and
bob, the missionary shot transforms, the standing camera and Anon's body lean, the standing eye
override, the free look and the captured player look. The body pose is `docs/poses.md`; the kiss
itself is `docs/kiss.md`; the hands are `docs/hands.md`.

## Ownership

`camera/service.gd` is the act camera session. It owns the lean input and its smoothing, the
speed-driven surge/bob response and the afterglow back-off, the debug free look, the free-camera
`controls_locked` lock, the standing eye override, the form-reset path, the captured player look,
every size/torso helper the shot and the hands read, and the shot's scene points: the neck
midpoint, her missionary face point and the vulva target. The runtime forwards those point reads for
the shot camera and the anatomy diagnostic row; the anatomy opening itself still comes from the
anatomy bridge.

`camera/missionary_camera.gd` and `camera/standing_camera.gd` stay the shot implementations;
`poses/standing_anon.gd` and `poses/missionary_anon.gd` stay the Anon body wrappers. The runtime owns the tick
order, the start sequence and the shot targets (stroke speed, climax wave); `act/exit.gd:run()`
calls the camera facade's `release_act_shot()` and `finish_act_shot()`, which run the leaves in
the built order.

The look point is the camera's too: `write_look_target()` picks the missionary gaze, blends toward
the kissing mouth by the kiss's own fade and writes the pose's `look_point`, `kiss` and `climaxing`
for the rendered frame. The runtime calls it between the pose render write and the shot tick, so
the head solves against this frame's lean. The gaze target itself comes from the anatomy bridge
through `facts.gaze_point`.

## Typed view

Every camera, shot and body module reads `shared/act_facts.gd` and never the runtime node. The runtime
binds the view and refreshes it once per phase (idle, physics after the pose tick and before the
fan-out, render before the camera work, and `apply_camera_motion()`), and the modules read the
camera fields (`lean_*`, `bob`, `lean`, `shot_lean_forward`, `free_camera_active`,
`look_*`, `camera`, `bed_frame`, `viewport`) plus the `kiss_controller()`, `missionary_body()`,
`authored_pose_asset()` and `mark_camera_basis_ready()` callbacks. `authored_pose_asset()` returns
the live rendered asset, so the bed camera holds the source shots through an edge and reads the
target's shots after completion. The internal bed face-sit declares the same `missionary_shots`
profile and its own five authored shots; the camera cuts to them when its edge settles. The pose
family, the contact kind
(`view.contact_kind`) and the presentation lean profile come from `facts.pose_view`; the camera
does not read a start pose id or a contact mirror. The field and callback contract is
`docs/act_facts.md`; a camera module that preloads `runtime.gd` or `main.gd` fails
`scripts/architecture.py --check`.

The camera's `pose_changed(view)` hook is the retarget seam: it caches the last family, shot
profile and presentation lean, and only on a change retires the pose-local lean action and re-aims
the next shot. It keeps the act camera session, the eye override and the captured look; the
eye-camera tick stays the runtime's render-time callback. The standing camera re-reads its glance/
tail config from the view's `from_config`/`pose_config` and caches it by settings group and pose
id, so a held debug pair does not snap. `tests/act_camera/test_camera.gd` pins the hook and
`tests/act_camera/test_kiss.gd` the kiss side.

## Modes and lean

- Desktop human Anon always uses the mod-controlled act camera.
- AnonPony and headset/VR keep the stock camera; they do not receive lean or act actions.
- Mouse motion does not turn the view; vertical mouse motion still thrusts.
- `Q`/`E` plus `W`/`S` form one continuous lean vector, not a press-to-fire key event:

  ```text
  side    = E - Q
  forward = W - S + abs(side), clamped -1…1
  ```

- `LEAN_RAMP_SECONDS = 0.5`, `LEAN_RETURN_SECONDS = 1.6`.
- During standing oral (`view.contact_kind == "mouth"`) the lean is locked: `Q`/`E` and `W`/`S`
  are not read, an active `Q`/`E` shoulder reach ends, an active `F` lean kiss releases, and
  `lean_forward`, `lean_side`, the displayed lean and the sway return to rest. The caress hands
  still tick and the standing look response still runs; the oral head path is `docs/hands.md`.
- The standing facing lock reads `view.facing`/`facing_amount` every physics tick. The pose-owned
  oral turn writes them; amount 0 clears the override and the normal `_facing_basis` resumes. The
  camera keeps one facing path and no service carries a facing copy.
- Camera mapping: forward `0.24 m`; backward `0.08 m` (half); side `0.18 m`; pitch is `6°`
  downward in **both** directions, plus `8°` outward side roll, `3°` side yaw and `1.5°` forward
  roll.
- Lean distances, pitch, yaw and roll scale with pony size:
  `lean_size_scale_for(size) = clamp(2.0 - size, 0.75, 1.5)`. JRHNBR (`1.0`) is the reference;
  Canon (`0.66`) is `1.34` (+34%).
- Standing Anon body lean: `apply_anon_lean()` freezes the whole lower body (hip target and both
  foot targets) at its act-start pose. The camera/head moves forward, sideways or down, so the
  torso hinges over her while the legs keep their pose instead of walking into the shot. Pulling
  back translates the hips and both feet together, so the whole lower body moves away without
  changing the leg pose.
- The hip is **depth-driven**. `_hip_phase` is the mouse `depth` low-passed by
  `HIP_SMOOTH_S = 0.04 s`. The fixed rump point is the base HipsTarget plus
  `THRUST_MAX_M = 0.045 × body_scale` toward her; `poses/anon_hip_thrust.gd` moves only the Hips bone
  by `THRUST_MAX_M × (1 - thrust.travel × (1 - phase))`, so depth 0 is the full backset and
  depth 1 reaches the rump point. `thrust.travel` scales the backset. The modifier restores the
  Spine and both UpperLegs to their pre-offset global poses, so the torso, head and legs do not
  follow. There is no speed/strength attack and no return spring.
- `presentation.standing.torso_angle_deg` (experimental/unbounded) hinges Anon's
  upper body forward over her. `apply_anon_lean()` keeps the pelvis through the hinge;
  `apply_camera_motion()` moves the head/camera along the spine arc
  (`ANON_TORSO_LEN_M = 0.65`). It applies live.
- With the lean active, the standing controller captures both foot targets and pins them at their
  live stepping pose, so the legs do not walk through the lean. With no lean the game's stepping
  feet are left alone. The capture clears at act end; the old planted-lower-body switch is retired.
- The camera is **speed-driven**, never an impulse. The physics tick filters the signed depth
  speed (`CAM_SPEED_SMOOTH_S = 0.06`) and `camera/service.gd` follows it with one critically damped
  response (`CAM_RESPONSE_S = 0.12`). `CAM_SPEED_REF = 4.0` depth/s reaches full travel; outward
  strokes use `CAM_BACK_RATIO = 0.5`. The bob target is negative, so the camera dips toward her on
  the inward stroke and rises on the return. Surge and Bob are cached from the complete
  `camera_thrust.*` block in `configure()` at act start and on a live settings edit; the facade
  keeps no fallback value.
- Side lean rolls the camera outward (`-LEAN_SIDE_ROLL_DEG × side`).
- The displayed lean is always smoothed at `CAMERA_INERTIA_SMOOTH = 5.0` (`camera/service.gd`).
- `Q`/`E` fire their pose action at `LEAN_FIRE = 0.75` and release at `LEAN_RELEASE = 0.60`. The
  action is latched while above release.
- The lean always holds a released position. `_lean_step()` only ramps toward a pressed target;
  the explicit `S` shoulder recentre uses `return_to_zero`. The act end and paused paths still
  return the lean over `LEAN_RETURN_SECONDS = 1.6`. There is no auto-return mode or toggle.
- With `idle_camera_sway` enabled the camera lean gets a small, slow forward rock
  (`0.010`). It is a **separate offset** (`camera/service.gd:shot_lean_forward()`), never added into
  `lean_view_forward`: folded in, the inertia smoother amplified it about twelvefold and the shot
  crept while nobody was leaning. There is no side sway. Pressing `S` arms a gradual side return,
  so the shoulder roll decays to neutral without leaning the other way.
- Lean and actions are available in both `ACTIVE` and `CLIMAX`; every other state ends them.
- The lean camera owns `player.controls_locked = true` for the two base poses. Save and restore
  the prior value at act end.
- `F` is not an act control in missionary. In standing, holding `F` at a full side lean
  (`abs(side) >= STANDING_KISS_LEAN = 0.90`) starts the same base-game kiss; outside an act it
  remains the game's flight key.
- Teardown order in `release_act_shot()`/`finish_act_shot()`: free-camera lock, Anon wrapper and
  palm scale, eye override and avatar, missionary view, standing camera, then player look.
  `restore_look()` only runs when the camera captured the player (`look_captured`), so a forced
  stop at `IDLE` cannot reset the player's facing.

## Missionary camera

`presentation.missionary.camera_mode` (debug) picks the eye. **Authored shots** uses the shot
trajectory below. **Anon eyes** keeps the view at `poses/missionary_anon.gd`'s
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

## Missionary shot

With the authored base pose in charge the shot is a **blend of the five authored camera transforms**
from the pose lab: `shots.start` (neutral), `shots.back` (S), `shots.front` (W, the kiss framing),
`shots.left`/`shots.right` (Q/E; the asset names are from her side, so Q reads `right` and E reads
`left` to match the screen). Both position and direction are used; the origin is
`shot_origin()`: the authored point scaled about the hips anchor and lifted so it stays on the
mattress at the live body size. The authored basis is unchanged at every size. The weights are
`max(0, 1 - |forward| - |side|)` for start, `|forward|` for the
forward/back shot and `|side|` for the side shot, normalised. A pure axis lean has a single weight
of one, so with no stroke speed the eye meets the authored transform exactly; everything between is
a position average and a quaternion average. The speed-driven surge/bob from standing is added on
top (along the camera forward and world up) and settles to zero at rest. A kiss does not move the
authored shot — the `front` transform is the framing.

The `KISS_CLEARANCE_M` lean-in applies only in **Anon eyes**. A missing shot falls back to a fixed
frame-space point placed by the same anchor/lift rule and aimed at her live face, and is named in
the log. There is no live offset, no frozen anchor and no framing nudge.

**Third-person views** (`presentation.missionary.third_person`, debug) is the only
way off the trajectory: with it on, the lean tilts the eye and the side-lean travel and kiss
lateral/drop are added. Off, the authored transform plus the surge/bob is the whole shot.

- Missionary body motion is `prone_sway` (`missionary_body_motion`), not the standing `body_sway`
  (`standing_body_sway`): the spine slides a little along the bed with raw depth and the head/neck
  nod `±3°`. The hooves are not pinned the way the standing sway pins them.
- Eyes: `ACT_LIDS = 0.45` during `POSING_IN`/`ACTIVE`, `CLIMAX_LIDS = 0.0` only in `CLIMAX`, and
  sleepier afterglow `0.90`/`0.95`. A late `_eyes_tick()` reasserts the stare every tick so a
  climax return or fluster peek cannot leave her wide-eyed. While a kiss is active it releases the
  act's stare once and stops touching the eyes, so the game's own fluster/deep-kiss eyelids run;
  the custom kiss's `touch("affection", ..., 0.95)` lid layer is not overridden.
- Missionary parks the desktop presentation for the act (process off, disabled) and re-shows the
  act's own `AnonBody`; `missionary_anon.remove()` restores the presentation, the avatar transform
  and its process at end, so the rotated bed body cannot appear inside the camera shot and the rig
  is back on the player afterwards.
- **His body keeps the authored placement.** There is no second stroke asset: during the act the
  attached alignment moves his pelvis, never his whole body, so his head (the act camera) cannot
  swing on a thrust. The standing start's placement fit is the exception and runs before the act:
  it moves his whole body once so the shaft rests at her entrance, then the camera is framed on the
  fitted stance. A shape resume repeats that fit before the resumed framing. He is a human, so only
  his placement follows her size; the debug `presentation.missionary.anon_size_match` (0…1) blends
  his body scale toward hers, 0 human and 1 a uniform scale with her.
- **The two base poses use the attached alignment.** `anon_part.gd`'s `_aim_attached()` turns the shaft
  about its base along her opening's normal and asks for `hip_offset_wanted`; the body that carries
  him applies that offset, so his pelvis follows the entrance and the shaft can never slide out of
  his crotch — the same logic the standing act uses. The detached bed holder (`_track_bed`) is no
  longer used by the act.
- **Her tail is laid on the bed.** The hair tail is not in the authored body pose: every tail rig
  differs. `poses/tail_lay.gd` is installed on the hair skeleton for the missionary act and turns
  whichever `mTail1..6` bones exist onto the bed plane toward her rump, straightening the chain;
  the root stays where the rig put it. The chain's pre-act local poses are restored before the
  modifier is freed, so the game's own tail motion resumes from the normal pose.
- The speed-driven surge and bob (camera forward and world up, zero at rest) are always added. The
  third-person debug adds the lean basis (pitch, side yaw, roll), the side-lean travel and the kiss
  lateral/drop. There is no frozen anchor and no framing nudge, so nothing can accumulate.

## Standing camera

- Camera height through player `_stand_eye` / `_eye_height`; do not set the eye line by teleporting
  the rig. The target is the preset eye (`player_eye_height × size_scale`) raised to her live
  `pony_head` **global rest** line when that is higher; that lift never passes Anon's own eye. A
  fitted body taller than its preset (the princesses, a tall modded mare) therefore cannot leave
  the view at her chest, and Anon is not scaled up to her. Rest, not the posed bone, so a
  conversation bow or the act neck-down does not move the camera. The global rest, not the bone's
  local rest, so a head parented under the neck carries the neck's rest offset. The line is
  measured in Anon's root frame, which terrain and the footstool may raise. A missing skeleton or
  head bone keeps the preset. The camera aims at the middle of her neck
  (`pony_neck1`/`pony_neck2` midpoint) once at pose start, then freezes. The lean vector is applied
  on top.
- A presented body's entrance follows its `BodyForm`: `form.rig` supplies the rear anchor and scale
  and `form.body_scale` the live scale (`camera/service.gd:entrance_offset_for()` delegates the
  math to `shared/body_profile.gd`). The preset moves by the entrance height, a raise capped at
  Anon's own eye or at a preset that is already higher; `runtime.act.swap.standing_gap()` adds the
  back offset, so Anon keeps the same distance from her entrance. The runtime passes the presented form
  to `apply_eye_override()` at start and every body-form refresh; the camera has no separate body
  binding. A re-application derives its target from the saved true base, not from the eye it
  already lowered, and a form that needs no crouch gives the true eye back. `camera.reset_for_form()`
  undoes the old override and shot state before applying the new form; `act/swap.gd:reset_visual_for_form()`
  re-fits a standing Anon with `_reanchor_player_for_form()` and then prepares the shot. A same-node
  revision runs the same reset as a resume (`docs/runtime.md`, `docs/body_change.md`).
- The bed shot needs no placement pass: `missionary_anon.apply()` and the authored camera read the
  live `body_scale` every tick. `reset_for_form()` clears the shot smoothing and the eye state, and
  the next tick re-evaluates the authored shot from the new body.
- Canon lowers the standing eye line by `CANON_STANDING_CAMERA_DROP_M = 0.10 m` and multiplies lean
  travel by `0.8`; JRHNBR raises it by `MOUNTING_STANDING_CAMERA_LIFT_M = 0.10 m`. These offsets
  apply on top of the eye target; the preset is the clamp's floor, not its cap.
- Lean mapping: forward `0.24 m` / `6°` down / `1.5°` roll; backward
  `presentation.lean_back_m` with the same downward pitch; side `0.18 m` /
  `8°` outward roll / `3°` yaw. All scale with pony size.
- Standing has no separate thrust rock spring; the shared speed-driven surge/bob handles it.
- Palm scale is a shared caress setting; see `docs/hands.md`. `shared/hands_scale.gd` runs after the pose's
  hand solve and restores the cached scales on every act exit.
- A footstool may raise Anon's player root before the standing pose; the camera, feet and hips
  follow the raised floor. The rule, prop and supply are in `docs/stool.md`.
- Glances use `pony.secondary.look_toward`; `head_back` is eased; pupils aim via
  `eye_motion.target_world` / `target_weight`. Look-back yaw clamps at
  `GLANCE_BACK_YAW = 1.62`; `glance_back_pitch` is multiplied by `1.2`. The `head_back` ease uses
  `GLANCE_BACK_FADE / glance_back_speed`, with `glance_back_speed` live in the settings tab. Every
  glance and camera value (`glance_min`, `glance_max`, `glance_hold`, `glance_back_chance`,
  `glance_back_pitch`, `glance_yaw`, `glance_back_speed`, `camera_forward_m`, `camera_pitch_deg`)
  is indexed from the cached pose config or the presentation block; the controller keeps no
  `GLANCE_*` constants and no fallback copy. A full forward `W` lean with no side lean forces
  `head_back = 1.0` and an upward look at Anon.
- Standing kiss camera: `presentation.standing.kiss` `camera_yaw_deg` yaws the
  camera toward her; the mouth target, lean distances and palm offsets are in `docs/kiss.md`.
- The standing controller caches the view's `from_config` (falling back to its `pose_config` when
  that is empty) by the pose view's settings group and pose id: it re-reads the dictionary only
  when the group or the pose changes and never reads a facts config alias, so the debug
  `standing ↔ standing_test` edge keeps the standing config and the glance/tail values do not
  snap. `facts.presentation_config` is still read on every sync.
- Standing enters the same held `AFTERGLOW`; the camera back-off is in `docs/afterglow.md`.

## Free look (debug)

`presentation.missionary.free_look` (debug) turns the act view where it stands — his head in
**Anon eyes**, the authored shot otherwise — instead of holding the authored orientation: mouse look
works, and `input/service.gd` sends the motion to `runtime.act.input.look_motion()` instead of
`thrust_motion()` through the act input protocol (`act/input.gd`). The pose and act keep running.
Standing has no separate view, so the standing camera controller simply leaves the player camera
alone. The setting is live through `apply_live_settings`; the settings page pauses the world, so it
takes effect when the panel closes.

## Dependencies

### Uses
| service | world | `world/service.gd` | the eye's camera |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_state | `shared/act_state.gd` | act state constants |
| shared | act_motion | `shared/act_motion.gd` | lean and travel math |
| shared | body_form | `shared/body_form.gd` | presented body rig and scale for the entrance offset |
| shared | body_profile | `shared/body_profile.gd` | rig entrance offset math |
| shared | log | `shared/log.gd` | log sink, perf entry and panel |

## Lifecycle

- Scope: per-act
- Constructed by: `act/build.gd` through `runtime._init()`
- Begin: `bind()`/`begin_session(family)`
- End: act teardown
- Idempotent: yes


## Tests

- `tests/act_camera/test_camera.gd` — lean ramp/return, the oral lean lock, the pose-view facing
  override, shot targets, free camera, the idempotent eye override and form reset, the global-rest
  eye line, the form entrance offsets, look capture and restore, size scales and the afterglow
  back-off.
- `tests/poses/test_session.gd` — the pose camera targets and the bed frame the shot reads.
- `tests/hands/test_actions.gd` — the camera amplitudes the caress uses.

## Verification / lab

- Missionary: authored shot at rest, S/W/Q/E blends, Anon eyes, third-person debug, free look,
  kiss framing and restore.
- Standing: lean, torso angle, hip depth, lean-time foot pin, glance, kiss yaw and the afterglow
  back-off.

## Related docs

- `docs/poses.md` — body pose, bed frame, standing stance, timing domains.
- `docs/kiss.md` — the kiss paths and the shared mouth/lean values.
- `docs/hands.md` — caress, reach and smack.
- `docs/stool.md` — the standing reach gap and the footstool lift.
- `docs/afterglow.md` — afterglow camera and wing return.
