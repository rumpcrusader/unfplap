extends SceneTree
## The reduced proactive service: Base clearance, the placeable options, the reasoning, the walk,
## the ask line and the Mare-offer handoff, against a fake director bridge, privacy and runtime.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/initiation/test_initiation_api.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const INIT := preload("res://mods/unfplap/initiation/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const CLASSIFIER := preload("res://mods/unfplap/initiation/classifier.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


class FakeView extends RefCounted:
	var form := "human"
	var view := "desktop"


class FakeEligibility extends ELIGIBILITY:
	var act := true
	var relationship := true

	func setup() -> void:
		pass

	func eligible(_pony: Node, _target: int = ELIGIBILITY.Target.ACT) -> bool:
		return act

	func relationship_ok(_pony: Node) -> bool:
		return relationship


class FixtureHost extends Node:
	var player: Node3D
	var game: Node


## The Negotiation facade as the Proactive service sees it: the lock, the form view, the Context,
## the typed Mare offer and the one adapter.
class FakeNegotiation extends NEGOTIATION:
	var view := NEGOTIATION.FormView.new()
	var locked := false
	var handed: NEGOTIATION.MareOffer = null
	var handoff_ok := true
	var adapter_node: Node = null

	func is_locked() -> bool:
		return locked

	func form_view() -> NEGOTIATION.FormView:
		return view

	func context(_pony: Node) -> CONTEXT.Context:
		return CONTEXT.build({"willingness": true, "history": {"offer_weight": 0.7}})

	func begin_mare_offer(mare_offer: NEGOTIATION.MareOffer) -> bool:
		handed = mare_offer
		return handoff_ok

	func adapter() -> Node:
		return adapter_node


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node
	var headset_view := false


class FakeWorldContext extends Node:
	var records: Array = []

	func record(kind: String, text: String, ids: Array, _audience: Array, key: String) -> void:
		records.append({"kind": kind, "text": text, "ids": ids, "key": key})


class FakeNavigator extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true
	var command_speed_limit: Variant = INF
	var command_pace_target: Variant = -1.0
	var _has_target := false
	var goal: Variant = null

	func stay() -> void:
		_has_target = false

	func command_support(point: Vector3) -> Vector3:
		return point

	func command_destination(point: Vector3, _gait: String) -> bool:
		goal = point
		_has_target = true
		return true


class FakePony extends Node3D:
	var identity: Dictionary = {"filly": false, "stallion": false}
	var sleeping := false


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var cuddle := false
	var bed_under: Node3D = null
	var hard_ok := true
	var phase := "normal"
	var scene_reasons: Array = []
	var gate: Variant = null
	var act: Variant = null

	func _init() -> void:
		gate = self
		act = self

	func scene_only_verdict(_pose: String, _source: String, _bed: Variant,
			_frozen: Variant) -> Dictionary:
		return {"hard_ok": hard_ok, "ok": hard_ok, "transient": [], "reasons": scene_reasons}

	func cuddle_active() -> bool:
		return cuddle

	func force_stop() -> void:
		pass

	func apply_live_settings() -> void:
		pass

	func find_bed_under() -> Node3D:
		return bed_under

	func cycle_phase() -> String:
		return phase


class FakePrivacy extends PRIVACY:
	var private := true

	func setup() -> void:
		pass

	func offer_private(_except: Node = null) -> bool:
		return private

	func cuddle_private(_pony: Node) -> bool:
		return private


class FakeAdapter extends Node:
	var quiet_reason_value := ""
	var reason_reply := "{\"offer\":false}"
	var reason_error := ""
	var greeting_ok := true
	var greetings: Array = []
	var queued: Array = []
	var cancelled: Array = []
	var situations: Array = []
	var reason_payloads: Array = []
	var auto := true

	func quiet_reason(_gap: float) -> String:
		return quiet_reason_value

	func quiet(_gap: float) -> bool:
		return quiet_reason_value == ""

	func begin_greeting(id: String, context: String) -> bool:
		greetings.append([id, context])
		return greeting_ok

	func queue(id: String, purpose: String, key: String, _valid: Callable,
			_priority: bool) -> bool:
		queued.append([id, purpose, key])
		return true

	func cancel_keys(keys: Array) -> void:
		cancelled.append_array(keys)

	func record_situation(text: String, ids: Array, key: String) -> void:
		situations.append({"text": text, "ids": ids, "key": key})

	func complete_raw(_system: String, payload: Dictionary, _scope: String,
			done: Callable) -> bool:
		reason_payloads.append(payload)
		if auto:
			done.call(reason_reply, reason_error)
		return true

	func cancel_scope(scope: String) -> void:
		cancelled.append(scope)


class FakeTerminal extends RefCounted:
	var pony: Node = null
	var pony_id := ""
	var outcome := 0
	var reason := ""
	var trigger := 0
	var cooldown_s := 0.0


## The idle offer facade's one read the Proactive gate uses: which pony the act key would start.
class FakeOffer extends OFFER:
	var target: Variant = null
	var reads := 0

	func offer_target() -> Node:
		reads += 1
		return target if is_instance_valid(target) else null


func _fixture() -> Dictionary:
	var main := FixtureHost.new()
	var game := FakeGame.new()
	var context := FakeWorldContext.new()
	var player := Node3D.new()
	var target := FakePony.new()
	target.name = "Rarity"
	target.set_meta("relationship_id", "rarity")
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	target.add_child(nav)
	var runtime := FakeRuntime.new()
	runtime.pony = target
	target.add_child(runtime)
	var eligibility := FakeEligibility.new()
	var adapter := FakeAdapter.new()
	var privacy := FakePrivacy.new()
	var offer := FakeOffer.new()
	game.world_context = context
	game.mares = [target]
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	var negotiation := FakeNegotiation.new()
	negotiation.adapter_node = adapter
	PONIES.shutdown()
	PONIES.factory = func(_pony_node: Node) -> Node: return runtime
	PONIES.attach(target)
	for node: Node in [game, player, target, adapter, negotiation, offer]:
		root.add_child(node)
	root.add_child(main)
	var service := INIT.new()
	service.name = "UnfplapInitiation"
	service.eligibility = eligibility
	service.setup(privacy, negotiation, offer)
	root.add_child(service)
	return {"main": main, "game": game, "context": context, "player": player,
		"target": target, "nav": nav, "runtime": runtime, "eligibility": eligibility,
		"adapter": adapter, "privacy": privacy, "service": service, "offer": offer,
		"negotiation": negotiation}


func _free(made: Dictionary) -> void:
	PONIES.shutdown()
	for key: String in ["service", "main", "game", "player", "target", "adapter", "offer",
			"negotiation"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func run() -> void:
	check(CLASSIFIER.NEGOTIATION_LIMITS.get("reasoning_room", 0) >= 512,
		"the negotiation classifier reserves private-reasoning room")
	check(CLASSIFIER.DEADLINE_SECONDS >= 8.0,
		"the negotiation classifier deadline covers reasoning")
	_check_force()
	_check_clearance_and_options()
	_check_reasoning()
	_check_handoff_failure()
	_check_cuddle()
	_check_cuddle_target()
	_check_outcome_and_reset()
	_check_scan_quiet()
	print("INITIATION_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_API_PASS")
	quit(0 if failures == 0 else 1)


func _check_force() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FixtureHost = made["main"]
	var nav: FakeNavigator = made["nav"]
	var context: FakeWorldContext = made["context"]
	var adapter: FakeAdapter = made["adapter"]
	var target: FakePony = made["target"]
	target.global_position = Vector3.ZERO
	var forced: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(forced.ok, "force starts a standing offer")
	check(forced.id == "rarity" and forced.pose == CATALOG.STANDING,
		"the force result names the mare and the pose")
	check(nav.command_owner == "unfplap:request:rarity",
		"the ask owns the navigator")
	check(not nav.wander_enabled and not nav._has_target, "the ask holds her still")
	check(negotiation.handed != null, "the offer is handed to the negotiation")
	check(negotiation.handed.hold_token == "unfplap:request:rarity",
		"the handoff carries the request lease")
	check(negotiation.handed.private, "a quiet house forms a private offer")
	check(not negotiation.handed.cuddle, "a standing offer is not a cuddle")
	check(adapter.greetings.size() == 1 and adapter.greetings[0][0] == "rarity",
		"the ask line opens with the greeting")
	check(adapter.situations.size() == 1 and adapter.situations[0]["key"].ends_with(":situation"),
		"the ask records one situation")
	check(service.debug_rows(target).size() > 0, "the request rows render")
	# The negotiation owns the lease after the handoff; the fake negotiator ends it here.
	check(nav.command_owner == "unfplap:request:rarity",
		"a handed-off ask leaves the lease to the negotiation")
	nav.command_owner = ""
	nav.wander_enabled = true

	# A fallback queue path when the greeting cannot open the line.
	service.on_world_closed()
	check(nav.command_owner.is_empty() and nav.wander_enabled,
		"reset leaves the released lease untouched")
	adapter.greeting_ok = false
	adapter.queued.clear()
	var asked: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(asked.ok, "force still asks without a greeting")
	check(adapter.queued.size() == 1 and str(adapter.queued[0][2]).ends_with(":ask"),
		"the fallback ask key names the request")
	adapter.greeting_ok = true

	# A distant Anon starts the walk, not the ask.
	service.on_world_closed()
	nav.command_owner = ""
	nav.wander_enabled = true
	adapter.greetings.clear()
	adapter.queued.clear()
	target.global_position = Vector3(10.0, 0.0, 0.0)
	var walking: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(walking.ok, "force starts a distant walk")
	check(nav.command_owner.begins_with("unfplap:request:rarity") and nav._has_target,
		"the walk owns the navigator and has a route")
	check(adapter.greetings.is_empty() and adapter.queued.is_empty(),
		"a distant walk has not asked yet")
	target.global_position = Vector3(2.0, 0.0, 0.0)
	service.tick(0.0)
	check(not nav._has_target, "arriving stops the walk")
	check(adapter.greetings.is_empty(), "the arrival still settles")
	_free(made)


func _check_clearance_and_options() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var eligibility: FakeEligibility = made["eligibility"]
	var main: FixtureHost = made["main"]
	eligibility.relationship = false
	var rejected: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not rejected.ok and rejected.reject.contains("clearance:relationship"),
		"a failed Base clearance rejects the offer")
	eligibility.relationship = true
	runtime.state = 1
	var busy: INIT.ForceResult = service.force(runtime)
	check(not busy.ok and busy.reject.contains("state=1"), "force reports the runtime state")
	runtime.state = 0
	var missing: INIT.ForceResult = service.force(null)
	check(not missing.ok and missing.reject == "no_runtime", "force rejects a missing runtime")
	var internal_pose: INIT.ForceResult = service.force(runtime, CATALOG.STANDING_ORAL)
	check(not internal_pose.ok and internal_pose.reject.contains("pose:standing_oral"),
		"an internal pose is never offered")
	negotiation.view.view = "vr"
	var vr_bed: INIT.ForceResult = service.force(runtime, CATALOG.MISSIONARY)
	check(not vr_bed.ok and vr_bed.reject.contains("pose:missionary"),
		"a pose the display cannot place is never offered")
	negotiation.view.view = "desktop"
	runtime.hard_ok = false
	runtime.scene_reasons = ["affection"]
	var blocked: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not blocked.ok and blocked.reject.contains("scene:affection"),
		"a hard scene row rejects the formation")
	runtime.hard_ok = true
	_free(made)


func _check_reasoning() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var adapter: FakeAdapter = made["adapter"]
	var main: FixtureHost = made["main"]
	var target: FakePony = made["target"]
	target.global_position = Vector3.ZERO
	adapter.reason_reply = "{\"offer\":false}"
	service.tick(0.5)
	check(adapter.reason_payloads.size() == 1, "the scan runs one reasoning call")
	var payload: Dictionary = adapter.reason_payloads[0]
	check((payload.get("options", []) as Array).size() == 1,
		"the scan sends the one placeable option")
	check((payload.get("context", {}) as Dictionary).get("willing") == true,
		"the reasoning payload carries Context")
	check(negotiation.handed == null, "a no-offer reasoning forms nothing")

	service.on_world_closed()
	adapter.reason_payloads.clear()
	service.tick(0.5)

	# Clear the stamped cooldown so the next scan may reason again.
	service.clear_cooldown(target)
	adapter.reason_payloads.clear()
	adapter.reason_reply = "{\"offer\":true,\"option\":0}"
	service.tick(0.5)
	check(negotiation.handed != null, "a reasoning yes forms the offer")
	check(adapter.greetings.size() == 1, "the reasoning yes asks")
	_free(made)


func _check_handoff_failure() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FixtureHost = made["main"]
	var nav: FakeNavigator = made["nav"]
	var adapter: FakeAdapter = made["adapter"]
	negotiation.handoff_ok = false
	var result: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not result.ok, "a refused handoff forms no offer")
	check(result.reject == "handoff refused", "a refused handoff reports the close reason")
	check(nav.command_owner.is_empty(), "a refused handoff releases the request lease")
	check(adapter.greetings.is_empty(), "a refused handoff speaks no ask line")
	check("\n".join(PackedStringArray(service.debug_rows(made["target"]))).contains("retry left="),
		"a refused handoff sets the short retry")
	_free(made)


func _check_cuddle() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FixtureHost = made["main"]
	var nav: FakeNavigator = made["nav"]
	var bed := Node3D.new()
	root.add_child(bed)
	runtime.cuddle = true
	runtime.bed_under = bed
	var result: INIT.ForceResult = service.force(runtime)
	check(result.ok, "a cuddle offer forms")
	check(negotiation.handed.cuddle, "the handoff marks the cuddle")
	check(negotiation.handed.hold_token.is_empty(),
		"the cuddle handoff carries no navigator lease")
	check(nav.command_owner.is_empty(), "the cuddle keeps the session's navigator")
	service.on_world_closed()
	root.remove_child(bed)
	bed.free()
	_free(made)


## The Proactive scan's cuddle gate reads the offer facade's current target: a non-forced scan
## skips a cuddle the act key would not start, and asks the one it would.
func _check_cuddle_target() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FixtureHost = made["main"]
	var adapter: FakeAdapter = made["adapter"]
	var target: FakePony = made["target"]
	var offer: FakeOffer = made["offer"]
	var bed := Node3D.new()
	root.add_child(bed)
	runtime.cuddle = true
	runtime.bed_under = bed
	service.clear_cooldown(target)
	adapter.reason_reply = "{\"offer\":true,\"option\":0}"

	# The act key would start another pony, so the scan's cuddle candidate is skipped, not forced.
	offer.target = null
	service.tick(0.5)
	check(offer.reads > 0, "the scan reads the offer facade's current target")
	check(adapter.reason_payloads.is_empty(),
		"a cuddle the act key would not start reasons nothing")
	check(negotiation.handed == null, "a cuddle the act key would not start forms nothing")

	# The act key's current offer is her, so the same scan asks.
	offer.target = target
	service.tick(0.5)
	check(negotiation.handed != null, "a cuddle the act key would start forms the offer")
	check(negotiation.handed.cuddle, "the non-forced handoff marks the cuddle")
	service.on_world_closed()
	root.remove_child(bed)
	bed.free()
	_free(made)


func _check_outcome_and_reset() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var target: FakePony = made["target"]
	var terminal := FakeTerminal.new()
	terminal.pony_id = "rarity"
	terminal.outcome = 2
	terminal.reason = ""
	terminal.cooldown_s = 120.0
	service.on_negotiation_outcome(terminal)
	check("\n".join(PackedStringArray(service.debug_rows(target))).contains("cooldown ready="),
		"the outcome updates the pacing rows")
	var retry := FakeTerminal.new()
	retry.pony_id = "rarity"
	retry.reason = "privacy"
	retry.cooldown_s = 0.0
	service.on_negotiation_outcome(retry)
	var rows := "\n".join(PackedStringArray(service.debug_rows(target)))
	check(rows.contains("retry left=") and not rows.contains("retry left=none"),
		"a no-cooldown outcome sets the short retry")
	check(not service.clear_cooldown(null), "clear_cooldown rejects a missing mare")
	check(service.clear_cooldown(target), "clear_cooldown accepts a known mare")
	_free(made)


## A quiet scan and a locked negotiation form nothing: the guards hold without the console.
func _check_scan_quiet() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var adapter: FakeAdapter = made["adapter"]
	var main: FixtureHost = made["main"]
	adapter.quiet_reason_value = "chat"
	service.tick(0.5)
	service.tick(0.5)
	check(adapter.reason_payloads.is_empty(), "a recent chat reasons nothing")
	adapter.quiet_reason_value = ""
	negotiation.locked = true
	adapter.reason_payloads.clear()
	service.tick(0.5)
	check(adapter.reason_payloads.is_empty(), "a live negotiation keeps the scan quiet")
	negotiation.locked = false
	_free(made)
