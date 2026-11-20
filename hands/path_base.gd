extends RefCounted
## Base for a pose-specific caress path: ordered contacts, preferred first.
## The engine owns the coat snap, smoothing and palm placement; a path never reads the pose.


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
