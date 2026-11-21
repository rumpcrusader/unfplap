extends "res://mods/unfplap/shared/service.gd"
## Service: privacy
## Contract: docs/privacy.md
## Scope: world
## Import: privacy/service.gd only
## Scene facts in, pure privacy predicates out.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PRIVACY_RULES := preload("res://mods/unfplap/shared/privacy_rules.gd")

## The other-mare radius outdoors. Indoors the house itself is the bound.
const RADIUS_M := 30.0

## Resolved privacy state for one target.
class State:
	var player: Node3D = null
	var house: Node3D = null
	var indoors := false
	var house_alone := false
	var others_near := false
	var offer_private := false
	var cuddle_private := false
	var in_house: Array[String] = []
	var nearby: Array[String] = []

	## Pick the offer or the cuddle predicate.
	func private_for(cuddle: bool) -> bool:
		return cuddle_private if cuddle else offer_private



## The live privacy facts for `target`. The target itself is excluded from the other-mare checks.
func state_for(target: Node) -> State:
	var out := State.new()
	var node := player()
	out.player = node
	if not is_instance_valid(node):
		return out
	var house := house_at(node.global_position)
	out.house = house
	out.indoors = house != null
	out.house_alone = house != null
	out.others_near = false
	for item: Variant in _mares():
		if not is_instance_valid(item) or item == target or not item is Node3D:
			continue
		var actor := item as Node3D
		var distance := actor.global_position.distance_to(node.global_position)
		var label := label_for(actor)
		var in_house := house != null and house_at(actor.global_position) == house
		if in_house:
			out.house_alone = false
			out.in_house.append("%s(%.1fm)" % [label, distance])
		if distance <= RADIUS_M:
			out.others_near = true
			out.nearby.append("%s(%.1fm)" % [label, distance])
	out.offer_private = PRIVACY_RULES.offer_private(out.house_alone, out.others_near)
	out.cuddle_private = PRIVACY_RULES.cuddle_private(out.indoors, out.house_alone,
		out.others_near)
	return out


## The private state for an offer kind. A cuddle uses the stricter cuddle rule.
func private_for(target: Node, cuddle := false) -> bool:
	return state_for(target).private_for(cuddle)


## The bed/standing offer predicate.
func offer_private(target: Node) -> bool:
	return state_for(target).offer_private


## The cuddle predicate.
func cuddle_private(target: Node) -> bool:
	return state_for(target).cuddle_private


## The debug report. The target is labelled and excluded from the other-pony checks, so the
## logged result matches the offer's actual privacy rule.
func report(target: Node) -> String:
	var state := state_for(target)
	if not is_instance_valid(state.player):
		return "player=none"
	var house_text := "none"
	if state.house != null:
		house_text = "%s@%s" % [str(state.house.name), str(state.house.global_position)]
	var target_id := label_for(target) if is_instance_valid(target) else "?"
	return "player=%s target=%s house=%s in_house=[%s] within_%dm=[%s] offer_private=%s cuddle_private=%s" % [
		str(state.player.global_position), target_id, house_text, ",".join(state.in_house),
		int(RADIUS_M), ",".join(state.nearby), str(state.offer_private),
		str(state.cuddle_private)]


## The house at a world point, or null outdoors. One scene read for the provider and the bed scan.
func house_at(at: Vector3) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return HOUSE.at(tree, at)


func player() -> Node3D:
	if not is_instance_valid(WORLD.game):
		return null
	var node: Variant = WORLD.player
	return node as Node3D if is_instance_valid(node) else null


func _mares() -> Array:
	if not is_instance_valid(WORLD.game):
		return []
	var game: Variant = WORLD.game
	if not is_instance_valid(game):
		return []
	var list: Variant = game.get("mares")
	return list if list is Array else []


func label_for(pony: Node) -> String:
	if not is_instance_valid(pony):
		return "?"
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	return id if not id.is_empty() else str(pony.name)
