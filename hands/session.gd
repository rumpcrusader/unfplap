extends RefCounted
## Interface between `hands/service.gd` and the hand actions. `hands/service.gd` extends this and
## overrides every method it uses; `hands/smack.gd` is typed against it so a missing method or a
## renamed accessor fails at compile time instead of at runtime.

const CAESS := preload("res://mods/unfplap/shared/hands_caress.gd")


func hand_driver() -> Node:
	return null

func smack_body_scale() -> float:
	return 1.0

func smack_flank() -> Node:
	return null

func smack_presentation() -> CAESS.SmackPresentation:
	return CAESS.SmackPresentation.new()

func smack_pony() -> Node3D:
	return null

func hand_on_touch(_kind: String) -> void:
	pass

func hand_on_smack_impact(_strength: float) -> void:
	pass
