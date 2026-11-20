extends "res://mods/unfplap/tests/support/suite.gd"
## The offer service's act start: the act key's one press, the hotkey attempt and its Agreement
## exact match, the blocked and empty toasts, the live Agreement start's wait/start/fail answers
## and the Agreement auto-start clock with its act, menu and privacy guards.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/offer/test_start.gd

const OFFER := preload("res://mods/unfplap/offer/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")



class FakePony extends Node3D:
	var requested := "stand"
	var identity := {"filly": false, "stallion": false}

	func _init() -> void:
		set_meta("relationship_id", "rarity")

	func posture_status() -> Dictionary:
		return {"requested": requested}


class FakeRuntime extends Node:
	var gate_ready := true
	var stool := {"need": 0, "have": 0}
	var hotkey_starts := 0
	var hotkey_result := true
	var agreement_result := 0
	var agreement_handles: Array = []
	var agreement_skips: Array = []
	var gate: Variant = null

	func _init() -> void:
		gate = self

	func available() -> bool:
		return gate_ready

	func pose_supported(_pose: String, _source: String) -> bool:
		return true

	func player_ready(_pose: String, _source: String, _bed: Variant) -> bool:
		return true

	func navigator_allows(_pose: String, _source: String) -> bool:
		return true

	func posture_allows(_pose: String) -> bool:
		return true

	func hotkey_ready(_pose: String, _source: String, _bed: Variant,
			_pair := Vector2i(-1, -1)) -> bool:
		return gate_ready

	func stool_pair(_pose: String) -> Vector2i:
		return Vector2i(int(stool.get("need", 0)), int(stool.get("have", 0)))

	func hint_stool() -> Dictionary:
		return stool

	func stool_gap_m() -> Variant:
		return 0.0

	func stool_case_count() -> int:
		return int(stool.get("have", 0))

	func start_hotkey(_pose: String, _bed: Variant, _source: String) -> bool:
		hotkey_starts += 1
		return hotkey_result

	func start_agreement(handle: Variant, skip_presentation := false) -> int:
		agreement_handles.append(handle)
		agreement_skips.append(skip_presentation)
		return agreement_result


class FakeNegotiation extends NEGOTIATION:
	var live: NEGOTIATION.AGREEMENT.Handle = null
	var match: NEGOTIATION.AGREEMENT.Handle = null
	var locked := false
	var is_ready := true
	var interrupts := 0
	var reports: Array = []
	var cancels: Array = []

	func handle() -> NEGOTIATION.AGREEMENT.Handle:
		return live

	func ready_offer() -> bool:
		return is_ready and live != null

	func hotkey_handle(_runtime: Node, _option: POSE_OPTIONS.Option) -> NEGOTIATION.AGREEMENT.Handle:
		return match

	func interrupt_for_hotkey() -> bool:
		interrupts += 1
		return true

	func is_locked() -> bool:
		return locked

	func report(handle: NEGOTIATION.AGREEMENT.Handle, started: bool) -> bool:
		reports.append([handle, started])
		return true

	func cancel(handle: NEGOTIATION.AGREEMENT.Handle, reason: String) -> bool:
		cancels.append([handle, reason])
		live = null
		return true


class FakeHud extends Node:
	var toasts: Array[String] = []
	var prompts: Array[String] = []
	var hides := 0

	func _show_toast(text: String, _seconds := 2.0) -> void:
		toasts.append(text)

	func show_prompt(text: String, _icon_name := "", _cap := "") -> void:
		prompts.append(text)

	func hide_prompt() -> void:
		hides += 1


class FakePrivacy extends PRIVACY:
	var private := true
	var offer_samples := 0
	var cuddle_samples := 0

	func setup() -> void:
		pass

	func offer_private(_target: Node) -> bool:
		offer_samples += 1
		return private

	func cuddle_private(_target: Node) -> bool:
		cuddle_samples += 1
		return private


## The act-target rule: the ponies this fixture allows.
class Targets extends ELIGIBILITY:
	var allowed: Array = []

	func eligible(pony: Node, _target: Target = Target.ACT) -> bool:
		return allowed.has(pony)

	func relationship_ok(_pony: Node) -> bool:
		return true


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false
	var save_menu: Variant = null


class FakeMenu extends Node:
	var opened := false


class FakePlayer extends Node3D:
	var seat: Variant = null
	var camera: Variant = null


func run() -> void:
	SETTINGS.load_settings()
	check_answers()
	check_act_key()
	check_blocked()
	check_start_outcomes()
	check_auto_start()
	if failures == 0:
		print("OFFER_START_PASS")
	finish()


## The offer restates the runtime's Agreement answer, because a service never preloads the
## runtime; the check that the two agree is here.
func check_answers() -> void:
	check(OFFER.AGREEMENT_WAIT == ACT_AGREEMENT.AGREEMENT_WAIT,
		"the offer's wait answer is the runtime's")
	check(OFFER.AGREEMENT_STARTED == ACT_AGREEMENT.AGREEMENT_STARTED,
		"the offer's started answer is the runtime's")
	check(OFFER.AGREEMENT_WAIT != OFFER.AGREEMENT_STARTED
		and ACT_AGREEMENT.AGREEMENT_FAILED != OFFER.AGREEMENT_STARTED,
		"the answers are distinct")


## The act key's one entry: a live act takes the press, a scanned standing offer starts through
## the scene-only hotkey path, and an empty scene says there is nothing to start.
func check_act_key() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var hud: FakeHud = made["hud"]
	PONIES.set_active(runtime)
	check(not service.try_start(), "a live act takes the act key")
	check(runtime.hotkey_starts == 0, "a live act starts nothing")
	check(service.current() == null, "the act key does not scan while an act is live")
	PONIES.clear_active(runtime)
	check(service.try_start(), "the act key starts the scanned offer")
	check(runtime.hotkey_starts == 1, "the press runs the one hotkey attempt")
	check(hud.hides > 0, "a started press clears the hint")
	check(service.current() == null, "the started offer is dropped")
	_free(made)

	var empty := _fixture(false)
	var idle: OFFER = empty["service"]
	var quiet: FakeHud = empty["hud"]
	check(not idle.try_start(), "an empty scene starts nothing")
	check(quiet.toasts == ["There is nothing to start here."],
		"an empty scene says there is nothing to start")
	_free(empty)


## A standing gate that wants a footstool blocks the press: the hint names the need, the idle
## frame toasts once and the press shows the recorded toast again, and nothing starts.
func check_blocked() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var hud: FakeHud = made["hud"]
	runtime.stool = {"need": 1, "have": 0}
	service.tick(0.2)
	check(service.current() == null, "a blocked gate offers nothing to start")
	check(service.blocked() != null, "the blocked gate records an offer")
	check(hud.toasts == ["Find a footstool in a house."], "the block toasts once")
	check(not service.try_start(), "the act key starts nothing on a blocked gate")
	check(runtime.hotkey_starts == 0, "a blocked press runs no attempt")
	check(hud.toasts.size() == 2, "the blocked press shows the recorded toast")
	_free(made)


## The one typed start path: blocked, hotkey, Agreement wait/start/fail, exact match, interrupts
## and the invalid handle.
func check_start_outcomes() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var pony: FakePony = made["pony"]
	var hud: FakeHud = made["hud"]
	var negotiation: FakeNegotiation = made["negotiation"]

	# A blocked offer shows its toast and starts nothing.
	var blocked := _handle(runtime, pony)
	blocked.blocked = {"hint": "Needs a footstool", "need": 1,
		"toast": "Find a footstool in a house."}
	hud.toasts.clear()
	check(not service.start_pose_offer(blocked), "a blocked offer does not start")
	check(runtime.hotkey_starts == 0 and runtime.agreement_handles.is_empty(),
		"a blocked offer starts neither path")
	check(hud.toasts == ["Find a footstool in a house."],
		"a blocked offer shows the recorded toast once")

	# The hotkey: the scene-only attempt, the hint cleared only when it starts.
	var hotkey := _handle(runtime, pony)
	runtime.hotkey_result = true
	var hides := hud.hides
	check(service.start_pose_offer(hotkey), "the hotkey starts an immediate attempt")
	check(runtime.hotkey_starts == 1, "the hotkey uses the scene-only path")
	check(hud.hides == hides + 1, "a started hotkey clears the hint")
	runtime.hotkey_result = false
	hides = hud.hides
	check(not service.start_pose_offer(hotkey), "a blocked hotkey starts nothing")
	check(hud.hides == hides, "a blocked hotkey keeps the hint")
	runtime.hotkey_result = true

	# A live Agreement is consumed through the scene-only start: WAIT keeps the hint and the
	# Agreement, STARTED and FAILED clear it and hand the result to the Negotiation service.
	negotiation.live = _agreement(pony)
	var agreement := _handle(runtime, pony)
	agreement.trigger = "agreement"
	runtime.agreement_result = OFFER.AGREEMENT_WAIT
	hides = hud.hides
	check(not service.start_pose_offer(agreement), "a waiting Agreement does not start")
	check(hud.hides == hides, "a waiting Agreement keeps the hint")
	check(runtime.agreement_handles.size() == 1, "the Agreement handle reaches the runtime")
	check(negotiation.reports.is_empty(), "a waiting Agreement reports nothing")
	runtime.agreement_result = OFFER.AGREEMENT_STARTED
	hides = hud.hides
	check(service.start_pose_offer(agreement),
		"a ready Agreement starts through the scene-only path")
	check(hud.hides == hides + 1, "a started Agreement clears the hint")
	check(negotiation.reports.size() == 1 and bool(negotiation.reports[0][1]),
		"the started Agreement is reported")
	runtime.agreement_result = ACT_AGREEMENT.AGREEMENT_FAILED
	check(not service.start_pose_offer(agreement), "a failed Agreement starts nothing")
	check(negotiation.reports.size() == 2 and not bool(negotiation.reports[1][1]),
		"the failed Agreement is reported")
	negotiation.live = null
	hides = hud.hides
	check(not service.start_pose_offer(agreement), "a missing Agreement handle starts nothing")
	check(hud.hides == hides + 1, "a missing Agreement still clears the hint")

	# A live Agreement's exact match skips the presentation and consumes the handle.
	negotiation.live = _agreement(pony)
	negotiation.match = negotiation.live
	var matching := _handle(runtime, pony)
	runtime.agreement_result = OFFER.AGREEMENT_STARTED
	var hotkey_before := runtime.hotkey_starts
	check(service.start_pose_offer(matching), "a matching Agreement starts from the hotkey")
	check(runtime.hotkey_starts == hotkey_before,
		"a matching Agreement is not a hotkey attempt")
	check(bool(runtime.agreement_skips[runtime.agreement_skips.size() - 1]),
		"the exact match skips the presentation turn")
	negotiation.live = null
	negotiation.match = null

	# A live negotiation without an Agreement is interrupted before the attempt.
	negotiation.locked = true
	check(service.start_pose_offer(hotkey), "the hotkey runs after a negotiation")
	check(negotiation.interrupts == 1, "an active negotiation is interrupted")
	negotiation.locked = false

	# A live Agreement with a different option is interrupted; the attempt still runs.
	negotiation.live = _agreement(pony)
	check(service.start_pose_offer(hotkey), "a different Agreement is interrupted")
	check(negotiation.interrupts == 2, "the different Agreement is interrupted")
	negotiation.live = null

	# An invalid handle is a no-op.
	hotkey_before = runtime.hotkey_starts
	check(not service.start_pose_offer(POSE_OFFER.new()), "an invalid offer starts nothing")
	check(runtime.hotkey_starts == hotkey_before, "an invalid offer runs no attempt")
	_free(made)


## The Agreement auto-start: its 0.25 s clock, the live-act and menu guards, the scene readiness,
## the fresh private sample with the cuddle rule, and the wait that keeps the Agreement.
func check_auto_start() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var pony: FakePony = made["pony"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var privacy: FakePrivacy = made["privacy"]
	var game: FakeGame = made["game"]
	var menu: FakeMenu = made["menu"]

	# The clock waits for the cadence, and a live act does not advance it.
	service.tick(OFFER.AGREEMENT_START_S * 0.5)
	check(runtime.agreement_handles.is_empty(), "the clock waits for the cadence")
	PONIES.set_active(runtime)
	service.tick(1.0)
	PONIES.clear_active(runtime)
	check(runtime.agreement_handles.is_empty(), "a live act holds the auto-start")
	check(float(service.get("_agreement_clock")) < OFFER.AGREEMENT_START_S,
		"a live act does not advance the clock")

	# A live private Agreement whose fresh sample is public is cancelled, not started.
	negotiation.live = _agreement(pony, CATALOG.MISSIONARY, false, true)
	privacy.private = false
	service.tick(OFFER.AGREEMENT_START_S)
	check(negotiation.cancels.size() == 1 and str(negotiation.cancels[0][1]) == "privacy",
		"a private auto-start cancels when the fresh sample is public")
	check(runtime.agreement_handles.is_empty(), "a cancelled private auto-start starts no act")
	check(privacy.offer_samples == 1, "the private sample reads the offer rule")

	# The menu panel holds the start.
	negotiation.live = _agreement(pony)
	privacy.private = true
	menu.opened = true
	service.tick(OFFER.AGREEMENT_START_S)
	check(runtime.agreement_handles.is_empty(), "an open menu holds the auto-start")
	check(game.save_menu == menu, "the menu is the scene's own panel")
	menu.opened = false

	# A public Agreement takes no privacy sample and starts.
	runtime.agreement_result = OFFER.AGREEMENT_STARTED
	service.tick(OFFER.AGREEMENT_START_S)
	check(runtime.agreement_handles.size() == 1,
		"a public Agreement auto-starts without a privacy sample")
	check(privacy.offer_samples == 1, "the public auto-start does not sample")
	check(negotiation.reports.size() == 1 and bool(negotiation.reports[0][1]),
		"the auto-started Agreement is reported")

	# A cuddle Agreement takes the stricter cuddle sample.
	negotiation.live = _agreement(pony, CATALOG.MISSIONARY, true, true)
	service.tick(OFFER.AGREEMENT_START_S)
	check(privacy.cuddle_samples == 1, "a cuddle auto-start reads the cuddle rule")
	check(runtime.agreement_handles.size() == 2, "the cuddle Agreement starts")

	# A wait keeps the Agreement live and restarts the clock.
	negotiation.live = _agreement(pony)
	runtime.agreement_result = OFFER.AGREEMENT_WAIT
	var starts := runtime.agreement_handles.size()
	service.tick(OFFER.AGREEMENT_START_S)
	check(runtime.agreement_handles.size() == starts + 1, "a waiting Agreement is asked again")
	check(negotiation.live != null, "a waiting Agreement stays live")

	# An Agreement the scene does not accept starts nothing.
	negotiation.live = _agreement(pony)
	negotiation.is_ready = false
	starts = runtime.agreement_handles.size()
	service.tick(OFFER.AGREEMENT_START_S)
	check(runtime.agreement_handles.size() == starts,
		"an Agreement the scene does not accept starts nothing")
	negotiation.is_ready = true

	# The hotkey's exact match starts at once and does not sample the provider.
	negotiation.match = negotiation.live
	runtime.agreement_result = OFFER.AGREEMENT_STARTED
	var samples := privacy.offer_samples + privacy.cuddle_samples
	check(service.start_pose_offer(_handle(runtime, pony)), "the exact hotkey match starts")
	check(privacy.offer_samples + privacy.cuddle_samples == samples,
		"the hotkey match does not resample privacy")
	_free(made)


## One world with Anon behind a standing mare's rump, her runtime and the offer's host reads.
func _fixture(with_world := true) -> Dictionary:
	var pony := FakePony.new()
	pony.name = "Rarity"
	root.add_child(pony)
	var runtime := FakeRuntime.new()
	runtime.name = "UnfplapRuntime"
	pony.add_child(runtime)
	var negotiation := FakeNegotiation.new()
	root.add_child(negotiation)
	var hud := FakeHud.new()
	root.add_child(hud)
	var privacy := FakePrivacy.new()
	var game := FakeGame.new()
	game.name = "FakeGame"
	var menu := FakeMenu.new()
	game.save_menu = menu
	game.add_child(menu)
	var world_nodes: Array[Node] = []
	if with_world:
		game.mares = [pony]
		root.add_child(game)
		var player := FakePlayer.new()
		player.name = "FakePlayer"
		var view := Camera3D.new()
		player.add_child(view)
		player.camera = view
		root.add_child(player)
		player.global_position = Vector3(0.0, 0.0, 3.0)
		pony.global_position = Vector3(0.0, 0.0, 2.2)
		world_nodes = [player]
		WORLD.bind_world(game)
		WORLD.bind_player(player)
	var targets := Targets.new()
	targets.allowed = [pony]
	PONIES.eligibility = targets
	PONIES.stock_smack = null
	var service := OFFER.new()
	service.name = "UnfplapOffer"
	service.bind(negotiation, privacy, hud)
	PONIES.offer = service
	HUD.instance = hud
	root.add_child(service)
	return {"service": service, "pony": pony, "runtime": runtime, "game": game, "menu": menu,
		"negotiation": negotiation, "hud": hud, "privacy": privacy, "nodes": world_nodes}


func _handle(runtime: Node, pony: Node3D) -> POSE_OFFER:
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony
	offer.pose = CATALOG.MISSIONARY
	offer.source = "bed_side"
	return offer


func _agreement(pony: Node3D, pose := CATALOG.MISSIONARY, cuddle := false,
		private := false) -> AGREEMENT.Handle:
	var option := POSE_OPTIONS.Option.new()
	option.pose = pose
	option.source = "bed_side"
	option.cuddle = cuddle
	var handle := AGREEMENT.Handle.new()
	handle.id = 1
	handle.generation = 1
	handle.pony = pony
	handle.pony_id = "rarity"
	handle.option = option
	handle.private = private
	handle.cancel = func(_reason: String) -> bool: return true
	return handle


func _free(made: Dictionary) -> void:
	var service: Node = made["service"]
	service.on_world_closed()
	PONIES.stock_smack = null
	PONIES.clear_active(made["runtime"])
	PONIES.eligibility = null
	PONIES.offer = null
	WORLD.unbind()
	HUD.instance = null
	var nodes: Array[Node] = [made["game"], made["negotiation"], made["hud"], made["pony"],
		made["runtime"]]
	nodes.append_array(made["nodes"])
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			root.remove_child(node)
		node.free()
	root.remove_child(service)
	service.free()
