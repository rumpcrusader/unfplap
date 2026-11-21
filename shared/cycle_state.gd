extends RefCounted
## One mare's cycle phase, derived for every consumer the same way.
##
## The debug override wins even with the feature off, so the lab can force heat. A pony that has
## only just spawned has no relationship runtime yet, so that reads as normal.

const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")


static func phase(pony: Node, enabled: bool) -> String:
	if not is_instance_valid(pony):
		return CYCLE.NORMAL
	var id := PONY_ID.of(pony)
	var override := CYCLE.override_for(id)
	if not override.is_empty():
		return override
	if not enabled or id.is_empty() or not pony.has_meta("relationship_runtime"):
		return CYCLE.NORMAL
	var day := GAME.bond_day(GAME.bonds_of(pony))
	if is_nan(day):
		return CYCLE.NORMAL
	return CYCLE.phase(day, id)