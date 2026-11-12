extends SceneTree
## The director line channel: the typed line state, the keep-active cancel and the cancel prefix.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_dialogue.gd

const MEMORY := preload("res://mods/unfplap/memory.gd")

var failures := 0
var checks := 0


class FakeMain extends Node:
	var game: Node


class FakeDirector extends Node:
	var _authored_lines = {}
	var _authored_active := ""
	var state := "idle"
	var cancelled: Array = []

	func queue_generated_intent(_id: String, _intent: String, key: String,
			_valid: Callable, _finished: Callable, _once := false, _firm := false) -> bool:
		_authored_lines[key] = {"started": false, "delivered": false, "heard": []}
		return true

	func cancel_authored_line(key: String) -> void:
		cancelled.append(key)
		_authored_lines.erase(key)


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var director := FakeDirector.new()
	director.add_to_group("conversation_director")
	root.add_child(director)
	var main := FakeMain.new()
	main.game = director
	root.add_child(main)
	var memory := MEMORY.new()
	memory.setup(main)

	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.UTTERANCE
	request.id = "fluttershy"
	request.event_id = "act"
	request.suffix = "climax"
	request.purpose = "Say something."
	request.valid = func() -> bool: return true
	var line := memory.line(request)
	check(line.queued, "the line is accepted")
	check(line.key == "unfplap:act:line:climax", "director key format")
	var key := line.key

	check(memory.line_state(key) == MEMORY.LineState.QUEUED, "an unclaimed row is queued")

	director._authored_lines[key] = {"started": true, "delivered": false}
	director._authored_active = "other"
	check(memory.line_state(key) == MEMORY.LineState.QUEUED,
		"a started row without the active key is safe to cancel")

	director._authored_active = key
	director.state = "thinking"
	check(memory.line_state(key) == MEMORY.LineState.GENERATING, "thinking row is generating")
	director.state = "rendering"
	check(memory.line_state(key) == MEMORY.LineState.GENERATING,
		"rendering before any heard sentence is generating")

	director._authored_lines[key]["heard"] = ["one sentence"]
	check(memory.line_state(key) == MEMORY.LineState.SPEAKING,
		"a multi-sentence line between beats is speaking")
	director.state = "speaking"
	check(memory.line_state(key) == MEMORY.LineState.SPEAKING, "speaking state is speaking")

	director._authored_lines[key]["delivered"] = true
	director._authored_active = ""
	check(memory.line_state(key) == MEMORY.LineState.DELIVERED, "delivered row is delivered")

	director._authored_lines.erase(key)
	check(memory.line_state(key) == MEMORY.LineState.ABSENT, "erased row is absent")

	director._authored_lines = null
	check(memory.line_state(key) == MEMORY.LineState.UNKNOWN,
		"unreadable queue is unknown")

	director._authored_lines = {}
	director._authored_lines["unfplap:act:line:speaking"] = {"started": true, "delivered": false}
	director._authored_lines["unfplap:act:line:queued"] = {"started": false, "delivered": false}
	director._authored_lines["unfplap:other:line:queued"] = {"started": false, "delivered": false}
	director._authored_active = "unfplap:act:line:speaking"
	director.state = "speaking"
	director.cancelled.clear()
	var cancelled := memory.cancel_act("act", true)
	check(cancelled == 1, "cancel_act keeps the speaking line and drops the queued one")
	check(not "unfplap:act:line:speaking" in director.cancelled, "cancel_act keeps the speaking line")
	check("unfplap:act:line:queued" in director.cancelled, "cancel_act drops the queued line")
	check(not "unfplap:other:line:queued" in director.cancelled, "cancel_act leaves another act alone")

	director._authored_lines["unfplap:act:line:speaking"] = {"started": true, "delivered": false}
	director.cancelled.clear()
	cancelled = memory.cancel_act("act", false)
	check(cancelled == 1, "cancel_act with keep_speaking false drops the speaking line")
	check("unfplap:act:line:speaking" in director.cancelled, "cancel-all drops the speaking line")

	director._authored_lines["unfplap:act:line:queued"] = {"started": false, "delivered": false}
	director.cancelled.clear()
	memory.cancel_line("unfplap:act:line:queued")
	check("unfplap:act:line:queued" in director.cancelled, "cancel_line drops one line")

	main.queue_free()
	director.queue_free()

	print("MEMORY_DIALOGUE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_DIALOGUE_PASS")
	quit(0 if failures == 0 else 1)
