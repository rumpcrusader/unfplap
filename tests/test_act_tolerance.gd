extends SceneTree
## Pure per-act tolerance: tiers, warnings, compensation, decay and stop cooldowns.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_tolerance.gd

const TOLERANCE := preload("res://mods/unfplap/act_tolerance.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func make(kind: String) -> RefCounted:
	var tolerance = TOLERANCE.new()
	tolerance.reset({"tolerance": kind})
	return tolerance


func push(tolerance: RefCounted, count: int) -> Array:
	var out: Array = []
	for _index in count:
		out.append(tolerance.observe_dislike("smack"))
	return out


func warning_of(events: Array, index: int) -> int:
	if index < 0 or index >= events.size():
		return 0
	var event: Dictionary = events[index]
	return int(event.get("warning", 0))


func is_stop(events: Array, index: int) -> bool:
	if index < 0 or index >= events.size():
		return false
	return bool((events[index] as Dictionary).get("stop", false))


func run() -> void:
	var neutral = make("neutral")
	var neutral_events := push(neutral, 10)
	check(warning_of(neutral_events, 0) == 1, "neutral warns at 1")
	check(warning_of(neutral_events, 1) == 0 and warning_of(neutral_events, 2) == 0,
		"neutral stays quiet between warnings")
	check(warning_of(neutral_events, 3) == 2, "neutral warns a second time at 4")
	check(not is_stop(neutral_events, 8), "neutral does not stop before 10")
	check(is_stop(neutral_events, 9), "neutral stops at 10")
	check(bool(neutral.stopped), "neutral records the stop")
	check(neutral.cooldown_seconds() > 0.0, "neutral has a stop cooldown")

	var strict = make("strict")
	var strict_events := push(strict, 3)
	check(warning_of(strict_events, 0) == 1, "strict warns at 1")
	check(not is_stop(strict_events, 1), "strict does not stop at 2")
	check(is_stop(strict_events, 2), "strict stops at 3")
	check(strict.cooldown_seconds() > neutral.cooldown_seconds(),
		"the strict cooldown is longer than neutral")

	var timid = make("timid")
	var timid_events := push(timid, 20)
	check(warning_of(timid_events, 2) == 0, "timid does not warn before 4")
	check(warning_of(timid_events, 3) == 1, "timid warns once at 4")
	check(not timid.stopped, "timid never stops")
	check(timid.cooldown_seconds() == 0.0, "timid has no stop cooldown")

	var relief = make("strict")
	push(relief, 2)
	var before := float(relief.distress)
	relief.observe_like("caress")
	check(float(relief.distress) == before - 1.0, "a liked action removes one point")
	var after_like := push(relief, 2)
	check(is_stop(after_like, after_like.size() - 1), "compensation only delays the stop")

	var decay = make("neutral")
	push(decay, 2)
	var decay_before := float(decay.distress)
	decay.tick(24.0)
	check(is_equal_approx(float(decay.distress), decay_before), "decay waits for its interval")
	decay.tick(1.0)
	check(float(decay.distress) == decay_before - 1.0, "decay removes one point after 25 s")

	var repeats = make("neutral")
	push(repeats, 1)
	check(repeats.warning_stage == 1, "the first warning stage is remembered")
	repeats.observe_like("caress")
	repeats.observe_dislike("smack")
	check(repeats.warning_stage == 1, "a warning is not replayed after compensation")

	var reset = make("strict")
	push(reset, 2)
	reset.reset({"tolerance": "neutral"})
	check(reset.distress == 0.0 and reset.warning_stage == 0 and not reset.stopped,
		"a new act resets the meter")
	check(reset.tier == "neutral", "a new act reads the new tier")

	print("ACT_TOLERANCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_TOLERANCE_PASS")
	quit(0 if failures == 0 else 1)
