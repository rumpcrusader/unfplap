extends SceneTree
## Dock attach skin: the rebuilt dock must be a two-bind skin on the hair tail. The bind math must
## reproduce the body-space cuff at the build pose, the base ring must stay on `mPelvis`, and the
## outer end must follow `mTail1`.
##
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_dock_attach.gd

const DOCK_ATTACH := preload("res://mods/unfplap/anatomy/tail/dock_attach.gd")
const DOCK_SEAT := preload("res://mods/unfplap/anatomy/tail/dock_seat.gd")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const APPROVED_FIT := "res://world/characters/hybrid_mare/dock_fit.json"

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
	var body := Skeleton3D.new()
	body.name = "TestBodySkeleton"
	var hair := Skeleton3D.new()
	hair.name = "TestHairSkeleton"
	get_root().add_child(body)
	get_root().add_child(hair)
	var pelvis := hair.add_bone("mPelvis")
	var tail := hair.add_bone("mTail1")
	hair.set_bone_parent(tail, pelvis)
	hair.set_bone_rest(pelvis, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.60, 0.25)))
	hair.set_bone_rest(tail, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.08, 0.0)))
	hair.reset_bone_poses()
	# The hair rig is scaled and offset from the body; the bind has to carry that.
	hair.transform = Transform3D(Basis.from_scale(Vector3(1.2, 1.2, 1.2)),
		Vector3(0.05, 0.10, 0.02))

	var fit: Dictionary = HYBRID_DOCK.read_fit(APPROVED_FIT)
	var fitted: ArrayMesh = HYBRID_DOCK.fitted_mesh(fit, false)
	var reached: ArrayMesh = HYBRID_DOCK._stretched(fitted, "mare")
	var mesh: ArrayMesh = DOCK_SEAT.snap_base(reached, "mare")
	check(mesh != null, "the test dock is built")
	if mesh == null:
		_finish()
		return
	var lift := 0.012
	var parts := DOCK_ATTACH.build(mesh, body, hair, lift)
	check(not parts.is_empty(), "the dock builds a skinned mesh")
	if parts.is_empty():
		_finish()
		return

	var skinned: ArrayMesh = parts.get("mesh")
	var skin: Skin = parts.get("skin")
	var placement: Transform3D = parts.get("transform")
	check(skinned != null and skinned.get_surface_count() == 1, "one skinned surface")
	check(skin != null and skin.get_bind_count() == 2, "two binds: pelvis and tail")
	if skinned == null or skin == null:
		_finish()
		return

	var arrays: Array = skinned.surface_get_arrays(0)
	var source: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	check(vertices.size() == source_vertices.size(), "keeps every vertex")
	check(bones.size() == vertices.size() * 4, "four bone slots per vertex")
	check(weights.size() == bones.size(), "a weight for every bone slot")
	var ring: PackedInt32Array = skinned.get_meta("base_indices", PackedInt32Array())
	check(ring == mesh.get_meta("base_indices", PackedInt32Array()),
		"keeps the base-ring metadata")
	var sums_ok := true
	var binds_ok := true
	for index in vertices.size():
		if absf(weights[index * 4] + weights[index * 4 + 1] - 1.0) > 0.0001:
			sums_ok = false
		if bones[index * 4] != 0 or bones[index * 4 + 1] != 1:
			binds_ok = false
	check(sums_ok, "every vertex weight sums to one")
	check(binds_ok, "every vertex uses bind 0 and bind 1")
	var ring_zero := true
	for index: int in ring:
		if index >= 0 and index < vertices.size() and weights[index * 4 + 1] != 0.0:
			ring_zero = false
	check(ring_zero, "the base ring is pelvis-only")

	var area := skinned.get_aabb()
	check(area.size.is_finite() and area.size.length() > 0.001, "the skinned mesh keeps a real AABB")

	# At the build pose the two-bone skin must land exactly on the body-space cuff, lift included.
	var base_index: int = ring[0] if not ring.is_empty() else 0
	var tip_index := _tip_index(vertices, ring)
	var mid_index := _mid_index(weights)
	for entry: Array in [[base_index, "base"], [mid_index, "mid"], [tip_index, "tip"]]:
		var index: int = int(entry[0])
		var world := _skinned_world(index, vertices, weights, skin, hair, pelvis, tail, placement)
		var expected: Vector3 = body.global_transform \
			* (vertices[index] + Vector3(0.0, lift, 0.0))
		check(world.distance_to(expected) < 0.001,
			"%s vertex matches the body-space cuff" % str(entry[1]))

	var base_before := _skinned_world(base_index, vertices, weights, skin, hair, pelvis, tail,
		placement)
	var tip_before := _skinned_world(tip_index, vertices, weights, skin, hair, pelvis, tail,
		placement)
	hair.set_bone_pose_rotation(tail, Quaternion(Vector3.BACK, deg_to_rad(25.0)))
	hair.force_update_all_bone_transforms()
	var base_after := _skinned_world(base_index, vertices, weights, skin, hair, pelvis, tail,
		placement)
	var tip_after := _skinned_world(tip_index, vertices, weights, skin, hair, pelvis, tail,
		placement)
	check(base_before.distance_to(base_after) < 0.0005, "the base ring stays on the pelvis")
	check(tip_before.distance_to(tip_after) > 0.002, "the outer end follows the tail joint")

	_finish()


func _skinned_world(index: int, vertices: PackedVector3Array, weights: PackedFloat32Array,
		skin: Skin, hair: Skeleton3D, pelvis: int, tail: int, placement: Transform3D) -> Vector3:
	var weight := weights[index * 4 + 1]
	var on_pelvis: Vector3 = hair.get_bone_global_pose(pelvis) * skin.get_bind_pose(0) \
		* vertices[index]
	var on_tail: Vector3 = hair.get_bone_global_pose(tail) * skin.get_bind_pose(1) \
		* vertices[index]
	return (hair.global_transform * placement) * on_pelvis.lerp(on_tail, weight)


func _tip_index(vertices: PackedVector3Array, ring: PackedInt32Array) -> int:
	var base := Vector3.ZERO
	for index: int in ring:
		if index >= 0 and index < vertices.size():
			base += vertices[index]
	base /= float(maxi(1, ring.size()))
	var best := 0
	var far := -1.0
	for index in vertices.size():
		var distance := vertices[index].distance_squared_to(base)
		if distance > far:
			far = distance
			best = index
	return best


func _mid_index(weights: PackedFloat32Array) -> int:
	var count := int(weights.size() / 4)
	var best := 0
	var closest := INF
	for index in count:
		var distance := absf(weights[index * 4 + 1] - 0.5)
		if distance < closest:
			closest = distance
			best = index
	return best


func _finish() -> void:
	print("DOCK_ATTACH_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("DOCK_ATTACH_PASS")
	quit(0 if failures == 0 else 1)
