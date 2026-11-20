extends SceneTree
## The standing offer zone: a 90 degree half-angle rear fan behind her rump within 2 m.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_rump_cone.gd

const CONE := preload("res://mods/unfplap/shared/rump_cone.gd")

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
	var back := Vector3(0.0, 0.0, 1.0)
	var rump := Vector3.ZERO
	check(CONE.contains(back, rump, Vector3(0.0, 0.0, 1.9)), "directly behind is offered")
	check(not CONE.contains(back, rump, Vector3(0.0, 0.0, -0.6)), "in front is refused")
	check(CONE.contains(back, rump, Vector3(1.0, 0.0, 0.0)),
		"exactly to her side is offered at the 90 degree boundary")
	check(CONE.contains(back, rump, Vector3(0.75, 0.0, 0.80)),
		"a 45 degree rear diagonal is offered")
	check(CONE.contains(back, rump, Vector3(0.90, 0.0, 0.70)),
		"the old outside diagonal is inside the wider fan")
	check(CONE.contains(back, rump, Vector3(0.0, 2.0, 1.0)), "eye height does not matter")
	check(CONE.contains(back, rump, Vector3(0.0, 0.0, 2.0)),
		"the exact 2 m boundary is inside")
	check(not CONE.contains(back, rump, Vector3(0.0, 0.0, 2.1)), "beyond reach is refused")
	check(CONE.contains(Vector3(1.0, 0.0, 0.0), rump, Vector3(0.9, 0.0, 0.0)),
		"uses her own backward axis")
	check(not CONE.contains(Vector3(1.0, 0.0, 0.0), rump, Vector3(-0.6, 0.0, 0.0)),
		"the opposite side of her axis is refused")

	# The approximate anchor the discovery scan uses, on her own backward axis.
	var actor := Node3D.new()
	root.add_child(actor)
	actor.global_position = Vector3(1.0, 0.5, -2.0)
	actor.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	var expected := actor.global_position + Vector3.UP * CONE.APPROX_HEIGHT \
		+ actor.global_basis.z.normalized() * CONE.APPROX_BACK
	check(CONE.approx_point(actor).is_equal_approx(expected),
		"the approximate rump follows her position and backward axis")
	check(not CONE.approx_point(null).is_finite(), "no body has no approximate rump")
	root.remove_child(actor)
	actor.free()

	print("RUMP_CONE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUMP_CONE_PASS")
	quit(0 if failures == 0 else 1)
