extends Node
## Unfplap manual test lab. Run with:
##   ./lab.sh
## The session is written to last-run.log beside the script.
##
## Loads only Twilight, Fluttershy, Rarity, Derpy, Applejack, Tempest Shadow, Lily Valley and
## Colgate, and pauses population/living-world/time plus background AI. At setup each one is moved
## to the spot she stood on in the world save (TEST_SPAWNS); a pony with no snapshot row falls back
## to the path in front of Golden Oak Library. Applejack starts as a stranger: friendship 0, no
## romance tier and no dating record.
## No extra bed is spawned: use the Golden Oak guest bed in the treebrary. Generated town houses
## skip furnishing before the loading wait; the authored library keeps its room and bed. The
## dialogue director stays running, because it serializes replies and a stopped director leaves
## ponies stuck "thinking".
##
## Lab hotkeys (mouse must be captured, like normal play):
##   - / =       lower / raise the pointed mare's romance tier (all test mares when not aiming)
##   9 / 0       lower / raise the pointed mare's anger mood (all test mares when not aiming)
##   Mouse 4     invite a test mare to the treebrary bed; a far mare is moved to the bed approach
##               first, and the log says why cuddling cannot start
##   Mouse 5     make the pointed adult mare idle and qualify for sex
##               without changing her romance tier
##   Shift+[ / ]  move the previous/next mare in front of Anon in a 3/4 rear view, standing idle.
##               The eight starters stay loaded and the previous starter returns to her saved
##               spot; any other mare is spawned on demand and the previous non-starter is
##               despawned again, so only one extra is live.

const BED_REST := preload("res://world/relationships/shared_bed.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const LAB_POPULATION := preload("res://world/population/pony_population_config.gd")
const MOD_SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const TEST_IDS := ["twilight_sparkle", "fluttershy", "rarity", "derpy_hooves", "applejack",
	"tempest_shadow", "lily_valley", "minuette"]
## Strangers start at friendship 0 (Stranger level), with no romance tier and no dating record.
const TEST_STRANGERS := ["applejack"]
## Review framing: she stands in front of Anon with her rump toward him, slightly to his right and
## turned so the camera sees one hip and the dock at a 3/4 rear angle.
const REVIEW_AHEAD_M := 1.25
const REVIEW_SIDE_M := 0.15
const REVIEW_TURN_DEG := 35.0
## Where each test pony stands at lab start: the transform she had in the world save of
## 2026-11-07 20:53 (save_20261107-205358). Position and yaw only; the ground raycast and
## `_upright()` still run on top.
const TEST_SPAWNS := {
	"twilight_sparkle": [Vector3(-42.32326889038086, -12.62147331237793, -261.1934509277344),
		0.772023618221283],
	"fluttershy": [Vector3(-39.58679962158203, -13.043929100036621, -253.56686401367188),
		2.0684242248535156],
	"rarity": [Vector3(-39.45050811767578, -13.06634521484375, -252.7421112060547),
		1.9742286205291748],
	"derpy_hooves": [Vector3(-25.958627700805664, -12.776995658874512, -254.7842559814453),
		-0.8870112299919128],
	"applejack": [Vector3(-30.345932006835938, -12.755083084106445, -259.98870849609375),
		0.09786661714315414],
	"tempest_shadow": [Vector3(-29.946136474609375, -13.015596389770508, -246.27793884277344),
		-2.327993392944336],
	"lily_valley": [Vector3(-36.51396560668945, -13.163646697998047, -244.48155212402344),
		2.682124614715576],
	"minuette": [Vector3(-35.94418716430664, -12.89651870727539, -255.7242431640625),
		2.76523756980896],
}
## Starting love XP: 0 = New Couple and below the sex gate, 150 = Marefriend, 400 = Head Over
## Hooves, 900 = the dating maximum (Soulmates still needs marriage). The -/= keys step these.
const TEST_ROMANCE := {
	"twilight_sparkle": 150,
	"fluttershy": 400,
	"rarity": 900,
	"derpy_hooves": 0,
}
const ROMANCE_LEVELS := [0, 150, 400, 900]
const ANGER_MOODS := ["neutral", "annoyed", "angry"]
## Printed at startup so the lab's full session setup is explicit in the log.
const SETUP_ACTIONS := [
	"wait for the game's world loading screen to finish",
	"temporarily set world/opening=skip, then restore the stored value",
	"skip the arrival tutorial when it is active",
	"restrict population to the eight test ponies (memory only)",
	"assign any missing test pony to Ponyville before spawning",
	"lift Max nearby ponies to Unlimited for the loading screen, then restore it",
	"place any far-off test pony's spawn at the library front",
	"move every test pony to her saved standing spot; the library row is only a fallback",
	"despawn any other resident already live in the world",
	"keep the dialogue director alive with ai_usage=talk",
	"pause population, life and needs",
	"cycle every adult mare on demand: one extra spawn, previous extra despawned",
	"pause PrincessVisits, TrixieShow, DayRunner, NightRest and StuckRescue",
	"pause TimeOfDay",
	"skip generated house furnishing; the authored library keeps its room and bed",
	"set friendship >= 500, neutral mood and idle for every test pony except the strangers",
	"set romance tier and dating record only for the adult test mares that are not strangers",
	"clear the adult test mares' long-term act history",
	"spawn no bed; use the Golden Oak guest bed",
]

var game: Node
var _done := false
var _old_opening := ""
var _settings: Node
var _furnishing_trimmed := false
## The simulation half of `_stop_standard_systems()` is idempotent across the stress lab's
## roster wait and the normal lab's final setup.
var _standard_systems_stopped := false
## The player's Max nearby ponies cap; -1 when the lab has not lifted it.
var _old_nearby := -1
## Shift+[ / ] review cursor over the full adult mare roster.
var _lab_mare_index := -1
## The one non-starter mare kept live for review; empty when only the starters are out.
var _extra_id := ""
var _extra_mare: Node3D = null
## The mare currently standing in front of Anon; the previous starter is returned to her spot.
var _review_id := ""
var _review_mare: Node3D = null
var _cycle_busy := false
var _cycle_ids_cache: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The title screen adds this lab before starting the game scene. Skip the opening tutorial
	# before the arrival story reads the setting, then restore the player's preference afterwards.
	_settings = get_node_or_null("/root/Settings")
	if _settings != null:
		_old_opening = str(_settings.get_value("world/opening"))
		_settings.set_value("world/opening", "skip")
		_lift_nearby_cap()
	print("[unfplap test] ready game=%s" % str(game))
	run.call_deferred()


func run() -> void:
	print("[unfplap test] lab start game=%s" % str(game))
	_log_action("lab setup actions", PackedStringArray(SETUP_ACTIONS))
	if not await _wait_for_world():
		return
	await _skip_arrival_tutorial()
	_restrict_population()
	_stop_standard_systems()
	_restore_nearby_cap()
	_prune_population()
	if _settings != null:
		_settings.set_value("world/opening", _old_opening)
	var ponies := _test_ponies()
	if ponies.is_empty():
		print("[unfplap test] no test ponies loaded")
		return
	_setup_ponies(ponies)
	_done = true
	var bed := _treebrary_bed()
	print("[unfplap test] bed=none spawned; treebrary guest bed=%s" % (
		str(bed.global_position) if is_instance_valid(bed) else "missing"))
	print("[unfplap test] E sit, Ctrl lie back; test ponies placed on their saved standing spots")
	print("[unfplap test] -/= romance tier, 9/0 anger mood, Mouse4 bed invite, Mouse5 sex-ready, Shift+[ / ] cycle mares")
	print("[unfplap test] background AI, population and time paused; the dialogue director still answers")


func _wait_for_world() -> bool:
	# Do not touch the population until the game's own loading screen is gone. The loading
	# coroutine is still spawning residents behind "Waking up the ponies…"; stopping population
	# early freezes that loop and the screen waits forever at "2 out, 39 to go".
	var waiting_logged := false
	for i in 3600:
		if not is_instance_valid(game):
			var scene := get_tree().current_scene
			if scene != null and scene.get("world_context") != null:
				game = scene
		if is_instance_valid(game):
			_trim_generated_furnishing()
			_restrict_population()
			var loading: bool = game.get("title_active") == true \
				or game.get_node_or_null("LoadingCover") != null
			if loading and not waiting_logged:
				waiting_logged = true
				print("[unfplap test] waiting for the world loading screen to finish")
			if not loading and is_instance_valid(game.get("player")) \
					and is_instance_valid(game.get("world_context")) \
					and not _test_ponies().is_empty():
				return true
		await get_tree().process_frame
	print("[unfplap test] world did not become ready game=%s player=%s ctx=%s" % [
		str(game), str(game.get("player")) if is_instance_valid(game) else "null",
		str(game.get("world_context")) if is_instance_valid(game) else "null"])
	return false


## An existing save can already be in the tutorial stage even with `world/opening = skip`.
## Skip that sequence explicitly before the test mares are moved.
func _skip_arrival_tutorial() -> void:
	var arrival: Variant = game.get("arrival")
	if arrival == null or not is_instance_valid(arrival) or not arrival.has_method("stage"):
		return
	var stage := str(arrival.call("stage"))
	if stage not in ["wake", "tutorial", "found"]:
		return
	print("[unfplap test] skipping arrival stage=%s" % stage)
	if arrival.has_method("_skip_opening"):
		await arrival.call("_skip_opening")
	else:
		arrival.call("_finish")


## The player's "Max nearby ponies" setting caps the loading screen too, so a value of four leaves
## two test ponies unspawned. Lift it in memory for the session only; settings.cfg is not written,
## and `_restore_nearby_cap()` puts the player's value back once the population is paused.
func _lift_nearby_cap() -> void:
	if _old_nearby >= 0 or not is_instance_valid(_settings):
		return
	_old_nearby = int(_settings.get_value("ponies/max_nearby"))
	if _old_nearby == 0:
		return
	var values: Variant = _settings.get("_values")
	if values is Dictionary:
		(values as Dictionary)["ponies/max_nearby"] = 0
		print("[unfplap test] nearby cap lifted from %d to unlimited for the loading screen" % _old_nearby)


func _restore_nearby_cap() -> void:
	if _old_nearby < 0 or not is_instance_valid(_settings):
		return
	var values: Variant = _settings.get("_values")
	if values is Dictionary:
		(values as Dictionary)["ponies/max_nearby"] = _old_nearby
	_old_nearby = -1


## Keep only the test ponies in this session's population config, before the loading screen
## starts spawning the rest. A test pony that the world's config does not list is assigned to
## Ponyville here, because membership in TEST_IDS alone never spawns anybody. The edit is in
## memory only; population.json is not saved.
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
	var added: Array[String] = []
	for id: String in TEST_IDS:
		if (assignments as Dictionary).has(id):
			continue
		(assignments as Dictionary)[id] = "ponyville"
		added.append(id)
	if not added.is_empty():
		print("[unfplap test] population assigned %s to ponyville" % ", ".join(PackedStringArray(added)))
	var removed: Array[String] = []
	for id: Variant in (assignments as Dictionary).keys():
		if TEST_IDS.has(str(id)):
			continue
		removed.append(str(id))
		(assignments as Dictionary).erase(id)
	if not removed.is_empty():
		print("[unfplap test] population restricted to %s (removed %d)" % [
			", ".join(PackedStringArray(TEST_IDS)), removed.size()])
	_place_missing_test_spawns(population)


## A test pony whose home point sits outside the 240 m activation radius never spawns, because
## the loading screen only brings out nearby candidates. Put her saved row at the library front
## with a fresh resume marker so the game's own spawn path places her there; the lab moves her
## into the row afterwards.
func _place_missing_test_spawns(population: Variant) -> void:
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
	for id: String in TEST_IDS:
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
		print("[unfplap test] %s spawn placed at the library; her home was %.0f m away" % [
			id, distance])


func _test_spawn_point() -> Vector3:
	var home := _library_home()
	if is_instance_valid(home) and home.has_method("outside"):
		return home.call("outside")
	if is_instance_valid(game) and is_instance_valid(game.get("player")):
		return (game.get("player") as Node3D).global_position
	return Vector3.INF


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The loading screen waits for every generated town house to finish furnishing, and they start
## 200 ms apart (house_interior._furnish_when_ready). That was the whole 16-20 s of lab startup.
## The lab only uses the authored Golden Oak library, which has its own room and guest bed, so
## stop the generated houses before their furnisher starts. Authored homes keep their furniture.
func _trim_generated_furnishing() -> void:
	if _furnishing_trimmed or not is_instance_valid(game):
		return
	var houses := get_tree().get_nodes_in_group("house_interiors")
	if houses.is_empty():
		return
	_furnishing_trimmed = true
	var stopped := 0
	for node: Variant in houses:
		var house: Node = node as Node
		if not is_instance_valid(house):
			continue
		# Authored homes (the library, boutique, cottage, ...) carry `home_kind` on themselves or
		# on an ancestor. Their interiors are not part of the generated-house wait.
		var authored := false
		var ancestor: Node = house
		while is_instance_valid(ancestor):
			if ancestor.get("home_kind") != null:
				authored = true
				break
			ancestor = ancestor.get_parent()
		if authored or not bool(house.get("furnish")):
			continue
		house.set("furnish", false)
		# A scheduled _do_furnish checks its generation, so bumping this stops the timer from
		# starting a furnisher after this point. One already running may finish, but the loading
		# wait no longer counts it because `furnish` is false.
		house.set("furnish_gen", int(house.get("furnish_gen")) + 1)
		stopped += 1
	print("[unfplap test] skipped generated house furnishing for %d houses; authored homes keep theirs" % stopped)


## A late filter can still leave a non-test pony already out. Retire those through the game's
## own despawn path after loading, then pause population so they cannot return.
func _prune_population() -> void:
	var population: Variant = game.get("population") if is_instance_valid(game) else null
	if not is_instance_valid(population):
		return
	var live: Variant = population.get("live")
	if not live is Dictionary:
		return
	for id: Variant in (live as Dictionary).keys():
		if TEST_IDS.has(str(id)):
			continue
		var entry: Variant = (live as Dictionary)[id]
		var actor: Variant = (entry as Dictionary).get("actor") if entry is Dictionary else null
		if is_instance_valid(actor) and game.has_method("_despawn_resident"):
			game.call("_despawn_resident", str(id), actor)
		(live as Dictionary).erase(id)
		print("[unfplap test] despawned non-test pony %s" % str(id))


## `pause_population = false` leaves the streamer running while everything else stops. The stress
## lab uses that between the loading screen and the end of its roster wait, so a slow spawn does
## not keep the full town simulation running at 13 fps.
func _stop_standard_systems(pause_population := true) -> void:
	if pause_population and is_instance_valid(game.get("population")):
		game.get("population").set_physics_process(false)
		game.get("population").set_process(false)
	if _standard_systems_stopped:
		return
	_standard_systems_stopped = true
	# The dialogue director must keep processing: it serializes every reply, so stopping it
	# leaves a pony stuck in "thinking" forever and blocks all later conversation. Silence the
	# world's own AI instead by switching this session to usage "talk": ambient group chatter,
	# approach greetings and lulls stop, while player-initiated replies and the act's generated
	# lines still run.
	var director: Variant = game.get("director")
	if is_instance_valid(director):
		var config: Variant = director.get("config")
		var data: Variant = config.get("data") if config != null else null
		if data is Dictionary:
			(data as Dictionary)["ai_usage"] = "talk"
			print("[unfplap test] director kept alive (processing=%s); background AI disabled (ai_usage=talk)" \
				% str(director.is_processing()))
	if is_instance_valid(game.get("life")):
		game.get("life").set_physics_process(false)
	if is_instance_valid(game.get("needs")):
		game.get("needs").set_physics_process(false)
	# Story visitors and Trixie's show can add their own characters; keep the town to the test set.
	# Day/night schedulers and the stuck rescue can still move or teleport them, so pause those too.
	for name: String in ["PrincessVisits", "TrixieShow", "DayRunner", "NightRest", "StuckRescue"]:
		var extra: Node = game.get_node_or_null(name)
		if extra != null:
			extra.set_physics_process(false)
			extra.set_process(false)
	var clock: Node = get_node_or_null("/root/TimeOfDay")
	if clock != null:
		clock.set("paused", true)


func _setup_ponies(ponies: Array) -> void:
	var impressions := _impressions()
	var xp: Dictionary = {}
	if is_instance_valid(impressions):
		var current: Variant = impressions.get("xp")
		if current is Dictionary:
			xp = current
		else:
			impressions.set("xp", xp)
	var rows := PackedStringArray()
	var home := _library_home()
	var index := 0
	var stranger_index := 0
	# Fallback placement only: a stranger without a snapshot row spawns away from the library row.
	var row_count := 0
	for pony_node: Variant in ponies:
		var pony: Node3D = pony_node as Node3D
		if not is_instance_valid(pony):
			continue
		if not TEST_STRANGERS.has(_pony_id(pony)):
			row_count += 1
	for pony_node: Variant in ponies:
		var pony: Node3D = pony_node as Node3D
		if not is_instance_valid(pony):
			continue
		var id := _pony_id(pony)
		if id.is_empty():
			continue
		var young := _is_young(pony)
		var stranger := TEST_STRANGERS.has(id)
		var friendship_xp := 0
		if is_instance_valid(impressions):
			var row: Dictionary = xp.get(id, impressions.call("xp_for", id))
			if stranger:
				row["friendship"] = 0
				if not young:
					row["romance"] = 0
			else:
				row["friendship"] = maxi(int(row.get("friendship", 0)), 500)
				if not young:
					row["romance"] = int(TEST_ROMANCE.get(id, 150))
			friendship_xp = int(row["friendship"])
			xp[id] = row
		if not young and not stranger:
			_set_dating_record(pony)
		if stranger:
			_forget_meeting(pony)
		_set_mood(pony, "neutral")
		_make_idle(pony, true)
		var spawn := "saved"
		if not _place_saved(pony, id):
			spawn = "row"
			if stranger:
				_place_stranger(pony, home, stranger_index)
			else:
				_place_front(pony, home, index, row_count)
		if stranger:
			stranger_index += 1
		else:
			index += 1
		if young:
			rows.append("%s young friendship_xp=%d pos=%s spawn=%s" % [
				id, friendship_xp, str(pony.global_position), spawn])
		elif stranger:
			rows.append("%s stranger friendship_xp=%d pos=%s spawn=%s" % [
				id, friendship_xp, str(pony.global_position), spawn])
		else:
			rows.append("%s romance_xp=%d level=%s pos=%s spawn=%s" % [
				id, int(TEST_ROMANCE.get(id, 150)), _love_name(pony, id),
				str(pony.global_position), spawn])
	var found := {}
	for pony_node: Variant in ponies:
		var pony: Node3D = pony_node as Node3D
		if is_instance_valid(pony):
			found[_pony_id(pony)] = true
	var missing := PackedStringArray()
	for id: String in TEST_IDS:
		if not found.has(id):
			missing.append(id)
	if not missing.is_empty():
		print("[unfplap test] missing test ponies: %s" % ", ".join(missing))
		# Why a requested pony never came out: assignment, spawn point and distance from the
		# player. A missing assignment or a point beyond the 240 m activation radius explains it.
		var population: Variant = game.get("population") if is_instance_valid(game) else null
		if is_instance_valid(population):
			var cfg: Variant = population.get("config")
			var assigned: Variant = cfg.get("assignments") if cfg != null else null
			var anchor: Variant = population.get("anchor")
			for id: String in missing:
				var where: Vector3 = population.call("candidate_position", id)
				var distance := -1.0
				if where.is_finite() and anchor is Node3D:
					distance = Vector2(where.x - (anchor as Node3D).global_position.x,
						where.z - (anchor as Node3D).global_position.z).length()
				print("	%s assigned=%s candidate=%s distance=%.1f" % [
					id, str((assigned as Dictionary).get(id, "")) if assigned is Dictionary else "?",
					str(where), distance])
	if not rows.is_empty():
		_log_action("test ponies", rows)
	if is_instance_valid(impressions):
		impressions.set("xp", xp)
	var history_section: Dictionary = ACT_HISTORY.section()
	var history_rows := PackedStringArray()
	for id: String in TEST_IDS:
		if ACT_HISTORY.reset(history_section, id):
			history_rows.append(id)
	if not history_rows.is_empty():
		ACT_HISTORY.save()
		_log_action("act history cleared", history_rows)
	var context: Variant = game.get("world_context")
	if is_instance_valid(context):
		context.call("_changed")


## Fallback for a stranger with no snapshot row: a separate nearby point, away from the row in
## front of the door.
func _place_stranger(pony: Node3D, home: Node3D, stranger_index: int) -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(home):
		return false
	if not home.has_method("outside"):
		return false
	var front: Vector3 = home.call("outside")
	var right: Vector3 = home.global_basis.x.normalized()
	var back: Vector3 = home.global_basis.z.normalized()
	# Side of the library, stepping each stranger apart so they do not overlap.
	var at := front + right * (4.0 + float(stranger_index) * 0.60) + back * (1.0 + float(stranger_index) * 0.40)
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1)
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


# --------------------------------------------------------------------------- hotkeys

## One action = one printed entry. The first line identifies the action; every following line
## starts with a tab so multi-line reports stay readable in the log.
func _log_action(title: String, rows: PackedStringArray) -> void:
	var text := "[unfplap test] " + title
	for row: String in rows:
		if row.is_empty():
			continue
		text += "\n\t" + row
	print(text)


## Split the runtime's `a | b | c` report into indented rows, optionally prefixed.
func _report_rows(text: String, prefix := "") -> PackedStringArray:
	var rows := PackedStringArray()
	for part: String in text.split(" | "):
		if part.is_empty():
			continue
		rows.append(part if prefix.is_empty() else prefix + part)
	return rows


func _input(event: InputEvent) -> void:
	if not is_instance_valid(game) or game.get("title_active") == true:
		return
	# Shift+[ / ] remains available after a menu released the mouse; the other lab hotkeys act
	# under the crosshair and still need normal play. Ctrl+[ is kept as an alias for layouts and
	# compositors that still deliver it as a bracket key instead of the historical Escape code.
	if event is InputEventKey:
		var cycle_key := event as InputEventKey
		var step := _cycle_step(cycle_key)
		if step != 0:
			if _text_entry_open():
				return
			if get_tree().paused:
				print("[unfplap test] cycle while paused: posture settles when the menu closes")
			_cycle_lab_mare(step)
			get_viewport().set_input_as_handled()
			return
		if cycle_key.pressed and not cycle_key.echo \
				and (cycle_key.ctrl_pressed or cycle_key.shift_pressed) \
				and (_is_bracket_code(cycle_key.physical_keycode)
					or _is_bracket_code(cycle_key.keycode)):
			print("[unfplap test] cycle key ignored: physical=%d keycode=%d unicode=%d ctrl=%s shift=%s paused=%s mouse=%s" % [
				cycle_key.physical_keycode, cycle_key.keycode, cycle_key.unicode,
				str(cycle_key.ctrl_pressed), str(cycle_key.shift_pressed),
				str(get_tree().paused), str(Input.mouse_mode)])
		elif cycle_key.pressed and not cycle_key.echo and cycle_key.ctrl_pressed \
				and (cycle_key.keycode == KEY_ESCAPE
					or cycle_key.physical_keycode == KEY_ESCAPE):
			print("[unfplap test] Ctrl+[ arrived as Escape (physical=%d keycode=%d unicode=%d); use Shift+[ / ]" % [
				cycle_key.physical_keycode, cycle_key.keycode, cycle_key.unicode])
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo or key.alt_pressed:
			return
		match key.physical_keycode:
			KEY_MINUS:
				_adjust_romance(-1)
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_PLUS:
				_adjust_romance(1)
				get_viewport().set_input_as_handled()
			KEY_9:
				_adjust_anger(-1)
				get_viewport().set_input_as_handled()
			KEY_0:
				_adjust_anger(1)
				get_viewport().set_input_as_handled()
			KEY_QUOTELEFT:
				_toggle_console()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		if mouse.button_index == MOUSE_BUTTON_XBUTTON1:
			_invite_target_to_bed()
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_XBUTTON2:
			_qualify_target()
			get_viewport().set_input_as_handled()


## One cycle step, or 0. Shift+[ / ] is the documented control; Ctrl+[ / ] still works where the
## event arrives as a bracket key. Ctrl+[ is the historical Escape control code on many systems,
## so it may never reach the game as a bracket at all.
func _cycle_step(key: InputEventKey) -> int:
	if not key.pressed or key.echo or key.alt_pressed:
		return 0
	if not (key.shift_pressed or key.ctrl_pressed):
		return 0
	if key.physical_keycode == KEY_BRACKETLEFT \
			or key.keycode in [KEY_BRACKETLEFT, KEY_BRACELEFT] or key.unicode in [91, 123]:
		return -1
	if key.physical_keycode == KEY_BRACKETRIGHT \
			or key.keycode in [KEY_BRACKETRIGHT, KEY_BRACERIGHT] or key.unicode in [93, 125]:
		return 1
	return 0


static func _is_bracket_code(code: int) -> bool:
	return code in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BRACELEFT, KEY_BRACERIGHT]


## A text field owns the keyboard: Shift+[ would type a brace, and the settings filter/chat box
## must not cycle the review mare.
func _text_entry_open() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return true
	if not is_instance_valid(game):
		return false
	var chat: Node = game.get_node_or_null("ChatBox")
	return chat != null and bool(chat.get("visible"))


## Shift+[ / ]: move the previous/next adult mare in front of Anon, facing away, standing idle.
## The eight starters stay live and the previous starter returns to her saved spot; a mare outside
## that roster is spawned through the population streamer on demand, and the previous non-starter
## is despawned so only one extra stays loaded.
func _cycle_lab_mare(step: int) -> void:
	if _cycle_busy:
		return
	_cycle_busy = true
	await _cycle_lab_mare_async(step)
	_cycle_busy = false


func _cycle_lab_mare_async(step: int) -> void:
	var ids := _cycle_ids()
	if ids.is_empty():
		print("[unfplap test] cycle: no adult mares in the population catalogue")
		return
	_lab_mare_index = wrapi(_lab_mare_index + step, 0, ids.size())
	var id := ids[_lab_mare_index]
	if _review_in_act():
		print("[unfplap test] cycle: %s is in an act; end it before cycling" % _review_id)
		return
	var pony := _find_live_pony(id)
	if not is_instance_valid(pony):
		if TEST_IDS.has(id):
			print("[unfplap test] cycle %s: starter is not live, spawning" % id)
		_release_extra_mare("")
		pony = await _spawn_lab_mare(id)
		if not is_instance_valid(pony):
			return
	else:
		_release_extra_mare(id)
		if not TEST_IDS.has(id):
			# She was already live (a manual spawn or a previous review). Track her as the one
			# extra so the next non-starter cycle despawns her too.
			_prepare_spawned_pony(pony)
			_extra_id = id
			_extra_mare = pony
	if not is_instance_valid(pony):
		return
	_restore_previous_review(id)
	_bring_to_anon(pony)
	_review_id = id
	_review_mare = pony
	print("[unfplap test] cycle %d/%d %s%s" % [
		_lab_mare_index + 1, ids.size(), id,
		"" if TEST_IDS.has(id) else " (non-starter)"])


## The eight starters first, then every other adult mare the population catalogue can spawn in
## the mod's settings order. Cached for the session.
func _cycle_ids() -> Array[String]:
	if not _cycle_ids_cache.is_empty():
		return _cycle_ids_cache
	var catalogue: Dictionary = LAB_POPULATION.catalogue()
	var ids: Array[String] = []
	for id: String in TEST_IDS:
		if catalogue.has(id):
			ids.append(id)
	for id: String in MOD_SETTINGS.CHARACTER_ORDER:
		if ids.has(id) or not catalogue.has(id):
			continue
		ids.append(id)
	_cycle_ids_cache = ids
	return _cycle_ids_cache


## The previous starter goes back to her saved standing spot, so only the current review mare is
## in front of Anon. A non-starter is despawned by `_release_extra_mare()` instead.
func _restore_previous_review(next_id: String) -> void:
	if _review_id.is_empty() or _review_id == next_id:
		return
	var id := _review_id
	var pony := _review_mare
	_review_id = ""
	_review_mare = null
	if not TEST_IDS.has(id) or not is_instance_valid(pony):
		return
	_clear_busy(pony)
	if not _place_saved(pony, id):
		var home := _library_home()
		if is_instance_valid(home):
			_place_front(pony, home, 0, 1)
	_make_idle(pony, true)
	print("[unfplap test] cycle returned %s to her saved spot" % id)


## The live actor for an id, or null. `game.mares` holds every spawned resident.
func _find_live_pony(id: String) -> Node3D:
	if id.is_empty() or not is_instance_valid(game):
		return null
	var list: Variant = game.get("mares")
	if list is Array:
		for node: Variant in list:
			if is_instance_valid(node) and _pony_id(node) == id:
				return node as Node3D
	return null


func _review_in_act() -> bool:
	if is_instance_valid(_review_mare) and _review_mare.has_meta("sex_active"):
		return true
	return is_instance_valid(_extra_mare) and _extra_mare.has_meta("sex_active")


## Despawn the one non-starter kept for review, unless it is the mare being kept. The in-memory
## population assignment and saved row are removed too, so the lab returns to its starter-only
## state until another mare is requested.
func _release_extra_mare(keep_id: String) -> void:
	if _extra_id.is_empty() or _extra_id == keep_id:
		return
	var id := _extra_id
	var pony: Node3D = _extra_mare if is_instance_valid(_extra_mare) else _find_live_pony(id)
	if is_instance_valid(pony):
		_clear_busy(pony)
		if is_instance_valid(game) and game.has_method("_despawn_resident"):
			game.call("_despawn_resident", id, pony)
	var population := _population()
	if is_instance_valid(population):
		_erase_population_id(population, id)
		_sync_life_roster(population)
	print("[unfplap test] cycle despawned %s" % id)
	_extra_id = ""
	_extra_mare = null
	if _review_id == id:
		_review_id = ""
		_review_mare = null


## Spawn one non-starter mare through the game's own streaming path, then give her the same
## starter state as the eight. The population is paused, so reconcile() is ticked by hand until
## the actor is live; the loader still runs one asynchronous spawn at a time.
func _spawn_lab_mare(id: String) -> Node3D:
	var population := _population()
	if not is_instance_valid(population):
		print("[unfplap test] cycle %s: no population streamer" % id)
		return null
	var at := _test_spawn_point()
	if not at.is_finite():
		print("[unfplap test] cycle %s: no spawn point" % id)
		return null
	var config: Variant = population.get("config")
	var assignments: Variant = config.get("assignments") if config != null else null
	if not assignments is Dictionary:
		print("[unfplap test] cycle %s: population has no assignments" % id)
		return null
	(assignments as Dictionary)[id] = "ponyville"
	var saved: Variant = population.get("saved")
	if saved is Dictionary:
		(saved as Dictionary)[id] = {"region": "ponyville", "position": at,
			"rotation": Vector3.ZERO, "resume": {}}
	_clear_population_blockers(population, id)
	_sync_life_roster(population)
	_lift_nearby_cap()
	print("[unfplap test] cycle %s spawning at %s" % [id, str(at)])
	var deadline := Time.get_ticks_msec() + 60000
	var pony: Node3D = null
	while Time.get_ticks_msec() < deadline and is_instance_valid(game) and is_inside_tree():
		pony = _find_live_pony(id)
		if is_instance_valid(pony):
			break
		population.call("reconcile")
		await get_tree().process_frame
	_restore_nearby_cap()
	if not is_instance_valid(pony):
		print("[unfplap test] cycle %s did not spawn: status=%s" % [
			id, str(population.get("status"))])
		return null
	if not TEST_IDS.has(id):
		_extra_id = id
		_extra_mare = pony
	_prepare_spawned_pony(pony)
	return pony


## The same starter state `_setup_ponies()` gives the eight: friendship, neutral mood, dating
## record and a standing idle posture. Act history is left alone: it lives in the mod's global
## state, not the lab world, and reviewing a dock must not clear the player's real history.
func _prepare_spawned_pony(pony: Node3D) -> void:
	var id := _pony_id(pony)
	_clear_busy(pony)
	var impressions := _impressions()
	if is_instance_valid(impressions):
		var stored: Variant = impressions.get("xp")
		var xp: Dictionary = stored if stored is Dictionary else {}
		if not stored is Dictionary:
			impressions.set("xp", xp)
		var row: Dictionary = xp.get(id, impressions.call("xp_for", id))
		row["friendship"] = maxi(int(row.get("friendship", 0)), 500)
		if not _is_young(pony):
			row["romance"] = int(TEST_ROMANCE.get(id, 150))
		xp[id] = row
		impressions.set("xp", xp)
	if not _is_young(pony):
		_set_dating_record(pony)
	_set_mood(pony, "neutral")
	_make_idle(pony, true)
	var context: Variant = game.get("world_context") if is_instance_valid(game) else null
	if is_instance_valid(context):
		context.call("_changed")


func _population() -> Node:
	if not is_instance_valid(game):
		return null
	var found: Variant = game.get("population")
	return found as Node if is_instance_valid(found) else null


func _clear_population_blockers(population: Node, id: String) -> void:
	for key: String in ["visiting", "retry_at", "_startup_failures", "status"]:
		var block: Variant = population.get(key)
		if block is Dictionary:
			(block as Dictionary).erase(id)


func _erase_population_id(population: Node, id: String) -> void:
	var live: Variant = population.get("live")
	if live is Dictionary:
		(live as Dictionary).erase(id)
	var config: Variant = population.get("config")
	var assignments: Variant = config.get("assignments") if config != null else null
	if assignments is Dictionary:
		(assignments as Dictionary).erase(id)
	var saved: Variant = population.get("saved")
	if saved is Dictionary:
		(saved as Dictionary).erase(id)
	_clear_population_blockers(population, id)


func _sync_life_roster(population: Node) -> void:
	var life: Variant = population.get("life")
	if is_instance_valid(life) and (life as Node).has_method("_sync_roster"):
		(life as Node).call("_sync_roster")


func _bring_to_anon(pony: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(game):
		return
	var body: Variant = game.get("player")
	if not is_instance_valid(body) or not body is Node3D:
		return
	var view: Variant = game.call("_find_camera", body) \
		if game.has_method("_find_camera") else null
	var forward: Vector3 = -(view as Camera3D).global_basis.z \
		if is_instance_valid(view) else -(body as Node3D).global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right: Vector3 = (view as Camera3D).global_basis.x \
		if is_instance_valid(view) else (body as Node3D).global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.000001:
		right = forward.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var at: Vector3 = (body as Node3D).global_position + forward * REVIEW_AHEAD_M \
		+ right * REVIEW_SIDE_M
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5,
		at + Vector3.DOWN * 4.0, 1, [pony.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		at = hit.get("position", at)
	_clear_busy(pony)
	pony.global_position = at
	var scale := pony.global_basis.get_scale()
	var away := Basis.looking_at(forward, Vector3.UP)
	var turned := Basis(Vector3.UP, deg_to_rad(REVIEW_TURN_DEG)) * away
	pony.global_transform = Transform3D(turned * Basis.from_scale(scale), at)
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	_upright(pony)
	_make_idle(pony, true)
	pony.reset_physics_interpolation()
	_log_action("lab mare", PackedStringArray([
		"%s pos=%s 3/4 rear view" % [_pony_id(pony), str(at)]]))


## Console is normally refused while the player's rest owns controls_locked. Open it with a
## temporary unlock so the lab can be inspected while lying on the bed.
func _toggle_console() -> void:
	var console: Node = game.get_node_or_null("CommandConsole") if is_instance_valid(game) else null
	if console == null:
		return
	if bool(console.get("visible")):
		# Already open (the console may have handled this same key first). Leaving it alone
		# avoids a double toggle; the console closes itself on the next backtick.
		return
	var body: Variant = game.get("player")
	var locked := false
	if is_instance_valid(body) and body.get("controls_locked") != null:
		locked = bool(body.get("controls_locked"))
		body.set("controls_locked", false)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_QUOTELEFT
	event.pressed = true
	console.call("_input", event)
	if not bool(console.get("visible")) and is_instance_valid(body):
		body.set("controls_locked", locked)


## Aiming at a test mare affects her only; otherwise the hotkeys apply to every test mare so a
## whole batch can be prepared without walking the crosshair over each one.
func _adjust_romance(step: int) -> void:
	var target := _target_under_aim()
	if is_instance_valid(target) and _is_young(target):
		_log_action("romance", PackedStringArray(["%s is young; no romance tier" % _pony_id(target)]))
		return
	var targets: Array = [target] if is_instance_valid(target) else _adult_test_ponies()
	if targets.is_empty():
		_log_action("romance", PackedStringArray(["no adult test mares loaded"]))
		return
	var rows := PackedStringArray()
	for pony: Variant in targets:
		rows.append(_set_romance(pony as Node3D, step))
	var title := "romance " + ("+" if step > 0 else "-")
	if is_instance_valid(target):
		title += " " + _pony_id(target)
	else:
		title += " (all test mares)"
	_log_action(title, rows)


func _set_romance(pony: Node3D, step: int) -> String:
	var id := _pony_id(pony)
	var impressions := _impressions()
	if not is_instance_valid(impressions):
		return "%s: no impressions" % id
	var stored: Variant = impressions.get("xp")
	var xp: Dictionary = stored if stored is Dictionary else {}
	if not stored is Dictionary:
		impressions.set("xp", xp)
	var row: Dictionary = xp.get(id, impressions.call("xp_for", id))
	var before := int(row.get("romance", 0))
	var tier := 0
	for i: int in ROMANCE_LEVELS.size():
		if before >= int(ROMANCE_LEVELS[i]):
			tier = i
	var next := clampi(tier + step, 0, ROMANCE_LEVELS.size() - 1)
	var value := int(ROMANCE_LEVELS[next])
	row["romance"] = value
	xp[id] = row
	impressions.set("xp", xp)
	var context: Variant = game.get("world_context")
	if is_instance_valid(context):
		context.call("_changed")
	return "%s xp %d -> %d tier=%d/%d level=%s" % [
		id, before, value, next, ROMANCE_LEVELS.size() - 1, _love_name(pony, id)]


func _adjust_anger(step: int) -> void:
	var target := _target_under_aim()
	var targets: Array = [target] if is_instance_valid(target) else _test_ponies()
	if targets.is_empty():
		_log_action("anger", PackedStringArray(["no test ponies loaded"]))
		return
	var rows := PackedStringArray()
	for pony: Variant in targets:
		rows.append(_set_anger(pony as Node3D, step))
	var title := "anger " + ("+" if step > 0 else "-")
	if is_instance_valid(target):
		title += " " + _pony_id(target)
	else:
		title += " (all test mares)"
	_log_action(title, rows)


func _set_anger(pony: Node3D, step: int) -> String:
	var id := _pony_id(pony)
	var impressions := _impressions()
	if not is_instance_valid(impressions):
		return "%s: no impressions" % id
	var before := str(impressions.call("profile", id).get("mood", "neutral"))
	var level := 0
	if before == "annoyed":
		level = 1
	elif before == "angry":
		level = 2
	var next := clampi(level + step, 0, ANGER_MOODS.size() - 1)
	var mood := str(ANGER_MOODS[next])
	impressions.call("commit", id, {"mood": mood},
		"unfplap-lab-mood:%s:%d" % [id, Time.get_ticks_usec()])
	# Show the same held face the refusal/stop paths use, so the anger keys are a real preview.
	var runtime: Node = pony.get_node_or_null("UnfplapRuntime")
	if runtime != null and runtime.has_method("_start_upset"):
		if next == 0:
			runtime.call("_end_upset")
		else:
			runtime.call("_start_upset", mood)
	var after := str(impressions.call("profile", id).get("mood", "neutral"))
	var anger := 0.0
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel != null and is_instance_valid(rel) and rel.get("bonds") != null:
		anger = float(rel.get("bonds").call("anger", id))
	return "%s mood %s -> %s (level %d/%d) anger=%.0f" % [
		id, before, after, next, ANGER_MOODS.size() - 1, anger]


func _invite_target_to_bed() -> void:
	var target := _target_under_aim()
	var bed := _treebrary_bed()
	if not is_instance_valid(bed):
		print("[unfplap test] Mouse4: no Golden Oak guest bed found")
		return
	var rest: Node3D = BED_REST.for_bed(bed)
	rest.call("refresh")
	var note := ""
	if not is_instance_valid(target):
		target = _nearest_test_pony(bed)
		note = "no mare under the crosshair; nearest test mare"
	if not is_instance_valid(target):
		print("[unfplap test] Mouse4: no test pony loaded")
		return
	var id := _pony_id(target)
	if _is_young(target):
		# A young pony is never a bed guest. Bring her to the bed front so she can witness an act
		# there, and stop before the invite.
		var rows := PackedStringArray()
		if _needs_bed_transport(target, bed):
			rows.append("transport=" + _bring_to_bed(target, rest))
			await get_tree().create_timer(0.7).timeout
			if not is_instance_valid(target) or not is_instance_valid(rest) or not is_inside_tree():
				return
			rows.append("grounded=" + _make_idle(target, true))
			rows.append("front=" + _bring_to_bed(target, rest))
		else:
			rows.append("idle=" + _make_idle(target, true))
		rows.append("young: witness position only, no invite")
		_log_action("Mouse4 " + id, rows)
		return
	var idle := _make_idle(target, true)
	var rows := PackedStringArray()
	if not note.is_empty():
		rows.append(note)
	rows.append("idle=" + idle)
	if _needs_bed_transport(target, bed):
		rows.append("transport=" + _bring_to_bed(target, rest))
		await get_tree().create_timer(0.7).timeout
		if not is_instance_valid(target) or not is_instance_valid(rest) or not is_inside_tree():
			return
		idle = _make_idle(target, true)
		rows.append("grounded=" + idle)
		# Recompute once she is inside: the first pass ran while she was outside the house,
		# where the bed-front height test cannot match her floor.
		rows.append("front=" + _bring_to_bed(target, rest))
	var lying := _ensure_player_lying(rest)
	rows.append("player=" + lying)
	if _player_lying():
		# Let the reclined avatar settle before inviting: the snuggle support takes its
		# landing height from the avatar's hip/head targets.
		await get_tree().create_timer(1.2).timeout
		if not is_instance_valid(target) or not is_instance_valid(rest) or not is_inside_tree():
			return
	rows.append_array(_report_rows(_cuddle_state(target, rest), "cuddle "))
	if not _player_lying():
		rows.append("Anon must be lying on the bed to cuddle")
		_log_action("Mouse4 " + id, rows)
		return
	var accepted := bool(rest.call("accept", target))
	rows.append("invite=" + str(accepted))
	_log_action("Mouse4 " + id, rows)
	_follow_cuddle(id, target, rest)


## The lab starts the mares outside the library. Bed eligibility needs the same floor and a
## short walk, so move the pointed mare to the guest-bed approach before inviting her.
func _needs_bed_transport(pony: Node3D, bed: Node3D) -> bool:
	var to_bed := pony.global_position - bed.global_position
	return Vector2(to_bed.x, to_bed.z).length() > 8.0 or absf(to_bed.y) > 0.5


func _nearest_test_pony(bed: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node: Variant in _adult_test_ponies():
		var pony: Node3D = node as Node3D
		if not is_instance_valid(pony):
			continue
		var distance := pony.global_position.distance_to(bed.global_position)
		if distance < best_distance:
			best = pony
			best_distance = distance
	return best


func _bring_to_bed(pony: Node3D, rest: Node3D) -> String:
	var front: Vector3 = rest.call("_front_for", pony)
	if not front.is_finite():
		var exit_at: Variant = rest.get("_exit")
		if exit_at is Vector3:
			front = exit_at
	if not front.is_finite():
		return "no floor beside the bed"
	pony.global_position = front
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	if pony.get("motion_paused") != null:
		pony.set("motion_paused", false)
	_upright(pony)
	pony.reset_physics_interpolation()
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		var travel: Variant = nav.get("house_travel")
		if travel != null and is_instance_valid(travel):
			travel.call("clear", pony)
		nav.call("stay")
		nav.set("command_owner", "")
		nav.set("wander_enabled", false)
	return str(front)


func _qualify_target() -> void:
	var target := _target_under_aim()
	if not is_instance_valid(target):
		print("[unfplap test] Mouse5: no test pony under the crosshair")
		return
	var id := _pony_id(target)
	if _is_young(target):
		print("[unfplap test] Mouse5: %s is the filly witness; no romance or sex-ready" % id)
		return
	var rows := PackedStringArray()
	rows.append("idle=" + _make_idle(target, true))
	rows.append("cleared=" + _clear_busy(target))
	rows.append("record=" + _set_dating_record(target))
	rows.append("mood=" + _set_mood(target, "neutral"))
	rows.append("romance untouched")
	_log_action("Mouse5 " + id, rows)
	_report_after_delay(target, "Mouse5 " + id)


func _report_after_delay(pony: Node3D, label: String) -> void:
	if not is_instance_valid(pony) or not is_inside_tree():
		return
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(pony) or not is_instance_valid(game) or not is_inside_tree():
		return
	_report_line(pony, label)


func _report_line(pony: Node3D, label: String) -> void:
	var runtime: Node = pony.get_node_or_null("UnfplapRuntime")
	if runtime == null:
		print("[unfplap test] %s report: no UnfplapRuntime" % label)
		return
	var view := _view_camera()
	var dist := -1.0
	var dot := -1.0
	if view != null:
		var delta: Vector3 = pony.global_position + Vector3.UP * 0.9 - view.global_position
		dist = delta.length()
		if dist > 0.001:
			dot = (-view.global_basis.z).dot(delta.normalized())
	# Match the runtime debug_line pose choice: a standing mare reports the standing gate; one
	# already lying reports the bed path so the report explains the pose the player would get.
	var pose := CATALOG.STANDING
	var source := ""
	var bed: Variant = null
	var status: Dictionary = pony.call("posture_status") if pony.has_method("posture_status") else {}
	if str(status.get("requested", "")) == "lie_down":
		pose = CATALOG.MISSIONARY
		source = "already_lying"
		bed = runtime.call("find_bed_under")
	var line := str(runtime.call("debug_line", pose, source, bed, dist, dot))
	_log_action(label + " report", _report_rows(line, "report "))


func _follow_cuddle(id: String, pony: Node3D, rest: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(rest) or not is_inside_tree():
		return
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(pony) or not is_instance_valid(rest) or not is_inside_tree():
		return
	var state := _guest_state(rest)
	var rows := _cuddle_follow_rows(pony, rest)
	if _cuddle_active(pony):
		_log_action("Mouse4 follow " + id, rows)
		return
	if state == "joining":
		rows.append("still walking to the bed; checking again")
		_log_action("Mouse4 follow " + id, rows)
		await get_tree().create_timer(6.0).timeout
		if not is_instance_valid(pony) or not is_instance_valid(rest) or not is_inside_tree():
			return
		var later := _cuddle_follow_rows(pony, rest)
		if _cuddle_active(pony):
			_log_action("Mouse4 follow " + id, later)
			return
		later.append_array(_report_rows(_cuddle_state(pony, rest), "cuddle "))
		_log_action("Mouse4 follow " + id, later)
		return
	rows.append_array(_report_rows(_cuddle_state(pony, rest), "cuddle "))
	_log_action("Mouse4 follow " + id, rows)


func _cuddle_follow_rows(pony: Node3D, rest: Node3D) -> PackedStringArray:
	return PackedStringArray([
		"guest=%s cuddle_active=%s couch_cuddle=%s session=%s" % [
			_guest_state(rest), str(_cuddle_active(pony)),
			str(pony.get_meta("couch_cuddle", false)), str(_cuddle_session(pony))],
	])


func _guest_state(rest: Node3D) -> String:
	var guest: Variant = rest.get("_guest") if rest != null else null
	return str((guest as Dictionary).get("state", "none")) \
		if guest is Dictionary and not (guest as Dictionary).is_empty() else "none"


func _cuddle_active(pony: Node3D) -> bool:
	if pony.get_meta("cuddle_active", false):
		return true
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session == null:
		return false
	var blend := 0.0
	if session.get("blend") != null:
		blend = float(session.get("blend"))
	return bool(session.get("enabled")) or blend > 0.0


func _cuddle_session(pony: Node3D) -> bool:
	var session: Node = pony.get_node_or_null("CuddleSession")
	return session != null and bool(session.get("enabled"))


# --------------------------------------------------------------------------- test helpers

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
			if TEST_IDS.has(id) and not by_id.has(id):
				by_id[id] = node
	for id: String in TEST_IDS:
		if by_id.has(id):
			out.append(by_id[id])
	if not _extra_id.is_empty() and not TEST_IDS.has(_extra_id) \
			and is_instance_valid(_extra_mare) and not out.has(_extra_mare):
		out.append(_extra_mare)
	return out


func _pony_id(pony: Variant) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str((pony as Node).get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = (pony as Node).get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


## The game's young flag: true for fillies and colts alike. Young test ponies never get a
## romance tier, a dating record, a romance hotkey or a bed invite.
func _is_young(pony: Variant) -> bool:
	if not is_instance_valid(pony):
		return false
	var identity: Variant = (pony as Node).get("identity")
	return identity != null and bool(identity.get("filly"))


func _adult_test_ponies() -> Array:
	return _test_ponies().filter(func(node: Variant) -> bool: return not _is_young(node))


func _impressions() -> Node:
	if not is_instance_valid(game):
		return null
	var context: Variant = game.get("world_context")
	if not is_instance_valid(context):
		return null
	var impressions: Variant = context.get("impressions")
	return impressions as Node if is_instance_valid(impressions) else null


func _love_name(pony: Node3D, id: String) -> String:
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel) or not rel.has_method("ladder"):
		return "?"
	var love: Dictionary = rel.call("ladder", id).get("love", {})
	return str(love.get("name", "?"))


func _set_dating_record(pony: Node3D) -> String:
	if _is_young(pony):
		return "young; no dating record"
	var id := _pony_id(pony)
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel):
		return "no relationship runtime"
	var bonds: Variant = rel.get("bonds")
	if bonds == null or not is_instance_valid(bonds) or not bonds.has_method("record_for"):
		return "no bonds"
	var row: Dictionary = bonds.call("record_for", id)
	var before := str(row.get("stage", "?"))
	row["stage"] = "dating"
	row["familiarity"] = maxf(float(row.get("familiarity", 0.0)), 80.0)
	row["trust"] = maxf(float(row.get("trust", 0.0)), 40.0)
	row["together_s"] = maxf(float(row.get("together_s", 0.0)), 3600.0)
	if row.get("plan") is Dictionary:
		row["plan"] = {}
	if row.get("offer") is Dictionary:
		row["offer"] = {}
	var stored: Variant = row.get("cooldowns", {})
	var cooldowns: Dictionary = stored if stored is Dictionary else {}
	cooldowns.erase("boundary")
	cooldowns.erase("dating")
	row["cooldowns"] = cooldowns
	bonds.call("_save", id, row)
	if bonds.has_method("mark_met"):
		bonds.call("mark_met", id)
	return "stage %s -> dating" % before


## Clear "met" knowledge so the pony reads as Stranger (friendship level 0). The lab reuses a
## saved test world, so a prior session's meeting receipt would otherwise keep her at Acquaintance.
func _forget_meeting(pony: Node3D) -> String:
	var id := _pony_id(pony)
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel):
		return "no relationship runtime"
	var bonds: Variant = rel.get("bonds")
	if bonds == null or not is_instance_valid(bonds):
		return "no bonds"
	var data: Variant = bonds.get("data")
	if not data is Dictionary:
		return "no bonds data"
	var knowledge: Variant = (data as Dictionary).get("knowledge", {})
	if not knowledge is Dictionary:
		return "no knowledge"
	var known: Dictionary = knowledge as Dictionary
	if not known.has(id):
		return "already unknown"
	known.erase(id)
	(data as Dictionary)["knowledge"] = known
	var context: Node = game.get("world_context") if is_instance_valid(game) else null
	if context == null:
		return "no world context"
	context.state.player_bonds = (data as Dictionary).duplicate(true)
	context.call("_changed")
	return "forgot meeting"


func _set_mood(pony: Node3D, mood: String) -> String:
	var id := _pony_id(pony)
	var impressions := _impressions()
	if not is_instance_valid(impressions):
		return "no impressions"
	var before := str(impressions.call("profile", id).get("mood", "neutral"))
	impressions.call("commit", id, {"mood": mood},
		"unfplap-lab-mood:%s:%d" % [id, Time.get_ticks_usec()])
	var after := str(impressions.call("profile", id).get("mood", "neutral"))
	return "%s -> %s" % [before, after]


## A saved test-world actor can carry a non-yaw transform from an old throw/cuddle. Reset the
## tilt while keeping the facing yaw; otherwise support recovery fights the tilted collider every
## tick and the body looks broken on every reload.
func _upright(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	var t := pony.global_transform
	var euler := t.basis.get_euler()
	if absf(euler.x) < 0.01 and absf(euler.z) < 0.01:
		return
	var yaw := euler.y
	var scale := t.basis.get_scale()
	t.basis = Basis(Vector3.UP, yaw) * Basis.from_scale(scale)
	pony.global_transform = t
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	pony.reset_physics_interpolation()
	print("[unfplap test] upright %s rot=(%.2f, %.2f, %.2f) -> yaw=%.2f" % [
		str(pony.name), euler.x, euler.y, euler.z, yaw])


func _make_idle(pony: Node3D, stand: bool) -> String:
	var notes := PackedStringArray()
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		nav.call("stay")
		if str(nav.get("command_owner")) != "":
			notes.append("owner " + str(nav.get("command_owner")))
			nav.set("command_owner", "")
		nav.set("wander_enabled", false)
		if str(nav.get("reserved_by")) != "":
			notes.append("reserved " + str(nav.get("reserved_by")))
			nav.set("reserved_by", "")
	if pony.has_meta("active_follow"):
		pony.remove_meta("active_follow")
	if pony.get("motion_paused") == true:
		pony.set("motion_paused", false)
	var status: Dictionary = pony.call("posture_status") if pony.has_method("posture_status") else {}
	if stand and str(status.get("requested", "")) != "stand":
		if pony.has_method("request_posture"):
			pony.call("request_posture", "stand")
			notes.append("stand requested")
	if stand:
		_upright(pony)
	return "none" if notes.is_empty() else ", ".join(notes)


func _clear_busy(pony: Node3D) -> String:
	var notes := PackedStringArray()
	var session: Node = pony.get_node_or_null("CuddleSession")
	var blend := 0.0
	if session != null and session.get("blend") != null:
		blend = float(session.get("blend"))
	if session != null and (bool(session.get("enabled")) or blend > 0.0):
		session.call("end", true)
		notes.append("cuddle ended")
	for meta: String in ["couch_cuddle", "cuddle_active", "sex_aftercare"]:
		if pony.has_meta(meta):
			pony.remove_meta(meta)
			notes.append("cleared " + meta)
	var runtime: Node = pony.get_node_or_null("UnfplapRuntime")
	if runtime != null and int(runtime.get("state")) == 0 and pony.has_meta("sex_active"):
		pony.remove_meta("sex_active")
		notes.append("cleared sex_active")
	return "none" if notes.is_empty() else ", ".join(notes)


func _player_lying() -> bool:
	var body: Variant = game.get("player") if is_instance_valid(game) else null
	return is_instance_valid(body) and bool((body as Node).get_meta("couch_sleeping", false))


## Mouse4 is the cuddle setup key: sit Anon on the bed's player seat and lie him back if needed.
## The normal sit path still enforces its 3 m reach, so the log asks the player to step closer
## rather than teleporting the rig.
func _ensure_player_lying(rest: Node3D) -> String:
	if _player_lying():
		return "already lying"
	var body: Variant = game.get("player") if is_instance_valid(game) else null
	if not is_instance_valid(body):
		return "no player"
	var seats: Variant = rest.get("seats") if rest != null else null
	if not seats is Array or (seats as Array).is_empty():
		return "bed has no player seat"
	var seat: Variant = (seats as Array)[0]
	if not is_instance_valid(seat):
		return "bed player seat invalid"
	if body.get("seat") != seat:
		if not body.has_method("sit_on"):
			return "player cannot sit"
		if not bool(body.call("sit_on", seat)):
			return "sit failed: move within 3 m of the bed"
	if not body.has_method("toggle_couch_sleep"):
		return "player cannot lie down"
	if not bool(body.call("toggle_couch_sleep")):
		return "lie-down failed"
	return "Anon sat and lay down"


func _library_home() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("house_interiors"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		if node.has_method("place_id") and str(node.call("place_id")) == "house:golden_oak_library":
			return node as Node3D
	return null


## Put her back on the spot she stood on in the save (TEST_SPAWNS): stored position and yaw, with
## a floor snap only when the hit is close to the saved height so a roof above her cannot pull her
## up. Returns false when she has no snapshot row, so the caller falls back to the library row.
func _place_saved(pony: Node3D, id: String) -> bool:
	if not is_instance_valid(pony):
		return false
	var row: Variant = TEST_SPAWNS.get(id)
	if not row is Array or (row as Array).size() != 2:
		return false
	var at: Vector3 = (row as Array)[0]
	var yaw := float((row as Array)[1])
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	query.exclude = [pony.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var floor_at: Vector3 = hit.get("position", at)
		if absf(floor_at.y - at.y) <= 0.6:
			at.y = floor_at.y
	var scale := pony.global_basis.get_scale()
	pony.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), at)
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	_upright(pony)
	pony.reset_physics_interpolation()
	return true


## Put the test ponies in a loose row on the path outside the library door (fallback only).
func _place_front(pony: Node3D, home: Node3D, index: int, count: int) -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(home):
		return false
	if not home.has_method("outside"):
		return false
	var front: Vector3 = home.call("outside")
	var right: Vector3 = home.global_basis.x.normalized()
	var back: Vector3 = home.global_basis.z.normalized()
	var at := front + right * ((float(index) - (float(count) - 1.0) * 0.5) * 0.80) + back * 0.80
	var space := pony.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1)
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


func _treebrary_bed() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("house_interiors"):
		if not node.has_method("place_id") or not node.has_method("ensure_bed"):
			continue
		if str(node.call("place_id")) != "house:golden_oak_library":
			continue
		var bed: Variant = node.call("ensure_bed", "guest")
		if bed is Node3D and is_instance_valid(bed):
			return bed as Node3D
	return null


func _view_camera() -> Camera3D:
	if is_instance_valid(game) and game.has_method("_find_camera"):
		var found: Variant = game.call("_find_camera", game.get("player"))
		if found is Camera3D and is_instance_valid(found):
			return found as Camera3D
	var camera := get_viewport().get_camera_3d()
	return camera if camera is Camera3D else null


func _target_under_aim() -> Node3D:
	var view := _view_camera()
	if view == null:
		return null
	var screen := get_viewport().get_visible_rect().size * 0.5
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		screen = get_viewport().get_mouse_position()
	var from := view.project_ray_origin(screen)
	var direction := view.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 8.0, 1)
	var body: Variant = game.get("player") if is_instance_valid(game) else null
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := view.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Variant = hit.get("collider")
		if collider is Node:
			for pony: Variant in _test_ponies():
				var actor: Node = pony as Node
				if is_instance_valid(actor) and (actor == collider or actor.is_ancestor_of(collider as Node)):
					return pony as Node3D
	return _aim_cone_target(view)


## Fallback when the ray misses a thin limb: the same forward cone the debug target picker uses,
## limited to test mares.
func _aim_cone_target(view: Camera3D) -> Node3D:
	var forward := -view.global_basis.z
	var best: Node3D = null
	var best_score := -INF
	for node: Variant in _test_ponies():
		var pony: Node3D = node as Node3D
		if not is_instance_valid(pony):
			continue
		var delta: Vector3 = pony.global_position + Vector3.UP * 0.9 - view.global_position
		var dist := delta.length()
		if dist > 6.0 or dist < 0.001:
			continue
		var dot := forward.dot(delta.normalized())
		if dot < 0.2:
			continue
		var score := dot - dist * 0.05
		if score > best_score:
			best_score = score
			best = pony
	return best


func _cuddle_state(pony: Node3D, rest: Node3D) -> String:
	var id := _pony_id(pony)
	var bed: Variant = rest.get("_bed") if rest != null else null
	var nav: Node = pony.get_node_or_null("Navigator")
	var guest: Variant = rest.get("_guest") if rest != null else null
	var sleeper: Variant = rest.get("_sleeper") if rest != null else null
	var seats: Variant = rest.get("seats") if rest != null else null
	var seat_free := false
	if seats is Array and (seats as Array).size() > 1:
		var seat: Variant = (seats as Array)[1]
		seat_free = is_instance_valid(seat) and bool(seat.call("free_for", pony))
	var dist := -1.0
	if is_instance_valid(bed):
		dist = pony.global_position.distance_to((bed as Node3D).global_position)
	var body_scale := 1.0
	if pony.get("body_scale") != null:
		body_scale = float(pony.get("body_scale"))
	var reasons := PackedStringArray()
	if not is_instance_valid(bed):
		reasons.append("no_bed")
	elif Vector2(pony.global_position.x - (bed as Node3D).global_position.x,
			pony.global_position.z - (bed as Node3D).global_position.z).length() > 8.0 \
			or absf(pony.global_position.y - (bed as Node3D).global_position.y) > 0.5:
		reasons.append("too_far")
	if pony.get("sleeping") == true:
		reasons.append("sleeping")
	if pony.get("_held") == true:
		reasons.append("held")
	if pony.get("motion_paused") == true:
		reasons.append("motion_paused")
	for meta: String in ["seating", "fishing_companion", "balloon_passenger", "cuddle_active"]:
		if pony.has_meta(meta):
			reasons.append("meta:" + meta)
	if pony.get_meta("affection_active", false):
		reasons.append("affection")
	if pony.has_method("action_interruption_reason") \
			and not str(pony.call("action_interruption_reason")).is_empty():
		reasons.append("interrupt")
	if pony.get("flight") != null and bool(pony.get("flight").active()):
		reasons.append("flight")
	if body_scale > 1.05:
		reasons.append("too_big")
	if nav == null:
		reasons.append("no_navigator")
	else:
		var owner := str(nav.get("command_owner"))
		var routine := owner.is_empty() or owner == "rest_after_command" \
			or owner.begins_with("life:") or owner.begins_with("bond:") or owner.begins_with("day:")
		if str(nav.get("reserved_by")) != "":
			reasons.append("nav_reserved")
		if bool(nav.get("_has_target")):
			reasons.append("nav_target")
		if not routine:
			reasons.append("nav_owner=" + owner)
	var willing := bool(rest.call("_willing", pony)) if rest != null else false
	if not willing:
		reasons.append("unwilling")
	if rest == null or not bool(rest.get("_mare_fits")):
		reasons.append("mare_fits")
	if is_instance_valid(sleeper):
		reasons.append("sleeper=" + str((sleeper as Node).name))
	if guest is Dictionary and not (guest as Dictionary).is_empty():
		reasons.append("guest=" + str((guest as Dictionary).get("state", "?")))
	if not seat_free:
		reasons.append("seat_busy")
	if not _player_lying():
		reasons.append("player_not_lying")
	return ("pony=%s bed=%s dist=%.2f eligible=%s player_lying=%s willing=%s mare_fits=%s "
		+ "seat_free=%s guest=%s sleeper=%s | nav owner=%s target=%s reserved=%s | reasons=%s") % [
		id, str((bed as Node).name) if is_instance_valid(bed) else "none", dist,
		str(rest.call("eligible", pony)) if rest != null else "no_rest", str(_player_lying()),
		str(willing), str(rest.get("_mare_fits")) if rest != null else "?",
		str(seat_free),
		str((guest as Dictionary).get("state", "?")) if guest is Dictionary \
			and not (guest as Dictionary).is_empty() else "none",
		str((sleeper as Node).name) if is_instance_valid(sleeper) else "none",
		str(nav.get("command_owner")) if nav != null else "?",
		str(bool(nav.get("_has_target"))) if nav != null else "?",
		str(nav.get("reserved_by")) if nav != null else "?",
		"none" if reasons.is_empty() else ", ".join(reasons)]


func _exit_tree() -> void:
	pass
