extends "res://mods/unfplap/shared/service.gd"
## Service: negotiation
## Scope: world
## Contract: docs/negotiation.md
## The Act Negotiation: one live offer or Agreement, its global lock and its terminal outcome.

const AGREEMENT := preload("res://mods/unfplap/shared/agreement.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const HOST := preload("res://mods/unfplap/negotiation/host.gd")
const DIRECTOR := preload("res://mods/unfplap/director/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/api.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const POSE_PLACEMENT := preload("res://mods/unfplap/shared/pose_placement.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")

# The exchange's position and its terminal outcome stay inside the service; a consumer reads the
# lock, the handle and the terminal record instead.
const _PHASE_NONE := 0
const _PHASE_OFFERED := 1
const _PHASE_AGREEMENT := 2
const _OUTCOME_ACCEPTED := 0
const _OUTCOME_REFUSED := 1
const _OUTCOME_EXPIRED := 2
const _OUTCOME_INTERRUPTED := 3
const _OUTCOME_START_FAILED := 4
const _OUTCOME_NO_OFFER := 5
const _OUTCOME_OCCUPIED := 6

## The offer cooldown: only a plain decline or an acceptance.
const _COOLDOWN_S := 120.0
## The privacy provider is sampled at the request-scan cadence, not per frame.
const _PRIVACY_SAMPLE_S := 0.5


## The player form and display the Anon option builder filters on.
class _FormView:
	var form := "human"
	var view := "desktop"


## The finalized proactive offer the Proactive service hands over at formation: the pose option
## and the request hold. Everything else is decided here.
class MareOffer:
	var runtime: Node = null
	var pony: Node3D = null
	var option: POSE_OPTIONS.Option = null
	var hold_token := ""
	var hold_old_wander := true
	var line := ""

	func valid() -> bool:
		return is_instance_valid(runtime) and is_instance_valid(pony) and option != null \
			and option.valid()


## The terminal outcome reported to the Proactive service and the debug log.
class Terminal:
	var pony_id := ""
	var reason := ""
	var cooldown_s := 0.0


## One live negotiation's private state. It is cleared when the Agreement forms.
class _Exchange:
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

var _host: HOST.Host
var _bridge: HOST = null
var _voice: DIRECTOR = null
var _phase := _PHASE_NONE
var _locked := false
var _exchange: _Exchange = null
var _agreement: AGREEMENT.Package = null
var _handle: AGREEMENT.Handle = null
var _generation := 0
var _serial := 0
var _deadline := 0.0
var _privacy_clock := 0.0

## The services the bridge reads, wired once by the entry; the facade reads none of them itself.
var _eligibility: ELIGIBILITY = null
var _gate: ACT_GATE = null
var _memory: MEMORY = null
var _privacy: PRIVACY = null
var _hud: Node = null
var _initiation: Node = null
## The act frame the bridge's watch gates on.
var _act_owner: ACT_OWNER = null
## The roster the terminal outcome and the Agreement handle read runtimes through.
var _ponies: PONIES = null


## Takes the peers this service calls; the composition root is the only caller. The bridge is built
## in `_ready()`, after every peer is wired.
func wire(eligibility_service: ELIGIBILITY, gate_service: ACT_GATE, memory_service: MEMORY,
		privacy_service: PRIVACY, initiation_service: Node, voice: DIRECTOR,
		owner: ACT_OWNER, hud_service: Node = null, ponies_service: PONIES = null) -> void:
	_eligibility = eligibility_service
	_gate = gate_service
	_memory = memory_service
	_privacy = privacy_service
	_initiation = initiation_service
	_voice = voice
	_act_owner = owner
	_hud = hud_service
	_ponies = ponies_service
	assert(_eligibility != null and _gate != null and _memory != null)
	assert(_privacy != null and _initiation != null and _voice != null and _act_owner != null)


## Builds the bridge, then binds the typed host to it.
func _ready() -> void:
	if _bridge == null:
		_bridge = HOST.new()
	_bridge.service = self
	_bridge.voice = _voice
	_bridge.eligibility = _eligibility
	_bridge.gate = _gate
	_bridge.memory = _memory
	_bridge.privacy = _privacy
	_bridge.hud = _hud
	_bridge.initiation = _initiation
	_bridge.act_owner = _act_owner
	_bridge.ponies = _ponies
	_bind_host()


## A world started: close the world that is gone, bind the host again, then drop its watch.
func on_world(_host: Node) -> void:
	on_world_closed()
	if _bridge == null:
		return
	_bind_host()
	_bridge.disarm()


## Build the typed host from the bridge. Every model callback is the director's; every world read
## is the bridge or the form view below.
func _bind_host() -> void:
	if _bridge == null:
		return
	var host := HOST.Host.new()
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
	host.react = Callable(self, "_react_line")
	host.on_outcome = Callable(self, "_on_outcome_terminal")
	host.on_agreement = Callable(self, "_on_agreement_handle")
	_host = host


## The suite seam: a typed host replaces the bridge the entry builds. The entry never calls it.
func setup(host: HOST.Host) -> void:
	_host = host


## A world enter or a world close. It releases the hold and cancels every classifier scope; a
## close reports no terminal outcome.
func on_world_closed() -> void:
	_cancel_scope(_exchange.scope if _exchange != null else "")
	_cancel_scope(_agreement.classifier_scope if _agreement != null else "")
	_release_hold()
	_clear_state()
	_host = null


## True while some exchange owns the field: a Mare offer, an Anon offer or a live Agreement.
func is_locked() -> bool:
	return _locked


## The live Agreement handle, or null. The offer service reads it immediately.
func handle() -> AGREEMENT.Handle:
	return _handle if _phase == _PHASE_AGREEMENT else null


## The one readiness read: formed, unexpired and still private. A lost cover is closed here.
func can_start() -> bool:
	if _phase != _PHASE_AGREEMENT or _agreement == null or _handle == null or _host == null:
		return false
	if not _handle.valid() or _agreement.expired(_now()):
		return false
	if _agreement.option == null or not is_instance_valid(_agreement.pony):
		return false
	if not _agreement.private or _private_now(_agreement.pony, _cuddle_flag()):
		return true
	LOG.debug("negotiation privacy lost id=%s", [_agreement.pony_id])
	_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_PRIVACY, 0.0, true)
	return false


## The entry's idle frame: the TTL and the privacy sample, then the bridge's global watch. The
## watch keeps its own chunk, so a stalled watch stays visible next to the exchange.
func tick(delta: float) -> void:
	_tick_offer(delta)
	PERF.begin("entry_watch")
	if _bridge != null:
		_bridge.tick_watch()
	PERF.end("entry_watch")


func _tick_offer(delta: float) -> void:
	if _host == null or _phase == _PHASE_NONE:
		return
	if _now() >= _deadline:
		_close(_OUTCOME_EXPIRED, "", 0.0)
		return
	if not _keep_hold():
		return
	var private := _exchange.private if _phase == _PHASE_OFFERED else _agreement.private
	if not private:
		return
	_privacy_clock += delta
	if _privacy_clock < _PRIVACY_SAMPLE_S:
		return
	_privacy_clock = 0.0
	var pony: Node = _pony()
	if not is_instance_valid(pony) or not _private_now(pony, _cuddle_flag()):
		LOG.debug("negotiation privacy lost id=%s", [_pony_id(pony)])
		_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_PRIVACY, 0.0, true)


## The Proactive service's formed Mare offer. From here the exchange and the answer watch are this
## service's. Base clearance and visibility are read here, not taken from the Proactive.
func begin_mare_offer(offer: MareOffer) -> bool:
	if _host == null or offer == null or not offer.valid():
		return false
	if _locked:
		_blocked(offer.pony)
		return false
	var base := _clearance_for(offer.runtime)
	if not base.ok():
		_formation_failure(offer.pony, _OUTCOME_NO_OFFER, base.reason())
		return false
	var live := _Exchange.new()
	_begin_state(live, offer.runtime, offer.pony, offer.option, AGREEMENT.Trigger.MARE_OFFER,
		offer.line, offer.option.cuddle)
	live.base = base
	live.private = _private_now(offer.pony, offer.option.cuddle)
	if not _claim_mare_hold(live, offer):
		LOG.debug("negotiation hold claim id=%s trigger=mare result=false", [live.pony_id])
		_close(_OUTCOME_OCCUPIED, AGREEMENT.REASON_OCCUPIED, 0.0)
		return false
	LOG.debug("negotiation hold claim id=%s trigger=mare result=true token=%s", [
		live.pony_id, live.hold_token])
	live.context = _context(live.pony)
	var scope := _scope("answer")
	live.scope = scope
	var watching := bool(_host.await_answer.call(live.pony, scope,
		func(text: String, error: String) -> void: _on_anon_answer(live, text, error)))
	if not watching:
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return false
	LOG.debug("negotiation offer id=%s trigger=mare pose=%s private=%s", [
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
		_formation_failure(pony, _OUTCOME_NO_OFFER, base.reason())
		return false
	var options := _options_for(runtime)
	if options.is_empty():
		_formation_failure(pony, _OUTCOME_NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE)
		return false
	var live := _Exchange.new()
	_begin_state(live, runtime, pony, null, AGREEMENT.Trigger.ANON_OFFER, text, false)
	live.base = base
	live.options = options
	live.context = _context(live.pony)
	LOG.debug("negotiation classify start id=%s text_len=%d options=%d", [
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
		_close(_OUTCOME_NO_OFFER, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return false
	return true


## The offer reports the start answer; a success hands the hold to the act.
func report(handle: AGREEMENT.Handle, started: bool) -> bool:
	if handle == null or not _agreement_matches(handle):
		return false
	var package := _agreement
	if started:
		_clear_state()
		LOG.debug("negotiation started id=%d state=none", [package.id])
	else:
		_close(_OUTCOME_START_FAILED, "", 0.0)
	return true


## The Act service's one cancel callback. A stale handle is ignored.
func cancel(handle: AGREEMENT.Handle, reason: String) -> bool:
	if handle == null or not _agreement_matches(handle):
		return false
	var live_reason := _interrupt_reason(reason)
	_close(_OUTCOME_INTERRUPTED, live_reason, 0.0, live_reason == AGREEMENT.REASON_PRIVACY)
	return true


## One press: a match keeps the live Agreement, anything else live is ended first.
func press(runtime: Node, option: POSE_OPTIONS.Option) -> AGREEMENT.Handle:
	if _phase == _PHASE_AGREEMENT and _agreement != null and _host != null \
			and is_instance_valid(runtime) and _agreement.runtime == runtime \
			and _agreement.matches(_agreement.pony, option):
		LOG.debug("negotiation press match id=%s", [_agreement.pony_id])
		return _handle
	if _phase == _PHASE_NONE:
		return null
	LOG.debug("negotiation press interrupt id=%s state=%s", [
		_pony_id(_pony()), _phase_name(_phase)])
	_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_HOTKEY, 0.0)
	return null


## Debug rows for the Show data block.
func debug_rows(pony: Node) -> Array[String]:
	var rows: Array[String] = []
	rows.append("phase=%s locked=%s" % [_phase_name(_phase), str(_locked)])
	if _exchange != null and (not is_instance_valid(pony) or _exchange.pony == pony):
		rows.append("offer id=%s trigger=%s pose=%s private=%s" % [
			_exchange.pony_id, _trigger_name(_exchange.trigger), _exchange.option.key() if
			_exchange.option != null else "none", str(_exchange.private)])
		rows.append("offer expires in %.1fs" % maxf(0.0, _exchange.expires_at - _now()))
	if _agreement != null and (not is_instance_valid(pony) or _agreement.pony == pony):
		rows.append("agreement id=%d pose=%s private=%s" % [
			_agreement.id, _agreement.option_key(), str(_agreement.private)])
		rows.append("agreement expires in %.1fs" % maxf(0.0, _agreement.expires_at() - _now()))
	return rows


## The player's live form and display for the Anon route's option builder.
func _form_view() -> _FormView:
	var out := _FormView.new()
	out.form = "pony" if WORLD.anon().form_is_pony() else "human"
	out.view = "vr" if WORLD.headset_view() else "desktop"
	return out


# --------------------------------------------------------------------------- terminal handoffs

## The shared terminal line. Its purpose follows the close reason: a counter-offer still wants
## him, a privacy loss lets the moment go, anything else is the generic release.
func _react_line(pony: Node, reason: String) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(_voice):
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
	_voice.queue(id, purpose, key, DIRECTOR.Validity.of(func() -> bool:
		return is_instance_valid(pony) and pony.is_inside_tree()), false)


## The terminal outcome reaches the Proactive pacing through this one line.
func _on_outcome_terminal(terminal: Terminal) -> void:
	if terminal == null:
		return
	LOG.debug("negotiation outcome id=%s reason=%s cooldown=%.0f", [
		terminal.pony_id, "none" if terminal.reason.is_empty() else terminal.reason,
		terminal.cooldown_s])
	if is_instance_valid(_initiation) and _initiation.has_method("on_negotiation_outcome"):
		_initiation.on_negotiation_outcome(terminal)


## The Agreement is formed: the offer's tick starts its standing presentation and consumes it.
func _on_agreement_handle(handle: AGREEMENT.Handle) -> void:
	if handle == null:
		return
	var pony_id := handle.pony_id
	if pony_id.is_empty() and is_instance_valid(handle.pony):
		pony_id = PONY_ID.from(str(handle.pony.get_meta("relationship_id", "")),
			handle.pony.get("identity"))
	var option := handle.option
	LOG.debug("agreement formed id=%s trigger=%s pose=%s private=%s", [
		pony_id, _trigger_name(_trigger()),
		option.pose if option != null else "none", str(handle.private)])


# --------------------------------------------------------------------------- state

func _begin_state(live: _Exchange, runtime: Node, pony: Node3D, option: POSE_OPTIONS.Option,
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
	_exchange = live
	_agreement = null
	_handle = null
	_phase = _PHASE_OFFERED
	_locked = true
	_deadline = live.expires_at
	_privacy_clock = 0.0
	LOG.debug("negotiation state=offered id=%s serial=%d trigger=%s", [
		live.pony_id, live.id, _trigger_name(trigger)])


func _clear_state() -> void:
	_phase = _PHASE_NONE
	_locked = false
	_exchange = null
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
	if _exchange != null:
		_cancel_scope(_exchange.scope)
	if _agreement != null:
		_cancel_scope(_agreement.classifier_scope)
	_release_hold()
	_clear_state()
	LOG.debug("negotiation outcome=%s reason=%s cooldown=%.0f", [
		_outcome_name(outcome), "none" if reason.is_empty() else reason, cooldown])
	_report_outcome(package_pony, reason, cooldown)
	_notify(outcome, reason)
	if reaction and is_instance_valid(package_pony):
		_react(package_pony, reason)


## A genuine non-offer closes silently: the scopes and the claim are released and the pacing is
## never told.
func _silent_close() -> void:
	if _exchange != null:
		_cancel_scope(_exchange.scope)
	if _agreement != null:
		_cancel_scope(_agreement.classifier_scope)
	_release_hold()
	_clear_state()
	LOG.debug("negotiation state=none reason=non_offer")


func _formation_failure(pony: Variant, outcome: int, reason: String) -> void:
	var target := pony as Node if pony is Node else null
	_report_outcome(target, reason, 0.0)
	_notify(outcome, reason)


func _report_outcome(pony: Node, reason: String, cooldown: float) -> void:
	if _host == null or not _host.on_outcome.is_valid():
		return
	var terminal := Terminal.new()
	terminal.pony_id = _pony_id(pony)
	terminal.reason = reason
	terminal.cooldown_s = cooldown
	_host.on_outcome.call(terminal)


func _accept(live: _Exchange) -> void:
	_generation += 1
	var package := AGREEMENT.Package.new()
	package.id = live.id
	package.generation = _generation
	package.runtime = live.runtime
	package.pony = live.pony
	package.pony_id = live.pony_id
	package.option = live.option
	package.private = live.private
	package.pose_profile_ok = POSE_SPECS.is_public(live.option.pose)
	package.pose_source_ok = POSE_PLACEMENT.source_allowed(live.option.pose, live.option.source)
	package.accepted_at = _now()
	package.ttl_s = AGREEMENT.AGREEMENT_TTL_S
	package.trigger = live.trigger
	package.classifier_scope = live.scope
	_agreement = package
	_handle = _make_handle(package)
	_exchange = null
	_phase = _PHASE_AGREEMENT
	_deadline = package.expires_at()
	_privacy_clock = 0.0
	LOG.debug("negotiation state=agreement id=%s", [package.pony_id])
	LOG.debug("negotiation outcome=accepted cooldown=%.0f", [_COOLDOWN_S])
	_report_outcome(package.pony, "", _COOLDOWN_S)
	LOG.debug("negotiation agreement id=%d trigger=%s pose=%s private=%s", [
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
	return out


func _agreement_matches(handle: AGREEMENT.Handle) -> bool:
	if _phase != _PHASE_AGREEMENT or _agreement == null:
		return false
	return handle.id == _agreement.id and handle.generation == _agreement.generation


func _interrupt_reason(reason: String) -> String:
	if reason in [AGREEMENT.REASON_PRIVACY, AGREEMENT.REASON_POSE, AGREEMENT.REASON_HOTKEY,
			AGREEMENT.REASON_TARGET_LEFT]:
		return reason
	return AGREEMENT.REASON_CANCELLED


# --------------------------------------------------------------------------- decisions

func _on_anon_answer(live: _Exchange, text: String, error: String) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	if not error.is_empty():
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
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
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)


func _on_anon_decision(live: _Exchange, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	LOG.debug("negotiation answer id=%s kind=anon_decision answer=%s failed=%s", [
		live.pony_id, "none" if reply == null else reply.answer,
		str(reply == null or reply.failed)])
	if reply == null or reply.failed:
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return
	var answer := str(reply.answer)
	if answer == CONTEXT.ANSWER_ACCEPT:
		if not _placement_ok(live.option):
			_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_POSE, 0.0)
			return
		_accept(live)
	elif answer == CONTEXT.ANSWER_COUNTER_OFFER:
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_COUNTER_OFFER, 0.0, true)
	else:
		_close(_OUTCOME_REFUSED, "", _COOLDOWN_S)


func _on_anon_offer_classified(live: _Exchange, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	if reply != null:
		LOG.debug("negotiation classify result id=%s answer=%s option=%d failed=%s out_of_range=%s", [
			live.pony_id, reply.answer, reply.option_index, str(reply.failed),
			str(reply.out_of_range)])
	else:
		LOG.debug("negotiation classify result id=%s answer=none failed=true", [live.pony_id])
	if reply == null or reply.failed:
		_close(_OUTCOME_NO_OFFER, AGREEMENT.REASON_CLASSIFIER_UNAVAILABLE, 0.0)
		return
	if reply.out_of_range:
		_close(_OUTCOME_NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE, 0.0)
		return
	if reply.answer != CONTEXT.ANSWER_ACCEPT:
		LOG.debug("negotiation non-offer id=%s answer=%s", [live.pony_id, reply.answer])
		_silent_close()
		return
	if reply.option_index < 0 or reply.option_index >= live.options.size():
		_close(_OUTCOME_NO_OFFER, AGREEMENT.REASON_NO_CONTEXT_POSE, 0.0)
		return
	var option: POSE_OPTIONS.Option = live.options[reply.option_index]
	live.option = option
	live.cuddle = option.cuddle
	if not _placement_ok(option):
		_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_POSE, 0.0)
		return
	if not _claim_anon_hold(live):
		LOG.debug("negotiation hold claim id=%s trigger=anon result=false", [live.pony_id])
		_close(_OUTCOME_OCCUPIED, AGREEMENT.REASON_OCCUPIED, 0.0)
		return
	LOG.debug("negotiation hold claim id=%s trigger=anon result=true token=%s", [
		live.pony_id, live.hold_token])
	live.private = _private_now(live.pony, option.cuddle)
	LOG.debug("negotiation offer id=%s trigger=anon pose=%s private=%s", [
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
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_REASONING_FAILED, 0.0)


func _on_mare_response(live: _Exchange, reply: PROMPTS.Reply) -> void:
	if not _current(live):
		return
	_cancel_scope(live.scope)
	LOG.debug("negotiation answer id=%s kind=mare_response answer=%s failed=%s", [
		live.pony_id, "none" if reply == null else reply.answer,
		str(reply == null or reply.failed)])
	if reply == null or reply.failed:
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_REASONING_FAILED, 0.0)
		return
	var answer := str(reply.answer)
	if answer == CONTEXT.ANSWER_ACCEPT:
		_accept(live)
	elif answer == CONTEXT.ANSWER_COUNTER_OFFER:
		_close(_OUTCOME_REFUSED, AGREEMENT.REASON_COUNTER_OFFER, 0.0, true)
	else:
		_close(_OUTCOME_REFUSED, "", _COOLDOWN_S)


## True while a callback still belongs to the live offer. A late result after any terminal
## transition can never form an Agreement.
func _current(live: _Exchange) -> bool:
	return live != null and _exchange == live and _phase == _PHASE_OFFERED \
		and live.generation == _generation


# --------------------------------------------------------------------------- clearance and context

func _clearance_for(runtime: Node) -> CLEARANCE.Result:
	var pony: Variant = runtime.get("pony")
	var present := is_instance_valid(pony)
	var session: Variant = runtime.get("act") if is_instance_valid(runtime) else null
	var state: Variant = session.state if session != null else null
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
	if not view is _FormView or not placement is POSE_OPTIONS.Placement:
		return []
	var live := view as _FormView
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

func _claim_mare_hold(live: _Exchange, offer: MareOffer) -> bool:
	var hold: Variant = _hold()
	if hold == null:
		return false
	if not offer.hold_token.is_empty():
		if not (bool(hold.holds_negotiation()) and str(hold.token) == offer.hold_token):
			if not bool(hold.transfer_nav(offer.hold_token, offer.hold_old_wander)):
				return false
	elif offer.option.cuddle:
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


func _claim_anon_hold(live: _Exchange) -> bool:
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
		LOG.debug("negotiation hold lost id=%s reason=missing", [_pony_id(_pony())])
		_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	if _exchange != null and not _exchange.hold_claimed:
		# The Anon offer is still being classified; there is no lease to keep yet, only attention.
		if not bool(hold.keep_target()):
			LOG.debug("negotiation hold lost id=%s reason=target_left target=%s", [
				_pony_id(_pony()), _target_name()])
			_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
			return false
		return true
	hold.keep_nav()
	if not bool(hold.keep_target()):
		LOG.debug("negotiation hold lost id=%s reason=target_left target=%s", [
			_pony_id(_pony()), _target_name()])
		_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	if not bool(hold.accepts_hold(_pose(), _source())):
		LOG.debug("negotiation hold lost id=%s reason=owner", [_pony_id(_pony())])
		_close(_OUTCOME_INTERRUPTED, AGREEMENT.REASON_TARGET_LEFT, 0.0)
		return false
	return true


func _release_hold() -> void:
	if _exchange != null and not _exchange.hold_claimed:
		return
	if _agreement == null and _exchange == null:
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
	if _exchange != null and is_instance_valid(_exchange.runtime):
		return _exchange.runtime
	if _agreement != null and is_instance_valid(_agreement.runtime):
		return _agreement.runtime
	return null


func _pony() -> Node:
	if _exchange != null and is_instance_valid(_exchange.pony):
		return _exchange.pony
	if _agreement != null and is_instance_valid(_agreement.pony):
		return _agreement.pony
	return null


func _pose() -> String:
	if _exchange != null and _exchange.option != null:
		return _exchange.option.pose
	if _agreement != null and _agreement.option != null:
		return _agreement.option.pose
	return ""


func _source() -> String:
	if _exchange != null and _exchange.option != null:
		return _exchange.option.source
	if _agreement != null and _agreement.option != null:
		return _agreement.option.source
	return ""


func _cuddle_flag() -> bool:
	if _exchange != null:
		return _exchange.cuddle
	if _agreement != null and _agreement.option != null:
		return _agreement.option.cuddle
	return false


func _trigger() -> int:
	if _exchange != null:
		return _exchange.trigger
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


func _toast(text: String) -> void:
	if _host != null and _host.toast.is_valid():
		_host.toast.call(text)


func _react(pony: Node, reason: String) -> void:
	if _host != null and _host.react.is_valid():
		_host.react.call(pony, reason)


func _blocked(pony: Node) -> void:
	_report_outcome(pony, AGREEMENT.REASON_LOCKED, 0.0)
	LOG.debug("negotiation blocked reason=locked")
	_toast("Another offer is already in progress.")


func _notify(outcome: int, reason: String) -> void:
	match outcome:
		_OUTCOME_OCCUPIED:
			LOG.debug("negotiation occupied")
			_toast("She is busy right now.")
		_OUTCOME_NO_OFFER:
			LOG.debug("negotiation no offer reason=%s", [reason])
			_toast("She is not available for that.")
		_OUTCOME_REFUSED:
			LOG.debug("negotiation refused reason=%s", [("none" if reason.is_empty() else reason)])
			_toast("She said not here." if reason == AGREEMENT.REASON_COUNTER_OFFER else
				"She said no.")
		_OUTCOME_EXPIRED:
			LOG.debug("negotiation expired")
			_toast("The offer expired.")
		_OUTCOME_INTERRUPTED:
			LOG.debug("negotiation interrupted reason=%s", [reason])
			if reason == AGREEMENT.REASON_PRIVACY:
				_toast("Someone came near; the offer ended.")
			elif reason == AGREEMENT.REASON_HOTKEY:
				_toast("The offer was cancelled.")
			elif reason == AGREEMENT.REASON_TARGET_LEFT:
				_toast("She was called away.")
			else:
				_toast("The offer ended.")
		_OUTCOME_START_FAILED:
			LOG.debug("negotiation start failed")
			_toast("The act could not start.")


func _outcome_name(value: int) -> String:
	match value:
		_OUTCOME_ACCEPTED: return "accepted"
		_OUTCOME_REFUSED: return "refused"
		_OUTCOME_EXPIRED: return "expired"
		_OUTCOME_INTERRUPTED: return "interrupted"
		_OUTCOME_START_FAILED: return "start_failed"
		_OUTCOME_NO_OFFER: return "no_offer"
		_OUTCOME_OCCUPIED: return "occupied"
	return "none"


func _phase_name(value: int) -> String:
	match value:
		_PHASE_OFFERED: return "offered"
		_PHASE_AGREEMENT: return "agreement"
	return "none"


func _trigger_name(value: int) -> String:
	match value:
		AGREEMENT.Trigger.MARE_OFFER: return "mare"
		AGREEMENT.Trigger.ANON_OFFER: return "anon"
		AGREEMENT.Trigger.HOTKEY_MATCH: return "hotkey"
	return "anon"
