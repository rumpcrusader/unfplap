extends "res://mods/unfplap/tests/support/suite.gd"
## The hand-authored missionary pose asset the runtime poses from, and the rig check that refuses
## to pose a body missing one of its bones.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/poses/test_pose_asset.gd

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

## Every body bone the base pose must carry, in the pose lab's `PONY_BONES` order. The runtime
## writes only the bones the file holds and never resets the rest, so a missing bone keeps the
## game's own pose and breaks the chain it hangs from. A filter typo in the lab shows up here.
const REQUIRED := [
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
## Bones the game or the act animates every frame. Baking them would fight the gaze, lids, ears,
## wings, mane or tail.
const BANNED := ["pony_head", "pony_lid", "pony_ear", "pony_Wing", "pony_wing", "pony_Feather",
	"pony_foldedWing", "pony_tail", "rd_", "jaw", "EYETARGET", "MOUNT_"]



func run() -> void:
	var pose: Variant = AUTHORED.shared()
	check(pose != null, "asset instance")
	if pose == null:
		_finish()
		return
	check(bool(pose.get("available")), "asset available: %s" % str(pose.get("error")))
	check(int(pose.get("version")) == AUTHORED.CURRENT_VERSION,
		"version %d" % int(pose.get("version")))
	check(str(pose.get("space")) == AUTHORED.SPACE_LOCAL_REST, "local_rest space")
	check(str(pose.get("frame")) == "bed", "the missionary asset is a bed pose")
	check(int(pose.get("rig_version")) == AUTHORED.RIG_VERSION, "rig version")
	check(int(pose.get("rig_bones")) == AUTHORED.RIG_BONES, "rig bone count")
	var bones: Dictionary = pose.get("pony_bones")
	var banned: Array[String] = []
	for name: String in bones:
		for prefix: String in BANNED:
			if name.begins_with(prefix):
				banned.append(name)
	check(banned.is_empty(), "no runtime-owned bones in the base pose: %s" % str(banned))
	var missing: Array[String] = []
	for name: String in REQUIRED:
		if not bones.has(name):
			missing.append(name)
	check(missing.is_empty(), "every body bone is authored: %s" % str(missing))
	check(bones.size() == REQUIRED.size(), "pose carries %d bones, expected %d" % [
		bones.size(), REQUIRED.size()])
	var bad_rotation: Array[String] = []
	var bad_position: Array[String] = []
	for key: Variant in bones:
		var entry: Dictionary = bones[key]
		var rotation: Quaternion = entry["rotation"]
		var position: Vector3 = entry["position"]
		if absf(rotation.length() - 1.0) > 0.001:
			bad_rotation.append(str(key))
		if not position.is_finite():
			bad_position.append(str(key))
	check(bad_rotation.is_empty(), "unit bone rotations: %s" % str(bad_rotation))
	check(bad_position.is_empty(), "finite bone positions: %s" % str(bad_position))

	var anchor: Dictionary = pose.get("anchor")
	check(str(anchor.get("bone", "")) == "pony_hips", "the anchor is the hips")
	var anchor_pose: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
	check(anchor_pose.origin.is_finite(), "the anchor is finite")
	# Bed space: her anchor sits above the mattress, roughly on the bed centreline, inside the length.
	check(anchor_pose.origin.y > 0.02 and anchor_pose.origin.y < 0.4,
		"anchor height %.3f" % anchor_pose.origin.y)
	check(absf(anchor_pose.origin.x) <= 0.6, "anchor across the bed %.3f" % anchor_pose.origin.x)
	check(absf(anchor_pose.origin.z) <= 1.4, "anchor along the bed %.3f" % anchor_pose.origin.z)
	check(absf(anchor_pose.basis.determinant() - 1.0) < 0.001, "anchor basis is a rotation")
	var contact: Vector3 = anchor.get("contact", Vector3.INF)
	check(contact.is_finite(), "the contact is finite")
	check(not contact.is_zero_approx(), "the contact is authored")
	var root: Transform3D = pose.get("root")
	check(root.origin.is_finite(), "the root placement is finite")
	check(absf(root.basis.determinant() - 1.0) < 0.001, "root basis is a rotation")

	var anon_bones: Dictionary = pose.get("anon_bones")
	check(str(pose.get("anon_rig")) == "Anon3", "anon rig is Anon3: %s" % str(pose.get("anon_rig")))
	check(str(pose.get("anon_mode")) == "act_body", "anon mode is act_body")
	check(anon_bones.size() >= 10, "anon pose bones %d" % anon_bones.size())
	check((pose.get("anon_transform") as Transform3D).origin.is_finite(),
		"anon placement is finite")
	var bed_size: Vector3 = pose.get("bed_size")
	check(bed_size.x > 0.5 and bed_size.z > 1.0, "bed reference size %s" % str(bed_size))
	check((pose.get("variants") as Dictionary).is_empty(), "v1 ships no variants")
	var reference: Dictionary = pose.get("reference")
	check(float(reference.get("body_scale", 0.0)) == 1.0, "the reference is canon")

	# The authored shot positions are optional until they are placed in the lab, but every entry
	# present must be a usable bed-space camera.
	var shots: Dictionary = pose.get("shots")
	check(bool(pose.get("has_shots")) == not shots.is_empty(), "shot block agrees with its count")
	var bad_shots: Array[String] = []
	for key: Variant in shots:
		var shot: Transform3D = shots[key]
		if not shot.origin.is_finite() or shot.origin.y <= 0.2 or shot.origin.y >= 1.6:
			bad_shots.append(str(key))
	check(bad_shots.is_empty(), "shot positions are finite and over the mattress: %s" % str(bad_shots))
	check(bool(pose.call("has_shot", "start")) or shots.is_empty(), "has_shot agrees with the block")
	if shots.has("start") and shots.has("back"):
		var start: Transform3D = shots["start"]
		var back: Transform3D = shots["back"]
		check(start.origin.distance_to(back.origin) > 0.02, "the start and back ends differ")

	# Reloading the file in place is what the debug action does mid-act.
	check(AUTHORED.reload_file().is_empty(), "reload clears the error")
	check(bool(pose.get("available")), "available after reload")
	check(not bool(pose.call("apply_pony", null, 1.0, Transform3D.IDENTITY, 1.0)),
		"null skeleton is refused")
	_check_rig()
	_finish()


## The rig rule: the full body rig is accepted and one missing bone is reported by name.
func _check_rig() -> void:
	var pose: Variant = AUTHORED.new()
	pose.available = true
	pose.pony_bones = {}
	for name: String in REQUIRED:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
	var full := _rig_skeleton()
	check(pose.missing_bones(full).is_empty(), "a full rig has no missing bone")
	var broken := _rig_skeleton("pony_finger_L")
	var missing: Array = pose.missing_bones(broken)
	check(missing.size() == 1 and missing[0] == "pony_finger_L",
		"a broken rig reports exactly the missing bone: %s" % str(missing))
	check(pose.missing_bones(null).is_empty(), "a null skeleton reports nothing")


func _rig_skeleton(skip := "") -> Skeleton3D:
	var sk := Skeleton3D.new()
	root.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	for name: String in REQUIRED:
		if name == skip:
			continue
		var bone := sk.add_bone(name)
		sk.set_bone_parent(bone, armature)
	sk.reset_bone_poses()
	return sk


func _finish() -> void:
	if failures == 0:
		print("POSE_ASSET_PASS")
	finish()
