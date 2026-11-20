extends RefCounted
## The request cooldown store: one `Mods.state("unfplap").request_times` dictionary of
## id -> unix time. It mirrors `shared/act_history.gd` (a static section owner with no scene state of its
## own) and composes the history offer cooldown with the heat shortening. See
## `docs/initiation.md` (`## Data ownership`).

const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")

const MOD_ID := "unfplap"
const KEY := "request_times"
const NEVER := -100000.0


## The whole `unfplap` state section, or `{}` outside a world.
static func section() -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	return GAME.mods_state(mods, MOD_ID).rows


## The stored cooldown clock for one mare, or a very old time so the first offer is ready.
static func last(section_data: Dictionary, id: String) -> float:
	var times: Variant = section_data.get(KEY, {})
	if not times is Dictionary:
		return NEVER
	return float((times as Dictionary).get(id, NEVER))


## True when the per-mare wait has passed. `wait` is the history cooldown, quartered in heat.
static func ready(section_data: Dictionary, id: String, now: float, in_heat: bool) -> bool:
	return POLICY.cooldown_ready(now, last(section_data, id),
		wait_seconds(section_data, id, in_heat))


## The live-section variant of `ready` used by the scan and the debug rows.
static func ready_for(id: String, in_heat: bool) -> bool:
	return ready(section(), id, Time.get_unix_time_from_system(), in_heat)


## The effective per-mare wait: the history offer cooldown, quartered in heat.
static func wait_seconds(section_data: Dictionary, id: String, in_heat: bool) -> float:
	var history := ACT_HISTORY.effective_row(section_data, id, ACT_HISTORY.day_now())
	var wait := ACT_HISTORY.offer_cooldown(history)
	if in_heat:
		wait = POLICY.heat_cooldown(wait)
	return wait


## Stamp the cooldown for one mare in the live section and save.
static func set_last(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var data: Dictionary = GAME.mods_state(mods, MOD_ID).rows
	var times: Variant = data.get(KEY, {})
	if not times is Dictionary:
		times = {}
	(times as Dictionary)[id] = Time.get_unix_time_from_system()
	data[KEY] = times
	GAME.mods_save(mods)


## Drop one mare's cooldown. A cuddle rising edge does this.
static func clear(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var data: Dictionary = GAME.mods_state(mods, MOD_ID).rows
	var times: Variant = data.get(KEY, {})
	if not times is Dictionary or not (times as Dictionary).has(id):
		return
	(times as Dictionary).erase(id)
	data[KEY] = times
	GAME.mods_save(mods)


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
