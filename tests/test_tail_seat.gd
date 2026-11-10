extends SceneTree
## Tail seat exception data and target math.
##
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_tail_seat.gd

const PLACEMENT := preload("res://mods/unfplap/tail_seat_placement.gd")

var failures := 0
var checks := 0
const REFERENCE := Vector3(0.0018, 0.5946, 0.2725)


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
	_check_target()
	_check_storage()
	_check_text()
	print("TAIL_SEAT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("TAIL_SEAT_PASS")
	quit(0 if failures == 0 else 1)


func _check_target() -> void:
	var exact := PLACEMENT.target(REFERENCE, Vector2.ZERO)
	check(exact.is_equal_approx(REFERENCE), "no exception uses the exact reference")
	var raised := PLACEMENT.target(REFERENCE, Vector2(0.012, -0.003))
	check(near(raised.x, REFERENCE.x), "the reference carries the lateral position")
	check(near(raised.y, REFERENCE.y + 0.012), "the exception raises Y")
	check(near(raised.z, REFERENCE.z - 0.003), "the exception moves Z")
	var lifted := PLACEMENT.target(REFERENCE, Vector2(0.012, -0.003), 0.020)
	check(near(lifted.y, raised.y + 0.020), "the global tail lift adds to Y")
	var anchor := Vector3(0.0, 0.5, 0.25)
	var delta := PLACEMENT.delta(anchor, REFERENCE, Vector2(0.012, -0.003))
	check(delta.is_equal_approx(raised - anchor), "the translation reaches the target")
	var lifted_delta := PLACEMENT.delta(anchor, REFERENCE, Vector2(0.012, -0.003), 0.020)
	check(lifted_delta.is_equal_approx(lifted - anchor), "the lift reaches the lifted target")


func _check_storage() -> void:
	var row := PLACEMENT.diff(Vector2(0.012, -0.003))
	check(row.size() == 2, "a two-axis exception stores both keys")
	check(near(float(row.get("offset_y", 0.0)), 0.012), "Y is stored")
	check(near(float(row.get("offset_z", 0.0)), -0.003), "Z is stored")
	var read := PLACEMENT.read(row)
	check(near(read.x, 0.012) and near(read.y, -0.003), "a stored row reads back")
	check(PLACEMENT.same(read, Vector2(0.012, -0.003)), "stored values compare equal")
	check(PLACEMENT.diff(Vector2.ZERO).is_empty(), "a zero exception stores nothing")
	check(PLACEMENT.read({}).is_equal_approx(Vector2.ZERO), "a missing row is zero")
	check(PLACEMENT.read({"offset_y": "bad", "offset_z": 0.004}).is_equal_approx(
		Vector2(0.0, 0.004)), "a malformed key is ignored")
	check(PLACEMENT.read({"offset_y": NAN, "offset_z": INF}).is_equal_approx(Vector2.ZERO),
		"a non-finite row is ignored")
	var fallback := PLACEMENT.sanitize(Vector2(NAN, INF), Vector2(0.02, 0.03))
	check(near(fallback.x, 0.02) and near(fallback.y, 0.03),
		"a non-finite pair falls back per component")
	var from_row := PLACEMENT.sanitize({"offset_y": 0.004, "offset_z": -0.002})
	check(near(from_row.x, 0.004) and near(from_row.y, -0.002), "sanitize accepts a row")
	check(near(PLACEMENT.dock({"dock_y": 0.012}), 0.012), "the dock distance reads back")
	check(near(PLACEMENT.dock({}), 0.0), "a missing dock distance is zero")
	check(near(PLACEMENT.dock({"dock_y": NAN}), 0.0), "a non-finite dock distance is zero")
	check(PLACEMENT.dock_diff(0.0).is_empty(), "a zero dock distance stores nothing")
	check(near(float(PLACEMENT.dock_diff(0.012).get("dock_y", 0.0)), 0.012),
		"a dock distance stores dock_y")
	check(near(PLACEMENT.dock_scale({}), 1.0), "a missing dock scale is authored 1.0")
	check(near(PLACEMENT.dock_scale({"dock_scale": 1.06}), 1.06), "the dock scale reads back")
	check(near(PLACEMENT.dock_scale({"dock_scale": 0.0}), PLACEMENT.DOCK_SCALE_MIN),
		"a zero dock scale takes the floor")
	check(PLACEMENT.dock_scale_diff(1.0).is_empty(), "an authored dock scale stores nothing")
	check(near(float(PLACEMENT.dock_scale_diff(1.06).get("dock_scale", 0.0)), 1.06),
		"a changed dock scale stores dock_scale")


func _check_text() -> void:
	check(PLACEMENT.text(Vector2.ZERO) == "y=+0mm z=+0mm", "zero text")
	check(PLACEMENT.text(Vector2(0.012, -0.003)) == "y=+12mm z=-3mm", "exception text")
	check(PLACEMENT.dock_text(0.012) == "dock=+12mm", "dock distance text")
	check(PLACEMENT.scale_text(1.06) == "scale=1.06x", "dock scale text")
