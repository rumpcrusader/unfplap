extends RefCounted
## Horse (legacy Pose 2) standing skeleton recipe.

const STANDING_BOW := 2.4
const STANDING_FORELEG := 2.0
const STANDING_HIND_SPREAD := 0.16
var _config: Dictionary = {}


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	_bow(rig, sk, weight, _value("bow", STANDING_BOW))
	_bend_forelegs(rig, sk, weight, _value("foreleg", STANDING_FORELEG))
	_spread_hind(rig, sk, weight, _value("hind_spread", STANDING_HIND_SPREAD))
	var head_back := float(state.get("head_back", 0.0))
	if head_back > 0.001:
		_raise_head(rig, sk, weight * head_back)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback


func _bow(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	var spine_angles: Array[float] = [-0.05, -0.06, -0.04]
	for i: int in rig.spine.size():
		rig.rotate(sk, rig.spine[i], axis, spine_angles[mini(i, spine_angles.size() - 1)] * weight * scale)
	var neck_angles: Array[float] = [-0.08, -0.06, -0.04]
	for i: int in rig.neck.size():
		rig.rotate(sk, rig.neck[i], axis, neck_angles[mini(i, neck_angles.size() - 1)] * weight * scale)


func _bend_forelegs(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	for leg: Dictionary in rig.fore:
		rig.rotate(sk, int(leg.upper), axis, -0.06 * weight * scale)
		rig.rotate(sk, int(leg.lower), axis, 0.10 * weight * scale)


func _spread_hind(rig, sk: Skeleton3D, weight: float, angle: float) -> void:
	if rig.hind.is_empty() or rig.hips < 0:
		return
	var hips_origin := sk.get_bone_global_pose(rig.hips).origin
	var forward: Vector3 = rig.forward_axis(sk)
	for leg: Dictionary in rig.hind:
		var bone := int(leg.femur)
		if bone < 0:
			continue
		var pose := sk.get_bone_global_pose(bone)
		var outward := pose.origin - hips_origin
		outward.y = 0.0
		var direction: Vector3 = -rig.up_axis(sk)
		var lower := int(leg.get("lower", -1))
		if lower >= 0:
			direction = sk.get_bone_global_pose(lower).origin - pose.origin
		var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
		rig.rotate(sk, bone, forward, sign * angle * weight)


func _raise_head(rig, sk: Skeleton3D, weight: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	var angles: Array[float] = [0.24, 0.22, 0.18]
	for i: int in rig.neck.size():
		rig.rotate(sk, rig.neck[i], axis, angles[mini(i, angles.size() - 1)] * weight)
