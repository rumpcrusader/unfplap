extends SceneTree
## Caress contact surface, hand shape and reach plan.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_caress.gd

const SURFACE := preload("res://mods/unfplap/caress/caress_surface.gd")
const HAND := preload("res://mods/unfplap/caress/caress_hand.gd")
const ARM := preload("res://mods/unfplap/caress/caress_arm.gd")

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

	var palm := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "palm", 0.0, 0.0)
	var right_basis := HAND.palm_basis("right", Vector3.UP, Vector3.FORWARD, 30.0)
	var left_basis := HAND.palm_basis("left", Vector3.UP, Vector3.FORWARD, -30.0)
	check(right_basis.x.dot(Vector3.UP) > 0.99, "the right palm marker faces the coat")
	check(left_basis.x.dot(Vector3.UP) < -0.99, "the left palm marker faces the coat")
	check(right_basis.determinant() > 0.99 and left_basis.determinant() > 0.99,
		"the rolled palm bases stay orthonormal")
	var resolved: Dictionary = HAND.resolve(surface, palm, "palm", 0.0)
	var frame: Transform3D = resolved.get("frame", palm)
	check(bool(resolved.get("resolved", false)), "the palm resolves outside the plane")
	check(frame.origin.y >= HAND.PALM_RADIUS, "the palm centre is at least one palm radius up")
	var bad := false
	for sample: Dictionary in HAND.samples("palm"):
		var p: Vector3 = frame * (sample["offset"] as Vector3)
		check(p.y >= float(sample["radius"]) - 0.003, "every palm sample clears the plane")
		bad = bad or p.y < 0.0
	check(not bad, "no palm sample is left inside the plane")

	var tip := HAND.place(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "right", "fingertip", 0.0, 0.0)
	var tip_resolved: Dictionary = HAND.resolve(surface, tip, "fingertip", 0.0)
	var tip_frame: Transform3D = tip_resolved.get("frame", tip)
	check(tip_frame.origin.y >= HAND.FINGER_RADIUS,
		"the fingertip mode clears the plane too")

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

	print("CAESS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CAESS_PASS")
	quit(0 if failures == 0 else 1)
