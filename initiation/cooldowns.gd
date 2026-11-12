extends RefCounted
## The request cooldown store: one `Mods.state("unfplap").request_times` dictionary of
## id -> unix time. It mirrors `act_history.gd` (a static section owner with no scene state of its
## own) and composes the history offer cooldown with the heat shortening. See
## `docs/initiation.md` (`## Data ownership`).

const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")

const MOD_ID := "unfplap"
const KEY := "request_times"
const NEVER := -100000.0


## The whole `unfplap` state section, or `{}` outside a world.
static func section() -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	var data: Variant = mods.call("state", MOD_ID)
	return data if data is Dictionary else {}


## The stored cooldown clock for one mare, or a very old time so the first offer is ready.
static func last(section_data: Dictionary, id: String) -> float:
	var times: Variant = section_data.get(KEY, {})
	if not times is Dictionary:
		return NEVER
	return float((times as Dictionary).get(id, NEVER))


## True when the per-mare wait has passed. `wait` is the history cooldown, quartered in heat.
static func ready(section_data: Dictionary, id: String, now: float, in_heat: bool) -> bool:
	var history := ACT_HISTORY.effective_row(section_data, id, ACT_HISTORY.day_now())
	var wait := ACT_HISTORY.offer_cooldown(history)
	if in_heat:
		wait = POLICY.heat_cooldown(wait)
	return POLICY.cooldown_ready(now, last(section_data, id), wait)


## Stamp the cooldown for one mare in the live section and save.
static func set_last(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var data: Dictionary = mods.call("state", MOD_ID)
	var times: Variant = data.get(KEY, {})
	if not times is Dictionary:
		times = {}
	(times as Dictionary)[id] = Time.get_unix_time_from_system()
	data[KEY] = times
	mods.call("save_changed")


## Drop one mare's cooldown. A cuddle rising edge does this.
static func clear(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var data: Dictionary = mods.call("state", MOD_ID)
	var times: Variant = data.get(KEY, {})
	if not times is Dictionary or not (times as Dictionary).has(id):
		return
	(times as Dictionary).erase(id)
	data[KEY] = times
	mods.call("save_changed")


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
