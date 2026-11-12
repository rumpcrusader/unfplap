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


## The live per-pony service. The runtime creates one, binds the host callbacks and keeps the
## scene gates; this object owns the grant/end/refresh decisions and the store calls.
var host: Dictionary = {}


func bind(host_in: Dictionary) -> void:
	host = host_in


func _host(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = host.get(key, null)
	if value is Callable:
		return (value as Callable).call()
	return fallback


func _callback(key: String) -> Callable:
	var value: Variant = host.get(key, null)
	return value as Callable if value is Callable else Callable()


## The live mod section. A test can supply one through the host, so the service is testable
## without the `Mods` autoload.
func _section() -> Dictionary:
	var cb := _callback("section")
	if cb.is_valid():
		var value: Variant = cb.call()
		return value if value is Dictionary else {}
	return section()


## Grant the bond after a clear spoken agreement or the Debug action. The runtime already made the
## scene checks; the host's `bond_facts` carries the policy's bond/stage/love level.
func grant_bond(source := "dialogue", line := "") -> bool:
	var id := str(_host("id", ""))
	var pony: Variant = _host("pony")
	if int(_host("state", 0)) != 0 or not is_instance_valid(pony) or bool(pony.get("sleeping")):
		return false
	if id.is_empty():
		return false
	var facts: Dictionary = _host("bond_facts", {})
	if not bool(facts.get("bond", false)):
		return false
	var stage := str(facts.get("stage", ""))
	var section_data := _section()
	if bonded(section_data, id):
		return true
	if not grant(section_data, id, stage, int(facts.get("love_level", 0)), source, line):
		return false
	save()
	_emit("You and Anon became lovers.")
	_log("lover bond granted id=%s stage=%s source=%s" % [id, stage, source])
	return true


## Clear the bond after a spoken withdrawal or from the Debug action. A break-up is the refresh
## sweep's job.
func end_bond(source := "dialogue", _line := "") -> bool:
	var id := str(_host("id", ""))
	if id.is_empty():
		return false
	var section_data := _section()
	if not bonded(section_data, id):
		return false
	if not clear(section_data, id, source):
		return false
	save()
	_emit("You and Anon are no longer lovers.")
	_log("lover bond ended id=%s source=%s" % [id, source])
	return true


## Clear a stored bond once the base relationship has left the romantic stages. The gate already
## rejects it; this prevents it from reviving if they date again later.
func refresh_bond() -> void:
	var id := str(_host("id", ""))
	if id.is_empty():
		return
	var section_data := _section()
	if not bonded(section_data, id):
		return
	var runtime: Variant = _host("relationship")
	if runtime == null or not is_instance_valid(runtime):
		return
	var row_data := row(section_data, id)
	var stored_stage := str(row_data.get("stage", ""))
	var record: Dictionary = runtime.bonds.record_for(id)
	var live_stage := str(record.get("stage", ""))
	if romantic_stage(live_stage):
		# A Crush bond can become a dating bond later; keep the stored stage current so a
		# break-up still clears it.
		if stored_stage != live_stage and set_stage(section_data, id, live_stage):
			save()
		return
	# A bond made at Crush or Any Adult has no romantic stage to leave. A bond made while
	# dating/engaged/married is cleared by a break-up.
	if not romantic_stage(stored_stage):
		return
	if clear(section_data, id, "stage=" + live_stage):
		save()
		_log("lover bond cleared id=%s stage=%s" % [id, live_stage])


func _emit(text: String) -> void:
	var event := _callback("event")
	if event.is_valid():
		event.call(text)


func _log(text: String) -> void:
	var logger := _callback("log")
	if logger.is_valid():
		logger.call(text)


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
