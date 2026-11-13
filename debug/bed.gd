extends RefCounted
## Debug-only stock bed cuddle. Finds the bed Anon is on or in his current house, sits and lies
## him back, brings a far mare to the bed approach and asks the game's own `SharedBed` to accept
## her. The wheel's Bed cuddle action and Show data's BED section both come through here.

const BED_REST := preload("res://world/relationships/shared_bed.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")

## A mare farther than this from the bed, or on another floor, is moved to the bed approach first.
const TRANSPORT_RANGE_M := 8.0
const TRANSPORT_FLOOR_M := 0.5


## The player's current bed, else the bed of the house he is in, else a bed under his feet.
static func find_bed(main: Node) -> Node3D:
	if not is_instance_valid(main):
		return null
	var body: Variant = main.get("player")
	if not is_instance_valid(body) or not body is Node3D:
		return null
	var seat: Variant = body.get("seat")
	if is_instance_valid(seat):
		var from_seat := _bed_from_seat(main, seat)
		if is_instance_valid(from_seat):
			return from_seat
	var home: Node3D = HOUSE.at(main.get_tree(), (body as Node3D).global_position)
	if is_instance_valid(home):
		var bed: Variant = home.call("ensure_bed", "guest")
		if not bed is Node3D or not is_instance_valid(bed):
			bed = home.call("ensure_bed", "")
		if bed is Node3D and is_instance_valid(bed):
			return bed as Node3D
	var under: Variant = main.call("bed_under", (body as Node3D).global_position)
	return under as Node3D if under is Node3D and is_instance_valid(under) else null


## The BED section of Show data: the bed, Anon's seat, the stock rest's partner and the target's
## own cuddle flags, followed by the full cuddle-gate line.
static func rows(main: Node, target: Node) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(main):
		out.append("main unavailable")
		return out
	var bed := find_bed(main)
	if not is_instance_valid(bed):
		out.append("bed=none")
		return out
	var body: Variant = main.get("player")
	var seat: Variant = body.get("seat") if is_instance_valid(body) else null
	out.append("bed=%s at=%s" % [str(bed.name), str(bed.global_position)])
	out.append("player seat=%s lying=%s" % [_node_name(seat), str(_player_lying(main))])
	var rest := _existing_rest(bed)
	if not is_instance_valid(rest):
		out.append("stock rest=not installed")
		return out
	var partner: Variant = rest.call("partner", seat) \
		if seat is Node3D and rest.has_method("partner") else null
	out.append("partner=%s" % _node_name(partner))
	if is_instance_valid(target) and target is Node3D:
		var pony := target as Node3D
		out.append("target cuddle_active=%s couch_cuddle=%s session=%s" % [
			str(pony.get_meta("cuddle_active", false)),
			str(pony.get_meta("couch_cuddle", false)),
			str(_cuddle_session(pony))])
		out.append(state_text(main, pony, rest))
	return out


## The wheel action: prepare the bed, recline Anon, move a far mare and call the stock accept path.
## The detailed result goes to the debug log; the one-line result is the wheel toast.
static func invite(main: Node, target: Node) -> String:
	if not is_instance_valid(main) or not is_instance_valid(target) or not target is Node3D:
		return "No mare under the crosshair."
	var pony := target as Node3D
	var bed := find_bed(main)
	if not is_instance_valid(bed):
		return "No bed found in this house."
	var rest: Node3D = BED_REST.for_bed(bed)
	if not is_instance_valid(rest):
		return "The bed has no stock rest."
	rest.call("refresh")
	var notes: Array[String] = []
	notes.append("idle=" + _idle_pony(pony))
	if _needs_transport(pony, bed):
		notes.append("transport=" + _bring_to_bed(pony, rest))
		await main.get_tree().create_timer(0.7).timeout
		if not _alive(main, target, rest):
			return "Bed cuddle interrupted."
		# Recompute once she is inside: the first pass ran outside the house, where the
		# bed-front height test cannot match her floor.
		notes.append("grounded=" + _idle_pony(pony))
		notes.append("front=" + _bring_to_bed(pony, rest))
	notes.append("player=" + _ensure_player_lying(main, rest))
	if _player_lying(main):
		# Let the reclined avatar settle before inviting: the snuggle support takes its landing
		# height from the avatar's hip and head targets.
		await main.get_tree().create_timer(1.2).timeout
		if not _alive(main, target, rest):
			return "Bed cuddle interrupted."
	notes.append("state=" + state_text(main, pony, rest))
	if not _player_lying(main):
		notes.append("Anon must be lying on the bed to cuddle")
		return _report(main, pony, false, notes)
	var accepted := bool(rest.call("accept", pony))
	notes.append("invite=" + str(accepted))
	return _report(main, pony, accepted, notes)


static func _bed_from_seat(main: Node, seat: Variant) -> Node3D:
	if not seat is Node or not is_instance_valid(seat):
		return null
	var couch: Variant = (seat as Node).get_meta("couch") if (seat as Node).has_meta("couch") \
		else null
	if is_instance_valid(couch):
		var bound: Variant = couch.get("_bed")
		if not is_instance_valid(bound):
			bound = couch.get("bed_node")
		if bound is Node3D and is_instance_valid(bound):
			return bound as Node3D
	var real: Variant = main.call("real_bed", seat)
	return real as Node3D if real is Node3D and is_instance_valid(real) else null


## The rest node `SharedBed.for_bed()` installed, without installing one as a read-only query.
static func _existing_rest(bed: Node3D) -> Node3D:
	if not is_instance_valid(bed):
		return null
	if bed.has_meta("bed_rest"):
		var bound: Variant = bed.get_meta("bed_rest")
		if is_instance_valid(bound) and not (bound as Node).is_queued_for_deletion():
			return bound as Node3D
	var child: Node = bed.get_node_or_null("BedRest")
	return child as Node3D if is_instance_valid(child) else null


static func _player_lying(main: Node) -> bool:
	if not is_instance_valid(main):
		return false
	var body: Variant = main.get("player")
	return is_instance_valid(body) and bool((body as Node).get_meta("couch_sleeping", false))


## Sit Anon on the bed's player seat and lie him back. The stock sit path still enforces its 3 m
## reach, so a failed sit says to step closer instead of teleporting the rig.
static func _ensure_player_lying(main: Node, rest: Node3D) -> String:
	if _player_lying(main):
		return "already lying"
	var body: Variant = main.get("player")
	if not is_instance_valid(body):
		return "no player"
	var seats: Variant = rest.get("seats") if rest != null else null
	if not seats is Array or (seats as Array).is_empty():
		return "bed has no player seat"
	var seat: Variant = (seats as Array)[0]
	if not seat is Node3D or not is_instance_valid(seat):
		return "bed player seat invalid"
	if body.get("seat") != seat:
		if not body.has_method("sit_on"):
			return "player cannot sit"
		if not bool(body.call("sit_on", seat)):
			return "sit failed: move within 3 m of the bed"
	if not body.has_method("toggle_couch_sleep"):
		return "player cannot lie down"
	if not bool(body.call("toggle_couch_sleep")):
		return "lie-down failed"
	return "Anon sat and lay down"


## A saved test-world actor can carry a non-yaw transform from an old throw or cuddle. Reset the
## tilt while keeping the facing yaw, or support recovery fights the tilted collider every tick.
static func _upright(pony: Node3D) -> void:
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


static func _idle_pony(pony: Node3D) -> String:
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
	_upright(pony)
	return "none" if notes.is_empty() else ", ".join(notes)


static func _needs_transport(pony: Node3D, bed: Node3D) -> bool:
	var to_bed := pony.global_position - bed.global_position
	return Vector2(to_bed.x, to_bed.z).length() > TRANSPORT_RANGE_M \
		or absf(to_bed.y) > TRANSPORT_FLOOR_M


## Move her to the bed approach and clear her navigator command, matching the lab's old Mouse4
## transport. Her capsule still owns the floor ray; this is a debug teleport, not a game path.
static func _bring_to_bed(pony: Node3D, rest: Node3D) -> String:
	var front_value: Variant = rest.call("_front_for", pony)
	var front := Vector3.INF
	if front_value is Vector3:
		front = front_value
	if not front.is_finite():
		var exit_at: Variant = rest.get("_exit")
		if exit_at is Vector3:
			front = exit_at
	if not front.is_finite():
		return "no floor beside the bed"
	pony.global_position = front
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	if pony.get("motion_paused") != null:
		pony.set("motion_paused", false)
	_upright(pony)
	pony.reset_physics_interpolation()
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		var travel: Variant = nav.get("house_travel")
		if travel != null and is_instance_valid(travel):
			travel.call("clear", pony)
		nav.call("stay")
		nav.set("command_owner", "")
		nav.set("wander_enabled", false)
	return str(front)


## The full cuddle gate the old lab printed on Mouse4: the bed, the target's own blockers, the
## navigator lease and the player's recline state, one line.
static func state_text(main: Node, pony: Node3D, rest: Node3D) -> String:
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	var bed: Variant = rest.get("_bed") if rest != null else null
	var nav: Node = pony.get_node_or_null("Navigator")
	var guest: Variant = rest.get("_guest") if rest != null else null
	var sleeper: Variant = rest.get("_sleeper") if rest != null else null
	var seats: Variant = rest.get("seats") if rest != null else null
	var seat_free := false
	if seats is Array and (seats as Array).size() > 1:
		var seat: Variant = (seats as Array)[1]
		seat_free = is_instance_valid(seat) and bool(seat.call("free_for", pony))
	var dist := -1.0
	if is_instance_valid(bed):
		dist = pony.global_position.distance_to((bed as Node3D).global_position)
	var body_scale := 1.0
	if pony.get("body_scale") != null:
		body_scale = float(pony.get("body_scale"))
	var reasons := PackedStringArray()
	if not is_instance_valid(bed):
		reasons.append("no_bed")
	elif Vector2(pony.global_position.x - (bed as Node3D).global_position.x,
			pony.global_position.z - (bed as Node3D).global_position.z).length() > TRANSPORT_RANGE_M \
			or absf(pony.global_position.y - (bed as Node3D).global_position.y) > TRANSPORT_FLOOR_M:
		reasons.append("too_far")
	if pony.get("sleeping") == true:
		reasons.append("sleeping")
	if pony.get("_held") == true:
		reasons.append("held")
	if pony.get("motion_paused") == true:
		reasons.append("motion_paused")
	for meta: String in ["seating", "fishing_companion", "balloon_passenger", "cuddle_active"]:
		if pony.has_meta(meta):
			reasons.append("meta:" + meta)
	if pony.get_meta("affection_active", false):
		reasons.append("affection")
	if pony.has_method("action_interruption_reason") \
			and not str(pony.call("action_interruption_reason")).is_empty():
		reasons.append("interrupt")
	if pony.get("flight") != null and bool(pony.get("flight").active()):
		reasons.append("flight")
	if body_scale > 1.05:
		reasons.append("too_big")
	if nav == null:
		reasons.append("no_navigator")
	else:
		var owner := str(nav.get("command_owner"))
		var routine := owner.is_empty() or owner == "rest_after_command" \
			or owner.begins_with("life:") or owner.begins_with("bond:") or owner.begins_with("day:")
		if str(nav.get("reserved_by")) != "":
			reasons.append("nav_reserved")
		if bool(nav.get("_has_target")):
			reasons.append("nav_target")
		if not routine:
			reasons.append("nav_owner=" + owner)
	var willing := bool(rest.call("_willing", pony)) if rest != null else false
	if not willing:
		reasons.append("unwilling")
	if rest == null or not bool(rest.get("_mare_fits")):
		reasons.append("mare_fits")
	if is_instance_valid(sleeper):
		reasons.append("sleeper=" + str((sleeper as Node).name))
	if guest is Dictionary and not (guest as Dictionary).is_empty():
		reasons.append("guest=" + str((guest as Dictionary).get("state", "?")))
	if not seat_free:
		reasons.append("seat_busy")
	if not _player_lying(main):
		reasons.append("player_not_lying")
	return ("pony=%s bed=%s dist=%.2f eligible=%s player_lying=%s willing=%s mare_fits=%s "
		+ "seat_free=%s guest=%s sleeper=%s | nav owner=%s target=%s reserved=%s | reasons=%s") % [
		id, _node_name(bed), dist,
		str(rest.call("eligible", pony)) if rest != null else "no_rest",
		str(_player_lying(main)), str(willing),
		str(rest.get("_mare_fits")) if rest != null else "?",
		str(seat_free),
		str((guest as Dictionary).get("state", "?")) if guest is Dictionary \
			and not (guest as Dictionary).is_empty() else "none",
		_node_name(sleeper),
		str(nav.get("command_owner")) if nav != null else "?",
		str(bool(nav.get("_has_target"))) if nav != null else "?",
		str(nav.get("reserved_by")) if nav != null else "?",
		"none" if reasons.is_empty() else ", ".join(reasons)]


static func _cuddle_session(pony: Node3D) -> bool:
	var session: Node = pony.get_node_or_null("CuddleSession")
	return session != null and bool(session.get("enabled"))


static func _alive(main: Node, target: Node, rest: Node3D) -> bool:
	return is_instance_valid(main) and is_instance_valid(target) and is_instance_valid(rest) \
		and main.is_inside_tree()


static func _report(main: Node, pony: Node3D, accepted: bool, rows: Array[String]) -> String:
	var title := "BED CUDDLE %s %s" % [str(pony.name), "accepted" if accepted else "refused"]
	if main.has_method("debug_block"):
		main.call("debug_block", title, rows)
	else:
		main.call("debug", title)
	return "Bed cuddle started for %s." % str(pony.name) if accepted \
		else "Bed cuddle refused for %s." % str(pony.name)


static func _node_name(value: Variant) -> String:
	return str((value as Node).name) if value is Node and is_instance_valid(value) else "none"
