extends Node3D
## Forwards the desktop Anon body's pose driver and adds the act's hip thrust after the body has
## placed its IK targets. The original driver still owns all action poses and rest-hand targets.

var original: Node
var runtime: Node


func apply_torso_pose(hip: Node3D, facing: Basis) -> void:
	if is_instance_valid(original) and original.has_method("apply_torso_pose"):
		original.call("apply_torso_pose", hip, facing)
	if is_instance_valid(runtime) and runtime.has_method("apply_anon_thrust"):
		runtime.call("apply_anon_thrust", hip, facing)


func set_rest_hand_targets(left: Node3D, right: Node3D) -> void:
	if is_instance_valid(original) and original.has_method("set_rest_hand_targets"):
		original.call("set_rest_hand_targets", left, right)


func clear_rest_hand_targets(left: Node3D, right: Node3D) -> void:
	if is_instance_valid(original) and original.has_method("clear_rest_hand_targets"):
		original.call("clear_rest_hand_targets", left, right)
