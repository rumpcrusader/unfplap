extends Node
## Unfplap: adult intimacy for consenting adult ponies at the Marefriend stage.
## The entry node owns the player HUD/input and one lightweight runtime per pony. It never edits
## game files; it only reads the game's pony, relationship, memory and bed APIs.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HUD := preload("res://mods/unfplap/hud.gd")
const INPUT := preload("res://mods/unfplap/input.gd")
const AI_OFFER := preload("res://mods/unfplap/ai_offer.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const CURRENCY := preload("res://world/ui/currency.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
## Mod setting: DEBUG LOGS. Persisted in user://mods/data/unfplap/settings.json.
## Default ON. Toggle in game with Ctrl+Shift+D.
var debug_logs := true

var game
var player
var hud
var input
var active_runtime

var _runtimes: Dictionary = {}
var _offer: Dictionary = {}
var _offer_clock := 0.0
var _ai_clock := 0.0
var _interactor: Node
var _desktop: Node
var _camera_cache: Camera3D
var _camera_cache_at := 0.0
## -1 = nothing pending; 0/1 = the controls_locked value to restore once menus close.
var pending_unlock := -1
var _last_offer_key := ""
var _native_hint_label: Label


func debug(text: String) -> void:
	if debug_logs:
		print("[unfplap] " + text)


func _debug(text: String) -> void:
	debug(text)


func toggle_debug_logs() -> void:
	debug_logs = not debug_logs
	SETTINGS.save_debug_logs(debug_logs)
	if debug_logs:
		print("[unfplap] debug logs ON")
	else:
		print("[unfplap] debug logs OFF")


func _ready() -> void:
	process_priority = 100
	set_process(true)
	debug_logs = SETTINGS.load_debug_logs()
	# Proves which build is live: a real source file has a non-zero mtime; a pack/PCK reports 0.
	var source_mtime := 0
	for path: String in [
			"res://mods/unfplap/runtime.gd",
			"res://mods/unfplap/pump.gd",
			"res://mods/unfplap/preferences.gd",
			"res://mods/unfplap/utterance.gd",
			"res://mods/unfplap/hud_pump.gd",
			"res://mods/unfplap/poses/skeleton_pose.gd",
			"res://mods/unfplap/poses/missionary_recipe.gd",
			"res://mods/unfplap/poses/horse_recipe.gd",
	]:
		source_mtime = maxi(source_mtime, FileAccess.get_modified_time(path))
	_debug("entry ready (debug logs %s) runtime_mtime=%d" % [
		"ON" if debug_logs else "OFF", source_mtime])
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	Mods.player_ready.connect(_on_player)
	Mods.on_node(PONY_PATH, _on_pony)
	# Switched on mid-game: the world and player already exist.
	if is_instance_valid(Mods.game):
		_on_world(Mods.game)
		var existing: Variant = Mods.game.get("player")
		if is_instance_valid(existing):
			_on_player(existing)


func _on_world(host: Node) -> void:
	_clear_native_hint()
	game = host
	_debug("world ready")
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0
	_offer = {}
	_ai_clock = 0.0
	if is_instance_valid(hud):
		hud.hide_all()


func _on_world_closed(_host: Node) -> void:
	_debug("world closed")
	_clear_native_hint()
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	game = null
	player = null
	_offer = {}
	if is_instance_valid(hud):
		hud.hide_all()


func _on_player(body: Node) -> void:
	player = body
	_debug("player ready")
	if not is_instance_valid(hud):
		hud = HUD.new()
		hud.name = "UnfplapHUD"
		add_child(hud)
	if not is_instance_valid(input):
		input = INPUT.new()
		input.name = "UnfplapInput"
		input.main = self
		add_child(input)


func _on_pony(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	if _runtimes.has(pony):
		return
	# The player's own AnonPony is a pony_locomotion too. Never attach an intimacy runtime to her.
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.set("pony", pony)
	runtime.set("main", self)
	pony.add_child(runtime)
	_runtimes[pony] = runtime
	_debug("runtime attached %s id=%s" % [str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


func _process(delta: float) -> void:
	if not is_instance_valid(player) and is_instance_valid(game):
		var body: Variant = game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active_runtime):
		active_runtime.apply_camera_motion()
		if is_instance_valid(hud):
			hud.update_from(active_runtime, debug_logs)
		_offer = {}
		_sync_native_hint(false)
		return

	_offer_clock += delta
	_ai_clock += delta
	if _offer_clock >= 0.15:
		_offer_clock = 0.0
		_refresh_offer()
	if _ai_clock >= 30.0:
		_ai_clock = 0.0
		AI_OFFER.tick(self)
	if _offer.is_empty():
		_last_offer_key = ""
		_sync_native_hint(false)
	else:
		_sync_native_hint(true)


func _refresh_offer() -> void:
	_offer = {}
	if not is_instance_valid(player) or not is_instance_valid(game):
		return
	if get_tree().paused:
		return
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = camera()
	if view == null:
		return
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var pony_form: bool = PLAYER_FORM.is_pony(form)

	# Pose 1 now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid pose-1 camera, so that entry is not offered.
	if not pony_form and is_instance_valid(player) and player.get("seat") != null:
		var lying: Node = _bedside_pony(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and runtime.can_start(CATALOG.MISSIONARY, "bed_side", bed):
					_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY, "source": "bed_side", "bed": bed}
					_log_offer()
					return

	# Pose 1, AnonPony: an awake pony already lying on a bed.
	if pony_form:
		var lying: Node = nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and runtime.can_start(CATALOG.MISSIONARY, "already_lying", bed):
					_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY, "source": "already_lying", "bed": bed}
					_log_offer()
					return

	# Pose 2: a settled standing pony in front of the player.
	var standing: Node = nearest_standing(view)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime) and runtime.can_start(CATALOG.HORSE, "", null):
			_offer = {"runtime": runtime, "pony": standing, "pose": CATALOG.HORSE, "source": "", "bed": null}
			_log_offer()


func _native_row() -> HBoxContainer:
	if not is_instance_valid(game):
		return null
	var hints: Node = game.get_node_or_null("InteractionHints")
	if hints == null:
		return null
	# VR uses the world-space prompt row; the L hint falls back to the HUD prompt there.
	if bool(hints.get("xr")):
		return null
	var row: Variant = hints.get("_prompt2d")
	if row is HBoxContainer and is_instance_valid(row):
		return row
	return null


func _make_native_hint_label() -> Label:
	var label := Label.new()
	label.text = "L · Intimate"
	CURRENCY.apply(label)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("f4f1ff"))
	label.add_theme_color_override("font_outline_color", Color("1a1624"))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _remove_native_hint(row: HBoxContainer = null) -> void:
	if is_instance_valid(_native_hint_label):
		var holder: Node = _native_hint_label.get_parent()
		if is_instance_valid(holder):
			holder.remove_child(_native_hint_label)
		_native_hint_label.queue_free()
	_native_hint_label = null
	if row != null and is_instance_valid(row):
		var parent: Node = row.get_parent()
		if is_instance_valid(parent) and parent is Control and row.get_child_count() == 0:
			(parent as Control).visible = false


func _clear_native_hint() -> void:
	_remove_native_hint(_native_row())


func _sync_native_hint(show_hint: bool) -> void:
	var row: HBoxContainer = _native_row()
	if row == null:
		if is_instance_valid(hud):
			if show_hint:
				hud.show_prompt("L · Intimate")
			else:
				hud.hide_prompt()
		return
	if not show_hint:
		_remove_native_hint(row)
		if is_instance_valid(hud):
			hud.hide_prompt()
		return
	if not is_instance_valid(_native_hint_label) or _native_hint_label.get_parent() != row or _native_hint_label.is_queued_for_deletion():
		_remove_native_hint(row)
		_native_hint_label = _make_native_hint_label()
		row.add_child(_native_hint_label)
	var parent: Node = row.get_parent()
	if parent is Control:
		(parent as Control).visible = true
	if is_instance_valid(hud):
		hud.hide_prompt()


func _log_offer() -> void:
	if _offer.is_empty():
		return
	var target: Variant = _offer.get("pony")
	var key := "%s:%s:%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		str(_offer.get("pose", "")), str(_offer.get("source", ""))]
	if key == _last_offer_key:
		return
	_last_offer_key = key
	_debug("OFFER pony=%s pose=%s legacy=%d source=%s bed=%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		str(_offer.get("pose", "")), CATALOG.legacy_index(str(_offer.get("pose", ""))),
		str(_offer.get("source", "")), str(_offer.get("bed"))])


func _debug_target(view: Camera3D) -> Node:
	if not is_instance_valid(player) or not is_instance_valid(game):
		return null
	var pony_form := PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	if not pony_form:
		var reach: Node = interactor()
		if is_instance_valid(reach) and reach.get("cradled") == true:
			var held: Variant = reach.get("held")
			if held is Node3D and is_instance_valid(held):
				return held
	var forward := -view.global_basis.z
	var best = null
	var best_score := -INF
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null:
			continue
		var at: Vector3 = actor.global_position + Vector3.UP * 0.9
		var delta: Vector3 = at - view.global_position
		var dist: float = delta.length()
		if dist > 6.0:
			continue
		var dot: float = forward.dot(delta.normalized()) if dist > 0.001 else 0.0
		if dot < 0.2:
			continue
		var score: float = dot - dist * 0.05
		if score > best_score:
			best_score = score
			best = actor
	return best


func _debug_bed_state() -> void:
	if not is_instance_valid(player):
		return
	var seat: Variant = player.get("seat")
	if not is_instance_valid(seat):
		_debug("bed: seat=null")
		return
	var couch: Variant = seat.get_meta("couch") if seat.has_meta("couch") else null
	if not is_instance_valid(couch):
		_debug("bed: seat=%s couch=null" % str(seat.name))
		return
	var guest: Variant = couch.get("_guest")
	var sleeper: Variant = couch.get("_sleeper")
	_debug("bed: seat=%s couch=%s fits=%s side=%.2f guest=%s sleeper=%s mare_front=%s mare_rest=%s" % [
		str(seat.name), str(couch.name), str(couch.get("_mare_fits")), float(couch.get("_side")),
		str((guest as Dictionary).get("state", "?")) if guest is Dictionary and not (guest as Dictionary).is_empty() else "none",
		str(sleeper.name) if is_instance_valid(sleeper) else "null",
		str(couch.get("_mare_front")), str(couch.get("_mare_rest"))])


func _debug_offer() -> void:
	if not debug_logs:
		return
	if not is_instance_valid(player) or not is_instance_valid(game):
		return
	_debug_bed_state()
	var view: Camera3D = camera()
	if view == null:
		_debug("debug camera=null")
		return
	var target = _debug_target(view)
	if target == null:
		_debug("debug nearest=none locked=%s mouse=%s paused=%s menu=%s" % [
			str(player.get("controls_locked")), str(Input.mouse_mode), str(get_tree().paused),
			str(menu_open())])
		return
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		_debug("debug nearest=%s no runtime" % str(target.name))
		return
	var pony_form := PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	var pose := CATALOG.HORSE
	var source := ""
	var bed: Variant = null
	var reach: Node = interactor()
	if not pony_form and is_instance_valid(reach) and reach.get("held") == target and reach.get("cradled") == true:
		pose = CATALOG.MISSIONARY
		source = "cradle"
		bed = bed_for_cradle(target)
	elif str(target.call("posture_status").get("requested")) == "lie_down":
		pose = CATALOG.MISSIONARY
		source = "already_lying"
		bed = runtime.call("find_bed_under")
	var delta: Vector3 = target.global_position + Vector3.UP * 0.9 - view.global_position
	var dist: float = delta.length()
	var dot: float = (-view.global_basis.z).dot(delta.normalized()) if dist > 0.001 else 0.0
	var line := str(runtime.call("debug_line", pose, source, bed, dist, dot))
	_debug("DEBUG nearest = " + line)


func try_start() -> bool:
	if is_instance_valid(active_runtime):
		return false
	_refresh_offer()
	if _offer.is_empty():
		return _try_refusal()
	var runtime: Variant = _offer.get("runtime")
	if not is_instance_valid(runtime):
		return false
	var started: bool = runtime.start(str(_offer.get("pose", "")), _offer.get("bed"), str(_offer.get("source", "")))
	if started:
		_offer = {}
		if is_instance_valid(hud):
			hud.hide_prompt()
	return started


func debug_pose1_float() -> void:
	if not debug_logs:
		return
	var target: Node = _debug_target(camera())
	if not is_instance_valid(target):
		_debug("float pose1: no pony target")
		return
	var runtime: Node = runtime_for(target)
	if not is_instance_valid(runtime):
		_debug("float pose1: no runtime")
		return
	runtime.call("debug_float_pose1", 3.0)


func _try_refusal() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(game):
		return false
	if get_tree().paused:
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var view: Camera3D = camera()
	if view == null:
		return false
	var pony_form: bool = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	if not pony_form:
		var reach: Node = interactor()
		if is_instance_valid(reach) and reach.get("cradled") == true:
			var held: Variant = reach.get("held")
			if held is Node3D and is_instance_valid(held):
				var runtime: Node = runtime_for(held)
				if is_instance_valid(runtime):
					var bed: Node3D = bed_for_cradle(held)
					if bed != null and bool(runtime.call("refuse_available", CATALOG.MISSIONARY, "cradle", bed)):
						runtime.call("refuse", CATALOG.MISSIONARY, "cradle", bed)
						return true
	if pony_form:
		var lying: Node = nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Variant = runtime.call("find_bed_under")
				if bed is Node3D and bool(runtime.call("refuse_available", CATALOG.MISSIONARY, "already_lying", bed)):
					runtime.call("refuse", CATALOG.MISSIONARY, "already_lying", bed)
					return true
	var standing: Node = nearest_standing(view)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime) and bool(runtime.call("refuse_available", CATALOG.HORSE, "", null)):
			runtime.call("refuse", CATALOG.HORSE, "", null)
			return true
	return false


func allocate_serial() -> int:
	var section: Dictionary = Mods.state("unfplap")
	var value: int = int(section.get("serial", 0)) + 1
	section["serial"] = value
	Mods.save_changed()
	return value


func set_active(runtime: Node) -> void:
	active_runtime = runtime
	_offer = {}


func clear_active(runtime: Node) -> void:
	if active_runtime == runtime:
		active_runtime = null


func camera() -> Camera3D:
	if not is_instance_valid(player):
		return null
	var direct: Variant = player.get("camera")
	if direct is Camera3D and is_instance_valid(direct):
		return direct
	var now := Time.get_ticks_msec() * 0.001
	if is_instance_valid(_camera_cache) and now - _camera_cache_at < 1.0:
		return _camera_cache
	if is_instance_valid(game) and game.has_method("_find_camera"):
		var found: Variant = game.call("_find_camera", player)
		if found is Camera3D and is_instance_valid(found):
			_camera_cache = found
			_camera_cache_at = now
			return found
	var current: Camera3D = get_viewport().get_camera_3d()
	_camera_cache = current
	_camera_cache_at = now
	return current


func interactor() -> Node:
	if is_instance_valid(_interactor):
		return _interactor
	if not is_instance_valid(player):
		return null
	for node: Node in player.find_children("*", "", true, false):
		var script: Variant = node.get_script()
		if script != null and str(script.resource_path) == INTERACTOR_PATH:
			_interactor = node
			return node
	return null


func desktop() -> Node:
	if is_instance_valid(_desktop):
		return _desktop
	_desktop = get_tree().get_first_node_in_group("desktop_interactions")
	return _desktop


func player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var form: Variant = player.get("form_driver")
	if form != null and is_instance_valid(form):
		var avatar: Variant = form.get("avatar")
		if avatar is Node3D and is_instance_valid(avatar):
			return avatar
	var body: Variant = player.find_child("Body", true, false)
	if body is Node3D and is_instance_valid(body):
		return body
	return player as Node3D


func mares() -> Array:
	if is_instance_valid(game):
		var list: Variant = game.get("mares")
		if list is Array:
			return list
	return []


func runtime_for(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var runtime: Variant = _runtimes.get(pony)
	if is_instance_valid(runtime):
		return runtime
	var child: Node = pony.get_node_or_null("UnfplapRuntime")
	return child if is_instance_valid(child) else null


func bed_under(point: Vector3, exclude: RID = RID()) -> Node3D:
	var world: World3D = null
	if is_instance_valid(player):
		world = player.get_world_3d()
	if world == null:
		world = get_viewport().world_3d
	if world == null:
		return null
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return null
	for lift: float in [0.6, 0.35, 0.15]:
		var from := point + Vector3.UP * lift
		var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * 2.5, 1)
		if exclude.is_valid():
			query.exclude = [exclude]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var bed: Node3D = MATTRESS.bed_of(hit.get("collider"))
		if bed != null:
			return bed
	return null


func bed_for_cradle(pony: Node3D) -> Node3D:
	if not is_instance_valid(pony):
		return null
	var exclude: RID = (pony as CollisionObject3D).get_rid() if pony is CollisionObject3D else RID()
	var down: Node3D = bed_under(pony.global_position, exclude)
	if down != null:
		return down
	var view: Camera3D = camera()
	if view == null:
		return null
	var space: PhysicsDirectSpaceState3D = view.get_world_3d().direct_space_state
	if space == null:
		return null
	var from := view.global_position
	var to := from - view.global_basis.z * 3.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if exclude.is_valid():
		query.exclude = [exclude]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	return MATTRESS.bed_of(hit.get("collider"))


func bed_occupied(bed: Node3D, target: Node) -> bool:
	if not is_instance_valid(bed):
		return false
	var top := float(bed.get_meta("mattress_top", 0.6))
	var at := bed.to_global(Vector3(0.0, top, 0.0))
	for node: Variant in mares():
		if not is_instance_valid(node) or node == target:
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		if absf(actor.global_position.y - at.y) > 0.55:
			continue
		if Vector2(actor.global_position.x - at.x, actor.global_position.z - at.z).length() > 1.3:
			continue
		return true
	return false


func player_beside_bed(bed: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var seat: Variant = player.get("seat")
	if seat == null or not is_instance_valid(seat):
		return true
	if not is_instance_valid(bed):
		return true
	if seat is Node3D and (seat as Node3D).get_parent() == bed:
		return true
	if seat is Node3D and (seat as Node3D).has_meta("couch"):
		var couch: Variant = (seat as Node3D).get_meta("couch")
		if is_instance_valid(couch):
			var bed_node: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
			if bed_node == bed:
				return true
			if is_instance_valid(bed_node) and (bed_node as Node3D).is_ancestor_of(seat as Node):
				return true
	return false


func house_at(point: Vector3) -> Node3D:
	return HOUSE.at(get_tree(), point)


func menu_open() -> bool:
	if get_tree().paused:
		return true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	if not is_instance_valid(game):
		return false
	for key: String in ["save_menu", "settings_menu", "pause_menu"]:
		var panel: Variant = game.get(key)
		if is_instance_valid(panel) and bool(panel.get("opened")):
			return true
	var inventory: Variant = game.get("inventory")
	if not is_instance_valid(inventory):
		return false
	if inventory.has_method("_map_open") and bool(inventory.call("_map_open")):
		return true
	var case: Variant = inventory.get("case")
	if is_instance_valid(case) and bool(case.get("visible")):
		return true
	var customizer: Variant = inventory.get("customizer")
	if is_instance_valid(customizer) and bool(customizer.get("opened")):
		return true
	var inspector: Variant = inventory.get("inspector")
	if is_instance_valid(inspector) and bool(inspector.get("active")):
		return true
	return false


func _bedside_pony(view: Camera3D) -> Node:
	# The player's bed/couch seat knows exactly who lies beside Anon.
	if is_instance_valid(player):
		var seat: Variant = player.get("seat")
		if is_instance_valid(seat) and seat.has_meta("couch"):
			var couch: Variant = seat.get_meta("couch")
			if is_instance_valid(couch) and couch.has_method("partner"):
				var partner: Variant = couch.call("partner", seat)
				if partner is Node and is_instance_valid(partner):
					return partner
	return null


func nearest_standing(view: Camera3D) -> Node:
	if view == null:
		return null
	var best: Node
	var best_dot := 0.82
	var forward := -view.global_basis.z
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "stand":
			continue
		var at := actor.global_position + Vector3.UP * 0.9
		var delta := at - view.global_position
		if delta.length() > 2.5:
			continue
		var dot := forward.dot(delta.normalized())
		if dot > best_dot:
			best_dot = dot
			best = actor
	return best


func nearest_lying(view: Camera3D) -> Node:
	if view == null:
		return null
	var best: Node
	var best_dot := 0.78
	var forward := -view.global_basis.z
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		var at := actor.global_position + Vector3.UP * 0.5
		var delta := at - view.global_position
		if delta.length() > 3.2:
			continue
		var dot := forward.dot(delta.normalized())
		if dot > best_dot:
			best_dot = dot
			best = actor
	return best


func _exit_tree() -> void:
	_clear_native_hint()
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtime.force_stop()
			runtime.queue_free()
	_runtimes.clear()
	_offer = {}
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
