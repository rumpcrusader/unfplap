extends RefCounted
## The bound inventory node: its briefcase store, world drops, shop scene and quick-slot HUD.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _inventory: Node


func _init(inventory: Node) -> void:
	_inventory = inventory


func _bound() -> Node:
	return _inventory


## The inventory's briefcase store; null without one.
func store() -> Object:
	return GAME.case_store(_inventory)


## A typed copy of the store's slot rows.
func slots(store: Object) -> Array[Dictionary]:
	return GAME.case_slots(store)


## A typed copy of the store's checked-out loans.
func loans(store: Object) -> Array[Dictionary]:
	return GAME.case_loans(store)


## Whether the store accepts writes.
func writable(store: Object) -> bool:
	return GAME.case_writable(store)


## The units a slot can give right now; -1 without the op.
func available(store: Object, slot: int) -> int:
	return GAME.case_available(store, slot)


## Take one unit out; the loan token, empty when it refuses.
func take(store: Object, slot: int) -> String:
	return GAME.case_take(store, slot)


## Put a loaned token back at a slot, else anywhere; false when it refuses.
func put(store: Object, token: String, slot: int) -> bool:
	return GAME.case_put(store, token, slot)


## Add units of one item; the slot used, -1 when they do not fit.
func grant(store: Object, id: String, count: int) -> int:
	return GAME.case_grant(store, id, count)


## Drop an owned copy of an item into the world at a pose.
func spawn_drop(id: String, pose: Transform3D) -> Node:
	return GAME.spawn_owned_drop(_inventory, id, pose)


## The shop's packed item scene; null when it has no such item.
func item_scene(id: String) -> PackedScene:
	return GAME.shop_item_scene(id)


## How many item rows the inventory holds; 0 without one.
func held_count() -> int:
	return GAME.inventory_held_count(_inventory)


## The item id the inventory holds as a case; empty when it holds none.
func holding_case() -> String:
	return GAME.inventory_holding_case(_inventory)


## The inventory's quick-slot bar; null without one.
func hotbar() -> Node:
	return GAME.hotbar(_inventory)


## Whether a quick-slot bar is on screen.
func hotbar_visible(bar: Node) -> bool:
	return GAME.hotbar_visible(bar)


## Show or hide a quick-slot bar.
func set_hotbar_visible(bar: Node, visible: bool) -> void:
	GAME.set_hotbar_visible(bar, visible)


## The canvas layer a quick-slot bar draws on; null without one.
func hotbar_layer(bar: Node) -> CanvasLayer:
	return GAME.hotbar_hud_layer(bar)


## Show or hide a quick-slot bar's own HUD layer.
func set_hotbar_layer_visible(bar: Node, visible: bool) -> void:
	GAME.set_hotbar_hud_visible(bar, visible)


## Re-place the inventory's quick slots after its HUD flag changes.
func place_hotbar() -> void:
	GAME.inventory_place_hotbar(_inventory)


## Whether the quick-slot card is currently hidden.
func hud_hidden() -> bool:
	return GAME.inventory_hud_hidden(_inventory)


## Hide or restore the inventory's quick-slot card.
func set_hud_hidden(hidden: bool) -> void:
	GAME.set_inventory_hud_hidden(_inventory, hidden)
