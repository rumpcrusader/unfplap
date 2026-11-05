extends RefCounted
## The standing "Make love" zone: Anon must stand in a cone behind her rump.
##
## The cone is horizontal: eye height does not matter, and the reach is the ground distance from
## her rump anchor. `HALF_ANGLE_DEG` is a half-angle, so the full fan is twice this value.

## 45 degrees total, 22.5 to each side of her backward axis.
const HALF_ANGLE_DEG := 22.5
## Ground distance from her rump anchor, matching the old flank touch reach.
const REACH_M := 0.8


## `back` is her backward axis (`global_basis.z`), `rump` the anchor and `point` the player.
static func contains(back: Vector3, rump: Vector3, point: Vector3) -> bool:
	var axis := Vector3(back.x, 0.0, back.z)
	var to := Vector3(point.x - rump.x, 0.0, point.z - rump.z)
	if axis.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return false
	if to.length() > REACH_M:
		return false
	return axis.normalized().dot(to.normalized()) >= cos(deg_to_rad(HALF_ANGLE_DEG))
