extends SceneTree
## The debug pony-preparation helper shared by the wheel's Bed cuddle and Sex ready actions.
## Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_debug_pony.gd
##
## Fake nodes only: the helper touches a pony's Navigator, CuddleSession, act metas and public
## posture state, never a game file.

const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")

var failures := 0
var checks := 0


class FakeNavigator extends Node:
	var command_owner := ""
	var reserved_by := ""
	var wander_enabled := true
	var _has_target := false
	var stayed := false

	func stay() -> void:
		stayed = true


class FakeSession extends Node:
	var enabled := false
	var blend := 0.0
	var ended := false

	func end(_immediate := false) -> void:
		ended = true
		enabled = false


class FakeRuntime extends Node:
	var state := 0


class FakePony extends Node3D:
	var velocity := Vector3.ZERO
	var motion_paused := false
	var requested := ""
	var requests := 0

	func posture_status() -> Dictionary:
		return {"requested": requested}

	func request_posture(name: String) -> void:
		requested = name
		requests += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_upright()
	_check_idle()
	_check_clear_busy()
	print("DEBUG_PONY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("DEBUG_PONY_PASS")
	quit(0 if failures == 0 else 1)


func _pony(name: String) -> FakePony:
	var pony := FakePony.new()
	pony.name = name
	root.add_child(pony)
	return pony


func _check_upright() -> void:
	var pony := _pony("Tilted")
	pony.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.35, 0.7, -0.2)) * Basis.from_scale(Vector3(1.2, 1.2, 1.2)),
		Vector3(4.0, 5.0, 6.0))
	pony.velocity = Vector3(1.0, 0.0, 0.0)
	DEBUG_PONY.upright(pony)
	var euler := pony.global_basis.get_euler()
	check(absf(euler.x) < 0.001 and absf(euler.z) < 0.001, "upright zeroes the tilt")
	check(absf(angle_difference(euler.y, 0.7)) < 0.001, "upright keeps the facing yaw")
	check(pony.global_basis.get_scale().is_equal_approx(Vector3(1.2, 1.2, 1.2)),
		"upright keeps the scale")
	check(pony.velocity == Vector3.ZERO, "upright stops the residual velocity")
	pony.free()


func _check_idle() -> void:
	var pony := _pony("Busy")
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	nav.command_owner = "life:graze"
	nav.reserved_by = "rest_spot"
	nav._has_target = true
	pony.add_child(nav)
	pony.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 1.1, 0.1)), Vector3.ZERO)
	pony.velocity = Vector3(2.0, 0.0, 0.0)
	pony.motion_paused = true
	pony.set_meta("active_follow", "player")
	var notes := DEBUG_PONY.idle(pony)
	check(nav.stayed, "idle stops the navigator")
	check(nav.command_owner == "", "idle clears the command owner")
	check(nav.reserved_by == "", "idle clears the reservation")
	check(not nav.wander_enabled, "idle disables wandering")
	check(not pony.has_meta("active_follow"), "idle removes the follow meta")
	check(not pony.motion_paused, "idle unpauses motion")
	check(pony.requested == "stand", "idle requests the standing pose")
	check(notes.contains("owner life:graze"), "idle reports the cleared owner")
	check(notes.contains("reserved rest_spot"), "idle reports the cleared reservation")
	check(notes.contains("stand requested"), "idle reports the posture request")
	check(absf(pony.global_basis.get_euler().x) < 0.001, "idle uprights the pony")
	pony.free()

	var clean := _pony("Clean")
	var clean_nav := FakeNavigator.new()
	clean_nav.name = "Navigator"
	clean.add_child(clean_nav)
	clean.requested = "stand"
	check(DEBUG_PONY.idle(clean) == "none", "a clean idle reports none")
	check(clean_nav.stayed, "a clean idle still stops the navigator")
	check(clean.requests == 0, "a pony already standing is not re-requested")
	clean.free()


func _check_clear_busy() -> void:
	var pony := _pony("Cuddled")
	var session := FakeSession.new()
	session.name = "CuddleSession"
	session.enabled = true
	session.blend = 0.4
	pony.add_child(session)
	pony.set_meta("couch_cuddle", true)
	pony.set_meta("cuddle_active", true)
	pony.set_meta("sex_aftercare", true)
	pony.set_meta("sex_active", true)
	var runtime := FakeRuntime.new()
	runtime.name = "UnfplapRuntime"
	runtime.state = 0
	pony.add_child(runtime)
	var notes := DEBUG_PONY.clear_busy(pony)
	check(session.ended, "clear_busy ends the live cuddle")
	check(not pony.has_meta("couch_cuddle"), "clear_busy clears couch_cuddle")
	check(not pony.has_meta("cuddle_active"), "clear_busy clears cuddle_active")
	check(not pony.has_meta("sex_aftercare"), "clear_busy clears sex_aftercare")
	check(not pony.has_meta("sex_active"), "clear_busy clears sex_active outside an act")
	check(notes.contains("cuddle ended"), "clear_busy reports the ended cuddle")
	pony.free()

	var live := _pony("Live")
	var live_runtime := FakeRuntime.new()
	live_runtime.name = "UnfplapRuntime"
	live_runtime.state = 1
	live.add_child(live_runtime)
	live.set_meta("sex_active", true)
	DEBUG_PONY.clear_busy(live)
	check(live.has_meta("sex_active"), "clear_busy never drops sex_active mid-act")
	live.free()

	var clean := _pony("Clean")
	check(DEBUG_PONY.clear_busy(clean) == "none", "a clean pony reports none")
	clean.free()
