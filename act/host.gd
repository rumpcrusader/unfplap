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


## The presented body as a value, for a host callback that needs it rather than a field read.
func pony_value() -> Node:
	return pony if is_instance_valid(pony) else null


## The runtime node itself, for the anatomy host's VR controller.
func runtime() -> Node:
	return node


## The conversation director, when this runtime is in a tree.
func director() -> Node:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("conversation_director")


## Whether another mod's entry is active in this launch.
func mod_enabled(id: String) -> bool:
	if id.is_empty() or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	var mods: Node = node.get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", id))


## The VR scene handles the anatomy bridge wires into the VR act: the player, the avatar and the
## two XR nodes. A desktop launch returns null.
func vr_scene() -> Variant:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return null
	var player: Node = WORLD.player
	var avatar := player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return null
	var cameras: Array = player.find_children("*", "XRCamera3D", true, false)
	var origins: Array = player.find_children("*", "XROrigin3D", true, false)
	if cameras.is_empty() or origins.is_empty():
		return null
	return {
		"player": player,
		"avatar": avatar,
		"camera": cameras[0],
		"origin": origins[0],
		"hip_target": avatar.get("_hip_target"),
	}


## The pony build's near-mesh flag and simulation tier, or null when the game has neither.
func near_mesh() -> Variant:
	return pony.get("near_mesh_enabled") if is_instance_valid(pony) else null


func tier() -> Variant:
	return pony.get("sim_tier") if is_instance_valid(pony) else null


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
