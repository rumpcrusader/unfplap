extends SceneTree
## Pure depth/stroke tracker tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_pump.gd

const PUMP := preload("res://mods/unfplap/pump.gd")
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
	check(near(PUMP.mouse_to_depth(-100.0, 400.0, true), 0.25), "mouse up deepens")
	check(near(PUMP.mouse_to_depth(-100.0, 400.0, false), -0.25), "mouse up shallows when inverted")
	check(near(PUMP.mouse_to_depth(100.0, 400.0, false), 0.25), "mouse down deepens when inverted")

	var weight := func(_value: float) -> float: return 1.0
	var tracker: RefCounted = PUMP.new()
	var events: Array = tracker.move(2.0, 0.0, weight)
	check(events.is_empty(), "overshoot emits no stroke yet")
	check(near(tracker.depth, 1.0), "depth clamps at 1")
	events = tracker.move(-2.0, 0.5, weight)
	check(events.size() == 1, "reversal closes the inward stroke")
	var inward: Dictionary = events[0]
	check(int(inward.get("direction", 0)) == 1, "inward direction")
	check(bool(inward.get("pump", false)), "full inward travel is a pump")
	check(near(float(inward.get("base_gain", 0.0)), 1.0), "overshoot discarded above 1")
	check(near(float(inward.get("speed", 0.0)), 2.0), "inward speed")
	check(near(float(inward.get("peak_speed", 0.0)), 2.0), "inward peak speed")
	check(near(float(inward.get("strength", 0.0)), 1.0), "full deep pump strength")
	events = tracker.tick(0.8)
	check(events.size() == 1, "idle outward stroke closes on timeout")
	var outward: Dictionary = events[0]
	check(int(outward.get("direction", 0)) == -1, "outward direction")
	check(not bool(outward.get("pump", false)), "outward stroke is not a pump")
	check(near(float(outward.get("base_gain", 0.0)), 1.0), "outward base gain")
	check(near(float(inward.get("base_gain", 0.0)) + float(outward.get("base_gain", 0.0)), 2.0), "full pump total is 2.0")

	var tiny: RefCounted = PUMP.new()
	events = tiny.move(0.02, 0.0, weight)
	check(events.is_empty(), "small move does not close")
	events = tiny.move(-0.01, 0.05, weight)
	check(events.size() == 1, "reversal closes a tiny stroke")
	check(not bool((events[0] as Dictionary).get("pump", false)), "tiny stroke is not a pump")
	check(float((events[0] as Dictionary).get("strength", 1.0)) < 0.1, "tiny stroke has tiny strength")

	var hold: RefCounted = PUMP.new()
	hold.move(0.5, 0.0, weight)
	check(hold.tick(0.1).is_empty(), "no timeout before the deadline")
	check(hold.tick(0.19).size() == 1, "timeout closes the stroke")

	var reset: RefCounted = PUMP.new()
	reset.move(0.5, 0.0, weight)
	reset.reset()
	check(near(reset.depth, 0.0), "reset clears depth")
	check(reset.tick(10.0).is_empty(), "reset clears the open stroke")

	print("PUMP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PUMP_PASS")
	quit(0 if failures == 0 else 1)
