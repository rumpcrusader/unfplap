extends RefCounted
## Debug-only pony preparation shared by the wheel's Bed cuddle and Sex ready actions. `upright`
## and `idle` clear a saved test actor's leftover tilt and navigator lease before a stock path
## runs; `idle` also requests the standing pose. `clear_busy` ends a live stock cuddle and drops
## the act metas. Nothing here is game state of its own except the metas it clears and the bond
## record the sex-ready path writes; see `docs/debug.md`.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The bond stages the sex-ready write never lowers: an engaged or married mare keeps her stage.
const KEPT_STAGES := ["dating", "engaged", "married"]
## The lab's qualification floors. A stored value above a floor is kept.
const FAMILIARITY_FLOOR := 80.0
const TRUST_FLOOR := 40.0
const TOGETHER_FLOOR_S := 3600.0


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
		pony.set("velocity", Vector3.ZERO)
	pony.reset_physics_interpolation()


static func idle(pony: Node3D) -> String:
	var notes := PackedStringArray()
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		nav.call("stay")
		if str(nav.get("command_owner")) != "":
			notes.append("owner " + str(nav.get("command_owner")))
			nav.set("command_owner", "")
		nav.set("wander_enabled", false)
		if str(nav.get("reserved_by")) != "":
			notes.append("reserved " + str(nav.get("reserved_by")))
			nav.set("reserved_by", "")
	if pony.has_meta("active_follow"):
		pony.remove_meta("active_follow")
	if pony.get("motion_paused") == true:
		pony.set("motion_paused", false)
	var status: Dictionary = pony.call("posture_status") if pony.has_method("posture_status") else {}
	if str(status.get("requested", "")) != "stand" and pony.has_method("request_posture"):
		pony.call("request_posture", "stand")
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
		session.call("end", true)
		notes.append("cuddle ended")
	for meta: String in ["couch_cuddle", "cuddle_active", "sex_aftercare"]:
		if pony.has_meta(meta):
			pony.remove_meta(meta)
			notes.append("cleared " + meta)
	var runtime: Node = pony.get_node_or_null("UnfplapRuntime")
	if runtime != null and int(runtime.get("state")) == 0 and pony.has_meta("sex_active"):
		pony.remove_meta("sex_active")
		notes.append("cleared sex_active")
	return "none" if notes.is_empty() else ", ".join(notes)


## Clear her busy state and write the bond record that opens the act gate: dating when she is
## below it, the lab's familiarity/trust/together floors, no pending plan/offer and no boundary or
## dating cooldown. A record path that cannot save refuses before anything changes; the romance
## ladder, tier and love are never touched.
static func sex_ready(main: Node, pony: Node3D) -> String:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return "No adult mare under the crosshair."
	var refusal := _record_refusal(pony)
	if not refusal.is_empty():
		var refused_rows: Array[String] = ["record=refused: " + refusal]
		return _report(main, pony, refused_rows)
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	var rows: Array[String] = []
	rows.append("idle=" + idle(pony))
	rows.append("cleared=" + clear_busy(pony))
	rows.append_array(_write_record(main, pony, id))
	rows.append("mood=" + _neutral_mood(main, pony, id))
	rows.append("romance=untouched")
	return _report(main, pony, rows)


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
	if not pony.has_meta("relationship_runtime"):
		return null
	var rel: Variant = pony.get_meta("relationship_runtime")
	if not is_instance_valid(rel):
		return null
	var bonds: Variant = rel.get("bonds")
	return bonds as Object if is_instance_valid(bonds) else null


## Raise the stage to dating unless she is already dating, engaged or married.
static func _raise_stage(row: Dictionary) -> String:
	var before := str(row.get("stage", "acquaintance"))
	if before in KEPT_STAGES:
		return "stage %s (kept)" % before
	row["stage"] = "dating"
	return "stage %s -> dating" % before


## Write the game's own bond record. The row is the save field the relationship runtime reads;
## this is a debug cheat, documented in docs/debug.md.
static func _write_record(main: Node, pony: Node3D, id: String) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(main) or not is_instance_valid(pony):
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
	var row: Dictionary = bonds.call("record_for", id)
	out.append("record=" + _raise_stage(row))
	row["familiarity"] = maxf(float(row.get("familiarity", 0.0)), FAMILIARITY_FLOOR)
	row["trust"] = maxf(float(row.get("trust", 0.0)), TRUST_FLOOR)
	row["together_s"] = maxf(float(row.get("together_s", 0.0)), TOGETHER_FLOOR_S)
	row["plan"] = {}
	row["offer"] = {}
	var stored: Variant = row.get("cooldowns", {})
	var cooldowns: Dictionary = stored if stored is Dictionary else {}
	cooldowns.erase("boundary")
	cooldowns.erase("dating")
	row["cooldowns"] = cooldowns
	bonds.call("_save", id, row)
	if bonds.has_method("mark_met"):
		bonds.call("mark_met", id)
	return out


## The game's impressions write one neutral mood and report the mood before and after.
static func _neutral_mood(main: Node, pony: Node3D, id: String) -> String:
	if not is_instance_valid(pony):
		return "no pony"
	if not is_instance_valid(main):
		return "no game"
	var game: Variant = WORLD.game
	if not is_instance_valid(game):
		return "no game"
	var context: Variant = game.get("world_context")
	if not is_instance_valid(context):
		return "no world context"
	var impressions: Variant = context.get("impressions")
	if not is_instance_valid(impressions) or not impressions.has_method("profile") \
			or not impressions.has_method("commit"):
		return "no impressions"
	var before := "neutral"
	var before_profile: Variant = impressions.call("profile", id)
	if before_profile is Dictionary:
		before = str((before_profile as Dictionary).get("mood", "neutral"))
	impressions.call("commit", id, {"mood": "neutral"},
		"unfplap-debug-mood:%s:%d" % [id, Time.get_ticks_usec()])
	var after := "neutral"
	var after_profile: Variant = impressions.call("profile", id)
	if after_profile is Dictionary:
		after = str((after_profile as Dictionary).get("mood", "neutral"))
	return "%s -> %s" % [before, after]


## Print the detail block (or the title alone when the main node has no block helper) and return
## the one-line wheel toast.
static func _report(_main: Node, pony: Node3D, rows: Array[String]) -> String:
	var refused := not rows.is_empty() and rows[0].begins_with("record=refused:")
	var title := "SEX READY %s" % str(pony.name)
	LOG.block(title, rows)
	return "Sex ready refused for %s." % str(pony.name) if refused \
		else "Sex ready for %s." % str(pony.name)
