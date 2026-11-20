extends RefCounted
## The peak-memory store; the only memory file that saves.

const GAME := preload("res://mods/unfplap/world/game.gd")
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
	var mods := _mods()
	if mods == null:
		return false
	var state := GAME.mods_state(mods, MOD_ID).rows
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
	save(mods)
	return true


static func section() -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	return GAME.mods_state(mods, MOD_ID).rows


static func save(mods: Node) -> void:
	if is_instance_valid(mods):
		GAME.mods_save(mods)


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
