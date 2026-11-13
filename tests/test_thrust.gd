extends SceneTree
## Pure depth/stroke tracker tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_thrust.gd

const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")
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
	check(PREF.intensity_for_travel(float(inward.get("travel", 0.0))) == "rough",
		"full depth reads rough on the travel axis")
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
	check(PREF.intensity_for_travel(float(hand_event.get("travel", 0.0))) == "soft",
		"a 20% hand stroke reads soft on the travel axis")

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
	check(PREF.intensity_for_travel(float((_only(events, "stroke")[0] as Dictionary).get("travel", 0.0))) == "rough",
		"slow full-depth reads rough on the travel axis")

	var fast_full: RefCounted = THRUST.new()
	fast_full.move(1.0, 0.0)
	events = fast_full.move(-1.0, 0.15)
	check(_only(events, "stroke").size() == 1, "fast full-depth stroke closes")
	var fast_strength := float((_only(events, "stroke")[0] as Dictionary).get("strength", 0.0))
	check(near(fast_strength, 5.0 / 6.0, 0.001), "fast full-depth strength is high")
	check(PREF.intensity_for(fast_strength) == "rough", "fast full-depth reads rough")
	check(PREF.intensity_for_travel(float((_only(events, "stroke")[0] as Dictionary).get("travel", 0.0))) == "rough",
		"fast full-depth reads rough on the travel axis")

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

	# The body slap follows the model: the gap is a distance from the pose's deepest placement,
	# and the contact epsilon counts as touching.
	var reach := 0.17
	check(near(THRUST.skin_gap_m(reach, reach), 0.0), "bottomed out leaves no skin gap")
	check(near(THRUST.skin_gap_m(reach - 0.03, reach), 0.03), "a stroke short leaves a gap")
	check(near(THRUST.skin_gap_m(-0.05, reach), reach + 0.05),
		"the back-out standoff is a full gap")
	check(THRUST.plap_touching(0.0, 0.02), "a bottomed-out stroke touches")
	check(THRUST.plap_touching(0.02, 0.02), "the epsilon edge still touches")
	check(not THRUST.plap_touching(0.021, 0.02), "a stroke past the epsilon is silent")
	check(not THRUST.plap_touching(0.01, 0.0), "a zero epsilon needs the deepest point")

	# The tier is the impact speed, not the readiness intensity band. A slow bottom is silent even
	# when it touches; the same travel in less time is firm, and a hard bottom is rough.
	check(THRUST.plap_tier(THRUST.PLAP_FIRM_SPEED - 0.01) == "", "below firm is silent")
	check(THRUST.plap_tier(THRUST.PLAP_FIRM_SPEED) == "firm", "firm speed picks firm")
	check(THRUST.plap_tier(THRUST.PLAP_ROUGH_SPEED - 0.01) == "firm", "the top of firm stays firm")
	check(THRUST.plap_tier(THRUST.PLAP_ROUGH_SPEED) == "rough", "rough speed picks rough")

	var slow_bottom: RefCounted = THRUST.new()
	slow_bottom.move(0.25, 0.0)
	slow_bottom.move(0.25, 1.0)
	events = slow_bottom.move(-0.30, 1.1)
	var slow_speed := float((_only(events, "impact")[0] as Dictionary).get("impact_speed", 0.0))
	check(near(slow_speed, 0.25), "a slow bottom reads its bottom speed")
	check(THRUST.plap_tier(slow_speed) == "", "a slow bottomed-out stroke stays silent")

	var fast_bottom: RefCounted = THRUST.new()
	fast_bottom.move(0.25, 0.0)
	fast_bottom.move(0.25, 0.05)
	events = fast_bottom.move(-0.30, 0.1)
	var fast := float((_only(events, "impact")[0] as Dictionary).get("impact_speed", 0.0))
	check(near(fast, 5.0), "a normal bottom reads its bottom speed")
	check(THRUST.plap_tier(fast) == "firm", "a normal bottomed-out stroke plaps firm")

	var hard_bottom: RefCounted = THRUST.new()
	hard_bottom.move(0.25, 0.0)
	hard_bottom.move(0.25, 0.02)
	events = hard_bottom.move(-0.30, 0.03)
	var hard := float((_only(events, "impact")[0] as Dictionary).get("impact_speed", 0.0))
	check(hard > fast, "a hard bottom reads faster than a normal one")
	check(THRUST.plap_tier(hard) == "rough", "a hard bottomed-out stroke plaps rough")

	# A pause at the bottom is not an impact: the deepest-window average ignores the flat samples.
	var dwelled: RefCounted = THRUST.new()
	dwelled.move(0.25, 0.0)
	dwelled.move(0.25, 0.05)
	dwelled.tick(0.07)
	events = dwelled.move(-0.30, 0.2)
	var dwell_speed := float((_only(events, "impact")[0] as Dictionary).get("impact_speed", 0.0))
	check(near(dwell_speed, fast), "a dwell at the bottom does not dilute the impact speed")

	print("THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("THRUST_PASS")
	quit(0 if failures == 0 else 1)
