extends SkeletonModifier3D
## Standing body sway on the thrust stroke (feature: standing_body_sway). The pelvis, chest, neck
## and head move fore/aft with raw depth while both hind-femur and foreleg chains are pinned back
## to their original origins, so the hooves stay planted. The pelvis motion also publishes its
## world offset, which the standing Anon body applies to its pinned hip so the two move together.
##

const BODY_SWAY_MAX_M := 0.035
const SWAY_STIFFNESS := 90.0
const SWAY_DAMPING := 16.0

var mare: Node3D
## The typed act view: the live depth and the world-space sway the standing Anon reads.
var facts: Variant

var _hips := -1
var _roots: Array[int] = []
var _cached := false
var _base_local_origin := Vector3.ZERO
var _offset := 0.0
var _velocity := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_apply(delta)
	if facts != null:
		facts.perf("body_sway", Time.get_ticks_usec() - started)


func _exit_tree() -> void:
	if facts != null:
		facts.standing_sway_offset = Vector3.ZERO


func _apply(delta: float) -> void:
	if not is_instance_valid(mare) or facts == null:
		return
	var depth_value: Variant = facts.depth
	# Inverted from the first pass: the body now rocks back on the inward stroke and forward on
	# the outward stroke. The spring gives it inertia instead of following mouse depth directly;
	# keep the exaggerated amplitude for this review.
	var target := -clampf(float(depth_value), 0.0, 1.0) * BODY_SWAY_MAX_M
	var accel := -SWAY_STIFFNESS * (_offset - target) - SWAY_DAMPING * _velocity
	_velocity += accel * delta
	_offset += _velocity * delta
	var sk := get_skeleton()
	if sk == null:
		return
	if not _cached:
		_hips = sk.find_bone("pony_hips")
		_roots.clear()
		for side: String in ["L", "R"]:
			for bone_name: String in ["pony_upperArm_" + side, "pony_femur_" + side]:
				var root := sk.find_bone(bone_name)
				if root >= 0:
					_roots.append(root)
		if _hips >= 0:
			_base_local_origin = sk.get_bone_pose(_hips).origin
		_cached = true
	if _hips < 0 or _roots.is_empty():
		return
	# The skeleton pose persists between frames. Reset the pelvis's local origin before applying
	# this frame's offset, or the translation would accumulate every modifier pass.
	var base := sk.get_bone_pose(_hips)
	base.origin = _base_local_origin
	sk.set_bone_pose(_hips, base)
	var forward := (sk.global_basis.inverse() * -mare.global_basis.z).normalized()
	if forward.length_squared() < 0.000001:
		return
	var saved: Array[Transform3D] = []
	for root: int in _roots:
		saved.append(sk.get_bone_global_pose(root))
	if absf(_offset) > 0.00001:
		var body := sk.get_bone_global_pose(_hips)
		body.origin += forward * _offset
		sk.set_bone_global_pose(_hips, body)
		facts.standing_sway_offset = sk.global_transform.basis * (forward * _offset)
	else:
		facts.standing_sway_offset = Vector3.ZERO
	# Restore every limb root after the pelvis move so the hooves stay on the ground.
	for i: int in _roots.size():
		var root := sk.get_bone_global_pose(_roots[i])
		root.origin = saved[i].origin
		sk.set_bone_global_pose(_roots[i], root)
