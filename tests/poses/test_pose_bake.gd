extends "res://mods/unfplap/tests/support/suite.gd"
## The bake tool's capture/compare math on a synthetic rig, the deterministic writer and its test
## path refusal. The shipped standing asset is the rig's rest pose plus the reference recipe, and
## the live base is proven equal to the old procedural pose on every owned bone (head included).
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_bake.gd

const BAKE := preload("res://mods/unfplap/tools/pose_bake.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RECIPE := preload("res://mods/unfplap/poses/standing_recipe.gd")
const ORAL := preload("res://mods/unfplap/poses/standing_oral_recipe.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const BODY := preload("res://world/characters/hybrid_mare/body.glb")

const STANDING_PATH := "res://mods/unfplap/poses/standing_pose.json"
const MISSIONARY_PATH := "res://mods/unfplap/poses/missionary_pose.json"
const SIZES := [1.0, 1.35, 1.7, 2.3]

const PONY_BONES := AUTHORED.PONY_BONES



func run() -> void:
	_check_capture()
	_check_compare()
	_check_writer()
	await _check_shipped_standing()
	await _check_missionary()
	if failures == 0:
		print("POSE_BAKE_PASS")
	finish()


func _check_capture() -> void:
	var sk := _skeleton()
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.0, -0.5))
	var contact := frame * Vector3(0.0, 0.0, 0.0)
	var pose := BAKE.capture_pose(sk, frame, contact, {}, "canon", 1.0, "standing", "ground")
	check(str(pose.get("space", "")) == AUTHORED.SPACE_LOCAL_REST, "capture writes local_rest")
	check(str(pose.get("frame", "")) == "ground", "capture writes the frame kind")
	check(str(pose.get("id", "")) == "standing", "capture writes the id")
	var bones: Dictionary = (pose.get("pony") as Dictionary).get("bones", {})
	check(bones.size() == PONY_BONES.size(), "capture writes every body bone: %d" % bones.size())
	var anchor: Dictionary = pose.get("anchor", {})
	check(str(anchor.get("bone", "")) == "pony_hips", "the anchor is the hips")
	check(float(anchor.get("support", -1.0)) == 0.0, "the support is the frame height")
	var contact_local: Vector3 = str_to_var(str(anchor.get("contact", "")))
	check(contact_local.is_finite(), "the captured contact is finite")
	var root: Transform3D = str_to_var(str(pose.get("root", "")))
	check(root.origin.is_finite(), "the captured root is finite")
	_free(sk)


func _check_compare() -> void:
	var sk := _skeleton()
	sk.force_update_all_bone_transforms()
	var frame := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var config := RECIPE.reference_config()
	check(config.size() == 6, "the reference config carries the six keys")
	var contact := BAKE.body_contact(sk.get_parent() as Node3D)
	if not contact.is_finite():
		# The synthetic rig has no mesh; use the frame origin as the support point.
		contact = frame.origin
	var asset := BAKE.capture_asset(sk, frame, config, "canon", contact, 1.0, "standing", "ground")
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var result := BAKE.compare(asset, sk, frame, config, "canon", 1.0)
	check(bool(result.get("ok", false)), "the baked asset matches the reference recipe: %s"
		% str(result))
	check(int(result.get("bones", 0)) == PONY_BONES.size(), "compare covers every body bone")
	check(float(result.get("worst_deg", 999.0)) <= 0.1, "rotations round-trip")
	check(float(result.get("worst_m", 999.0)) <= 0.001, "positions round-trip")
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var bigger := BAKE.compare(asset, sk, frame, config, "canon", 1.35)
	check(bool(bigger.get("ok")), "canon body at 1.35")
	_free(sk)


func _check_writer() -> void:
	var sk := _skeleton()
	var asset := BAKE.capture_pose(sk, Transform3D.IDENTITY, Vector3.ZERO, {}, "canon", 1.0,
		"standing", "ground")
	var text := BAKE.serialize(asset)
	check(text == BAKE.serialize(asset), "the writer is deterministic")
	var path := "user://unfplap_pose_bake_test.json"
	check(str(BAKE.write_asset(asset, path)).is_empty(), "the scratch asset writes")
	var loader: Variant = AUTHORED.new()
	check(str(loader.call("load_file", path)).is_empty(), "the scratch asset loads")
	check(not str(BAKE.write_asset(asset,
		"res://mods/unfplap/tests/poses/fixtures/bake_guard.json")).is_empty(),
		"the writer refuses a fixture path")
	_free(sk)


## The shipped standing asset is exactly the rig's rest pose plus the reference recipe, and the
## body pose is size-invariant while the hips stay over the anchor and the contact on the ground.
func _check_shipped_standing() -> void:
	var pony: Node3D = BODY.instantiate()
	root.add_child(pony)
	await process_frame
	var sk := _find_skeleton(pony)
	check(sk != null, "the reference rig has a skeleton")
	if sk == null:
		return
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var frame := Transform3D.IDENTITY
	var config := RECIPE.reference_config()
	var contact := BAKE.body_contact(pony)
	if not contact.is_finite():
		contact = frame.origin
	var asset := BAKE.capture_asset(sk, frame, config, "canon", contact, 1.0,
		"standing", "ground")
	check(BAKE.serialize(asset) == FileAccess.get_file_as_string(STANDING_PATH),
		"the shipped standing asset is the rest pose + reference recipe")
	var asset_root: Transform3D = str_to_var(str(asset.get("root", "")))
	check(asset_root.origin.length() < 2.0,
		"the baked root is frame-local, not a world position")
	var anchor_transform: Transform3D = str_to_var(str(
		(asset.get("anchor") as Dictionary).get("transform", "")))
	check(anchor_transform.origin.length() < 2.0,
		"the baked anchor is frame-local, not a world position")
	var loader: Variant = AUTHORED.new()
	check(str(loader.call("load_file", STANDING_PATH)).is_empty(), "the shipped asset loads")
	check(bool(loader.call("usable", "ground")), "the shipped asset is a ground pose")
	var reference: Dictionary = loader.get("reference")
	var reference_config: Variant = reference.get("config", {})
	check(reference_config == config, "the asset reference config equals the recipe")
	check((loader.get("variants") as Dictionary).is_empty(), "the standing asset ships no variants")

	var original := pony.transform
	var anchor_world: Transform3D = loader.call("anchor_world", frame)
	var support := float(loader.call("support"))
	var canon := {}
	var worst_pos := 0.0
	var worst_deg := 0.0
	for size: float in SIZES:
		pony.transform.basis = original.basis * Basis.from_scale(Vector3.ONE * size)
		sk.reset_bone_poses()
		sk.force_update_all_bone_transforms()
		check(bool(loader.call("apply_pony", sk, 1.0, frame, size, "canon")),
			"the asset applies at %.2f" % size)
		sk.force_update_all_bone_transforms()
		var root := AUTHORED.root_bone(sk)
		check(absf(sk.get_bone_global_pose(root).basis.determinant() - 1.0) <= 0.001,
			"the skeleton-space root stays orthonormal at %.2f" % size)
		var hips := sk.find_bone("pony_hips")
		var hips_world: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		var lift := float(loader.call("body_lift", frame, size))
		check(absf(hips_world.x - anchor_world.origin.x) <= 0.0001
			and absf(hips_world.z - anchor_world.origin.z) <= 0.0001,
			"the hips stay over the anchor at %.2f" % size)
		check(absf(hips_world.y - (anchor_world.origin.y + lift)) <= 0.0001,
			"the hips ride the contact lift at %.2f" % size)
		var placed_contact: Vector3 = loader.call("place_origin",
			loader.call("contact_world", frame), frame, size)
		check(absf(placed_contact.y - (frame.origin.y + support)) <= 0.0001,
			"the contact stays on the support at %.2f" % size)
		var local := {}
		for name: String in PONY_BONES:
			var bone := sk.find_bone(name)
			if bone >= 0:
				local[name] = sk.get_bone_pose(bone)
		if canon.is_empty():
			canon = local
			continue
		for name: String in canon:
			var a: Transform3D = canon[name]
			var b: Transform3D = local[name]
			worst_pos = maxf(worst_pos, a.origin.distance_to(b.origin))
			var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
			var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
			worst_deg = maxf(worst_deg, rad_to_deg(qa.angle_to(qb)))
	check(worst_pos <= 0.002, "the body positions are size-invariant: %.5f m" % worst_pos)
	check(worst_deg <= 0.5, "the body rotations are size-invariant: %.4f deg" % worst_deg)
	pony.transform = original
	# The stance guard: the baked base is rotation-only and keeps a real width. A bake once
	# mirror-averaged the pair origins about the sagittal plane and collapsed both legs onto the
	# centreline; `compare()` could not see it because it averaged the reference the same way.
	var bones: Dictionary = (asset.get("pony") as Dictionary).get("bones", {})
	var worst_shift := 0.0
	for name: Variant in bones:
		var shift: Variant = str_to_var(str((bones[name] as Dictionary).get("position", "")))
		if shift is Vector3:
			worst_shift = maxf(worst_shift, (shift as Vector3).length())
	check(worst_shift <= 0.005, "the baked base is rotation-only: %.5f m" % worst_shift)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	check(bool(loader.call("apply_pony", sk, 1.0, frame, 1.0, "canon")),
		"the asset applies at canon for the stance width")
	sk.force_update_all_bone_transforms()
	var hoof_l := sk.get_bone_global_pose(sk.find_bone("pony_hoof_L")).origin
	var hoof_r := sk.get_bone_global_pose(sk.find_bone("pony_hoof_R")).origin
	var width := absf(hoof_l.x - hoof_r.x)
	check(width >= 0.1, "the hind stance keeps its width: %.3f m" % width)
	check(hoof_l.x * hoof_r.x < 0.0, "the hind hooves stay on opposite sides")
	_check_old_pose_parity(pony, sk, frame, config)
	_check_oral_parity(pony, sk, frame, config)

	root.remove_child(pony)
	pony.free()


## The live base and the old procedural recipe produce the same pose, head included. This is the
## "100% corresponds" proof: `apply_reference()` is the pre-bake path (rest + the full recipe), and
## the live path is the baked asset plus `_apply_difference()` at the reference config.
func _check_old_pose_parity(pony: Node3D, sk: Skeleton3D, frame: Transform3D,
		config: Dictionary) -> void:
	var rig: Variant = RIG.new()
	rig.call("cache", pony, sk)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var recipe: Variant = RECIPE.new()
	recipe.call("apply_reference", rig, sk, 1.0, config)
	sk.force_update_all_bone_transforms()
	var old := _owned_poses(sk)
	var loader: Variant = AUTHORED.new()
	loader.call("load_file", STANDING_PATH)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var state := {
		"config": config, "authored": loader, "ground_frame": frame,
		"body_scale": 1.0, "size_name": "canon", "stretch": false,
	}
	check(bool(recipe.call("apply_base", rig, sk, 1.0, state)),
		"the live standing base applies for the old-pose parity")
	sk.force_update_all_bone_transforms()
	var live := _owned_poses(sk)
	var worst_pos := 0.0
	var worst_deg := 0.0
	var worst_name := ""
	for name: String in old:
		var a: Transform3D = old[name]
		var b: Transform3D = live[name]
		var gap := a.origin.distance_to(b.origin)
		var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
		var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
		var angle := rad_to_deg(qa.angle_to(qb))
		if angle > worst_deg:
			worst_deg = angle
			worst_name = name
		worst_pos = maxf(worst_pos, gap)
	check(worst_deg <= 0.1 and worst_pos <= 0.001,
		"the live base matches the old procedural pose (worst %s: %.5f m / %.4f deg)"
		% [worst_name, worst_pos, worst_deg])


## Every bone the standing act owns, plus the head it applies separately.
func _owned_poses(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for name: String in PONY_BONES:
		var bone := sk.find_bone(name)
		if bone >= 0:
			out[name] = sk.get_bone_pose(bone)
	var head := sk.find_bone("pony_head")
	if head >= 0:
		out["pony_head"] = sk.get_bone_pose(head)
	return out


## The oral delta on the baked base matches the reference recipe plus the same delta at four sizes:
## the neck/head rotations and the head anchor relative to the hips.
func _check_oral_parity(pony: Node3D, sk: Skeleton3D, frame: Transform3D,
		config: Dictionary) -> void:
	var rig: Variant = RIG.new()
	rig.call("cache", pony, sk)
	var keys := {"oral_pitch": 0.25, "oral_yaw": -0.12, "oral_roll": 0.15}
	var oral: Variant = ORAL.new()
	sk.reset_bone_poses()
	var recipe: Variant = RECIPE.new()
	recipe.call("apply_reference", rig, sk, 1.0, config)
	sk.force_update_all_bone_transforms()
	oral.call("apply_delta", rig, sk, 1.0, {"config": keys})
	sk.force_update_all_bone_transforms()
	var reference := _oral_places(sk)
	var loader: Variant = AUTHORED.new()
	loader.call("load_file", STANDING_PATH)
	var live: Variant = RECIPE.new()
	var original := pony.transform
	var worst_pos := 0.0
	var worst_deg := 0.0
	for size: float in SIZES:
		pony.transform.basis = original.basis * Basis.from_scale(Vector3.ONE * size)
		sk.reset_bone_poses()
		sk.force_update_all_bone_transforms()
		var state := {
			"config": config, "authored": loader, "ground_frame": frame,
			"body_scale": size, "size_name": "canon", "stretch": false,
		}
		check(bool(live.call("apply_base", rig, sk, 1.0, state)),
			"the live standing base applies the asset at %.2f" % size)
		sk.force_update_all_bone_transforms()
		oral.call("apply_delta", rig, sk, 1.0, {"config": keys})
		sk.force_update_all_bone_transforms()
		var got := _oral_places(sk)
		for name: String in reference:
			var a: Dictionary = reference[name]
			var b: Dictionary = got[name]
			var qa: Quaternion = (a["rotation"] as Quaternion).normalized()
			var qb: Quaternion = (b["rotation"] as Quaternion).normalized()
			var angle := rad_to_deg(qa.angle_to(qb))
			worst_deg = maxf(worst_deg, angle)
			worst_pos = maxf(worst_pos, (a["position"] as Vector3).distance_to(b["position"]))
	pony.transform = original
	check(worst_deg <= 0.5, "the oral neck/head parity is size-invariant: %.4f deg" % worst_deg)
	check(worst_pos <= 0.002, "the oral head anchor is size-invariant: %.5f m" % worst_pos)


## The neck/head local rotations and their skeleton-space positions relative to the hips.
func _oral_places(sk: Skeleton3D) -> Dictionary:
	var out := {}
	var hips := sk.find_bone("pony_hips")
	var hips_origin := sk.get_bone_global_pose(hips).origin if hips >= 0 else Vector3.ZERO
	for name: String in ["pony_neck1", "pony_neck2", "pony_head"]:
		var bone := sk.find_bone(name)
		if bone < 0:
			continue
		var pose := sk.get_bone_global_pose(bone)
		out[name] = {
			"rotation": pose.basis.get_rotation_quaternion(),
			"position": pose.origin - hips_origin,
		}
	return out


## The shipped missionary: the four-size body parity and the Anon anchor placement at canon and
## one non-canon size.
func _check_missionary() -> void:
	var asset: Variant = AUTHORED.new()
	check(str(asset.call("load_file", MISSIONARY_PATH)).is_empty(), "the missionary asset loads")
	check(bool(asset.call("usable", "bed")), "the missionary asset is a bed pose")
	check(str(asset.get("anon_mode")) == "act_body", "the missionary asset carries an act body")
	var pony: Node3D = BODY.instantiate()
	root.add_child(pony)
	await process_frame
	var sk := _find_skeleton(pony)
	check(sk != null, "the missionary rig has a skeleton")
	if sk == null:
		return
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.65, -2.0))

	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	check(bool(asset.call("apply_pony", sk, 1.0, frame, 1.0, "canon")), "the missionary applies")
	sk.force_update_all_bone_transforms()
	var canon_local := _local_poses(sk)

	# Four sizes: the body pose is size-invariant, the contact stays on the mattress and the
	# skeleton-space root stays orthonormal.
	var original := pony.transform
	var anchor: Transform3D = asset.call("anchor_world", frame)
	var size_pos := 0.0
	var size_deg := 0.0
	for size: float in SIZES:
		pony.transform.basis = original.basis * Basis.from_scale(Vector3.ONE * size)
		sk.reset_bone_poses()
		sk.force_update_all_bone_transforms()
		check(bool(asset.call("apply_pony", sk, 1.0, frame, size, "canon")),
			"the missionary applies at %.2f" % size)
		sk.force_update_all_bone_transforms()
		var top := AUTHORED.root_bone(sk)
		check(absf(sk.get_bone_global_pose(top).basis.determinant() - 1.0) <= 0.001,
			"the missionary root stays orthonormal at %.2f" % size)
		var hips := sk.find_bone("pony_hips")
		var hips_world: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		var lift := float(asset.call("body_lift", frame, size))
		check(absf(hips_world.x - anchor.origin.x) <= 0.0001
			and absf(hips_world.z - anchor.origin.z) <= 0.0001,
			"the missionary hips stay over the anchor at %.2f" % size)
		check(absf(hips_world.y - (anchor.origin.y + lift)) <= 0.0001,
			"the missionary hips ride the lift at %.2f" % size)
		var placed_contact: Vector3 = asset.call("place_origin",
			asset.call("contact_world", frame), frame, size)
		check(absf(placed_contact.y - frame.origin.y) <= 0.0001,
			"the missionary contact stays on the mattress at %.2f" % size)
		var local := _local_poses(sk)
		for name: String in canon_local:
			var a: Transform3D = canon_local[name]
			var b: Transform3D = local[name]
			size_pos = maxf(size_pos, a.origin.distance_to(b.origin))
			var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
			var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
			size_deg = maxf(size_deg, rad_to_deg(qa.angle_to(qb)))
	pony.transform = original
	check(size_pos <= 0.002, "the missionary body positions are size-invariant: %.5f m" % size_pos)
	check(size_deg <= 0.5, "the missionary body rotations are size-invariant: %.4f deg" % size_deg)

	# The Anon body places by the same anchor/contact rule.
	var placement: Transform3D = asset.call("active_anon_transform")
	var canon_anon: Vector3 = (frame * placement).origin
	var size := 1.35
	var here: Vector3 = anchor.origin
	var lift := float(asset.call("body_lift", frame, size))
	var expected_anon := here + (canon_anon - here) * size + Vector3.UP * lift
	check((asset.call("place_origin", (frame * placement).origin, frame, size) as Vector3)
		.distance_to(expected_anon) <= 0.0001, "the Anon follows the anchor at %.2f" % size)
	root.remove_child(pony)
	pony.free()


func _local_poses(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for name: String in PONY_BONES:
		var bone := sk.find_bone(name)
		if bone >= 0:
			out[name] = sk.get_bone_pose(bone)
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	for child: Node in node.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


## A bare rig with the 30 body bones and the joints the standing recipe needs.
func _skeleton() -> Skeleton3D:
	var parent := Node3D.new()
	root.add_child(parent)
	var sk := Skeleton3D.new()
	parent.add_child(sk)
	_add(sk, "armature", "", Transform3D.IDENTITY)
	_add(sk, "pony_hips", "armature", _rest(Vector3(0.0, 0.8, 0.0)))
	_add(sk, "pony_spine1", "pony_hips", _rest(Vector3(0.0, 0.2, 0.0)))
	_add(sk, "pony_spine2", "pony_spine1", _rest(Vector3(0.0, 0.18, 0.0)))
	_add(sk, "pony_spine3", "pony_spine2", _rest(Vector3(0.0, 0.16, 0.0)))
	_add(sk, "pony_neck1", "pony_spine3", _rest(Vector3(0.0, 0.15, 0.0)))
	_add(sk, "pony_neck2", "pony_neck1", _rest(Vector3(0.0, 0.14, 0.0)))
	_add(sk, "pony_head", "pony_neck2", _rest(Vector3(0.0, 0.12, 0.0)))
	for side: String in ["L", "R"]:
		var lateral := 1.0 if side == "L" else -1.0
		_add(sk, "pony_flank_" + side, "pony_hips",
			_rest(Vector3(0.1 * lateral, -0.1, 0.0)))
		_add(sk, "pony_femur_" + side, "pony_flank_" + side,
			_rest(Vector3(0.15 * lateral, -0.05, 0.0)))
		_add(sk, "pony_tibia_" + side, "pony_femur_" + side,
			_rest(Vector3(0.18 * lateral, 0.0, 0.0)))
		_add(sk, "pony_legLower_" + side, "pony_tibia_" + side,
			_rest(Vector3(0.16 * lateral, 0.0, 0.0)))
		_add(sk, "pony_tarsal_" + side, "pony_legLower_" + side,
			_rest(Vector3(0.12 * lateral, 0.0, 0.0)))
		_add(sk, "pony_hoof_" + side, "pony_tarsal_" + side,
			_rest(Vector3(0.06 * lateral, 0.0, 0.0)))
		_add(sk, "pony_shoulder_" + side, "pony_spine3",
			_rest(Vector3(0.15 * lateral, 0.1, 0.0)))
		_add(sk, "pony_upperArm_" + side, "pony_shoulder_" + side,
			_rest(Vector3(0.18 * lateral, 0.0, 0.0)))
		_add(sk, "pony_lowerArm_" + side, "pony_upperArm_" + side,
			_rest(Vector3(0.18 * lateral, 0.0, 0.0)))
		_add(sk, "pony_wrist_" + side, "pony_lowerArm_" + side,
			_rest(Vector3(0.10 * lateral, 0.0, 0.0)))
		_add(sk, "pony_hand_" + side, "pony_wrist_" + side,
			_rest(Vector3(0.05 * lateral, 0.0, 0.0)))
		_add(sk, "pony_finger_" + side, "pony_hand_" + side,
			_rest(Vector3(0.03 * lateral, 0.0, 0.0)))
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	return sk


func _rest(origin: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin)


func _add(sk: Skeleton3D, name: String, parent_name: String, rest: Transform3D) -> void:
	var bone := sk.add_bone(name)
	if not parent_name.is_empty():
		sk.set_bone_parent(bone, sk.find_bone(parent_name))
	sk.set_bone_rest(bone, rest)


func _free(sk: Skeleton3D) -> void:
	var parent := sk.get_parent()
	if parent != null:
		parent.queue_free()
	else:
		sk.queue_free()