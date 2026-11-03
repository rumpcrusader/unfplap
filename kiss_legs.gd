extends SkeletonModifier3D
## Keep the two foreleg tips where they were when the pose-2 base kiss started. The base kiss
## bends the chest to reach Anon, and its chest carriers run after body_sway's upper-arm pin, so
## the hooves would otherwise slide. This modifier runs last and CCDs the real foreleg chains
## back to the captured hoof positions.

const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const PASSES := 12
const STEP_DEG := 8.0
const REACH_EPS_M := 0.003

var mare: Node3D
var runtime: Node

var _rig = RIG.new()
var _legs: Array[Dictionary] = []
var _targets: Array[Vector3] = []
var _captured := false


func capture() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_rig.cache(mare, sk)
	_legs.clear()
	_targets.clear()
	for side: String in ["L", "R"]:
		var upper := sk.find_bone("pony_upperArm_" + side)
		var lower := sk.find_bone("pony_lowerArm_" + side)
		var carpus := sk.find_bone("pony_wrist_" + side)
		if carpus < 0:
			carpus = sk.find_bone("pony_hand_" + side)
		var tip := sk.find_bone("pony_finger_%s_end" % side)
		if tip < 0:
			tip = carpus
		if upper < 0 or lower < 0 or tip < 0:
			continue
		_legs.append({"upper": upper, "lower": lower, "carpus": carpus, "tip": tip})
		_targets.append(sk.global_transform * sk.get_bone_global_pose(tip).origin)
	_captured = _legs.size() == 2


func _process_modification_with_delta(_delta: float) -> void:
	if not _captured:
		return
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	var to_sk := sk.global_transform.affine_inverse()
	for k: int in _legs.size():
		var leg: Dictionary = _legs[k]
		var tip := int(leg.tip)
		var target: Vector3 = to_sk * _targets[k]
		for _pass: int in PASSES:
			var tip_pose := sk.get_bone_global_pose(tip)
			if tip_pose.origin.distance_to(target) <= REACH_EPS_M:
				break
			for bone: int in [int(leg.carpus), int(leg.lower), int(leg.upper)]:
				if bone < 0:
					continue
				var at := sk.get_bone_global_pose(bone).origin
				var from := sk.get_bone_global_pose(tip).origin - at
				var to := target - at
				if from.length_squared() < 0.00000001 or to.length_squared() < 0.00000001:
					continue
				var axis := from.cross(to)
				if axis.length_squared() < 0.0000000001:
					continue
				_rig.rotate(sk, bone, axis.normalized(),
					minf(from.angle_to(to), deg_to_rad(STEP_DEG)))
