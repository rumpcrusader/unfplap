extends SceneTree
## Pure depth/stroke tracker tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_thrust.gd

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


func run() -> void:
	check(near(THRUST.mouse_to_depth(-100.0, 400.0, true), 0.25), "mouse up deepens")
	check(near(THRUST.mouse_to_depth(-100.0, 400.0, false), -0.25), "mouse up shallows when inverted")
	check(near(THRUST.mouse_to_depth(100.0, 400.0, false), 0.25), "mouse down deepens when inverted")

	var tracker: RefCounted = THRUST.new()
	var events: Array = tracker.move(2.0, 0.0)
	check(events.is_empty(), "overshoot emits no stroke yet")
	check(near(tracker.depth, 1.0), "depth clamps at 1")
	events = tracker.move(-2.0, 0.25)
	check(events.size() == 1, "reversal closes the inward stroke")
	var inward: Dictionary = events[0]
	check(int(inward.get("direction", 0)) == 1, "inward direction")
	check(bool(inward.get("thrust", false)), "full inward travel is a thrust")
	check(near(float(inward.get("travel", 0.0)), 1.0), "inward travel")
	check(near(float(inward.get("duration", 0.0)), 0.25), "inward duration")
	check(near(float(inward.get("speed", 0.0)), 4.0), "inward speed")
	check(near(float(inward.get("peak_speed", 0.0)), 4.0), "inward peak speed")
	check(near(float(inward.get("strength", 0.0)), 0.5), "full deep thrust strength")
	check(PREF.intensity_for(float(inward.get("strength", 0.0))) == "firm",
		"full normal-speed thrust reads firm")
	check(not inward.has("base_gain"), "stroke has no base gain")
	events = tracker.tick(0.8)
	check(events.size() == 1, "idle outward stroke closes on timeout")
	var outward: Dictionary = events[0]
	check(int(outward.get("direction", 0)) == -1, "outward direction")
	check(not bool(outward.get("thrust", false)), "outward stroke is not a thrust")

	var jitter: RefCounted = THRUST.new()
	jitter.move(0.30, 0.0)
	events = jitter.move(-0.02, 0.1)
	check(events.is_empty(), "small pullback does not close the stroke")
	events = jitter.move(0.20, 0.2)
	check(events.is_empty(), "resuming inward keeps the same stroke")
	events = jitter.move(-0.50, 0.4)
	check(events.size() == 1, "real reversal closes the jittered stroke")
	check(near(float((events[0] as Dictionary).get("travel", 0.0)), 0.48),
		"jitter does not split stroke travel")

	var tiny: RefCounted = THRUST.new()
	tiny.move(0.20, 0.0)
	events = tiny.move(-0.30, 0.1)
	check(events.size() == 1, "reversal closes a tiny stroke")
	check(not bool((events[0] as Dictionary).get("thrust", false)), "tiny stroke is not a thrust")

	var hold: RefCounted = THRUST.new()
	hold.move(0.5, 0.0)
	check(hold.tick(0.1).is_empty(), "no timeout before the deadline")
	check(hold.tick(0.19).size() == 1, "timeout closes the stroke")

	var smoothed: RefCounted = THRUST.new()
	smoothed.move(0.10, 0.0)
	smoothed.move(0.10, 0.10)
	smoothed.move(0.30, 0.101)
	events = smoothed.move(-0.60, 0.20)
	check(events.size() == 1, "smoothed stroke closes")
	var smoothed_event: Dictionary = events[0]
	var speed := float(smoothed_event.get("speed", 0.0))
	var peak := float(smoothed_event.get("peak_speed", 0.0))
	check(peak <= speed * THRUST.PEAK_SPEED_CAP + 0.0001, "peak speed is capped against average")

	var slow_full: RefCounted = THRUST.new()
	slow_full.move(1.0, 0.0)
	events = slow_full.move(-1.0, 2.0)
	check(events.size() == 1, "slow full-depth stroke closes")
	var slow_strength := float((events[0] as Dictionary).get("strength", 0.0))
	check(near(slow_strength, 0.15), "slow full-depth strength is soft")
	check(PREF.intensity_for(slow_strength) == "soft", "slow full-depth reads soft")

	var fast_full: RefCounted = THRUST.new()
	fast_full.move(1.0, 0.0)
	events = fast_full.move(-1.0, 0.15)
	check(events.size() == 1, "fast full-depth stroke closes")
	var fast_strength := float((events[0] as Dictionary).get("strength", 0.0))
	check(near(fast_strength, 5.0 / 6.0, 0.001), "fast full-depth strength is high")
	check(PREF.intensity_for(fast_strength) == "rough", "fast full-depth reads rough")

	var live: RefCounted = THRUST.new()
	live.move(0.2, 0.0)
	live.move(0.2, 0.1)
	check(near(live.live_travel(), 0.4), "live travel follows the open stroke")
	check(near(live.live_speed(0.1), 4.0), "live speed follows the open stroke")
	check(near(live.live_strength(0.1), 0.2), "live strength follows the open stroke")

	var reset: RefCounted = THRUST.new()
	reset.move(0.5, 0.0)
	reset.reset()
	check(near(reset.depth, 0.0), "reset clears depth")
	check(reset.tick(10.0).is_empty(), "reset clears the open stroke")

	print("THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("THRUST_PASS")
	quit(0 if failures == 0 else 1)
