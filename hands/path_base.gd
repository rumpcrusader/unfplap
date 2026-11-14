extends RefCounted
## Base for a pose-specific caress path. A path answers where the caress should be for a hand;
## `hands/placement.gd` owns the snap to the posed coat, smoothing and palm placement.
##
## `candidates(hand_side, context)` returns an ordered list of contacts, preferred first. Each
## contact has:
##   point, normal, oval_x, oval_y   centre and tangent axes before the oval offset
##   finger, mode, roll              palm orientation (`palm` or `fingertip`)
##   region                          `torso` or `head`: the coat patch the engine snaps to
##   exact                           optional: the point is already on the coat, skip the snap
##   u                               optional path parameter for debug logging
##
## The contact is always on the posed coat surface. The engine never reads the pose; how a path
## chooses and orders contacts is the only pose-specific part of the caress.


var pony: Variant
## The typed act view: a path reads the camera, the scene handles and the log from it.
var facts: Variant


func setup(pony_node: Variant, facts_context: Variant = null) -> void:
	pony = pony_node
	facts = facts_context


func candidates(_hand_side: String, _context: Dictionary) -> Array:
	return []


func debug_world(_hand_side: String) -> Array:
	return []


func reset() -> void:
	pass
