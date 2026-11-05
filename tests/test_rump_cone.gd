extends SceneTree
## The standing offer zone: a 45 degree cone behind her rump within reach.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_rump_cone.gd

const CONE := preload("res://mods/unfplap/rump_cone.gd")

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
	check(CONE.contains(back, rump, Vector3(0.0, 0.0, 0.6)), "directly behind is offered")
	check(not CONE.contains(back, rump, Vector3(0.0, 0.0, -0.6)), "in front is refused")
	check(CONE.contains(back, rump, Vector3(0.25, 0.0, 0.65)), "just inside the cone is offered")
	check(not CONE.contains(back, rump, Vector3(0.32, 0.0, 0.60)), "outside the cone is refused")
	check(CONE.contains(back, rump, Vector3(0.0, 2.0, 0.6)), "eye height does not matter")
	check(not CONE.contains(back, rump, Vector3(0.0, 0.0, 1.0)), "beyond reach is refused")
	check(CONE.contains(Vector3(1.0, 0.0, 0.0), rump, Vector3(0.6, 0.0, 0.0)),
		"uses her own backward axis")
	check(not CONE.contains(Vector3(1.0, 0.0, 0.0), rump, Vector3(-0.6, 0.0, 0.0)),
		"the opposite side of her axis is refused")
	print("RUMP_CONE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUMP_CONE_PASS")
	quit(0 if failures == 0 else 1)
