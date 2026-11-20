extends RefCounted
## The standing "Make love" zone: Anon must stand in a fan behind her rump.
##
## The fan is horizontal: eye height does not matter, and the reach is the ground distance from
## her rump anchor. `HALF_ANGLE_DEG` is a half-angle, so the full fan is twice this value.

## The fan spans a half-plane behind her, so stepping to her side at a normal offset still gets the
## prompt.
const HALF_ANGLE_DEG := 90.0
## Ground distance from her rump anchor. Large enough to offer from a step back, still inside the
## act-start placement's bounded correction.
const REACH_M := 2.0
const REACH_SQ := REACH_M * REACH_M
## `cos(90°)` is effectively zero, so a point exactly to her side stays inside the fan.
const EDGE_EPSILON := 0.000001
const COS_HALF_ANGLE := cos(deg_to_rad(HALF_ANGLE_DEG)) - EDGE_EPSILON
## The approximate rump anchor on her body axis, for the discovery scan that does not read a rig.
const APPROX_HEIGHT := 0.78
const APPROX_BACK := 0.12


## The approximate rump anchor: her position, the height offset and the backset on her backward
## axis. `reactions.rump_point()` falls back to the same point without a skeleton.
static func approx_point(actor: Node3D) -> Vector3:
	if not is_instance_valid(actor):
		return Vector3.INF
	var back: Vector3 = actor.global_basis.z.normalized()
	return actor.global_position + Vector3.UP * APPROX_HEIGHT + back * APPROX_BACK


## `back` is her backward axis (`global_basis.z`), `rump` the anchor and `point` the player.
static func contains(back: Vector3, rump: Vector3, point: Vector3) -> bool:
	var axis := Vector3(back.x, 0.0, back.z)
	var to := Vector3(point.x - rump.x, 0.0, point.z - rump.z)
	if axis.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return false
	if to.length_squared() > REACH_SQ:
		return false
	return axis.normalized().dot(to.normalized()) >= COS_HALF_ANGLE
