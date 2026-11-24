extends "res://mods/unfplap/tests/support/suite.gd"
## The readiness facade: heat, stroke scoring, touch/talk input, cues and the act counters.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_readiness.gd

const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")

const ACTIVE := 2
const CLIMAX := 3



class Host extends RefCounted:
	var clock := 0.0
	var state := 2
	var heat := false
	var climaxes := 0
	var closes := 0
	var faces: Array[String] = []
	var cue_calls := 0
	var last_mood := ""
	var last_cue := ""
	var last_override := false

	func now() -> float:
		return clock

	func current_state() -> int:
		return state

	func on_climax() -> void:
		climaxes += 1

	func on_close() -> void:
		closes += 1

	func on_face(name: String) -> void:
		faces.append(name)

	func on_cue(mood: String, cue: String, override: bool) -> void:
		cue_calls += 1
		last_mood = mood
		last_cue = cue
		last_override = override

	func is_heat() -> bool:
		return heat

func run() -> void:
	var host := Host.new()
	var readiness := READINESS.new()
	readiness.clock = Callable(host, "now")
	readiness.state = Callable(host, "current_state")
	readiness.on_climax = Callable(host, "on_climax")
	readiness.on_close = Callable(host, "on_close")
	readiness.on_face = Callable(host, "on_face")
	readiness.on_cue = Callable(host, "on_cue")
	readiness.heat_cycle = Callable(host, "is_heat")
	var preferences := PREF.resolve({
		"intensity": "firm", "pattern": "steady", "touch": ["caress"],
		"dislikes": ["smack"], "talk": ["praise"], "warmth": "normal",
		"tolerance": "normal",
	})

	readiness.configure(READINESS.Profile.from_dict(PREF.resolve({})), 10.0, 1.2, 4.0, 8.0, 8.0)
	check(near(readiness.override_seconds, 10.0), "configure keeps the override lifetime")
	readiness.reset(READINESS.Profile.from_dict(preferences))
	check(near(readiness.satisfaction, 0.0), "reset clears satisfaction")
	check(readiness.pony_climaxes == 0, "reset clears the climax count")
	check(readiness.mood == "warming", "reset leaves the caller's mood alone")
	check(readiness.cue == "", "reset leaves the caller's cue alone")
	check(readiness.tolerance != null and readiness.tolerance.tier == "normal",
		"reset binds the tolerance tier")
	check(near(readiness.distress(), 0.0), "the tolerance meter starts at zero")

	readiness.add_heat(59.0)
	check(near(readiness.satisfaction, 59.0), "heat raises satisfaction")
	readiness.add_heat(999.0)
	check(near(readiness.satisfaction, 100.0), "satisfaction clamps at 100")
	check(near(readiness.peak_satisfaction, 100.0), "the peak is tracked")

	readiness.satisfaction = 0.0
	host.heat = false
	readiness.last_intensity = "firm"
	readiness.last_pattern = "steady"
	readiness.last_thrust_score_at = -1000.0
	readiness.score_thrust()
	check(near(readiness.satisfaction, 1.4), "matching both axes adds the both-axis chunk")
	check(readiness.act_intensity_total == 1 and readiness.act_intensity_right == 1,
		"the intensity axis counters move")
	check(readiness.act_both_matches == 1, "both-axis matches count")
	check(readiness.act_thrusts == 0, "score_thrust does not count a stroke by itself")

	readiness.satisfaction = 0.0
	host.heat = true
	readiness.last_thrust_score_at = -1000.0
	readiness.score_thrust()
	check(near(readiness.satisfaction, 1.4 * 1.6), "heat multiplies the chunk")

	check(readiness.thrusts_per_second() == 0.0, "no impacts means no rate")
	readiness.thrust_times.append(host.clock)
	check(near(readiness.thrusts_per_second(), 1.0), "an impact inside one second counts")
	host.clock = 2.0
	check(near(readiness.thrusts_per_second(), 0.0), "an old impact drops out")

	host.state = ACTIVE
	readiness.satisfaction = 0.0
	readiness.last_touch_at = -1000.0
	readiness.touch("caress")
	check(readiness.satisfaction > 0.0, "a liked touch adds heat")
	check(readiness.act_liked_touch == 1, "the liked-touch counter increments")
	check(readiness.take_tolerance_decision().is_empty(),
		"a liked touch queues no tolerance decision")
	var before := readiness.satisfaction
	readiness.touch("caress")
	check(near(readiness.satisfaction, before), "the shared touch cooldown blocks a second chunk")
	readiness.last_touch_at = -1000.0
	readiness.touch("smack")
	check(readiness.satisfaction < before, "a disliked touch lowers readiness")
	check(host.faces.has("overwhelmed"), "a disliked touch asks for the overwhelmed face")
	var warning := readiness.take_tolerance_decision()
	check(warning.warning == 1, "the first dislike queues a warning")
	check(readiness.take_tolerance_decision().is_empty(), "the decision is consumed once")
	check(near(readiness.distress(), 1.0), "the meter counts the dislike")

	readiness.last_talk_at = -1000.0
	before = readiness.satisfaction
	readiness.talk("you are beautiful")
	check(readiness.satisfaction > before, "a liked talk adds readiness")

	readiness.set_cue_override("", 0.0)
	readiness.close_notified = false
	host.clock = 0.0
	readiness.last_stroke_at = 0.0
	readiness.satisfaction = 70.0
	readiness.tick(0.1)
	check(host.closes == 1, "crossing the close threshold fires one close beat")
	readiness.tick(0.1)
	check(host.closes == 1, "the close beat fires once per act")
	check(host.cue_calls > 0, "the tick publishes the cue")
	check(not host.last_override, "a base cue is not an override")

	readiness.set_cue_override("She likes that.", 4.0)
	check(readiness.cue == "She likes that.", "the override writes the cue")
	check(readiness.cue_override == "She likes that.", "the override is latched")

	host.state = ACTIVE
	readiness.satisfaction = 100.0
	readiness.tick(0.1)
	check(host.climaxes > 0, "a full meter asks the host to climax")
	check(near(readiness.peak_satisfaction, 100.0), "the peak stays for the summary")

	readiness.tolerance_tick(26.0)
	check(near(readiness.distress(), 0.0), "decay cannot go below zero")
	readiness.request_debug("warning")
	check(readiness.take_debug() == "warning", "the debug request is consumed once")
	check(readiness.take_debug() == "", "the debug request clears")

	# The act's meter is one record taken at the verdict. Every source carries a distinct value, so
	# a forgotten field or a transposed pair fails here instead of in her history.
	readiness.act_thrusts = 3
	readiness.pony_climaxes = 5
	readiness.act_liked_talk = 7
	readiness.act_talk_dislikes = 11
	readiness.act_liked_touch = 13
	readiness.act_touch_dislikes = {"smack": 17}
	readiness.act_player_lines = 19
	readiness.act_intensity_total = 23
	readiness.act_intensity_right = 29
	readiness.act_pattern_total = 31
	readiness.act_pattern_right = 37
	readiness.peak_satisfaction = 41.5
	readiness.act_both_matches = 43
	readiness.act_dislikes = 47
	readiness.last_player_talk = "stay with me"
	var meter := readiness.act_output()
	check(meter.thrusts == 3, "the meter keeps the real thrusts")
	check(meter.pony_climaxes == 5, "the meter keeps the pony climaxes")
	check(meter.talk_liked == 7, "the meter keeps the liked talk")
	check(meter.talk_dislikes == 11, "the meter keeps the disliked talk")
	check(meter.touches_liked == 13, "the meter keeps the liked touches")
	check(int(meter.touch_dislikes.get("smack", 0)) == 17, "the meter keeps the disliked touches")
	check(meter.player_lines == 19, "the meter keeps the player lines")
	check(meter.intensity_total == 23 and meter.intensity_right == 29,
		"the meter keeps the intensity pair")
	check(meter.pattern_total == 31 and meter.pattern_right == 37,
		"the meter keeps the pattern pair")
	check(near(meter.peak_satisfaction, 41.5), "the meter keeps the peak satisfaction")
	check(meter.both_matches == 43, "the meter keeps the both-axis matches")
	check(meter.dislikes == 47, "the meter keeps the dislike count")
	check(meter.liked_touch == 13, "the meter keeps the peak's liked touch")
	check(meter.liked_talk == 7, "the meter keeps the peak's liked talk")
	check(meter.player_talk == "stay with me", "the meter keeps his last line")
	readiness.act_touch_dislikes["smack"] = 99
	readiness.act_thrusts = 101
	check(int(meter.touch_dislikes.get("smack", 0)) == 17,
		"the meter's dislike map is detached from the live counter")
	check(meter.thrusts == 3, "the meter is a snapshot, not a view of the live counters")

	readiness.free()
	if failures == 0:
		print("READINESS_PASS")
	finish()

