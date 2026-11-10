extends "res://mods/unfplap/caress/caress_path_base.gd"
## Standing caress path: the flank/shoulder point follows the lean, and the oval is laid out on
## the coat. The shared engine does the contact query and palm placement.

const CARESS_UP_BIAS_M := 0.05
## Backward lean reaches the rump top at this magnitude, not at a full -1 lean.
const CARESS_RUMP_LEAN := 0.5

var _flank: Node
var _last_centre := Vector3.INF
var _last_normal := Vector3.UP


func candidates(hand_side: String, context: Dictionary) -> Array:
	if not is_instance_valid(pony):
		return []
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank):
		return []
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	var index := 0 if hand_side == "left" else 1
	if not centers is Array or index >= (centers as Array).size() \
			or not normals is Array or index >= (normals as Array).size():
		return []
	var centre: Variant = (centers as Array)[index]
	var normal_local: Variant = (normals as Array)[index]
	if not centre is Vector3 or not normal_local is Vector3:
		return []
	var frame: Transform3D = _flank.global_transform
	var centre_world: Vector3 = frame * (centre as Vector3)
	var normal: Vector3 = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
	if normal.length_squared() < 0.001:
		return []
	# Keep the offset on the outside of the body even if the stored normal is inverted.
	var outward: Vector3 = pony.global_basis.x.normalized()
	if hand_side == "left":
		outward = -outward
	if normal.dot(outward) < 0.0:
		normal = -normal
	var size := maxf(float(context.get("size", 1.0)), 0.1)
	var profile: Variant = context.get("profile", {})
	if not profile is Dictionary:
		profile = {}
	var flank_world: Vector3 = centre_world \
		+ Vector3.UP * (float((profile as Dictionary).get("up", 0.16)) + CARESS_UP_BIAS_M) \
		+ pony.global_basis.z.normalized() * float((profile as Dictionary).get("back", 0.08)) \
		+ outward * float((profile as Dictionary).get("out", 0.0))
	var shoulder_info := shoulder_point(hand_side)
	var shoulder_world: Vector3 = flank_world
	if not shoulder_info.is_empty():
		shoulder_world = shoulder_info["palm"]
	var side_world: Vector3 = flank_world.lerp(shoulder_world, 0.5) + Vector3.DOWN * (0.06 * size)
	var rump_top: Vector3 = flank_world + Vector3.UP * (0.12 * size) + outward * (0.02 * size)
	var lean := clampf(float(context.get("lean", 0.0)), -1.0, 1.0)
	var target_normal := outward
	if lean < 0.0:
		var t := clampf(-lean / CARESS_RUMP_LEAN, 0.0, 1.0)
		centre_world = flank_world.lerp(rump_top, t)
		target_normal = normal.lerp(Vector3.UP, t).normalized()
	elif lean <= 0.5:
		var t := lean * 2.0
		centre_world = flank_world.lerp(side_world, t)
		target_normal = normal.lerp(outward, t).normalized()
	else:
		var t := (lean - 0.5) * 2.0
		centre_world = side_world.lerp(shoulder_world, t)
	normal = target_normal
	var up := Vector3.UP.slide(normal)
	if up.length_squared() < 0.001:
		# On the rump top the world-up tangent collapses; use the body axis instead.
		up = -pony.global_basis.z.slide(normal)
	up = up.normalized()
	var across := up.cross(normal).normalized()
	_last_centre = centre_world
	_last_normal = normal
	return [{
		"point": centre_world,
		"normal": normal,
		"oval_x": across,
		"oval_y": up,
		"finger": -pony.global_basis.z.normalized(),
		"mode": "palm",
		"roll": 0.0,
		"region": "torso",
		"precise": bool(context.get("precise", true)),
		"hull_lift": 0.0,
		"ignore": context.get("ignore", []),
		"regions": [],
		"radial": true,
	}]


func shoulder_point(side: String) -> Dictionary:
	if side.is_empty() or not is_instance_valid(pony):
		return {}
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return {}
	var skeleton := sk as Skeleton3D
	var bone := skeleton.find_bone("pony_shoulder_" + side)
	if bone < 0:
		return {}
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == "left":
		outward = -outward
	return {"palm": shoulder.origin, "outward": outward}


func debug_world(_hand_side: String) -> Array:
	if not _last_centre.is_finite():
		return []
	return [{
		"id": "caress",
		"position": _last_centre,
		"normal": _last_normal,
	}]


func reset() -> void:
	_flank = null
	_last_centre = Vector3.INF
	_last_normal = Vector3.UP
