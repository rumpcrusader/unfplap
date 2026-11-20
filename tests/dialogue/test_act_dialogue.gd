extends SceneTree
## The act dialogue facade: pacing configuration, cue admission, the memory line channel, reaction
## lines and the recent-line reads.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/dialogue/test_act_dialogue.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")

var failures := 0
var checks := 0


class FakeGame extends Node:
	pass


class FakeMemory extends Node:
	var requests: Array = []
	var notes: Array = []
	var states := {}
	var cancel_act_calls := 0
	var cancel_line_calls := 0

	func note(kind: int, id: String, event_id: String, _reason := 0) -> void:
		notes.append({"kind": kind, "id": id, "event_id": event_id})

	func cue_facts(_id: String, _event_id: String) -> MEMORY.CueFacts:
		return MEMORY.CueFacts.new()

	func shared_memory(_id: String, _cue: String, _event_id: String,
			_used: Array[String]) -> MEMORY.MemoryHit:
		return MEMORY.MemoryHit.new()

	func line(request: MEMORY.LineRequest) -> MEMORY.Line:
		requests.append(request)
		var line := MEMORY.Line.new()
		line.key = "line:%d" % requests.size()
		line.queued = true
		states[line.key] = MEMORY.LineState.QUEUED
		return line

	func line_state(key: String) -> int:
		return int(states.get(key, MEMORY.LineState.UNKNOWN))

	func cancel_line(key: String) -> void:
		cancel_line_calls += 1
		states[key] = MEMORY.LineState.ABSENT

	func cancel_act(_event_id: String, _keep_speaking: bool) -> int:
		cancel_act_calls += 1
		return 2

	func observers(_pony: Variant) -> Array:
		return []


class FakeMain extends Node:
	var game: Node = FakeGame.new()
	var memory: Node = FakeMemory.new()


class FakePony extends Node3D:
	var speaking := false
	var conversation_target: Variant = null

	func is_speaking() -> bool:
		return speaking


class FakeDirector extends Node:
	var state := "idle"
	var characters: Dictionary = {}
	var _turn_id := 0
	var _player_text := ""


class Host extends RefCounted:
	var director: Node
	var clock := 0.0

	func get_director() -> Node:
		return director

	func clock_now() -> float:
		return clock


class FakeMods extends Node:
	var data := {"unfplap": {}}
	var saves := 0

	func state(id: String) -> Dictionary:
		var value: Variant = data.get(id, {})
		return value if value is Dictionary else {}

	func save_changed() -> void:
		saves += 1


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
		existing.name = "ModsTest"
	var mods := FakeMods.new()
	mods.name = "Mods"
	root.add_child(mods)
	return mods


func run() -> void:
	var facts := FACTS.new()
	var main := FakeMain.new()
	WORLD.bind_world(main.game)
	MEMORY.instance = main.memory
	var pony := FakePony.new()
	var director := FakeDirector.new()
	director.characters = {
		"fluttershy": {
			"spoken": ["I missed you.", "Not so fast."],
			"last_spoken_at": 12.5,
		},
	}
	var host := Host.new()
	host.director = director
	facts.pony = pony
	facts.pony_id = "fluttershy"
	facts.display_name = "Fluttershy"
	facts.event_id = "evt1"
	var pose: RefCounted = VIEW.new()
	pose.id = "standing"
	pose.family = "standing"
	pose.contact_kind = "opening"
	facts.pose_view = pose
	facts.state = 2
	facts.mood = "warming"
	facts.cue = "She wants it firmer."
	facts.preferences = {
		"intensity": "soft", "pattern": "steady",
		"touch": [], "dislikes": [], "talk": [],
	}
	facts.act_prompts = {"cue": "Cue: {cue}. {seed}"}
	facts.features = {
		"act_speech_feel": false,
	}
	facts.director = Callable(host, "get_director")
	facts.now = Callable(host, "clock_now")

	var dialogue := DIALOGUE.new(facts)
	check(dialogue.scheduler() != null, "the facade owns a scheduler")
	var pacing := DIALOGUE.Pacing.new()
	pacing.base_stable = 2.0
	pacing.override_stable = 0.5
	pacing.utterance_gap = 18.0
	pacing.demand_gap = 28.0
	pacing.demand_repeat = 45.0
	pacing.max_age = 20.0
	pacing.release_hold = 1.0
	dialogue.configure(pacing)
	check(is_equal_approx(dialogue.scheduler().base_stable_s, 2.0),
		"configure pushes the base stability")
	check(is_equal_approx(dialogue.scheduler().utterance_gap_s, 18.0),
		"configure pushes the shared gap")

	dialogue.reset(0.0, 12.0)
	check(dialogue.admit_cue(0.0) == "", "a fresh base cue waits for its stability")
	check(dialogue.admit_cue(2.1) != "", "a stable base cue is admitted")
	check(main.memory.requests.size() == 1, "the cue reaches the memory line channel")
	var request: MEMORY.LineRequest = main.memory.requests[0]
	check(request.kind == MEMORY.LineKind.UTTERANCE, "the cue is an utterance")
	check(request.id == "fluttershy" and request.event_id == "evt1",
		"the cue carries the pony and act ids")
	check(not request.suffix.is_empty(), "the cue gets a unique suffix")
	check(request.purpose.contains("Cue: She wants it firmer."),
		"the prompt is formatted: %s" % request.purpose)
	check(request.purpose.contains("let it colour one short line"),
		"the cue seed is included")
	check(request.purpose.contains("[face:"), "the cue carries the face hint")
	check(request.valid.is_valid() and request.finished.is_valid(),
		"the cue carries its validity and completion callbacks")

	check(dialogue.recent_lines() == "I missed you. | Not so fast.",
		"the recent lines come from the director")
	check(dialogue.last_spoken_line() == "Not so fast.", "the last line is the newest")
	check(is_equal_approx(dialogue.last_spoken_at(), 12.5), "the last-spoken time is read")
	check(not dialogue.busy(), "an idle director is not busy")
	director.state = "speaking"
	check(dialogue.busy(), "a speaking director owns the channel")
	director.state = "idle"
	pony.speaking = true
	check(dialogue.busy(), "a speaking pony owns the channel")
	pony.speaking = false

	var reaction := dialogue.reaction_line(MEMORY.Reaction.CLIMAX, "evt1:climax",
		"The climax line.", DIALOGUE.Validity.new())
	check(reaction == "line:2", "a reaction line is queued through memory")
	check(main.memory.requests[1].kind == MEMORY.LineKind.REACTION,
		"the reaction carries its kind")
	dialogue.note_reaction(reaction, "She is climaxing.", 30.0)
	check(dialogue.scheduler().pending_key() == reaction,
		"the reaction takes the shared slot")

	dialogue.end_act("evt1")
	check(main.memory.cancel_act_calls == 1, "the act's lines are cancelled once")
	check(dialogue.scheduler().pending_key() == "", "the pending slot is dropped")

	# The idle history scan: a sincere apology repairs one point and writes one note.
	var mods := _mods()
	facts.state = 0
	var player := FakePony.new()
	player.name = "Player"
	root.add_child(player)
	WORLD.bind_player(player)
	facts.pony = pony
	mods.data["unfplap"]["act_history"] = {
		"fluttershy": {"hurt": 3, "last_apology_day": -1.0, "reminder_pending": false},
	}
	var history := DIALOGUE.new(facts)
	history.history_tick(0.0, pony, "fluttershy", "evt1", 100.0)
	director._turn_id = 3
	director._player_text = "I'm sorry"
	pony.conversation_target = player
	history.history_tick(1.1, pony, "fluttershy", "evt1", 100.0)
	var repair_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["fluttershy"]
	check(int(repair_row.get("hurt", 3)) == 2, "a sincere apology repairs one point")
	check(main.memory.notes.size() == 1, "the apology records a note")
	if not main.memory.notes.is_empty():
		check(int(main.memory.notes[0].get("kind", -1)) == MEMORY.NoteKind.APOLOGY,
			"the apology note carries its kind")

	# A pending reminder queues one line and is marked announced.
	var queued_before: int = main.memory.requests.size()
	mods.data["unfplap"]["act_history"] = {
		"fluttershy": {"hurt": 2, "last_at": 0.0, "reminder_pending": true,
			"complaint_pending": false},
	}
	history = DIALOGUE.new(facts)
	director._player_text = ""
	pony.conversation_target = null
	history.history_tick(1.1, pony, "fluttershy", "evt1", 100.0)
	check(main.memory.requests.size() == queued_before + 1, "a pending reminder queues one line")
	var reminder_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["fluttershy"]
	check(not bool(reminder_row.get("reminder_pending", true)),
		"the queued reminder is marked announced")

	# A busy scene queues no reminder.
	mods.data["unfplap"]["act_history"] = {
		"fluttershy": {"hurt": 2, "last_at": 0.0, "complaint_pending": true},
	}
	history = DIALOGUE.new(facts)
	director.state = "speaking"
	history.history_tick(1.1, pony, "fluttershy", "evt1", 100.0)
	check(main.memory.requests.size() == queued_before + 1, "a busy scene queues no reminder")
	director.state = "idle"

	print("ACT_DIALOGUE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_DIALOGUE_PASS")
	quit(0 if failures == 0 else 1)
