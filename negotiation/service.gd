extends Node
## Service: negotiation
## Contract: docs/negotiation.md
## Scope: world
## Import: negotiation/service.gd only
##
## The Act Negotiation: Anon offers, the Anon decision, the Mare response, pose re-checks,
## privacy sampling, Agreement formation and ownership, the one global lock and the terminal
## outcome. The service owns the whole negotiation and the Agreement window; the Act service
## receives an opaque handle and never mutates the package. `negotiation/host.gd` is the bridge to
## the live world and `negotiation/adapter.gd` the one director and model host: this file builds
## the typed `Host` from them and runs the exchange on it.

const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const HOST := preload("res://mods/unfplap/negotiation/host.gd")
const ADAPTER := preload("res://mods/unfplap/negotiation/adapter.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const POSE_PLACEMENT := preload("res://mods/unfplap/shared/pose_placement.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

enum Phase { NONE, OFFERED, AGREEMENT }
enum Outcome { ACCEPTED, REFUSED, EXPIRED, INTERRUPTED, START_FAILED, NO_OFFER, OCCUPIED, STARTED }

## The offer cooldown: only a plain decline or an acceptance.
const COOLDOWN_S := 120.0
## The privacy provider is sampled at the request-scan cadence, not per frame.
const PRIVACY_SAMPLE_S := 0.5

const ANSWER_ACCEPT := "accept"


## The player form and display the option builder filters on.
class FormView:
	var form := "human"
	var view := "desktop"


## The finalized proactive offer the Proactive service hands over at formation. It carries the
## already-decided base clearance, pose option, visibility and request hold.
class MareOffer:
	var runtime: Node = null
	var pony: Node3D = null
	var option: POSE_OPTIONS.Option = null
	var base: CLEARANCE.Result = null
	var private := false
	var hold_token := ""
	var hold_old_wander := true
	var line := ""
	var cuddle := false

	func valid() -> bool:
		return is_instance_valid(runtime) and is_instance_valid(pony) and option != null \
			and option.valid() and base != null and base.ok()


## The terminal outcome reported to the Proactive service and the debug log.
class Terminal:
	var pony: Node = null
	var pony_id := ""
	var outcome := 0
	var reason := ""
	var trigger := 0
	var cooldown_s := 0.0


## The host boundary. Every field is a named callback the service builds from its bridge and its
## model host; nothing outside this service assembles one, and the service never touches the
## runtime's private fields.
class Host:
	## Seconds. The service's one clock.
	var now: Callable
	## (pony) -> bool: the eligibility service's `eligible?` answer.
	var eligible: Callable
	## (pony) -> bool: the live relationship, romance and Promiscuity floor.
	var relationship_ok: Callable
	## (pony) -> Dictionary: the plain facts `shared/context.gd` builds from.
	var context_facts: Callable
	## (pony, cuddle) -> bool: the privacy provider's live predicate.
	var privacy_private: Callable
	## (runtime) -> PoseOptions.Placement: the plain placement facts.
	var placement_for: Callable
	## (runtime, PoseOptions.Option) -> bool: the live scene-only placement re-check before an
	## Agreement forms. A missing callback refuses.
	var pose_placed: Callable
	## () -> FormView: the player's live form and display.
	var form_view: Callable
	## (runtime) -> RefCounted: the per-pony `scene_hold/service.gd` ledger.
	var hold_for: Callable
	## (PROMPTS.Request, scope, done) -> bool: the dialogue classifier. `done` gets a
	## PROMPTS.Reply.
	var classify: Callable
	## (PROMPTS.Request, scope, done) -> bool: the Mare reasoning call.
	var reason: Callable
	## (pony, scope, done) -> bool: watch the first new line from the conversation target.
	var await_answer: Callable
	## (scope) -> void: cancel one classifier scope.
	var cancel_scope: Callable
	## (text) -> void.
	var toast: Callable
	## (text) -> void.
	var log: Callable
	## (pony, reason) -> void: the shared reaction line.
	var react: Callable
	## (Terminal) -> void.
	var on_outcome: Callable
	## (Handle) -> void: the Agreement is ready for the Act service.
	var on_agreement: Callable


## One live negotiation's private state. It is cleared when the Agreement forms.
class Offer:
	var id := 0
	var generation := 0
	var runtime: Node = null
	var pony: Node3D = null
	var pony_id := ""
	var option: POSE_OPTIONS.Option = null
	## The exact option list sent to the Anon classifier. The reply indexes this list, never a
	## recomputed one.
	var options: Array[POSE_OPTIONS.Option] = []
	var base: CLEARANCE.Result = null
	var context: CONTEXT.Context = null
	var private := false
	var trigger := 0
	var hold_token := ""
	var hold_old_wander := true
	var hold_claimed := false
	var scope := ""
	var line := ""
	var cuddle := false
	var expires_at := 0.0

var _host: Host
var _bridge: HOST = null
var _adapter: ADAPTER = null
var _phase := Phase.NONE
var _locked := false
var _offer: Offer = null
var _agreement: AGREEMENT.Package = null
var _handle: AGREEMENT.Handle = null
var _generation := 0
var _serial := 0
var _deadline := 0.0
var _privacy_clock := 0.0

## The services the bridge reads, bound once by the entry. `eligibility` is rebuilt on every world
## enter, so the entry rebinds it there and calls `on_world()`; `initiation` and `offer` are plain
## nodes because each of them preloads this facade.
var eligibility: ELIGIBILITY = null
var memory: MEMORY = null
var privacy: PRIVACY = null
var initiation: Node = null
var offer: Node = null


## The entry's one call: the services the bridge reads. The adapter and the bridge are built here
## and nowhere else, so the entry never assembles a `Host`.
func bind(eligibility_service: ELIGIBILITY, memory_service: MEMORY, privacy_service: PRIVACY,
		initiation_service: Node, offer_service: Node) -> void:
	eligibility = eligibility_service
	memory = memory_service
	privacy = privacy_service
	initiation = initiation_service
	offer = offer_service
	if not is_instance_valid(_adapter):
		_adapter = ADAPTER.new()
		_adapter.name = "UnfplapNegotiationAdapter"
		_adapter.classifier_source = Callable(self, "_classifier")
		add_child(_adapter)
	if _bridge == null:
		_bridge = HOST.new()
	_bridge.service = self
	_bridge.adapter = _adapter
	_bridge.eligibility = eligibility
	_bridge.memory = memory
	_bridge.privacy = privacy
	_bridge.initiation = initiation
	_bridge.offer = offer
	_bind_host()


## The adapter is this service's; the Proactive service and the model calls reach it here.
func adapter() -> Node:
	return _adapter if is_instance_valid(_adapter) else null


## A world started: the close of the world that is gone comes first, then the bridge is bound to
## the new one and its Anon-offer watch is armed.
func on_world(_host: Node) -> void:
	on_world_closed()
	if _bridge == null:
		return
	_bridge.eligibility = eligibility
	_bind_host()
	_bridge.disarm()


## Build the typed host from the bridge. Every model callback is the one adapter; every world read
## is the bridge or the form view below.
func _bind_host() -> void:
	if _bridge == null:
		return
	var host := Host.new()
	host.now = Callable(_bridge, "now")
	host.eligible = Callable(_bridge, "eligible")
	host.relationship_ok = Callable(_bridge, "relationship_ok")
	host.context_facts = Callable(_bridge, "context_facts")
	host.privacy_private = Callable(_bridge, "privacy_private")
	host.placement_for = Callable(_bridge, "placement_for")
	host.pose_placed = Callable(_bridge, "pose_placed")
	host.form_view = Callable(self, "_form_view")
	host.hold_for = Callable(_bridge, "hold_for")
	host.classify = Callable(_bridge, "classify")
	host.reason = Callable(_bridge, "reason")
	host.await_answer = Callable(_bridge, "await_answer")
	host.cancel_scope = Callable(_bridge, "cancel_scope")
	host.toast = Callable(_bridge, "toast")
	host.log = Callable(_bridge, "log")
	host.react = Callable(self, "_react_line")
	host.on_outcome = Callable(self, "_on_outcome_terminal")
	host.on_agreement = Callable(self, "_on_agreement_handle")
	_host = host


## The classifier is the Proactive service's; this side only calls it.
func _classifier() -> Node:
	if not is_instance_valid(initiation) or not initiation.has_method("classifier_node"):
		return null
	var node: Variant = initiation.call("classifier_node")
	return node as Node if is_instance_valid(node) else null


func setup(host: Host) -> void:
	_host = host


## A world enter or a world close. It releases the hold and cancels every classifier scope; a
## close reports no terminal outcome.
func on_world_closed() -> void:
	_cancel_scope(_offer.scope if _offer != null else "")
	_cancel_scope(_agreement.classifier_scope if _agreement != null else "")
	_release_hold()
	_clear_state()
	_host = null



func phase() -> Phase:
	return _phase


func is_locked() -> bool:
	return _locked


## The live Agreement handle, or null. The offer service reads it immediately.
func handle() -> AGREEMENT.Handle:
	return _handle if _phase == Phase.AGREEMENT else null


## The live Agreement package for the debug row. Consumers do not mutate it.
func agreement() -> AGREEMENT.Package:
	return _agreement if _phase == Phase.AGREEMENT else null


## The entry's idle frame: the TTL and the privacy sample, then the bridge's global watch. The
## watch keeps its own perf chunk, so a stalled watch stays visible next to the exchange.
func tick(delta: float) -> void:
	_tick_offer(delta)
	var timed := LOG.idle_on()
	var started := Time.get_ticks_usec() if timed else 0
	if _bridge != null:
		_bridge.tick_watch()
	if timed:
		LOG.close("entry_watch", started)


func _tick_offer(delta: float) -> void:
	if _host == null or _phase == Phase.NONE:
		return
	if _now() >= _deadline:
		_close(Outcome.EXPIRED, "", 0.0)
		return
	if not _keep_hold():
		return
	var private := _offer.private if _phase == Phase.OFFERED else _agreement.private
	if not private:
		return
	_privacy_clock += delta
	if _privacy_clock < PRIVACY_SAMPLE_S:
		return
	_privacy_clock = 0.0
	var pony: Node = _pony()
	if not is_instance_valid(pony) or not _private_now(pony, _cuddle_flag()):
		_log_line("negotiation privacy lost id=%s" % _pony_id(pony))
		_close(Outcome.INTERRUPTED, AGREEMENT.REASON_PRIVACY, 0.0, true)


## The Proactive service's handoff: a formed Mare offer. The service owns the exchange from here;
## the Anon decision is the first new line from the conversation target.
func begin_mare_offer(offer: MareOffer) -> bool:
	if _host == null or offer == null or not offer.valid():
		return false
	if _locked:
		_blocked(offer.pony)
		return false
	var live := Offer.new()
	_begin_state(live, offer.runtime, offer.pony, offer.option, AGREEMENT.Trigger.MARE_OFFER,
		offer.line, offer.cuddle)
	live.base = offer.base
	live.private = offer.private
	if not _claim_mare_hold(live, offer):
		_log_line("negotiation hold claim id=%s trigger=mare result=false" % live.pony_id)
		_close(Outcome.OCCUPIED, AGREEMENT.REASON_OCCUPIED, 0.0)
		return false
	_log_line("negotiation hold claim id=%s trigger=mare result=true token=%s" % [
		live.pony_id, live.hold_token])
	live.context = _context(live.pony)
	var scope := _scope("answer")
	live.scope = scope
	var watching := bool(_host.await_answer.call(live.pony, scope,
		func(text: String, error: String) -> void: _on_anon_answer(live, text, error)))
	if not watching:
		_close(Outcome.REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return false
	_log_line("negotiation offer id=%s trigger=mare pose=%s private=%s" % [
		live.pony_id, live.option.key(), str(live.private)])
	return true


## An Anon offer, classified from his line. The target runtime is the one the watch resolved.
func begin_anon_offer(runtime: Node, text: String) -> bool:
	if _host == null or not is_instance_valid(runtime):
		return false
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		return false
	if _locked:
		_blocked(pony as Node)
		return false
	var base := _clearance_for(runtime)
	if not base.ok():
		_formation_failure(pony, Outcome.NO_OFFER, base.reason(), AGREEMENT.Trigger.ANON_OFFER)
		return false
	var options := _options_for(runtime)
	if options.is_empty():
		_formation_failure(pony, Outcome.NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE,
			AGREEMENT.Trigger.ANON_OFFER)
		return false
	var live := Offer.new()
	_begin_state(live, runtime, pony, null, AGREEMENT.Trigger.ANON_OFFER, text, false)
	live.base = base
	live.options = options
	live.context = _context(live.pony)
	_log_line("negotiation classify start id=%s text_len=%d options=%d" % [
		live.pony_id, text.length(), options.size()])
	var scope := _scope("anon_offer")
	live.scope = scope
	var request := PROMPTS.Request.new()
	request.kind = "anon_offer"
	request.text = text
	request.context = live.context
	request.options = options
	var started := bool(_host.classify.call(request, scope,
		func(reply: PROMPTS.Reply) -> void: _on_anon_offer_classified(live, reply)))
	if not started:
		_close(Outcome.NO_OFFER, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return false
	return true


## The offer service reports the Act service's start result. Started closes the Agreement without
## releasing the adopted hold; StartFailed clears it and releases the hold.
func report(handle: AGREEMENT.Handle, started: bool) -> bool:
	if handle == null or not _agreement_matches(handle):
		return false
	var package := _agreement
	if started:
		_clear_state()
		_report_outcome(package.pony, Outcome.STARTED, "", package.trigger, 0.0)
		_log_line("negotiation started id=%d state=none" % package.id)
	else:
		_close(Outcome.START_FAILED, "", 0.0)
	return true


## The Act service's one cancel callback. A stale handle is ignored.
func cancel(handle: AGREEMENT.Handle, reason: String) -> bool:
	if handle == null or not _agreement_matches(handle):
		return false
	var live_reason := _interrupt_reason(reason)
	_close(Outcome.INTERRUPTED, live_reason, 0.0, live_reason == AGREEMENT.REASON_PRIVACY)
	return true


## The hotkey's exact match: the same mare and the exact pose option. A live Agreement with any
## other mare, pose, source or bed is not a match.
func hotkey_handle(runtime: Node, option: POSE_OPTIONS.Option) -> AGREEMENT.Handle:
	if _phase != Phase.AGREEMENT or _agreement == null or _host == null:
		return null
	if not is_instance_valid(runtime) or _agreement.runtime != runtime:
		return null
	if not _agreement.matches(_agreement.pony, option):
		return null
	_log_line("negotiation hotkey match id=%s" % _agreement.pony_id)
	return _handle


## The hotkey breaks any live Act Negotiation. It logs the interruption and returns whether one
## was ended.
func interrupt_for_hotkey() -> bool:
	if _phase == Phase.NONE:
		return false
	_log_line("negotiation hotkey interrupt id=%s" % _pony_id(_pony()))
	_close(Outcome.INTERRUPTED, AGREEMENT.REASON_HOTKEY, 0.0)
	return true


## Debug rows for the Show data block.
func debug_rows(pony: Node) -> Array[String]:
	var rows: Array[String] = []
	rows.append("phase=%s locked=%s" % [_phase_name(_phase), str(_locked)])
	if _offer != null and (not is_instance_valid(pony) or _offer.pony == pony):
		rows.append("offer id=%s trigger=%s pose=%s private=%s" % [
			_offer.pony_id, _trigger_name(_offer.trigger), _offer.option.key() if
			_offer.option != null else "none", str(_offer.private)])
		rows.append("offer expires in %.1fs" % maxf(0.0, _offer.expires_at - _now()))
	if _agreement != null and (not is_instance_valid(pony) or _agreement.pony == pony):
		rows.append("agreement id=%d pose=%s private=%s" % [
			_agreement.id, _agreement.option_key(), str(_agreement.private)])
		rows.append("agreement expires in %.1fs" % maxf(0.0, _agreement.expires_at() - _now()))
	return rows


## The Context snapshot the Proactive service's reasoning reads. Both stages judge the same mare
## from the same facts, so the bridge is the only source.
func context(pony: Node) -> CONTEXT.Context:
	if _host == null:
		return CONTEXT.build({})
	return _context(pony)


## The player's live form and display for the pose option builder; the Proactive filters its own
## candidates on the same view.
func form_view() -> FormView:
	return _form_view()


func _form_view() -> FormView:
	var out := FormView.new()
	out.form = "pony" if PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())) else "human"
	out.view = "vr" if WORLD.headset_view() else "desktop"
	return out


# --------------------------------------------------------------------------- terminal handoffs

## The shared terminal line. The purpose follows the close reason: a counter-offer still wants
## him, a privacy loss lets the moment go, and every other close is the generic release. It is a
## short generated line, queued and not delaying the clear.
func _react_line(pony: Node, reason: String) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(_adapter):
		return
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	if id.is_empty():
		return
	var purpose := ""
	match reason:
		AGREEMENT.REASON_COUNTER_OFFER:
			purpose = "Anon just offered sex and she said no only to the place or the timing, " \
				+ "because she still wants him. Say one short, in-character line declining that " \
				+ "place or moment and making that clear. Do not ask again and do not narrate actions."
		AGREEMENT.REASON_PRIVACY:
			purpose = "The moment was interrupted. Say one short, in-character line letting it " \
				+ "go, without anger. Do not ask again and do not narrate actions."
		_:
			purpose = "The offer ended. Say one short, in-character line letting it go, without " \
				+ "anger. Do not ask again and do not narrate actions."
	var key := "unfplap:negotiation:react:%d" % Time.get_ticks_usec()
	_adapter.call("queue", id, purpose,
		key, func() -> bool: return is_instance_valid(pony) and pony.is_inside_tree(), false)


## Every terminal outcome reaches the Proactive pacing and the runtime's presentation; a start
## that already happened belongs to the act, so it is not forwarded.
func _on_outcome_terminal(terminal: Variant) -> void:
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
	if int(_field(terminal, "outcome", -1)) != Outcome.STARTED \
			and is_instance_valid(initiation) and initiation.has_method("on_negotiation_outcome"):
		initiation.call("on_negotiation_outcome", terminal)


## The Agreement is ready: the target runtime consumes it through its one start path.
func _on_agreement_handle(handle: Variant) -> void:
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
		cancel(handle, "cancelled")
		return
	# The presentation is act-owned: it starts now, and the auto-start waits for it to settle.
	if option != null and str(option.pose) == CATALOG.STANDING \
			and not bool(runtime.call("present_standing")):
		LOG.debug("agreement present failed pony=%s" % str(pony.name))
	if is_instance_valid(offer):
		offer.call("clear_current")


## Read a typed field from the production handle/terminal or a test dictionary.
func _field(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(key, fallback)
	if value == null:
		return fallback
	var got: Variant = value.get(key)
	return fallback if got == null else got


# --------------------------------------------------------------------------- state

func _begin_state(live: Offer, runtime: Node, pony: Node3D, option: POSE_OPTIONS.Option,
		trigger: int, line: String, cuddle: bool) -> void:
	_generation += 1
	_serial += 1
	live.id = _serial
	live.generation = _generation
	live.runtime = runtime
	live.pony = pony
	live.pony_id = _pony_id(pony)
	live.option = option
	live.trigger = trigger
	live.line = line
	live.cuddle = cuddle
	live.expires_at = _now() + AGREEMENT.OFFER_TTL_S
	_offer = live
	_agreement = null
	_handle = null
	_phase = Phase.OFFERED
	_locked = true
	_deadline = live.expires_at
	_privacy_clock = 0.0
	_log_line("negotiation state=offered id=%s serial=%d trigger=%s" % [
		live.pony_id, live.id, _trigger_name(trigger)])


func _clear_state() -> void:
	_phase = Phase.NONE
	_locked = false
	_offer = null
	_agreement = null
	_handle = null
	_deadline = 0.0
	_privacy_clock = 0.0
	_generation += 1


## One close path for every terminal outcome. The hold is released unless the Act adopted it on
## Started. No cooldown, no record and no reasoning write happens here.
func _close(outcome: int, reason: String, cooldown: float, reaction := false) -> void:
	var pony: Node = _pony()
	var trigger := _trigger()
	var package_pony: Node = _agreement.pony if _agreement != null else pony
	if _offer != null:
		_cancel_scope(_offer.scope)
	if _agreement != null:
		_cancel_scope(_agreement.classifier_scope)
	_release_hold()
	_clear_state()
	_log_line("negotiation outcome=%s reason=%s cooldown=%.0f" % [
		_outcome_name(outcome), "none" if reason.is_empty() else reason, cooldown])
	_report_outcome(package_pony, outcome, reason, trigger, cooldown)
	_notify(outcome, reason)
	if reaction and is_instance_valid(package_pony):
		_react(package_pony, reason)


## A genuine non-offer: cancel the scopes, release any claim and clear the state without a
## terminal outcome, a toast or a reaction. The Proactive pacing sees nothing, so a normal
## conversation line cannot write a retry or a cooldown.
func _silent_close() -> void:
	if _offer != null:
		_cancel_scope(_offer.scope)
	if _agreement != null:
		_cancel_scope(_agreement.classifier_scope)
	_release_hold()
	_clear_state()
	_log_line("negotiation state=none reason=non_offer")


func _formation_failure(pony: Variant, outcome: int, reason: String, trigger: int) -> void:
	var target := pony as Node if pony is Node else null
	_report_outcome(target, outcome, reason, trigger, 0.0)
	_notify(outcome, reason)


func _report_outcome(pony: Node, outcome: int, reason: String, trigger: int,
		cooldown: float) -> void:
	if _host == null or not _host.on_outcome.is_valid():
		return
	var terminal := Terminal.new()
	terminal.pony = pony
	terminal.pony_id = _pony_id(pony)
	terminal.outcome = outcome
	terminal.reason = reason
	terminal.trigger = trigger
	terminal.cooldown_s = cooldown
	_host.on_outcome.call(terminal)


func _accept(live: Offer) -> void:
	_generation += 1
	var package := AGREEMENT.Package.new()
	package.id = live.id
	package.generation = _generation
	package.runtime = live.runtime
	package.pony = live.pony
	package.pony_id = live.pony_id
	package.option = live.option
	package.private = live.private
	package.clearance = live.base
	package.context = live.context
	package.pose_profile_ok = POSE_SPECS.is_public(live.option.pose)
	package.pose_source_ok = POSE_PLACEMENT.source_allowed(live.option.pose, live.option.source)
	package.answer = ANSWER_ACCEPT
	package.accepted_at = _now()
	package.ttl_s = AGREEMENT.AGREEMENT_TTL_S
	package.hold_token = live.hold_token
	package.hold_old_wander = live.hold_old_wander
	package.trigger = live.trigger
	package.classifier_scope = live.scope
	package.offer_line = live.line
	_agreement = package
	_handle = _make_handle(package)
	_offer = null
	_phase = Phase.AGREEMENT
	_deadline = package.expires_at()
	_privacy_clock = 0.0
	_log_line("negotiation state=agreement id=%s" % package.pony_id)
	_log_line("negotiation outcome=accepted cooldown=%.0f" % COOLDOWN_S)
	_report_outcome(package.pony, Outcome.ACCEPTED, "", package.trigger, COOLDOWN_S)
	_log_line("negotiation agreement id=%d trigger=%s pose=%s private=%s" % [
		package.id, _trigger_name(package.trigger), package.option_key(), str(package.private)])
	if _host.on_agreement.is_valid():
		_host.on_agreement.call(_handle)


func _make_handle(package: AGREEMENT.Package) -> AGREEMENT.Handle:
	var out := AGREEMENT.Handle.new()
	out.id = package.id
	out.generation = package.generation
	out.pony = package.pony
	out.pony_id = package.pony_id
	out.option = package.option
	out.private = package.private
	out.pose_profile_ok = package.pose_profile_ok
	out.pose_source_ok = package.pose_source_ok
	out.hold_token = package.hold_token
	out.hold_old_wander = package.hold_old_wander
	out.trigger = package.trigger
	out.cancel = Callable(self, "_cancel_handle").bind(package.id, package.generation)
	return out


func _cancel_handle(reason: String, id: int, generation: int) -> bool:
	if _phase != Phase.AGREEMENT or _agreement == null:
		return false
	if _agreement.id != id or _agreement.generation != generation:
		return false
	var live_reason := _interrupt_reason(reason)
	_close(Outcome.INTERRUPTED, live_reason, 0.0, live_reason == AGREEMENT.REASON_PRIVACY)
	return true


func _agreement_matches(handle: AGREEMENT.Handle) -> bool:
	if _phase != Phase.AGREEMENT or _agreement == null:
		return false
	return handle.id == _agreement.id and handle.generation == _agreement.generation


func _interrupt_reason(reason: String) -> String:
	if reason in [AGREEMENT.REASON_PRIVACY, AGREEMENT.REASON_POSE, AGREEMENT.REASON_HOTKEY,
			AGREEMENT.REASON_TARGET_LEFT]:
		return reason
	return AGREEMENT.REASON_CANCELLED


# --------------------------------------------------------------------------- decisions

func _on_anon_answer(live: Offer, text: String, error: String) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	if not error.is_empty():
		_close(Outcome.REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return
	var scope := _scope("decision")
	live.scope = scope
	var request := PROMPTS.Request.new()
	request.kind = "anon_decision"
	request.text = text
	request.line = live.line
	request.context = live.context
	var started := bool(_host.classify.call(request, scope,
		func(reply: PROMPTS.Reply) -> void: _on_anon_decision(live, reply)))
	if not started:
		_close(Outcome.REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)


func _on_anon_decision(live: Offer, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	_log_line("negotiation answer id=%s kind=anon_decision answer=%s failed=%s" % [
		live.pony_id, "none" if reply == null else reply.answer,
		str(reply == null or reply.failed)])
	if reply == null or reply.failed:
		_close(Outcome.REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return
	var answer := str(reply.answer)
	if answer == CONTEXT.ANSWER_ACCEPT:
		if not _placement_ok(live.option):
			_close(Outcome.INTERRUPTED, AGREEMENT.REASON_POSE, 0.0)
			return
		_accept(live)
	elif answer == CONTEXT.ANSWER_COUNTER_OFFER:
		_close(Outcome.REFUSED, AGREEMENT.REASON_COUNTER_OFFER, 0.0, true)
	else:
		_close(Outcome.REFUSED, "", COOLDOWN_S)


func _on_anon_offer_classified(live: Offer, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	if reply != null:
		_log_line("negotiation classify result id=%s answer=%s option=%d failed=%s out_of_range=%s" % [
			live.pony_id, reply.answer, reply.option_index, str(reply.failed),
			str(reply.out_of_range)])
	else:
		_log_line("negotiation classify result id=%s answer=none failed=true" % live.pony_id)
	if reply == null or reply.failed:
		_close(Outcome.NO_OFFER, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return
	if reply.out_of_range:
		_close(Outcome.NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE, 0.0)
		return
	if reply.answer != CONTEXT.ANSWER_ACCEPT:
		# A normal line that is not an offer is silent for the player: no outcome, no toast,
		# no cooldown. The debug line keeps it visible in the log.
		_log_line("negotiation non-offer id=%s answer=%s" % [live.pony_id, reply.answer])
		_silent_close()
		return
	if reply.option_index < 0 or reply.option_index >= live.options.size():
		_close(Outcome.NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE, 0.0)
		return
	var option: POSE_OPTIONS.Option = live.options[reply.option_index]
	live.option = option
	live.cuddle = option.cuddle
	if not _placement_ok(option):
		_close(Outcome.INTERRUPTED, AGREEMENT.REASON_POSE, 0.0)
		return
	if not _claim_anon_hold(live):
		_log_line("negotiation hold claim id=%s trigger=anon result=false" % live.pony_id)
		_close(Outcome.OCCUPIED, AGREEMENT.REASON_OCCUPIED, 0.0)
		return
	_log_line("negotiation hold claim id=%s trigger=anon result=true token=%s" % [
		live.pony_id, live.hold_token])
	live.private = _private_now(live.pony, option.cuddle)
	_log_line("negotiation offer id=%s trigger=anon pose=%s private=%s" % [
		live.pony_id, option.key(), str(live.private)])
	var scope := _scope("mare_response")
	live.scope = scope
	var request := PROMPTS.Request.new()
	request.kind = "mare_response"
	request.text = live.line
	request.context = live.context
	request.options = [option]
	var started := bool(_host.reason.call(request, scope,
		func(reply: PROMPTS.Reply) -> void: _on_mare_response(live, reply)))
	if not started:
		_close(Outcome.REFUSED, AGREEMENT.REASON_REASONING_FAILED, 0.0)


func _on_mare_response(live: Offer, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	_log_line("negotiation answer id=%s kind=mare_response answer=%s failed=%s" % [
		live.pony_id, "none" if reply == null else reply.answer,
		str(reply == null or reply.failed)])
	if reply == null or reply.failed:
		_close(Outcome.REFUSED, AGREEMENT.REASON_REASONING_FAILED, 0.0)
		return
	var answer := str(reply.answer)
	if answer == CONTEXT.ANSWER_ACCEPT:
		_accept(live)
	elif answer == CONTEXT.ANSWER_COUNTER_OFFER:
		_close(Outcome.REFUSED, AGREEMENT.REASON_COUNTER_OFFER, 0.0, true)
	else:
		_close(Outcome.REFUSED, "", COOLDOWN_S)


## True while a callback still belongs to the live offer. A late result after any terminal
## transition can never form an Agreement.
func _current(live: Offer) -> bool:
	return live != null and _offer == live and _phase == Phase.OFFERED \
		and live.generation == _generation


# --------------------------------------------------------------------------- clearance and context

func _clearance_for(runtime: Node) -> CLEARANCE.Result:
	var pony: Variant = runtime.get("pony")
	var present := is_instance_valid(pony)
	var state: Variant = runtime.get("state")
	var in_act := state != null and int(state) != 0
	var sleeping := present and bool((pony as Node).get("sleeping"))
	var eligible := present and bool(_host.eligible.call(pony))
	var relationship := present and bool(_host.relationship_ok.call(pony))
	var available := CLEARANCE.available(in_act, sleeping, present, false)
	return CLEARANCE.evaluate(eligible, relationship, available)


func _context(pony: Node) -> CONTEXT.Context:
	var facts: Variant = _host.context_facts.call(pony)
	return CONTEXT.build(facts if facts is Dictionary else {})


func _options_for(runtime: Node) -> Array[POSE_OPTIONS.Option]:
	var view: Variant = _host.form_view.call()
	var placement: Variant = _host.placement_for.call(runtime)
	if not view is FormView or not placement is POSE_OPTIONS.Placement:
		return []
	var live := view as FormView
	return POSE_OPTIONS.build(live.form, live.view, placement as POSE_OPTIONS.Placement)


## The live placement re-check for the chosen option, just before the hold is claimed or the
## Agreement forms. It runs the scene-only rows through the host; a missing callback refuses.
func _placement_ok(option: POSE_OPTIONS.Option) -> bool:
	if _host == null or not _host.pose_placed.is_valid() or option == null:
		return false
	var runtime: Node = _runtime()
	if not is_instance_valid(runtime):
		return false
	return bool(_host.pose_placed.call(runtime, option))


# --------------------------------------------------------------------------- hold

func _claim_mare_hold(live: Offer, offer: MareOffer) -> bool:
	var hold: Variant = _hold()
	if hold == null:
		return false
	if not offer.hold_token.is_empty():
		if not (bool(hold.holds_negotiation()) and str(hold.token) == offer.hold_token):
			if not bool(hold.transfer_nav(offer.hold_token, offer.hold_old_wander)):
				return false
	elif offer.cuddle:
		if not bool(hold.claim_attention()):
			return false
	else:
		if not bool(hold.claim_negotiation(live.pony_id)):
			return false
	if not bool(hold.hold_affection()):
		hold.release_nav()
		return false
	live.hold_token = str(hold.token)
	live.hold_old_wander = bool(hold.nav_old_wander)
	live.hold_claimed = true
	return true


func _claim_anon_hold(live: Offer) -> bool:
	var hold: Variant = _hold()
	if hold == null:
		return false
	var claimed := bool(hold.claim_attention()) if live.cuddle \
		else bool(hold.claim_negotiation(live.pony_id))
	if not claimed:
		return false
	if not bool(hold.hold_affection()):
		hold.release_nav()
		return false
	live.hold_token = str(hold.token)
	live.hold_old_wander = bool(hold.nav_old_wander)
	live.hold_claimed = true
	return true


## Keep the navigator and Anon as the conversation target. A lost owner or a reassigned target is
## `target_left`; the service still owns the Agreement until the Act reports Started.
func _keep_hold() -> bool:
	var hold: Variant = _hold()
	if hold == null:
		_log_line("negotiation hold lost id=%s reason=missing" % _pony_id(_pony()))
		_close(Outcome.INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	if _offer != null and not _offer.hold_claimed:
		# The Anon offer is still being classified; there is no lease to keep yet, only attention.
		if not bool(hold.keep_target()):
			_log_line("negotiation hold lost id=%s reason=target_left target=%s" % [
				_pony_id(_pony()), _target_name()])
			_close(Outcome.INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
			return false
		return true
	hold.keep_nav()
	if not bool(hold.keep_target()):
		_log_line("negotiation hold lost id=%s reason=target_left target=%s" % [
			_pony_id(_pony()), _target_name()])
		_close(Outcome.INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	if not bool(hold.accepts_hold(_pose(), _source())):
		_log_line("negotiation hold lost id=%s reason=owner" % _pony_id(_pony()))
		_close(Outcome.INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	return true


func _release_hold() -> void:
	if _offer != null and not _offer.hold_claimed:
		return
	if _agreement == null and _offer == null:
		return
	var hold: Variant = _hold()
	if hold != null:
		hold.release_negotiation()


func _hold() -> Variant:
	var runtime: Node = _runtime()
	if not is_instance_valid(runtime) or _host == null or not _host.hold_for.is_valid():
		return null
	var hold: Variant = _host.hold_for.call(runtime)
	return hold if hold != null else null


# --------------------------------------------------------------------------- helpers

func _runtime() -> Node:
	if _offer != null and is_instance_valid(_offer.runtime):
		return _offer.runtime
	if _agreement != null and is_instance_valid(_agreement.runtime):
		return _agreement.runtime
	return null


func _pony() -> Node:
	if _offer != null and is_instance_valid(_offer.pony):
		return _offer.pony
	if _agreement != null and is_instance_valid(_agreement.pony):
		return _agreement.pony
	return null


func _pose() -> String:
	if _offer != null and _offer.option != null:
		return _offer.option.pose
	if _agreement != null and _agreement.option != null:
		return _agreement.option.pose
	return ""


func _source() -> String:
	if _offer != null and _offer.option != null:
		return _offer.option.source
	if _agreement != null and _agreement.option != null:
		return _agreement.option.source
	return ""


func _cuddle_flag() -> bool:
	if _offer != null:
		return _offer.cuddle
	if _agreement != null and _agreement.option != null:
		return _agreement.option.cuddle
	return false


func _trigger() -> int:
	if _offer != null:
		return _offer.trigger
	if _agreement != null:
		return _agreement.trigger
	return AGREEMENT.Trigger.ANON_OFFER


func _private_now(pony: Node, cuddle: bool) -> bool:
	if _host == null or not _host.privacy_private.is_valid():
		return true
	return bool(_host.privacy_private.call(pony, cuddle))


func _pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	return PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))


func _target_name() -> String:
	var pony: Node = _pony()
	if not is_instance_valid(pony):
		return "none"
	var target: Variant = pony.get("conversation_target")
	return str(target.name) if is_instance_valid(target) else "none"


func _scope(kind: String) -> String:
	return "negotiation:%s:%d:%d" % [kind, _serial, _generation]


func _cancel_scope(scope: String) -> void:
	if scope.is_empty() or _host == null or not _host.cancel_scope.is_valid():
		return
	_host.cancel_scope.call(scope)


func _now() -> float:
	if _host != null and _host.now.is_valid():
		return float(_host.now.call())
	return Time.get_ticks_msec() / 1000.0


func _log_line(text: String) -> void:
	if _host != null and _host.log.is_valid():
		_host.log.call(text)


func _toast(text: String) -> void:
	if _host != null and _host.toast.is_valid():
		_host.toast.call(text)


func _react(pony: Node, reason: String) -> void:
	if _host != null and _host.react.is_valid():
		_host.react.call(pony, reason)


func _blocked(pony: Node) -> void:
	_report_outcome(pony, Outcome.NO_OFFER, AGREEMENT.REASON_LOCKED, _trigger(), 0.0)
	_log_line("negotiation blocked reason=locked")
	_toast("Another offer is already in progress.")


func _notify(outcome: int, reason: String) -> void:
	match outcome:
		Outcome.OCCUPIED:
			_log_line("negotiation occupied")
			_toast("She is busy right now.")
		Outcome.NO_OFFER:
			_log_line("negotiation no offer reason=%s" % reason)
			_toast("She is not available for that.")
		Outcome.REFUSED:
			_log_line("negotiation refused reason=%s" % ("none" if reason.is_empty() else reason))
			_toast("She said not here." if reason == AGREEMENT.REASON_COUNTER_OFFER else
				"She said no.")
		Outcome.EXPIRED:
			_log_line("negotiation expired")
			_toast("The offer expired.")
		Outcome.INTERRUPTED:
			_log_line("negotiation interrupted reason=%s" % reason)
			if reason == AGREEMENT.REASON_PRIVACY:
				_toast("Someone came near; the offer ended.")
			elif reason == AGREEMENT.REASON_HOTKEY:
				_toast("The offer was cancelled.")
			elif reason == AGREEMENT.REASON_TARGET_LEFT:
				_toast("She was called away.")
			else:
				_toast("The offer ended.")
		Outcome.START_FAILED:
			_log_line("negotiation start failed")
			_toast("The act could not start.")
		Outcome.STARTED:
			_log_line("negotiation started")


func _outcome_name(value: int) -> String:
	match value:
		Outcome.ACCEPTED: return "accepted"
		Outcome.REFUSED: return "refused"
		Outcome.EXPIRED: return "expired"
		Outcome.INTERRUPTED: return "interrupted"
		Outcome.START_FAILED: return "start_failed"
		Outcome.NO_OFFER: return "no_offer"
		Outcome.OCCUPIED: return "occupied"
		Outcome.STARTED: return "started"
	return "none"


func _phase_name(value: int) -> String:
	match value:
		Phase.OFFERED: return "offered"
		Phase.AGREEMENT: return "agreement"
	return "none"


func _trigger_name(value: int) -> String:
	match value:
		AGREEMENT.Trigger.MARE_OFFER: return "mare"
		AGREEMENT.Trigger.ANON_OFFER: return "anon"
		AGREEMENT.Trigger.HOTKEY_MATCH: return "hotkey"
	return "anon"
