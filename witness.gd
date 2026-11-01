extends RefCounted
## Thin wrapper so the witness pass has its own file, as the plan's layout describes.

const MEMORY := preload("res://mods/unfplap/memory.gd")


static func commit(game: Node, partner_id: String, partner_name: String, serial: int, partner: Node3D) -> void:
	MEMORY.witnesses(game, partner_id, partner_name, serial, partner)
