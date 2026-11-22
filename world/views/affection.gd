extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## The scene's stock kisser, bound, plus the affection, cuddle and carry nodes the act writes.

const GAME := preload("res://mods/unfplap/world/game.gd")
const TOUCH_BRIDGE := preload("res://mods/unfplap/shared/touch_bridge.gd")

var _kisser: Node


func _init(kisser: Node) -> void:
	_kisser = kisser


func _bound() -> Node:
	return _kisser


## The kisser as the accessor may take it: a freed kisser is the same as no kisser.
func _kisser_node() -> Node:
	return _kisser if is_instance_valid(_kisser) else null


## The scene's stock kisser; null when the scene has none.
func kisser() -> Node:
	return _kisser_node()


## Start the stock kiss from her side; false when the kisser refuses or lacks the op.
func begin_from_pony(pony: Node3D) -> bool:
	return GAME.begin_from_pony(_kisser_node(), pony)


## Drop the kisser's own latch so the next kiss starts clean.
func clear_kisser() -> void:
	GAME.clear_kisser(_kisser_node())


## End the stock affection through its own op.
func end(affection: Node) -> void:
	GAME.end_affection(affection)


## Clear the affection's own 60 s stare afterglow.
func cancel_afterglow(affection: Node) -> void:
	GAME.cancel_afterglow(affection)


## Feed the affection Anon's live mouth target, eye and face.
func feed(affection: Node, target: Vector3, eye: Vector3, face: Basis) -> void:
	GAME.feed_affection(affection, target, eye, face)


## Whether the stock kiss pose exposes the side latch the act pins.
func side_known(pose: SkeletonModifier3D) -> bool:
	return GAME.kiss_side_known(pose)


## Pin the stock kiss pose to one side and hold it there.
func pin_side(pose: SkeletonModifier3D, side: float, hold_s: float) -> void:
	GAME.pin_kiss_side(pose, side, hold_s)


## Release the stock kiss pose's side hold.
func release_side(pose: SkeletonModifier3D) -> void:
	GAME.release_kiss_side(pose)


## Settle the excitement Beat's hold so the stock horn sparkle does not fire.
func settle_excitement(excitement: Node) -> void:
	GAME.settle_excitement(excitement)


## Let her Affection buck at Anon; false without the op or when it refuses.
func buck(affection: Node, body: Node3D) -> bool:
	return GAME.affection_buck(affection, body)


## End a cuddle session at once.
func end_cuddle(session: Node) -> void:
	GAME.cuddle_end(session)


## Whether a hoof hold reports itself active.
func hoof_active(hoof: Object) -> bool:
	return GAME.hoof_active(hoof)


## Whether this reach holds and cradles this pony.
func carry_ours(reach: Node, pony: Node3D) -> bool:
	return GAME.carry_ours(reach, pony)


## The reach's desktop action node; null when it keeps none.
func carry_actions(reach: Node) -> Node:
	return GAME.carry_actions(reach)


## Clear the carry flags the salute path leaves behind.
func clear_carry(reach: Node) -> void:
	GAME.clear_carry(reach)


## Tell the desktop actions the carried pony was released.
func carry_released(actions: Node) -> void:
	GAME.carry_released(actions)


## End her hold interaction.
func end_interaction(pony: Node) -> void:
	GAME.end_interaction(pony)


## Fire the touch host's caress event; a bridge without a callable stays silent.
func caress(touch: TOUCH_BRIDGE) -> void:
	GAME.caress(touch)
