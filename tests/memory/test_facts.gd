extends SceneTree
## The typed boundary data: the cue-facts dictionary and the memory hit's found flag.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_facts.gd

const FACTS := preload("res://mods/unfplap/memory/facts.gd")

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
	var witness := FACTS.Witness.new()
	check(witness.to_dict().has("distance"), "a witness row carries its distance")

	var facts := FACTS.CueFacts.new()
	var row := facts.to_dict()
	check(row.has("friendship") and row.has("love") and row.has("stage"), "the cue facts dict carries the ladder")
	check(row.has("anger") and row.has("mood"), "the cue facts dict carries the mood and anger")
	check(row.has("first_time") and row.has("careful"), "the cue facts dict carries the flags")

	var hit := FACTS.MemoryHit.new()
	check(not hit.found(), "an empty memory hit is not found")
	hit.text = "  "
	check(not hit.found(), "a whitespace memory hit is not found")
	hit.text = "We talked about the garden."
	check(hit.found(), "a real memory hit is found")

	print("MEMORY_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_FACTS_PASS")
	quit(0 if failures == 0 else 1)
