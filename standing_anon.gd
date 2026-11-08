extends RefCounted
## Standing Anon body: the hip thrust wrapper, planted lower body and palm scale. The runtime
## owns readiness and scoring; this controller only poses the player rig.

const ANON_THRUST := preload("res://mods/unfplap/anon_thrust.gd")
const HIP_THRUST := preload("res://mods/unfplap/anon_hip_thrust.gd")
const PALM_SCALE := preload("res://mods/unfplap/palm_scale.gd")
const CHEST_BACK := preload("res://mods/unfplap/chest_back.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const THRUST_MAX_M := 0.045
## Captured feet sit this far behind their first act frame spot so they are not between her
## hind legs. The hips use the same capture, so the whole lower body translates as one.
const PLANT_FEET_BACK_M := 0.15

var runtime: Node
var main: Variant
var pony: Variant
var _hip_phase := 0.0
var _anon_thrust_driver: Node3D
var _anon_thrust_original: Node
var _anon_thrust_avatar: Node3D
var _hip_thrust: SkeletonModifier3D
var _palm_scale: SkeletonModifier3D
var _chest_back: SkeletonModifier3D
var _lower_left := Transform3D.IDENTITY
var _lower_right := Transform3D.IDENTITY
var _lower_captured := false
var _plant_left := Transform3D.IDENTITY
var _plant_right := Transform3D.IDENTITY
var _plant_hip := Transform3D.IDENTITY
var _plant_captured := false
## The AnonBody that owns `_left_foot`/`_right_foot`. The HipsTarget sits under the skeleton,
## so walking up from the hip target must skip the skeleton and find the body node.
var _lower_body: Node

func _hip_phase_tick(delta: float) -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING or int(runtime.get("state")) not in [2, 3, 4]:
		_hip_phase = 0.0
		return
	_hip_phase = MOTION.hip_phase_step(_hip_phase, float(runtime.get("depth")), delta)


## Signed forward offset from the base HipsTarget. Positive is toward the fixed rump limit;
## negative is the initial backset behind the base. `travel` is the backset multiplier.
static func hip_offset(phase: float, scale: float, travel: float) -> float:
	var forward_reach := THRUST_MAX_M * clampf(scale, 0.5, 2.5)
	var backset := forward_reach * maxf(0.0, travel)
	return forward_reach - backset * (1.0 - clampf(phase, 0.0, 1.0))


func apply_anon_thrust(_hip: Node3D, facing: Basis) -> void:
	# integration: the optional alignment pins the hip target but keeps this old hip-bone
	# backset, so large depths cannot drive his crotch into her.
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
	var forward := -facing.z.normalized()
	# With the anatomy part showing, the part asks for the pelvis to move to her entrance; the
	# Hips-bone offset carries the pelvis and the part together.
	var part: Variant = _anon_part()
	if part != null:
		var wanted: Variant = part.call("hip_offset_wanted")
		if wanted is Vector3 and (wanted as Vector3).is_finite():
			_hip_thrust.set("offset_world", wanted)
			part.set("hip_offset_applied", wanted)
			return
	_hip_thrust.set("offset_world", forward * hip_offset(_hip_phase, scale, travel))


## Phase-2 Anon body lean: the lower body stays exactly where the act started. The camera/head
## moves forward, sideways or down, so the torso hinges over her while the feet and hips stay
## planted. Pulling back moves the whole lower body away from her; the hips and both feet use the
## same capture offset, so the legs keep their pose.
func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	var kiss: Variant = runtime.call("_kiss_controller")
	if str(runtime.get("pose_id")) != CATALOG.STANDING or not bool(runtime.get("_free_camera_active")) or not is_instance_valid(hip):
		return
	var forward := -facing.z.normalized()
	var side := facing.x.normalized()
	var body := _lower_body_of(hip)
	# A rig without the body's foot targets (tests, odd overrides) still gets the unplanted lean.
	if body == null:
		body = hip.get_parent()
	var plant_basis := _rump_facing(_plant_hip.basis, forward)
	if body != null:
		var left: Variant = body.get("_left_foot")
		var right: Variant = body.get("_right_foot")
		# The capture happens on the first act frame, after the game placed the feet and hips
		# from the act camera. Freeze that as the lower-body rest for the whole act.
		if not _plant_captured and left is Node3D and right is Node3D:
			_plant_left = (left as Node3D).global_transform
			_plant_right = (right as Node3D).global_transform
			var back := facing.z.normalized()
			var spread := Vector3(facing.x.x, 0.0, facing.x.z).normalized() \
				* (SETTINGS.plant_spread_m.get_num() * 0.5)
			_plant_left.origin += back * PLANT_FEET_BACK_M + spread
			_plant_right.origin += back * PLANT_FEET_BACK_M - spread
			_plant_hip = hip.global_transform
			_plant_captured = true
			_log("standing feet pinned")
		if _feature_on("standing_plant_feet") and _plant_captured:
			# Every lean moves only the upper body; the captured lower body never travels.
			var sway := _sway_offset()
			var drop := Vector3.DOWN * _hip_drop()
			if left is Node3D:
				(left as Node3D).global_transform = _plant_left
			if right is Node3D:
				(right as Node3D).global_transform = _plant_right
			hip.global_transform = Transform3D(
				plant_basis, _plant_hip.origin + sway + drop)
			return
		var lean_scale: float = float(runtime.call("_standing_lean_scale"))
		var forward_shift: float = MOTION.lean_distance(maxf(float(runtime.call("shot_lean_forward")), 0.0), lean_scale) \
			+ kiss.lean_distance() + float(runtime.call("_anon_torso_forward"))
		hip.global_position -= forward * forward_shift
		var side_shift: float = kiss.lateral_offset(lean_scale)
		hip.global_position -= side * side_shift
		# The kiss and torso angle drop the camera/head; keep the pelvis planted through the hinge.
		hip.global_position.y += kiss.lean_drop() * kiss.lean() + float(runtime.call("_anon_torso_drop"))
		hip.global_position.y -= _hip_drop()
		# Flag off: keep the game's stepping feet and only pin the lower body while leaning.
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


func _anon_part() -> Variant:
	if not is_instance_valid(runtime):
		return null
	var main: Variant = runtime.get("main")
	if not is_instance_valid(main):
		return null
	var part: Variant = main.get("anon_part")
	if is_instance_valid(part) and bool(part.call("showing")):
		return part
	return null


## Square his hips to her entrance every frame: his forward turns to face the opening, so the
## shaft leaves his pelvis normal to her vulva instead of arriving at an angle. Using the opening
## itself avoids depending on which way her mesh's rear axis happens to point.
func _rump_facing(plant: Basis, forward: Vector3) -> Basis:
	var part: Variant = _anon_part()
	if part == null or not runtime.has_method("anatomy_opening"):
		return plant
	var toward := Vector3.ZERO
	var normal: Vector3 = runtime.call("anatomy_normal") if runtime.has_method("anatomy_normal") else Vector3.ZERO
	if normal.length_squared() > 0.0001:
		# Face straight into her opening, so his pelvis plane is parallel to her vulva.
		toward = -Vector3(normal.x, 0.0, normal.z)
	if toward.length_squared() < 0.0004:
		var opening: Vector3 = runtime.call("anatomy_opening")
		var pivot: Vector3 = part.call("root_now")
		toward = Vector3(opening.x - pivot.x, 0.0, opening.z - pivot.z)
	if toward.length_squared() < 0.0004:
		return plant
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.0001:
		return plant
	var delta := flat_forward.normalized().signed_angle_to(toward.normalized(), Vector3.UP)
	if is_zero_approx(delta):
		return plant
	return Basis(Vector3.UP, delta) * plant


func _hip_drop() -> float:
	return SETTINGS.hip_drop_m.get_num()


func _sway_offset() -> Vector3:
	if not is_instance_valid(runtime):
		return Vector3.ZERO
	var raw: Variant = runtime.get("_standing_sway_offset")
	if raw is Vector3 and (raw as Vector3).is_finite():
		return raw
	return Vector3.ZERO


## The AnonBody above the hip target that owns both foot targets. `HipsTarget` is parented to the
## skeleton, not the body, so `hip.get_parent()` never sees `_left_foot`/`_right_foot`; walk up
## until the body node is found and cache it for the act.
func _lower_body_of(hip: Node3D) -> Node:
	if is_instance_valid(_lower_body) and _lower_body.get("_left_foot") != null:
		return _lower_body
	var node: Node = hip.get_parent()
	for _step: int in 8:
		if not is_instance_valid(node):
			break
		if node.get("_left_foot") != null and node.get("_right_foot") != null:
			_lower_body = node
			return node
		node = node.get_parent()
	return null


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
		_chest_back = CHEST_BACK.new()
		_chest_back.name = "UnfplapChestBack"
		_chest_back.set("player", main.player)
		_chest_back.process_priority = 30
		skeleton.add_child(_chest_back)
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
	_plant_captured = false
	_lower_captured = false
	_lower_body = null
	if is_instance_valid(_hip_thrust):
		_hip_thrust.queue_free()
	_hip_thrust = null
	if is_instance_valid(_chest_back):
		_chest_back.queue_free()
	_chest_back = null
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
	_plant_captured = false
	_lower_captured = false


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


func _feature_on(name: String) -> bool:
	if is_instance_valid(runtime) and runtime.has_method("_feature"):
		return bool(runtime.call("_feature", name))
	return false
