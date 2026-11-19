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
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
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
const API := preload("res://mods/unfplap/api.gd")
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"

var hud: HUD
var input
## Cross-mod API facade; see docs/api.md.
var api: Node
## Anatomy system facade: per-pony controllers, the player part and tail seating.
var anatomy: Node
## Base body-change service: the per-body form store and the source/binding registries. Inert until
## `wire()` builds the bindings from the facades above and the providers register with it.
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
## The Act Negotiation service: the Anon offer, the Mare exchange, the Agreement, the lock, the
## director bridge and the Anon-offer watch. See `docs/negotiation.md`.
var negotiation: NEGOTIATION
## Internal eligibility service; see docs/eligibility.md. Never part of the cross-mod API.
var eligibility: ELIGIBILITY
## Internal memory service: act events, impressions, witnesses and the mod's own lines.
## See docs/memory.md. Never part of the cross-mod API.
var memory: MEMORY

## The idle act offer and its hint; see docs/offer.md.
var offer: OFFER
## Every Debug block button and wheel slot; see `docs/debug.md`.
var debug_actions: DEBUG_ACTIONS


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
	# The two debug switches arrive through the log sink's own settings listener: the entry binds
	# the reads once, and every later edit reaches `LOG.apply_settings()` through the notification.
	LOG.debug_read = Callable(SETTINGS.debug_mode, "get_bool")
	LOG.perf_read = Callable(SETTINGS.debug_perf, "get_bool")
	LOG.attach(self)
	LOG.act_running = Callable(PONIES, "act_running")
	LOG.counts = Callable(PONIES, "_counts")
	eligibility = ELIGIBILITY.new()
	eligibility.setup()
	memory = MEMORY.new()
	MEMORY.instance = memory
	privacy = PRIVACY.new()
	negotiation = NEGOTIATION.new()
	negotiation.name = "UnfplapNegotiation"
	add_child(negotiation)
	# The HUD exists before the player does: it owns the act card, the toast line, the caption
	# move and the one-time key notice, and it is the one sink the rest of the mod reaches
	# through `HUD.toast()`.
	hud = HUD.new()
	hud.name = "UnfplapHUD"
	hud.log = Callable(LOG, "debug")
	HUD.instance = hud
	add_child(hud)
	hud.apply_settings()
	# The idle offer is built before the Proactive service, which asks it which pony the act key
	# would start. Its entry reads are the runtime registry, the act-target rule and the live act.
	offer = OFFER.new()
	offer.name = "UnfplapOffer"
	offer.runtime_for = Callable(self, "runtime_for")
	offer.act_target = Callable(self, "_is_act_target")
	offer.act_live = Callable(self, "_act_live")
	offer.negotiation = negotiation
	offer.privacy = privacy
	offer.hud = hud
	offer.apply_settings()
	add_child(offer)
	# The act key and the seated-player guard exist before the player does; the offer above is
	# the one service the input policy hands its press to.
	input = INPUT.new()
	input.name = "UnfplapInput"
	input.offer = offer
	add_child(input)
	# The Proactive service owns the bounded classifier and takes the Negotiation facade: its
	# adapter, lock, form view and Context. The bridge reads this service back, so it is bound
	# once both exist.
	initiation = INITIATION.new()
	initiation.name = "UnfplapInitiation"
	initiation.eligibility = eligibility
	initiation.setup(privacy, negotiation, offer)
	add_child(initiation)
	negotiation.bind(eligibility, memory, privacy, initiation, offer)
	anatomy = ANATOMY.new()
	anatomy.name = "UnfplapAnatomy"
	anatomy.call("setup")
	add_child(anatomy)
	body_change = BODY_CHANGE_SERVICE.new()
	body_change.name = "UnfplapBodyChange"
	body_change.call("setup")
	add_child(body_change)
	PONIES.body_change = body_change
	pantyhose = PANTYHOSE.new()
	pantyhose.name = "UnfplapPantyhose"
	pantyhose.call("setup")
	add_child(pantyhose)
	stool = STOOL.new()
	stool.name = "UnfplapStool"
	stool.call("setup")
	STOOL.instance = stool
	add_child(stool)
	stock_smack = STOCK_SMACK.new()
	stock_smack.name = "UnfplapStockSmack"
	stock_smack.set("log", Callable(LOG, "debug"))
	add_child(stock_smack)
	body_change.call("wire", anatomy, pantyhose, stock_smack)
	api = API.new()
	api.name = "UnfplapAPI"
	add_child(api)
	PONIES.api = api
	changelings = CHANGELINGS.new()
	changelings.name = "UnfplapChangelings"
	changelings.call("setup")
	add_child(changelings)
	body_change.call("register_source", changelings)
	# The debug actions run against the services above, so they are built last. They read the live
	# act through the facades themselves; the entry hands them only the services they act through.
	debug_actions = DEBUG_ACTIONS.new()
	debug_actions.name = "UnfplapDebugActions"
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
	PONIES.factory = Callable(self, "_new_runtime")
	PONIES.bind_settings()
	PONIES.anatomy = anatomy
	PONIES.offer = offer
	PONIES.stock_smack = stock_smack
	PONIES.eligibility = eligibility
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	Mods.player_ready.connect(_on_player)
	Mods.on_node(PONY_PATH, _on_pony)
	Mods.on_node(SETTINGS_PAGE_PATH, _on_settings_page)
	# The HUD owns the caption path, the tracking and the move; the entry only registers the game
	# hook. See `docs/hud.md`.
	Mods.on_node(HUD.CAPTION_PATH, Callable(hud, "caption_node"))
	Mods.on_node(DEBUG_STRETCH.ENTRY_PATH, Callable(debug_actions, "on_idle_life"))
	# Switched on mid-game: the world and player already exist.
	if is_instance_valid(Mods.game):
		_on_world(Mods.game)
		var existing: Variant = Mods.game.get("player")
		if is_instance_valid(existing):
			_on_player(existing)


func _on_world(host: Node) -> void:
	debug_actions.close_debug_wheel()
	offer.on_world(host)
	WORLD.bind_world(host)
	if not is_instance_valid(eligibility):
		eligibility = ELIGIBILITY.new()
	eligibility.setup()
	PONIES.eligibility = eligibility
	initiation.eligibility = eligibility
	negotiation.eligibility = eligibility
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
		negotiation.on_world()
	if is_instance_valid(initiation):
		initiation.cancel_classifier()
	hud.on_world()


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
		negotiation.reset()
	if is_instance_valid(initiation):
		initiation.cancel_classifier()
	PONIES.close_world()
	if is_instance_valid(stock_smack):
		stock_smack.call("clear_world")
	WORLD.unbind()
	LOG.reset()
	LOG.clear_panel()
	if is_instance_valid(stool):
		stool.call("on_world_closed")
	hud.on_world_closed()


func _on_player(body: Node) -> void:
	WORLD.bind_player(body)
	LOG.debug("player ready")
	if is_instance_valid(anatomy):
		anatomy.call("player_ready", body)
	hud.on_player(body)


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
## settings.json; the settings UI owns the deferred injection and the sub-tabs. Every call it
## takes is a facade's, so the page never calls back into the entry.
func _on_settings_page(page: Node) -> void:
	SETTINGS_UI.inject(page, Callable(debug_actions, "build_settings_block"),
		Callable(PONIES, "live_character_ids"), Callable(SETTINGS, "profile_participation"),
		Callable(SETTINGS, "apply_live"), Callable(LOG, "debug"))


func _process(delta: float) -> void:
	var timed := LOG.tick(delta)
	var started := Time.get_ticks_usec() if timed else 0
	_process_entry(delta, timed)
	if timed:
		LOG.close("entry_process", started)


## The entry's per-frame body. `_process` above only times it for the idle probe; the call order
## here is load-bearing.
func _process_entry(delta: float, timed: bool) -> void:
	# The caption move is an act-only path the HUD owns: the entry only reports the live state,
	# and the HUD's process priority keeps the move after the caption's own _process.
	var active: Node = PONIES.active()
	hud.caption_tick(int(active.get("state")) if is_instance_valid(active) else RUNTIME.State.IDLE)
	if not is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game):
		var body: Variant = WORLD.game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active):
		var camera_started := Time.get_ticks_usec()
		active.call("apply_camera_motion")
		active.call("perf_note", "camera_motion", Time.get_ticks_usec() - camera_started)
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


## The act-target capability. `ponies` holds the live registry and the eligibility service that
## owns the rule; the offer takes this read as its callable.
func _is_act_target(pony: Variant) -> bool:
	return pony is Node and PONIES.act_target(pony)


## The offer's act-live read: a live act owns the frame, so the act key starts nothing and no
## Agreement auto-starts.
func _act_live() -> bool:
	return PONIES.act_running()


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
		initiation.cancel_classifier()
		initiation.queue_free()
	# The adapter is the negotiation's child; it goes with it.
	if is_instance_valid(negotiation):
		negotiation.reset()
		negotiation.queue_free()
	negotiation = null
	privacy = null
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
	HUD.instance = null
	MEMORY.instance = null
	STOOL.instance = null
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
