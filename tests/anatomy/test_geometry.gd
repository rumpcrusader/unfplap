extends SceneTree
## Pure anatomy geometry: the lip-radius rule, the body-local mapping, the still-zone radius,
## the V2 anal ring weights/centre, the coat weight grid/sampler and the coat-follow matrices.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_geometry.gd

const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	# The density walk can collapse or overshoot; keep the authored band.
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.004),
		GEOMETRY.WINKING_LIP_RADIUS), "a collapsed lip radius falls back to the authored band")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(GEOMETRY.WINKING_LIP_RADIUS),
		GEOMETRY.WINKING_LIP_RADIUS), "the authored lip radius is kept")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.030), 0.030),
		"a nearby measured lip radius is kept")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(NAN),
		GEOMETRY.WINKING_LIP_RADIUS), "a non-finite measurement falls back")

	# The hip bind maps an anatomy-local point into the coat's body-local space.
	var bind := Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var mesh_xf := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	check(GEOMETRY.body_local_point(bind, mesh_xf, Vector3.ZERO) == Vector3(-1.0, -2.0, -3.0),
		"body_local_point removes the hip bind origin")
	check(GEOMETRY.body_local_point(bind, mesh_xf, Vector3(2.0, 0.0, 0.0))
		== Vector3(1.0, -2.0, -3.0), "body_local_point carries the mesh transform")
	check(GEOMETRY.body_local_direction(bind, mesh_xf, Vector3(1.0, 0.0, 0.0))
		== Vector3.RIGHT, "body_local_direction keeps an unrotated basis")

	# The still-zone radius follows the lip band with a floor.
	var radius := GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 1.0)
	var expected := maxf(0.022 * 2.2 * 0.742 * 1.3, 0.045)
	check(near(radius, expected), "the anal still radius follows the lip band")
	check(near(GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 0.0), 0.0),
		"a zero multiplier turns the anal still zone off")

	# The V2 anal keys start where the previous one ends.
	var base := GEOMETRY.anal_ring_weights(0.0, 1.0)
	check(near(float(base["open"]), 0.0) and near(float(base["stretch"]), 0.0)
		and near(float(base["over"]), 0.0) and near(float(base["extreme"]), 0.0),
		"the closed ring has no open keys")
	var opened := GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_OPEN_R, 1.0)
	check(near(float(opened["open"]), 1.0) and near(float(opened["stretch"]), 0.0),
		"the open key finishes at ANAL_OPEN_R")
	var stretched := GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_STRETCH_R, 1.0)
	check(near(float(stretched["stretch"]), 1.0) and near(float(stretched["over"]), 0.0),
		"the stretch key finishes at ANAL_STRETCH_R")
	var over := GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_OVER_R, 1.0)
	check(near(float(over["over"]), 1.0) and near(float(over["extreme"]), 0.0),
		"the overstretch key finishes at ANAL_OVER_R")
	var extreme := GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_EXTREME_R, 1.0)
	check(near(float(extreme["extreme"]), 1.0), "the extreme key reaches 1 at ANAL_EXTREME_R")
	var oversized := GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_EXTREME_R * 1.5, 1.0)
	check(float(oversized["extreme"]) > 1.0, "an oversized shaft extrapolates the extreme key")

	# The ponut key is a ponut-only scale that fades under the extreme key.
	var small := GEOMETRY.anal_ring_weights(0.0, 0.9)
	check(near(float(small["ponut"]), -0.1), "anal_scale below 1 shrinks the ponut")
	check(near(float(GEOMETRY.anal_ring_weights(0.0, 1.1)["ponut"]), 0.1),
		"anal_scale above 1 grows the ponut")
	check(near(float(GEOMETRY.anal_ring_weights(GEOMETRY.ANAL_EXTREME_R, 0.9)["ponut"]), 0.0),
		"the extreme key fades the ponut key out")

	# The ring centre moves from the base ring to the extreme ring.
	check(GEOMETRY.anal_ring_centre(base).distance_to(GEOMETRY.V2_ANAL_RING_BASE) < 0.0001,
		"the closed ring is the base ring")
	check(GEOMETRY.anal_ring_centre(extreme).distance_to(GEOMETRY.V2_ANAL_RING_EXTREME) < 0.0001,
		"the extreme ring is the measured extreme point")

	# The coat follow samples the body's own skin weights. The grid buckets the body rest
	# vertices, and the sampler averages the nearest three by inverse distance.
	var body_vertices := PackedVector3Array([Vector3.ZERO, Vector3(0.01, 0.0, 0.0)])
	var grid := GEOMETRY.body_weight_grid(body_vertices, 0.02)
	check(grid.has(Vector3i.ZERO), "the weight grid buckets a body vertex")
	check(not grid.is_empty(), "the weight grid has a cell")
	var names := PackedStringArray()
	for bone: String in GEOMETRY.COAT_FOLLOW_BONES:
		names.append(bone)
	check(names.size() == 4, "the four leg bones are the coat-follow order")
	var bones := PackedInt32Array([0, 1, 2, 3, 0, 1, 2, 3])
	var weights := PackedFloat32Array([0.5, 0.0, 0.0, 0.0, 0.0, 0.25, 0.0, 0.0])
	var sampled := GEOMETRY.sample_coat_weights(
		PackedVector3Array([Vector3(0.005, 0.0, 0.0)]), Transform3D.IDENTITY,
		body_vertices, bones, weights, names, grid, 0.02)
	check(sampled.size() == 4, "one anatomy vertex gets four coat weights")
	if sampled.size() == 4:
		check(abs(sampled[0] - 64) <= 1, "the sampler averages flank L by inverse distance")
		check(abs(sampled[1] - 32) <= 1, "the sampler averages flank R by inverse distance")
		check(sampled[2] == 0 and sampled[3] == 0, "unused leg weights stay zero")
	var empty := GEOMETRY.sample_coat_weights(
		PackedVector3Array([Vector3(2.0, 2.0, 2.0)]), Transform3D.IDENTITY,
		body_vertices, bones, weights, names, grid, 0.02)
	check(empty == PackedByteArray([0, 0, 0, 0]), "a vertex outside the grid falls back to hips")

	# The anatomy mesh gets a custom0 RGBA8 channel without touching its positions or shapes.
	var source := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var packed := PackedByteArray([255, 0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0])
	var weighted := GEOMETRY.mesh_with_coat_weights(source, packed)
	check(weighted != null, "the anatomy mesh rebuild keeps one surface")
	if weighted != null:
		var format := weighted.surface_get_format(0)
		check((format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0,
			"the anatomy mesh carries its weight channel")
		check(((format >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			& Mesh.ARRAY_FORMAT_CUSTOM_BITS) == Mesh.ARRAY_CUSTOM_RGBA8_UNORM,
			"the weight channel is RGBA8")
		var stored: Variant = weighted.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
		check(stored is PackedByteArray and (stored as PackedByteArray) == packed,
			"the sampled weights survive the rebuild")
		check(weighted.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			== source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
			"the weighted mesh keeps its rest vertices")

	# The follow matrices are pelvis-relative and identity at rest.
	var rest := Transform3D.IDENTITY
	var quarter := Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO)
	var turned := GEOMETRY.coat_follow_matrices(rest, rest, [quarter], [rest], rest)
	check(turned.size() == 1, "one leg produces one follow matrix")
	check((turned[0] * Vector3.RIGHT).is_equal_approx(Vector3.UP),
		"the follow matrix applies the leg rotation")
	var same := GEOMETRY.coat_follow_matrices(
		Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.1, 0.2, 0.3)), rest,
		[Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.1, 0.2, 0.3))], [rest], rest)
	check(same[0].is_equal_approx(Transform3D.IDENTITY),
		"a leg that moves with the pelvis has no relative motion")
	var placed := GEOMETRY.coat_follow_matrices(rest, rest, [quarter], [rest],
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)))
	check((placed[0] * Vector3.ZERO).is_equal_approx(Vector3(-1.0, 1.0, 0.0)),
		"the follow matrix is placed in anatomy-local space")

	print("ANATOMY_GEOMETRY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
