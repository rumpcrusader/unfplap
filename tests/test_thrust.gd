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


## Only the events of one kind: `impact` is the bottom of a stroke, `stroke` its close.
func _only(events: Array, kind: String) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if str(event.get("kind", "stroke")) == kind:
			out.append(event)
	return out


func run() -> void:
	check(near(THRUST.pixels_to_metres(-100.0, 100.0, true), 0.01), "mouse up pushes in")
	check(near(THRUST.pixels_to_metres(-100.0, 100.0, false), -0.01),
		"mouse up pulls out when inverted")
	check(near(THRUST.pixels_to_metres(100.0, 100.0, false), 0.01),
		"mouse down pushes in when inverted")
	check(near(THRUST.pixels_to_metres(-200.0, 200.0, true), 0.01),
		"sensitivity sets the travel per pixel")
	# Depth is measured insertion: anything behind her lips, the back-out included, is zero.
	check(near(THRUST.penetration_to_depth(-0.05, 0.17), 0.0), "the standoff is zero depth")
	check(near(THRUST.penetration_to_depth(0.0, 0.17), 0.0), "the tip at her lips is zero depth")
	check(near(THRUST.penetration_to_depth(0.085, 0.17), 0.5), "half the reach is half depth")
	check(near(THRUST.penetration_to_depth(0.2, 0.17), 1.0), "depth clamps at the reach")

	var tracker: RefCounted = THRUST.new()
	var events: Array = tracker.move(2.0, 0.0)
	check(events.is_empty(), "overshoot emits no stroke yet")
	check(near(tracker.depth, 1.0), "depth clamps at 1")
	events = tracker.move(-2.0, 0.25)
	check(_only(events, "impact").size() == 1, "the reversal fires the impact")
	check(_only(events, "stroke").size() == 1, "reversal closes the inward stroke")
	var inward: Dictionary = _only(events, "stroke")[0]
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
	check(_only(events, "impact").is_empty(), "an outward stroke fires no impact")
	check(_only(events, "stroke").size() == 1, "idle outward stroke closes on timeout")
	var outward: Dictionary = _only(events, "stroke")[0]
	check(int(outward.get("direction", 0)) == -1, "outward direction")
	check(not bool(outward.get("thrust", false)), "outward stroke is not a thrust")

	var jitter: RefCounted = THRUST.new()
	jitter.move(0.30, 0.0)
	events = jitter.move(-0.02, 0.1)
	check(_only(events, "impact").size() == 1, "a pullback fires the impact at the bottom")
	check(_only(events, "stroke").is_empty(), "small pullback does not close the stroke")
	events = jitter.move(0.20, 0.2)
	check(_only(events, "stroke").is_empty(), "resuming inward keeps the same stroke")
	events = jitter.move(-0.50, 0.4)
	check(_only(events, "stroke").size() == 1, "real reversal closes the jittered stroke")
	check(near(float((_only(events, "stroke")[0] as Dictionary).get("travel", 0.0)), 0.48),
		"jitter does not split stroke travel")

	var tiny: RefCounted = THRUST.new()
	tiny.move(0.08, 0.0)
	events = tiny.move(-0.12, 0.1)
	check(_only(events, "impact").is_empty(), "a tiny stroke fires no impact")
	check(_only(events, "stroke").size() == 1, "reversal closes a tiny stroke")
	check(not bool((_only(events, "stroke")[0] as Dictionary).get("thrust", false)),
		"tiny stroke is not a thrust")

	# A 20% peak counts as a soft thrust. Auto strokes after the first start 0.06 above the
	# bottom, so their travel is 0.14; a hand stroke from the bottom reaches the full 0.20.
	var hand_shallow: RefCounted = THRUST.new()
	hand_shallow.move(0.20, 0.0)
	events = hand_shallow.move(-0.30, 0.1)
	check(_only(events, "stroke").size() == 1, "shallow hand stroke closes")
	var hand_event: Dictionary = _only(events, "stroke")[0]
	check(bool(hand_event.get("thrust", false)), "a 20% hand stroke is a thrust")
	check(PREF.intensity_for(float(hand_event.get("strength", 0.0))) == "soft",
		"a 20% hand stroke reads soft")

	var hold: RefCounted = THRUST.new()
	hold.move(0.5, 0.0)
	events = hold.tick(0.1)
	check(_only(events, "stroke").is_empty(), "no timeout before the deadline")
	check(_only(events, "impact").size() == 1, "the held bottom fires the impact")
	events = hold.tick(0.19)
	check(_only(events, "stroke").size() == 1, "timeout closes the stroke")
	check(_only(events, "impact").is_empty(), "the impact fires only once")

	# The stall clock follows the peak, so mouse jitter at the bottom cannot postpone the plap,
	# while a stroke that is still really going inward does not fire early.
	var jittered: RefCounted = THRUST.new()
	jittered.move(0.5, 0.0)
	jittered.move(0.0004, 0.02)
	events = jittered.tick(0.05)
	check(_only(events, "impact").size() == 1, "a pixel of jitter does not postpone the impact")

	var progressing: RefCounted = THRUST.new()
	progressing.move(0.5, 0.0)
	progressing.move(0.002, 0.03)
	events = progressing.tick(0.05)
	check(_only(events, "impact").is_empty(), "real progress restarts the stall clock")

	var smoothed: RefCounted = THRUST.new()
	smoothed.move(0.10, 0.0)
	smoothed.move(0.10, 0.10)
	smoothed.move(0.30, 0.101)
	events = smoothed.move(-0.60, 0.20)
	check(_only(events, "stroke").size() == 1, "smoothed stroke closes")
	var smoothed_event: Dictionary = _only(events, "stroke")[0]
	var speed := float(smoothed_event.get("speed", 0.0))
	var peak := float(smoothed_event.get("peak_speed", 0.0))
	check(peak <= speed * THRUST.PEAK_SPEED_CAP + 0.0001, "peak speed is capped against average")

	var slow_full: RefCounted = THRUST.new()
	slow_full.move(1.0, 0.0)
	events = slow_full.move(-1.0, 2.0)
	check(_only(events, "stroke").size() == 1, "slow full-depth stroke closes")
	var slow_strength := float((_only(events, "stroke")[0] as Dictionary).get("strength", 0.0))
	check(near(slow_strength, 0.15), "slow full-depth strength is soft")
	check(PREF.intensity_for(slow_strength) == "soft", "slow full-depth reads soft")

	var fast_full: RefCounted = THRUST.new()
	fast_full.move(1.0, 0.0)
	events = fast_full.move(-1.0, 0.15)
	check(_only(events, "stroke").size() == 1, "fast full-depth stroke closes")
	var fast_strength := float((_only(events, "stroke")[0] as Dictionary).get("strength", 0.0))
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

	# The wobble follows travel, so a full stroke is uniform across speed; only the soft band
	# fades out, and a soft slow stroke is almost still.
	check(near(THRUST.jiggle_amount(0.94, 0.50), 1.0), "firm full stroke wobbles fully")
	check(near(THRUST.jiggle_amount(0.94, 0.90), 1.0), "rough full stroke wobbles fully")
	check(near(THRUST.jiggle_amount(0.94, 0.14), 0.04), "soft slow full stroke is almost still")
	check(THRUST.jiggle_amount(0.20, 0.60) < 0.30, "a shallow stroke wobbles less")
	check(THRUST.jiggle_amount(0.45, 0.30) > 0.20 and THRUST.jiggle_amount(0.45, 0.30) < 0.40,
		"the soft band fades the wobble in between")

	# The body slap follows the model: full contact at the deepest point, none a compression
	# margin short of it, whatever shaft length and pelvis gap make the reach.
	var reach := 0.17
	check(near(THRUST.contact_amount(reach, reach), 1.0), "bottomed out is full body contact")
	check(near(THRUST.contact_amount(reach - THRUST.CONTACT_COMPRESSION_M, reach), 0.0),
		"a stroke a margin short has no body contact")
	var half := THRUST.contact_amount(reach - THRUST.CONTACT_COMPRESSION_M * 0.5, reach)
	check(half > 0.4 and half < 0.6, "body contact fades in over the compression margin")
	check(THRUST.contact_amount(0.17, 0.17) > THRUST.contact_amount(0.17, 0.19),
		"a shorter reach moves the contact point with it")
	check(near(THRUST.contact_amount(-0.05, reach), 0.0), "the back-out standoff has no contact")

	print("THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("THRUST_PASS")
	quit(0 if failures == 0 else 1)
