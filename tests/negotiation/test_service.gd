extends SceneTree
## The Negotiation service through its public API with a fake host: the Anon offer and its
## captured options, the live placement re-check, the Anon decision, the Mare response, the lock,
## the hold, privacy, the TTL, the Agreement handle and the terminal outcomes. No live scene and no
## model.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/negotiation/test_service.gd

const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


class FakePony extends Node3D:
	var sleeping := false
	var identity := {"id": "rarity"}

	func _init() -> void:
		name = "Rarity"


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0


class FakeHold extends RefCounted:
	var token := ""
	var nav_old_wander := true
	var negotiation := false
	var affection_owned := false
	var claimed := false
	var claim_ok := true
	var target_ok := true
	var transfer_count := 0
	var release_count := 0
	var attention_count := 0

	func claim_attention() -> bool:
		attention_count += 1
		token = ""
		negotiation = true
		claimed = false
		return true

	func claim_negotiation(id: String) -> bool:
		if not claim_ok:
			return false
		token = "unfplap:negotiation:" + id
		negotiation = true
		claimed = true
		return true

	func transfer_nav(existing: String, wander: bool) -> bool:
		transfer_count += 1
		if not claim_ok:
			return false
		token = existing
		nav_old_wander = wander
		negotiation = true
		claimed = true
		return true

	func holds_negotiation() -> bool:
		return negotiation

	func hold_affection() -> bool:
		affection_owned = true
		return true

	func keep_nav() -> void:
		pass

	func keep_target() -> bool:
		return target_ok

	func accepts_hold(_pose: String, _source: String) -> bool:
		return affection_owned and (token.is_empty() or claimed)

	func release_nav() -> void:
		claimed = false
		negotiation = false
		token = ""

	func release_negotiation() -> void:
		release_count += 1
		affection_owned = false
		release_nav()


class Boxes:
	var clock := 100.0
	var eligible := true
	var relationship := true
	var privacy := true
	var place_ok := true
	var scene_ready := true
	var scene_ready_calls := 0
	var classify_mode := "sync"
	var reason_mode := "sync"
	var await_mode := "sync"
	var classify_decision = null
	var reason_decision = null
	var classify_done := Callable()
	var reason_done := Callable()
	var answer_done := Callable()
	var kinds: Array[String] = []
	var scopes: Array[String] = []
	var cancelled: Array[String] = []
	var outcomes: Array = []
	var agreements: Array = []
	var reactions: Array = []
	var toasts: Array[String] = []
	var hold: FakeHold
	var placement: POSE_OPTIONS.Placement
	var placed: Array = []
	var form_view = null
	var context_facts: Dictionary = {"willingness": true}


func _fixture() -> Dictionary:
	var boxes := Boxes.new()
	var pony := FakePony.new()
	var runtime := FakeRuntime.new()
	runtime.pony = pony
	boxes.hold = FakeHold.new()
	boxes.placement = POSE_OPTIONS.Placement.new()
	boxes.placement.standing_free = true
	boxes.form_view = NEGOTIATION.FormView.new()
	var host := NEGOTIATION.Host.new()
	host.now = func() -> float: return boxes.clock
	host.eligible = func(_target: Node) -> bool: return boxes.eligible
	host.relationship_ok = func(_target: Node) -> bool: return boxes.relationship
	host.context_facts = func(_target: Node) -> Dictionary: return boxes.context_facts
	host.privacy_private = func(_target: Node, _cuddle: bool) -> bool: return boxes.privacy
	host.placement_for = func(_target: Node): return boxes.placement
	host.pose_placed = func(_target: Node, option) -> bool:
		boxes.placed.append(option)
		return boxes.place_ok
	host.scene_ready = func(_target: Node, _option, _profile_ok: bool, _source_ok: bool) -> bool:
		boxes.scene_ready_calls += 1
		return boxes.scene_ready
	host.form_view = func(): return boxes.form_view
	host.hold_for = func(_target: Node): return boxes.hold
	host.classify = func(request, scope, done) -> bool:
		boxes.kinds.append(str(request.kind))
		boxes.scopes.append(str(scope))
		if boxes.classify_mode == "unavailable":
			return false
		boxes.classify_done = done
		if boxes.classify_mode == "sync":
			done.call(boxes.classify_decision)
		return true
	host.reason = func(request, scope, done) -> bool:
		boxes.kinds.append(str(request.kind))
		boxes.scopes.append(str(scope))
		if boxes.reason_mode == "unavailable":
			return false
		boxes.reason_done = done
		if boxes.reason_mode == "sync":
			done.call(boxes.reason_decision)
		return true
	host.await_answer = func(_offer, _scope, done) -> bool:
		boxes.answer_done = done
		if boxes.await_mode == "unavailable":
			return false
		if boxes.await_mode == "sync":
			done.call("yes", "")
		return true
	host.cancel_scope = func(scope) -> void: boxes.cancelled.append(str(scope))
	host.toast = func(text) -> void: boxes.toasts.append(str(text))
	host.react = func(pony_node, reason) -> void: boxes.reactions.append([pony_node, reason])
	host.on_outcome = func(terminal) -> void: boxes.outcomes.append(terminal)
	host.on_agreement = func(handle) -> void: boxes.agreements.append(handle)
	var service := NEGOTIATION.new()
	service.setup(host)
	root.add_child(runtime)
	return {"service": service, "boxes": boxes, "host": host, "runtime": runtime, "pony": pony}


func _decision(answer: String, index := -1, failed := false, out_of_range := false):
	var out := PROMPTS.Reply.new()
	out.answer = answer
	out.option_index = index
	out.failed = failed
	out.out_of_range = out_of_range
	return out


func _standing_option() -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = CATALOG.STANDING
	return out


func _cuddle_option(bed: Node3D) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = CATALOG.MISSIONARY
	out.source = "bed_side"
	out.bed = bed
	out.cuddle = true
	return out


func _mare_offer(made: Dictionary, option: POSE_OPTIONS.Option, private := true, cuddle := false):
	var offer := NEGOTIATION.MareOffer.new()
	offer.runtime = made["runtime"]
	offer.pony = made["pony"]
	offer.option = option
	offer.base = CLEARANCE.evaluate(true, true, true)
	offer.private = private
	offer.hold_token = "unfplap:request:rarity"
	offer.hold_old_wander = true
	offer.line = "come here"
	offer.cuddle = cuddle
	return offer


func _outcome_kinds(boxes: Boxes) -> Array:
	var out: Array = []
	for terminal in boxes.outcomes:
		out.append(terminal.outcome)
	return out


func _free(made: Dictionary) -> void:
	var runtime: Node = made["runtime"]
	var pony: Node = made["pony"]
	var service: Node = made["service"]
	root.remove_child(runtime)
	runtime.free()
	pony.free()
	service.free()


func _accept_anon(made: Dictionary) -> void:
	var boxes: Boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("accept")
	made["service"].begin_anon_offer(made["runtime"], "want to?")


func run() -> void:
	_check_anon_accept()
	_check_anon_failures()
	_check_capture_and_placement()
	_check_anon_cuddle()
	_check_mare_cuddle()
	_check_mare_offer()
	_check_mare_response()
	_check_privacy()
	_check_hold_loss()
	_check_report_and_cancel()
	_check_lock()
	_check_ready_offer()
	print("NEGOTIATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_anon_accept() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var service = made["service"]
	var runtime = made["runtime"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("accept")
	check(service.begin_anon_offer(runtime, "want to?"), "an Anon offer starts")
	check(boxes.kinds == ["anon_offer", "mare_response"], "the classifier then the reasoning run")
	check(service.phase() == NEGOTIATION.Phase.AGREEMENT, "an accept forms the Agreement")
	check(service.is_locked(), "the Agreement keeps the global lock")
	check(boxes.outcomes.size() == 1 and boxes.outcomes[0].outcome == NEGOTIATION.Outcome.ACCEPTED,
		"an accept reports Accepted")
	check(boxes.outcomes[0].cooldown_s == NEGOTIATION.COOLDOWN_S,
		"an acceptance writes the offer cooldown")
	var handle = service.handle()
	check(handle != null and handle.valid(), "the Agreement handle is valid")
	check(handle.pony == made["pony"], "the handle names the mare")
	check(handle.option.pose == CATALOG.STANDING, "the handle carries the chosen option")
	check(handle.private, "the private context forms a private Agreement")
	check(handle.pose_profile_ok and handle.pose_source_ok, "the pose capability is frozen")
	check(handle.trigger == AGREEMENT.Trigger.ANON_OFFER, "the handle names the Anon route")
	var package = service.agreement()
	check(package.context.willingness, "the Agreement carries the Context")
	check(package.answer == "accept", "the Agreement carries the answer")
	check(package.clearance.ok(), "the Agreement carries the frozen clearance")
	check(package.offer_line == "want to?", "the Agreement carries the offer line")
	check(boxes.agreements.size() == 1 and boxes.agreements[0] == handle,
		"the Agreement is handed to main")
	check(boxes.hold.release_count == 0, "the live Agreement keeps the hold")
	check(service.hotkey_handle(runtime, _standing_option()) == handle,
		"the exact hotkey option matches the Agreement")
	var other := POSE_OPTIONS.Option.new()
	other.pose = CATALOG.STANDING
	other.cuddle = true
	check(service.hotkey_handle(runtime, other) == null,
		"a different option does not match the Agreement")
	boxes.clock = 221.0
	service.tick(0.0)
	check(_outcome_kinds(boxes).has(NEGOTIATION.Outcome.EXPIRED), "the Agreement TTL expires")
	check(not service.is_locked(), "an expiry releases the lock")
	check(not service.report(handle, true), "a stale handle after expiry is ignored")
	_free(made)


## The live Agreement's readiness: the scene and privacy answer live, and no flag is kept.
func _check_ready_offer() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var service = made["service"]
	check(not service.ready_offer(), "no live Agreement is never ready")
	_accept_anon(made)
	check(service.ready_offer(), "a formed Agreement is ready")
	check(boxes.scene_ready_calls == 1, "the ready path asks the scene once")
	boxes.scene_ready = false
	check(not service.ready_offer(), "a changed scene is not ready")
	check(boxes.scene_ready_calls == 2, "the failed scene was still asked")
	boxes.scene_ready = true
	boxes.privacy = false
	check(not service.ready_offer(), "a lost private view is not ready")
	boxes.privacy = true
	check(service.ready_offer(), "the recovered scene and privacy are ready again")
	boxes.clock += AGREEMENT.AGREEMENT_TTL_S
	var calls: int = boxes.scene_ready_calls
	check(not service.ready_offer() and boxes.scene_ready_calls == calls,
		"an expired Agreement is not ready and asks no scene")
	_free(made)


func _check_anon_failures() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var service = made["service"]
	var runtime = made["runtime"]
	boxes.eligible = false
	check(not service.begin_anon_offer(runtime, "want to?"), "an ineligible mare makes no offer")
	check(_outcome_kinds(boxes).has(NEGOTIATION.Outcome.NO_OFFER), "the failure is NoOffer")
	check(boxes.outcomes[0].reason == "eligibility", "the clearance reason is named")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.relationship = false
	service = made["service"]
	runtime = made["runtime"]
	check(not service.begin_anon_offer(runtime, "want to?"), "a failed relationship makes no offer")
	check(boxes.outcomes[0].reason == "relationship", "the relationship reason is named")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.placement.standing_free = false
	service = made["service"]
	runtime = made["runtime"]
	check(not service.begin_anon_offer(runtime, "want to?"), "no placement makes no offer")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_NO_CONTEXT_POSE,
		"the empty option list is named")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_mode = "unavailable"
	service = made["service"]
	runtime = made["runtime"]
	check(not service.begin_anon_offer(runtime, "want to?"), "an unavailable classifier makes no offer")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE,
		"the classifier failure is named")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("no_offer")
	service = made["service"]
	runtime = made["runtime"]
	check(service.begin_anon_offer(runtime, "nice weather"), "the attempt starts")
	check(service.phase() == NEGOTIATION.Phase.NONE, "an unclear line forms no offer")
	check(boxes.outcomes.is_empty(), "a normal line reports no terminal outcome")
	check(boxes.toasts.is_empty(), "a normal line has no toast")
	check(not service.is_locked(), "a normal line releases the lock")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0, false, true)
	service = made["service"]
	runtime = made["runtime"]
	service.begin_anon_offer(runtime, "want to?")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_NO_CONTEXT_POSE,
		"an out-of-range marker is NoOffer")
	check(not boxes.toasts.is_empty(), "an out-of-range option is feedback, not silence")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 5)
	service = made["service"]
	runtime = made["runtime"]
	service.begin_anon_offer(runtime, "want to?")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_NO_CONTEXT_POSE,
		"an out-of-list option is NoOffer")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.hold.claim_ok = false
	_accept_anon(made)
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.OCCUPIED, "a failed hold is Occupied")
	check(not made["service"].is_locked(), "Occupied releases the lock")
	_free(made)


func _check_capture_and_placement() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var bed := Node3D.new()
	root.add_child(bed)
	# The classifier request captures the standing-only list; the placement changes to a cuddle
	# while the reply is in flight. The captured list decides the option.
	boxes.classify_mode = "async"
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("accept")
	var service = made["service"]
	check(service.begin_anon_offer(made["runtime"], "want to?"), "the async Anon offer starts")
	boxes.placement.standing_free = false
	boxes.placement.cuddle = true
	boxes.placement.cuddle_bed = bed
	boxes.classify_done.call(boxes.classify_decision)
	check(boxes.placed.size() == 1 and boxes.placed[0].pose == CATALOG.STANDING,
		"the reply indexes the options captured at request time")
	check(boxes.agreements.size() == 1, "the captured option still forms the Agreement")
	root.remove_child(bed)
	bed.free()
	_free(made)

	# The Anon route checks placement after the classifier and before the hold claim.
	made = _fixture()
	boxes = made["boxes"]
	boxes.place_ok = false
	boxes.classify_decision = _decision("accept", 0)
	service = made["service"]
	check(service.begin_anon_offer(made["runtime"], "want to?"), "the offer attempt starts")
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.INTERRUPTED,
		"a moved placement interrupts the Anon route")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_POSE, "the placement failure is pose")
	check(boxes.agreements.is_empty(), "a placement failure forms no Agreement")
	check(boxes.hold.release_count == 0, "the Anon route has not claimed the hold yet")
	_free(made)

	# The Mare route checks placement after Anon's answer and before the Agreement forms.
	made = _fixture()
	boxes = made["boxes"]
	boxes.place_ok = false
	boxes.classify_decision = _decision("accept")
	var offer = _mare_offer(made, _standing_option())
	service = made["service"]
	check(service.begin_mare_offer(offer), "the Mare offer starts the exchange")
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.INTERRUPTED,
		"a moved placement interrupts the Mare route")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_POSE,
		"the Mare placement failure is pose")
	check(boxes.agreements.is_empty(), "the Mare placement failure forms no Agreement")
	check(boxes.hold.release_count == 1, "the Mare placement failure releases the hold")
	_free(made)


func _check_mare_cuddle() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var service = made["service"]
	var bed := Node3D.new()
	root.add_child(bed)
	var offer = _mare_offer(made, _cuddle_option(bed), true, true)
	offer.hold_token = ""
	boxes.classify_decision = _decision("accept")
	check(service.begin_mare_offer(offer), "a cuddle Mare offer starts")
	check(boxes.hold.attention_count == 1, "the cuddle offer takes the attention hold")
	check(boxes.hold.transfer_count == 0, "the cuddle offer transfers no lease")
	check(service.handle().option.cuddle, "the cuddle option is kept")
	check(service.phase() == NEGOTIATION.Phase.AGREEMENT, "the cuddle Agreement forms")
	root.remove_child(bed)
	bed.free()
	_free(made)


func _check_anon_cuddle() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var bed := Node3D.new()
	root.add_child(bed)
	boxes.placement.cuddle = true
	boxes.placement.cuddle_bed = bed
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("accept")
	check(made["service"].begin_anon_offer(made["runtime"], "cuddle?"),
		"an Anon cuddle offer starts")
	check(boxes.hold.attention_count == 1, "the Anon cuddle offer takes the attention hold")
	check(made["service"].handle().option.cuddle, "the Anon cuddle option forms the Agreement")
	root.remove_child(bed)
	bed.free()
	_free(made)


func _check_mare_offer() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	var service = made["service"]
	var offer = _mare_offer(made, _standing_option())
	boxes.classify_decision = _decision("accept")
	check(service.begin_mare_offer(offer), "a formed Mare offer starts the exchange")
	check(boxes.hold.transfer_count == 1, "the request lease is transferred")
	check(service.phase() == NEGOTIATION.Phase.AGREEMENT, "the Anon accept forms the Agreement")
	check(service.handle().trigger == AGREEMENT.Trigger.MARE_OFFER, "the route is the Mare offer")
	check(service.handle().hold_token == "unfplap:request:rarity",
		"the Agreement keeps the request token")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.classify_decision = _decision("refuse")
	service.begin_mare_offer(offer)
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.REFUSED, "a refusal is Refused")
	check(boxes.outcomes[0].cooldown_s == NEGOTIATION.COOLDOWN_S,
		"a plain decline writes the cooldown")
	check(boxes.reactions.is_empty(), "a plain decline queues no extra line")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.classify_decision = _decision("counter_offer")
	service.begin_mare_offer(offer)
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_COUNTER_OFFER,
		"a counter-offer is a refusal reason")
	check(boxes.outcomes[0].cooldown_s == 0.0, "a counter-offer writes no cooldown")
	check(boxes.reactions.size() == 1
		and boxes.reactions[0][1] == AGREEMENT.REASON_COUNTER_OFFER,
		"a counter-offer queues one reaction line")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.classify_decision = _decision("maybe")
	service.begin_mare_offer(offer)
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.REFUSED,
		"an ambiguous Anon line is a refusal")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.classify_mode = "unavailable"
	service.begin_mare_offer(offer)
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE,
		"an unavailable Anon classifier is a refusal")
	check(boxes.outcomes[0].cooldown_s == 0.0, "a classifier failure writes no cooldown")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.await_mode = "unavailable"
	check(not service.begin_mare_offer(offer), "an unavailable answer watch makes no negotiation")
	check(boxes.hold.release_count == 1, "a failed watch releases the transferred hold")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	service = made["service"]
	offer = _mare_offer(made, _standing_option())
	boxes.hold.claim_ok = false
	check(not service.begin_mare_offer(offer), "a failed transfer makes no negotiation")
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.OCCUPIED, "a failed transfer is Occupied")
	check(boxes.hold.release_count == 0, "a failed transfer leaves the request hold alone")
	_free(made)


func _check_mare_response() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("refuse")
	made["service"].begin_anon_offer(made["runtime"], "want to?")
	check(boxes.outcomes[0].outcome == NEGOTIATION.Outcome.REFUSED, "the Mare can refuse")
	check(boxes.outcomes[0].cooldown_s == NEGOTIATION.COOLDOWN_S, "a Mare decline writes the cooldown")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("counter_offer")
	made["service"].begin_anon_offer(made["runtime"], "want to?")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_COUNTER_OFFER, "the Mare can counter-offer")
	check(boxes.outcomes[0].cooldown_s == 0.0, "a Mare counter-offer writes no cooldown")
	check(boxes.reactions.size() == 1
		and boxes.reactions[0][1] == AGREEMENT.REASON_COUNTER_OFFER,
		"the Mare counter-offer queues one reaction line")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_decision = _decision("accept", -1, true)
	made["service"].begin_anon_offer(made["runtime"], "want to?")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_REASONING_FAILED,
		"a reasoning failure is a refusal")
	check(boxes.outcomes[0].cooldown_s == 0.0, "a reasoning failure writes no cooldown")
	check(boxes.hold.release_count == 1, "a refused reasoning releases the hold")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_decision = _decision("accept", 0)
	boxes.reason_mode = "unavailable"
	made["service"].begin_anon_offer(made["runtime"], "want to?")
	check(boxes.outcomes[0].reason == AGREEMENT.REASON_REASONING_FAILED,
		"an unavailable reasoning is a refusal")
	_free(made)


func _check_privacy() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	_accept_anon(made)
	var service = made["service"]
	check(service.agreement().private, "the private context forms a private Agreement")
	boxes.privacy = false
	service.tick(0.5)
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.INTERRUPTED,
		"privacy loss ends a private Agreement")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_PRIVACY, "the reason is privacy")
	check(boxes.reactions.size() == 1, "the interruption queues the shared reaction line")
	check(boxes.hold.release_count == 1, "privacy loss releases the hold")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.privacy = false
	_accept_anon(made)
	service = made["service"]
	check(not service.agreement().private, "a public context forms a public Agreement")
	service.tick(0.5)
	check(service.phase() == NEGOTIATION.Phase.AGREEMENT, "a public Agreement ignores privacy")
	boxes.clock = 221.0
	service.tick(0.0)
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.EXPIRED,
		"a public Agreement still expires")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_mode = "async"
	var service2 = made["service"]
	var offer = _mare_offer(made, _standing_option())
	check(service2.begin_mare_offer(offer), "the Mare offer waits for the answer")
	boxes.privacy = false
	service2.tick(0.5)
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.INTERRUPTED,
		"privacy loss ends a private negotiation")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_PRIVACY, "the negotiation loss is privacy")
	_free(made)


func _check_hold_loss() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	_accept_anon(made)
	boxes.hold.target_ok = false
	made["service"].tick(0.0)
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.INTERRUPTED,
		"a reassigned conversation target interrupts")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_TARGET_LEFT, "the reason is target_left")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_mode = "async"
	var service = made["service"]
	service.begin_anon_offer(made["runtime"], "want to?")
	boxes.hold.target_ok = false
	service.tick(0.0)
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_TARGET_LEFT,
		"the unclaimed offer still keeps attention")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	_accept_anon(made)
	boxes.hold.affection_owned = false
	made["service"].tick(0.0)
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_TARGET_LEFT,
		"a lost affection hold is target_left")
	_free(made)


func _check_report_and_cancel() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	_accept_anon(made)
	var service = made["service"]
	var handle = service.handle()
	check(service.report(handle, true), "Started is accepted")
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.STARTED, "Started is reported")
	check(boxes.hold.release_count == 0, "Started leaves the adopted hold to the act")
	check(not service.is_locked(), "Started releases the lock")
	check(not service.report(handle, false), "a closed Agreement ignores a later report")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	_accept_anon(made)
	service = made["service"]
	handle = service.handle()
	check(service.report(handle, false), "StartFailed is accepted")
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.START_FAILED, "StartFailed is reported")
	check(boxes.hold.release_count == 1, "StartFailed releases the hold")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	_accept_anon(made)
	service = made["service"]
	handle = service.handle()
	check(service.cancel(handle, "hotkey"), "the hotkey cancels the Agreement")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_HOTKEY, "the cancel reason is kept")
	check(not service.cancel(handle, "hotkey"), "a stale cancel is ignored")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	_accept_anon(made)
	service = made["service"]
	handle = service.handle()
	check(handle.cancel.call("privacy"), "the handle's one cancel callback closes the Agreement")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_PRIVACY, "the handle reason is kept")
	check(boxes.reactions.size() == 1, "the handle privacy loss queues a line")
	_free(made)

	made = _fixture()
	boxes = made["boxes"]
	boxes.classify_mode = "async"
	service = made["service"]
	service.begin_anon_offer(made["runtime"], "want to?")
	check(service.interrupt_for_hotkey(), "the hotkey breaks a live negotiation")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_HOTKEY, "the negotiation break is hotkey")
	_free(made)


func _check_lock() -> void:
	var made := _fixture()
	var boxes: Boxes = made["boxes"]
	boxes.classify_mode = "async"
	var service = made["service"]
	check(service.begin_anon_offer(made["runtime"], "first"), "the first offer starts")
	check(service.is_locked(), "the first offer owns the lock")
	check(not service.begin_anon_offer(made["runtime"], "second"), "a second Anon offer is blocked")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_LOCKED, "the block is the lock")
	check(not service.begin_mare_offer(_mare_offer(made, _standing_option())),
		"a Mare offer is blocked while the lock is live")
	check(boxes.outcomes[-1].reason == AGREEMENT.REASON_LOCKED, "the Mare block is the lock")
	check(boxes.outcomes.size() == 2, "the lock is reported once per attempt")
	boxes.clock = 221.0
	service.tick(0.0)
	check(boxes.outcomes[-1].outcome == NEGOTIATION.Outcome.EXPIRED, "the negotiation TTL expires")
	check(boxes.outcomes[-1].cooldown_s == 0.0, "an expiry writes no cooldown")
	var late: Callable = boxes.classify_done
	if late.is_valid():
		late.call(_decision("accept", 0))
	check(boxes.outcomes.size() == 3, "a late classifier result is ignored")
	_free(made)
