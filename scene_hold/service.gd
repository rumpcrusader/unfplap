extends RefCounted
## The scene ownership the act borrows: the navigator lease, the player's movement hold, the
## face-turn rate, the conversation attention, the carry and the cuddle session. The runtime owns
## the act state and the one teardown ledger; this object owns the flags and the release order.
## Contract: `docs/scene_hold.md`.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const STATE_IDLE := 0
const STATE_AFTERGLOW := 4
const STATE_RESTORE := 5

## The two owner namespaces: an act lease and a negotiation lease. The scene gate accepts both
## through the hold's compatibility predicate.
const TOKEN_ACT := "unfplap:"
const TOKEN_NEGOTIATION := "unfplap:negotiation:"

## Ownership state. The runtime keeps read views for its old field names and the reports.
var nav: Node = null
var token := ""
var nav_old_wander := true
## True while this ledger holds the negotiation lease. `adopt_hold()` hands it to the act.
var negotiation := false
## True while this ledger set the game's `affection_active` meta and must clear it.
var affection_owned := false
var face_turn_rate_owned := false
var face_turn_rate_saved := -1.0
var locked_player := false
var had_kiss_hold := false
var kisser: Node = null
var kisser_processing := false

## Host boundary. A missing callback is a no-op.
var host: Dictionary = {}


func bind(host_in: Dictionary) -> void:
	host = host_in


func _host(key: String, fallback: Variant = null) -> Variant:
	var value: Variant = host.get(key, null)
	if value is Callable:
		return (value as Callable).call()
	return fallback


func _callback(key: String) -> Callable:
	var value: Variant = host.get(key, null)
	return value as Callable if value is Callable else Callable()


## Take the navigator: the act owns the lease and holds her in place. The token is the runtime's
## `unfplap:<id>` owner string.
func claim_nav(owner_id: String) -> bool:
	return _claim(owner_id, TOKEN_ACT)


## Claim the negotiation lease: `unfplap:negotiation:<id>`. It works while the runtime is IDLE.
## A missing or reserved navigator, another mod's live owner, or a routine owner with an active
## route is Occupied.
func claim_negotiation(owner_id: String) -> bool:
	return _claim(owner_id, TOKEN_NEGOTIATION)


## Take the attention and physical affection hold without a navigator lease. A cuddle session
## already owns the navigator; the negotiation keeps Anon as the target, owns the affection meta
## and leaves the session's lease alone.
func claim_attention() -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return false
	var found: Node = pony.get_node_or_null("Navigator")
	if found == null or str(found.get("reserved_by")) != "":
		return false
	nav = null
	token = ""
	negotiation = true
	return true


## Take over an owner that the proactive request already holds. The release data (`old_wander`)
## comes from the request lease; the navigator itself is not changed.
func transfer_nav(existing_token: String, old_wander := true) -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony) or existing_token.is_empty():
		return false
	var found: Node = pony.get_node_or_null("Navigator")
	if found == null or str(found.get("command_owner")) != existing_token:
		return false
	nav = found
	token = existing_token
	nav_old_wander = old_wander
	negotiation = true
	nav.call("stay")
	nav.set("command_owner", token)
	nav.set("wander_enabled", false)
	return str(nav.get("command_owner")) == token


## Attach this ledger to an owner claimed elsewhere, without touching the navigator. The act
## start uses it when the negotiation ledger is a different object.
func adopt_nav(existing_token: String, old_wander := true) -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony) or existing_token.is_empty():
		return false
	var found: Node = pony.get_node_or_null("Navigator")
	if found == null or str(found.get("command_owner")) != existing_token:
		return false
	nav = found
	token = existing_token
	nav_old_wander = old_wander
	negotiation = false
	return true


## Keep this ledger's negotiation hold as the act hold: the owner, wander and affection stay
## untouched, so the act start does not claim a second owner.
func adopt_hold() -> bool:
	if not holds_negotiation():
		return false
	negotiation = false
	return true


## True while this ledger owns the negotiation lease.
func holds_negotiation() -> bool:
	if not negotiation or token.is_empty() or nav == null or not is_instance_valid(nav):
		return false
	return str(nav.get("command_owner")) == token


## The scene gate's hold-compatibility predicate. It is true while the affection hold is ours
## and, when there is a navigator lease, the owner is this ledger's token. An attention-only
## cuddle hold has no lease of its own.
func accepts_hold(_pose: String, _source: String) -> bool:
	if not affection_owned:
		return false
	if token.is_empty():
		return true
	if nav == null or not is_instance_valid(nav):
		return false
	return str(nav.get("command_owner")) == token


func _claim(owner_id: String, prefix: String) -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return false
	nav = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	if str(nav.get("reserved_by")) != "":
		return false
	if prefix == TOKEN_NEGOTIATION:
		var owner := str(nav.get("command_owner"))
		if owner.begins_with("unfplap:"):
			return false
		# A routine owner is free only with no active route; anything else is Occupied.
		if not owner.is_empty() and not (owner.begins_with("life:") or owner.begins_with("day:")):
			return false
		if bool(nav.get("_has_target")):
			return false
	nav_old_wander = bool(nav.get("wander_enabled"))
	token = prefix + owner_id
	negotiation = prefix == TOKEN_NEGOTIATION
	nav.call("stay")
	nav.set("command_owner", token)
	nav.set("wander_enabled", false)
	return str(nav.get("command_owner")) == token


## Re-assert the lease on every tick if another system changed the owner. A negotiation lease also
## clears a walk target another system set, so she stays with Anon.
func keep_nav() -> void:
	if nav == null or not is_instance_valid(nav):
		return
	if str(nav.get("command_owner")) != token:
		nav.call("stay")
		nav.set("command_owner", token)
		nav.set("wander_enabled", false)
	if negotiation and bool(nav.get("_has_target")):
		nav.call("stay")


## Give the navigator back and restore the wander flag it had before the act. The adopted hold's
## affection meta is cleared here too, so a normal act teardown releases both.
func release_nav() -> void:
	release_affection()
	if nav == null or not is_instance_valid(nav):
		nav = null
		token = ""
		negotiation = false
		return
	if str(nav.get("command_owner")) == token:
		nav.set("command_owner", "")
	nav.set("wander_enabled", nav_old_wander)
	nav = null
	token = ""
	negotiation = false


## Keep Anon as her conversation target. A cleared target is re-asserted; another live target is
## an attention reassignment and returns false, so the negotiation can end with `target_left`.
func keep_target() -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	var player: Variant = WORLD.player
	if not is_instance_valid(player):
		return false
	if not pony.has_method("set_conversation_target"):
		return false
	var current: Variant = pony.get("conversation_target")
	if is_instance_valid(current) and current != player:
		# The game points at Anon's rig/body child, not always at main.player itself.
		var under_player := current is Node and player is Node \
			and (player as Node).is_ancestor_of(current as Node)
		if not under_player:
			return false
	pony.call("set_conversation_target", player, true)
	return true


## Take the game's physical affection hold. The offering request's own face hold is handed over at
## formation; any other live affection hold is Occupied.
func hold_affection() -> bool:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return false
	if affection_owned:
		return true
	if pony.has_meta("affection_active"):
		return false
	affection_owned = true
	pony.set_meta("affection_active", true)
	return true


## Clear the affection hold only when this ledger set it.
func release_affection() -> void:
	var pony: Variant = _host("pony")
	if affection_owned and is_instance_valid(pony) and pony.has_meta("affection_active"):
		pony.remove_meta("affection_active")
	affection_owned = false


## Release the whole negotiation hold: the physical affection first, then the navigator lease.
## Idempotent; every terminal outcome calls it.
func release_negotiation() -> void:
	release_affection()
	release_nav()


## Hold the standing face-turn rate at zero without pausing locomotion or emotions. A forced call
## also pauses it in a non-standing pose, for the failed-start report.
func pause_face_turn(force := false) -> void:
	var pony: Variant = _host("pony")
	if (not force and str(_host("pose_family", "")) != "standing") \
			or not is_instance_valid(pony):
		return
	if face_turn_rate_owned:
		if absf(float(pony.get("face_turn_rate"))) > 0.0001:
			pony.set("face_turn_rate", 0.0)
		return
	var rate: Variant = pony.get("face_turn_rate")
	if rate == null:
		return
	face_turn_rate_saved = float(rate)
	if absf(face_turn_rate_saved) > 0.0001:
		pony.set("face_turn_rate", 0.0)
		face_turn_rate_owned = true


func restore_face_turn() -> void:
	var pony: Variant = _host("pony")
	if face_turn_rate_owned and is_instance_valid(pony):
		pony.set("face_turn_rate", face_turn_rate_saved)
	face_turn_rate_owned = false
	face_turn_rate_saved = -1.0


## Keep the act's attention while another character talks to Anon. Clearing the listener every
## tick stops the director from turning her away or pinning her gaze; speech, emotions and
## locomotion keep running, and the act's own interruption check does not treat conversation as a
## stop.
func keep_attention() -> void:
	if int(_host("state", 0)) in [STATE_IDLE, STATE_RESTORE, STATE_AFTERGLOW]:
		return
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return
	if pony.has_method("set_conversation_target"):
		pony.call("set_conversation_target", null, false)


## Hold the player's movement with the game's `kiss_hold` meta, not `controls_locked`: the camera
## stays free. The game's kisser removes the meta every physics tick, so its physics is paused.
func lock_player() -> void:
	if not is_instance_valid(WORLD.game):
		return
	var body: Variant = WORLD.player
	if not is_instance_valid(body):
		return
	had_kiss_hold = body.has_meta("kiss_hold")
	if not had_kiss_hold:
		body.set_meta("kiss_hold", true)
	if is_instance_valid(WORLD.game):
		var found: Variant = WORLD.game.get("kisser")
		if is_instance_valid(found) and found is Node:
			kisser = found as Node
			kisser_processing = kisser.is_physics_processing()
			if kisser_processing:
				kisser.set_physics_process(false)
	locked_player = true
	if body.get("seat") != null:
		body.set("_q_held", true)


func unlock_player() -> void:
	if not locked_player:
		return
	if is_instance_valid(kisser):
		kisser.set_physics_process(kisser_processing)
	kisser = null
	kisser_processing = false
	if is_instance_valid(WORLD.player):
		var body: Variant = WORLD.player
		if not had_kiss_hold and body.has_meta("kiss_hold"):
			body.remove_meta("kiss_hold")
	locked_player = false


## Release the held carry and return whether the carry was ours. A refused cradle start uses the
## false answer to abort.
func release_carry() -> bool:
	if not is_instance_valid(WORLD.game):
		return false
	var reach: Node = WORLD.interactor()
	var pony: Variant = _host("pony")
	if not is_instance_valid(reach) or not is_instance_valid(pony):
		return false
	if reach.get("held") != pony or reach.get("cradled") != true:
		return false
	pony.call("end_interaction")
	reach.set("held", null)
	reach.set("cradled", false)
	reach.set("_drop_upright", false)
	reach.set("_laying", -1.0)
	reach.set("_sleepy_kiss", false)
	reach.set("_lean", 0.0)
	reach.set("_lay", {})
	var actions: Variant = reach.get("desktop_actions")
	if is_instance_valid(actions) and actions.has_method("pony_released"):
		actions.call("pony_released")
	return true


## End the game's cuddle session before the act takes the pose.
func end_cuddle() -> void:
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session != null and session.has_method("end"):
		if bool(session.get("enabled")) or float(session.get("blend")) > 0.0:
			session.call("end", true)
	if pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")
