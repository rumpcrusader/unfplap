extends SceneTree
## Pure anatomy geometry: the lip-radius rule, the body-local mapping, the still-zone radius and
## the V2 anal ring weights/centre.
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

	print("ANATOMY_GEOMETRY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
