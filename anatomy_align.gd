extends RefCounted
## integration: optional standing hip/shaft alignment ported from PonyPussyParadise
## apply_anon_align. It moves only Anon's hip target onto her axis; the camera, lean and planted
## feet stay under the current standing controller.

const ANON_ALIGN_REACH_M := 1.2
const ANON_HIP_AIM := 0.1


static func apply(hip: Node3D, pose_amount: float, pose_basis: Basis, depth: float,
		part: Node, opening: Vector3, rear: Vector3) -> bool:
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
	var root: Vector3 = part.call("root_for", opening, unit_rear, clampf(depth, 0.0, 1.0))
	var wanted: Vector3 = part.call("hip_for", root, square)
	var shift := wanted - hip.global_position
	hip.global_position += shift.limit_length(ANON_ALIGN_REACH_M) * amount
	hip.global_basis = hip.global_basis.orthonormalized().slerp(square, amount)
	return true
