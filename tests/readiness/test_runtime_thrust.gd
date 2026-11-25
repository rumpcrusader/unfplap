extends "res://mods/unfplap/tests/support/suite.gd"
## The act's meter on a live runtime: the stroke and its score, heat, the touch and talk verbs, her
## climax and its limit, the automatic stroke through the same tracker and the depth scale. No
## world is needed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")

## One deepening move of a real thrust. It is shorter than the tracker's stroke timeout and longer
## than its bottom stall, so the hold scores no idle close of its own.
const STROKE_STEP_S := 0.08
## The idle wait after each thrust, long enough for the meter's scoring interval.
const THRUST_GAP_S := 0.2


func _view(runtime: Node) -> RefCounted:
	runtime.act.refresh_view()
	runtime.act.sync_hud()
	return runtime.act.facts()


func _readout(runtime: Node) -> READINESS.Readout:
	return runtime.act.context.readiness.readout()


## A new act on the same runtime: her profile, a fresh meter, a fresh automatic stroke and the
## scoring window.
func _new_act(runtime: Node) -> void:
	var readiness: READINESS = runtime.act.context.readiness
	readiness.start_act(READINESS.Profile.from_dict(runtime.act.preferences))
	runtime.act.context.auto.start_act()
	readiness.activate()


## One real thrust through the mouse path: five deepening moves over a steady duration, then the
## reversal closes it.
func _thrust(runtime: Node, travel: float) -> void:
	var readiness: READINESS = runtime.act.context.readiness
	var impact: Variant = runtime.act.context.impact
	var part := travel / 5.0
	for i: int in 5:
		readiness._process(STROKE_STEP_S)
		impact.move(part)
	impact.move(-travel)
	readiness._process(THRUST_GAP_S)


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
	runtime.act.apply_start()
	runtime.act._set_state(2) # ACTIVE
	runtime.act.reset_thrust_state()
	root.add_child(runtime)
	_new_act(runtime)
	return runtime


func run() -> void:
	var previous_limit := SETTINGS.max_pony_climaxes.get_num()
	var runtime: Node = _runtime()
	var readiness: READINESS = runtime.act.context.readiness
	# The act's own clocks still advance; the meter keeps its own tick, so the act never drives it.
	runtime.act.tick_clock(0.25)
	check(runtime.act.context.face.clock.is_valid(), "face binds the session clock")
	check(near(runtime.act.context.face._now(), 0.25), "face clock advances with the session")
	check(runtime.act.context.facts.now.is_valid(), "act facts bind the session clock")
	check(near(float(runtime.act.context.facts.now.call()), 0.25),
		"act facts clock advances with the session")
	readiness._process(0.25)
	check(_readout(runtime).seconds_since_stroke > 1.0,
		"the meter's own tick runs with no stroke behind it")

	# A tiny movement is presentation only: it closes a stroke too small to be a thrust.
	runtime.act.context.impact.move(0.10)
	readiness._process(0.1)
	runtime.act.context.impact.move(-0.15)
	check(_readout(runtime).last_intensity.is_empty(), "tiny stroke does not feed the axes")
	_thrust(runtime, 0.5)
	check(not _readout(runtime).last_intensity.is_empty(), "a real thrust classifies intensity")
	check(near(_readout(runtime).satisfaction, 0.7),
		"a single matching axis adds only the one-axis chunk")
	check(int(readiness.take_meter().thrusts) == 1, "the real thrust is counted")

	# No passive decay while the act runs.
	var before := _readout(runtime).satisfaction
	readiness._process(10.0)
	check(near(_readout(runtime).satisfaction, before), "readiness does not decay on its own")

	# A steady window of matching strokes adds the both-axis chunk, and heat multiplies it.
	_thrust(runtime, 0.5)
	_thrust(runtime, 0.5)
	_thrust(runtime, 0.5)
	before = _readout(runtime).satisfaction
	_thrust(runtime, 0.5)
	check(near(_readout(runtime).satisfaction - before, 1.4),
		"a matched stroke adds the both-axis chunk")
	runtime.act.cycle_heat = true
	CYCLE.set_override(runtime.live_id(), "heat")
	before = _readout(runtime).satisfaction
	_thrust(runtime, 0.5)
	check(near(_readout(runtime).satisfaction - before, 1.4 * 1.6),
		"heat multiplies the matching chunk")
	CYCLE.set_override(runtime.live_id(), "")
	runtime.act.cycle_heat = false

	# The touch and talk verbs share one cooldown each; a like stops at the assist cap.
	_new_act(runtime)
	before = _readout(runtime).satisfaction
	readiness.caress()
	check(_readout(runtime).satisfaction > before, "liked touch adds readiness")
	before = _readout(runtime).satisfaction
	readiness.smack()
	check(near(_readout(runtime).satisfaction, before),
		"the shared touch cooldown blocks a second chunk")
	readiness._process(10.0)
	before = _readout(runtime).satisfaction
	readiness.talk("you are beautiful")
	check(_readout(runtime).satisfaction > before, "liked talk adds readiness")
	before = _readout(runtime).satisfaction
	readiness.kiss()
	check(near(_readout(runtime).satisfaction, before), "a neutral kiss changes no readiness")
	_new_act(runtime)
	readiness.heat(59.0)
	readiness.caress()
	check(near(_readout(runtime).satisfaction, 60.0), "liked touch clamps at the assist cap")
	readiness._process(10.0)
	readiness.caress()
	check(near(_readout(runtime).satisfaction, 60.0), "caress cannot pass the assist cap")

	# A full meter starts her climax through the runtime's connected event.
	readiness.heat(999.0)
	check(near(_readout(runtime).satisfaction, 100.0), "readiness clamps at 100")
	check(int(runtime.act.state) == 3, "100 readiness starts a pony climax")
	check(_readout(runtime).climaxes == 1, "pony climax count increments")
	var climax_readiness := _readout(runtime).satisfaction
	_thrust(runtime, 0.5)
	check(near(_readout(runtime).satisfaction, climax_readiness),
		"thrusting during climax does not score")
	check(int(runtime.act.state) == 3, "thrusting during climax does not end it")

	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "first climax returns to ACTIVE")
	check(near(_readout(runtime).satisfaction, 0.0), "a climax resets readiness to zero")
	check(_readout(runtime).climaxes == 1, "climax count survives the return to ACTIVE")

	_readout(runtime).climaxes = 2
	readiness.heat(100.0)
	check(_readout(runtime).climaxes == 3, "the next climax counts")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "third climax auto-enters AFTERGLOW")

	SETTINGS.max_pony_climaxes.set_num(0)
	runtime.act._set_state(2)
	_readout(runtime).climaxes = 5
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 5/∞"),
		"unlimited climax limit uses the infinity display")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 2, "zero climax limit keeps the act going")
	SETTINGS.max_pony_climaxes.set_num(2)
	runtime.act._set_state(2)
	_readout(runtime).climaxes = 2
	check(HUD_LINES.cue_line_for(_view(runtime), true).begins_with("❤ 2/2"),
		"configured climax limit shows the denominator")
	runtime.act.finish_climax()
	check(int(runtime.act.state) == 4, "configured climax limit enters AFTERGLOW")
	SETTINGS.max_pony_climaxes.set_num(3)

	# Auto thrust feeds the same tracker and scores through it.
	runtime.act._set_state(2)
	_new_act(runtime)
	var auto_thrusts := int(readiness.take_meter().intensity_total)
	runtime.act.input.toggle_auto_thrust()
	check(runtime.act.input.auto_active(), "X enables auto thrust in ACTIVE")
	for _i: int in 240:
		readiness._process(1.0 / 60.0)
		runtime.act.context.impact.auto_advance(1.0 / 60.0)
	check(int(readiness.take_meter().intensity_total) > auto_thrusts,
		"auto thrust feeds the same tracker")
	check(not _readout(runtime).last_intensity.is_empty(), "auto thrust classifies intensity")
	runtime.act.context.auto.stop()
	check(not runtime.act.input.auto_active(), "stopping auto clears the mode")
	runtime.act.reset_thrust_state()
	check(not runtime.act.input.auto_active(), "thrust reset clears auto for the next act")

	# The depth scale is physical: his shaft length decides a full stroke, and the tip rests at her
	# entrance so the resting contact sits at zero depth.
	_new_act(runtime)
	check(near(runtime.act.penetration_reach(), THRUST_STATE.NOMINAL_SHAFT_M),
		"the nominal shaft sets the depth scale with no part")
	check(near(_readout(runtime).penetration_m, 0.0), "the start rests the tip at her entrance")
	runtime.act.context.impact.set_penetration(-1.0)
	check(near(_readout(runtime).penetration_m, 0.0) and near(_readout(runtime).depth, 0.0),
		"pulling out never moves the tip behind her lips")
	runtime.act.context.impact.set_penetration(0.1)
	check(near(_readout(runtime).depth, 0.5), "half the reach reads as half depth")
	runtime.act.context.impact.set_penetration(1.0)
	check(near(_readout(runtime).penetration_m, THRUST_STATE.NOMINAL_SHAFT_M),
		"full depth stops at the reach")

	# The meter fills the physical facts presentation reads: the tier, the contact, the gap, the
	# wobble and the visual impact all arrive on the typed event.
	_new_act(runtime)
	readiness.stroke(2.0)
	var impacts: Array = readiness.stroke(-2.0)
	check(not impacts.is_empty() and str(impacts[0].kind) == "impact",
		"the stroke bottom is one impact event")
	if not impacts.is_empty():
		var impact: RefCounted = impacts[0]
		check(str(impact.tier) == "rough" and bool(impact.plap),
			"a fast bottomed stroke plaps rough")
		check(near(float(impact.gap), 0.0), "a bottomed-out stroke leaves no skin gap")
		check(near(float(impact.visual), 1.0), "a full fast stroke reaches full visual impact")
		check(float(impact.jiggle) > 0.9, "a full stroke wobbles the flank")
	runtime.free()
	SETTINGS.max_pony_climaxes.set_num(previous_limit)

	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	finish()
