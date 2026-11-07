extends SceneTree
## Auto thrust: the generated depth must be real tracker strokes, and the pace range must
## reach every intensity and pattern class the preference system uses.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_auto_thrust.gd

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const AUTO := preload("res://mods/unfplap/auto_thrust.gd")
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


## Drive the real tracker with the generated depth. Returns every closed stroke event.
func _simulate(depth: float, pace: float, seconds: float) -> Array:
	var auto: RefCounted = AUTO.new()
	auto.call("reset", pace, depth)
	auto.call("begin", 0.0)
	var tracker: RefCounted = THRUST.new()
	var events: Array = []
	var now := 0.0
	var dt := 1.0 / 120.0
	for _i: int in int(seconds / dt):
		now += dt
		var next_depth: float = auto.call("step", dt)
		for event: Dictionary in tracker.move(next_depth - tracker.depth, now):
			events.append(event)
		for event: Dictionary in tracker.tick(now):
			events.append(event)
	# Close an outward stroke still open at the end; inward thrusts are already closed.
	for event: Dictionary in tracker.tick(now + 10.0):
		events.append(event)
	return events


func _thrusts(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if int(event.get("direction", 0)) > 0 and bool(event.get("thrust", false)):
			out.append(event)
	return out


func _last_four(strokes: Array) -> Array:
	return strokes.slice(maxi(0, strokes.size() - 4))


func _intensity(depth: float, pace: float, seconds: float) -> String:
	var strokes := _thrusts(_simulate(depth, pace, seconds))
	if strokes.is_empty():
		return ""
	return PREF.intensity_for(float(strokes[strokes.size() - 1].get("strength", 0.0)))


func _pattern(depth: float, pace: float, seconds: float) -> String:
	return PREF.pattern_for(_last_four(_thrusts(_simulate(depth, pace, seconds))))


## Strongest inward stroke in the last four. A window can end on a partial or timed-out stroke,
## so the fastest pace is read from the best stroke it produced, not from whichever closed last.
func _strongest_intensity(depth: float, pace: float, seconds: float) -> String:
	var strokes := _last_four(_thrusts(_simulate(depth, pace, seconds)))
	var best := 0.0
	for stroke: Dictionary in strokes:
		best = maxf(best, float(stroke.get("strength", 0.0)))
	return PREF.intensity_for(best)


func run() -> void:
	# A cycle is a real thrust with the requested travel.
	var strokes := _thrusts(_simulate(0.9, 1.5, 3.0))
	check(strokes.size() >= 3, "auto thrust produces real inward strokes")
	if not strokes.is_empty():
		var travel := float((strokes[strokes.size() - 1] as Dictionary).get("travel", 0.0))
		check(travel > 0.8 and travel <= 0.9, "auto travel follows the peak depth")
	check(_thrusts(_simulate(AUTO.DEPTH_MIN, 1.0, 4.0)).size() >= 3,
		"the shallowest auto peak still registers every thrust")
	var shallow_strokes := _thrusts(_simulate(AUTO.DEPTH_MIN, 1.0, 4.0))
	if not shallow_strokes.is_empty():
		var shallow_travel := float(
			(shallow_strokes[shallow_strokes.size() - 1] as Dictionary).get("travel", 0.0))
		check(near(shallow_travel, 0.14, 0.01),
			"auto shallow travel keeps the reversal hysteresis offset")
	check(_intensity(AUTO.DEPTH_MIN, 2.0, 3.0) == "soft",
		"the shallowest auto peak counts as soft")

	# Pace and depth together reach every intensity class.
	check(_intensity(1.0, AUTO.PACE_MIN, 3.0) == "soft", "slow full auto reads soft")
	check(_intensity(1.0, 2.0, 2.0) == "firm", "normal full auto reads firm")
	check(_strongest_intensity(1.0, AUTO.PACE_MAX, 1.4) == "rough",
		"fastest full auto reads rough")
	check(_intensity(AUTO.DEPTH_MIN, AUTO.PACE_MAX, 1.0) == "soft",
		"fast shallow auto stays soft")

	# The pace range reaches every pattern class. Depth does not decide the rhythm.
	check(_pattern(0.32, AUTO.PACE_MIN, 16.0) == "teasing", "slow shallow auto reads teasing")
	check(_pattern(0.32, 1.5, 4.0) == "steady", "normal shallow auto reads steady")
	check(_pattern(0.32, 2.5, 2.0) == "quick", "fast shallow auto reads quick")
	check(_pattern(1.0, AUTO.PACE_MIN, 12.0) == "teasing", "slow full auto reads teasing")
	check(_pattern(1.0, 1.5, 4.0) == "steady", "normal full auto reads steady")
	check(_pattern(1.0, 2.5, 2.0) == "quick", "fast full auto reads quick")

	# Every class is inside the slider range, so no setting hangs outside the model.
	var intensities: Dictionary = {}
	var patterns: Dictionary = {}
	for depth: float in [AUTO.DEPTH_MIN, 0.5, 0.9, 1.0]:
		for pace: float in [AUTO.PACE_MIN, 1.25, 1.5, 2.5, 3.5, AUTO.PACE_MAX]:
			intensities[_intensity(depth, pace, 4.0)] = true
			patterns[_pattern(depth, pace, 8.0)] = true
	for name: String in PREF.INTENSITIES:
		check(intensities.has(name), "auto range reaches intensity " + name)
	for name: String in PREF.PATTERNS:
		check(patterns.has(name), "auto range reaches pattern " + name)

	# Enabling from the hand's depth must not snap backwards.
	var auto: RefCounted = AUTO.new()
	auto.call("reset", 1.5, 0.9)
	auto.call("begin", 0.6)
	check(near(float(auto.get("max_depth")), 0.9), "auto keeps the configured peak")
	check(near(float(auto.call("current_depth")), 0.6), "auto begins at the hand's depth")
	auto.call("stop")
	check(not bool(auto.get("active")), "stop clears the mode")
	check(near(float(auto.call("current_depth")), 0.6), "stop leaves the depth alone")

	# A peak shallower than the current depth is raised instead of pulling him back.
	var raised: RefCounted = AUTO.new()
	raised.call("reset", 1.5, AUTO.DEPTH_MIN)
	raised.call("begin", 0.8)
	check(near(float(raised.get("max_depth")), 0.8), "begin raises the peak to the current depth")
	check(near(float(raised.call("current_depth")), 0.8), "raised begin keeps the current depth")

	# Wheel/mouse nudges stay inside the contract bounds.
	var bounds: RefCounted = AUTO.new()
	bounds.call("reset", 1.5, 0.9)
	bounds.call("nudge_depth", -10.0)
	check(near(float(bounds.get("max_depth")), AUTO.DEPTH_MIN), "auto depth clamps at the minimum")
	bounds.call("nudge_depth", 10.0)
	check(near(float(bounds.get("max_depth")), AUTO.DEPTH_MAX), "auto depth clamps at the maximum")
	bounds.call("nudge_pace", -10.0)
	check(near(float(bounds.get("pace")), AUTO.PACE_MIN), "auto pace clamps at the minimum")
	bounds.call("nudge_pace", 10.0)
	check(near(float(bounds.get("pace")), AUTO.PACE_MAX), "auto pace clamps at the maximum")

	# Schema bounds are the player contract, so they must match the generator.
	check(near(SETTINGS.pace.low, AUTO.PACE_MIN),
		"schema auto pace low matches")
	check(near(SETTINGS.pace.high, AUTO.PACE_MAX),
		"schema auto pace high matches")
	check(near(SETTINGS.pace.step, 0.25),
		"schema auto pace steps by a quarter")
	check(near(SETTINGS.max_depth.low, AUTO.DEPTH_MIN),
		"schema auto depth low matches")
	check(near(SETTINGS.max_depth.high, AUTO.DEPTH_MAX),
		"schema auto depth high matches")
	check(near(AUTO.PACE_STEP, 0.25), "wheel pace step is fixed")
	check(SETTINGS.by_path("auto_thrust.pace_step") == null, "the wheel pace step is not a setting")

	print("AUTO_THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("AUTO_THRUST_PASS")
	quit(0 if failures == 0 else 1)
