extends Node
## Unfplap manual test lab. Run with:
##   ./lab.sh
## The session is written to last-run.log beside the script.
##
## Loads only Twilight, Fluttershy, Rarity, Derpy and Diamond Tiara and pauses population/living-world/time
## plus background AI. At setup they are moved to the path in front of Golden Oak Library.
## Diamond Tiara is the filly witness fixture: no romance tier or dating record, never invited to bed.
## No extra bed is spawned: use the Golden Oak guest bed in the treebrary. The dialogue director
## stays running, because it serializes replies and a stopped director leaves ponies stuck
## "thinking".
##
## Lab hotkeys (mouse must be captured, like normal play):
##   - / =       lower / raise the pointed mare's romance tier (all test mares when not aiming)
##   9 / 0       lower / raise the pointed mare's anger mood (all test mares when not aiming)
##   Mouse 4     invite a test mare to the treebrary bed; a far mare is moved to the bed approach
##               first, and the log says why cuddling cannot start
##   Mouse 5     make the pointed adult mare idle, grant the lover bond and qualify for sex
##               without changing her romance tier

const BED_REST := preload("res://world/relationships/shared_bed.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const TEST_IDS := ["twilight_sparkle", "fluttershy", "rarity", "derpy_hooves", "diamond_tiara"]
## Starting love XP: 0 = New Couple and below the sex gate, 150 = Marefriend, 400 = Head Over
## Hooves, 900 = the dating maximum (Soulmates still needs marriage). The -/= keys step these.
## Diamond Tiara is young and never gets entries here.
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
	"restrict population to Twilight, Fluttershy, Rarity, Derpy and Diamond Tiara (memory only)",
	"despawn any other resident already live in the world",
	"keep the dialogue director alive with ai_usage=talk",
	"pause population, life and needs",
	"pause PrincessVisits, TrixieShow, DayRunner, NightRest and StuckRescue",
	"pause TimeOfDay",
	"set friendship >= 500, neutral mood and idle for every test pony",
	"set romance tier and dating record only for the four adult test mares",
	"leave lover bonds unset; Mouse5 grants one",
	"spawn no bed; use the Golden Oak guest bed",
]

var game: Node
var _done := false
var _old_opening := ""
var _settings: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The title screen adds this lab before starting the game scene. Skip the opening tutorial
	# before the arrival story reads the setting, then restore the player's preference afterwards.
	_settings = get_node_or_null("/root/Settings")
	if _settings != null:
		_old_opening = str(_settings.get_value("world/opening"))
		_settings.set_value("world/opening", "skip")
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
	print("[unfplap test] E sit, Ctrl lie back; test ponies teleported in front of the library")
	print("[unfplap test] -/= romance tier (adults), 9/0 anger mood, Mouse4 bed (adults) or witness spot (filly), Mouse5 sex-ready (grants lover bond)")
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


## Keep only the five test ponies in this session's population config, before the loading
## screen starts spawning the rest. The edit is in memory only; population.json is not saved.
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
	var removed: Array[String] = []
	for id: Variant in (assignments as Dictionary).keys():
		if TEST_IDS.has(str(id)):
			continue
		removed.append(str(id))
		(assignments as Dictionary).erase(id)
	if not removed.is_empty():
		print("[unfplap test] population restricted to %s (removed %d)" % [
			", ".join(PackedStringArray(TEST_IDS)), removed.size()])


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


func _stop_standard_systems() -> void:
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
	if is_instance_valid(game.get("population")):
		game.get("population").set_physics_process(false)
		game.get("population").set_process(false)
	if is_instance_valid(game.get("life")):
		game.get("life").set_physics_process(false)
	if is_instance_valid(game.get("needs")):
		game.get("needs").set_physics_process(false)
	# Story visitors and Trixie's show can add their own characters; keep the town to the five.
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
	for pony_node: Variant in ponies:
		var pony: Node3D = pony_node as Node3D
		if not is_instance_valid(pony):
			continue
		var id := _pony_id(pony)
		if id.is_empty():
			continue
		var young := _is_young(pony)
		var friendship_xp := 0
		if is_instance_valid(impressions):
			var row: Dictionary = xp.get(id, impressions.call("xp_for", id))
			row["friendship"] = maxi(int(row.get("friendship", 0)), 500)
			friendship_xp = int(row["friendship"])
			if not young:
				row["romance"] = int(TEST_ROMANCE.get(id, 150))
			xp[id] = row
		if not young:
			_set_dating_record(pony)
		_set_mood(pony, "neutral")
		_make_idle(pony, true)
		var placed := _place_front(pony, home, index, ponies.size())
		index += 1
		if young:
			rows.append("%s young friendship_xp=%d pos=%s front=%s" % [
				id, friendship_xp, str(pony.global_position), str(placed)])
		else:
			rows.append("%s romance_xp=%d level=%s pos=%s front=%s" % [
				id, int(TEST_ROMANCE.get(id, 150)), _love_name(pony, id),
				str(pony.global_position), str(placed)])
	if not rows.is_empty():
		_log_action("test ponies", rows)
	if is_instance_valid(impressions):
		impressions.set("xp", xp)
	var context: Variant = game.get("world_context")
	if is_instance_valid(context):
		context.call("_changed")


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
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo or key.alt_pressed or key.ctrl_pressed:
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
	var runtime: Node = target.get_node_or_null("UnfplapRuntime")
	if runtime != null and runtime.has_method("grant_sex_bond"):
		rows.append("bond=" + str(runtime.call("grant_sex_bond", "lab", "")))
	else:
		rows.append("bond=no runtime")
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


## Put the test ponies in a loose row on the path outside the library door.
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
