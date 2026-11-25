extends "res://mods/unfplap/tests/support/suite.gd"
## The act's meter: the start and its scoring window, the stroke and its score, the touch and talk
## verbs, the cue and its events, her climax, the tolerance decisions, the idle stroke, the drain
## and the one counter record. No runtime and no scene are needed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_readiness.gd

const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")

const PROFILE := {
	"intensity": "firm", "pattern": "steady", "touch": ["caress"],
	"dislikes": ["smack"], "talk": ["praise"], "warmth": "normal", "tolerance": "normal",
}


## The act's live reads: a detached pose at the nominal shaft, and the cycle's heat switch.
class Host extends RefCounted:
	var heat := false

	func shaft_length() -> float:
		return 0.2

	func pose_family() -> String:
		return ""

	func in_heat() -> bool:
		return heat


## Everything the meter emits, counted and stored for the assertions.
class Sink extends RefCounted:
	var climaxes := 0
	var closes := 0
	var overwhelmed := 0
	var cues: Array[Dictionary] = []
	var tolerance: Array[Dictionary] = []
	var stroke_batches := 0
	var end_satisfaction := -1.0

	func on_climax() -> void:
		climaxes += 1

	func on_close() -> void:
		closes += 1

	func on_overwhelmed() -> void:
		overwhelmed += 1

	func on_tolerance(warning: int, stop: bool, distress: float, kind: String) -> void:
		tolerance.append({"warning": warning, "stop": stop, "distress": distress, "kind": kind})

	func on_cue(mood: String, text: String, override: bool) -> void:
		cues.append({"mood": mood, "text": text, "override": override})

	func on_strokes(_events: Array[THRUST_STATE.StrokeEvent]) -> void:
		stroke_batches += 1


func _act(preferences: Dictionary = PROFILE) -> Dictionary:
	var host := Host.new()
	var sink := Sink.new()
	var readiness: READINESS = READINESS.new()
	readiness.wire(READINESS.Deps.new(Callable(host, "shaft_length"),
		Callable(host, "pose_family"), Callable(host, "in_heat")))
	readiness.climaxed.connect(Callable(sink, "on_climax"))
	readiness.close_reached.connect(Callable(sink, "on_close"))
	readiness.overwhelmed.connect(Callable(sink, "on_overwhelmed"))
	readiness.cue_changed.connect(Callable(sink, "on_cue"))
	readiness.tolerance.connect(Callable(sink, "on_tolerance"))
	readiness.strokes.connect(Callable(sink, "on_strokes"))
	readiness.start_act(READINESS.Profile.from_dict(PREF.resolve(preferences)))
	readiness.activate()
	return {"readiness": readiness, "host": host, "sink": sink}


## One real inward thrust: three deepening moves inside one stroke, then the reversal closes it.
## Every hold is shorter than the tracker's bottom stall, so the close is not an idle one.
func _thrust(readiness: READINESS, travel: float, seconds: float) -> void:
	var step := seconds / 3.0
	var part := travel / 3.0
	readiness._process(step)
	readiness.stroke(part)
	readiness._process(step)
	readiness.stroke(part)
	readiness._process(step)
	readiness.stroke(part)
	readiness.stroke(-travel)


func run() -> void:
	_check_start()
	_check_score_and_signals()
	_check_touch_and_talk()
	_check_cue()
	_check_climax()
	_check_tolerance()
	_check_idle_stroke()
	_check_drain()
	_check_meter_copy()
	if failures == 0:
		print("READINESS_PASS")
	finish()


func _check_start() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var readout := readiness.readout()
	check_same(readiness.readout(), readout, "the readout is the one instance")
	check(near(readout.satisfaction, 0.0), "the start clears the meter")
	check(readout.mood == "warming" and readout.cue.is_empty(), "the start clears the cue")
	check(readout.climaxes == 0 and readout.distress == 0.0, "the start clears her counts")
	check(readout.seeks_touch and readout.seeks_talk, "the start reads her seeking flags")
	check(near(readout.reach_m, 0.2) and near(readout.shaft_m, 0.2),
		"the start reads the depth scale")
	check(near(readout.travel, SETTINGS.travel.get_num()), "the start reads the stroke travel")
	check(readout.up_is_deep == (SETTINGS.orientation.get_choice() == "up"),
		"the start reads the mouse orientation")
	readiness.free()


## Scoring opens only with the act's scoring window: a fresh start is not active yet.
func _check_score_and_signals() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	readiness.heat(59.0)
	check(near(readiness.readout().satisfaction, 59.0), "heat raises the meter")
	readiness.heat(999.0)
	check(near(readiness.readout().satisfaction, 100.0), "the meter clamps at full")
	check(sink.climaxes == 1, "a full meter reports her climax")
	check(near(readiness.take_meter().peak_satisfaction, 100.0), "the peak is kept")
	check(sink.closes == 0, "a full meter is no close beat")
	readiness.free()

	var fresh := _act()
	var idle: READINESS = fresh["readiness"]
	var fresh_sink: Sink = fresh["sink"]
	idle.start_act(READINESS.Profile.from_dict(PREF.resolve(PROFILE)))
	idle.heat(50.0)
	check(near(idle.readout().satisfaction, 50.0),
		"heat lands before the scoring window opens")
	check(fresh_sink.closes == 0, "the close threshold needs the scoring window")
	idle.free()

	# One real stroke: a share of his reach in, the reversal closes it, and it scores.
	var scored := _act()
	var meter: READINESS = scored["readiness"]
	var scored_sink: Sink = scored["sink"]
	_thrust(meter, 0.5, 0.09)
	check(scored_sink.stroke_batches == 0, "a stroke closed by the hand needs no idle signal")
	check(near(meter.readout().satisfaction, 0.7),
		"one matching axis adds the one-axis chunk")
	check(meter.readout().last_intensity == "firm", "the stroke reads its intensity")
	check(int(meter.take_meter().intensity_total) == 1, "the intensity axis is counted")
	check(int(meter.take_meter().thrusts) == 1, "a real thrust is counted once")
	# A mismatch gains nothing; the same stroke with the wrong depth axis is presentation only.
	meter._process(0.25)
	_thrust(meter, 0.2, 0.09)
	check(near(meter.readout().satisfaction, 0.7), "a mismatch adds nothing")
	meter.free()


func _check_touch_and_talk() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	readiness.caress()
	check(readiness.readout().satisfaction > 0.0, "a liked caress adds heat")
	check(readiness.take_meter().liked_touch == 1, "the liked-touch counter moves")
	check(sink.overwhelmed == 0, "a liked touch does not overwhelm her")
	var before := readiness.readout().satisfaction
	readiness.kiss()
	check(near(readiness.readout().satisfaction, before), "the shared cooldown blocks a chunk")
	check(readiness.readout().last_touch == "caress", "the cooldown keeps the last scored touch")
	readiness._process(SETTINGS.touch_cooldown_seconds.get_num())
	before = readiness.readout().satisfaction
	readiness.smack()
	check(readiness.readout().satisfaction < before, "a disliked smack lowers the meter")
	check(sink.overwhelmed == 1, "a disliked touch reports her overwhelmed")
	check(readiness.readout().overwhelmed, "the readout carries the overwhelmed state")
	check(sink.tolerance.size() == 1 and int(sink.tolerance[0]["warning"]) == 1,
		"the dislike arrives as one tolerance decision")
	check(near(readiness.readout().distress, 1.0), "the meter counts the dislike")
	# Talk is scored on its own cooldown; his words are kept once per turn.
	readiness._process(SETTINGS.talk_cooldown_seconds.get_num())
	before = readiness.readout().satisfaction
	readiness.talk("you are beautiful")
	check(readiness.readout().satisfaction > before, "a liked talk adds the meter")
	check(readiness.readout().last_talk == "praise", "the talk reads its category")
	check(readiness.take_meter().player_talk == "you are beautiful", "his line is kept")
	check(readiness.take_meter().player_lines == 1, "the turn is counted once")
	readiness.talk("hello")
	check(readiness.take_meter().player_lines == 2, "every turn is counted")
	readiness.talk("")
	check(readiness.take_meter().player_lines == 2, "an empty turn is not counted")
	readiness.free()


func _check_cue() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	readiness._process(0.1)
	check(sink.cues.size() == 1, "the first live frame publishes the base cue")
	check(not bool(sink.cues[0]["override"]), "a base cue is no override")
	readiness._process(0.1)
	check(sink.cues.size() == 1, "an unchanged cue is not published again")
	readiness.cue("She likes that.", 4.0)
	check(readiness.readout().cue == "She likes that.", "the cue writes the readout")
	check(readiness.readout().cue_override, "the readout marks the override")
	readiness._process(0.1)
	check(sink.cues.size() == 2 and bool(sink.cues[1]["override"]),
		"the override reaches the act once")
	readiness._process(4.0)
	check(sink.cues.size() == 3 and not bool(sink.cues[2]["override"]),
		"the expired override falls back to the base cue")
	readiness.cue("", 0.0)
	readiness._process(0.1)
	check(not readiness.readout().cue_override, "an empty cue clears the override")
	readiness.free()


func _check_climax() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	readiness.begin_climax(5.0)
	check(readiness.readout().climaxes == 1, "the climax count moves")
	check(readiness.readout().mood == "climax", "her mood becomes the climax")
	check(readiness.readout().cue_override and not readiness.readout().cue.is_empty(),
		"the climax sets her cue")
	readiness._process(0.1)
	check(sink.cues.is_empty(), "the climax frame does not publish a base cue")
	readiness.end_climax()
	check(near(readiness.readout().satisfaction, 0.0), "the climax return resets the meter")
	check(readiness.readout().mood == "warming", "the climax return resets the mood")
	check(readiness.readout().climaxes == 1, "the count survives the return")
	readiness._process(0.1)
	check(sink.climaxes == 0, "no old climax is replayed")
	# A stroke during her climax counts but does not score.
	readiness.heat(40.0)
	readiness.begin_climax(5.0)
	var before := readiness.readout().satisfaction
	_thrust(readiness, 0.5, 0.5)
	check(near(readiness.readout().satisfaction, before), "thrusting during climax does not score")
	check(int(readiness.take_meter().thrusts) == 1, "the thrust still counts")
	check(sink.climaxes == 0, "the meter does not report a second climax")
	readiness.free()


func _check_tolerance() -> void:
	var made := _act({"tolerance": "strict", "dislikes": ["smack"]})
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	for i: int in 3:
		readiness._process(SETTINGS.touch_cooldown_seconds.get_num())
		readiness.smack()
	check(sink.tolerance.size() == 2, "the warning and the stop are one decision each")
	check(int(sink.tolerance[0]["warning"]) == 1, "the strict tier warns first")
	check(bool(sink.tolerance[1]["stop"]), "the strict tier stops at once")
	check(str(sink.tolerance[1]["kind"]) == "smack", "the stop names the input")
	readiness.free()
	# Passive time forgives a little, one point per declared interval.
	var decaying := _act({"dislikes": ["smack"]})
	var meter: READINESS = decaying["readiness"]
	for i: int in 2:
		meter._process(SETTINGS.touch_cooldown_seconds.get_num())
		meter.smack()
	var before := meter.readout().distress
	meter._process(SETTINGS.decay_seconds.get_num() * 0.5)
	check(near(meter.readout().distress, before), "the decay waits for its interval")
	meter._process(SETTINGS.decay_seconds.get_num())
	check(meter.readout().distress < before, "the decay forgives over time")
	meter.free()


func _check_idle_stroke() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	var sink: Sink = made["sink"]
	# A held stroke with no reversal closes on the idle tick and reaches the act as one signal.
	readiness.stroke(0.5)
	readiness._process(0.5)
	check(sink.stroke_batches == 1, "an idle close reaches the act as a stroke signal")
	check(int(readiness.take_meter().thrusts) == 1, "the idle close is scored by the meter")
	check(near(readiness.readout().rate, 1.0), "the held bottom counts as one impact")
	readiness.free()


func _check_drain() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	readiness.heat(40.0)
	readiness.end_act()
	var at_end := readiness.readout().satisfaction
	readiness._process(READINESS.DRAIN_SECONDS * 0.5)
	check(readiness.readout().satisfaction < at_end, "the end runs the meter down")
	check(readiness.readout().satisfaction > 0.5, "the run-down takes its window")
	readiness._process(READINESS.DRAIN_SECONDS)
	check(near(readiness.readout().satisfaction, 0.0), "the run-down reaches zero")
	# A new act cancels a run still going and starts from a full meter again.
	readiness.start_act(READINESS.Profile.from_dict(PREF.resolve(PROFILE)))
	readiness.activate()
	readiness.heat(10.0)
	readiness._process(10.0)
	check(near(readiness.readout().satisfaction, 10.0), "a live act does not drain")
	readiness.heat(30.0)
	readiness.end_act()
	readiness._process(1.0)
	readiness.start_act(READINESS.Profile.from_dict(PREF.resolve(PROFILE)))
	check(near(readiness.readout().satisfaction, 0.0), "a new act starts from zero")
	readiness._process(1.0)
	check(near(readiness.readout().satisfaction, 0.0), "the old run-down is cancelled")
	readiness.free()


## The act's one counter record: every source is set to a distinct value, so a forgotten field or
## a transposed pair fails here instead of in her history.
func _check_meter_copy() -> void:
	var made := _act()
	var readiness: READINESS = made["readiness"]
	readiness._act_thrusts = 3
	readiness.readout().climaxes = 5
	readiness._act_liked_talk = 7
	readiness._act_talk_dislikes = 11
	readiness._act_liked_touch = 13
	readiness._touch_dislikes = {"smack": 17}
	readiness._act_player_lines = 19
	readiness._act_intensity_total = 23
	readiness._act_intensity_right = 29
	readiness._act_pattern_total = 31
	readiness._act_pattern_right = 37
	readiness._peak_satisfaction = 41.5
	readiness._act_both_matches = 43
	readiness._act_dislikes = 47
	readiness._last_player_talk = "stay with me"
	var meter := readiness.take_meter()
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
	check(meter.liked_touch == 13 and meter.liked_talk == 7, "the meter keeps the peak's likes")
	check(meter.player_talk == "stay with me", "the meter keeps his last line")
	readiness._touch_dislikes["smack"] = 99
	readiness._act_thrusts = 101
	check(int(meter.touch_dislikes.get("smack", 0)) == 17,
		"the meter's dislike map is detached from the live counter")
	check(meter.thrusts == 3, "the meter is a copy, not a view of the live counters")
	readiness.free()
