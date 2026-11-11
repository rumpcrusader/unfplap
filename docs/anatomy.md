# Anatomy and tail seating

The anatomy system is the optional adult anatomy layer: the per-mare mesh and material, the act's
hole/oral/finish controls, the player part, and the tail dock seat. This file is the single
technical contract; other docs link here.

## Scope

This contract covers:

- which adult mares attach anatomy and how the mesh is bound;
- anatomy visibility, teats, the skin strip and the body-coat deform;
- the per-mare placement block and the debug placement actions;
- the act's shape drive, winking, hole, oral and finish controls;
- idle heat winking and discharge;
- the player part's placement, shaping and throb;
- tail seating, the dock skin and the tail/dock placement;
- the debug and performance surface.

It does not cover eligibility, act readiness, thrust scoring, pose or camera rules. Those are in
`docs/eligibility.md`, `PREFERENCES.md` and `ROTATION.md`.

## Architecture

| File | Role |
|---|---|
| `anatomy.gd` | persistent per-mare controller: attach/detach, placement, material, teats, strip, body coat, shape drive, idle heat, dock visibility, debug placement |
| `anatomy/act.gd` | per-act controller: shaft-driven shapes, winking and fluid; reads a plain act-facts dictionary and returns pose/facing values |
| `anatomy/act/state.gd` | pure hole/oral mix, shared shape drive and wink scheduler |
| `anatomy/act/oral.gd` | oral turn state, mouth anchor, style motion and facing |
| `anatomy/act/finish.gd` | finish in/out, finish droplets and afterglow rest depth |
| `anatomy/act/debug.gd` | the three aim markers |
| `anatomy/shapes.gd` | persistent closed/idle/fill/grip state, shaft mask and V2 anal keys |
| `anatomy/coat.gd` | rig coat patch, vulva/anal spread and the still zones |
| `anatomy/appearance.gd` | material, skin tones, teats, skin strip and their visibility |
| `anatomy/heat.gd` | idle heat phase poll, rest shape, wink and drip schedule |
| `anon_part.gd` | player part mesh, placement, aim, girth/head/length shaping, throb and the hip-offset handshake |
| `anatomy_placement.gd` | pure placement schema, shipped per-mare defaults, merge/sanitize/diff and the one-time legacy migration |
| `anatomy/tail/seat.gd` | world controller: seats every adult mare's hair tail at the reference dock, installs the dock cuff, applies placement and restores the original |
| `anatomy/tail/dock_attach.gd` | builds the dock's two-bind GPU skin on the hair skeleton |
| `anatomy/tail/dock_seat.gd` | snaps the dock base ring to the rumen and measures the tail-cap seat |
| `anatomy/tail/hide.gd` | debug modifier: collapses the tail chain by scale, restores cached scales |
| `anatomy/tail/visibility.gd` | debug controller: installs `anatomy/tail/hide.gd` on loaded AI characters |
| `anatomy/fluid.gd` | droplets with gravity, sticking, creeping and ground pools |
| `anatomy/teat_jiggle.gd` | teat spring sway |
| `anatomy/still_zone_debug.gd` | debug overlay for the two no-jiggle zones |
| `anatomy/body_coat_patch.gd` | runtime patch of the game coat shader; swaps the jiggle include and call |
| `anatomy/anatomy.gdshader` | the per-pony anatomy material |
| `anatomy/body_coat_deform.gdshaderinc` | the coat deform include used by the patch |
| `vr_act.gd` | optional VR standing act, gated by the anatomy master; not anatomy behavior |

The current entry points are not yet isolated:

- `main.gd` creates and holds `anon_part` and `tail_seat`, refreshes anatomy on settings changes,
  owns the placement debug actions and `refresh_dock_color`, and forwards `anon_encounter` and
  `anon_track`.
- `runtime.gd` resolves the persistent controller through `main.anatomy`, ticks the act handle,
  exposes the V/N/B gates and object queries, and supplies the shaft length and body-coat jiggle
  handoff.
- `missionary_anon.gd` and `standing_anon.gd` read `main.anon_part` directly for the hip offset,
  shaft length and shoulder aim.
- `input.gd` calls the runtime's anatomy action gates; `hud.gd` renders the matching rows and
  hidden finish row.
- `settings.gd` and `mare_registry.gd` use `anatomy_placement.gd` as the shared pure schema.

The migration target in `## Migration target` replaces those entry points with one world facade,
a per-pony controller and a per-act handle. Until then, treat the current files as the contract.

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
- `V` also requires the V2 mare bits. The original PPP mesh has no anal mesh, so the toggle is a
  no-op on it.
- Anal and oral need the mare's per-mare consent (`action_consent(pony, "anal"/"oral")`); a
  refusal shows the anatomy status line and changes nothing.
- `B` only changes the finish selection and shows the status line. The finish is applied by the
  player's climax event.
- `Y` owns the act; `V`/`N`/`B` never start or end it.

## Attachment and identity

- Anatomy attaches to every adult identity with a `pony_hips` bone and a stable id, including
  mares added by other mods. The base-game roster is not a whitelist. Filly/colt and stallion
  identities are excluded, and the player's own AnonPony never receives anatomy.
- The stable id is `relationship_id` metadata first, then the identity id. Placement, the
  per-mare profile and the act history all key off the same value.
- The princess body profile applies to `celestia` and `luna` and to a modded copy that sets
  `character_id` to either. It supplies the body scale and the placement anchor; an ordinary
  off-roster mare uses the normal profile.
- `assets_exist()` requires the winking mesh, teats and the skin strip. The V2 mesh is optional:
  `mare_bits = v2` falls back to the original PPP mesh when its asset is absent.
- The winking mesh is rebuilt once per source mesh and shared. The rebuild masks the anal rim out
  of the authored `closed` and `wink` shapes, so those shapes move only the vulva.
- Attachment loads the selected scene, moves its `MeshInstance3D` under a `BoneAttachment3D` on
  `pony_hips`, caches the bone bind, applies the placement, builds the material, attaches the
  teats and strip, resets the anal shape, and connects `physical_reaction` for a stock flank
  smack. The mesh is not parented to the body model.
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
- `vulva_height`, `lip_vertical` and `anal_scale` drive the shader. On the V2 mesh the anal scale
  is carried by the blend shape, so the shader's `anal_scale` stays at `1.0`.
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
- `mare_bits = original`/`v2` swaps the mesh in place. The anchor, material override, placement
  and current shape values stay on the existing node; the replacement mesh is refined and the
  lip radius is measured again.
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
- `anatomy_placement.gd` owns the shipped `MARE_DEFAULTS` table and resolves the player override,
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

The runtime passes one reused plain dictionary of act facts: `state`, `depth`, `penetration_m`,
`climaxes`, `size_scale`, `auto_pace`, `fluid_ground_y` and `penetration_reach`. The act never
reads runtime private fields. It returns the oral pose keys through `pose_config()` and the oral
turn's camera facing through `facing()`; the runtime applies both in the same frame.

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
  original PPP mesh has no anal shape keys; `anal_mesh()` returns null and `V` is unavailable.

### Winking

- The `closed` shape is 1 for the authored closed lips and 0 for open. The V2 `wink` shape adds the
  clitoral accent; the original PPP mesh has only `closed` and `stretch`.
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

- `V` toggles the anal hole in `ACTIVE`/`CLIMAX` when `features.anatomy_holes` is on, the V2 anal
  mesh exists, she is not oral and the per-mare `anal` consent is true. The mix eases over `0.9 s`.
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
  `VERTEX += flank_jiggle(VERTEX);` with `VERTEX += body_coat_deform(VERTEX);`. The outline hull
  is patched the same way. No game source is edited and no cel shader is copied.
- The patch is cached per source shader. A game update that removes either hook makes
  `anatomy/body_coat_patch.patched()` return null; the original shader is left alone.
- The patch drives the vulva spread, the V2 anal mound and hole, and two no-jiggle ellipsoids:
  one around the vulva and one around the visible ponut. The uniforms are body-local, mapped
  through the `pony_hips` bind.
- `coat_spread` scales the vulva spread, `jiggle_still` the vulva still zone, `anal_still` the anal
  zone, `still_oval` the vertical half-axis, `still_fade` the rim fade, `still_height_mm` the
  vulva zone's vertical placement and `vulva_out_mm` the mesh push. `draw_still_zones` overlays the
  two ellipsoids and their fully-still cores.
- The per-pony material duplicate and its outline are added back to the game's jiggle target list
  after every `_start_jiggle()`. The anatomy also re-adds them on a stock flank smack through
  `physical_reaction("flank_smack")`.
- Turning the flag off restores the original shader resource and clears the mod uniforms. The
  per-pony material copies stay; only the shader and the uniforms are undone.

## Player part

- `anon_part.gd` loads `assets/anatomy/anon_part.scn` and its albedo, AO and normal maps. It is
  available only for the human player form; AnonPony and a young form never show it.
- The part is attached to the player's Hips bone and placed from `anatomy.placement.anon.*`.
  `player_scale`, `part_base_scale`, `part_mid_scale`, `part_head_scale`, `part_length_scale` and
  `part_throb` shape the mesh; `part_front_m` and `pelvis_gap_m` set the standoff. The shaped
  length and head radius feed `entry`, `girth_at`, `shaft_radii`, the tip and the hole grip, so
  geometry and collision stay together.
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
  never inherits the previous transform.
- `missionary_anon.gd` adds the act-only `bed_inset_m` to `part_front_m` for the bed pose. The
  part is fully reset by `encounter(false)` and `encounter(true)`.
- `shaft_length_m()` is the visible placed length; the runtime's penetration reach is
  `shaft length - pelvis gap`. With the anatomy off the runtime uses `NOMINAL_SHAFT_M = 0.20`.

## Tail seating

- `anatomy.reseat_tails` (Anatomy → **Re-seat tails and docks**, default on) moves every adult
  mare's hair tail base to the game's exact reference anchor from
  `res://world/characters/hybrid_mare/dock_tail_mounts.json`. The reference is the game's
  canonical dock seat, derived from the body's own tail root (`pony_tail_01`). Mares added by
  other mods use the same seat: they are not gated by `SETTINGS.CHARACTER_ORDER`, an id with no
  `dock_visibility_fits.json` row gets `DOCK_VISIBILITY_FALLBACK`, and its
  `tail_y`/`tail_z`/`dock_y`/`dock_scale`/`tail_tilt_deg` come from the global
  `anatomy.placement.default.*`; the princesses' fitted bodies have no hair skeleton, so their
  tail seat is unavailable and their pre-hidden dock stays hidden.
- The `OpenPonyDock` uses the game reference fit, not `effective_fit()`: the per-mare
  `dock_visibility_fits.json` offset was fitted for the mare's *own* tail and, once the seat moves
  that tail to the reference, pushes the cuff above and behind the tail base. The fit is re-reached
  with `hybrid_dock`; its base ring is snapped to `hybrid_dock.rump_z(y) - 4 mm` by
  `anatomy/tail/dock_seat.gd`. The 4 mm embed and a falloff over the first 35% of the dock keep the
  base in the coat without creasing. The body, skeleton, mane and anatomy placement are untouched.
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

## Settings

The declarations are in `settings.gd`; this section is the anatomy-specific contract. The
settings page is built from the declarations, so the label, help, default and bounds are not
restated here.

- `anatomy.anatomy_mode`: `never`, `act` or `always`; default `never`. It replaced the old master
  switch and `act_only`, and drives `SETTINGS.anatomy_on()`.
- `anatomy.teats`, `anatomy.skin_strip`: optional teats and the midline strip; both off by
  default.
- `features.anatomy_fluid`: climax, finish and idle droplets; default on.
- `features.body_coat_deform`: runtime coat patch; debug, default on.
- `anatomy.skin_tone`, `anatomy.vulva_height`, `anatomy.vulva_inner_color`,
  `anatomy.clitoris_color`: material appearance.
- `anatomy.show_dock`, `anatomy.dock_color`, `anatomy.reseat_tails`: dock visibility, colour and
  seat; reseat is on by default.
- `anatomy.mare_bits`: `original`/`v2`, default `v2`; V2 falls back to the original when absent.
- `anatomy.placement.default.*`, `anatomy.placement.anon.*`, `anatomy.placement.<id>.*` and
  `anatomy.placement_target`: the placement block and editor target.
- `anatomy.anal_scale`, `anatomy.anal_aim_mm`, `anatomy.anal_hug_mm`, `anatomy.vulva_hug_mm`,
  `anatomy.lip_vertical`, `anatomy.strip_scale`: shape and grip tuning.
- `anatomy.coat_spread`, `anatomy.jiggle_still`, `anatomy.anal_still`, `anatomy.still_oval`,
  `anatomy.still_fade`, `anatomy.still_height_mm`, `anatomy.vulva_out_mm`,
  `anatomy.draw_still_zones`: body coat and still-zone debug values.
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
  and body tail roots through `anatomy/tail/hide.gd`; it touches no other body part.
- `anatomy.draw_still_zones` (**Draw still zones**) overlays the two still-zone ellipsoids and
  their fully-still cores on the body coat.
- **Force heat**, **Force diestrus** and **Clear forced cycle** are cycle debug actions; their
  effect on the idle heat display is described in `## Idle heat`.
- With **Enable debug** and **Print perf logs** on, an act prints the runtime's `perf` block; the
  anatomy contributes `anatomy_visibility`, `anatomy_tick` and `anatomy_afterglow` timings. Tail
  seating prints `tail perf attach`/`tail perf refresh` one-shot lines and a once-per-second
  `tail perf seats=… skinned=… builds=…/s` line; steady state is `builds=0/s` because the dock
  blend runs on the GPU.
- The mesh and material debug helpers (`body_coat_mesh()`, `body_coat_material()`,
  `body_outline_material()`, `is_attached()`) exist so the runtime can re-add the patched material
  to the game's jiggle target list.

## Tests

Current suites:

- `tests/anatomy/test_identity.gd`: the stable id, the adult-mare predicate, the princess body
  profile and the off-roster list.
- `tests/anatomy/test_geometry.gd`: the lip-radius rule, the body-local mapping, the still-zone
  radius and the V2 anal ring weights/centre.
- `tests/anatomy/test_act_state.gd`: the hole/oral mix, the shared shape drive and the wink
  scheduler.
- `tests/anatomy/test_appearance.gd`: the anatomy material, shader and V2 rebuild path.
- `tests/anatomy/test_anatomy.gd`: the legacy integration suite (placement, dock visibility,
  idle heat, mesh refinement, act calls, player part, body coat and still zones).
- `tests/anatomy/test_dock_attach.gd`: the dock's two-bind skin and bind math.
- `tests/anatomy/test_dock_seat.gd`: the dock base ring stays at or inside `rump_z - 4 mm`.
- `tests/anatomy/test_tail_hide.gd`: the debug tail collapse and restore.

The target layout is `tests/anatomy/`, split by system area: identity, geometry, act state,
controller, shapes, coat, heat, fluid, act API, player part and tail. Pure tests must not
instantiate a scene or read private controller state; facade tests use documented accessors and
fakes. See `## Migration target`.

## Known limits

- The anatomy is per-pony and attaches after the pony enters the tree; a mod that assigns the
  identity a frame later is caught by the deferred `_read_id()`/refresh retry. The service
  migration must keep that timing.
- The rig coat material is shared between ponies of one identity. A per-pony copy and its outline
  must stay owned by the anatomy; removing the copy would make one mare's still zone move every
  copy of that body.
- The dock's far-mesh bake and the parked skeleton are sensitive to its parent. It must stay under
  the hair skeleton; moving it under the body remaps its skin onto body bones.
- The body-coat patch depends on the game shader keeping `flank_jiggle.gdshaderinc` and
  `VERTEX += flank_jiggle(VERTEX);`. A game update that removes either hook disables the patch,
  not the whole anatomy.
- The princesses' fitted bodies have no hair skeleton; their tail seat is unavailable and their
  pre-hidden dock stays hidden.
- `V` is V2-only. The original PPP mesh has no anal mesh.
- The act's idle wink and the climax pulse share one countdown; adding a second scheduler would
  make them overlap.
- The persistent controller still reads runtime private fields. The act controller no longer
  does: it reads the facts dictionary and returns pose/facing values. That is the boundary the
  persistent split must copy; see the migration target.

## Migration target

The refactor is one system at a time, with no behavior change:

- `anatomy.gd` becomes the world facade owned by `main` as `main.anatomy`. It owns the per-pony
  controllers, the player part and tail seating.
- `anatomy/appearance.gd`, `shapes.gd`, `coat.gd` and `heat.gd` are already split out.
  `anatomy/controller.gd` and `anatomy/attach.gd` are the remaining split: attach/detach, LOD,
  placement and the per-pony lifecycle.
- `anatomy/act.gd` is the per-act handle returned by `controller.begin_act(pose_id)`;
  `anatomy/act/state.gd` is pure, and `act/oral.gd`, `act/finish.gd` and `act/debug.gd` own the
  three behaviors.
- `anatomy/identity.gd`, `geometry.gd` and `act/state.gd` are pure. `anatomy_placement.gd` stays
  a shared pure schema.
- The player part and tail seating move under `anatomy/`; `main` drops its `anon_part`,
  `tail_seat`, `refresh_anatomy`, `refresh_dock_color` and placement debug code.
- The act receives the plain act-facts dictionary (later a typed value) from the runtime instead
  of reading runtime private fields, and returns the oral pose delta and facing instead of writing
  `runtime._pose_cfg`. This part is already in place.
- Tests move to `tests/anatomy/`, split pure vs facade. The boundary is enforced by
  `tests/test_source_hygiene.gd`.

The plan and phase gates live in the refactor notes; this section only records the target API.
