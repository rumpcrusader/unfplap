extends SceneTree
## Caress contact surface, hand shape and reach plan.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hands/test_caress.gd

const SURFACE := preload("res://mods/unfplap/hands/surface.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")
const ARM := preload("res://mods/unfplap/shared/hands_reach_plan.gd")
const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const SYSTEM := preload("res://mods/unfplap/hands/placement.gd")
const FLANK := preload("res://mods/unfplap/hands/paths/standing.gd")
const ORAL := preload("res://mods/unfplap/hands/paths/oral.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

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


class FixedPath extends RefCounted:
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var calls := 0

	func candidates(_hand_side: String, _context: Dictionary) -> Array:
		calls += 1
		return [{
			"point": point,
			"normal": normal,
			"oval_x": Vector3.RIGHT,
			"oval_y": Vector3.FORWARD,
			"finger": Vector3.FORWARD,
			"mode": "palm",
			"roll": 0.0,
			"region": "torso",
		}]

	func debug_world(_hand_side: String) -> Array:
		return []


class FakeHead extends RefCounted:
	var model: Node3D
	var skeleton: Skeleton3D

class FakePony extends RefCounted:
	var _model: Node3D
	var skeleton: Skeleton3D
	var head: Variant = null

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


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


func _plane() -> Variant:
	var surface: Variant = SURFACE.new()
	var faces := PackedVector3Array([
		Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1),
		Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1),
	])
	var normals := PackedVector3Array()
	for _i in 6:
		normals.append(Vector3.UP)
	surface.set("faces", faces)
	surface.set("vertex_normals", normals)
	return surface


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
	var surface: Variant = _plane()
	var hit: Dictionary = surface.call("closest", Vector3(0.2, 0.25, 0.1))
	check(not hit.is_empty(), "the triangle patch answers a closest query")
	check(near(float(hit.get("point", Vector3.ZERO).y), 0.0), "the patch contact lies on the plane")
	check((hit.get("normal", Vector3.UP) as Vector3).dot(Vector3.UP) > 0.99,
		"the patch uses its vertex normal")
	check(not bool(hit.get("inside", true)), "a point above the plane is outside")
	var under: Dictionary = surface.call("closest", Vector3(0.0, -0.1, 0.0))
	check(bool(under.get("inside", false)), "a point below the plane is inside")
	var tri: TriangleMesh = surface.get("_tri")
	check(tri == null, "the ray mesh is built lazily")
	var ray_hit: Dictionary = surface.call("nearest", Vector3(0.2, 0.1, 0.1), Vector3.UP)
	check(not ray_hit.is_empty(), "the hand ray finds the plane")
	check(near(float(ray_hit.get("point", Vector3.ZERO).y), 0.0),
		"the ray contact lies on the plane")
	check(not bool(ray_hit.get("inside", true)), "the ray point outside the plane is outside")
	check(surface.get("_tri") != null, "the first ray builds the ray mesh once")

	# The player quality: precise still snaps a missed ray to the coat; fast keeps the intended
	# oval point and the path normal when the ray misses.
	var lossy: Variant = _plane()
	lossy.call("set_quality", "fast")
	var miss: Dictionary = lossy.call("nearest", Vector3(0.2, 0.5, 0.1), Vector3.UP)
	check(int(miss.get("face", 0)) < 0, "the lossy miss reports no exact face")
	check((miss.get("point", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.2, 0.5, 0.1)),
		"the lossy miss keeps the intended oval point")
	var exact: Variant = _plane()
	exact.call("set_quality", "precise")
	var exact_miss: Dictionary = exact.call("nearest", Vector3(0.2, 0.5, 0.1), Vector3.UP)
	var exact_point: Vector3 = exact_miss.get("point", Vector3.ZERO)
	check(near(exact_point.y, 0.0), "precise still snaps a missed ray to the coat")
	lossy.call("set_quality", "precise")
	check(int(lossy.get("update_ms")) == 33 and int(lossy.get("blur_depth")) == 2,
		"precise restores the full patch refresh and blur")
	lossy.call("set_quality", "fast")
	check(int(lossy.get("update_ms")) == 66 and int(lossy.get("blur_depth")) == 1,
		"fast lowers the patch refresh and the blur ring")

	# The refresh gate: a still body keeps the last skinned patch instead of paying for the skin,
	# the soup write and the BVH rebuild.
	var identity := Transform3D.IDENTITY
	check(SURFACE._pose_close(identity, identity),
		"the refresh gate accepts an unchanged pose")
	check(SURFACE._pose_close(identity,
		Transform3D(Basis(), Vector3(0.0005, 0.0, 0.0))),
		"the refresh gate accepts a sub-millimetre shift")
	check(not SURFACE._pose_close(identity,
		Transform3D(Basis(), Vector3(0.003, 0.0, 0.0))),
		"the refresh gate rejects a 3 mm shift")
	check(not SURFACE._pose_close(identity,
		Transform3D(Basis(Vector3.UP, deg_to_rad(2.0)), Vector3.ZERO)),
		"the refresh gate rejects a 2 degree turn")
	check(not SURFACE._pose_close(identity,
		Transform3D(Basis(Vector3.RIGHT, deg_to_rad(2.0)), Vector3.ZERO)),
		"the refresh gate catches a turn about a second axis")

	var palm := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "palm", 0.0, 0.0)
	var hovered := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "palm",
		0.0, 0.03)
	check(near(hovered.origin.y, 0.03), "the single-point palm uses the hover distance")
	var right_basis := HAND.palm_basis("right", Vector3.UP, Vector3.FORWARD, 30.0)
	var left_basis := HAND.palm_basis("left", Vector3.UP, Vector3.FORWARD, -30.0)
	check(right_basis.x.dot(Vector3.UP) > 0.99, "the right palm marker faces the coat")
	check(left_basis.x.dot(Vector3.UP) < -0.99, "the left palm marker faces the coat")
	check(right_basis.determinant() > 0.99 and left_basis.determinant() > 0.99,
		"the rolled palm bases stay orthonormal")
	var tip := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "fingertip", 0.0, 0.0)
	check(tip.is_finite() and tip.origin != palm.origin,
		"the fingertip mode uses its own palm offset")

	check(near(PATH.u_for(-1.0, 0.0), 0.0), "S reaches the lower belly anchor")
	check(near(PATH.u_for(0.0, 0.0), PATH.BELLY_U), "neutral stays on the belly anchor")
	check(near(PATH.u_for(1.0, 0.0), 1.0), "W reaches the cheek anchor")
	check(near(PATH.u_for(0.5, 0.25), 0.875), "along_m shifts the path parameter")
	var world: Array = []
	for i in 5:
		world.append({
			"position": Vector3(0.0, 0.0, -float(i) * 0.2),
			"normal": Vector3.UP,
			"lateral": 1.0 - float(i) * 0.25,
			"roll": 1.0 - float(i) * 0.25,
			"region": "head" if i == 4 else "torso",
		})
	var start: Dictionary = PATH.sample_world(world, 0.0, "right", Vector3.RIGHT)
	var middle: Dictionary = PATH.sample_world(world, PATH.BELLY_U, "right", Vector3.RIGHT)
	var end: Dictionary = PATH.sample_world(world, 1.0, "right", Vector3.RIGHT)
	check(near((start["point"] as Vector3).z, 0.0), "the path starts at the lower anchor")
	check(near((end["point"] as Vector3).z, -0.8), "the path ends at the cheek anchor")
	check((middle["point"] as Vector3).z < -0.15 and (middle["point"] as Vector3).z > -0.3,
		"neutral sits near the belly anchor")
	check((middle["finger"] as Vector3).dot(Vector3.FORWARD) > 0.9,
		"the path tangent points toward her head")
	check(near(float(end["lateral"]), 0.0), "the lateral offset fades at the cheek")
	check(str(end["region"]) == "head", "the cheek sample uses the head region")
	var left: Dictionary = PATH.sample_world(world, PATH.BELLY_U, "left", Vector3.RIGHT)
	check((left["side"] as Vector3).dot(Vector3.RIGHT) < -0.9,
		"the left hand uses her left lateral axis")

	var fixture := _path_fixture()
	var pony: Variant = fixture["pony"]
	var root: Node3D = fixture["root"]
	var path: Variant = PATH.new()
	check(bool(path.call("build", pony, "right")), "the path builds from a real skinned mesh")
	check((path.get("anchors") as Array).size() >= 3, "the path finds the body anchors")
	var built: Dictionary = path.call("sample", 0.0, 0.0, Vector3.RIGHT)
	check(not built.is_empty(), "the built path samples")
	var built_point: Vector3 = built["point"]
	var built_finger: Vector3 = built["finger"]
	var built_normal: Vector3 = built["normal"]
	check(built_point.is_finite(), "the built path point is finite")
	check(near(built_point.y, -0.3, 0.01), "the built path point sits on the body mesh")
	check(built_finger.dot(Vector3.FORWARD) > 0.5,
		"the built path tangent points toward her head")
	check(built_normal.y < -0.9, "the built path normal faces outward")
	var ids: Array = []
	for anchor: Dictionary in (path.get("anchors") as Array):
		ids.append(str(anchor.get("id", "")))
	check(ids.has("lower"), "the path keeps the lower belly anchor")
	check(ids.has("neck"), "the path finds the neck side")
	for anchor: Dictionary in (path.get("anchors") as Array):
		if str(anchor.get("id", "")) == "lower":
			var lower_position: Vector3 = anchor["position"]
			check(near(lower_position.y, -0.3, 0.01),
				"the lower anchor stays on the belly")
	root.free()

	# The real OpenPony head: the Head mesh's `skeleton` path is the model root, so the source
	# must use the skeleton passed by `find_mesh`, not `mesh.skeleton`.
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
	var head_surface: Variant = SURFACE.new()
	var head_ok := bool(head_surface.call("ensure", head_pony, "head"))
	check(head_ok, "the real head source builds")
	if head_ok:
		var head_source: Dictionary = head_surface.get("source")
		check(not (head_source.get("vertices", []) as Array).is_empty(),
			"the real head source has vertices")
		var head_faces := PackedVector3Array()
		var head_vertices: Array = head_source["vertices"]
		var head_indices: PackedInt32Array = head_source["indices"]
		head_faces.resize(head_indices.size())
		for i in head_indices.size():
			head_faces[i] = head_vertices[head_indices[i]]["position"]
		var head_tri := TriangleMesh.new()
		head_tri.create_from_faces(head_faces)
		var head_bone := head_sk.find_bone("mHead")
		check(head_bone >= 0, "the real head skeleton has mHead")
		if head_bone >= 0:
			var head_origin: Vector3 = head_sk.get_bone_global_rest(head_bone).origin \
				+ Vector3.FORWARD * 0.52
			var head_hit: Dictionary = head_tri.intersect_segment(
				head_origin + Vector3.RIGHT * 0.6,
				head_origin - Vector3.RIGHT * 0.6)
			check(not head_hit.is_empty(), "the cheek ray hits the real head")
	# Authored anchors from the Blender vertex groups, snapped to the real body/head sources.
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
	var authored_path: Variant = PATH.new()
	for side in ["left", "right"]:
		var anchors: Array = authored_path.call("_build_authored", body_pony, side, "one")
		check(anchors.size() == 5, "the authored %s path has five anchors" % side)
		var authored_ids: Array = []
		for anchor: Dictionary in anchors:
			authored_ids.append(str(anchor.get("id", "")))
		check(authored_ids == ["lower", "belly", "chest", "neck", "cheek"],
			"the authored %s path follows lower-belly-chest-neck-cheek" % side)
		if anchors.size() == 5:
			check(str((anchors[4] as Dictionary).get("source_region", "")) == "head",
				"the authored %s cheek uses the head source" % side)
		var side_sign := 1.0 if side == "left" else -1.0
		for anchor: Dictionary in anchors:
			var anchor_id := str(anchor.get("id", ""))
			if anchor_id == "belly":
				continue
			var anchor_x := (anchor.get("position", Vector3.ZERO) as Vector3).x
			check(signf(anchor_x) == side_sign,
				"the authored %s %s is on the authored %s side" % [side, anchor_id, side])
		var anchors_two: Array = authored_path.call("_build_authored", body_pony, side, "two")
		check(anchors_two.size() == 3, "the authored %s second path has three anchors" % side)
		var ids_two: Array = []
		for anchor: Dictionary in anchors_two:
			ids_two.append(str(anchor.get("id", "")))
		check(ids_two == ["flank", "shoulder", "neck"],
			"the authored %s second path follows flank-shoulder-neck" % side)
		for anchor: Dictionary in anchors_two:
			var anchor_x := (anchor.get("position", Vector3.ZERO) as Vector3).x
			check(signf(anchor_x) == side_sign,
				"the authored %s second path stays on the authored %s side" % [side, side])
	# Marked area path: the JSON standing order is a lean-sampled chain.
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
	# Local caress window: the region source is unchanged, but each hand skins and raycasts only
	# the coat around its intended point. Inside the window the contact matches the full patch.
	var local_surface: Variant = SURFACE.new()
	check(bool(local_surface.call("ensure", body_pony, "torso")),
		"the local caress window source builds")
	local_surface.call("set_quality", "precise")
	local_surface.call("set_local", true)
	var flank_centre := _json_position(area_areas, "flank_side", "left")
	var flank_out := Vector3.LEFT
	local_surface.call("select", flank_centre)
	local_surface.call("update_pose", true)
	var local_faces := int(local_surface.call("face_count"))
	var full_faces := int(local_surface.call("patch_face_count"))
	check(local_faces > 100 and local_faces * 2 < full_faces,
		"the local window keeps a fraction of the patch")
	var full_surface: Variant = SURFACE.new()
	full_surface.call("ensure", body_pony, "torso")
	full_surface.call("update_pose", true)
	for point: Vector3 in [flank_centre, flank_centre + Vector3.UP * 0.03,
			flank_centre + Vector3.BACK * 0.04,
			flank_centre + Vector3.UP * 0.03 + Vector3.BACK * 0.03]:
		var local_hit: Dictionary = local_surface.call("nearest", point, flank_out)
		var full_hit: Dictionary = full_surface.call("nearest", point, flank_out)
		check(not local_hit.is_empty() and not full_hit.is_empty(),
			"the local and full patches both answer a nearby ray")
		if local_hit.is_empty() or full_hit.is_empty():
			continue
		if int(local_hit.get("face", -1)) < 0 or int(full_hit.get("face", -1)) < 0:
			continue
		check((local_hit["point"] as Vector3).distance_to(full_hit["point"] as Vector3) < 0.0005,
			"the local window keeps the exact contact point")
		check((local_hit["normal"] as Vector3).dot(full_hit["normal"] as Vector3) > 0.999,
			"the local window keeps the exact contact normal")
	var seed_hit: Dictionary = local_surface.call("nearest", flank_centre + Vector3.UP * 0.03,
		flank_out)
	var seed := int(seed_hit.get("seed", -1))
	var seed_face := int(seed_hit.get("face", -1))
	var local_face_ids: PackedInt32Array = local_surface.get("_local_faces")
	var source_indices: PackedInt32Array = local_surface.get("_indices")
	check(seed >= 0, "the local hit reports a vertex seed")
	if seed >= 0 and seed_face >= 0 and seed_face < local_face_ids.size():
		var at := local_face_ids[seed_face] * 3
		check(seed == source_indices[at] or seed == source_indices[at + 1]
			or seed == source_indices[at + 2],
			"the blur seed is a vertex of the hit face")
	var first_center: Vector3 = local_surface.get("_local_center")
	var neck_point := flank_centre + Vector3.FORWARD * 0.30
	local_surface.call("select", neck_point)
	local_surface.call("update_pose", true)
	check(bool(local_surface.get("_local_valid")), "the re-centred window stays local")
	check((local_surface.get("_local_center") as Vector3).distance_to(first_center) > 0.1,
		"the window re-centres when the hand leaves its core")
	check(not (local_surface.call("nearest", neck_point, flank_out) as Dictionary).is_empty(),
		"the re-centred window still answers the ray")
	local_surface.call("set_local", false)
	local_surface.call("update_pose", true)
	check(int(local_surface.call("face_count")) == full_faces,
		"turning the local window off restores the full patch")
	var local_facts := ACT_FACTS.new()
	local_facts.features = {"caress_local": true}
	var split_engine: Variant = SYSTEM.new(local_facts)
	var left_surface: Variant = split_engine.call("_surface", body_pony, "torso", "left",
		flank_centre)
	var right_surface: Variant = split_engine.call("_surface", body_pony, "torso", "right",
		flank_centre)
	check(left_surface != null and right_surface != null and left_surface != right_surface,
		"each hand owns its local caress window")
	local_facts.features = {"caress_local": false}
	var shared_engine: Variant = SYSTEM.new(local_facts)
	var shared_left: Variant = shared_engine.call("_surface", body_pony, "torso", "left",
		flank_centre)
	var shared_right: Variant = shared_engine.call("_surface", body_pony, "torso", "right",
		flank_centre)
	check(shared_left != null and shared_left == shared_right,
		"the full caress patch is shared by both hands")
	var area_path: Variant = PATH.new()
	check(bool(area_path.call("build_areas", body_pony, "left", "standing")),
		"the marked area path builds for the left hand")
	var area_ids: Array = []
	for anchor: Dictionary in (area_path.get("anchors") as Array):
		area_ids.append(str(anchor.get("id", "")))
	check(area_ids == expected_left, "the marked area path follows the JSON standing order")
	var area_start_index := expected_left.find(area_start)
	check(area_start_index >= 0, "the JSON start is in the standing area order")
	var expected_belly_u := 0.0
	if area_start_index >= 0 and expected_left.size() > 1:
		expected_belly_u = float(area_start_index) / float(expected_left.size() - 1)
	check(near(float(area_path.get("belly_u")), expected_belly_u),
		"the marked area path starts at the JSON start")
	var area_neutral: Dictionary = area_path.call("sample", 0.0, 0.0, Vector3.RIGHT)
	var area_forward: Dictionary = area_path.call("sample", 1.0, 0.0, Vector3.RIGHT)
	var area_back: Dictionary = area_path.call("sample", -1.0, 0.0, Vector3.RIGHT)
	check(not area_neutral.is_empty() and not area_forward.is_empty() and not area_back.is_empty(),
		"the marked area path samples")
	if not area_neutral.is_empty() and not area_forward.is_empty() and not area_back.is_empty() \
			and expected_left.size() >= 2:
		var area_first := str(expected_left[0])
		var area_last := str(expected_left[expected_left.size() - 1])
		check((area_neutral["point"] as Vector3).distance_to(
			_json_position(area_areas, area_start, "left")) < 0.01,
			"no lean starts at the JSON start area")
		check((area_forward["point"] as Vector3).distance_to(
			_json_position(area_areas, area_last, "left")) < 0.01,
			"forward lean reaches the last JSON area")
		check((area_back["point"] as Vector3).distance_to(
			_json_position(area_areas, area_first, "left")) < 0.01,
			"backward lean reaches the first JSON area")
		check(str(area_neutral.get("id", "")) == area_start,
			"the neutral area is the JSON start")
	var area_right: Variant = PATH.new()
	check(bool(area_right.call("build_areas", body_pony, "right", "standing")),
		"the marked area path builds for the right hand")
	var area_right_start: Dictionary = area_right.call("sample", 0.0, 0.0, Vector3.RIGHT)
	check(not area_right_start.is_empty()
		and (area_right_start["point"] as Vector3).x > 0.0,
		"the right area path stays on her right side")
	# Oral head path: one authored node per hand. The JSON is mare-PoV and Anon faces her, so
	# his hands read the opposite side.
	var head_side_left := _json_position(area_areas, "head_side", "left")
	var head_side_right := _json_position(area_areas, "head_side", "right")
	check(head_side_left.x < 0.0 and head_side_right.x > 0.0,
		"the head side JSON is authored from the mare's point of view")
	var single_path: Variant = PATH.new()
	for side in ["left", "right"]:
		check(bool(single_path.call("build_single_area", head_pony, side, "head_side")),
			"the head side area builds one %s node" % side)
		var single: Dictionary = single_path.call("single")
		check(not single.is_empty()
			and (single.get("position", Vector3.ZERO) as Vector3).distance_to(
				_json_position(area_areas, "head_side", side)) < 0.005,
			"the %s head node snaps to the authored vertex" % side)
		check(str(single.get("region", "")) == "head",
			"the %s head node uses the head region" % side)
		check(str(single_path.get("single_mode")) == "palm",
			"the head side area keeps its palm mode")
	var oral_pony := NodePony.new()
	oral_pony._model = head_model
	oral_pony.skeleton = head_sk
	oral_pony.head = fake_head
	head_root.add_child(oral_pony)
	var oral_path: Variant = ORAL.new()
	oral_path.call("setup", oral_pony, null)
	var oral_left: Array = oral_path.call("candidates", "left", {"lean": 0.0})
	var oral_right: Array = oral_path.call("candidates", "right", {"lean": 0.0})
	check(oral_left.size() == 1 and oral_right.size() == 1,
		"the oral path returns one node per hand")
	if oral_left.size() == 1 and oral_right.size() == 1:
		var left_candidate: Dictionary = oral_left[0]
		var right_candidate: Dictionary = oral_right[0]
		var left_point: Vector3 = left_candidate["point"]
		var right_point: Vector3 = right_candidate["point"]
		check(left_point.x > 0.0 and left_point.distance_to(head_side_right) < 0.005,
			"Anon's left hand holds her right head side")
		check(right_point.x < 0.0 and right_point.distance_to(head_side_left) < 0.005,
			"Anon's right hand holds her left head side")
		check(str(left_candidate.get("region", "")) == "head",
			"the oral candidate uses the head region")
		check(str(left_candidate.get("mode", "")) == "palm",
			"the oral candidate uses the area palm mode")
		check(absf(float(left_candidate.get("roll", 0.0))) > 0.0
			and signf(float(left_candidate.get("roll", 0.0)))
				!= signf(float(right_candidate.get("roll", 0.0))),
			"the oral palm roll mirrors the hand")
		var oval_x: Vector3 = left_candidate["oval_x"]
		var oval_y: Vector3 = left_candidate["oval_y"]
		var oval_normal: Vector3 = left_candidate["normal"]
		check(absf(oval_x.dot(oval_y)) < 0.001 and absf(oval_x.dot(oval_normal)) < 0.001,
			"the oral oval axes are tangent and orthogonal")
		var leaned: Array = oral_path.call("candidates", "left", {"lean": 1.0})
		check(leaned.size() == 1
			and (leaned[0]["point"] as Vector3).is_equal_approx(left_point),
			"the oral head target ignores the lean")
		var oral_debug: Array = oral_path.call("debug_world", "left")
		check(oral_debug.size() == 1, "the oral debug path shows the single node")
		var oral_engine: Variant = SYSTEM.new()
		var oral_context := {
			"oval": Vector2(0.02, 0.03), "phase": 0.0, "hover": 0.02,
			"clearance": 0.02, "scale": 1.0, "delta": 0.016, "lean": 0.0,
		}
		var frame_zero: Transform3D = oral_engine.call("frame", oral_pony, oral_path,
			"left", oral_context)
		oral_context["phase"] = PI * 0.5
		var frame_moved: Transform3D = oral_engine.call("frame", oral_pony, oral_path,
			"left", oral_context)
		check(frame_zero.is_finite() and frame_moved.is_finite()
			and frame_zero.origin.distance_to(frame_moved.origin) > 0.005,
			"the oral oval phase moves the intended point")
	var blend_from := Transform3D(Basis(), Vector3.ZERO)
	var blend_to := Transform3D(Basis(), Vector3(1.0, 0.0, 0.0))
	check(near(HANDS.caress_oral_blend(blend_from, blend_to, 0.0).origin.x, 0.0),
		"the oral contact blend starts at the captured frame")
	check(near(HANDS.caress_oral_blend(blend_from, blend_to,
		HANDS.CARESS_ORAL_BLEND_S * 0.5).origin.x, 0.5),
		"the oral contact blend eases over 0.35 s")
	check(near(HANDS.caress_oral_blend(blend_from, blend_to,
		HANDS.CARESS_ORAL_BLEND_S).origin.x, 1.0),
		"the oral contact blend reaches the target at the window end")
	check(near(HANDS.caress_oral_blend(blend_from, blend_to, 1.0).origin.x, 1.0),
		"the oral contact blend keeps the target after the window")
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
	var left_shoulder: Dictionary = standing_path.call("shoulder_point", "left")
	var right_shoulder: Dictionary = standing_path.call("shoulder_point", "right")
	check(not standing_path.call("shoulder_point", "L").is_empty()
		and not standing_path.call("shoulder_point", "R").is_empty(),
		"the standing shoulder point accepts both side spellings")
	check(not left_shoulder.is_empty() and not right_shoulder.is_empty(),
		"the standing path resolves both shoulder bones")
	if not left_shoulder.is_empty() and not right_shoulder.is_empty():
		check((left_shoulder["palm"] as Vector3).x < 0.0
			and (right_shoulder["palm"] as Vector3).x > 0.0,
			"the standing shoulder points sit on their own sides")
		check((left_shoulder["outward"] as Vector3).dot(Vector3.LEFT) > 0.9
			and (right_shoulder["outward"] as Vector3).dot(Vector3.RIGHT) > 0.9,
			"the standing shoulder outward hints point away from the body")
	var stand_context := {
		"lean": 0.0, "size": 1.0, "profile": {"up": 0.16, "back": 0.08, "out": 0.02},
	}
	var flank_start: Array = standing_path.call("candidates", "left", stand_context)
	stand_context["lean"] = 1.0
	var flank_end: Array = standing_path.call("candidates", "left", stand_context)
	check(flank_start.size() == 1 and flank_end.size() == 1,
		"the standing area path returns one contact per hand")
	if flank_start.size() == 1 and flank_end.size() == 1:
		var start_point: Vector3 = flank_start[0]["point"]
		var end_point: Vector3 = flank_end[0]["point"]
		check(start_point.distance_to(end_point) > 0.05,
			"forward lean walks the standing path away from the flank")
		check(end_point.y > start_point.y or end_point.z < start_point.z,
			"forward lean walks toward the shoulder and neck")
		check((end_point as Vector3).x < 0.0, "the left hand stays on her left side")
		stand_context["lean"] = 1.0
		var right_flank: Array = standing_path.call("candidates", "right", stand_context)
		check(right_flank.size() == 1 and (right_flank[0]["point"] as Vector3).x > 0.0,
			"the right hand stays on her right side")
		var debug_anchors: Array = standing_path.call("debug_world", "left")
		check(debug_anchors.size() >= 3,
			"the standing debug path shows the area chain")
	stand_context["lean"] = -1.0
	var rump: Array = standing_path.call("candidates", "left", stand_context)
	check(rump.size() == 1, "backward lean still returns a contact")
	# The marked area chain is the standing path; no toggle remains.
	standing_path.call("reset")
	var area_context := {
		"lean": 0.0, "size": 1.0, "profile": {},
	}
	var area_start_candidates: Array = standing_path.call("candidates", "left", area_context)
	check(area_start_candidates.size() == 1,
		"the area standing path returns one contact")
	if area_start_candidates.size() == 1:
		var area_candidate: Dictionary = area_start_candidates[0]
		check((area_candidate["point"] as Vector3).x < 0.0,
			"the left area standing path stays on her left side")
		check((area_candidate["point"] as Vector3).distance_to(
			_json_position(area_areas, area_start, "left")) < 0.02,
			"no lean starts the standing area path at the JSON start")
	area_context["hover"] = 0.02
	area_context["clearance"] = 0.02
	area_context["oval"] = Vector2.ZERO
	area_context["phase"] = 0.0
	area_context["delta"] = 0.016
	area_context["scale"] = 1.0
	var area_engine: Variant = SYSTEM.new()
	var area_frame: Transform3D = area_engine.call("frame", stand_pony, standing_path,
		"left", area_context)
	check(area_frame.is_finite(), "the area standing path builds a palm frame")
	check((area_frame.origin as Vector3).x < 0.0
		and (area_frame.origin as Vector3).distance_to(
			_json_position(area_areas, area_start, "left")) < 0.05,
		"the area standing palm sits on the JSON start point")
	area_context["lean"] = 1.0
	var area_forward_candidates: Array = standing_path.call("candidates", "left", area_context)
	check(area_forward_candidates.size() == 1
		and (area_forward_candidates[0]["point"] as Vector3).x < 0.0,
		"forward lean reaches the area neck")
	area_context["lean"] = -1.0
	var area_back_candidates: Array = standing_path.call("candidates", "left", area_context)
	check(area_back_candidates.size() == 1
		and (area_back_candidates[0]["point"] as Vector3).x < 0.0,
		"backward lean reaches the area flank_back")
	standing_path.call("reset")
	head_root.free()

	var blur_surface: Variant = SURFACE.new()
	blur_surface.set("_positions", PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.0, 0.0), Vector3(0.10, 0.0, 0.0),
	]))
	blur_surface.set("_normals", PackedVector3Array([
		Vector3.UP, Vector3(0.7, 0.7, 0.0), Vector3.RIGHT,
	]))
	var blurred: Vector3 = blur_surface.call("normal_blur", Vector3.ZERO, 0.08, Vector3.UP)
	check(blurred.length() > 0.99, "the crease normal blur is normalized")
	check(blurred.y > 0.7 and blurred.x > 0.1,
		"the crease normal blur averages the facing normals")
	check((blur_surface.call("normal_blur", Vector3.ZERO, 0.0, Vector3.UP) as Vector3)
		.is_zero_approx(), "zero radius disables the normal blur")

	# The seeded blur walks only the hit face's rings. At the real radii it must match the full
	# scan, and a radius beyond the ring's proven reach must keep the full-scan average.
	var ring_surface: Variant = SURFACE.new()
	ring_surface.set("_positions", PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.0, 0.0), Vector3(0.10, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.05), Vector3(0.0, 0.0, -0.05),
	]))
	ring_surface.set("_normals", PackedVector3Array([
		Vector3.UP, Vector3(0.7, 0.7, 0.0), Vector3.RIGHT, Vector3.UP, Vector3.UP,
	]))
	ring_surface.set("_rings", [
		[1, 2, 3, 4], [0, 2], [0, 1], [0, 4], [0, 3],
	])
	var full: Vector3 = ring_surface.call("normal_blur", Vector3.ZERO, 0.02, Vector3.UP)
	var seeded: Vector3 = ring_surface.call("normal_blur", Vector3.ZERO, 0.02, Vector3.UP, 0)
	check(seeded.is_equal_approx(full), "the seeded blur matches the full scan at 2 cm")
	var wide_full: Vector3 = ring_surface.call("normal_blur", Vector3.ZERO, 0.08, Vector3.UP)
	var wide_seeded: Vector3 = ring_surface.call("normal_blur", Vector3.ZERO, 0.08, Vector3.UP, 0)
	check(wide_seeded.is_equal_approx(wide_full),
		"a blur beyond the ring reach keeps the full scan")

	# The pose-free engine: the same candidate gives the same frame through different paths, and
	# the intended oval motion is not delayed by contact smoothing.
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
	var context := {
		"oval": Vector2.ZERO, "phase": 0.0, "hover": 0.02, "clearance": 0.02,
		"scale": 1.0, "delta": 0.016,
	}
	var first_frame: Transform3D = engine.call("frame", engine_pony, first_path, "right", context)
	var second_frame: Transform3D = engine.call("frame", engine_pony, second_path, "right", context)
	check(first_frame.is_finite(), "the engine builds a palm frame")
	check(first_frame.is_equal_approx(second_frame),
		"the engine does not depend on which pose path supplied the contact")
	check(near(first_frame.origin.y, -0.32, 0.005),
		"the engine places the palm at the hover above the exact coat")
	check((first_path.calls == 1) and (second_path.calls == 1),
		"each caress hand asks its path once per tick")
	var state := {
		"point": Vector3.INF, "normal": Vector3.UP, "source": "",
		"switches": 0, "miss": 0, "offset": Vector3.ZERO, "offset_valid": false,
		"normal_valid": false,
	}
	var first_smooth: Dictionary = engine.call("_smooth_precise", state,
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.01, 0.0), Vector3.UP, 0.016)
	var second_smooth: Dictionary = engine.call("_smooth_precise", state,
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.02, 0.0), Vector3.UP, 0.016)
	check(near((first_smooth["point"] as Vector3).y, 0.01),
		"the first exact contact starts without smoothing")
	check(near((second_smooth["point"] as Vector3).x, 1.0),
		"contact smoothing never delays the intended caress motion")
	var offset_y := (second_smooth["point"] as Vector3).y
	check(offset_y > 0.01 and offset_y < 0.02,
		"contact smoothing eases the surface snap correction")
	engine.call("reset")
	engine_root.free()

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
	var flank_candidates: Array = flank_path.call("candidates", "right", {
		"lean": 0.0, "size": 1.0, "profile": {"up": 0.16, "back": 0.08, "out": 0.02},
	})
	check(flank_candidates.size() == 1, "the standing path returns one contact")
	if flank_candidates.size() == 1:
		var flank_candidate: Dictionary = flank_candidates[0]
		var flank_point: Vector3 = flank_candidate["point"]
		var flank_normal: Vector3 = flank_candidate["normal"]
		var flank_x: Vector3 = flank_candidate["oval_x"]
		var flank_y: Vector3 = flank_candidate["oval_y"]
		check(flank_point.is_finite() and flank_point.y > 0.15,
			"the standing path lifts the rub above the flank centre")
		check(flank_normal.dot(Vector3.RIGHT) > 0.9, "the standing path faces outward")
		check(absf(flank_x.dot(flank_y)) < 0.001 and absf(flank_x.dot(flank_normal)) < 0.001,
			"the standing oval axes are tangent and orthogonal")
		check(flank_x.length() > 0.99 and flank_y.length() > 0.99,
			"the standing oval axes are normalized")
	var coat_engine: Variant = SYSTEM.new()
	var coat_frame: Transform3D = coat_engine.call("coat_frame", flank_pony, "right",
		Vector3(0.0, 1.0, 0.0), Vector3.UP, Vector3.FORWARD, 0.02, false)
	check(coat_frame.is_finite(), "the shared engine builds a hull palm frame")
	check(near(coat_frame.origin.y, 1.02, 0.001),
		"the hull palm frame sits one clearance above the coat")
	flank_root.free()

	var near_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(0.5, 0.0, 0.0),
		1.0, 0.08, 0.0)
	check(bool(near_plan.get("reachable", false)), "a short target is reachable")
	check(near(float(near_plan.get("stretch", 0.0)), 1.0), "a short target needs no stretch")
	var far_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(1.0, 0.0, 0.0),
		1.0, 0.05, 0.0)
	check(not bool(far_plan.get("reachable", true)), "a far target is clamped")
	check((far_plan.get("target", Vector3.ZERO) as Vector3).length() <= 0.65 + 0.001,
		"the clamped target stays within the arm reach")
	check(near(float(far_plan.get("shoulder_shift", 0.0)), 0.05),
		"the shoulder cap is consumed before the clamp")
	var body_plan: Dictionary = ARM.plan(Vector3.ZERO, 0.3, 0.3, Vector3(1.0, 0.0, 0.0),
		1.0, 0.05, 0.15)
	check(near(float(body_plan.get("body_shift", 0.0)), 0.15),
		"the body cap is used after the shoulder cap")

	print("HANDS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("HANDS_PASS")
	quit(0 if failures == 0 else 1)
