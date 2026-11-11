extends Node
## The footstool system's entry: the standing reach rule, the case item, the act prop and the
## world supply. Other systems call this facade only; see docs/stool.md.

const MEASURE := preload("res://mods/unfplap/stool/measure.gd")
const ITEM := preload("res://mods/unfplap/stool/item.gd")
const PROP := preload("res://mods/unfplap/stool/prop.gd")
const SUPPLY := preload("res://mods/unfplap/stool/supply.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

const ID := ITEM.ID

var main: Node
var _supply: Node


func setup(main_node: Node) -> void:
	main = main_node
	if is_instance_valid(_supply):
		return
	_supply = SUPPLY.new()
	_supply.name = "UnfplapStoolSupply"
	_supply.call("setup", main_node, self)
	add_child(_supply)


func on_world(host: Node) -> void:
	if is_instance_valid(_supply):
		_supply.call("world_changed", host)


func on_world_closed() -> void:
	if is_instance_valid(_supply):
		_supply.call("reset")


func shutdown() -> void:
	if is_instance_valid(_supply):
		_supply.set_process(false)
		_supply.call("reset")
		_supply.queue_free()
		_supply = null
	main = null


func enabled() -> bool:
	return SETTINGS.standing_stool.get_bool()


func threshold_m() -> float:
	return SETTINGS.stool_gap_m.get_num()


func gap(her_opening_y: float, her_hoof_y: float, his_root_y: float,
		his_foot_y: float) -> float:
	return MEASURE.gap(her_opening_y, her_hoof_y, his_root_y, his_foot_y)


func required(gap_m: float) -> bool:
	return MEASURE.required(gap_m, threshold_m())


func case_slot(store: Variant) -> int:
	return ITEM.case_slot(store)


func owned_count(store: Variant) -> int:
	return ITEM.owned_count(store)


func free_slots(store: Variant) -> int:
	return ITEM.free_slots(store)


func writable(store: Variant) -> bool:
	return ITEM.writable(store)


func build_prop(host: Node, at: Vector3, yaw: float) -> Dictionary:
	return PROP.build(host, at, yaw)


func free_prop(prop: Variant) -> void:
	PROP.remove(prop)
