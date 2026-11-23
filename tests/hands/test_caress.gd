extends "res://mods/unfplap/tests/support/suite.gd"
## Caress sphere contact, path chain, hand shape and reach plan.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hands/test_caress.gd

const HAND := preload("res://mods/unfplap/hands/palm.gd")
const ARM := preload("res://mods/unfplap/shared/hands_reach_plan.gd")
const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const FIT := preload("res://mods/unfplap/hands/coat_fit.gd")
const SYSTEM := preload("res://mods/unfplap/hands/placement.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")
const FLANK := preload("res://mods/unfplap/hands/paths/standing.gd")
const ORAL := preload("res://mods/unfplap/hands/paths/oral.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const CONTROLLER := preload("res://mods/unfplap/hands/controller.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")


class FlankPony extends Node3D:
	var skeleton: Skeleton3D
	var _model: Node3D
	var body_scale := 1.0


class FakeFlank extends Node3D:
	var centers: Array = []
	var normals: Array = []


class NodePony extends Node3D:
	var _model: Node3D
	var skeleton: Skeleton3D
	var head: Variant = null
	var body_scale := 1.0


class FixedPath extends PATH_BASE:
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var center := Vector3.ZERO
	var radius := 0.0
	var calls := 0

	func candidates(_side: MODEL.Side, _context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
		calls += 1
		var out := MODEL.Candidate.new()
		out.point = point
		out.center = center
		out.radius = radius
		out.normal = normal
		out.oval_x = Vector3.RIGHT
		out.oval_y = Vector3.FORWARD
		out.finger = Vector3.FORWARD
		out.mode = "palm"
		out.roll = 0.0
		out.region = "torso"
		return [out]

	func debug_world(_side: MODEL.Side) -> Array[MODEL.AnchorWorld]:
		return []


class FakeHead extends RefCounted:
	var model: Node3D
	var skeleton: Skeleton3D

class FakePony extends Node3D:
	var _model: Node3D
	var skeleton: Skeleton3D
	var head: Variant = null


func _json_position(areas: Dictionary, area: String, side: String) -> Vector3:
	var entry: Variant = areas.get(area, {})
	if not entry is Dictionary:
		return Vector3.INF
	var side_entry: Variant = (entry as Dictionary).get(side, {})
	if not side_entry is Dictionary:
		return Vector3.INF
	var values: Variant = (side_entry as Dictionary).get("position", [])
	if not values is Array or (values as Array).size() < 3:
		return Vector3.INF
	return Vector3(float((values as Array)[0]), float((values as Array)[1]),
		float((values as Array)[2]))


## The coat point an anchor's fitted sphere passes through.
func _anchor_point(anchor: MODEL.Anchor) -> Vector3:
	return anchor.center + anchor.normal * anchor.radius


func _add_quad(verts: PackedVector3Array, norms: PackedVector3Array,
		indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3) -> void:
	var base := verts.size()
	verts.append_array(PackedVector3Array([a, b, c, d]))
	for _i in 4:
		norms.append(normal)
	indices.append_array(PackedInt32Array([base, base + 1, base + 2,
		base, base + 2, base + 3]))


func _path_fixture() -> Dictionary:
	var root := Node3D.new()
	get_root().add_child(root)
	var sk := Skeleton3D.new()
	root.add_child(sk)
	var names := ["pony_spine2", "pony_spine3", "pony_neck1", "pony_head"]
	var zs := [0.0, -0.25, -0.5, -0.8]
	for i in 4:
		sk.add_bone(names[i])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, zs[i])))
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var x0 := -0.2
	var x1 := 0.2
	var y0 := -0.3
	var y1 := 0.1
	var z0 := -1.0
	var z1 := 0.4
	var x_steps := 4
	var z_steps := 14
	for ix in x_steps:
		var xa := x0 + (x1 - x0) * float(ix) / float(x_steps)
		var xb := x0 + (x1 - x0) * float(ix + 1) / float(x_steps)
		for iz in z_steps:
			var za := z0 + (z1 - z0) * float(iz) / float(z_steps)
			var zb := z0 + (z1 - z0) * float(iz + 1) / float(z_steps)
			_add_quad(verts, norms, indices, Vector3(xa, y0, za), Vector3(xb, y0, za),
				Vector3(xb, y0, zb), Vector3(xa, y0, zb), Vector3.DOWN)
	_add_quad(verts, norms, indices, Vector3(x0, y1, z1), Vector3(x1, y1, z1),
		Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.UP)
	_add_quad(verts, norms, indices, Vector3(x1, y0, z0), Vector3(x1, y1, z0),
		Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT)
	_add_quad(verts, norms, indices, Vector3(x0, y0, z1), Vector3(x0, y1, z1),
		Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3.LEFT)
	_add_quad(verts, norms, indices, Vector3(x0, y0, z0), Vector3(x0, y1, z0),
		Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.FORWARD)
	_add_quad(verts, norms, indices, Vector3(x1, y0, z1), Vector3(x1, y1, z1),
		Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.BACK)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for _i in verts.size():
		bones.append_array(PackedInt32Array([0, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := MeshInstance3D.new()
	body.name = "MareBody"
	body.mesh = mesh
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	body.skin = skin
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	model.add_child(body)
	body.skeleton = body.get_path_to(sk)
	var pony := FakePony.new()
	pony._model = model
	pony.skeleton = sk
	return {"root": root, "pony": pony}


func run() -> void:
	var palm := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "palm", 0.0, 0.0)
	var hovered := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "palm",
		0.0, 0.03)
	check(near(hovered.origin.y, 0.03, 0.001), "the single-point palm uses the hover distance")
	var right_basis := HAND.palm_basis("right", Vector3.UP, Vector3.FORWARD, 30.0)
	var left_basis := HAND.palm_basis("left", Vector3.UP, Vector3.FORWARD, -30.0)
	check(right_basis.x.dot(Vector3.UP) > 0.99, "the right palm marker faces the coat")
	check(left_basis.x.dot(Vector3.UP) < -0.99, "the left palm marker faces the coat")
	check(right_basis.determinant() > 0.99 and left_basis.determinant() > 0.99,
		"the rolled palm bases stay orthonormal")
	var tip := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "fingertip", 0.0, 0.0)
	check(tip.is_finite() and tip.origin != palm.origin,
		"the fingertip mode uses its own palm offset")

	check(near(PATH.u_for(-1.0, 0.0), 0.0, 0.001), "S reaches the lower belly anchor")
	check(near(PATH.u_for(0.0, 0.0), PATH.BELLY_U, 0.001), "neutral stays on the belly anchor")
	check(near(PATH.u_for(1.0, 0.0), 1.0, 0.001), "W reaches the cheek anchor")
	check(near(PATH.u_for(0.5, 0.25), 0.875, 0.001), "along_m shifts the path parameter")
	var world: Array[MODEL.AnchorWorld] = []
	for i in 5:
		var anchor := MODEL.AnchorWorld.new()
		anchor.position = Vector3(0.0, 0.0, -float(i) * 0.2)
		anchor.center = Vector3(0.0, -0.2, -float(i) * 0.2)
		anchor.radius = 0.2
		anchor.normal = Vector3.UP
		anchor.lateral = 1.0 - float(i) * 0.25
		anchor.roll = 1.0 - float(i) * 0.25
		anchor.region = "head" if i == 4 else "torso"
		world.append(anchor)
	var start: MODEL.Sample = PATH.sample_world(world, 0.0, MODEL.Side.RIGHT, Vector3.RIGHT)
	var middle: MODEL.Sample = PATH.sample_world(world, PATH.BELLY_U, MODEL.Side.RIGHT,
		Vector3.RIGHT)
	var end: MODEL.Sample = PATH.sample_world(world, 1.0, MODEL.Side.RIGHT, Vector3.RIGHT)
	check(near(start.point.z, 0.0, 0.001), "the path starts at the lower anchor")
	check(near(end.point.z, -0.8, 0.001), "the path ends at the cheek anchor")
	check(middle.point.z < -0.15 and middle.point.z > -0.3, "neutral sits near the belly anchor")
	check(middle.finger.dot(Vector3.FORWARD) > 0.9, "the path tangent points toward her head")
	check(near(end.lateral, 0.0, 0.001), "the lateral offset fades at the cheek")
	check(end.region == "head", "the cheek sample uses the head region")
	var left: MODEL.Sample = PATH.sample_world(world, PATH.BELLY_U, MODEL.Side.LEFT, Vector3.RIGHT)
	check(left.side.dot(Vector3.RIGHT) < -0.9, "the left hand uses her left lateral axis")
	check(middle.center.is_finite() and near(middle.radius, 0.2, 0.001),
		"the path sample carries its sphere")
	check((start.center + start.normal * start.radius).is_equal_approx(start.point),
		"the coat point sits on the sphere at the anchor")

	# The real OpenPony head and the real mare body; the fit and the authored paths read them.
	var head_root := Node3D.new()
	get_root().add_child(head_root)
	var head_scene: Node = load("res://world/characters/openpony/openpony_mare.tscn").instantiate()
	head_root.add_child(head_scene)
	await process_frame
	await process_frame
	var head_model: Node3D = head_scene.get("model")
	var head_sk: Skeleton3D = head_scene.get("skeleton")
	var fake_head := FakeHead.new()
	fake_head.model = head_model
	fake_head.skeleton = head_sk
	var head_pony := FakePony.new()
	head_pony._model = head_model
	head_pony.skeleton = head_sk
	head_pony.head = fake_head
	var area_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://mods/unfplap/hands/areas/areas.json"))
	check(area_data is Dictionary, "the marked area JSON parses")
	var area_areas: Dictionary = {}
	var area_order: Array = []
	var area_start := ""
	if area_data is Dictionary:
		var area_root: Dictionary = area_data
		var area_poses: Variant = area_root.get("poses", {})
		if area_poses is Dictionary:
			var area_standing: Variant = (area_poses as Dictionary).get("standing", {})
			if area_standing is Dictionary:
				area_order = (area_standing as Dictionary).get("order", [])
				area_start = str((area_standing as Dictionary).get("start", ""))
		var area_rows: Variant = area_root.get("areas", {})
		if area_rows is Dictionary:
			area_areas = area_rows as Dictionary
	check(area_order.size() >= 3, "the standing area order has at least three areas")
	var expected_left: Array = []
	for area_name: Variant in area_order:
		var row: Variant = area_areas.get(area_name, {})
		if row is Dictionary and (row as Dictionary).has("left"):
			expected_left.append(str(area_name))
	var head_side_left := _json_position(area_areas, "head_side", "left")
	var head_side_right := _json_position(area_areas, "head_side", "right")
	check(head_side_left.x < 0.0 and head_side_right.x > 0.0,
		"the head side JSON is authored from the mare's point of view")

	# The coat fit: one sphere per authored area, through the nearest coat vertex.
	var flank_authored := _json_position(area_areas, "flank_side", "left")
	var body_scene: Node = load("res://world/characters/hybrid_mare/body.glb").instantiate()
	head_root.add_child(body_scene)
	var body_mesh := body_scene.find_child("MareBody", true, false) as MeshInstance3D
	var body_sk: Skeleton3D = null
	if body_mesh != null and not body_mesh.skeleton.is_empty():
		body_sk = body_mesh.get_node_or_null(body_mesh.skeleton) as Skeleton3D
	if body_sk == null:
		for child: Node in body_scene.find_children("*", "Skeleton3D", true, false):
			body_sk = child as Skeleton3D
			break
	var body_pony := FakePony.new()
	body_pony._model = body_scene as Node3D
	body_pony.skeleton = body_sk
	body_pony.head = fake_head
	var torso_primitive: Variant = FIT.primitive(body_pony, "torso", flank_authored)
	check(torso_primitive != null, "the coat fit returns a primitive for an authored area")
	if torso_primitive != null:
		check(float(torso_primitive.radius) >= FIT.MIN_RADIUS_M
			and float(torso_primitive.radius) <= FIT.MAX_RADIUS_M,
			"the fitted radius stays inside the scan bounds")
		check((torso_primitive.normal as Vector3).length() > 0.99,
			"the fitted sphere carries a unit coat normal")
		check(not (torso_primitive.influences as Array).is_empty(),
			"the fitted sphere carries its skin influences")
		check(float(torso_primitive.residual_mm) < 20.0,
			"the fitted sphere stays close to the coat")
		check(FIT.primitive(body_pony, "torso", flank_authored) == torso_primitive,
			"the coat fit is cached per skin and area")
	var head_primitive: Variant = FIT.primitive(head_pony, "head", head_side_left)
	check(head_primitive != null and float(head_primitive.radius) >= FIT.MIN_RADIUS_M,
		"the head area fits its own sphere")
	check(FIT.primitive(head_pony, "torso", Vector3(100.0, 100.0, 100.0)) == null,
		"an area beyond the coat tolerance finds no primitive")

	# Authored anchors from the Blender vertex groups, one fitted sphere each.
	var authored_path: Variant = PATH.new()
	check(bool(authored_path.call("build", body_pony, MODEL.Side.RIGHT)),
		"the authored path builds on the real body")
	var built: MODEL.Sample = authored_path.call("sample", 0.0, 0.0, Vector3.RIGHT)
	check(built != null, "the built path samples")
	check(built.point.is_finite(), "the built path point is finite")
	check(built.center.is_finite() and built.radius > 0.0,
		"the built sample carries its sphere")
	check(built.finger.dot(Vector3.FORWARD) > 0.5,
		"the built path tangent points toward her head")
	check(built.normal.y < -0.9, "the built path normal faces outward")
	var authored_sides: Array[MODEL.Side] = [MODEL.Side.LEFT, MODEL.Side.RIGHT]
	for side: MODEL.Side in authored_sides:
		var side_name := MODEL.side_key(side)
		var anchors: Array = authored_path.call("_build_authored", body_pony, side, "one")
		check(anchors.size() == 5, "the authored %s path has five anchors" % side_name)
		var authored_ids: Array = []
		for anchor_value: Variant in anchors:
			var anchor: MODEL.Anchor = anchor_value
			authored_ids.append(anchor.id)
		check(authored_ids == ["lower", "belly", "chest", "neck", "cheek"],
			"the authored %s path follows lower-belly-chest-neck-cheek" % side_name)
		if anchors.size() == 5:
			check((anchors[4] as MODEL.Anchor).region == "head",
				"the authored %s cheek uses the head mesh" % side_name)
		var side_sign := 1.0 if side == MODEL.Side.LEFT else -1.0
		for anchor_value: Variant in anchors:
			var anchor: MODEL.Anchor = anchor_value
			if anchor.id == "belly":
				continue
			var anchor_x := _anchor_point(anchor).x
			check(signf(anchor_x) == side_sign,
				"the authored %s %s is on the authored %s side" % [side_name, anchor.id, side_name])
			check(anchor.radius > 0.0 and not anchor.influences.is_empty(),
				"the authored %s %s carries its sphere and skin" % [side_name, anchor.id])
		var anchors_two: Array = authored_path.call("_build_authored", body_pony, side, "two")
		check(anchors_two.size() == 3,
			"the authored %s second path has three anchors" % side_name)
		var ids_two: Array = []
		for anchor_value: Variant in anchors_two:
			ids_two.append((anchor_value as MODEL.Anchor).id)
		check(ids_two == ["flank", "shoulder", "neck"],
			"the authored %s second path follows flank-shoulder-neck" % side_name)
		for anchor_value: Variant in anchors_two:
			var anchor: MODEL.Anchor = anchor_value
			var anchor_x := _anchor_point(anchor).x
			check(signf(anchor_x) == side_sign,
				"the authored %s second path stays on the authored %s side" % [side_name, side_name])

	# Marked area chain: the JSON standing order is a lean-sampled chain of fitted spheres.
	var area_path: Variant = PATH.new()
	check(bool(area_path.call("build_areas", body_pony, MODEL.Side.LEFT, "standing")),
		"the marked area path builds for the left hand")
	var area_ids: Array = []
	for anchor_value: Variant in (area_path.get("anchors") as Array):
		area_ids.append((anchor_value as MODEL.Anchor).id)
	check(area_ids == expected_left, "the marked area path follows the JSON standing order")
	var area_start_index := expected_left.find(area_start)
	var expected_belly_u := 0.0
	if area_start_index >= 0 and expected_left.size() > 1:
		expected_belly_u = float(area_start_index) / float(expected_left.size() - 1)
	check(near(float(area_path.get("belly_u")), expected_belly_u, 0.001),
		"the marked area path starts at the JSON start")
	var area_neutral: MODEL.Sample = area_path.call("sample", 0.0, 0.0, Vector3.RIGHT)
	var area_forward: MODEL.Sample = area_path.call("sample", 1.0, 0.0, Vector3.RIGHT)
	var area_back: MODEL.Sample = area_path.call("sample", -1.0, 0.0, Vector3.RIGHT)
	check(area_neutral != null and area_forward != null and area_back != null,
		"the marked area path samples")
	if area_neutral != null and area_forward != null and area_back != null \
			and expected_left.size() >= 2:
		var area_first := str(expected_left[0])
		var area_last := str(expected_left[expected_left.size() - 1])
		check(area_neutral.point.distance_to(
			_json_position(area_areas, area_start, "left")) < 0.01,
			"no lean starts at the JSON start area")
		check(area_forward.point.distance_to(
			_json_position(area_areas, area_last, "left")) < 0.01,
			"forward lean reaches the last JSON area")
		check(area_back.point.distance_to(
			_json_position(area_areas, area_first, "left")) < 0.01,
			"backward lean reaches the first JSON area")
		check(area_neutral.id == area_start, "the neutral area is the JSON start")
		check(area_neutral.center.is_finite() and area_neutral.radius > 0.0,
			"the area sample carries its fitted sphere")
	var area_right: Variant = PATH.new()
	check(bool(area_right.call("build_areas", body_pony, MODEL.Side.RIGHT, "standing")),
		"the marked area path builds for the right hand")
	var area_right_start: MODEL.Sample = area_right.call("sample", 0.0, 0.0, Vector3.RIGHT)
	check(area_right_start != null and area_right_start.point.x > 0.0,
		"the right area path stays on her right side")

	# Oral head path: one authored node per hand. The JSON is mare-PoV and Anon faces her, so
	# his hands read the opposite side.
	var single_path: Variant = PATH.new()
	var single_sides: Array[MODEL.Side] = [MODEL.Side.LEFT, MODEL.Side.RIGHT]
	for side: MODEL.Side in single_sides:
		var side_name := MODEL.side_key(side)
		check(bool(single_path.call("build_single_area", head_pony, side, "head_side")),
			"the head side area builds one %s node" % side_name)
		var single: MODEL.Anchor = single_path.call("single")
		check(single != null and _anchor_point(single).distance_to(
			_json_position(area_areas, "head_side", side_name)) < 0.005,
			"the %s head node snaps to the authored vertex" % side_name)
		check(single.region == "head", "the %s head node uses the head region" % side_name)
		check(str(single_path.get("single_mode")) == "palm",
			"the head side area keeps its palm mode")
	var oral_pony := NodePony.new()
	oral_pony._model = head_model
	oral_pony.skeleton = head_sk
	oral_pony.head = fake_head
	head_root.add_child(oral_pony)
	var oral_path: Variant = ORAL.new()
	oral_path.call("setup", oral_pony, null)
	var oral_context := MODEL.CaressContext.new()
	oral_context.lean = 0.0
	var oral_left: Array = oral_path.call("candidates", MODEL.Side.LEFT, oral_context)
	var oral_right: Array = oral_path.call("candidates", MODEL.Side.RIGHT, oral_context)
	check(oral_left.size() == 1 and oral_right.size() == 1,
		"the oral path returns one node per hand")
	if oral_left.size() == 1 and oral_right.size() == 1:
		var left_candidate: MODEL.Candidate = oral_left[0]
		var right_candidate: MODEL.Candidate = oral_right[0]
		var left_point := left_candidate.point
		var right_point := right_candidate.point
		check(left_point.x > 0.0 and left_point.distance_to(head_side_right) < 0.005,
			"Anon's left hand holds her right head side")
		check(right_point.x < 0.0 and right_point.distance_to(head_side_left) < 0.005,
			"Anon's right hand holds her left head side")
		check(left_candidate.region == "head", "the oral candidate uses the head region")
		check(left_candidate.mode == "palm", "the oral candidate uses the area palm mode")
		check(left_candidate.exact, "the oral node is exact and skips the sphere snap")
		check(absf(left_candidate.roll) > 0.0
			and signf(left_candidate.roll) != signf(right_candidate.roll),
			"the oral palm roll mirrors the hand")
		var oval_x := left_candidate.oval_x
		var oval_y := left_candidate.oval_y
		var oval_normal := left_candidate.normal
		check(absf(oval_x.dot(oval_y)) < 0.001 and absf(oval_x.dot(oval_normal)) < 0.001,
			"the oral oval axes are tangent and orthogonal")
		oral_context.lean = 1.0
		var leaned: Array = oral_path.call("candidates", MODEL.Side.LEFT, oral_context)
		check(leaned.size() == 1 and (leaned[0] as MODEL.Candidate).point.is_equal_approx(
			left_point), "the oral head target ignores the lean")
		var oral_debug: Array = oral_path.call("debug_world", MODEL.Side.LEFT)
		check(oral_debug.size() == 1, "the oral debug path shows the single node")
		var oral_engine: Variant = SYSTEM.new()
		var engine_context := MODEL.CaressContext.new()
		engine_context.oval = Vector2(0.02, 0.03)
		engine_context.phase = 0.0
		engine_context.hover = 0.02
		engine_context.scale = 1.0
		engine_context.delta = 0.016
		engine_context.lean = 0.0
		var frame_zero: Transform3D = oral_engine.call("frame", oral_pony, oral_path,
			MODEL.Side.LEFT, engine_context)
		engine_context.phase = PI * 0.5
		var frame_moved: Transform3D = oral_engine.call("frame", oral_pony, oral_path,
			MODEL.Side.LEFT, engine_context)
		check(frame_zero.is_finite() and frame_moved.is_finite()
			and frame_zero.origin.distance_to(frame_moved.origin) > 0.005,
			"the oral oval phase moves the intended point")
		# The exact node must not need the head fit: break the head handle after the path
		# built and confirm the engine still frames the palm at the skinned coat point.
		var head_keep: Variant = oral_pony.head
		oral_pony.head = null
		var exact_engine: Variant = SYSTEM.new()
		var exact_context := MODEL.CaressContext.new()
		exact_context.oval = Vector2.ZERO
		exact_context.phase = 0.0
		exact_context.hover = 0.02
		exact_context.scale = 1.0
		exact_context.delta = 0.016
		exact_context.lean = 0.0
		var exact_frame: Transform3D = exact_engine.call("frame", oral_pony, oral_path,
			MODEL.Side.LEFT, exact_context)
		check(exact_frame.is_finite(), "the exact oral node frames without the head fit")
		check(exact_frame.is_finite()
			and exact_frame.origin.distance_to(left_point + oval_normal * 0.02) < 0.001,
			"the exact oral palm sits on the skinned coat point with the hover")
		oral_pony.head = head_keep
	var blend_from := Transform3D(Basis(), Vector3.ZERO)
	var blend_to := Transform3D(Basis(), Vector3(1.0, 0.0, 0.0))
	check(near(MODEL.caress_oral_blend(blend_from, blend_to, 0.0).origin.x, 0.0, 0.001),
		"the oral contact blend starts at the captured frame")
	check(near(MODEL.caress_oral_blend(blend_from, blend_to,
		MODEL.CARESS_ORAL_BLEND_S * 0.5).origin.x, 0.5, 0.001),
		"the oral contact blend eases over 0.35 s")
	check(near(MODEL.caress_oral_blend(blend_from, blend_to,
		MODEL.CARESS_ORAL_BLEND_S).origin.x, 1.0, 0.001),
		"the oral contact blend reaches the target at the window end")
	check(near(MODEL.caress_oral_blend(blend_from, blend_to, 1.0).origin.x, 1.0, 0.001),
		"the oral contact blend keeps the target after the window")

	# Standing: the marked areas on the real body, the procedural flank fallback and the reach.
	var stand_pony := NodePony.new()
	stand_pony._model = body_scene as Node3D
	stand_pony.skeleton = body_sk
	stand_pony.head = fake_head
	head_root.add_child(stand_pony)
	var stand_flank := FakeFlank.new()
	stand_flank.name = "FlankTouch"
	stand_flank.centers = [Vector3(0.2, 0.55, 0.1), Vector3(-0.2, 0.55, 0.1)]
	stand_flank.normals = [Vector3.RIGHT, Vector3.LEFT]
	stand_pony.add_child(stand_flank)
	var standing_path: Variant = FLANK.new()
	standing_path.call("setup", stand_pony, null)
	var left_shoulder: MODEL.ShoulderPoint = standing_path.call("shoulder_point",
		MODEL.Side.LEFT)
	var right_shoulder: MODEL.ShoulderPoint = standing_path.call("shoulder_point",
		MODEL.Side.RIGHT)
	check(left_shoulder != null and right_shoulder != null,
		"the standing path resolves both shoulder bones")
	if left_shoulder != null and right_shoulder != null:
		check(left_shoulder.palm.x < 0.0 and right_shoulder.palm.x > 0.0,
			"the standing shoulder points sit on their own sides")
		check(left_shoulder.outward.dot(Vector3.LEFT) > 0.9
			and right_shoulder.outward.dot(Vector3.RIGHT) > 0.9,
			"the standing shoulder outward hints point away from the body")
	var stand_context := MODEL.CaressContext.new()
	stand_context.lean = 0.0
	stand_context.size = 1.0
	stand_context.profile = MODEL.CaressProfile.new(0.16, 0.08, 0.02)
	var flank_start: Array = standing_path.call("candidates", MODEL.Side.LEFT, stand_context)
	stand_context.lean = 1.0
	var flank_end: Array = standing_path.call("candidates", MODEL.Side.LEFT, stand_context)
	check(flank_start.size() == 1 and flank_end.size() == 1,
		"the standing area path returns one contact per hand")
	if flank_start.size() == 1 and flank_end.size() == 1:
		var start_point: Vector3 = (flank_start[0] as MODEL.Candidate).point
		var end_point: Vector3 = (flank_end[0] as MODEL.Candidate).point
		check(start_point.distance_to(end_point) > 0.05,
			"forward lean walks the standing path away from the flank")
		check(end_point.y > start_point.y or end_point.z < start_point.z,
			"forward lean walks toward the shoulder and neck")
		check(end_point.x < 0.0, "the left hand stays on her left side")
		var first_candidate: MODEL.Candidate = flank_start[0]
		check(first_candidate.center.is_finite(),
			"the area candidate carries its fitted sphere")
		stand_context.lean = 1.0
		var right_flank: Array = standing_path.call("candidates", MODEL.Side.RIGHT,
			stand_context)
		check(right_flank.size() == 1
			and (right_flank[0] as MODEL.Candidate).point.x > 0.0,
			"the right hand stays on her right side")
		var debug_anchors: Array = standing_path.call("debug_world", MODEL.Side.LEFT)
		check(debug_anchors.size() >= 3,
			"the standing debug path shows the area chain")
	stand_context.lean = -1.0
	var rump: Array = standing_path.call("candidates", MODEL.Side.LEFT, stand_context)
	check(rump.size() == 1, "backward lean still returns a contact")
	standing_path.call("reset")
	var area_context := MODEL.CaressContext.new()
	area_context.lean = 0.0
	area_context.size = 1.0
	var area_start_candidates: Array = standing_path.call("candidates", MODEL.Side.LEFT,
		area_context)
	check(area_start_candidates.size() == 1,
		"the area standing path returns one contact")
	if area_start_candidates.size() == 1:
		var area_candidate: MODEL.Candidate = area_start_candidates[0]
		check(area_candidate.point.x < 0.0,
			"the left area standing path stays on her left side")
		check(area_candidate.point.distance_to(
			_json_position(area_areas, area_start, "left")) < 0.02,
			"no lean starts the standing area path at the JSON start")
	area_context.hover = 0.02
	area_context.oval = Vector2.ZERO
	area_context.phase = 0.0
	area_context.delta = 0.016
	area_context.scale = 1.0
	var area_engine: Variant = SYSTEM.new()
	var area_frame: Transform3D = area_engine.call("frame", stand_pony, standing_path,
		MODEL.Side.LEFT, area_context)
	check(area_frame.is_finite(), "the area standing path builds a palm frame")
	check(area_frame.origin.x < 0.0
		and area_frame.origin.distance_to(
			_json_position(area_areas, area_start, "left")) < 0.05,
		"the area standing palm sits on the JSON start point")
	area_context.lean = 1.0
	var area_forward_candidates: Array = standing_path.call("candidates", MODEL.Side.LEFT,
		area_context)
	check(area_forward_candidates.size() == 1
		and (area_forward_candidates[0] as MODEL.Candidate).point.x < 0.0,
		"forward lean reaches the area neck")
	area_context.lean = -1.0
	var area_back_candidates: Array = standing_path.call("candidates", MODEL.Side.LEFT,
		area_context)
	check(area_back_candidates.size() == 1
		and (area_back_candidates[0] as MODEL.Candidate).point.x < 0.0,
		"backward lean reaches the area flank_back")

	# The background fit fills the cache one area per tick while the act poses, and the warm
	# build waits for it so the first caress press pays nothing.
	var prefetched := 0
	while prefetched < 400 and PATH.prefit_tick(stand_pony):
		prefetched += 1
	check(not PATH.prefit_pending(stand_pony), "the background coat fit drains its queue")
	check(prefetched >= 20, "the background fit covers every authored area")
	var warm_facts := ACT_FACTS.new()
	warm_facts.pony = stand_pony
	warm_facts.size_scale = 1.0
	warm_facts.lean_forward = 0.0
	warm_facts.physics_delta = 0.016
	var warm_view: RefCounted = VIEW.new()
	warm_view.family = "standing"
	warm_view.hands = {"path": "standing"}
	warm_view.contact_kind = "opening"
	warm_facts.pose_view = warm_view
	var warm_hands := CONTROLLER.new(warm_facts)
	warm_hands.tick(0.016, true)
	var warm_provider: Variant = warm_hands.path()
	check(warm_provider is FLANK
		and (warm_provider as FLANK).built_hand_count() == 1,
		"the first warm tick builds only its own hand's path")
	warm_hands.tick(0.016, true)
	check(warm_provider is FLANK
		and (warm_provider as FLANK).built_hand_count() == 2,
		"the second warm tick builds the other hand's path")
	check(not warm_hands.caress().active(MODEL.Side.LEFT)
		and not warm_hands.caress().active(MODEL.Side.RIGHT),
		"warming never latches a caress")
	warm_hands.tick(0.016, true)
	check(warm_provider is FLANK
		and (warm_provider as FLANK).built_hand_count() == 2,
		"a third warm tick does no work")
	standing_path.call("reset")
	head_root.free()
	head_pony.free()
	body_pony.free()

	# The pose-free engine: the same candidate gives the same frame through different paths, the
	# sphere projects the intended oval point, and contact smoothing never delays the intended
	# motion.
	var engine: Variant = SYSTEM.new()
	var engine_fixture := _path_fixture()
	var engine_pony: Variant = engine_fixture["pony"]
	var engine_root: Node3D = engine_fixture["root"]
	var first_path := FixedPath.new()
	first_path.point = Vector3(0.0, -0.3, -0.5)
	first_path.normal = Vector3.DOWN
	var second_path := FixedPath.new()
	second_path.point = first_path.point
	second_path.normal = first_path.normal
	var context := MODEL.CaressContext.new()
	context.oval = Vector2.ZERO
	context.phase = 0.0
	context.hover = 0.02
	context.scale = 1.0
	context.delta = 0.016
	var first_frame: Transform3D = engine.call("frame", engine_pony, first_path,
		MODEL.Side.RIGHT, context)
	var second_frame: Transform3D = engine.call("frame", engine_pony, second_path,
		MODEL.Side.RIGHT, context)
	check(first_frame.is_finite(), "the engine builds a palm frame")
	check(first_frame.is_equal_approx(second_frame),
		"the engine does not depend on which pose path supplied the contact")
	check(near(first_frame.origin.y, -0.32, 0.005),
		"a candidate without a sphere keeps its exact coat point and hover")
	check((first_path.calls == 1) and (second_path.calls == 1),
		"each caress hand asks its path once per tick")
	var sphere_path := FixedPath.new()
	sphere_path.point = Vector3(0.1, -0.1, 0.0)
	sphere_path.normal = Vector3.UP
	sphere_path.center = Vector3(0.0, -0.3, 0.0)
	sphere_path.radius = 0.2
	var sphere_frame: Transform3D = engine.call("frame", engine_pony, sphere_path,
		MODEL.Side.LEFT, context)
	check(sphere_frame.is_finite(), "the engine frames a fitted sphere candidate")
	check(near((sphere_frame.origin - sphere_path.center).length(), 0.22, 0.006),
		"the palm sits one hover above the fitted sphere")
	var state := MODEL.ContactState.new()
	var first_smooth: MODEL.ContactState = engine.call("_smooth_precise", state,
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.01, 0.0), Vector3.UP, 0.016, context)
	check(near(first_smooth.point.y, 0.01, 0.001),
		"the first exact contact starts without smoothing")
	var second_smooth: MODEL.ContactState = engine.call("_smooth_precise", state,
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.02, 0.0), Vector3.UP, 0.016, context)
	check(near(second_smooth.point.x, 1.0, 0.001),
		"contact smoothing never delays the intended caress motion")
	var offset_y := second_smooth.point.y
	check(offset_y > 0.01 and offset_y < 0.02,
		"contact smoothing eases the sphere snap correction")
	engine.call("reset")
	engine_root.free()
	engine_pony.free()

	# Standing path: the flank centre and oval axes are pose geometry, supplied to the engine.
	var flank_root := Node3D.new()
	get_root().add_child(flank_root)
	var flank := FakeFlank.new()
	flank.name = "FlankTouch"
	flank.centers = [Vector3(0.2, 0.0, 0.0), Vector3(-0.2, 0.0, 0.0)]
	flank.normals = [Vector3.RIGHT, Vector3.LEFT]
	var flank_pony := FlankPony.new()
	flank_pony._model = flank_root
	flank_pony.skeleton = null
	flank_root.add_child(flank_pony)
	flank_pony.add_child(flank)
	var flank_path: Variant = FLANK.new()
	flank_path.call("setup", flank_pony, null)
	var flank_context := MODEL.CaressContext.new()
	flank_context.lean = 0.0
	flank_context.size = 1.0
	flank_context.profile = MODEL.CaressProfile.new(0.16, 0.08, 0.02)
	var flank_candidates: Array = flank_path.call("candidates", MODEL.Side.RIGHT, flank_context)
	check(flank_candidates.size() == 1, "the standing path returns one contact")
	if flank_candidates.size() == 1:
		var flank_candidate: MODEL.Candidate = flank_candidates[0]
		check(flank_candidate.point.is_finite() and flank_candidate.point.y > 0.15,
			"the standing path lifts the rub above the flank centre")
		check(flank_candidate.normal.dot(Vector3.RIGHT) > 0.9,
			"the standing path faces outward")
		check(absf(flank_candidate.oval_x.dot(flank_candidate.oval_y)) < 0.001
			and absf(flank_candidate.oval_x.dot(flank_candidate.normal)) < 0.001,
			"the standing oval axes are tangent and orthogonal")
		check(flank_candidate.oval_x.length() > 0.99 and flank_candidate.oval_y.length() > 0.99,
			"the standing oval axes are normalized")
		check(flank_candidate.radius == 0.0,
			"the procedural flank point has no sphere and stays exact")
	var coat_engine: Variant = SYSTEM.new()
	var coat_context := MODEL.CoatContext.new()
	coat_context.contact_smooth = 0.0
	coat_context.normal_deg_s = 0.0
	var coat_frame: Transform3D = coat_engine.call("coat_frame", flank_pony, MODEL.Side.RIGHT,
		Vector3(0.0, 1.0, 0.0), Vector3.UP, Vector3.FORWARD, 0.02, coat_context)
	check(coat_frame.is_finite(), "the shared engine builds a hull palm frame")
	check(near(coat_frame.origin.y, 1.02, 0.001),
		"the hull palm frame sits one clearance above the coat")
	flank_root.free()

	var near_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(0.5, 0.0, 0.0),
		1.0, 0.08, 0.0)
	check(bool(near_plan.get("reachable", false)), "a short target is reachable")
	check(near(float(near_plan.get("stretch", 0.0)), 1.0, 0.001), "a short target needs no stretch")
	var far_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(1.0, 0.0, 0.0),
		1.0, 0.05, 0.0)
	check(not bool(far_plan.get("reachable", true)), "a far target is clamped")
	check((far_plan.get("target", Vector3.ZERO) as Vector3).length() <= 0.65 + 0.001,
		"the clamped target stays within the arm reach")
	check(near(float(far_plan.get("shoulder_shift", 0.0)), 0.05, 0.001),
		"the shoulder cap is consumed before the clamp")
	var body_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(1.0, 0.0, 0.0),
		1.0, 0.05, 0.15)
	check(near(float(body_plan.get("body_shift", 0.0)), 0.15, 0.001),
		"the body cap is used after the shoulder cap")

	if failures == 0:
		print("HANDS_PASS")
	finish()
