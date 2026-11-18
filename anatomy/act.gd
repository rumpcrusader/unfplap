extends Node
## integration: per-act anatomy behaviour. It reads the
## current act depth, the pose view's contact and drives the anatomy meshes, the Anon part and the
## fluid. It never touches thrust scoring, auto thrust or the camera.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const STATE := preload("res://mods/unfplap/anatomy/act/state.gd")
const DEBUG := preload("res://mods/unfplap/anatomy/act/debug.gd")
const ORAL := preload("res://mods/unfplap/anatomy/act/oral.gd")

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
## Her own wink during the act: one quiet beat while the tip rests at her lips, and a frequent
## beat once a climax has been pulled out of her. The tip counts as touching within this margin.
const ACT_WINK_S := 0.5
const TOUCH_WINK_MIN_S := 4.0
const TOUCH_WINK_MAX_S := 7.0
const OUT_WINK_MIN_S := 1.0
const OUT_WINK_MAX_S := 2.0
const TOUCH_MARGIN_M := 0.02
const HOLE_SWAP_S := 0.9
const PULLED_OUT_PHASE := 0.35
const PONY_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)

var pony: Node3D
var anatomy: Node
var consent := Callable()
var status := Callable()
var _display_name := ""
## The bridge's typed act context, kept across ticks. The act never allocates or reads the runtime.
var _facts: RefCounted = null
## The controller's player-part handle. The act reads the anatomy it was given, never the facade.
var _part_handle: Node
## The missionary part inset, read once per act. A live debug edit applies at the next act.
var _part_inset_m := 0.0
var _anal := false
var _hole_mix := 0.0
var _oral: RefCounted
## True while the face contact has parked the part: his body owns the contact placement and her
## opening is left neutral. The first face tick parts it; the first opening tick restores it.
var _face_parted := false
var _fill := 0.0
var _wide := 0.0
## Climax wink: the shapes stay driven around the shaft, and this adds the open/close pulses
## on top instead of a tween that the per-frame drive would cancel.
var _wink_left := 0.0
## The beat's own length and count, so the climax pulse and her act wink share one countdown.
var _wink_total := 0.0
var _wink_beats := 0.0
## Her act wink scheduler: seconds to the next beat, and the mode those seconds were measured in.
var _act_wink_next := 0.0
var _act_wink_mode := 0
## Unit normal of the current opening, pointing out of her toward Anon.
var _normal := Vector3.ZERO
## The part target for this tick: her mouth while the pose view names the mouth contact, her
## opening otherwise. Filled in place so the per-frame path allocates nothing.
var _contact_point := Vector3.ZERO
var _contact_normal := Vector3.ZERO
var _contact_rear := Vector3.ZERO
var _debug: RefCounted


func setup(pony_node: Node3D, anatomy_node: Node,
		consent_callable := Callable(), status_callable := Callable()) -> void:
	pony = pony_node
	anatomy = anatomy_node
	consent = consent_callable
	status = status_callable
	_part_inset_m = SETTINGS.part_inset_m.get_num()
	_part_handle = null
	if is_instance_valid(anatomy) and anatomy.has_method("part"):
		_part_handle = anatomy.call("part")
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	if identity != null and identity.get("display_name") != null:
		_display_name = str(identity.get("display_name"))
	elif is_instance_valid(pony):
		_display_name = str(pony.name)
	_oral = ORAL.new()
	_oral.call("setup", pony, anatomy)
	reset()
	_debug = DEBUG.new()
	_debug.setup(anatomy, anatomy)


func reset() -> void:
	_anal = false
	_hole_mix = 0.0
	_fill = 0.0
	_wide = 0.0
	_face_parted = false
	if _oral != null:
		_oral.call("reset")
	_wink_left = 0.0
	_wink_total = 0.0
	_wink_beats = 0.0
	_act_wink_next = 0.0
	_act_wink_mode = 0
	if is_instance_valid(anatomy):
		anatomy.call("animate", 0.0, 1.0)


func _state() -> int:
	return int(_facts.state) if _facts != null else 0


func _depth() -> float:
	return clampf(float(_facts.depth), 0.0, 1.0) if _facts != null else 0.0


func _climaxes() -> int:
	return int(_facts.climaxes) if _facts != null else 0


## The per-act contact view the runtime refreshed this tick.
func _pose_view() -> Variant:
	return _facts.pose_view if _facts != null else null


## Whether the live pose is the bed frame. The act reads it for the missionary-only part inset and
## owns no start pose id.
func _bed_pose() -> bool:
	return _facts != null and _facts.bed_pose()


## True while the pose view names the mouth contact. The pose service owns the contact switch;
## the act only reads it.
func _mouth_contact() -> bool:
	return _facts != null and _facts.mouth_contact()


## True while the pose view names the face contact. The act parks the part; the pose's face driver
## owns the contact placement.
func _face_contact() -> bool:
	return _facts != null and _facts.face_contact()


## Her vulva opening at the live hole mix.
func hole_point() -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.ZERO
	return anatomy.call("hole_point", _hole_mix)


## Her opening's outward normal: the mesh's own +Z, flipped if needed so it points at Anon. This
## avoids every guess about which way the anatomy mesh was authored.
func opening_normal() -> Vector3:
	return _normal


func hole_rear() -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.BACK
	return anatomy.call("hole_rear", _hole_mix)


## Re-assert the oral provider's mouth shape after the base game stopped her speech.
func hold_oral_mouth() -> void:
	if _oral != null:
		_oral.call("hold_viseme")


## The edge's `viseme` event: set the open mouth, or clear it on the contact release.
func set_oral_viseme(letter: String) -> void:
	if _oral == null:
		return
	if letter.is_empty():
		_oral.call("clear")
	else:
		_oral.call("set_viseme", letter)


## The mouth point the pose turn aims at once settled.
func oral_mouth_point() -> Vector3:
	if _oral == null:
		return Vector3.ZERO
	var point: Variant = _oral.call("mouth_point")
	return point if point is Vector3 and (point as Vector3).is_finite() else Vector3.ZERO


func toggle_hole(state: int) -> void:
	if not SETTINGS.anatomy_holes.get_bool() or state not in [2, 3] \
			or _mouth_contact() or _face_contact():
		return
	if not is_instance_valid(anatomy) or not is_instance_valid(anatomy.call("winking_mesh")):
		return
	if not _anal and not _consent("anal"):
		_status("%s is not into that" % _display_name)
		return
	_anal = not _anal


func _part() -> Variant:
	if is_instance_valid(_part_handle):
		return _part_handle
	_part_handle = null
	if is_instance_valid(anatomy) and anatomy.has_method("part"):
		var handle: Variant = anatomy.call("part")
		if is_instance_valid(handle):
			_part_handle = handle
	return _part_handle


func _consent(key: String) -> bool:
	return bool(consent.call(key)) if consent.is_valid() else false


func _status(text: String) -> void:
	if status.is_valid():
		status.call(text)


## The point the part targets this tick. In mouth contact it is the pose turn's anchor (the
## captured opening while the turn runs, the live mouth once settled); otherwise the vulva opening
## and its resolved normal. `_normal` must be set first.
func _contact() -> void:
	if _mouth_contact():
		var view: Variant = _pose_view()
		var point: Vector3 = (view.contact_target as Vector3) if view != null \
			else Vector3.INF
		if not point.is_finite():
			point = hole_point()
		_contact_point = point
		# A zero normal makes the part auto-aim from his crotch to the mouth instead of
		# turning along the vulva plane.
		_contact_normal = Vector3.ZERO
		_contact_rear = Vector3.ZERO
		return
	_contact_point = hole_point()
	_contact_normal = _normal
	_contact_rear = hole_rear()


func tick(delta: float, facts: RefCounted) -> void:
	if facts != null:
		_facts = facts
	if _facts == null or not is_instance_valid(anatomy) or not is_instance_valid(pony):
		return
	var mesh: Variant = anatomy.call("winking_mesh")
	if not is_instance_valid(mesh):
		return
	var part: Variant = _part()
	# The face contact owns his authored mouth and parks her part: no opening shape drive, no
	# shaft, no player track, no aim writes. The hip offset the act body reads is zero because a
	# parted part reports none.
	if _face_contact():
		_face_tick(delta, part)
		return
	if _face_parted:
		_face_parted = false
		if is_instance_valid(part):
			part.call("encounter", true)
	var started := Time.get_ticks_usec()
	var frame: Transform3D = (mesh as Node3D).global_transform
	var mesh_scale := maxf(frame.basis.get_scale().x, 0.001)
	var width: float = -1.0
	if is_instance_valid(part):
		width = float(part.call("girth_at", hole_point()))
	if width < 0.0:
		width = _depth() * WINKING_STRETCH_RADIUS
	else:
		width /= mesh_scale
	var wide := minf(width / WINKING_STRETCH_RADIUS, WINKING_STRETCH_MAX)
	_wide = lerpf(_wide, wide, 1.0 - exp(-delta * WINKING_HUG_RATE))
	_fill = lerpf(_fill, smoothstep(0.0, WINKING_OPEN_AT, wide),
		1.0 - exp(-delta * WINKING_FILL_RATE))
	_hole_mix = STATE.hole_mix_step(_hole_mix, _anal, HOLE_SWAP_S, delta)
	if _oral != null:
		_oral.call("set_scale", _facts.size_scale)
	var oral_mix := 1.0 if _mouth_contact() else 0.0
	var rearward := 1.0 - oral_mix
	var front := STATE.front(_hole_mix, oral_mix)
	_act_wink_tick(delta, part)
	# The shapes stay driven through the climax too, so the lips keep their grip on the shaft
	# instead of snapping closed; the climax wink is applied on top as a pulse.
	if _state() in [2, 3]:
		var closed := STATE.closed_for(_fill, _hole_mix, oral_mix, WINKING_REST_OPEN)
		if _wink_left > 0.0:
			_wink_left = maxf(_wink_left - delta, 0.0)
			var beat := STATE.wink_beat(_wink_left, _wink_total, _wink_beats)
			closed = lerpf(closed, WINK_OPEN if closed > 0.5 else 0.85, beat)
		# The fill closes the shader's cut over the shaft; without it the hole stays fully open
		# and the lips cannot read as gripping it.
		anatomy.call("set_fill", _fill)
		anatomy.call("drive", closed)
		# Solve the lips against the real shaft radius instead of a fixed stretch constant. `_wide`
		# is the local girth ratio, so convert back to world metres here: `set_grip()` converts to
		# mesh units itself. Passing the local value made the hole ~1/scale (12 %) too large.
		var grip_world := _wide * WINKING_STRETCH_RADIUS * mesh_scale
		anatomy.call("set_grip", grip_world * front)
		# The anal ring is solved against the same real shaft radius as the vulva, so it opens to
		# exactly his girth instead of scaling a blend shape by a constant.
		anatomy.call("set_anal_grip", grip_world * _hole_mix * rearward)
	_normal = _compute_normal(part)
	_contact()
	if is_instance_valid(part):
		if bool(part.call("showing")):
			var pivot: Vector3 = part.call("root_now")
			var tip: Vector3 = part.call("tip_world")
			var span := tip - pivot
			var length := span.length()
			if length > 0.0001:
				anatomy.call("set_shaft", pivot, span / length, length,
					part.call("shaft_radii", 8))
		else:
			anatomy.call("clear_shaft")
		part.call("set_aim", _contact_normal, _contact_point, 0.0)
		# The bed pose needs the base pulled back into the pelvis: the authored pose puts it on
		# the lower belly, which also leaves the hips farther from her than `Pelvis gap` implies.
		part.call("set_bed_inset", _part_inset_m if _bed_pose() else 0.0)
	# Both poses use the attached alignment: the part is a child of his Hips bone, it turns about its
	# base to her opening's normal, and the pose that carries his body applies `hip_offset_wanted`, so
	# his pelvis follows the entrance instead of the shaft sliding out of his crotch.
	var shown: float = _facts.penetration_m
	if anatomy.has_method("player_track"):
		anatomy.call("player_track", _contact_point, _contact_rear,
			frame.basis.y.normalized(), false, shown, delta, (mesh as Node3D).get_parent(),
			true)
	if _debug != null:
		_debug.tick(part)
	_facts.perf("anatomy_tick", Time.get_ticks_usec() - started)


## The face contact: part once, then hold her shapes at the neutral closed value and point the
## contact at his authored mouth. The part is parked, so the shaft-hug beat and the act wink have
## nothing to close on and are not driven; the emphasis stays on her body and the pose's press.
func _face_tick(_delta: float, part: Variant) -> void:
	var started := Time.get_ticks_usec()
	if not _face_parted:
		_face_parted = true
		if is_instance_valid(part):
			part.call("encounter", false)
	if is_instance_valid(anatomy):
		anatomy.call("set_fill", 0.0)
		anatomy.call("set_grip", 0.0)
		anatomy.call("clear_shaft")
		anatomy.call("drive", WINKING_REST_OPEN)
	var point := hole_point()
	var view: Variant = _pose_view()
	if view != null:
		var target: Variant = view.contact_target
		if target is Vector3 and (target as Vector3).is_finite():
			point = target
	_contact_point = point
	_contact_normal = Vector3.ZERO
	_contact_rear = Vector3.ZERO
	_facts.perf("anatomy_tick", Time.get_ticks_usec() - started)


## Her own wink while the act runs: one quiet beat while the tip rests at her lips, and a
## frequent beat once a climax has been pulled out of her. Only the vulva, and never on top of a
## climax pulse, because both share the one countdown.
func _act_wink_tick(delta: float, part: Variant) -> void:
	if _state() != 2 or _hole_mix >= 0.5 or _mouth_contact() or _wink_left > 0.0:
		return
	var touching := false
	if is_instance_valid(part) and bool(part.call("showing")):
		var reach := TOUCH_MARGIN_M
		var tip: Vector3 = part.call("tip_center")
		touching = tip.is_finite() and tip.distance_to(hole_point()) <= reach
	var mode := STATE.wink_mode(_depth(), touching, _climaxes(), PULLED_OUT_PHASE)
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


## The pure decision lives in `anatomy/act/state.gd`.
static func wink_mode(depth: float, touching: bool, climaxes: int) -> int:
	return STATE.wink_mode(depth, touching, climaxes, PULLED_OUT_PHASE)


func _wink_interval(mode: int) -> float:
	if mode == 2:
		return randf_range(OUT_WINK_MIN_S, OUT_WINK_MAX_S)
	return randf_range(TOUCH_WINK_MIN_S, TOUCH_WINK_MAX_S)


## One open/close pulse layered on the live shape drive. The drive rewrites `closed` every tick,
## so a tween would be cancelled; a countdown is what survives.
func _start_wink(seconds: float, beats: float) -> void:
	_wink_left = seconds
	_wink_total = maxf(seconds, 0.001)
	_wink_beats = beats


## The vulva plane's normal, oriented toward Anon. `hole_rear()` is the anatomy mesh's own axis;
## its sign depends on how the asset was authored, so it is resolved against his pelvis position.
func _compute_normal(_part: Variant) -> Vector3:
	if not is_instance_valid(anatomy):
		return Vector3.ZERO
	var normal: Vector3 = hole_rear()
	if normal.length_squared() < 0.000001:
		return Vector3.ZERO
	normal = normal.normalized()
	# Resolve the sign against *her own body*, never against Anon: the outward normal points away
	# from her hip centre, and that reference does not move when his pelvis does.
	var hips := _hips_point()
	if hips == Vector3.ZERO:
		return normal
	return -normal if normal.dot(hole_point() - hips) < 0.0 else normal


## Her pelvis bone in world space, the stable reference for the opening's outward direction.
func _hips_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.ZERO
	var skeleton: Skeleton3D = pony.get("skeleton") as Skeleton3D if pony.get("skeleton") != null else null
	if not is_instance_valid(skeleton):
		return Vector3.ZERO
	var hips := skeleton.find_bone("pony_hips")
	if hips < 0:
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin


## integration: shape and fluid hooks called by the runtime.
func on_climax() -> void:
	if is_instance_valid(anatomy):
		anatomy.call("_clear_part")
		_start_wink(CLIMAX_WINK_S, CLIMAX_WINKS)
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return
	fluid.call("spray", hole_point(), _hole_out(), 26, 1.0, 0.0075, PONY_FLUID_COLOR)
	fluid.call("drip", Callable(self, "hole_point"), 2.5, 7.0, 0.007, PONY_FLUID_COLOR)


## integration: afterglow part tracking, on the act's attached alignment.
func afterglow_tick(delta: float, facts: RefCounted) -> void:
	if facts != null:
		_facts = facts
	if _facts == null or not is_instance_valid(anatomy) or not is_instance_valid(pony):
		return
	var started := Time.get_ticks_usec()
	var mesh: Variant = anatomy.call("winking_mesh")
	var part: Variant = _part()
	if not is_instance_valid(mesh) or not is_instance_valid(part) or not bool(part.call("showing")):
		return
	# The held phase rests the tip at her entrance; no finish state drives this depth any more.
	var rest_m := 0.0
	# Keep the act's attached alignment through the held phase. The detached bed holder aligns
	# the part's roll to the anatomy mesh's own axes, and in the lying pose her mesh +Y points
	# into the mattress, so the shaft would be rolled 180° there.
	var normal := _compute_normal(part)
	_normal = normal
	_contact()
	part.call("set_aim", _contact_normal, _contact_point, 0.0)
	# The missionary inset belongs to the whole bed act, not only to the thrusting states.
	part.call("set_bed_inset", _part_inset_m if _bed_pose() else 0.0)
	if anatomy.has_method("player_track"):
		anatomy.call("player_track", _contact_point, _contact_rear,
			(mesh as Node3D).global_transform.basis.y.normalized(), false, rest_m, delta,
			(mesh as Node3D).get_parent(), true)
	_facts.perf("anatomy_afterglow", Time.get_ticks_usec() - started)


func end() -> void:
	if is_instance_valid(anatomy):
		anatomy.call("animate", 1.0, 1.5)
		anatomy.call("_clear_part")
	if _oral != null:
		_oral.call("clear")


func teardown() -> void:
	if _debug != null:
		_debug.clear()
		_debug = null
	_facts = null
	_part_handle = null
	if _oral != null:
		_oral.call("teardown")
	_anal = false
	_hole_mix = 0.0
	_face_parted = false


func _hole_out() -> Vector3:
	var rear := hole_rear()
	return rear + Vector3.DOWN * 0.3


func _fluid_node() -> Node3D:
	if not is_instance_valid(anatomy):
		return null
	return anatomy.call("fluid") as Node3D
