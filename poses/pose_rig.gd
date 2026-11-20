extends RefCounted
## Bone cache and low-level helpers shared by pose recipes. All writes are in skeleton space.

var mare: Node3D
var root := -1
var hips := -1
var spine: Array[int] = []
var neck: Array[int] = []
var fore: Array[Dictionary] = []
var hind: Array[Dictionary] = []
var limits: Variant = null
var cached := false


func cache(mare_node: Node3D, sk: Skeleton3D) -> void:
	cached = true
	mare = mare_node
	limits = mare.get("joint_limits")
	hips = sk.find_bone("pony_hips")
	root = hips
	while root >= 0:
		var parent := sk.get_bone_parent(root)
		if parent < 0:
			break
		root = parent
	spine.clear()
	for name: String in ["pony_spine1", "pony_spine2", "pony_spine3"]:
		var bone := sk.find_bone(name)
		if bone >= 0:
			spine.append(bone)
	neck.clear()
	for name: String in ["pony_neck1", "pony_neck2", "pony_head"]:
		var bone := sk.find_bone(name)
		if bone >= 0:
			neck.append(bone)
	fore.clear()
	for side: String in ["L", "R"]:
		var upper := sk.find_bone("pony_upperArm_" + side)
		var lower := sk.find_bone("pony_lowerArm_" + side)
		if upper >= 0 and lower >= 0:
			fore.append({"upper": upper, "lower": lower, "side": side})
	hind.clear()
	for side: String in ["L", "R"]:
		var femur := sk.find_bone("pony_femur_" + side)
		var lower := sk.find_bone("pony_legLower_" + side)
		if femur >= 0:
			hind.append({"femur": femur, "lower": lower})


## Write a bone's local pose so its skeleton-space pose becomes `target`, using the parent's
## orthonormal rotation. Stock hiders collapse bones to 0.001 and that inversion would grow 1000×.
static func set_global(sk: Skeleton3D, bone: int, target: Transform3D) -> void:
	if sk == null or bone < 0:
		return
	if not target.origin.is_finite() or not target.basis.x.is_finite() \
			or not target.basis.y.is_finite() or not target.basis.z.is_finite():
		return
	var parent := sk.get_bone_parent(bone)
	var rotation := Basis.IDENTITY
	var origin := Vector3.ZERO
	if parent >= 0:
		var parent_pose := sk.get_bone_global_pose(parent)
		rotation = parent_pose.basis.orthonormalized()
		origin = parent_pose.origin
	var inverse := rotation.inverse()
	var local := Transform3D(inverse * target.basis, inverse * (target.origin - origin))
	if not local.origin.is_finite():
		return
	sk.set_bone_pose(bone, local)


## Rotate a bone in skeleton space, then clamp it with the pony's joint limits.
func rotate(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	set_global(sk, bone, pose)
	_limit(sk, bone)


## As `rotate()`, with no joint-limit clamp: the hand-authored base sits beyond the limits of the
## game's motion library, and a clamp would undo it together with its corrections.
func rotate_free(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	set_global(sk, bone, pose)


## Joint-limit clamp for `rotate()`; skipped for direct global-pose corrections.
func _limit(sk: Skeleton3D, bone: int) -> void:
	if limits == null or not limits.has_method("constrain"):
		return
	var held: Basis = limits.call("constrain", bone, Basis(sk.get_bone_pose_rotation(bone)))
	sk.set_bone_pose_rotation(bone, held.get_rotation_quaternion())


## A synthetic rig has no mare; the skeleton's own basis is the same frame.
func _body_basis(sk: Skeleton3D) -> Basis:
	return mare.global_basis if is_instance_valid(mare) else sk.global_basis


## Body-relative axes in skeleton space.
func right_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * _body_basis(sk).x).normalized()


func up_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * _body_basis(sk).y).normalized()


func forward_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * -_body_basis(sk).z).normalized()
