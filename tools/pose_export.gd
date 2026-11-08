extends SceneTree
## Dev-only: exports the hand-posed rigs saved in pose_lab.tscn to the runtime pose JSON.
## The scene is the authoring source; this is the command-line twin of the lab's **Save pose**
## button, so a pose can be exported without opening the editor. It also loads the file back into a
## fresh rig and reports the worst joint drift, so a broken export cannot slip through.
##
##   godot --headless --xr-mode off --path . --script res://mods/unfplap/tools/pose_export.gd
##
## It never ships: `tools/` is outside the pack.

const LAB := preload("res://mods/unfplap/tools/pose_lab.tscn")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")


func _initialize() -> void:
	var authored: Node = await _open()
	var before := _bones(authored)
	authored.call("_save_pose")
	# Round trip: read the file back into an untouched rig and compare the joints it was authored
	# from. This catches a bad bed frame or a bone that is written in the wrong space.
	var check: Node = await _open()
	check.call("_load_pose")
	var after := _bones(check)
	var worst := 0.0
	var worst_name := ""
	for name: String in before:
		if not after.has(name):
			print("[pose_export] FAIL missing %s after reload" % name)
			worst = INF
			continue
		var delta: float = (before[name] as Vector3).distance_to(after[name])
		if delta > worst:
			worst = delta
			worst_name = name
	print("[pose_export] round-trip bones=%d worst=%.5f m %s" % [
		before.size(), worst, worst_name])
	# Then the runtime path itself: `apply_pony` at full weight into a moved, yawed bed frame must
	# put every joint at the authored position carried by that frame.
	var moved := _apply_runtime(check, before)
	print("[pose_export] runtime apply worst=%.5f m %s" % [moved, worst_name])
	var ok := worst <= 0.001 and moved <= 0.001
	if ok:
		print("[pose_export] PASS")
	else:
		print("[pose_export] FAIL drift round-trip=%.4f runtime=%.4f" % [worst, moved])
	authored.queue_free()
	check.queue_free()
	quit(0 if ok else 1)


## Resets the rig to rest, runs the game's own application path into a bed frame that is rotated and
## moved, and returns the worst joint error against the authored joints carried into that frame.
func _apply_runtime(scene: Node, authored: Dictionary) -> float:
	var sk: Variant = scene.get("_pony_skel")
	if not sk is Skeleton3D:
		return INF
	var skeleton := sk as Skeleton3D
	var probe := Transform3D(Basis(Vector3.UP, 1.1), Vector3(3.0, 0.2, -1.5))
	# The authored joints are lab-world; the asset is bed-relative, so carry them into the moved
	# bed frame before comparing against the placed rig.
	var carry: Transform3D = probe * (scene.call("_pose_frame") as Transform3D).affine_inverse()
	var pose: Variant = AUTHORED.shared()
	if not bool(pose.get("available")):
		print("[pose_export] FAIL runtime asset: %s" % str(pose.get("error")))
		return INF
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	pose.call("apply_pony", skeleton, 1.0, probe, 1.0)
	skeleton.force_update_all_bone_transforms()
	var worst := 0.0
	for name: String in authored:
		var bone := skeleton.find_bone(name)
		if bone < 0:
			return INF
		var got: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, got.distance_to(carry * (authored[name] as Vector3)))
	return worst


## A scene with the saved rigs adopted, in the tree so global transforms resolve. Anon rigs run
## their own `_ready` first; `_adopt_or_build` stops them and the pony is untouched by them.
func _open() -> Node:
	var scene: Node = LAB.instantiate()
	root.add_child(scene)
	await process_frame
	scene.call("_adopt_or_build")
	# The scene no longer stores the pose (Godot drops instance-child overrides on save), so the
	# exporter applies the exported JSON exactly like the editor does before writing it back.
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
	var names: Array = scene.get_script().get_script_constant_map().get("PONY_BONES", [])
	skeleton.force_update_all_bone_transforms()
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			out[name] = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return out
