extends RefCounted
## Shared derivation of one mare's phase: the debug override, the feature switch, then her bond
## day. Estrus and the act gate both read it here, so the two cannot disagree.

const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")


## The phase from the override, the switch and the caller's bond day; NAN is no bond clock.
static func phase(pony: Node, enabled: bool, day: float) -> String:
	if not is_instance_valid(pony):
		return CYCLE.NORMAL
	var id := PONY_ID.of(pony)
	var override := CYCLE.override_for(id)
	if not override.is_empty():
		return override
	if not enabled or id.is_empty() or not pony.has_meta("relationship_runtime"):
		return CYCLE.NORMAL
	if is_nan(day):
		return CYCLE.NORMAL
	return CYCLE.phase(day, id)
