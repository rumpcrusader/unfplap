extends Node
## integration: per-act anatomy behaviour ported from PonyPussyParadise runtime.gd. It reads the
## current act depth and drives the anatomy meshes, the Anon part, the oral turn, the finish state
## and the fluid. It never touches thrust scoring, auto thrust or the camera.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

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
const MARE_HOLD_PHASE := 0.45
const PULLED_OUT_PHASE := 0.35
const ORAL_TURN_S := 1.6
const ORAL_DEPTH := 0.5
const ORAL_DIP_DEG := 8.0
const ORAL_CHIN_DEG := 6.0
const ORAL_NECK_DEG := -14.0
const ORAL_MOUTH := "D"
const ORAL_LEAN_M := 0.14
const ORAL_STYLE_MIN_S := 3.5
const ORAL_STYLE_MAX_S := 8.0
const ORAL_STYLE_BLEND := 2.0
const ORAL_ANCHOR_RATE := 0.8
const ORAL_BELOW_NOSE_M := 0.03
const PONY_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)
const ANON_FLUID_COLOR := Color(0.98, 0.97, 0.93, 0.96)
const ORAL_STYLES := [
	[Vector3(0.085, 0.16, 0.04), 1.0],
	[Vector3(0.05, 0.14, 0.26), 0.85],
	[Vector3(0.06, 0.08, 0.34), 0.75],
	[Vector3(0.03, 0.08, 0.12), 1.6],
	[Vector3(0.1, 0.22, 0.1), 0.6],
]

var runtime: Node
var pony: Node3D
var anatomy: Node
var main: Node
var pose := ""
var _id := ""
var _display_name := ""
var _anal := false
var _hole_mix := 0.0
var _oral := false
var _oral_mix := 0.0
var _oral_style: Array = ORAL_STYLES[0]
var _oral_style_left := 0.0
var _oral_now := Vector3.ZERO
var _oral_speed := 1.0
var _oral_clock := 0.0
var _oral_side := 1.0
var _oral_anchor := Vector3.INF
var _oral_hold := Vector3.ZERO
var _oral_rear := Vector3.BACK
var _oral_from := Vector3.ZERO
var _oral_to := Vector3.ZERO
var _oral_from_basis := Basis.IDENTITY
var _fill := 0.0
var _wide := 0.0
var _pull_out := false
var _finish_out := false
var _finished_inside := false
var _bed_rest := 0.8
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
var _debug_vulva: MeshInstance3D
var _debug_anus: MeshInstance3D
var _debug_tip: MeshInstance3D


func setup(runtime_node: Node, anatomy_node: Node, pose_id: String) -> void:
	runtime = runtime_node
	anatomy = anatomy_node
	main = runtime.get("main")
	pony = runtime.get("pony")
	pose = pose_id
	_id = str(runtime.get("_id"))
	_display_name = str(runtime.get("_display_name"))
	reset()
	_debug_setup()


func reset() -> void:
	_anal = false
	_hole_mix = 0.0
	_oral = false
	_oral_mix = 0.0
	_oral_style = ORAL_STYLES[0]
	_oral_style_left = 0.0
	_oral_now = Vector3.ZERO
	_oral_speed = 1.0
	_oral_clock = 0.0
	_oral_side = 1.0
	_oral_anchor = Vector3.INF
	_oral_from = Vector3.ZERO
	_oral_to = Vector3.ZERO
	_oral_from_basis = Basis.IDENTITY
	_fill = 0.0
	_wide = 0.0
	_pull_out = false
	_finish_out = false
	_finished_inside = false
	_bed_rest = 0.8
	_wink_left = 0.0
	_wink_total = 0.0
	_wink_beats = 0.0
	_act_wink_next = 0.0
	_act_wink_mode = 0
	if is_instance_valid(anatomy):
		anatomy.call("animate", 0.0, 1.0)


func _state() -> int:
	return int(runtime.get("state"))


func _depth() -> float:
	return clampf(float(runtime.get("depth")), 0.0, 1.0)


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
	return _oral or _oral_mix > 0.0


func finish_out() -> bool:
	return _finish_out


func pull_out_selected() -> bool:
	return _pull_out


func finished_inside() -> bool:
	return _finished_inside


func toggle_hole() -> void:
	if not SETTINGS.anatomy_holes.get_bool() or _state() not in [2, 3] or _oral:
		return
	if not is_instance_valid(anatomy) or not is_instance_valid(anatomy.call("anal_mesh")):
		return
	if not _anal and not _consent("anal"):
		_status("%s is not into that" % _display_name)
		return
	_anal = not _anal


func toggle_oral() -> void:
	if not SETTINGS.anatomy_oral.get_bool() or _state() != 2 or pose != CATALOG.STANDING:
		return
	if not _consent("oral"):
		_status("%s is not into that" % _display_name)
		return
	var ends := _head_ends()
	if ends.is_empty():
		return
	if not _oral and _oral_mix <= 0.0:
		_anal = false
		_hole_mix = 0.0
		var mouth: Vector3 = pony.global_transform.affine_inverse() * _mouth_point()
		var scale: Vector3 = pony.global_transform.basis.get_scale()
		var turned := Basis(Vector3.UP, PI) * pony.global_transform.basis.orthonormalized()
		var opening: Vector3 = hole_point()
		var to: Vector3 = opening - turned * (mouth * scale)
		_oral_from = pony.global_position
		_oral_to = Vector3(to.x, pony.global_position.y, to.z)
		_oral_from_basis = pony.global_transform.basis.orthonormalized()
		_oral_hold = opening
		var back: Vector3 = anatomy.call("hole_rear", _hole_mix)
		_oral_rear = Vector3(back.x, 0.0, back.z).normalized()
	_oral = not _oral
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null:
		if _oral and mouth_rig.has_method("set_viseme"):
			mouth_rig.call("set_viseme", ORAL_MOUTH)
		elif not _oral and mouth_rig.has_method("clear"):
			mouth_rig.call("clear")


func toggle_finish() -> void:
	if not SETTINGS.anatomy_finish.get_bool() or _state() not in [2, 3]:
		return
	_pull_out = not _pull_out
	_status("Finish: %s" % ("pull out" if _pull_out else "stay in"))


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


func _head_ends() -> Array:
	var boop: Variant = pony.get("boop_node")
	var head: Variant = boop.get("head_skeleton") if boop != null else null
	if not head is Skeleton3D:
		return []
	var skeleton := head as Skeleton3D
	var bone := skeleton.find_bone("mHead")
	if bone < 0:
		return []
	return [skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin,
		boop.call("nose_world")]


func _pony_mouth() -> Variant:
	var head: Variant = pony.get("head")
	return head.get("mouth") if head != null else null


func _mouth_point() -> Vector3:
	var ends := _head_ends()
	if ends.is_empty():
		return hole_point()
	return (ends[1] as Vector3) + Vector3.DOWN * ORAL_BELOW_NOSE_M * _size_scale()


func _size_scale() -> float:
	return float(runtime.call("_size_scale"))


func tick(delta: float) -> void:
	if not is_instance_valid(anatomy) or not is_instance_valid(pony):
		return
	var started := Time.get_ticks_usec()
	var mesh: Variant = anatomy.call("winking_mesh")
	if not is_instance_valid(mesh):
		return
	var frame: Transform3D = (mesh as Node3D).global_transform
	var mesh_scale := maxf(frame.basis.get_scale().x, 0.001)
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
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
	_hole_mix = move_toward(_hole_mix, 1.0 if _anal else 0.0, delta / HOLE_SWAP_S)
	_oral_tick(delta)
	if _oral_mix > 0.0:
		_oral_motion_tick(delta)
	var rearward := 1.0 - _oral_mix
	var front := (1.0 - _hole_mix) * rearward
	_act_wink_tick(delta, part)
	# The shapes stay driven through the climax too, so the lips keep their grip on the shaft
	# instead of snapping closed; the climax wink is applied on top as a pulse.
	if _state() in [2, 3]:
		var closed := 1.0 - (1.0 - WINKING_REST_OPEN * (1.0 - _fill)) * front
		if _wink_left > 0.0:
			_wink_left = maxf(_wink_left - delta, 0.0)
			var beat: float = absf(sin((1.0 - _wink_left / _wink_total) * PI * _wink_beats))
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
	var shown := float(runtime.get("penetration_m"))
	main.call("anon_track", hole_point(), hole_rear(), frame.basis.y.normalized(), false,
		shown, delta, (mesh as Node3D).get_parent(), true)
	_debug_tick(part)
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_tick", Time.get_ticks_usec() - started)


func pose_config(config: Dictionary) -> void:
	if not is_instance_valid(anatomy):
		return
	# Missionary needs no pose overrides: the authored base pose already holds the pelvis and legs.
	if pose == CATALOG.STANDING and _oral_mix > 0.0:
		config["oral_pitch"] = _oral_now.y * 0.5 * _oral_mix
		config["oral_yaw"] = _oral_now.z * _oral_mix
		config["oral_roll"] = _oral_now.z * 0.3 * _oral_mix


## Her own wink while the act runs: one quiet beat while the tip rests at her lips, and a
## frequent beat once a climax has been pulled out of her. Only the vulva, and never on top of a
## climax pulse, because both share the one countdown.
func _act_wink_tick(delta: float, part: Variant) -> void:
	if _state() != 2 or _hole_mix >= 0.5 or _oral_mix > 0.0 or _wink_left > 0.0:
		return
	var touching := false
	if is_instance_valid(part) and bool(part.call("showing")):
		var reach := TOUCH_MARGIN_M + maxf(SETTINGS.back_out_m.get_num(), 0.0)
		var tip: Vector3 = part.call("tip_center")
		touching = tip.is_finite() and tip.distance_to(hole_point()) <= reach
	var mode := wink_mode(_depth(), touching, int(runtime.get("pony_climaxes")))
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


## 0: nothing. 1: the tip is at her lips. 2: she has climaxed and he has pulled out of her.
static func wink_mode(depth: float, touching: bool, climaxes: int) -> int:
	if depth >= PULLED_OUT_PHASE:
		return 0
	if touching:
		return 1
	return 2 if climaxes >= 1 else 0


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


func _oral_motion_tick(delta: float) -> void:
	_oral_style_left -= delta
	if _oral_style_left <= 0.0:
		_oral_style_left = randf_range(ORAL_STYLE_MIN_S, ORAL_STYLE_MAX_S)
		_oral_style = ORAL_STYLES.pick_random()
		_oral_side = -_oral_side
	var blend := 1.0 - exp(-delta * ORAL_STYLE_BLEND)
	_oral_now = _oral_now.lerp(_oral_style[0], blend)
	_oral_speed = lerpf(_oral_speed, float(_oral_style[1]), blend)
	var pace := 0.8
	var auto: Variant = runtime.get("_auto_thrust")
	if auto != null:
		pace = maxf(pace, float(auto.get("pace")))
	_oral_clock = fposmod(_oral_clock + delta * pace * _oral_speed, 16.0)
	var turn := TAU * _oral_clock
	var stroke := sin(turn)
	var mix := smoothstep(0.0, 1.0, _oral_mix)
	var mouth := _mouth_point()
	_oral_anchor = mouth if _oral_anchor == Vector3.INF \
		else _oral_anchor.lerp(mouth, 1.0 - exp(-delta * ORAL_ANCHOR_RATE))
	var config: Dictionary = runtime.get("_pose_cfg") if runtime.get("_pose_cfg") is Dictionary else {}
	config["oral_pitch"] = cos(turn) * _oral_now.y * mix
	config["oral_yaw"] = (sin(turn * 0.5) * _oral_now.z + _oral_side * _oral_now.z * 0.5) * mix
	config["oral_roll"] = sin(turn * 0.5 + 1.1) * _oral_now.z * 0.6 * mix
	if is_instance_valid(runtime.get("_pose")) and runtime.get("_pose").get("pose_config") is Dictionary:
		var live: Dictionary = runtime.get("_pose").get("pose_config")
		live["oral_pitch"] = config["oral_pitch"]
		live["oral_yaw"] = config["oral_yaw"]
		live["oral_roll"] = config["oral_roll"]


func _oral_tick(delta: float) -> void:
	var mix := move_toward(_oral_mix, 1.0 if _oral else 0.0, delta / ORAL_TURN_S)
	if mix == _oral_mix:
		return
	_oral_mix = mix
	if mix <= 0.0 and is_instance_valid(runtime.get("_pose")) \
			and runtime.get("_pose").get("pose_config") is Dictionary:
		for key: String in ["oral_pitch", "oral_yaw", "oral_roll"]:
			(runtime.get("_pose").get("pose_config") as Dictionary).erase(key)
	if not _oral:
		_oral_anchor = Vector3.INF
	var eased := smoothstep(0.0, 1.0, mix)
	var basis: Basis = Basis(Vector3.UP, PI * eased) * _oral_from_basis
	if is_instance_valid(runtime) and runtime.has_method("anatomy_facing"):
		runtime.call("anatomy_facing", basis, eased)
	pony.global_position = _oral_from.lerp(_oral_to, eased)


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
	# integration: with the finish control off, keep the master inside semantics and do not
	# create an outside finish spray.
	if not SETTINGS.anatomy_finish.get_bool():
		_finish_out = false
		_finished_inside = false
		return
	_finish_out = _pull_out or _depth() < PULLED_OUT_PHASE
	if _finish_out:
		if SETTINGS.anatomy_fluid.get_bool():
			_spurts_on_her(0)
	elif not _oral:
		_finished_inside = true
		if _fluid_ready():
			get_tree().create_timer(0.7).timeout.connect(_inside_leak)


## integration: afterglow part tracking for the optional bed body.
func afterglow_tick(delta: float) -> void:
	if not is_instance_valid(anatomy) \
			or not is_instance_valid(pony) or not is_instance_valid(main):
		return
	var started := Time.get_ticks_usec()
	var mesh: Variant = anatomy.call("winking_mesh")
	var part: Variant = main.get("anon_part")
	if not is_instance_valid(mesh) or not is_instance_valid(part) or not bool(part.call("showing")):
		return
	_bed_rest = move_toward(_bed_rest, 0.0 if _finish_out else 0.8, delta * 1.6)
	# `_bed_rest` is a depth share; the part is placed by measured penetration now.
	var rest_m := _bed_rest * float(runtime.call("penetration_reach"))
	main.call("anon_track", hole_point(), hole_rear(),
		(mesh as Node3D).global_transform.basis.y.normalized(), true, rest_m, delta,
		(mesh as Node3D).get_parent())
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_afterglow", Time.get_ticks_usec() - started)


func withdraw() -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		_finished_inside = false
		return
	var fluid := _fluid_node()
	if _finished_inside and is_instance_valid(fluid):
		fluid.call("spray", hole_point(), _hole_out(), 34, 0.55, 0.0105, ANON_FLUID_COLOR)
		fluid.call("drip", Callable(self, "hole_point"), 5.0, 11.0, 0.009, ANON_FLUID_COLOR)
	_finished_inside = false


func end() -> void:
	if is_instance_valid(anatomy):
		anatomy.call("animate", 1.0, 1.5)
		anatomy.call("_clear_part")
	if _oral_mix > 0.0:
		_oral = false
		_oral_mix = 0.0
		if is_instance_valid(runtime) and runtime.has_method("anatomy_facing"):
			runtime.call("anatomy_facing", Basis.IDENTITY, 0.0)
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("clear"):
		mouth_rig.call("clear")


func teardown() -> void:
	_debug_free()
	_oral = false
	_oral_mix = 0.0
	_anal = false
	_hole_mix = 0.0
	_finished_inside = false
	_finish_out = false
	_pull_out = false
	_bed_rest = 0.8


## Debug markers: always visible through geometry, no debug flag and no feature gate. They show
## the vaginal entrance, the anal entrance and the current cock tip for the act partner.
func _debug_setup() -> void:
	if not is_instance_valid(main):
		return
	if not SETTINGS.debug_aim_points.get_bool():
		return
	_debug_vulva = _debug_sphere(Color(1.0, 0.1, 0.75))
	_debug_anus = _debug_sphere(Color(1.0, 0.35, 0.05))
	_debug_tip = _debug_sphere(Color(0.1, 1.0, 0.4))
	for point: MeshInstance3D in [_debug_vulva, _debug_anus, _debug_tip]:
		main.add_child(point)


func _debug_sphere(color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	sphere.radial_segments = 8
	sphere.rings = 4
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.visible = false
	return mesh


func _debug_tick(part: Variant) -> void:
	if not SETTINGS.debug_aim_points.get_bool():
		if is_instance_valid(_debug_vulva):
			_debug_free()
		return
	if not is_instance_valid(_debug_vulva):
		_debug_setup()
	var shown := is_instance_valid(anatomy) and is_instance_valid(anatomy.call("winking_mesh"))
	for point: MeshInstance3D in [_debug_vulva, _debug_anus]:
		point.visible = shown
	if shown:
		_debug_vulva.global_position = anatomy.call("hole_point", 0.0)
		_debug_anus.global_position = anatomy.call("hole_point", 1.0)
	var tip_shown: bool = is_instance_valid(part) and bool(part.call("showing"))
	if is_instance_valid(_debug_tip):
		_debug_tip.visible = tip_shown
		if tip_shown:
			_debug_tip.global_position = part.call("tip_world")


func _debug_free() -> void:
	for point: MeshInstance3D in [_debug_vulva, _debug_anus, _debug_tip]:
		if is_instance_valid(point):
			point.queue_free()
	_debug_vulva = null
	_debug_anus = null
	_debug_tip = null


func _hole_out() -> Vector3:
	var rear := hole_rear()
	return rear + Vector3.DOWN * 0.3


func _fluid_node() -> Node3D:
	if not is_instance_valid(anatomy):
		return null
	return anatomy.call("fluid") as Node3D


func _fluid_ready() -> bool:
	if not SETTINGS.anatomy_fluid.get_bool():
		return false
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return false
	var ground := pony.global_position.y
	if pose == CATALOG.MISSIONARY:
		var camera: Variant = runtime.call("_missionary_camera_controller")
		if camera != null and camera.has_method("_bed_surface_top"):
			var top: Variant = camera.call("_bed_surface_top")
			if top is float and is_finite(top):
				ground = top
	fluid.set("ground_y", ground)
	return true


func _spurts_on_her(pulse: int) -> void:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	var fluid := _fluid_node()
	if pulse >= 4 or not is_instance_valid(part) or not bool(part.call("showing")) \
			or not is_instance_valid(fluid):
		return
	if pulse == 0:
		get_tree().create_timer(0.55).timeout.connect(_spurts_on_her.bind(1))
		return
	var rear := hole_rear()
	var up_and_over := -Vector3(rear.x, 0.0, rear.z).normalized() + Vector3.UP * 0.55
	if pose == CATALOG.MISSIONARY:
		var mesh: Variant = anatomy.call("winking_mesh")
		if is_instance_valid(mesh):
			up_and_over = (mesh as Node3D).global_basis.y.normalized() + Vector3.UP * 0.45
	fluid.call("spray", part.call("tip_world"), up_and_over, 20 - pulse * 3,
		2.3 - pulse * 0.35, 0.0095, ANON_FLUID_COLOR)
	get_tree().create_timer(0.38).timeout.connect(_spurts_on_her.bind(pulse + 1))


func _inside_leak() -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	var fluid := _fluid_node()
	if not is_instance_valid(fluid):
		return
	fluid.call("drip", Callable(self, "hole_point"), 9.0, 8.0, 0.009, ANON_FLUID_COLOR)
