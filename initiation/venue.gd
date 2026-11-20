extends Node
## The scene adapter: it alone reads navigators, posture, beds and the world house.
## It returns plain values; the facade owns the reasons and the log.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const BED_REST := preload("res://world/relationships/shared_bed.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")

## The per-pony gate handle: the scene verdicts and the offer readiness reads.
func _gate(runtime: Node) -> Variant:
	return runtime.get("gate")

var _privacy: RefCounted


func bind(privacy_node: RefCounted) -> void:
	_privacy = privacy_node


func player() -> Node3D:
	if not is_instance_valid(WORLD.game):
		return null
	var node: Variant = WORLD.player
	return node as Node3D if is_instance_valid(node) else null


func mares() -> Array:
	if not is_instance_valid(WORLD.game):
		return []
	var game: Variant = WORLD.game
	if not is_instance_valid(game):
		return []
	var list: Variant = game.get("mares")
	return list if list is Array else []


func pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	return PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))


func region_of(at: Vector3) -> String:
	return str(WorldLayout.nearest(at).get("id", ""))


## The flat direction Anon faces: the view first, his body as the fallback.
func camera_forward() -> Vector3:
	var node := player()
	var forward := Vector3.FORWARD
	if is_instance_valid(WORLD.game):
		var view: Variant = WORLD.camera()
		if is_instance_valid(view) and view is Camera3D:
			forward = -(view as Camera3D).global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and is_instance_valid(node):
		forward = -node.global_basis.z
	return forward.normalized()


func house_at(at: Vector3) -> Node3D:
	if not is_instance_valid(_privacy):
		return null
	return _privacy.house_at(at)


## A standing offer needs a navigator free near Anon, in his region.
func can_approach(pony: Node3D) -> bool:
	var node := player()
	if not is_instance_valid(node):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	if str(nav.get("reserved_by")) != "":
		return false
	var owner := str(nav.get("command_owner"))
	if not (owner.is_empty() or owner.begins_with("life:")):
		return false
	if bool(nav.get("_has_target")):
		return false
	if region_of(node.global_position) != region_of(pony.global_position):
		return false
	if node.global_position.distance_to(pony.global_position) > POLICY.STANDING_RANGE_M:
		return false
	return true


## Ask her to stand only when she is not already heading there.
func ensure_stand(pony: Node) -> void:
	if not is_instance_valid(pony) or not pony.has_method("request_posture"):
		return
	var status: Variant = pony.call("posture_status")
	if status is Dictionary and str((status as Dictionary).get("requested", "")) == "stand":
		return
	pony.call("request_posture", "stand")


## Claim the navigator for a request episode and return its previous state:
## `{nav, owner, wander, limit, pace}`, or `{}` when she has no navigator.
func claim_nav(pony: Node3D, token: String) -> Dictionary:
	if not is_instance_valid(pony):
		return {}
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		return {}
	var before := {
		"nav": nav,
		"owner": str(nav.get("command_owner")),
		"wander": bool(nav.get("wander_enabled")),
		"limit": nav.get("command_speed_limit"),
		"pace": nav.get("command_pace_target"),
	}
	nav.call("stay")
	nav.set("command_owner", token)
	nav.set("wander_enabled", false)
	nav.set("command_speed_limit", INF)
	nav.set("command_pace_target", -1.0)
	return before


func nav_owned(nav: Node, token: String) -> bool:
	return is_instance_valid(nav) and str(nav.get("command_owner")) == token


func nav_has_target(nav: Node) -> bool:
	return is_instance_valid(nav) and bool(nav.get("_has_target"))


func stay(nav: Node) -> void:
	if is_instance_valid(nav):
		nav.call("stay")


## Hand the navigator back. The owner is restored only when the request still owns it; the
## wander, speed and pace values are always restored.
func release_nav(nav: Node, token: String, prev_owner: String, prev_wander: bool,
		prev_limit: Variant, prev_pace: Variant) -> void:
	if not is_instance_valid(nav):
		return
	if str(nav.get("command_owner")) == token:
		nav.set("command_owner", prev_owner)
	nav.set("wander_enabled", prev_wander)
	if prev_limit != null:
		nav.set("command_speed_limit", prev_limit)
	if prev_pace != null:
		nav.set("command_pace_target", prev_pace)


## The nearest free bed within reach, as `{bed, rest, front, distance}` or `{}`.
func find_bed_for(pony: Node3D) -> Dictionary:
	var node := player()
	if not is_instance_valid(node) or not is_instance_valid(pony):
		return {}
	var own := player_bed_node(node)
	if own != null:
		var own_row := bed_row(own, pony, node)
		if not own_row.is_empty():
			return own_row
	var best: Dictionary = {}
	var best_distance := POLICY.BED_SEARCH_M
	for bed: Node3D in beds_near(node):
		var row := bed_row(bed, pony, node)
		if row.is_empty():
			continue
		var distance := float(row.get("distance", POLICY.BED_SEARCH_M))
		if distance < best_distance:
			best_distance = distance
			best = row
	return best


func player_bed_node(node: Node3D) -> Node3D:
	var seat: Variant = node.get("seat")
	if not is_instance_valid(seat) or not seat.has_meta("couch"):
		return null
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return null
	var bed: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
	return bed as Node3D if is_instance_valid(bed) else null


## Every loaded bed near Anon: the `couches` group beds and the house's mattress tops.
func beds_near(node: Node3D) -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	if is_inside_tree():
		for item: Variant in get_tree().get_nodes_in_group("couches"):
			if not is_instance_valid(item) or not (item as Node).has_method("rest_word"):
				continue
			if str((item as Node).call("rest_word")) != "bed":
				continue
			var bed: Variant = item.get("_bed") if item.get("_bed") != null else item.get("bed_node")
			if is_instance_valid(bed) and not seen.has((bed as Node).get_instance_id()):
				seen[(bed as Node).get_instance_id()] = true
				found.append(bed)
	var house := house_at(node.global_position)
	if house != null:
		for child: Node in house.find_children("*", "Node3D", true, false):
			if not child.has_meta("mattress_top") and not child.has_meta("soft_support"):
				continue
			if seen.has(child.get_instance_id()):
				continue
			seen[child.get_instance_id()] = true
			found.append(child)
	return found


## One bed row: readable, in range, same floor and region, with a free seat and a front spot.
func bed_row(bed: Node3D, pony: Node3D, node: Node3D) -> Dictionary:
	if not is_instance_valid(bed) or not bed.is_inside_tree():
		return {}
	var at := bed.global_position
	if at.distance_to(node.global_position) > POLICY.BED_SEARCH_M:
		return {}
	if absf(at.y - node.global_position.y) > 1.5:
		return {}
	if region_of(at) != region_of(node.global_position):
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
	if bool(WORLD.bed_occupied(bed, pony)):
		return {}
	var front: Variant = rest_front(rest, pony)
	if not front is Vector3 or not (front as Vector3).is_finite():
		return {}
	return {
		"bed": bed, "rest": rest, "front": front,
		"distance": at.distance_to(node.global_position),
	}


## The bed rest's front stand point, or null when the rest cannot report one.
func rest_front(rest: Node, pony: Node3D) -> Variant:
	if not is_instance_valid(rest) or not rest.has_method("_front_for"):
		return null
	var value: Variant = rest.call("_front_for", pony)
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	return null


## The plain placement facts for one runtime: a cuddle bed under her, a free bed near Anon with
## its front spot, and a free standing approach. One pass answers every option.
func placement_for(runtime: Node) -> POSE_OPTIONS.Placement:
	var out := POSE_OPTIONS.Placement.new()
	var pony: Variant = runtime.get("pony") if is_instance_valid(runtime) else null
	if not is_instance_valid(pony):
		return out
	var node := player()
	var gate: Variant = _gate(runtime)
	var cuddle := bool(gate.cuddle_active()) if gate != null else false
	if cuddle:
		var under: Variant = gate.find_bed_under() if gate != null else null
		if is_instance_valid(under):
			out.cuddle = true
			out.cuddle_bed = under
	var found := find_bed_for(pony)
	if not found.is_empty():
		out.bed = found.get("bed")
		out.bed_front = found.get("front")
	if is_instance_valid(node) and can_approach(pony):
		out.standing_free = true
	return out


## Restore the request claim's speed and pace overrides before the negotiation takes the lease.
## The navigator owner and the wander flag stay with the request episode.
func restore_limits(nav: Node, limit: Variant, pace: Variant) -> void:
	if not is_instance_valid(nav):
		return
	if limit != null:
		nav.set("command_speed_limit", limit)
	if pace != null:
		nav.set("command_pace_target", pace)
