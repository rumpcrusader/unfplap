extends SceneTree
## Pure rotation tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_rotation.gd

const ROT := preload("res://mods/unfplap/poses/rotation.gd")
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
	var forward := Vector3(0, 0, -1)
	var up := Vector3.UP
	var side := Vector3.RIGHT
	check(near(ROT.line_roll(forward, up, -side, side), 0.0), "level line is zero")
	var tilted := side + up
	check(near(ROT.line_roll(forward, up, -tilted, tilted), PI * 0.25), "45 degree tilt")
	var flipped := -side + up * 0.01
	var wrapped := ROT.line_roll(forward, up, -flipped, flipped)
	check(absf(wrapped) <= PI * 0.5 + 0.0001, "line roll wrapped to ±90")
	check(not near(wrapped, PI), "wrap does not choose 180 branch")

	var arc := ROT.direction_rotation(forward, Vector3.DOWN, 1.0)
	check(near((arc * forward).normalized().dot(Vector3.DOWN), 1.0), "shortest arc forward to down")
	check(ROT.direction_rotation(forward, forward, 1.0).is_equal_approx(Basis.IDENTITY), "already aligned")

	var pose := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var turned := ROT.rotate_at(pose, Vector3.RIGHT, PI * 0.5, Vector3.ZERO)
	var behind := turned * Vector3(0, 0, 1)
	check(behind.y < -0.99, "positive right-axis rotation moves point behind pivot down")

	var pivot := Vector3(0, 1, 0)
	var lifted := ROT.rotate_at(Transform3D(Basis.IDENTITY, pivot), Vector3.RIGHT, PI * 0.5, pivot)
	check(lifted.origin.is_equal_approx(pivot), "pivot stays fixed")

	print("ROTATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ROTATION_PASS")
	quit(0 if failures == 0 else 1)
