extends SceneTree
## Dev-only: exports the pose authored in `pose_lab.tscn` to the v7 runtime JSON and verifies the
## round trip, the moved-frame runtime apply and the four size cases. It is the command-line twin
## of the lab's **Save pose** button.
##
##   godot --headless --xr-mode off --path . --script res://mods/unfplap/tools/pose_export.gd
##   ... -- --out user://pose_export_check.json --check   # scratch file, do not touch the asset
##
## The shipped `poses/missionary_pose.json` is only overwritten by the C4 conversion commit; the
## gate runs with `--out`/`--check`. It never ships: `tools/` is outside the pack.

const LAB := preload("res://mods/unfplap/tools/pose_lab.tscn")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const BODY_BONES := AUTHORED.PONY_BONES
const SIZES := [1.0, 1.35, 1.7, 2.3]


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := _args()
	var lab: Node = LAB.instantiate()
	root.add_child(lab)
	await process_frame
	lab.call("_adopt_or_build")
	var source := str(lab.call("pose_path"))
	lab.call("_load_pose")
	var before := _bones(lab)
	var lab_frame: Transform3D = lab.call("_pose_frame")
	var out_path := source
	if args.has("out"):
		out_path = str(args["out"])
	elif args.has("check"):
		out_path = "user://pose_export_check.json"
	lab.set("pose_path_override", out_path)
	lab.call("_save_pose")

	var check: Node = await _open(out_path)
	var after := _bones(check)
	var worst := 0.0
	var worst_name := ""
	for name: String in before:
		if not after.has(name):
			print("[pose_export] FAIL missing %s after reload" % name)
			worst = INF
			continue
		var delta: float = (before[name] as Vector3).distance_to(after[name] as Vector3)
		if delta > worst:
			worst = delta
			worst_name = name
	print("[pose_export] round-trip bones=%d worst=%.5f m %s" % [
		before.size(), worst, worst_name])

	var moved := _apply_runtime(check, before, lab_frame, out_path)
	print("[pose_export] runtime apply worst=%.5f m %s" % [moved, worst_name])
	var sized := _four_sizes(check, lab_frame, out_path)
	print("[pose_export] four-size worst=%.5f m / %.4f deg %s" % [
		sized["position"], sized["rotation"], sized["name"]])
	var ok := worst <= 0.001 and moved <= 0.001 \
		and float(sized["position"]) <= 0.002 and float(sized["rotation"]) <= 0.1
	if ok:
		print("[pose_export] PASS out=%s" % out_path)
	else:
		print("[pose_export] FAIL drift round-trip=%.4f runtime=%.4f size=%.4f/%.4f" % [
			worst, moved, float(sized["position"]), float(sized["rotation"])])
	lab.queue_free()
	check.queue_free()
	quit(0 if ok else 1)


## Resets the rig to rest, runs the game's own application path into a bed frame that is rotated
## and moved, and returns the worst joint error against the authored joints carried into that
## frame.
func _apply_runtime(scene: Node, authored: Dictionary, lab_frame: Transform3D,
		path: String) -> float:
	var sk: Variant = scene.get("_pony_skel")
	if not sk is Skeleton3D:
		return INF
	var skeleton := sk as Skeleton3D
	var probe := Transform3D(Basis(Vector3.UP, 1.1), Vector3(3.0, 0.2, -1.5))
	var carry: Transform3D = probe * lab_frame.affine_inverse()
	var pose: Variant = AUTHORED.shared(path)
	if not bool(pose.get("available")):
		print("[pose_export] FAIL runtime asset: %s" % str(pose.get("error")))
		return INF
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	pose.call("apply_pony", skeleton, 1.0, probe, 1.0, "canon")
	skeleton.force_update_all_bone_transforms()
	var worst := 0.0
	for name: String in authored:
		var bone := skeleton.find_bone(name)
		if bone < 0:
			return INF
		var got: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, got.distance_to(carry * (authored[name] as Vector3)))
	return worst


## The body pose is size-invariant: placing the same asset at the four shipped sizes changes the
## root and the contact, never the hips-relative bone pose. The rig pivot carries `body_scale`, so
## the skeleton-space root pose stays orthonormal.
func _four_sizes(scene: Node, lab_frame: Transform3D, path: String) -> Dictionary:
	var sk: Variant = scene.get("_pony_skel")
	if not sk is Skeleton3D:
		return {"position": INF, "rotation": INF, "name": "no skeleton"}
	var skeleton := sk as Skeleton3D
	var pony: Node3D = scene.get("_pony")
	var pose: Variant = AUTHORED.shared(path)
	var probe := Transform3D(Basis(Vector3.UP, 0.6), Vector3(-1.0, 0.0, 2.0))
	var canon := {}
	var worst_pos := 0.0
	var worst_deg := 0.0
	var worst_name := ""
	var original := pony.transform
	for size: float in SIZES:
		pony.transform.basis = original.basis * Basis.from_scale(Vector3.ONE * size)
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
		pose.call("apply_pony", skeleton, 1.0, probe, size, "canon")
		skeleton.force_update_all_bone_transforms()
		var root := AUTHORED.root_bone(skeleton)
		var root_pose := skeleton.get_bone_global_pose(root)
		if absf(root_pose.basis.determinant() - 1.0) > 0.001:
			print("[pose_export] FAIL root basis at %.2f det=%.4f" % [
				size, root_pose.basis.determinant()])
			worst_pos = INF
		var contact: Vector3 = pose.call("place_origin", pose.call("contact_world", probe),
			probe, size)
		if absf(contact.y - probe.origin.y) > 0.001:
			print("[pose_export] FAIL contact at %.2f y=%.4f" % [size, contact.y])
			worst_pos = INF
		var local := {}
		for name: String in BODY_BONES:
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				local[name] = skeleton.get_bone_pose(bone)
		if canon.is_empty():
			canon = local
			continue
		for name: String in canon:
			if not local.has(name):
				worst_pos = INF
				continue
			var a: Transform3D = canon[name]
			var b: Transform3D = local[name]
			var distance := a.origin.distance_to(b.origin)
			if distance > worst_pos:
				worst_pos = distance
				worst_name = name
			var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
			var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
			worst_deg = maxf(worst_deg, rad_to_deg(qa.angle_to(qb)))
	pony.transform = original
	return {"position": worst_pos, "rotation": worst_deg, "name": worst_name,
		"frame": lab_frame}


## A scene with the saved pose adopted, in the tree so global transforms resolve.
func _open(path: String) -> Node:
	var scene: Node = LAB.instantiate()
	root.add_child(scene)
	await process_frame
	scene.call("_adopt_or_build")
	scene.set("pose_path_override", path)
	scene.call("_load_pose")
	return scene


## World origin of every body bone the asset writes, keyed by bone name. Everything else in the
## rig (lids, mane, tail, wings) is the game's or the act's at runtime and is deliberately not
## baked, so it is not part of the comparison either.
func _bones(scene: Node) -> Dictionary:
	var out := {}
	var sk: Variant = scene.get("_pony_skel")
	if not sk is Skeleton3D:
		return out
	var skeleton := sk as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	for name: String in BODY_BONES:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			out[name] = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return out


func _args() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		var arg: String = args[i]
		if arg == "--check":
			out["check"] = true
		elif arg == "--out" and i + 1 < args.size():
			out["out"] = args[i + 1]
	return out