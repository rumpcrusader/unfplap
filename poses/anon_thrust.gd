extends Node3D
## Forwards the desktop Anon body's pose driver and adds the act's hip thrust after the body has
## placed its IK targets. The original driver still owns all action poses and rest-hand targets.

const WORLD := preload("res://mods/unfplap/world/api.gd")

var original: Node
var runtime: Node


func apply_torso_pose(hip: Node3D, facing: Basis) -> void:
	WORLD.anon().apply_torso_pose(original, hip, facing)
	if is_instance_valid(runtime):
		var session: Variant = runtime.get("act")
		if session != null:
			session.apply_anon_thrust(hip, facing)
			session.apply_anon_lean(hip, facing)
			# integration: the optional anatomy alignment runs last on the hip target.
			session.apply_anon_align(hip, facing)


func set_rest_hand_targets(left: Node3D, right: Node3D) -> void:
	WORLD.anon().set_rest_hand_targets(original, left, right)


func clear_rest_hand_targets(left: Node3D, right: Node3D) -> void:
	WORLD.anon().clear_rest_hand_targets(original, left, right)


func set_hold_target(side: String, world: Transform3D, kind: String = "hold") -> void:
	WORLD.anon().set_hold_target(original, side, world, kind)


func clear_hold_target(side: String) -> void:
	WORLD.anon().clear_hold_target(original, side)


func hand_frame(side: String = "right") -> Transform3D:
	var frame := WORLD.anon().hand_frame(original, side)
	if not frame.origin.is_finite():
		return Transform3D.IDENTITY
	return frame
