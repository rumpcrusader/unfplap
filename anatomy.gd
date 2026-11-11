extends Node
## The anatomy system's world facade. One service under `main` owns the per-pony controllers and,
## later, the player part and tail seating. Other systems call this facade, never a controller's
## internals.
##
## The per-pony controller is `anatomy/controller.gd`; the act handle is `anatomy_act.gd` until
## it moves under the same facade.
##
## See `docs/anatomy.md`.

const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")

var main: Node

## pony -> controller
var _controllers: Dictionary = {}


func setup(main_node: Node) -> void:
	main = main_node


## The live controller for a pony, created on first use. Runtime passes itself so the controller
## can read the act state, cycle and perf sink.
func controller_for(pony: Node, runtime: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var existing: Variant = _controllers.get(pony)
	if is_instance_valid(existing):
		return existing
	var controller: Node = CONTROLLER.new()
	controller.name = "UnfplapAnatomyController"
	add_child(controller)
	controller.call("setup", pony, runtime)
	_controllers[pony] = controller
	pony.tree_exiting.connect(func() -> void: detach_controller(pony))
	return controller


func bind(pony: Node, runtime: Node) -> Node:
	return controller_for(pony, runtime)


func controller(pony: Node) -> Node:
	var value: Variant = _controllers.get(pony)
	return value if is_instance_valid(value) else null


func online(pony: Node) -> bool:
	return is_instance_valid(controller(pony))


## Re-read settings and identity for every live controller.
func refresh_all() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("refresh"):
			controller.call("refresh")


func apply_live() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("apply_live"):
			controller.call("apply_live")


func detach_controller(pony: Node) -> void:
	var controller: Variant = _controllers.get(pony)
	_controllers.erase(pony)
	if not is_instance_valid(controller):
		return
	controller.call("detach")
	controller.queue_free()


func shutdown() -> void:
	for pony: Variant in _controllers.keys():
		if is_instance_valid(pony):
			var controller: Variant = _controllers[pony]
			if is_instance_valid(controller):
				controller.call("detach")
				controller.queue_free()
	_controllers.clear()
	main = null


# --------------------------------------------------------------------------- static identity

static func assets_exist() -> bool:
	return CONTROLLER.assets_exist()


static func selected_mare_bits_path() -> String:
	return CONTROLLER.selected_mare_bits_path()


static func eligible(pony_node: Node3D) -> bool:
	return CONTROLLER.eligible(pony_node)


static func pony_id(pony_node: Node) -> String:
	return CONTROLLER.pony_id(pony_node)


static func body_profile(identity: Variant) -> Array:
	return CONTROLLER.body_profile(identity)


static func off_roster_ids(ponies: Array, base_ids: Array) -> Array[String]:
	return CONTROLLER.off_roster_ids(ponies, base_ids)
