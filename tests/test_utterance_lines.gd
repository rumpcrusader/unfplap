extends SceneTree
## Line-state tests for the base-game intent queue bridge.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_utterance_lines.gd

const MEMORY := preload("res://mods/unfplap/memory.gd")
var failures := 0
var checks := 0


class FakeMain extends Node:
	var game: Node


class FakeDirector:
	extends Node
	var _authored_lines = {}
	var _authored_active := ""
	var state := "idle"

	func cancel_authored_line(_key: String) -> void:
		pass


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
	var key := MEMORY.mod_key("act", "reply", "climax")
	check(key == "unfplap:act:reply:climax", "director key format")

	check(memory.line_state(key) == "absent", "missing row is absent")
	director._authored_lines[key] = {"started": false, "delivered": false}
	check(memory.line_state(key) == "queued", "unclaimed row is queued")

	director._authored_lines[key] = {"started": true, "delivered": false}
	director._authored_active = "other"
	check(memory.line_state(key) == "queued",
		"a started row without the active key is safe to cancel")

	director._authored_active = key
	director.state = "thinking"
	check(memory.line_state(key) == "generating", "thinking row is generating")
	director.state = "rendering"
	check(memory.line_state(key) == "generating",
		"rendering before any heard sentence is generating")

	director._authored_lines[key]["heard"] = ["one sentence"]
	check(memory.line_state(key) == "speaking",
		"a multi-sentence line between beats is speaking")
	director.state = "speaking"
	check(memory.line_state(key) == "speaking", "speaking state is speaking")

	director._authored_lines[key]["delivered"] = true
	director._authored_active = ""
	check(memory.line_state(key) == "delivered", "delivered row is delivered")

	director._authored_lines.erase(key)
	check(memory.line_state(key) == "absent", "erased row is absent")

	director._authored_lines = null
	check(memory.line_state(key) == "unknown",
		"unreadable queue is unknown")

	main.queue_free()
	director.queue_free()

	print("UTTERANCE_LINES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("UTTERANCE_LINES_PASS")
	quit(0 if failures == 0 else 1)
