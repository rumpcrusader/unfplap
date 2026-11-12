extends SceneTree
## The hand-authored missionary pose asset the runtime poses from.
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
	var pose: Variant = AUTHORED.shared()
	check(pose != null, "asset instance")
	if pose == null:
		_finish()
		return
	check(bool(pose.get("available")), "asset available: %s" % str(pose.get("error")))
	check(int(pose.get("version")) >= int(AUTHORED.MIN_VERSION), "version %d" % int(pose.get("version")))
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

	var frame: Transform3D = pose.get("pony_frame")
	check(frame.origin.is_finite(), "pony placement is finite")
	# Bed space: her root sits above the mattress, roughly on the bed centreline, inside the length.
	check(frame.origin.y > 0.2 and frame.origin.y < 1.2, "placement height %.3f" % frame.origin.y)
	check(absf(frame.origin.x) <= 0.6, "placement across the bed %.3f" % frame.origin.x)
	check(absf(frame.origin.z) <= 1.4, "placement along the bed %.3f" % frame.origin.z)
	check(absf(frame.basis.determinant() - 1.0) < 0.001, "placement basis is a rotation")

	var anon_bones: Dictionary = pose.get("anon_bones")
	check(str(pose.get("anon_rig")) == "Anon3", "anon rig is Anon3: %s" % str(pose.get("anon_rig")))
	check(anon_bones.size() >= 10, "anon pose bones %d" % anon_bones.size())
	check((pose.get("anon_frame") as Transform3D).origin.is_finite(), "anon placement is finite")
	var bed_size: Vector3 = pose.get("bed_size")
	check(bed_size.x > 0.5 and bed_size.z > 1.0, "bed reference size %s" % str(bed_size))

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
	_finish()


func _finish() -> void:
	print("POSE_ASSET_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_ASSET_PASS")
	quit(0 if failures == 0 else 1)
