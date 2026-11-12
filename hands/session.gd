extends RefCounted
## Interface between `hand_control.gd` and the hand actions. `hand_control.gd` extends this and
## overrides every method it uses; `hands/smack.gd` is typed against it so a missing method or a
## renamed accessor fails at compile time instead of at runtime.

func hand_driver() -> Node:
	return null

func caress_active(_side: String) -> bool:
	return false

func caress_latched(_side: String) -> bool:
	return false

func caress_set_hand(_side: String, _apply := true) -> Transform3D:
	return Transform3D.IDENTITY

func caress_begin_return(_caress_side: String, _from: Transform3D) -> void:
	pass

func caress_finish_keep(_caress_side: String) -> void:
	pass

func caress_reset_hand(_side: String) -> void:
	pass

func caress_return_seconds() -> float:
	return 0.12

func smack_body_scale() -> float:
	return 1.0

func smack_flank() -> Node:
	return null

func smack_presentation() -> Dictionary:
	return {}

func smack_pony() -> Variant:
	return null

func hand_on_touch(_kind: String) -> void:
	pass

func hand_on_smack_impact(_strength: float) -> void:
	pass
