extends Node
## unfplap mod entry: the primitives, the ordered service list, the frame order and one teardown.
##
## `_ready()` loads the settings, attaches the log sink and builds every long-running service in
## the one list `_build_services()` writes. The list order is the call order of every broadcast:
##
## - `_on_world(host)`: `WORLD.bind_world`, every `on_world(host)` in list order, then the two
##   static facades that are not list members (`PONIES.reset()`, `LOG.reset()`);
## - `_on_player(body)`: `WORLD.bind_player`, every `on_player(body)` in list order;
## - `_on_world_closed()`: the "world closed" line, then `_release()`;
## - `_exit_tree()`: `_release()`, the registry shutdown, every `shutdown()` in reverse list order.
##
## `_release()` is the one release sequence: every service's `on_world_closed()`, then
## `WORLD.unbind()`, then the log window. A world close and the process exit both run it, so a
## service cannot be released in one path and forgotten in the other. `WORLD` stays outside the
## loop because it is the scene read every service makes: bound before the first service and
## unbound after the last.
##
## A service takes part in a broadcast by naming the hook (`on_world(host)`, `on_world_closed()`,
## `on_player(body)`, `shutdown()`); a hook it does not implement is skipped.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const INPUT := preload("res://mods/unfplap/input/service.gd")
const INITIATION := preload("res://mods/unfplap/initiation/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const BUILD_STAMP := preload("res://mods/unfplap/shared/build_stamp.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/actions.gd")
const DEBUG_STRETCH := preload("res://mods/unfplap/debug/idle_stretch.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const PANTYHOSE := preload("res://mods/unfplap/integrations/pantyhose.gd")
const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const STOCK_SMACK := preload("res://mods/unfplap/audio/stock_smack.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings/ui.gd")
const API := preload("res://mods/unfplap/api.gd")
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"

## The long-running services in construction order. The list is the lifecycle: `_on_world`,
## `_on_player`, `_release` and `_shutdown` walk it, so a service joins a broadcast by being here.
var _services: Array = []

var hud: HUD
var input: INPUT
## Cross-mod API facade; see docs/api.md.
var api: API
## Anatomy system facade: per-pony controllers, the player part and tail seating.
var anatomy: ANATOMY
## Base body-change service: the per-body form store and the source/binding registries. Inert until
## `wire()` builds the bindings from the facades above and the providers register with it.
var body_change: BODY_CHANGE_SERVICE
## The Pantyhose & Panties world adapter; inert when that pack is absent.
var pantyhose: PANTYHOSE
## The changelings world adapter; inert when that pack is absent.
var changelings: CHANGELINGS
## Footstool system facade: the standing reach rule, item, act prop and world supply.
var stool: STOOL
## Outside-act stock smack sound layer; see `docs/audio.md`.
var stock_smack: STOCK_SMACK
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
	# The loader owns this node; the lookup rather than the autoload name keeps the entry loadable
	# by a suite, the way `runtime.gd` and `api.gd` reach the same node.
	var mods: Variant = get_node_or_null("/root/Mods")
	if mods == null:
		push_error("unfplap: the Mods autoload is missing; the mod is not loading")
		set_process(false)
		return
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
	LOG.runtime_count = Callable(PONIES, "runtime_count")
	LOG.mare_count = Callable(PONIES, "mare_count")
	_build_services()
	# The per-pony registry binds the services above once and builds its runtimes through the
	# one factory, so no other entry member holds a runtime.
	PONIES.factory = Callable(self, "_new_runtime")
	PONIES.bind_settings()
	# Proves which build is live: a real source file has a non-zero mtime; a pack/PCK reports 0.
	BUILD_STAMP.log_stamp()
	mods.world_ready.connect(_on_world)
	mods.world_closed.connect(_on_world_closed)
	mods.player_ready.connect(_on_player)
	mods.on_node(PONY_PATH, _on_pony)
	mods.on_node(SETTINGS_PAGE_PATH, _on_settings_page)
	# The HUD owns the caption path, the tracking and the move; the entry only registers the game
	# hook. See `docs/hud.md`.
	mods.on_node(HUD.CAPTION_PATH, Callable(hud, "caption_node"))
	mods.on_node(DEBUG_STRETCH.ENTRY_PATH, Callable(debug_actions, "on_idle_life"))
	# Switched on mid-game: the world and player already exist.
	if is_instance_valid(mods.game):
		_on_world(mods.game)
		var existing: Variant = WORLD.game_player()
		if is_instance_valid(existing):
			_on_player(existing)


## The one ordered service list: each line constructs its service and joins it to the tree and to
## `_services`; its `bind()` hands it the facades it reads. The order is load-bearing: a consumer is
## built after the services it reads, and the static `PONIES` registry binds last.
func _build_services() -> void:
	eligibility = _add(ELIGIBILITY.new())
	memory = _add(MEMORY.new())
	MEMORY.instance = memory
	privacy = _add(PRIVACY.new())
	negotiation = _add(NEGOTIATION.new(), "UnfplapNegotiation")
	# The HUD exists before the player does: it owns the act card, the toast line, the caption
	# move and the one-time key notice, and it is the one sink the rest of the mod reaches
	# through `HUD.toast()`.
	hud = _add(HUD.new(), "UnfplapHUD")
	hud.bind(Callable(LOG, "debug"))
	HUD.instance = hud
	hud.apply_settings()
	offer = _add(OFFER.new(), "UnfplapOffer")
	offer.bind(negotiation, privacy, hud)
	offer.apply_settings()
	# The act key and the seated-player guard exist before the player does; the offer above is
	# the one service the input policy hands its press to.
	input = _add(INPUT.new(), "UnfplapInput")
	input.bind(offer)
	# The Proactive service owns the bounded classifier and takes the Negotiation facade: its
	# adapter, lock, form view and Context. The bridge reads this service back, so it is bound
	# once both exist.
	initiation = _add(INITIATION.new(), "UnfplapInitiation")
	initiation.bind(eligibility)
	initiation.setup(privacy, negotiation, offer)
	negotiation.bind(eligibility, memory, privacy, initiation, offer)
	anatomy = _add(ANATOMY.new(), "UnfplapAnatomy")
	anatomy.setup()
	body_change = _add(BODY_CHANGE_SERVICE.new(), "UnfplapBodyChange")
	body_change.setup()
	pantyhose = _add(PANTYHOSE.new(), "UnfplapPantyhose")
	pantyhose.setup()
	stool = _add(STOOL.new(), "UnfplapStool")
	stool.setup()
	STOOL.instance = stool
	stock_smack = _add(STOCK_SMACK.new(), "UnfplapStockSmack")
	stock_smack.log = Callable(LOG, "debug")
	body_change.wire(anatomy, pantyhose, stock_smack)
	changelings = _add(CHANGELINGS.new(), "UnfplapChangelings")
	changelings.setup()
	body_change.register_source(changelings)
	api = _add(API.new(), "UnfplapAPI")
	# The debug actions run against the services above, so they are built last. They read the live
	# act through the facades themselves; the entry hands them only the services they act through.
	debug_actions = _add(DEBUG_ACTIONS.new(), "UnfplapDebugActions")
	debug_actions.bind(body_change, initiation, negotiation, anatomy, pantyhose)
	debug_actions.sync_skeleton_overlay()
	PONIES.bind(anatomy, body_change, offer, stock_smack, eligibility, api)


## Join one service to the tree and to the ordered list. A RefCounted service only joins the list:
## it has no node, no name and no teardown beyond its references.
func _add(service: Variant, node_name := "") -> Variant:
	_services.append(service)
	if not service is Node:
		return service
	service.name = node_name
	add_child(service)
	return service


func _on_world(host: Node) -> void:
	WORLD.bind_world(host)
	for service: Variant in _services:
		if is_instance_valid(service) and service.has_method("on_world"):
			service.on_world(host)
	# The two static facades are not list members: the registry drops the swap of the world that is
	# gone and the log opens a fresh probe window.
	PONIES.reset()
	LOG.reset()


func _on_world_closed(_host: Node) -> void:
	LOG.debug("world closed")
	_release()


## The one release sequence, shared by the world close and the process exit.
func _release() -> void:
	for service: Variant in _services:
		if is_instance_valid(service) and service.has_method("on_world_closed"):
			service.on_world_closed()
	WORLD.unbind()
	LOG.reset()
	LOG.clear_panel()


func _on_player(body: Node) -> void:
	WORLD.bind_player(body)
	LOG.debug("player ready")
	for service: Variant in _services:
		if is_instance_valid(service) and service.has_method("on_player"):
			service.on_player(body)


## Every body the game spawns arrives here. `ponies` owns the registry, the prepare hooks
## and the pending-swap adoption; the factory below is the entry's only runtime
## construction.
func _on_pony(pony: Node) -> void:
	PONIES.attach(pony)


## The entry's one runtime construction: `ponies` calls it once per attached body. The
## runtime file is the entry's preload, so the registry never imports it.
func _new_runtime(pony: Node) -> Node:
	var runtime: RUNTIME = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.pony = pony
	return runtime


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
	var active: RUNTIME = PONIES.active() as RUNTIME
	hud.caption_tick(active.act.state if is_instance_valid(active) else ACT_STATE.State.IDLE)
	if not is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game):
		var body: Variant = WORLD.game_player()
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active):
		var camera_started := Time.get_ticks_usec()
		active.act.apply_camera_motion()
		active.act.host.perf_note("camera_motion", Time.get_ticks_usec() - camera_started)
		var hud_started := Time.get_ticks_usec()
		hud.update_from(active.act.facts())
		active.act.host.perf_note("hud", Time.get_ticks_usec() - hud_started)
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


func _exit_tree() -> void:
	_release()
	_shutdown()


## The process-only release: the registry goes first, so every runtime is stopped and freed while
## the services it reads are still alive; then each service's `shutdown()` runs in reverse list
## order and the nodes leave the tree.
func _shutdown() -> void:
	PONIES.shutdown()
	for index: int in range(_services.size() - 1, -1, -1):
		var service: Variant = _services[index]
		if not is_instance_valid(service):
			continue
		if service.has_method("shutdown"):
			service.shutdown()
		if service is Node:
			service.queue_free()
	_services.clear()
	SETTINGS_UI.clear_pages()
	LOG.detach()
	MEMORY.instance = null
	HUD.instance = null
	STOOL.instance = null
