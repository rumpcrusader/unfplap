extends RefCounted
## Base for a pose-specific caress path. A path answers where the caress should be for a hand;
## `hands/placement.gd` owns the contact query, smoothing and palm placement.
##
## `candidates(hand_side, context)` returns an ordered list of contacts, preferred first. Each
## contact has:
##   point, normal, oval_x, oval_y   centre and tangent axes before the oval offset
##   finger, mode, roll              palm orientation (`palm` or `fingertip`)
##   region                          `torso` or `head`
##   precise                         true for the exact posed patch, false for the hull query
##   hull_lift, ignore, regions      legacy hull query only
##   u                               optional path parameter for debug logging


var pony: Variant
var runtime: Node


func setup(pony_node: Variant, runtime_node: Node = null) -> void:
	pony = pony_node
	runtime = runtime_node


func candidates(_hand_side: String, _context: Dictionary) -> Array:
	return []


func debug_world(_hand_side: String) -> Array:
	return []


func reset() -> void:
	pass
