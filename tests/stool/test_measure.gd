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
	check(MEASURE.required(0.21, 0.20), "21 cm needs a stool")
	check(not MEASURE.required(0.20, 0.20), "exactly 20 cm does not")
	check(not MEASURE.required(0.19, 0.20), "19 cm does not")
	check(not MEASURE.required(NAN, 0.20), "a missing measurement does not")
	check(not is_finite(MEASURE.gap(NAN, 0.0, 0.9, 0.0)), "a missing opening is not finite")
	check(MEASURE.count(0.25, 0.20, 0.20) == 1, "25 cm with 20 cm steps needs one")
	check(MEASURE.count(0.40, 0.20, 0.20) == 2, "40 cm with 20 cm steps needs two")
	check(MEASURE.count(0.60, 0.20, 0.20) == 3, "60 cm with 20 cm steps needs three")
	check(MEASURE.count(0.20, 0.20, 0.20) == 0, "a gap at the threshold needs none")
	check(MEASURE.count(0.40, 0.20, 0.0) == 0, "a zero step is guarded")

	print("STOOL_MEASURE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
