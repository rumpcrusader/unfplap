extends Node
## Proactive sex requests. One episode at a time: she waits for a quiet moment, walks to
## Anon when needed, asks in character, reminds him twice, then gives up. A private standing
## offer is asked while standing; after Anon accepts she presents, comments on the pose and
## waits for Y. Nothing starts until the player presses Y.
##
## Request eligibility is the existing relationship/social gate, not the act-time readiness
## meter. Automatic requests are background AI turns, so they require AI usage Full.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const AI_CONFIG := preload("res://world/ai/ai_config.gd")
const CONSENT := preload("res://mods/unfplap/consent_classifier.gd")
const BED_REST := preload("res://world/relationships/shared_bed.gd")
const REST_CONTROL := preload("res://mods/unfplap/rest_control.gd")

const COOLDOWN_S := 600.0
const SCAN_INTERVAL_S := 0.5
const QUIET_CHAT_GAP_S := 45.0
const APPROACH_RADIUS_M := 24.0
const APPROACH_GOAL_M := 2.0
const ARRIVE_RANGE_M := 2.8
const ARRIVE_WAIT_S := 2.0
const APPROACH_TIMEOUT_S := 35.0
const PLAYER_MOVE_CANCEL_M := 5.0
const ASK_RANGE_CANCEL_M := 8.0
const PRIVACY_RADIUS_M := 30.0
const PROMPT_1_S := 12.0
const PROMPT_2_S := 24.0
## No reply at all: she lets it go after this long.
const GIVE_UP_S := 60.0
## After Anon answers, the answer, classifier and clarification need their own window.
const REPLY_GRACE_S := 45.0
const CLARIFY_GRACE_S := 30.0
## How long a private standing invitation may wait after the turn completes.
const INVITE_TIMEOUT_S := 60.0
## Safety cap while the presentation turns; `presentation_settled()` normally wins earlier.
const PRESENT_TURN_TIMEOUT_S := 5.0
const RETRY_S := 30.0
## A bed invite only considers beds this close to Anon, so she can join without a long detour.
const BED_SEARCH_M := 10.0
## Walking to the bed front and waiting for Anon to lie down.
const BED_LEAD_TIMEOUT_S := 25.0
const BED_WAIT_TIMEOUT_S := 90.0
## Give her the ask line a moment before lying down on the offered bed counts as a yes.
const PHYSICAL_ACCEPT_GRACE_S := 2.5
const KEY_PREFIX := "unfplap:request"

var main
var _episode: Dictionary = {}
var _scan_clock := 0.0
var _serial := 0
var _cuddle_seen: Dictionary = {}
var _cuddle_asked: Dictionary = {}
var _retry_at: Dictionary = {}


func _ready() -> void:
	set_process(true)


func tick(delta: float) -> void:
	if not is_instance_valid(main):
		return
	if not _episode.is_empty():
		_tick_episode(delta)
		return
	_scan_clock += delta
	if _scan_clock < SCAN_INTERVAL_S:
		return
	_scan_clock = 0.0
	_tick_cuddle_edges()
	_consider_start()


## Reset session state for a world close. Cooldowns stay in the world's mod state.
func reset() -> void:
	if not _episode.is_empty():
		_cancel_episode(false)
	_unhook_director()
	var classifier := _classifier()
	if is_instance_valid(classifier):
		classifier.call("cancel_scope", "offer:")
	_cuddle_seen.clear()
	_cuddle_asked.clear()
	_retry_at.clear()
	_scan_clock = 0.0


## Manual lab/debug entry point: bypass the quiet, cooldown and AI-usage checks, but keep the
## relationship, consent and pose gates. An empty `pose` lets the mare choose.
func force(runtime: Node, pose := "") -> bool:
	if not is_instance_valid(main) or not is_instance_valid(runtime):
		return false
	if not _episode.is_empty():
		_cancel_episode(false)
	var candidate: Dictionary = _candidate_for(runtime, true, pose)
	if candidate.is_empty():
		_debug("request force: gates reject %s pose=%s" % [
			_runtime_name(runtime), "any" if pose.is_empty() else pose])
		return false
	candidate["forced"] = true
	_serial += 1
	var player: Variant = main.get("player")
	var pony: Node3D = candidate.get("pony")
	var near: bool = is_instance_valid(player) and is_instance_valid(pony) \
		and player.global_position.distance_to(pony.global_position) <= ARRIVE_RANGE_M
	if bool(candidate.get("bed_invite", false)):
		_start_bed_approach(candidate)
	elif near:
		_start_ask(candidate)
	else:
		_start_approach(candidate)
	_debug("request force %s pose=%s" % [str(candidate.get("id", "?")), str(candidate.get("pose", ""))])
	return not _episode.is_empty()


## Called before a normal Y start. The act owns the pony now.
func cancel_for(pony: Node) -> void:
	if is_instance_valid(pony) and not _episode.is_empty() and _episode.get("pony") == pony:
		# The act start owns the bed now; do not stand her up before runtime.start().
		_cancel_episode(true, "", true)
		return
	if is_instance_valid(pony):
		var runtime: Variant = main.call("runtime_for", pony) if is_instance_valid(main) else null
		if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
			runtime.call("clear_presentation")


# --------------------------------------------------------------------------- cuddle edge and cooldown

func _tick_cuddle_edges() -> void:
	for node: Variant in _mares():
		if not is_instance_valid(node):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime) or not runtime.has_method("_cuddle_active"):
			continue
		var id := _pony_id(node)
		if id.is_empty():
			continue
		var active: bool = bool(runtime.call("_cuddle_active"))
		var seen: bool = bool(_cuddle_seen.get(id, false))
		if active and not seen:
			_cuddle_seen[id] = true
			_cuddle_asked[id] = false
			_clear_cooldown(id)
		elif not active and seen:
			_cuddle_seen[id] = false
			_cuddle_asked[id] = false


func _cooldown_ok(id: String) -> bool:
	var mods := _mods()
	if mods == null:
		return true
	var section: Dictionary = mods.call("state", "unfplap")
	var times: Variant = section.get("request_times", {})
	if not times is Dictionary:
		times = {}
	var last: float = float((times as Dictionary).get(id, -100000.0))
	return cooldown_ready(Time.get_unix_time_from_system(), last)


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
	if not _quiet():
		return
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return
	var cuddles: Array = []
	var offers: Array = []
	for node: Variant in _mares():
		if not is_instance_valid(node):
			continue
		var runtime: Variant = main.call("runtime_for", node)
		if not is_instance_valid(runtime):
			continue
		var candidate: Dictionary = _candidate_for(runtime, false)
		if candidate.is_empty():
			continue
		if bool(candidate.get("cuddle", false)):
			cuddles.append(candidate)
		else:
			offers.append(candidate)
	var chosen: Dictionary = {}
	if not cuddles.is_empty():
		chosen = cuddles.pick_random()
	elif not offers.is_empty():
		chosen = offers.pick_random()
	if chosen.is_empty():
		return
	_serial += 1
	var pony: Node3D = chosen.get("pony")
	var near: bool = is_instance_valid(pony) \
		and player.global_position.distance_to(pony.global_position) <= ARRIVE_RANGE_M
	if bool(chosen.get("bed_invite", false)):
		_start_bed_approach(chosen)
	elif near:
		_start_ask(chosen)
	else:
		_start_approach(chosen)


func _candidate_for(runtime: Node, forced: bool, pose_request := "") -> Dictionary:
	if not is_instance_valid(main) or not is_instance_valid(runtime):
		return {}
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		return {}
	if int(runtime.get("state")) != 0:
		return {}
	var id := _pony_id(pony)
	if id.is_empty():
		return {}
	if not forced and not _cooldown_ok(id):
		return {}
	if not forced and _now() < float(_retry_at.get(id, -100000.0)):
		return {}
	var cuddle: bool = bool(runtime.call("_cuddle_active")) if runtime.has_method("_cuddle_active") else false
	if pose_request == CATALOG.MISSIONARY or (pose_request.is_empty() and cuddle):
		var bed_candidate := _cuddle_candidate(runtime, forced) if cuddle \
			else _bed_candidate(runtime, forced)
		if not bed_candidate.is_empty() or not pose_request.is_empty():
			return bed_candidate
	var standing_candidate := _standing_candidate(runtime, forced)
	if pose_request == CATALOG.STANDING:
		return standing_candidate
	if cuddle:
		return {}
	var bed_candidate := _bed_candidate(runtime, forced)
	var pose := pick_offer_pose(not bed_candidate.is_empty(),
		not standing_candidate.is_empty(), randf())
	if pose == CATALOG.MISSIONARY:
		return bed_candidate
	if pose == CATALOG.STANDING:
		return standing_candidate
	return {}


func _cuddle_candidate(runtime: Node, forced: bool) -> Dictionary:
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		return {}
	var id := _pony_id(pony)
	if id.is_empty():
		return {}
	if not forced and bool(_cuddle_asked.get(id, false)):
		return {}
	if not _cuddle_privacy_ok(pony):
		return {}
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var source := "already_lying" if PLAYER_FORM.is_pony(form) else "bed_side"
	var bed: Variant = runtime.call("find_bed_under")
	if not is_instance_valid(bed):
		return {}
	if not bool(runtime.call("can_offer", CATALOG.MISSIONARY, source, bed)):
		return {}
	if not _offer_targets_pony(pony):
		return {}
	return {
		"pony": pony, "runtime": runtime, "id": id,
		"pose": CATALOG.MISSIONARY, "source": source, "bed": bed,
		"private": true, "cuddle": true, "bed_invite": false,
	}


func _bed_candidate(runtime: Node, _forced: bool) -> Dictionary:
	var pony: Node3D = runtime.get("pony") if is_instance_valid(runtime) else null
	if not is_instance_valid(pony):
		return {}
	var found := _find_bed_for(pony)
	if found.is_empty():
		return {}
	var bed: Node3D = found.get("bed")
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var source := "already_lying" if PLAYER_FORM.is_pony(form) else "bed_side"
	if not bool(runtime.call("can_offer", CATALOG.MISSIONARY, source, bed)):
		return {}
	return {
		"pony": pony, "runtime": runtime, "id": _pony_id(pony),
		"pose": CATALOG.MISSIONARY, "source": source, "bed": bed,
		"private": _private_at_player(pony), "cuddle": false, "bed_invite": true,
		"bed_rest": found.get("rest"), "bed_front": found.get("front"),
	}


func _standing_candidate(runtime: Node, _forced: bool) -> Dictionary:
	var pony: Variant = runtime.get("pony")
	if not is_instance_valid(pony):
		return {}
	if not bool(runtime.call("can_offer", CATALOG.STANDING, "", null)):
		return {}
	if not _can_approach(pony):
		return {}
	return {
		"pony": pony, "runtime": runtime, "id": _pony_id(pony),
		"pose": CATALOG.STANDING, "source": "", "bed": null,
		"private": _private_at_player(pony), "cuddle": false, "bed_invite": false,
	}


func _can_approach(pony: Node3D) -> bool:
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or str(nav.get("reserved_by")) != "":
		return false
	var owner := str(nav.get("command_owner"))
	if not (owner.is_empty() or owner.begins_with("life:")):
		return false
	if bool(nav.get("_has_target")):
		return false
	if _region_of(player.global_position) != _region_of(pony.global_position):
		return false
	return player.global_position.distance_to(pony.global_position) <= APPROACH_RADIUS_M


# --------------------------------------------------------------------------- privacy

func _private_at_player(except: Node = null) -> bool:
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return false
	var house: Node3D = _house_at(player.global_position)
	return presentation_allowed(house != null and not _other_in_house(house, except),
		_other_within(player.global_position, except, PRIVACY_RADIUS_M))


func _cuddle_privacy_ok(pony: Node3D) -> bool:
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return false
	var house: Node3D = _house_at(player.global_position)
	var indoor := house != null
	return cuddle_private(indoor, indoor and not _other_in_house(house, pony),
		_other_within(player.global_position, pony, PRIVACY_RADIUS_M))


func _house_at(at: Vector3) -> Node3D:
	if not is_inside_tree():
		return null
	return HOUSE.at(get_tree(), at)


func _other_in_house(house: Node3D, except: Node) -> bool:
	if not is_instance_valid(house):
		return false
	for node: Variant in _mares():
		if not is_instance_valid(node) or node == except:
			continue
		if _house_at((node as Node3D).global_position) == house:
			return true
	return false


func _other_within(at: Vector3, except: Node, radius: float) -> bool:
	for node: Variant in _mares():
		if not is_instance_valid(node) or node == except:
			continue
		if (node as Node3D).global_position.distance_to(at) <= radius:
			return true
	return false


## Diagnostic for a standing offer's privacy decision. The target is labelled and excluded from
## the other-pony checks, so the logged result matches the offer's actual privacy rule.
func _privacy_report(target: Node = null) -> String:
	var player: Variant = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(player):
		return "player=none"
	var house: Node3D = _house_at((player as Node3D).global_position)
	var in_house: Array[String] = []
	var nearby: Array[String] = []
	for node: Variant in _mares():
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var actor := node as Node3D
		var distance := actor.global_position.distance_to((player as Node3D).global_position)
		var id := _pony_id(actor)
		var tag := id if not id.is_empty() else str(actor.name)
		if actor == target:
			tag += "(target)"
		if house != null and _house_at(actor.global_position) == house:
			in_house.append("%s(%.1fm)" % [tag, distance])
		if distance <= PRIVACY_RADIUS_M:
			nearby.append("%s(%.1fm)" % [tag, distance])
	var house_text := "none"
	if house != null:
		house_text = "%s@%s" % [str(house.name), str(house.global_position)]
	return "player=%s target=%s house=%s in_house=[%s] within_%dm=[%s] private=%s" % [
		str((player as Node3D).global_position), str(_pony_id(target)) if is_instance_valid(target) else "?",
		house_text, ",".join(in_house), int(PRIVACY_RADIUS_M), ",".join(nearby),
		str(_private_at_player(target))]


func _log_privacy_once(target: Node) -> void:
	if not is_instance_valid(main):
		return
	var now := _now()
	if now - float(_episode.get("privacy_log_at", -1000.0)) < 1.0:
		return
	var report := _privacy_report(target)
	if str(_episode.get("privacy_report", "")) == report:
		return
	_episode["privacy_report"] = report
	_episode["privacy_log_at"] = now
	_debug("request privacy " + report)


# --------------------------------------------------------------------------- approach

func _start_approach(candidate: Dictionary) -> void:
	var pony: Node3D = candidate.get("pony")
	var runtime: Node = candidate.get("runtime")
	var player: Variant = main.get("player")
	var nav: Node = pony.get_node_or_null("Navigator") if is_instance_valid(pony) else null
	if not is_instance_valid(pony) or not is_instance_valid(runtime) or not is_instance_valid(player) or nav == null:
		return
	var episode := {
		"serial": _serial,
		"pony": pony, "runtime": runtime, "id": str(candidate.get("id", "")),
		"pose": str(candidate.get("pose", "")), "source": str(candidate.get("source", "")),
		"bed": candidate.get("bed"), "private": bool(candidate.get("private", false)),
		"cuddle": false, "phase": "arrive",
		"bed_invite": bool(candidate.get("bed_invite", false)),
		"bed_rest": candidate.get("bed_rest"), "bed_front": candidate.get("bed_front"),
		"started_at": _now(), "arrive_until": _now() + ARRIVE_WAIT_S,
		"nav": nav, "token": KEY_PREFIX + ":" + str(candidate.get("id", "")),
		"prev_owner": str(nav.get("command_owner")),
		"prev_wander": bool(nav.get("wander_enabled")),
		"prev_limit": nav.get("command_speed_limit"),
		"prev_pace": nav.get("command_pace_target"),
		"player_start": player.global_position,
		"region": _region_of(player.global_position),
		"forced": bool(candidate.get("forced", false)),
		"keys": [],
	}
	_episode = episode
	_hook_director()
	_log_privacy_once(pony)
	nav.call("stay")
	nav.set("command_owner", str(episode.get("token")))
	nav.set("wander_enabled", false)
	nav.set("command_speed_limit", INF)
	nav.set("command_pace_target", -1.0)
	if pony.has_method("request_posture"):
		pony.request_posture("stand")
	if player.global_position.distance_to(pony.global_position) <= ARRIVE_RANGE_M:
		_arrive()
		return
	var view: Camera3D = main.call("camera")
	var forward := Vector3.FORWARD
	if is_instance_valid(view):
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_basis.z
	forward = forward.normalized()
	var goal: Vector3 = nav.call("command_support", player.global_position + forward * APPROACH_GOAL_M)
	if goal is Vector3 and (goal as Vector3).is_finite() and absf((goal as Vector3).y - pony.global_position.y) <= 3.0:
		_episode["goal"] = goal
		if not bool(nav.call("command_destination", goal, "trot")):
			_cancel_episode(false)
		return
	_cancel_episode(false)


func _tick_approach() -> void:
	var pony: Node3D = _episode.get("pony")
	var nav: Node = _episode.get("nav")
	if not is_instance_valid(pony) or not is_instance_valid(nav):
		_cancel_episode(false)
		return
	if not bool(_episode.get("forced", false)) and not _quiet():
		_cancel_episode(false)
		return
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		_cancel_episode(false)
		return
	if _region_of(player.global_position) != str(_episode.get("region", "")) \
			or player.global_position.distance_to(_episode.get("player_start")) > PLAYER_MOVE_CANCEL_M:
		_cancel_episode(false)
		return
	if str(nav.get("command_owner")) != str(_episode.get("token")):
		_cancel_episode(false)
		return
	if _now() > float(_episode.get("started_at")) + APPROACH_TIMEOUT_S:
		_cancel_episode(false)
		return
	if player.global_position.distance_to(pony.global_position) > ARRIVE_RANGE_M:
		return
	_arrive()


func _arrive() -> void:
	var pony: Node3D = _episode.get("pony")
	var nav: Node = _episode.get("nav")
	if not is_instance_valid(pony) or not is_instance_valid(nav):
		_cancel_episode(false)
		return
	nav.call("stay")
	_episode["phase"] = "arrive"
	_episode["arrive_until"] = _now() + ARRIVE_WAIT_S


func _tick_arrive() -> void:
	var pony: Node3D = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(false)
		return
	var player: Variant = main.get("player")
	if not is_instance_valid(player) \
			or player.global_position.distance_to(pony.global_position) > ARRIVE_RANGE_M + 0.75:
		if _now() >= float(_episode.get("arrive_until")):
			_cancel_episode(false, "arrive target moved")
		return
	_episode["private"] = _private_at_player(pony)
	_log_privacy_once(pony)
	_issue_initial()


# --------------------------------------------------------------------------- bed invitation

## A bed offer walks to the bed front, not to Anon. Asking from the bed avoids a blocked
## approach spot when he is already lying down.
func _start_bed_approach(candidate: Dictionary) -> void:
	if not _episode.is_empty():
		return
	var pony: Node3D = candidate.get("pony")
	var runtime: Node = candidate.get("runtime")
	var rest: Node = candidate.get("bed_rest")
	var front: Variant = candidate.get("bed_front")
	if not is_instance_valid(pony) or not is_instance_valid(runtime) \
			or not is_instance_valid(rest) or not front is Vector3:
		return
	_episode = {
		"serial": _serial,
		"pony": pony, "runtime": runtime, "id": str(candidate.get("id", "")),
		"pose": CATALOG.MISSIONARY, "source": str(candidate.get("source", "")),
		"bed": candidate.get("bed"), "private": bool(candidate.get("private", false)),
		"cuddle": false, "bed_invite": true,
		"bed_rest": rest, "bed_front": front,
		"phase": "bed_approach", "started_at": _now(),
		"bed_approach_started": _now(),
		"forced": bool(candidate.get("forced", false)),
		"keys": [],
	}
	_hook_director()
	_log_privacy_once(pony)
	var nav := _claim_nav(pony)
	if nav == null:
		_cancel_episode(false)
		return
	if pony.has_method("request_posture") and str(pony.posture_status().get("requested", "")) != "stand":
		pony.request_posture("stand")
	if pony.global_position.distance_to(front) <= 1.2:
		nav.call("stay")
		_arrive_bed_ask()
		return
	if not bool(nav.call("command_destination", front, "trot")):
		_cancel_episode(false)


func _arrive_bed_ask() -> void:
	_episode["phase"] = "ask"
	_issue_initial()


func _tick_bed_approach() -> void:
	var pony: Node3D = _episode.get("pony")
	var nav: Node = _episode.get("nav")
	var front: Variant = _episode.get("bed_front")
	if not is_instance_valid(pony) or not is_instance_valid(nav) or not front is Vector3:
		_cancel_episode(false, "bed approach lost")
		return
	if str(nav.get("command_owner")) != str(_episode.get("token")):
		_cancel_episode(false, "bed approach owner")
		return
	if _now() - float(_episode.get("bed_approach_started", _now())) > BED_LEAD_TIMEOUT_S:
		_cancel_episode(false, "bed approach timeout")
		return
	if pony.global_position.distance_to(front) <= 1.4 or not bool(nav.get("_has_target")):
		nav.call("stay")
		_arrive_bed_ask()


## Walk her to the offered bed and wait for Anon to lie down. The native bed rest seats her
## once he is reclined; only then is the missionary pose actually startable.
func _start_bed_lead() -> bool:
	var pony: Node3D = _episode.get("pony")
	var rest: Node = _episode.get("bed_rest")
	if not is_instance_valid(pony) or not is_instance_valid(rest):
		return false
	var front: Variant = _episode.get("bed_front")
	if not front is Vector3 or not (front as Vector3).is_finite():
		front = rest.call("_front_for", pony)
	if not front is Vector3 or not (front as Vector3).is_finite():
		return false
	var nav := _claim_nav(pony)
	if nav == null:
		return false
	if pony.has_method("request_posture") and str(pony.posture_status().get("requested", "")) != "stand":
		pony.request_posture("stand")
	_episode["bed_front"] = front
	_episode["bed_lead_started"] = _now()
	if pony.global_position.distance_to(front) <= 1.2:
		nav.call("stay")
		_begin_bed_wait()
		return true
	if not bool(nav.call("command_destination", front, "trot")):
		return false
	_episode["phase"] = "bed_lead"
	_debug("request bed lead %s front=%s" % [str(_episode.get("id", "")), str(front)])
	return true


func _begin_bed_wait() -> void:
	_episode["phase"] = "bed_wait"
	_episode["bed_wait_started"] = _now()
	_episode["bed_join_tries"] = 0
	_debug("request bed wait %s" % str(_episode.get("id", "")))


func _tick_bed_lead() -> void:
	var pony: Node3D = _episode.get("pony")
	var nav: Node = _episode.get("nav")
	var front: Variant = _episode.get("bed_front")
	if not is_instance_valid(pony) or not is_instance_valid(nav) or not front is Vector3:
		_cancel_episode(false, "bed lead lost")
		return
	if str(nav.get("command_owner")) != str(_episode.get("token")):
		_cancel_episode(false, "bed lead owner")
		return
	if _now() - float(_episode.get("bed_lead_started", _now())) > BED_LEAD_TIMEOUT_S:
		_give_up("bed walk timeout")
		return
	if pony.global_position.distance_to(front) <= 1.4 or not bool(nav.get("_has_target")):
		nav.call("stay")
		_begin_bed_wait()


func _tick_bed_wait() -> void:
	var pony: Node3D = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	var rest: Node = _episode.get("bed_rest")
	var bed: Variant = _episode.get("bed")
	var player: Variant = main.get("player")
	if not is_instance_valid(pony) or not is_instance_valid(runtime) \
			or not is_instance_valid(rest) or not is_instance_valid(player) or not is_instance_valid(bed):
		_cancel_episode(false, "bed wait lost")
		return
	if _now() - float(_episode.get("bed_wait_started", _now())) > BED_WAIT_TIMEOUT_S:
		_give_up("bed wait timeout")
		return
	if player.global_position.distance_to(pony.global_position) > PRIVACY_RADIUS_M:
		_cancel_episode(false, "bed wait player left")
		return
	if not bool(_episode.get("bed_joining", false)):
		if not _player_in_bed(bed):
			return
		if _now() < float(_episode.get("bed_join_retry_at", 0.0)):
			return
		# The bed rest refuses an actor whose navigator is still owned by the request. Hand it
		# back without standing her up, then let the native invite take her onto the bed.
		_yield_nav_to_bed()
		runtime.call("set_request_face", false)
		if not bool(rest.call("accept", pony)):
			var tries := int(_episode.get("bed_join_tries", 0)) + 1
			_episode["bed_join_tries"] = tries
			_episode["bed_join_retry_at"] = _now() + 1.0
			if tries >= 5:
				_give_up("bed join failed")
			return
		_episode["bed_joining"] = true
		_episode["bed_joined"] = true
		_debug("request bed join %s" % str(_episode.get("id", "")))
	if not bool(runtime.call("can_start", CATALOG.MISSIONARY, str(_episode.get("source", "")), bed)):
		if not _player_in_bed(bed):
			_cancel_episode(false, "bed player stood up")
		return
	if bool(_episode.get("invite_queued", false)):
		return
	if not _queue_invitation():
		_cancel_episode(false, "bed invite queue failed")
		return
	_episode["invite_queued"] = true
	_episode["phase"] = "invite"
	_episode["invite_started"] = _now()
	_debug("request invite %s pose=missionary" % str(_episode.get("id", "")))


func _claim_nav(pony: Node3D) -> Node:
	var nav: Node = pony.get_node_or_null("Navigator") if is_instance_valid(pony) else null
	if nav == null:
		return null
	if not _episode.has("nav"):
		var id := str(_episode.get("id", ""))
		_episode["nav"] = nav
		_episode["token"] = KEY_PREFIX + ":" + id
		_episode["prev_owner"] = str(nav.get("command_owner"))
		_episode["prev_wander"] = bool(nav.get("wander_enabled"))
		_episode["prev_limit"] = nav.get("command_speed_limit")
		_episode["prev_pace"] = nav.get("command_pace_target")
	nav.set("command_owner", str(_episode.get("token", "")))
	nav.set("wander_enabled", false)
	nav.set("command_speed_limit", INF)
	nav.set("command_pace_target", -1.0)
	return nav


func _yield_nav_to_bed() -> void:
	if bool(_episode.get("nav_released", false)):
		return
	var nav: Node = _episode.get("nav")
	if is_instance_valid(nav):
		nav.call("stay")
		if str(nav.get("command_owner")) == str(_episode.get("token", "")):
			nav.set("command_owner", str(_episode.get("prev_owner", "")))
			nav.set("wander_enabled", bool(_episode.get("prev_wander", true)))
			if _episode.get("prev_limit") != null:
				nav.set("command_speed_limit", _episode.get("prev_limit"))
			if _episode.get("prev_pace") != null:
				nav.set("command_pace_target", _episode.get("prev_pace"))
	_episode["nav_released"] = true


func _player_in_bed(bed: Variant) -> bool:
	var player: Variant = main.get("player")
	if not is_instance_valid(player) or not is_instance_valid(bed):
		return false
	if not bool(player.get_meta("couch_sleeping", false)):
		return false
	var seat: Variant = player.get("seat")
	if not is_instance_valid(seat):
		return false
	if not seat.has_meta("couch"):
		return false
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return false
	var bed_node: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
	return bed_node == bed


# --------------------------------------------------------------------------- bed search

func _find_bed_for(pony: Node3D) -> Dictionary:
	var player: Variant = main.get("player")
	if not is_instance_valid(player) or not is_instance_valid(pony):
		return {}
	var own := _player_bed_node(player)
	if own != null:
		var own_row := _bed_row(own, pony, player)
		if not own_row.is_empty():
			return own_row
	var best: Dictionary = {}
	var best_distance := BED_SEARCH_M
	for bed: Node3D in _beds_near(player):
		var row := _bed_row(bed, pony, player)
		if row.is_empty():
			continue
		var distance := float(row.get("distance", BED_SEARCH_M))
		if distance < best_distance:
			best_distance = distance
			best = row
	return best


func _player_bed_node(player: Node3D) -> Node3D:
	var seat: Variant = player.get("seat")
	if not is_instance_valid(seat) or not seat.has_meta("couch"):
		return null
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return null
	var bed: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
	return bed as Node3D if is_instance_valid(bed) else null


func _beds_near(player: Node3D) -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	for node: Variant in get_tree().get_nodes_in_group("couches"):
		if not is_instance_valid(node) or not (node as Node).has_method("rest_word"):
			continue
		if str((node as Node).call("rest_word")) != "bed":
			continue
		var bed: Variant = node.get("_bed") if node.get("_bed") != null else node.get("bed_node")
		if is_instance_valid(bed) and not seen.has((bed as Node).get_instance_id()):
			seen[(bed as Node).get_instance_id()] = true
			found.append(bed)
	var house: Node3D = _house_at(player.global_position)
	if house != null:
		for node: Node in house.find_children("*", "Node3D", true, false):
			if not node.has_meta("mattress_top") and not node.has_meta("soft_support"):
				continue
			if seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			found.append(node)
	return found


func _bed_row(bed: Node3D, pony: Node3D, player: Node3D) -> Dictionary:
	if not is_instance_valid(bed) or not bed.is_inside_tree():
		return {}
	var at := bed.global_position
	if at.distance_to(player.global_position) > BED_SEARCH_M:
		return {}
	if absf(at.y - player.global_position.y) > 1.5:
		return {}
	if _region_of(at) != _region_of(player.global_position):
		return {}
	var rest: Variant = bed.get_meta("bed_rest") if bed.has_meta("bed_rest") else null
	if not is_instance_valid(rest):
		rest = BED_REST.for_bed(bed)
	if not is_instance_valid(rest):
		return {}
	rest.call("refresh")
	if not bool(rest.get("_mare_fits")):
		return {}
	var guest: Variant = rest.get("_guest")
	if guest is Dictionary and not (guest as Dictionary).is_empty():
		return {}
	if is_instance_valid(rest.get("_sleeper")):
		return {}
	if bool(main.call("bed_occupied", bed, pony)):
		return {}
	var front: Variant = rest.call("_front_for", pony)
	if not front is Vector3 or not (front as Vector3).is_finite():
		return {}
	return {
		"bed": bed, "rest": rest, "front": front,
		"distance": at.distance_to(player.global_position),
	}



# --------------------------------------------------------------------------- ask

func _start_ask(candidate: Dictionary) -> void:
	if not _episode.is_empty():
		return
	_episode = {
		"serial": _serial,
		"pony": candidate.get("pony"), "runtime": candidate.get("runtime"),
		"id": str(candidate.get("id", "")), "pose": str(candidate.get("pose", "")),
		"source": str(candidate.get("source", "")), "bed": candidate.get("bed"),
		"private": bool(candidate.get("private", true)), "cuddle": bool(candidate.get("cuddle", false)),
		"bed_invite": bool(candidate.get("bed_invite", false)),
		"bed_rest": candidate.get("bed_rest"), "bed_front": candidate.get("bed_front"),
		"phase": "ask", "started_at": _now(), "ask_started": _now(),
		"forced": bool(candidate.get("forced", false)),
		"prompts_sent": 0, "keys": [],
	}
	_hook_director()
	_issue_initial()


func _issue_initial() -> void:
	var director: Node = _director()
	var pony: Node = _episode.get("pony")
	if director == null or not is_instance_valid(pony):
		_cancel_episode(false)
		return
	var id := str(_episode.get("id", ""))
	var context := _ask_context()
	var started: bool = false
	if director.has_method("begin_player_greeting"):
		started = bool(director.call("begin_player_greeting", id, context))
	if not started and director.has_method("queue_generated_intent"):
		var key := "%s:%s:%d:ask" % [KEY_PREFIX, id, int(_episode.get("serial", 0))]
		started = bool(director.call("queue_generated_intent", id, _ask_purpose(),
			key, Callable(self, "_episode_valid").bind(int(_episode.get("serial", 0))), Callable(), false))
	if not started:
		_cancel_episode(false)
		return
	_episode["phase"] = "ask"
	_episode["ask_started"] = _now()
	_episode["deadline_at"] = _now() + GIVE_UP_S
	_episode["prompts_sent"] = 0
	if bool(_episode.get("cuddle")):
		_cuddle_asked[id] = true
	if _is_private_standing():
		var runtime: Node = _episode.get("runtime")
		if is_instance_valid(runtime) and runtime.has_method("set_request_face"):
			runtime.call("set_request_face", true)
	_record_situation()
	_debug("request ask %s pose=%s private=%s cuddle=%s" % [
		id, str(_episode.get("pose", "")), str(_episode.get("private", false)),
		str(_episode.get("cuddle", false))])


func _is_private_offer() -> bool:
	return not _episode.is_empty() and bool(_episode.get("private", false))


func _is_private_standing() -> bool:
	return _is_private_offer() and str(_episode.get("pose", "")) == CATALOG.STANDING


func _tick_ask(_delta: float) -> void:
	var pony: Node = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(true, "ask pony lost")
		return
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		_cancel_episode(true, "ask player lost")
		return
	var pose := str(_episode.get("pose", ""))
	var source := str(_episode.get("source", ""))
	if not bool(runtime.call("can_offer", pose, source, _episode.get("bed"))):
		_cancel_episode(true, "ask can_offer false")
		return
	if player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		_cancel_episode(true, "ask player moved")
		return
	var now := _now()
	var deadline := float(_episode.get("deadline_at",
		float(_episode.get("ask_started", now)) + GIVE_UP_S))
	if now >= deadline:
		if bool(_episode.get("consent_pending", false)) or not _director_idle() \
				or _episode_pony_speaking():
			# His answer or her reply is still in flight. Do not cancel the line the player is
			# waiting on; give it another moment and check again.
			_episode["deadline_at"] = now + 5.0
		else:
			_give_up("timeout")
			return
	if pose == CATALOG.MISSIONARY and not bool(_episode.get("cuddle", false)) \
			and not bool(_episode.get("consent_pending", false)) \
			and _now() - float(_episode.get("ask_started", now)) >= PHYSICAL_ACCEPT_GRACE_S \
			and _player_in_bed(_episode.get("bed")):
		# Lying down on the offered bed is a physical yes.
		if bool(_episode.get("reply_seen", false)):
			return
		_accept_offer()
		return
	var private_offer := _is_private_offer()
	if private_offer:
		if bool(_episode.get("reply_seen", false)):
			if bool(_episode.get("consent_pending", false)):
				if not bool(_episode.get("consent_started", false)) and _director_idle() \
						and not _episode_pony_speaking():
					_start_consent_classification()
				return
			if str(_episode.get("consent_intent", "")) == "unclear" \
					and not bool(_episode.get("clarified", false)):
				_clarify_consent()
			return
		if bool(_episode.get("reacted", false)):
			return
		if _player_reacted():
			var text := _last_player_text()
			if text.is_empty():
				_episode["reacted"] = true
			else:
				_on_player_transcript(text)
			return
	else:
		if bool(_episode.get("reacted", false)):
			return
		if _player_reacted():
			_episode["reacted"] = true
			return
	var sent := int(_episode.get("prompts_sent", 0))
	var next_at := next_prompt_time(sent)
	if next_at < 0.0 or now - float(_episode.get("ask_started")) < next_at:
		return
	if not _director_idle():
		return
	if _queue_reminder(sent + 1):
		_episode["prompts_sent"] = sent + 1


func _tick_present() -> void:
	var runtime: Node = _episode.get("runtime")
	var pony: Node = _episode.get("pony")
	if not is_instance_valid(runtime) or not is_instance_valid(pony):
		_cancel_episode(false, "present pony lost")
		return
	if not bool(runtime.call("presentation_active")):
		if _represent_or_cancel("presentation lost"):
			return
		return
	var player: Variant = main.get("player")
	if not is_instance_valid(player) or player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		_cancel_episode(false, "present player moved")
		return
	if bool(_episode.get("invite_queued", false)):
		return
	var now := _now()
	var settled := true
	if runtime.has_method("presentation_settled"):
		settled = bool(runtime.call("presentation_settled"))
	if not settled and now < float(_episode.get("present_until", 0.0)):
		return
	if not _queue_invitation():
		_cancel_episode(false, "invite queue failed")
		return
	_episode["invite_queued"] = true
	_episode["phase"] = "invite"
	_episode["invite_started"] = now
	_debug("request invite %s settled=%s" % [str(_episode.get("id", "")), str(settled)])


func _tick_invite() -> void:
	var runtime: Node = _episode.get("runtime")
	var pony: Node = _episode.get("pony")
	if not is_instance_valid(runtime) or not is_instance_valid(pony):
		_cancel_episode(false, "invite pony lost")
		return
	if str(_episode.get("pose", "")) == CATALOG.MISSIONARY:
		if not _player_in_bed(_episode.get("bed")):
			_cancel_episode(false, "invite left bed")
			return
		if not bool(runtime.call("can_start", CATALOG.MISSIONARY,
				str(_episode.get("source", "")), _episode.get("bed"))):
			_cancel_episode(true, "invite can_start false")
			return
		if _now() - float(_episode.get("invite_started", _now())) >= INVITE_TIMEOUT_S:
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
	var player: Variant = main.get("player")
	if not is_instance_valid(player) or player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		_cancel_episode(false, "invite player moved")
		return
	if not bool(runtime.call("can_start", CATALOG.STANDING, "", null)):
		_cancel_episode(true, "invite can_start false")
		return
	if _now() - float(_episode.get("invite_started", _now())) >= INVITE_TIMEOUT_S:
		_invite_give_up()


## A movement or other action can still break the idle pose. Re-present twice before ending
## an offer the player already accepted.
func _represent_or_cancel(reason: String) -> bool:
	var runtime: Node = _episode.get("runtime")
	var id := str(_episode.get("id", ""))
	var count := int(_episode.get("represent_count", 0))
	if is_instance_valid(runtime) and count < 2 and runtime.has_method("present_standing"):
		if bool(runtime.call("present_standing")):
			_episode["represent_count"] = count + 1
			_episode["present_until"] = _now() + PRESENT_TURN_TIMEOUT_S
			_episode["invite_started"] = _now()
			_debug("request re-present %s reason=%s" % [id, reason])
			return true
	_cancel_episode(false, reason)
	return false


func _queue_invitation() -> bool:
	var director: Node = _director()
	if director == null or not director.has_method("queue_generated_intent"):
		return false
	var id := str(_episode.get("id", ""))
	var serial := int(_episode.get("serial", 0))
	var key := "%s:%s:%d:invite" % [KEY_PREFIX, id, serial]
	var queued := bool(director.call("queue_generated_intent", id, _invite_purpose(), key,
		Callable(self, "_invite_valid").bind(serial), Callable(), true))
	if queued:
		var keys: Array = _episode.get("keys", [])
		if not key in keys:
			keys.append(key)
		_episode["keys"] = keys
	return queued


func _invite_valid(serial: int) -> bool:
	if _episode.is_empty() or int(_episode.get("serial", -1)) != serial:
		return false
	if str(_episode.get("phase", "")) not in ["present", "invite", "bed_wait"]:
		return false
	var pony: Node = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	if str(_episode.get("pose", "")) == CATALOG.MISSIONARY:
		if not _player_in_bed(_episode.get("bed")):
			return false
		return bool(runtime.call("can_start", CATALOG.MISSIONARY,
			str(_episode.get("source", "")), _episode.get("bed")))
	if not bool(runtime.call("presentation_active")):
		return false
	var player: Variant = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_start", CATALOG.STANDING, "", null))


## A private offer waits for Anon's own answer. Clear yes/no is parsed locally before the
## director builds her reply; ambiguous text gets one bounded model request.
func _on_player_transcript(text: String) -> void:
	if _episode.is_empty():
		return
	if str(_episode.get("phase", "")) != "ask":
		return
	if not bool(_episode.get("private", false)):
		return
	text = text.strip_edges()
	if text.is_empty():
		return
	if bool(_episode.get("consent_pending", false)):
		# A new answer replaces the one still waiting for the model.
		if bool(_episode.get("consent_started", false)):
			var classifier := _classifier()
			if is_instance_valid(classifier):
				classifier.call("cancel_key", str(_episode.get("consent_key", "")))
		_episode["consent_pending"] = false
		_episode["consent_started"] = false
		_episode["reply_seen"] = false
	if bool(_episode.get("reply_seen", false)):
		# One clear answer ends the wait. After the one clarification, a different answer
		# may still resolve it; the same text is the `_tick_ask` fallback re-reading it.
		if not bool(_episode.get("clarified", false)):
			return
		if text == str(_episode.get("response_text", "")):
			return
	_episode["reply_seen"] = true
	_episode["reacted"] = true
	_episode["response_text"] = text
	_episode["deadline_at"] = _now() + REPLY_GRACE_S
	_debug("request consent text=\"%s\"" % text.left(120))
	var intent := CONSENT.local_intent(text, _player_name())
	if intent != "unclear":
		_resolve_consent(intent, text, "local")
		return
	# Do not put a classifier request beside the director's reply to the same line. The
	# tick starts it once the director is idle again.
	_episode["consent_text"] = text
	_episode["consent_pending"] = true
	_episode["consent_started"] = false
	_debug("request consent waiting %s" % str(_episode.get("id", "")))


func _on_consent_result(intent: String, detail: String, serial: int, text: String) -> void:
	if _episode.is_empty() or int(_episode.get("serial", -1)) != serial:
		return
	_episode["consent_pending"] = false
	_episode["consent_started"] = false
	_resolve_consent(intent, text, "llm" if detail.is_empty() else "llm:%s" % detail)


## Start the model request only after the director is idle. The player's line and the
## director's reply already occupy the provider; a second request beside it is what produced
## the HTTP 429s. Clear answers never reach this function.
func _start_consent_classification() -> void:
	if _episode.is_empty() or bool(_episode.get("consent_started", false)):
		return
	if not bool(_episode.get("consent_pending", false)):
		return
	var text := str(_episode.get("consent_text", "")).strip_edges()
	if text.is_empty():
		_resolve_consent("unclear", text, "empty")
		return
	var classifier := _classifier()
	if not is_instance_valid(classifier):
		_resolve_consent("unclear", text, "unavailable")
		return
	var id := str(_episode.get("id", ""))
	var offer := "The pony %s has just asked Anon directly to have sex with her. She is waiting for his answer." % id
	var serial := int(_episode.get("serial", -1))
	var key := "offer:%s:%d" % [id, serial]
	_episode["consent_key"] = key
	_episode["consent_started"] = true
	var accepted: bool = bool(classifier.call("classify_offer", text, offer, key,
		Callable(self, "_on_consent_result").bind(serial, text)))
	if not accepted:
		_episode["consent_started"] = false
		_episode["consent_pending"] = false
		_resolve_consent("unclear", text, "unavailable")
		return
	_debug("request consent classify %s text=\"%s\"" % [id, text.left(120)])


func _resolve_consent(intent: String, text: String, source: String) -> void:
	if _episode.is_empty() or str(_episode.get("phase", "")) != "ask":
		return
	var id := str(_episode.get("id", ""))
	_episode["consent_pending"] = false
	_episode["consent_intent"] = intent
	_episode["consent_source"] = source
	_debug("request consent %s intent=%s source=%s text=\"%s\"" % [
		id, intent, source, text.left(120)])
	match intent:
		"accept":
			_accept_offer()
		"decline":
			_decline_offer()
		_:
			_clarify_consent()


func _accept_offer() -> void:
	var pony: Node3D = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		_cancel_episode(false, "accept pony lost")
		return
	# A third pony may have arrived while she was asking.
	_episode["private"] = _private_at_player(pony)
	_log_privacy_once(pony)
	if not bool(_episode.get("private", false)):
		_debug("request accept blocked %s: no longer private" % str(_episode.get("id", "")))
		_cancel_episode(false, "accept not private")
		return
	var pose := str(_episode.get("pose", ""))
	if pose == CATALOG.MISSIONARY:
		_episode["accepted_at"] = _now()
		_episode["invite_queued"] = false
		if bool(_episode.get("cuddle", false)):
			_episode["phase"] = "invite"
			_episode["invite_started"] = _now()
			if not _queue_invitation():
				_cancel_episode(false, "accept bed invite failed")
				return
			_episode["invite_queued"] = true
		elif not _start_bed_lead():
			_cancel_episode(false, "accept bed lead failed")
			return
		_record_consent_situation(true)
		_debug("request accept %s pose=missionary cuddle=%s" % [
			str(_episode.get("id", "")), str(_episode.get("cuddle", false))])
		return
	if not runtime.has_method("present_standing") or not bool(runtime.call("present_standing")):
		_debug("request accept present failed %s" % str(_episode.get("id", "")))
		_cancel_episode(false, "accept present failed")
		return
	_episode["phase"] = "present"
	_episode["accepted_at"] = _now()
	_episode["present_until"] = _now() + PRESENT_TURN_TIMEOUT_S
	_episode["invite_queued"] = false
	_record_consent_situation(true)
	_debug("request accept %s private=true" % str(_episode.get("id", "")))


func _decline_offer() -> void:
	var id := str(_episode.get("id", ""))
	_record_consent_situation(false)
	_cancel_episode(true, "declined")
	_debug("request decline %s" % id)


func _clarify_consent() -> void:
	if _episode.is_empty():
		return
	if bool(_episode.get("clarified", false)):
		_give_up("unclear")
		return
	var director: Node = _director()
	if director == null or not director.has_method("queue_generated_intent"):
		return
	var id := str(_episode.get("id", ""))
	var serial := int(_episode.get("serial", 0))
	var key := "%s:%s:%d:clarify" % [KEY_PREFIX, id, serial]
	var queued := bool(director.call("queue_generated_intent", id, _clarify_purpose(), key,
		Callable(self, "_clarify_valid").bind(serial), Callable(), true))
	if queued:
		_episode["clarified"] = true
		_episode["deadline_at"] = _now() + CLARIFY_GRACE_S
		var keys: Array = _episode.get("keys", [])
		if not key in keys:
			keys.append(key)
		_episode["keys"] = keys
		_debug("request clarify %s" % id)


func _clarify_valid(serial: int) -> bool:
	if _episode.is_empty() or int(_episode.get("serial", -1)) != serial:
		return false
	if str(_episode.get("phase", "")) != "ask":
		return false
	var pony: Node = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	var player: Variant = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_offer", str(_episode.get("pose", "")),
		str(_episode.get("source", "")), _episode.get("bed")))


func _invite_give_up() -> void:
	var id := str(_episode.get("id", ""))
	_record_end_situation("invite timeout")
	var director: Node = _director()
	if director != null and director.has_method("queue_generated_intent"):
		var key := "%s:%s:%d:invite_giveup" % [KEY_PREFIX, id, int(_episode.get("serial", 0))]
		director.call("queue_generated_intent", id, _invite_give_up_purpose(), key,
			Callable(self, "_pony_alive").bind(id), Callable(), true)
	_cancel_episode(true, "invite give up")
	_debug("request invite give up %s" % id)


func _classifier() -> Node:
	if not is_instance_valid(main):
		return null
	var classifier: Variant = main.get("classifier")
	return classifier if is_instance_valid(classifier) else null


## The scenario that allows Y while the feature flag is off. An active request is enough;
## the later present/invite phases keep the same scenario.
func press_y_scenario(pony: Node) -> String:
	if _episode.is_empty() or not is_instance_valid(pony) or _episode.get("pony") != pony:
		return ""
	var phase := str(_episode.get("phase", ""))
	return "request" if phase in ["ask", "present", "invite", "bed_lead", "bed_wait"] else ""


static func y_start_allowed(flag: bool, source: String, scenario: String) -> bool:
	if flag:
		return true
	if source in ["bed_side", "already_lying"]:
		return true
	return not scenario.is_empty()


func _player_name() -> String:
	var director: Node = _director()
	if director == null:
		return "Anon"
	var config: Variant = director.get("config")
	if config == null:
		return "Anon"
	return str(config.get_value("player_name", "Anon"))


func _last_player_text() -> String:
	var director: Node = _director()
	if director == null:
		return ""
	return str(director.get("_player_text")).strip_edges()


func _hook_director() -> void:
	var director: Node = _director()
	if director == null or not director.has_signal("transcript"):
		return
	if not director.transcript.is_connected(_on_player_transcript):
		director.transcript.connect(_on_player_transcript)


func _unhook_director() -> void:
	var director: Node = _director()
	if director == null or not director.has_signal("transcript"):
		return
	if director.transcript.is_connected(_on_player_transcript):
		director.transcript.disconnect(_on_player_transcript)


func _queue_reminder(number: int) -> bool:
	var director: Node = _director()
	if director == null or str(director.get("state")) != "idle":
		return false
	var id := str(_episode.get("id", ""))
	var key := "%s:%s:%d:prompt%d" % [KEY_PREFIX, id, int(_episode.get("serial", 0)), number]
	var keys: Array = _episode.get("keys", [])
	if key in keys:
		return false
	var queued: bool = bool(director.call("queue_generated_intent", id, _reminder_purpose(),
		key, Callable(self, "_episode_valid").bind(int(_episode.get("serial", 0))), Callable(), true))
	if queued:
		keys.append(key)
		_episode["keys"] = keys
		_debug("request reminder %d %s" % [number, id])
	return queued


func _give_up(reason := "timeout") -> void:
	var id := str(_episode.get("id", ""))
	_record_end_situation(reason)
	var director: Node = _director()
	if director != null and director.has_method("queue_generated_intent"):
		var key := "%s:%s:%d:giveup" % [KEY_PREFIX, id, int(_episode.get("serial", 0))]
		director.call("queue_generated_intent", id, _give_up_purpose(), key,
			Callable(self, "_pony_alive").bind(id), Callable(), true)
	_cancel_episode(true, "give up:" + reason)
	_debug("request give up %s reason=%s" % [id, reason])


func _cancel_episode(set_cooldown: bool, reason := "", keep_rest := false) -> void:
	if _episode.is_empty():
		return
	var pony: Node = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	var id := str(_episode.get("id", ""))
	var phase := str(_episode.get("phase", ""))
	var classifier := _classifier()
	if is_instance_valid(classifier):
		classifier.call("cancel_scope", "offer:")
	if is_instance_valid(runtime) and runtime.has_method("set_request_face"):
		runtime.call("set_request_face", false)
	if is_instance_valid(runtime) and runtime.has_method("clear_presentation"):
		runtime.call("clear_presentation")
	if not keep_rest and bool(_episode.get("bed_joined", false)) and is_instance_valid(pony):
		REST_CONTROL.release_managed(pony)
	_release_nav()
	if set_cooldown and phase in ["present", "invite", "ask", "bed_lead", "bed_wait"]:
		_set_cooldown(id)
	elif not set_cooldown and phase in ["approach", "arrive", "present", "invite", "ask",
			"bed_approach", "bed_lead", "bed_wait"]:
		# A walk-over or unavailable ask must not retry every scan, but must not eat the full
		# cooldown either.
		_retry_at[id] = _now() + RETRY_S
	var director: Node = _director()
	if director != null and director.has_method("cancel_authored_line"):
		for key: Variant in _episode.get("keys", []):
			director.call("cancel_authored_line", str(key))
	if not reason.is_empty():
		_debug("request end %s phase=%s reason=%s" % [id, phase, reason])
	_episode = {}


func _release_nav() -> void:
	if bool(_episode.get("nav_released", false)):
		return
	var nav: Node = _episode.get("nav")
	if not is_instance_valid(nav):
		return
	var token := str(_episode.get("token", ""))
	if str(nav.get("command_owner")) == token:
		nav.set("command_owner", str(_episode.get("prev_owner", "")))
	nav.set("wander_enabled", bool(_episode.get("prev_wander", true)))
	if _episode.get("prev_limit") != null:
		nav.set("command_speed_limit", _episode.get("prev_limit"))
	if _episode.get("prev_pace") != null:
		nav.set("command_pace_target", _episode.get("prev_pace"))


func _tick_episode(delta: float) -> void:
	var phase := str(_episode.get("phase", ""))
	if phase == "approach":
		_tick_approach()
	elif phase == "arrive":
		_tick_arrive()
	elif phase == "present":
		_tick_present()
	elif phase == "invite":
		_tick_invite()
	elif phase == "bed_lead":
		_tick_bed_lead()
	elif phase == "bed_approach":
		_tick_bed_approach()
	elif phase == "bed_wait":
		_tick_bed_wait()
	elif phase == "ask":
		_tick_ask(delta)
	else:
		_cancel_episode(false)


# --------------------------------------------------------------------------- director and prompts

func _ask_context() -> String:
	var cuddle := bool(_episode.get("cuddle", false))
	var private := bool(_episode.get("private", false))
	var pose := str(_episode.get("pose", ""))
	var text := "[Observed situation, not player speech] "
	if cuddle:
		text += "You are cuddling with Anon and want more. You have decided to invite him to have sex in the bed. "
	elif pose == CATALOG.MISSIONARY:
		text += "You want Anon in bed with you. You have decided to invite him to come to bed and have sex. "
	else:
		text += "You want Anon to take you from behind. You have decided to ask him to come and have sex with you. "
	if not private:
		text += "Other ponies are around. Ask indirectly, with an in-character euphemism or hint; do not say it plainly. Phrase it as a question to him. "
	elif pose == CATALOG.STANDING:
		text += "You are alone together. Ask him directly, in your own voice, and make it an unmistakable sexual invitation; do not hint. Phrase it as a direct question ending with a question mark. "
	elif pose == CATALOG.MISSIONARY:
		text += "You are alone together. Ask him directly to come to bed with you, in your own voice, and make it an unmistakable invitation; do not hint. Phrase it as a direct question ending with a question mark. "
	else:
		text += "You are alone together. You may ask directly and bluntly or hint indirectly, whichever fits you; phrase it as a question to him. "
	text += "Say one or two short sentences in your own voice. Do not describe your body or narrate actions, and do not use action tags."
	return text


func _ask_purpose() -> String:
	var private := bool(_episode.get("private", false))
	var cuddle := bool(_episode.get("cuddle", false))
	var pose := str(_episode.get("pose", ""))
	var text := "You have decided to ask Anon for sex."
	if cuddle:
		text = "You are cuddling with Anon and have decided to invite him to have sex in the bed."
	elif pose == CATALOG.MISSIONARY:
		text = "You want Anon in bed with you and have decided to invite him to come to bed for sex."
	elif pose == CATALOG.STANDING:
		text = "You want Anon to take you from behind and have decided to ask him for sex."
	if not private:
		text += " Other ponies are around, so hint indirectly and do not say it plainly; phrase it as a question."
	elif pose == CATALOG.STANDING:
		text += " You are alone together. Ask him directly and unmistakably in your own voice; do not hint. You are asking him a question."
	elif pose == CATALOG.MISSIONARY:
		text += " You are alone together. Ask him directly to come to bed with you; do not hint. You are asking him a question."
	else:
		text += " You may ask directly and bluntly or hint indirectly, in your own voice; phrase it as a question."
	text += " Say one or two short sentences. Do not narrate actions. End with a question mark."
	return text


func _invite_purpose() -> String:
	if str(_episode.get("pose", "")) == CATALOG.MISSIONARY:
		return "You are lying beside Anon on the bed, ready for him. Comment on taking the bed position and invite him in your own voice. One short sentence. Do not narrate actions."
	return "You have just turned your back to Anon and lifted your tail aside, ready for him. Comment on taking the position and invite him in your own voice. One short sentence. Do not narrate actions."


func _clarify_purpose() -> String:
	return "Anon's answer was not clear. Ask him plainly, as a direct question, whether he wants this, in your own voice. One short sentence ending with a question mark. Do not narrate actions."


func _invite_give_up_purpose() -> String:
	return "Anon accepted but did not take you up on it. Say one short, in-character line letting it go for now, without anger. Do not narrate actions."


func _reminder_purpose() -> String:
	if not bool(_episode.get("private", false)):
		return "Anon has not reacted to your hint. Ask once more, indirectly and in character, as a question in one short sentence. Other ponies are around. Do not repeat your first line."
	return "Anon has not answered your offer. Ask the question once more, short and in character; playful or blunt is fine (\"come on, don't you want me?\"). Do not repeat your first line."


func _give_up_purpose() -> String:
	return "Your offer is over for now. Say one short, in-character line letting it go without pressure or anger. Do not ask again and do not narrate actions."


func _record_situation() -> void:
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return
	var ctx: Variant = game.get("world_context")
	if not is_instance_valid(ctx):
		return
	var id := str(_episode.get("id", ""))
	if id.is_empty():
		return
	var text := "You are with Anon and have decided to ask him for sex."
	if bool(_episode.get("cuddle", false)):
		text = "You are cuddling with Anon and have decided to invite him to have sex in the bed."
	elif str(_episode.get("pose", "")) == CATALOG.MISSIONARY:
		text = "You want Anon in bed with you and have decided to invite him to come to bed for sex."
	elif str(_episode.get("pose", "")) == CATALOG.STANDING:
		text = "You want Anon to take you from behind and have decided to ask him for sex."
	if not bool(_episode.get("private", false)):
		text += " Other ponies are around, so you can only hint at it."
	ctx.call("record", "situation", text, [id], [id],
		"%s:%s:%d:situation" % [KEY_PREFIX, id, int(_episode.get("serial", 0))])


func _record_consent_situation(accepted: bool) -> void:
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return
	var ctx: Variant = game.get("world_context")
	if not is_instance_valid(ctx):
		return
	var id := str(_episode.get("id", ""))
	if id.is_empty():
		return
	var text := "Anon accepted your offer. You are alone together and taking the position he came for." if accepted \
		else "Anon declined your offer. Accept it gracefully and do not pressure him."
	var mark := "accepted" if accepted else "declined"
	ctx.call("record", "situation", text, [id], [id],
		"%s:%s:%d:%s" % [KEY_PREFIX, id, int(_episode.get("serial", 0)), mark])


## The offer is over without an answer. Replace the open "you have decided to ask" situation
## so the director's next line does not keep the offer alive after the controller gave up.
func _record_end_situation(reason: String) -> void:
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return
	var ctx: Variant = game.get("world_context")
	if not is_instance_valid(ctx):
		return
	var id := str(_episode.get("id", ""))
	if id.is_empty():
		return
	var text := "Your offer for sex is over for now. Anon did not take it up; let it go without pressure and stop asking."
	ctx.call("record", "situation", text, [id], [id],
		"%s:%s:%d:end:%s" % [KEY_PREFIX, id, int(_episode.get("serial", 0)), reason])


func _episode_valid(serial: int) -> bool:
	if _episode.is_empty() or int(_episode.get("serial", -1)) != serial:
		return false
	var pony: Node = _episode.get("pony")
	var runtime: Node = _episode.get("runtime")
	if not is_instance_valid(pony) or not is_instance_valid(runtime):
		return false
	if bool(_episode.get("reacted", false)) or _player_reacted():
		return false
	var player: Variant = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(player):
		return false
	if player.global_position.distance_to(pony.global_position) > ASK_RANGE_CANCEL_M:
		return false
	return bool(runtime.call("can_offer", str(_episode.get("pose", "")), str(_episode.get("source", "")), _episode.get("bed")))


func _pony_alive(id: String) -> bool:
	if id.is_empty() or not is_instance_valid(main):
		return false
	for node: Variant in _mares():
		if is_instance_valid(node) and _pony_id(node) == id:
			return true
	return false


func _player_reacted() -> bool:
	var director: Node = _director()
	if director == null:
		return false
	var said: Variant = director.get("_player_text")
	if said != null and str(said) != "":
		return true
	var held: Variant = director.get("_held_text")
	if held != null and str(held) != "":
		return true
	var speech: Variant = director.get("speech")
	return speech != null and is_instance_valid(speech) and str(speech.get("state")) == "hearing"


func _director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


func _director_idle() -> bool:
	var director: Node = _director()
	return director != null and str(director.get("state")) == "idle"


func _episode_pony_speaking() -> bool:
	var pony: Node = _episode.get("pony")
	return is_instance_valid(pony) and pony.has_method("is_speaking") and bool(pony.call("is_speaking"))


func _quiet() -> bool:
	if not is_instance_valid(main) or get_tree().paused:
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if main.call("menu_open"):
		return false
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return false
	if bool(player.get("controls_locked")) or bool(player.get("flying")):
		return false
	if bool(player.get_meta("knocked_down", false)):
		return false
	var director: Node = _director()
	if director == null or not director.has_method("begin_player_greeting"):
		return false
	if str(director.get("state")) != "idle":
		return false
	var approaches: Variant = director.get("player_approaches")
	if approaches != null and approaches.has_method("active") and bool(approaches.call("active")):
		return false
	var group: Variant = director.get("group")
	if group != null and group.has_method("active") and bool(group.call("active")):
		return false
	var speech: Variant = director.get("speech")
	if speech != null and is_instance_valid(speech) and str(speech.get("state")) == "hearing":
		return false
	var config: Variant = director.get("config")
	if config != null and not AI_CONFIG.background_allowed(config):
		return false
	var now := float(director.call("_now"))
	var characters: Variant = director.get("characters")
	if characters is Dictionary:
		for entry: Variant in (characters as Dictionary).values():
			if entry is Dictionary and now - float((entry as Dictionary).get("chat_last", -1e9)) < QUIET_CHAT_GAP_S:
				return false
	return true


func _offer_targets_pony(pony: Node) -> bool:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return false
	if not main.has_method("_refresh_offer"):
		return false
	main.call("_refresh_offer")
	var offer: Variant = main.get("_offer")
	return offer is Dictionary and not (offer as Dictionary).is_empty() and (offer as Dictionary).get("pony") == pony


# --------------------------------------------------------------------------- helpers

func _mares() -> Array:
	if not is_instance_valid(main):
		return []
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return []
	var list: Variant = game.get("mares")
	return list if list is Array else []


func _pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


func _region_of(at: Vector3) -> String:
	return str(WorldLayout.nearest(at).get("id", ""))


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


# --------------------------------------------------------------------------- pure rules (tested headless)

static func cooldown_ready(now: float, last: float) -> bool:
	return now - last >= COOLDOWN_S


static func cuddle_private(indoor: bool, house_alone: bool, others_near: bool) -> bool:
	return house_alone if indoor else not others_near


static func presentation_allowed(house_alone: bool, others_near: bool) -> bool:
	return house_alone or not others_near


static func wording_mode(private: bool) -> String:
	return "free" if private else "indirect"


static func next_prompt_time(prompts_sent: int) -> float:
	if prompts_sent <= 0:
		return PROMPT_1_S
	if prompts_sent == 1:
		return PROMPT_2_S
	return -1.0


## Per-mare pose choice for an automatic offer. Both feasible: a coin flip; one feasible: it.
static func pick_offer_pose(bed_ok: bool, standing_ok: bool, roll: float) -> String:
	if bed_ok and standing_ok:
		return CATALOG.MISSIONARY if roll < 0.5 else CATALOG.STANDING
	if bed_ok:
		return CATALOG.MISSIONARY
	if standing_ok:
		return CATALOG.STANDING
	return ""
