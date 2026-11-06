extends RefCounted
## integration: optional standing hip/shaft alignment ported from PonyPussyParadise
## apply_anon_align. The hip position stays pinned at the act-start lower-body point; this only
## turns his pelvis onto her axis. The camera, lean and planted feet stay under the current
## standing controller.

const ANON_HIP_AIM := 0.1


## integration: rotation only. Moving the hip target forward was what pushed Anon's crotch into
## her at large depths; the existing hip-bone backset still supplies the visible stroke.
static func apply_rotation(hip: Node3D, pose_amount: float, pose_basis: Basis, part: Node,
		_opening: Vector3, rear: Vector3) -> bool:
	if not is_instance_valid(hip) or not is_instance_valid(part) or not bool(part.call("showing")):
		return false
	if not pose_basis.is_finite() or rear.length_squared() < 0.0001:
		return false
	var unit_rear := rear.normalized()
	var forward := Vector3(-unit_rear.x, 0.0, -unit_rear.z).normalized()
	if forward.length_squared() < 0.0001:
		return false
	var amount := clampf(pose_amount, 0.0, 1.0)
	var level := Basis.looking_at(forward, Vector3.UP, true)
	var aim := Quaternion(level * (part.call("axis") as Vector3), -unit_rear)
	var square := Basis(Quaternion.IDENTITY.slerp(aim, ANON_HIP_AIM)) * level
	hip.global_basis = hip.global_basis.orthonormalized().slerp(square, amount)
	return true
