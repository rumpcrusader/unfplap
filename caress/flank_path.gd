extends "res://mods/unfplap/caress/caress_path_base.gd"
## Standing caress path: the authored flank -> shoulder -> neck chain from `anchors2.json`, with
## the old procedural flank/rump point as the fallback and the backward-lean reach.

const PATH := preload("res://mods/unfplap/caress/caress_path.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

const CARESS_UP_BIAS_M := 0.05
## Backward lean reaches the rump top at this magnitude, not at a full -1 lean.
const CARESS_RUMP_LEAN := 0.5

var _flank: Node
var _paths: Dictionary = {}
var _path_failed: Dictionary = {}
var _path_pony_id := 0
var _last_world: Dictionary = {}
var _last_centres: Dictionary = {}
var _last_normals: Dictionary = {}


func candidates(hand_side: String, context: Dictionary) -> Array:
	if not is_instance_valid(pony):
		return []
	var precise := bool(context.get("precise", true))
	var lean := clampf(float(context.get("lean", 0.0)), -1.0, 1.0)
	if precise and lean >= 0.0:
		var authored := _authored_candidates(hand_side, context, lean)
		if not authored.is_empty():
			return authored
	var candidate := _procedural_candidate(hand_side, context, precise)
	return [] if candidate.is_empty() else [candidate]


## The authored path is the standing caress path. It moves from the flank at no lean through
## the shoulder to the base of the neck at a full forward lean.
func _authored_candidates(hand_side: String, context: Dictionary, lean: float) -> Array:
	# Anon stands behind her, so his left hand reaches her left side. The authored body chain
	# uses the missionary facing, where the hands cross; request its opposite side here.
	var anchor_hand := "right" if hand_side == "left" else "left"
	var path: Variant = _path_for(anchor_hand)
	if path == null:
		return []
	var world: Array = path.call("skinned")
	if world.size() < 3:
		return []
	var body_right: Vector3 = pony.global_basis.x.normalized()
	var length := PATH.path_length(world)
	var u: float = PATH.u_for(lean, 0.0, float(path.get("belly_u")))
	var sample := PATH.sample_world(world, u, anchor_hand, body_right)
	if sample.is_empty():
		return []
	var normal: Vector3 = sample["normal"]
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var up := Vector3.UP.slide(normal)
	if up.length_squared() < 0.001:
		up = -pony.global_basis.z.slide(normal)
	up = up.normalized()
	var across := up.cross(normal).normalized()
	_last_world[hand_side] = world
	return [{
		"point": sample["point"],
		"normal": normal,
		"oval_x": across,
		"oval_y": up,
		"finger": -pony.global_basis.z.normalized(),
		"mode": "palm",
		"roll": 0.0,
		"region": "torso",
		"precise": true,
		"hull_lift": 0.0,
		"ignore": context.get("ignore", []),
		"regions": [],
		"radial": true,
		"u": u,
	}]


## The old flank/rump point: the backward-lean reach, the hull fallback and the last resort when
## the authored anchors cannot be built.
func _procedural_candidate(hand_side: String, context: Dictionary,
		precise: bool) -> Dictionary:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank):
		return {}
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	var index := 0 if hand_side == "left" else 1
	if not centers is Array or index >= (centers as Array).size() \
			or not normals is Array or index >= (normals as Array).size():
		return {}
	var centre: Variant = (centers as Array)[index]
	var normal_local: Variant = (normals as Array)[index]
	if not centre is Vector3 or not normal_local is Vector3:
		return {}
	var frame: Transform3D = _flank.global_transform
	var centre_world: Vector3 = frame * (centre as Vector3)
	var normal: Vector3 = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
	if normal.length_squared() < 0.001:
		return {}
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
	_last_world.erase(hand_side)
	_last_centres[hand_side] = centre_world
	_last_normals[hand_side] = normal
	return {
		"point": centre_world,
		"normal": normal,
		"oval_x": across,
		"oval_y": up,
		"finger": -pony.global_basis.z.normalized(),
		"mode": "palm",
		"roll": 0.0,
		"region": "torso",
		"precise": precise,
		"hull_lift": 0.0,
		"ignore": context.get("ignore", []),
		"regions": [],
		"radial": true,
	}


func _path_for(hand_side: String) -> Variant:
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_path_failed.clear()
		_last_world.clear()
		_path_pony_id = pony_id
	if bool(_path_failed.get(hand_side, false)):
		return null
	var path: Variant = _paths.get(hand_side)
	if path != null and bool(path.get("valid")):
		return path
	var started := Time.get_ticks_usec()
	path = PATH.new()
	if not bool(path.call("build", pony, hand_side, _camera_position(), "two")):
		_path_failed[hand_side] = true
		return null
	var ids: Array = []
	for anchor: Dictionary in (path.get("anchors") as Array):
		ids.append(str(anchor.get("id", "")))
	if ids != ["flank", "shoulder", "neck"]:
		_path_failed[hand_side] = true
		return null
	_paths[hand_side] = path
	if bool(SETTINGS.caress_debug.get_bool()):
		_log("caress path side=%s path=two anchors=%d build_ms=%.1f" % [hand_side,
			(path.get("anchors") as Array).size(),
			float(Time.get_ticks_usec() - started) / 1000.0])
		for note: Variant in (path.get("debug_notes") as Array):
			_log("caress " + str(note))
		var world: Array = path.call("skinned")
		for anchor: Dictionary in world:
			_log("caress anchor %s pos=%s normal=%s" % [anchor["id"],
				str(anchor["position"]), str(anchor["normal"])])
	return path


func _camera_position() -> Vector3:
	if not is_instance_valid(runtime):
		return Vector3.INF
	var value: Variant = runtime.get("_camera")
	if value is Camera3D and is_instance_valid(value):
		return (value as Camera3D).global_position
	var main: Variant = runtime.get("main")
	if is_instance_valid(main) and main.has_method("camera"):
		var cam: Variant = main.call("camera")
		if cam is Camera3D and is_instance_valid(cam):
			return (cam as Camera3D).global_position
	return Vector3.INF


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


func debug_world(hand_side: String) -> Array:
	var world: Variant = _last_world.get(hand_side)
	if world is Array and not (world as Array).is_empty():
		return world
	var centre: Variant = _last_centres.get(hand_side)
	if centre is Vector3 and (centre as Vector3).is_finite():
		var normal: Variant = _last_normals.get(hand_side, Vector3.UP)
		return [{
			"id": "caress",
			"position": centre,
			"normal": normal if normal is Vector3 else Vector3.UP,
		}]
	return []


func reset() -> void:
	_flank = null
	_paths.clear()
	_path_failed.clear()
	_path_pony_id = 0
	_last_world.clear()
	_last_centres.clear()
	_last_normals.clear()


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
