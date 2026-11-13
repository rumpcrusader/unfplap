extends SceneTree
## The readiness facade: heat, stroke scoring, touch/talk input, cues and the act counters.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_readiness.gd

const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")

const ACTIVE := 2
const CLIMAX := 3

var failures := 0
var checks := 0


class Host extends RefCounted:
	var clock := 0.0
	var state := 2
	var heat := false
	var climaxes := 0
	var closes := 0
	var faces: Array[String] = []
	var tolerance_events: Array = []
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

	func dislikes(kind: String) -> Dictionary:
		return {"kind": kind, "source": "test"}

	func likes(_kind: String) -> void:
		pass

	func tolerance(event: Dictionary) -> void:
		tolerance_events.append(event)

	func is_heat() -> bool:
		return heat

	func log_text(_text: String) -> void:
		pass


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
	var host := Host.new()
	var readiness := READINESS.new()
	readiness.log = Callable(host, "log_text")
	readiness.clock = Callable(host, "now")
	readiness.state = Callable(host, "current_state")
	readiness.on_climax = Callable(host, "on_climax")
	readiness.on_close = Callable(host, "on_close")
	readiness.on_face = Callable(host, "on_face")
	readiness.on_cue = Callable(host, "on_cue")
	readiness.tolerance_dislike = Callable(host, "dislikes")
	readiness.tolerance_like = Callable(host, "likes")
	readiness.tolerance_event = Callable(host, "tolerance")
	readiness.heat_cycle = Callable(host, "is_heat")
	var preferences := PREF.resolve({
		"intensity": "firm", "pattern": "steady", "touch": ["caress"],
		"dislikes": ["smack"], "talk": ["praise"], "warmth": "normal",
		"tolerance": "normal",
	})

	readiness.configure(PREF.resolve({}), 10.0, 1.2, 4.0, 8.0, 8.0)
	check(near(readiness.override_seconds, 10.0), "configure keeps the override lifetime")
	readiness.reset(preferences)
	check(near(readiness.satisfaction, 0.0), "reset clears satisfaction")
	check(readiness.pony_climaxes == 0, "reset clears the climax count")
	check(readiness.mood == "warming", "reset leaves the caller's mood alone")
	check(readiness.cue == "", "reset leaves the caller's cue alone")

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
	check(host.tolerance_events.size() == 1, "the touch reports its tolerance event")
	var before := readiness.satisfaction
	readiness.touch("caress")
	check(near(readiness.satisfaction, before), "the shared touch cooldown blocks a second chunk")
	readiness.last_touch_at = -1000.0
	readiness.touch("smack")
	check(readiness.satisfaction < before, "a disliked touch lowers readiness")
	check(host.faces.has("overwhelmed"), "a disliked touch asks for the overwhelmed face")

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

	print("READINESS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("READINESS_PASS")
	quit(0 if failures == 0 else 1)

