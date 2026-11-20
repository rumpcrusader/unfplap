extends RefCounted
## Base for a pose-specific caress path: ordered contacts, preferred first.
## The engine owns the coat snap, smoothing and palm placement; a path never reads the pose.


var pony: Variant
## The typed act view: a path reads the camera, the scene handles and the log from it.
var facts: Variant


## Report a one-time path/anchor build to the act probe. The first caress of an act pays it, so
## the row is a max-frame risk rather than a steady chunk. See `docs/perf.md`.
func report_path_build(started_usec: int) -> void:
	if facts != null:
		facts.perf("caress_path", Time.get_ticks_usec() - started_usec)


func setup(pony_node: Variant, facts_context: Variant = null) -> void:
	pony = pony_node
	facts = facts_context


func candidates(_hand_side: String, _context: Dictionary) -> Array:
	return []


func debug_world(_hand_side: String) -> Array:
	return []


func reset() -> void:
	pass
