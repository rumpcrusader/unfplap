extends "res://mods/unfplap/tests/support/suite.gd"
## The Negotiation bridge: the typed host the service builds from its facades, the Context both
## reasoning stages read, the global Anon-offer watch and its guard table, the react line per
## close reason, the terminal outcome routing and the Agreement handoff. Fake scene, director,
## classifier and services; no model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/negotiation/test_host.gd

const HOST := preload("res://mods/unfplap/negotiation/host.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const ADAPTER := preload("res://mods/unfplap/negotiation/adapter.gd")
const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")



class FakePony extends Node3D:
	var identity := {"id": "rarity"}
	var sleeping := false
	var conversation_target: Variant = null

	func _init() -> void:
		name = "Rarity"


class FakeHold extends RefCounted:
	pass


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var scene_ok := true
	var agreement_ok := true
	var agreement_calls: Array = []
	var verdict_calls := 0
	var presented := 0
	var cleared := 0
	var started := 0
	var gate: Variant = null
	var act: Variant = null

	func _init() -> void:
		gate = self
		act = self

	func scene_only_verdict(_pose: String, _source: String, _bed: Variant,
			_frozen: Variant) -> Dictionary:
		verdict_calls += 1
		return {"hard_ok": scene_ok, "ok": scene_ok, "transient": [], "reasons": []}

	func agreement_ready(pose: String, source: String, bed: Variant, frozen: Variant) -> bool:
		agreement_calls.append([pose, source, bed, frozen])
		return agreement_ok

	func hold_handle() -> RefCounted:
		return FakeHold.new()

	func clear_presentation() -> void:
		cleared += 1

	func present_standing() -> bool:
		presented += 1
		return true

	func start_agreement(_handle: Variant) -> int:
		started += 1
		return 1

	func force_stop() -> void:
		pass

	func apply_live_settings() -> void:
		pass


class FakeAdapter extends ADAPTER:
	var watched: Array = []
	var unwatched := 0
	var queued: Array = []
	var classify_calls := 0
	var cancelled: Array[String] = []

	func watch_player(callback: Callable) -> void:
		watched.append(callback)

	func unwatch_player() -> void:
		unwatched += 1

	func queue(id: String, purpose: String, key: String, valid: Callable,
			priority: bool) -> bool:
		queued.append({"id": id, "purpose": purpose, "key": key, "valid": valid,
			"priority": priority})
		return true

	func classify(_request: PROMPTS.Request, _scope: String, _done: Callable) -> bool:
		classify_calls += 1
		return false

	func cancel_scope(scope: String) -> void:
		cancelled.append(scope)


## The service as the bridge sees it: the lock, the Anon answer and the Agreement cancel.
class FakeService extends Node:
	var locked := false
	var anon_calls: Array = []
	var cancelled: Array = []

	func is_locked() -> bool:
		return locked

	func begin_anon_offer(runtime: Node, text: String) -> bool:
		anon_calls.append({"runtime": runtime, "text": text})
		return true

	func cancel(handle: Variant, reason: String) -> bool:
		cancelled.append({"handle": handle, "reason": reason})
		return true


class FakeInitiation extends Node:
	var available := true
	var placement := POSE_OPTIONS.Placement.new()
	var approaches := 0
	var outcomes: Array = []
	var classifier: Node = null

	func placement_for(_runtime: Node) -> POSE_OPTIONS.Placement:
		return placement

	func cancel_approach() -> void:
		approaches += 1

	func on_negotiation_outcome(terminal: Variant) -> void:
		outcomes.append(terminal)

	func classifier_available() -> bool:
		return available

	func classifier_node() -> Node:
		return classifier


class FakeOffer extends Node:
	var cleared := 0

	func clear_current() -> void:
		cleared += 1


class FakeEligibility extends ELIGIBILITY:
	var act := true
	var relationship := true
	var facts: ELIGIBILITY.Facts = null

	func setup() -> void:
		pass

	func eligible(_pony: Node, _target: int = ELIGIBILITY.Target.ACT) -> bool:
		return act

	func relationship_ok(_pony: Node) -> bool:
		return relationship

	func get_verdict(_pony: Node, mode: ELIGIBILITY.Mode = ELIGIBILITY.Mode.START):
		var out := ELIGIBILITY.Verdict.new()
		out.mode = mode
		out.facts = facts if facts != null else ELIGIBILITY.Facts.new()
		return out


class FakeMemory extends MEMORY:
	var stage := "dating"

	func setup() -> void:
		pass

	func cue_facts(id: String, _event_id: String) -> MEMORY.CueFacts:
		var out := MEMORY.CueFacts.new()
		if id.is_empty():
			return out
		out.friendship = "warm"
		out.love = "deep"
		out.love_level = 2
		out.stage = stage
		return out


class FakePrivacy extends "res://mods/unfplap/tests/support/fakes/fake_privacy.gd":
	pass


class FakeImpressions extends Node:
	func profile(id: String) -> Dictionary:
		return {"mood": "warm" if id == "rarity" else ""}


class FakeWorldContext extends Node:
	var impressions: Node = null

	func _init() -> void:
		impressions = FakeImpressions.new()


class FakeGame extends Node:
	var mares: Array = []
	var player: Variant = null
	var headset_view := false
	var world_context: Node = FakeWorldContext.new()


class FakeDirector extends Node:
	signal transcript(text: String)

	var state := "idle"
	var queued: Array = []

	func queue_generated_intent(id: String, purpose: String, key: String, valid: Callable,
			_extra: Callable, priority: bool) -> bool:
		queued.append({"id": id, "purpose": purpose, "key": key, "valid": valid,
			"priority": priority})
		return true


## The bridge on its own: fakes on every side, the world bound to a fake game.
func _bridge_fixture() -> Dictionary:
	var game := FakeGame.new()
	var pony := FakePony.new()
	var runtime := FakeRuntime.new()
	runtime.pony = pony
	pony.add_child(runtime)
	var player := Node3D.new()
	player.name = "Anon"
	game.mares = [pony]
	game.player = player
	game.add_child(pony)
	game.add_child(player)
	var facts := ELIGIBILITY.Facts.new()
	facts.id = "rarity"
	facts.willing = true
	facts.heat = true
	facts.cycle_phase = "heat"
	facts.consent.public = false
	var eligibility := FakeEligibility.new()
	eligibility.facts = facts
	var bridge := HOST.new()
	bridge.service = FakeService.new()
	bridge.adapter = FakeAdapter.new()
	bridge.eligibility = eligibility
	bridge.memory = FakeMemory.new()
	bridge.privacy = FakePrivacy.new()
	bridge.initiation = FakeInitiation.new()
	bridge.offer = FakeOffer.new()
	PONIES.shutdown()
	PONIES.factory = func(_pony_node: Node) -> Node: return runtime
	PONIES.attach(pony)
	for node: Node in [game, bridge.service, bridge.adapter, bridge.initiation, bridge.offer]:
		root.add_child(node)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	return {"bridge": bridge, "game": game, "pony": pony, "runtime": runtime,
		"player": player, "eligibility": eligibility, "facts": facts,
		"service": bridge.service, "adapter": bridge.adapter, "initiation": bridge.initiation,
		"offer": bridge.offer}


func _free_bridge(made: Dictionary) -> void:
	PONIES.shutdown()
	WORLD.unbind()
	for key: String in ["service", "adapter", "initiation", "offer", "game"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


## The real service bound to fakes through `bind()`, with a live director for the react line.
func _service_fixture() -> Dictionary:
	var game := FakeGame.new()
	var pony := FakePony.new()
	var runtime := FakeRuntime.new()
	runtime.pony = pony
	pony.add_child(runtime)
	var player := Node3D.new()
	game.mares = [pony]
	game.player = player
	game.add_child(pony)
	game.add_child(player)
	var director := FakeDirector.new()
	director.add_to_group("conversation_director")
	var facts := ELIGIBILITY.Facts.new()
	facts.id = "rarity"
	facts.willing = true
	facts.heat = true
	facts.cycle_phase = "heat"
	var eligibility := FakeEligibility.new()
	eligibility.facts = facts
	var initiation := FakeInitiation.new()
	var offer := FakeOffer.new()
	PONIES.shutdown()
	PONIES.factory = func(_pony_node: Node) -> Node: return runtime
	PONIES.attach(pony)
	var service := NEGOTIATION.new()
	service.name = "UnfplapNegotiation"
	for node: Node in [game, director, initiation, offer]:
		root.add_child(node)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	root.add_child(service)
	service.bind(eligibility, FakeMemory.new(), FakePrivacy.new(), initiation, offer)
	return {"service": service, "game": game, "pony": pony, "runtime": runtime,
		"player": player, "eligibility": eligibility, "facts": facts,
		"initiation": initiation, "offer": offer, "director": director}


func _free_service(made: Dictionary) -> void:
	PONIES.shutdown()
	WORLD.unbind()
	for key: String in ["service", "director", "initiation", "offer", "game"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func _option(pose: String) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = pose
	return out


func run() -> void:
	_check_host_callbacks()
	_check_context_and_form()
	_check_watch()
	_check_anon_line_guards()
	_check_react_line()
	_check_outcome_routing()
	_check_agreement_handoff()
	finish()


## The bridge answers the typed host callbacks from the facades the entry binds.
func _check_host_callbacks() -> void:
	var made := _bridge_fixture()
	var bridge: HOST = made["bridge"]
	var eligibility: FakeEligibility = made["eligibility"]
	var runtime: FakeRuntime = made["runtime"]
	check(bridge.eligible(made["pony"]), "the act target comes from the eligibility facade")
	eligibility.act = false
	check(not bridge.eligible(made["pony"]), "an ineligible mare is not an act target")
	eligibility.act = true
	check(not bridge.eligible(null), "a missing mare is not an act target")
	check(bridge.relationship_ok(made["pony"]), "the relationship row comes from eligibility")
	eligibility.relationship = false
	check(not bridge.relationship_ok(made["pony"]), "a broken relationship refuses the route")
	eligibility.relationship = true
	check(bridge.now() > 0.0, "the clock is the bridge's")
	check((bridge.placement_for(runtime) as POSE_OPTIONS.Placement) != null,
		"the placement comes from the Proactive service")
	check(bridge.privacy_private(made["pony"], false), "the privacy provider answers offers")
	check(bridge.hold_for(runtime) is FakeHold, "the per-pony hold is the runtime's ledger")
	check(bridge.pose_placed(runtime, _option(CATALOG.STANDING)),
		"the scene-only rows are the runtime's verdict")
	runtime.scene_ok = false
	check(not bridge.pose_placed(runtime, _option(CATALOG.STANDING)),
		"a hard scene row refuses the placement")
	runtime.scene_ok = true
	check(not bridge.pose_placed(runtime, null), "a missing option is not placed")
	runtime.verdict_calls = 0
	check(bridge.scene_ready(made["pony"], _option(CATALOG.STANDING), true, true),
		"the Agreement readiness is the runtime's small scene check")
	var frozen: Variant = runtime.agreement_calls[0][3]
	check(frozen != null and frozen.pose_profile_ok and frozen.pose_source_ok,
		"the frozen pose pair reaches the gate")
	runtime.agreement_ok = false
	check(not bridge.scene_ready(made["pony"], _option(CATALOG.STANDING), true, true),
		"a changed scene refuses the readiness")
	runtime.agreement_ok = true
	check(not bridge.scene_ready(made["pony"], null, true, true),
		"a missing option is not ready")
	check(runtime.verdict_calls == 0, "the ready path builds no scene verdict")
	check(not bridge.classify(null, "", Callable()), "a model call is the adapter's")
	(made["adapter"] as FakeAdapter).classify_calls = 0
	var request := PROMPTS.Request.new()
	bridge.classify(request, "negotiation:anon_offer:1", func(_reply) -> void: pass)
	check((made["adapter"] as FakeAdapter).classify_calls == 1,
		"the classifier call reaches the one adapter")
	_free_bridge(made)


## The Context and the form view both reasoning stages read come from the service's own bridge.
func _check_context_and_form() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var pony: FakePony = made["pony"]
	var context := service.context(pony)
	check(context.willingness, "the Context carries the willingness")
	check(context.heat, "the Context carries heat")
	check(context.private, "the Context carries the live privacy")
	check(context.mood == "warm", "the Context carries the world-context mood")
	check(not context.relation_note.is_empty(), "the Context carries the relationship note")
	var view := service.form_view()
	check(view.form == "human", "the form view names Anon's form")
	check(view.view == "desktop", "the form view names the display")
	check(is_instance_valid(service.adapter()), "the service owns its adapter")
	check(service.adapter().name == "UnfplapNegotiationAdapter",
		"the adapter is the service's child by its stable name")
	_free_service(made)


## The watch is armed only while no act and no negotiation own the frame.
func _check_watch() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var adapter := service.adapter()
	service.tick(0.0)
	service.tick(0.0)
	var watch: Callable = adapter.get("_offer_watch")
	check(watch.is_valid(), "the adapter holds the watch")
	PONIES.set_active(runtime)
	service.tick(0.0)
	watch = adapter.get("_offer_watch")
	check(not watch.is_valid(), "the adapter drops the watch")
	PONIES.clear_active(runtime)
	service.on_world(null)
	service.tick(0.0)
	_free_service(made)

	var bridged := _bridge_fixture()
	var bridge: HOST = bridged["bridge"]
	var fake: FakeService = bridged["service"]
	var fake_adapter: FakeAdapter = bridged["adapter"]
	bridge.tick_watch()
	check(fake_adapter.watched.size() == 1, "an unlocked negotiation arms the watch")
	fake.locked = true
	bridge.tick_watch()
	check(fake_adapter.unwatched == 1, "the lock disarms the watch")
	bridge.tick_watch()
	check(fake_adapter.unwatched == 1, "a locked frame does not disarm twice")
	bridge.disarm()
	check(fake_adapter.unwatched == 1, "disarming an unarmed watch is a no-op")
	_free_bridge(bridged)


## The first new line is only an Anon offer when every guard passes.
func _check_anon_line_guards() -> void:
	var made := _bridge_fixture()
	var bridge: HOST = made["bridge"]
	var service: FakeService = made["service"]
	var initiation: FakeInitiation = made["initiation"]
	var runtime: FakeRuntime = made["runtime"]
	var pony: FakePony = made["pony"]

	bridge.on_anon_line("   ")
	bridge.on_anon_line("a".repeat(HOST.MAX_LINE + 1))
	service.locked = true
	bridge.on_anon_line("take me to bed")
	service.locked = false
	initiation.available = false
	bridge.on_anon_line("take me to bed")
	initiation.available = true
	pony.conversation_target = null
	bridge.on_anon_line("take me to bed")
	pony.conversation_target = made["player"]
	runtime.state = 1
	bridge.on_anon_line("take me to bed")
	runtime.state = 0
	check(service.anon_calls.is_empty(), "no skipped line forms an offer")

	bridge.on_anon_line("  take me to bed  ")
	check(service.anon_calls.size() == 1, "the guarded line forms one Anon offer")
	check(str(service.anon_calls[0]["text"]) == "take me to bed",
		"the offer carries the trimmed line")
	check(service.anon_calls[0]["runtime"] == runtime, "the offer carries the mare's runtime")
	check(initiation.approaches == 1, "a live Proactive approach is cancelled first")
	_free_bridge(made)


## The one react line takes its purpose from the close reason.
func _check_react_line() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var director: FakeDirector = made["director"]
	var pony: FakePony = made["pony"]
	pony.set_meta("relationship_id", "rarity")
	service.call("_react_line", pony, AGREEMENT.REASON_COUNTER_OFFER)
	check(director.queued.size() == 1, "the counter-offer queues one line")
	var row: Dictionary = director.queued[0]
	check(str(row["purpose"]).begins_with("Anon just offered sex"),
		"the counter-offer asks for a place or timing decline")
	check(str(row["key"]).begins_with("unfplap:negotiation:react:"),
		"the react key keeps its stable prefix")
	check(str(row["id"]) == "rarity", "the line is queued for the mare")
	service.call("_react_line", pony, AGREEMENT.REASON_PRIVACY)
	check(str(director.queued[1]["purpose"]).begins_with("The moment was interrupted"),
		"a privacy loss lets the moment go")
	service.call("_react_line", pony, "")
	check(str(director.queued[2]["purpose"]).begins_with("The offer ended"),
		"every other close is the generic release")
	check(director.queued[0]["key"] != director.queued[1]["key"], "each line has its own key")
	service.call("_react_line", null, "")
	check(director.queued.size() == 3, "a missing mare queues nothing")
	_free_service(made)


## Every terminal outcome clears the presentation and reaches the Proactive pacing unless the
## act already started.
func _check_outcome_routing() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var initiation: FakeInitiation = made["initiation"]
	var runtime: FakeRuntime = made["runtime"]
	var pony: FakePony = made["pony"]
	var terminal := NEGOTIATION.Terminal.new()
	terminal.pony = pony
	terminal.pony_id = "rarity"
	terminal.outcome = NEGOTIATION.Outcome.REFUSED
	terminal.reason = AGREEMENT.REASON_COUNTER_OFFER
	terminal.cooldown_s = NEGOTIATION.COOLDOWN_S
	service.call("_on_outcome_terminal", terminal)
	check(runtime.cleared == 1, "the outcome clears the presentation")
	check(initiation.outcomes.size() == 1, "a non-started outcome reaches the Proactive")
	var started := NEGOTIATION.Terminal.new()
	started.pony = pony
	started.outcome = NEGOTIATION.Outcome.STARTED
	service.call("_on_outcome_terminal", started)
	check(initiation.outcomes.size() == 1, "a started act is not forwarded as a negotiation")
	check(runtime.cleared == 2, "a started outcome clears the presentation too")
	service.call("_on_outcome_terminal", null)
	check(runtime.cleared == 2, "a missing terminal changes nothing")
	_free_service(made)


## The Agreement handoff presents the standing pose at once and clears the shared offer window.
func _check_agreement_handoff() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var offer: FakeOffer = made["offer"]
	var runtime: FakeRuntime = made["runtime"]
	var pony: FakePony = made["pony"]
	var handle := AGREEMENT.Handle.new()
	handle.id = 1
	handle.generation = 1
	handle.pony = pony
	handle.pony_id = "rarity"
	handle.option = _option(CATALOG.STANDING)
	service.call("_on_agreement_handle", handle)
	check(runtime.presented == 1, "a standing Agreement presents at once")
	check(offer.cleared == 1, "the shared offer window is cleared")
	var missionary := AGREEMENT.Handle.new()
	missionary.id = 2
	missionary.generation = 2
	missionary.pony = pony
	missionary.pony_id = "rarity"
	missionary.option = _option(CATALOG.MISSIONARY)
	service.call("_on_agreement_handle", missionary)
	check(runtime.presented == 1, "a bed Agreement starts no presentation")
	check(offer.cleared == 2, "the offer window is cleared for every Agreement")
	var orphan := AGREEMENT.Handle.new()
	orphan.id = 3
	orphan.generation = 3
	orphan.pony = null
	orphan.pony_id = ""
	orphan.option = _option(CATALOG.STANDING)
	service.call("_on_agreement_handle", orphan)
	check(runtime.presented == 1, "an Agreement with no runtime presents nothing")
	check(offer.cleared == 2, "an Agreement with no runtime clears no offer")
	service.call("_on_agreement_handle", null)
	check(offer.cleared == 2, "a missing handle changes nothing")
	_free_service(made)
