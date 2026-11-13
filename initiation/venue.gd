extends Node
## The request system's venue adapter: the only file that touches navigators, posture, the bed
## search and the privacy scan. It answers with plain values and appends reject reasons for the
## debug log. See `docs/initiation.md`.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const BED_REST := preload("res://world/relationships/shared_bed.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")

var main: Node


func bind(main_node: Node) -> void:
	main = main_node


func player() -> Node3D:
	if not is_instance_valid(main):
		return null
	var node: Variant = main.get("player")
	return node as Node3D if is_instance_valid(node) else null


func mares() -> Array:
	if not is_instance_valid(main):
		return []
	var game: Variant = main.get("game")
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
	if is_instance_valid(main):
		var view: Variant = main.call("camera")
		if is_instance_valid(view) and view is Camera3D:
			forward = -(view as Camera3D).global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and is_instance_valid(node):
		forward = -node.global_basis.z
	return forward.normalized()


func house_at(at: Vector3) -> Node3D:
	if not is_inside_tree():
		return null
	return HOUSE.at(get_tree(), at)


## The offer privacy rule. The facade resolves `public_offer` from eligibility and this gathers
## the house and distance facts.
func private_at_player(except: Node, public_offer: bool) -> bool:
	var node := player()
	if not is_instance_valid(node):
		return false
	var house := house_at(node.global_position)
	return POLICY.offer_private(is_instance_valid(except) and public_offer,
		house != null and not other_in_house(house, except),
		other_within(node.global_position, except, POLICY.PRIVACY_RADIUS_M))


## The cuddle rule: an indoor cuddle needs the house alone, an outdoor one needs nobody near.
func cuddle_privacy(pony: Node, public_offer: bool) -> bool:
	var node := player()
	if not is_instance_valid(node):
		return false
	if is_instance_valid(pony) and public_offer:
		return true
	var house := house_at(node.global_position)
	var indoor := house != null
	return POLICY.cuddle_private(indoor, indoor and not other_in_house(house, pony),
		other_within(node.global_position, pony, POLICY.PRIVACY_RADIUS_M))


func other_in_house(house: Node3D, except: Node) -> bool:
	if not is_instance_valid(house):
		return false
	for node: Variant in mares():
		if not is_instance_valid(node) or node == except:
			continue
		if house_at((node as Node3D).global_position) == house:
			return true
	return false


func other_within(at: Vector3, except: Node, radius: float) -> bool:
	for node: Variant in mares():
		if not is_instance_valid(node) or node == except:
			continue
		if (node as Node3D).global_position.distance_to(at) <= radius:
			return true
	return false


## Diagnostic for an offer's privacy decision. The target is labelled and excluded from the
## other-pony checks, so the logged result matches the offer's actual privacy rule.
func privacy_report(target: Node, public_offer: bool, private: bool) -> String:
	var node := player()
	if not is_instance_valid(node):
		return "player=none"
	var house := house_at(node.global_position)
	var in_house: Array[String] = []
	var nearby: Array[String] = []
	for item: Variant in mares():
		if not is_instance_valid(item) or not item is Node3D:
			continue
		var actor := item as Node3D
		var distance := actor.global_position.distance_to(node.global_position)
		var id := pony_id(actor)
		var tag := id if not id.is_empty() else str(actor.name)
		if actor == target:
			tag += "(target)"
		if house != null and house_at(actor.global_position) == house:
			in_house.append("%s(%.1fm)" % [tag, distance])
		if distance <= POLICY.PRIVACY_RADIUS_M:
			nearby.append("%s(%.1fm)" % [tag, distance])
	var house_text := "none"
	if house != null:
		house_text = "%s@%s" % [str(house.name), str(house.global_position)]
	var target_id := str(pony_id(target)) if is_instance_valid(target) else "?"
	return "player=%s target=%s house=%s in_house=[%s] within_%dm=[%s] public_offer=%s private=%s" % [
		str(node.global_position), target_id, house_text, ",".join(in_house),
		int(POLICY.PRIVACY_RADIUS_M), ",".join(nearby), str(public_offer), str(private)]


## A standing offer needs a free navigator in Anon's region and within reach.
func can_approach(pony: Node3D, reasons: Array = []) -> bool:
	var node := player()
	if not is_instance_valid(node):
		reasons.append("standing:no_player")
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		reasons.append("standing:no_navigator")
		return false
	if str(nav.get("reserved_by")) != "":
		reasons.append("standing:reserved")
		return false
	var owner := str(nav.get("command_owner"))
	if not (owner.is_empty() or owner.begins_with("life:")):
		reasons.append("standing:owner")
		return false
	if bool(nav.get("_has_target")):
		reasons.append("standing:busy")
		return false
	if region_of(node.global_position) != region_of(pony.global_position):
		reasons.append("standing:region")
		return false
	if node.global_position.distance_to(pony.global_position) > POLICY.APPROACH_RADIUS_M:
		reasons.append("standing:too_far")
		return false
	return true


func stand(pony: Node) -> void:
	if is_instance_valid(pony) and pony.has_method("request_posture"):
		pony.call("request_posture", "stand")


## Ask her to stand only when she is not already heading there.
func ensure_stand(pony: Node) -> void:
	if not is_instance_valid(pony) or not pony.has_method("request_posture"):
		return
	var status: Variant = pony.call("posture_status")
	if status is Dictionary and str((status as Dictionary).get("requested", "")) == "stand":
		return
	pony.call("request_posture", "stand")


func nav_for(pony: Node3D) -> Node:
	if not is_instance_valid(pony):
		return null
	return pony.get_node_or_null("Navigator")


## Claim the navigator for a request episode and return its previous state:
## `{nav, owner, wander, limit, pace}`, or `{}` when she has no navigator. `stop` halts her before
## the ownership token is set.
func claim_nav(pony: Node3D, token: String, stop := false) -> Dictionary:
	var nav := nav_for(pony)
	if nav == null:
		return {}
	var before := {
		"nav": nav,
		"owner": str(nav.get("command_owner")),
		"wander": bool(nav.get("wander_enabled")),
		"limit": nav.get("command_speed_limit"),
		"pace": nav.get("command_pace_target"),
	}
	if stop:
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
	if is_instance_valid(main) and bool(main.call("bed_occupied", bed, pony)):
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


## Seat her through the native bed rest. False when it refuses.
func accept_bed(rest: Node, pony: Node3D) -> bool:
	if not is_instance_valid(rest) or not is_instance_valid(pony):
		return false
	if not rest.has_method("accept"):
		return false
	return bool(rest.call("accept", pony))


## True while Anon is reclined on this bed.
func player_in_bed(bed: Variant) -> bool:
	var node := player()
	if not is_instance_valid(node) or not is_instance_valid(bed):
		return false
	if not bool(node.get_meta("couch_sleeping", false)):
		return false
	var seat: Variant = node.get("seat")
	if not is_instance_valid(seat):
		return false
	if not seat.has_meta("couch"):
		return false
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return false
	var bed_node: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
	return bed_node == bed
