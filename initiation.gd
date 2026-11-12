extends Node
## Proactive sex requests. One episode at a time: she waits for a quiet moment, walks to Anon when
## needed, asks in character, reminds him twice, then gives up. A private standing offer is asked
## while standing; after Anon accepts she presents, comments on the pose and waits for Y. Nothing
## starts until the player presses Y.
##
## The facade owns the episode, admission and phase orchestration. Rules are
## `initiation/policy.gd`, wording is `initiation/prompts.gd`, and every scene read is behind
## `initiation/conversation.gd` (director, classifier, world context) or `initiation/venue.gd`
## (navigator, posture, beds, privacy). See `docs/initiation.md`.
##
## Request eligibility is the existing relationship/social gate, not the act-time readiness
## meter. Automatic requests are background AI turns, so they require AI usage Full.

const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const FACTS := preload("res://mods/unfplap/initiation/facts.gd")
const PROMPTS := preload("res://mods/unfplap/initiation/prompts.gd")
const CONVERSATION := preload("res://mods/unfplap/initiation/conversation.gd")
const VENUE := preload("res://mods/unfplap/initiation/venue.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const CONSENT := preload("res://mods/unfplap/consent_classifier.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/relationship_cue.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
const REST_CONTROL := preload("res://mods/unfplap/rest_control.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

const KEY_PREFIX := "unfplap:request"

## Episode phases. The pure phase tables are spelled in `initiation/policy.gd`.
enum Phase { NONE, APPROACH, ARRIVE, ASK, PRESENT, INVITE, BED_APPROACH, BED_LEAD, BED_WAIT }
const PHASE_NAMES := {
	Phase.NONE: POLICY.PHASE_NONE,
	Phase.APPROACH: POLICY.PHASE_APPROACH,
	Phase.ARRIVE: POLICY.PHASE_ARRIVE,
	Phase.ASK: POLICY.PHASE_ASK,
	Phase.PRESENT: POLICY.PHASE_PRESENT,
	Phase.INVITE: POLICY.PHASE_INVITE,
	Phase.BED_APPROACH: POLICY.PHASE_BED_APPROACH,
	Phase.BED_LEAD: POLICY.PHASE_BED_LEAD,
	Phase.BED_WAIT: POLICY.PHASE_BED_WAIT,
}


## One candidate offer: scene handles plus the values admission and the debug log need.
class Candidate extends RefCounted:
	var id := ""
	var runtime: Node
	var pony: Node3D
	var pose := ""
	var source := ""
	var bed: Node
	var rest: Node
	## A `Vector3` front spot for a bed invite, or null.
	var front: Variant = null
	var private := false
	var cuddle := false
	var bed_invite := false
	var weight := 0.0
	var forced := false


## One live request episode. The facade owns it and clears it on every exit; it is never stored
## across a world.
class Episode extends RefCounted:
	var serial := 0
	## A `Phase` value. Inner classes cannot see the script enum, so 0 is `Phase.NONE`.
	var phase := 0
	var id := ""
	var runtime: Node
	var pony: Node3D
	var pose := ""
	var source := ""
	var bed: Node
	var rest: Node
	## A `Vector3` spot, or null.
	var front: Variant = null
	var private := false
	var cuddle := false
	var bed_invite := false
	var forced := false
	var started_at := 0.0
	var arrive_until := 0.0
	var ask_started := 0.0
	var deadline_at := 0.0
	var prompts_sent := 0
	var present_until := 0.0
	var invite_started := 0.0
	var invite_queued := false
	var accepted_at := 0.0
	var represent_count := 0
	var bed_approach_started := 0.0
	var bed_lead_started := 0.0
	var bed_wait_started := 0.0
	var bed_join_tries := 0
	var bed_join_retry_at := 0.0
	var bed_joining := false
	var bed_joined := false
	var clarified := false
	var consent_pending := false
	var consent_started := false
	var consent_intent := ""
	var consent_source := ""
	var consent_key := ""
	var consent_text := ""
	var reply_seen := false
	var reacted := false
	var response_text := ""
	var keys: Array[String] = []
	var nav: Node
	var token := ""
	var prev_owner := ""
	var prev_wander := true
	var prev_limit: Variant = null
	var prev_pace: Variant = null
	var nav_released := false
	var player_start := Vector3.ZERO
	var region := ""
	## A `Vector3` walk goal, or null.
	var goal: Variant = null
	var privacy_report := ""
	var privacy_log_at := -1000.0


## What `force()` produced. `reject` is the comma-joined candidate reasons on failure.
class ForceResult extends RefCounted:
	var ok := false
	var id := ""
	var pose := ""
	var reject := ""


var main: Node
var _episode: Episode = null
var _scan_clock := 0.0
var _serial := 0
## id -> whether she was cuddling on the last scan.
var _cuddle_seen: Dictionary = {}
## id -> whether this cuddle has already produced an ask.
var _cuddle_asked: Dictionary = {}
## id -> the short retry deadline after a failed walk-over or unavailable ask.
var _retry_at: Dictionary = {}
var _conversation: Node
var _venue: Node


func setup(main_node: Node) -> void:
	main = main_node
	_conversation = CONVERSATION.new()
	_conversation.name = "UnfplapRequestThought"
	_conversation.call("bind", main_node, Callable(self, "_on_player_transcript"))
	add_child(_conversation)
	_venue = VENUE.new()
	_venue.name = "UnfplapRequestPlace"
	_venue.call("bind", main_node)
	add_child(_venue)


func tick(delta: float) -> void:
	if not is_instance_valid(main):
		return
	if _episode != null:
		_tick_episode(delta)
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
		_cancel_episode(false)
	if is_instance_valid(_conversation):
		_conversation.call("unhook")
		_conversation.call("cancel_scope")
	_cuddle_seen.clear()
	_cuddle_asked.clear()
	_retry_at.clear()
	_scan_clock = 0.0


## Manual lab/debug entry point: bypass the quiet, cooldown and AI-usage checks, but keep the
## relationship, consent and pose gates. An empty `pose` lets the mare choose.
func force(runtime: Node, pose := "") -> ForceResult:
	var out := ForceResult.new()
	if not is_instance_valid(main) or not is_instance_valid(runtime):
		out.reject = "no_runtime"
		return out
	if _episode != null:
		_cancel_episode(false)
	var reasons: Array = []
	var candidate := _candidate_for(runtime, true, pose, reasons)
	out.reject = ",".join(PackedStringArray(reasons))
	if candidate == null:
		_debug("request force reject %s pose=%s reasons=%s" % [
			_runtime_name(runtime), "any" if pose.is_empty() else pose, out.reject])
		return out
	out.reject = ""
	candidate.forced = true
	_serial += 1
	var player: Node3D = _venue.call("player")
	var near := is_instance_valid(player) and is_instance_valid(candidate.pony) \
		and player.global_position.distance_to(candidate.pony.global_position) \
		<= POLICY.ARRIVE_RANGE_M
	if candidate.bed_invite:
		_start_bed_approach(candidate)
	elif near:
		_start_ask(candidate)
	else:
		_start_approach(candidate)
	out.ok = _episode != null
	out.id = candidate.id
	out.pose = candidate.pose
	_debug("request force %s pose=%s" % [candidate.id, candidate.pose])
	return out


## Called before a normal Y start. The act owns the pony now.
func cancel_for(pony: Node) -> void:
	if is_instance_valid(pony) and _episode != null and _episode.pony == pony:
		# The act start owns the bed now; do not stand her up before runtime.start().
		_cancel_episode(true, "", true)
		return
	if is_instance_valid(pony):
		var runtime: Variant = main.call("runtime_for", pony) if is_instance_valid(main) else null
		if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
			runtime.call("clear_presentation")


# --------------------------------------------------------------------------- cuddle edge and cooldown

func _tick_cuddle_edges() -> void:
	for node: Variant in _venue.call("mares"):
		if not is_instance_valid(node):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime) or not runtime.has_method("cuddle_active"):
			continue
		var id: String = _venue.call("pony_id", node)
		if id.is_empty():
			continue
		var active := bool(runtime.call("cuddle_active"))
		var seen := bool(_cuddle_seen.get(id, false))
		if active and not seen:
			_cuddle_seen[id] = true
			_cuddle_asked[id] = false
			_clear_cooldown(id)
		elif not active and seen:
			_cuddle_seen[id] = false
			_cuddle_asked[id] = false


func _cooldown_ok(id: String, in_heat := false) -> bool:
	var mods := _mods()
	if mods == null:
		return true
	var section: Dictionary = mods.call("state", "unfplap")
	var times: Variant = section.get("request_times", {})
	if not times is Dictionary:
		times = {}
	var last := float((times as Dictionary).get(id, -100000.0))
	var history := ACT_HISTORY.effective_row(section, id, ACT_HISTORY.day_now())
	var wait := ACT_HISTORY.offer_cooldown(history)
	if in_heat:
		wait = POLICY.heat_cooldown(wait)
	return POLICY.cooldown_ready(Time.get_unix_time_from_system(), last, wait)


func _set_cooldown(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var section: Dictionary = mods.call("state", "unfplap")
	var times: Variant = section.get("request_times", {})
	if not times is Dictionary:
		times = {}
	(times as Dictionary)[id] = Time.get_unix_time_from_system()
	section["request_times"] = times
	mods.call("save_changed")


func _clear_cooldown(id: String) -> void:
	if id.is_empty():
		return
	var mods := _mods()
	if mods == null:
		return
	var section: Dictionary = mods.call("state", "unfplap")
	var times: Variant = section.get("request_times", {})
	if not times is Dictionary or not (times as Dictionary).has(id):
		return
	(times as Dictionary).erase(id)
	section["request_times"] = times
	mods.call("save_changed")


func _mods() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Mods")


# --------------------------------------------------------------------------- candidate

func _consider_start() -> void:
	if not bool(_conversation.call("quiet")):
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		return
	var cuddles: Array = []
	var offers: Array = []
	for node: Variant in _venue.call("mares"):
		if not is_instance_valid(node):
			continue
		if main.has_method("is_adult_mare") and not bool(main.call("is_adult_mare", node)):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime):
			continue
		var candidate := _candidate_for(runtime, false)
		if candidate == null:
			continue
		if candidate.cuddle:
			cuddles.append(candidate)
		else:
			offers.append(candidate)
	var chosen: Candidate = null
	if not cuddles.is_empty():
		chosen = _pick_weighted(cuddles)
	elif not offers.is_empty():
		chosen = _pick_weighted(offers)
	if chosen == null:
		return
	_serial += 1
	var near := is_instance_valid(chosen.pony) \
		and player.global_position.distance_to(chosen.pony.global_position) <= POLICY.ARRIVE_RANGE_M
	if chosen.bed_invite:
		_start_bed_approach(chosen)
	elif near:
		_start_ask(chosen)
	else:
		_start_approach(chosen)


func _pick_weighted(items: Array) -> Candidate:
	var weights: Array = []
	for item: Variant in items:
		weights.append((item as Candidate).weight)
	var index := POLICY.weighted_pick(weights, randf())
	if index < 0:
		return null
	return items[index]


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
	var id: String = _venue.call("pony_id", pony)
	if id.is_empty():
		reasons.append("no_id")
		return null
	var verdict: ELIGIBILITY.Verdict = null
	var service := _eligibility()
	if service != null:
		verdict = service.get_verdict(pony, ELIGIBILITY.Mode.OFFER)
	if not forced and not _cooldown_ok(id, _in_heat(runtime)):
		reasons.append("cooldown")
		return null
	if not forced and not POLICY.retry_ready(_now(), float(_retry_at.get(id, -100000.0))):
		reasons.append("retry")
		return null
	var cuddle := bool(runtime.call("cuddle_active")) if runtime.has_method("cuddle_active") else false
	if pose_request == CATALOG.MISSIONARY or (pose_request.is_empty() and cuddle):
		var bed_candidate := _cuddle_candidate(runtime, forced, reasons, verdict) if cuddle \
			else _bed_candidate(runtime, forced, reasons, verdict)
		if bed_candidate != null or not pose_request.is_empty():
			return bed_candidate
	var standing_candidate := _standing_candidate(runtime, forced, reasons, verdict)
	if pose_request == CATALOG.STANDING:
		return standing_candidate
	if cuddle:
		return null
	var bed := _bed_candidate(runtime, forced, reasons, verdict)
	var pose := POLICY.pick_offer_pose(bed != null, standing_candidate != null, randf())
	if pose == CATALOG.MISSIONARY:
		return bed
	if pose == CATALOG.STANDING:
		return standing_candidate
	return null


func _history_row(id: String) -> Dictionary:
	return ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())


func _cuddle_candidate(runtime: Node, forced: bool, reasons: Array = [],
		verdict_in: ELIGIBILITY.Verdict = null) -> Candidate:
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		reasons.append("cuddle:no_pony")
		return null
	var id: String = _venue.call("pony_id", pony)
	if id.is_empty():
		reasons.append("cuddle:no_id")
		return null
	if not forced and bool(_cuddle_asked.get(id, false)):
		reasons.append("cuddle:asked")
		return null
	if not _cuddle_privacy_ok(pony):
		reasons.append("cuddle:privacy")
		return null
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var source := "already_lying" if PLAYER_FORM.is_pony(form) else "bed_side"
	var bed: Variant = runtime.call("find_bed_under")
	if not is_instance_valid(bed):
		reasons.append("cuddle:no_bed_under")
		return null
	var gate: Dictionary = runtime.call("offer_verdict", CATALOG.MISSIONARY, source, bed, forced,
		verdict_in)
	if not bool(gate.get("ok", false)):
		_append_gate_reasons(reasons, "cuddle", gate)
		return null
	if not _offer_targets_pony(pony):
		reasons.append("cuddle:target")
		return null
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	var out := Candidate.new()
	out.pony = pony
	out.runtime = runtime
	out.id = id
	out.pose = CATALOG.MISSIONARY
	out.source = source
	out.bed = bed
	out.private = true
	out.cuddle = true
	out.forced = forced
	out.weight = policy.offer_weight if policy != null else 0.0
	return out


func _bed_candidate(runtime: Node, forced: bool, reasons: Array = [],
		verdict_in: ELIGIBILITY.Verdict = null) -> Candidate:
	var pony: Node3D = runtime.get("pony") if is_instance_valid(runtime) else null
	if not is_instance_valid(pony):
		reasons.append("bed:no_pony")
		return null
	var found: Dictionary = _venue.call("find_bed_for", pony)
	if found.is_empty():
		reasons.append("bed:no_free_bed")
		return null
	var bed: Node3D = found.get("bed")
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var source := "already_lying" if PLAYER_FORM.is_pony(form) else "bed_side"
	var gate: Dictionary = runtime.call("offer_verdict", CATALOG.MISSIONARY, source, bed, forced,
		verdict_in)
	if not bool(gate.get("ok", false)):
		_append_gate_reasons(reasons, "bed", gate)
		return null
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	var out := Candidate.new()
	out.pony = pony
	out.runtime = runtime
	out.id = _venue.call("pony_id", pony)
	out.pose = CATALOG.MISSIONARY
	out.source = source
	out.bed = bed
	out.rest = found.get("rest")
	out.front = found.get("front")
	out.private = _private_at_player(pony)
	out.bed_invite = true
	out.forced = forced
	out.weight = policy.offer_weight if policy != null else 0.0
	return out


func _standing_candidate(runtime: Node, forced: bool, reasons: Array = [],
		verdict_in: ELIGIBILITY.Verdict = null) -> Candidate:
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		reasons.append("standing:no_pony")
		return null
	var gate: Dictionary = runtime.call("offer_verdict", CATALOG.STANDING, "", null, forced,
		verdict_in)
	if not bool(gate.get("ok", false)):
		_append_gate_reasons(reasons, "standing", gate)
		return null
	if not bool(_venue.call("can_approach", pony, reasons)):
		return null
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	var out := Candidate.new()
	out.pony = pony
	out.runtime = runtime
	out.id = _venue.call("pony_id", pony)
	out.pose = CATALOG.STANDING
	out.private = _private_at_player(pony)
	out.forced = forced
	out.weight = policy.offer_weight if policy != null else 0.0
	return out


func _append_gate_reasons(reasons: Array, label: String, gate: Dictionary) -> void:
	var failed: PackedStringArray = []
	for row: ELIGIBILITY.Row in gate.get("rows", []):
		if not row.ok:
			failed.append(row.reason)
	reasons.append("%s:%s" % [label, ",".join(failed)])


# --------------------------------------------------------------------------- privacy

func _private_at_player(except: Node = null) -> bool:
	var public_offer := is_instance_valid(except) and _public_offer_ok(except)
	return bool(_venue.call("private_at_player", except, public_offer))


func _cuddle_privacy_ok(pony: Node3D) -> bool:
	var public_offer := is_instance_valid(pony) and _public_offer_ok(pony)
	return bool(_venue.call("cuddle_privacy", pony, public_offer))


## Heat and per-mare public consent override the privacy reserve, for every kind of offer. The
## exact rule is in `docs/eligibility.md`.
func _public_offer_ok(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	var service := _eligibility()
	if service == null:
		return false
	return service.get_verdict(pony, ELIGIBILITY.Mode.OFFER).actions.public_offer


## The cuddle offer must be the same offer Y would start.
func _offer_targets_pony(pony: Node) -> bool:
	if not is_instance_valid(main) or not is_instance_valid(pony) or not main.has_method("offer_target"):
		return false
	var target: Variant = main.call("offer_target")
	return is_instance_valid(target) and target == pony


func _log_privacy_once(target: Node) -> void:
	if not is_instance_valid(main) or _episode == null:
		return
	var now := _now()
	if now - _episode.privacy_log_at < 1.0:
		return
	var public_offer := is_instance_valid(target) and _public_offer_ok(target)
	var report := str(_venue.call("privacy_report", target, public_offer,
		_private_at_player(target)))
	if _episode.privacy_report == report:
		return
	_episode.privacy_report = report
	_episode.privacy_log_at = now
	_debug("request privacy " + report)


# --------------------------------------------------------------------------- approach

func _start_approach(candidate: Candidate) -> void:
	var pony: Node3D = candidate.pony
	var runtime: Node = candidate.runtime
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(pony) or not is_instance_valid(runtime) or not is_instance_valid(player):
		return
	if not is_instance_valid(_venue.call("nav_for", pony)):
		return
	var episode := Episode.new()
	episode.serial = _serial
	episode.phase = Phase.ARRIVE
	episode.pony = pony
	episode.runtime = runtime
	episode.id = candidate.id
	episode.pose = candidate.pose
	episode.source = candidate.source
	episode.bed = candidate.bed
	episode.private = candidate.private
	episode.bed_invite = candidate.bed_invite
	episode.rest = candidate.rest
	episode.front = candidate.front
	episode.started_at = _now()
	episode.arrive_until = _now() + POLICY.ARRIVE_WAIT_S
	episode.player_start = player.global_position
	episode.region = str(_venue.call("region_of", player.global_position))
	episode.forced = candidate.forced
	episode.token = KEY_PREFIX + ":" + candidate.id
	_episode = episode
	_conversation.call("hook")
	_log_privacy_once(pony)
	var claim: Dictionary = _venue.call("claim_nav", pony, episode.token, true)
	if claim.is_empty():
		_cancel_episode(false)
		return
	_apply_claim(claim)
	_venue.call("stand", pony)
	if player.global_position.distance_to(pony.global_position) <= POLICY.ARRIVE_RANGE_M:
		_arrive()
		return
	var forward: Vector3 = _venue.call("camera_forward")
	var goal: Variant = episode.nav.call("command_support",
		player.global_position + forward * POLICY.APPROACH_GOAL_M)
	if goal is Vector3 and (goal as Vector3).is_finite() \
			and absf((goal as Vector3).y - pony.global_position.y) <= 3.0:
		episode.goal = goal
		if not bool(episode.nav.call("command_destination", goal, "trot")):
			_cancel_episode(false)
		return
	_cancel_episode(false)


func _tick_approach() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	if not is_instance_valid(pony) or not is_instance_valid(nav):
		_cancel_episode(false)
		return
	if not _episode.forced and not bool(_conversation.call("quiet")):
		_cancel_episode(false)
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		_cancel_episode(false)
		return
	if str(_venue.call("region_of", player.global_position)) != _episode.region \
			or player.global_position.distance_to(_episode.player_start) \
			> POLICY.PLAYER_MOVE_CANCEL_M:
		_cancel_episode(false)
		return
	if not bool(_venue.call("nav_owned", nav, _episode.token)):
		_cancel_episode(false)
		return
	if _now() > _episode.started_at + POLICY.APPROACH_TIMEOUT_S:
		_cancel_episode(false)
		return
	if player.global_position.distance_to(pony.global_position) > POLICY.ARRIVE_RANGE_M:
		return
	_arrive()


func _arrive() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	if not is_instance_valid(pony) or not is_instance_valid(nav):
		_cancel_episode(false)
		return
	_venue.call("stay", nav)
	_episode.phase = Phase.ARRIVE
	_episode.arrive_until = _now() + POLICY.ARRIVE_WAIT_S


func _tick_arrive() -> void:
	var pony: Node3D = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(false)
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player) \
			or player.global_position.distance_to(pony.global_position) \
			> POLICY.ARRIVE_RANGE_M + 0.75:
		if _now() >= _episode.arrive_until:
			_cancel_episode(false, "arrive target moved")
		return
	_episode.private = _private_at_player(pony)
	_log_privacy_once(pony)
	_issue_initial()


# --------------------------------------------------------------------------- bed invitation

## A bed offer walks to the bed front, not to Anon. Asking from the bed avoids a blocked
## approach spot when he is already lying down.
func _start_bed_approach(candidate: Candidate) -> void:
	if _episode != null:
		return
	var pony: Node3D = candidate.pony
	var runtime: Node = candidate.runtime
	var rest: Node = candidate.rest
	var front: Variant = candidate.front
	if not is_instance_valid(pony) or not is_instance_valid(runtime) \
			or not is_instance_valid(rest) or not front is Vector3:
		return
	var episode := Episode.new()
	episode.serial = _serial
	episode.pony = pony
	episode.runtime = runtime
	episode.id = candidate.id
	episode.pose = CATALOG.MISSIONARY
	episode.source = candidate.source
	episode.bed = candidate.bed
	episode.private = candidate.private
	episode.bed_invite = true
	episode.rest = rest
	episode.front = front
	episode.phase = Phase.BED_APPROACH
	episode.started_at = _now()
	episode.bed_approach_started = _now()
	episode.forced = candidate.forced
	episode.token = KEY_PREFIX + ":" + candidate.id
	_episode = episode
	_conversation.call("hook")
	_log_privacy_once(pony)
	var nav := _claim_nav(pony)
	if nav == null:
		_cancel_episode(false)
		return
	_venue.call("ensure_stand", pony)
	if pony.global_position.distance_to(front) <= 1.2:
		_venue.call("stay", nav)
		_arrive_bed_ask()
		return
	if not bool(nav.call("command_destination", front, "trot")):
		_cancel_episode(false)


func _arrive_bed_ask() -> void:
	_episode.phase = Phase.ASK
	_issue_initial()


func _tick_bed_approach() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	var front: Variant = _episode.front
	if not is_instance_valid(pony) or not is_instance_valid(nav) or not front is Vector3:
		_cancel_episode(false, "bed approach lost")
		return
	if not bool(_venue.call("nav_owned", nav, _episode.token)):
		_cancel_episode(false, "bed approach owner")
		return
	if _now() - _episode.bed_approach_started > POLICY.BED_LEAD_TIMEOUT_S:
		_cancel_episode(false, "bed approach timeout")
		return
	if pony.global_position.distance_to(front) <= 1.4 \
			or not bool(_venue.call("nav_has_target", nav)):
		_venue.call("stay", nav)
		_arrive_bed_ask()


## Walk her to the offered bed and wait for Anon to lie down. The native bed rest seats her
## once he is reclined; only then is the missionary pose actually startable.
func _start_bed_lead() -> bool:
	var pony: Node3D = _episode.pony
	var rest: Node = _episode.rest
	if not is_instance_valid(pony) or not is_instance_valid(rest):
		return false
	var front: Variant = _episode.front
	if not front is Vector3 or not (front as Vector3).is_finite():
		front = _venue.call("rest_front", rest, pony)
	if not front is Vector3 or not (front as Vector3).is_finite():
		return false
	var nav := _claim_nav(pony)
	if nav == null:
		return false
	_venue.call("ensure_stand", pony)
	_episode.front = front
	_episode.bed_lead_started = _now()
	if pony.global_position.distance_to(front) <= 1.2:
		_venue.call("stay", nav)
		_begin_bed_wait()
		return true
	if not bool(nav.call("command_destination", front, "trot")):
		return false
	_episode.phase = Phase.BED_LEAD
	_debug("request bed lead %s front=%s" % [_episode.id, str(front)])
	return true


func _begin_bed_wait() -> void:
	_episode.phase = Phase.BED_WAIT
	_episode.bed_wait_started = _now()
	_episode.bed_join_tries = 0
	_debug("request bed wait %s" % _episode.id)


func _tick_bed_lead() -> void:
	var pony: Node3D = _episode.pony
	var nav: Node = _episode.nav
	var front: Variant = _episode.front
	if not is_instance_valid(pony) or not is_instance_valid(nav) or not front is Vector3:
		_cancel_episode(false, "bed lead lost")
		return
	if not bool(_venue.call("nav_owned", nav, _episode.token)):
		_cancel_episode(false, "bed lead owner")
		return
	if _now() - _episode.bed_lead_started > POLICY.BED_LEAD_TIMEOUT_S:
		_give_up("bed walk timeout")
		return
	if pony.global_position.distance_to(front) <= 1.4 \
			or not bool(_venue.call("nav_has_target", nav)):
		_venue.call("stay", nav)
		_begin_bed_wait()


func _tick_bed_wait() -> void:
	var pony: Node3D = _episode.pony
	var runtime: Node = _episode.runtime
	var rest: Node = _episode.rest
	var bed: Variant = _episode.bed
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(pony) or not is_instance_valid(runtime) \
			or not is_instance_valid(rest) or not is_instance_valid(player) \
			or not is_instance_valid(bed):
		_cancel_episode(false, "bed wait lost")
		return
	if _now() - _episode.bed_wait_started > POLICY.BED_WAIT_TIMEOUT_S:
		_give_up("bed wait timeout")
		return
	if player.global_position.distance_to(pony.global_position) > POLICY.PRIVACY_RADIUS_M:
		_cancel_episode(false, "bed wait player left")
		return
	if not _episode.bed_joining:
		if not _player_in_bed(bed):
			return
		if _now() < _episode.bed_join_retry_at:
			return
		# The bed rest refuses an actor whose navigator is still owned by the request. Hand it
		# back without standing her up, then let the native invite take her onto the bed.
		_yield_nav_to_bed()
		runtime.call("set_request_face", false)
		if not bool(_venue.call("accept_bed", rest, pony)):
			_episode.bed_join_tries += 1
			_episode.bed_join_retry_at = _now() + 1.0
			if _episode.bed_join_tries >= 5:
				_give_up("bed join failed")
			return
		_episode.bed_joining = true
		_episode.bed_joined = true
		_debug("request bed join %s" % _episode.id)
	if not bool(runtime.call("can_show_start", CATALOG.MISSIONARY, _episode.source, bed)):
		if not _player_in_bed(bed):
			_cancel_episode(false, "bed player stood up")
		return
	if _episode.invite_queued:
		return
	if not _queue_invitation():
		_cancel_episode(false, "bed invite queue failed")
		return
	_episode.invite_queued = true
	_episode.phase = Phase.INVITE
	_episode.invite_started = _now()
	_debug("request invite %s pose=missionary" % _episode.id)


func _claim_nav(pony: Node3D) -> Node:
	if _episode == null:
		return null
	if _episode.token.is_empty():
		_episode.token = KEY_PREFIX + ":" + _episode.id
	var claim: Dictionary = _venue.call("claim_nav", pony, _episode.token)
	if claim.is_empty():
		return null
	if not is_instance_valid(_episode.nav):
		_apply_claim(claim)
	return _episode.nav


## Keep the navigator's previous state the first time it is claimed.
func _apply_claim(claim: Dictionary) -> void:
	_episode.nav = claim.get("nav")
	_episode.prev_owner = str(claim.get("owner", ""))
	_episode.prev_wander = bool(claim.get("wander", true))
	_episode.prev_limit = claim.get("limit")
	_episode.prev_pace = claim.get("pace")


func _yield_nav_to_bed() -> void:
	if _episode == null or _episode.nav_released:
		return
	_venue.call("stay", _episode.nav)
	_release_nav()
	_episode.nav_released = true


func _release_nav() -> void:
	if _episode == null or _episode.nav_released:
		return
	_venue.call("release_nav", _episode.nav, _episode.token, _episode.prev_owner,
		_episode.prev_wander, _episode.prev_limit, _episode.prev_pace)


func _player_in_bed(bed: Variant) -> bool:
	return bool(_venue.call("player_in_bed", bed))


# --------------------------------------------------------------------------- ask

func _start_ask(candidate: Candidate) -> void:
	if _episode != null:
		return
	var episode := Episode.new()
	episode.serial = _serial
	episode.pony = candidate.pony
	episode.runtime = candidate.runtime
	episode.id = candidate.id
	episode.pose = candidate.pose
	episode.source = candidate.source
	episode.bed = candidate.bed
	episode.private = candidate.private
	episode.cuddle = candidate.cuddle
	episode.bed_invite = candidate.bed_invite
	episode.rest = candidate.rest
	episode.front = candidate.front
	episode.phase = Phase.ASK
	episode.started_at = _now()
	episode.ask_started = _now()
	episode.forced = candidate.forced
	episode.token = KEY_PREFIX + ":" + candidate.id
	_episode = episode
	_conversation.call("hook")
	_issue_initial()


func _issue_initial() -> void:
	if not is_instance_valid(_episode.pony):
		_cancel_episode(false)
		return
	var started := bool(_conversation.call("begin_greeting", _episode.id, _ask_context()))
	if not started:
		started = bool(_conversation.call("queue", _episode.id, _ask_purpose(),
			"%s:%s:%d:ask" % [KEY_PREFIX, _episode.id, _episode.serial],
			Callable(self, "_episode_valid").bind(_episode.serial), false))
	if not started:
		_cancel_episode(false)
		return
	_episode.phase = Phase.ASK
	_episode.ask_started = _now()
	_episode.deadline_at = _now() + POLICY.GIVE_UP_S
	_episode.prompts_sent = 0
	if _episode.cuddle:
		_cuddle_asked[_episode.id] = true
	if _is_private_standing():
		var runtime: Node = _episode.runtime
		if is_instance_valid(runtime) and runtime.has_method("set_request_face"):
			runtime.call("set_request_face", true)
	_record_situation()
	_debug("request ask %s pose=%s private=%s cuddle=%s" % [
		_episode.id, _episode.pose, str(_episode.private), str(_episode.cuddle)])


func _is_private_offer() -> bool:
	return _episode != null and _episode.private


func _is_private_standing() -> bool:
	return _is_private_offer() and _episode.pose == CATALOG.STANDING


func _tick_ask(_delta: float) -> void:
	var pony: Node = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(true, "ask pony lost")
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		_cancel_episode(true, "ask player lost")
		return
	if not bool(runtime.call("can_offer", _episode.pose, _episode.source, _episode.bed)):
		_cancel_episode(true, "ask can_offer false")
		return
	if player.global_position.distance_to(pony.global_position) > POLICY.ASK_RANGE_CANCEL_M:
		_cancel_episode(true, "ask player moved")
		return
	var now := _now()
	if now >= _episode.deadline_at:
		if _episode.consent_pending or not bool(_conversation.call("idle")) \
				or bool(_conversation.call("pony_speaking", pony)):
			# His answer or her reply is still in flight. Do not cancel the line the player is
			# waiting on; give it another moment and check again.
			_episode.deadline_at = now + POLICY.DEADLINE_EXTEND_S
		else:
			_give_up("timeout")
			return
	if _episode.pose == CATALOG.MISSIONARY and not _episode.cuddle \
			and not _episode.consent_pending \
			and _now() - _episode.ask_started >= POLICY.PHYSICAL_ACCEPT_GRACE_S \
			and _player_in_bed(_episode.bed):
		# Lying down on the offered bed is a physical yes.
		if _episode.reply_seen:
			return
		_accept_offer()
		return
	if _is_private_offer():
		if _episode.reply_seen:
			if _episode.consent_pending:
				if not _episode.consent_started and bool(_conversation.call("idle")) \
						and not bool(_conversation.call("pony_speaking", pony)):
					_start_consent_classification()
				return
			if _episode.consent_intent == "unclear" and not _episode.clarified:
				_clarify_consent()
			return
		if _episode.reacted:
			return
		if bool(_conversation.call("player_reacted")):
			var text: String = _conversation.call("last_player_text")
			if text.is_empty():
				_episode.reacted = true
			else:
				_on_player_transcript(text)
			return
	else:
		if _episode.reacted:
			return
		if bool(_conversation.call("player_reacted")):
			_episode.reacted = true
			return
	var sent := _episode.prompts_sent
	var next_at := POLICY.next_prompt_time(sent)
	if next_at < 0.0 or now - _episode.ask_started < next_at:
		return
	if not bool(_conversation.call("idle")):
		return
	if _queue_reminder(sent + 1):
		_episode.prompts_sent = sent + 1


func _tick_present() -> void:
	var runtime: Node = _episode.runtime
	var pony: Node = _episode.pony
	if not is_instance_valid(runtime) or not is_instance_valid(pony):
		_cancel_episode(false, "present pony lost")
		return
	if not bool(runtime.call("presentation_active")):
		if _represent_or_cancel("presentation lost"):
			return
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player) \
			or player.global_position.distance_to(pony.global_position) \
			> POLICY.ASK_RANGE_CANCEL_M:
		_cancel_episode(false, "present player moved")
		return
	if _episode.invite_queued:
		return
	var now := _now()
	var settled := true
	if runtime.has_method("presentation_settled"):
		settled = bool(runtime.call("presentation_settled"))
	if not settled and now < _episode.present_until:
		return
	if not _queue_invitation():
		_cancel_episode(false, "invite queue failed")
		return
	_episode.invite_queued = true
	_episode.phase = Phase.INVITE
	_episode.invite_started = now
	_debug("request invite %s settled=%s" % [_episode.id, str(settled)])


func _tick_invite() -> void:
	var runtime: Node = _episode.runtime
	var pony: Node = _episode.pony
	if not is_instance_valid(runtime) or not is_instance_valid(pony):
		_cancel_episode(false, "invite pony lost")
		return
	if _episode.pose == CATALOG.MISSIONARY:
		if not _player_in_bed(_episode.bed):
			_cancel_episode(false, "invite left bed")
			return
		if not bool(runtime.call("can_show_start", CATALOG.MISSIONARY, _episode.source,
				_episode.bed)):
			_cancel_episode(true, "invite can_show_start false")
			return
		if _now() - _episode.invite_started >= POLICY.INVITE_TIMEOUT_S:
			_invite_give_up()
		return
	if not bool(runtime.call("presentation_active")):
		if _represent_or_cancel("invite presentation lost"):
			return
		return
	if runtime.has_method("presentation_settled") \
			and not bool(runtime.call("presentation_settled")):
		# A re-present is turning her again; wait for the pose before checking the act gates.
		return
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player) \
			or player.global_position.distance_to(pony.global_position) \
			> POLICY.ASK_RANGE_CANCEL_M:
		_cancel_episode(false, "invite player moved")
		return
	if not bool(runtime.call("can_show_start", CATALOG.STANDING, "", null)):
		_cancel_episode(true, "invite can_show_start false")
		return
	if _now() - _episode.invite_started >= POLICY.INVITE_TIMEOUT_S:
		_invite_give_up()


## A movement or other action can still break the idle pose. Re-present twice before ending
## an offer the player already accepted.
func _represent_or_cancel(reason: String) -> bool:
	var runtime: Node = _episode.runtime
	if is_instance_valid(runtime) and _episode.represent_count < 2 \
			and runtime.has_method("present_standing"):
		if bool(runtime.call("present_standing")):
			_episode.represent_count += 1
			_episode.present_until = _now() + POLICY.PRESENT_TURN_TIMEOUT_S
			_episode.invite_started = _now()
			_debug("request re-present %s reason=%s" % [_episode.id, reason])
			return true
	_cancel_episode(false, reason)
	return false


func _queue_invitation() -> bool:
	if _episode == null:
		return false
	var key := "%s:%s:%d:invite" % [KEY_PREFIX, _episode.id, _episode.serial]
	var queued := bool(_conversation.call("queue", _episode.id, _invite_purpose(), key,
		Callable(self, "_invite_valid").bind(_episode.serial), true))
	if queued and not key in _episode.keys:
		_episode.keys.append(key)
	return queued


func _invite_valid(serial: int) -> bool:
	if _episode == null or _episode.serial != serial:
		return false
	if not POLICY.invite_phase(_phase_name(_episode.phase)):
		return false
	var pony: Node = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	if _episode.pose == CATALOG.MISSIONARY:
		if not _player_in_bed(_episode.bed):
			return false
		return bool(runtime.call("can_show_start", CATALOG.MISSIONARY, _episode.source,
			_episode.bed))
	if not bool(runtime.call("presentation_active")):
		return false
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > POLICY.ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_show_start", CATALOG.STANDING, "", null))


# --------------------------------------------------------------------------- consent

## A private offer waits for Anon's own answer. Clear yes/no is parsed locally before the
## director builds her reply; ambiguous text gets one bounded model request.
func _on_player_transcript(text: String) -> void:
	if _episode == null or _episode.phase != Phase.ASK:
		return
	if not _episode.private:
		return
	text = text.strip_edges()
	if text.is_empty():
		return
	if _episode.consent_pending:
		# A new answer replaces the one still waiting for the model.
		if _episode.consent_started:
			_conversation.call("cancel_key", _episode.consent_key)
		_episode.consent_pending = false
		_episode.consent_started = false
		_episode.reply_seen = false
	if _episode.reply_seen:
		# One clear answer ends the wait. After the one clarification, a different answer
		# may still resolve it; the same text is the `_tick_ask` fallback re-reading it.
		if not _episode.clarified:
			return
		if text == _episode.response_text:
			return
	_episode.reply_seen = true
	_episode.reacted = true
	_episode.response_text = text
	_episode.deadline_at = _now() + POLICY.REPLY_GRACE_S
	_debug("request consent text=\"%s\"" % text.left(120))
	var intent := CONSENT.local_intent(text, _player_name())
	if intent != "unclear":
		_resolve_consent(intent, text, "local")
		return
	# Do not put a classifier request beside the director's reply to the same line. The
	# tick starts it once the director is idle again.
	_episode.consent_text = text
	_episode.consent_pending = true
	_episode.consent_started = false
	_debug("request consent waiting %s" % _episode.id)


func _on_consent_result(intent: String, detail: String, serial: int, text: String) -> void:
	if _episode == null or _episode.serial != serial:
		return
	_episode.consent_pending = false
	_episode.consent_started = false
	_resolve_consent(intent, text, "llm" if detail.is_empty() else "llm:%s" % detail)


## Start the model request only after the director is idle. The player's line and the
## director's reply already occupy the provider; a second request beside it is what produced
## the HTTP 429s. Clear answers never reach this function.
func _start_consent_classification() -> void:
	if _episode == null or _episode.consent_started:
		return
	if not _episode.consent_pending:
		return
	var text := _episode.consent_text.strip_edges()
	if text.is_empty():
		_resolve_consent("unclear", text, "empty")
		return
	var id := _episode.id
	var offer := "The pony %s has just asked Anon directly to have sex with her. She is waiting for his answer." % id
	var key := "offer:%s:%d" % [id, _episode.serial]
	_episode.consent_key = key
	_episode.consent_started = true
	var accepted := bool(_conversation.call("classify_offer", text, offer, key,
		Callable(self, "_on_consent_result").bind(_episode.serial, text)))
	if not accepted:
		_episode.consent_started = false
		_episode.consent_pending = false
		_resolve_consent("unclear", text, "unavailable")
		return
	_debug("request consent classify %s text=\"%s\"" % [id, text.left(120)])


func _resolve_consent(intent: String, text: String, source: String) -> void:
	if _episode == null or _episode.phase != Phase.ASK:
		return
	_episode.consent_pending = false
	_episode.consent_intent = intent
	_episode.consent_source = source
	_debug("request consent %s intent=%s source=%s text=\"%s\"" % [
		_episode.id, intent, source, text.left(120)])
	match intent:
		"accept":
			_accept_offer()
		"decline":
			_decline_offer()
		_:
			_clarify_consent()


func _accept_offer() -> void:
	var pony: Node3D = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(false, "accept pony lost")
		return
	# A third pony may have arrived while she was asking.
	_episode.private = _private_at_player(pony)
	_log_privacy_once(pony)
	if not _episode.private:
		_debug("request accept blocked %s: no longer private" % _episode.id)
		_cancel_episode(false, "accept not private")
		return
	if _episode.pose == CATALOG.MISSIONARY:
		_episode.accepted_at = _now()
		_episode.invite_queued = false
		if _episode.cuddle:
			_episode.phase = Phase.INVITE
			_episode.invite_started = _now()
			if not _queue_invitation():
				_cancel_episode(false, "accept bed invite failed")
				return
			_episode.invite_queued = true
		elif not _start_bed_lead():
			_cancel_episode(false, "accept bed lead failed")
			return
		_record_consent_situation(true)
		_debug("request accept %s pose=missionary cuddle=%s" % [
			_episode.id, str(_episode.cuddle)])
		return
	if not runtime.has_method("present_standing") or not bool(runtime.call("present_standing")):
		_debug("request accept present failed %s" % _episode.id)
		_cancel_episode(false, "accept present failed")
		return
	_episode.phase = Phase.PRESENT
	_episode.accepted_at = _now()
	_episode.present_until = _now() + POLICY.PRESENT_TURN_TIMEOUT_S
	_episode.invite_queued = false
	_record_consent_situation(true)
	_debug("request accept %s private=true" % _episode.id)


func _decline_offer() -> void:
	var id := _episode.id
	_record_consent_situation(false)
	_cancel_episode(true, "declined")
	_debug("request decline %s" % id)


func _clarify_consent() -> void:
	if _episode == null:
		return
	if _episode.clarified:
		_give_up("unclear")
		return
	var id := _episode.id
	var key := "%s:%s:%d:clarify" % [KEY_PREFIX, id, _episode.serial]
	var queued := bool(_conversation.call("queue", id, PROMPTS.clarify_purpose(), key,
		Callable(self, "_clarify_valid").bind(_episode.serial), true))
	if queued:
		_episode.clarified = true
		_episode.deadline_at = _now() + POLICY.CLARIFY_GRACE_S
		if not key in _episode.keys:
			_episode.keys.append(key)
		_debug("request clarify %s" % id)


func _clarify_valid(serial: int) -> bool:
	if _episode == null or _episode.serial != serial:
		return false
	if _episode.phase != Phase.ASK:
		return false
	var pony: Node = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > POLICY.ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_offer", _episode.pose, _episode.source, _episode.bed))


func _invite_give_up() -> void:
	var id := _episode.id
	_record_end_situation("invite timeout")
	_conversation.call("queue", id, PROMPTS.invite_give_up_purpose(),
		"%s:%s:%d:invite_giveup" % [KEY_PREFIX, id, _episode.serial],
		Callable(self, "_pony_alive").bind(id), true)
	_cancel_episode(true, "invite give up")
	_debug("request invite give up %s" % id)


func _player_name() -> String:
	return str(_conversation.call("player_name"))


# --------------------------------------------------------------------------- give up and cancel

func _give_up(reason := "timeout") -> void:
	var id := _episode.id
	_record_end_situation(reason)
	_conversation.call("queue", id, PROMPTS.give_up_purpose(),
		"%s:%s:%d:giveup" % [KEY_PREFIX, id, _episode.serial],
		Callable(self, "_pony_alive").bind(id), true)
	_cancel_episode(true, "give up:" + reason)
	_debug("request give up %s reason=%s" % [id, reason])


func _cancel_episode(set_cooldown: bool, reason := "", keep_rest := false) -> void:
	if _episode == null:
		return
	var pony: Node = _episode.pony
	var runtime: Node = _episode.runtime
	var id := _episode.id
	var phase := _phase_name(_episode.phase)
	_conversation.call("cancel_scope")
	if is_instance_valid(runtime) and runtime.has_method("set_request_face"):
		runtime.call("set_request_face", false)
	if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
		runtime.call("clear_presentation")
	if not keep_rest and _episode.bed_joined and is_instance_valid(pony):
		REST_CONTROL.release_managed(pony)
	_release_nav()
	if set_cooldown and POLICY.sets_cooldown(phase):
		_set_cooldown(id)
	elif not set_cooldown and POLICY.sets_retry(phase):
		_retry_at[id] = _now() + POLICY.RETRY_S
	_conversation.call("cancel_keys", _episode.keys)
	if not reason.is_empty():
		_debug("request end %s phase=%s reason=%s" % [id, phase, reason])
	_episode = null


func _tick_episode(delta: float) -> void:
	match _episode.phase:
		Phase.APPROACH:
			_tick_approach()
		Phase.ARRIVE:
			_tick_arrive()
		Phase.PRESENT:
			_tick_present()
		Phase.INVITE:
			_tick_invite()
		Phase.BED_LEAD:
			_tick_bed_lead()
		Phase.BED_APPROACH:
			_tick_bed_approach()
		Phase.BED_WAIT:
			_tick_bed_wait()
		Phase.ASK:
			_tick_ask(delta)
		_:
			_cancel_episode(false)


# --------------------------------------------------------------------------- prompts and context

func _ask_context() -> String:
	return PROMPTS.ask_context(_request())


func _ask_purpose() -> String:
	return PROMPTS.ask_purpose(_request("ask"))


func _invite_purpose() -> String:
	return PROMPTS.invite_purpose(_request("invite"))


func _reminder_purpose() -> String:
	return PROMPTS.reminder_purpose(_episode.private)


## The pure request facts for one wording call. `face_moment` is empty unless the line has a face
## hint ("ask", "invite").
func _request(face_moment := "") -> FACTS.Request:
	var out := FACTS.Request.new()
	if _episode == null:
		return out
	out.pose = _episode.pose
	out.cuddle = _episode.cuddle
	out.private = _episode.private
	out.heat = _in_heat(_episode.runtime)
	out.relation_note = _relationship_ask_note()
	out.history_note = _history_ask_note()
	if not face_moment.is_empty() and SETTINGS.act_faces.get_bool():
		out.face_note = ACT_FACE.prompt_note(face_moment)
	return out


## True when the runtime reports the mare's heat phase.
func _in_heat(runtime: Variant) -> bool:
	return is_instance_valid(runtime) and runtime.has_method("cycle_phase") \
		and str(runtime.call("cycle_phase")) == CYCLE.HEAT


func _history_ask_note() -> String:
	var id := _episode.id if _episode != null else ""
	if id.is_empty():
		return ""
	return ACT_HISTORY.ask_note(_history_row(id))


## Private relationship facts for a proactive ask. Empty when the world or bond is unavailable.
func _relationship_ask_note() -> String:
	var id := _episode.id if _episode != null else ""
	if id.is_empty() or not is_instance_valid(main):
		return ""
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return ""
	var facts := MEMORY.cue_facts(game, id, "")
	var note := RELATIONSHIP_CUE.note(facts)
	if note.is_empty():
		return ""
	return note + " " + RELATIONSHIP_CUE.tone_line(RELATIONSHIP_CUE.tone(facts))


func _record_situation() -> void:
	if _episode == null or _episode.id.is_empty():
		return
	_conversation.call("record_situation", PROMPTS.situation_ask(_request()), [_episode.id],
		"%s:%s:%d:situation" % [KEY_PREFIX, _episode.id, _episode.serial])


func _record_consent_situation(accepted: bool) -> void:
	if _episode == null or _episode.id.is_empty():
		return
	var mark := "accepted" if accepted else "declined"
	_conversation.call("record_situation", PROMPTS.situation_consent(accepted), [_episode.id],
		"%s:%s:%d:%s" % [KEY_PREFIX, _episode.id, _episode.serial, mark])


func _record_end_situation(reason: String) -> void:
	if _episode == null or _episode.id.is_empty():
		return
	_conversation.call("record_situation", PROMPTS.situation_end(), [_episode.id],
		"%s:%s:%d:end:%s" % [KEY_PREFIX, _episode.id, _episode.serial, reason])


func _episode_valid(serial: int) -> bool:
	if _episode == null or _episode.serial != serial:
		return false
	var pony: Node = _episode.pony
	var runtime: Node = _episode.runtime
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	if _episode.reacted or bool(_conversation.call("player_reacted")):
		return false
	var player: Node3D = _venue.call("player")
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > POLICY.ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_offer", _episode.pose, _episode.source, _episode.bed))


func _pony_alive(id: String) -> bool:
	if id.is_empty() or not is_instance_valid(main):
		return false
	for node: Variant in _venue.call("mares"):
		if is_instance_valid(node) and str(_venue.call("pony_id", node)) == id:
			return true
	return false


func _queue_reminder(number: int) -> bool:
	if not bool(_conversation.call("idle")):
		return false
	var id := _episode.id
	var key := "%s:%s:%d:prompt%d" % [KEY_PREFIX, id, _episode.serial, number]
	if key in _episode.keys:
		return false
	var queued := bool(_conversation.call("queue", id, _reminder_purpose(), key,
		Callable(self, "_episode_valid").bind(_episode.serial), true))
	if queued:
		_episode.keys.append(key)
		_debug("request reminder %d %s" % [number, id])
	return queued


# --------------------------------------------------------------------------- helpers

func _eligibility() -> ELIGIBILITY:
	if not is_instance_valid(main):
		return null
	return main.get("eligibility")


func _phase_name(phase: int) -> String:
	return str(PHASE_NAMES.get(phase, POLICY.PHASE_NONE))


func _runtime_name(runtime: Node) -> String:
	if not is_instance_valid(runtime):
		return "?"
	var pony: Variant = runtime.get("pony")
	return str(pony.name) if is_instance_valid(pony) else "?"


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _debug(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
