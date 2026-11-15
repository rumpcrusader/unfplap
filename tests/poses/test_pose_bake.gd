extends SceneTree
## The bake tool's capture/compare math on a synthetic rig, the deterministic writer and its test
## path refusal. The shipped standing asset's freshness and the four-size parity are pinned once
## the asset exists (C2).
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_bake.gd

const BAKE := preload("res://mods/unfplap/tools/pose_bake.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RECIPE := preload("res://mods/unfplap/poses/standing_recipe.gd")

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