extends SceneTree
## Normal-dialogue notes that are not act lines: the after-sex satisfied note and the neutral
## lover wording. The live inspector print is covered by main/debug_actions, not here.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_runtime_notes.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const REL := preload("res://mods/unfplap/relationship_cue.gd")
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
	var runtime: Node = RUNTIME.new()
	runtime.state = 0 # IDLE
	runtime._satisfied = Node.new()
	var note := str(runtime.call("prompt_note"))
	check(note.contains("after making love with Anon"), "the satisfied note names the act")
	check(note.contains("warm") and note.contains("relaxed"), "the satisfied note is warm")
	check(not note.to_lower().contains("sex"), "the satisfied note has no bare sex word")
	runtime._satisfied.free()
	runtime._satisfied = null
	runtime.free()

	check(REL.lover_note(true) == "- You and Anon are lovers.", "bonded lover note")
	check(REL.lover_note(false) == "- You are not Anon's lover.", "unbonded lover note")
	check(not REL.lover_note(true).to_lower().contains("sex"),
		"the bonded lover note has no sex word")
	check(not REL.lover_note(false).to_lower().contains("sex"),
		"the unbonded lover note has no sex word")

	print("RUNTIME_NOTES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_NOTES_PASS")
	quit(0 if failures == 0 else 1)
