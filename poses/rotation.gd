extends RefCounted
## Pure rotation helpers used by the pose recipes. Keep these free of scene state so they can be
## unit-tested without spawning a pony.


## Angle needed to level a left/right line against the body plane, wrapped into ±90°.
## A left/right line has no direction: ±180° describe the same line. Always choose the branch
## nearest level or a correction can roll the body from belly-up to belly-down.
static func line_roll(forward: Vector3, up: Vector3, left: Vector3, right: Vector3) -> float:
	var fwd := forward.normalized()
	var lateral := right - left
	lateral -= fwd * lateral.dot(fwd)
	if lateral.length_squared() < 0.000001:
		return 0.0
	var side := fwd.cross(up)
	if side.length_squared() < 0.000001:
		return 0.0
	var angle := atan2(lateral.dot(up), lateral.dot(side.normalized()))
	if angle > PI * 0.5:
		angle -= PI
	elif angle < -PI * 0.5:
		angle += PI
	return angle


## Shortest-arc basis that rotates `direction` toward `target` by `weight`.
static func direction_rotation(direction: Vector3, target: Vector3, weight: float) -> Basis:
	if direction.length_squared() < 0.000001 or target.length_squared() < 0.000001:
		return Basis.IDENTITY
	var dir := direction.normalized()
	var wanted := target.normalized()
	var axis := dir.cross(wanted)
	if axis.length_squared() < 0.000001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), dir.angle_to(wanted) * weight)


## Rotate a global pose around `axis` at `pivot` by `angle` radians.
static func rotate_at(pose: Transform3D, axis: Vector3, angle: float, pivot: Vector3) -> Transform3D:
	if axis.length_squared() < 0.000001 or absf(angle) < 0.000001:
		return pose
	var turn := Basis(axis.normalized(), angle)
	var out := pose
	out.origin = pivot + turn * (pose.origin - pivot)
	out.basis = turn * pose.basis
	return out
