extends RefCounted
## Debug-only pony preparation shared by the wheel's Bed cuddle and Sex ready actions. `upright`
## and `idle` clear a saved test actor's leftover tilt and navigator lease before a stock path
## runs; `idle` also requests the standing pose. `clear_busy` ends a live stock cuddle and drops
## the act metas. Nothing here is game state of its own except the metas it clears and the bond
## record the sex-ready path writes; see `docs/debug_actions.md`.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const BOND_RECORD := preload("res://mods/unfplap/shared/bond_record.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")

## The bond stages the sex-ready write never lowers: an engaged or married mare keeps her stage.
const KEPT_STAGES := ["dating", "engaged", "married"]
## The lab's qualification floors. A stored value above a floor is kept.
const FAMILIARITY_FLOOR := 80.0
const TRUST_FLOOR := 40.0
const TOGETHER_FLOOR_S := 3600.0


## The values the scene gate's status line prints: the act's own session values, plus the pony,
## the world, the relationship and the player body.
static func context(pony: Node, id: String, act: Dictionary,
		gate: ACT_GATE = null) -> Dictionary:
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	var pony_id := id if not id.is_empty() else PONY_ID.from("", identity)
	var display := "?"
	if identity != null:
		display = str(identity.get("display_name")) \
			if identity.get("display_name") != null else pony_id
	var relations: Variant = _relations(pony, gate)
	var love_name := "?"
	if is_instance_valid(pony):
		love_name = WORLD.relationship().love_name(pony, pony_id)
	var mood := "?"
	if is_instance_valid(WORLD.world_root()):
		var committed := WORLD.director().impression_mood(pony_id, "?")
		if not committed.is_empty():
			mood = committed
	var posture := WORLD.pony(pony).posture_requested()
	var lease := WORLD.navigator(pony)
	var owner := lease.owner()
	var target := lease.has_target()
	var reserved := lease.reserved()
	var body: Variant = WORLD.player_rig() if is_instance_valid(WORLD.world_root()) else null
	var out := act.duplicate()
	out.merge({
		"id": pony_id, "display": display, "stage": relations.stage,
		"love_name": love_name, "love_level": relations.love_level,
		"welcomes": relations.willing,
		"mood": mood,
		"sleeping": bool(pony.get("sleeping")) if is_instance_valid(pony) else false,
		"held": WORLD.pony(pony).is_held(),
		"grounded": WORLD.pony(pony).grounded(),
		"seated": pony.has_meta("seated") if is_instance_valid(pony) else false,
		"motion": bool(pony.get("motion_paused")) if is_instance_valid(pony) else false,
		"speed": float(pony.get("actual_speed")) if is_instance_valid(pony) else 0.0,
		"posture": posture,
		"interrupt": WORLD.pony(pony).interruption_reason(),
		"owner": owner, "target": target, "reserved": reserved,
		"body_controls_locked": str(body.get("controls_locked")) if body != null else "?",
		"body_flying": str(body.get("flying")) if body != null else "?",
		"body_seat": str(body.get("seat")) if body != null else "?",
		"mouse": str(Input.mouse_mode), "paused": _paused(pony),
	}, true)
	return out


## A saved test-world actor can carry a non-yaw transform from an old throw or cuddle. Reset the
## tilt while keeping the facing yaw, or support recovery fights the tilted collider every tick.
static func upright(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	var transform := pony.global_transform
	var euler := transform.basis.get_euler()
	if absf(euler.x) < 0.01 and absf(euler.z) < 0.01:
		return
	var scale := transform.basis.get_scale()
	transform.basis = Basis(Vector3.UP, euler.y) * Basis.from_scale(scale)
	pony.global_transform = transform
	if pony.get("velocity") != null:
		WORLD.set_velocity(pony, Vector3.ZERO)
	pony.reset_physics_interpolation()


static func idle(pony: Node3D) -> String:
	var notes := PackedStringArray()
	var lease := WORLD.navigator(pony)
	lease.stay()
	if not lease.owner().is_empty():
		notes.append("owner " + lease.owner())
		lease.set_owner("")
	lease.set_wander(false)
	if not lease.reserved().is_empty():
		notes.append("reserved " + lease.reserved())
		lease.set_reserved("")
	if pony.has_meta("active_follow"):
		pony.remove_meta("active_follow")
	if pony.get("motion_paused") == true:
		WORLD.pony(pony).set_motion_paused(false)
	if WORLD.pony(pony).posture_requested() != "stand" and pony.has_method("request_posture"):
		WORLD.pony(pony).request_posture("stand")
		notes.append("stand requested")
	upright(pony)
	return "none" if notes.is_empty() else ", ".join(notes)


static func clear_busy(pony: Node3D) -> String:
	var notes := PackedStringArray()
	var session: Node = pony.get_node_or_null("CuddleSession")
	var blend := 0.0
	if session != null and session.get("blend") != null:
		blend = float(session.get("blend"))
	if session != null and (bool(session.get("enabled")) or blend > 0.0):
		WORLD.affection().end_cuddle(session)
		notes.append("cuddle ended")
	for meta: String in ["couch_cuddle", "cuddle_active", "sex_aftercare"]:
		if pony.has_meta(meta):
			pony.remove_meta(meta)
			notes.append("cleared " + meta)
	var runtime: Node = pony.get_node_or_null("UnfplapRuntime")
	var act_session: Variant = runtime.get("act") if runtime != null else null
	# The suites build a fake runtime with its own `state` field; the live runtime owns it in the
	# session.
	var state: Variant = act_session.state if act_session != null \
		else (runtime.get("state") if runtime != null else null)
	if state != null and int(state) == 0 and pony.has_meta("sex_active"):
		pony.remove_meta("sex_active")
		notes.append("cleared sex_active")
	return "none" if notes.is_empty() else ", ".join(notes)


## Clear her busy state and write the bond record that opens the act gate, refusing before any
## change when the record cannot save. The romance tier is never touched.
static func sex_ready(host: Node, pony: Node3D) -> String:
	if not is_instance_valid(host) or not is_instance_valid(pony):
		return "No adult mare under the crosshair."
	var refusal := _record_refusal(pony)
	if not refusal.is_empty():
		var refused_rows: Array[String] = ["record=refused: " + refusal]
		return _report(host, pony, refused_rows)
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	var rows: Array[String] = []
	rows.append("idle=" + idle(pony))
	rows.append("cleared=" + clear_busy(pony))
	rows.append_array(_write_record(host, pony, id))
	rows.append("mood=" + _neutral_mood(host, pony, id))
	rows.append("romance=untouched")
	return _report(host, pony, rows)


## The reason the game's bond record cannot be written, or "" when it can.
static func _record_refusal(pony: Node3D) -> String:
	if not is_instance_valid(pony):
		return "no pony"
	var bonds := _bonds(pony)
	if bonds == null:
		return "no bonds"
	if not bonds.has_method("record_for"):
		return "no record_for"
	if not bonds.has_method("_save"):
		return "no _save"
	return ""


## The pony's relationship runtime's bonds store, or null when she has none.
static func _bonds(pony: Node3D) -> Object:
	return WORLD.relationship().bonds_of(pony)


## Raise the stage to dating unless she is already dating, engaged or married.
static func _raise_stage(record: BOND_RECORD) -> String:
	var before := record.stage
	if before in KEPT_STAGES:
		return "stage %s (kept)" % before
	record.stage = "dating"
	return "stage %s -> dating" % before


## Write the game's own bond record. The row is the save field the relationship runtime reads;
## this is a debug cheat, documented in docs/debug_actions.md.
static func _write_record(host: Node, pony: Node3D, id: String) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(host) or not is_instance_valid(pony):
		out.append("refused: no pony")
		return out
	var bonds := _bonds(pony)
	if bonds == null:
		out.append("refused: no bonds")
		return out
	if not bonds.has_method("record_for"):
		out.append("refused: no record_for")
		return out
	if not bonds.has_method("_save"):
		out.append("refused: no _save")
		return out
	var record := WORLD.relationship().record(bonds, id)
	out.append("record=" + _raise_stage(record))
	record.familiarity = maxf(record.familiarity, FAMILIARITY_FLOOR)
	record.trust = maxf(record.trust, TRUST_FLOOR)
	record.together_s = maxf(record.together_s, TOGETHER_FLOOR_S)
	record.plan = {}
	record.offer = {}
	record.cooldowns.erase("boundary")
	record.cooldowns.erase("dating")
	WORLD.relationship().save_record(bonds, id, record)
	if bonds.has_method("mark_met"):
		WORLD.relationship().mark_met(bonds, id)
	return out


## The game's impressions write one neutral mood and report the mood before and after.
static func _neutral_mood(host: Node, pony: Node3D, id: String) -> String:
	if not is_instance_valid(pony):
		return "no pony"
	if not is_instance_valid(host):
		return "no game"
	if not is_instance_valid(WORLD.world_root()):
		return "no game"
	if WORLD.director().world_context() == null:
		return "no world context"
	var before := WORLD.director().impression_mood(id)
	if before.is_empty():
		before = "neutral"
	if not WORLD.director().set_impression_mood(id, "neutral",
			"unfplap-debug-mood:%s:%d" % [id, Time.get_ticks_usec()]):
		return "no impressions"
	var after := WORLD.director().impression_mood(id)
	if after.is_empty():
		after = "neutral"
	return "%s -> %s" % [before, after]


## The act gate's relationship values for the debug line, or the empty defaults outside a live
## service.
static func _relations(pony: Node, service: ACT_GATE = null) -> Variant:
	if not is_instance_valid(pony) or not is_instance_valid(service):
		return ACT_GATE.Relations.new()
	var verdict: Variant = service.get_verdict(pony, ACT_GATE.Mode.START)
	return verdict.relations if verdict != null else ACT_GATE.Relations.new()


## The tree's pause state, read from the pony's tree so a runtime outside one cannot error.
static func _paused(pony: Node) -> bool:
	return pony.get_tree().paused if is_instance_valid(pony) and pony.is_inside_tree() else false


## Print the detail block and return the one-line wheel toast.
static func _report(_host: Node, pony: Node3D, rows: Array[String]) -> String:
	var refused := not rows.is_empty() and rows[0].begins_with("record=refused:")
	var title := "SEX READY %s" % str(pony.name)
	LOG.block(title, rows)
	return "Sex ready refused for %s." % str(pony.name) if refused \
		else "Sex ready for %s." % str(pony.name)
