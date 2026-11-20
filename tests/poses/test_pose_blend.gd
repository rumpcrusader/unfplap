extends "res://mods/unfplap/tests/support/suite.gd"
## The pose evaluator: the typed single/blend modes, the single fast path, the base+delta order,
## the two-base capture/blend/overlay math and the reused capture buffers. A bare skeleton and
## fake drivers keep it off every game file.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_blend.gd

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const DRIVER := preload("res://mods/unfplap/poses/pose_driver.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const FAKE_A := "fake_a"
const FAKE_B := "fake_b"
const FAKE_DELTA := "fake_delta"
const BONE := "pony_spine1"



class FakeMare extends Node3D:
	var body_scale := 1.0


## A procedural driver with the driver protocol. `splits` selects the split form: `apply_base`
## writes the base only (and reports whether it owns one) and `apply_overlay` is the moveable
## head/neck layer; a driver without it writes the whole pose in `apply`.
class FakeDriver extends "res://mods/unfplap/poses/pose_driver.gd":
	var log: Array[String] = []
	var tag := ""
	var bone := "pony_spine1"
	var angle := 0.0
	var origin := Vector3.ZERO
	var base_ok := true
	var non_finite := false
	var use_authored := false
	var splits := true
	## The pose a bound authored asset stands for in this suite; a shipped asset carries none.
	var authored_poses: Dictionary = {}
	var seen_configs: Array[String] = []

	func splits_base() -> bool:
		return splits

	func apply(_rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
		var pose := asset(state)
		log.append("apply:%s:%.3f" % [str(pose["tag"]), weight])
		write(sk, weight, pose)
		seen_configs.append(config_tag(state))

	func apply_base(_rig, sk: Skeleton3D, weight: float, state: Dictionary) -> bool:
		var pose := asset(state)
		log.append("base:%s:%.3f" % [str(pose["tag"]), weight])
		write(sk, weight, pose)
		seen_configs.append(config_tag(state))
		return base_ok

	func apply_overlay(_rig, _sk: Skeleton3D, weight: float, state: Dictionary) -> void:
		var pose := asset(state)
		log.append("overlay:%s:%.3f" % [str(pose["tag"]), weight])
		seen_configs.append(config_tag(state))

	func write(sk: Skeleton3D, weight: float, pose: Dictionary = {}) -> void:
		var index := sk.find_bone(bone)
		if index < 0:
			return
		var at: Vector3 = pose.get("origin", origin)
		var turn: float = float(pose.get("angle", angle))
		var position := Vector3(INF, 0.0, 0.0) if non_finite else at
		sk.set_bone_pose(index, Transform3D(Basis(Vector3.RIGHT, turn * weight), position))

	## The authored asset of the side this driver is evaluating, when the test binds one; otherwise
	## the driver's own constants. The two-asset case proves each recipe sees its own document.
	func asset(state: Dictionary) -> Dictionary:
		var authored: Variant = state.get("authored")
		if use_authored and authored != null and authored_poses.has(authored):
			return authored_poses[authored]
		return {"tag": tag, "angle": angle, "origin": origin}

	func config_tag(state: Dictionary) -> String:
		var config: Variant = state.get("config", {})
		return str((config as Dictionary).get("tag", "")) if config is Dictionary else ""


## The procedural delta for the A5 oral path: it must run after the base and see its write.
class FakeDelta extends "res://mods/unfplap/poses/pose_driver.gd":
	var log: Array[String] = []
	var bone := "pony_spine1"
	var origin := Vector3.ZERO
	var seen_before := Vector3.INF

	func apply_delta(_rig, sk: Skeleton3D, weight: float, _state: Dictionary) -> void:
		var index := sk.find_bone(bone)
		if index >= 0:
			seen_before = sk.get_bone_pose(index).origin
			sk.set_bone_pose(index, Transform3D(Basis.IDENTITY, origin))
		log.append("delta:%.3f" % weight)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_single()
	_check_modes()
	_check_base_delta()
	_check_whole_pose_driver()
	_check_two_base()
	_check_two_assets()
	_check_buffers()
	_check_non_finite()
	_check_render_order()
	_check_shipped_driver()
	_check_oral_delta()
	if failures == 0:
		print("POSE_BLEND_PASS")
	finish()


## A bare rig with the two spine/neck chains the recipes and the fakes write. The evaluator is the
## only modifier the skeleton carries.
func _graph() -> Dictionary:
	var mare := FakeMare.new()
	root.add_child(mare)
	var sk := Skeleton3D.new()
	mare.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	var hips := sk.add_bone("pony_hips")
	sk.set_bone_parent(hips, armature)
	for name: String in ["pony_spine1", "pony_spine2", "pony_spine3",
			"pony_neck1", "pony_neck2", "pony_head"]:
		sk.set_bone_parent(sk.add_bone(name), hips)
	sk.reset_bone_poses()
	var pose_node: Node = POSE.new()
	pose_node.mare = mare
	sk.add_child(pose_node)
	return {"mare": mare, "sk": sk, "pose_node": pose_node}


func _free_graph(made: Dictionary) -> void:
	var mare: FakeMare = made["mare"]
	var pose_node: Node = made["pose_node"]
	if is_instance_valid(pose_node):
		pose_node.free()
	if is_instance_valid(mare):
		root.remove_child(mare)
		mare.free()


func _fake(path: String, made: Dictionary, tag: String, angle: float,
		origin: Vector3) -> FakeDriver:
	var driver := FakeDriver.new()
	driver.tag = tag
	driver.angle = angle
	driver.origin = origin
	driver.bone = BONE
	var pose_node: Node = made["pose_node"]
	pose_node.driver_objects[path] = driver
	return driver


## The single fast path: one driver `apply()` with the pose ramp, no split calls, and the normal
## diagnostics still name the base.
func _check_single() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var driver := _fake(FAKE_A, made, "one", 0.4, Vector3(0.0, 0.1, 0.0))
	var config: Dictionary = {"tag": "one"}
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", config, config)
	check(pose_node.mode == POSE.MODE_SINGLE, "equal pair and configs take the single path")
	check(pose_node.from_driver == FAKE_A and pose_node.to_driver == FAKE_A,
		"the evaluator keeps the resolved pair")
	pose_node.amount = 0.5
	pose_node.target_amount = 0.5
	driver.log.clear()
	pose_node.call("apply_render", sk)
	check(driver.log == ["apply:one:0.500"], "the single path calls apply once with the ramp")
	var index := sk.find_bone(BONE)
	check(near(sk.get_bone_pose(index).basis.get_rotation_quaternion().get_angle(), 0.2),
		"the ramp scales the written pose")
	check(pose_node.diag_last_base == "none", "the single path keeps the base diagnostics")
	_free_graph(made)


## The typed mode: the same driver and configs are single; a different driver, a delta, another
## config or a different authored asset makes it a blend. The mode is an int, never a string.
func _check_modes() -> void:
	var made := _graph()
	var pose_node: Node = made["pose_node"]
	_fake(FAKE_A, made, "a", 0.1, Vector3.ZERO)
	_fake(FAKE_B, made, "b", -0.1, Vector3.ZERO)
	var a: Dictionary = {"tag": "a"}
	var b: Dictionary = {"tag": "b"}
	var asset_a := AUTHORED.new()
	var asset_b := AUTHORED.new()
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", a, a)
	check(pose_node.mode == POSE.MODE_SINGLE, "one driver and equal configs are single")
	pose_node.call("set_pose", FAKE_A, FAKE_B, "", "", a, a)
	check(pose_node.mode == POSE.MODE_BLEND, "two drivers are a blend")
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", FAKE_DELTA, a, a)
	check(pose_node.mode == POSE.MODE_BLEND, "a delta is a blend")
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", a, b)
	check(pose_node.mode == POSE.MODE_BLEND, "different configs are a blend")
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", a, a, asset_a, asset_b)
	check(pose_node.mode == POSE.MODE_BLEND,
		"two different authored assets are a blend with equal drivers and configs")
	check(not is_same(pose_node.from_authored, pose_node.to_authored),
		"the evaluator keeps the two authored sides apart")
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", a, a, asset_a, asset_a)
	check(pose_node.mode == POSE.MODE_SINGLE, "the same authored asset instance is single")
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", a, a, null, null)
	check(pose_node.mode == POSE.MODE_SINGLE, "a null asset pair is the presentation single path")
	check(typeof(POSE.MODE_SINGLE) == TYPE_INT and typeof(POSE.MODE_BLEND) == TYPE_INT,
		"the mode is typed")
	_free_graph(made)


## A base and a delta with one driver: base -> delta -> overlay, and the delta reads the base's
## write. The single path uses the same order at the pose ramp.
func _check_base_delta() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var driver := _fake(FAKE_A, made, "a", 0.2, Vector3(0.0, 0.1, 0.0))
	var delta := FakeDelta.new()
	delta.origin = Vector3(0.0, 0.3, 0.0)
	pose_node.driver_objects[FAKE_DELTA] = delta
	var shared: Array[String] = []
	driver.log = shared
	delta.log = shared
	var a: Dictionary = {"tag": "a"}
	var b: Dictionary = {"tag": "b"}
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", FAKE_DELTA, a, b)
	pose_node.call("set_weight", 1.0)
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	shared.clear()
	pose_node.call("apply_render", sk)
	check(delta.seen_before.is_equal_approx(Vector3(0.0, 0.1, 0.0)),
		"the delta runs after the base and sees its write")
	var index := sk.find_bone(BONE)
	check(sk.get_bone_pose(index).origin.is_equal_approx(delta.origin),
		"the blended pose carries the delta")
	var base_at := _last_index(shared, "base:")
	var delta_at := _last_index(shared, "delta:")
	var overlay_at := _last_index(shared, "overlay:")
	check(base_at >= 0 and delta_at > base_at and overlay_at > delta_at,
		"the base, the delta and the overlay run in that order")
	shared.clear()
	pose_node.call("set_pose", FAKE_A, FAKE_A, FAKE_DELTA, FAKE_DELTA, a, a)
	check(pose_node.mode == POSE.MODE_SINGLE, "the same delta on both sides is single")
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("apply_render", sk)
	check(shared == ["base:a:1.000", "delta:1.000", "overlay:a:1.000"],
		"the single delta path runs base, delta then overlay")
	_free_graph(made)


## A driver without the split: a pose carrying a delta runs the whole pose and then the delta, so
## an injected driver that is not a split recipe still lands.
func _check_whole_pose_driver() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var driver := _fake(FAKE_A, made, "whole", 0.2, Vector3.ZERO)
	driver.splits = false
	var delta := FakeDelta.new()
	delta.origin = Vector3(0.0, 0.2, 0.0)
	pose_node.driver_objects[FAKE_DELTA] = delta
	var shared: Array[String] = []
	driver.log = shared
	delta.log = shared
	var config: Dictionary = {"tag": "a"}
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", FAKE_DELTA, config, config)
	pose_node.call("set_weight", 1.0)
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("apply_render", sk)
	check(shared.has("apply:whole:1.000"), "a driver without the split applies the whole pose")
	check(_last_index(shared, "apply:") < _last_index(shared, "delta:"),
		"the whole pose runs before the delta")
	var index := sk.find_bone(BONE)
	check(sk.get_bone_pose(index).origin.is_equal_approx(delta.origin),
		"the delta still lands after the whole pose")
	_free_graph(made)


## Two bases: each side is captured at full base weight, the transforms blend at the edge weight
## and the overlays run from then to with 1-w and w.
func _check_two_base() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var from_driver := _fake(FAKE_A, made, "a", 0.4, Vector3(0.0, 0.1, 0.0))
	var to_driver := _fake(FAKE_B, made, "b", -0.3, Vector3(0.0, 0.3, 0.0))
	var shared: Array[String] = []
	from_driver.log = shared
	to_driver.log = shared
	var a: Dictionary = {"tag": "a"}
	var b: Dictionary = {"tag": "b"}
	pose_node.call("set_pose", FAKE_A, FAKE_B, "", "", a, b)
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	var index := sk.find_bone(BONE)
	pose_node.call("set_weight", 0.0)
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), 0.4) < 0.01,
		"weight zero lands on the from base")
	check(sk.get_bone_pose(index).origin.is_equal_approx(Vector3(0.0, 0.1, 0.0)),
		"weight zero keeps the from origin")
	pose_node.call("set_weight", 0.5)
	shared.clear()
	from_driver.seen_configs.clear()
	to_driver.seen_configs.clear()
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), 0.05) < 0.01,
		"weight half slerps the rotations")
	check(sk.get_bone_pose(index).origin.is_equal_approx(Vector3(0.0, 0.2, 0.0)),
		"weight half lerps the origins")
	var overlays: Array[String] = []
	for line: String in shared:
		if line.begins_with("overlay:"):
			overlays.append(line)
	check(overlays == ["overlay:a:0.500", "overlay:b:0.500"],
		"the overlays run once per side, from then to, with the side weights")
	check(from_driver.seen_configs.has("a") and not from_driver.seen_configs.has("b"),
		"the from side sees its own config")
	check(to_driver.seen_configs.has("b") and not to_driver.seen_configs.has("a"),
		"the to side sees its own config")
	pose_node.call("set_weight", 1.0)
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), -0.3) < 0.01,
		"weight one lands on the to base")
	check(sk.get_bone_pose(index).origin.is_equal_approx(Vector3(0.0, 0.3, 0.0)),
		"weight one keeps the to origin")
	_free_graph(made)


## Two authored assets with the same driver and configs: each side's recipe sees its own asset,
## and the blend carries the captured bone between them. The buffers are reused across weights.
func _check_two_assets() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var from_driver := _fake(FAKE_A, made, "driver_a", 0.0, Vector3.ZERO)
	var to_driver := _fake(FAKE_B, made, "driver_b", 0.0, Vector3.ZERO)
	from_driver.use_authored = true
	to_driver.use_authored = true
	var shared: Array[String] = []
	from_driver.log = shared
	to_driver.log = shared
	var asset_a := AUTHORED.new()
	var asset_b := AUTHORED.new()
	var from_doc := {"tag": "a", "angle": 0.4, "origin": Vector3(0.0, 0.1, 0.0)}
	var to_doc := {"tag": "b", "angle": -0.3, "origin": Vector3(0.0, 0.3, 0.0)}
	from_driver.authored_poses[asset_a] = from_doc
	from_driver.authored_poses[asset_b] = to_doc
	var same_config: Dictionary = {"tag": "same"}
	pose_node.call("set_pose", FAKE_A, FAKE_A, "", "", same_config, same_config, asset_a, asset_b)
	check(pose_node.mode == POSE.MODE_BLEND, "two authored assets take the two-base blend")
	check(pose_node.from_authored == asset_a and pose_node.to_authored == asset_b,
		"the evaluator stores the authored pair")
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	var index := sk.find_bone(BONE)
	pose_node.call("set_weight", 0.0)
	shared.clear()
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), 0.4) < 0.01,
		"weight zero lands on the from asset")
	check(sk.get_bone_pose(index).origin.is_equal_approx(from_doc["origin"] as Vector3),
		"weight zero keeps the from asset origin")
	check(shared.has("base:a:1.000") and shared.has("base:b:1.000"),
		"each side's recipe sees its own authored asset")
	var overlays: Array[String] = []
	for line: String in shared:
		if line.begins_with("overlay:"):
			overlays.append(line)
	check(overlays.size() == 2 and overlays[0].ends_with(":1.000")
		and overlays[1].ends_with(":0.000"),
		"the overlay pass runs once per side with the side weights")
	var pre: Array = pose_node._pre
	var from_pose: Array = pose_node._from_pose
	pose_node.call("set_weight", 0.5)
	shared.clear()
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), 0.05) < 0.01,
		"weight half slerps the two authored rotations")
	check(sk.get_bone_pose(index).origin.is_equal_approx(Vector3(0.0, 0.2, 0.0)),
		"weight half lerps the two authored origins")
	check(shared.has("base:a:1.000") and shared.has("base:b:1.000"),
		"both authored tags appear at the midpoint")
	check(is_same(pre, pose_node._pre) and is_same(from_pose, pose_node._from_pose),
		"a second asset blend reuses the capture buffers")
	pose_node.call("set_weight", 1.0)
	pose_node.call("apply_render", sk)
	check(_angle_to(sk.get_bone_pose(index), -0.3) < 0.01,
		"weight one lands on the to asset")
	check(sk.get_bone_pose(index).origin.is_equal_approx(to_doc["origin"] as Vector3),
		"weight one keeps the to asset origin")
	to_doc["origin"] = Vector3(INF, 0.0, 0.0)
	pose_node.call("apply_render", sk)
	check(sk.get_bone_pose(index).origin.is_finite()
		and sk.get_bone_pose(index).basis.x.is_finite(),
		"a non-finite authored side is skipped")
	_free_graph(made)


## The capture buffers are resized once and reused, and the evaluator adds no second modifier.
func _check_buffers() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	_fake(FAKE_A, made, "a", 0.2, Vector3.ZERO)
	_fake(FAKE_B, made, "b", -0.2, Vector3.ZERO)
	pose_node.call("set_pose", FAKE_A, FAKE_B, "", "", {"tag": "a"}, {"tag": "b"})
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("apply_render", sk)
	var pre: Array = pose_node._pre
	var from_pose: Array = pose_node._from_pose
	var to_pose: Array = pose_node._to_pose
	pose_node.call("set_weight", 0.75)
	pose_node.call("apply_render", sk)
	check(is_same(pre, pose_node._pre) and is_same(from_pose, pose_node._from_pose)
		and is_same(to_pose, pose_node._to_pose),
		"a second blend reuses the three capture buffers")
	check(pre.size() == sk.get_bone_count() and from_pose.size() == sk.get_bone_count(),
		"the buffers cover every bone")
	var modifiers := 0
	for child: Node in sk.get_children():
		if child is SkeletonModifier3D:
			modifiers += 1
	check(modifiers == 1, "the evaluator adds no second modifier")
	_free_graph(made)


## A non-finite side is skipped instead of written to the rig.
func _check_non_finite() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	var bad := _fake(FAKE_A, made, "bad", 0.2, Vector3.ZERO)
	bad.non_finite = true
	_fake(FAKE_B, made, "good", -0.2, Vector3(0.0, 0.2, 0.0))
	pose_node.call("set_pose", FAKE_A, FAKE_B, "", "", {"tag": "a"}, {"tag": "b"})
	pose_node.call("set_weight", 0.5)
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("apply_render", sk)
	var index := sk.find_bone(BONE)
	check(sk.get_bone_pose(index).origin.is_finite() and sk.get_bone_pose(index).basis.x.is_finite(),
		"a non-finite side is skipped")
	check(pose_node.diag_last_base == "blend", "the blend names itself in the diagnostics")
	_free_graph(made)


## The modifier pass and the render write use the same pair and weight, and a repeated write does
## not depend on the previous call.
func _check_render_order() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	_fake(FAKE_A, made, "a", 0.4, Vector3(0.0, 0.1, 0.0))
	_fake(FAKE_B, made, "b", -0.3, Vector3(0.0, 0.3, 0.0))
	pose_node.call("set_pose", FAKE_A, FAKE_B, "", "", {"tag": "a"}, {"tag": "b"})
	pose_node.call("set_weight", 0.5)
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	var index := sk.find_bone(BONE)
	pose_node.call("_apply", 1.0 / 60.0)
	var modifier_pose := sk.get_bone_pose(index)
	check(pose_node.diag_frames == 1, "the modifier pass counts the frame")
	pose_node.call("apply_render", sk)
	check(sk.get_bone_pose(index).is_equal_approx(modifier_pose),
		"apply_render uses the same pair and weight")
	pose_node.call("apply_render", sk)
	check(sk.get_bone_pose(index).is_equal_approx(modifier_pose),
		"a repeated blend is idempotent")
	_free_graph(made)


## The shipped standing config with the test overrides, so the recipes read the reference values
## instead of a missing key's zero.
func _standing_config(overrides := {}) -> Dictionary:
	var config: Dictionary = CATALOG.defaults(CATALOG.STANDING).duplicate(true)
	config.merge(overrides, true)
	return config


## A synthetic v7 base for the standing driver: one observable bone and a ground frame. The
## shipped asset's numbers belong to `test_pose_bake`; this suite only needs a base to exist.
func _standing_base(made: Dictionary, bone := "pony_spine1", angle := 0.2) -> Variant:
	var asset: Variant = AUTHORED.new()
	asset.available = true
	asset.version = 7
	asset.space = "local_rest"
	asset.frame = "ground"
	asset.root = Transform3D.IDENTITY
	asset.anchor = {
		"bone": "pony_hips", "transform": Transform3D.IDENTITY,
		"contact": Vector3.ZERO, "support": 0.0,
	}
	asset.pony_bones = {bone: {"rotation": Quaternion(Vector3.RIGHT, angle),
		"position": Vector3.ZERO}}
	var pose_node: Node = made["pose_node"]
	pose_node.authored = asset
	pose_node.ground_frame = Transform3D.IDENTITY
	pose_node.size_name = "canon"
	return asset


## The shipped standing driver resolves through the driver table and writes the stance.
func _check_shipped_driver() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	_standing_base(made)
	pose_node.call("set_pose", POSE.STANDING_PATH, POSE.STANDING_PATH, "", "", _standing_config(), _standing_config())
	check(pose_node.mode == POSE.MODE_SINGLE, "the standing pair is single")
	check(pose_node.from_driver == POSE.STANDING_PATH, "the pair names the standing driver")
	var driver: Variant = pose_node.driver_objects.get(POSE.STANDING_PATH)
	check(driver != null and driver.splits_base(), "the shipped standing driver exposes the split")
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("apply_render", sk)
	var index := sk.find_bone("pony_spine1")
	check(_angle_to(sk.get_bone_pose(index), 0.0) > 0.001,
		"the shipped standing driver writes the baked base")
	_free_graph(made)


## The oral row's procedural delta: it forces the two-base blend in both edge directions, the
## shipped delta object is loaded from the driver table, and it writes the neck swing on the to
## side while the standing from side has none.
func _check_oral_delta() -> void:
	var made := _graph()
	var sk: Skeleton3D = made["sk"]
	var pose_node: Node = made["pose_node"]
	_standing_base(made)
	var config_a: Dictionary = _standing_config()
	var config_b: Dictionary = _standing_config({"oral_pitch": 0.4, "oral_yaw": 0.25, "oral_roll": 0.1})
	pose_node.call("set_pose", POSE.STANDING_PATH, POSE.STANDING_PATH, "",
		POSE.STANDING_ORAL_PATH, config_a, config_b)
	check(pose_node.mode == POSE.MODE_BLEND,
		"the standing to oral delta pair takes the blend path")
	check(pose_node.from_delta == "" and pose_node.to_delta == POSE.STANDING_ORAL_PATH,
		"the pair carries the oral delta on the to side")
	var delta: Variant = pose_node.driver_objects.get(POSE.STANDING_ORAL_PATH)
	check(delta is DRIVER, "the shipped oral recipe is loaded from the delta table")
	pose_node.amount = 1.0
	pose_node.target_amount = 1.0
	pose_node.call("set_weight", 0.0)
	pose_node.call("apply_render", sk)
	var neck := sk.find_bone("pony_neck2")
	var head := sk.find_bone("pony_head")
	var at_from := sk.get_bone_pose(neck)
	var head_from := sk.get_bone_pose(head)
	pose_node.call("set_weight", 1.0)
	pose_node.call("apply_render", sk)
	check(not sk.get_bone_pose(neck).is_equal_approx(at_from),
		"the oral delta turns the neck at the to side")
	check(not sk.get_bone_pose(head).is_equal_approx(head_from),
		"the oral delta counters the head at the to side")
	pose_node.call("set_pose", POSE.STANDING_PATH, POSE.STANDING_PATH,
		POSE.STANDING_ORAL_PATH, "", config_b, config_a)
	check(pose_node.mode == POSE.MODE_BLEND,
		"the oral to standing pair takes the blend path")
	pose_node.call("set_pose", POSE.STANDING_PATH, POSE.STANDING_PATH,
		POSE.STANDING_ORAL_PATH, POSE.STANDING_ORAL_PATH, config_b, config_b)
	check(pose_node.mode == POSE.MODE_SINGLE,
		"the settled oral pose keeps the single delta path")
	_free_graph(made)


## The rotation angle of a local pose, for the known test rotations.
func _angle_to(pose: Transform3D, angle: float) -> float:
	return rad_to_deg(pose.basis.get_rotation_quaternion().angle_to(
		Basis(Vector3.RIGHT, angle).get_rotation_quaternion()))


func _last_index(lines: Array[String], prefix: String) -> int:
	var found := -1
	for i: int in lines.size():
		if lines[i].begins_with(prefix):
			found = i
	return found
