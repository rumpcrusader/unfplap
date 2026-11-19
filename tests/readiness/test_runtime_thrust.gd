extends SceneTree
## Minimal integration test for ACTIVE readiness and pony-climax separation, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")
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


func _view(runtime: Node) -> RefCounted:
	runtime.act.refresh_view()
	runtime.act.sync_hud()
	return runtime.act.facts()


func _runtime() -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.act.preferences = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
		"warmth": "normal",
	})
	runtime.act.snapshot_settings()
	runtime.act._set_state(2) # ACTIVE
	runtime._bundle.readiness.last_touch_at = -1000.0
	runtime._bundle.readiness.last_talk_at = -1000.0
	runtime.act.reset_thrust_state()
	return runtime


func run() -> void:
	var runtime: Node = _runtime()
	# A dangling clock binding returns 0.0 forever and freezes the timers; the three consumers
	# must read the session's clock and advance with it.
	runtime.act.tick_clock(0.25)
	check(runtime._bundle.readiness.clock.is_valid(), "readiness binds the session clock")
	check(near(runtime._bundle.readiness._now(), 0.25), "readiness clock advances with the session")
	check(runtime._bundle.face.clock.is_valid(), "face binds the session clock")
	check(near(runtime._bundle.face._now(), 0.25), "face clock advances with the session")
	check(runtime._bundle.facts.now.is_valid(), "act facts bind the session clock")
	check(near(float(runtime._bundle.facts.now.call()), 0.25), "act facts clock advances with the session")
	runtime._bundle.impact.move(0.10, 0.0)
	runtime._bundle.impact.move(-0.15, 0.1)
	check(str(runtime._bundle.readiness.last_intensity).is_empty(), "tiny stroke does not feed the axes")
	runtime._bundle.impact.move(0.5, 0.2)
	runtime._bundle.impact.move(-0.5, 0.45)
	check(not str(runtime._bundle.readiness.last_intensity).is_empty(), "real thrust classifies intensity")
	check(near(runtime._bundle.readiness.satisfaction, 0.7), "a single matching axis adds only the one-axis chunk")

	runtime._bundle.readiness.last_intensity = "firm"
	runtime._bundle.readiness.last_pattern = "steady"
	runtime._bundle.readiness.last_stroke_at = runtime.act.clock_s()
	runtime._bundle.readiness.last_thrust_score_at = -1000.0
	runtime._bundle.readiness.score_thrust()
	check(runtime._bundle.readiness.satisfaction > 1.0, "matching both axes adds readiness")
	# Heat multiplies the same matching chunk; the debug override bypasses the world day.
	CYCLE.set_override(runtime.live_id(), "heat")
	runtime._bundle.readiness.satisfaction = 0.0
	runtime._bundle.readiness.last_intensity = "firm"
	runtime._bundle.readiness.last_pattern = "steady"
	runtime._bundle.readiness.last_thrust_score_at = -1000.0
	runtime._bundle.readiness.receptive_until = 0.0
	runtime._bundle.readiness.score_thrust()
	check(near(runtime._bundle.readiness.satisfaction, 1.4 * 1.6), "heat multiplies the thrust chunk")
	runtime.act.cycle_heat = true
	check(HUD_LINES.readiness_line_for(_view(runtime), true).contains("In heat"),
		"heat shows on the readiness line")
	check(HUD_LINES.readiness_line_for(_view(runtime), false).is_empty(),
		"readouts off hide the heat line")
	runtime.act.cycle_heat = false
	CYCLE.set_override(runtime.live_id(), "")
	var before: float = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.tick(10.0)
	check(near(runtime._bundle.readiness.satisfaction, before), "readiness does not decay on its own")

	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.touch("caress")
	check(runtime._bundle.readiness.satisfaction > before, "liked touch adds readiness")
	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.talk("you are beautiful")
	check(runtime._bundle.readiness.satisfaction > before, "liked talk adds readiness")
	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.touch("smack")
	check(near(runtime._bundle.readiness.satisfaction, before), "shared touch cooldown blocks a second chunk")
	runtime._bundle.readiness.last_touch_at = -1000.0
	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.touch("kiss")
	check(near(runtime._bundle.readiness.satisfaction, before), "neutral touch does not change readiness")
	runtime._bundle.readiness.last_touch_at = -1000.0
	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.touch("smack")
	check(runtime._bundle.readiness.satisfaction < before, "disliked touch lowers readiness")

	runtime._bundle.readiness.satisfaction = 59.0
	runtime._bundle.readiness.last_touch_at = -1000.0
	runtime._bundle.readiness.touch("caress")
	check(near(runtime._bundle.readiness.satisfaction, 60.0), "liked touch clamps at the assist cap")
	before = runtime._bundle.readiness.satisfaction
	runtime._bundle.readiness.last_touch_at = -1000.0
	runtime._bundle.readiness.touch("caress")
	check(near(runtime._bundle.readiness.satisfaction, before), "caress cannot pass the assist cap")
	check(runtime._bundle.readiness.receptive_until > runtime.act.clock_s(), "liked touch opens the receptive window")

	runtime._bundle.readiness.add_heat(999.0)
	check(near(runtime._bundle.readiness.satisfaction, 100.0), "readiness clamps at 100")
	runtime._bundle.readiness.tick(0.1)
	check(int(runtime.act.state) == 3, "100 readiness starts a pony climax")
	check(runtime._bundle.readiness.pony_climaxes == 1, "pony climax count increments")
	var climax_readiness: float = runtime._bundle.readiness.satisfaction
	var stroke := THRUST_STATE.StrokeEvent.new()
	stroke.kind = "stroke"
	stroke.direction = 1
	stroke.thrust = true
	stroke.travel = 0.5
	stroke.duration = 0.5
	stroke.speed = 1.0
	stroke.peak_speed = 1.0
	stroke.strength = 0.5
	runtime._bundle.readiness.stroke(stroke)
	check(near(runtime._bundle.readiness.satisfaction, climax_readiness), "thrusting during climax does not score")
	check(int(runtime.act.state) == 3, "thrusting during climax does not end it")

	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "first climax returns to ACTIVE")
	check(near(runtime._bundle.readiness.satisfaction, 0.0), "a climax resets readiness to zero")
	check(runtime._bundle.readiness.pony_climaxes == 1, "climax count survives the return to ACTIVE")

	runtime._bundle.readiness.pony_climaxes = 2
	runtime._bundle.readiness.satisfaction = 100.0
	runtime.act.climax()
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "third climax auto-enters AFTERGLOW")

	runtime.act.max_pony_climaxes = 0
	runtime.act._set_state(2)
	runtime._bundle.readiness.pony_climaxes = 5
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 5/∞"),
		"unlimited climax limit uses the infinity display")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "zero climax limit keeps the act going")
	runtime.act.max_pony_climaxes = 2
	runtime.act._set_state(2)
	runtime._bundle.readiness.pony_climaxes = 2
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 2/2"),
		"configured climax limit shows the denominator")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "configured climax limit enters AFTERGLOW")
	runtime.act.max_pony_climaxes = 3

	# Auto thrust feeds the same tracker and scores through it.
	runtime.act._set_state(2)
	runtime._bundle.readiness.configure_auto(1.5, 0.9, "cosine", 0.0)
	runtime.act.reset_thrust_state()
	var auto_thrusts := int(runtime._bundle.readiness.act_intensity_total)
	runtime.act.input.toggle_auto_thrust()
	check(runtime.act.input.auto_active(), "X enables auto thrust in ACTIVE")
	for _i: int in 240:
		runtime.act._clock_s += 1.0 / 60.0
		runtime._bundle.impact.auto_advance(1.0 / 60.0)
	check(int(runtime._bundle.readiness.act_intensity_total) > auto_thrusts, "auto thrust feeds the same tracker")
	check(not str(runtime._bundle.readiness.last_intensity).is_empty(), "auto thrust classifies intensity")
	runtime._bundle.readiness.stop_auto()
	check(not runtime.act.input.auto_active(), "stopping auto clears the mode")
	runtime.act.reset_thrust_state()
	check(not runtime.act.input.auto_active(), "thrust reset clears auto for the next act")
	# The depth scale is physical: his shaft length decides a full stroke, and the tip rests at her
	# entrance so the resting contact sits at zero depth.
	check(near(runtime.act.penetration_reach(), THRUST_STATE.NOMINAL_SHAFT_M),
		"the nominal shaft sets the depth scale with no part")
	check(near(runtime._bundle.readiness.penetration_m, 0.0), "the reset rests the tip at her entrance")
	runtime._bundle.impact.set_penetration(-1.0, 0.0)
	check(near(runtime._bundle.readiness.penetration_m, 0.0) and near(runtime._bundle.readiness.depth, 0.0),
		"pulling out never moves the tip behind her lips")
	runtime._bundle.impact.set_penetration(0.1, 0.2)
	check(near(runtime._bundle.readiness.depth, 0.5), "half the reach reads as half depth")
	runtime._bundle.impact.set_penetration(1.0, 0.4)
	check(near(runtime._bundle.readiness.penetration_m, THRUST_STATE.NOMINAL_SHAFT_M), "full depth stops at the reach")
	# The readiness stroke state fills the physical facts presentation reads: the tier, the
	# contact, the gap, the wobble and the visual impact all arrive on the typed event.
	runtime.act.reset_thrust_state()
	runtime._bundle.readiness.move(2.0, 0.0)
	var impacts: Array = runtime._bundle.readiness.move(-2.0, 0.05)
	check(not impacts.is_empty() and str(impacts[0].kind) == "impact",
		"the stroke bottom is one impact event")
	if not impacts.is_empty():
		var impact: RefCounted = impacts[0]
		check(str(impact.tier) == "rough" and bool(impact.plap),
			"a fast bottomed stroke plaps rough")
		check(near(float(impact.gap), 0.0), "a bottomed-out stroke leaves no skin gap")
		check(near(float(impact.visual), 1.0), "a full fast stroke reaches full visual impact")
		check(float(impact.jiggle) > 0.9, "a full stroke wobbles the flank")
	runtime.act.reset_thrust_state()
	runtime.free()

	print("RUNTIME_THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	quit(0 if failures == 0 else 1)
