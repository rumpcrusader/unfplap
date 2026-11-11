extends Node
## integration: per-act anatomy behaviour ported from PonyPussyParadise runtime.gd. It reads the
## current act depth and drives the anatomy meshes, the Anon part, the oral turn, the finish state
## and the fluid. It never touches thrust scoring, auto thrust or the camera.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const STATE := preload("res://mods/unfplap/anatomy/act/state.gd")
const DEBUG := preload("res://mods/unfplap/anatomy/act/debug.gd")
const FINISH := preload("res://mods/unfplap/anatomy/act/finish.gd")
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

var runtime: Node
var pony: Node3D
var anatomy: Node
var main: Node
var pose := ""
var _display_name := ""
## Per-tick act facts written by the runtime. The act never reads runtime private fields.
var _facts: Dictionary = {}
var _anal := false
var _hole_mix := 0.0
var _oral_turn: RefCounted
var _fill := 0.0
var _wide := 0.0
var _finish: RefCounted
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
var _debug: RefCounted


func setup(runtime_node: Node, main_node: Node, pony_node: Node3D, anatomy_node: Node,
		pose_id: String) -> void:
	runtime = runtime_node
	main = main_node
	pony = pony_node
	anatomy = anatomy_node
	pose = pose_id
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	if identity != null and identity.get("display_name") != null:
		_display_name = str(identity.get("display_name"))
	elif is_instance_valid(pony):
		_display_name = str(pony.name)
	_finish = FINISH.new()
	_finish.setup(anatomy, pony, main, pose)
	_oral_turn = ORAL.new()
	_oral_turn.setup(pony, main, anatomy, pose)
	reset()
	_debug = DEBUG.new()
	_debug.setup(main, anatomy)


func reset() -> void:
	_facts.clear()
	_anal = false
	_hole_mix = 0.0
	_fill = 0.0
	_wide = 0.0
	if _oral_turn != null:
		_oral_turn.reset()
	if _finish != null:
		_finish.reset()
	_wink_left = 0.0
	_wink_total = 0.0
	_wink_beats = 0.0
	_act_wink_next = 0.0
	_act_wink_mode = 0
	if is_instance_valid(anatomy):
		anatomy.call("animate", 0.0, 1.0)


func _state() -> int:
	return int(_facts.get("state", 0))


func _depth() -> float:
	return clampf(float(_facts.get("depth", 0.0)), 0.0, 1.0)


func _fact_float(key: String, fallback: float) -> float:
	var value: Variant = _facts.get(key, fallback)
	return float(value) if value is float or value is int else fallback


## The oral facing the runtime applies after the tick. Empty when no turn is active.
func facing() -> Dictionary:
	return _oral_turn.facing() if _oral_turn != null else {}


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


func oral_active() -> bool:
	return _oral_turn != null and bool(_oral_turn.active())


func finish_out() -> bool:
	return _finish != null and bool(_finish.finish_out())


func pull_out_selected() -> bool:
	return _finish != null and bool(_finish.pull_out_selected())


func finished_inside() -> bool:
	return _finish != null and bool(_finish.finished_inside())


func toggle_hole(state: int) -> void:
	if not SETTINGS.anatomy_holes.get_bool() or state not in [2, 3] \
			or (_oral_turn != null and bool(_oral_turn.active())):
		return
	if not is_instance_valid(anatomy) or not is_instance_valid(anatomy.call("anal_mesh")):
		return
	if not _anal and not _consent("anal"):
		_status("%s is not into that" % _display_name)
		return
	_anal = not _anal


func toggle_oral(state: int) -> void:
	if _oral_turn == null:
		return
	if bool(_oral_turn.toggle(state)):
		_anal = false
		_hole_mix = 0.0


func toggle_finish(state: int) -> void:
	if _finish != null:
		_finish.toggle(state)


func _service() -> Variant:
	return main.get("anatomy") if is_instance_valid(main) else null


func _part() -> Variant:
	var service: Variant = _service()
	if service == null or not service.has_method("part"):
		return null
	return service.call("part")


func _consent(key: String) -> bool:
	if not is_instance_valid(main):
		return false
	var service: Variant = main.get("eligibility")
	if service == null or not service.has_method("action_consent"):
		return false
	return bool(service.call("action_consent", pony, key))


func _status(text: String) -> void:
	if is_instance_valid(main) and main.has_method("anatomy_status"):
		main.call("anatomy_status", text, 2.0)


func tick(delta: float, facts: Dictionary) -> void:
	_facts = facts
	if not is_instance_valid(anatomy) or not is_instance_valid(pony):
		return
	var started := Time.get_ticks_usec()
	var mesh: Variant = anatomy.call("winking_mesh")
	if not is_instance_valid(mesh):
		return
	var frame: Transform3D = (mesh as Node3D).global_transform
	var mesh_scale := maxf(frame.basis.get_scale().x, 0.001)
	var part: Variant = _part()
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
	if _oral_turn != null:
		_oral_turn.set_facts(_facts)
		_oral_turn.tick(delta)
	var oral_mix := float(_oral_turn.mix()) if _oral_turn != null else 0.0
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
		var anal := _wide * _hole_mix * rearward
		anatomy.call("set_anal_shape", anal * 1.4, anal)
		anatomy.call("set_anal_grip", grip_world * _hole_mix * rearward)
	_normal = _compute_normal(part)
	if is_instance_valid(part):
		part.set("aim_pitch_deg", 0.0)
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
		part.set("aim_normal", _normal)
		part.set("aim_opening", hole_point())
		# The bed pose needs the base pulled back into the pelvis: the authored pose puts it on
		# the lower belly, which also leaves the hips farther from her than `Pelvis gap` implies.
		part.set("bed_inset_m", SETTINGS.part_inset_m.get_num()
			if pose == CATALOG.MISSIONARY else 0.0)
	# Both poses use the attached alignment: the part is a child of his Hips bone, it turns about its
	# base to her opening's normal, and the pose that carries his body applies `hip_offset_wanted`, so
	# his pelvis follows the entrance instead of the shaft sliding out of his crotch.
	var shown := _fact_float("penetration_m", 0.0)
	var service: Variant = _service()
	if service != null:
		service.call("player_track", hole_point(), hole_rear(),
			frame.basis.y.normalized(), false, shown, delta, (mesh as Node3D).get_parent(),
			true)
	if _debug != null:
		_debug.tick(part)
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_tick", Time.get_ticks_usec() - started)


func pose_config(config: Dictionary) -> void:
	if not is_instance_valid(anatomy) or _oral_turn == null:
		return
	# Missionary needs no pose overrides: the authored base pose already holds the pelvis and legs.
	if pose != CATALOG.STANDING:
		return
	var delta: Dictionary = _oral_turn.pose_delta()
	for key: String in delta:
		config[key] = delta[key]


## Her own wink while the act runs: one quiet beat while the tip rests at her lips, and a
## frequent beat once a climax has been pulled out of her. Only the vulva, and never on top of a
## climax pulse, because both share the one countdown.
func _act_wink_tick(delta: float, part: Variant) -> void:
	if _state() != 2 or _hole_mix >= 0.5 or _oral_turn == null \
			or bool(_oral_turn.active()) or _wink_left > 0.0:
		return
	var touching := false
	if is_instance_valid(part) and bool(part.call("showing")):
		var reach := TOUCH_MARGIN_M + maxf(SETTINGS.back_out_m.get_num(), 0.0)
		var tip: Vector3 = part.call("tip_center")
		touching = tip.is_finite() and tip.distance_to(hole_point()) <= reach
	var mode := STATE.wink_mode(_depth(), touching, int(_facts.get("climaxes", 0)),
		PULLED_OUT_PHASE)
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


## The pure decision lives in `anatomy/act/state.gd`; this forwarder keeps the act's static
## surface stable while the system is split.
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
func _compute_normal(part: Variant) -> Vector3:
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


func on_finish() -> void:
	if _finish != null:
		_finish.on_finish(_depth(), _oral_turn != null and bool(_oral_turn.active()),
			_fact_float("fluid_ground_y", pony.global_position.y))


## integration: afterglow part tracking for the optional bed body.
func afterglow_tick(delta: float, facts: Dictionary) -> void:
	_facts = facts
	if not is_instance_valid(anatomy) \
			or not is_instance_valid(pony) or not is_instance_valid(main):
		return
	var started := Time.get_ticks_usec()
	var mesh: Variant = anatomy.call("winking_mesh")
	var part: Variant = _part()
	if not is_instance_valid(mesh) or not is_instance_valid(part) or not bool(part.call("showing")):
		return
	var rest_m := 0.0
	if _finish != null:
		rest_m = float(_finish.afterglow_step(delta, _fact_float("penetration_reach", 0.2)))
	var service: Variant = _service()
	if service != null:
		service.call("player_track", hole_point(), hole_rear(),
			(mesh as Node3D).global_transform.basis.y.normalized(), true, rest_m, delta,
			(mesh as Node3D).get_parent())
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_afterglow", Time.get_ticks_usec() - started)


func withdraw() -> void:
	if _finish != null:
		_finish.withdraw()


func end() -> void:
	if is_instance_valid(anatomy):
		anatomy.call("animate", 1.0, 1.5)
		anatomy.call("_clear_part")
	if _oral_turn != null:
		_oral_turn.end()


func teardown() -> void:
	if _debug != null:
		_debug.free()
		_debug = null
	_facts.clear()
	if _oral_turn != null:
		_oral_turn.teardown()
	_anal = false
	_hole_mix = 0.0
	if _finish != null:
		_finish.teardown()


func _hole_out() -> Vector3:
	var rear := hole_rear()
	return rear + Vector3.DOWN * 0.3


func _fluid_node() -> Node3D:
	if not is_instance_valid(anatomy):
		return null
	return anatomy.call("fluid") as Node3D
