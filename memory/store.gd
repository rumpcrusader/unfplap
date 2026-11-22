extends RefCounted
## The peak-memory store; the only memory file that saves.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const MOD_ID := "unfplap"
const KEY := "peak_memories"


## The stored peak for one mare, or an empty dictionary.
static func peak(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var state := section()
	var rows: Variant = state.get(KEY, {})
	if not rows is Dictionary:
		return {}
	var row: Variant = (rows as Dictionary).get(id, {})
	return (row as Dictionary).duplicate(true) if row is Dictionary else {}


## Keep a peak only when it beats the stored score. Returns whether it was written.
static func record(id: String, event_id: String, text: String, score: float) -> bool:
	if id.is_empty():
		return false
	if not WORLD.mods().present():
		return false
	var state := WORLD.mods().state(MOD_ID).rows
	var rows: Variant = state.get(KEY, {})
	if not rows is Dictionary:
		rows = {}
	var old: Variant = (rows as Dictionary).get(id, {})
	if old is Dictionary and float((old as Dictionary).get("score", -1.0)) >= score:
		return false
	(rows as Dictionary)[id] = {
		"text": text,
		"score": score,
		"event_id": event_id,
		"at": Time.get_unix_time_from_system(),
	}
	state[KEY] = rows
	save()
	return true


static func section() -> Dictionary:
	if not WORLD.mods().present():
		return {}
	return WORLD.mods().state(MOD_ID).rows


static func save() -> void:
	WORLD.mods().save()
