extends "res://mods/unfplap/tests/support/suite.gd"
## Pure anatomy geometry: the lip-radius rule, the body-local mapping,
## the V2 anal ring weights/centre, the coat line targets/bend/frames and the shader sample sync.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_geometry.gd

const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const COAT_LINE := preload("res://mods/unfplap/anatomy/coat_line.gd")


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

	# The line targets span the mesh's local Y range at x = 0.
	var targets := GEOMETRY.coat_line_targets(-0.04, 0.06, 3)
	check(targets.size() == 3, "the line has one target per sample")
	check(targets[0].is_equal_approx(Vector3(0.0, -0.04, 0.0)),
		"the first target is the mesh's bottom")
	check(targets[2].is_equal_approx(Vector3(0.0, 0.06, 0.0)),
		"the last target is the mesh's top")
	check(targets[1].is_equal_approx(Vector3(0.0, 0.01, 0.0)),
		"the middle target is evenly spaced")

	# The live line is the rest line shifted by the bend, anchored at the top.
	var bent_line := PackedVector3Array()
	GEOMETRY.coat_line_bend(targets, Vector3(0.01, 0.0, 0.0), bent_line)
	check(bent_line.size() == targets.size(), "the bend keeps one point per sample")
	check(bent_line[2].is_equal_approx(targets[2]), "the top sample stays anchored")
	check(bent_line[0].is_equal_approx(targets[0] + Vector3(0.01, 0.0, 0.0)),
		"the bottom sample follows the bend")
	check(bent_line[1].is_equal_approx(targets[1] + Vector3(0.005, 0.0, 0.0)),
		"the middle sample follows half the bend")
	GEOMETRY.coat_line_bend(targets, Vector3.ZERO, bent_line)
	check(bent_line == targets, "a zero bend keeps the rest line")

	# The line frames: identity at rest, bend with the tangent and stretch along it.
	var rest := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.1, 0.0),
		Vector3(0.0, 0.2, 0.0)])
	var basis_x := PackedVector3Array()
	var basis_y := PackedVector3Array()
	var basis_z := PackedVector3Array()
	var origin := PackedVector3Array()
	basis_x.resize(3)
	basis_y.resize(3)
	basis_z.resize(3)
	origin.resize(3)
	GEOMETRY.fill_line_frames(rest, rest, basis_x, basis_y, basis_z, origin)
	check(basis_x[1].is_equal_approx(Vector3.RIGHT), "a matching line keeps its X column")
	check(basis_y[1].is_equal_approx(Vector3.UP), "a matching line keeps its Y column")
	check(basis_z[1].is_equal_approx(Vector3.BACK), "a matching line keeps its Z column")
	check(origin[1].is_equal_approx(Vector3.ZERO), "a matching line has no offset")
	check(GEOMETRY.line_point_at(Vector3(0.01, 0.05, 0.0), rest, basis_x, basis_y,
		basis_z, origin).is_equal_approx(Vector3(0.01, 0.05, 0.0)),
		"an identity line keeps the point")

	var bent := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.1, 0.0),
		Vector3(0.1, 0.2, 0.0)])
	GEOMETRY.fill_line_frames(rest, bent, basis_x, basis_y, basis_z, origin)
	var rotated := GEOMETRY.line_point_at(Vector3(0.01, 0.1, 0.0), rest, basis_x,
		basis_y, basis_z, origin)
	check(rotated.x > 0.005 and rotated.y < 0.1,
		"a bent line rotates a perpendicular offset at the bend")

	var stretched_line := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.2, 0.0),
		Vector3(0.0, 0.4, 0.0)])
	GEOMETRY.fill_line_frames(rest, stretched_line, basis_x, basis_y, basis_z, origin)
	check(near(GEOMETRY.line_point_at(Vector3(0.0, 0.1, 0.0), rest, basis_x, basis_y,
		basis_z, origin).y, 0.2), "a stretched line scales the along-line component")
	check(near(GEOMETRY.line_point_at(Vector3(0.0, -1.0, 0.0), rest, basis_x, basis_y,
		basis_z, origin).y, -2.0), "a Y below the line clamps to the first frame")
	check(near(GEOMETRY.line_point_at(Vector3(0.0, 1.0, 0.0), rest, basis_x, basis_y,
		basis_z, origin).y, 2.0), "a Y above the line clamps to the last frame")

	# Unused shader slots copy the last frame.
	basis_x.resize(5)
	basis_y.resize(5)
	basis_z.resize(5)
	origin.resize(5)
	GEOMETRY.fill_line_frames(rest, bent, basis_x, basis_y, basis_z, origin)
	check(basis_x[3] == basis_x[2] and basis_x[4] == basis_x[2],
		"padded X slots copy the last frame")
	check(origin[3] == origin[2] and origin[4] == origin[2],
		"padded offsets copy the last frame")

	# The opening CPU twin mixes the two neighbouring frames.
	basis_x.resize(3)
	basis_y.resize(3)
	basis_z.resize(3)
	origin.resize(3)
	GEOMETRY.fill_line_frames(rest, bent, basis_x, basis_y, basis_z, origin)
	var f := 0.5
	var mix_x := basis_x[0].lerp(basis_x[1], f)
	var mix_y := basis_y[0].lerp(basis_y[1], f)
	var mix_z := basis_z[0].lerp(basis_z[1], f)
	var mix_origin := origin[0].lerp(origin[1], f)
	var local := Vector3(0.01, 0.05, 0.0)
	var expected_point := mix_x * local.x + mix_y * local.y + mix_z * local.z + mix_origin
	check(GEOMETRY.line_point_at(local, rest, basis_x, basis_y, basis_z, origin)
		.is_equal_approx(expected_point), "the opening point mixes its two frames")
	var direction_local := Vector3(0.0, 0.05, 1.0)
	var direction := mix_x * direction_local.x + mix_y * direction_local.y \
		+ mix_z * direction_local.z
	check(GEOMETRY.line_direction_at(direction_local, rest, basis_x, basis_y, basis_z,
		origin).is_equal_approx(direction.normalized()),
		"the opening normal mixes its two frames")

	# The shader's sample count must match the module.
	var shader := FileAccess.get_file_as_string("res://mods/unfplap/anatomy/anatomy.gdshader")
	check(shader.contains("const int LINE_N = %d;" % COAT_LINE.LINE_SAMPLES),
		"the shader declares the coat line sample count")

	finish()
