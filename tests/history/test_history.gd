extends SceneTree
## The history facade: the summary commit, peak memory, the tolerance meter, the idle scan
## decisions and the refusal gate. No live world is needed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/history/test_history.gd

const HISTORY := preload("res://mods/unfplap/history.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")

var failures := 0
var checks := 0


class FakeMods extends Node:
	var data := {"unfplap": {}}
	var saves := 0

	func state(id: String) -> Dictionary:
		var value: Variant = data.get(id, {})
		return value if value is Dictionary else {}

	func save_changed() -> void:
		saves += 1


class FakeGame extends Node:
	pass


class FakeMemory extends Node:
	var impressions: Array = []
	var notes: Array = []
	var peaks: Array = []

	func commit(impression: MEMORY.Impression) -> void:
		impressions.append(impression)

	func note(kind: int, id: String, event_id: String, _reason := 0) -> void:
		notes.append({"kind": kind, "id": id, "event_id": event_id})

	func record_peak(peak: MEMORY.Peak) -> void:
		peaks.append(peak)


class FakeMain extends Node:
	var game: Node = FakeGame.new()
	var memory: Node = FakeMemory.new()


class FakePony extends Node3D:
	pass


class FakeVerdict extends RefCounted:
	var history_refuse := false


class Host extends RefCounted:
	var text := ""
	var calls := 0
	var busy := false
	var idle := true

	func write(line: String) -> void:
		text = line

	func react(_reaction: int, _event_id: String, _fallback: String,
			_valid: Callable) -> String:
		calls += 1
		return "history:%d" % calls

	func is_busy() -> bool:
		return busy

	func is_idle() -> bool:
		return idle

	func clock_now() -> float:
		return 100.0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _mods() -> FakeMods:
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var mods := FakeMods.new()
	mods.name = "Mods"
	root.add_child(mods)
	return mods


func _main() -> FakeMain:
	var main := FakeMain.new()
	root.add_child(main)
	main.add_child(main.game)
	root.add_child(main.memory)
	return main


func _inputs(seconds := 90.0, thrusts := 10) -> Dictionary:
	return {
		"preferences": {"intensity": "firm", "pattern": "steady", "talk": [], "touch": [],
			"dislikes": []},
		"seconds": seconds,
		"thrusts": thrusts,
		"pony_climaxes": 1,
		"talk_liked": 0,
		"talk_dislikes": 0,
		"touches_liked": 0,
		"touch_dislikes": {},
		"player_lines": 0,
		"intensity_total": 5,
		"intensity_right": 5,
		"pattern_total": 5,
		"pattern_right": 5,
		"ended_early": false,
		"stopped_by_her": false,
		"tolerance": "normal",
		"forced": false,
	}


func _context(main: FakeMain, inputs: Dictionary) -> Dictionary:
	return {
		"main": main,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"inputs": inputs,
	}


func run() -> void:
	var mods := _mods()
	var main := _main()
	var host := Host.new()
	var history := HISTORY.new()
	history.log = Callable(host, "write")
	history.reaction_line = Callable(host, "react")
	history.idle = Callable(host, "is_idle")

	check(history.summary.is_empty(), "the summary starts empty")
	check(not history.summary_done, "the summary flag starts clear")
	check(not history.peak_recorded, "the peak flag starts clear")
	history.reset_act({"tolerance": "strict"})
	check(history.tolerance != null and history.tolerance.tier == "strict",
		"reset binds the tolerance tier")
	check(is_zero_approx(history.distress()), "the tolerance meter starts at zero")

	history.commit_summary(true, _context(main, _inputs()))
	check(not history.summary.is_empty(), "a summary is committed once")
	check(str(history.summary.get("grade", "")) == "good", "a clean act is good")
	check(int(history.summary.get("romance", 0)) == 2, "a good act gives romance +2")
	check(main.memory.impressions.size() == 1, "the impression is written once")
	check(mods.saves >= 1, "the history row is saved")
	var row: Dictionary = (mods.data["unfplap"].get("act_history", {}) as Dictionary).get("rarity", {})
	check(int(row.get("acts", 0)) == 1, "the history row counts the act once")
	history.commit_summary(true, _context(main, _inputs()))
	check(main.memory.impressions.size() == 1, "a second commit is a no-op")

	history.summary_done = false
	history.summary = {}
	history.commit_summary(false, _context(main, _inputs(1.0, 0)))
	check(history.summary.is_empty(), "a short act with no thrusts is skipped")

	history.reset_act({"tolerance": "normal"})
	history.summary = {"positive": true, "grade": "good"}
	history.record_peak_memory({
		"main": main,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"satisfaction": 95.0,
		"both_matches": 6,
		"dislikes": 0,
		"liked_touch": 1,
		"liked_talk": 0,
		"player_talk": "you are perfect",
		"her_at": 10.0,
		"her_line": "I know.",
	}, 5.0)
	check(main.memory.peaks.size() == 1, "a peak act is stored once")
	if not main.memory.peaks.is_empty():
		var peak: MEMORY.Peak = main.memory.peaks[0]
		check(peak.text.contains("you are perfect") and peak.text.contains("I know."),
			"the peak quotes the act's exchange")
		check(peak.score > 0.0, "the peak keeps its score")
	history.record_peak_memory({"main": main}, 0.0)
	check(main.memory.peaks.size() == 1, "the peak is stored once per act")

	var disliked: Dictionary = history.observe_dislike("smack")
	check(not disliked.is_empty() and int(disliked.get("warning", 0)) == 1,
		"the first dislike warns")
	check(is_equal_approx(history.distress(), 1.0), "the meter counts the dislike")
	history.observe_like("caress")
	check(is_zero_approx(history.distress()), "a liked touch relieves the meter")
	history.tolerance_tick(26.0)
	check(is_zero_approx(history.distress()), "decay cannot go below zero")

	history.reset_act({"tolerance": "strict"})
	history.observe_dislike("smack")
	history.observe_dislike("smack")
	var stopped: Dictionary = history.observe_dislike("smack")
	check(bool(stopped.get("stop", false)), "the strict tier stops at three")
	var decision: Dictionary = history.tolerance_decision(stopped)
	check(bool(decision.get("stop", false)), "the stop event survives the decision")
	check(not history.tolerance_decision({}).has("stop"), "an empty event is no decision")

	history.request_debug("warning")
	check(history.take_debug() == "warning", "the debug request is consumed once")
	check(history.take_debug() == "", "the debug request clears")

	var blocks := FakeVerdict.new()
	check(not history.blocks_start(blocks), "a normal verdict does not block the start")
	blocks.history_refuse = true
	check(history.blocks_start(blocks), "a withdrawn verdict blocks the start")
	check(history.blocks_start(null) == false, "a missing verdict does not block")
	check(history.refusal_ready(10.0), "a fresh refusal is ready")
	history.mark_refusal(10.0)
	check(not history.refusal_ready(11.0), "the refusal rate limit holds")
	check(history.refusal_ready(15.0), "the refusal rate limit clears")

	var pony := FakePony.new()
	root.add_child(pony)
	var director := Node.new()
	root.add_child(director)
	mods.data["unfplap"]["act_history"] = {
		"rarity": {"hurt": 3, "last_apology_day": -1.0, "reminder_pending": false},
	}
	# The first turn is the baseline; a later turn with an apology repairs one point.
	history.tick_idle(0.0, {
		"main": main, "pony": pony, "director": director,
		"pony_id": "rarity", "event_id": "intimacy_test", "now": 100.0,
		"turn": 2, "text": "", "paused": false, "speech_busy": false,
		"director_state": "idle", "distance": 1.0, "target_is_player": false,
	})
	history.tick_idle(1.1, {
		"main": main,
		"pony": pony,
		"director": director,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"now": 100.0,
		"turn": 3,
		"text": "I'm sorry",
		"paused": false,
		"speech_busy": false,
		"director_state": "idle",
		"distance": 1.0,
		"target_is_player": true,
	})
	var repair_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["rarity"]
	check(int(repair_row.get("hurt", 3)) == 2, "a sincere apology repairs one point")
	check(main.memory.notes.size() == 1, "the apology writes one note")

	mods.data["unfplap"]["act_history"] = {
		"rarity": {"hurt": 2, "last_at": 0.0, "reminder_pending": true,
			"complaint_pending": false},
	}
	var before_calls := host.calls
	history.tick_idle(1.1, {
		"main": main,
		"pony": pony,
		"director": director,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"now": 200.0,
		"turn": 3,
		"text": "",
		"paused": false,
		"speech_busy": false,
		"director_state": "idle",
		"distance": 1.0,
		"target_is_player": false,
	})
	check(host.calls == before_calls + 1, "a pending reminder queues one line")
	var reminder_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["rarity"]
	check(not bool(reminder_row.get("reminder_pending", true)),
		"the queued reminder is marked announced")

	print("HISTORY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("HISTORY_PASS")
	quit(0 if failures == 0 else 1)
