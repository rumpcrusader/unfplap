extends RefCounted
## Service: world
## Contract: docs/world.md `## Base-game access`
## Stateless readers for the base-game members the mod touches; the scene root is an argument.


## The eye is in a headset; absent reads as false.
static func headset_view(game: Node) -> bool:
	if not is_instance_valid(game):
		return false
	return game.get("headset_view") == true


## The game's player property; null when absent or not a body.
static func game_player(game: Node) -> Node3D:
	if not is_instance_valid(game):
		return null
	var body: Variant = game.get("player")
	if body is Node3D and is_instance_valid(body):
		return body
	return null


## The world's chat box; null when the scene has none.
static func chat_box(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	return game.get_node_or_null("ChatBox") as Node
