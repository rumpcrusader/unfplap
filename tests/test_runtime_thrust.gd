extends SceneTree
## Minimal integration test for ACTIVE readiness and pony-climax separation, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
const PREF := preload("res://mods/unfplap/preferences.gd")
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


func _runtime() -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime._preferences = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
		"warmth": "normal",
	})
	runtime._thrust_tracker = THRUST.new()
	runtime.state = 2 # ACTIVE
	runtime._last_touch_at = -1000.0
	runtime._last_talk_at = -1000.0
	return runtime


func run() -> void:
	var runtime: Node = _runtime()
	runtime._thrust_move(0.10, 0.0)
	runtime._thrust_move(-0.15, 0.1)
	check(str(runtime._last_intensity).is_empty(), "tiny stroke does not feed the axes")
	runtime._thrust_move(1.0, 0.2)
	runtime._thrust_move(-1.0, 0.45)
	check(not str(runtime._last_intensity).is_empty(), "real thrust classifies intensity")
	check(near(runtime.satisfaction, 0.7), "a single matching axis adds only the one-axis chunk")

	runtime._last_intensity = "firm"
	runtime._last_pattern = "steady"
	runtime._last_stroke_at = runtime._now_s()
	runtime._last_thrust_score_at = -1000.0
	runtime._score_thrust()
	check(runtime.satisfaction > 1.0, "matching both axes adds readiness")
	# Heat multiplies the same matching chunk; the debug override bypasses the world day.
	runtime._cycle_override = "heat"
	runtime.satisfaction = 0.0
	runtime._last_intensity = "firm"
	runtime._last_pattern = "steady"
	runtime._last_thrust_score_at = -1000.0
	runtime._receptive_until = 0.0
	runtime._score_thrust()
	check(near(runtime.satisfaction, 1.4 * 1.6), "heat multiplies the thrust chunk")
	check(runtime.hud_readiness_line(true).contains("In heat"), "heat shows on the readiness line")
	check(runtime.hud_readiness_line(false).is_empty(), "readouts off hide the heat line")
	runtime._cycle_override = ""
	var before: float = runtime.satisfaction
	runtime._readiness_tick(10.0)
	check(near(runtime.satisfaction, before), "readiness does not decay on its own")

	before = runtime.satisfaction
	runtime._on_touch("caress")
	check(runtime.satisfaction > before, "liked touch adds readiness")
	before = runtime.satisfaction
	runtime._on_talk("you are beautiful")
	check(runtime.satisfaction > before, "liked talk adds readiness")
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(near(runtime.satisfaction, before), "shared touch cooldown blocks a second chunk")
	runtime._last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("kiss")
	check(near(runtime.satisfaction, before), "neutral touch does not change readiness")
	runtime._last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(runtime.satisfaction < before, "disliked touch lowers readiness")

	runtime.satisfaction = 59.0
	runtime._last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, 60.0), "liked touch clamps at the assist cap")
	before = runtime.satisfaction
	runtime._last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, before), "caress cannot pass the assist cap")
	check(runtime._receptive_until > runtime._now_s(), "liked touch opens the receptive window")

	runtime._add_heat(999.0)
	check(near(runtime.satisfaction, 100.0), "readiness clamps at 100")
	runtime._readiness_tick(0.1)
	check(int(runtime.state) == 3, "100 readiness starts a pony climax")
	check(runtime.pony_climaxes == 1, "pony climax count increments")
	var climax_readiness: float = runtime.satisfaction
	runtime._on_stroke({
		"direction": 1, "thrust": true, "travel": 0.5, "duration": 0.5,
		"speed": 1.0, "peak_speed": 1.0, "strength": 0.5,
	})
	check(near(runtime.satisfaction, climax_readiness), "thrusting during climax does not score")
	check(int(runtime.state) == 3, "thrusting during climax does not end it")

	runtime._finish_climax()
	check(int(runtime.state) == 2, "first climax returns to ACTIVE")
	check(near(runtime.satisfaction, 0.0), "a climax resets readiness to zero")
	check(runtime.pony_climaxes == 1, "climax count survives the return to ACTIVE")

	runtime.pony_climaxes = 2
	runtime.satisfaction = 100.0
	runtime._climax()
	runtime._finish_climax()
	check(int(runtime.state) == 4, "third climax auto-enters AFTERGLOW")

	runtime._max_pony_climaxes = 0
	runtime.state = 2
	runtime.pony_climaxes = 5
	check(runtime.hud_cue_line(true).begins_with("❤ 5/∞"),
		"unlimited climax limit uses the infinity display")
	runtime._finish_climax()
	check(int(runtime.state) == 2, "zero climax limit keeps the act going")
	runtime._max_pony_climaxes = 2
	runtime.state = 2
	runtime.pony_climaxes = 2
	check(runtime.hud_cue_line(true).begins_with("❤ 2/2"),
		"configured climax limit shows the denominator")
	runtime._finish_climax()
	check(int(runtime.state) == 4, "configured climax limit enters AFTERGLOW")
	runtime._max_pony_climaxes = 3

	# Auto thrust feeds the same tracker and scores through it.
	runtime.state = 2
	runtime._auto_default_pace = 1.5
	runtime._auto_default_depth = 0.9
	runtime._reset_thrust_state()
	var auto_thrusts := int(runtime._act_intensity_total)
	runtime.toggle_auto_thrust()
	check(runtime.auto_active(), "X enables auto thrust in ACTIVE")
	for _i: int in 240:
		runtime._clock_s += 1.0 / 60.0
		runtime._auto_thrust_tick(1.0 / 60.0)
	check(int(runtime._act_intensity_total) > auto_thrusts, "auto thrust feeds the same tracker")
	check(not str(runtime._last_intensity).is_empty(), "auto thrust classifies intensity")
	runtime._stop_auto_thrust()
	check(not runtime.auto_active(), "stopping auto clears the mode")
	runtime._reset_thrust_state()
	check(not runtime.auto_active(), "thrust reset clears auto for the next act")
	runtime.free()

	print("RUNTIME_THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	quit(0 if failures == 0 else 1)
