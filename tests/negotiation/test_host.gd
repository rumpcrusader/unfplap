extends "res://mods/unfplap/tests/support/suite.gd"
## The Negotiation bridge: the typed host the service builds from its facades, the Context both
## reasoning stages read, the global Anon-offer watch and its guard table, the react line per
## close reason and the terminal outcome routing. Fake scene, director, classifier and services;
## no model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/negotiation/test_host.gd

const HOST := preload("res://mods/unfplap/negotiation/host.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/api.gd")
const DIRECTOR := preload("res://mods/unfplap/director/api.gd")
const CLASSIFIER := preload("res://mods/unfplap/classifier/api.gd")
const AGREEMENT := preload("res://mods/unfplap/shared/agreement.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/api.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/api.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/api.gd")
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


class FakeHold extends Node:
	pass


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var scene_ok := true
	var verdict_calls := 0
	var scene: Variant = null
	var presentation: Variant = null
	var act: Variant = null

	func _init() -> void:
		scene = self
		presentation = self
		act = self

	func scene_only_verdict(_pose: String, _source: String, _bed: Variant,
			_frozen: Variant) -> Dictionary:
		verdict_calls += 1
		return {"hard_ok": scene_ok, "ok": scene_ok, "transient": [], "reasons": []}

	func hold_handle() -> Node:
		return FakeHold.new()


class FakeVoice extends DIRECTOR:
	var watched := 0
	var unwatched := 0
	var queued: Array = []
	var cancel_calls: Array[String] = []

	func watch_player(_sink: DIRECTOR.Line) -> void:
		watched += 1

	func unwatch_player() -> void:
		unwatched += 1

	func queue(id: String, purpose: String, key: String, valid: DIRECTOR.Validity,
			priority: bool) -> bool:
		queued.append({"id": id, "purpose": purpose, "key": key, "valid": valid,
			"priority": priority})
		return true

	func cancel_scope(scope: String) -> void:
		cancel_calls.append(scope)
		super(scope)


class FakeClassifier extends "res://mods/unfplap/classifier/api.gd":
	var calls: Array = []
	var can_answer := true
	var reply := "{\"offer\":true,\"option\":0}"
	var error := ""

	func available() -> bool:
		return can_answer

	func run(definition: CLASSIFIER.Definition, utterance: String) -> CLASSIFIER.Call:
		if not can_answer:
			return null
		var call := CLASSIFIER.Call.new()
		call.definition = definition
		call.utterance = utterance
		calls.append({"definition": definition, "utterance": utterance, "call": call})
		return call

	func answer() -> void:
		var row: Dictionary = calls[-1]
		(row["call"] as CLASSIFIER.Call).done.emit(reply, error)


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
	var placement := POSE_OPTIONS.Placement.new()
	var approaches := 0
	var outcomes: Array = []

	func placement_for(_runtime: Node) -> POSE_OPTIONS.Placement:
		return placement

	func cancel_approach() -> void:
		approaches += 1

	func on_negotiation_outcome(terminal: Variant) -> void:
		outcomes.append(terminal)


class FakeEligibility extends ELIGIBILITY:
	var act := true

	func eligible(_pony: Node, _target: ELIGIBILITY.Target) -> bool:
		return act


class FakeGate extends ACT_GATE:
	var relationship := true
	var facts: ACT_GATE.Facts = null

	func relationship_ok(_pony: Node) -> bool:
		return relationship

	func get_verdict(_pony: Node, mode: ACT_GATE.Mode = ACT_GATE.Mode.START):
		var out := ACT_GATE.Verdict.new()
		out.mode = mode
		out.facts = facts if facts != null else ACT_GATE.Facts.new()
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
## A wired act owner for one fixture: the watch reads its frame.
func _owner() -> ACT_OWNER:
	var owner := ACT_OWNER.new()
	owner.wire(null, null)
	return owner


## The roster's peers come from the fixture's record, the way the entry hands them.
func _wire(roster: PONIES, world: HANDLES) -> void:
	roster.wire(world.anatomy, world.eligibility, world.act_gate, world.body_change,
		world.estrus, world.stock_smack, world.act_owner)


func _bridge_fixture() -> Dictionary:
	var game := FakeGame.new()
	var pony := FakePony.new()
	var runtime := FakeRuntime.new()
	runtime.name = "UnfplapRuntime"
	runtime.pony = pony
	pony.add_child(runtime)
	var player := Node3D.new()
	player.name = "Anon"
	game.mares = [pony]
	game.player = player
	game.add_child(pony)
	game.add_child(player)
	var facts := ACT_GATE.Facts.new()
	facts.id = "rarity"
	facts.willing = true
	facts.heat = true
	facts.cycle_phase = "heat"
	facts.consent.public = false
	var eligibility := FakeEligibility.new()
	var gate := FakeGate.new()
	gate.facts = facts
	var world := HANDLES.new()
	world.eligibility = eligibility
	world.act_gate = gate
	world.act_owner = _owner()
	var roster := PONIES.new()
	_wire(roster, world)
	roster.factory = func(_pony_node: Node) -> Node: return runtime
	roster.attach(pony)
	var bridge := HOST.new()
	bridge.service = FakeService.new()
	bridge.voice = FakeVoice.new()
	bridge.classifier = FakeClassifier.new()
	bridge.eligibility = eligibility
	bridge.gate = gate
	bridge.memory = FakeMemory.new()
	bridge.privacy = FakePrivacy.new()
	bridge.initiation = FakeInitiation.new()
	bridge.act_owner = world.act_owner
	bridge.ponies = roster
	for node: Node in [game, bridge.service, bridge.voice, bridge.classifier, bridge.initiation]:
		root.add_child(node)
	root.add_child(roster)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	return {"bridge": bridge, "game": game, "pony": pony, "runtime": runtime,
		"player": player, "eligibility": eligibility, "gate": gate, "facts": facts,
		"service": bridge.service, "voice": bridge.voice, "classifier": bridge.classifier,
		"initiation": bridge.initiation, "owner": world.act_owner, "ponies": roster,
		"memory": bridge.memory, "privacy": bridge.privacy}


func _free_bridge(made: Dictionary) -> void:
	var roster: PONIES = made["ponies"]
	roster.shutdown()
	root.remove_child(roster)
	roster.free()
	WORLD.unbind()
	for key: String in ["service", "voice", "classifier", "initiation", "game"]:
		var node: Node = made[key]
		root.remove_child(node)
		if key == "game" and node.world_context != null:
			if node.world_context.impressions != null:
				node.world_context.impressions.free()
			node.world_context.free()
		node.free()
	(made["owner"] as Node).free()
	for key: String in ["eligibility", "gate", "memory", "privacy"]:
		(made[key] as Node).free()


## The real service bound to fakes through `bind()`, with a live director for the react line.
func _service_fixture() -> Dictionary:
	var game := FakeGame.new()
	var pony := FakePony.new()
	var runtime := FakeRuntime.new()
	runtime.name = "UnfplapRuntime"
	runtime.pony = pony
	pony.add_child(runtime)
	var player := Node3D.new()
	game.mares = [pony]
	game.player = player
	game.add_child(pony)
	game.add_child(player)
	var director := FakeDirector.new()
	director.add_to_group("conversation_director")
	var facts := ACT_GATE.Facts.new()
	facts.id = "rarity"
	facts.willing = true
	facts.heat = true
	facts.cycle_phase = "heat"
	var eligibility := FakeEligibility.new()
	var gate := FakeGate.new()
	gate.facts = facts
	var initiation := FakeInitiation.new()
	var owner := _owner()
	var world := HANDLES.new()
	world.eligibility = eligibility
	world.act_gate = gate
	world.act_owner = owner
	var roster := PONIES.new()
	_wire(roster, world)
	roster.factory = func(_pony_node: Node) -> Node: return runtime
	roster.attach(pony)
	var service := NEGOTIATION.new()
	service.name = "UnfplapNegotiation"
	var voice := FakeVoice.new()
	var classifier := FakeClassifier.new()
	for node: Node in [game, director, initiation, voice, classifier]:
		root.add_child(node)
	root.add_child(roster)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	var memory := FakeMemory.new()
	var privacy := FakePrivacy.new()
	service.wire(eligibility, gate, memory, privacy, initiation, voice, owner, null, roster,
		classifier)
	root.add_child(service)
	return {"service": service, "game": game, "pony": pony, "runtime": runtime,
		"player": player, "eligibility": eligibility, "gate": gate, "facts": facts,
		"initiation": initiation, "director": director, "owner": owner, "voice": voice,
		"classifier": classifier, "ponies": roster, "memory": memory, "privacy": privacy}


func _free_service(made: Dictionary) -> void:
	var roster: PONIES = made["ponies"]
	roster.shutdown()
	root.remove_child(roster)
	roster.free()
	WORLD.unbind()
	(made["owner"] as Node).free()
	for key: String in ["service", "director", "initiation", "voice", "classifier", "game"]:
		var node: Node = made[key]
		root.remove_child(node)
		if key == "game" and node.world_context != null:
			if node.world_context.impressions != null:
				node.world_context.impressions.free()
			node.world_context.free()
		node.free()
	for key: String in ["eligibility", "gate", "memory", "privacy"]:
		(made[key] as Node).free()


func _option(pose: String) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = pose
	return out


func run() -> void:
	_check_wire_build()
	_check_host_callbacks()
	_check_models()
	_check_context_facts()
	_check_watch()
	_check_anon_line_guards()
	_check_react_line()
	_check_outcome_routing()
	finish()


## `wire()` stores its peers only; the bridge and the typed host are `_ready()`'s, so a service
## that attaches after every `wire()` still owns the live bridge.
func _check_wire_build() -> void:
	var service := NEGOTIATION.new()
	service.name = "UnfplapNegotiation"
	var owner := _owner()
	var eligibility := FakeEligibility.new()
	var gate := FakeGate.new()
	var memory := FakeMemory.new()
	var privacy := FakePrivacy.new()
	var initiation := FakeInitiation.new()
	var voice := FakeVoice.new()
	var classifier := FakeClassifier.new()
	service.wire(eligibility, gate, memory, privacy, initiation, voice, owner, null, null,
		classifier)
	check(service.get_child_count() == 0, "wire() builds no child")
	root.add_child(service)
	check(service.get_child_count() == 0, "attaching builds no child either")
	check(service.get("_bridge") != null, "attaching builds the bridge")
	check(service.get("_host") != null, "attaching binds the typed host to the bridge")
	root.remove_child(service)
	service.free()
	owner.free()
	eligibility.free()
	gate.free()
	memory.free()
	privacy.free()
	initiation.free()
	voice.free()
	classifier.free()


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
	var gate: FakeGate = made["gate"]
	check(bridge.relationship_ok(made["pony"]), "the relationship row comes from the act gate")
	gate.relationship = false
	check(not bridge.relationship_ok(made["pony"]), "a broken relationship refuses the route")
	gate.relationship = true
	check(bridge.now() > 0.0, "the clock is the bridge's")
	check((bridge.placement_for(runtime) as POSE_OPTIONS.Placement) != null,
		"the placement comes from the Proactive service")
	check(bridge.privacy_private(made["pony"], false), "the privacy provider answers offers")
	var hold: Node = bridge.hold_for(runtime)
	check(hold is FakeHold, "the per-pony hold is the runtime's ledger")
	hold.free()
	check(bridge.pose_placed(runtime, _option(CATALOG.STANDING)),
		"the scene-only rows are the runtime's verdict")
	runtime.scene_ok = false
	check(not bridge.pose_placed(runtime, _option(CATALOG.STANDING)),
		"a hard scene row refuses the placement")
	runtime.scene_ok = true
	check(not bridge.pose_placed(runtime, null), "a missing option is not placed")
	runtime.verdict_calls = 0
	check(not bridge.classify(null, "", Callable()), "a model call needs a request")
	_free_bridge(made)


## The two typed model requests: this bridge builds the instruction and the payload, makes the
## one raw transport call and parses the reply. No model.
func _check_models() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var bridge: HOST = service.get("_bridge")
	var classifier: FakeClassifier = made["classifier"]
	var context := CONTEXT.build({"willingness": true})
	var options: Array[POSE_OPTIONS.Option] = [
		_option(CATALOG.MISSIONARY),
		_option(CATALOG.STANDING),
	]
	var request := PROMPTS.Request.new()
	request.kind = "anon_offer"
	request.text = "take me to bed"
	request.context = context
	request.options = options
	var got: Array = []
	check(bridge.classify(request, "negotiation:anon_offer:1", func(reply) -> void:
		got.append(reply)), "the Anon offer classifier runs")
	check(classifier.calls.size() == 1, "one classifier call is made")
	var row: Dictionary = classifier.calls[0]
	check(str((row["definition"] as CLASSIFIER.Definition).instruction).contains("option"),
		"the Anon offer instruction is used")
	var payload := _utterance(row)
	check(str(payload.get("player_line", "")) == "take me to bed",
		"the classifier payload carries the line")
	check((payload.get("options", []) as Array).size() == 2,
		"the classifier payload carries the options")
	check((payload.get("context", {}) as Dictionary).get("willing") == true,
		"the classifier payload carries Context")
	classifier.answer()
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_ACCEPT and got[0].option_index == 0,
		"the reply is parsed into the typed answer")

	got.clear()
	request.kind = "anon_decision"
	request.text = "right here"
	request.line = "come here"
	classifier.reply = "{\"answer\":\"accept\"}"
	check(bridge.classify(request, "negotiation:decision:1", func(reply) -> void:
		got.append(reply)), "the Anon decision classifier runs")
	classifier.answer()
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_ACCEPT,
		"the Anon decision is parsed")
	payload = _utterance(classifier.calls[-1])
	check(str(payload.get("offer", "")) == "come here", "the decision payload carries the offer")

	got.clear()
	request.kind = "mare_response"
	request.text = "want to?"
	request.options = [options[1]]
	classifier.reply = "{\"answer\":\"counter_offer\"}"
	check(bridge.reason(request, "negotiation:response:1", func(reply) -> void:
		got.append(reply)), "the Mare response reasoning runs")
	classifier.answer()
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_COUNTER_OFFER,
		"the Mare response is parsed")
	payload = _utterance(classifier.calls[-1])
	check((payload.get("option", {}) as Dictionary).get("pose") == CATALOG.STANDING,
		"the Mare response payload carries the option")

	got.clear()
	classifier.reply = "not json"
	check(bridge.reason(request, "negotiation:response:2", func(reply) -> void:
		got.append(reply)), "a malformed reply still completes the call")
	classifier.answer()
	check(got.size() == 1 and got[0].failed, "a malformed reply is a failed answer")

	classifier.can_answer = false
	check(not bridge.classify(request, "negotiation:response:3", func(_reply) -> void: pass),
		"an unavailable model refuses the call")
	classifier.can_answer = true
	var unknown := PROMPTS.Request.new()
	unknown.kind = "nonsense"
	check(not bridge.classify(unknown, "negotiation:nonsense:1", func(_reply) -> void: pass),
		"an unknown request kind is refused")
	_free_service(made)


func _utterance(row: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(row.get("utterance", "")))
	return parsed if parsed is Dictionary else {}


## The Context facts the service's reasoning reads come from the service's own bridge.
func _check_context_facts() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var bridge: HOST = service.get("_bridge")
	var pony: FakePony = made["pony"]
	var facts: Dictionary = bridge.context_facts(pony)
	check(bool(facts.get("willingness", false)), "the facts carry the willingness")
	check(bool(facts.get("heat", false)), "the facts carry heat")
	check(bool(facts.get("private", false)), "the facts carry the live privacy")
	check(str(facts.get("mood", "")) == "warm", "the facts carry the world-context mood")
	check(not str(facts.get("relation_note", "")).is_empty(),
		"the facts carry the relationship note")
	check(bridge.context_facts(null).is_empty(), "a missing mare has no facts")
	_free_service(made)


## The watch is armed only while no act and no negotiation own the frame.
func _check_watch() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var voice: FakeVoice = made["voice"]
	service.tick(0.0)
	service.tick(0.0)
	check(voice.watched == 1, "an unlocked negotiation arms the watch once")
	(made["owner"] as ACT_OWNER).set_active(runtime)
	service.tick(0.0)
	check(voice.unwatched == 1, "a live act disarms the watch")
	(made["owner"] as ACT_OWNER).clear_active(runtime)
	service.on_world(null)
	service.tick(0.0)
	check(voice.watched == 2, "a new world arms the watch again")
	_free_service(made)


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
	var voice: FakeVoice = made["voice"]
	var pony: FakePony = made["pony"]
	pony.set_meta("relationship_id", "rarity")
	service.call("_react_line", pony, AGREEMENT.REASON_COUNTER_OFFER)
	check(voice.queued.size() == 1, "the counter-offer queues one line")
	var row: Dictionary = voice.queued[0]
	check(str(row["purpose"]).begins_with("Anon just offered sex"),
		"the counter-offer asks for a place or timing decline")
	check(str(row["key"]).begins_with("unfplap:negotiation:react:"),
		"the react key keeps its stable prefix")
	check(str(row["id"]) == "rarity", "the line is queued for the mare")
	service.call("_react_line", pony, AGREEMENT.REASON_PRIVACY)
	check(str(voice.queued[1]["purpose"]).begins_with("The moment was interrupted"),
		"a privacy loss lets the moment go")
	service.call("_react_line", pony, "")
	check(str(voice.queued[2]["purpose"]).begins_with("The offer ended"),
		"every other close is the generic release")
	check(voice.queued[0]["key"] != voice.queued[1]["key"], "each line has its own key")
	service.call("_react_line", null, "")
	check(voice.queued.size() == 3, "a missing mare queues nothing")
	_free_service(made)


## The terminal outcome reaches the Proactive pacing through its one handoff.
func _check_outcome_routing() -> void:
	var made := _service_fixture()
	var service: NEGOTIATION = made["service"]
	var initiation: FakeInitiation = made["initiation"]
	var terminal := NEGOTIATION.Terminal.new()
	terminal.pony_id = "rarity"
	terminal.reason = AGREEMENT.REASON_COUNTER_OFFER
	terminal.cooldown_s = 0.0
	service.call("_on_outcome_terminal", terminal)
	check(initiation.outcomes.size() == 1, "the outcome reaches the Proactive")
	var lower := NEGOTIATION.Terminal.new()
	lower.pony_id = "rarity"
	lower.reason = "privacy"
	lower.cooldown_s = 0.0
	service.call("_on_outcome_terminal", lower)
	check(initiation.outcomes.size() == 2
		and str(initiation.outcomes[1].reason) == "privacy", "the reason is kept")
	service.call("_on_outcome_terminal", null)
	check(initiation.outcomes.size() == 2, "a missing terminal changes nothing")
	_free_service(made)
