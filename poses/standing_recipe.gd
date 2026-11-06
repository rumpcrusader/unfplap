extends RefCounted
## Standing (Standing) skeleton recipe.

const STANDING_BOW := 2.4
const STANDING_FORELEG := 2.0
const STANDING_FORELEG_SPREAD := 0.172
const STANDING_HIND_SPREAD := 0.32
const STANDING_CHIN_UP_DEG := 30.0
const STANDING_NECK_DOWN_DEG := 15.0

## Play-bow stance (`features.standing_play_bow`): the rump stays up, the chest drops and the
## front legs stretch out ahead instead of tucking under the chest. The hips pitch nose-down and
## the hind femurs counter it, so the hind legs stay planted under her.
const PLAY_BOW_BOW := 3.0
const PLAY_BOW_PITCH_DEG := 8.0
const PLAY_BOW_SHOULDER_DEG := 35.0
const PLAY_BOW_FORELEG_DEG := 35.0
const PLAY_BOW_LOWER_DEG := 55.0
const PLAY_BOW_WRIST_DEG := 10.0
const PLAY_BOW_HAND_DEG := 10.0
const PLAY_BOW_FORELEG_SPREAD := 0.14
const PLAY_BOW_HIND_SPREAD := 0.10
const PLAY_BOW_NECK1_DEG := -30.0
const PLAY_BOW_NECK2_DEG := -22.0
const PLAY_BOW_HEAD_DEG := 10.0
## integration: oral keeps her muzzle pointed along the shaft while her neck swings.
const ORAL_HEAD_COUNTER := 0.75
var _config: Dictionary = {}


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	if bool(_config.get("play_bow", false)):
		_apply_play_bow(rig, sk, weight, state)
		return
	_bow(rig, sk, weight, _value("bow", STANDING_BOW))
	_bend_forelegs(rig, sk, weight, _value("foreleg", STANDING_FORELEG))
	_spread_fore(rig, sk, weight, _value("foreleg_spread", STANDING_FORELEG_SPREAD))
	_spread_hind(rig, sk, weight, _value("hind_spread", STANDING_HIND_SPREAD))
	_chin_neck(rig, sk, weight,
		_value("chin_up_deg", STANDING_CHIN_UP_DEG),
		_value("neck_down_deg", STANDING_NECK_DOWN_DEG))
	_oral_neck(rig, sk, weight)
	var head_back := float(state.get("head_back", 0.0))
	if head_back > 0.001:
		_raise_head(rig, sk, weight * head_back)


## Deep stretch: body pitched down over the shoulder, front legs reaching forward with the
## elbows open, and the neck hanging so the snout is near the ground. Head-back still lifts her
## face while she looks at Anon.
func _apply_play_bow(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	var pitch := deg_to_rad(_value("play_bow_pitch_deg", PLAY_BOW_PITCH_DEG)) * weight
	if rig.hips >= 0:
		rig.rotate(sk, rig.hips, axis, -pitch)
	for leg: Dictionary in rig.hind:
		rig.rotate(sk, int(leg.femur), axis, pitch)
	_spine_bow(rig, sk, weight, _value("play_bow_bow", PLAY_BOW_BOW))
	var shoulder := deg_to_rad(_value("play_bow_shoulder_deg", PLAY_BOW_SHOULDER_DEG)) * weight
	var upper := deg_to_rad(_value("play_bow_upper_deg", PLAY_BOW_FORELEG_DEG)) * weight
	var lower := deg_to_rad(_value("play_bow_lower_deg", PLAY_BOW_LOWER_DEG)) * weight
	var wrist := deg_to_rad(_value("play_bow_wrist_deg", PLAY_BOW_WRIST_DEG)) * weight
	var hand := deg_to_rad(_value("play_bow_hand_deg", PLAY_BOW_HAND_DEG)) * weight
	for leg: Dictionary in rig.fore:
		var side := str(leg.get("side", ""))
		rig.rotate(sk, sk.find_bone("pony_shoulder_" + side), axis, shoulder)
		rig.rotate(sk, int(leg.upper), axis, upper)
		rig.rotate(sk, int(leg.lower), axis, lower)
		rig.rotate(sk, sk.find_bone("pony_wrist_" + side), axis, wrist)
		rig.rotate(sk, sk.find_bone("pony_hand_" + side), axis, hand)
	_spread_fore(rig, sk, weight, _value("play_bow_foreleg_spread", PLAY_BOW_FORELEG_SPREAD))
	_spread_hind(rig, sk, weight, _value("play_bow_hind_spread", PLAY_BOW_HIND_SPREAD))
	var neck1 := deg_to_rad(_value("play_bow_neck1_deg", PLAY_BOW_NECK1_DEG)) * weight
	var neck2 := deg_to_rad(_value("play_bow_neck2_deg", PLAY_BOW_NECK2_DEG)) * weight
	var head := deg_to_rad(_value("play_bow_head_deg", PLAY_BOW_HEAD_DEG)) * weight
	if not rig.neck.is_empty():
		rig.rotate(sk, rig.neck[0], axis, neck1)
	if rig.neck.size() > 1:
		rig.rotate(sk, rig.neck[1], axis, neck2)
	if rig.neck.size() > 2:
		rig.rotate(sk, rig.neck[2], axis, head)
	var head_back := float(state.get("head_back", 0.0))
	if head_back > 0.001:
		_raise_head(rig, sk, weight * head_back)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback


## integration: swing the neck through the oral bob and counter-rotate the head so her muzzle
## stays pointed along the shaft. Zero keys leave the normal standing pose untouched.
func _oral_neck(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.neck.size() < 3:
		return
	var pitch := _value("oral_pitch", 0.0) * weight
	var yaw := _value("oral_yaw", 0.0) * weight
	var roll := _value("oral_roll", 0.0) * weight
	if absf(pitch) + absf(yaw) + absf(roll) < 0.0001:
		return
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	for i: int in 2:
		rig.rotate(sk, rig.neck[i], right, pitch * 0.5)
		rig.rotate(sk, rig.neck[i], up, yaw * 0.5)
	var head: int = rig.neck[2]
	rig.rotate(sk, head, right, -pitch * ORAL_HEAD_COUNTER)
	rig.rotate(sk, head, up, -yaw * ORAL_HEAD_COUNTER)
	rig.rotate(sk, head, forward, roll)


func _bow(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	_spine_bow(rig, sk, weight, scale)
	var axis: Vector3 = rig.right_axis(sk)
	var neck_angles: Array[float] = [-0.08, -0.06, -0.04]
	for i: int in rig.neck.size():
		rig.rotate(sk, rig.neck[i], axis, neck_angles[mini(i, neck_angles.size() - 1)] * weight * scale)


func _spine_bow(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	var spine_angles: Array[float] = [-0.05, -0.06, -0.04]
	for i: int in rig.spine.size():
		rig.rotate(sk, rig.spine[i], axis, spine_angles[mini(i, spine_angles.size() - 1)] * weight * scale)


func _bend_forelegs(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	for leg: Dictionary in rig.fore:
		rig.rotate(sk, int(leg.upper), axis, -0.06 * weight * scale)
		rig.rotate(sk, int(leg.lower), axis, 0.10 * weight * scale)


## `target` is the absolute outward half-angle from the body centreline. Measuring the current
## hoof line first keeps the default placement unchanged while still allowing wider/narrower
## stance values.
func _spread_fore(rig, sk: Skeleton3D, weight: float, target: float) -> void:
	if rig.fore.size() < 2:
		return
	var right: Vector3 = rig.right_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var left := sk.get_bone_global_pose(int(rig.fore[0].upper)).origin
	var right_origin := sk.get_bone_global_pose(int(rig.fore[1].upper)).origin
	var center := (left + right_origin) * 0.5
	for leg: Dictionary in rig.fore:
		var upper := int(leg.upper)
		if upper < 0:
			continue
		var side := str(leg.get("side", ""))
		var tip := sk.find_bone("pony_finger_%s_end" % side)
		if tip < 0:
			tip = sk.find_bone("pony_wrist_%s" % side)
		if tip < 0:
			tip = int(leg.get("lower", -1))
		if tip < 0:
			continue
		var upper_pose := sk.get_bone_global_pose(upper)
		var tip_pose := sk.get_bone_global_pose(tip)
		var outward := tip_pose.origin - center
		var lateral := absf(outward.dot(right))
		var drop := maxf(outward.dot(-up), 0.01)
		var current := atan2(lateral, drop)
		var delta := target - current
		if absf(delta) < 0.00001:
			continue
		var direction := tip_pose.origin - upper_pose.origin
		var side_out := upper_pose.origin - center
		side_out.y = 0.0
		var sign := 1.0 if forward.cross(direction).dot(side_out) >= 0.0 else -1.0
		rig.rotate(sk, upper, forward, sign * delta * weight)


## Standing S-curve: neck reaches down/forward while the chin lifts, so she follows the thrust
## with her snoot instead of standing rigidly upright.
func _chin_neck(rig, sk: Skeleton3D, weight: float, chin_deg: float, neck_deg: float) -> void:
	if rig.neck.is_empty():
		return
	var axis: Vector3 = rig.right_axis(sk)
	var neck_count := maxi(0, rig.neck.size() - 1)
	if neck_count > 0:
		var per := deg_to_rad(neck_deg) * weight / float(neck_count)
		for i: int in neck_count:
			rig.rotate(sk, rig.neck[i], axis, -per)
	var head: int = rig.neck[rig.neck.size() - 1]
	rig.rotate(sk, head, axis, deg_to_rad(chin_deg) * weight)


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
