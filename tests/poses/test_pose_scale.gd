extends SceneTree
## The authored pose's size handling: the rig's own pivot scales her body, so the placement has to
## scale the same way, or a bigger pony renders as a canon body shifted along the bed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/poses/test_pose_scale.gd

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

## The 30 body bones the runtime writes, in the pose lab's order.
const PONY_BONES := [
	"pony_hips",
	"pony_spine1", "pony_spine2", "pony_spine3",
	"pony_neck1", "pony_neck2",
	"pony_flank_L", "pony_femur_L", "pony_tibia_L", "pony_legLower_L", "pony_tarsal_L",
	"pony_hoof_L",
	"pony_flank_R", "pony_femur_R", "pony_tibia_R", "pony_legLower_R", "pony_tarsal_R",
	"pony_hoof_R",
	"pony_shoulder_L", "pony_upperArm_L", "pony_lowerArm_L", "pony_wrist_L", "pony_hand_L",
	"pony_finger_L",
	"pony_shoulder_R", "pony_upperArm_R", "pony_lowerArm_R", "pony_wrist_R", "pony_hand_R",
	"pony_finger_R",
]

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	# Hand-built pose, so the test does not depend on the shipped file's numbers.
	var pose := AUTHORED.new()
	pose.available = true
	pose.pony_frame = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	pose.pony_bones = {}
	for name: String in PONY_BONES:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
	pose.pony_bones["pony_hips"] = {"rotation": Quaternion.IDENTITY,
		"position": Vector3(0.0, 0.1, 0.0)}

	# Canon: the body sits at the authored height with no scale.
	var canon := _skeleton(1.0)
	var canon_world := _apply(pose, canon)
	check(near(canon_world.y, 0.6), "canon hips at 0.6: %.3f" % canon_world.y)

	# JRHNBR: the rig's pivot scales her body, so the placement must scale with it. The hips land
	# at 1.35 x the canon height, not at the canon height.
	var big := _skeleton(1.35)
	var big_world := _apply(pose, big)
	check(near(big_world.y, 0.81), "JRHNBR hips at 1.35 x 0.6: %.3f" % big_world.y)
	check(near(big_world.x, canon_world.x * 1.35), "JRHNBR lateral scale")
	check(near(big_world.z, canon_world.z * 1.35), "JRHNBR longitudinal scale")

	# The root's skeleton-space pose stays orthonormal: the pivot carries the scale, so a scaled
	# root basis would multiply the body twice.
	var root := AUTHORED.root_bone(big)
	var root_pose := big.get_bone_global_pose(root)
	check(near(root_pose.basis.determinant(), 1.0),
		"root basis is orthonormal: %.4f" % root_pose.basis.determinant())

	_finish()


func _skeleton(scale: float) -> Skeleton3D:
	var parent := Node3D.new()
	parent.scale = Vector3.ONE * scale
	root.add_child(parent)
	var sk := Skeleton3D.new()
	parent.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	for name: String in PONY_BONES:
		var bone := sk.add_bone(name)
		sk.set_bone_parent(bone, armature)
	sk.reset_bone_poses()
	return sk


func _apply(pose: Variant, sk: Skeleton3D) -> Vector3:
	check(bool(pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY,
		sk.global_transform.basis.get_scale().x)), "apply_pony")
	var hips := sk.find_bone("pony_hips")
	return sk.global_transform * sk.get_bone_global_pose(hips).origin


func _finish() -> void:
	print("POSE_SCALE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_SCALE_PASS")
	quit(0 if failures == 0 else 1)
