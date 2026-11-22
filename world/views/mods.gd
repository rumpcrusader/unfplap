extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## The game's mods registry, with the autoload host already bound.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _host: Node


func _init(host: Node) -> void:
	_host = host


func _bound() -> Node:
	return _host


## The host as the accessor may take it: a freed registry is the same as no registry.
func _host_node() -> Node:
	return _host if is_instance_valid(_host) else null


## One mod's live section, as the registry keeps the dictionary; empty rows without a reader.
func state(id: String) -> GAME.ModState:
	return GAME.mods_state(_host_node(), id)


## Whether the registry reports one mod installed and enabled.
func active(id: String) -> bool:
	return GAME.mod_active(_host_node(), id)


## Ask the registry to persist its state; nothing is saved without its writer.
func save() -> void:
	GAME.mods_save(_host_node())


## The registry's installed pack rows, as a typed copy.
func list() -> Array[Dictionary]:
	return GAME.mods_list(_host_node())


## One mod's data folder; empty when the host cannot name one.
func data_folder(id: String) -> String:
	return GAME.mods_data_folder(_host_node(), id)
