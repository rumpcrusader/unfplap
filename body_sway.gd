extends SkeletonModifier3D
## Standing upper-body sway on the thrust stroke (feature: standing_body_sway). The chest, neck
## and head move fore/aft with raw depth while the foreleg chains are pinned back to their original
## origins, so the hooves stay planted.
##

const BODY_SWAY_MAX_M := 0.035
const SWAY_STIFFNESS := 90.0
const SWAY_DAMPING := 16.0

var mare: Node3D
var runtime: Node

var _spine := -1
var _arms: Array[int] = []
var _cached := false
var _base_local_origin := Vector3.ZERO
var _offset := 0.0
var _velocity := 0.0


func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(mare) or not is_instance_valid(runtime):
		return
	var depth_value: Variant = runtime.get("depth")
	if depth_value == null:
		return
	# Inverted from the first pass: the upper body now rocks back on the inward stroke and
	# forward on the outward stroke. The spring gives it inertia instead of following mouse
	# depth directly; keep the exaggerated amplitude for this review.
	var target := -clampf(float(depth_value), 0.0, 1.0) * BODY_SWAY_MAX_M
	var accel := -SWAY_STIFFNESS * (_offset - target) - SWAY_DAMPING * _velocity
	_velocity += accel * delta
	_offset += _velocity * delta
	if absf(_offset) < 0.00001 and absf(_velocity) < 0.00001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if not _cached:
		_spine = sk.find_bone("pony_spine1")
		_arms.clear()
		for side: String in ["L", "R"]:
			var arm := sk.find_bone("pony_upperArm_" + side)
			if arm >= 0:
				_arms.append(arm)
		if _spine >= 0:
			_base_local_origin = sk.get_bone_pose(_spine).origin
		_cached = true
	if _spine < 0 or _arms.is_empty():
		return
	# The skeleton pose persists between frames. Reset the spine's local origin before applying
	# this frame's offset, or the translation would accumulate every modifier pass.
	var base := sk.get_bone_pose(_spine)
	base.origin = _base_local_origin
	sk.set_bone_pose(_spine, base)
	var forward := (sk.global_basis.inverse() * -mare.global_basis.z).normalized()
	if forward.length_squared() < 0.000001:
		return
	var saved: Array[Transform3D] = []
	for arm: int in _arms:
		saved.append(sk.get_bone_global_pose(arm))
	var body := sk.get_bone_global_pose(_spine)
	body.origin += forward * _offset
	sk.set_bone_global_pose(_spine, body)
	for i: int in _arms.size():
		var arm := sk.get_bone_global_pose(_arms[i])
		arm.origin = saved[i].origin
		sk.set_bone_global_pose(_arms[i], arm)
