extends "res://mods/unfplap/tests/test_lab.gd"
## integration: stress lab. Every adult mare in the game is assigned to Ponyville and placed in
## a grid in front of Golden Oak Library. Run with ./lab-stress.sh. Fillies are excluded.

const POPULATION_CONFIG := preload("res://world/population/pony_population_config.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const GRID_COLUMNS := 15
const GRID_ACROSS_M := 0.95
const GRID_BACK_M := 0.95
const GRID_FIRST_BACK_M := 0.9

var _stress_ids_cache: Array[String] = []
var _restrict_logged := false


## integration: every female adult the catalogue can spawn. Fillies, stallions and Spike are
## deliberately excluded; this is the "all mares" stress roster.
func _stress_ids() -> Array[String]:
	if not _stress_ids_cache.is_empty():
		return _stress_ids_cache
	var catalogue: Dictionary = POPULATION_CONFIG.catalogue()
	var ids: Array[String] = []
	for id: Variant in catalogue.keys():
		var name := str(id)
		if name == "spike" or POPULATION_CONFIG.STALLIONS.has(name) \
				or POPULATION_CONFIG.FILLIES.has(name):
			continue
		ids.append(name)
	ids.sort()
	_stress_ids_cache = ids
	return _stress_ids_cache


func run() -> void:
	await super.run()
	if is_instance_valid(game):
		print("[unfplap stress] %d adult mares; fillies excluded" % _stress_ids().size())
		print("[unfplap stress] anatomy flags: mode=%s holes=%s oral=%s finish=%s fluid=%s" % [
			SETTINGS.anatomy_mode.get_choice(),
			str(SETTINGS.anatomy_holes.get_bool()),
			str(SETTINGS.anatomy_oral.get_bool()),
			str(SETTINGS.anatomy_finish.get_bool()),
			str(SETTINGS.anatomy_fluid.get_bool()),
		])


## integration: the normal lab returns on the first live test pony. The stress lab waits for the
## whole roster before pausing population.
func _wait_for_world() -> bool:
	if not await super._wait_for_world():
		return false
	var target := _stress_ids().size()
	# The first run loads every background rig; 105 mares take several minutes on a cold cache.
	var wait_until := Time.get_ticks_msec() + 420000
	var last := -1
	while Time.get_ticks_msec() < wait_until:
		var count := _test_ponies().size()
		if count != last:
			last = count
			print("[unfplap stress] mares live %d/%d" % [count, target])
		if count >= target:
			return true
		await get_tree().process_frame
	print("[unfplap stress] roster did not finish spawning; proceeding with %d/%d" % [
		_test_ponies().size(), target])
	return true


func _restrict_population() -> void:
	if not is_instance_valid(game):
		return
	var population: Variant = game.get("population")
	if not is_instance_valid(population):
		return
	var config: Variant = population.get("config")
	var assignments: Variant = config.get("assignments") if config != null else null
	if not assignments is Dictionary:
		return
	var ids := _stress_ids()
	var added: Array[String] = []
	for id: String in ids:
		if (assignments as Dictionary).has(id):
			continue
		(assignments as Dictionary)[id] = "ponyville"
		added.append(id)
	if not added.is_empty():
		print("[unfplap stress] assigned %d missing mares to ponyville" % added.size())
	var removed := 0
	for id: Variant in (assignments as Dictionary).keys():
		if ids.has(str(id)):
			continue
		(assignments as Dictionary).erase(id)
		removed += 1
	if not _restrict_logged or removed > 0:
		print("[unfplap stress] population limited to %d mares (removed %d)" % [ids.size(), removed])
		_restrict_logged = true
	_place_missing_stress_spawns(population)


## integration: put every stress mare's saved candidate at the library when her real home is
## outside the activation radius. The game's own loading path still spawns them.
func _place_missing_stress_spawns(population: Variant) -> void:
	if not is_instance_valid(population):
		return
	var anchor: Variant = population.get("anchor")
	if not anchor is Node3D:
		return
	var saved: Variant = population.get("saved")
	if not saved is Dictionary:
		return
	var live: Variant = population.get("live")
	var at := _test_spawn_point()
	if not at.is_finite():
		return
	var origin: Vector3 = (anchor as Node3D).global_position
	var moved := 0
	for id: String in _stress_ids():
		if live is Dictionary and (live as Dictionary).has(id):
			continue
		if (saved as Dictionary).has(id) and (saved as Dictionary)[id] is Dictionary \
				and ((saved as Dictionary)[id] as Dictionary).has("resume"):
			continue
		var where: Vector3 = population.call("candidate_position", id)
		var reach := float(population.call("activate_distance", id))
		var distance := _flat_distance(where, origin) if where.is_finite() else INF
		if distance < reach - 5.0:
			continue
		(saved as Dictionary)[id] = {"region": "ponyville", "position": at,
			"rotation": Vector3.ZERO, "resume": {}}
		moved += 1
	if moved > 0:
		print("[unfplap stress] %d mares moved to the library spawn" % moved)


func _prune_population() -> void:
	var population: Variant = game.get("population") if is_instance_valid(game) else null
	if not is_instance_valid(population):
		return
	var live: Variant = population.get("live")
	if not live is Dictionary:
		return
	var ids := _stress_ids()
	var removed := 0
	for id: Variant in (live as Dictionary).keys():
		if ids.has(str(id)):
			continue
		var entry: Variant = (live as Dictionary)[id]
		var actor: Variant = (entry as Dictionary).get("actor") if entry is Dictionary else null
		if is_instance_valid(actor) and game.has_method("_despawn_resident"):
			game.call("_despawn_resident", str(id), actor)
		(live as Dictionary).erase(id)
		removed += 1
	if removed > 0:
		print("[unfplap stress] despawned %d non-stress ponies" % removed)


func _test_ponies() -> Array:
	var out: Array = []
	if not is_instance_valid(game):
		return out
	var by_id := {}
	var list: Variant = game.get("mares")
	if list is Array:
		for node: Variant in list:
			if not is_instance_valid(node):
				continue
			var id := _pony_id(node)
			if _stress_ids().has(id) and not by_id.has(id):
				by_id[id] = node
	for id: String in _stress_ids():
		if by_id.has(id):
			out.append(by_id[id])
	return out


func _setup_ponies(ponies: Array) -> void:
	var impressions := _impressions()
	var xp: Dictionary = {}
	if is_instance_valid(impressions):
		var current: Variant = impressions.get("xp")
		if current is Dictionary:
			xp = current
		else:
			impressions.set("xp", xp)
	var home := _library_home()
	var rows := PackedStringArray()
	var count := ponies.size()
	var index := 0
	for pony_node: Variant in ponies:
		var pony: Node3D = pony_node as Node3D
		if not is_instance_valid(pony):
			continue
		var id := _pony_id(pony)
		if id.is_empty():
			continue
		if is_instance_valid(impressions):
			var row: Dictionary = xp.get(id, impressions.call("xp_for", id))
			row["friendship"] = maxi(int(row.get("friendship", 0)), 500)
			row["romance"] = 150
			xp[id] = row
		_set_dating_record(pony)
		_set_mood(pony, "neutral")
		_make_idle(pony, true)
		var placed := _place_stress_grid(pony, home, index, count)
		rows.append("%s pos=%s placed=%s" % [id, str(pony.global_position), str(placed)])
		index += 1
	if is_instance_valid(impressions):
		impressions.set("xp", xp)
	_log_action("stress mares", rows)
	var context: Variant = game.get("world_context")
	if is_instance_valid(context):
		context.call("_changed")
	var history_rows := PackedStringArray()
	var history_section: Dictionary = ACT_HISTORY.section()
	for id: String in _stress_ids():
		if ACT_HISTORY.reset(history_section, id):
			history_rows.append(id)
	if not history_rows.is_empty():
		ACT_HISTORY.save()
		_log_action("stress act history cleared", history_rows)


## integration: a 15-column grid in front of the library, stepping back one row at a time.
func _place_stress_grid(pony: Node3D, home: Node3D, index: int, count: int) -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(home):
		return false
	if not home.has_method("outside"):
		return false
	var front: Vector3 = home.call("outside")
	var right: Vector3 = home.global_basis.x.normalized()
	var back: Vector3 = home.global_basis.z.normalized()
	var columns := GRID_COLUMNS
	var total := maxi(count, 1)
	var row := int(index / columns)
	var col := index % columns
	var in_row := mini(columns, total - row * columns)
	var at := front \
		+ right * ((float(col) - (float(in_row) - 1.0) * 0.5) * GRID_ACROSS_M) \
		+ back * (GRID_FIRST_BACK_M + float(row) * GRID_BACK_M)
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 5.0, 1)
	query.exclude = [pony.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		at = hit.get("position", at)
	pony.global_position = at
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	_upright(pony)
	pony.reset_physics_interpolation()
	return true
