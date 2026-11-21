extends RefCounted
## Shared derivation of one mare's phase: the debug override, the feature switch, then her bond
## day. Estrus and the act gate both read it here, so the two cannot disagree.

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