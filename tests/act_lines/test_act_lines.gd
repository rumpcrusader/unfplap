extends SceneTree
## The act line facade: pacing configuration, cue admission, the memory line channel, reaction
## lines and the recent-line reads.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_lines/test_act_lines.gd

const LINES := preload("res://mods/unfplap/act_lines.gd")
const FACTS := preload("res://mods/unfplap/act_facts.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")

var failures := 0
var checks := 0


class FakeGame extends Node:
	pass


class FakeMemory extends Node:
	var requests: Array = []
	var states := {}
	var cancel_act_calls := 0
	var cancel_line_calls := 0

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

	func is_speaking() -> bool:
		return speaking


class FakeDirector extends Node:
	var state := "idle"
	var characters: Dictionary = {}


class Host extends RefCounted:
	var director: Node
	var clock := 0.0

	func get_director() -> Node:
		return director

	func clock_now() -> float:
		return clock


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var facts := FACTS.new()
	var main := FakeMain.new()
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
	facts.pose_id = "standing"
	facts.state = 2
	facts.mood = "warming"
	facts.cue = "She wants it firmer."
	facts.preferences = {
		"intensity": "soft", "pattern": "steady",
		"touch": [], "dislikes": [], "talk": [],
	}
	facts.act_prompts = {"cue": "Cue: {cue}. {seed}"}
	facts.features = {
		"act_lines": true, "act_faces": true, "act_line_angles": true,
		"act_speech_feel": false, "act_bystanders": true,
	}
	facts.director = Callable(host, "get_director")
	facts.now = Callable(host, "clock_now")

	var lines := LINES.new(facts)
	lines.setup(main)
	check(lines.scheduler() != null, "the facade owns a scheduler")
	lines.configure({
		"base_stable": 2.0, "override_stable": 0.5, "utterance_gap": 18.0,
		"demand_gap": 28.0, "demand_repeat": 45.0, "max_age": 20.0,
		"release_hold": 1.0,
	})
	check(is_equal_approx(lines.scheduler().base_stable_s, 2.0),
		"configure pushes the base stability")
	check(is_equal_approx(lines.scheduler().utterance_gap_s, 18.0),
		"configure pushes the shared gap")

	lines.reset(0.0, 12.0)
	check(lines.admit_cue(0.0) == "", "a fresh base cue waits for its stability")
	check(lines.admit_cue(2.1) != "", "a stable base cue is admitted")
	check(main.memory.requests.size() == 1, "the cue reaches the memory line channel")
	var request: MEMORY.LineRequest = main.memory.requests[0]
	check(request.kind == MEMORY.LineKind.UTTERANCE, "the cue is an utterance")
	check(request.id == "fluttershy" and request.event_id == "evt1",
		"the cue carries the pony and act ids")
	check(not request.suffix.is_empty(), "the cue gets a unique suffix")
	check(request.purpose.contains("Cue: She wants it firmer."),
		"the prompt is formatted: %s" % request.purpose)
	check(request.purpose.contains("private, not a script"),
		"the cue seed is included")
	check(request.valid.is_valid() and request.finished.is_valid(),
		"the cue carries its validity and completion callbacks")

	check(lines.recent_lines() == "I missed you. | Not so fast.",
		"the recent lines come from the director")
	check(lines.last_spoken_line() == "Not so fast.", "the last line is the newest")
	check(is_equal_approx(lines.last_spoken_at(), 12.5), "the last-spoken time is read")
	check(not lines.busy(), "an idle director is not busy")
	director.state = "speaking"
	check(lines.busy(), "a speaking director owns the channel")
	director.state = "idle"
	pony.speaking = true
	check(lines.busy(), "a speaking pony owns the channel")
	pony.speaking = false

	var reaction := lines.reaction_line(MEMORY.Reaction.CLIMAX, "evt1:climax",
		"The climax line.", Callable())
	check(reaction == "line:2", "a reaction line is queued through memory")
	check(main.memory.requests[1].kind == MEMORY.LineKind.REACTION,
		"the reaction carries its kind")
	lines.note_reaction(reaction, "She is climaxing.", 30.0)
	check(lines.scheduler().pending_key() == reaction,
		"the reaction takes the shared slot")

	lines.end_act("evt1")
	check(main.memory.cancel_act_calls == 1, "the act's lines are cancelled once")
	check(lines.scheduler().pending_key() == "", "the pending slot is dropped")

	print("ACT_LINES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_LINES_PASS")
	quit(0 if failures == 0 else 1)
