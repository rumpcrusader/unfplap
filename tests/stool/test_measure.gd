extends SceneTree
## Pure footstool reach-gap arithmetic.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_measure.gd

const MEASURE := preload("res://mods/unfplap/stool/measure.gd")

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
	check(is_equal_approx(MEASURE.gap(1.2, 0.0, 0.9, 0.0), 0.3),
		"level ground gap is her bits above hooves minus his above feet")
	check(is_equal_approx(MEASURE.gap(1.5, 0.3, 0.9, 0.0), 0.6),
		"a higher floor under her adds to the world gap")
	check(is_equal_approx(MEASURE.gap(0.8, 0.0, 0.9, 0.0), -0.1),
		"a low opening gives a negative gap")
	check(MEASURE.required(0.31, 0.30), "31 cm needs a stool")
	check(not MEASURE.required(0.30, 0.30), "exactly 30 cm does not")
	check(not MEASURE.required(0.29, 0.30), "29 cm does not")
	check(not MEASURE.required(NAN, 0.30), "a missing measurement does not")
	check(not is_finite(MEASURE.gap(NAN, 0.0, 0.9, 0.0)), "a missing opening is not finite")

	print("STOOL_MEASURE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
