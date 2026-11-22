extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## The bound world root's named menu panels, its HUD toast line and the stock UI cue.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _root: Node


func _init(root: Node) -> void:
	_root = root


func _bound() -> Node:
	return _root


## One of the game's named menu panels; null when absent.
func panel(key: StringName) -> Node:
	return GAME.menu_panel(_root, key)


## One line in the HUD's own toast slot.
func show_toast(instance: Node, text: String, seconds: float) -> void:
	GAME.show_toast(instance, text, seconds)


## One stock UI cue at a world point, sourced by a live scene node.
func sound(kind: String, source: Node3D, at: Vector3) -> void:
	GAME.interaction_sound(source, kind, at)
