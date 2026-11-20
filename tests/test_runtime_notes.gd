extends SceneTree
## Normal-dialogue notes that are not act lines: the after-sex warm note. The live inspector
## print is covered by main/debug_actions, not here.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_runtime_notes.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
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
	check(bool(id_runtime.act.refresh_identity()), "identity fallback reads a runtime id")
	check(str(id_runtime.act.pony_id) == "identity_id", "identity id is the fallback")
	pony.set_meta("relationship_id", "rarity")
	id_runtime.act.refresh_identity()
	check(str(id_runtime.act.pony_id) == "rarity", "relationship metadata wins when it appears")
	check(str(id_runtime.act.display_name) == "Identity", "display name is kept")
	id_runtime.free()

	var ready_pony := FakePony.new()
	ready_pony.identity = identity
	ready_pony.set_meta("relationship_id", "ready_id")
	root.add_child(ready_pony)
	var ready_runtime: Node = RUNTIME.new()
	ready_runtime.pony = ready_pony
	ready_pony.add_child(ready_runtime)
	await process_frame
	check(str(ready_runtime.act.pony_id) == "ready_id", "a runtime reads its id on ready")
	check(str(ready_runtime.act.display_name) == "Identity",
		"a runtime keeps its display name on ready")
	ready_runtime.free()
	ready_pony.free()

	var runtime: Node = RUNTIME.new()
	runtime.act._set_state(0) # IDLE
	runtime._bundle.face.warm_note = true
	var note := str(runtime.act.prompt_note())
	check(not note.is_empty(), "the warm note is produced after making love")
	runtime._bundle.face.warm_note = false
	check(str(runtime.act.prompt_note()).is_empty(), "an ordinary idle note is empty")
	runtime.free()

	print("RUNTIME_NOTES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_NOTES_PASS")
	quit(0 if failures == 0 else 1)
