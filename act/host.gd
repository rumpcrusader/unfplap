extends RefCounted
## The node operations the act's own modules use. One per pony, built and bound once by the
## runtime node; a module never reaches back into that node. Node ops, the scene handles and the
## two sinks live here and nowhere else.
##
## See `docs/runtime.md`.

var node: Node = null
## The presented body, refreshed by the runtime's `pony` setter.
var pony: Node = null
## Named sinks the runtime binds once; a missing sink is a no-op.
var log_sink: Callable = Callable()
var perf_sink: Callable = Callable()


func bind(host_node: Node) -> void:
	node = host_node


func tree() -> SceneTree:
	return node.get_tree() if is_instance_valid(node) else null


func viewport() -> Viewport:
	return node.get_viewport() if is_instance_valid(node) else null


func physics_delta() -> float:
	return node.get_physics_process_delta_time() if is_instance_valid(node) else 0.0


func add_child(child: Node) -> void:
	if is_instance_valid(node) and child != null:
		node.add_child(child)


func tween() -> Tween:
	return node.create_tween() if is_instance_valid(node) else null


func log(text: String) -> void:
	if log_sink.is_valid():
		log_sink.call(text)


func perf_note(key: String, usec: int) -> void:
	if perf_sink.is_valid():
		perf_sink.call(key, usec)
