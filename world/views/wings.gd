extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## Her wing node and the excitement Beat that owns the stock spread, bound to either one.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _node: Node


func _init(node: Node) -> void:
	_node = node


func _bound() -> Node:
	return _node


## Her wing node, read off the excitement Beat that owns it.
func node() -> Node:
	return GAME.wings_of(_node)


## Take the act's half-open hold on the wing node; false without the op.
func hold(owner: String, value: float) -> bool:
	return GAME.wing_hold_at(_node, owner, value)


func release_hold(owner: String) -> void:
	GAME.wing_release_hold(_node, owner)


func set_open(open: bool) -> void:
	GAME.wing_set_open(_node, open)


## The Beat's stock spread, which the act uses when the half-open fold is unavailable.
func spread(seconds: float) -> void:
	GAME.wing_spread(_node, seconds)


func flutter() -> void:
	GAME.wing_flutter(_node)


func opened() -> bool:
	return GAME.wing_opened(_node)


func set_opened(open: bool) -> void:
	GAME.set_wing_opened(_node, open)


func set_tuck(value: float) -> void:
	GAME.set_wing_tuck(_node, value)


func set_half(value: float) -> void:
	GAME.set_wing_half(_node, value)
