extends SceneTree
## The bake tool's capture/compare math on a synthetic rig, the deterministic writer and its test
## path refusal. The shipped standing asset's freshness and the four-size parity are pinned once
## the asset exists (C2).
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_bake.gd

const BAKE := preload("res://mods/unfplap/tools/pose_bake.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RECIPE := preload("res://mods/unfplap/poses/standing_recipe.gd")
const ORAL := preload("res://mods/unfplap/poses/standing_oral_recipe.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const BODY := preload("res://world/characters/hybrid_mare/body.glb")

const STANDING_PATH := "res://mods/unfplap/poses/standing_pose.json"
const FIXTURE_PATH := "res://mods/unfplap/tests/poses/fixtures/standing_reference.json"
const SIZES := [1.0, 1.35, 1.7, 2.3]

const PONY_BONES := AUTHORED.PONY_BONES

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
	_check_capture()
	_check_compare()
	_check_writer()
	await _check_shipped_standing()
	print("POSE_BAKE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_BAKE_PASS")
	quit(0 if failures == 0 else 1)


func _check_capture() -> void:
	var sk := _skeleton()
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.0, -0.5))
	var contact := frame * Vector3(0.0, 0.0, 0.0)
	var pose := BAKE.capture_pose(sk, frame, contact, {}, "canon", 1.0, "standing", "ground")
	check(int(pose.get("version", 0)) == 7, "capture writes version 7")
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
	check(int(loader.get("version")) == 7, "the written asset is v7")
	check(not str(BAKE.write_asset(asset,
		"res://mods/unfplap/tests/poses/fixtures/missionary_pose_v6.json")).is_empty(),
		"the writer refuses a fixture path")
	_free(sk)


## The shipped standing asset is exactly the fixture plus the reference recipe, and the body pose
## is size-invariant while the hips stay over the anchor and the contact on the ground.
func _check_shipped_standing() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	check(fixture is Dictionary, "the standing fixture loads")
	if not fixture is Dictionary:
		return
	var pony: Node3D = BODY.instantiate()
	root.add_child(pony)
	await process_frame
	var sk := _find_skeleton(pony)
	check(sk != null, "the reference rig has a skeleton")
	if sk == null:
		return
	_load_fixture(sk, fixture as Dictionary)
	var frame_value: Variant = str_to_var(str((fixture as Dictionary).get("frame", "")))
	var frame: Transform3D = frame_value if frame_value is Transform3D else Transform3D.IDENTITY
	var config := RECIPE.reference_config()
	var size_name := str((fixture as Dictionary).get("size_name", "canon"))
	var body_scale := float((fixture as Dictionary).get("body_scale", 1.0))
	var contact := BAKE.body_contact(pony)
	if not contact.is_finite():
		contact = frame.origin
	var asset := BAKE.capture_asset(sk, frame, config, size_name, contact, body_scale,
		"standing", "ground")
	check(BAKE.serialize(asset) == FileAccess.get_file_as_string(STANDING_PATH),
		"the shipped standing asset is the fixture + reference recipe")
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
	_check_oral_parity(pony, sk, fixture as Dictionary, frame, config)

	root.remove_child(pony)
	pony.free()


## The oral delta on the baked base matches the reference recipe plus the same delta at four sizes:
## the neck/head rotations and the head anchor relative to the hips.
func _check_oral_parity(pony: Node3D, sk: Skeleton3D, fixture: Dictionary, frame: Transform3D,
		config: Dictionary) -> void:
	var rig: Variant = RIG.new()
	rig.call("cache", pony, sk)
	var keys := {"oral_pitch": 0.25, "oral_yaw": -0.12, "oral_roll": 0.15}
	var oral: Variant = ORAL.new()
	_load_fixture(sk, fixture)
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


func _find_skeleton(node: Node) -> Skeleton3D:
	for child: Node in node.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


## Puts the fixture's settled local poses on the rig.
func _load_fixture(sk: Skeleton3D, fixture: Dictionary) -> void:
	sk.reset_bone_poses()
	var bones: Variant = fixture.get("bones", {})
	if bones is Dictionary:
		for name: Variant in (bones as Dictionary):
			var bone := sk.find_bone(str(name))
			var pose_value: Variant = str_to_var(str((bones as Dictionary)[name]))
			if bone >= 0 and pose_value is Transform3D:
				sk.set_bone_pose(bone, pose_value)
	sk.force_update_all_bone_transforms()


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