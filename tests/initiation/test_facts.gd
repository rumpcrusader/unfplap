extends SceneTree
## The typed request facts: defaults and the plain values the pure rules and wording read.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_facts.gd

const FACTS := preload("res://mods/unfplap/initiation/facts.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var request := FACTS.Request.new()
	check(request.pose == "", "a request starts with no pose")
	check(not request.cuddle and not request.private and not request.heat,
		"a request starts quiet and sober")
	check(request.face_note.is_empty() and request.relation_note.is_empty()
		and request.history_note.is_empty(), "a request starts with no prompt notes")

	request.pose = "standing"
	request.cuddle = true
	request.private = true
	request.heat = true
	request.face_note = " Face."
	request.relation_note = "You and Anon: friends."
	request.history_note = "You want to make it up to him."
	check(request.pose == "standing" and request.cuddle and request.private and request.heat,
		"the request carries its facts")
	check(request.face_note == " Face." and request.relation_note.contains("friends")
		and request.history_note.contains("make it up"), "the request carries its notes")

	var other := FACTS.Request.new()
	check(other.pose == "" and not other.private,
		"a second request is independent")

	print("INITIATION_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_FACTS_PASS")
	quit(0 if failures == 0 else 1)
