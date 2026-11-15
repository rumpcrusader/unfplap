extends RefCounted
## Standing (Standing) skeleton recipe.

const STANDING_BOW := 2.4
const STANDING_FORELEG := 2.0
const STANDING_FORELEG_SPREAD := 0.172
const STANDING_HIND_SPREAD := 0.32
const STANDING_CHIN_UP_DEG := 30.0
const STANDING_NECK_DOWN_DEG := 30.0

var _config: Dictionary = {}


## The effective reference config the standing base is baked at: the act defaults, not the
## `default.poses.standing` block (the presentation overrides its neck values). The bake writes
## this into the asset and the bake test pins it.
static func reference_config() -> Dictionary:
	return {
		"bow": STANDING_BOW,
		"foreleg": STANDING_FORELEG,
		"foreleg_spread": STANDING_FORELEG_SPREAD,
		"hind_spread": STANDING_HIND_SPREAD,
		"chin_up_deg": STANDING_CHIN_UP_DEG,
		"neck_down_deg": STANDING_NECK_DOWN_DEG,
	}


## The full reference recipe: the bake and the parity baseline. It is stretch-independent and is
## never called by the shipped runtime, which uses the baked base plus the live-setting difference.
func apply_reference(rig, sk: Skeleton3D, weight: float, config: Dictionary) -> void:
	_config = config
	_stance(rig, sk, weight)


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	if bool(state.get("stretch", false)):
		# The external Idle Life holder owns the body, the stance and the ground plant. The act
		# keeps only its head-back lift on top.
		apply_overlay(rig, sk, weight, state)
		return
	apply_base(rig, sk, weight, state)
	apply_overlay(rig, sk, weight, state)


## The stance: the bow, the foreleg bend and spread, the hind spread and the neck/chin curve. False
## while the external stretch holder owns the body; the two-base form then skips this side's delta.
func apply_base(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> bool:
	_config = state.get("config", {})
	if bool(state.get("stretch", false)):
		return false
	_stance(rig, sk, weight)
	return true


## The full stance: the bow, foreleg bend and spread, hind spread and the neck/chin curve.
func _stance(rig, sk: Skeleton3D, weight: float) -> void:
	_bow(rig, sk, weight, _value("bow", STANDING_BOW))
	_bend_forelegs(rig, sk, weight, _value("foreleg", STANDING_FORELEG))
	_spread_fore(rig, sk, weight, _value("foreleg_spread", STANDING_FORELEG_SPREAD))
	_spread_hind(rig, sk, weight, _value("hind_spread", STANDING_HIND_SPREAD))
	_chin_neck(rig, sk, weight,
		_value("chin_up_deg", STANDING_CHIN_UP_DEG),
		_value("neck_down_deg", STANDING_NECK_DOWN_DEG))


## The moveable neck overlay: the head-back lift. The oral neck swing is the oral row's procedural
## delta (`poses/standing_oral_recipe.gd`), not part of this base pose. The two-base form crossfades
## this overlay after the blended base.
func apply_overlay(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	var head_back := float(state.get("head_back", 0.0))
	if head_back > 0.001:
		_raise_head(rig, sk, weight * head_back)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback


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
