extends SceneTree
## The runtime's shared excitement Beat hold: named owners, one saved original, last release wins.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_hold.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var excitement: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _setup(paused := false, with_beat := true) -> Dictionary:
	var pony := FakePony.new()
	pony.name = "HoldPony"
	var excitement := Node.new()
	excitement.name = "Excitement"
	var beat: Timer = null
	if with_beat:
		beat = Timer.new()
		beat.name = "Beat"
		beat.paused = paused
		excitement.add_child(beat)
	pony.add_child(excitement)
	pony.excitement = excitement
	root.add_child(pony)
	var runtime := RUNTIME.new()
	runtime.pony = pony
	return {"pony": pony, "beat": beat, "runtime": runtime}


func _free(scene: Dictionary) -> void:
	var runtime: Variant = scene.get("runtime")
	if runtime is Node and is_instance_valid(runtime):
		(runtime as Node).free()
	var pony: Variant = scene.get("pony")
	if pony is Node and is_instance_valid(pony):
		(pony as Node).free()


func run() -> void:
	_check_last_release()
	_check_pre_paused()
	_check_duplicate_owner()
	_check_teardown_fallback()
	_check_missing_beat()
	print("INTEGRATIONS_HOLD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_last_release() -> void:
	var scene := _setup()
	var runtime: Variant = scene["runtime"]
	var beat: Timer = scene["beat"]
	runtime.call("_hold_excitement", "first")
	check(beat.paused, "the first hold pauses the Beat")
	runtime.call("_hold_excitement", "second")
	runtime.call("_release_excitement", "first")
	check(beat.paused, "one remaining owner keeps the Beat paused")
	runtime.call("_release_excitement", "second")
	check(not beat.paused, "the last release restores the Beat")
	_free(scene)


func _check_pre_paused() -> void:
	var scene := _setup(true)
	var runtime: Variant = scene["runtime"]
	var beat: Timer = scene["beat"]
	runtime.call("_hold_excitement", "first")
	runtime.call("_release_excitement", "first")
	check(beat.paused, "an already-paused Beat stays paused")
	_free(scene)


func _check_duplicate_owner() -> void:
	var scene := _setup()
	var runtime: Variant = scene["runtime"]
	var beat: Timer = scene["beat"]
	runtime.call("_hold_excitement", "same")
	runtime.call("_hold_excitement", "same")
	runtime.call("_release_excitement", "same")
	check(not beat.paused, "a repeated owner releases once")
	_free(scene)


func _check_teardown_fallback() -> void:
	var scene := _setup()
	var runtime: Variant = scene["runtime"]
	var beat: Timer = scene["beat"]
	runtime.call("_hold_excitement", "first")
	runtime.call("_hold_excitement", "second")
	runtime.call("_reset_excitement_hold")
	check(not beat.paused, "act teardown restores the Beat even with owners left")
	_free(scene)


func _check_missing_beat() -> void:
	var scene := _setup(false, false)
	var runtime: Variant = scene["runtime"]
	runtime.call("_hold_excitement", "first")
	runtime.call("_release_excitement", "first")
	check(true, "a missing Beat is a safe no-op")
	_free(scene)
