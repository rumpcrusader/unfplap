extends SceneTree
## The held post-act mood face: table, duration and the line-face yield/clear rule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_mood_face.gd

const MOOD_FACE := preload("res://mods/unfplap/mood_face.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
var checks := 0
var failures := 0


class FakeExpressions extends Node:
	var dialogue_face := ""
	var set_calls := 0
	var clear_calls := 0

	func set_dialogue(value: String) -> void:
		dialogue_face = value
		set_calls += 1

	func clear_dialogue() -> void:
		dialogue_face = ""
		clear_calls += 1

	func finish_dialogue(_delay := 3.0) -> void:
		pass


class FakePony extends Node3D:
	var expressions: Variant = null
	var boop_node: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fake() -> Dictionary:
	var pony := FakePony.new()
	var expressions := FakeExpressions.new()
	pony.add_child(expressions)
	pony.expressions = expressions
	root.add_child(pony)
	return {"pony": pony, "expressions": expressions}


func run() -> void:
	check(MOOD_FACE.DURATION == 300.0, "mood face matches the 300 s freshness")
	check(MOOD_FACE.MOOD_FACES.size() == 10, "all ten moods are mapped")
	for mood: String in MOOD_FACE.MOOD_FACES:
		var face := str(MOOD_FACE.MOOD_FACES[mood])
		check(face.is_empty() or ACT_FACE.valid_face(face), "valid mood face %s" % mood)

	var f := _fake()
	var pony: Node3D = f["pony"]
	var expressions: FakeExpressions = f["expressions"]
	var node: Node = MOOD_FACE.new()
	node.set("pony", pony)
	node.set("face", "relaxed")
	node.set("mood", "")
	node.set("blush", 0.0)
	root.add_child(node)
	node.set_physics_process(false)
	check(expressions.dialogue_face == "relaxed", "mood face applies on start")
	check(expressions.set_calls >= 1, "mood face sets the face once")

	expressions.dialogue_face = "happy"
	node.call("_physics_process", 0.1)
	check(expressions.dialogue_face == "happy", "mood face yields to a spoken line")

	expressions.dialogue_face = ""
	node.call("_physics_process", 0.1)
	check(expressions.dialogue_face == "relaxed", "mood face returns after the line")

	node.call("_finish", "test")
	check(expressions.dialogue_face == "", "mood face clears only its own face")
	check(expressions.clear_calls == 1, "mood face clears once")

	var g := _fake()
	var pony2: Node3D = g["pony"]
	var expressions2: FakeExpressions = g["expressions"]
	var node2: Node = MOOD_FACE.new()
	node2.set("pony", pony2)
	node2.set("face", "relaxed")
	node2.set("mood", "")
	node2.set("blush", 0.0)
	root.add_child(node2)
	node2.set_physics_process(false)
	expressions2.dialogue_face = "happy"
	node2.call("_finish", "test")
	check(expressions2.dialogue_face == "happy", "mood face never clears another owner's face")

	if is_instance_valid(node):
		node.queue_free()
	if is_instance_valid(node2):
		node2.queue_free()
	pony.queue_free()
	pony2.queue_free()

	print("MOOD_FACE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MOOD_FACE_PASS")
	quit(0 if failures == 0 else 1)
