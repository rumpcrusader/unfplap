extends SkeletonModifier3D
## Lab-only tail offset. Moves the hair tail base by `offset` in hair-skeleton space and rotates
## the first tail joint around the moved base by `rotation` (Euler radians). Runs after the game's
## tail motion and the lab's aside pose; no runtime code uses it.

var offset := Vector3.ZERO
var euler := Vector3.ZERO


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var pelvis := sk.find_bone("mPelvis")
	var tail1 := sk.find_bone("mTail1")
	if pelvis < 0 or tail1 < 0:
		return
	var base := sk.get_bone_global_pose(pelvis)
	base.origin += offset
	sk.set_bone_global_pose(pelvis, base)
	if euler.is_zero_approx():
		return
	var turn := Basis.from_euler(euler)
	var tail := sk.get_bone_global_pose(tail1)
	tail.origin = base.origin + turn * (tail.origin - base.origin)
	tail.basis = turn * tail.basis
	sk.set_bone_global_pose(tail1, tail)
