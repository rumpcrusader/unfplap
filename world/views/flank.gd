extends RefCounted
## Her flank patch and touch body: the hull sync, the jiggle surface and its fold.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _node: Node


func _init(node: Node) -> void:
	_node = node


func _bound() -> Node:
	return _node


## Re-sync one of her touch body's rigs after the act moved the hulls.
func sync(rig: int) -> void:
	GAME.touch_sync(_node, rig)


## Skin the patch on `surface` to the act skeleton before its faces are read.
func update_surface(surface: Object, skeleton: Skeleton3D, frame: Transform3D) -> void:
	GAME.flank_surface_update(surface, skeleton, frame)


## The flank patch's contact query at a local point; empty when it has no query.
func surface_contact(surface: Object, point: Vector3, palm: Vector3, reach: float) -> Dictionary:
	return GAME._flank_surface_contact(surface, point, palm, reach)


## The touch body's nearest hull at a world point; empty when it keeps no query.
func touch_nearest(point: Vector3) -> Dictionary:
	return GAME._touch_nearest(_node, point)


func impact(index: int, at: Vector3, strength: float) -> void:
	GAME.flank_impact(_node, index, at, strength)


func wake_tick() -> void:
	GAME.flank_wake_tick(_node)


func start_jiggle(index: int, strength: float) -> bool:
	return GAME.flank_start_jiggle(_node, index, strength)


func process(delta: float) -> void:
	GAME.flank_process(_node, delta)


func jiggle_amount() -> float:
	return GAME.flank_jiggle_amount(_node)


func set_jiggle_amount(amount: float) -> void:
	GAME.set_flank_jiggle_amount(_node, amount)


## The stock rump blush texture; null until the game has built it.
func rump_blush_texture() -> Texture2D:
	return GAME.rump_blush_texture()
