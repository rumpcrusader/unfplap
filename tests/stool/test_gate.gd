extends SceneTree
## The runtime's live footstool gate: opening/part heights, threshold and case slot.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_gate.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const STOOL := preload("res://mods/unfplap/stool.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const STORE := preload("res://world/inventory/inventory_store.gd")

var failures := 0
var checks := 0


class FakeController extends Node:
	var opening_y := 1.25

	func hole_point(_mix := 0.0) -> Vector3:
		return Vector3(0.0, opening_y, 0.0)


class FakeService extends Node:
	var root_y := 0.9

	func player_prepare() -> bool:
		return true

	func player_root_now() -> Vector3:
		return Vector3(0.0, root_y, 0.0)


class FakeGame extends Node:
	var inventory: Node
	var headset_view := false


class FakeInventory extends Node:
	var inventory: Variant


class FakeMain extends Node:
	var player: Node3D
	var game: Node
	var anatomy: Node
	var stool: Node


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.standing_stool.set_bool(true)
	SETTINGS.stool_gap_m.set_num(0.30)
	var main := FakeMain.new()
	var pony := Node3D.new()
	var player := Node3D.new()
	var game := FakeGame.new()
	var inventory := FakeInventory.new()
	var store = STORE.new()
	inventory.inventory = store
	game.inventory = inventory
	main.player = player
	main.game = game
	main.anatomy = FakeService.new()
	main.stool = STOOL.new()
	root.add_child(main)
	root.add_child(pony)
	root.add_child(player)
	root.add_child(game)
	root.add_child(inventory)
	var runtime: Node = RUNTIME.new()
	runtime.main = main
	runtime.pony = pony
	runtime.set("_anatomy", FakeController.new())

	check(runtime.stool_applies(), "the gate applies with anatomy and a human player")
	check(is_equal_approx(runtime.stool_gap_m(), 0.35), "the live gap is 35 cm")
	check(runtime.stool_required(), "35 cm needs a stool at a 30 cm threshold")
	check(runtime.stool_case_slot() == -1, "no case footstool")
	var controller: Node = runtime.get("_anatomy")
	controller.set("opening_y", 1.19)
	check(is_equal_approx(runtime.stool_gap_m(), 0.29), "the live gap follows her opening")
	check(not runtime.stool_required(), "29 cm does not need a stool")
	controller.set("opening_y", 1.25)
	store.slots[0] = {"id": STOOL.ID, "count": 1}
	check(runtime.stool_case_slot() == 0, "the case footstool is found")
	SETTINGS.anatomy_mode.set_choice("never")
	check(not runtime.stool_required(), "anatomy off disables the gate")
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.stool_gap_m.set_num(0.30)
	runtime.free()
	controller.free()
	main.anatomy.free()
	main.stool.free()
	main.free()
	pony.free()
	player.free()
	game.free()
	inventory.free()
	SETTINGS.anatomy_mode.set_choice("never")

	print("STOOL_GATE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
