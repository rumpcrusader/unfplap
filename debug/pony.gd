extends RefCounted
## Debug-only pony preparation shared by the wheel's Bed cuddle and Sex ready actions. `upright`
## and `idle` clear a saved test actor's leftover tilt and navigator lease before a stock path
## runs; `idle` also requests the standing pose. `clear_busy` ends a live stock cuddle and drops
## the act metas. Nothing here is game state of its own except the metas it clears and the bond
## record the sex-ready path writes; see `docs/debug.md`.


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
