extends RefCounted
## The node operations the act's own modules use. One per pony, built and bound once by the
## runtime node; a module never reaches back into that node. Node ops, the scene handles and the
## two sinks live here and nowhere else.
##
## `Ledger` is the one exception in R2: the start and exit ledgers still call a few steps the
## runtime node owns (the settings snapshot, the face transitions, the camera open, the audio
## start, the tail tuck and the rest context). They are named callbacks, never a dictionary, and
## a missing one is a no-op. R3/R4 move them to their owners.
##
## See `docs/runtime.md`.

var node: Node = null
## The presented body, refreshed by the runtime's `pony` setter.
var pony: Node = null
## Named sinks the runtime binds once; a missing sink is a no-op.
var log_sink: Callable = Callable()
var perf_sink: Callable = Callable()
## The runtime-bound ledger steps.
var ledger: Ledger = Ledger.new()


## The runtime-bound steps the start and exit ledgers call until their owners take them.
class Ledger extends RefCounted:
	var snapshot_settings := Callable()
	var bind_face := Callable()
	var clear_face := Callable()
	var set_face := Callable()
	var end_act_face := Callable()
	var act_face_beat := Callable()
	var begin_camera_mode := Callable()
	var restore_look := Callable()
	var restore_camera := Callable()
	var start_audio := Callable()
	var apply_voice_policy := Callable()
	var stop_audio := Callable()
	var restore_voice_volume := Callable()
	var reset_excitement_hold := Callable()
	var sync_hud_facts := Callable()
	var start_tail_tuck := Callable()
	var end_tail_tuck := Callable()
	var end_act_lines := Callable()
	var rest_context := Callable()
	var reset_thrust := Callable()
	var begin_standing_placement := Callable()


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
