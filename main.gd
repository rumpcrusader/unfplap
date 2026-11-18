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
const ANATOMY_BINDING := preload("res://mods/unfplap/anatomy/body_binding.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const LOD_BINDING := preload("res://mods/unfplap/body_change/lod_binding.gd")
const GARMENT_BINDING := preload("res://mods/unfplap/body_change/garment_binding.gd")
const SMACK_BINDING := preload("res://mods/unfplap/body_change/smack_binding.gd")
const RUNTIME_BINDING := preload("res://mods/unfplap/runtime/body_binding.gd")
const PANTYHOSE := preload("res://mods/unfplap/integrations/pantyhose.gd")
const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const STOCK_SMACK := preload("res://mods/unfplap/audio/stock_smack.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const DEBUG_UI := preload("res://mods/unfplap/debug/ui.gd")
const API := preload("res://mods/unfplap/api.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0
## The offer hint beside the game's prompt row: a single act-key press starts the act, so it reads
## like the base game's tap prompts ("G · Carry"), not a hold. Only holding the act key during an
## act is a hold.
const OFFER_HINT := "Make love"
## The idle offer hint's scan cadence. The act key rescans immediately in `try_start()`.
const OFFER_SCAN_S := 1.0
## The standing gate's refresh cadence while the same mare stays the cone target; the scan reads
## the cone every `OFFER_SCAN_S`, the full gate is the expensive half.
const GATE_REFRESH_S := 2.0
## The standing-act note when her reach needs a footstool and Anon has none in the case.
const NEEDS_STOOL_HINT := "Needs a footstool"

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
var active_runtime
## Internal eligibility service; see docs/eligibility.md. Never part of the cross-mod API.
var eligibility: ELIGIBILITY
## Internal memory service: act events, impressions, witnesses and the mod's own lines.
## See docs/memory.md. Never part of the cross-mod API.
var memory: MEMORY

var _runtimes: Dictionary = {}
## One suspended act waiting for the body its source is building. The runtime reparents itself to
## `main` before the old body goes; the new body's spawn adopts it here.
var _pending_swap: Dictionary = {}
## The idle scan's playable offer and its blocked variant. Both are typed `PoseOffer` handles;
## null means none. See `start_pose_offer()`.
var _offer: POSE_OFFER = null
var _offer_blocked: POSE_OFFER = null
var _offer_clock := 0.0
## The standing gate's last verdict and its footstool pair, reused while the same mare stays the
## cone target. See `_standing_ready()`.
var _gate_target: Node
var _gate_at := 0.0
var _gate_ready := false
var _gate_stool_need := 0
var _gate_stool_have := 0
var _last_offer_key := ""
var _last_blocked_key := ""
var _stool_hint_toast_shown := false
var _native_hint_label: Control
var _native_hint_text := ""
## The game's hints node and its 2D prompt row; resolved once per world, not per frame.
var _native_hints_node: Node
var _native_hint_row: HBoxContainer
var _dance_hint_shown := false
## Every Debug block button and wheel slot; see `docs/debug.md`.
var debug_actions: DEBUG_ACTIONS
## instance id -> WeakRef for every SpeechCaption the mod may move to the top.
var _captions: Dictionary = {}
## Cached captions_on_top so the per-frame caption tick never rereads settings.json.
var _captions_on_top: bool
## True while the adapter's global Anon-offer watch is armed.
var _watching_player := false
## The Agreement auto-start's 0.25 s readiness clock.
var _agreement_clock := 0.0


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
	LOG.act_running = Callable(self, "_perf_act_running")
	LOG.counts = Callable(self, "_perf_counts")
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
	body_change = BODY_CHANGE_SERVICE.new()
	body_change.name = "UnfplapBodyChange"
	body_change.call("setup", self)
	add_child(body_change)
	var anatomy_binding: RefCounted = ANATOMY_BINDING.new()
	anatomy_binding.call("setup", anatomy)
	body_change.call("register_binding", anatomy_binding)
	var runtime_binding: RefCounted = RUNTIME_BINDING.new()
	runtime_binding.call("setup", self)
	body_change.call("register_binding", runtime_binding)
	var lod_binding: RefCounted = LOD_BINDING.new()
	lod_binding.call("setup", self)
	body_change.call("register_binding", lod_binding)
	pantyhose = PANTYHOSE.new()
	pantyhose.name = "UnfplapPantyhose"
	pantyhose.call("setup", self)
	add_child(pantyhose)
	var garment_binding: RefCounted = GARMENT_BINDING.new()
	garment_binding.call("setup", pantyhose)
	body_change.call("register_binding", garment_binding)
	stool = STOOL.new()
	stool.name = "UnfplapStool"
	stool.call("setup", self)
	add_child(stool)
	stock_smack = STOCK_SMACK.new()
	stock_smack.name = "UnfplapStockSmack"
	stock_smack.set("log", Callable(LOG, "debug"))
	add_child(stock_smack)
	var smack_binding: RefCounted = SMACK_BINDING.new()
	smack_binding.call("setup", stock_smack)
	body_change.call("register_binding", smack_binding)
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
	_clear_native_hint()
	_dance_hint_shown = false
	WORLD.bind_world(host)
	if not is_instance_valid(eligibility):
		eligibility = ELIGIBILITY.new()
	eligibility.setup(self)
	if is_instance_valid(stool):
		stool.call("on_world", host)
	if is_instance_valid(pantyhose):
		pantyhose.call("on_world", host)
	if is_instance_valid(body_change):
		body_change.call("refresh_sources")
	_stool_hint_toast_shown = false
	_last_blocked_key = ""
	_offer = null
	_offer_blocked = null
	_pending_swap = {}
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
	_warm_offer_assets()


## Parse the two offerable pose assets while the world is still under its loading cover. The idle
## hint's authored row would otherwise load them inside its first scan.
func _warm_offer_assets() -> void:
	for pose: String in [POSE_SPECS.MISSIONARY, POSE_SPECS.STANDING]:
		var asset_path := str(POSE_SPECS.spec(pose).get("asset", ""))
		if not asset_path.is_empty():
			AUTHORED.shared(asset_path)


func _on_world_closed(_host: Node) -> void:
	LOG.debug("world closed")
	debug_actions.close_debug_wheel()
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
	_pending_swap = {}
	if is_instance_valid(stock_smack):
		stock_smack.call("clear_world")
	WORLD.unbind()
	_offer = null
	_offer_blocked = null
	_gate_target = null
	_gate_at = 0.0
	_gate_ready = false
	LOG.reset()
	LOG.clear_panel()
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
	_clear_native_hint()
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
		for pony: Variant in _runtimes.keys():
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
	_prepare_pony(pony)
	if _adopt_pending_swap(pony):
		return
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
	LOG.debug("runtime attached %s id=%s" % [str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


## Record the act's one pending body swap. The runtime keeps the act; this record only lets the
## new body's spawn find it before a second runtime is created.
func begin_body_swap(runtime: Node, old_pony: Node, id: String, change: BODY_CHANGE) -> void:
	if not is_instance_valid(runtime) or change == null:
		return
	_pending_swap = {
		"runtime": runtime,
		"old_pony": old_pony,
		"id": id,
		"change": change,
	}
	if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
		_runtimes.erase(old_pony)


## The swap finished, failed or the act ended. Idempotent and scoped to the runtime.
func clear_body_swap(runtime: Node) -> void:
	if _pending_swap.get("runtime") == runtime:
		_pending_swap = {}


func body_swap_pending() -> bool:
	return not _pending_swap.is_empty()


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


## Fit and prepare a new body before it can take a runtime or an act. The body-change service asks
## the handling provider for the body's form and mirrors it before anatomy attaches.
func _prepare_pony(pony: Node) -> void:
	if is_instance_valid(body_change):
		body_change.call("notify_body_ready", pony)
	if is_instance_valid(anatomy):
		anatomy.call("tail_ready", pony)
	if is_instance_valid(stock_smack):
		stock_smack.call("pony_ready", pony)


## A mod that adds a node the first prepare needed, such as the changelings tail chain, calls
## this once it exists. Every prepare hook is idempotent, and this never creates a runtime.
func prepare_pony_late(pony: Node) -> void:
	if not is_instance_valid(pony) or not is_inside_tree():
		return
	_prepare_pony(pony)


## Adopt the body the suspended act's source reports when the spawn hook arrives too late for the
## pending swap. The runtime calls this from its watcher after the adoption grace.
func adopt_pending_body(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	_prepare_pony(pony)
	return _adopt_pending_swap(pony)


## Adopt the suspended act onto a newly spawned body. Runs after the adapter fitted it but before
## a runtime is created, so there is never a second act owner. Returns true when it adopted.
func _adopt_pending_swap(pony: Node) -> bool:
	if _pending_swap.is_empty() or not is_instance_valid(pony):
		return false
	var runtime: Variant = _pending_swap.get("runtime")
	if not is_instance_valid(runtime):
		_pending_swap = {}
		return false
	var change: Variant = _pending_swap.get("change")
	var source: Node = null
	if change is BODY_CHANGE and is_instance_valid((change as BODY_CHANGE).source):
		source = (change as BODY_CHANGE).source
	var claimed: bool = is_instance_valid(source) and source.has_method("claims_body") \
		and bool(source.call("claims_body", pony))
	if not claimed:
		var identity: Variant = pony.get("identity")
		var new_id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
		if new_id != str(_pending_swap.get("id", "")):
			return false
	var duplicate: Variant = _runtimes.get(pony)
	if is_instance_valid(duplicate) and duplicate != runtime:
		# A runtime created before adoption could only be a race; the suspended act is the owner.
		# Its anatomy controller holds the duplicate's facts, so drop it before the bind below.
		if is_instance_valid(anatomy) and anatomy.has_method("detach_controller"):
			anatomy.call("detach_controller", pony)
		if duplicate.has_method("force_stop"):
			duplicate.call("force_stop")
		duplicate.queue_free()
	var old_pony: Variant = _pending_swap.get("old_pony")
	if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
		_runtimes.erase(old_pony)
	_runtimes[pony] = runtime
	if is_instance_valid(anatomy):
		anatomy.call("bind", pony, runtime)
	if runtime.get_parent() != pony:
		runtime.call("attach_to_body", pony)
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))
	_pending_swap = {}
	runtime.call("adopt_body", pony)
	return true


## Live adult mares that are not in the base roster, for the Characters selector. A modded mare
## appears while she is in the world; her saved preset stays in settings.json when she despawns.
## Installed-profile sources also list their mares while they are away.
func live_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for pony: Variant in _runtimes.keys():
		if pony is Node3D and is_instance_valid(pony) and is_instance_valid(eligibility) \
				and eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER):
			ids.append(ANATOMY.pony_id(pony))
	var out: Array[String] = ANATOMY.off_roster_ids(ids, SETTINGS.CHARACTER_ORDER)
	for id: String in installed_character_ids():
		if not id in SETTINGS.CHARACTER_ORDER and not out.has(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return SETTINGS.character_name(a).naturalnocasecmp_to(
			SETTINGS.character_name(b)) < 0)
	return out


## Mares an active installed-profile source lists even while she is away. The source owns the
## installation gate; the base roster stays the base roster.
func installed_character_ids() -> Array[String]:
	if not is_instance_valid(body_change):
		return []
	return body_change.call("installed_character_ids")


## The settings page hook. No game-script extension is used. Opening the page re-reads
## settings.json; the settings UI owns the deferred injection and the sub-tabs.
func _on_settings_page(page: Node) -> void:
	SETTINGS_UI.inject(page, Callable(self, "_build_settings_actions"),
		Callable(self, "live_character_ids"), Callable(self, "_character_participation"),
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


## The idle probe's act gate. The runtime belongs to the entry until the pony registry moves out,
## so the entry is the one place that can answer it.
func _perf_act_running() -> bool:
	return is_instance_valid(active_runtime)


## The idle block's header counts. Read once per window, never per note.
func _perf_counts() -> Dictionary:
	var runtimes := 0
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtimes += 1
	return {"runtimes": runtimes, "mares": WORLD.mares().size()}


## The debug actions' reads of the live act. The runtime registry is the entry's until `ponies`
## owns it, so these named reads are the one place it hands them over.
func _debug_host() -> DEBUG_ACTIONS.Host:
	var host := DEBUG_ACTIONS.Host.new()
	host.act = func() -> Node: return active_runtime if is_instance_valid(active_runtime) else null
	host.runtime_for = Callable(self, "runtime_for")
	host.runtimes = func() -> Array: return _runtimes.keys()
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
	if _captions_on_top and is_instance_valid(active_runtime):
		_caption_top_tick()
	if not is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game):
		var body: Variant = WORLD.game.get("player")
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
	if _offer_clock >= OFFER_SCAN_S:
		_offer_clock = 0.0
		if timed:
			var offer_started := Time.get_ticks_usec()
			_refresh_offer()
			LOG.close("offer_scan", offer_started)
		else:
			_refresh_offer()
	if is_instance_valid(initiation):
		var initiation_started := Time.get_ticks_usec() if timed else 0
		initiation.tick(delta)
		if timed:
			LOG.close("entry_initiation", initiation_started)
	if is_instance_valid(negotiation):
		var negotiation_started := Time.get_ticks_usec() if timed else 0
		negotiation.tick(delta)
		_tick_agreement_auto_start(delta)
		if timed:
			LOG.close("entry_negotiation", negotiation_started)
	var watch_started := Time.get_ticks_usec() if timed else 0
	_tick_negotiation_watch()
	if timed:
		LOG.close("entry_watch", watch_started)
	var hint := ""
	if _offer != null:
		hint = OFFER_HINT
	elif _offer_blocked != null:
		var blocked_hint := _offer_blocked.blocked_hint()
		hint = blocked_hint if not blocked_hint.is_empty() else NEEDS_STOOL_HINT
	else:
		_last_offer_key = ""
		_last_blocked_key = ""
	var hint_started := Time.get_ticks_usec() if timed else 0
	_sync_native_hint(hint)
	if timed:
		LOG.close("entry_hint", hint_started)


func _refresh_offer() -> void:
	_offer = null
	_offer_blocked = null
	if not is_instance_valid(WORLD.player) or not is_instance_valid(WORLD.game):
		return
	if get_tree().paused:
		return
	if DisplayServer.get_name() != "headless" and not WORLD.headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = WORLD.camera()
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
	if not pony_form and is_instance_valid(WORLD.player) and WORLD.player.get("seat") != null:
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
	var timed := LOG.idle_on()
	var cone_started := Time.get_ticks_usec() if timed else 0
	var standing: Node = _rump_cone_target(view)
	if timed:
		LOG.note("offer_cone", Time.get_ticks_usec() - cone_started)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime):
			var gate_started := Time.get_ticks_usec() if timed else 0
			var ready := _standing_ready(standing, runtime)
			if timed:
				LOG.note("offer_gate", Time.get_ticks_usec() - gate_started)
			if ready:
				_offer = _new_offer(runtime, standing, CATALOG.STANDING, "", null)
				_log_offer()
			else:
				var need := _gate_stool_need
				if need > 0 and _gate_stool_have < need:
					var blocked_offer := _new_offer(runtime, standing, CATALOG.STANDING, "", null)
					blocked_offer.blocked = _blocked_record(need, _stool_hint_for(need))
					_offer_blocked = blocked_offer
					_log_blocked_offer(runtime, standing, need)


## The standing gate, with its verdict reused while the same mare stays the cone target. The full
## gate costs about half a millisecond (the scene rows, the pose rows and her relationship ladder),
## and its inputs change on a state transition the cone scan cannot see, so it is refreshed every
## `GATE_REFRESH_S`. The act key runs the gate again on every press, so a reused verdict can only
## hold the hint back, never start or block an act.
func _standing_ready(target: Node, runtime: Node) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if target == _gate_target and now - _gate_at < GATE_REFRESH_S:
		return _gate_ready
	_gate_target = target
	_gate_at = now
	_gate_ready = bool(runtime.call("hotkey_ready", CATALOG.STANDING, "", null))
	_gate_stool_need = 0
	_gate_stool_have = 0
	if not _gate_ready:
		var stool: Dictionary = runtime.call("hint_stool")
		_gate_stool_need = int(stool.get("need", 0))
		_gate_stool_have = int(stool.get("have", 0))
	return _gate_ready


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
	# candidates pay for it, and only while they beat the nearest eligible one already found.
	# One pass keeps the scan allocation-free: the scan runs every second in the frame.
	var best: Node3D = null
	var best_distance := INF
	for node: Variant in WORLD.mares():
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
		if distance > RUMP_CONE.REACH_M or distance >= best_distance:
			continue
		if not _is_act_target(actor):
			continue
		best_distance = distance
		best = actor
	return best


func _native_row() -> HBoxContainer:
	# The row is read every frame, so it is cached: the path lookup allocates a NodePath and walks
	# the tree, and the game keeps the same hints node and row for the whole world.
	if is_instance_valid(_native_hint_row) and _native_hint_row.is_inside_tree():
		return _native_hint_row
	_native_hint_row = null
	if not is_instance_valid(_native_hints_node) or _native_hints_node.get_parent() != WORLD.game:
		_native_hints_node = WORLD.game.get_node_or_null("InteractionHints") \
			if is_instance_valid(WORLD.game) else null
	if not is_instance_valid(_native_hints_node):
		return null
	# VR uses the world-space prompt row; the act-key hint falls back to the HUD prompt there.
	if bool(_native_hints_node.get("xr")):
		return null
	var row: Variant = _native_hints_node.get("_prompt2d")
	if row is HBoxContainer and is_instance_valid(row):
		_native_hint_row = row
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
	_native_hint_row = null
	_native_hints_node = null


func _sync_native_hint(text: String) -> void:
	var row: HBoxContainer = _native_row()
	if row == null:
		if is_instance_valid(hud):
			if text.is_empty():
				hud.hide_prompt()
			else:
				hud.show_prompt(text, "", _act_key_label() if text == OFFER_HINT else "")
		return
	# The scan changes the hint at most once a second; the common frame has nothing to apply, so it
	# returns before the label checks and the container pokes.
	if text == _native_hint_text:
		if text.is_empty():
			return
		if is_instance_valid(_native_hint_label) and _native_hint_label.get_parent() == row:
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
	LOG.debug("OFFER blocked pony=%s reason=needs_stool gap=%s need=%d have=%d" % [
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
	LOG.debug("OFFER pony=%s pose=%s source=%s bed=%s pending=%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		_offer.pose, _offer.source, str(_offer.bed), str(_offer.pending)])


## The act key's one start entry. The act key is the hotkey: it always accepts, never bucks or
## refuses, and a missing context pose is no attempt. The tolerance stop owns the refusal path.
func try_start() -> bool:
	if is_instance_valid(active_runtime):
		return false
	_refresh_offer()
	if _offer == null:
		if _offer_blocked != null:
			return start_pose_offer(_offer_blocked)
		LOG.debug("hotkey no context pose")
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
	var id := PONY_ID.from(str(offer.pony.get_meta("relationship_id", "")),
		offer.pony.get("identity")) if is_instance_valid(offer.pony) else "?"
	if is_instance_valid(negotiation):
		var handle: Variant = negotiation.call("handle")
		if handle != null:
			var match: Variant = negotiation.call("hotkey_handle", runtime, _option_for(offer))
			if match != null:
				LOG.debug("hotkey exact match id=%s pose=%s" % [id, offer.pose])
				return _start_agreement_offer(offer, true)
			LOG.debug("hotkey interrupt agreement id=%s" % id)
			negotiation.call("interrupt_for_hotkey")
		elif bool(negotiation.call("is_locked")):
			LOG.debug("hotkey interrupt negotiation id=%s" % id)
			negotiation.call("interrupt_for_hotkey")
	LOG.debug("hotkey immediate id=%s pose=%s source=%s" % [id, offer.pose, offer.source])
	var started := bool(runtime.call("start_hotkey", offer.pose, offer.bed, offer.source))
	if not started:
		LOG.debug("hotkey start blocked id=%s pose=%s source=%s" % [id, offer.pose, offer.source])
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
	var id := PONY_ID.from(str(offer.pony.get_meta("relationship_id", "")),
		offer.pony.get("identity")) if is_instance_valid(offer.pony) else "?"
	LOG.debug("agreement start id=%s pose=%s skip_presentation=%s result=%d" % [
		id, offer.pose, str(skip_presentation), result])
	if result == RUNTIME.AGREEMENT_WAIT:
		LOG.debug("agreement start waiting pose=%s source=%s" % [offer.pose, offer.source])
		return false
	_clear_offer_hint()
	return result == RUNTIME.AGREEMENT_STARTED


## The Agreement's automatic start: it waits for the presentation to settle and Anon to be in
## position, then consumes the handle with no key press. A menu, a paused tree or a live act
## holds it. A private Agreement takes a fresh privacy sample; the exact hotkey match does not,
## because a live Agreement's own visibility wins for that press.
func _tick_agreement_auto_start(delta: float) -> void:
	if is_instance_valid(active_runtime) or not is_instance_valid(negotiation):
		return
	# The clock runs before the handle read so the common frame pays one arithmetic step: a
	# handle that appears between polls is consumed on the next one, 0.25 s later at most.
	_agreement_clock += delta
	if _agreement_clock < 0.25:
		return
	var handle: Variant = negotiation.call("handle")
	if handle == null:
		return
	_agreement_clock = 0.0
	if WORLD.menu_panel_open():
		return
	if DisplayServer.get_name() != "headless" and not WORLD.headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var pony: Variant = handle.pony
	var runtime: Node = runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("agreement_offer_ready"):
		return
	var offer := _agreement_offer(handle)
	if offer == null:
		return
	var option: Variant = _field(handle, "option")
	var cuddle := option != null and bool(_field(option, "cuddle", false))
	var pony_id := str(_field(handle, "pony_id", ""))
	if pony_id.is_empty() and is_instance_valid(pony):
		pony_id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	LOG.debug("agreement auto-start id=%s pose=%s" % [pony_id, offer.pose])
	if bool(handle.private) and not _agreement_private_now(pony, cuddle):
		LOG.debug("agreement auto-start privacy lost pony=%s" % str(pony.name))
		negotiation.call("cancel", handle, "privacy")
		return
	LOG.debug("agreement auto-start pony=%s pose=%s" % [str(pony.name), offer.pose])
	_start_agreement_offer(offer, false)


## A fresh privacy sample for the auto-start, with the offer's cuddle rule. A missing provider
## reads as public, so a private Agreement does not start on a stale answer.
func _agreement_private_now(pony: Node, cuddle: bool) -> bool:
	if not is_instance_valid(privacy):
		return false
	return privacy.cuddle_private(pony) if cuddle else privacy.offer_private(pony)


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


## The runtime's Agreement start result, forwarded to the Negotiation service.
func report_agreement(handle: Variant, started: bool) -> void:
	if is_instance_valid(negotiation):
		negotiation.call("report", handle, started)


## Clear the act-key hint and its cached offer.
func _clear_offer_hint() -> void:
	_offer = null
	if is_instance_valid(hud):
		hud.hide_prompt()


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
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime) and runtime.has_method("apply_live_settings"):
			runtime.call("apply_live_settings")
	if is_instance_valid(anatomy):
		anatomy.call("refresh_player")
		anatomy.call("refresh_all")
		anatomy.call("apply_live")
		anatomy.call("player_apply_live")


func allocate_serial() -> int:
	var section: Dictionary = Mods.state("unfplap")
	var value: int = int(section.get("serial", 0)) + 1
	section["serial"] = value
	Mods.save_changed()
	return value


func set_active(runtime: Node) -> void:
	active_runtime = runtime
	_offer = null
	if is_instance_valid(stock_smack):
		stock_smack.call("act_start", runtime.get("pony"))


func clear_active(runtime: Node) -> void:
	if active_runtime == runtime:
		active_runtime = null
		if is_instance_valid(stock_smack):
			stock_smack.call("act_end", runtime.get("pony"))


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


func _bedside_pony(_view: Camera3D) -> Node:
	# The player's bed/couch seat knows exactly who lies beside Anon.
	if is_instance_valid(WORLD.player):
		var seat: Variant = WORLD.player.get("seat")
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
	for node: Variant in WORLD.mares():
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
	var free := not is_instance_valid(active_runtime) and not bool(negotiation.call("is_locked"))
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
			"act" if is_instance_valid(active_runtime) else "locked"])


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
	var runtime: Variant = runtime_for(pony)
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
		var runtime: Variant = runtime_for(pony)
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
	var runtime: Variant = runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("start_agreement"):
		if is_instance_valid(negotiation):
			negotiation.call("cancel", handle, "cancelled")
		return
	# The presentation is act-owned: it starts now, and the auto-start waits for it to settle.
	if option != null and str(option.pose) == CATALOG.STANDING \
			and not bool(runtime.call("present_standing")):
		LOG.debug("agreement present failed pony=%s" % str(pony.name))
	_offer = null


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
	_pending_swap = {}
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
	if is_instance_valid(stock_smack):
		stock_smack.call("shutdown")
		stock_smack.queue_free()
		stock_smack = null
	_offer = null
	LOG.detach()
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
