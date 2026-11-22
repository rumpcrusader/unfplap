extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## Her expression controller, dialogue face and blush, bound to her node.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _pony: Node


func _init(pony: Node) -> void:
	_pony = pony


func _bound() -> Node:
	return _pony


## Her expression controller; null when the body has none.
func controller() -> Object:
	return GAME.expressions_of(_pony)


## Add a smile and lid weight under `source`; the game sums the sources itself.
func touch(source: String, smile: float, lids: float) -> void:
	GAME.touch(GAME.expressions_of(_pony), source, smile, lids)


func release_touch(source: String) -> void:
	GAME.release_touch(GAME.expressions_of(_pony), source)


## Hold or release the stare; a NAN `lids` keeps the game's own default.
func stare(on: bool, lids: float = NAN) -> void:
	GAME.stare(GAME.expressions_of(_pony), on, lids)


func fluster(seconds: float, peeks: bool = true) -> void:
	GAME.fluster(GAME.expressions_of(_pony), seconds, peeks)


func fluster_amount() -> float:
	return GAME.fluster_amount(GAME.expressions_of(_pony))


## The face the controller is speaking through; empty when it holds none.
func dialogue_face() -> String:
	return GAME.dialogue_face(GAME.expressions_of(_pony))


func set_dialogue(face: String) -> void:
	GAME.set_dialogue(GAME.expressions_of(_pony), face)


func finish_dialogue(seconds: float) -> void:
	GAME.finish_dialogue(GAME.expressions_of(_pony), seconds)


func clear_dialogue() -> void:
	GAME.clear_dialogue(GAME.expressions_of(_pony))


func sustain_blush(amount: float) -> void:
	GAME.sustain_blush(GAME.boop_of(_pony), amount)


## Fire her blush sustainer's own heart burst; false without the op.
func celebrate() -> bool:
	return GAME.celebrate(GAME.boop_of(_pony))


## One mouth expression write; the mouth is hers, so the caller names only the shape.
func set_expression(name: String, amount: float) -> void:
	GAME.set_expression(GAME.mouth_of(GAME.head_of(_pony)), name, amount)
