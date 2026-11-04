extends SkeletonModifier3D
## Moves only the Hips bone (the crotch/pelvis mesh) backward from Anon's fixed rump limit.
## Runs after BodyIK and restores the Spine and both upper legs to their pre-offset global
## poses, so the torso, head and planted legs do not follow the hip thrust.

var offset_world := Vector3.ZERO


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or offset_world.length_squared() < 0.0000001:
		return
	var hips := sk.find_bone("Hips")
	if hips < 0:
		return
	var spine := sk.find_bone("Spine")
	var left_leg := sk.find_bone("LeftUpperLeg")
	var right_leg := sk.find_bone("RightUpperLeg")
	var spine_pose := Transform3D.IDENTITY
	var left_pose := Transform3D.IDENTITY
	var right_pose := Transform3D.IDENTITY
	if spine >= 0:
		spine_pose = sk.get_bone_global_pose(spine)
	if left_leg >= 0:
		left_pose = sk.get_bone_global_pose(left_leg)
	if right_leg >= 0:
		right_pose = sk.get_bone_global_pose(right_leg)
	var local_offset := sk.global_transform.affine_inverse().basis * offset_world
	var hip_pose := sk.get_bone_global_pose(hips)
	hip_pose.origin += local_offset
	sk.set_bone_global_pose(hips, hip_pose)
	# Keep the body above and the legs exactly where BodyIK placed them. Only the Hips-weighted
	# crotch/pelvis vertices move.
	if spine >= 0:
		sk.set_bone_global_pose(spine, spine_pose)
	if left_leg >= 0:
		sk.set_bone_global_pose(left_leg, left_pose)
	if right_leg >= 0:
		sk.set_bone_global_pose(right_leg, right_pose)
