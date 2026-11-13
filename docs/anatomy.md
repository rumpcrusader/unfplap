# Anatomy and tail seating

The anatomy system is the optional adult anatomy layer: the per-mare mesh and material, the act's
hole/oral/finish controls, the player part, and the tail dock seat. This file is the single
technical contract; other docs link here.

## Scope

This contract covers:

- which adult mares attach anatomy and how the mesh is bound;
- anatomy visibility, teats, the skin strip, the body-coat deform and the coat follow;
- the per-mare placement block and the debug placement actions;
- the act's shape drive, winking, hole, oral and finish controls;
- idle heat winking and discharge;
- the player part's placement, shaping and throb;
- tail seating, the dock skin and the tail/dock placement;
- the debug and performance surface.

It does not cover eligibility, act readiness, thrust scoring, pose or camera rules. Those are in
`docs/eligibility.md`, `docs/readiness.md`, `docs/poses.md` and `docs/camera.md`.

## Architecture

| File | Role |
|---|---|
| `anatomy/service.gd` | world facade: per-pony controllers, player part, tail seat/visibility and the placement editor |
| `anatomy/controller.gd` | persistent per-mare shell: placement, shapes, coat and appearance forwards, act lifecycle and the typed-facts boundary |
| `anatomy/attach.gd` | persistent attachment: mesh/anchor/dock, visibility, dock restore, the fluid node and idle discharge |
| `anatomy/facts.gd` | typed runtime context: state, pose, depth, bed frame, cycle phase and the host callbacks |
| `anatomy/placement.gd` | saved offset/pitch/scale, missionary trims and the debug nudge/save/reset path |
| `anatomy/act.gd` | per-act controller: shaft-driven shapes, winking and fluid; reads a plain act-facts dictionary and returns pose/facing values |
| `anatomy/act_bridge.gd` | per-act handle the runtime owns: the persistent controller handle, the per-act handle, the typed context, the missionary body, the VR controller, the action gates and the aim/gaze reads |
| `anatomy/act/state.gd` | pure hole/oral mix, shared shape drive and wink scheduler |
| `anatomy/act/oral.gd` | oral turn state, mouth anchor, style motion and facing |
| `anatomy/act/finish.gd` | finish in/out, finish droplets and afterglow rest depth |
| `anatomy/act/debug.gd` | the three aim markers |
| `anatomy/shapes.gd` | persistent closed/idle/fill/grip state, shaft mask and V2 anal keys |
| `anatomy/coat.gd` | rig coat patch, vulva/anal spread, the vulva cut and the still zones |
| `anatomy/coat_follow.gd` | samples the body coat's leg weights and keeps the anatomy shell on the rump |
| `anatomy/appearance.gd` | material, skin tones, teats, skin strip and their visibility |
| `anatomy/heat.gd` | idle heat phase poll, rest shape, wink and drip schedule |
| `anatomy/player.gd` | player part mesh, placement, aim, girth/head/length shaping, throb and the hip-offset handshake |
| `shared/anatomy_placement.gd` | pure placement schema, shipped per-mare defaults, merge/sanitize/diff and the one-time legacy migration |
| `anatomy/tail/seat.gd` | world controller: seats every adult mare's hair tail at the reference dock, installs the dock cuff, applies placement and restores the original |
| `anatomy/tail/dock_attach.gd` | builds the dock's two-bind GPU skin on the hair skeleton |
| `anatomy/tail/dock_seat.gd` | snaps the dock base ring to the rumen and measures the tail-cap seat |
| `anatomy/tail/hide.gd` | debug modifier: collapses the tail chain by scale, restores cached scales |
| `anatomy/tail/visibility.gd` | debug controller: installs `anatomy/tail/hide.gd` on loaded AI characters |
| `anatomy/fluid.gd` | droplets with gravity, sticking, creeping and ground pools |
| `anatomy/teat_jiggle.gd` | teat spring sway |
| `anatomy/still_zone_debug.gd` | debug overlay for the two no-jiggle zones |
| `anatomy/body_coat_patch.gd` | runtime patch of the game coat shader; swaps the jiggle include and call and adds the vulva cut |
| `anatomy/anatomy.gdshader` | the per-pony anatomy material |
| `anatomy/body_coat_deform.gdshaderinc` | the coat deform include used by the patch |
| `vr/service.gd` | optional VR standing act, gated by the anatomy master; not anatomy behavior |

The internal entry points are:

- `main.gd` creates `main.anatomy`. `_on_pony` binds the controller and tail seat, `_on_player`
  creates the player part, and the placement debug buttons forward to the service.
- `anatomy/service.gd` owns the per-pony controllers, the player part, tail seat/visibility and the
  placement editor. It supplies the typed facts, the service, consent, status and the dock
  refresh to each controller. Runtime and pose systems use its methods; no other system needs the
  player node or a controller handle.
- `runtime.gd` resolves the controller through the service, passes the typed facts object,
  asks it to begin/end the act, ticks the act handle, and supplies the body-coat jiggle handoff.
- `poses/missionary_anon.gd` and `poses/standing_anon.gd` use the service's player methods for the hip
  offset, root position and scale.
- `input/service.gd` calls the runtime's anatomy action gates; `hud/service.gd` renders the matching rows and
  hidden finish row.
- `settings/service.gd` and `registry/service.gd` use `shared/anatomy_placement.gd` as the shared pure schema.

The controller reads the typed `anatomy/facts.gd` object and host callbacks; it never reads the
runtime node. `anatomy/attach.gd` owns the mesh, dock, visibility and fluid, so the controller is
a thin shell.

## Internal API

`main.anatomy` (world service):

```gdscript
setup(main)
player_ready(body), clear_player(), refresh_player(), player_apply_live()
controller_for(pony, runtime), bind(pony, runtime), controller(pony), online(pony)
refresh_all(), apply_live(), detach_controller(pony), shutdown()
tail_ready(pony), refresh_tails(), refresh_dock_color(pony), can_seat(pony), tail_report()
placement_target(), placement_id(), placement_values(id), placement_refresh()
placement_debug(op, value), placement_show()
consent(pony, key), status(text)
player_encounter(on), player_track(...), player_showing(), player_available()
player_prepare(), player_root_now(), player_tip_center(), player_shaft_radii(count)
player_shaft_length_m(), player_girth_at(point), player_tip_world()
player_set_aim(normal, opening, pitch), player_set_bed_inset(metres)
player_hip_offset(), player_note_hip_offset(offset), player_debug_scale()
```

`main.anatomy.controller(pony)` (per-pony handle):

```gdscript
setup(pony, facts, service, consent, status, dock_refresh)
set_facts(facts)
refresh(), detach(), apply_live()
begin_act(pose_id) -> Node, end_act(), act()
apply_part_visibility(show, teats_on, strip_on)
is_attached(), body_coat_refresh()
body_coat_mesh(), body_coat_material(), body_outline_material()
fluid(), idle_discharge(count)
```

`controller.begin_act(pose_id)` (per-act handle):

```gdscript
tick(delta, facts), pose_config(config), facing()
toggle_hole(state), toggle_oral(state), toggle_finish(state)
oral_active(), pull_out_selected(), finish_out(), finished_inside()
opening_normal(), hole_point(), hole_rear()
on_climax(), on_finish(), withdraw(), afterglow_tick(delta, facts)
end(), teardown()
```

`part()` is an anatomy-internal handle for the act; other systems use the service's `player_*`
methods. The act and controller read `anatomy/facts.gd`; neither reads the runtime node.

## Controls

| Input | Action |
|---|---|
| `V` | toggle the anal hole in `ACTIVE`/`CLIMAX` |
| `N` | turn her to oral in standing `ACTIVE` |
| `B` | choose finish in/out in `ACTIVE`/`CLIMAX` |

- The controls require their feature flag: `features.anatomy_holes`, `features.anatomy_oral` and
  `features.anatomy_finish`. With every flag off the keys are not consumed and the act is the
  master act.
- With `anatomy_mode = never` the keys pass through: the act controller does not exist.
- `V` toggles the anal hole. The mare bits mesh carries the anal shape keys; `anal_mesh()`
  returns the anatomy mesh.
- Anal and oral need the mare's per-mare consent (`get_profile(id).consent.anal` / `.oral`); a
  refusal shows the anatomy status line and changes nothing.
- `B` only changes the finish selection and shows the status line. The finish is applied by the
  player's climax event.
- `Y` owns the act; `V`/`N`/`B` never start or end it.

## Attachment and identity

- Anatomy attaches to every adult identity with a `pony_hips` bone and a stable id, including
  mares added by other mods. The base-game roster is not a whitelist. Filly/colt and stallion
  identities are excluded, and the player's own AnonPony never receives anatomy.
- A provider's `adult` assertion overrides the identity's age flag; `null` lets the identity
  decide. It changes age, not sex.
- The eligibility facade owns the adult capability: anatomy calls
  `eligible(pony, Target.ANATOMY)` and tail seating calls `eligible(pony, Target.TAIL)`. Anatomy
  never inspects the identity, filly/stallion flags or the provider's `adult` assertion itself.
- `profile.participation.anatomy` is part of the `Target.ANATOMY` answer. A `false` value detaches
  the anatomy and leaves the rest of the mare's profile alone. The Characters selector asks
  `Target.CHARACTER`, which has no participation veto, so an opted-out mare stays editable.
- The anatomy facade forwards the capability to its controllers and the tail seat as a callable;
  the runtime asks the eligibility service directly before it binds a controller. Rig readiness
  (`pony_hips`, the dock, the hair skeleton) stays here.
- The stable id is `relationship_id` metadata first, then the identity id. Placement, the
  per-mare profile and the act history all key off the same value.
- The princess body profile applies to `celestia` and `luna` and to a modded copy that sets
  `character_id` to either. It supplies the body scale and the placement anchor; an ordinary
  off-roster mare uses the normal profile.
- The mare bits mesh, teats and skin strip ship with the pack, so a missing mesh is a broken
  build, not a state the controller handles.
- The winking mesh is rebuilt once per source mesh and shared. The rebuild masks the anal rim out
  of the authored `closed` and `wink` shapes, so those shapes move only the vulva.
- Attachment loads the mare bits scene, moves its `MeshInstance3D` under a `BoneAttachment3D` on
  `pony_hips`, caches the bone bind, applies the placement, builds the material, attaches the
  teats and strip, resets the anal shape, builds the coat-follow weights, and connects
  `physical_reaction` for a stock flank smack. The mesh is not parented to the body model.
- `anatomy_mode = never` detaches. `act` shows her only during `POSING_IN`, `ACTIVE`, `CLIMAX`
  and `AFTERGLOW`; `always` shows her whenever the mesh is not a far mesh. `RESTORE` is hidden in
  `act` mode.
- A far-mesh LOD hides the anatomy, teats, strip and dock without detaching. Visibility polls
  every `VISIBILITY_POLL_S = 0.2 s`.
- Detach restores the body-coat shader and material override, frees the mesh, teats, strip, fluid
  and debug zones, disconnects the signal and asks the dock controller to refresh its colour.

## Appearance

- The anatomy material is `anatomy/anatomy.gdshader`, created per pony. `skin_tone` maps `0` to
  her coat,
  `0.5` to the old Darker tone and `1` to the old Dark tone, interpolating between the three
  anchors. Inner-fold and clitoris colours are separate settings.
- `vulva_height`, `lip_vertical` and `anal_scale` drive the shader. The mesh carries its anal
  scale in the blend shape, so the shader's `anal_scale` stays at `1.0`; the setting drives the
  ponut and the body coat.
- `disable_fold_coloring` is a missionary-only hack: it drops the vertex-alpha fold/clitoris
  masks so the whole mesh uses her skin tones.
- `coat_color` and `coat_shadow` on the anatomy material are her coat colours. The dock and the
  strip edges read that fallback; leaving it at zero made those vertices black.
- Teats are a skinned part from `teats.scn`, bound to the mare's own skin. The id hash selects the
  `mid`/`full` blend weights and the jiggle swing. `anatomy/teat_jiggle.gd` is parented under the
  teats
  and only physics-processes while they are visible.
- The skin strip is `skin_bridge.scn`, also skinned to the mare. Its span is measured from the
  dock AABB and the teat strip end; its gap is measured from the hip bind and the authored slit.
  `strip_scale` scales the strip in model-space X around the midline.
- The default dock colour is `genitals`: the dock copies the attached anatomy material with the
  skin tones. `coat` keeps the game's coat material. With anatomy detached, the dock falls back to
  the coat.

## Placement

- Placement lives in one block, `anatomy.placement`:
  - `default.*` is the global default for every mare;
  - `anon.*` is the player part;
  - `<mare id>.*` is a partial per-mare override.
- The ten anatomy/tail keys are `offset_x`, `offset_y`, `offset_z`, `pitch_deg`, `scale`,
  `tail_y`, `tail_z`, `dock_y`, `dock_scale` and `tail_tilt_deg`. The player block uses the first
  five only.
- `shared/anatomy_placement.gd` owns the shipped `MARE_DEFAULTS` table and resolves the player override,
  then the shipped per-mare default, then the global default. Only keys that differ from the
  resolved default are stored; saving a row equal to the default removes the block.
- The anatomy mesh is placed at the saved offset plus the calibrated `0.03 m` lift, pitched and
  scaled, then mapped through the `pony_hips` bind. A princess profile scales the origin and basis
  about the body. `show_dock` is visibility only and never moves the mesh.
- `vulva_out_mm` pushes the whole mesh out along its own normal; it exists for a pose that tucks
  the anatomy into the coat.
- Missionary adds the per-size vulva trims from `presentation.missionary.size.<preset>`:
  `vulva_shift_mm` (world up/down), `vulva_pitch_deg` (about the bed's lateral axis) and
  `vulva_depth_shift_mm` (starts at 20% depth and reaches its signed value at full thrust). They
  move only the anatomy mesh; the body, skeleton and saved placement are untouched.
- `anatomy.placement_target` is the persisted Default/Pointed-mare selection for every Placement
  action. The Debug actions **Placement**, **Placement tail**, **Placement dock**, **Placement
  tail tilt** (1° per press) and **Placement file** edit, save, reset or log the selected target.
  A default edit is staged until Save; a mare override is written directly.
- The old `anatomy_place.json` and `anon_place.json` files import once and are renamed to
  `.migrated`. The retired `anatomy.tail_seat.<id>` block and the `tail_offset_mm`,
  `tail_forward_mm` and `dock_offset_mm` globals migrate into the placement block. The legacy
  v0-v3 shifts live only in that migration.
- Old skin tones map to the slider anchors; an old `teats = false` file keeps the strip off once.
  Retired anatomy keys are erased on load and unknown keys are inert.

## Act anatomy

The runtime passes one reused typed context from `anatomy/facts.gd`: `state`, `pose_id`, `depth`,
`penetration_m`, `climaxes`, `size_scale`, `auto_pace`, `fluid_ground_y`, `penetration_reach`,
`bed_frame` and `cycle_phase`. The act and the persistent controller read that object and the
host callbacks; neither reads the runtime node. It returns the oral pose keys through
`pose_config()` and the oral turn's camera facing through `facing()`; the runtime applies both in
the same frame.

The bridge also writes `perf_on` from the host's `perf_enabled`, so the persistent controller takes
no idle perf clock while the debug probe is off. See `docs/perf.md`.

## Act bridge

`anatomy/act_bridge.gd` is the per-act handle the runtime owns. It is a `RefCounted`, created by
`anatomy.gd.new_act(host)`; the runtime creates one per act, binds it on every access and keeps
the orchestration. It owns:

- the persistent controller handle and the per-act `anatomy/act.gd` handle;
- the reused `anatomy/facts.gd` context;
- the missionary Anon body handle and the VR standing controller;
- the action gates (`hole_ready`, `oral_ready`, `finish_ready`, `actions_ready`), the toggles,
  the oral/finish reads and the placement controls;
- the aim/gaze reads (`gaze_point`, `aim_eyes`, `normal`, `opening`, `rear`);
- the act hooks (`tick`, `pose_config`, `withdraw`, `on_climax`, `on_finish`, `afterglow_tick`,
  `end`, `apply_live`, `detach`);
- the VR hooks (`vr_start`, `vr_stop`, `vr_y_held`, `vr_forward`, `vr_depth`).

The host is a plain dictionary of callables. The runtime supplies `main`, `pony`, `runtime`,
`reactions`, `anatomy_service`, `eligibility_service`, the live state (`state`, `pose_id`, `depth`,
`penetration_m`, `penetration_reach`, `climaxes`, `size_scale`, `auto_pace`, `fluid_ground_y`,
`cycle_phase`, `bed_frame`), the callbacks (`log`, `perf_note`, `perf_enabled`, `body_coat_smack`,
`status`,
`anatomy_facing`, `missionary_camera`, `kiss_controller`, `pose`, `thrust_move`, `now_s`,
`set_penetration_m`, `player_pony`, `headset_view`). A missing callable is a no-op.

The bridge never reads `runtime` or `main` private fields and never preloads either host. The
action keys, consent gates and shape behavior are `anatomy/act.gd` and the paragraph above; the
bridge only routes them.

### Shape drive

- The act reads the player part's girth at the opening. Without a part, the width comes from the
  depth scale. `_wide` is the local girth ratio and drives the vulva stretch, the anal shape and
  the shader cut.
- `_fill` smoothsteps the width into the grip. `_hole_mix` moves the drive from the vulva to the
  anal opening over `HOLE_SWAP_S = 0.9 s`. The oral turn subtracts itself from both.
- The live `closed` value is `1 - (1 - 0.6 * (1 - fill)) * front`; the lips keep their grip
  through the climax instead of snapping shut. The shader cut is closed over the shaft by the
  fill.
- `set_grip(radius)` converts world metres to mesh units, adds `vulva_hug_mm` (positive opens,
  negative grips), writes `hole_target`, zeroes the `stretch` blend shape and updates the body
  coat. Missionary uses `presentation.missionary.size.<preset>.vulva_hug_mm` instead of the global
  value.
- `set_shaft(pivot, axis, length, radii)` publishes Anon's shaft so the shader can project any
  vertex inside it back onto the surface. `clear_shaft()` zeroes it.
- The V2 anal shape has five additive keys: `anal_open`, `anal_stretch`, `anal_overstretch`,
  `anal_extreme` and `ponut_scale`. The first four start where the previous one ends; the ponut key
  is a 2× ponut-only scale that fades out under the extreme key. No upper clamp: an oversized
  shaft extrapolates the extreme key so the ring can still wrap it.
- The anal ring centre is interpolated between the measured V2 ring points. `anal_aim_mm` moves
  the penetration point vertically for the hole query; the ring shape itself uses the measured
  points. `anal_scale` drives the ponut and body coat, not the opening.
- `set_anal_grip(radius)` uses the same world-to-local conversion and `anal_hug_mm` padding. The
  mesh carries the anal shape keys, so `anal_mesh()` always returns the anatomy mesh and `V` is
  available.

### Winking

- The `closed` shape is 1 for the authored closed lips and 0 for open. The `wink` shape adds the
  clitoral accent.
- The idle heat rest and each wink drive `set_idle_wink(amount)`, which writes
  `closed = 1 - amount` and `wink = amount`. The shader depth cut stays off while the idle path
  owns the shapes, so a partial cut cannot drag the clitoris out through the lips.
- The act's own wink is one `0.5 s` beat. It runs while the tip rests at her lips (every
  `4…7 s`) or while the stroke is below 35% depth after at least one climax (every `1…2 s`). It
  never runs on top of a climax pulse, during the anal drive, or during oral.
- A climax clears the grip, starts three `1.35 s` open/close pulses, and layers them on the shape
  drive. The lips keep their shaft grip underneath.
- `wink_mode(depth, touching, climaxes)` is pure: 0 is nothing, 1 is touching, 2 is pulled out
  after at least one climax.

### Hole, oral and finish

- `V` toggles the anal hole in `ACTIVE`/`CLIMAX` when `features.anatomy_holes` is on, she is not
  oral and the per-mare `anal` consent is true. The mix eases over `0.9 s`.
- `N` turns her to oral in standing `ACTIVE` when `features.anatomy_oral` is on and the per-mare
  `oral` consent is true. She is turned about `UP` over `ORAL_TURN_S = 1.6 s`, her position eases
  to the mirrored anchor, her mouth viseme becomes `D`, and the oral style sequence drives
  `oral_pitch`, `oral_yaw` and `oral_roll` on the pose config. The head/mouth anchor is tracked
  during the act. Releasing the toggle eases her back to `_oral_from`.
- `B` toggles finish in/out in `ACTIVE`/`CLIMAX` when `features.anatomy_finish` is on. The row is
  built in the HUD but hidden until the finish has a visible effect.
- The oral turn writes the pony's global position. Every exit restores `_oral_from` before the
  navigator and posture resume; both a normal release and an act end use the same restore.

### Finish and fluid

- On the player's finish, `on_finish()` chooses out when `pull_out` is selected or the stroke is
  below `PULLED_OUT_PHASE = 0.35`; otherwise it finishes inside.
- An outside finish sprays on her with timed `_spurts_on_her` pulses (up to four). An inside
  finish schedules the leak after `0.7 s`. `withdraw()` sprays the inside finish when the player
  pulls out.
- Every fluid path is gated by `features.anatomy_fluid`. The persistent fluid node is reused by
  every act; idle heat discharge uses the same node.
- The afterglow tracks the part at a resting share: `0.8` of reach when he stays in, `0` when he
  finished out. The share moves toward its target at `1.6/s`.
- Act end animates the closed shape back to 1 over `1.5 s`, clears the part and the mouth viseme,
  and restores the oral facing.

### Aim markers

- `features.debug_aim_points` creates three unshaded spheres: the vulva opening, the V2 anal
  opening and the current player tip. They are parented under the main node today and removed at
  the next tick or teardown. They are debug-only.

## Idle heat

- Idle heat uses the same phase as the estrus cycle. `cycle_phase()` is `normal` when the feature
  is off or no relationship runtime exists; the debug cycle override still applies.
- `POSING_IN`, `ACTIVE` and `CLIMAX` suppress the idle display because the act owns the mesh.
  `AFTERGLOW`, `RESTORE` and `IDLE` may display it.
- The idle display requires the anatomy mesh to be shown and not a far mesh.
- In heat she rests at `heat_rest_open` (default `0.3`) of the open shape. Each idle burst uses
  `cycle.wink_burst_count()`: 70% single, 25% double, 5% triple. The gap is
  `wink_min_s…wink_max_s` (default `17…34 s`).
- Each beat opens to `wink_open_min…wink_open_max` (default 90% of the open shape) with an
  accelerated open, a short hold and an accelerated close. `wink_timing` scales the three phase
  times.
- The first beat's peak may discharge one or more droplets. `drip` scales the count (`0` turns it
  off), `fluid_size` the droplet size and `fluid_alpha` the opacity. The droplets launch along the
  ground with `fluid_y_speed` and fall under the fluid node's gravity; the persistent node pools
  them on the ground under her.
- Normal and diestrus rest closed. The idle path does not fight a running tween; it only writes a
  new rest when no tween is active.

## Body coat deform

- `features.body_coat_deform` (debug, default on) duplicates the rig coat material and patches its
  `Shader` at runtime. It replaces the `flank_jiggle.gdshaderinc` include with the mod include and
  `VERTEX += flank_jiggle(VERTEX);` with `VERTEX += body_coat_deform(VERTEX);`, then adds the
  vulva coat cut at the start of `fragment()`. The outline hull is patched the same way. No game
  source is edited and no cel shader is copied.
- The patch is cached per source shader. The include and call are required: a game update that
  removes either makes `anatomy/body_coat_patch.patched()` return null and leaves the original
  shader alone. The `void fragment()` hook is optional; without it the deform still applies and
  only the vulva cut is left out.
- The anatomy shell is pushed slightly into the coat, so without the cut the closed lips show the
  body surface behind them. The patch discards coat fragments within `coat_hole` × the measured
  lip radius, up to `coat_hole_depth_mm` behind the opening plane, in the same body-local frame
  as the spread. The cut is gated on the anatomy mesh being visible, so `act` mode leaves the coat
  whole while she is hidden. `coat_hole` 0 turns the cut off.
- The patch drives the vulva spread, the V2 anal mound and hole, the vulva cut and two no-jiggle
  ellipsoids: one around the vulva and one around the visible ponut. The uniforms are body-local,
  mapped through the `pony_hips` bind.
- `coat_spread` scales the vulva spread, `coat_hole` the cut radius, `coat_hole_depth_mm` the cut
  depth, `jiggle_still` the vulva still zone, `anal_still` the anal zone, `still_oval` the vertical
  half-axis, `still_fade` the rim fade, `still_height_mm` the vulva zone's vertical placement and
  `vulva_out_mm` the mesh push. `draw_still_zones` overlays the two ellipsoids and their
  fully-still cores.
- The per-pony material duplicate and its outline are added back to the game's jiggle target list
  after every `_start_jiggle()`. The anatomy also re-adds them on a stock flank smack through
  `physical_reaction("flank_smack")`.
- Turning the flag off restores the original shader resource and clears the mod uniforms. The
  per-pony material copies stay; only the shader and the uniforms are undone.

### Coat follow

The anatomy mesh is rigidly attached to `pony_hips`, while the visible rig coat is skinned to
`pony_hips` plus `pony_flank_L/R` and `pony_femur_L/R`. Without a follow, the coat's rump moves
with the hind legs and the anatomy rim slides out of the coat. The follow gives the anatomy the
body's own deformation across the whole mesh.

- `anatomy/coat_follow.gd` finds the skinned `MareBody`, buckets its 7,625 rest vertices into a
  2 cm grid and samples the nearest three body vertices for every anatomy vertex. Only the four
  leg weights are stored; the rest of the body weight stays on the pelvis. The weight is written
  to the anatomy mesh's unused `ARRAY_CUSTOM0` channel as RGBA8, so the mesh keeps its vertices,
  normals, material and blend shapes.
- `geometry.sample_coat_weights()` is pure: it maps the anatomy vertex through the body skin's
  `pony_hips` bind into body rest space, averages the nearest three weights by inverse distance,
  and clamps the four leg weights so the pelvis keeps the remainder.
- Each frame the controller computes four matrices `place⁻¹ · A_hips⁻¹ · A_leg · place`, where
  `A` is the live skeleton pose times the rest pose inverse and `place` is the untrimmed anatomy
  placement in skeleton rest space. `anatomy.gdshader` blends them by `CUSTOM0`; at rest every
  matrix is the identity.
- The same four matrices and the opening's sampled weights drive the controller's
  `hole_point()` and `hole_rear()`: the act's shaft contact, the fluid and the idle drips track
  the visible vulva and anus instead of the rigid mesh transform. The opening point uses the
  nearest anatomy vertex's custom0 weights; the normal uses the same blend of the local +Z.
  `shapes.hole_local()` stays the base local point; the controller deforms it before applying the
  mesh transform.
- `anatomy.coat_follow` is the 0…1 debug strength; 0 sets the shader strength to zero and keeps
  the anatomy rigid. The teats and skin strip are already engine-skinned, and the dock rides the
  hair skeleton, so their material copies set the strength to zero.
- The follow is independent of `features.body_coat_deform`: it finds the body skin itself and
  works with the game coat shader untouched. It skips when the body has no `MareBody`, no
  skinned `ARRAY_BONES`/`ARRAY_WEIGHTS`, or no `pony_hips` bind; the anatomy then keeps its rigid
  attachment. A missing `pony_flank`/`pony_femur` bone leaves that leg's contribution zero.
- The weighted mesh is per pony and is rebuilt when the selected anatomy mesh changes, the
  placement changes, or the body mesh or skin is replaced. The body weight grid is cached per
  body mesh and skin. The mesh swap keeps the anatomy's blend-shape values and the surface
  override material.

## Player part

- `anatomy/player.gd` loads `assets/anatomy/anon/anon_part.scn` and its albedo, AO and normal
  maps. It is
  available only for the human player form; AnonPony and a young form never show it.
- The part is attached to the player's Hips bone and placed from `anatomy.placement.anon.*`.
  `player_scale`, `part_base_scale`, `part_mid_scale`, `part_head_scale`, `part_length_scale` and
  `part_throb` shape the mesh; `part_front_m` and `pelvis_gap_m` set the standoff. The shaped
  length and head radius feed `entry`, `girth_at`, `shaft_radii`, the tip and the hole grip, so
  geometry and collision stay together.
- `player_prepare()` builds the part mesh hidden so the standing footstool gate can measure its
  natural root before an encounter. `player_root_now()` returns `Vector3.INF` until the mesh
  exists; `root_now()` on the part does the same guard.
- `part_throb` scales a two-lobe heartbeat. It also lifts the visible shaft while it is outside
  her; the lift fades to nothing at full depth.
- `back_out_m` is how far the tip rests behind her lips when pulled all the way out. It is
  negative penetration, so the depth scale never counts it.
- `track()` takes measured penetration in metres and places the tip exactly that far past her
  lips. The attached aim pulls his pelvis to `opening - normal × (shaft - penetration)`; the
  sliding aim puts the tip there; the bed holder sits `shaft - penetration` behind her. The
  applied value is eased by `PENETRATION_SMOOTH_S = 0.06 s`.
- The hip-offset handshake is two-way: the part publishes `hip_offset_wanted` and accepts
  `hip_offset_applied` after the pose moves his pelvis. `reset_state()` clears the offset, aim,
  bend, squash, shader squish, throb, bed inset and the smoothed penetration, so a following act
  never inherits the previous transform. A closing world removes the player body, and the part
  with it, from the tree before `world_closed` reaches the facade, so the part never reads a mesh
  world transform outside the tree: that reset only collects the bed holder, and the next
  `prepare()` or encounter rebuilds a detached part on the current body.
- `poses/missionary_anon.gd` adds the act-only `bed_inset_m` to `part_front_m` for the bed pose. The
  part is fully reset by `encounter(false)` and `encounter(true)`.
- `shaft_length_m()` is the visible placed length; the runtime's penetration reach is
  `shaft length - pelvis gap`. With the anatomy off the runtime uses `NOMINAL_SHAFT_M = 0.20`.
  The body-slap skin gap is measured from this same reach, so `Pelvis gap` already counts as
  distance and is never double-counted against Contact gap.

## Tail seating

- `anatomy.reseat_tails` (Anatomy → **Re-seat tails and docks**, default on) moves every adult
  mare's hair tail base to the game's exact reference anchor from
  `res://world/characters/hybrid_mare/dock_tail_mounts.json`. The reference is the game's
  canonical dock seat, derived from the body's own tail root (`pony_tail_01`). Mares added by
  other mods use the same seat: they are not gated by `SETTINGS.CHARACTER_ORDER`, and their
  `tail_y`/`tail_z`/`dock_y`/`dock_scale`/`tail_tilt_deg` come from the global
  `anatomy.placement.default.*`; the princesses' fitted bodies have no hair skeleton, so their
  tail seat is unavailable and their pre-hidden dock stays hidden.
- The stock game seats tails itself since 0.3.1: `hybrid_dock.apply()` calls
  `dock_tail_mount.seat()`, which moves the hair link to the reference plus the mare's
  `tail_seat_trims.json` row and marks her with the `tail_seated` meta. The pony build runs
  before `Mods.on_node`, so the mod's `attach()` measures the **already seated** tail: its delta
  is `anatomy.placement` minus the game trim, and the placement therefore replaces the game's
  trim rather than stacking on it. The shipped placement defaults and the game trim table carry
  the same values; only `tail_tilt_deg` is mod-only. Turning `reseat_tails` off restores the
  game-seated tail, which is the stock result.
- `profile.participation.tail` gates the seat. A `false` value skips the attach and restores the
  row if the seat was already applied; `refresh_all()` re-checks the row. A provider's `adult`
  assertion applies to the tail seat too, so a provider can make a character an adult without
  giving her a tail seat.
- The `OpenPonyDock` is rebuilt from the game reference fit, not from `effective_fit()`'s seat
  shift, and re-reached with `hybrid_dock`; its base ring is snapped to
  `hybrid_dock.rump_z(y) - 4 mm` by `anatomy/tail/dock_seat.gd`. The 4 mm embed and a falloff over
  the first 35% of the dock keep the base in the coat without creasing. The body, skeleton, mane
  and anatomy placement are untouched.
- The dock's outer opening is seated on the pinned tail cap's vertical centre.
  `anatomy/tail/seat.gd` measures the cap low/high in body bind space and the fitted dock's top,
  then applies `cap_centre - dock_top` through `anatomy/tail/dock_attach.gd`; there is no fixed
  drop constant. The Anatomy **Dock offset** trims that cuff position.
- `anatomy/tail/dock_attach.gd` builds the dock as a two-bind GPU skin on the hair skeleton:
  `mPelvis` at the base, `mTail1` at the outer end, and the same smoothstep weight between them.
  The mesh stays in the body skeleton's space; the bind poses convert body space into the hair
  skeleton's bind space
  (`rest_pose^-1 * hair_global^-1 * body_global`), and the dock's instance transform carries the
  lift as a post-skin body-space Y offset. The engine blends it every frame, so there is no
  per-frame mesh rebuild; lift, aside, flick, tail lay and tail tuck all carry the cuff, and it
  never bridges body and tail, so sitting cannot stretch it. The mesh keeps the dock metadata
  (`base_indices`, `pinned_*`).
- The dock must stay parented under the hair skeleton: `hybrid_far_mesh.sources()` bakes every
  visible `_model` mesh with a skin into the far mesh, and a hair-bound skin there would be
  remapped onto body bones. Under `hair`, `_show_far_mesh()` hides the cuff with the hair and the
  near/far bakes ignore it by name. Turning the setting off restores the original parent, local
  transform, skeleton path, skin, mesh and material, and strips the game's `parked_skeleton` meta.
- The seat is measured once on the live pony with `dock_tail_mount.measure()`. The original hair
  `pelvis_offset`, dock mesh, skin, material and tail material are cached before the first write,
  so turning the setting off restores the game's tail and dock exactly. The far-mesh identity
  cache is invalidated, and a currently shown far mesh is forced back to the near mesh for the
  next bake.
- Nothing is measured or written while the setting is off. `attach()` then stores only the mare's
  id, so a disabled seat costs one dictionary entry per pony instead of a tail measurement and a
  dock rebuild. Turning the setting on measures and seats every remembered mare from
  `refresh_all()`; turning it off restores them, and a settings tick with the seat already off
  writes nothing.
- A placement edit writes the tail immediately and the skinned dock follows it. The dock mesh is
  rebuilt once `DOCK_SETTLE_S` after the last edit, because only the base-ring snap needs it, so a
  slider drag rebuilds each mare once instead of once per tick. A `dock_y` edit needs no rebuild
  at all: it is the post-skin lift on the dock instance transform. `dock_scale` rebuilds without
  touching the tail.
- `tail_y`/`tail_z` move the tail from the exact reference; the dock follows. `dock_y` trims the
  cuff and `dock_scale` scales it. `tail_tilt_deg` rotates the hair pelvis about the body's rear
  axis, origin fixed, so the whole tail and its dock tilt sideways without moving the base. All
  apply live.
- The exact reference is applied to all eligible adult mares, including tails currently above it.
  A per-mare row lives under `anatomy.placement.<id>` with the same keys; only differences from
  the resolved default are stored, and a row equal to the default removes the key. **Placement
  file Show** logs every live mare's anchor, target, resolved placement, applied delta and source.
- A new tail mesh alone cannot change the seat: `hybrid_tail_anchor` re-pins the first 12 mm of the
  tail root to the hair `mPelvis`, and the hair link places `mPelvis` from the tail mount. Author a
  new tail only for shape or silhouette; the seat remains this controller's job.

## Lifecycle

- Scope: world + per-act bridge
- Constructed by: `main._ready()`
- Begin: `setup()`/`new_act()`
- End: `shutdown()`
- Idempotent: yes


## Settings

The declarations are in `settings/service.gd`; this section is the anatomy-specific contract. The
settings page is built from the declarations, so the label, help, default and bounds are not
restated here.

- `anatomy.anatomy_mode`: `never`, `act` or `always`; default `never`. It replaced the old master
  switch and `act_only`, and drives `SETTINGS.anatomy_on()`.
- `anatomy.teats`, `anatomy.skin_strip`: optional teats and the midline strip; both off by
  default.
- `features.anatomy_fluid`: climax, finish and idle droplets; default on.
- `features.body_coat_deform`: runtime coat patch; debug, default on.
- `anatomy.coat_follow`: how far the anatomy follows the body coat's leg skinning; debug,
  default `1.0`, `0` keeps it rigid.
- `anatomy.skin_tone`, `anatomy.vulva_height`, `anatomy.vulva_inner_color`,
  `anatomy.clitoris_color`: material appearance.
- `anatomy.show_dock`, `anatomy.dock_color`, `anatomy.reseat_tails`: dock visibility, colour and
  seat; reseat is on by default.
- `anatomy.placement.default.*`, `anatomy.placement.anon.*`, `anatomy.placement.<id>.*` and
  `anatomy.placement_target`: the placement block and editor target.
- `anatomy.anal_scale`, `anatomy.anal_aim_mm`, `anatomy.anal_hug_mm`, `anatomy.vulva_hug_mm`,
  `anatomy.lip_vertical`, `anatomy.strip_scale`: shape and grip tuning.
- `anatomy.coat_spread`, `anatomy.coat_hole`, `anatomy.coat_hole_depth_mm`,
  `anatomy.jiggle_still`, `anatomy.anal_still`, `anatomy.still_oval`, `anatomy.still_fade`,
  `anatomy.still_height_mm`, `anatomy.vulva_out_mm`, `anatomy.draw_still_zones`: body coat,
  vulva cut and still-zone debug values.
- `anatomy.wink_min_s`, `anatomy.wink_max_s`, `anatomy.heat_rest_open`, `anatomy.wink_open_min`,
  `anatomy.wink_open_max`, `anatomy.wink_timing`: idle heat.
- `anatomy.fluid_size`, `anatomy.fluid_y_speed`, `anatomy.drip`, `anatomy.fluid_alpha`: idle
  discharge.
- `anatomy.player_scale`, `anatomy.part_base_scale`, `anatomy.part_mid_scale`,
  `anatomy.part_head_scale`, `anatomy.part_length_scale`, `anatomy.part_throb`: player part.
- `anatomy.back_out_m`, `anatomy.part_front_m`, `anatomy.pelvis_gap_m`: player-part standoff.
- `presentation.missionary.part_inset_m`: missionary-only part inset, added to `part_front_m`.
- `presentation.missionary.size.<preset>.vulva_shift_mm`, `vulva_pitch_deg`,
  `vulva_depth_shift_mm` and `vulva_hug_mm`: the missionary-only placement and grip trims.
- `features.anatomy_holes`, `features.anatomy_oral`, `features.anatomy_finish`: the V/N/B
  controls; hole on, oral off, finish off by default.
- `features.anatomy_vr`: the optional VR standing act, default on.
- `features.debug_aim_points`: the three aim markers.

## Debug and performance

- Anatomy debug actions live in the Anatomy tab's Debug block:
  **Placement** (anatomy), **Placement tail**, **Placement dock**, **Placement tail tilt** and
  **Placement file**. They edit the selected target; the default is staged until Save, a mare
  override writes directly. **Placement file Show** logs every live mare's anchor, target,
  resolved placement, applied delta and source.
- **Hide tails** is the persisted Debug toggle that collapses every loaded AI character's hair
  and body tail roots through `anatomy/tail/hide.gd`; it touches no other body part. The facade
  pushes the switch to `anatomy/tail/visibility.gd`, which processes only while it is on.
- `anatomy.draw_still_zones` (**Draw still zones**) overlays the two still-zone ellipsoids and
  their fully-still cores on the body coat.
- **Force heat**, **Force diestrus** and **Clear forced cycle** are cycle debug actions; their
  effect on the idle heat display is described in `## Idle heat`.
- With **Enable debug** and **Print perf logs** on, an act prints the runtime's `perf` block; the
  anatomy contributes `anatomy_visibility`, `anatomy_tick`, `anatomy_coat_follow` and
  `anatomy_afterglow` timings. Tail
  seating prints `tail perf attach`/`tail perf refresh` one-shot lines and a once-per-second
  `tail perf seats=… skinned=… builds=…/s` line; steady state is `builds=0/s` because the dock
  blend runs on the GPU. The seat's own `_process` is enabled only while **Print perf logs** is
  on, so the probe costs nothing in a normal session.
- The mesh and material debug helpers (`body_coat_mesh()`, `body_coat_material()`,
  `body_outline_material()`, `is_attached()`) exist so the runtime can re-add the patched material
  to the game's jiggle target list.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | vr | `vr/service.gd` | VR act controls |
| shared | anatomy_placement | `shared/anatomy_placement.gd` | placement defaults |
| shared | cycle | `shared/cycle.gd` | estrus cycle |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Tests

Current suites:

- `tests/anatomy/test_identity.gd`: the stable id, the princess body profile and the off-roster
  list. The adult capability is tested with the eligibility service in `tests/eligibility/`.
- `tests/anatomy/test_geometry.gd`: the lip-radius rule, the body-local mapping, the still-zone
  radius, the V2 anal ring weights/centre, the coat weight grid/sampler and the coat-follow
  matrices.
- `tests/anatomy/test_act_state.gd`: the hole/oral mix, the shared shape drive and the wink
  scheduler.
- `tests/anatomy/test_appearance.gd`: the anatomy material, shader and V2 rebuild path.
- `tests/anatomy/test_anatomy.gd`: the legacy integration suite (placement, dock visibility,
  idle heat, mesh refinement, act calls, player part, body coat, the vulva cut and still zones),
  plus the provider's `adult` assertion and the participation gate.
- `tests/anatomy/test_facts.gd`: the typed context defaults and its optional perf/log/smack
  callbacks.
- `tests/anatomy/test_dock_attach.gd`: the dock's two-bind skin and bind math.
- `tests/anatomy/test_dock_seat.gd`: the dock base ring stays at or inside `rump_z - 4 mm`.
- `tests/anatomy/test_tail_hide.gd`: the debug tail collapse and restore.

All anatomy suites live under `tests/anatomy/`. Pure tests must not instantiate a scene or read
private controller state; facade tests use documented accessors and fakes. The legacy
`test_anatomy.gd` integration suite is the one exception: it still reads private state and is
split when the suite is next touched.

## Known limits

- The anatomy is per-pony and attaches after the pony enters the tree; a mod that assigns the
  identity a frame later is caught by the deferred `_read_id()`/refresh retry. The service keeps
  that timing.
- The rig coat material is shared between ponies of one identity. A per-pony copy and its outline
  must stay owned by the anatomy; removing the copy would make one mare's still zone move every
  copy of that body.
- The dock's far-mesh bake and the parked skeleton are sensitive to its parent. It must stay under
  the hair skeleton; moving it under the body remaps its skin onto body bones.
- The body-coat patch depends on the game shader keeping `flank_jiggle.gdshaderinc` and
  `VERTEX += flank_jiggle(VERTEX);`. A game update that removes either hook disables the patch,
  not the whole anatomy. A missing `void fragment()` keeps the deform but drops the vulva cut.
- The coat follow depends on the body coat's `pony_flank_L/R` and `pony_femur_L/R` skin weights.
  A body without those bones, a skin, or a `pony_hips` bind stays rigid. The act's hole point and
  normal use the same matrices and the opening's sampled weights as the shader, so the shaft
  tracks the visible opening.
- The princesses' fitted bodies have no hair skeleton; their tail seat is unavailable and their
  pre-hidden dock stays hidden.
- The act's idle wink and the climax pulse share one countdown; adding a second scheduler would
  make them overlap.
- The persistent controller and the act read the typed `anatomy/facts.gd` context, not the
  runtime node. The legacy `test_anatomy.gd` integration suite still reads private controller
  state; it is the only test seam left.

## Migration target

The anatomy migration is complete:

- `anatomy/service.gd` is the world facade owned by `main` as `main.anatomy`. It owns the per-pony
  controllers, the player part and tail seating.
- `anatomy/appearance.gd`, `shapes.gd`, `coat.gd`, `heat.gd`, `placement.gd` and `attach.gd` are
  split out. The controller is a thin shell; the attach module owns the mesh, dock, visibility,
  fluid and idle discharge.
- `anatomy/act.gd` is the per-act handle returned by `controller.begin_act(pose_id)`;
  `anatomy/act/state.gd` is pure, and `act/oral.gd`, `act/finish.gd` and `act/debug.gd` own the
  three behaviors.
- `anatomy/act_bridge.gd` is the per-act bridge the runtime owns: created by
  `anatomy.gd.new_act(host)`, it keeps the controller/act handles, the typed context, the
  missionary Anon body, the VR controller, the action gates and the aim/gaze reads. The runtime
  binds a cached host dictionary and never preloads the bridge.
- `anatomy/identity.gd`, `geometry.gd`, `act/state.gd` and `facts.gd` are pure.
  `shared/anatomy_placement.gd` stays a shared pure schema.
- The player part and tail seating are under `anatomy/`; `main` keeps only thin debug/button
  forwards and the HUD status gateway. The player body, the dock refresh, the perf sink and the
  debug logger are injected into the anatomy modules.
- The act and the persistent controller receive the typed `anatomy/facts.gd` context from the
  runtime instead of reading runtime private fields, and return the oral pose delta and facing
  instead of writing `runtime._pose_cfg`.
- Tests live under `tests/anatomy/`, split pure vs facade. The boundary is enforced by
  `tests/test_source_hygiene.gd`.

The only remaining seam is the legacy `test_anatomy.gd` integration suite, which still reads
private state; split it when the suite is next touched.
