extends SceneTree
## Normal-dialogue notes that are not act lines: the after-sex warm note and the neutral
## lover wording. The live inspector print is covered by main/debug_actions, not here.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_runtime_notes.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const REL := preload("res://mods/unfplap/shared/relationship_cue.gd")
var failures := 0
var checks := 0


class FakePony extends Node3D:
	var identity: Variant


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var identity := {"id": "identity_id", "display_name": "Identity"}
	var pony := FakePony.new()
	pony.identity = identity
	root.add_child(pony)
	var id_runtime: Node = RUNTIME.new()
	id_runtime.pony = pony
	check(bool(id_runtime.call("_read_id")), "identity fallback reads a runtime id")
	check(str(id_runtime.get("_id")) == "identity_id", "identity id is the fallback")
	pony.set_meta("relationship_id", "rarity")
	id_runtime.call("_read_id")
	check(str(id_runtime.get("_id")) == "rarity", "relationship metadata wins when it appears")
	check(str(id_runtime.get("_display_name")) == "Identity", "display name is kept")
	id_runtime.free()

	var ready_pony := FakePony.new()
	ready_pony.identity = identity
	ready_pony.set_meta("relationship_id", "ready_id")
	root.add_child(ready_pony)
	var ready_runtime: Node = RUNTIME.new()
	ready_runtime.pony = ready_pony
	ready_pony.add_child(ready_runtime)
	await process_frame
	check(str(ready_runtime.get("_id")) == "ready_id", "a runtime reads its id on ready")
	check(str(ready_runtime.get("_display_name")) == "Identity",
		"a runtime keeps its display name on ready")
	ready_runtime.free()
	ready_pony.free()

	var runtime: Node = RUNTIME.new()
	runtime.state = 0 # IDLE
	runtime._face.warm_note = true
	var note := str(runtime.call("prompt_note"))
	check(note.contains("after making love with Anon"), "the warm note names the act")
	check(note.contains("warm") and note.contains("relaxed"), "the warm note is warm")
	check(not note.to_lower().contains("sex"), "the warm note has no bare sex word")
	runtime._face.warm_note = false
	runtime.free()

	check(REL.lover_note(true) == "- You and Anon are lovers.", "romantic lover note")
	check(REL.lover_note(false) == "- You are not Anon's lover.", "non-romantic lover note")
	check(not REL.lover_note(true).to_lower().contains("sex"),
		"the romantic lover note has no sex word")
	check(not REL.lover_note(false).to_lower().contains("sex"),
		"the non-romantic lover note has no sex word")

	print("RUNTIME_NOTES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_NOTES_PASS")
	quit(0 if failures == 0 else 1)
