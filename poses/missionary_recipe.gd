extends RefCounted
## Missionary (Pose 1) skeleton recipe. Order is load-bearing; see ROTATION.md.

const ROT := preload("res://mods/unfplap/poses/rotation.gd")

const POSE1_HIND_SPREAD := 0.42
const POSE1_RUMP_DROP_DEG := 35.0
const POSE1_LOOK_SCALE := 0.55
const POSE1_NUZZLE_SCALE := 0.45
const NUZZLE_PERIOD := 7.0
const NUZZLE_DURATION := 2.4
const POSE1_ROLL_TWEAK := 0.0
## Extra neck lift off the mattress after the head aim. In the standing model this is the
## chin-down direction; the supine body turns it into an upward head lift.
const POSE1_NECK_LIFT_DEG := 15.0

var last_roll := 0.0
var last_chest_roll := 0.0
var _config: Dictionary = {}


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	_roll_root(rig, sk, PI * weight)
	_lift_root(rig, sk, weight, 0.05)
	_straighten_spine_neck(rig, sk, weight)
	_align_chain_straight(rig, sk, weight)
	_level_body_roll(rig, sk, weight)
	_level_chest_roll(rig, sk, weight)
	_pitch_body_about_shoulders(rig, sk, weight, _value("rump_drop_deg", POSE1_RUMP_DROP_DEG))
	_bend_forelegs(rig, sk, weight, 0.3)
	_raise_hind_legs(rig, sk, weight)
	_hug_forelegs(rig, sk, weight)
	_aim_head(rig, sk, weight, _value("look_scale", POSE1_LOOK_SCALE), state.get("look_point", Vector3.ZERO))
	var pulse := 1.0 if bool(state.get("climaxing", false)) else _nuzzle_pulse(float(state.get("clock", 0.0)))
	if bool(state.get("climaxing", false)):
		pulse = 0.75 + 0.25 * sin(float(state.get("clock", 0.0)) * 4.0)
	if pulse > 0.001:
		_aim_head(rig, sk, weight * pulse, _value("nuzzle_scale", POSE1_NUZZLE_SCALE), state.get("look_point", Vector3.ZERO))
	var kiss := float(state.get("kiss", 0.0))
	if kiss > 0.001:
		# Extra neck/head share toward Anon's lips for the act kiss action.
		_aim_head(rig, sk, weight * kiss, 1.0, state.get("look_point", Vector3.ZERO))
	_neck_lift(rig, sk, weight, _value("neck_lift_deg", POSE1_NECK_LIFT_DEG))
	_roll_head(rig, sk, weight, float(state.get("head_roll", 0.0)))


func _roll_root(rig, sk: Skeleton3D, angle: float) -> void:
	if rig.root < 0 or rig.hips < 0 or absf(angle) < 0.0001:
		return
	var axis: Vector3 = rig.forward_axis(sk)
	var pivot := sk.get_bone_global_pose(rig.hips).origin
	var pose := sk.get_bone_global_pose(rig.root)
	pose.origin = pivot + Basis(axis, angle) * (pose.origin - pivot)
	pose.basis = Basis(axis, angle) * pose.basis
	pose.origin += rig.up_axis(sk) * (0.03 * absf(angle))
	sk.set_bone_global_pose(rig.root, pose)


func _lift_root(rig, sk: Skeleton3D, weight: float, metres: float) -> void:
	if rig.root < 0:
		return
	var pose := sk.get_bone_global_pose(rig.root)
	pose.origin += rig.up_axis(sk) * metres * weight
	sk.set_bone_global_pose(rig.root, pose)


func _straighten_spine_neck(rig, sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	if rig.hips >= 0:
		bones.append(rig.hips)
	bones.append_array(rig.spine)
	bones.append_array(rig.neck)
	for bone: int in bones:
		if bone < 0:
			continue
		var rest := sk.get_bone_rest(bone).basis.get_rotation_quaternion()
		var current := sk.get_bone_pose_rotation(bone)
		sk.set_bone_pose_rotation(bone, current.slerp(rest, weight))


func _align_chain_straight(rig, sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	bones.append_array(rig.spine)
	bones.append_array(rig.neck)
	if bones.is_empty():
		return
	var head := sk.find_bone("pony_head")
	var target: Vector3 = rig.forward_axis(sk)
	target.y = 0.0
	if target.length_squared() < 0.0001:
		return
	target = target.normalized()
	for i: int in bones.size():
		var bone := bones[i]
		if bone < 0 or bone == head:
			continue
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if i + 1 < bones.size():
			direction = sk.get_bone_global_pose(bones[i + 1]).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var axis := direction.cross(target)
		if axis.length_squared() < 0.0001:
			continue
		var angle := direction.angle_to(target) * weight
		pose.basis = Basis(axis.normalized(), angle) * pose.basis
		sk.set_bone_global_pose(bone, pose)


func _line_roll(rig, sk: Skeleton3D, left: Vector3, right: Vector3) -> float:
	return ROT.line_roll(rig.forward_axis(sk), rig.up_axis(sk), left, right)


func _pitch_body_about_shoulders(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if rig.root < 0 or rig.fore.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.fore[0].upper)).origin
	var right := sk.get_bone_global_pose(int(rig.fore[1].upper)).origin
	var pivot := (left + right) * 0.5
	var angle := deg_to_rad(degrees) * weight
	if absf(angle) < 0.0001:
		return
	var pose := sk.get_bone_global_pose(rig.root)
	var turn := Basis(rig.right_axis(sk), angle)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(rig.root, pose)


func _level_body_roll(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.root < 0 or rig.hips < 0 or rig.hind.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.hind[0].femur)).origin
	var right := sk.get_bone_global_pose(int(rig.hind[1].femur)).origin
	var angle := (_line_roll(rig, sk, left, right) + _value("roll_tweak", POSE1_ROLL_TWEAK)) * weight
	last_roll = angle
	if absf(angle) < 0.0001:
		return
	var forward: Vector3 = rig.forward_axis(sk)
	var pivot := sk.get_bone_global_pose(rig.hips).origin
	var pose := sk.get_bone_global_pose(rig.root)
	var turn := Basis(forward, angle)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(rig.root, pose)


func _level_chest_roll(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.spine.is_empty() or rig.fore.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.fore[0].upper)).origin
	var right := sk.get_bone_global_pose(int(rig.fore[1].upper)).origin
	var angle := _line_roll(rig, sk, left, right) * weight
	last_chest_roll = angle
	if absf(angle) < 0.0001:
		return
	var bone: int = rig.spine[0]
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(rig.forward_axis(sk), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)


func _bend_forelegs(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	for leg: Dictionary in rig.fore:
		rig.rotate(sk, int(leg.upper), axis, -0.06 * weight * scale)
		rig.rotate(sk, int(leg.lower), axis, 0.10 * weight * scale)


func _raise_hind_legs(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.hind.is_empty():
		return
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	var target := (up * 0.75 + forward * 0.45).normalized()
	for leg: Dictionary in rig.hind:
		var bone := int(leg.femur)
		var lower := int(leg.get("lower", -1))
		if bone < 0:
			continue
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if lower >= 0:
			direction = sk.get_bone_global_pose(lower).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var axis := direction.cross(target)
		if axis.length_squared() > 0.0001:
			rig.rotate(sk, bone, axis.normalized(), direction.angle_to(target) * 0.75 * weight)
		var outward := pose.origin - sk.get_bone_global_pose(rig.hips).origin
		outward.y = 0.0
		var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
		rig.rotate(sk, bone, forward, sign * _value("hind_spread", POSE1_HIND_SPREAD) * weight)
		if lower >= 0:
			rig.rotate(sk, lower, right, -0.55 * weight)


func _hug_forelegs(rig, sk: Skeleton3D, weight: float) -> void:
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	for leg: Dictionary in rig.fore:
		var upper := int(leg.upper)
		var lower := int(leg.lower)
		if upper >= 0 and rig.hips >= 0:
			var pose := sk.get_bone_global_pose(upper)
			var outward := pose.origin - sk.get_bone_global_pose(rig.hips).origin
			outward.y = 0.0
			var direction := sk.get_bone_global_pose(lower).origin - pose.origin
			var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
			rig.rotate(sk, upper, forward, sign * 0.45 * weight)
		rig.rotate(sk, upper, right, -0.55 * weight)
		rig.rotate(sk, lower, right, 1.1 * weight)
		rig.rotate(sk, upper, up, 0.18 * weight)
		rig.rotate(sk, lower, forward, 0.35 * weight)


func _aim_head(rig, sk: Skeleton3D, weight: float, scale: float, look_point: Vector3) -> void:
	if rig.neck.is_empty() or not look_point.is_finite():
		return
	var head: int = rig.neck[rig.neck.size() - 1]
	var head_pose := sk.get_bone_global_pose(head)
	var head_world := sk.global_transform * head_pose
	var to := look_point - head_world.origin
	if to.length_squared() < 0.0001:
		return
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var local := sk.global_basis.inverse() * to
	var flat := Vector2(local.x, local.z).length()
	var yaw := atan2(-local.x, -local.z) if flat > 0.001 else 0.0
	var pitch := atan2(local.y, flat)
	var shares: Array[float] = [0.30, 0.36, 0.34]
	for i: int in rig.neck.size():
		var share := shares[mini(i, shares.size() - 1)] * weight * scale
		rig.rotate(sk, rig.neck[i], up, clampf(yaw, -1.1, 1.1) * share)
		rig.rotate(sk, rig.neck[i], right, clampf(pitch, -0.8, 0.8) * share)


## Lift the head off the mattress by bending the neck "down" in the standing model. Applied
## after the head aim so the lift is a fixed offset, not something the aim can cancel.
func _neck_lift(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if rig.neck.size() < 2 or absf(degrees) < 0.0001:
		return
	var angle := deg_to_rad(degrees) * weight
	var right: Vector3 = rig.right_axis(sk)
	rig.rotate(sk, rig.neck[0], right, angle * 0.5)
	rig.rotate(sk, rig.neck[1], right, angle * 0.5)


func _nuzzle_pulse(clock: float) -> float:
	var period := maxf(0.1, _value("nuzzle_period", NUZZLE_PERIOD))
	var duration := maxf(0.05, _value("nuzzle_duration", NUZZLE_DURATION))
	var phase := fmod(clock, period)
	if phase > duration:
		return 0.0
	return sin(phase / duration * PI)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback


func _roll_head(rig, sk: Skeleton3D, weight: float, head_roll: float) -> void:
	if absf(head_roll) < 0.0001 or rig.neck.is_empty():
		return
	var head: int = rig.neck[rig.neck.size() - 1]
	if head < 0:
		return
	var pose := sk.get_bone_global_pose(head)
	pose.basis = Basis(rig.forward_axis(sk), head_roll * weight) * pose.basis
	sk.set_bone_global_pose(head, pose)
