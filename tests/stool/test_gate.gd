extends SceneTree
## The runtime's live footstool gate: opening/part heights, threshold and case slot.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_gate.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
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
	SETTINGS.stool_gap_m.set_num(0.20)
	SETTINGS.stool_height_m.set_num(0.20)
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
	runtime._anatomy_bridge.controller = FakeController.new()
	var controller: Node = runtime._anatomy_bridge.controller
	controller.set("opening_y", 1.30)

	check(runtime.stool_applies(), "the gate applies with anatomy and a human player")
	check(is_equal_approx(runtime.stool_gap_m(), 0.40), "the live gap is 40 cm")
	check(runtime.stool_needed_count() == 2, "40 cm needs two 20 cm steps")
	check(runtime.stool_case_count() == 0, "no case footstool")
	controller.set("opening_y", 1.09)
	check(is_equal_approx(runtime.stool_gap_m(), 0.19), "the live gap follows her opening")
	check(runtime.stool_needed_count() == 0, "19 cm does not need a stool")
	controller.set("opening_y", 1.25)
	check(runtime.stool_needed_count() == 1, "35 cm needs one 20 cm step")
	store.slots[0] = {"id": STOOL.ID, "count": 1}
	check(runtime.stool_case_count() == 1, "one case footstool is counted")
	# The idle blocked hint reuses the gate it already built instead of running it again.
	controller.set("opening_y", 1.30)
	var stool_only := ELIGIBILITY.Row.new()
	stool_only.key = "stool"
	stool_only.reason = "needs_stool"
	var verdict := {"rows": [stool_only]}
	check(runtime.stool_blocks_verdict(verdict),
		"the blocked hint reads the stool row from the first gate")
	var other := ELIGIBILITY.Row.new()
	other.key = "sleeping"
	other.ok = false
	other.reason = "sleeping"
	check(not runtime.stool_blocks_verdict({"rows": [stool_only, other]}),
		"another failed row still hides the stool hint")
	store.slots[1] = {"id": STOOL.ID, "count": 1}
	check(runtime.stool_case_count() == 2, "two case footstools are counted")
	SETTINGS.anatomy_mode.set_choice("never")
	check(not runtime.stool_required(), "anatomy off disables the gate")
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.stool_gap_m.set_num(0.20)
	SETTINGS.stool_height_m.set_num(0.20)
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
