extends RefCounted
## The standing "Make love" zone: Anon must stand in a fan behind her rump.
##
## The fan is horizontal: eye height does not matter, and the reach is the ground distance from
## her rump anchor. `HALF_ANGLE_DEG` is a half-angle, so the full fan is twice this value.

## 180 degrees total, 90 to each side of her backward axis. The fan is the whole rear half-plane,
## so a player who steps to her side at a normal offset still gets the prompt.
const HALF_ANGLE_DEG := 90.0
## Ground distance from her rump anchor. Large enough to offer from a step back, still inside the
## act-start placement's bounded correction.
const REACH_M := 2.0
## `cos(90°)` is effectively zero, so a point exactly to her side stays inside the fan.
const EDGE_EPSILON := 0.000001


## `back` is her backward axis (`global_basis.z`), `rump` the anchor and `point` the player.
static func contains(back: Vector3, rump: Vector3, point: Vector3) -> bool:
	var axis := Vector3(back.x, 0.0, back.z)
	var to := Vector3(point.x - rump.x, 0.0, point.z - rump.z)
	if axis.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return false
	if to.length() > REACH_M:
		return false
	return axis.normalized().dot(to.normalized()) \
		>= cos(deg_to_rad(HALF_ANGLE_DEG)) - EDGE_EPSILON
