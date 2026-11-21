extends Node
## integration: per-act anatomy behaviour. It reads the act's pose view and stage, and drives the
## anatomy meshes, the Anon part and the fluid. It never touches thrust scoring or the camera.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SHAPE_DRIVE := preload("res://mods/unfplap/anatomy/act/shape_drive.gd")
const DEBUG := preload("res://mods/unfplap/anatomy/act/debug.gd")
const ORAL := preload("res://mods/unfplap/anatomy/act/oral.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")
const FLUID := preload("res://mods/unfplap/anatomy/fluid.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const WINKING_REST_OPEN := 0.6
const WINKING_OPEN_AT := 0.3
const WINKING_HUG_RATE := 45.0
const WINKING_FILL_RATE := 16.0
const WINKING_STRETCH_RADIUS := 0.05
const WINKING_STRETCH_MAX := 1.4
## Climax wink: three open/close beats, applied on top of the live hug instead of a tween.
const CLIMAX_WINKS := 3.0
const CLIMAX_WINK_S := 1.35
const WINK_OPEN := 0.25
## Her own act wink beat, layered on the live shape drive.
const ACT_WINK_S := 0.5
const TOUCH_WINK_MIN_S := 4.0
const TOUCH_WINK_MAX_S := 7.0
const OUT_WINK_MIN_S := 1.0
const OUT_WINK_MAX_S := 2.0
const TOUCH_MARGIN_M := 0.02
const HOLE_SWAP_S := 0.9
const PULLED_OUT_PHASE := 0.35
const PONY_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)

## The act's phase values, matching `anatomy/api.gd`'s `Phase`.
const PHASE_POSING_IN := 0
const PHASE_ACTIVE := 1
const PHASE_CLIMAX := 2
const PHASE_AFTERGLOW := 3
const PHASE_RESTORE := 4

var pony: Node3D
var anatomy: CONTROLLER
var rig: RIG
var status := Callable()
## The API's act stage and pose view for this tick. The API owns the objects.
var _stage: Variant = null
var _view: Variant = null
## The controller's player-part handle.
var _part_handle: PLAYER
## Missionary part inset, read once in setup.
var _part_inset_m := 0.0
var _anal := false
var _hole_mix := 0.0
var _oral: ORAL
## True while the face contact has parked the part.
var _face_parted := false
var _fill := 0.0
var _wide := 0.0
## Climax wink: the shapes stay driven around the shaft, and this adds the open/close pulses
## on top instead of a tween that the per-frame drive would cancel.
var _wink_left := 0.0
var _wink_total := 0.0
var _wink_beats := 0.0
## True after the first climax; the wink cadence and `wink_mode` read it.
var _climaxed := false
var _act_wink_next := 0.0
var _act_wink_mode := 0
## Unit normal of the current opening, pointing out of her toward Anon.
var _normal := Vector3.ZERO
var _contact_point := Vector3.ZERO
var _contact_normal := Vector3.ZERO
var _contact_rear := Vector3.ZERO
var _debug_aim := false
var _aim_debug_left := 0.0
var _debug: DEBUG


func setup(pony_node: Node3D, anatomy_node: CONTROLLER, rig_node: RIG,
		status_callable := Callable()) -> void:
	pony = pony_node
	anatomy = anatomy_node
	rig = rig_node
	status = status_callable
	_part_inset_m = SETTINGS.part_inset_m.get_num()
	_part_handle = null
	if is_instance_valid(anatomy):
		_part_handle = anatomy.part()
	_oral = ORAL.new()
	_oral.setup(pony, anatomy, rig)
	reset()
	_debug_aim = SETTINGS.debug_mode.get_bool()
	_debug = DEBUG.new()
	_debug.setup(anatomy, anatomy)


func reset() -> void:
	_anal = false
	_hole_mix = 0.0
	_fill = 0.0
	_wide = 0.0
	_face_parted = false
	_climaxed = false
	if _oral != null:
		_oral.reset()
	_wink_left = 0.0
	_wink_total = 0.0
	_wink_beats = 0.0
	_act_wink_next = 0.0
	_act_wink_mode = 0
	if is_instance_valid(anatomy):
		anatomy.animate(0.0, 1.0)


## The pose read model for this act step. The API updates it on every view change.
func set_view(view: Variant) -> void:
	_view = view


## The act stage for this tick.
func set_stage(stage: Variant) -> void:
	_stage = stage


func set_climaxed(value: bool) -> void:
	_climaxed = value


## True while the hole mix is turned to the anal opening.
func anal_turned() -> bool:
	return _anal


## The selected opening's mix, for the presentation's frame point.
func hole_mix() -> float:
	return _hole_mix


## The face contact's parked state and the live wink countdown, for the act debug rows.
func face_parted() -> bool:
	return _face_parted


func wink_left() -> float:
	return _wink_left


func wink_beats() -> float:
	return _wink_beats


## The part target and contact normal this tick, for the debug readouts.
func contact_point() -> Vector3:
	return _contact_point


func contact_normal() -> Vector3:
	return _contact_normal


func _phase() -> int:
	return int(_stage.phase) if _stage != null else PHASE_POSING_IN


func _depth() -> float:
	return clampf(float(_stage.depth), 0.0, 1.0) if _stage != null else 0.0


func _penetration() -> float:
	return float(_stage.penetration_m) if _stage != null else 0.0


func _size_scale() -> float:
	return float(_stage.size_scale) if _stage != null else 1.0


func _family() -> String:
	return str(_view.family) if _view != null else ""


func _frame() -> String:
	return str(_view.frame) if _view != null else ""


func _contact_kind() -> String:
	return str(_view.contact_kind) if _view != null else ""


## Whether the live pose is the bed frame. The act reads it for the missionary-only part inset.
func _bed_pose() -> bool:
	return _frame() == "bed"


## True while the pose view names the mouth contact.
func _mouth_contact() -> bool:
	return _contact_kind() == "mouth"


## True in face contact, where the act parks the part.
func _face_contact() -> bool:
	return _contact_kind() == "face"


## Her vulva opening at the live hole mix.
func hole_point() -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.ZERO
	return anatomy.hole_point(_hole_mix)


## Her opening's outward normal.
func opening_normal() -> Vector3:
	return _normal


func hole_rear() -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.BACK
	return anatomy.hole_rear(_hole_mix)


## Re-assert the oral provider's mouth shape after the base game stopped her speech.
func hold_oral_mouth() -> void:
	if _oral != null:
		_oral.hold_viseme()


## The edge's `viseme` event: set the open mouth, or clear it on the contact release.
func set_oral_viseme(letter: String) -> void:
	if _oral == null:
		return
	if letter.is_empty():
		_oral.clear()
	else:
		_oral.set_viseme(letter)


## The mouth point the pose turn aims at once settled.
func oral_mouth_point() -> Vector3:
	if _oral == null:
		return Vector3.ZERO
	var point := _oral.mouth_point()
	return point if point.is_finite() else Vector3.ZERO


## Switch the presented opening. An invalid handle is a no-op.
func set_anal(anal: bool) -> void:
	_anal = anal


func _part() -> PLAYER:
	if is_instance_valid(_part_handle):
		return _part_handle
	_part_handle = null
	if is_instance_valid(anatomy):
		var handle := anatomy.part()
		if is_instance_valid(handle):
			_part_handle = handle
	return _part_handle


## The part target and contact normal for this tick.
func _contact() -> void:
	if _mouth_contact():
		var point: Vector3 = (_view.contact_target as Vector3) if _view != null \
			else Vector3.INF
		if not point.is_finite():
			point = hole_point()
		_contact_point = point
		_contact_normal = Vector3.ZERO
		_contact_rear = Vector3.ZERO
		return
	_contact_point = hole_point()
	_contact_normal = _normal
	_contact_rear = hole_rear()


## One act frame: the phase's shape drive, the part track and the debug markers.
func stage(delta: float, stage_node: Variant) -> void:
	_stage = stage_node
	if _stage == null or not is_instance_valid(anatomy) or not is_instance_valid(pony):
		return
	var mesh := anatomy.winking_mesh()
	if not is_instance_valid(mesh):
		return
	var part := _part()
	if _face_contact():
		_face_tick(delta, part)
		return
	if _face_parted:
		_face_parted = false
		if is_instance_valid(part):
			part.encounter(true)
	var phase := _phase()
	if phase == PHASE_ACTIVE or phase == PHASE_CLIMAX:
		_active_tick(delta, part, mesh)
	elif phase == PHASE_AFTERGLOW:
		_afterglow_tick(delta, part, mesh)
	else:
		_normal = _compute_normal(part)
		_contact()


func _active_tick(delta: float, part: PLAYER, mesh: MeshInstance3D) -> void:
	PERF.begin("anatomy_tick")
	var frame: Transform3D = mesh.global_transform
	var mesh_scale := maxf(frame.basis.get_scale().x, 0.001)
	var width: float = -1.0
	if is_instance_valid(part):
		width = part.girth_at(hole_point())
	if width < 0.0:
		width = _depth() * WINKING_STRETCH_RADIUS
	else:
		width /= mesh_scale
	var wide := minf(width / WINKING_STRETCH_RADIUS, WINKING_STRETCH_MAX)
	_wide = lerpf(_wide, wide, 1.0 - exp(-delta * WINKING_HUG_RATE))
	_fill = lerpf(_fill, smoothstep(0.0, WINKING_OPEN_AT, wide),
		1.0 - exp(-delta * WINKING_FILL_RATE))
	_hole_mix = SHAPE_DRIVE.hole_mix_step(_hole_mix, _anal, HOLE_SWAP_S, delta)
	if _oral != null:
		_oral.set_scale(_size_scale())
	var oral_mix := 1.0 if _mouth_contact() else 0.0
	var rearward := 1.0 - oral_mix
	var front := SHAPE_DRIVE.front(_hole_mix, oral_mix)
	_act_wink_tick(delta, part)
	var closed := SHAPE_DRIVE.closed_for(_fill, _hole_mix, oral_mix, WINKING_REST_OPEN)
	if _wink_left > 0.0:
		_wink_left = maxf(_wink_left - delta, 0.0)
		var beat := SHAPE_DRIVE.wink_beat(_wink_left, _wink_total, _wink_beats)
		closed = lerpf(closed, WINK_OPEN if closed > 0.5 else 0.85, beat)
	anatomy.set_fill(_fill)
	anatomy.drive(closed)
	var grip_world := _wide * WINKING_STRETCH_RADIUS * mesh_scale
	anatomy.set_grip(grip_world * front)
	anatomy.set_anal_grip(grip_world * _hole_mix * rearward)
	_normal = _compute_normal(part)
	_contact()
	_track_part(delta, part, mesh, _penetration())
	_aim_debug_tick(delta, part)
	if _debug != null:
		_debug.tick(part)
	PERF.end("anatomy_tick")


func _track_part(delta: float, part: PLAYER, mesh: MeshInstance3D, penetration_m: float) -> void:
	if is_instance_valid(part):
		if part.showing():
			var pivot := part.root_now()
			var tip := part.tip_world()
			var span := tip - pivot
			var length := span.length()
			if length > 0.0001:
				anatomy.set_shaft(pivot, span / length, length, part.shaft_radii(8))
		else:
			anatomy.clear_shaft()
		part.set_aim(_contact_normal, _contact_point, 0.0)
		part.set_bed_inset(_part_inset_m if _bed_pose() else 0.0)
	anatomy.player_track(_contact_point, _contact_rear,
		mesh.global_transform.basis.y.normalized(), false, penetration_m, delta,
		mesh.get_parent(), true)


## Face contact: park the part once, hold her shapes neutral, point at his mouth.
func _face_tick(_delta: float, part: PLAYER) -> void:
	PERF.begin("anatomy_tick")
	if not _face_parted:
		_face_parted = true
		if is_instance_valid(part):
			part.encounter(false)
	if is_instance_valid(anatomy):
		anatomy.set_fill(0.0)
		anatomy.set_grip(0.0)
		anatomy.clear_shaft()
		anatomy.drive(WINKING_REST_OPEN)
	var point := hole_point()
	if _view != null:
		var target: Variant = _view.contact_target
		if target is Vector3 and (target as Vector3).is_finite():
			point = target
	_contact_point = point
	_contact_normal = Vector3.ZERO
	_contact_rear = Vector3.ZERO
	PERF.end("anatomy_tick")


## Her own wink: rest beats while touching, faster ones once she has climaxed.
func _act_wink_tick(delta: float, part: PLAYER) -> void:
	if _phase() != PHASE_ACTIVE or _hole_mix >= 0.5 or _mouth_contact() or _wink_left > 0.0:
		return
	var touching := false
	if is_instance_valid(part) and part.showing():
		var tip := part.tip_center()
		touching = tip.is_finite() and tip.distance_to(hole_point()) <= TOUCH_MARGIN_M
	var mode := SHAPE_DRIVE.wink_mode(_depth(), touching, _climaxed, PULLED_OUT_PHASE)
	if mode != _act_wink_mode:
		_act_wink_mode = mode
		_act_wink_next = _wink_interval(mode)
	if mode == 0:
		return
	_act_wink_next -= delta
	if _act_wink_next > 0.0:
		return
	_act_wink_next = _wink_interval(mode)
	_start_wink(ACT_WINK_S, 1.0)


## The pure decision lives in `anatomy/act/shape_drive.gd`.
static func wink_mode(depth: float, touching: bool, climaxed: bool) -> int:
	return SHAPE_DRIVE.wink_mode(depth, touching, 1 if climaxed else 0, PULLED_OUT_PHASE)


func _wink_interval(mode: int) -> float:
	if mode == 2:
		return randf_range(OUT_WINK_MIN_S, OUT_WINK_MAX_S)
	return randf_range(TOUCH_WINK_MIN_S, TOUCH_WINK_MAX_S)


func _start_wink(seconds: float, beats: float) -> void:
	_wink_left = seconds
	_wink_total = maxf(seconds, 0.001)
	_wink_beats = beats


## The vulva plane's normal, flipped to point at Anon rather than into her.
func _compute_normal(_part: PLAYER) -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.ZERO
	var normal: Vector3 = hole_rear()
	if normal.is_finite() and normal.length_squared() > 0.000001:
		return normal.normalized()
	var fallback := Vector3.BACK
	var hips := _hips_point()
	if hips != Vector3.ZERO and fallback.dot(hole_point() - hips) < 0.0:
		fallback = -fallback
	return fallback


## Debug: one aim line every two seconds.
func _aim_debug_tick(delta: float, part: PLAYER) -> void:
	if not _debug_aim:
		return
	_aim_debug_left -= delta
	if _aim_debug_left > 0.0:
		return
	_aim_debug_left = 2.0
	if _stage == null or not is_instance_valid(pony):
		return
	var root := Vector3.INF
	var hip := Vector3.ZERO
	if is_instance_valid(part):
		root = part.root_now()
		hip = part.hip_offset_wanted()
	var scale := rig.body_scale_of(pony) if rig != null else 1.0
	var fit := BODY_FORM.default_form(pony).fit_id
	if is_instance_valid(anatomy):
		fit = anatomy.form_fit_id()
	LOG.debug("anatomy aim normal=%s hole=%s rear=%s hips=%s root=%s hip=%s fit=%s scale=%.2f pen=%.3f", [
		str(_normal), str(hole_point()), str(hole_rear()), str(_hips_point()), str(root),
		str(hip), fit, scale, _penetration()])


## Her pelvis bone in world space.
func _hips_point() -> Vector3:
	if not is_instance_valid(pony) or rig == null:
		return Vector3.ZERO
	var skeleton := rig.skeleton_of(pony)
	if not is_instance_valid(skeleton):
		return Vector3.ZERO
	var hips := skeleton.find_bone("pony_hips")
	if hips < 0:
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin


## One-shot climax: the grip releases, the pulse train starts and the fluid fires.
func climax() -> void:
	_climaxed = true
	if is_instance_valid(anatomy):
		anatomy.clear_part()
		_start_wink(CLIMAX_WINK_S, CLIMAX_WINKS)
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return
	fluid.spray(hole_point(), _hole_out(), 26, 1.0, 0.0075, PONY_FLUID_COLOR)
	fluid.drip(Callable(self, "hole_point"), 2.5, 7.0, 0.007, PONY_FLUID_COLOR)


## The held afterglow keeps the part at her entrance on the attached alignment.
func _afterglow_tick(delta: float, part: PLAYER, mesh: MeshInstance3D) -> void:
	PERF.begin("anatomy_afterglow")
	if not is_instance_valid(part) or not part.showing():
		PERF.end("anatomy_afterglow")
		return
	_normal = _compute_normal(part)
	_contact()
	part.set_aim(_contact_normal, _contact_point, 0.0)
	part.set_bed_inset(_part_inset_m if _bed_pose() else 0.0)
	anatomy.player_track(_contact_point, _contact_rear,
		mesh.global_transform.basis.y.normalized(), false, 0.0, delta,
		mesh.get_parent(), true)
	PERF.end("anatomy_afterglow")


func end() -> void:
	if is_instance_valid(anatomy):
		anatomy.animate(1.0, 1.5)
		anatomy.clear_part()
	if _oral != null:
		_oral.clear()


func teardown() -> void:
	if _debug != null:
		_debug.clear()
		_debug = null
	_stage = null
	_view = null
	_part_handle = null
	if _oral != null:
		_oral.teardown()
	_anal = false
	_hole_mix = 0.0
	_face_parted = false
	_climaxed = false


func _hole_out() -> Vector3:
	var rear := hole_rear()
	return rear + Vector3.DOWN * 0.3


func _fluid_node() -> FLUID:
	if not is_instance_valid(anatomy):
		return null
	return anatomy.fluid()
