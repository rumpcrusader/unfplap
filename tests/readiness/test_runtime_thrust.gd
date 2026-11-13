extends SceneTree
## Minimal integration test for ACTIVE readiness and pony-climax separation, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
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
	runtime._readiness.last_touch_at = -1000.0
	runtime._readiness.last_talk_at = -1000.0
	runtime._reset_thrust_state()
	return runtime


func run() -> void:
	var runtime: Node = _runtime()
	runtime._thrust_move(0.10, 0.0)
	runtime._thrust_move(-0.15, 0.1)
	check(str(runtime._readiness.last_intensity).is_empty(), "tiny stroke does not feed the axes")
	runtime._thrust_move(0.5, 0.2)
	runtime._thrust_move(-0.5, 0.45)
	check(not str(runtime._readiness.last_intensity).is_empty(), "real thrust classifies intensity")
	check(near(runtime.satisfaction, 0.7), "a single matching axis adds only the one-axis chunk")

	runtime._readiness.last_intensity = "firm"
	runtime._readiness.last_pattern = "steady"
	runtime._readiness.last_stroke_at = runtime._now_s()
	runtime._readiness.last_thrust_score_at = -1000.0
	runtime._score_thrust()
	check(runtime.satisfaction > 1.0, "matching both axes adds readiness")
	# Heat multiplies the same matching chunk; the debug override bypasses the world day.
	runtime._cycle_override = "heat"
	runtime.satisfaction = 0.0
	runtime._readiness.last_intensity = "firm"
	runtime._readiness.last_pattern = "steady"
	runtime._readiness.last_thrust_score_at = -1000.0
	runtime._readiness.receptive_until = 0.0
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
	runtime._readiness.last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("kiss")
	check(near(runtime.satisfaction, before), "neutral touch does not change readiness")
	runtime._readiness.last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(runtime.satisfaction < before, "disliked touch lowers readiness")

	runtime.satisfaction = 59.0
	runtime._readiness.last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, 60.0), "liked touch clamps at the assist cap")
	before = runtime.satisfaction
	runtime._readiness.last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, before), "caress cannot pass the assist cap")
	check(runtime._readiness.receptive_until > runtime._now_s(), "liked touch opens the receptive window")

	runtime._add_heat(999.0)
	check(near(runtime.satisfaction, 100.0), "readiness clamps at 100")
	runtime._readiness_tick(0.1)
	check(int(runtime.state) == 3, "100 readiness starts a pony climax")
	check(runtime.pony_climaxes == 1, "pony climax count increments")
	var climax_readiness: float = runtime.satisfaction
	runtime._on_stroke({
		"direction": 1, "thrust": true, "travel": 0.5, "duration": 0.5,
		"speed": 1.0, "peak_speed": 1.0, "impact_speed": 1.0, "strength": 0.5,
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
	runtime._readiness.configure_auto(1.5, 0.9, "cosine", 0.0)
	runtime._reset_thrust_state()
	var auto_thrusts := int(runtime._readiness.act_intensity_total)
	runtime.toggle_auto_thrust()
	check(runtime.auto_active(), "X enables auto thrust in ACTIVE")
	for _i: int in 240:
		runtime._clock_s += 1.0 / 60.0
		runtime._auto_tick(1.0 / 60.0)
	check(int(runtime._readiness.act_intensity_total) > auto_thrusts, "auto thrust feeds the same tracker")
	check(not str(runtime._readiness.last_intensity).is_empty(), "auto thrust classifies intensity")
	runtime._stop_auto()
	check(not runtime.auto_active(), "stopping auto clears the mode")
	runtime._reset_thrust_state()
	check(not runtime.auto_active(), "thrust reset clears auto for the next act")
	# The depth scale is physical: his shaft length decides a full stroke, and the back-out
	# standoff sits below zero depth so it can never eat into the stroke.
	check(near(runtime.penetration_reach(), runtime.NOMINAL_SHAFT_M),
		"the nominal shaft sets the depth scale with no part")
	check(near(runtime.penetration_m, -float(runtime.call("_back_out_m"))),
		"the reset rests at the back-out standoff")
	runtime._set_penetration(-1.0, 0.0)
	check(near(runtime.depth, 0.0), "pulling through the standoff leaves depth at zero")
	runtime._set_penetration(0.1, 0.2)
	check(near(runtime.depth, 0.5), "half the reach reads as half depth")
	runtime._set_penetration(1.0, 0.4)
	check(near(runtime.penetration_m, runtime.NOMINAL_SHAFT_M), "full depth stops at the reach")
	# Back-out is signed: a negative value rests the tip inside her and clamps the pull-out there.
	var back_out_before := SETTINGS.back_out_m.get_num()
	SETTINGS.back_out_m.set_num(-0.03)
	check(near(float(runtime.call("_back_out_m")), -0.03),
		"the back-out gap keeps its sign")
	runtime._reset_thrust_state()
	check(near(runtime.penetration_m, 0.03), "a negative back-out rests inside her")
	runtime._set_penetration(-1.0, 0.0)
	check(near(runtime.penetration_m, 0.03),
		"a negative back-out clamps the pull-out inside her")
	SETTINGS.back_out_m.set_num(back_out_before)
	runtime._reset_thrust_state()
	runtime.free()

	print("RUNTIME_THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	quit(0 if failures == 0 else 1)
