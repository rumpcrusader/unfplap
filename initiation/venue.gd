extends Node
## The scene adapter: it alone reads navigators, posture and beds.
## It returns plain values; the facade owns the reasons and the log.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")


func pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	return PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))


func region_of(at: Vector3) -> String:
	return str(WorldLayout.nearest(at).get("id", ""))


## The flat direction Anon faces: the view first, his body as the fallback.
func camera_forward() -> Vector3:
	var node: Node3D = WORLD.player
	var forward := Vector3.FORWARD
	if is_instance_valid(WORLD.game):
		var view: Variant = WORLD.camera()
		if is_instance_valid(view) and view is Camera3D:
			forward = -(view as Camera3D).global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and is_instance_valid(node):
		forward = -node.global_basis.z
	return forward.normalized()


## A standing offer needs a navigator free near Anon, in his region.
func can_approach(pony: Node3D) -> bool:
	var node: Node3D = WORLD.player
	if not is_instance_valid(node):
		return false
	if not is_instance_valid(GAME.navigator_of(pony)):
		return false
	var nav := WORLD.navigator(pony)
	if not nav.reserved().is_empty():
		return false
	var owner := nav.owner()
	if not (owner.is_empty() or owner.begins_with("life:")):
		return false
	if nav.has_target():
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
	if WORLD.pony(pony).posture_requested() == "stand":
		return
	WORLD.pony(pony).request_posture("stand")


## Claim the navigator for a request episode and return its previous state:
## `{nav, owner, wander, limit, pace}`, or `{}` when she has no navigator.
func claim_nav(pony: Node3D, token: String) -> Dictionary:
	if not is_instance_valid(pony):
		return {}
	var found := GAME.navigator_of(pony)
	if found == null:
		return {}
	var nav := WORLD.navigator(pony)
	var before := {
		"nav": found,
		"owner": nav.owner(),
		"wander": nav.wander(),
		"limit": nav.speed_limit(),
		"pace": nav.pace_target(),
	}
	nav.stay()
	nav.set_owner(token)
	nav.set_wander(false)
	nav.set_speed_limit(INF)
	nav.set_pace_target(-1.0)
	return before


func nav_owned(pony: Node, token: String) -> bool:
	return is_instance_valid(GAME.navigator_of(pony)) and WORLD.navigator(pony).owner() == token


func nav_has_target(pony: Node) -> bool:
	return WORLD.navigator(pony).has_target()


func stay(pony: Node) -> void:
	WORLD.navigator(pony).stay()


## Hand the navigator back. The owner is restored only when the request still owns it; the
## wander, speed and pace values are always restored.
func release_nav(pony: Node, token: String, prev_owner: String, prev_wander: bool,
		prev_limit: float, prev_pace: float) -> void:
	if not is_instance_valid(GAME.navigator_of(pony)):
		return
	var nav := WORLD.navigator(pony)
	if nav.owner() == token:
		nav.set_owner(prev_owner)
	nav.set_wander(prev_wander)
	if not is_nan(prev_limit):
		nav.set_speed_limit(prev_limit)
	if not is_nan(prev_pace):
		nav.set_pace_target(prev_pace)


## The nearest free bed within reach, as `{bed, rest, front, distance}` or `{}`.
func find_bed_for(pony: Node3D) -> Dictionary:
	var node: Node3D = WORLD.player
	if not is_instance_valid(node) or not is_instance_valid(pony):
		return {}
	var own := player_bed_node()
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


func player_bed_node() -> Node3D:
	var seat := WORLD.anon().seat()
	if not is_instance_valid(seat) or not seat.has_meta("couch"):
		return null
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return null
	return WORLD.bed(couch).rest_bed()


## Every loaded bed near Anon: the `couches` group beds and the house's mattress tops.
func beds_near(node: Node3D) -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	if is_inside_tree():
		for item: Variant in get_tree().get_nodes_in_group("couches"):
			if not is_instance_valid(item) or not (item as Node).has_method("rest_word"):
				continue
			if WORLD.bed(item).rest_word() != "bed":
				continue
			var bed := WORLD.bed(item).rest_bed()
			if bed != null and not seen.has(bed.get_instance_id()):
				seen[bed.get_instance_id()] = true
				found.append(bed)
	var house: Node3D = WORLD.house_at(node.global_position)
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
		rest = WORLD.bed(bed).stock_rest()
	if not is_instance_valid(rest):
		return {}
	var view := WORLD.bed(rest)
	view.refresh()
	if not view.fits():
		return {}
	if view.has_guest():
		return {}
	if view.sleeper() != null:
		return {}
	if bool(WORLD.bed_occupied(bed, pony)):
		return {}
	var front := view.front(pony)
	if not front.is_finite():
		return {}
	return {
		"bed": bed, "rest": rest, "front": front,
		"distance": at.distance_to(node.global_position),
	}


## The plain placement facts for one runtime: a cuddle bed under her, a free bed near Anon with
## its front spot, and a free standing approach. One pass answers every option.
func placement_for(runtime: Node) -> POSE_OPTIONS.Placement:
	var out := POSE_OPTIONS.Placement.new()
	var pony: Variant = runtime.get("pony") if is_instance_valid(runtime) else null
	if not is_instance_valid(pony):
		return out
	var node: Node3D = WORLD.player
	var gate: Variant = PONIES.scene_of(runtime)
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
func restore_limits(pony: Node, limit: float, pace: float) -> void:
	if not is_instance_valid(GAME.navigator_of(pony)):
		return
	var nav := WORLD.navigator(pony)
	if not is_nan(limit):
		nav.set_speed_limit(limit)
	if not is_nan(pace):
		nav.set_pace_target(pace)
