extends "res://mods/unfplap/tests/support/suite.gd"
## Minimal integration test for ACTIVE readiness and pony-climax separation, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")

func _view(runtime: Node) -> RefCounted:
	runtime.act.refresh_view()
	runtime.act.sync_hud()
	return runtime.act.facts()


func _runtime() -> Node:
	var runtime: Node = RUNTIME.new()
	var body := Node3D.new()
	runtime.add_child(body)
	runtime.pony = body
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
	runtime.act.context.readiness.last_touch_at = -1000.0
	runtime.act.context.readiness.last_talk_at = -1000.0
	runtime.act.reset_thrust_state()
	root.add_child(runtime)
	return runtime


func run() -> void:
	var runtime: Node = _runtime()
	# A dangling clock binding returns 0.0 forever and freezes the timers; the three consumers
	# must read the session's clock and advance with it.
	runtime.act.tick_clock(0.25)
	check(runtime.act.context.readiness.clock.is_valid(), "readiness binds the session clock")
	check(near(runtime.act.context.readiness._now(), 0.25), "readiness clock advances with the session")
	check(runtime.act.context.face.clock.is_valid(), "face binds the session clock")
	check(near(runtime.act.context.face._now(), 0.25), "face clock advances with the session")
	check(runtime.act.context.facts.now.is_valid(), "act facts bind the session clock")
	check(near(float(runtime.act.context.facts.now.call()), 0.25), "act facts clock advances with the session")
	runtime.act.context.impact.move(0.10, 0.0)
	runtime.act.context.impact.move(-0.15, 0.1)
	check(str(runtime.act.context.readiness.last_intensity).is_empty(), "tiny stroke does not feed the axes")
	runtime.act.context.impact.move(0.5, 0.2)
	runtime.act.context.impact.move(-0.5, 0.45)
	check(not str(runtime.act.context.readiness.last_intensity).is_empty(), "real thrust classifies intensity")
	check(near(runtime.act.context.readiness.satisfaction, 0.7), "a single matching axis adds only the one-axis chunk")

	runtime.act.context.readiness.last_intensity = "firm"
	runtime.act.context.readiness.last_pattern = "steady"
	runtime.act.context.readiness.last_stroke_at = runtime.act.clock_s()
	runtime.act.context.readiness.last_thrust_score_at = -1000.0
	runtime.act.context.readiness.score_thrust()
	check(runtime.act.context.readiness.satisfaction > 1.0, "matching both axes adds readiness")
	# Heat multiplies the same matching chunk; the debug override bypasses the world day.
	CYCLE.set_override(runtime.live_id(), "heat")
	runtime.act.context.readiness.satisfaction = 0.0
	runtime.act.context.readiness.last_intensity = "firm"
	runtime.act.context.readiness.last_pattern = "steady"
	runtime.act.context.readiness.last_thrust_score_at = -1000.0
	runtime.act.context.readiness.receptive_until = 0.0
	runtime.act.context.readiness.score_thrust()
	check(near(runtime.act.context.readiness.satisfaction, 1.4 * 1.6), "heat multiplies the thrust chunk")
	runtime.act.cycle_heat = true
	check(HUD_LINES.readiness_line_for(_view(runtime), true).contains("In heat"),
		"heat shows on the readiness line")
	check(HUD_LINES.readiness_line_for(_view(runtime), false).is_empty(),
		"readouts off hide the heat line")
	runtime.act.cycle_heat = false
	CYCLE.set_override(runtime.live_id(), "")
	var before: float = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.tick(10.0)
	check(near(runtime.act.context.readiness.satisfaction, before), "readiness does not decay on its own")

	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.touch("caress")
	check(runtime.act.context.readiness.satisfaction > before, "liked touch adds readiness")
	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.talk("you are beautiful")
	check(runtime.act.context.readiness.satisfaction > before, "liked talk adds readiness")
	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.touch("smack")
	check(near(runtime.act.context.readiness.satisfaction, before), "shared touch cooldown blocks a second chunk")
	runtime.act.context.readiness.last_touch_at = -1000.0
	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.touch("kiss")
	check(near(runtime.act.context.readiness.satisfaction, before), "neutral touch does not change readiness")
	runtime.act.context.readiness.last_touch_at = -1000.0
	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.touch("smack")
	check(runtime.act.context.readiness.satisfaction < before, "disliked touch lowers readiness")

	runtime.act.context.readiness.satisfaction = 59.0
	runtime.act.context.readiness.last_touch_at = -1000.0
	runtime.act.context.readiness.touch("caress")
	check(near(runtime.act.context.readiness.satisfaction, 60.0), "liked touch clamps at the assist cap")
	before = runtime.act.context.readiness.satisfaction
	runtime.act.context.readiness.last_touch_at = -1000.0
	runtime.act.context.readiness.touch("caress")
	check(near(runtime.act.context.readiness.satisfaction, before), "caress cannot pass the assist cap")
	check(runtime.act.context.readiness.receptive_until > runtime.act.clock_s(), "liked touch opens the receptive window")

	runtime.act.context.readiness.add_heat(999.0)
	check(near(runtime.act.context.readiness.satisfaction, 100.0), "readiness clamps at 100")
	runtime.act.context.readiness.tick(0.1)
	check(int(runtime.act.state) == 3, "100 readiness starts a pony climax")
	check(runtime.act.context.readiness.pony_climaxes == 1, "pony climax count increments")
	var climax_readiness: float = runtime.act.context.readiness.satisfaction
	var stroke := THRUST_STATE.StrokeEvent.new()
	stroke.kind = "stroke"
	stroke.direction = 1
	stroke.thrust = true
	stroke.travel = 0.5
	stroke.duration = 0.5
	stroke.speed = 1.0
	stroke.peak_speed = 1.0
	stroke.strength = 0.5
	runtime.act.context.readiness.stroke(stroke)
	check(near(runtime.act.context.readiness.satisfaction, climax_readiness), "thrusting during climax does not score")
	check(int(runtime.act.state) == 3, "thrusting during climax does not end it")

	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "first climax returns to ACTIVE")
	check(near(runtime.act.context.readiness.satisfaction, 0.0), "a climax resets readiness to zero")
	check(runtime.act.context.readiness.pony_climaxes == 1, "climax count survives the return to ACTIVE")

	runtime.act.context.readiness.pony_climaxes = 2
	runtime.act.context.readiness.satisfaction = 100.0
	runtime.act.climax()
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "third climax auto-enters AFTERGLOW")

	runtime.act.max_pony_climaxes = 0
	runtime.act._set_state(2)
	runtime.act.context.readiness.pony_climaxes = 5
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 5/∞"),
		"unlimited climax limit uses the infinity display")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "zero climax limit keeps the act going")
	runtime.act.max_pony_climaxes = 2
	runtime.act._set_state(2)
	runtime.act.context.readiness.pony_climaxes = 2
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 2/2"),
		"configured climax limit shows the denominator")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "configured climax limit enters AFTERGLOW")
	runtime.act.max_pony_climaxes = 3

	# Auto thrust feeds the same tracker and scores through it.
	runtime.act._set_state(2)
	runtime.act.context.readiness.configure_auto(1.5, 0.9, "cosine", 0.0)
	runtime.act.reset_thrust_state()
	var auto_thrusts := int(runtime.act.context.readiness.act_intensity_total)
	runtime.act.input.toggle_auto_thrust()
	check(runtime.act.input.auto_active(), "X enables auto thrust in ACTIVE")
	for _i: int in 240:
		runtime.act._clock_s += 1.0 / 60.0
		runtime.act.context.impact.auto_advance(1.0 / 60.0)
	check(int(runtime.act.context.readiness.act_intensity_total) > auto_thrusts, "auto thrust feeds the same tracker")
	check(not str(runtime.act.context.readiness.last_intensity).is_empty(), "auto thrust classifies intensity")
	runtime.act.context.readiness.stop_auto()
	check(not runtime.act.input.auto_active(), "stopping auto clears the mode")
	runtime.act.reset_thrust_state()
	check(not runtime.act.input.auto_active(), "thrust reset clears auto for the next act")
	# The depth scale is physical: his shaft length decides a full stroke, and the tip rests at her
	# entrance so the resting contact sits at zero depth.
	check(near(runtime.act.penetration_reach(), THRUST_STATE.NOMINAL_SHAFT_M),
		"the nominal shaft sets the depth scale with no part")
	check(near(runtime.act.context.readiness.penetration_m, 0.0), "the reset rests the tip at her entrance")
	runtime.act.context.impact.set_penetration(-1.0, 0.0)
	check(near(runtime.act.context.readiness.penetration_m, 0.0) and near(runtime.act.context.readiness.depth, 0.0),
		"pulling out never moves the tip behind her lips")
	runtime.act.context.impact.set_penetration(0.1, 0.2)
	check(near(runtime.act.context.readiness.depth, 0.5), "half the reach reads as half depth")
	runtime.act.context.impact.set_penetration(1.0, 0.4)
	check(near(runtime.act.context.readiness.penetration_m, THRUST_STATE.NOMINAL_SHAFT_M), "full depth stops at the reach")
	# The readiness stroke state fills the physical facts presentation reads: the tier, the
	# contact, the gap, the wobble and the visual impact all arrive on the typed event.
	runtime.act.reset_thrust_state()
	runtime.act.context.readiness.move(2.0, 0.0)
	var impacts: Array = runtime.act.context.readiness.move(-2.0, 0.05)
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

	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	finish()
