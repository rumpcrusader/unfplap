extends SceneTree
## The per-act footstool handle: the reach rule, the case loans, the placed stack and the release.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_act.gd

const ACT := preload("res://mods/unfplap/stool/act.gd")
const ITEM := preload("res://mods/unfplap/stool/item.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const STORE := preload("res://world/inventory/inventory_store.gd")

var failures := 0
var checks := 0


class FakeFacade extends RefCounted:
	var gap_value := 0.40
	var need := 2
	var threshold := 0.20
	var height := 0.20
	var built: Array = []
	var freed: Array = []

	func gap(_opening: float, _hoof: float, _root: float, _foot: float) -> float:
		return gap_value

	func needed_count(_gap: float) -> int:
		return need

	func threshold_m() -> float:
		return threshold

	func height_m() -> float:
		return height

	func writable(_store: Variant) -> bool:
		return true

	func case_slot(store: Variant) -> int:
		return ITEM.case_slot(store)

	func case_count(store: Variant) -> int:
		return ITEM.case_count(store)

	func owned_count(_store: Variant) -> int:
		return 2

	func free_slots(_store: Variant) -> int:
		return 1

	func build_prop(_host: Variant, at: Vector3, _yaw: float, _count: int, _step: float,
			_ignore: PhysicsBody3D = null) -> Dictionary:
		var node := Node3D.new()
		node.name = "FakeStool"
		built.append(node)
		return {"node": node, "height": 0.4, "count": 2, "step": 0.2, "at": at}

	func free_prop(node: Variant) -> void:
		freed.append(node)
		if node is Node:
			(node as Node).queue_free()

	func floor_y_at(_at: Vector3, _body: Variant) -> float:
		return 0.0


class FakeController extends Node:
	var opening_y := 1.30

	func hole_point(_mix := 0.0) -> Vector3:
		return Vector3(0.0, opening_y, 0.0)


class FakeService extends Node:
	func player_prepare() -> bool:
		return true

	func player_root_now() -> Vector3:
		return Vector3(0.0, 0.9, 0.0)


class FakeGame extends Node:
	var inventory: Variant = null
	var headset_view := false


class FakeInventory extends Node:
	var inventory: Variant = null


class FakeMain extends Node:
	var player: Variant = null
	var game: Variant = null
	var anatomy: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	SETTINGS.anatomy_mode.set_choice("always")
	SETTINGS.standing_stool.set_bool(true)
	var facade := FakeFacade.new()
	var pony := Node3D.new()
	var player := Node3D.new()
	var main := FakeMain.new()
	var game := FakeGame.new()
	var inventory := FakeInventory.new()
	var store = STORE.new()
	inventory.inventory = store
	game.inventory = inventory
	main.player = player
	main.game = game
	main.anatomy = FakeService.new()
	var ctl := FakeController.new()
	root.add_child(main)
	root.add_child(pony)
	root.add_child(player)
	root.add_child(game)
	root.add_child(inventory)
	var act: RefCounted = ACT.new()
	act.bind(facade, main, pony, player, ctl)
	return {
		"act": act, "facade": facade, "pony": pony, "player": player, "main": main,
		"game": game, "inventory": inventory, "store": store, "ctl": ctl,
	}


func _free(made: Dictionary) -> void:
	SETTINGS.anatomy_mode.set_choice("never")
	var pony: Node3D = made["pony"]
	var player: Node3D = made["player"]
	var main: FakeMain = made["main"]
	var game: FakeGame = made["game"]
	var inventory: FakeInventory = made["inventory"]
	var ctl: FakeController = made["ctl"]
	root.remove_child(pony)
	pony.free()
	root.remove_child(player)
	player.free()
	game.free()
	inventory.free()
	main.anatomy.free()
	root.remove_child(main)
	main.free()
	ctl.free()


func run() -> void:
	_check_rule()
	_check_items()
	_check_place_release()
	_check_blocks()

	print("STOOL_ACT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("STOOL_ACT_PASS")
	quit(0 if failures == 0 else 1)


func _check_rule() -> void:
	var made := _fixture()
	var act: RefCounted = made["act"]
	check(bool(act.call("applies")), "the rule applies with anatomy and a human player")
	check(is_equal_approx(float(act.call("gap_m")), 0.40), "the fake facade gap reaches the handle")
	check(int(act.call("needed_count")) == 2, "the facade step count reaches the handle")
	check(bool(act.call("required")), "a positive step count is required")
	var text := str(act.call("state_text"))
	check(text.contains("need=2") and text.contains("active=false"),
		"the debug row reports the need and the inactive stack")
	var no_ctl := _fixture()
	(no_ctl["act"] as RefCounted).anatomy_ctl = null
	check(not bool((no_ctl["act"] as RefCounted).call("applies")),
		"a missing anatomy controller makes the rule inapplicable")
	_free(no_ctl)
	(made["facade"] as FakeFacade).gap_value = 0.1
	(made["facade"] as FakeFacade).need = 0
	check(not bool(act.call("required")), "a below-threshold gap needs no stool")
	_free(made)


func _check_items() -> void:
	var made := _fixture()
	var act: RefCounted = made["act"]
	var store = made["store"]
	check(int(act.call("case_slot")) == -1, "an empty case has no slot")
	check(int(act.call("case_count")) == 0, "an empty case has no footstool")
	store.slots[0] = {"id": ITEM.ID, "count": 1}
	store.slots[1] = {"id": ITEM.ID, "count": 1}
	check(int(act.call("case_count")) == 2, "two case footstools are counted")
	check(int(act.call("case_slot")) == 0, "the first footstool slot is found")
	check(bool(act.call("take_items", 2)), "two units are checked out")
	check(bool(act.get("active")) and int(act.get("count")) == 2,
		"the act marks the stack active and counted")
	check((act.get("tokens") as Array).size() == 2, "every unit keeps its token")
	check(int(act.call("case_count")) == 0, "the checked-out units leave the case")
	act.call("release")
	check(int(act.call("case_count")) == 2, "the release puts both units back")
	check(not bool(act.get("active")), "the release ends the stack")
	check(not bool(act.call("take_items", 3)), "a short case cannot take three units")
	check((act.get("tokens") as Array).is_empty(), "a failed take gives back what it took")
	_free(made)


func _check_place_release() -> void:
	var made := _fixture()
	var act: RefCounted = made["act"]
	var store = made["store"]
	var player: Node3D = made["player"]
	store.slots[0] = {"id": ITEM.ID, "count": 1}
	store.slots[1] = {"id": ITEM.ID, "count": 1}
	check(bool(act.call("take_items", 2)), "the placement fixture takes two units")
	var target := Vector3(1.0, 0.5, 2.0)
	var raised: Vector3 = act.call("place", target, 0.0, 0.0)
	check(is_equal_approx(raised.y, 0.405), "placing the stack raises the player target")
	check(int(act.call("case_count")) == 0, "placing keeps the checked-out units")
	check(is_instance_valid(act.get("node")), "the placed prop is kept")
	check((made["facade"] as FakeFacade).built.size() == 1, "the facade built one stack")
	player.global_position = Vector3(1.0, 0.4, 2.0)
	act.call("release")
	check((made["facade"] as FakeFacade).freed.size() == 1, "the release frees the stack")
	check(act.get("node") == null, "the release drops the prop handle")
	check(is_equal_approx(player.global_position.y, 0.002), "the release lowers the player")
	check(int(act.call("case_count")) == 2, "the release returns the units")
	check(not bool(act.get("failed")), "a good release clears the failure flag")
	act.call("take_items", 1)
	act.call("reset")
	check(not bool(act.get("active")) and int(act.get("count")) == 0,
		"the reset clears a half-started act")
	check(int(act.call("case_count")) == 2, "the reset returns a half-started loan")
	_free(made)


func _check_blocks() -> void:
	var made := _fixture()
	var act: RefCounted = made["act"]
	var store = made["store"]
	store.slots[0] = {"id": ITEM.ID, "count": 1}
	check(bool(act.call("blocks_start", PackedStringArray(["needs_stool"]))),
		"a missing stool with a need blocks")
	(made["facade"] as FakeFacade).need = 0
	check(not bool(act.call("blocks_start", PackedStringArray(["needs_stool"]))),
		"no required stack never blocks")
	(made["facade"] as FakeFacade).need = 2
	check(not bool(act.call("blocks_start",
		PackedStringArray(["needs_stool", "player"]))),
		"another failing reason owns the block")
	check(not bool(act.call("blocks_start", PackedStringArray())),
		"no failing reasons never blocks on the stool")
	store.slots[1] = {"id": ITEM.ID, "count": 1}
	check(not bool(act.call("blocks_start", PackedStringArray(["needs_stool"]))),
		"enough case stools do not block")
	_free(made)
