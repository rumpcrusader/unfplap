extends SceneTree
## Dev-only: runs the real missionary recipe on the real pony rig, with the authored base pose, and
## checks that the runtime path (base + overlays) lands where the pose says it should, in an
## arbitrary bed frame. This is the headless half of the in-game pose check.
##
##   godot --headless --xr-mode off --path . --script res://mods/unfplap/tools/pose_runtime_check.gd
##
## It never ships: `tools/` is outside the pack.

const BODY := preload("res://world/characters/hybrid_mare/body.glb")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const MISSIONARY := preload("res://mods/unfplap/poses/missionary_recipe.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

## Bones the overlays never touch, so the recipe's base must match a bare base application exactly.
## The full body set: a bone left out of the file keeps the game's own pose at runtime.
const BODY_BONES := ["pony_hips", "pony_spine1", "pony_spine2", "pony_spine3",
	"pony_neck1", "pony_neck2",
	"pony_flank_L", "pony_femur_L", "pony_tibia_L", "pony_legLower_L", "pony_tarsal_L",
	"pony_hoof_L",
	"pony_flank_R", "pony_femur_R", "pony_tibia_R", "pony_legLower_R", "pony_tarsal_R",
	"pony_hoof_R",
	"pony_shoulder_L", "pony_upperArm_L", "pony_lowerArm_L", "pony_wrist_L", "pony_hand_L",
	"pony_finger_L",
	"pony_shoulder_R", "pony_upperArm_R", "pony_lowerArm_R", "pony_wrist_R", "pony_hand_R",
	"pony_finger_R"]
## The gaze solve and the nuzzle own the neck, so the recipe is compared against the bare asset on
## everything else.
const OVERLAY_BONES := ["pony_neck1", "pony_neck2"]


class FakeMare:
	extends Node3D
	var joint_limits: Variant = null
	var body_scale := 1.0


func _initialize() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var pony: Node3D = BODY.instantiate()
	host.add_child(pony)
	await process_frame
	var skeleton: Skeleton3D = null
	for node: Node in pony.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		print("[pose_runtime] FAIL no skeleton in body.glb")
		quit(1)
		return
	var mare := FakeMare.new()
	mare.name = "FakeMare"
	mare.global_transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, -2.0))
	host.add_child(mare)
	var rig = RIG.new()
	rig.cache(mare, skeleton)
	var pose: Variant = AUTHORED.shared()
	if not bool(pose.get("available")):
		print("[pose_runtime] FAIL asset: %s" % str(pose.get("error")))
		quit(1)
		return
	# A bed frame moved and yawed away from the lab, its mattress surface where a real one is.
	var frame := Transform3D(Basis(Vector3.UP, 1.1), Vector3(3.0, 0.62, -2.0))
	var look_point: Vector3 = frame * Vector3(0.05, 0.30, 0.45)
	var state := {
		"config": {},
		"authored": pose,
		"bed_frame": frame,
		"body_scale": 1.0,
		"look_point": look_point,
		"clock": 0.0,
		"climaxing": false,
	}
	var recipe = MISSIONARY.new()
	recipe.apply(rig, skeleton, 1.0, state)
	skeleton.force_update_all_bone_transforms()
	var baked := _joints(skeleton)
	# The same frame through the bare asset, from rest, is the reference the overlays must preserve
	# for every bone they do not own.
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	pose.call("apply_pony", skeleton, 1.0, frame, 1.0)
	skeleton.force_update_all_bone_transforms()
	var reference := _joints(skeleton)
	var worst := 0.0
	var worst_name := ""
	for name: String in BODY_BONES:
		if OVERLAY_BONES.has(name):
			continue
		if not baked.has(name) or not reference.has(name):
			print("[pose_runtime] FAIL missing %s" % name)
			worst = INF
			continue
		var delta: float = (baked[name] as Vector3).distance_to(reference[name])
		if delta > worst:
			worst = delta
			worst_name = name
	print("[pose_runtime] base through recipe worst=%.5f m %s" % [worst, worst_name])

	# The runtime never resets the rig: it writes only the bones the file holds. Perturb every bone
	# first, apply the bare asset again and require the same joints, which proves the file carries
	# every body bone instead of leaning on a reset.
	skeleton.reset_bone_poses()
	var tilt := Quaternion(Vector3.RIGHT, 0.35)
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i, tilt)
		skeleton.set_bone_pose_position(i,
			skeleton.get_bone_pose_position(i) + Vector3(0.01, 0.02, 0.03))
	skeleton.force_update_all_bone_transforms()
	pose.call("apply_pony", skeleton, 1.0, frame, 1.0)
	skeleton.force_update_all_bone_transforms()
	var resumed := _joints(skeleton)
	var worst_resume := 0.0
	var resume_name := ""
	for name: String in BODY_BONES:
		if not resumed.has(name) or not reference.has(name):
			worst_resume = INF
			resume_name = name
			continue
		var delta: float = (resumed[name] as Vector3).distance_to(reference[name])
		if delta > worst_resume:
			worst_resume = delta
			resume_name = name
	print("[pose_runtime] apply over a posed rig worst=%.5f m %s" % [worst_resume, resume_name])

	# Shape checks in bed space: she rests on the mattress, her head is toward the head end, and
	# her hind hooves are lifted around him.
	var hips: Vector3 = frame.affine_inverse() * (baked["pony_hips"] as Vector3)
	var head: Vector3 = frame.affine_inverse() * (baked["pony_head"] as Vector3)
	var hoof: Vector3 = frame.affine_inverse() * (baked["pony_hoof_L"] as Vector3)
	var hips_up := hips.y
	var head_forward := head.z
	var hoof_up := hoof.y - hips.y
	print("[pose_runtime] bed space hips=%.3f head=%.3f hoof=%.3f" % [hips_up, head_forward, hoof_up])
	var ok := worst <= 0.001 and worst_resume <= 0.001 \
		and hips_up > 0.0 and hips_up < 0.15 and head_forward > 0.2 and hoof_up > 0.2
	print("[pose_runtime] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _joints(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for bone in skeleton.get_bone_count():
		out[skeleton.get_bone_name(bone)] = \
			skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return out
