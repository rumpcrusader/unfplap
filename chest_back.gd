extends SkeletonModifier3D
## Pushes Anon's chest backward from the camera in the standing act. The head/camera pose is
## restored after the move, so the view stays put while the chest clears it. 0 is off.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")

var player: Node3D

var _chest := -1
var _head := -1


func _process_modification_with_delta(_delta: float) -> void:
	var back_m := TUNABLES.get_float("presentation.standing.chest_back_m")
	if absf(back_m) < 0.00001:
		return
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(player):
		return
	if _chest < 0:
		_chest = sk.find_bone("Chest")
		if _chest < 0:
			_chest = sk.find_bone("Spine2")
		_head = sk.find_bone("Head")
	if _chest < 0:
		return
	var head_pose := sk.get_bone_global_pose(_head) if _head >= 0 else Transform3D.IDENTITY
	var chest_pose := sk.get_bone_global_pose(_chest)
	var scale := maxf(sk.global_basis.get_scale().x, 0.001)
	var back := (sk.global_transform.affine_inverse().basis * player.global_basis.z).normalized()
	chest_pose.origin += back * (back_m / scale)
	sk.set_bone_global_pose(_chest, chest_pose)
	# Keep the camera/head where BodyIK put it; the neck absorbs the offset.
	if _head >= 0:
		sk.set_bone_global_pose(_head, head_pose)
