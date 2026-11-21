# Anatomy and tail seating

The anatomy system is the optional adult anatomy layer: the per-mare mesh and material, the act's
hole/oral controls, the player part, and the tail dock seat. This file is the single
technical contract; other docs link here.

## Scope

This contract covers:

- which adult mares attach anatomy and how the mesh is bound;
- the presented body's form rig, fit, marker and tail-root refresh;
- anatomy visibility, teats, the skin strip, the body-coat deform and the coat line;
- the per-mare placement block and the debug placement actions;
- the act's shape drive, winking, hole and oral controls;
- idle heat winking and discharge;
- the player part's placement, shaping and throb;
- tail seating, the dock skin and the tail/dock placement;
- the debug and performance surface.

It does not cover eligibility, act readiness, thrust scoring, pose or camera rules. Those are in
`docs/eligibility.md`, `docs/readiness.md`, `docs/poses.md` and `docs/camera.md`.

## Architecture

| File | Role |
|---|---|
| `anatomy/api.gd` | the public entry and composition root: roster verbs, act presentation, Anon and garment handles, the `Rig` and the `Parts` |
| `anatomy/rig.gd` | the one `world/game.gd` boundary; every skeleton, body, hair, dock and mouth read |
| `anatomy/parts.gd` | per-pony registry: controllers, forms, tail rows, the player host and the placement editor |
| `anatomy/player_host.gd` | the Anon part lifecycle: create, free, warm and resolve the player body |
| `anatomy/placement_editor.gd` | the Anatomy Placement editor: the named pony's placement and reset actions and the report |
| `anatomy/controller.gd` | persistent per-mare shell: placement, shapes, coat, appearance, heat, the player-part handle and the act lifecycle |
| `anatomy/attach.gd` | persistent attachment: mesh/anchor/dock, visibility, dock restore, the fluid node and idle discharge |
| `anatomy/placement.gd` | saved offset/pitch/scale, the calibrated lift and the missionary trims |
| `anatomy/act.gd` | per-act presentation: shaft-driven shapes, winking, fluid and the afterglow track |
| `anatomy/act/shape_drive.gd` | pure hole/oral mix, shared shape drive and wink scheduler |
| `anatomy/act/oral.gd` | the mouth/contact provider: mouth point, base opening, D viseme and clear |
| `anatomy/act/debug.gd` | the three aim markers |
| `anatomy/shapes.gd` | persistent closed/idle/fill/grip state, shaft mask and V2 anal keys |
| `anatomy/coat.gd` | rig and merged-near coat patch, vulva/anal spread, the vulva cut and the vulva still zone |
| `anatomy/coat_line.gd` | bends the anatomy shell around a vertical line driven by the hind legs |
| `anatomy/coat_line_debug.gd` | debug overlay for the rest/live coat line and its cross-sections |
| `anatomy/garment_hull.gd` | the worn-garment rear-facing outer depth field, shared by every mare |
| `anatomy/appearance.gd` | material, skin tones, teats, skin strip and their visibility |
| `anatomy/body_fit.gd` | carries a part modelled on the mare body onto another body's skin binds |
| `anatomy/udder.gd` | the generated two-lobe teats, grown from her own belly surface |
| `anatomy/heat.gd` | the idle rest shape and one wink burst; estrus owns the schedule |
| `anatomy/player.gd` | player part mesh, placement, the aim/bed-inset write seam, girth/head/length shaping, throb and the hip-offset handshake |
| `estrus/service.gd` | the optional cycle: phase, per-pony wink schedule and the idle rest push |
| `shared/anatomy_placement.gd` | pure placement schema, merge/sanitize/diff and the one-time legacy migration |
| `shared/body_profile.gd` | the typed `RigProfile`, the legacy body profiles, the body-fit key and the standing entrance offset |
| `anatomy/tail/seat.gd` | world controller: seats every adult mare's hair tail at the reference dock, installs the dock cuff, applies placement and restores the original |
| `anatomy/tail/dock_attach.gd` | builds the dock's two-bind GPU skin on the hair skeleton |
| `anatomy/tail/dock_seat.gd` | snaps the dock base ring to the rumen and measures the tail-cap seat |
| `anatomy/tail/hide.gd` | debug modifier: collapses the tail chain by scale, restores cached scales |
| `anatomy/tail/visibility.gd` | debug controller: installs `anatomy/tail/hide.gd` on loaded AI characters |
| `anatomy/fluid.gd` | droplets with gravity, sticking, creeping and ground pools |
| `anatomy/teat_jiggle.gd` | teat spring sway |
| `anatomy/still_zone_debug.gd` | debug overlay for the vulva no-jiggle zone |
| `anatomy/body_coat_patch.gd` | runtime patch of the rig coat and the merged-near palette shaders; swaps the jiggle include and call and adds the vulva cut |
| `anatomy/anatomy.gdshader` | the per-pony anatomy material |
| `anatomy/body_coat_deform.gdshaderinc` | the coat deform include used by the patch |
| `vr/service.gd` | optional VR standing act, gated by the anatomy master; not anatomy behavior |

The internal entry points are:

- The entry creates the service and `ponies` hands it out as `PONIES.anatomy`. `ponies` binds the
  controller on attach and seats the tail on
  every prepare, `_on_player` creates the player part, and the placement debug buttons forward to
  the service.
- `anatomy/api.gd` owns the per-pony controllers, the player part, tail seat/visibility and the
  placement editor. It supplies the typed facts, the service, consent, status and the dock
  refresh to each controller, and pushes the live player part to every controller on a player
  rebuild. Runtime and pose systems use its methods; no other system needs the player node or a
  controller handle.
- `act/start.gd` calls `begin_act` before the pose reads its configuration, and `act/tick.gd`
  stages the returned handle every frame. `act/exit.gd` ends it before the pose is freed;
  `act/swap.gd` ends the old handle and begins the new body's. The runtime owns the `act_started`
  signal the start emits.
- `poses/missionary_anon.gd` and `poses/standing_anon.gd` read the `AnonBody` handle from the act
  facts: the standing body applies its wanted pelvis offset through `drive_hip()`, and the bed
  body asks for `hip_offset()` and records the applied value.
- `input/service.gd` calls the act session's anatomy action gates; `hud/service.gd` renders the matching rows.
- `settings/service.gd` and `registry/service.gd` use `shared/anatomy_placement.gd` as the shared pure schema.

The controller reads only its injected `anatomy/rig.gd` and Settings; it never reads the runtime
node or eligibility. `anatomy/attach.gd` owns the mesh, dock, visibility and fluid, so the
controller is a thin shell. The internal act reads the controller's `part()` handle and
`player_track()` forward; it has no service dependency.

## Internal API

`PONIES.anatomy` holds one `anatomy/api.gd` instance. The public verbs are:

```gdscript
bind_eligibility(service)
present(pony, form), withdraw(pony)
begin_act(pony, view, bed_frame) -> ActPresentation
anon(pony) -> AnonBody, entrance_point(pony) -> Vector3
wink(pony, beats), rest(pony, open)
garment(pony) -> Garment, rebuild_garment()
follow_body_coat(pony, flank) -> bool
debug_placement(pony, op, value, tail_owned), debug_show(pony), debug_anon_scale(pony)
```

`present` is idempotent and a null form means the body's own default. It is the one place the
assignment is decided: it stores the form, asks `eligibility` once for `Target.ANATOMY`, and then
attaches or detaches the controller and the tail row together. An ineligible body, or a facade with
no bound eligibility, keeps its stored form and gets neither the controller nor the tail row.
Presenting the same body with a new form refreshes the existing controller and tail instead of
adding a second one. `withdraw` releases the controller, the tail row and the form. `begin_act` returns null when
the pony is not presented; its handle's `end()` is the only teardown. The status signal `status(text,
seconds)` is the one HUD output.

The handles are inner classes of `api.gd`:

- `PoseView` has `family`, `frame`, `contact_kind`, `contact_target` and the live `bed_frame`.
- `ActStage` has `phase`, `depth`, `penetration_m` and `size_scale`.
- `ActPresentation` exposes `pose`, `stage`, `climax`, `end`, the `can_target_*` gates, the
  `target_*` choices, `target`, `mouth_point`, `hold_mouth`, `set_mouth_viseme`, `frame_point` and
  `frame_axis`.
- `AnonBody` exposes `prepare`, `showing`, `root_now`, `shaft_length_m`, `drive_hip`,
  `hip_offset`, `note_hip_offset`, `debug_scale`, `reset_pelvis` and `encounter`.
- `Garment` exposes `hull`, `transform`, `parent` and `visible`.

`Parts` owns `controllers`, `forms`, the tail seat/visibility and the `PlayerHost`. Its roster
verbs are `remember` (store the form), `attach` (build or refresh the controller and seat the tail together),
`release` (drop both and keep the form) and `detach` (drop everything). A controller is constructed
with `pony`, `form`, the `Rig`, a status callback and a dock-colour callback. The controller never
reads the runtime node or eligibility; the facade owns the gate. `PlayerHost`
resolves the Anon body through `Rig.anon_body_of()` and owns the hidden warm mesh.

The Placement editor no longer selects a pony: `debug_placement(pony, op, value, tail_owned)` and
`debug_show(pony)` take the body the debug caller aimed at. A source-owned tail is passed as
`tail_owned` by `debug/actions.gd`, which also applies the source's wrapper after a write.

`ActPresentation` stages the act with the caller-owned `PoseView` and `ActStage`. `act/tick.gd`
calls `stage(delta, stage)` every frame from `POSING_IN` through `RESTORE`; `act/tick._fanout`
updates the view and calls `pose(view)` on every change. `climax()` is one-shot: it sets the
handle's `climaxed` flag, tells the internal act, clears the grip and releases the fluid.

## Controls

| Input | Action |
|---|---|
| `V` | turn the vulva or the anus in `ACTIVE`/`CLIMAX`; refused in the mouth and face contacts |
| `N` | request the standing oral pose, or its return edge |

- The controls require their gate: `SETTINGS.anatomy_holes` for `V` and `SETTINGS.anatomy_oral`
  for `N`. `act/input.gd:anatomy_hole_ready()` and `:anatomy_oral_ready()` read the act handle's
  `can_target_vulva()`/`can_target_mouth()`, so the input service only consumes a key when the
  anatomy offer is live.
- `V` reads `target()`. From `VULVA`, if `can_target_anus()` and the per-mare `anal` consent from
  `eligibility.consent(pony, "anal")` pass, it calls `target_anus()`; otherwise it calls
  `target_vulva()`. A refusal is the input's HUD line, not an anatomy signal.
- `N` calls `can_target_mouth()`, requests the authored `standing ↔ standing_oral` edge through
  `poses/service.gd` with the per-mare `oral` consent, and shows the pose's refusal line. When
  the new view reports `contact_kind == "mouth"`, the act fan-out calls `target_mouth()`.
- `pose(view)` clears a `MOUTH` target back to `VULVA` when the contact is no longer mouth, so the
  key cannot be locked out after the oral edge ends. A face contact overrides every target and
  parks the part.
- The act key owns the act; `V`/`N` never start or end it.

## Attachment and identity

- Anatomy attaches to every adult identity with a `pony_hips` bone and a stable id, including
  mares added by other mods. The base-game roster is not a whitelist. Filly/colt and stallion
  identities are excluded, and the player's own AnonPony never receives anatomy.
- A provider's `eligible` assertion overrides the identity's age flag; `null` lets the identity
  decide. It changes age, not sex.
- The eligibility facade owns the adult capability: `present` is the only caller and asks
  `eligible(pony, Target.ANATOMY)` once. Anatomy never inspects the identity, filly/stallion flags
  or the provider's `eligible` assertion itself. The tail follows the anatomy controller, so the
  deprecated `tail` participation key no longer has a decision of its own.
- `profile.participation.anatomy` is the whole `Target.ANATOMY` capability. A `false` value detaches
  the anatomy and the tail and leaves the rest of the mare's profile alone. The Characters selector
  asks `Target.CHARACTER`, which has no participation veto, so an opted-out mare stays editable.
- Rig readiness (`pony_hips`, the dock, the hair skeleton) stays here; it is a physical check, not a
  capability.
- The stable id is `relationship_id` metadata first, then the identity id; the one rule is
  `shared/pony_id.gd:from()`. Placement, the per-mare profile and the act history all key off the
  same value.
- The presented body's `BodyForm` is the authority for every physical read: `form.rig` supplies the
  `RigProfile` (scale and rear anchor), `form.fit_id` the placement row, `form.owned_mesh_meta` the
  mesh-hide marker and `form.tail_root` a source-owned tail. A body with no stored form uses the
  default own form built from its identity (`shared/body_form.gd`). The anatomy body binding stores
  the form; the controller, the appearance and the tail seat read it.
- `shared/body_profile.gd` owns the princess table, the typed `RigProfile`, the ordinary rig and the
  entrance-offset math. Its array accessors `body_profile()`, `body_profile_for()` and
  `body_fit_id()` remain as legacy compatibility for the placement editor and the tail seat's
  no-form fallback; `anatomy/identity.gd` only delegates, and new code reads `BodyForm.rig` and
  `BodyForm.fit_id`. A modded copy is matched by `character_id` first, then by its own identity id;
  an off-table identity uses the ordinary rig.
- The placement row resolves by the form's `fit_id`, so a borrowed body uses its own fit. The
  player's placement override stays keyed by the stable id, so it follows the mare rather than a
  temporary body. The teats and the standing entrance follow the same form, so they fit the body
  that is actually rendered.
- A body may hide every mesh under its model unless the mesh carries a marker of the body's own.
  The form names that marker as `owned_mesh_meta`; the service mirrors it to `anatomy_owned_meta`
  and attachment copies it onto the anatomy mesh and its parts, which ride the same skeleton. Queen
  Chrysalis's body uses this so its `chrysalis_own` hide pass leaves the anatomy alone. The marker
  is provider metadata, not a `docs/api.md` convention.
- The anatomy body binding is `body_change/anatomy_binding.gd`: `body_change.wire()` builds it
  from the anatomy API the entry hands over. `bind_body()` and `refresh_body()` call `present`, and
  `unbind_body()` calls `withdraw`. The API gates the identity itself, so a provider that binds a
  body before the roster sees it cannot present an ineligible controller. `refresh_form()` re-fits
  the placement and rebuilds the appearance, marker and placement only when the rig or fit changed.
  `docs/body_change.md` owns the binding and lifecycle contract. The roster's
  `PONIES._prepare()` calls `present` once with the provider's stored form; there is no separate
  tail pass and no settings re-check loop.
- The mare bits mesh and skin strip ship with the pack, so a missing mesh is a broken build, not a
  state the controller handles. The teats are generated from her body; the old mare-shaped
  `teats.scn` is the fallback when her belly cannot be measured.
- The winking mesh is rebuilt once per source mesh and shared. The rebuild masks the anal rim out
  of the authored `closed` and `wink` shapes, so those shapes move only the vulva.
- Attachment loads the mare bits scene, moves its `MeshInstance3D` under a `BoneAttachment3D` on
  `pony_hips`, caches the bone bind, applies the placement, builds the material, attaches the
  teats and strip, resets the anal shape, builds the coat line, and connects
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
  masks so the whole mesh uses her skin tones. It is applied per material build, so the next
  non-missionary build restores the authored colors.
- `coat_color` and `coat_shadow` on the anatomy material are her coat colours. The dock and the
  strip edges read that fallback; leaving it at zero made those vertices black.
- The appearance reads the presented form: `set_form()` stores it, `_rig()` supplies the typed
  `RigProfile`, `_fit_id()` the placement row, and `_profile()` is empty for the ordinary rig so an
  ordinary mare keeps the shared body's teats. A princess or borrowed rig uses its rear anchor and
  scale, and `PRINCESS_TEATS` is keyed by the form's fit. The controller calls the form path on
  attach and on every form refresh; a same-rig revision keeps the attached parts.
- Teats are grown from her own belly (`anatomy/udder.gd`), not laid on as a mare-shaped part. An
  oval patch of her rest belly surface is found with vertical rays, pushed out into two rounded
  lobes with nipples, and skinned with her own weights at each point, so it rides with her belly.
  The outer ring stays on her coat and fades to the coat colour, so there is no rim. Her size comes
  from the **Teat size** per-mare preference (Auto, Small, Medium, Large, Huge); Auto keeps the
  princess look or a size from her name. The mesh is cached per body and rounded size, so a town of
  mares shares a handful of builds.
- `anatomy/body_fit.gd` carries the old mare-shaped part onto a body it was not modelled on: it
  scales the skin binds about her anatomy anchor and moves the part so its top meets her belly the
  way it meets the mare's. Celestia's pair also sits 7.6 cm further back. `PRINCESS_TEATS` carries
  her size, extra bounce and slower spring; only Celestia has a hand-placed look, so Luna uses Auto.
- `anatomy/teat_jiggle.gd` is parented under the teats and only physics-processes while they are
  visible. The generated pair carries its sway weight in `CUSTOM0.x` (0 at the base, 1 at the tip)
  and the material sets `sway_custom`, so the tips swing while the base stays on her belly; the old
  asset fades with the vertex alpha instead. `swing`, `stiffness_scale` and `damping_scale` set the
  travel and the spring.
- The skin strip is `skin_bridge.scn`, also skinned to the mare. Its span is measured from the
  dock AABB and the teat strip end; its gap is measured from the hip bind and the authored slit.
- The dock style setting chooses the dock material: `genitals` copies the attached anatomy material
  with the skin tones, `coat` keeps the game's coat material, and `hide` removes the dock. With
  anatomy detached, the dock falls back to the coat.

## Garment hull

The optional worn-garment compatibility (`docs/integrations.md`, Pantyhose & Panties) needs the
anatomy's outer surface as a height field the cloth shader can sample. `anatomy/garment_hull.gd`
builds it in anatomy-local space (`+Z` toward the tail):

- Every rest triangle is rasterised; the field is the maximum Z per cell. The inner canal and
  body-facing surfaces sit behind the outer surface and never win the max, so no normal filter is
  needed and the curved ponut-top/vulva-bottom silhouette is included.
- The field is the **rest appearance**, not the act envelope: the base mesh with `closed` at 1 and
  `ponut_scale` at the rest `anal_scale - 1`. `wink`, `anal_open`, `anal_stretch`,
  `anal_overstretch`, `anal_extreme` and `stretch` are at 0. The garment is removed at act start,
  so the field does not need the opened or stretched act shapes; the debug heatmap shows the rest
  vulva/ponut. If `pantyhose_undress` is off, the cloth stays on during an act and the act shapes
  can poke through; that is the player's choice.
- The X/Y projection is a `width × height` grid of the maximum Z per cell. The domain is the
  rest mesh's X/Y bounds plus a small margin; the Y margin is larger so the ponut top and vulva
  bottom are inside the field and the shader's edge fade does not cut their lift. Empty cells are
  filled by dilation and the debug smoothing passes.
- The field is normalised over `z_min`/`z_max`; an uncovered cell keeps a negative marker and the
  shader skips it. The texture is `FORMAT_RF`, linear, no repeat.
- The build is cached by source mesh RID, width, height, smoothing and the rest ponut scale, so
  every mare shares one field. `garment_hull_rebuild()` clears the cache; a precision edit or the
  Rebuild action rebuilds once, off the frame path.
- Width, height, smoothing and margin are unbounded debug values (the builder only floors the
  cells to 1 and smoothing to 0). High values cost a one-time rebuild. The adapter updates the
  hull transform every frame; it re-discovers the worn nodes on a fixed fallback, not a player
  refresh rate.

The reads:

- `garment_hull()` — the shared field, or null when detached.
- `garment_transform()` — `body.global_transform.affine_inverse() * anatomy_mesh.global_transform`,
  the anatomy-local → garment-model mapping, including the live placement and the missionary
  trims. `garment_transform_for(body, mesh)` is the pure form the tests pin.
- `garment_visible()` — attached and the visibility poll has the mesh shown; a far mesh or
  `act` mode outside the act is false, and the cloth is left alone.
- `garment_parent()` — the anatomy mesh itself; the debug heatmap copies its live transform
  rather than parenting to it, so a hidden far/act mesh does not hide the debug overlay.

The shader maps the worn vertex into anatomy-local space, reads the field, and pushes along the
anatomy's +Z by `surface_z + margin - local.z`. The margin is converted from millimetres by the
basis' Z scale, and the local push is converted back when it is applied, so the slider stays in
world millimetres on every body size. The edge fade is a small 3% of the domain, so the lift is
full at the anatomy; the larger Y domain margin keeps the ponut top and vulva bottom away from the
fade. The hull block is in the copied compatibility shaders under
`integrations/shaders/`; see `docs/integrations.md`.

## Placement

- Placement lives in one block, `anatomy.placement`:
  - `default.*` is the global default for every mare;
  - `anon.*` is the player part;
  - `<mare id>.*` is a partial per-mare override.
- The ten anatomy/tail keys are `offset_x`, `offset_y`, `offset_z`, `pitch_deg`, `scale`,
  `tail_y`, `tail_z`, `dock_y`, `dock_scale` and `tail_tilt_deg`. The player block uses
  `offset_y`, `offset_z` and `scale` only.
- `shared/anatomy_placement.gd` owns the schema and the merge/sanitize/diff helpers. The shipped
  per-mare rows live in `settings/characters.json` under `anatomy.placement`; resolution is the
  player override (keyed by the stable pony id), then a provider layer, then the shipped row, then
  the global default. The provider and shipped layers resolve by the presented form's fit
  (`## Attachment and identity`), so a disguise borrows the copied pony's row where the player has
  not saved an override on the mare's stable id. Only keys
  that differ from the resolved default are stored; saving a row equal to the default removes the
  block. A provider's placement therefore wins wherever the player did not edit.
- The anatomy mesh is placed at the saved offset plus the calibrated `0.03 m` lift, pitched and
  scaled, then mapped through the `pony_hips` bind. A princess profile scales the origin and basis
  about the body. `Dock style` is visibility/colour only and never moves the mesh.
- The per-size vulva trims are cached on attach and `apply_live()`; a live edit applies at that
  refresh, not on the per-frame trim.
- Missionary adds the per-size vulva trims from `presentation.missionary.size.<preset>`:
  `vulva_shift_mm` (world up/down), `vulva_pitch_deg` (about the bed's lateral axis) and
  `vulva_depth_shift_mm` (starts at 20% depth and reaches its signed value at full thrust). They
  move only the anatomy mesh; the body, skeleton and saved placement are untouched.
- `anatomy.placement_target` is the persisted Default/Pointed-mare selection for every Placement
  action. The Debug actions **Placement**, **Placement tail**, **Placement dock**, **Placement
  tail tilt** (1° per press) and **Placement file** edit, reset or log the selected target.
  Every action writes immediately: a Default edit persists the `anatomy.placement.default.*`
  block, and a mare edit writes her override. **Reset** returns the Default block to its shipped
  values, or drops the pointed mare's override so her resolved row applies.
  `anatomy/placement_editor.gd` owns the target resolution (`WORLD.camera()` →
  `debug/service.gd`'s `aimed_pony()` → `nearest_pony()`) and the placement and reset calls; the
  facade keeps `placement_debug()`/`placement_show()` as one-line delegates. The aim rule is one
  implementation shared with the debug action wheel.
- `anatomy/placement.gd` and the player part keep only the live placement fields: `load()` and
  `_apply_values()` take the complete resolved block and index it, so neither carries a copy of a
  placement default.
- The old `anatomy_place.json` and `anon_place.json` files import once and are renamed to
  `.migrated`. The retired `anatomy.tail_seat.<id>` block and the `tail_offset_mm`,
  `tail_forward_mm` and `dock_offset_mm` globals migrate into the placement block. The legacy
  v0-v3 shifts live only in that migration.
- Old skin tones map to the slider anchors; an old `teats = false` file keeps the strip off once.
  Retired anatomy keys are erased on load and unknown keys are inert.

## Rig contract

`anatomy/rig.gd` is the anatomy package's one game boundary: it wraps every `world/game.gd` read
and command anatomy makes. It is constructed by `anatomy/api.gd` and injected into the modules
that need a skeleton, body, hair, dock or mouth. No other anatomy file calls `GAME`.

## Act anatomy

`anatomy/api.gd:begin_act(pony, view, bed_frame)` creates the internal `anatomy/act.gd` and
returns an `ActPresentation`. The act keeps the caller-owned `PoseView` and `ActStage` by
reference; it allocates nothing per frame. The controller's `part()` is the one player-part seam;
the API's `PlayerHost` pushes the part to every controller on a player rebuild, and the act calls
`player_track()` for the per-tick track. The act writes the aim and bed inset through
`player.set_aim()` and `player.set_bed_inset()`.

`act/tick.gd` is the single per-frame anatomy caller: it fills `ActStage.phase` from the act
state, `depth` and `penetration_m` from readiness and `size_scale` from the camera, then calls
`ActPresentation.stage(delta, stage)` for every state from `POSING_IN` through `RESTORE`.
`act/tick._fanout` copies the live pose family, frame and contact into `PoseView` and calls
`ActPresentation.pose(view)` on every change. `act/phases.gd` calls the handle's `climax()` on
each climax event, and `act/exit.gd` calls `session.release_anatomy()` before the pose is freed.
`act/start.gd` creates the handle before the pose reads its configuration and emits the runtime's
`act_started(pony)` for the world integrations.

The face contact has a real provider. `PoseView.contact_kind == "face"` parks the part once
(`encounter(false)`), zeroes the fill, grip and anal shape, clears the shaft and drives the neutral
closed vulva; it never calls `player_track` or writes the part's aim or bed inset. The first
opening tick restores the part once and the normal track resumes. `contact_target` is the mouth
point in the mouth contact and `Vector3.INF` otherwise; the act falls back to the live hole when
it is not finite.

The pose-owned oral turn supplies the mouth and opening points through the act session's
`anatomy_mouth_point()` and `anatomy_opening()`. `poses/service.gd` owns the missionary Anon body;
the act facts' `missionary_anon` callback reads it, so anatomy no longer carries that body. The
gaze target and pupil aim move to `camera/service.gd:gaze_point()` and `:aim_eyes()`, which read
the same act body. VR scene construction moves to `vr/service.gd:attach()`, called by the session
with the act's typed callbacks.

### Shape drive

- The grip and anal tuning is cached by `shapes.read_settings()` on `set_mesh()` and
  `controller.apply_live()`: the vulva hug (global and missionary), the anal hug, the anal aim and
  the anal scale. A live edit applies at that refresh, not mid-tick.
- The act reads the player part's girth at the opening. Without a part, the width comes from the
  depth scale. `_wide` is the local girth ratio and drives the vulva stretch, the anal shape and
  the shader cut.
- `_fill` smoothsteps the width into the grip. `_hole_mix` moves the drive from the vulva to the
  anal opening over `HOLE_SWAP_S = 0.9 s`. The mouth contact subtracts itself from both.
- The live `closed` value is `1 - (1 - 0.6 * (1 - fill)) * front`; the lips keep their grip
  through the climax instead of snapping shut. The fill closes the lip shapes over the shaft.
- `set_grip(radius)` converts world metres to mesh units, adds `vulva_hug_mm` (positive opens,
  negative grips), writes `hole_target`, zeroes the `stretch` blend shape and updates the body
  coat. Missionary uses `presentation.missionary.size.<preset>.vulva_hug_mm` instead of the global
  value.
- `set_shaft(pivot, axis, length, radii)` publishes Anon's shaft so the shader can project any
  outer vertex inside it back onto the surface. While `shaft_length > 0` the fragment skips the
  inner-wall depth pull entirely: the shaft itself fills the opening, and pulling the pink wall
  toward the camera drew the interior over the cock. `clear_shaft()` zeroes the shaft and restores
  the pull for the empty opening. The guard is generic to standing, missionary and every contact
  where the shaft is visible.
- The V2 anal shape has five additive keys: `anal_open`, `anal_stretch`, `anal_overstretch`,
  `anal_extreme` and `ponut_scale`. The first four start where the previous one ends; the ponut key
  is a 2× ponut-only scale that fades out under the extreme key. No upper clamp: an oversized
  shaft extrapolates the extreme key so the ring can still wrap it.
- The anal ring centre is interpolated between the measured V2 ring points. `anal_aim_mm` moves
  the penetration point vertically for the hole query; the ring shape itself uses the measured
  points. `anal_scale` drives the ponut and body coat, not the opening.
- `set_anal_grip(radius)` uses the same world-to-local conversion and `anal_hug_mm` padding. The
  mesh carries the anal shape keys, so `winking_mesh()` always returns the anatomy mesh and `V` is
  available.

### Winking

- The `closed` shape is 1 for the authored closed lips and 0 for open. The `wink` shape adds the
  clitoral accent.
- The idle heat rest and each wink drive `set_idle_wink(amount)`, which writes
  `closed = 1 - amount` and `wink = amount`. The shader depth cut stays off while the idle path
  owns the shapes, so a partial cut cannot drag the clitoris out through the lips.
- The act's own wink is one `0.5 s` beat. It runs while the tip rests at her lips (every
  `4…7 s`) or while the stroke is below 35% depth after at least one climax (every `1…2 s`). It
  never runs on top of a climax pulse, during the anal drive, or during the mouth contact.
- A climax clears the grip, starts three `1.35 s` open/close pulses, and layers them on the shape
  drive. The lips keep their shaft grip underneath.
- `wink_mode(depth, touching, climaxes)` is pure: 0 is nothing, 1 is touching, 2 is pulled out
  after at least one climax.

### Hole and oral

- `V` toggles the anal hole in `ACTIVE`/`CLIMAX` when `features.anatomy_holes` is on, the pose
  view is not in mouth contact, and the per-mare `anal` consent is true. The mix eases over `0.9 s`.
- `N` requests the authored `standing ↔ standing_oral` edge through the runtime's pose request;
  the forward edge requires `features.anatomy_oral`, the per-mare `oral` consent and an inactive
  stretch holder. The pose-owned turn captures her root, facing and the live opening, turns her
  about `UP` over `1.6 s`, and moves the player part to the captured opening while she rotates.
  The edge switches the contact to the mouth at `0.9 s`; the act then reads
  `view.contact_target`, which eases to her live mouth once the turn settles. The reverse edge
  releases the contact at its start and restores the captured frame at its end.
- While the contact is `mouth`: the runtime keeps the slide, her impact vocal, the wings, the rump
  blush and the ear twitch, but drops the body plap, the rump/tail jiggle and the standing body
  sway. The lean is locked (`W`/`S`/`Q`/`E`, the shoulder reach and the `F` lean kiss are
  inactive) and `A`/`D` caress targets the sides of her head; the hand and camera contracts are
  `docs/hands.md` and `docs/camera.md`. The edge's `speech_stop` event cancels her act line,
  stops her base-game voice and re-asserts the viseme; its `viseme` event writes the `D` mouth.
  Her climax reaction line is skipped. The pose turn plays the base game's soft kiss on a
  `2.5–4.5 s` idle timer. Bystanders may still speak. Releasing the contact restores the regular
  standing behaviour.
- The pose turn writes the pony's global position. The reverse edge's completion, a release and
  the one act exit restore the position and facing the turn captured before the navigator and
  posture resume.

### Fluid

- Every fluid path is gated by `features.anatomy_fluid`. The persistent fluid node is reused by
  every act; idle heat discharge uses the same node.
- The afterglow tracks the part at her entrance (zero penetration). The held phase keeps the
  act's attached alignment: the part stays on Anon's Hips and turns to the live opening normal. The
  detached bed holder is not used, because it rolls the part to her anatomy mesh's own axes and
  her mesh is inverted in the lying pose.
- Act end animates the closed shape back to 1 over `1.5 s`, clears the part and the mouth viseme;
  the pose turn restores the captured frame through the one pose teardown.

### Aim markers

- `features.debug_aim_points` creates three unshaded spheres: the vulva opening, the V2 anal
  opening and the current player tip. They are parented under the main node today and removed at
  the next tick or teardown. They are debug-only.

## Idle heat

- `estrus/service.gd` owns the cycle phase and the per-pony wink schedule. It is the only reader
  of `features.estrus_cycle`, `anatomy.wink_min_s`, `anatomy.wink_max_s` and
  `anatomy.heat_rest_open`; it snapshots them on world enter and on a settings change.
- On a phase change estrus calls `anatomy.rest(pony, heat_rest_open)` and, in heat, a burst timer
  calls `anatomy.wink(pony, cycle.wink_burst_count(randf()))`. The burst mix is 70% single, 25%
  double, 5% triple; the gap is `wink_min_s…wink_max_s`.
- Anatomy suppresses both verbs while an act holds the mesh. `anatomy/heat.gd` keeps only the
  resting shape and one burst: it applies `set_idle_wink(amount)` and does not read Settings or
  poll a phase. The idle display still needs the mesh shown and not a far mesh.
- A burst opens to the `wink_open_min…wink_open_max` range with an accelerated open, a short hold
  and an accelerated close; `wink_timing` scales the three phase times. The first beat's peak may
  discharge droplets: `drip` scales the count, `fluid_size` the size and `fluid_alpha` the opacity.
  They launch along the ground with `fluid_y_speed` and fall under the persistent fluid node.
- Normal and diestrus rest closed. The idle path does not fight a running tween; it only writes a
  new rest when no tween is active.

## Body coat deform

- `features.body_coat_deform` (debug) duplicates the rig coat material and patches its
  `Shader` at runtime. It replaces the `flank_jiggle.gdshaderinc` include with the mod include and
  `VERTEX += flank_jiggle(VERTEX);` with `VERTEX += body_coat_deform(VERTEX);`, then adds the
  vulva coat cut at the start of `fragment()`. The outline hull is patched the same way. No game
  source is edited and no cel shader is copied.
- The cel alpha-cutout and occlusion variants use the same base include but omit the game
  `flank_jiggle` hook. The patch injects the game include, the mod include and the deform call into
  their duplicate before `void vertex()`, so a source body that dresses its coat with either
  variant gets the same cut and spread as the base shader.
- The merged near pony (`hybrid_near_mesh`) is covered too. Its palette shader, occlusion variant
  and outline use `VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal];`; the patch swaps in the
  same deform and cut for the palette entries whose source path is `MareBody`. A
  `body_coat_entry[pal]` mask built from the near mesh's source paths keeps head, hair, dock and
  wing entries on the stock jiggle with no cut. The merged body and outline materials join the
  same jiggle target list as the rig coat.
- The patch is cached per source shader. The base and outline hooks are required; a game update
  that removes either makes `anatomy/body_coat_patch.patched()` return null and leaves the
  original shader alone. The cutout/occlusion variants get the hook injected. The `void fragment()`
  hook is optional; without it the deform still applies and only the vulva cut is left out.
- The patch targets the **drawn** body coat. The game's `MareBody` is used while it is visible; a
  source body that hides it and draws its own (the changelings pack's `ChrysalisBody`) uses its
  own visible coat surface (`cq_Body`) and outline. The coat surface is the one whose source
  material is named in the coat list (`MareBody`, `cq_Body`) before the coat include is matched,
  because a source mesh's other cel surfaces carry the same include: on `ChrysalisBody` the teeth
  come first in the surface list. A hidden game body is never patched, because its cut would have
  nothing to show on. A material that is not a `ShaderMaterial`, or a shader with neither coat
  hook, is left alone and logs one `body coat skipped` warning naming the mesh, surface and
  shader, so a provider body cannot silently lose the cut.
- The anatomy shell is pushed slightly into the coat, so without the cut the closed lips show the
  body surface behind them. The patch discards coat fragments inside an ellipse behind the opening:
  the radii are `coat_hole` (lateral) and `coat_hole_height` (vertical) × the measured lip radius,
  up to `coat_hole_depth_mm` behind the opening plane. The cut is taller than it is wide because
  the measured lip radius is radial while the lips reach further up and down. The cut is gated on
  the anatomy mesh being visible, so `act` mode leaves the coat whole while she is hidden. Either
  radius at 0 turns the cut off.
- The patch drives the vulva spread, the V2 anal mound and hole, the vulva cut and one no-jiggle
  ellipsoid around the vulva. The uniforms are in the anatomy mesh's local frame. A
  body-to-anatomy matrix, refreshed every frame, maps each already-skinned coat vertex into that
  frame before the cut and the mask are evaluated, so the cut and the zone follow the live pose,
  the saved placement and the missionary trims. The debug rings use the anatomy mesh's own
  transform.
- `coat_spread` scales the vulva spread, `coat_hole` and `coat_hole_height` the cut's lateral and
  vertical radii, `coat_hole_depth_mm` the cut depth, `jiggle_still` the still-zone strength,
  `still_oval` the vertical half-axis, `still_fade` the rim fade and `still_height_mm` the zone's
  vertical placement. `draw_still_zones` overlays the ellipsoid and its fully-still core. The
  coat reads the oval and fade into its ring fields from the uniform pass; it holds no default
  for them. The deform and draw-still-zone toggles are cached on the visibility poll; the
  per-frame ring check reads the fields.
- The per-pony rig duplicate and its outline, plus the patched merged near materials, are added
  back to the game's jiggle target list after every `_start_jiggle()`. The anatomy also re-adds
  them on a stock flank smack through `physical_reaction("flank_smack")`.
- Turning the flag off restores the original shader resource and clears the mod uniforms on the
  rig, the hull and the merged near materials. The per-pony material copies stay; only the shader
  and the uniforms are undone.
- The body-coat and still-zone rows are unbounded debug numbers. The shader keeps its physical
  guards: a negative radius turns that deform or still zone off, and the fade and oval keep their
  lower-safe ranges.

### Coat line

The anatomy mesh is rigidly attached to `pony_hips`. The coat line is a vertical line in the
anatomy mesh's local space: when the line bends, every cross-section of the mesh bends with it,
and when the line stretches, the mesh stretches along it. It is a simple uniform bend, not a
sample of the body coat.

- `anatomy/coat_line.gd` builds `LINE_SAMPLES` points at `x = 0` across the bits mesh's local Y
  range. The line is the mesh's own vertical axis; it does not read `MareBody`, its skin or its
  weights.
- Each time the skeleton reports its final pose (`skeleton_updated`, after every
  `SkeletonModifier3D`), the controller reads the hind-leg tip bones (`pony_tibia_L/R`, falling
  back to `pony_femur_L/R` then `pony_flank_L/R`). It maps each tip's live and rest origin into
  anatomy local with `base_place⁻¹ · hips_delta⁻¹`, where
  `hips_delta = pose(hips) · hips_rest⁻¹`, and takes the horizontal component of the larger
  side's travel. The line's lower samples shift by that bend with a smooth falloff; the top
  sample stays seated. The bend is scaled and capped in local units.
- `geometry.coat_line_bend()` is pure: it fills the live line from the rest line and the bend.
  `geometry.fill_line_frames()` builds one frame per sample: the shortest-arc rotation from the
  rest tangent to the live tangent and the along-tangent stretch, with no roll about the line and
  no coat-normal follow. The stretch clamps to 0.5…2. The frame origin puts the sample's rest
  point on its live point.
- The pose is read inside `skeleton_updated` because outside it the skeleton reports its
  unmodified pose. The idle stretch, the buck and the other fidget layers are
  `SkeletonModifier3D`s, so a `_process` read would miss exactly the motions this line exists to
  follow.
- `anatomy.gdshader` stores the frames as `line_basis_x/y/z`, `line_origin` and `line_rest` with
  `line_count`. It finds the segment by the vertex's local Y, mixes the two neighbouring frames,
  and applies `basis · vertex + origin` to the position and the basis to the normal, after the
  anal/vulva/strip scaling and before the shaft projection.
- The same frames drive the controller's `hole_point()` and `hole_rear()` through
  `line_point_at()`/`line_direction_at()`: the act's shaft contact, the fluid and the idle drips
  track the visible vulva and anus instead of the rigid mesh transform. `shapes.hole_local()` stays
  the base local point; the controller deforms it before applying the mesh transform.
- Missionary trims stay on the mesh transform; the line uses the untrimmed `base_place`.
- The line is independent of `features.body_coat_deform` and the body coat's skin. It needs the
  `pony_hips` bone and at least one hind-leg tip; a missing leg bone leaves the line straight.
- The teats and skin strip are already engine-skinned and the dock rides the hair skeleton, so
  their copies of the anatomy material set `line_count` to zero. The generated teats' copy also sets
  `sway_custom`; the shader then uses `CUSTOM0.x` for their sway instead of the vertex alpha.
- The line is per pony and is rebuilt when the anatomy mesh changes or the placement changes. It
  retries every two seconds while it cannot be built. The line does not tick while the anatomy
  mesh is hidden.
- **Anatomy → Debug → Coat line** gates the whole line. Off uploads `line_count = 0` and keeps
  the mesh rigid; **Draw coat line** only controls the overlay. The controller caches both toggles
  in `_read_toggles()` on setup, `refresh()` and `apply_live()`, so a live edit applies there and
  the per-frame path only reads fields.
- With **Anatomy → Debug → Draw coat line** on, `anatomy/coat_line_debug.gd` draws the rest line,
  the live line and one cross-section marker per sample under the anatomy mesh. Live segments
  warm up when stretched and cool down when compressed.
- A stock flank smack jiggles the body coat; the anatomy shader does not call the game's
  `flank_jiggle`.

## Player part

- `anatomy/player.gd` loads `assets/anatomy/anon/anon_part.scn` and its albedo, AO and normal
  maps. It is
  available only for the human player form; AnonPony and a young form never show it.
- The part is attached to the player's Hips bone and placed from `anatomy.placement.anon.*`.
  `player_scale`, `part_base_scale`, `part_mid_scale`, `part_head_scale`, `part_length_scale` and
  `part_throb` shape the mesh; `part_front_m` and `pelvis_gap_m` set the standoff. The shaped
  length and head radius feed `entry`, `girth_at`, `shaft_radii`, the tip and the hole grip, so
  geometry and collision stay together. Every one of those values is read from its setting into
  a plain field by `_read_settings()`/`_load_place()`; the part declares no copy of a setting's
  default.
- The part is created on player ready and its hidden mesh is warmed by a deferred, guarded
  `prepare()`, so the first standing offer does not load `anon_part.scn`, its shader and three
  textures inside the offer scan. The anatomy master must be on; a body that is not ready yet is
  left to the gate's fallback.
- `AnonBody.prepare()` builds the part mesh hidden so the standing footstool gate can measure its
  natural root before an encounter, and is the idempotent fallback/rebuild path after the warm.
  `AnonBody.root_now()` returns `Vector3.INF` until the mesh exists; the part's own `root_now()`
  does the same guard.
- `part_throb` scales a two-lobe heartbeat. It also lifts the visible shaft while it is outside
  her; the lift fades to nothing at full depth.
- The tip rests at her entrance when it is all the way out: the runtime clamps penetration at zero,
  so the depth scale never counts a standoff behind her lips. The old `anatomy.back_out_m` row is
  retired and fixed at zero.
- `track()` takes measured penetration in metres and places the tip exactly that far past her
  lips. The attached aim pulls his pelvis to `opening - normal × (shaft - penetration)`; the
  sliding aim puts the tip there; the bed holder sits `shaft - penetration` behind her. The
  applied value is eased by `PENETRATION_SMOOTH_S = 0.06 s`.
- The act writes the part's per-frame aim through `set_aim(normal, opening, pitch)` and the
  missionary slide through `set_bed_inset(metres)`. `bed_inset_m` comes from the act's
  once-per-act `part_inset_m`; a live debug edit applies at the next act.
- Her opening's outward normal is the anatomy mesh's own rear (+Z). The V2 mesh authors the vulva
  on that axis and the coat shader reads the same `vulva_out`, so the mesh is authoritative; a
  body fit, a shape or a body swap may move the hips reference but cannot reverse the authored
  mesh. `_compute_normal()` uses `pony_hips` only when the mesh rear is degenerate. In **Enable
  debug**, the act logs `anatomy aim` every two seconds with the normal, hole, rear, hips, part
  root, hip offset, form fit id, body scale and penetration.
- The hip-offset handshake is two-way: the part publishes `hip_offset_wanted` and accepts
  `hip_offset_applied` after the pose moves his pelvis. `root_natural()` returns the pivot with
  the applied offset removed, so a placement can measure where the part sits without the last
  pose. `reset_pelvis()` clears the applied/wanted offset, the aim, the bend and the smoothed
  penetration without touching the mesh, the act's throb or the act state; the body swap's resume
  and the standing start call it through the service.
- A standing start does not fit Anon's whole body. `act/frame.gd:begin()` places him at her gap on
  her centreline, using the body form's entrance back offset as one of its inputs, and clears the
  old handshake (`player_reset_pelvis()`) so the first act tick starts from a clean stance. The
  per-frame aim then moves only his pelvis for the stroke; `refit()` repeats the placement on a new
  body. The bed view's head clearance is another frame input: the clearance over her skull and
  muzzle radii comes from the plan, and the live view enforces it.
- `reset_state()` also clears the offset, aim, bend, squash, shader squish, throb, bed inset and the
  smoothed penetration, so a following act never inherits the previous transform. A closing world
  removes the player body, and the part with it, from the tree before `world_closed` reaches the
  facade, so the part never reads a mesh world transform outside the tree: that reset only collects
  the bed holder, and the next `prepare()` or encounter rebuilds a detached part on the current
  body.
- `poses/missionary_anon.gd` adds the act-only `bed_inset_m` to `part_front_m` for the bed pose. The
  part is fully reset by `encounter(false)` and `encounter(true)`.
- `shaft_length_m()` is the visible placed length; the runtime's penetration reach is
  `shaft length - pelvis gap`. With the anatomy off the runtime uses `NOMINAL_SHAFT_M = 0.20`.
  The body-slap skin gap is measured from this same reach, so `Pelvis gap` already counts as
  distance and is never double-counted against the body slap's true-contact gate.

## Tail seating

- The seat moves every adult mare's hair tail base to the game's exact reference anchor from
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
  trim rather than stacking on it. The shipped row (`settings/characters.json` →
  `anatomy.placement.<id>`) is the mod's tuned seat and may differ from the stock
  `tail_seat_trims.json` table; `tail_tilt_deg` is mod-only.
- `profile.participation.tail` gates the seat. A `false` value skips the attach and restores the
  row if the seat was already applied; `refresh_all()` re-checks the row. A provider's `eligible`
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
  near/far bakes ignore it by name. A restore returns the original parent, local transform,
  skeleton path, skin, mesh and material, and strips the game's `parked_skeleton` meta.
- The seat is measured once on the live pony with `dock_tail_mount.measure()`. The original hair
  `pelvis_offset`, dock mesh, skin, material and tail material are cached before the first write,
  so a restore returns the game's tail and dock exactly. The far-mesh identity cache is
  invalidated, and a currently shown far mesh is forced back to the near mesh for the next bake.
- `attach()` measures and seats every eligible pony. A settings tick re-resolves each live row's
  placement and dock style, and never re-measures her.
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
- The seat row keeps the presented form and its fit. `attach(pony, form)` and
  `refresh_form(pony, form)` resolve the placement row by `form.fit_id`; a revised fit updates the
  row and re-seats the tail and dock, and a form with a `tail_root` returns the tail to its
  provider. The anatomy binding's unbind calls `release()` so a body that stays in the tree drops
  the old fit's seat. A row with no form keeps the legacy body-fit fallback.
- A new tail mesh alone cannot change the seat: `hybrid_tail_anchor` re-pins the first 12 mm of the
  tail root to the hair `mPelvis`, and the hair link places `mPelvis` from the tail mount. Author a
  new tail only for shape or silhouette; the seat remains this controller's job.
- The seat is the game hair-tail/dock path only. A visible tail that is not on either game
  skeleton is owned by the body source that brings it; the changelings adapter puts an
  `UnfplapTailPlacement` wrapper above Queen Chrysalis's spring chain and applies the resolved
  `tail_y`/`tail_z`/`tail_tilt_deg` from the modelled root, the same rule the seat uses from its
  reference dock. Her provider placement carries her own tail reference, so the global tail
  default does not move her spring tail. The wrapper is not a seat row and has no dock.
  `docs/poses.md` owns how the act modifiers rotate and restore the chain itself, so a placement
  edit and an act never overwrite each other. The Anatomy editor's
  tail actions accept a source-owned tail through `can_place_tail()` and forward
  `PONIES.body_change.apply_tail_placement()`; a dock action still answers `no dock on this tail.` The princesses'
  fitted bodies keep their body-rig tail and have no seat or wrapper.

The per-pony seat state is the inner `SeatRow` class: the pony, the stable id, the presented form
and its fit, the cached originals, the measured anchor and cap, the five live placement values and
the seat/attached/build/applied state. `_prepare()` returns a row or null. `row.target(reference)`
is the one reference-plus-tail-trim math used by the tail write and the report, so the seat keeps
one target rule.

## Lifecycle

- Scope: world + per-act handles
- Constructed by: the entry's service list (`_build_services()`)
- Begin: `on_world(host)`/`begin_act(pony, view, bed_frame)`
- End: `on_world_closed()`/`shutdown()`, or the act handle's `end()`
- Idempotent: yes


## Settings

The declarations are in `settings/service.gd` and their values in `settings/settings.json`; each
declaration's `##` comment describes its row, so no label, hint or bound is repeated here. This
section is the anatomy-specific behaviour. `SETTINGS.anatomy_on()` is the one gate the mode drives.

The frame-path values are snapshotted: the coat-line and draw toggles, the anatomy mode, the
grip/aim/scale tuning, the placement trims and the part standoff are read on `setup()`,
`apply_live()` or the visibility poll. A live edit applies at that refresh; `part_inset_m` applies
at the next act. The wink burst shape/timing and the action feature flags stay event-time reads.
`estrus/service.gd` is the only reader of `features.estrus_cycle`, `anatomy.wink_min_s`,
`anatomy.wink_max_s` and `anatomy.heat_rest_open`; it snapshots them on world enter and on a
settings change.

- While the mode is `never` the settings page dims and disables every Anatomy row below the pill.
- The old `show_dock` and `dock_color` keys migrate into the dock style in that order, with a
  hidden dock winning over its colour.
- The anatomy placement block is `anatomy.placement.default.*` (hidden: only the Placement actions
  write it), `anatomy.placement.anon.*` (the player part's visible Debug rows) and the sparse
  `anatomy.placement.<id>.*` override; `anatomy.placement_target` is the editor's target.
- Her **Teat size** is a per-mare preference, not a setting: it lives in her Characters profile
  (`docs/preferences.md`) and applies the next time she appears.
- The VR standing act always starts on a headset; the old `features.anatomy_vr` switch is retired.
- The garment-hull rows are unbounded debug values; their behaviour is `docs/integrations.md`
  (`## Pantyhose & Panties`).

## Debug and performance

- Anatomy debug actions live in the Anatomy tab's Debug block:
  **Placement** (anatomy), **Placement tail**, **Placement dock**, **Placement tail tilt** and
  **Placement file**. They write the selected target immediately; **Reset** returns the Default
  block to its shipped values, or drops the pointed mare's override. **Placement file Show** logs
  every live mare's anchor, target, resolved placement, applied delta and source; a source-owned
  tail logs its applied wrapper offset instead.
- **Hide tails** is the persisted Debug toggle that collapses every loaded AI character's hair
  and body tail roots through `anatomy/tail/hide.gd`; it touches no other body part. The facade
  pushes the switch to `anatomy/tail/visibility.gd`, which processes only while it is on.
- `anatomy.draw_still_zones` (**Draw still zones**) overlays the still-zone ellipsoid and its
  fully-still core on the body coat.
- `anatomy.coat_line` (**Coat line**) enables the hind-leg line bend. Off keeps the anatomy rigid
  and hides the debug overlay.
- `anatomy.draw_coat_line` (**Draw coat line**) overlays the sampled rest and live coat lines and
  their cross-section markers. Live segments warm up when stretched and cool down when
  compressed.
- **Show skeleton overlay** (`anatomy.skeleton_overlay`) is a persisted Anatomy → Debug flag. It
  draws nearby ponies' body, face and hair/tail skeletons only while **Enable debug** is on; click
  a joint to print its bone data. The overlay itself is `debug/skeleton.gd`; see `docs/debug.md`.
- **Force/Clear heat** and **Force/Clear diestrus** are the cycle debug actions; their effect on
  the idle heat display is described in `## Idle heat`. The cycle owner is
  `docs/eligibility.md`.
- With **Enable debug** and **Print perf logs** on, the anatomy contributes the
  `anatomy_process`, `anatomy_visibility`, `anatomy_tick`, `anatomy_coat_line` and
  `anatomy_afterglow` chunks to the profiler's block, plus `tail_attach` and `tail_refresh` when
  the tail seat builds. The act's per-frame anatomy call is `anatomy_stage`; estrus adds
  `estrus_tick`. The seat also prints
  `tail perf refresh` and a once-per-second
  `tail perf seats=… skinned=… builds=…/s` line; steady state is `builds=0/s` because the dock
  blend runs on the GPU. The seat's own `_process` returns on the profiler's switch, so it costs
  nothing in a normal session.
- The mesh and material debug helpers (`body_coat_mesh()`, `body_coat_material()`,
  `body_outline_material()`, `body_coat_targets()`, `is_attached()`) exist so the runtime can
  re-add the patched rig and merged-near materials to the game's jiggle target list.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/game.gd` | service dependency |
| shared | anatomy_placement | `shared/anatomy_placement.gd` | placement schema and merge |
| shared | body_coat | `shared/body_coat.gd` | shared data |
| shared | body_form | `shared/body_form.gd` | shared data |
| shared | body_profile | `shared/body_profile.gd` | shared data |
| shared | log | `shared/log.gd` | log sink |
| shared | perf | `shared/perf.gd` | one profiler |
| shared | pony_id | `shared/pony_id.gd` | shared data |
| shared | preferences | `shared/preferences.gd` | profile schema and math |
| shared | settings_change | `shared/settings_change.gd` | settings change notification |

## Tests

Current suites:

- `tests/anatomy/test_identity.gd`: the legacy princess body profile accessors, the profile of the
  body a pony is wearing, the body-fit key (metadata, then `character_id`, then the identity id)
  and the off-roster list; the stable id is `tests/test_pony_id.gd`. The typed rig mapping and the
  default form are `tests/body_change/test_service.gd`; the adult capability is tested with the
  eligibility service in `tests/eligibility/`.
- `tests/anatomy/test_teats.gd`: the generated teat size curve (monotonic and clamped), the build
  guards, the mare-rest to her-rest fit (identity for the mare, Celestia's scale and 7.59 cm back
  offset) and the body-profile key.
- `tests/anatomy/test_geometry.gd`: the lip-radius rule, the body-local mapping, the still-zone
  radius, the V2 anal ring weights/centre, the coat line targets/bend/frames and the shader
  sample-count sync.
- `tests/anatomy/test_shape_drive.gd`: the hole/oral mix, the shared shape drive and the wink
  scheduler.
- `tests/anatomy/test_oral_turn.gd`: the mouth/contact provider returns her mouth point and the
  base opening, follows the player's size scale, holds and clears the `D` viseme, and carries no
  turn, mix, facing or pose-key state.
- `tests/anatomy/test_api.gd`: the public entry, the caller-owned read models, the safe absent
  handles and the act target gates.
- `tests/act_facts/test_act_facts.gd`: the `shared/act_facts.gd` read model, its host callbacks and
  its defaults.
- `tests/estrus/test_estrus.gd`: the phase override, the static read and the tracked schedule.
- `tests/anatomy/test_afterglow_track.gd`: the afterglow keeps the attached part alignment and the
  live opening aim, follows the pose view's mouth anchor while the contact holds, returns to the
  opening once it is released, and clears the missionary inset outside the bed pose.
- `tests/anatomy/test_placement.gd`: the placement resolution (player override → provider → shipped
  row → default), the body-fit key, the stable id, the default/override save, the legacy migration,
  the placement editor delegation, the tail-seat row integration, the form fit row refresh and the
  debug tail collapse.
- `tests/anatomy/test_part.gd`: the player part's prepare/encounter, the tip and root, the bed
  holder, `reset_state`, the throb/girth/length shaping, the controller's part handle and track
  forward, the face contact's parked part and restored opening, the act wink scheduler, the
  anatomy rear as the authoritative outward normal, and the body-swap pelvis reset.
- `tests/anatomy/test_coat.gd`: the refined winking mesh, the V2 anal keys, the rig and near-palette
  shader patch, the base/cutout/occlusion hook injection, the drawn coat choice over a hidden game
  body, the vulva cut, the still zone, the material rebuild after a mesh re-set, the form rig/fit
  appearance refresh, the fold-colour scoping and the cached entrance point (one deformation per
  body revision, the live transform, the live hole point's per-call deformation).
- `tests/anatomy/test_heat.gd`: the rest shape, one idle wink burst and the act suppression; the
  schedule half is `tests/estrus/test_estrus.gd`.
- `tests/anatomy/test_attach.gd`: the stable id, the presented default form, one controller per
  body, a revised form, and the withdraw path. The eligibility gates are in the roster and
  `tests/ponies/test_service.gd`; the body binding chain is `tests/body_change/test_service.gd`;
  the source-owned tail wrapper is `tests/integrations/test_changelings.gd`; the VR callables are
  `tests/test_vr_act.gd`.
- `tests/anatomy/test_dock_attach.gd`: the dock's two-bind skin and bind math.
- `tests/anatomy/test_dock_seat.gd`: the dock base ring stays at or inside `rump_z - 4 mm`.
- `tests/integrations/test_pantyhose.gd`: the garment hull builder, the transform mapping and the
  world adapter's surface overrides and act-start undress.

All anatomy suites live under `tests/anatomy/`. Pure tests must not instantiate a scene or read
private controller state; facade tests use documented accessors and fakes. The internal act
exposes read-only diagnostics for its own suite: `face_parted()`, `anal_turned()`,
`contact_point()`, `contact_normal()`, `wink_left()` and `wink_beats()`. `heat.suppressed()`,
`shapes.apply_anal_local()` and `shapes.state()` are the shape/heat diagnostics the pure modules
keep for their suites.

## Known limits

- The anatomy is per-pony and attaches after the pony enters the tree; a mod that assigns the
  identity a frame later is caught by the deferred `act/session.gd:refresh_identity()` retry. The
  service keeps that timing.
- The rig coat material is shared between ponies of one identity. A per-pony copy and its outline
  must stay owned by the anatomy; removing the copy would make one mare's still zone move every
  copy of that body.
- The dock's far-mesh bake and the parked skeleton are sensitive to its parent. It must stay under
  the hair skeleton; moving it under the body remaps its skin onto body bones.
- The body-coat patch depends on the game shader keeping `flank_jiggle.gdshaderinc` and
  `VERTEX += flank_jiggle(VERTEX);`. A game update that removes either hook disables the patch,
  not the whole anatomy. A missing `void fragment()` keeps the deform but drops the vulva cut.
- The coat line depends on the `pony_hips` bone and the hind-leg tip bones. A body without the
  pelvis bone stays rigid; a missing leg tip leaves the line straight. It must read the skeleton
  inside `skeleton_updated`; a read from `_process` sees the unmodified pose and drops every
  modifier-driven stretch or fidget. The act's hole point and normal use the same frames as the
  shader, so the shaft tracks the visible opening.
- The princesses' fitted bodies have no hair skeleton; their tail seat is unavailable and their
  pre-hidden dock stays hidden.
- Only Celestia has a hand-placed teat look (`PRINCESS_TEATS`); Luna uses the Auto size and the
  measured belly fit. The generated shape and its coat blend are verified in the lab by eye; the
  headless suites pin the size curve, the guards and the fit map, not the rendered surface.
- The generated teats need her `MareBody` mesh and skin; a body without them falls back to the old
  mare-shaped `teats.scn`, which is placed by `anatomy/body_fit.gd` and does not blend into a
  princess's own coat the same way.
- The act's idle wink and the climax pulse share one countdown; adding a second scheduler would
  make them overlap.
- The garment hull is the **rest appearance**; an idle heat wink or an act with `pantyhose_undress`
  off can open or stretch the anatomy past the cloth. The field deliberately does not include the
  act's `wink`, `anal_*` or `stretch` shapes, because the garment is removed at act start.
- The garment hull is a rear-facing depth field, not a 3D SDF: an undercut the field cannot
  represent is a deferred refinement, and the debug overlay is the way to see one. The panty
  mesh's own low resolution is a separate later concern; the mod does not tessellate it at
  runtime.
- The controller and the internal act read the activity's caller-owned read models, not a
  runtime object. `shared/act_facts.gd` belongs to the act, not anatomy.

## Boundary

- `anatomy/rig.gd` is the only anatomy file that preloads `world/game.gd`.
- No anatomy file preloads a mod service except `settings/service.gd`; no outside file preloads
  an anatomy file except `anatomy/api.gd`.
- `scripts/architecture.py --check` enforces both rules, and `scripts/test_architecture.py` pins
  an allowed and a forbidden synthetic edge.

Tests are split by concern: `tests/anatomy/test_api.gd` covers the public entry,
`test_placement.gd`, `test_part.gd`, `test_coat.gd`, `test_heat.gd` and `test_attach.gd` cover the
facade and its modules, and `tests/estrus/test_estrus.gd` covers the cycle.
