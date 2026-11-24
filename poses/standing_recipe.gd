extends "res://mods/unfplap/poses/pose_driver.gd"
## Standing skeleton recipe and the baked-base delta.

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

const STANDING_BOW := 2.4
const STANDING_FORELEG := 2.0
const STANDING_FORELEG_SPREAD := 0.172
const STANDING_HIND_SPREAD := 0.32
const STANDING_CHIN_UP_DEG := 30.0
const STANDING_NECK_DOWN_DEG := 30.0

var _config: Dictionary = {}


## The effective reference config the standing base is baked at: the act defaults, not
## `default.poses.standing`. The bake writes it into the asset and the bake test pins it.
static func reference_config() -> Dictionary:
	return {
		"bow": STANDING_BOW,
		"foreleg": STANDING_FORELEG,
		"foreleg_spread": STANDING_FORELEG_SPREAD,
		"hind_spread": STANDING_HIND_SPREAD,
		"chin_up_deg": STANDING_CHIN_UP_DEG,
		"neck_down_deg": STANDING_NECK_DOWN_DEG,
	}


## The full reference recipe: the bake and the parity baseline. It is never called by the shipped
## runtime, which uses the baked base plus the live-setting difference.
func apply_reference(rig, sk: Skeleton3D, weight: float, config: Dictionary) -> void:
	_config = config
	_stance(rig, sk, weight)


## This recipe splits its base from its overlays, so a pose with a delta keeps base, delta, overlay.
func splits_base() -> bool:
	return true


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	apply_base(rig, sk, weight, state)
	apply_overlay(rig, sk, weight, state)


## The baked base: the authored asset plus the live-setting difference from its reference. False when
## the asset or the ground frame is unavailable; there is no procedural fallback.
func apply_base(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> bool:
	_config = state.get("config", {})
	var authored: AUTHORED = state.get("authored")
	var frame: Variant = state.get("ground_frame")
	if authored == null or not frame is Transform3D or not authored.available:
		return false
	authored.apply_pony(sk, weight, frame as Transform3D, float(state.get("body_scale", 1.0)),
		str(state.get("size_name", "")))
	sk.force_update_all_bone_transforms()
	_apply_difference(rig, sk, weight)
	return true


## The live settings as deltas from the reference. The head is not in the asset, so it gets the
## absolute chin and only the neck is a difference.
func _apply_difference(rig, sk: Skeleton3D, weight: float) -> void:
	var reference := reference_config()
	_bow_body(rig, sk, weight, _value("bow") - float(reference["bow"]))
	# The head is not in the asset: apply its full reference bow and chin.
	_bow_head(rig, sk, weight * _value("bow"))
	_bend_forelegs(rig, sk, weight, _value("foreleg") - float(reference["foreleg"]))
	_spread_hind(rig, sk, weight,
		_value("hind_spread") - float(reference["hind_spread"]))
	_chin_neck(rig, sk, weight,
		_value("chin_up_deg"),
		_value("neck_down_deg") - float(reference["neck_down_deg"]))
	_spread_fore(rig, sk, weight, _value("foreleg_spread"))


## The moveable neck overlay: the head-back lift. The oral swing is the oral row's own delta, so
## it is not part of this base pose.
func apply_overlay(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	var head_back := float(state.get("head_back", 0.0))
	if head_back > 0.001:
		_raise_head(rig, sk, weight * head_back)


## The full stance: the bow, foreleg bend and spread, hind spread and the neck/chin curve. Bake and
## parity only; the live path applies the reference recipe once at capture time.
func _stance(rig, sk: Skeleton3D, weight: float) -> void:
	_bow(rig, sk, weight, _value("bow"))
	_bend_forelegs(rig, sk, weight, _value("foreleg"))
	_spread_fore(rig, sk, weight, _value("foreleg_spread"))
	_spread_hind(rig, sk, weight, _value("hind_spread"))
	_chin_neck(rig, sk, weight,
		_value("chin_up_deg"),
		_value("neck_down_deg"))


func _value(key: String) -> float:
	return float(_config[key])


func _bow(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	_spine_bow(rig, sk, weight, scale)
	_bow_body(rig, sk, weight, scale)
	_bow_head(rig, sk, weight * scale)


## The neck part of the bow, without the head: the head is not in the 30-bone asset, so the live
## path applies its full reference angle itself.
func _bow_body(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	if rig.neck.is_empty():
		return
	var axis: Vector3 = rig.right_axis(sk)
	var neck_angles: Array[float] = [-0.08, -0.06, -0.04]
	var neck_count := maxi(0, rig.neck.size() - 1)
	for i: int in neck_count:
		rig.rotate(sk, rig.neck[i], axis, neck_angles[mini(i, neck_angles.size() - 1)] * weight * scale)


## The bow's share on the head (`pony_head`), the same last neck angle.
func _bow_head(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.neck.size() < 2:
		return
	var axis: Vector3 = rig.right_axis(sk)
	rig.rotate(sk, rig.neck[rig.neck.size() - 1], axis, -0.04 * weight)


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


## `target` is measured from the centreline, not from the current pose; adding the hoof-line
## delta keeps the baked placement unchanged.
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
		var tip := sk.find_bone("pony_finger_%s" % side)
		if tip < 0:
			tip = sk.find_bone("pony_finger_%s_end" % side)
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
	# The head's global pose must see the neck it hangs from, before the chin is applied.
	sk.force_update_all_bone_transforms()
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
