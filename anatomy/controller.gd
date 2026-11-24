extends Node
## integration: the runtime anatomy attachment. One per adult mare, including mares added by
## other mods, persistent across acts. The mesh and textures ship with the mod.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const SHAPES := preload("res://mods/unfplap/anatomy/shapes.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const COAT_LINE := preload("res://mods/unfplap/anatomy/coat_line.gd")
const COAT_LINE_DEBUG := preload("res://mods/unfplap/anatomy/coat_line_debug.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy/placement.gd")
const APPEARANCE := preload("res://mods/unfplap/anatomy/appearance.gd")
const HEAT := preload("res://mods/unfplap/anatomy/heat.gd")
const ATTACH := preload("res://mods/unfplap/anatomy/attach.gd")
const GARMENT_HULL := preload("res://mods/unfplap/anatomy/garment_hull.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")
const FLUID := preload("res://mods/unfplap/anatomy/fluid.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/mare/"
const MARE_BITS_PATH := ASSET_DIR + "mare_bits_v2.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"

var pony: Node3D
## The anatomy's world seam, injected by the anatomy API.
var rig: RIG
## The presented body's form. Null keeps the default own form built from her identity.
var _form: BODY_FORM.BodyForm = null
## The anatomy facade's dock-colour refresh. Called after attach/detach/tone changes.
var dock_refresh := Callable()
## The status callback the API binds to its one signal. The act carries it.
var status := Callable()
## The API's player-part handle, pushed on every player rebuild. The act reads this.
var _part_handle: PLAYER
## True while the roster presents this body; `anatomy_mode` reads both flags.
var presented := true
## True from `begin_act()` until the act handle's `end()`; `act` mode hides outside it.
var act_presented := false
## The act's live pose and stage; the __init__ defaults are the outside-act presentation.
var _view: Variant = null
var _stage: Variant = null
var _act_bed_frame: Variant = null
## The fold-coloring state the live material was built with; the act's family edge rebuilds it.
var _fold_missionary := false

## The persistent mesh/anchor/dock/fluid/visibility attachment.
var attach: ATTACH
## The rig coat's runtime deform and still-zone debug.
var coat: COAT
## The anatomy shell's follow of the body coat's line.
var coat_line: COAT_LINE
## The coat line's debug overlay, parented to the anatomy mesh.
var _line_debug: COAT_LINE_DEBUG
var _line_debug_clock := 0.0
## Saved placement and the missionary trims.
var placement: PLACEMENT
## Persistent shape state: closing/winking, the grip solve, Anon's shaft mask and the V2 anal
## keys. The controller forwards its public shape API.
var shapes: SHAPES
## The current act handle; created here and freed with this controller.
var _act: ACT
## Material, skin tones, teats and the skin strip.
var appearance: APPEARANCE
var _rig_logged := false
## integration: visibility is polled, not rewritten every frame, and act-only can hide it.
var _visibility_clock := 0.0
## The frame-path toggles, read on setup/refresh/apply_live. A live edit applies there.
var _coat_line_on := false
var _draw_coat_line := false
var _anatomy_mode := ""
## Idle heat schedule; the controller supplies state, visibility and the cycle phase.
var heat: HEAT
## The cached `MareBody` for the per-frame garment transform.
var _garment_body: Node3D
## The cached local entrance point: the deformed resting hole, reused until the body is rebuilt.
var _entrance_local := Vector3.ZERO
var _entrance_ready := false
## The cached rest hull and the settings it was built for.
var _garment_hull: GARMENT_HULL.Hull
var _hull_width := 48
var _hull_height := 48
var _hull_smoothing := 1
var _hull_ponut := 0.0


func setup(pony_node: Node3D, form_node: BODY_FORM.BodyForm, rig_node: RIG,
		status_callable := Callable(), dock_refresh_callable := Callable()) -> void:
	pony = pony_node
	rig = rig_node
	_form = form_node
	status = status_callable
	dock_refresh = dock_refresh_callable
	attach = ATTACH.new()
	attach.setup(self, pony, rig)
	shapes = SHAPES.new()
	shapes.setup(pony, self)
	coat = COAT.new()
	coat.setup(pony, shapes, rig)
	placement = PLACEMENT.new()
	placement.setup(pony)
	coat_line = COAT_LINE.new()
	coat_line.setup(pony, placement)
	heat = HEAT.new()
	heat.setup(shapes)
	appearance = APPEARANCE.new()
	appearance.setup(pony, shapes, rig, dock_refresh)
	appearance.set_form(form())
	_read_hull_settings()
	_read_toggles()
	invalidate_entrance()


## The body form the controller measures from: the body-change service's form, or the default own
## form built from the pony identity when no source has claimed the body.
func form() -> BODY_FORM.BodyForm:
	if _form != null:
		return _form
	return BODY_FORM.default_form(pony)


## Store the presented form. `refresh_form()` is the write that re-applies an attached controller.
func set_form(value: BODY_FORM.BodyForm) -> void:
	_form = value
	if appearance != null:
		appearance.set_form(value)


## The fit id the aim diagnostic and the placement read; empty only for a body with no identity.
func form_fit_id() -> String:
	var current := form()
	return current.fit_id if current != null else ""


## A revised form on the same body: update the placement rig/fit and rebuild the parts that were
## fitted to the old body. The anatomy mesh is reused; the act handle is not touched.
func refresh_form(value: BODY_FORM.BodyForm) -> void:
	var previous := form()
	set_form(value)
	invalidate_entrance()
	if not is_attached():
		return
	var current := form()
	attach.mark_owned()
	if _same_rig_and_fit(previous, current):
		apply_live()
		return
	var mesh: MeshInstance3D = attach.mesh
	if not is_instance_valid(mesh):
		return
	placement.set_mesh(mesh, attach.bone_inverse, current.rig)
	placement.load(current.fit_id)
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame_value())
	if appearance != null:
		appearance.set_form(current)
		appearance.clear()
		appearance.set_mesh(mesh, attach.skeleton)
		appearance.attach_parts()
	attach.mark_owned()
	_apply_material()
	_apply_place()
	_apply_body_coat()


## True when the two forms measure the same body: the rig and the placement row are unchanged.
static func _same_rig_and_fit(a: BODY_FORM.BodyForm, b: BODY_FORM.BodyForm) -> bool:
	if a == null or b == null:
		return a == b
	if a.fit_id != b.fit_id:
		return false
	var a_rig := a.rig
	var b_rig := b.rig
	if a_rig == null or b_rig == null:
		return a_rig == b_rig
	if a_rig.id != b_rig.id or not is_equal_approx(a_rig.scale, b_rig.scale):
		return false
	return is_equal_approx(a_rig.rear_y, b_rig.rear_y) \
		and is_equal_approx(a_rig.rear_z, b_rig.rear_z)


## Create the per-act controller, owned here until `end_act()`.
func begin_act(view: Variant, bed_frame: Variant) -> ACT:
	end_act()
	_act = ACT.new()
	_act.name = "UnfplapAnatomyAct"
	add_child(_act)
	_act.setup(pony, self, rig, status)
	act_presented = true
	set_act_view(view, null, bed_frame)
	return _act


func end_act() -> void:
	act_presented = false
	if is_instance_valid(_act):
		_act.end()
		_act.teardown()
		_act.queue_free()
	_act = null
	_view = null
	_stage = null
	_act_bed_frame = null
	_sync_fold_coloring()


## The act's caller-owned pose and stage, kept by reference; the placement trim polls them.
func set_act_view(view: Variant, stage: Variant, bed_frame: Variant = null) -> void:
	_view = view
	_stage = stage
	if bed_frame is Transform3D:
		_act_bed_frame = bed_frame
	_sync_fold_coloring()


## The service owns the player part; this handle is the one seam the act reads. A rebuild pushes
## the new node, and an invalid one reads as absent.
func set_part(node: PLAYER) -> void:
	_part_handle = node if is_instance_valid(node) else null


func part() -> PLAYER:
	return _part_handle if is_instance_valid(_part_handle) else null


## Forward the act's per-tick part track to the live handle.
func player_track(target: Vector3, rear: Vector3, up: Vector3, bed: bool,
		penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
	var handle := part()
	if is_instance_valid(handle):
		handle.track(target, rear, up, bed, penetration_m, delta, mare_anchor, attached)


func refresh() -> void:
	_read_toggles()
	if not _enabled():
		detach()
		return
	_attach()


func _enabled() -> bool:
	return SETTINGS.anatomy_on()


## The frame-path toggles. `apply_live()` and the 0.2 s poll read these fields; `_process` never
## reads Settings.
func _read_toggles() -> void:
	_coat_line_on = SETTINGS.coat_line.get_bool()
	_draw_coat_line = SETTINGS.draw_coat_line.get_bool()
	_anatomy_mode = SETTINGS.anatomy_mode.get_choice()


func _attach() -> void:
	_read_toggles()
	if is_attached():
		apply_live()
		return
	if not is_instance_valid(pony):
		return
	if not attach.attach(MARE_BITS_PATH):
		if not _rig_logged:
			_rig_logged = true
			LOG.debug("anatomy skipped for %s: %s", [pony.name, attach.last_error])
		return
	var mesh: MeshInstance3D = attach.mesh
	var refined := GEOMETRY.refined_winking_mesh(mesh.mesh as ArrayMesh)
	if refined != null:
		mesh.mesh = refined
	var current := form()
	placement.set_mesh(mesh, attach.bone_inverse, current.rig)
	placement.load(current.fit_id)
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame_value())
	shapes.set_mesh(mesh)
	coat.set_mesh(mesh, attach.skeleton)
	coat_line.setup(pony, placement)
	coat_line.set_mesh(mesh, attach.skeleton)
	_ensure_line_debug()
	appearance.set_form(current)
	appearance.set_mesh(mesh, attach.skeleton)
	appearance.attach_parts()
	attach.mark_owned()
	_apply_material()
	if not coat_line.rebuild():
		LOG.debug("coat line skipped: %s", [str(coat_line.last_error)])
	else:
		LOG.debug("coat line built %s", [str(coat_line.summary())])
	set_process(true)
	attach.apply_visibility(_act_visible())
	_apply_body_coat()
	invalidate_entrance()
	LOG.debug("anatomy attached lift=%.3f", [PLACEMENT.LIFT])


func _process(delta: float) -> void:
	if coat == null or placement == null or coat_line == null or attach == null:
		return
	PERF.begin("anatomy_process")
	coat.tick()
	coat.tick_debug()
	placement.tick(_missionary_pose(), _pose_depth(), _bed_frame_value())
	PERF.begin("anatomy_coat_line")
	coat_line.set_enabled(_coat_line_on)
	coat_line.tick(attach.visible())
	PERF.end("anatomy_coat_line")
	_tick_line_debug(delta)
	_visibility_clock -= delta
	if _visibility_clock > 0.0:
		PERF.end("anatomy_process")
		return
	_visibility_clock = ATTACH.VISIBILITY_POLL_S
	_apply_place()
	shapes.refresh_anal()
	PERF.begin("anatomy_visibility")
	attach.apply_visibility(_act_visible())
	PERF.end("anatomy_visibility")
	# After visibility, so the vulva coat cut opens and closes with the mesh in the same poll.
	_apply_body_coat()
	PERF.end("anatomy_process")


## integration: the visibility pill. `always` shows whenever presented; `act` shows from
## `begin_act()` until the act handle's `end()`.
func _act_visible() -> bool:
	match _anatomy_mode:
		"always":
			return presented
		"act":
			return presented and act_presented
	return false


## The estrus service's resting openness; the shape module owns the tween.
func set_rest(open: float) -> void:
	if heat != null:
		heat.set_rest(open)


## The act-only placement trim. The lying missionary pose tilts her pelvis, so the rigged vulva can
## sit a little high/low or face the wrong way; these values move only the anatomy mesh.
func _missionary_pose() -> bool:
	return _view != null and str(_view.family) == "bed"


func _pose_depth() -> float:
	return clampf(float(_stage.depth), 0.0, 1.0) if _stage != null else 0.0


func _bed_frame_value() -> Variant:
	return _act_bed_frame


func _apply_place() -> void:
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame_value())


func _apply_material() -> void:
	_fold_missionary = _missionary_pose()
	if appearance != null:
		appearance.apply_material(_fold_missionary)
	if coat_line != null and appearance != null:
		coat_line.set_material(appearance.material())


## The fold hack is per material build, so only the act's family edge rebuilds it, never a tick.
func _sync_fold_coloring() -> void:
	if _missionary_pose() == _fold_missionary or not is_attached():
		return
	_apply_material()


## The coat line's debug overlay is a child of the anatomy mesh, so it shares the mesh's local
## space and hides with it. Created once per attachment.
func _ensure_line_debug() -> void:
	if is_instance_valid(_line_debug):
		return
	if not is_attached() or not is_instance_valid(attach.mesh):
		return
	_line_debug = COAT_LINE_DEBUG.new()
	_line_debug.name = "UnfplapCoatLine"
	attach.mesh.add_child(_line_debug)
	_line_debug.setup()
	_line_debug_clock = 0.0


## Redraw the debug line at 30 Hz while its debug flag is on and the mesh is shown.
func _tick_line_debug(delta: float) -> void:
	if not is_instance_valid(_line_debug):
		return
	if not _draw_coat_line or not coat_line.is_enabled() \
			or not is_attached() or not is_instance_valid(attach.mesh) or not attach.visible():
		_line_debug.update({}, false)
		_line_debug_clock = 0.0
		return
	_line_debug_clock -= delta
	if _line_debug_clock > 0.0:
		return
	_line_debug_clock = 1.0 / 30.0
	_line_debug.update(coat_line.debug_data(), true)


## The attach module computes the mesh/dock visibility; the controller owns the teats and strip
## parts, which live in the appearance module.
func apply_part_visibility(show: bool, teats_on: bool, strip_on: bool) -> void:
	if appearance != null:
		appearance.apply_visibility(show, teats_on, strip_on)


func is_attached() -> bool:
	return attach != null and attach.is_attached()


func body_coat_mesh() -> MeshInstance3D:
	return coat.body_mesh() if coat != null else null


func body_coat_material() -> ShaderMaterial:
	return coat.body_material() if coat != null else null


func body_outline_material() -> ShaderMaterial:
	return coat.body_outline_material() if coat != null else null


func body_coat_targets() -> Array:
	return coat.targets() if coat != null else []


## Public coat refresh for the runtime's jiggle fallback.
func body_coat_refresh() -> void:
	_apply_body_coat()


## Patch the drawn coat: rig or merged near, whichever is visible.
func _apply_body_coat() -> void:
	coat.apply()


## integration: a mesh modelled on the shared mare body and skinned with her own weights.
func apply_live() -> void:
	if not is_attached():
		return
	_read_toggles()
	placement.read_settings()
	shapes.read_settings()
	if SETTINGS.placement_revision != placement.revision():
		placement.load()
	_read_hull_settings()
	_apply_material()
	_apply_place()
	shapes.refresh_anal()
	attach.apply_visibility(_act_visible())
	_apply_body_coat()


func detach() -> void:
	end_act()
	invalidate_entrance()
	if is_instance_valid(_line_debug):
		_line_debug.update({}, false)
	_line_debug = null
	_line_debug_clock = 0.0
	if coat_line != null:
		coat_line.clear()
	if coat != null:
		coat.clear_mesh()
	if placement != null:
		placement.clear_mesh()
	if appearance != null:
		appearance.clear()
	if shapes != null:
		shapes.clear_mesh()
	if attach != null:
		attach.detach()
	_garment_body = null
	_garment_hull = null
	set_process(false)
	if dock_refresh.is_valid():
		dock_refresh.call(pony)


# --------------------------------------------------------------------------- garment hull

## The worn-garment depth field for the refined anatomy mesh; null when detached.
## No per-frame settings read: width, height and smoothing are read on setup/apply_live.
func garment_hull() -> GARMENT_HULL.Hull:
	if not is_attached() or not is_instance_valid(attach.mesh):
		return null
	var mesh := attach.mesh.mesh as ArrayMesh
	if mesh == null:
		return null
	if _garment_hull != null:
		return _garment_hull
	_garment_hull = GARMENT_HULL.build(mesh, _hull_width, _hull_height, _hull_smoothing,
		_hull_ponut)
	return _garment_hull


## Drop this controller's cached hull so the next read rebuilds with the current settings.
func garment_hull_clear() -> void:
	_garment_hull = null


func _read_hull_settings() -> void:
	var width := int(SETTINGS.pantyhose_hull_width.get_num())
	var height := int(SETTINGS.pantyhose_hull_height.get_num())
	var smoothing := int(SETTINGS.pantyhose_hull_smoothing.get_num())
	var ponut := SETTINGS.anal_scale.get_num() - 1.0
	if width == _hull_width and height == _hull_height and smoothing == _hull_smoothing \
			and is_equal_approx(ponut, _hull_ponut):
		return
	_hull_width = width
	_hull_height = height
	_hull_smoothing = smoothing
	_hull_ponut = ponut
	_garment_hull = null


## Map an anatomy-local point into the garment's model space, the body's rest space.
## The body is cached, so this stays cheap on the every-frame path.
func garment_transform() -> Transform3D:
	if not is_attached() or not is_instance_valid(attach.mesh):
		return Transform3D.IDENTITY
	if not is_instance_valid(_garment_body):
		_garment_body = null
		if is_instance_valid(pony):
			_garment_body = rig.body_of(pony)
			if _garment_body == null:
				_garment_body = pony
	return garment_transform_for(_garment_body, attach.mesh)


## True only while the poll shows the mesh; a hidden mesh leaves the cloth alone.
func garment_visible() -> bool:
	return is_attached() and is_instance_valid(attach.mesh) and attach.visible()


## The mesh the hull field is built in.
func garment_parent() -> Node3D:
	return attach.mesh if is_attached() and is_instance_valid(attach.mesh) else null


## The pure transform mapping, so the tests can pin it without a live attachment.
static func garment_transform_for(body: Node3D, mesh: Node3D) -> Transform3D:
	if not is_instance_valid(body) or not is_instance_valid(mesh):
		return Transform3D.IDENTITY
	return body.global_transform.affine_inverse() * mesh.global_transform


## A millimetre margin in anatomy-local units; the basis' Z scale converts the push back.
static func garment_margin_local(transform: Transform3D, millimetres: float) -> float:
	var scale := (transform.basis * Vector3(0.0, 0.0, 1.0)).length()
	return (millimetres / 1000.0) / maxf(scale, 0.0001)


func winking_mesh() -> MeshInstance3D:
	return shapes.winking_mesh()


## integration: one persistent fluid node per pony, reused by every act.
func fluid() -> FLUID:
	return attach.fluid() if attach != null else null


## Idle heat discharge: drops leave the vulva on a wink burst.
func idle_discharge(count: int) -> void:
	if attach != null:
		attach.idle_discharge(count)


func hole_local(mix: float) -> Vector3:
	return shapes.hole_local(mix)


## The act and fluid anchors follow the anatomy's coat line. The shader moves the visible
## opening; these two use the same frames so the shaft, droplets and drips stay on it.
func hole_point(mix := 0.0) -> Vector3:
	var mesh: MeshInstance3D = shapes.winking_mesh()
	if not is_instance_valid(mesh) or coat_line == null:
		return shapes.hole_point(mix)
	var local: Vector3 = shapes.hole_local(mix)
	local = coat_line.deform_point(local)
	return mesh.global_transform * local


## The scan's resting entrance anchor: one deformed local point, mapped by the live mesh.
func entrance_point() -> Vector3:
	var mesh: MeshInstance3D = shapes.winking_mesh()
	if not is_instance_valid(mesh):
		return shapes.hole_point(0.0)
	if not _entrance_ready:
		if coat_line == null:
			return shapes.hole_point(0.0)
		_entrance_local = coat_line.deform_point(shapes.hole_local(0.0))
		_entrance_ready = true
	return mesh.global_transform * _entrance_local


## Drop the cached entrance: the mesh or the body was rebuilt.
func invalidate_entrance() -> void:
	_entrance_ready = false


func hole_rear(mix := 0.0) -> Vector3:
	var mesh: MeshInstance3D = shapes.winking_mesh()
	if not is_instance_valid(mesh) or coat_line == null:
		return shapes.hole_rear(mix)
	var local: Vector3 = coat_line.deform_direction(Vector3.BACK)
	return (mesh.global_basis * local).normalized()


func set_closed(value: float) -> void:
	shapes.set_closed(value)


## Idle heat crossfade: 0 is resting closed, 1 is the authored open shape.
func set_idle_wink(amount: float) -> void:
	shapes.set_idle_wink(amount)


func drive(closed: float) -> void:
	shapes.drive(closed)


func animate(target: float, seconds: float) -> void:
	shapes.animate(target, seconds)


func wink(count := 1, seconds := 0.45) -> void:
	shapes.wink(count, seconds)


## Idle heat wink. The shape module owns the tween; the first beat's peak releases the droplets.
func wink_burst(count: int) -> void:
	if heat == null or act_presented:
		return
	heat.wink_burst(count, Callable(self, "idle_discharge"))
	_apply_body_coat()


## Open the lips to the shaft's actual radius. The shape module converts world metres to mesh
## units and applies the hug padding.
func set_grip(shaft_radius: float) -> void:
	shapes.set_grip(shaft_radius, _missionary_pose())
	_apply_body_coat()


func set_shaft(pivot: Vector3, axis: Vector3, length: float, radii: PackedFloat32Array) -> void:
	shapes.set_shaft(pivot, axis, length, radii)


func clear_shaft() -> void:
	shapes.clear_shaft()


## The lip band's mean radius in local units, used by the grip solve and by tuning readouts.
func lip_radius() -> float:
	return shapes.lip_radius()


func set_fill(fill: float) -> void:
	shapes.set_fill(fill)


## Drive the V2 anal blend shapes from the real shaft radius.
func set_anal_grip(shaft_radius: float) -> void:
	shapes.set_anal_grip(shaft_radius)


func react() -> void:
	shapes.react()


func clear_part() -> void:
	shapes.clear_part()
	_apply_body_coat()


