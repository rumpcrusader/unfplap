extends RefCounted
## Service: hands
## Contract: docs/hands.md
## Scope: per-act
## Import: hands/port.gd only
## Typed host seam between the hand coordinator and its action modules.

const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")


func pony() -> Node3D:
	return null


func driver() -> Node:
	return null


func path() -> PATH_BASE:
	return null


func engine() -> PLACEMENT:
	return null


func presentation() -> MODEL.SmackPresentation:
	return MODEL.SmackPresentation.new()


func smack_zone_radius() -> float:
	return 0.0


func body_scale() -> float:
	return 1.0


func frozen() -> bool:
	return false


func debug() -> bool:
	return false


func smack_owns(_side: MODEL.Side) -> bool:
	return false


func hand_frame(_side: MODEL.Side) -> Transform3D:
	return Transform3D(Basis(), Vector3.INF)


func hold(_side: MODEL.Side, _frame: Transform3D) -> void:
	pass


func release_hold(_side: MODEL.Side) -> void:
	pass


func flank() -> Node:
	return null


func flank_impact(_index: int, _at: Vector3, _strength: float) -> void:
	pass


func touch(_kind: String) -> void:
	pass


func impact(_strength: float) -> void:
	pass
