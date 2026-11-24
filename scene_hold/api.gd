extends Node
## Scope: pony
## The scene ownership an act borrows and gives back.
## The runtime owns the act state; this ledger owns the flags and the release order.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_IDLE := ACT_STATE.State.IDLE
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW
const STATE_RESTORE := ACT_STATE.State.RESTORE

## The two owner namespaces: an act lease and a negotiation lease. The scene gate accepts both
## through the hold's compatibility predicate.
const TOKEN_ACT := "unfplap:"
const TOKEN_NEGOTIATION := "unfplap:negotiation:"

## Ownership state. The runtime keeps read views for its old field names and the reports.
## Each flag says what this ledger actually took, which is what lets a start that aborted halfway
## give the same ownership back through the same teardown a normal end uses.
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
## Named holds on the game's excitement Beat, one per owner that asked for it.
var _beat_holders: Array[String] = []
var _beat: Timer = null
var _beat_saved := false
var _beat_paused := false

## The live values the ledger reads. The composition root keeps each read current.
class Host extends RefCounted:
	var pony: Callable = Callable()
	var state: Callable = Callable()
	var pose_family: Callable = Callable()

	func pony_node() -> Node:
		return pony.call() as Node if pony.is_valid() else null

	func state_value() -> int:
		return int(state.call()) if state.is_valid() else 0

	func pose_family_value() -> String:
		return str(pose_family.call()) if pose_family.is_valid() else ""


## Host boundary. A missing callback is a no-op.
var host: Host = null


func bind(host_in: Host) -> void:
	host = host_in


## Take the navigator: the act owns the lease and holds her in place. The token is the runtime's
## `unfplap:<id>` owner string.
func claim_nav(owner_id: String) -> bool:
	return _claim(owner_id, TOKEN_ACT)


## Claim the negotiation lease, which works while the runtime is IDLE.
## A reserved navigator, a foreign owner or a live route is Occupied.
func claim_negotiation(owner_id: String) -> bool:
	return _claim(owner_id, TOKEN_NEGOTIATION)


## Take attention and the affection hold with no navigator lease.
## A cuddle session already has the navigator, so that owner is left alone.
func claim_attention() -> bool:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony):
		return false
	var lease := WORLD.navigator(pony)
	if not lease.present() or not lease.reserved().is_empty():
		return false
	nav = null
	token = ""
	negotiation = true
	return true


## Take over an owner that the proactive request already holds. The release data (`old_wander`)
## comes from the request lease; the navigator itself is not changed.
func transfer_nav(existing_token: String, old_wander: bool = true) -> bool:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony) or existing_token.is_empty():
		return false
	var lease := WORLD.navigator(pony)
	var found := lease.node()
	if found == null:
		return false
	if lease.owner() != existing_token:
		return false
	nav = found
	token = existing_token
	nav_old_wander = old_wander
	negotiation = true
	lease.stay()
	lease.set_owner(token)
	lease.set_wander(false)
	return lease.owner() == token


## Attach this ledger to an owner claimed elsewhere, without touching the navigator. The act
## start uses it when the negotiation ledger is a different object.
func adopt_nav(existing_token: String, old_wander: bool = true) -> bool:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony) or existing_token.is_empty():
		return false
	var lease := WORLD.navigator(pony)
	var found := lease.node()
	if found == null or lease.owner() != existing_token:
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


## True while the negotiation lease is ours.
func holds_negotiation() -> bool:
	if not negotiation or token.is_empty() or nav == null or not is_instance_valid(nav):
		return false
	return WORLD.navigator(nav).owner() == token


## The scene gate's hold predicate: our affection hold, plus our lease when there is one.
## An attention-only cuddle hold has none.
func accepts_hold(_pose: String, _source: String) -> bool:
	if not affection_owned:
		return false
	if token.is_empty():
		return true
	if nav == null or not is_instance_valid(nav):
		return false
	return WORLD.navigator(nav).owner() == token


func _claim(owner_id: String, prefix: String) -> bool:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony):
		return false
	var lease := WORLD.navigator(pony)
	nav = lease.node()
	if nav == null:
		return false
	if lease.reserved() != "":
		return false
	if prefix == TOKEN_NEGOTIATION:
		var owner := lease.owner()
		if owner.begins_with("unfplap:"):
			return false
		# A routine owner is free only with no active route; anything else is Occupied.
		if not owner.is_empty() and not (owner.begins_with("life:") or owner.begins_with("day:")):
			return false
		if lease.has_target():
			return false
	nav_old_wander = lease.wander()
	token = prefix + owner_id
	negotiation = prefix == TOKEN_NEGOTIATION
	lease.stay()
	lease.set_owner(token)
	lease.set_wander(false)
	return lease.owner() == token


## Re-assert the lease on every tick if another system changed the owner. A negotiation lease also
## clears a walk target another system set, so she stays with Anon.
func keep_nav() -> void:
	# The handle the claim recorded, not the host's live pony read: a teardown that lost the pony
	# still has to give the lease back.
	if nav == null or not is_instance_valid(nav):
		return
	var lease := WORLD.navigator(nav)
	if lease.owner() != token:
		lease.stay()
		lease.set_owner(token)
		lease.set_wander(false)
	if negotiation and lease.has_target():
		lease.stay()


## Give the navigator back and restore the wander flag it had before the act. The adopted hold's
## affection meta is cleared here too, so a normal act teardown releases both.
func release_nav() -> void:
	release_affection()
	if nav == null or not is_instance_valid(nav):
		nav = null
		token = ""
		negotiation = false
		return
	var lease := WORLD.navigator(nav)
	if lease.owner() == token:
		lease.set_owner("")
	lease.set_wander(nav_old_wander)
	nav = null
	token = ""
	negotiation = false


## Keep Anon as her conversation target. A cleared target is re-asserted; another live target is
## an attention reassignment and returns false, so the negotiation can end with `target_left`.
func keep_target() -> bool:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony) or not WORLD.ready():
		return false
	var player: Node3D = WORLD.player_rig()
	if not is_instance_valid(player):
		return false
	if not pony.has_method("set_conversation_target"):
		return false
	var current: Variant = pony.get("conversation_target")
	if is_instance_valid(current) and current != player:
		# The game points at Anon's rig/body child, not always at the player rig itself.
		var under_player := current is Node and player is Node \
			and (player as Node).is_ancestor_of(current as Node)
		if not under_player:
			return false
	WORLD.navigator(pony).set_conversation_target(player, true)
	return true


## Take the game's physical affection hold. The offering request's own face hold is handed over at
## formation; any other live affection hold is Occupied.
func hold_affection() -> bool:
	var pony: Node = host.pony_node() if host != null else null
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
	var pony: Node = host.pony_node() if host != null else null
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
func pause_face_turn(force: bool = false) -> void:
	var pony: Node = host.pony_node() if host != null else null
	if (not force and (host == null or host.pose_family_value() != "standing")) \
			or not is_instance_valid(pony):
		return
	var view := WORLD.pony(pony)
	if face_turn_rate_owned:
		if absf(view.face_turn_rate()) > 0.0001:
			view.set_face_turn_rate(0.0)
		return
	var rate := view.face_turn_rate()
	if is_nan(rate):
		return
	face_turn_rate_saved = rate
	if absf(face_turn_rate_saved) > 0.0001:
		view.set_face_turn_rate(0.0)
		face_turn_rate_owned = true


func restore_face_turn() -> void:
	var pony: Node = host.pony_node() if host != null else null
	if face_turn_rate_owned and is_instance_valid(pony):
		WORLD.pony(pony).set_face_turn_rate(face_turn_rate_saved)
	face_turn_rate_owned = false
	face_turn_rate_saved = -1.0


## Drop the conversation listener every tick so another speaker cannot turn her away.
## Speech, emotions and locomotion keep running; conversation is not an interruption.
func keep_attention() -> void:
	if host == null or int(host.state_value()) in [STATE_IDLE, STATE_RESTORE, STATE_AFTERGLOW]:
		return
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony):
		return
	if pony.has_method("set_conversation_target"):
		WORLD.navigator(pony).set_conversation_target(null, false)


## Hold the player's movement with the game's `kiss_hold` meta, not `controls_locked`: the camera
## stays free. The game's kisser removes the meta every physics tick, so its physics is paused.
func lock_player() -> void:
	if not WORLD.ready():
		return
	var body: Node3D = WORLD.player_rig()
	if not is_instance_valid(body):
		return
	had_kiss_hold = body.has_meta("kiss_hold")
	if not had_kiss_hold:
		body.set_meta("kiss_hold", true)
	var found: Node = WORLD.affection().kisser()
	if is_instance_valid(found):
		kisser = found
		kisser_processing = kisser.is_physics_processing()
		if kisser_processing:
			kisser.set_physics_process(false)
	locked_player = true
	if body.get("seat") != null:
		WORLD.anon().set_q_held(true)


func unlock_player() -> void:
	if not locked_player:
		return
	if is_instance_valid(kisser):
		kisser.set_physics_process(kisser_processing)
	kisser = null
	kisser_processing = false
	if is_instance_valid(WORLD.player_rig()):
		var body: Node3D = WORLD.player_rig()
		if not had_kiss_hold and body.has_meta("kiss_hold"):
			body.remove_meta("kiss_hold")
	locked_player = false


## Release the held carry and return whether the carry was ours. A refused cradle start uses the
## false answer to abort.
func release_carry() -> bool:
	if not is_instance_valid(WORLD.world_root()):
		return false
	var reach: Node = WORLD.interactor()
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(reach) or not is_instance_valid(pony):
		return false
	if not WORLD.affection().carry_ours(reach, pony):
		return false
	WORLD.affection().end_interaction(pony)
	WORLD.affection().clear_carry(reach)
	WORLD.affection().carry_released(WORLD.affection().carry_actions(reach))
	return true


## End the game's cuddle session before the act takes the pose.
func end_cuddle() -> void:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony):
		return
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session != null and (bool(session.get("enabled")) or float(session.get("blend")) > 0.0):
		WORLD.affection().end_cuddle(session)
	if pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")


## Acquire a named hold on the game's excitement Beat: the first holder saves the current
## pause state and every holder keeps it paused. Repeating an owner is idempotent.
## A caller asks under its own name rather than writing the timer: a release then knows another
## owner may still need the Beat paused and only the final one resumes it.
func hold_beat(owner: String) -> void:
	if owner.is_empty() or _beat_holders.has(owner):
		return
	if not is_instance_valid(_beat):
		_beat = null
		_beat_saved = false
	if not _beat_saved:
		_resolve_beat()
	_beat_holders.append(owner)
	if is_instance_valid(_beat):
		_beat.paused = true


## Release a named hold; only the last release gives the saved pause state back.
func release_beat(owner: String) -> void:
	var index := _beat_holders.find(owner)
	if index >= 0:
		_beat_holders.remove_at(index)
	if not _beat_holders.is_empty():
		return
	_restore_beat()


## Act teardown fallback: drop every hold and restore the Beat once.
func release_all_beats() -> void:
	_beat_holders.clear()
	_restore_beat()


func _resolve_beat() -> void:
	var pony: Node = host.pony_node() if host != null else null
	if not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	var beat: Variant = (excitement as Node).get_node_or_null("Beat")
	if not beat is Timer:
		return
	_beat = beat as Timer
	_beat_paused = _beat.paused
	_beat_saved = true


func _restore_beat() -> void:
	if _beat_saved and is_instance_valid(_beat):
		_beat.paused = _beat_paused
	_beat = null
	_beat_saved = false
	_beat_paused = false
