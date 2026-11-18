extends Node
## Proactive offers. One episode at a time: she waits for a quiet moment, builds the placeable
## options, decides with her own reasoning whether to offer and which option, walks to Anon or to
## the bed front, asks in character and hands the formed Mare offer to the Negotiation service.
## The exchange, privacy sampling, the Agreement and the act start belong to
## `negotiation/service.gd` and the runtime; this service keeps the pacing, the approach and the
## offer formation. Nothing starts the act here.
##
## The facade owns the attempt, admission and phase orchestration. One `Candidate` carries the
## offer and the live route; `_begin_route` is the single route entry and reports a short reason
## for a route that ends before the ask. Rules are `initiation/policy.gd`, wording is
## `initiation/prompts.gd`, the reasoning request is `initiation/reasoning.gd`, and every scene
## read is behind `initiation/venue.gd` (navigators, posture, beds) or the
## `negotiation/adapter.gd` director bridge that `main` injects. See `docs/initiation.md`.
##
## Automatic requests are background AI turns, so they require AI usage Full.

const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const FACTS := preload("res://mods/unfplap/initiation/facts.gd")
const PROMPTS := preload("res://mods/unfplap/initiation/prompts.gd")
const REASONING := preload("res://mods/unfplap/initiation/reasoning.gd")
const VENUE := preload("res://mods/unfplap/initiation/venue.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const COOLDOWNS := preload("res://mods/unfplap/initiation/cooldowns.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")

const KEY_PREFIX := "unfplap:request"

## Attempt phases. The pure phase tables are spelled in `initiation/policy.gd`.
enum Phase { NONE, APPROACH, ARRIVE, ASK, BED_APPROACH }
const PHASE_NAMES := {
	Phase.NONE: POLICY.PHASE_NONE,
	Phase.APPROACH: POLICY.PHASE_APPROACH,
	Phase.ARRIVE: POLICY.PHASE_ARRIVE,
	Phase.ASK: POLICY.PHASE_ASK,
	Phase.BED_APPROACH: POLICY.PHASE_BED_APPROACH,
}


## One mare's offer candidate and, once `_begin_route` starts it, the live attempt: the placeable
## choices, the chosen option and the walk/ask route state. The scan builds candidates for several
## mares, so route-time privacy reads and lease fields stay in `_begin_route`, not in the scan.
class Candidate extends RefCounted:
	var id := ""
	var runtime: Node
	var pony: Node3D
	var options: Array[POSE_OPTIONS.Option] = []
	var option: POSE_OPTIONS.Option = null
	var base: CLEARANCE.Result = null
	var context: CONTEXT.Context = null
	var private := false
	var forced := false
	var serial := 0
	## `Phase.NONE` until a route starts.
	var phase := 0
	var started_at := 0.0
	var arrive_until := 0.0
	var token := ""
	var nav: Node
	var prev_owner := ""
	var prev_wander := true
	var prev_limit: Variant = null
	var prev_pace: Variant = null
	var player_start := Vector3.ZERO
	var region := ""
	var bed_front: Variant = null


## What `force()` produced. `reject` is the comma-joined candidate reasons or the route close
## reason.
class ForceResult extends RefCounted:
	var ok := false
	var id := ""
	var pose := ""
	var reject := ""


var main: Node
var _episode: Candidate = null
var _scan_clock := 0.0
var _serial := 0
var _scan_cursor := 0
## id -> whether this cuddle has already produced an ask; the key exists only while she cuddles.
var _cuddle_asked: Dictionary = {}
## id -> the short retry deadline after a close with a reason, a reasoning failure or a refused
## handoff.
var _retry_at: Dictionary = {}
## The last quiet reason the scan logged, so one blocked offer logs once.
var _quiet_reason := ""
## id -> the last candidate reject reasons, for the throttled skip log and Show data.
var _scan_reason: Dictionary = {}
## id -> the last skip log time.
var _scan_log_at: Dictionary = {}
var _venue: VENUE
var _privacy: PRIVACY
## The idle offer service: the cuddle offer must match the offer the act key would start.
var _offer: OFFER
## The injected director bridge and model host. `main` owns it; see `negotiation/adapter.gd`.
var _adapter: Node
## One reasoning call at a time. A new scan never starts a second; a terminal transition bumps
## the serial so a late reply cannot form an offer.
var _reasoning_pending := false
var _reasoning_serial := 0
var _reasoning_scope := ""


func setup(main_node: Node, privacy_node: PRIVACY = null, adapter_node: Node = null,
		offer_node: OFFER = null) -> void:
	main = main_node
	_privacy = privacy_node if is_instance_valid(privacy_node) else PRIVACY.new()
	if not is_instance_valid(privacy_node):
		_privacy.setup(main_node)
	_adapter = adapter_node if is_instance_valid(adapter_node) else main.get("adapter")
	_offer = offer_node
	_venue = VENUE.new()
	_venue.name = "UnfplapRequestPlace"
	_venue.bind(main_node, _privacy)
	add_child(_venue)


func tick(delta: float) -> void:
	if not is_instance_valid(main):
		return
	if _episode != null:
		_tick_episode()
		return
	if _reasoning_pending:
		return
	_scan_clock += delta
	if _scan_clock < POLICY.SCAN_INTERVAL_S:
		return
	_scan_clock = 0.0
	_tick_cuddle_edges()
	_consider_start()


## Reset session state for a world close. Cooldowns stay in the world's mod state.
func reset() -> void:
	if _episode != null:
		_close_episode("")
	_reasoning_serial += 1
	_reasoning_pending = false
	if is_instance_valid(_adapter) and not _reasoning_scope.is_empty():
		_adapter.call("cancel_scope", _reasoning_scope)
	_reasoning_scope = ""
	_cuddle_asked.clear()
	_retry_at.clear()
	_quiet_reason = ""
	_scan_reason.clear()
	_scan_log_at.clear()
	_scan_clock = 0.0
	_scan_cursor = 0


## Manual lab/debug entry point: bypass the quiet, cooldown, retry and reasoning; keep Base
## clearance, the placeable options and the formation check. An empty `pose` lets the scan's
## first option decide. A route that ends before the ask reports its reason in `reject`.
func force(runtime: Node, pose := "") -> ForceResult:
	var out := ForceResult.new()
	if not is_instance_valid(main) or not is_instance_valid(runtime):
		out.reject = "no_runtime"
		return out
	if _episode != null:
		_close_episode("force")
	var reasons: Array = []
	var candidate := _candidate_for(runtime, true, pose, reasons)
	out.reject = ",".join(PackedStringArray(reasons))
	if candidate == null:
		_debug("request force reject %s pose=%s reasons=%s" % [
			_runtime_name(runtime), "any" if pose.is_empty() else pose, out.reject])
		return out
	out.reject = ""
	candidate.option = candidate.options[0]
	candidate.context = _context(candidate.pony)
	var reason := _begin_route(candidate)
	out.ok = reason.is_empty()
	out.reject = reason
	out.id = candidate.id
	out.pose = candidate.option.pose
	if out.ok:
		_debug("request force %s pose=%s" % [candidate.id, candidate.option.pose])
	else:
		_debug("request force reject %s pose=%s reasons=%s" % [
			candidate.id, candidate.option.pose, reason])
	return out


## The Negotiation service's terminal outcome for one act negotiation. The Proactive applies its
## pacing: a reported cooldown stamps the full per-mare wait, anything else the short retry.
func on_negotiation_outcome(terminal: RefCounted) -> void:
	if terminal == null:
		return
	var id := str(terminal.pony_id)
	if id.is_empty():
		return
	if float(terminal.cooldown_s) > 0.0:
		COOLDOWNS.set_last(id)
		_retry_at.erase(id)
	else:
		_retry_at[id] = _now() + POLICY.RETRY_S
	_debug("request outcome id=%s outcome=%d reason=%s cooldown=%.0f" % [
		id, int(terminal.outcome), _reason_name(str(terminal.reason)),
		float(terminal.cooldown_s)])


## A new Anon offer or hotkey cancels a live attempt that has not formed a Mare offer.
func cancel_approach() -> void:
	if _episode == null:
		return
	_close_episode("interrupted")


## Debug: drop one mare's offer cooldown, short retry and last skip reason. False without an id.
func clear_cooldown(pony: Node) -> bool:
	var id := _venue.pony_id(pony) if is_instance_valid(pony) else ""
	if id.is_empty():
		return false
	COOLDOWNS.clear(id)
	_retry_at.erase(id)
	_scan_reason.erase(id)
	return true


## The live placement facts for one runtime. `main` binds this into the Negotiation Host and the
## scan uses the same pass to build the pose options.
func placement_for(runtime: Node) -> POSE_OPTIONS.Placement:
	if not is_instance_valid(_venue):
		return POSE_OPTIONS.Placement.new()
	return _venue.placement_for(runtime)


# --------------------------------------------------------------------------- cuddle edge and cooldown

func _tick_cuddle_edges() -> void:
	for node: Variant in _venue.mares():
		if not is_instance_valid(node):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime) or not runtime.has_method("cuddle_active"):
			continue
		var id: String = _venue.pony_id(node)
		if id.is_empty():
			continue
		var active := bool(runtime.call("cuddle_active"))
		if active and not _cuddle_asked.has(id):
			_cuddle_asked[id] = false
			COOLDOWNS.clear(id)
		elif not active and _cuddle_asked.has(id):
			_cuddle_asked.erase(id)


# --------------------------------------------------------------------------- scan and reasoning

func _consider_start() -> void:
	if not is_instance_valid(_adapter):
		return
	if is_instance_valid(main) and main.has_method("negotiation_locked") \
			and bool(main.call("negotiation_locked")):
		return
	var quiet := str(_adapter.call("quiet_reason", POLICY.QUIET_CHAT_GAP_S))
	if not quiet.is_empty():
		if quiet != _quiet_reason:
			_quiet_reason = quiet
			_debug("request scan quiet reason=%s" % quiet)
		return
	_quiet_reason = ""
	var player: Node3D = _venue.player()
	if not is_instance_valid(player):
		return
	var candidates: Array = []
	var eligibility := _eligibility()
	for node: Variant in _venue.mares():
		if not is_instance_valid(node):
			continue
		if eligibility == null or not eligibility.eligible(node, ELIGIBILITY.Target.ACT):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime):
			continue
		var reasons: Array = []
		var candidate := _candidate_for(runtime, false, "", reasons)
		if candidate == null:
			_log_scan_skip(runtime, reasons)
			continue
		candidates.append(candidate)
	if candidates.is_empty():
		return
	# One reasoning call per scan. Rotating the start keeps one mare from always winning the
	# scan order; her own reasoning still decides whether she offers.
	var index := _scan_cursor % candidates.size()
	_scan_cursor += 1
	_start_reasoning(candidates[index])


## One mare's placeable offer, or null with the reject reasons. Base clearance, the pose option
## list, the cuddle target and the scene-only formation rows; the reasoning is the caller's.
func _candidate_for(runtime: Node, forced: bool, pose_request := "",
		reasons: Array = []) -> Candidate:
	if not is_instance_valid(main) or not is_instance_valid(runtime):
		reasons.append("no_main")
		return null
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		reasons.append("no_pony")
		return null
	if int(runtime.get("state")) != 0:
		reasons.append("state=%d" % int(runtime.get("state")))
		return null
	var id: String = _venue.pony_id(pony)
	if id.is_empty():
		reasons.append("no_id")
		return null
	if not forced and not COOLDOWNS.ready_for(id, _in_heat(runtime)):
		reasons.append("cooldown")
		return null
	if not forced and not POLICY.retry_ready(_now(), float(_retry_at.get(id, -100000.0))):
		reasons.append("retry")
		return null
	var service := _eligibility()
	var eligible: bool = service != null and bool(service.call("eligible", pony,
		ELIGIBILITY.Target.ACT))
	var relationship: bool = service != null and bool(service.call("relationship_ok", pony))
	var base := CLEARANCE.evaluate(eligible, relationship, _available(pony))
	if not base.ok():
		reasons.append("clearance:%s" % base.reasons_text())
		return null
	var view: Variant = main.call("form_view")
	if view == null:
		reasons.append("no_form")
		return null
	var placement: POSE_OPTIONS.Placement = _venue.placement_for(runtime)
	var options := _options_for(placement, view, pose_request, reasons)
	if options.is_empty():
		return null
	if placement.cuddle:
		if bool(_cuddle_asked.get(id, false)) and not forced:
			reasons.append("cuddle:asked")
			return null
		if not forced and not _offer_targets_pony(pony):
			reasons.append("cuddle:target")
			return null
	var placeable: Array[POSE_OPTIONS.Option] = []
	for option: POSE_OPTIONS.Option in options:
		var verdict: Variant = runtime.call("scene_only_verdict", option.pose, option.source,
			option.bed, null)
		if verdict == null:
			continue
		if bool(verdict.hard_ok):
			placeable.append(option)
		else:
			reasons.append("scene:%s" % ",".join(verdict.reasons))
	if placeable.is_empty():
		return null
	var out := Candidate.new()
	out.id = id
	out.runtime = runtime
	out.pony = pony
	out.options = placeable
	out.base = base
	out.forced = forced
	return out


## The placeable options for this mare and the requested pose filter. The cuddle option comes
## only from an active cuddle's bed; a bed or standing offer comes from the venue.
func _options_for(placement: POSE_OPTIONS.Placement, view: Variant, pose_request: String,
		reasons: Array) -> Array[POSE_OPTIONS.Option]:
	var built := POSE_OPTIONS.build(str(view.form), str(view.view), placement)
	var out: Array[POSE_OPTIONS.Option] = []
	for option: POSE_OPTIONS.Option in built:
		if not pose_request.is_empty() and option.pose != pose_request:
			continue
		if placement.cuddle and not option.cuddle:
			continue
		out.append(option)
	if out.is_empty() and not pose_request.is_empty():
		reasons.append("pose:%s" % pose_request)
	elif out.is_empty():
		reasons.append("no_option")
	return out


## One bounded Mare Initiation Reasoning call. A reasoning "no" applies the full pacing cooldown;
## an unavailable or failed call applies the short retry.
func _start_reasoning(candidate: Candidate) -> void:
	if not is_instance_valid(_adapter):
		return
	candidate.context = _context(candidate.pony)
	_reasoning_serial += 1
	var serial := _reasoning_serial
	_reasoning_scope = "negotiation:initiation:%d:%d" % [_serial, serial]
	_reasoning_pending = true
	_debug("request reasoning start id=%s options=%d" % [
		candidate.id, candidate.options.size()])
	var payload := REASONING.payload(candidate.context, candidate.options)
	var started := bool(_adapter.call("complete_raw", REASONING.INSTRUCTION, payload,
		_reasoning_scope,
		func(reply: String, error: String) -> void:
			_on_reasoning(candidate, serial, reply, error)))
	if not started:
		_reasoning_pending = false
		_reasoning_scope = ""
		_retry_at[candidate.id] = _now() + POLICY.RETRY_S
		_debug("request reasoning unavailable id=%s" % candidate.id)


func _on_reasoning(candidate: Candidate, serial: int, reply: String, error: String) -> void:
	if serial != _reasoning_serial:
		return
	_reasoning_pending = false
	_reasoning_scope = ""
	if candidate == null or _episode != null:
		return
	var runtime: Node = candidate.runtime
	if not is_instance_valid(candidate.pony) or not is_instance_valid(runtime):
		return
	if int(runtime.get("state")) != 0:
		return
	if is_instance_valid(main) and main.has_method("negotiation_locked") \
			and bool(main.call("negotiation_locked")):
		return
	var decision := REASONING.parse(reply, error, candidate.options.size())
	_debug("request reasoning result id=%s offer=%s option=%d failed=%s reply=%s error=%s" % [
		candidate.id, str(decision.offer), decision.option_index, str(decision.failed),
		_reply_text(reply), "none" if error.is_empty() else error])
	if decision.failed:
		_retry_at[candidate.id] = _now() + POLICY.RETRY_S
		_debug("request reasoning failed id=%s error=%s" % [
			candidate.id, "none" if error.is_empty() else error])
		return
	if not decision.offer:
		COOLDOWNS.set_last(candidate.id)
		_debug("request reasoning no id=%s" % candidate.id)
		return
	candidate.option = candidate.options[decision.option_index]
	_debug("request reasoning yes id=%s pose=%s" % [candidate.id, candidate.option.pose])
	_begin_route(candidate)


## The single route entry: a cuddle asks from the bed, a bed walks to its front, a standing offer
## walks to Anon; already near means the ask starts now. Returns `""` when the route started or the
## ask formed, otherwise the close reason.
func _begin_route(candidate: Candidate) -> String:
	var player: Node3D = _venue.player()
	if not is_instance_valid(player) or not is_instance_valid(candidate.pony):
		return "route lost"
	_serial += 1
	candidate.serial = _serial
	candidate.token = KEY_PREFIX + ":" + candidate.id
	candidate.started_at = _now()
	candidate.private = _private_now(candidate.pony, candidate.option.cuddle)
	_episode = candidate
	if candidate.option.cuddle:
		return _ask_now()
	if candidate.option.pose == CATALOG.MISSIONARY:
		return _lead_to_bed()
	if player.global_position.distance_to(candidate.pony.global_position) <= POLICY.ARRIVE_RANGE_M:
		return _ask_now()
	return _walk_to_player(player)


## One mare's failed scan candidate. The reason text is logged when it changes or after 10 s, so a
## steady cooldown or a closed gate does not fill the log every half second.
func _log_scan_skip(runtime: Node, reasons: Array) -> void:
	var pony: Variant = runtime.get("pony") if is_instance_valid(runtime) else null
	var id := str(_venue.pony_id(pony)) if is_instance_valid(pony) else ""
	if id.is_empty():
		id = "?"
	var reason := ",".join(PackedStringArray(reasons))
	if reason.is_empty():
		reason = "no_candidate"
	var now := _now()
	if str(_scan_reason.get(id, "")) == reason \
			and now - float(_scan_log_at.get(id, -10000.0)) < 10.0:
		return
	_scan_reason[id] = reason
	_scan_log_at[id] = now
	_debug("request scan skip id=%s reasons=%s" % [id, reason])


## The request state for Show data's REQUEST section. Live-state reads only; no scene write.
func debug_rows(pony: Node) -> Array[String]:
	var rows: Array[String] = []
	var id := _venue.pony_id(pony) if is_instance_valid(pony) else ""
	if id.is_empty():
		rows.append("no relationship id")
		return rows
	var runtime: Variant = main.call("runtime_for", pony) if is_instance_valid(main) else null
	var section := COOLDOWNS.section()
	var heat := _in_heat(runtime)
	var wait := COOLDOWNS.wait_seconds(section, id, heat)
	var last := COOLDOWNS.last(section, id)
	rows.append("id=%s" % id)
	rows.append("cooldown ready=%s" % str(COOLDOWNS.ready_for(id, heat)))
	rows.append("last request=%s" % (
		Time.get_datetime_string_from_unix_time(int(last), true) if last > 0.0 else "never"))
	rows.append("wait seconds=%.0f" % wait)
	var retry_left := float(_retry_at.get(id, -100000.0)) - _now()
	rows.append("retry left=%s" % ("none" if retry_left <= 0.0 else "%.0fs" % retry_left))
	rows.append("reasoning pending=%s" % str(_reasoning_pending))
	if _episode != null and _episode.pony == pony:
		rows.append("episode phase=%s pose=%s private=%s" % [
			_phase_name(_episode.phase),
			_episode.option.pose if _episode.option != null else "",
			str(_episode.private)])
	else:
		rows.append("episode=none")
	rows.append("last scan skip=%s" % str(_scan_reason.get(id, "none")))
	return rows


# --------------------------------------------------------------------------- approach

## Walk to Anon and settle there; a failed claim or goal closes with its reason.
func _walk_to_player(player: Node3D) -> String:
	var pony: Node3D = _episode.pony
	_episode.phase = Phase.APPROACH
	_episode.arrive_until = _now() + POLICY.ARRIVE_WAIT_S
	_episode.player_start = player.global_position
	_episode.region = str(_venue.region_of(player.global_position))
	var reason := _claim("approach nav claim")
	if not reason.is_empty():
		return reason
	var nav: Node = _episode.nav
	_venue.ensure_stand(pony)
	if player.global_position.distance_to(pony.global_position) <= POLICY.ARRIVE_RANGE_M:
		_arrive()
		return ""
	var forward: Vector3 = _venue.camera_forward()
	var goal: Variant = nav.call("command_support",
		player.global_position + forward * POLICY.APPROACH_GOAL_M)
	if goal is Vector3 and (goal as Vector3).is_finite() \
			and absf((goal as Vector3).y - pony.global_position.y) <= 3.0:
		if not bool(nav.call("command_destination", goal, "trot")):
			return _close_episode("approach destination")
		return ""
	return _close_episode("approach goal")


func _tick_approach() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	if not is_instance_valid(pony) or not is_instance_valid(nav):
		_close_episode("approach lost")
		return
	if not _episode.forced and is_instance_valid(_adapter) \
			and not bool(_adapter.call("quiet", POLICY.QUIET_CHAT_GAP_S)):
		_close_episode("approach quiet")
		return
	var player: Node3D = _venue.player()
	if not is_instance_valid(player):
		_close_episode("approach player lost")
		return
	if str(_venue.region_of(player.global_position)) != _episode.region \
			or player.global_position.distance_to(_episode.player_start) \
			> POLICY.PLAYER_MOVE_CANCEL_M:
		_close_episode("approach player moved")
		return
	if not bool(_venue.nav_owned(nav, _episode.token)):
		_close_episode("approach owner")
		return
	if _now() > _episode.started_at + POLICY.APPROACH_TIMEOUT_S:
		_close_episode("approach timeout")
		return
	if player.global_position.distance_to(pony.global_position) > POLICY.ARRIVE_RANGE_M:
		return
	_arrive()


func _arrive() -> void:
	var nav: Node = _episode.nav
	if not is_instance_valid(_episode.pony) or not is_instance_valid(nav):
		_close_episode("arrive lost")
		return
	_venue.stay(nav)
	_episode.phase = Phase.ARRIVE
	_episode.arrive_until = _now() + POLICY.ARRIVE_WAIT_S


func _tick_arrive() -> void:
	var pony: Node3D = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_close_episode("arrive pony lost")
		return
	var player: Node3D = _venue.player()
	if not is_instance_valid(player) \
			or player.global_position.distance_to(pony.global_position) \
			> POLICY.ARRIVE_RANGE_M + 0.75:
		if _now() >= _episode.arrive_until:
			_close_episode("arrive target moved")
		return
	if _now() < _episode.arrive_until:
		return
	_start_ask_handoff()


# --------------------------------------------------------------------------- bed approach

## A bed offer walks to the bed front, not to Anon. Asking from the bed avoids a blocked
## approach spot when he is already lying down.
func _lead_to_bed() -> String:
	_episode.phase = Phase.BED_APPROACH
	var found: Dictionary = _venue.find_bed_for(_episode.pony)
	if found.is_empty() or found.get("bed") != _episode.option.bed:
		return _close_episode("bed approach")
	var front: Variant = found.get("front")
	if not front is Vector3:
		return _close_episode("bed approach")
	_episode.bed_front = front
	var reason := _claim("bed approach nav claim")
	if not reason.is_empty():
		return reason
	_venue.ensure_stand(_episode.pony)
	if _episode.pony.global_position.distance_to(front) <= 1.2:
		_venue.stay(_episode.nav)
		return _start_ask_handoff()
	if not bool(_episode.nav.call("command_destination", front, "trot")):
		return _close_episode("bed approach destination")
	return ""


func _tick_bed_approach() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	var front: Variant = _episode.bed_front
	if not is_instance_valid(pony) or not is_instance_valid(nav) or not front is Vector3:
		_close_episode("bed approach lost")
		return
	if not bool(_venue.nav_owned(nav, _episode.token)):
		_close_episode("bed approach owner")
		return
	if _now() - _episode.started_at > POLICY.BED_LEAD_TIMEOUT_S:
		_close_episode("bed approach timeout")
		return
	if pony.global_position.distance_to(front) <= 1.4 \
			or not bool(_venue.nav_has_target(nav)):
		_venue.stay(nav)
		_start_ask_handoff()


# --------------------------------------------------------------------------- ask and handoff

## A cuddle asks from the bed without a navigator claim: the cuddle session owns her. A non-cuddle
## claims the navigator here when no approach did, and a standing ask also asks her to stand.
func _ask_now() -> String:
	_episode.phase = Phase.ASK
	if not _episode.option.cuddle:
		var reason := _claim("ask nav claim")
		if not reason.is_empty():
			return reason
		if _episode.option.pose == CATALOG.STANDING:
			_venue.ensure_stand(_episode.pony)
	return _start_ask_handoff()


## Claim the navigator for this route, or close with `reason`. The venue always stops her first.
func _claim(reason: String) -> String:
	var claim: Dictionary = _venue.claim_nav(_episode.pony, _episode.token)
	if claim.is_empty():
		return _close_episode(reason)
	_apply_claim(_episode, claim)
	return ""


## Form the Mare offer and hand it to the Negotiation service, then speak the ask line. The
## request lease moves to the negotiation at formation; a refused handoff releases it and sets the
## short retry. Returns the close reason on failure, `""` after a successful handoff.
func _start_ask_handoff() -> String:
	if _episode == null:
		return ""
	var runtime: Node = _episode.runtime
	var pony: Node3D = _episode.pony
	var option: POSE_OPTIONS.Option = _episode.option
	if not is_instance_valid(runtime) or not is_instance_valid(pony) or option == null:
		return _close_episode("ask lost")
	# The place can have changed since the scan; only a hard scene failure closes the ask. An
	# unfilled bed gate or a player not yet in position is the Agreement's live condition.
	var verdict: Variant = runtime.call("scene_only_verdict", option.pose, option.source,
		option.bed, null)
	if verdict == null or not bool(verdict.hard_ok):
		return _close_episode("ask scene")
	_episode.private = _private_now(pony, option.cuddle)
	var request := _request(_episode.private, option, _episode.context)
	var line := PROMPTS.ask_context(request)
	var fields := {
		"runtime": runtime, "pony": pony, "option": option,
		"base": _episode.base, "private": _episode.private,
		"hold_token": "" if option.cuddle else _episode.token,
		"hold_old_wander": _episode.prev_wander,
		"line": _offer_line(option), "cuddle": option.cuddle,
	}
	var episode := _episode
	# The request's speed and pace overrides are not part of the negotiation lease.
	_venue.restore_limits(episode.nav, episode.prev_limit, episode.prev_pace)
	var handed := bool(main.call("form_mare_offer", fields))
	if not handed:
		return _close_episode("handoff refused")
	_episode = null
	if episode.option.cuddle:
		_cuddle_asked[episode.id] = true
	var started := false
	if is_instance_valid(_adapter):
		started = bool(_adapter.call("begin_greeting", episode.id, line))
	if not started and is_instance_valid(_adapter):
		var key := "%s:%s:%d:ask" % [KEY_PREFIX, episode.id, episode.serial]
		_adapter.call("queue", episode.id, PROMPTS.ask_purpose(request), key,
			Callable(self, "_line_valid").bind(runtime), true)
	if is_instance_valid(_adapter):
		_adapter.call("record_situation", PROMPTS.situation_ask(request), [episode.id],
			"%s:%s:%d:situation" % [KEY_PREFIX, episode.id, episode.serial])
	_debug("request ask %s pose=%s private=%s cuddle=%s" % [
		episode.id, option.pose, str(episode.private), str(option.cuddle)])
	return ""


## The Anon decision classifier's offer context: what she just asked him.
func _offer_line(option: POSE_OPTIONS.Option) -> String:
	if option.cuddle or option.pose == CATALOG.MISSIONARY:
		return "The pony has just invited Anon to bed. She is waiting for his answer."
	return "The pony has just asked Anon to have sex. She is waiting for his answer."


## The ask line is still worth speaking while the runtime is idle and its pony is in the tree.
func _line_valid(runtime: Node) -> bool:
	if not is_instance_valid(runtime) or int(runtime.get("state")) != 0:
		return false
	var pony: Variant = runtime.get("pony")
	return is_instance_valid(pony) and (pony as Node).is_inside_tree()


# --------------------------------------------------------------------------- privacy and context

func _private_now(pony: Node, cuddle: bool) -> bool:
	return _privacy.cuddle_private(pony) if cuddle else _privacy.offer_private(pony)


## The cuddle offer must be the same offer the act key would start.
func _offer_targets_pony(pony: Node) -> bool:
	if not is_instance_valid(_offer) or not is_instance_valid(pony):
		return false
	var target: Node = _offer.offer_target()
	return is_instance_valid(target) and target == pony


func _context(pony: Node) -> CONTEXT.Context:
	var facts: Variant = main.call("context_facts", pony) if is_instance_valid(main) else null
	return CONTEXT.build(facts if facts is Dictionary else {})


## The pure request facts for one wording call.
func _request(private: bool, option: POSE_OPTIONS.Option, context: CONTEXT.Context = null) -> FACTS.Request:
	var out := FACTS.Request.new()
	out.pose = option.pose
	out.cuddle = option.cuddle
	out.private = private
	out.heat = context != null and context.heat
	out.relation_note = context.relation_note if context != null else ""
	out.history_note = context.history_note if context != null else ""
	return out


# --------------------------------------------------------------------------- close and tick

func _apply_claim(episode: Candidate, claim: Dictionary) -> void:
	episode.nav = claim.get("nav")
	episode.prev_owner = str(claim.get("owner", ""))
	episode.prev_wander = bool(claim.get("wander", true))
	episode.prev_limit = claim.get("limit")
	episode.prev_pace = claim.get("pace")


## The one request close path. Stamps the short retry for any non-empty reason and returns it, so a
## route can report the close. The negotiator owns the lease after a successful handoff, so this
## only handles the request's own attempt.
func _close_episode(reason: String) -> String:
	if _episode == null:
		return reason
	var id := _episode.id
	var phase := _phase_name(_episode.phase)
	if is_instance_valid(_episode.nav):
		_venue.release_nav(_episode.nav, _episode.token, _episode.prev_owner,
			_episode.prev_wander, _episode.prev_limit, _episode.prev_pace)
	if not reason.is_empty():
		_retry_at[id] = _now() + POLICY.RETRY_S
		_debug("request end %s phase=%s reason=%s" % [id, phase, reason])
	_episode = null
	return reason


func _tick_episode() -> void:
	match _episode.phase:
		Phase.APPROACH:
			_tick_approach()
		Phase.ARRIVE:
			_tick_arrive()
		Phase.BED_APPROACH:
			_tick_bed_approach()
		_:
			_close_episode("unknown phase")


# --------------------------------------------------------------------------- helpers

## Present and awake; the caller has already rejected a busy runtime.
func _available(pony: Node3D) -> bool:
	return is_instance_valid(pony) and not bool(pony.get("sleeping"))


func _in_heat(runtime: Variant) -> bool:
	return is_instance_valid(runtime) and runtime.has_method("cycle_phase") \
		and str(runtime.call("cycle_phase")) == CYCLE.HEAT


func _eligibility() -> RefCounted:
	if not is_instance_valid(main):
		return null
	return main.get("eligibility")


func _phase_name(phase: int) -> String:
	return str(PHASE_NAMES.get(phase, POLICY.PHASE_NONE))


func _reason_name(reason: String) -> String:
	return "none" if reason.is_empty() else reason


func _runtime_name(runtime: Node) -> String:
	if not is_instance_valid(runtime):
		return "?"
	var pony: Variant = runtime.get("pony")
	return str(pony.name) if is_instance_valid(pony) else "?"


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _debug(text: String) -> void:
	LOG.debug(text)


func _reply_text(reply: String) -> String:
	var text := reply.strip_edges()
	return text if text.length() <= 512 else text.left(512) + "..."
