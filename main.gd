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
const LOG := preload("res://mods/unfplap/shared/log.gd")
const CLASSIFIER := preload("res://mods/unfplap/initiation/classifier.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/actions.gd")
const DEBUG_STRETCH := preload("res://mods/unfplap/debug/idle_stretch.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const PANTYHOSE := preload("res://mods/unfplap/integrations/pantyhose.gd")
const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const STOCK_SMACK := preload("res://mods/unfplap/audio/stock_smack.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const DEBUG_UI := preload("res://mods/unfplap/debug/ui.gd")
const API := preload("res://mods/unfplap/api.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0

var hud
var input
## Cross-mod API facade; see docs/api.md.
var api: Node
## Anatomy system facade: per-pony controllers, the player part and tail seating.
var anatomy: Node
## Base body-change service: the per-body form store and the source/binding registries. Inert until
## the runtime and the providers register with it.
var body_change: Node
## The Pantyhose & Panties world adapter; inert when that pack is absent.
var pantyhose: Node
## The changelings world adapter; inert when that pack is absent.
var changelings: Node
## Footstool system facade: the standing reach rule, item, act prop and world supply.
var stool: Node
## Outside-act stock smack sound layer; see `docs/audio.md`.
var stock_smack: Node
var _anatomy_status_label: Label
var initiation: INITIATION
var privacy: PRIVACY
var classifier
## The one director and model bridge: the Proactive service and the Negotiation Host share it.
## See `docs/negotiation.md` (`## Director and model host`).
var adapter: Node
## The Act Negotiation service: the Anon offer, the Mare exchange, the Agreement and the lock.
var negotiation: Node
## Internal eligibility service; see docs/eligibility.md. Never part of the cross-mod API.
var eligibility: ELIGIBILITY
## Internal memory service: act events, impressions, witnesses and the mod's own lines.
## See docs/memory.md. Never part of the cross-mod API.
var memory: MEMORY

## The idle act offer and its hint; see docs/offer.md.
var offer: OFFER
var _dance_hint_shown := false
## Every Debug block button and wheel slot; see `docs/debug.md`.
var debug_actions: DEBUG_ACTIONS
## instance id -> WeakRef for every SpeechCaption the mod may move to the top.
var _captions: Dictionary = {}
## Cached captions_on_top so the per-frame caption tick never rereads settings.json.
var _captions_on_top: bool
## True while the adapter's global Anon-offer watch is armed.
var _watching_player := false


## Live act/afterglow context for the game's normal dialogue prompt (pony_prompt_notes). The
## game calls a Node in the group, so the entry keeps the group join and this forward;
## `ponies` is a RefCounted facade and owns the note.
func prompt_note(pony: String) -> String:
	return PONIES.prompt_note(pony)


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
	LOG.attach(self)
	# The two debug switches arrive here once and again on a settings edit; every other module asks
	# LOG, so no frame reads `settings` for them.
	LOG.debug_logs = SETTINGS.debug_mode.get_bool()
	LOG.debug_perf = SETTINGS.debug_perf.get_bool()
	LOG.act_running = Callable(PONIES, "act_running")
	LOG.counts = Callable(PONIES, "_counts")
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
	# The idle offer is built before the Proactive service, which asks it which pony the act key
	# would start. Its entry reads are the runtime registry, the act-target rule and the live act.
	offer = OFFER.new()
	offer.name = "UnfplapOffer"
	offer.runtime_for = Callable(self, "runtime_for")
	offer.act_target = Callable(self, "_is_act_target")
	offer.act_live = Callable(self, "_act_live")
	offer.negotiation = negotiation
	offer.privacy = privacy
	offer.apply_settings()
	add_child(offer)
	initiation = INITIATION.new()
	initiation.name = "UnfplapInitiation"
	initiation.call("setup", self, privacy, adapter, offer)
	add_child(initiation)
	anatomy = ANATOMY.new()
	anatomy.name = "UnfplapAnatomy"
	anatomy.call("setup", self)
	add_child(anatomy)
	body_change = BODY_CHANGE_SERVICE.new()
	body_change.name = "UnfplapBodyChange"
	body_change.call("setup", self)
	add_child(body_change)
	pantyhose = PANTYHOSE.new()
	pantyhose.name = "UnfplapPantyhose"
	pantyhose.call("setup", self)
	add_child(pantyhose)
	stool = STOOL.new()
	stool.name = "UnfplapStool"
	stool.call("setup", self)
	add_child(stool)
	stock_smack = STOCK_SMACK.new()
	stock_smack.name = "UnfplapStockSmack"
	stock_smack.set("log", Callable(LOG, "debug"))
	add_child(stock_smack)
	body_change.call("wire", anatomy, pantyhose, stock_smack)
	api = API.new()
	api.name = "UnfplapAPI"
	api.call("_bind", self)
	add_child(api)
	changelings = CHANGELINGS.new()
	changelings.name = "UnfplapChangelings"
	changelings.call("setup", self)
	add_child(changelings)
	body_change.call("register_source", changelings)
	# The debug actions run against the services above, so they are built last. Their exact reads
	# of the entry's act state are bound here and nowhere else.
	debug_actions = DEBUG_ACTIONS.new()
	debug_actions.name = "UnfplapDebugActions"
	debug_actions.host = _debug_host()
	debug_actions.body_change = body_change
	debug_actions.initiation = initiation
	debug_actions.negotiation = negotiation
	debug_actions.anatomy = anatomy
	debug_actions.pantyhose = pantyhose
	add_child(debug_actions)
	debug_actions.sync_skeleton_overlay()
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
	LOG.debug("entry ready (debug logs %s) runtime_mtime=%d" % [
		"ON" if LOG.debug_logs else "OFF", source_mtime])
	# The per-pony registry binds the services above once and builds its runtimes through the
	# one factory, so no other entry member holds a runtime.
	PONIES.host = self
	PONIES.factory = Callable(self, "_new_runtime")
	PONIES.anatomy = anatomy
	PONIES.body_change = body_change
	PONIES.offer = offer
	PONIES.stock_smack = stock_smack
	PONIES.eligibility = eligibility
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	Mods.player_ready.connect(_on_player)
	Mods.on_node(PONY_PATH, _on_pony)
	Mods.on_node(SETTINGS_PAGE_PATH, _on_settings_page)
	Mods.on_node(CAPTION_PATH, _on_caption)
	Mods.on_node(DEBUG_STRETCH.ENTRY_PATH, Callable(debug_actions, "on_idle_life"))
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
	debug_actions.close_debug_wheel()
	offer.on_world(host)
	_dance_hint_shown = false
	WORLD.bind_world(host)
	if not is_instance_valid(eligibility):
		eligibility = ELIGIBILITY.new()
	eligibility.setup(self)
	PONIES.eligibility = eligibility
	if is_instance_valid(stool):
		stool.call("on_world", host)
	if is_instance_valid(pantyhose):
		pantyhose.call("on_world", host)
	if is_instance_valid(body_change):
		body_change.call("refresh_sources")
	PONIES.reset()
	LOG.reset()
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
	LOG.debug("world closed")
	debug_actions.close_debug_wheel()
	if is_instance_valid(pantyhose):
		pantyhose.call("on_world_closed")
	if is_instance_valid(anatomy):
		anatomy.call("clear_player")
	offer.reset()
	if is_instance_valid(initiation):
		initiation.reset()
	if is_instance_valid(negotiation):
		negotiation.call("reset")
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
	PONIES.close_world()
	if is_instance_valid(stock_smack):
		stock_smack.call("clear_world")
	WORLD.unbind()
	LOG.reset()
	LOG.clear_panel()
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
	var active: Node = PONIES.active()
	if not is_instance_valid(active):
		return false
	var state: int = int(active.get("state"))
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
	var active: Node = PONIES.active()
	if is_instance_valid(active) and active.has_method("apply_live_settings"):
		active.call("apply_live_settings")


## One path for every control edit: refresh the cached flags, the caption position and the live
## act. Every tunable change goes through here, so a control never needs its own handler.
func apply_settings_changed() -> void:
	_apply_settings_changed()


func _apply_settings_changed() -> void:
	LOG.debug_logs = SETTINGS.debug_mode.get_bool()
	LOG.debug_perf = SETTINGS.debug_perf.get_bool()
	if not (LOG.debug_logs and LOG.debug_perf):
		LOG.clear_panel()
	if not LOG.debug_logs:
		debug_actions.close_debug_wheel()
	if is_instance_valid(input):
		input.call("apply_settings")
	if is_instance_valid(hud):
		hud.call("set_act_key", _act_key_label())
	# The native offer row and the fallback prompt carry the key cap; rebuild them with the new
	# label on the next frame.
	offer.apply_settings()
	debug_actions.sync_skeleton_overlay()
	SETTINGS_UI.refresh_debug_visibility()
	_apply_caption_top()
	_apply_live_settings()
	# integration: anatomy switches are live outside acts too.
	refresh_anatomy()
	if is_instance_valid(anatomy):
		anatomy.call("refresh_tails")
	if is_instance_valid(body_change):
		# A settings edit can change the re-seat toggle or a saved tail; the source applies its
		# own wrapper once for each live body.
		for pony: Variant in PONIES.live_ponies():
			if is_instance_valid(pony):
				apply_custom_tail(pony)
	if is_instance_valid(pantyhose):
		pantyhose.call("apply_live_settings")
	if is_instance_valid(stock_smack):
		stock_smack.call("apply_settings")


## The anatomy controller owns the genitals material; refresh the dock after it attaches, changes
## tone or detaches.
func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(anatomy):
		anatomy.call("refresh_dock_color", pony)


func _on_player(body: Node) -> void:
	WORLD.bind_player(body)
	LOG.debug("player ready")
	if not is_instance_valid(hud):
		hud = HUD.new()
		hud.name = "UnfplapHUD"
		hud.log = Callable(LOG, "debug")
		add_child(hud)
		debug_actions.hud = hud
	if is_instance_valid(anatomy):
		anatomy.call("player_ready", body)
	if not is_instance_valid(input):
		input = INPUT.new()
		input.name = "UnfplapInput"
		input.main = self
		input.offer = offer
		add_child(input)
	offer.hud = hud
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


## Every body the game spawns arrives here. `ponies` owns the registry, the prepare hooks
## and the pending-swap adoption; the factory below is the entry's only runtime
## construction.
func _on_pony(pony: Node) -> void:
	PONIES.attach(pony)


## The entry's one runtime construction: `ponies` calls it once per attached body. The
## runtime file is the entry's preload, so the registry never imports it.
func _new_runtime(pony: Node) -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.set("pony", pony)
	runtime.set("main", self)
	return runtime


## The first active source that handles this pony, or null.
func shape_source_for(pony: Node) -> Variant:
	if not is_instance_valid(body_change):
		return null
	return body_change.call("source_for", pony)


## Any active shape-changing source, for the debug block's visibility gate.
func shape_source_active() -> bool:
	return is_instance_valid(body_change) and bool(body_change.call("active"))


## True when the body's source owns a tail placement the anatomy editor can move.
func custom_tail_ready(pony: Node) -> bool:
	return is_instance_valid(body_change) and bool(body_change.call("has_tail_placement", pony))


## Re-apply the source's current tail placement after an anatomy edit or a settings change.
func apply_custom_tail(pony: Node) -> void:
	if is_instance_valid(body_change):
		body_change.call("apply_tail_placement", pony)


## The live source-owned tail lines, one per wrapper.
func custom_tail_report() -> String:
	if not is_instance_valid(body_change):
		return ""
	return str(body_change.call("tail_placement_report"))


## The settings page hook. No game-script extension is used. Opening the page re-reads
## settings.json; the settings UI owns the deferred injection and the sub-tabs.
func _on_settings_page(page: Node) -> void:
	SETTINGS_UI.inject(page, Callable(self, "_build_settings_actions"),
		Callable(PONIES, "live_character_ids"), Callable(self, "_character_participation"),
		Callable(self, "_apply_settings_changed"), Callable(LOG, "debug"))


## The Debug block builder the settings panel inserts into each tab.
func _build_settings_actions(list: VBoxContainer, font_size: int, tab: String) -> void:
	DEBUG_UI.build_actions(list, font_size, debug_actions, tab)


## The live participation block for one mare. The Characters form is a settings UI file, so the
## eligibility service is reached through the entry node instead of a service dependency.
func _character_participation(id: String) -> Dictionary:
	if is_instance_valid(eligibility):
		return eligibility.get_profile(id).participation.to_dict()
	return {}


## The debug actions' reads of the live act. The runtime registry is `ponies`', so these named
## reads are the one place the entry hands them over.
func _debug_host() -> DEBUG_ACTIONS.Host:
	var host := DEBUG_ACTIONS.Host.new()
	host.act = func() -> Node: return PONIES.active()
	host.runtime_for = Callable(PONIES, "runtime_for")
	host.runtimes = func() -> Array: return PONIES.live_ponies()
	host.act_target = func(pony: Variant) -> bool: return _is_act_target(pony)
	host.reload_posed_base = func() -> String: return AUTHORED.reload_file()
	return host


func _process(delta: float) -> void:
	var timed := LOG.tick(delta)
	var started := Time.get_ticks_usec() if timed else 0
	_process_entry(delta, timed)
	if timed:
		LOG.close("entry_process", started)


## The entry's per-frame body. `_process` above only times it for the idle probe; the call order
## here is load-bearing.
func _process_entry(delta: float, timed: bool) -> void:
	# The caption move is an act-only path; the two reads behind it are not worth a per-frame call.
	var active: Node = PONIES.active()
	if _captions_on_top and is_instance_valid(active):
		_caption_top_tick()
	if not is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game):
		var body: Variant = WORLD.game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active):
		var camera_started := Time.get_ticks_usec()
		active.call("apply_camera_motion")
		active.call("perf_note", "camera_motion", Time.get_ticks_usec() - camera_started)
		if is_instance_valid(hud):
			var hud_started := Time.get_ticks_usec()
			hud.update_from(active.call("act_view"))
			active.call("perf_note", "hud", Time.get_ticks_usec() - hud_started)
		offer.hide_hint()
		return

	offer.tick(delta)
	if is_instance_valid(initiation):
		var initiation_started := Time.get_ticks_usec() if timed else 0
		initiation.tick(delta)
		if timed:
			LOG.close("entry_initiation", initiation_started)
	if is_instance_valid(negotiation):
		var negotiation_started := Time.get_ticks_usec() if timed else 0
		negotiation.tick(delta)
		if timed:
			LOG.close("entry_negotiation", negotiation_started)
	var watch_started := Time.get_ticks_usec() if timed else 0
	_tick_negotiation_watch()
	if timed:
		LOG.close("entry_watch", watch_started)


## The live placement re-check the Negotiation asks for before an Agreement forms: the chosen
## option's scene-only rows, with no frozen capability and no hold exemption. It is a scene
## check, not a new policy read.
func agreement_pose_placed(runtime: Node, option: POSE_OPTIONS.Option) -> bool:
	if not is_instance_valid(runtime) or option == null \
			or not runtime.has_method("scene_only_verdict"):
		return false
	var verdict: Variant = runtime.call("scene_only_verdict", option.pose, option.source,
		option.bed, null)
	return verdict != null and bool(verdict.hard_ok)


## integration: anatomy hooks used by the runtime and input.
func anatomy_status(text: String, seconds := 2.0) -> void:
	if is_instance_valid(hud) and hud.has_method("toast"):
		hud.call("toast", text, seconds)
	else:
		LOG.debug(text)


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
	PONIES.apply_live_settings()
	if is_instance_valid(anatomy):
		anatomy.call("refresh_player")
		anatomy.call("refresh_all")
		anatomy.call("apply_live")
		anatomy.call("player_apply_live")


## The act-target capability. The eligibility service owns the rule; a scan uses this before
## building a runtime gate for a stallion or a young pony.
func _is_act_target(pony: Variant) -> bool:
	return is_instance_valid(eligibility) \
		and eligibility.eligible(pony, ELIGIBILITY.Target.ACT)


## The offer's act-live read: a live act owns the frame, so the act key starts nothing and no
## Agreement auto-starts.
func _act_live() -> bool:
	return PONIES.act_running()


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
	host.pose_placed = Callable(self, "agreement_pose_placed")
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
	host.log = Callable(LOG, "debug")
	host.react = Callable(self, "_negotiation_react")
	host.on_outcome = Callable(self, "_on_negotiation_outcome")
	host.on_agreement = Callable(self, "_on_agreement")
	negotiation.call("setup", host)


## True while an Act Negotiation (offer or Agreement) owns the lock. The Proactive scan stays
## quiet, so no second mare starts a reasoning call or a walk.
func negotiation_locked() -> bool:
	return is_instance_valid(negotiation) and bool(negotiation.call("is_locked"))


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
	out.view = "vr" if WORLD.headset_view() else "desktop"
	return out


## The world-context impression mood for one id, or "".
func _world_mood(id: String) -> String:
	if id.is_empty() or not is_instance_valid(WORLD.game):
		return ""
	var ctx: Variant = WORLD.game.get("world_context")
	if ctx == null or not is_instance_valid(ctx):
		return ""
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions) or not impressions.has_method("profile"):
		return ""
	var prof: Variant = impressions.call("profile", id)
	return str((prof as Dictionary).get("mood", "")) if prof is Dictionary else ""


## The relationship prompt note for one id, or "".
func _relation_note(id: String) -> String:
	if id.is_empty() or not is_instance_valid(memory) or not is_instance_valid(WORLD.game):
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


## Read a typed field from the production handle/terminal or a test dictionary.
func _field(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(key, fallback)
	if value == null:
		return fallback
	var got: Variant = value.get(key)
	return fallback if got == null else got


## The shared terminal line. The purpose follows the close reason: a counter-offer still wants
## him, a privacy loss lets the moment go, and every other close is the generic release. It is a
## short generated line, queued and not delaying the clear.
func _negotiation_react(pony: Node, reason: String) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(adapter):
		return
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	if id.is_empty():
		return
	var purpose := ""
	match reason:
		NEGOTIATION.AGREEMENT.REASON_COUNTER_OFFER:
			purpose = "Anon just offered sex and she said no only to the place or the timing, " \
				+ "because she still wants him. Say one short, in-character line declining that " \
				+ "place or moment and making that clear. Do not ask again and do not narrate actions."
		NEGOTIATION.AGREEMENT.REASON_PRIVACY:
			purpose = "The moment was interrupted. Say one short, in-character line letting it " \
				+ "go, without anger. Do not ask again and do not narrate actions."
		_:
			purpose = "The offer ended. Say one short, in-character line letting it go, without " \
				+ "anger. Do not ask again and do not narrate actions."
	var key := "unfplap:negotiation:react:%d" % Time.get_ticks_usec()
	adapter.call("queue", id, purpose,
		key, func() -> bool: return is_instance_valid(pony) and pony.is_inside_tree(), false)


## The global Anon-offer watch is armed only while no negotiation and no act is live, so a line
## answering a Mare offer is never seen twice.
func _tick_negotiation_watch() -> void:
	if not is_instance_valid(adapter) or not is_instance_valid(negotiation):
		return
	var free := not PONIES.act_running() and not bool(negotiation.call("is_locked"))
	if free:
		if not _watching_player:
			_watching_player = true
			adapter.call("watch_player", Callable(self, "_on_anon_line"))
			LOG.debug("anon_watch armed")
		return
	if _watching_player:
		_watching_player = false
		adapter.call("unwatch_player")
		LOG.debug("anon_watch disarmed reason=%s" % [
			"act" if PONIES.act_running() else "locked"])


## The first new player line while he talks to a mare: an Anon offer. The Negotiation service
## classifies intent; a normal line forms nothing and says nothing.
func _on_anon_line(text: String) -> void:
	var line := text.strip_edges()
	LOG.debug("anon_line received len=%d" % line.length())
	if line.is_empty():
		LOG.debug("anon_line skip reason=empty")
		return
	if line.length() > 600:
		LOG.debug("anon_line skip reason=too_long len=%d" % line.length())
		return
	if not is_instance_valid(negotiation) or bool(negotiation.call("is_locked")):
		LOG.debug("anon_line skip reason=locked")
		return
	if not is_instance_valid(classifier) or not bool(classifier.call("available")):
		LOG.debug("anon_line skip reason=no_classifier")
		return
	var pony := _conversation_mare()
	if not is_instance_valid(pony):
		LOG.debug("anon_line skip reason=no_target")
		return
	var runtime: Variant = PONIES.runtime_for(pony)
	if not is_instance_valid(runtime) or int(runtime.get("state")) != 0:
		LOG.debug("anon_line skip reason=runtime_state state=%s" % [
			str(runtime.get("state")) if is_instance_valid(runtime) else "none"])
		return
	if is_instance_valid(initiation) and initiation.has_method("cancel_approach"):
		initiation.call("cancel_approach")
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	LOG.debug("anon_line -> negotiation id=%s" % [id if not id.is_empty() else str(pony.name)])
	var started := bool(negotiation.call("begin_anon_offer", runtime, line))
	LOG.debug("anon_line negotiation started=%s" % str(started))


## The mare whose conversation target is Anon, nearest first. The game's own target decides; the
## classifiers never reroute the director.
func _conversation_mare() -> Node:
	if not is_instance_valid(WORLD.player):
		return null
	var best: Node = null
	var best_distance := INF
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node) or not _is_act_target(node):
			continue
		var target: Variant = node.get("conversation_target")
		if not is_instance_valid(target):
			continue
		var bound: bool = target == WORLD.player \
			or (WORLD.player is Node and (WORLD.player as Node).is_ancestor_of(target))
		if not bound:
			continue
		var actor := node as Node3D
		var distance := actor.global_position.distance_to(WORLD.player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _on_negotiation_outcome(terminal: Variant) -> void:
	if terminal == null:
		return
	LOG.debug("negotiation outcome id=%s outcome=%d reason=%s cooldown=%.0f" % [
		str(_field(terminal, "pony_id", "")), int(_field(terminal, "outcome", 0)),
		str(_field(terminal, "reason", "")) if not str(_field(terminal, "reason", "")).is_empty()
			else "none", float(_field(terminal, "cooldown_s", 0.0))])
	var pony: Variant = _field(terminal, "pony")
	if is_instance_valid(pony):
		var runtime: Variant = PONIES.runtime_for(pony)
		if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
			runtime.call("clear_presentation")
	if int(_field(terminal, "outcome", -1)) != NEGOTIATION.Outcome.STARTED \
			and is_instance_valid(initiation) and initiation.has_method("on_negotiation_outcome"):
		initiation.call("on_negotiation_outcome", terminal)


## The Agreement is ready: the target runtime consumes it through its one start path.
func _on_agreement(handle: Variant) -> void:
	if handle == null:
		return
	var pony: Variant = _field(handle, "pony")
	var pony_id := str(_field(handle, "pony_id", ""))
	if pony_id.is_empty() and is_instance_valid(pony):
		pony_id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	var option: Variant = _field(handle, "option")
	LOG.debug("agreement formed id=%s trigger=%s pose=%s private=%s" % [
		pony_id, str(_field(handle, "trigger", "")),
		str(_field(option, "pose", "none")) if option != null else "none",
		str(_field(handle, "private", false))])
	var runtime: Variant = PONIES.runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("start_agreement"):
		if is_instance_valid(negotiation):
			negotiation.call("cancel", handle, "cancelled")
		return
	# The presentation is act-owned: it starts now, and the auto-start waits for it to settle.
	if option != null and str(option.pose) == CATALOG.STANDING \
			and not bool(runtime.call("present_standing")):
		LOG.debug("agreement present failed pony=%s" % str(pony.name))
	offer.clear_current()


func _exit_tree() -> void:
	if is_instance_valid(debug_actions):
		debug_actions.close_debug_wheel()
	if is_instance_valid(eligibility):
		eligibility.clear()
		eligibility = null
	if is_instance_valid(changelings):
		changelings.call("shutdown")
		changelings.queue_free()
		changelings = null
	if is_instance_valid(api):
		api.call("_shutdown")
		api.queue_free()
		api = null
	offer.reset()
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
	PONIES.shutdown()
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
	if is_instance_valid(stock_smack):
		stock_smack.call("shutdown")
		stock_smack.queue_free()
		stock_smack = null
	LOG.detach()
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
