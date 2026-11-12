extends RefCounted
## Thin wrapper so the witness pass has its own file, as the plan's layout describes.
## Returns one debug row per recorded witness, for the runtime's optional log.

const MEMORY := preload("res://mods/unfplap/memory.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")


static func commit(game: Node, service: ELIGIBILITY, partner_id: String, partner_name: String,
		serial: int, partner: Node3D) -> Array:
	return MEMORY.witnesses(game, service, partner_id, partner_name, serial, partner)
