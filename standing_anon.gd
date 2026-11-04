extends RefCounted
## Standing Anon body: the hip thrust wrapper, torso lean counter-move, foot pin and palm
## scale. The runtime owns readiness and scoring; this controller only poses the player rig.

const ANON_THRUST := preload("res://mods/unfplap/anon_thrust.gd")
const HIP_THRUST := preload("res://mods/unfplap/anon_hip_thrust.gd")
const PALM_SCALE := preload("res://mods/unfplap/palm_scale.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const THRUST_MAX_M := 0.045

var runtime: Node
var main: Variant
var pony: Variant
var _hip_phase := 0.0
var _anon_thrust_driver: Node3D
var _anon_thrust_original: Node
var _anon_thrust_avatar: Node3D
var _hip_thrust: SkeletonModifier3D
var _palm_scale: SkeletonModifier3D
var _lower_left := Transform3D.IDENTITY
var _lower_right := Transform3D.IDENTITY
var _lower_captured := false

func _hip_phase_tick(delta: float) -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING or int(runtime.get("state")) not in [2, 3, 4]:
		_hip_phase = 0.0
		return
	_hip_phase = MOTION.hip_phase_step(_hip_phase, float(runtime.get("depth")), delta)





## Free camera owns the movement keys completely: Anon cannot walk, shift on the bed, jump or
## start couch actions while the shot is active. The previous value is restored at act end.

## Initial backset from the fixed rump limit. At phase 0 the hips are back by the full
## travel; at phase 1 they return to the limit.
static func hip_backset(phase: float, scale: float, travel: float) -> float:
	return THRUST_MAX_M * clampf(scale, 0.5, 2.5) * maxf(0.0, travel) \
		* (1.0 - clampf(phase, 0.0, 1.0))


func apply_anon_thrust(_hip: Node3D, facing: Basis) -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING or not is_instance_valid(_hip_thrust):
		return
	if not facing.is_finite() or facing.z.length_squared() < 0.0001:
		return
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	var travel := 1.0
	var travel_value: Variant = runtime.get("_thrust_travel")
	if travel_value != null:
		travel = maxf(0.0, float(travel_value))
	var back := facing.z.normalized()
	_hip_thrust.set("offset_world", back * hip_backset(_hip_phase, scale, travel))


## Phase-2 Anon body lean: keep the pelvis planted behind her rump. The camera/head moves
## forward or sideways, so the torso hinges at the hips instead of the whole body sliding into
## her. Pulling back still moves the whole body away.

func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	var kiss: Variant = runtime.call("_kiss_controller")
	if str(runtime.get("pose_id")) != CATALOG.STANDING or not bool(runtime.get("_free_camera_active")) or not is_instance_valid(hip):
		return
	var forward := -facing.z.normalized()
	var side := facing.x.normalized()
	var lean_scale: float = float(runtime.call("_standing_lean_scale"))
	var forward_shift: float = MOTION.lean_distance(maxf(float(runtime.get("_lean_view_forward")), 0.0), lean_scale) \
		+ kiss.lean_distance() + float(runtime.call("_anon_torso_forward"))
	hip.global_position -= forward * forward_shift
	var side_shift: float = kiss.lateral_offset(lean_scale)
	hip.global_position -= side * side_shift
	# The kiss and torso angle drop the camera/head; keep the pelvis planted through the hinge.
	hip.global_position.y += kiss.lean_drop() * kiss.lean() + float(runtime.call("_anon_torso_drop"))
	# The feet are placed from the camera/head before this call. Pin the lower body so a forward
	# or kiss lean hinges the torso instead of walking his legs into the shot.
	var body := hip.get_parent()
	if body != null:
		var left: Variant = body.get("_left_foot")
		var right: Variant = body.get("_right_foot")
		if forward_shift > 0.001 or absf(side_shift) > 0.001 or kiss.lean() > 0.001:
			if not _lower_captured and left is Node3D and right is Node3D:
				_lower_left = (left as Node3D).global_transform
				_lower_right = (right as Node3D).global_transform
				_lower_captured = true
				_log("standing lower body pinned")
			if _lower_captured:
				if left is Node3D:
					(left as Node3D).global_transform = _lower_left
				if right is Node3D:
					(right as Node3D).global_transform = _lower_right
		elif _lower_captured:
			_lower_captured = false
			_log("standing lower body released")



func _install_anon_thrust() -> void:
	_remove_anon_thrust()
	if str(runtime.get("pose_id")) != CATALOG.STANDING or bool(runtime.get("_player_pony")) or not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var avatar := main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return
	var original: Variant = avatar.get("desktop_pose_driver")
	if not is_instance_valid(original):
		return
	var driver: Node3D = ANON_THRUST.new()
	driver.name = "UnfplapAnonThrust"
	driver.set("original", original)
	driver.set("runtime", runtime)
	main.player.add_child(driver)
	avatar.set("desktop_pose_driver", driver)
	_anon_thrust_driver = driver
	_anon_thrust_original = original
	_anon_thrust_avatar = avatar
	var skeleton := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if is_instance_valid(skeleton):
		_hip_thrust = HIP_THRUST.new()
		_hip_thrust.name = "UnfplapHipThrust"
		_hip_thrust.process_priority = 20
		skeleton.add_child(_hip_thrust)
	_install_palm_scale(avatar)



func _install_palm_scale(avatar: Node3D) -> void:
	_remove_palm_scale()
	if not is_instance_valid(avatar):
		return
	var factor: float = float(runtime.call("_palm_scale_factor"))
	if is_equal_approx(factor, 1.0):
		return
	var skeleton := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(skeleton):
		_log("standing palm scale skipped: no skeleton")
		return
	_palm_scale = PALM_SCALE.new()
	_palm_scale.name = "UnfplapPalmScale"
	_palm_scale.set("skeleton", skeleton)
	_palm_scale.set("factor", factor)
	_palm_scale.process_priority = 10
	skeleton.add_child(_palm_scale)
	_log("standing palm scale=%.2f size=%s" % [factor, runtime.call("_size_name")])



func _refresh_palm_scale() -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING or not is_instance_valid(_anon_thrust_avatar):
		return
	var factor: float = float(runtime.call("_palm_scale_factor"))
	if is_equal_approx(factor, 1.0):
		_remove_palm_scale()
		return
	if is_instance_valid(_palm_scale):
		if not is_equal_approx(float(_palm_scale.get("factor")), factor):
			_palm_scale.set("factor", factor)
		return
	_install_palm_scale(_anon_thrust_avatar)



func _remove_palm_scale() -> void:
	if is_instance_valid(_palm_scale):
		_palm_scale.set("active", false)
		_palm_scale.call("restore")
		_palm_scale.queue_free()
	_palm_scale = null



func _remove_anon_thrust() -> void:
	_remove_palm_scale()
	if is_instance_valid(_hip_thrust):
		_hip_thrust.queue_free()
	_hip_thrust = null
	if is_instance_valid(_anon_thrust_avatar) and is_instance_valid(_anon_thrust_original) \
			and _anon_thrust_avatar.get("desktop_pose_driver") == _anon_thrust_driver:
		_anon_thrust_avatar.set("desktop_pose_driver", _anon_thrust_original)
	if is_instance_valid(_anon_thrust_driver):
		_anon_thrust_driver.queue_free()
	_anon_thrust_driver = null
	_anon_thrust_original = null
	_anon_thrust_avatar = null


## Called after anon_body has set the hip target, through the desktop pose-driver wrapper.
## The hip follows the lightly smoothed mouse depth, so its position is the mouse travel.

func _desktop_pose_driver() -> Node:
	if is_instance_valid(_anon_thrust_driver):
		return _anon_thrust_driver
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return null
	var avatar: Node = main.player.find_child("AnonBody", true, false)
	if not is_instance_valid(avatar):
		return null
	var driver: Variant = avatar.get("desktop_pose_driver")
	return driver as Node if is_instance_valid(driver) else null




func _sync() -> void:
	main = runtime.get("main") if is_instance_valid(runtime) else null
	pony = runtime.get("pony") if is_instance_valid(runtime) else null


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


func reset_phase() -> void:
	_hip_phase = 0.0


func tick_phase(delta: float) -> void:
	_sync()
	_hip_phase_tick(delta)


func install() -> void:
	_sync()
	_install_anon_thrust()


func remove() -> void:
	_remove_anon_thrust()


func driver() -> Node:
	_sync()
	return _desktop_pose_driver()


func refresh_palm() -> void:
	_sync()
	_refresh_palm_scale()


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
