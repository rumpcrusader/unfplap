extends SceneTree
## Dev-only bake tool: turns the game's standing reference capture (the fixture, or a provisional
## `body.glb` rest pose when no live capture exists) into the shipped v7 `poses/standing_pose.json`,
## and compares a baked asset with the reference recipe. The capture can be a live mid-step frame,
## so the paired limb chains are mirror-averaged about the sagittal plane before the recipe; that
## is what makes the baked stance symmetric. It never ships: `tools/` is outside the pack, and no
## shipped runtime script preloads it.
##
##   godot --headless --xr-mode off --path . --script res://mods/unfplap/tools/pose_bake.gd
##   ... -- --write   # bake and write the shipped asset
##   ... -- --check   # bake in memory and fail when the checked-in asset is stale
##
## The static capture/compare functions are shared by the lab, the exporter and the tests.

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RECIPE := preload("res://mods/unfplap/poses/standing_recipe.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const BODY := preload("res://world/characters/hybrid_mare/body.glb")

const STANDING_PATH := "res://mods/unfplap/poses/standing_pose.json"
const FIXTURE_PATH := "res://mods/unfplap/tests/poses/fixtures/standing_reference.json"
const PONY_BONES := AUTHORED.PONY_BONES

## The paired limb chains, in parent-to-child order. Centerline bones (`hips`, `spine1-3`,
## `neck1-2`) are deliberately absent: they are the mirror plane, not an average of two sides.
const MIRROR_PAIRS := [
	["pony_flank_L", "pony_flank_R"],
	["pony_femur_L", "pony_femur_R"],
	["pony_tibia_L", "pony_tibia_R"],
	["pony_legLower_L", "pony_legLower_R"],
	["pony_tarsal_L", "pony_tarsal_R"],
	["pony_hoof_L", "pony_hoof_R"],
	["pony_shoulder_L", "pony_shoulder_R"],
	["pony_upperArm_L", "pony_upperArm_R"],
	["pony_lowerArm_L", "pony_lowerArm_R"],
	["pony_wrist_L", "pony_wrist_R"],
	["pony_hand_L", "pony_hand_R"],
	["pony_finger_L", "pony_finger_R"],
]

## The reflection about the skeleton-space sagittal plane.
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))


## Records the current pose as a v7 asset. `world_frame` is the live bed or ground frame, and
## `contact_point` is the world support contact (the mattress or the ground). All values are stored
## as the JSON strings the runtime loader reads.
static func capture_pose(skeleton: Skeleton3D, world_frame: Transform3D, contact_point: Vector3,
		config: Dictionary = {}, size_name: String = "canon", body_scale: float = 1.0,
		pose_id: String = "standing", frame_kind: String = "ground") -> Dictionary:
	var data := {
		"version": 7,
		"id": pose_id,
		"space": AUTHORED.SPACE_LOCAL_REST,
		"frame": frame_kind,
		"rig": {
			"name": AUTHORED.RIG_NAME,
			"version": AUTHORED.RIG_VERSION,
			"bones": AUTHORED.RIG_BONES,
		},
		"reference": {
			"size": size_name,
			"body_scale": body_scale,
			"config": config.duplicate(true),
		},
		"variants": {},
	}
	if skeleton == null:
		return data
	skeleton.force_update_all_bone_transforms()
	var frame_inv := world_frame.affine_inverse()
	var root_bone := AUTHORED.root_bone(skeleton)
	var hips := skeleton.find_bone("pony_hips")
	var hips_frame := frame_inv * (skeleton.global_transform * skeleton.get_bone_global_pose(hips))
	var contact_frame := frame_inv * contact_point
	var anchor := {
		"bone": "pony_hips",
		"transform": var_to_str(hips_frame),
		"contact": var_to_str(hips_frame.affine_inverse() * contact_frame),
		"support": 0.0,
	}
	data["anchor"] = anchor
	data["root"] = var_to_str(frame_inv * (skeleton.global_transform
		* skeleton.get_bone_global_pose(root_bone)))
	data["pony"] = {"bones": delta_bones(skeleton)}
	return data


## The reference recipe applied at `config`, then captured. This is the one bake path: the bake
## tool, the standing bake button and the lab's bake button all use it. The reference is
## mirror-averaged first, so a live capture caught mid-step cannot freeze an asymmetric stance.
static func capture_asset(skeleton: Skeleton3D, world_frame: Transform3D, config: Dictionary,
		size_name: String, contact_point: Vector3, body_scale: float = 1.0,
		pose_id: String = "standing", frame_kind: String = "ground") -> Dictionary:
	if skeleton == null:
		return {}
	var rig: Variant = RIG.new()
	var mare := skeleton.get_parent() as Node3D
	rig.call("cache", mare if mare != null else skeleton, skeleton)
	symmetrise_stance(skeleton)
	var recipe: Variant = RECIPE.new()
	recipe.call("apply_reference", rig, skeleton, 1.0, config)
	skeleton.force_update_all_bone_transforms()
	return capture_pose(skeleton, world_frame, contact_point, config, size_name, body_scale,
		pose_id, frame_kind)


## Reflects a skeleton-space transform across the sagittal plane. A reflection matrix would flip
## the basis determinant, so the basis is conjugated (`M * basis * M`) to stay a proper rotation.
static func mirror_x(t: Transform3D) -> Transform3D:
	return Transform3D(MIRROR * t.basis * MIRROR, MIRROR * t.origin)


## The midpoint of a transform and its mirrored partner: averaged origin and slerped rotation.
static func mirror_mid(a: Transform3D, b: Transform3D) -> Transform3D:
	var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
	var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
	return Transform3D(Basis(qa.slerp(qb, 0.5)), a.origin.lerp(b.origin, 0.5))


## Mirror-averages every paired limb chain about the skeleton-space sagittal plane, leaving the
## centerline bones untouched. The original globals are sampled once, before any write, so each
## pair averages the captured pose rather than a half-written one. Returns the pairs written; a
## rig without some pairs is symmetrised partially, never refused.
static func symmetrise_stance(skeleton: Skeleton3D) -> int:
	if skeleton == null:
		return 0
	skeleton.force_update_all_bone_transforms()
	var captured := {}
	for pair: Array in MIRROR_PAIRS:
		for name: String in pair:
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				captured[name] = skeleton.get_bone_global_pose(bone)
	var written := 0
	for pair: Array in MIRROR_PAIRS:
		var left_name := str(pair[0])
		var right_name := str(pair[1])
		if not captured.has(left_name) or not captured.has(right_name):
			continue
		var left := skeleton.find_bone(left_name)
		var right := skeleton.find_bone(right_name)
		if left < 0 or right < 0:
			continue
		var left_pose := mirror_mid(captured[left_name], mirror_x(captured[right_name]))
		skeleton.set_bone_global_pose(left, left_pose)
		skeleton.set_bone_global_pose(right, mirror_x(left_pose))
		# The next pair in the chain hangs from this one and must read the written parents.
		skeleton.force_update_all_bone_transforms()
		written += 1
	return written


## One bone's local-rest delta: `rest.affine_inverse() * pose`. Rotation and position only; the
## runtime resets the pose scale to the rest scale.
static func delta_bones(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for name: String in PONY_BONES:
		var bone := skeleton.find_bone(name)
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone)
		var pose := skeleton.get_bone_pose(bone)
		var delta := rest.affine_inverse() * pose
		out[name] = {
			"rotation": var_to_str(delta.basis.get_rotation_quaternion().normalized()),
			"position": var_to_str(delta.origin),
		}
	return out


## Deterministic, tab-indented JSON. The bake and its `--check` compare this text, so a stale
## shipped asset is detected exactly.
static func serialize(asset: Dictionary) -> String:
	return JSON.stringify(asset, "\t")


## Writes the runtime asset. It refuses a test or fixture path: dev data is never generated into
## the tracked test tree.
static func write_asset(asset: Dictionary, path: String) -> String:
	if path.contains("tests/") or path.contains("fixtures/"):
		return "refusing to write test data at %s" % path
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s" % path
	file.store_string(serialize(asset))
	file.close()
	return ""


## Applies an asset and the reference recipe to the same rig and reports the worst bone error.
## `skeleton` should be at rest; the function resets it between the two passes.
static func compare(asset: Dictionary, skeleton: Skeleton3D, world_frame: Transform3D,
		config: Dictionary, size_name: String, body_scale: float = 1.0) -> Dictionary:
	var loader: Variant = AUTHORED.new()
	var parsed: Variant = JSON.parse_string(serialize(asset))
	var load_error := str(loader.call("load_data", parsed as Dictionary))
	if not load_error.is_empty():
		return {"ok": false, "error": load_error, "worst_deg": INF, "worst_m": INF}
	var rig: Variant = RIG.new()
	var mare := skeleton.get_parent() as Node3D
	rig.call("cache", mare if mare != null else skeleton, skeleton)
	# The reference is the recipe applied to the same symmetrised capture the bake used (the
	# fixture's stance, a rest rig in the synthetic test); `capture_asset` applied the same pose.
	symmetrise_stance(skeleton)
	var recipe: Variant = RECIPE.new()
	recipe.call("apply_reference", rig, skeleton, 1.0, config)
	skeleton.force_update_all_bone_transforms()
	var reference := _local_poses(skeleton)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	loader.call("apply_pony", skeleton, 1.0, world_frame, body_scale, size_name)
	skeleton.force_update_all_bone_transforms()
	var applied := _local_poses(skeleton)
	var worst_deg := 0.0
	var worst_m := 0.0
	var worst_name := ""
	for name: String in reference:
		if not applied.has(name):
			return {"ok": false, "error": "missing %s" % name, "worst_deg": INF,
				"worst_m": INF}
		var a: Transform3D = reference[name]
		var b: Transform3D = applied[name]
		var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
		var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
		var angle := rad_to_deg(qa.angle_to(qb))
		var distance := a.origin.distance_to(b.origin)
		if angle > worst_deg:
			worst_deg = angle
			worst_name = name
		worst_m = maxf(worst_m, distance)
	var ok := worst_deg <= 0.1 and worst_m <= 0.001
	return {
		"ok": ok, "error": "", "worst_deg": worst_deg, "worst_m": worst_m,
		"worst_name": worst_name, "bones": reference.size(),
	}


static func _local_poses(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for name: String in PONY_BONES:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			out[name] = skeleton.get_bone_pose(bone)
	return out


## The lowest point of the body mesh AABB in world space. The skinned mesh AABB ignores bone poses,
## so this is the documented approximation for the support contact.
static func body_contact(pony: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for node: Node in pony.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var world: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	if first:
		return Vector3.INF
	return box.position


# ---------------------------------------------------------------------------------------------
# The command-line tool


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var mode := _mode()
	var pony := BODY.instantiate() as Node3D
	root.add_child(pony)
	await process_frame
	var skeleton := _skeleton(pony)
	if skeleton == null:
		print("[pose_bake] FAIL no body skeleton")
		quit(1)
		return
	var provisional := not FileAccess.file_exists(FIXTURE_PATH)
	var frame := Transform3D.IDENTITY
	var config: Dictionary = RECIPE.reference_config()
	var size_name := "canon"
	var body_scale := 1.0
	var fixture_data: Dictionary = {}
	if provisional:
		print("[pose_bake] PROVISIONAL reference=rest")
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	else:
		var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
		if not fixture is Dictionary:
			print("[pose_bake] FAIL bad fixture JSON")
			quit(1)
			return
		fixture_data = fixture
		provisional = bool(fixture_data.get("provisional", false))
		if provisional:
			print("[pose_bake] PROVISIONAL reference=fixture")
		var frame_value: Variant = str_to_var(str(fixture_data.get("frame", "")))
		frame = frame_value if frame_value is Transform3D else Transform3D.IDENTITY
		size_name = str(fixture_data.get("size_name", "canon"))
		body_scale = float(fixture_data.get("body_scale", 1.0))
		_load_reference(skeleton, fixture_data)
		# The fixture's frame is the live ground frame. Stand the instantiated body in it, so the
		# captured anchor/root are frame-space values and not the fixture's world position.
		pony.global_transform = frame
	var contact := body_contact(pony)
	var asset := capture_asset(skeleton, frame, config, size_name, contact, body_scale,
		"standing", "ground")
	if mode != "check":
		var write_error := write_asset(asset, STANDING_PATH)
		if not write_error.is_empty():
			print("[pose_bake] FAIL %s" % write_error)
			quit(1)
			return
		print("[pose_bake] wrote %s bones=%d provisional=%s" % [
			STANDING_PATH,
			((asset.get("pony") as Dictionary).get("bones") as Dictionary).size(),
			str(provisional)])
	if mode != "write":
		var check_error := ""
		if not FileAccess.file_exists(STANDING_PATH):
			check_error = "no shipped asset at %s" % STANDING_PATH
		else:
			var shipped := FileAccess.get_file_as_string(STANDING_PATH)
			if shipped != serialize(asset):
				check_error = "the shipped asset is stale; run --write"
		if check_error.is_empty():
			# `capture_asset` left the recipe on the rig; compare needs the reference pose again.
			if fixture_data.is_empty():
				skeleton.reset_bone_poses()
				skeleton.force_update_all_bone_transforms()
			else:
				_load_reference(skeleton, fixture_data)
			var result := compare(asset, skeleton, frame, config, size_name, body_scale)
			if not bool(result.get("ok", false)):
				check_error = "compare failed: %s" % str(result)
			else:
				print("[pose_bake] compare bones=%d worst=%.5f m / %.4f deg" % [
					int(result.get("bones", 0)), float(result.get("worst_m", 0.0)),
					float(result.get("worst_deg", 0.0))])
		if not check_error.is_empty():
			print("[pose_bake] FAIL %s" % check_error)
			quit(1)
			return
	print("[pose_bake] PASS")
	quit(0)


func _mode() -> String:
	var mode := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--write":
			mode = "write"
		elif arg == "--check":
			mode = "check"
	return mode


func _skeleton(node: Node) -> Skeleton3D:
	for child: Node in node.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


## Puts the fixture's settled local poses back on the rig (the reference before the recipe).
func _load_reference(skeleton: Skeleton3D, fixture: Dictionary) -> void:
	skeleton.reset_bone_poses()
	var bones: Variant = fixture.get("bones", {})
	if bones is Dictionary:
		for name: Variant in (bones as Dictionary):
			var bone := skeleton.find_bone(str(name))
			var pose_value: Variant = str_to_var(str((bones as Dictionary)[name]))
			if bone >= 0 and pose_value is Transform3D:
				skeleton.set_bone_pose(bone, pose_value)
	skeleton.force_update_all_bone_transforms()