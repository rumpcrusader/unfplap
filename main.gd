extends Node
## unfplap mod entry.
## The entry node owns the player HUD/input and one lightweight runtime per pony. It never edits
## game files; it only reads the game's pony, relationship, memory and bed APIs.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const INPUT := preload("res://mods/unfplap/input/service.gd")
const INITIATION := preload("res://mods/unfplap/initiation/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const ADAPTER := preload("res://mods/unfplap/negotiation/adapter.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")
const CLASSIFIER := preload("res://mods/unfplap/initiation/classifier.gd")
const DEBUG_SKELETON := preload("res://mods/unfplap/debug/skeleton.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const DEBUG_BED := preload("res://mods/unfplap/debug/bed.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")
const DEBUG_WHEEL := preload("res://mods/unfplap/debug/wheel.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const PANTYHOSE := preload("res://mods/unfplap/integrations/pantyhose.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const DEBUG_UI := preload("res://mods/unfplap/debug/ui.gd")
const API := preload("res://mods/unfplap/api.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0
## The offer hint beside the game's prompt row: a single act-key press starts the act, so it reads
## like the base game's tap prompts ("G · Carry"), not a hold. Only holding the act key during an
## act is a hold.
const OFFER_HINT := "Make love"
## The standing-act note when her reach needs a footstool and Anon has none in the case.
const NEEDS_STOOL_HINT := "Needs a footstool"
## Debug target rule: the mare closest to the camera's aim ray, inside this tube and range.
const AIM_RANGE_M := 8.0
const AIM_TUBE_M := 1.5
## Mod setting: DEBUG LOGS. Persisted in user://mods/data/unfplap/settings.json.
## Default OFF. Toggle in the Debug settings tab.
var debug_logs := false
var debug_perf := false

var game
var player
var hud
var input
## Cross-mod API facade; see docs/api.md.
var api: Node
## Anatomy system facade: per-pony controllers, the player part and tail seating.
var anatomy: Node
## The Pantyhose & Panties world adapter; inert when that pack is absent.
var pantyhose: Node
## Footstool system facade: the standing reach rule, item, act prop and world supply.
var stool: Node
var _anatomy_status_label: Label
var initiation
var privacy: PRIVACY
var classifier
## The one director and model bridge: the Proactive service and the Negotiation Host share it.
## See `docs/negotiation.md` (`## Director and model host`).
var adapter: Node
## The Act Negotiation service: the Anon offer, the Mare exchange, the Agreement and the lock.
var negotiation: Node
var active_runtime
## Internal eligibility service; see docs/eligibility.md. Never part of the cross-mod API.
var eligibility: ELIGIBILITY
## Internal memory service: act events, impressions, witnesses and the mod's own lines.
## See docs/memory.md. Never part of the cross-mod API.
var memory: MEMORY

var _runtimes: Dictionary = {}
## The idle scan's playable offer and its blocked variant. Both are typed `PoseOffer` handles;
## null means none. See `start_pose_offer()`.
var _offer: POSE_OFFER = null
var _offer_blocked: POSE_OFFER = null
var _offer_clock := 0.0
var _interactor: Node
var _desktop: Node
var _camera_cache: Camera3D
var _camera_cache_at := 0.0
var _last_offer_key := ""
var _last_blocked_key := ""
var _stool_hint_toast_shown := false
var _native_hint_label: Control
var _native_hint_text := ""
var _dance_hint_shown := false
var _debug_skeleton: Node3D
var _debug_wheel: CanvasLayer
var _debug_face_index := -1
## instance id -> WeakRef for every SpeechCaption the mod may move to the top.
var _captions: Dictionary = {}
## Cached captions_on_top so the per-frame caption tick never rereads settings.json.
var _captions_on_top := false
## The idle (outside-act) debug perf probe; see docs/perf.md.
var _perf_idle := PERF_IDLE.new()
## True while the adapter's global Anon-offer watch is armed.
var _watching_player := false
## The Agreement auto-start's 0.25 s readiness clock.
var _agreement_clock := 0.0


func debug(text: String) -> void:
	if debug_logs:
		print("[unfplap] " + text)


## Live act/afterglow context for the game's normal dialogue prompt (pony_prompt_notes).
func prompt_note(pony: String) -> String:
	if pony.is_empty():
		return ""
	for runtime: Variant in _runtimes.values():
		if not is_instance_valid(runtime):
			continue
		runtime.call("_read_id")
		var runtime_id := str(runtime.get("_id"))
		if runtime_id.is_empty():
			var target: Variant = runtime.get("pony")
			if is_instance_valid(target):
				runtime_id = ANATOMY.pony_id(target)
		if runtime_id != pony:
			continue
		var note := str(runtime.call("prompt_note"))
		var cycle := str(runtime.call("cycle_note"))
		if not cycle.is_empty():
			note = cycle if note.is_empty() else note + " " + cycle
		return note
	return ""


func _debug(text: String) -> void:
	debug(text)


## Debug idle perf probe. Idle runtimes report their timed chunks here; `shared/perf_idle.gd` prints
## one aggregated block a second while no act runs. See docs/perf.md.
func perf_idle_note(key: String, usec: int, owner := "") -> void:
	_perf_idle.note(key, usec, owner)


func _perf_idle_on() -> bool:
	return debug_logs and debug_perf and not is_instance_valid(active_runtime)


## Header counts for one idle block. Read once per window, never per note.
func _perf_idle_counts() -> Dictionary:
	var runtimes := 0
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtimes += 1
	return {"runtimes": runtimes, "mares": mares().size()}


## One entry per diagnostic action: identification first, then tab-indented rows.
func _debug_block(title: String, rows: Array) -> void:
	var text := title
	for row: Variant in rows:
		var line := str(row)
		if line.is_empty():
			continue
		text += "\n\t" + line
	debug(text)


func _ready() -> void:
	process_priority = 100
	set_process(true)
	# Load, migrate, merge and write the player file before any getter runs: the hot read path
	# must never touch the disk. A broken shipped document is a build error, so log it once and
	# install no hooks; the settings module already named the first offending path.
	if not SETTINGS.load_settings():
		push_error("unfplap: shipped settings data is invalid; the mod is not loading")
		set_process(false)
		return
	add_to_group("pony_prompt_notes")
	debug_logs = SETTINGS.debug_mode.get_bool()
	debug_perf = SETTINGS.debug_perf.get_bool()
	_sync_skeleton_overlay()
	_perf_idle.enabled = Callable(self, "_perf_idle_on")
	_perf_idle.counts = Callable(self, "_perf_idle_counts")
	_perf_idle.log = Callable(self, "debug")
	_captions_on_top = SETTINGS.captions_on_top.get_bool()
	eligibility = ELIGIBILITY.new()
	eligibility.setup(self)
	memory = MEMORY.new()
	memory.setup(self)
	classifier = CLASSIFIER.new()
	classifier.name = "UnfplapClassifier"
	add_child(classifier)
	privacy = PRIVACY.new()
	privacy.setup(self)
	adapter = ADAPTER.new()
	adapter.name = "UnfplapNegotiationAdapter"
	add_child(adapter)
	adapter.call("bind", self)
	negotiation = NEGOTIATION.new()
	negotiation.name = "UnfplapNegotiation"
	add_child(negotiation)
	_bind_negotiation_host()
	initiation = INITIATION.new()
	initiation.name = "UnfplapInitiation"
	initiation.call("setup", self, privacy, adapter)
	add_child(initiation)
	anatomy = ANATOMY.new()
	anatomy.name = "UnfplapAnatomy"
	anatomy.call("setup", self)
	add_child(anatomy)
	pantyhose = PANTYHOSE.new()
	pantyhose.name = "UnfplapPantyhose"
	pantyhose.call("setup", self)
	add_child(pantyhose)
	stool = STOOL.new()
	stool.name = "UnfplapStool"
	stool.call("setup", self)
	add_child(stool)
	api = API.new()
	api.name = "UnfplapAPI"
	api.call("_bind", self)
	add_child(api)
	# Proves which build is live: a real source file has a non-zero mtime; a pack/PCK reports 0.
	var source_mtime := 0
	for path: String in [
			"res://mods/unfplap/runtime.gd",
			"res://mods/unfplap/readiness/thrust.gd",
			"res://mods/unfplap/shared/preferences.gd",
			"res://mods/unfplap/dialogue/utterance.gd",
			"res://mods/unfplap/poses/skeleton_pose.gd",
			"res://mods/unfplap/poses/missionary_recipe.gd",
			"res://mods/unfplap/poses/standing_recipe.gd",
	]:
		source_mtime = maxi(source_mtime, FileAccess.get_modified_time(path))
	_debug("entry ready (debug logs %s) runtime_mtime=%d" % [
		"ON" if debug_logs else "OFF", source_mtime])
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	Mods.player_ready.connect(_on_player)
	Mods.on_node(PONY_PATH, _on_pony)
	Mods.on_node(SETTINGS_PAGE_PATH, _on_settings_page)
	Mods.on_node(CAPTION_PATH, _on_caption)
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("changed") \
			and not settings.changed.is_connected(_on_game_setting_changed):
		settings.changed.connect(_on_game_setting_changed)
	_apply_caption_top.call_deferred()
	# Switched on mid-game: the world and player already exist.
	if is_instance_valid(Mods.game):
		_on_world(Mods.game)
		var existing: Variant = Mods.game.get("player")
		if is_instance_valid(existing):
			_on_player(existing)


func _on_world(host: Node) -> void:
	close_debug_wheel()
	_clear_native_hint()
	_dance_hint_shown = false
	game = host
	if not is_instance_valid(eligibility):
		eligibility = ELIGIBILITY.new()
	eligibility.setup(self)
	if is_instance_valid(stool):
		stool.call("on_world", host)
	if is_instance_valid(pantyhose):
		pantyhose.call("on_world", host)
	_stool_hint_toast_shown = false
	_last_blocked_key = ""
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0
	_offer = null
	_offer_blocked = null
	_perf_idle.reset()
	if is_instance_valid(initiation):
		initiation.reset()
	if is_instance_valid(negotiation):
		negotiation.call("reset")
		_bind_negotiation_host()
	if is_instance_valid(adapter) and _watching_player:
		_watching_player = false
		adapter.call("unwatch_player")
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
	if is_instance_valid(hud):
		hud.hide_all()


func _on_world_closed(_host: Node) -> void:
	_debug("world closed")
	close_debug_wheel()
	if is_instance_valid(pantyhose):
		pantyhose.call("on_world_closed")
	if is_instance_valid(anatomy):
		anatomy.call("clear_player")
	_clear_native_hint()
	if is_instance_valid(initiation):
		initiation.reset()
	if is_instance_valid(negotiation):
		negotiation.call("reset")
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	game = null
	player = null
	_offer = null
	_offer_blocked = null
	_perf_idle.reset()
	_last_blocked_key = ""
	if is_instance_valid(stool):
		stool.call("on_world_closed")
	if is_instance_valid(hud):
		hud.hide_all()


## Move the game's bottom dialogue caption to the top only during an act and only when the player
## chose the explicit bottom-caption mode. "Over the pony's head" and "auto" are left untouched,
## and afterglow returns the caption to the bottom.
func _caption_top_enabled() -> bool:
	if not _captions_on_top:
		return false
	if not is_instance_valid(active_runtime):
		return false
	var state: int = int(active_runtime.get("state"))
	if state not in [RUNTIME.State.POSING_IN, RUNTIME.State.ACTIVE, RUNTIME.State.CLIMAX]:
		return false
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return false
	return str(settings.call("get_value", "access/speech_text")) == "caption"


func _on_caption(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_captions[node.get_instance_id()] = weakref(node)
	_caption_top_tick()


func _apply_caption_top() -> void:
	if not is_inside_tree():
		return
	_captions_on_top = SETTINGS.captions_on_top.get_bool()
	_caption_top_tick()


## Move the game's caption card after its own layout pass. The stock caption keeps its text,
## wrapping, roll and fade; only its y position changes. Runs at process priority 100, after
## the caption's own _process, and skips the settings-page preview.
func _caption_top_tick() -> void:
	if not _caption_top_enabled():
		return
	for id: int in _captions.keys():
		var ref: Variant = _captions[id]
		var node: Variant = ref.get_ref() if ref is WeakRef else null
		if not is_instance_valid(node):
			_captions.erase(id)
			continue
		if bool(node.get("preview")):
			continue
		var card: Variant = node.get("_card")
		if not card is Control:
			continue
		var scale_value: Variant = node.get("_scale")
		var scale := float(scale_value) if scale_value != null else 1.0
		(card as Control).position.y = roundf(CAPTION_TOP_MARGIN * maxf(scale, 0.01))


func _on_game_setting_changed(key: String) -> void:
	if key == "access/speech_text":
		_apply_caption_top()


func _apply_live_settings() -> void:
	if is_instance_valid(active_runtime) and active_runtime.has_method("apply_live_settings"):
		active_runtime.call("apply_live_settings")


## One path for every control edit: refresh the cached flags, the caption position and the live
## act. Every tunable change goes through here, so a control never needs its own handler.
func apply_settings_changed() -> void:
	_apply_settings_changed()


func _apply_settings_changed() -> void:
	debug_logs = SETTINGS.debug_mode.get_bool()
	debug_perf = SETTINGS.debug_perf.get_bool()
	if not debug_logs:
		close_debug_wheel()
	if is_instance_valid(input):
		input.call("apply_settings")
	if is_instance_valid(hud):
		hud.call("set_act_key", _act_key_label())
	# The native offer row and the fallback prompt carry the key cap; rebuild them with the new
	# label on the next frame.
	_clear_native_hint()
	_sync_skeleton_overlay()
	SETTINGS_UI.refresh_debug_visibility()
	_apply_caption_top()
	_apply_live_settings()
	# integration: anatomy switches are live outside acts too.
	refresh_anatomy()
	if is_instance_valid(anatomy):
		anatomy.call("refresh_tails")
	if is_instance_valid(pantyhose):
		pantyhose.call("apply_live_settings")


## The anatomy controller owns the genitals material; refresh the dock after it attaches, changes
## tone or detaches.
func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(anatomy):
		anatomy.call("refresh_dock_color", pony)


func _on_player(body: Node) -> void:
	player = body
	_debug("player ready")
	if not is_instance_valid(hud):
		hud = HUD.new()
		hud.name = "UnfplapHUD"
		hud.log = Callable(self, "debug")
		add_child(hud)
	if is_instance_valid(anatomy):
		anatomy.call("player_ready", body)
	if not is_instance_valid(input):
		input = INPUT.new()
		input.name = "UnfplapInput"
		input.main = self
		add_child(input)
	hud.call("set_act_key", _act_key_label())
	if not _dance_hint_shown:
		_dance_hint_shown = true
		_dance_key_notice()


## The bundled Dance Mod owns `Y`; one note when both mods are on and the act key is another key.
func _dance_key_notice() -> void:
	if int(SETTINGS.act_key.get_num()) == KEY_Y:
		return
	if not Mods.is_active("dance_mod"):
		return
	if is_instance_valid(hud) and hud.has_method("toast"):
		hud.call("toast", "Dance Mod uses Y; %s starts the act." % _act_key_label(), 5.0)


## The act key's key cap label, from the captured keycode.
func _act_key_label() -> String:
	return ACT_KEYS.label(int(SETTINGS.act_key.get_num()))


func _on_pony(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	# The player's own AnonPony is a pony_locomotion too. Never attach an intimacy runtime to her.
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	if is_instance_valid(anatomy):
		anatomy.call("tail_ready", pony)
	if _runtimes.has(pony):
		return
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.set("pony", pony)
	runtime.set("main", self)
	if is_instance_valid(anatomy):
		anatomy.call("bind", pony, runtime)
	pony.add_child(runtime)
	_runtimes[pony] = runtime
	_debug("runtime attached %s id=%s" % [str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


## Live adult mares that are not in the base roster, for the Characters selector. A modded mare
## appears while she is in the world; her saved preset stays in settings.json when she despawns.
func live_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for pony: Variant in _runtimes.keys():
		if pony is Node3D and is_instance_valid(pony) and is_instance_valid(eligibility) \
				and eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER):
			ids.append(ANATOMY.pony_id(pony))
	var out: Array[String] = ANATOMY.off_roster_ids(ids, SETTINGS.CHARACTER_ORDER)
	out.sort_custom(func(a: String, b: String) -> bool:
		return SETTINGS.character_name(a).naturalnocasecmp_to(
			SETTINGS.character_name(b)) < 0)
	return out


## The settings page hook. No game-script extension is used. Opening the page re-reads
## settings.json; the settings UI owns the deferred injection and the sub-tabs.
func _on_settings_page(page: Node) -> void:
	SETTINGS_UI.inject(page, Callable(self, "_build_settings_actions"),
		Callable(self, "live_character_ids"), Callable(self, "_character_participation"),
		Callable(self, "_apply_settings_changed"), Callable(self, "debug"))


## The Debug block builder the settings panel inserts into each tab.
func _build_settings_actions(list: VBoxContainer, font_size: int, tab: String) -> void:
	DEBUG_UI.build_actions(list, font_size, self, tab)


## The live participation block for one mare. The Characters form is a settings UI file, so the
## eligibility service is reached through the entry node instead of a service dependency.
func _character_participation(id: String) -> Dictionary:
	if is_instance_valid(eligibility):
		return eligibility.get_profile(id).participation.to_dict()
	return {}


func _process(delta: float) -> void:
	var timed := _perf_idle.on()
	var started := Time.get_ticks_usec() if timed else 0
	_process_entry(delta)
	if timed:
		_perf_idle.note("entry_process", Time.get_ticks_usec() - started)
	_perf_idle.tick(delta)


## The entry's per-frame body. `_process` above only times it for the idle probe; the call order
## here is load-bearing.
func _process_entry(delta: float) -> void:
	_caption_top_tick()
	if not is_instance_valid(player) and is_instance_valid(game):
		var body: Variant = game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active_runtime):
		var camera_started := Time.get_ticks_usec()
		active_runtime.apply_camera_motion()
		active_runtime.call("perf_note", "camera_motion", Time.get_ticks_usec() - camera_started)
		if is_instance_valid(hud):
			var hud_started := Time.get_ticks_usec()
			hud.update_from(active_runtime.call("act_view"))
			active_runtime.call("perf_note", "hud", Time.get_ticks_usec() - hud_started)
		_offer = null
		_offer_blocked = null
		_sync_native_hint("")
		return

	_offer_clock += delta
	if _offer_clock >= 0.15:
		_offer_clock = 0.0
		if _perf_idle.on():
			var offer_started := Time.get_ticks_usec()
			_refresh_offer()
			_perf_idle.note("offer_scan", Time.get_ticks_usec() - offer_started)
		else:
			_refresh_offer()
	if is_instance_valid(initiation):
		initiation.tick(delta)
	if is_instance_valid(negotiation):
		negotiation.tick(delta)
		_tick_agreement_auto_start(delta)
	_tick_negotiation_watch()
	var hint := ""
	if _offer != null:
		hint = OFFER_HINT
	elif _offer_blocked != null:
		var blocked_hint := _offer_blocked.blocked_hint()
		hint = blocked_hint if not blocked_hint.is_empty() else NEEDS_STOOL_HINT
	else:
		_last_offer_key = ""
		_last_blocked_key = ""
	_sync_native_hint(hint)


func _refresh_offer() -> void:
	_offer = null
	_offer_blocked = null
	if not is_instance_valid(player) or not is_instance_valid(game):
		return
	if get_tree().paused:
		return
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = camera()
	if view == null:
		return
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var pony_form: bool = PLAYER_FORM.is_pony(form)

	# A live Agreement owns the hint while it is ready: it is already a yes. While its rows wait
	# or the presentation turns, the context scan below still finds a hotkey attempt, so a press
	# can start the exact match immediately or interrupt a different one.
	if is_instance_valid(negotiation):
		var handle: Variant = negotiation.call("handle")
		if handle != null:
			var live: POSE_OFFER = _agreement_offer(handle)
			if live != null:
				_offer = live
				_log_offer()
				return

	# Missionary now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid missionary camera, so that entry is not offered.
	if not pony_form and is_instance_valid(player) and player.get("seat") != null:
		var lying: Node = _bedside_pony(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and bool(runtime.call("hotkey_ready", CATALOG.MISSIONARY, "bed_side", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "bed_side", bed)
					_log_offer()
					return

	# Missionary, AnonPony: an awake pony already lying on a bed.
	if pony_form:
		var lying: Node = nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and bool(runtime.call("hotkey_ready", CATALOG.MISSIONARY, "already_lying", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "already_lying", bed)
					_log_offer()
					return

	# Standing: Anon must stand in the cone behind her rump. No crosshair aim is needed. The
	# hotkey readiness is Base clearance plus the scene-only rows, with no policy snapshot.
	var timed := _perf_idle.on()
	var cone_started := Time.get_ticks_usec() if timed else 0
	var standing: Node = _rump_cone_target(view)
	if timed:
		_perf_idle.note("offer_cone", Time.get_ticks_usec() - cone_started)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime):
			var gate_started := Time.get_ticks_usec() if timed else 0
			var ready := bool(runtime.call("hotkey_ready", CATALOG.STANDING, "", null))
			if timed:
				_perf_idle.note("offer_gate", Time.get_ticks_usec() - gate_started)
			if ready:
				_offer = _new_offer(runtime, standing, CATALOG.STANDING, "", null)
				_log_offer()
			else:
				var need := int(runtime.call("stool_needed_count"))
				if need > 0 and int(runtime.call("stool_case_count")) < need:
					var blocked_offer := _new_offer(runtime, standing, CATALOG.STANDING, "", null)
					blocked_offer.blocked = _blocked_record(need, _stool_hint_for(need))
					_offer_blocked = blocked_offer
					_log_blocked_offer(runtime, standing, need)


## Build one typed offer for the idle scan. A live Agreement press is consumed by the scene-only
## start, not a request close, so the idle offers carry no cancel callback.
func _new_offer(runtime: Node, pony: Node, pose: String, source: String,
		bed: Variant = null) -> POSE_OFFER:
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony as Node3D
	offer.pose = pose
	offer.source = source
	offer.bed = bed
	return offer


## The blocked record: the prompt hint and the toast a press shows.
func _blocked_record(need: int, hint: String) -> Dictionary:
	return {"hint": hint, "need": maxi(1, need), "toast": _stool_find_hint(need)}


## A copy of the live request offer with its blocked record. The request service reuses its one
## The current offer's pony, for the request service's cuddle check. It refreshes the offer the
## same way the prompt does, so the act key and a proactive cuddle offer cannot disagree.
func offer_target() -> Node:
	_refresh_offer()
	if _offer == null:
		return null
	var target: Variant = _offer.pony
	return target if is_instance_valid(target) else null


## The standing act-key zone: the nearest standing mare whose rear cone holds Anon. The cone alone
## decides, so the crosshair can point anywhere as long as he stands behind her rump.
func _rump_cone_target(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var eye: Vector3 = view.global_position
	# Geometry first: eligibility resolves a whole profile per mare, so only the in-cone
	# candidates pay for it. Nearest first preserves the nearest eligible adult result.
	var candidates: Array = []
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		if str(actor.posture_status().get("requested", "")) != "stand":
			continue
		var runtime: Node = runtime_for(actor)
		if not is_instance_valid(runtime):
			continue
		var anchor: Variant = runtime.call("rump_anchor")
		if not anchor is Vector3:
			continue
		var rump: Vector3 = anchor
		if not rump.is_finite():
			continue
		if not RUMP_CONE.contains(actor.global_basis.z, rump, eye):
			continue
		var flat := Vector3(eye.x - rump.x, 0.0, eye.z - rump.z)
		var distance := flat.length()
		if distance > RUMP_CONE.REACH_M:
			continue
		candidates.append([distance, actor])
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) < float(b[0]))
	for candidate: Array in candidates:
		var actor := candidate[1] as Node3D
		if is_instance_valid(actor) and _is_act_target(actor):
			return actor
	return null


func _native_row() -> HBoxContainer:
	if not is_instance_valid(game):
		return null
	var hints: Node = game.get_node_or_null("InteractionHints")
	if hints == null:
		return null
	# VR uses the world-space prompt row; the act-key hint falls back to the HUD prompt there.
	if bool(hints.get("xr")):
		return null
	var row: Variant = hints.get("_prompt2d")
	if row is HBoxContainer and is_instance_valid(row):
		return row
	return null


## The offer hint is one more unit in the game's own prompt row, in that row's style and phrasing
## ("Hold G · Bridal carry" reads as "Hold: ..."), so it sits beside base prompts unnoticed.
func _make_native_hint_label(text: String) -> Control:
	var cap := _act_key_label() if text == OFFER_HINT else ""
	return HUD.prompt_row("", text, cap)


func _remove_native_hint(row: HBoxContainer = null) -> void:
	_native_hint_text = ""
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


func _sync_native_hint(text: String) -> void:
	var row: HBoxContainer = _native_row()
	if row == null:
		if is_instance_valid(hud):
			if text.is_empty():
				hud.hide_prompt()
			else:
				hud.show_prompt(text, "", _act_key_label() if text == OFFER_HINT else "")
		return
	if text.is_empty():
		_remove_native_hint(row)
		if is_instance_valid(hud):
			hud.hide_prompt()
		return
	if not is_instance_valid(_native_hint_label) or _native_hint_label.get_parent() != row \
			or _native_hint_label.is_queued_for_deletion() or _native_hint_text != text:
		_remove_native_hint(row)
		_native_hint_label = _make_native_hint_label(text)
		_native_hint_text = text
		row.add_child(_native_hint_label)
	var parent: Node = row.get_parent()
	if parent is Control:
		(parent as Control).visible = true
	if is_instance_valid(hud):
		hud.hide_prompt()


func _stool_hint_for(need: int) -> String:
	return NEEDS_STOOL_HINT if need <= 1 else "Needs %d footstools" % need


func _stool_find_hint(need: int) -> String:
	return "Find a footstool in a house." if need <= 1 \
		else "Find %d footstools in a house." % need


func _log_blocked_offer(runtime: Node, target: Node, need: int) -> void:
	var key := "stool:%d:%d" % [target.get_instance_id(), need]
	if key == _last_blocked_key:
		return
	_last_blocked_key = key
	var gap: Variant = runtime.call("stool_gap_m")
	var gap_text := "n/a" if not (gap is float or gap is int) \
		or not is_finite(float(gap)) else "%.3f" % float(gap)
	var have := int(runtime.call("stool_case_count"))
	_debug("OFFER blocked pony=%s reason=needs_stool gap=%s need=%d have=%d" % [
		str(target.name), gap_text, need, have])
	if not _stool_hint_toast_shown:
		_stool_hint_toast_shown = true
		if is_instance_valid(hud) and hud.has_method("toast"):
			hud.call("toast", _stool_find_hint(need), 4.0)


## The live Agreement as the act key's own typed offer. It is a yes already, so the rump fan and
## the policy snapshot do not rediscover it; the scene-only rows and the settled presentation
## decide the hint. Null while the world is not ready.
func _agreement_offer(handle: Variant) -> POSE_OFFER:
	if handle == null:
		return null
	var pony: Variant = handle.pony
	var runtime: Node = runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("agreement_offer_ready"):
		return null
	if not bool(runtime.call("agreement_offer_ready", handle)):
		return null
	var option: Variant = handle.option
	if option == null:
		return null
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony as Node3D
	offer.pose = str(option.pose)
	offer.source = str(option.source)
	offer.bed = option.bed
	offer.trigger = "agreement"
	offer.pending = false
	return offer


func _log_offer() -> void:
	if _offer == null:
		return
	var target: Variant = _offer.pony
	var key := "%s:%s:%s:%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		_offer.pose, _offer.source, str(_offer.pending)]
	if key == _last_offer_key:
		return
	_last_offer_key = key
	_debug("OFFER pony=%s pose=%s source=%s bed=%s pending=%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		_offer.pose, _offer.source, str(_offer.bed), str(_offer.pending)])


func debug_target(view: Camera3D) -> Node:
	return _debug_target(view)


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
	if not is_instance_valid(view):
		return null
	var forward := -view.global_basis.z
	var best: Node = null
	var best_perp := INF
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null:
			continue
		var at: Vector3 = actor.global_position + Vector3.UP * 0.9
		var delta: Vector3 = at - view.global_position
		var along := forward.dot(delta)
		if along <= 0.0 or along > AIM_RANGE_M:
			continue
		var perp := (delta - forward * along).length()
		if perp > AIM_TUBE_M:
			continue
		if perp < best_perp:
			best_perp = perp
			best = actor
	return best


## The act key's one start entry. The act key is the hotkey: it always accepts, never bucks or
## refuses, and a missing context pose is no attempt. The tolerance stop owns the refusal path.
func try_start() -> bool:
	if is_instance_valid(active_runtime):
		return false
	_refresh_offer()
	if _offer == null:
		if _offer_blocked != null:
			return start_pose_offer(_offer_blocked)
		_debug("hotkey no context pose")
		_toast("There is nothing to start here.")
		return false
	return start_pose_offer(_offer)


## The one typed act-start path. The act key and the Agreement auto-start call this. The offer
## carries its pose and trigger, so this function never names a pose.
func start_pose_offer(offer: POSE_OFFER) -> bool:
	if offer == null or not offer.valid():
		return false
	if not offer.blocked.is_empty():
		var toast := str(offer.blocked.get("toast", ""))
		if not toast.is_empty():
			_toast(toast)
		return false
	if offer.trigger == "agreement":
		return _start_agreement_offer(offer, false)
	return _start_hotkey_offer(offer)


## The hotkey: a live Agreement's exact match starts it immediately and skips the presentation;
## any other live negotiation or Agreement is interrupted and the immediate attempt runs. The
## attempt is Base clearance plus the scene-only rows, with no offer cooldown.
func _start_hotkey_offer(offer: POSE_OFFER) -> bool:
	var runtime: Node = offer.runtime
	if not is_instance_valid(runtime):
		return false
	if is_instance_valid(negotiation):
		var handle: Variant = negotiation.call("handle")
		if handle != null:
			var match: Variant = negotiation.call("hotkey_handle", runtime, _option_for(offer))
			if match != null:
				return _start_agreement_offer(offer, true)
			negotiation.call("interrupt_for_hotkey")
			_debug("hotkey interrupted a different agreement")
		elif bool(negotiation.call("is_locked")):
			negotiation.call("interrupt_for_hotkey")
			_debug("hotkey interrupted the negotiation")
	var started := bool(runtime.call("start_hotkey", offer.pose, offer.bed, offer.source))
	if not started:
		_debug("hotkey start blocked pose=%s source=%s" % [offer.pose, offer.source])
		return false
	_clear_offer_hint()
	return true


## The exact pose option a hotkey attempt names. The idle hint never offers a cuddle, so the flag
## is false; a cuddle Agreement is consumed by its own offer path instead.
func _option_for(offer: POSE_OFFER) -> POSE_OPTIONS.Option:
	var option := POSE_OPTIONS.Option.new()
	option.pose = offer.pose
	option.source = offer.source
	option.bed = offer.bed
	return option


## The act key consumes a live Agreement through its scene-only start. `WAIT` keeps the hint and
## the Agreement for the next press; a started or failed attempt clears the hint, and the runtime
## reports the result to the Negotiation service. `skip_presentation` is the exact hotkey match.
func _start_agreement_offer(offer: POSE_OFFER, skip_presentation: bool) -> bool:
	var handle: Variant = negotiation.call("handle") if is_instance_valid(negotiation) else null
	if handle == null or not is_instance_valid(offer.runtime):
		_clear_offer_hint()
		return false
	var result := int(offer.runtime.call("start_agreement", handle, skip_presentation))
	if result == RUNTIME.AGREEMENT_WAIT:
		_debug("agreement start waiting pose=%s source=%s" % [offer.pose, offer.source])
		return false
	_clear_offer_hint()
	return result == RUNTIME.AGREEMENT_STARTED


## The Agreement's automatic start: it waits for the presentation to settle and Anon to be in
## position, then consumes the handle with no key press. A menu, a paused tree or a live act
## holds it.
func _tick_agreement_auto_start(delta: float) -> void:
	if is_instance_valid(active_runtime) or not is_instance_valid(negotiation):
		return
	var handle: Variant = negotiation.call("handle")
	if handle == null:
		return
	_agreement_clock += delta
	if _agreement_clock < 0.25:
		return
	_agreement_clock = 0.0
	if get_tree().paused or menu_open():
		return
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var pony: Variant = handle.pony
	var runtime: Node = runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("agreement_offer_ready"):
		return
	if not bool(runtime.call("agreement_offer_ready", handle)):
		return
	var offer := _agreement_offer(handle)
	if offer != null:
		_debug("agreement auto-start pony=%s pose=%s" % [str(pony.name), offer.pose])
		_start_agreement_offer(offer, false)


## The runtime's Agreement start result, forwarded to the Negotiation service.
func report_agreement(handle: Variant, started: bool) -> void:
	if is_instance_valid(negotiation):
		negotiation.call("report", handle, started)


## Close the live request episode before a start or refusal that owns the pony. The offer carries
func _clear_offer_hint() -> void:
	_offer = null
	if is_instance_valid(hud):
		hud.hide_prompt()


## Debug Actions entries (`DEBUG_ACTIONS.ACTIONS`). The offer helper forces a proactive request for
## the aimed mare, bypassing the quiet/cooldown/AI-usage checks so the lab can test requests with
## ai_usage=talk.
func action_bed_offer() -> String:
	return _debug_offer_request(CATALOG.MISSIONARY)


func action_standing_offer() -> String:
	return _debug_offer_request(CATALOG.STANDING)


## Debug: form an Anon offer for the aimed mare as if Anon had just asked her. The classifier still
## decides the option and the response; this only skips typing the line in a conversation.
func action_anon_offer() -> String:
	if not is_instance_valid(negotiation) or not is_instance_valid(player):
		return "Act system not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		return "No runtime for %s." % str(target.name)
	var formed := bool(negotiation.call("begin_anon_offer", runtime, "I want you. Come here."))
	_debug("anon offer button: %s formed=%s" % [str(target.name), str(formed)])
	if formed:
		return "Anon offer started for %s." % str(target.name)
	return "Anon offer refused for %s." % str(target.name)


## Wheel-only: start the stock bed cuddle. The bed, recline and invite sequence runs after this
## returns, so the wheel closes immediately and the debug log carries the detailed result.
func action_bed_cuddle() -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	if not is_instance_valid(DEBUG_BED.find_bed(self)):
		return "No bed found in this house."
	_bed_cuddle_sequence(target)
	return "Bed cuddle started for %s." % str(target.name)


func _bed_cuddle_sequence(target: Node) -> void:
	var result: String = await DEBUG_BED.invite(self, target)
	_debug("bed cuddle: " + result)


## Wheel-only: qualify the aimed adult mare for the act gate. The helper clears her busy state,
## writes the game's bond record and a neutral mood; her romance tier is untouched.
func action_sex_ready() -> String:
	var target := _debug_history_target()
	if not is_instance_valid(target) or not target is Node3D or not _is_act_target(target):
		return "No adult mare under the crosshair."
	return DEBUG_PONY.sex_ready(self, target as Node3D)


## Debug-only estrus phase controls. The override is session-only and per pony; `cycle_auto`
## clears it and resumes the automatic day/id cycle. A toggle's label follows the target's phase.
func action_toggle_heat() -> String:
	return _debug_cycle_toggle(CYCLE.HEAT)


func action_toggle_diestrus() -> String:
	return _debug_cycle_toggle(CYCLE.DIESTRUS)


func action_cycle_auto() -> String:
	return _debug_cycle_request("")


func _debug_cycle_toggle(phase_name: String) -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("set_cycle_override"):
		return "No runtime for %s." % str(target.name)
	var current := str(runtime.call("cycle_phase")) if runtime.has_method("cycle_phase") else ""
	var next := CYCLE.NORMAL if current == phase_name else phase_name
	runtime.call("set_cycle_override", next)
	var verb := "cleared" if next == CYCLE.NORMAL else "forced"
	_debug("cycle %s %s=%s" % [phase_name, str(target.name), next])
	return "%s %s for %s." % [phase_name.capitalize(), verb, str(target.name)]


## The aimed mare's effective estrus phase, or "" when there is no target.
func debug_cycle_phase() -> String:
	if not is_instance_valid(player):
		return ""
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return ""
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("cycle_phase"):
		return ""
	return str(runtime.call("cycle_phase"))


func _debug_cycle_request(phase_name: String) -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("set_cycle_override"):
		return "No runtime for %s." % str(target.name)
	runtime.call("set_cycle_override", phase_name)
	var label := "automatic" if phase_name.is_empty() else phase_name
	_debug("cycle override %s=%s" % [str(target.name), label])
	return "Cycle for %s: %s." % [str(target.name), label]


## Shared by the Debug actions.
func _debug_offer_request(pose := "") -> String:
	if not is_instance_valid(initiation) or not is_instance_valid(player):
		return "Act system not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		_debug("request: no pony target")
		return "No mare under the crosshair."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		_debug("request: no runtime for %s" % str(target.name))
		return "No runtime for %s." % str(target.name)
	var result: INITIATION.ForceResult = initiation.force(runtime, pose)
	var started := result != null and result.ok
	var label := ""
	if pose == CATALOG.MISSIONARY:
		label = " (bed)"
	elif pose == CATALOG.STANDING:
		label = " (standing)"
	if started:
		_debug("request button: %s%s" % [str(target.name), label])
		return "Offer started for %s%s." % [str(target.name), label]
	var reason := "unknown"
	if result != null and not result.reject.is_empty():
		reason = result.reject
	_debug("request button reject %s%s reason=%s" % [str(target.name), label, reason])
	return "Offer rejected for %s%s: %s." % [str(target.name), label, reason]


## Debug: re-read the active pose's authored base without restarting. A running act picks the new
## pose up on its next frame, so the lab (export) -> game (reload) loop works while posing.
func action_reload_pose() -> String:
	var error := ""
	if is_instance_valid(active_runtime):
		error = str(active_runtime.call("reload_pose_asset"))
	else:
		error = AUTHORED.reload_file()
	if not error.is_empty():
		_debug("pose reload failed: %s" % error)
		return "Pose reload failed: %s" % error
	if is_instance_valid(active_runtime) and active_runtime.has_method("_sync_missionary_pose_config"):
		active_runtime.call("_sync_missionary_pose_config")
	_debug("pose reloaded")
	return "Reloaded the active posed base."


## Debug: toggle the internal standing_test pose in a live standing act. The edge holds the body;
## the reverse edge returns to standing. Never ends the act.
func action_pose_test_variant() -> String:
	if not is_instance_valid(active_runtime):
		return "No act."
	var view: Variant = active_runtime.call("pose_view")
	var active := str(view.id) if view != null else ""
	if active.is_empty():
		return "No act."
	if active != CATALOG.STANDING and active != CATALOG.STANDING_TEST:
		return "Only in a standing act."
	var target := CATALOG.STANDING_TEST if active == CATALOG.STANDING else CATALOG.STANDING
	var result: Variant = active_runtime.call("request_pose", target, "debug")
	if result is Dictionary:
		var code := str((result as Dictionary).get("code", ""))
		_debug("pose test variant %s -> %s: %s" % [active, target, code])
		return "Pose %s: %s." % [target, code]
	return "Pose request failed."


## Debug: toggle the internal bed face-sit in a live missionary act. The face-sit has no offer and
## no key; this button is its only trigger. The edge changes the arrangement and the contact and
## never ends the act.
func action_facesit_variant() -> String:
	if not is_instance_valid(active_runtime):
		return "No act."
	var error := str(active_runtime.call("face_sit_error"))
	if not error.is_empty():
		_debug("face-sit refused: %s" % error)
		return "Face-sit refused: %s." % error
	var view: Variant = active_runtime.call("pose_view")
	var active := str(view.id) if view != null else ""
	var target := CATALOG.BED_FACESIT if active == CATALOG.MISSIONARY else CATALOG.MISSIONARY
	var result: Variant = active_runtime.call("request_pose", target, "facesit")
	if result is Dictionary:
		var code := str((result as Dictionary).get("code", ""))
		_debug("pose face-sit %s -> %s: %s" % [active, target, code])
		return "Pose %s: %s." % [target, code]
	return "Pose request failed."


## Debug: one structured dump for the aimed mare. Show data, and a future always-on overlay, can
## render the same sections: TARGET, CYCLE, GATE, REQUEST, ACT, STOOL, HISTORY, PROMPT, BED.
func action_show_data() -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	var data := debug_data(target)
	var rows: Array[String] = []
	for section: Variant in data.get("sections", []):
		if not section is Dictionary:
			continue
		var item: Dictionary = section
		rows.append(str(item.get("title", "")))
		for row: Variant in item.get("rows", []):
			rows.append("  " + str(row))
	_debug_block("DATA " + str(target.name), rows)
	return "Data written to the debug log for %s." % str(target.name)


## The structured per-mare collector. `ACT` is present only while this target owns the live act.
func debug_data(target: Node) -> Dictionary:
	var data := {"target": target, "sections": []}
	if not is_instance_valid(target):
		return data
	var runtime: Variant = runtime_for(target)
	var id := _debug_pony_id(target)
	var sections: Array = data["sections"]
	sections.append(_debug_section("TARGET", _debug_target_rows(target, runtime, id)))
	sections.append(_debug_section("CYCLE", _debug_cycle_rows(runtime)))
	sections.append(_debug_section("GATE", _debug_gate_rows(target, runtime)))
	if is_instance_valid(initiation):
		sections.append(_debug_section("REQUEST", initiation.debug_rows(target)))
	else:
		sections.append(_debug_section("REQUEST", ["request service unavailable"]))
	if is_instance_valid(negotiation):
		sections.append(_debug_section("NEGOTIATION", negotiation.debug_rows(target)))
	else:
		sections.append(_debug_section("NEGOTIATION", ["negotiation service unavailable"]))
	if is_instance_valid(active_runtime) and runtime == active_runtime:
		sections.append(_debug_section("ACT", _debug_act_rows(runtime)))
	sections.append(_debug_section("STOOL", _debug_stool_rows(runtime)))
	sections.append(_debug_section("HISTORY", _debug_history_rows(target)))
	sections.append(_debug_section("PROMPT", _debug_prompt_rows(target)))
	sections.append(_debug_section("BED", DEBUG_BED.rows(self, target)))
	return data


func _debug_section(title: String, rows: Array) -> Dictionary:
	var lines: Array[String] = []
	for row: Variant in rows:
		lines.append(str(row))
	return {"title": title, "rows": lines}


func _debug_target_rows(target: Node, runtime: Variant, id: String) -> Array[String]:
	var state := "none"
	if is_instance_valid(runtime):
		state = "live" if runtime == active_runtime else "idle"
	return ["pony=%s id=%s" % [str(target.name), id if not id.is_empty() else "?"],
		"runtime=%s" % state]


func _debug_cycle_rows(runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	var phase := str(runtime.call("cycle_phase")) if runtime.has_method("cycle_phase") else "?"
	var override := str(runtime.call("cycle_override")) if runtime.has_method("cycle_override") else "?"
	return ["phase=%s override=%s" % [phase, override if not override.is_empty() else "none"],
		"heat=%s" % str(phase == CYCLE.HEAT)]


func _debug_gate_rows(target: Node, runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	var view: Camera3D = camera()
	var dist := -1.0
	var dot := -1.0
	if is_instance_valid(view) and target is Node3D:
		var delta: Vector3 = (target as Node3D).global_position + Vector3.UP * 0.9 \
			- view.global_position
		dist = delta.length()
		if dist > 0.001:
			dot = (-view.global_basis.z).dot(delta.normalized())
	var pose := CATALOG.STANDING
	var source := ""
	var bed: Variant = null
	var status: Dictionary = target.call("posture_status") if target.has_method("posture_status") else {}
	if str(status.get("requested", "")) == "lie_down":
		pose = CATALOG.MISSIONARY
		source = "already_lying"
		bed = runtime.call("find_bed_under")
	var line := str(runtime.call("debug_line", pose, source, bed, dist, dot)) \
		if runtime.has_method("debug_line") else "no debug line"
	return [line]


func _debug_act_rows(runtime: Variant) -> Array[String]:
	var rows: Array[String] = [
		"state=%d pose=%s" % [int(runtime.get("state")), str(runtime.get("pose_id"))],
		"climaxes=%d satisfaction=%.2f" % [
			int(runtime.get("pony_climaxes")), float(runtime.get("satisfaction"))],
	]
	if runtime.has_method("act_face_rows"):
		rows.append("face:")
		for row: Variant in runtime.call("act_face_rows"):
			rows.append("  " + str(row))
	if runtime.has_method("pose_state_rows"):
		rows.append("pose state:")
		for row: Variant in runtime.call("pose_state_rows"):
			rows.append("  " + str(row))
	return rows


func _debug_stool_rows(runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	if not runtime.has_method("stool_state_text"):
		return ["stool unavailable"]
	return [str(runtime.call("stool_state_text"))]


## Debug: cycle the game's expression faces on the active act or the aimed mare.
func action_force_act_face() -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	_debug_face_index = (_debug_face_index + 1) % ACT_FACE.FACES.size()
	var face := str(ACT_FACE.FACES[_debug_face_index])
	var runtime: Variant = runtime_for(target)
	var shown := false
	if is_instance_valid(runtime) and runtime.has_method("force_act_face"):
		shown = bool(runtime.call("force_act_face", face))
	if not shown:
		shown = ACT_FACE.react(target, face, 3.0)
	_debug("act face %s=%s shown=%s" % [str(target.name), face, str(shown)])
	return "Act face %s: %s%s." % [str(target.name), face,
		"" if shown else " (a spoken line owns the face)"]


## Debug: clear the aimed mare's proactive-offer cooldown and short retry.
func action_clear_cooldown() -> String:
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var name := str(target.name)
	if not is_instance_valid(initiation) or not bool(initiation.call("clear_cooldown", target)):
		return "No request state for %s." % name
	_debug("request cooldown cleared %s" % name)
	return "Offer cooldown cleared for %s." % name


## Debug: clear the aimed mare's long-term act history.
func action_reset_act_history() -> String:
	if not is_instance_valid(player):
		return "Act system not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	var id := _debug_pony_id(target)
	if id.is_empty():
		return "No relationship id for %s." % str(target.name)
	var section: Dictionary = ACT_HISTORY.section()
	if not ACT_HISTORY.reset(section, id):
		return "No act history for %s." % str(target.name)
	ACT_HISTORY.save()
	_debug("act history reset for %s" % id)
	return "Act history cleared for %s." % str(target.name)


## The stored act history, as Show data's HISTORY section.
func _debug_history_rows(target: Node) -> Array[String]:
	var id := _debug_pony_id(target)
	var rows: Array[String] = ["pony=%s id=%s" % [
		str(target.name), id if not id.is_empty() else "?"]]
	if id.is_empty():
		rows.append("no relationship id")
		return rows
	var row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var acts := int(row.get("acts", 0))
	if acts <= 0 and int(row.get("hurt", 0)) <= 0 and int(row.get("comfort", 0)) <= 0:
		rows.append("no history stored")
		return rows
	rows.append("tier=%s hurt=%d comfort=%d acts=%d good=%d bad=%d neutral=%d" % [
		ACT_HISTORY.tier_name(row), int(row.get("hurt", 0)), int(row.get("comfort", 0)),
		acts, int(row.get("good", 0)), int(row.get("bad", 0)), int(row.get("neutral", 0))])
	rows.append("streaks good=%d bad=%d announced=%d" % [
		int(row.get("streak_good", 0)), int(row.get("streak_bad", 0)),
		int(row.get("announced_tier", 0))])
	var reason_values: Array = row.get("last_reasons", [])
	var reason_text := ",".join(PackedStringArray(reason_values))
	rows.append("last grade=%s quality=%.2f reasons=%s" % [
		str(row.get("last_grade", "")), float(row.get("last_quality", 0.0)), reason_text])
	var text := str(row.get("last_text", "")).strip_edges()
	var wants := str(row.get("last_wants", "")).strip_edges()
	rows.append("last text=%s" % (text if not text.is_empty() else "none"))
	rows.append("wants=%s" % (wants if not wants.is_empty() else "none"))
	var stop_until := float(row.get("stop_until", 0.0))
	var now := Time.get_unix_time_from_system()
	if stop_until > now:
		rows.append("stop_until=%.0fs left (%s)" % [
			stop_until - now, str(row.get("last_stop_kind", ""))])
	var pending := ACT_HISTORY.pending_line(row)
	rows.append("pending=%s" % (pending if not pending.is_empty() else "none"))
	var recent: Variant = row.get("recent", [])
	if recent is Array and not (recent as Array).is_empty():
		rows.append("recent:")
		for entry: Variant in recent:
			if not entry is Dictionary:
				continue
			var item: Dictionary = entry
			var stamp := Time.get_datetime_string_from_unix_time(int(item.get("at", 0.0)), true)
			rows.append("- %s %.2f %s %s" % [
				str(item.get("grade", "")), float(item.get("quality", 0.0)), stamp,
				str(item.get("text", "")).strip_edges()])
	return rows


## The mod-owned parts of the next dialogue request, as Show data's PROMPT section.
func _debug_prompt_rows(target: Node) -> Array[String]:
	var id := _debug_pony_id(target)
	var rows: Array[String] = ["pony=%s id=%s" % [
		str(target.name), id if not id.is_empty() else "?"]]
	if id.is_empty():
		rows.append("no relationship id")
		return rows
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		rows.append("no runtime")
		return rows
	rows.append("prompt_note: " + str(runtime.call("prompt_note")))
	rows.append("cycle_note: " + str(runtime.call("cycle_note")))
	var history_row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var history_note := ACT_HISTORY.prompt_note(history_row)
	rows.append("history_note: " + (history_note if not history_note.is_empty() else "none"))
	var ctx: Variant = game.get("world_context") if is_instance_valid(game) else null
	if ctx != null and is_instance_valid(ctx):
		var events: Array = ctx.call("events_for", id, 10) if ctx.has_method("events_for") else []
		rows.append("recent events:")
		for event: Variant in events:
			if event is Dictionary:
				var item: Dictionary = event
				rows.append("  %s: %s" % [str(item.get("kind", "")), str(item.get("text", ""))])
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions) \
				and impressions.has_method("standing_line"):
			rows.append("standing_line: " + str(impressions.call("standing_line", id)))
	return rows


func action_reset_act_prompts() -> String:
	SETTINGS.reset_act_prompts()
	return "Act prompts reset to defaults."


func action_give_stool() -> String:
	if not is_instance_valid(game):
		return "Act system not ready."
	var inventory: Variant = game.get("inventory")
	if not is_instance_valid(inventory):
		return "No briefcase."
	var store: Variant = inventory.get("inventory")
	if store == null:
		return "No briefcase."
	var slot := int(store.call("grant", STOOL.ID, 1))
	if slot < 0:
		return "No room in the briefcase."
	_debug("stool granted slot=%d" % slot)
	return "Footstool added."


## Rebuild the worn-garment depth field after a precision edit. The integration owns the cache
## and the scan; `main` only forwards the button.
func action_pantyhose_rebuild() -> String:
	if not is_instance_valid(pantyhose):
		return "Pantyhose integration is not running."
	return str(pantyhose.call("rebuild_hull"))


func _debug_history_target() -> Node:
	var view: Camera3D = camera()
	return _debug_target(view) if is_instance_valid(view) else null


func _debug_pony_id(target: Node) -> String:
	return PONY_ID.from(str(target.get_meta("relationship_id", "")), target.get("identity"))


func action_force_tolerance_warning() -> String:
	return _debug_force_tolerance("warning")


func action_force_tolerance_stop() -> String:
	return _debug_force_tolerance("stop")


func _debug_force_tolerance(kind: String) -> String:
	if not is_instance_valid(active_runtime):
		return "No act is active."
	if not active_runtime.has_method("debug_force_tolerance"):
		return "The act cannot force a neglect warning."
	if not bool(active_runtime.call("debug_force_tolerance", kind)):
		return "Neglect forcing is only available during a live act."
	return "Neglect %s queued." % kind


## integration: anatomy hooks used by the runtime and input.
func anatomy_status(text: String, seconds := 2.0) -> void:
	if is_instance_valid(hud) and hud.has_method("toast"):
		hud.call("toast", text, seconds)
	else:
		_debug(text)


## Cross-mod API: a provider layer changed. Re-resolve the live anatomy, tail seat and act
## settings without writing the player's settings file.
func refresh_api_state() -> void:
	if not is_inside_tree():
		return
	_apply_live_settings()
	refresh_anatomy()
	if is_instance_valid(anatomy):
		anatomy.call("refresh_tails")


## integration: keep the anatomy feature live when the player edits a flag.
func refresh_anatomy() -> void:
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime) and runtime.has_method("apply_live_settings"):
			runtime.call("apply_live_settings")
	if is_instance_valid(anatomy):
		anatomy.call("refresh_player")
		anatomy.call("refresh_all")
		anatomy.call("apply_live")
		anatomy.call("player_apply_live")


## integration: the chat box refuses while the act holds the controls; open it past that lock.
func open_act_chat() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	var chat: Node = game.get_node_or_null("ChatBox")
	if chat == null or not chat.has_method("_open"):
		return false
	var held: Variant = player.get("controls_locked")
	player.set("controls_locked", false)
	var opened := bool(chat.call("_open"))
	player.set("controls_locked", held)
	if opened:
		chat.set("_lock_owned", false)
	return opened


## integration: the anatomy service owns the placement editor.
func _placement_debug(op: String, value := 0.0) -> String:
	if is_instance_valid(anatomy):
		return str(anatomy.call("placement_debug", op, value))
	return "Anatomy service unavailable."


func action_anatomy_up() -> String:
	return _placement_debug("y", 0.005)


func action_anatomy_down() -> String:
	return _placement_debug("y", -0.005)


func action_anatomy_forward() -> String:
	return _placement_debug("z", 0.005)


func action_anatomy_back() -> String:
	return _placement_debug("z", -0.005)


func action_anatomy_pitch_up() -> String:
	return _placement_debug("pitch", 1.0)


func action_anatomy_pitch_down() -> String:
	return _placement_debug("pitch", -1.0)


func action_anatomy_scale_up() -> String:
	return _placement_debug("scale", 0.02)


func action_anatomy_scale_down() -> String:
	return _placement_debug("scale", -0.02)


func action_tail_seat_up() -> String:
	return _placement_debug("tail_up", 0.005)


func action_tail_seat_down() -> String:
	return _placement_debug("tail_down", 0.005)


func action_tail_dock_up() -> String:
	return _placement_debug("dock_up", 0.005)


func action_tail_dock_down() -> String:
	return _placement_debug("dock_down", 0.005)


func action_tail_dock_scale_up() -> String:
	return _placement_debug("dock_scale_up", 0.05)


func action_tail_dock_scale_down() -> String:
	return _placement_debug("dock_scale_down", 0.05)


func action_tail_seat_forward() -> String:
	return _placement_debug("tail_forward", 0.005)


func action_tail_seat_back() -> String:
	return _placement_debug("tail_back", 0.005)


func action_tail_tilt_left() -> String:
	return _placement_debug("tail_tilt_left", 1.0)


func action_tail_tilt_right() -> String:
	return _placement_debug("tail_tilt_right", 1.0)


func action_placement_save() -> String:
	return _placement_debug("save")


func action_placement_reset() -> String:
	return _placement_debug("reset")


func action_placement_show() -> String:
	if is_instance_valid(anatomy):
		return str(anatomy.call("placement_show"))
	return "Anatomy service unavailable."


func nearest_pony(view: Camera3D) -> Node:
	return _nearest_pony(view)


func _nearest_pony(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var best: Node = null
	var best_distance := 8.0
	for node: Variant in mares():
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var actor: Node3D = node as Node3D
		var distance := actor.global_position.distance_to(view.global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


## The persisted Anatomy debug flag is the only switch; the overlay is live only while debug is on.
func _sync_skeleton_overlay() -> void:
	var enabled := debug_logs and SETTINGS.skeleton_overlay.get_bool()
	if enabled:
		if not is_instance_valid(_debug_skeleton):
			_debug_skeleton = DEBUG_SKELETON.new()
			_debug_skeleton.name = "UnfplapSkeleton"
			_debug_skeleton.set("main", self)
			add_child(_debug_skeleton)
		_debug_skeleton.set("enabled", true)
	elif is_instance_valid(_debug_skeleton):
		_debug_skeleton.set("enabled", false)


## The debug wheel is created lazily on the first middle press. The gate here keeps a pack with
## debug off from creating the node at all.
func debug_wheel_input(event: InputEvent) -> bool:
	if not is_instance_valid(_debug_wheel):
		if not debug_logs:
			return false
		if not event is InputEventMouseButton:
			return false
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_MIDDLE or not button.pressed:
			return false
		_debug_wheel = DEBUG_WHEEL.new()
		_debug_wheel.name = "UnfplapDebugWheel"
		_debug_wheel.set("main", self)
		add_child(_debug_wheel)
	return bool(_debug_wheel.call("handle_input", event))


func debug_wheel_open() -> bool:
	return is_instance_valid(_debug_wheel) and bool(_debug_wheel.call("is_open"))


func close_debug_wheel() -> void:
	if is_instance_valid(_debug_wheel):
		_debug_wheel.call("close")


func debug_wheel_act_live() -> bool:
	return is_instance_valid(active_runtime)


## The wheel's open gate: debug on, desktop, captured, focused, unpaused, no menu or text field,
## and the left button not held.
func debug_wheel_allowed() -> bool:
	if not debug_logs or DisplayServer.get_name() == "headless":
		return false
	if not is_instance_valid(player) or not is_instance_valid(game):
		return false
	if get_tree().paused or headset_view():
		return false
	if not DisplayServer.window_is_focused():
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if menu_open():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	return not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## The wheel's target: the active act's pony while an act runs, else the aimed mare.
func debug_wheel_context() -> Dictionary:
	var out := {"pony": null, "name": "No mare", "source": "none", "act": false}
	if is_instance_valid(active_runtime):
		out["act"] = true
		var act_pony: Variant = active_runtime.get("pony")
		if is_instance_valid(act_pony):
			out["pony"] = act_pony
			out["name"] = str((act_pony as Node).name)
			out["source"] = "act"
			return out
		return out
	var view: Camera3D = camera()
	if not is_instance_valid(view):
		return out
	var target: Node = _debug_target(view)
	if is_instance_valid(target):
		out["pony"] = target
		out["name"] = str(target.name)
		out["source"] = "aimed"
	return out


## Run a wheel action, toast its one-line result and log it. Show data's multi-line block stays in
## the log; the toast only carries the summary.
func debug_wheel_action(name: String) -> String:
	var result := DEBUG_ACTIONS.run_action(name, self)
	_debug("wheel %s: %s" % [name, result])
	if not result.is_empty() and is_instance_valid(hud) and hud.has_method("toast"):
		hud.call("toast", result, 3.0)
	return result


## Public wrapper for the debug bed helper's multi-line report.
func debug_block(title: String, rows: Array) -> void:
	_debug_block(title, rows)


func skeleton_click() -> bool:
	if not is_instance_valid(_debug_skeleton) or not bool(_debug_skeleton.get("enabled")):
		return false
	return bool(_debug_skeleton.call("handle_click"))

func allocate_serial() -> int:
	var section: Dictionary = Mods.state("unfplap")
	var value: int = int(section.get("serial", 0)) + 1
	section["serial"] = value
	Mods.save_changed()
	return value


func set_active(runtime: Node) -> void:
	active_runtime = runtime
	_offer = null


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


## The act-target capability. The eligibility service owns the rule; a scan uses this before
## building a runtime gate for a stallion or a young pony.
func _is_act_target(pony: Variant) -> bool:
	return is_instance_valid(eligibility) \
		and eligibility.eligible(pony, ELIGIBILITY.Target.ACT)


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
			var real := real_bed(bed)
			if real != null:
				return real
	return null


## The actual bed/couch behind a physics hit. A `SharedTorsoSupport` is a temporary child of the
## bed that also carries `soft_support`; using it as the bed leaves the act with a freed node
## once the cuddle support is removed.
func real_bed(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_meta("shared_rest_support"):
		var parent := node.get_parent() as Node3D
		if is_instance_valid(parent):
			return parent
	var walk: Node = node
	while walk != null:
		if walk is Node3D and walk.has_meta("mattress_top"):
			return walk as Node3D
		walk = walk.get_parent()
	if node is Node3D and node.has_meta("soft_support"):
		return node as Node3D
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
	return real_bed(MATTRESS.bed_of(hit.get("collider")))


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


## True while a menu or panel owns the mouse: the tree is paused or a known UI panel is open.
## Deliberately excludes "the mouse is visible" so a menu that leaves the cursor visible cannot
## keep offers and act input dead after it closes. Use menu_open() for "can he interact now".
func menu_panel_open() -> bool:
	if get_tree().paused:
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


## True when the player should not interact with the world right now. Adds the mouse state to
## menu_panel_open(): the base game leaves the cursor visible while a menu owns the mouse.
func menu_open() -> bool:
	if menu_panel_open():
		return true
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


## The eye is in a headset. There is no desktop cursor to capture, and the stock game leaves the
## mouse visible, so the "cursor is visible" gates must not read that as a menu owning the input.
func headset_view() -> bool:
	return is_instance_valid(game) and bool(game.get("headset_view"))


func _bedside_pony(view: Camera3D) -> Node:
	# The player's bed/couch seat knows exactly who lies beside Anon.
	if is_instance_valid(player):
		var seat: Variant = player.get("seat")
		if is_instance_valid(seat) and seat.has_meta("couch"):
			var couch: Variant = seat.get_meta("couch")
			if is_instance_valid(couch) and couch.has_method("partner"):
				var partner: Variant = couch.call("partner", seat)
				if partner is Node and is_instance_valid(partner) and _is_act_target(partner):
					return partner
	return null


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
		if not _is_act_target(actor):
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


## Bind the Negotiation service's typed host. `reset()` drops it on a world close;
## `_on_world()` rebinds it. Every model callback is the one adapter; every world read is a plain
## public method here or in the Proactive facade.
func _bind_negotiation_host() -> void:
	if not is_instance_valid(negotiation):
		return
	var host := NEGOTIATION.Host.new()
	host.now = func() -> float: return Time.get_ticks_msec() / 1000.0
	host.eligible = func(pony) -> bool: return _is_act_target(pony)
	host.relationship_ok = func(pony) -> bool:
		return is_instance_valid(eligibility) and eligibility.relationship_ok(pony)
	host.context_facts = Callable(self, "context_facts")
	host.privacy_private = func(pony, cuddle) -> bool:
		if not is_instance_valid(privacy):
			return false
		return privacy.cuddle_private(pony) if cuddle else privacy.offer_private(pony)
	host.placement_for = func(runtime) -> POSE_OPTIONS.Placement:
		if is_instance_valid(initiation) and initiation.has_method("placement_for"):
			return initiation.call("placement_for", runtime)
		return POSE_OPTIONS.Placement.new()
	host.form_view = Callable(self, "form_view")
	host.hold_for = func(runtime):
		if is_instance_valid(runtime) and runtime.has_method("hold_handle"):
			return runtime.call("hold_handle")
		return null
	host.classify = func(request, scope, done) -> bool:
		return is_instance_valid(adapter) and bool(adapter.call("classify", request, scope, done))
	host.reason = func(request, scope, done) -> bool:
		return is_instance_valid(adapter) and bool(adapter.call("reason", request, scope, done))
	host.await_answer = func(pony, scope, done) -> bool:
		return is_instance_valid(adapter) and bool(adapter.call("await_answer", pony, scope, done))
	host.cancel_scope = func(scope) -> void:
		if is_instance_valid(adapter):
			adapter.call("cancel_scope", scope)
	host.toast = Callable(self, "_toast")
	host.log = Callable(self, "debug")
	host.react = Callable(self, "_negotiation_react")
	host.on_outcome = Callable(self, "_on_negotiation_outcome")
	host.on_agreement = Callable(self, "_on_agreement")
	negotiation.call("setup", host)


## The Proactive service's handoff: it passes the formed Mare offer as plain values; `main`
## builds the typed package and hands it to the Negotiation service, which owns the answer,
## privacy, pose re-checks and the Agreement from here.
func form_mare_offer(fields: Dictionary) -> bool:
	if not is_instance_valid(negotiation) or fields.is_empty():
		return false
	var offer := NEGOTIATION.MareOffer.new()
	offer.runtime = fields.get("runtime")
	offer.pony = fields.get("pony")
	offer.option = fields.get("option")
	offer.base = fields.get("base")
	offer.private = bool(fields.get("private", false))
	offer.hold_token = str(fields.get("hold_token", ""))
	offer.hold_old_wander = bool(fields.get("hold_old_wander", true))
	offer.line = str(fields.get("line", ""))
	offer.cuddle = bool(fields.get("cuddle", false))
	return bool(negotiation.call("begin_mare_offer", offer))


## The Context facts both Mare reasoning stages and the Negotiation Host read. One snapshot per
## call from the eligibility facts, act history, memory and the live privacy state.
func context_facts(pony: Node) -> Dictionary:
	var out: Dictionary = {}
	if not is_instance_valid(pony) or not is_instance_valid(eligibility):
		return out
	var verdict: ELIGIBILITY.Verdict = eligibility.get_verdict(pony, ELIGIBILITY.Mode.OFFER)
	if verdict == null or verdict.facts == null:
		return out
	var facts: ELIGIBILITY.Facts = verdict.facts
	var history: ELIGIBILITY.History = facts.history
	var id := facts.id
	out["willingness"] = facts.willing
	out["history"] = {
		"tier": history.tier, "hurt": history.hurt, "comfort": history.comfort,
		"blocks_start": history.blocks_start, "blocks_offers": history.blocks_offers,
		"offer_weight": history.offer_weight,
	}
	out["cycle_phase"] = facts.cycle_phase
	out["heat"] = facts.heat
	out["aftercare"] = pony.has_meta("sex_aftercare")
	out["private"] = is_instance_valid(privacy) and privacy.offer_private(pony)
	out["public_preference"] = facts.consent.public
	out["mood"] = _world_mood(id)
	out["relation_note"] = _relation_note(id)
	out["history_note"] = ACT_HISTORY.ask_note(ACT_HISTORY.effective_row(
		ACT_HISTORY.section(), id, ACT_HISTORY.day_now())) if not id.is_empty() else ""
	return out


## The player's live form and display for the pose option builder.
func form_view() -> NEGOTIATION.FormView:
	var out := NEGOTIATION.FormView.new()
	out.form = "pony" if PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())) else "human"
	out.view = "vr" if headset_view() else "desktop"
	return out


## The world-context impression mood for one id, or "".
func _world_mood(id: String) -> String:
	if id.is_empty() or not is_instance_valid(game):
		return ""
	var ctx: Variant = game.get("world_context")
	if ctx == null or not is_instance_valid(ctx):
		return ""
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions) or not impressions.has_method("profile"):
		return ""
	var prof: Variant = impressions.call("profile", id)
	return str((prof as Dictionary).get("mood", "")) if prof is Dictionary else ""


## The relationship prompt note for one id, or "".
func _relation_note(id: String) -> String:
	if id.is_empty() or not is_instance_valid(memory) or not is_instance_valid(game):
		return ""
	var facts: MEMORY.CueFacts = memory.cue_facts(id, "")
	var facts_dict := facts.to_dict()
	var note := RELATIONSHIP_CUE.note(facts_dict)
	if note.is_empty():
		return ""
	return note + " " + RELATIONSHIP_CUE.tone_line(RELATIONSHIP_CUE.tone(facts_dict))


func _toast(text: String) -> void:
	if text.is_empty() or not is_instance_valid(hud) or not hud.has_method("toast"):
		return
	hud.call("toast", text, 4.0)


## The shared interruption line: a short generated line, queued and not delaying the clear.
func _negotiation_react(pony: Node, _reason: String) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(adapter):
		return
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	if id.is_empty():
		return
	var key := "unfplap:negotiation:react:%d" % Time.get_ticks_usec()
	adapter.call("queue", id,
		"The moment was interrupted. Say one short, in-character line letting it go, without " \
		+ "anger. Do not ask again and do not narrate actions.",
		key, func() -> bool: return is_instance_valid(pony) and pony.is_inside_tree(), false)


## The global Anon-offer watch is armed only while no negotiation and no act is live, so a line
## answering a Mare offer is never seen twice.
func _tick_negotiation_watch() -> void:
	if not is_instance_valid(adapter) or not is_instance_valid(negotiation):
		return
	var free := not is_instance_valid(active_runtime) and not bool(negotiation.call("is_locked"))
	if free:
		if not _watching_player:
			_watching_player = true
			adapter.call("watch_player", Callable(self, "_on_anon_line"))
		return
	if _watching_player:
		_watching_player = false
		adapter.call("unwatch_player")


## The first new player line while he talks to a mare: an Anon offer. The Negotiation service
## classifies intent; a normal line forms nothing and says nothing.
func _on_anon_line(text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty() or line.length() > 600:
		return
	if not is_instance_valid(negotiation) or bool(negotiation.call("is_locked")):
		return
	if not is_instance_valid(classifier) or not bool(classifier.call("available")):
		return
	var pony := _conversation_mare()
	if not is_instance_valid(pony):
		return
	var runtime: Variant = runtime_for(pony)
	if not is_instance_valid(runtime) or int(runtime.get("state")) != 0:
		return
	if is_instance_valid(initiation) and initiation.has_method("cancel_approach"):
		initiation.call("cancel_approach")
	negotiation.call("begin_anon_offer", runtime, line)


## The mare whose conversation target is Anon, nearest first. The game's own target decides; the
## classifiers never reroute the director.
func _conversation_mare() -> Node:
	if not is_instance_valid(player):
		return null
	var best: Node = null
	var best_distance := INF
	for node: Variant in mares():
		if not is_instance_valid(node) or not _is_act_target(node):
			continue
		var target: Variant = node.get("conversation_target")
		if not is_instance_valid(target):
			continue
		var bound: bool = target == player \
			or (player is Node and (player as Node).is_ancestor_of(target))
		if not bound:
			continue
		var actor := node as Node3D
		var distance := actor.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _on_negotiation_outcome(terminal: Variant) -> void:
	if terminal == null:
		return
	var pony: Variant = terminal.pony
	if is_instance_valid(pony):
		var runtime: Variant = runtime_for(pony)
		if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
			runtime.call("clear_presentation")
	if terminal.outcome != NEGOTIATION.Outcome.STARTED \
			and is_instance_valid(initiation) and initiation.has_method("on_negotiation_outcome"):
		initiation.call("on_negotiation_outcome", terminal)


## The Agreement is ready: the target runtime consumes it through its one start path.
func _on_agreement(handle: Variant) -> void:
	if handle == null:
		return
	var pony: Variant = handle.pony
	var runtime: Variant = runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("start_agreement"):
		if is_instance_valid(negotiation):
			negotiation.call("cancel", handle, "cancelled")
		return
	# The presentation is act-owned: it starts now, and the auto-start waits for it to settle.
	var option: Variant = handle.option
	if option != null and str(option.pose) == CATALOG.STANDING \
			and not bool(runtime.call("present_standing")):
		_debug("agreement present failed pony=%s" % str(pony.name))
	_offer = null


func _exit_tree() -> void:
	close_debug_wheel()
	if is_instance_valid(eligibility):
		eligibility.clear()
		eligibility = null
	if is_instance_valid(api):
		api.call("_shutdown")
		api.queue_free()
		api = null
	_clear_native_hint()
	SETTINGS_UI.clear_pages()
	if is_instance_valid(initiation):
		initiation.reset()
		initiation.queue_free()
	if is_instance_valid(negotiation):
		negotiation.call("reset")
		negotiation.queue_free()
	if is_instance_valid(adapter):
		adapter.queue_free()
	negotiation = null
	adapter = null
	privacy = null
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
		classifier.queue_free()
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtime.force_stop()
			runtime.queue_free()
	_runtimes.clear()
	if is_instance_valid(stool):
		stool.call("shutdown")
		stool.queue_free()
		stool = null
	if is_instance_valid(pantyhose):
		pantyhose.call("shutdown")
		pantyhose.queue_free()
		pantyhose = null
	if is_instance_valid(anatomy):
		anatomy.call("shutdown")
		anatomy.queue_free()
		anatomy = null
	_offer = null
	_perf_idle.reset()
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
