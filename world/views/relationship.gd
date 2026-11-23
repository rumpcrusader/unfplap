extends RefCounted
## The scene's relationship runtime and its bond store, with the runtime already bound.

const GAME := preload("res://mods/unfplap/world/game.gd")
const BOND_RECORD := preload("res://mods/unfplap/shared/bond_record.gd")

var _runtime: Node


func _init(runtime: Node) -> void:
	_runtime = runtime


func _bound() -> Node:
	return _runtime


## The runtime as the accessor may take it: a freed runtime is the same as no runtime.
func _runtime_node() -> Node:
	return _runtime if is_instance_valid(_runtime) else null


## The scene's relationship runtime; null when the scene has none.
func runtime() -> Node:
	return _runtime_node()


## The runtime's bond store; null when it keeps none.
func bonds() -> Object:
	return GAME.relationship_bonds(_runtime_node())


## Her friendship and love ladder as a typed view; an empty view without a reader.
func ladder(id: String) -> GAME.Ladder:
	return GAME.relationship_ladder(_runtime_node(), id)


## Her love stage name, or `?` while no ladder answers.
func love_name(pony: Node, id: String) -> String:
	return GAME.relationship_love_name(pony, id)


## The bond store a pony carries; null without a runtime or a store.
func bonds_of(pony: Node) -> Object:
	return GAME.bonds_of(pony)


## One bond record through the store's reader, as a typed record.
func record(store: Object, id: String) -> BOND_RECORD:
	return GAME.bond_record_for(store, id)


## Whether the store calls one pony romance-eligible; false without its op.
func eligible_for_romance(store: Object, id: String) -> bool:
	return GAME.bond_eligible_for_romance(store, id)


## Whether the store accepts one kind of advance from her; false without its op.
func welcomes(store: Object, id: String, kind: String) -> bool:
	return GAME.bond_welcomes(store, id, kind)


## The store's world day; NAN when it keeps no clock.
func day(store: Object) -> float:
	return GAME.bond_day(store)


## Mark her as met through the store's writer; false without its op.
func mark_met(store: Object, id: String) -> bool:
	return GAME.bond_mark_met(store, id)


## Withdraw the bond's standing invitation; nothing happens without the store's op.
func request_space(pony: Node, id: String) -> void:
	GAME.request_space(pony, id)


## Write a bond record back through the store's own save; false without the store's op.
func save_record(store: Object, id: String, record: BOND_RECORD) -> bool:
	return GAME.bond_record_save(store, id, record)
