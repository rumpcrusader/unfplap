extends "res://mods/unfplap/tests/test_lab.gd"
## integration: stress lab. Every adult mare in the game is assigned to Ponyville and placed in
## one line in front of Golden Oak Library, facing away from the building and standing idle.
## Run with ./lab-stress.sh. Fillies are excluded.

const POPULATION_CONFIG := preload("res://world/population/pony_population_config.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const LINE_SPACING_M := 0.80
const LINE_FIRST_BACK_M := 0.80
## The base spawner needs 3 m between residents. The final line is tighter, so every non-live
## stress mare gets a wide session-only pre-spawn point first and is moved into the line later.
## The grid follows the final line's width and stays shallow, so it cannot reach into the library.
const PRE_SPAWN_SPACING_M := 3.2
const PRE_SPAWN_COLUMNS := 26
const ROSTER_STALL_MS := 60000

var _stress_ids_cache: Array[String] = []
var _restrict_logged := false
var _pre_spawn_logged := false


## integration: every female adult the catalogue can spawn. Fillies, stallions and Spike are
## deliberately excluded; this is the "all mares" stress roster.
func _stress_ids() -> Array[String]:
	if not _stress_ids_cache.is_empty():
		return _stress_ids_cache
	var catalogue: Dictionary = POPULATION_CONFIG.catalogue()
	var ids: Array[String] = []
	# Use the anatomy roster, not the raw catalogue: it excludes the profile-marked
	# schoolfilly/stallion entries (Twist, Fiddly Twang) and includes the adult specials
	# (Sunset Shimmer) that the mod actually supports.
	for id: String in SETTINGS.CHARACTER_ORDER:
		if catalogue.has(id):
			ids.append(id)
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


## integration: the normal lab returns on the first live test pony. The stress lab quiets the
## simulation, then waits for the whole roster before pausing population.
func _wait_for_world() -> bool:
	if not await super._wait_for_world():
		return false
	# Population must stay on until the roster is out, but life, needs, schedulers and time do
	# not: keeping the full world running for every spawn is what made the wait run at 13 fps.
	_stop_standard_systems(false)
	var target := _stress_ids().size()
	# The first run loads every background rig; 103 mares take several minutes on a cold cache.
	var wait_until := Time.get_ticks_msec() + 420000
	var last := -1
	var last_change := Time.get_ticks_msec()
	while Time.get_ticks_msec() < wait_until:
		var now := Time.get_ticks_msec()
		var count := _test_ponies().size()
		if count != last:
			last = count
			last_change = now
			print("[unfplap stress] mares live %d/%d" % [count, target])
		if count >= target:
			return true
		if count > 0 and now - last_change >= ROSTER_STALL_MS:
			print("[unfplap stress] roster stalled at %d/%d; missing=%s" % [
				count, target, ",".join(_missing_stress_ids())])
			return true
		await get_tree().process_frame
	print("[unfplap stress] roster did not finish spawning; proceeding with %d/%d missing=%s" % [
		_test_ponies().size(), target, ",".join(_missing_stress_ids())])
	return true


func _missing_stress_ids() -> Array[String]:
	var live := {}
	for pony: Variant in _test_ponies():
		live[_pony_id(pony)] = true
	var missing: Array[String] = []
	for id: String in _stress_ids():
		if not live.has(id):
			missing.append(id)
	return missing


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
	var assigned: Array[String] = []
	for id: String in ids:
		if str((assignments as Dictionary).get(id, "")) == "ponyville":
			continue
		(assignments as Dictionary)[id] = "ponyville"
		assigned.append(id)
	if not assigned.is_empty():
		print("[unfplap stress] assigned %d mares to ponyville" % assigned.size())
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


## integration: every stress mare gets a session-only spawn on a wide grid in front of the
## library. The base population only streams a resident inside the activation radius, and a saved
## row from another region is ignored while the assignment still points there. The assignment is
## forced to Ponyville above; this row makes `resuming()` return the grid spot even when the life
## simulation still has her elsewhere. The game's own loading path still spawns them.
func _place_missing_stress_spawns(population: Variant) -> void:
	if not is_instance_valid(population):
		return
	var saved: Variant = population.get("saved")
	if not saved is Dictionary:
		return
	var live: Variant = population.get("live")
	var ids := _stress_ids()
	var visiting: Variant = population.get("visiting")
	var retry_at: Variant = population.get("retry_at")
	var failures: Variant = population.get("_startup_failures")
	var status: Variant = population.get("status")
	var placed := 0
	for index in ids.size():
		var id := ids[index]
		if live is Dictionary and (live as Dictionary).has(id):
			continue
		var at := _stress_spawn_point(index)
		if not at.is_finite():
			continue
		var current: Variant = (saved as Dictionary).get(id)
		if current is Dictionary and str((current as Dictionary).get("region", "")) == "ponyville" \
				and (current as Dictionary).has("resume") \
				and (current as Dictionary).get("position", Vector3.INF) == at:
			continue
		(saved as Dictionary)[id] = {"region": "ponyville", "position": at,
			"rotation": Vector3.ZERO, "resume": {}}
		for blocked: Variant in [visiting, retry_at, failures, status]:
			if blocked is Dictionary:
				(blocked as Dictionary).erase(id)
		placed += 1
	if placed > 0 and not _pre_spawn_logged:
		_pre_spawn_logged = true
		print("[unfplap stress] %d mares pre-spawned on the library grid" % placed)
	# The spawner reads the life simulation's region before `life.attach()` runs. Sync it now so
	# the session's Ponyville assignment, not the saved region, chooses the navigation service.
	# The same call moves unleased residents onto the grid rows above.
	var life: Variant = population.get("life")
	if is_instance_valid(life) and life.has_method("_sync_roster"):
		life.call("_sync_roster")


## A stable, separate point per stress id. The base spawner requires 3 m between residents, so
## the temporary grid is wider than the final line; `_setup_ponies()` moves them in afterwards.
func _stress_spawn_point(index: int) -> Vector3:
	var home := _library_home()
	if is_instance_valid(home) and home.has_method("outside"):
		var front: Vector3 = home.call("outside")
		var right: Vector3 = home.global_basis.x.normalized()
		var back: Vector3 = home.global_basis.z.normalized()
		var columns := maxi(PRE_SPAWN_COLUMNS, 1)
		var column := index % columns
		var row := floori(float(index) / float(columns))
		var side := (float(column) - (float(columns) - 1.0) * 0.5) * PRE_SPAWN_SPACING_M
		var depth := float(row) * PRE_SPAWN_SPACING_M
		return front + right * side + back * (LINE_FIRST_BACK_M + depth)
	return _test_spawn_point()


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
		var placed := _place_stress_line(pony, home, index, count)
		# Idle after the teleport: a navigator target queued before the move would otherwise
		# make her walk away from the line.
		var idle := _make_idle(pony, true)
		rows.append("%s pos=%s placed=%s idle=%s" % [
			id, str(pony.global_position), str(placed), idle])
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


## integration: one line in front of the library, all facing the same outward direction.
func _place_stress_line(pony: Node3D, home: Node3D, index: int, count: int) -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(home):
		return false
	if not home.has_method("outside"):
		return false
	var front: Vector3 = home.call("outside")
	var right: Vector3 = home.global_basis.x.normalized()
	var back: Vector3 = home.global_basis.z.normalized()
	var total := maxi(count, 1)
	var at := front \
		+ right * ((float(index) - (float(total) - 1.0) * 0.5) * LINE_SPACING_M) \
		+ back * LINE_FIRST_BACK_M
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
	_face(pony, back)
	pony.reset_physics_interpolation()
	return true


## Make every pony face the same outward direction (away from the library).
func _face(pony: Node3D, direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return
	var scale := pony.global_basis.get_scale()
	var basis := Basis.looking_at(flat.normalized(), Vector3.UP) \
		* Basis.from_scale(scale)
	pony.global_transform = Transform3D(basis, pony.global_position)
