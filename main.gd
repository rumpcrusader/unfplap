extends Node
## unfplap mod entry: the ordered service list, the entry frame and the one release.
##
## A service joins a broadcast by being in the list and naming the hook; the world close and the
## process exit run the same release, so a service cannot be released on one path and forgotten.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SERVICE := preload("res://mods/unfplap/shared/service.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const INPUT := preload("res://mods/unfplap/input/service.gd")
const INITIATION := preload("res://mods/unfplap/initiation/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const BUILD_STAMP := preload("res://mods/unfplap/shared/build_stamp.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/actions.gd")
const DEBUG_STRETCH := preload("res://mods/unfplap/debug/idle_stretch.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ESTRUS := preload("res://mods/unfplap/estrus/service.gd")
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

## The four lifecycle hooks a list service carries; the boot check validates each one.
const HOOKS: Array[String] = ["on_world", "on_world_closed", "on_player", "shutdown"]

## The long-running services in construction order: every broadcast walks the list, so a service
## joins a broadcast by being here.
var _services: Array[Node] = []

var hud: HUD
var input: INPUT
## Cross-mod API facade; see docs/api.md.
var api: API
## Anatomy system facade: one controller per pony, the player part and its tail seat.
var anatomy: ANATOMY
## The optional estrus cycle: phase, schedule and the idle wink/rest pushes.
var estrus: ESTRUS
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
## The dynamic act gate: relationship, romance, cycle, history and consent. See docs/act_gate.md.
var act_gate: ACT_GATE
## Internal memory service: act events, impressions, witnesses and the mod's own lines.
## See docs/memory.md. Never part of the cross-mod API.
var memory: MEMORY

## The idle act offer and its hint; see docs/offer.md.
var offer: OFFER
## Every Debug block button and wheel slot; see `docs/debug.md`.
var debug_actions: DEBUG_ACTIONS


## Live act/afterglow context for the game's normal dialogue prompt; the game calls a Node in the
## group, so the entry joins it and forwards to the RefCounted facade that owns the note.
func prompt_note(pony: String) -> String:
	return PONIES.prompt_note(pony)


func _ready() -> void:
	process_priority = 100
	set_process(true)
	# The loader owns this node; the lookup rather than the autoload name keeps the entry loadable
	# by a suite, the way `runtime.gd` and `api.gd` reach the same node.
	var mods: Variant = get_node_or_null("/root/Mods")
	if mods == null:
		LOG.error("the Mods autoload is missing; the mod is not loading")
		set_process(false)
		return
	# Load, migrate, merge and write the player file before any getter runs: the hot read path
	# must never touch the disk. A broken shipped document is a build error, so log it once and
	# install no hooks; the settings module already named the first offending path.
	if not SETTINGS.load_settings():
		LOG.error("shipped settings data is invalid; the mod is not loading")
		set_process(false)
		return
	add_to_group("pony_prompt_notes")
	# The two debug switches: each module binds its own read and keeps its gate in step.
	LOG.bind(Callable(SETTINGS.debug_mode, "get_bool"))
	PERF.bind(Callable(SETTINGS.debug_perf, "get_bool"), self)
	_build_services()
	# The per-pony registry binds the services above once and builds its runtimes through the
	# one factory, so no other entry member holds a runtime.
	PONIES.factory = Callable(self, "_new_runtime")
	PONIES.bind_settings()
	# A source run carries a non-zero mtime and a pack 0, which the one log line records.
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


## The one ordered service list: each line constructs its service, joins it to the tree and binds
## the facades it reads.
func _build_services() -> void:
	eligibility = _add(ELIGIBILITY.new())
	# The API can be discovered before the end of the build; `describe_mare` reads this service.
	PONIES.eligibility = eligibility
	# The dynamic gate asks the identity question and owns every "right now" row.
	act_gate = _add(ACT_GATE.new())
	act_gate.bind_eligibility(eligibility)
	PONIES.act_gate = act_gate
	memory = _add(MEMORY.new())
	privacy = _add(PRIVACY.new())
	negotiation = _add(NEGOTIATION.new(), "UnfplapNegotiation")
	# The HUD exists before the player does: it owns the act card, the toast line, the caption
	# move and the one-time key notice, and it is the one sink the rest of the mod reaches
	# through the instance the entry passes to each caller.
	hud = _add_hud(HUD.new(), "UnfplapHUD")
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
	initiation.bind(eligibility, act_gate)
	initiation.setup(privacy, negotiation, offer)
	negotiation.bind(eligibility, act_gate, memory, privacy, initiation, offer, hud)
	estrus = _add(ESTRUS.new(), "UnfplapEstrus")
	anatomy = _add(ANATOMY.new(), "UnfplapAnatomy")
	anatomy.status.connect(Callable(hud, "anatomy_status"))
	anatomy.bind_eligibility(eligibility)
	estrus.bind(anatomy)
	body_change = _add(BODY_CHANGE_SERVICE.new(), "UnfplapBodyChange")
	body_change.setup()
	pantyhose = _add(PANTYHOSE.new(), "UnfplapPantyhose")
	pantyhose.setup()
	stool = _add(STOOL.new(), "UnfplapStool")
	stool.setup()
	stock_smack = _add(STOCK_SMACK.new(), "UnfplapStockSmack")
	body_change.wire(anatomy, pantyhose, stock_smack)
	changelings = _add(CHANGELINGS.new(), "UnfplapChangelings")
	changelings.setup()
	body_change.register_source(changelings)
	api = _add_node(API.new(), "UnfplapAPI")
	# The debug actions run against the services above, so they are built last. They read the live
	# act through the facades themselves; the entry hands them only the services they act through.
	debug_actions = _add(DEBUG_ACTIONS.new(), "UnfplapDebugActions")
	debug_actions.bind(body_change, initiation, negotiation, anatomy, pantyhose, hud)
	debug_actions.sync_skeleton_overlay()
	PONIES.bind(anatomy, body_change, offer, stock_smack, eligibility, act_gate, estrus, api)
	_assert_hooks()


## Join one service to the tree and to the ordered list. Every list member is a base service.
func _add(service: SERVICE, node_name := "") -> Variant:
	_services.append(service)
	if not node_name.is_empty():
		service.name = node_name
	add_child(service)
	return service


## The HUD is the one `CanvasLayer` in the list; it carries the four hooks itself.
func _add_hud(service: HUD, node_name: String) -> HUD:
	_services.append(service)
	service.name = node_name
	add_child(service)
	return service


## The cross-mod API is frozen and carries no lifecycle hooks: parent it, keep it out of the list.
func _add_node(service: Node, node_name: String) -> Variant:
	service.name = node_name
	add_child(service)
	return service


## Log one error per list service that is missing a lifecycle hook; returns the offender count.
func _assert_hooks() -> int:
	var missing := 0
	for service: Node in _services:
		var bad := false
		for hook: String in HOOKS:
			if not service.has_method(hook):
				LOG.error("service %s is missing %s()", [str(service.name), hook])
				bad = true
		if bad:
			missing += 1
	return missing


func _on_world(host: Node) -> void:
	WORLD.bind_world(host)
	for service: Node in _services:
		if is_instance_valid(service):
			service.on_world(host)
	# The registry is not a list member: it drops the swap of the world that is gone. The world
	# binds before the first service and unbinds after the last, because every service reads it.
	PONIES.reset()


func _on_world_closed(_host: Node) -> void:
	LOG.debug("world closed")
	_release()


## The one release sequence, shared by the world close and the process exit.
func _release() -> void:
	for service: Node in _services:
		if is_instance_valid(service):
			service.on_world_closed()
	WORLD.unbind()


func _on_player(body: Node) -> void:
	WORLD.bind_player(body)
	LOG.debug("player ready")
	for service: Node in _services:
		if is_instance_valid(service):
			service.on_player(body)


## Every body the game spawns arrives here; the registry owns the prepare hooks and the
## pending-swap adoption, and the factory below is the entry's only runtime construction.
func _on_pony(pony: Node) -> void:
	PONIES.attach(pony)


## The entry's one runtime construction, called once per attached body. The runtime file is the
## entry's preload, so the registry never imports it.
func _new_runtime(pony: Node) -> Node:
	var runtime: RUNTIME = RUNTIME.new(hud, memory, stool)
	runtime.name = "UnfplapRuntime"
	runtime.pony = pony
	if is_instance_valid(pantyhose):
		runtime.act_started.connect(Callable(pantyhose, "act_started"))
	return runtime


## The settings page hook: no game-script extension is used, the settings UI owns the deferred
## injection. Every callable it takes is a facade's, so the page never calls back into the entry.
func _on_settings_page(page: Node) -> void:
	SETTINGS_UI.inject(page, Callable(debug_actions, "build_settings_block"),
		Callable(PONIES, "live_character_ids"), Callable(SETTINGS, "profile_participation"),
		Callable(SETTINGS, "apply_live"), Callable(LOG, "debug"))


func _process(delta: float) -> void:
	PERF.start_frame()
	_process_entry(delta)
	PERF.end_frame()


## The entry's per-frame body. `_process` above only brackets it for the profiler; the call order
## here is load-bearing.
func _process_entry(delta: float) -> void:
	# The caption move is an act-only path the HUD owns: the entry only reports the live state,
	# and the HUD's process priority keeps the move after the caption's own _process.
	var active: RUNTIME = PONIES.active() as RUNTIME
	hud.caption_tick(active.act.state if is_instance_valid(active) else ACT_STATE.State.IDLE)
	if not is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game):
		var body: Variant = WORLD.game_player()
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active):
		PERF.begin("camera_motion")
		active.act.apply_camera_motion()
		PERF.end("camera_motion")
		PERF.begin("hud")
		hud.update_from(active.act.facts())
		PERF.end("hud")
		offer.hide_hint()
		return

	offer.tick(delta)
	if is_instance_valid(initiation):
		PERF.begin("entry_initiation")
		initiation.tick(delta)
		PERF.end("entry_initiation")
	if is_instance_valid(negotiation):
		PERF.begin("entry_negotiation")
		negotiation.tick(delta)
		PERF.end("entry_negotiation")


func _exit_tree() -> void:
	_release()
	_shutdown()


## The process-only release: the registry goes first, so every runtime is stopped and freed while
## the services it reads are alive; then the service shutdown runs in reverse list order.
func _shutdown() -> void:
	PONIES.shutdown()
	for index: int in range(_services.size() - 1, -1, -1):
		var service: Node = _services[index]
		if not is_instance_valid(service):
			continue
		service.shutdown()
		service.queue_free()
	_services.clear()
	SETTINGS_UI.clear_pages()
