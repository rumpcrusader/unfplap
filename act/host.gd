extends RefCounted
## The node operations the act modules need from the runtime node. One per pony, built and bound
## by the runtime. The host owns the scene node, the presented pony and the two sinks; a module
## that needs the node reads a typed method here instead of reaching into the runtime.
##
## See `docs/runtime.md`.

const TAIL_TUCK: GDScript = preload("res://mods/unfplap/poses/tail_tuck.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")

var node: Node
## The presented body. The runtime's pony setter keeps it in step.
var pony: Node
## Named sinks the runtime binds; a missing sink is a no-op.
var log_sink: Callable = Callable()
var perf_sink: Callable = Callable()
## The tail-tuck node the exit starts and the runtime clears. It needs the runtime node to host
## the pose-scope node, so it stays a typed host op rather than a service call.
var _tail_tuck: Node = null


func bind(node_in: Node) -> void:
	node = node_in


func tree() -> SceneTree:
	return node.get_tree() if is_instance_valid(node) else null


## The presented body's node name, for the act's diagnostic lines.
func pony_name() -> String:
	return str(pony.name) if is_instance_valid(pony) else "?"


func viewport() -> Viewport:
	return node.get_viewport() if is_instance_valid(node) else null


func physics_delta() -> float:
	return node.get_physics_process_delta_time() if is_instance_valid(node) else 0.0


func add_child(child: Node) -> void:
	if is_instance_valid(node) and is_instance_valid(child):
		node.add_child(child)


func tween() -> Tween:
	return node.create_tween() if is_instance_valid(node) else null


## Move the runtime node under the world before a freed body is dropped. The runtime owns the
## reparent and its `_swapping_parent` flag; the host only names the world.
func attach_to_world() -> void:
	if is_instance_valid(node) and is_instance_valid(WORLD.game):
		node.call("attach_to_body", WORLD.game)


func log(text: String) -> void:
	if log_sink.is_valid():
		log_sink.call(text)


func perf_note(key: String, usec: int) -> void:
	if perf_sink.is_valid():
		perf_sink.call(key, usec)


## Start the aftercare tail tuck on the host's node. The pose-scope node needs the runtime as its
## parent, so the host owns the create/free pair.
func start_tail_tuck() -> void:
	end_tail_tuck()
	if not is_instance_valid(node) or not is_instance_valid(pony):
		return
	var tuck: Node = TAIL_TUCK.new()
	tuck.name = "UnfplapTailTuck"
	tuck.set("pony", pony)
	tuck.set("runtime", node)
	add_child(tuck)
	_tail_tuck = tuck


func end_tail_tuck() -> void:
	if is_instance_valid(_tail_tuck):
		_tail_tuck.queue_free()
	_tail_tuck = null
