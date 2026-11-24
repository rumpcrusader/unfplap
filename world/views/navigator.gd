extends RefCounted
## One pony's navigator leases, travel and facing, bound to her node or to the navigator itself.
## A travel lease belongs to the caller that claimed it: this view carries that owner's reads and
## writes and never claims, reassigns or releases a lease on its own.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _pony: Node


func _init(pony: Node) -> void:
	_pony = pony


func _bound() -> Node:
	return _pony


## The navigator child this view speaks for; a view bound to the navigator itself speaks for it.
func _nav() -> Node:
	if not is_instance_valid(_pony):
		return null
	var found := GAME.navigator_of(_pony)
	if found != null:
		return found
	return _pony if _is_navigator(_pony) else null


## Whether a node is the base-game navigator rather than a pony body that owns one.
static func _is_navigator(node: Node) -> bool:
	return is_instance_valid(node) and "command_owner" in node


## The navigator node the lease reads and writes; null on a body without one.
func node() -> Node:
	return _nav()


## True while she has a navigator, or while this view is bound to one.
func present() -> bool:
	return _nav() != null


## The lease holder's name; empty when the navigator is free.
func owner() -> String:
	return GAME.navigator_owner(_nav())


func reserved() -> String:
	return GAME.navigator_reserved(_nav())


func wander() -> bool:
	return GAME.navigator_wander(_nav())


## True while she is walking to a target.
func has_target() -> bool:
	return GAME.navigator_has_target(_nav())


func stay() -> void:
	GAME.navigator_stay(_nav())


func set_owner(value: String) -> void:
	GAME.set_navigator_owner(_nav(), value)


func set_reserved(value: String) -> void:
	GAME.set_navigator_reserved(_nav(), value)


func set_wander(enabled: bool) -> void:
	GAME.set_navigator_wander(_nav(), enabled)


## The speed override; NAN when the navigator has none.
func speed_limit() -> float:
	return GAME.navigator_speed_limit(_nav())


## The pace override; NAN when the navigator has none.
func pace_target() -> float:
	return GAME.navigator_pace_target(_nav())


func set_speed_limit(value: float) -> void:
	GAME.set_navigator_speed_limit(_nav(), value)


func set_pace_target(value: float) -> void:
	GAME.set_navigator_pace_target(_nav(), value)


## The navigator's own reachable point near `point`; `Vector3.INF` when it cannot answer.
func support(point: Vector3) -> Vector3:
	return GAME.navigator_support(_nav(), point)


## Walk her to `point`; false when she has no navigator or it refuses the goal.
func walk_to(point: Vector3, gait: String) -> bool:
	return GAME.navigator_destination(_nav(), point, gait)


## Clear a travel lease's carried body.
func clear_travel(travel: Node) -> void:
	GAME.travel_clear(travel, _pony)


## Keep `target` as her conversation aim; the hold keeps it across ticks.
func set_conversation_target(target: Node3D, hold: bool) -> void:
	GAME.set_conversation_target(_pony, target, hold)


## Drop the navigator's conversation facing.
func clear_conversation_target() -> void:
	GAME.clear_conversation_target(_nav())


## Turn her through the navigator's own face point.
func set_face_point(point: Vector3) -> void:
	GAME.set_face_point(_nav(), point)


## Turn her own locomotion facing; a body without the turn is left alone.
func set_facing(direction: Vector3) -> void:
	GAME.face_direction(_pony, direction)


## Drop both stale navigator writes that would face her away.
func clear_facing() -> void:
	GAME.clear_facing(_pony)
