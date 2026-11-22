extends "res://mods/unfplap/shared/service.gd"
## Service: privacy
## Contract: docs/privacy.md
## Scope: world
## Import: privacy/api.gd only
## Scene facts in, one privacy predicate out.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PRIVACY_RULES := preload("res://mods/unfplap/shared/privacy_rules.gd")

## The offer kind: the offer rule or the stricter cuddle rule.
enum Kind { OFFER, CUDDLE }

## The other-mare radius outdoors. Indoors the house itself is the bound.
const _RADIUS_M := 30.0


## Resolved privacy state for one target.
class _State:
	var indoors := false
	var house_alone := false
	var others_near := false
	var offer_private := false
	var cuddle_private := false

	## Pick the offer or the cuddle predicate.
	func private_for(cuddle: bool) -> bool:
		return cuddle_private if cuddle else offer_private


## The privacy predicate for `target`; the target is excluded from the other-mare checks.
func is_private(target: Node, kind: Kind = Kind.OFFER) -> bool:
	return _state_for(target).private_for(kind == Kind.CUDDLE)


## The live privacy facts for `target`. The target itself is excluded from the other-mare checks.
func _state_for(target: Node) -> _State:
	var out := _State.new()
	var node: Node3D = WORLD.player
	if not is_instance_valid(node):
		return out
	var house := WORLD.house_at(node.global_position)
	out.indoors = house != null
	out.house_alone = house != null
	for actor: Node3D in WORLD.mares():
		if not is_instance_valid(actor) or actor == target:
			continue
		var distance := actor.global_position.distance_to(node.global_position)
		if house != null and WORLD.house_at(actor.global_position) == house:
			out.house_alone = false
		if distance <= _RADIUS_M:
			out.others_near = true
	out.offer_private = PRIVACY_RULES.offer_private(out.house_alone, out.others_near)
	out.cuddle_private = PRIVACY_RULES.cuddle_private(out.indoors, out.house_alone,
		out.others_near)
	return out