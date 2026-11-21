extends "res://mods/unfplap/tests/support/suite.gd"
## The runtime's live footstool gate: opening/part heights, threshold and case slot.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_gate.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const STORE := preload("res://world/inventory/inventory_store.gd")



class FakeController extends "res://mods/unfplap/anatomy/controller.gd":
	var opening_y := 1.25
	var entrance_calls := 0

	func entrance_point() -> Vector3:
		entrance_calls += 1
		return Vector3(0.0, opening_y, 0.0)

	func hole_point(_mix := 0.0) -> Vector3:
		return Vector3(0.0, opening_y, 0.0)


class FakeService extends "res://mods/unfplap/anatomy/service.gd":
	var root_y := 0.9
	var prepare_calls := 0

	func player_prepare() -> bool:
		prepare_calls += 1
		return true

	func player_root_now() -> Vector3:
		return Vector3(0.0, root_y, 0.0)


class FakeGame extends Node:
	var inventory: Node
	var headset_view := false


class FakeInventory extends Node:
	var inventory: Variant
	var held := {}
	var holding_case := ""


class FakeMain extends Node:
	var player: Node3D
	var game: Node
	var anatomy: Node
	var stool: Node
	var eligibility: Node


class FakeEligibility extends "res://mods/unfplap/tests/support/fakes/fake_eligibility.gd":
	pass


class TestPony extends Node3D:
	var sleeping := false
	var motion_paused := false
	var actual_speed := 0.0
	var skeleton: Variant = null

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true

	func action_interruption_reason() -> String:
		return ""

	func posture_status() -> Dictionary:
		return {"requested": "stand", "settled": true}


class FakeNav extends Node:
	var reserved_by := ""
	var command_owner := ""


func run() -> void:
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.standing_stool.set_bool(true)
	SETTINGS.stool_gap_m.set_num(0.20)
	SETTINGS.stool_height_m.set_num(0.20)
	var fake_eligibility := FakeEligibility.new()
	var main := FakeMain.new()
	var pony := TestPony.new()
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var player := Node3D.new()
	var game := FakeGame.new()
	var inventory := FakeInventory.new()
	var store = STORE.new()
	inventory.inventory = store
	game.inventory = inventory
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	main.anatomy = FakeService.new()
	main.stool = STOOL.new()
	PONIES.anatomy = main.anatomy
	PONIES.eligibility = fake_eligibility
	root.add_child(main)
	root.add_child(pony)
	root.add_child(player)
	root.add_child(game)
	root.add_child(inventory)
	var runtime: Node = RUNTIME.new(null, null, main.stool)
	runtime.pony = pony
	# The scene gate gets its body from the runtime's own refresh, as it does on the idle frame.
	runtime.act.refresh_gate()
	runtime._bundle.anatomy_bridge.controller = FakeController.new()
	var controller: Node = runtime._bundle.anatomy_bridge.controller
	controller.set("opening_y", 1.30)
	var stool: Variant = main.stool.new_act()
	stool.bind(main.stool, pony, player, controller)

	check(main.stool.enabled() == SETTINGS.standing_stool.get_bool(),
		"the facade reads the feature switch")
	check(stool.applies(), "the gate applies with anatomy and a human player")
	check(is_equal_approx(runtime.gate.stool_gap_m(), 0.40), "the live gap is 40 cm")
	check(runtime.gate.stool_needed_count() == 2, "40 cm needs two 20 cm steps")
	check(runtime.gate.stool_case_count() == 0, "no case footstool")
	controller.set("opening_y", 1.09)
	check(is_equal_approx(runtime.gate.stool_gap_m(), 0.19), "the live gap follows her opening")
	check(runtime.gate.stool_needed_count() == 0, "19 cm does not need a stool")
	controller.set("opening_y", 1.25)
	check(runtime.gate.stool_needed_count() == 1, "35 cm needs one 20 cm step")
	store.slots[0] = {"id": STOOL.ID, "count": 1}
	check(runtime.gate.stool_case_count() == 1, "one case footstool is counted")
	store.slots[1] = {"id": STOOL.ID, "count": 1}
	check(runtime.gate.stool_case_count() == 2, "two case footstools are counted")

	# Each hint scan reads the reach and Base clearance; a failed scene reads no Base clearance.
	var eligibility: FakeEligibility = fake_eligibility
	var anatomy_service: FakeService = main.anatomy
	var prepare_before: int = anatomy_service.prepare_calls
	var pair: Vector2i = runtime.gate.stool_pair("standing")
	check(runtime.gate.hotkey_ready("standing", "", null, pair), "the standing hint is ready")
	check(anatomy_service.prepare_calls == prepare_before + 1,
		"the hint reads the reach once")
	check(eligibility.eligible_calls == 1 and eligibility.relationship_calls == 1,
		"the hint reads Base clearance")
	var hint_stool: Dictionary = runtime.gate.hint_stool()
	check(int(hint_stool.get("need", -1)) == 1 and int(hint_stool.get("have", -1)) == 2,
		"the blocked note reuses the gate's reach and case count")
	check(anatomy_service.prepare_calls == prepare_before + 1,
		"the blocked note does not repeat the reach read")
	pair = runtime.gate.stool_pair("standing")
	check(runtime.gate.hotkey_ready("standing", "", null, pair), "the next hint scan stays ready")
	check(anatomy_service.prepare_calls == prepare_before + 2,
		"the next scan reads the reach again")
	check(eligibility.eligible_calls == 2 and eligibility.relationship_calls == 2,
		"the next scan reads Base clearance again")
	pony.set_meta("seated", true)
	check(not runtime.gate.hotkey_ready("standing", "", null, pair),
		"a seated pony fails the standing hint")
	check(eligibility.eligible_calls == 2,
		"a failed scene row reads no Base clearance")
	pony.remove_meta("seated")
	check(runtime.gate.hotkey_ready("standing", "", null, pair), "the standing hint recovers")
	check(eligibility.eligible_calls == 3,
		"the recovered scene reads Base clearance once")

	SETTINGS.anatomy_mode.set_choice("never")
	check(not stool.required(), "anatomy off disables the gate")
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.stool_gap_m.set_num(0.20)
	SETTINGS.stool_height_m.set_num(0.20)
	runtime.free()
	controller.free()
	PONIES.eligibility = null
	main.anatomy.free()
	main.stool.free()
	main.free()
	pony.free()
	player.free()
	game.free()
	inventory.free()
	SETTINGS.anatomy_mode.set_choice("never")

	finish()
