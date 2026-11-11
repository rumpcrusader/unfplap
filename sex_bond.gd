extends RefCounted
## The mod-owned lover-bond store. The Promiscuity ladder, willingness, Starting Sex and every
## gate live in `eligibility.gd`; this file only stores the bond and its stage.
##
## The bond lives in `Mods.state("unfplap").sex_bonds`, so it is per-world save data and survives
## a reload. It never expires; a bond granted while dating/engaged/married is cleared when the base
## stage leaves those stages, and a clear spoken withdrawal always clears it.

const ROMANTIC_STAGES := ["dating", "engaged", "married"]


static func romantic_stage(stage: String) -> bool:
	return stage in ROMANTIC_STAGES


## The live mod section for the current world. Empty before a world loads or when the mod hook is
## unavailable; grant/clear still mutate a caller's dictionary so pure tests can use a fake one.
static func section() -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	var state: Variant = mods.call("state", "unfplap")
	return state if state is Dictionary else {}


static func records(section: Dictionary) -> Dictionary:
	var rows: Variant = section.get("sex_bonds", {})
	if rows is Dictionary:
		return rows
	var fresh: Dictionary = {}
	section["sex_bonds"] = fresh
	return fresh


static func row(section: Dictionary, id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var rows: Dictionary = records(section)
	var found: Variant = rows.get(id, {})
	return (found as Dictionary).duplicate(true) if found is Dictionary else {}


static func bonded(section: Dictionary, id: String) -> bool:
	if id.is_empty():
		return false
	var rows: Variant = section.get("sex_bonds", {})
	if not rows is Dictionary:
		return false
	var found: Variant = (rows as Dictionary).get(id, {})
	if not found is Dictionary:
		return false
	var at: Variant = (found as Dictionary).get("at", null)
	return at is int or at is float


## Write one bond. Idempotent: an existing row is left alone, so a repeat spoken yes cannot
## replace the original moment or record a second event.
static func grant(section: Dictionary, id: String, stage: String, love_level: int,
		source: String, line: String) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	if rows.has(id):
		return true
	rows[id] = {
		"at": Time.get_unix_time_from_system(),
		"stage": stage,
		"love_level": love_level,
		"source": source,
		"line": line.left(240),
	}
	section["sex_bonds"] = rows
	return true


## Keep the stored stage current while a bond moves through dating/engaged/married, so a later
## break-up can clear it even if the bond was first made at Crush.
static func set_stage(section: Dictionary, id: String, stage: String) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	var found: Variant = rows.get(id, null)
	if not found is Dictionary:
		return false
	(found as Dictionary)["stage"] = stage
	section["sex_bonds"] = rows
	return true


static func clear(section: Dictionary, id: String, reason: String) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	if not rows.has(id):
		return false
	rows.erase(id)
	section["sex_bonds"] = rows
	section["sex_bonds_last_clear"] = {"id": id, "reason": reason,
		"at": Time.get_unix_time_from_system()}
	return true


## Persist the mod section. Separate from grant/clear so pure tests never touch user://.
static func save() -> void:
	var mods := _mods()
	if mods != null and mods.has_method("save_changed"):
		mods.call("save_changed")


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
