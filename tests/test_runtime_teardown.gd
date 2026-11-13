extends SceneTree
## Act exit paths: one teardown, every borrowed value restored, safe to call twice.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_runtime_teardown.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const CATALOG_STANDING := "standing"
var failures := 0
var checks := 0


class FakePony extends Node3D:
	var face_turn_rate := 0.45
	var sleeping := false
	var body_scale := 1.0
	var posture: Variant = null
	var expressions: Variant = null
	var posture_requests: Array[String] = []

	func posture_status() -> Dictionary:
		return {"requested": "stand", "settled": true}

	func request_posture(name: String) -> bool:
		posture_requests.append(name)
		return true


class FakeNav extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true

	func stay() -> void:
		pass


class FakePlayer extends Node3D:
	var _pitch := 0.0
	var _stand_eye := 1.6
	var _eye_height := 1.6
	var controls_locked := false
	var form_driver: Variant = null
	var seat: Variant = null
	var eye_pushes: Array[float] = []

	func eye_height() -> float:
		return _stand_eye

	func _set_eye_y(value: float) -> void:
		eye_pushes.append(value)


class FakeInventory extends RefCounted:
	var hud_hidden := false
	var hotbar: Variant = null
	var placed := 0

	func _place_hotbar() -> void:
		placed += 1


class FakeGame extends Node:
	var inventory: Variant = null
	var headset_view := false


class FakeMain extends Node:
	var player: Variant = null
	var hud: Variant = null
	var game: Variant = null
	var active_runtime: Variant = null
	var cleared: Array = []

	func clear_active(runtime: Node) -> void:
		cleared.append(runtime)

	func camera() -> Camera3D:
		return null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony: FakePony = FakePony.new()
	pony.posture = Node.new()
	pony.add_child(pony.posture)
	var nav: FakeNav = FakeNav.new()
	var player: FakePlayer = FakePlayer.new()
	var main: FakeMain = FakeMain.new()
	var game: FakeGame = FakeGame.new()
	game.inventory = FakeInventory.new()
	main.player = player
	main.game = game
	runtime.add_child(pony)
	runtime.add_child(nav)
	runtime.add_child(main)
	main.add_child(player)
	main.add_child(game)
	var hud: CanvasLayer = HUD.new()
	hud.name = "UnfplapHUD"
	main.add_child(hud)
	main.hud = hud
	runtime.pony = pony
	runtime.main = main
	runtime._id = "test_mare"
	runtime._hold.face_turn_rate_saved = 0.45
	runtime._hold.face_turn_rate_owned = true
	pony.face_turn_rate = 0.0
	runtime._hold.locked_player = true
	runtime._hold.had_kiss_hold = false
	player.set_meta("kiss_hold", true)
	pony.set_meta("sex_active", true)
	runtime._posture_owned = true
	runtime.pose_id = CATALOG_STANDING
	runtime.source = "test"
	runtime.state = 2
	runtime.toggle_auto_thrust()
	runtime._hold.nav = nav
	nav.command_owner = "unfplap:test_mare"
	nav.wander_enabled = false
	runtime._hold.nav_old_wander = false
	runtime._hold.token = "unfplap:test_mare"
	hud.set_inventory_hidden(true)
	return {"runtime": runtime, "pony": pony, "player": player, "main": main, "hud": hud}


func run() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var pony: FakePony = f["pony"]
	var player: FakePlayer = f["player"]
	var main: FakeMain = f["main"]
	var nav: FakeNav = runtime._hold.nav
	var inventory: FakeInventory = main.game.inventory

	runtime._end_session(false)
	check(pony.face_turn_rate == 0.45, "face-turn rate restored")
	check(not runtime._hold.face_turn_rate_owned, "face-turn ownership cleared")
	check(nav.command_owner == "", "navigator ownership released")
	check(nav.wander_enabled == false, "navigator gives back the saved wander flag")
	check(not runtime._hold.locked_player, "player lock released")
	check(not player.has_meta("kiss_hold"), "kiss hold removed when the act set it")
	check(not pony.has_meta("sex_active"), "sex_active cleared")
	check(not (f["hud"] as CanvasLayer).inventory_hidden(), "inventory HUD restored")
	check(not inventory.hud_hidden, "inventory hud_hidden restored")
	check(inventory.placed == 1, "inventory re-places the hotbar")
	check(pony.posture_requests.size() == 1 and pony.posture_requests[0] == "stand",
		"standing posture requested once")
	check(not runtime._posture_owned, "posture ownership cleared")
	check(not runtime.auto_active(), "teardown clears auto thrust")
	check(int(runtime.state) == 0, "state returns to IDLE")
	check(runtime.pose_id == "" and runtime.source == "" and runtime.bed == null,
		"act ids cleared")
	check(main.cleared.size() == 1 and main.cleared[0] == runtime, "main clears the active runtime")

	# A second teardown is a no-op, not a second restore.
	runtime._end_session(false)
	check(pony.face_turn_rate == 0.45, "double teardown keeps the saved face-turn rate")
	check(not pony.has_meta("sex_active"), "double teardown is safe")
	check(inventory.placed == 1, "double teardown does not re-place the hotbar")

	# A forced stop at IDLE must not touch the player's captured look.
	var f2 := _fixture()
	var runtime2: Node = f2["runtime"]
	var player2: FakePlayer = f2["player"]
	runtime2.state = 0
	runtime2._act_camera.look_captured = false
	player2.rotation.y = 0.7
	runtime2.force_stop()
	check(absf(player2.rotation.y - 0.7) < 0.0001,
		"IDLE force_stop leaves the player yaw alone")

	# A failed standing start restores the player eye height without a camera step.
	var f3 := _fixture()
	var runtime3: Node = f3["runtime"]
	var player3: FakePlayer = f3["player"]
	runtime3._act_camera.camera_owned = false
	runtime3._act_camera.look_captured = false
	runtime3._act_camera.eye_override = true
	runtime3._act_camera.saved_stand_eye = 1.6
	runtime3._act_camera.saved_eye_height = 1.6
	player3._stand_eye = 2.1
	player3._eye_height = 2.1
	runtime3._end_session(false)
	check(absf(player3._stand_eye - 1.6) < 0.0001, "aborted start restores the eye override")
	check(absf(player3._eye_height - 1.6) < 0.0001, "aborted start restores the eye height")

	# An invalid pony still releases the player, navigator and active runtime.
	var f4 := _fixture()
	var runtime4: Node = f4["runtime"]
	var main4: FakeMain = f4["main"]
	var nav4: FakeNav = runtime4._hold.nav
	runtime4.pony = null
	runtime4.state = 4
	runtime4._finish_restore()
	check(not runtime4._hold.locked_player, "invalid pony still unlocks the player")
	check(nav4.command_owner == "", "invalid pony still releases the navigator")
	check(int(runtime4.state) == 0, "invalid pony ends in IDLE")
	check(main4.cleared.size() == 1, "invalid pony still clears the active runtime")

	# Finalize is idempotent.
	var f5 := _fixture()
	var runtime5: Node = f5["runtime"]
	runtime5._finalize_session(false)
	check(runtime5._session_finalized, "finalize marks the session done")
	runtime5._finalize_session(false)
	check(runtime5._session_finalized, "double finalize is a no-op")

	# Desktop standing start keeps her in place and places Anon behind her; act end restores him.
	var f6 := _fixture()
	var runtime6: Node = f6["runtime"]
	root.add_child(runtime6)
	var pony6: FakePony = f6["pony"]
	var player6: FakePlayer = f6["player"]
	pony6.global_position = Vector3(3.0, 0.0, 4.0)
	pony6.rotation.y = 0.7
	player6.global_position = Vector3(3.0, 0.0, 5.0)
	player6.rotation.y = 0.1
	var pony_start: Transform3D = pony6.global_transform
	var player_start: Transform3D = player6.global_transform
	var standing6: Transform3D = runtime6.call("_begin_standing_placement")
	check(pony6.global_transform.is_equal_approx(pony_start),
		"standing start keeps her in place")
	check(standing6.origin.is_equal_approx(pony6.global_position),
		"standing act transform uses her position")
	var gap6: float = float(runtime6.call("_standing_gap"))
	var behind6: Vector3 = pony6.global_position + pony6.global_basis.z.normalized() * gap6
	behind6.y = player_start.origin.y
	check(player6.global_position.is_equal_approx(behind6),
		"standing start places Anon behind her at the act gap")
	var placed6: Transform3D = player6.global_transform
	var placed_yaw6 := player6.rotation.y
	runtime6._act_camera.look_captured = true
	runtime6._act_camera.look_restore_yaw = false
	runtime6.call("_restore_look")
	check(player6.global_position.is_equal_approx(placed6.origin),
		"standing end leaves Anon in place")
	check(is_equal_approx(player6.rotation.y, placed_yaw6),
		"standing end leaves Anon's yaw alone")

	# An idle sibling runtime must not take the borrowed quick slots from the act.
	var f7 := _fixture()
	var idle7: Node = f7["runtime"]
	var main7: FakeMain = f7["main"]
	var hud7: CanvasLayer = f7["hud"]
	var acting7: Node = RUNTIME.new()
	acting7.main = main7
	acting7.state = 2 # ACTIVE
	main7.active_runtime = acting7
	idle7.call("_restore_stray_inventory_hud")
	check(hud7.inventory_hidden(), "idle sibling leaves the active act's inventory HUD hidden")
	acting7.state = 0 # IDLE
	idle7.call("_restore_stray_inventory_hud")
	check(not hud7.inventory_hidden(), "idle safety restores the HUD once no act is active")
	hud7.set_inventory_hidden(true)
	main7.active_runtime = null
	idle7.call("_restore_stray_inventory_hud")
	check(not hud7.inventory_hidden(), "idle safety restores the HUD with no active runtime")
	acting7.free()

	for item: Dictionary in [f, f2, f3, f4, f5, f6, f7]:
		(item["runtime"] as Node).free()
	print("RUNTIME_TEARDOWN_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_TEARDOWN_PASS")
	quit(0 if failures == 0 else 1)