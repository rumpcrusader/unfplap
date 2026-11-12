extends RefCounted
## The scene ownership the act borrows: the navigator lease, the player's movement hold, the
## face-turn rate, the conversation attention, the carry and the cuddle session. The runtime owns
## the act state and the one teardown ledger; this object owns the flags and the release order.
## Contract: `docs/scene_hold.md`.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const STATE_IDLE := 0
const STATE_AFTERGLOW := 4
const STATE_RESTORE := 5

## Ownership state. The runtime keeps read views for its old field names and the reports.
var nav: Node = null
var token := ""
var nav_old_wander := true
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
	var pony: Variant = _host("pony")
	if not is_instance_valid(pony):
		return false
	nav = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	if str(nav.get("reserved_by")) != "":
		return false
	nav_old_wander = bool(nav.get("wander_enabled"))
	token = "unfplap:" + owner_id
	nav.call("stay")
	nav.set("command_owner", token)
	nav.set("wander_enabled", false)
	return str(nav.get("command_owner")) == token


## Re-assert the lease on every tick if another system changed the owner.
func keep_nav() -> void:
	if nav == null or not is_instance_valid(nav):
		return
	if str(nav.get("command_owner")) != token:
		nav.call("stay")
		nav.set("command_owner", token)
		nav.set("wander_enabled", false)


## Give the navigator back and restore the wander flag it had before the act.
func release_nav() -> void:
	if nav == null or not is_instance_valid(nav):
		nav = null
		return
	if str(nav.get("command_owner")) == token:
		nav.set("command_owner", "")
	nav.set("wander_enabled", nav_old_wander)
	nav = null


## Hold the standing face-turn rate at zero without pausing locomotion or emotions. A forced call
## also pauses it in a non-standing pose, for the failed-start report.
func pause_face_turn(force := false) -> void:
	var pony: Variant = _host("pony")
	if (not force and str(_host("pose_id", "")) != CATALOG.STANDING) \
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
	var main: Variant = _host("main")
	if not is_instance_valid(main):
		return
	var body: Variant = main.get("player")
	if not is_instance_valid(body):
		return
	had_kiss_hold = body.has_meta("kiss_hold")
	if not had_kiss_hold:
		body.set_meta("kiss_hold", true)
	if is_instance_valid(main.get("game")):
		var found: Variant = main.get("game").get("kisser")
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
	var main: Variant = _host("main")
	if is_instance_valid(main) and is_instance_valid(main.get("player")):
		var body: Variant = main.get("player")
		if not had_kiss_hold and body.has_meta("kiss_hold"):
			body.remove_meta("kiss_hold")
	locked_player = false


## Release the held carry and return whether the carry was ours. A refused cradle start uses the
## false answer to abort.
func release_carry() -> bool:
	var main: Variant = _host("main")
	if not is_instance_valid(main):
		return false
	var reach: Node = main.call("interactor")
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
