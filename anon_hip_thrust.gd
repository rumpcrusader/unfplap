extends SkeletonModifier3D
## Carries the pelvis region on the act's depth stroke. The offset is graded down the spine so the
## crotch and lower belly move as one soft mass, the chest bends a little, and everything from the
## upper chest up plus both planted legs stay exactly where BodyIK put them.
##
## Grade table: Hips 1.0, Spine 0.55, Chest 0.25, UpperLeg 0.35, UpperChest and everything below
## the thighs 0. No per-vertex weights are needed because a bone's global pose moves all of its
## weighted vertices, and pinning a child after a parent keeps the knee where it was.

var offset_world := Vector3.ZERO

## How much of the offset each bone above the hips receives.
const GRADES := {"Spine": 0.55, "Chest": 0.25, "UpperChest": 0.1,
	"LeftUpperLeg": 0.35, "RightUpperLeg": 0.35}
## Bones that must not follow at all: everything above the chest and the lower legs, so the knees
## and planted feet stay exactly where BodyIK put them.
const PINNED := ["Neck", "Head",
	"LeftLowerLeg", "LeftFoot", "LeftToes", "RightLowerLeg", "RightFoot", "RightToes"]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or offset_world.length_squared() < 0.0000001:
		return
	var hips := sk.find_bone("Hips")
	if hips < 0:
		return
	var local_offset := sk.global_transform.affine_inverse().basis * offset_world
	var before := {}
	for name: String in GRADES:
		var bone := sk.find_bone(name)
		if bone >= 0:
			before[name] = sk.get_bone_global_pose(bone)
	var pinned := {}
	for name: String in PINNED:
		var bone := sk.find_bone(name)
		if bone >= 0:
			pinned[name] = sk.get_bone_global_pose(bone)
	var hip_pose := sk.get_bone_global_pose(hips)
	hip_pose.origin += local_offset
	sk.set_bone_global_pose(hips, hip_pose)
	# Grade the spine so the waist travels with the pelvis instead of being left behind.
	for name: String in GRADES:
		if not before.has(name):
			continue
		var pose: Transform3D = before[name]
		pose.origin += local_offset * float(GRADES[name])
		sk.set_bone_global_pose(sk.find_bone(name), pose)
	# Restore the pinned bones last: their children (arms, head, feet) then keep the pose BodyIK
	# gave them.
	for name: String in PINNED:
		if pinned.has(name):
			sk.set_bone_global_pose(sk.find_bone(name), pinned[name])
