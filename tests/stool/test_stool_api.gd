extends SceneTree
## The footstool facade's public arithmetic and setting read.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_stool_api.gd

const STOOL := preload("res://mods/unfplap/stool/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

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
	SETTINGS.stool_gap_m.set_num(0.20)
	SETTINGS.stool_height_m.set_num(0.20)
	var system: Node = STOOL.new()
	check(system.enabled() == SETTINGS.standing_stool.get_bool(),
		"the facade reads the feature switch")
	var threshold: float = system.threshold_m()
	check(is_equal_approx(threshold, SETTINGS.stool_gap_m.get_num()),
		"the facade reads the configured threshold")
	check(is_equal_approx(system.height_m(), 0.20), "the facade reads the step height")
	check(system.required(threshold + 0.01), "a gap over the threshold needs a stool")
	check(not system.required(threshold), "a gap at the threshold does not")
	check(system.needed_count(0.25) == 1, "25 cm needs one 20 cm step")
	check(system.needed_count(0.40) == 2, "40 cm needs two 20 cm steps")
	check(is_equal_approx(system.gap(1.1, 0.0, 0.8, 0.0), 0.3),
		"the facade exposes the pure gap")
	check(STOOL.ID == "goods:footstool", "the base-game footstool is the item")
	system.free()

	print("STOOL_API_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
