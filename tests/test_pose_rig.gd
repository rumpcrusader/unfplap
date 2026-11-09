extends SceneTree
## The rig check: the authored pose must not pose a body that is missing one of its bones.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_pose_rig.gd

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


func run() -> void:
	var pose := AUTHORED.new()
	pose.available = true
	pose.pony_bones = {}
	for name: String in PONY_BONES:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}

	# A full rig is accepted: nothing is missing.
	var full := _skeleton()
	check(pose.missing_bones(full).is_empty(), "full rig has no missing bones")

	# One bone missing is reported, and only that one.
	var broken := _skeleton("pony_finger_L")
	var missing := pose.missing_bones(broken)
	check(missing.size() == 1 and missing[0] == "pony_finger_L",
		"broken rig reports the missing bone: %s" % str(missing))

	# A null rig is refused rather than crashing.
	check(pose.missing_bones(null).is_empty(), "null skeleton reports nothing")

	_finish()


func _skeleton(skip := "") -> Skeleton3D:
	var sk := Skeleton3D.new()
	root.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	for name: String in PONY_BONES:
		if name == skip:
			continue
		var bone := sk.add_bone(name)
		sk.set_bone_parent(bone, armature)
	sk.reset_bone_poses()
	return sk


func _finish() -> void:
	print("POSE_RIG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_RIG_PASS")
	quit(0 if failures == 0 else 1)
