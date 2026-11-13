extends "res://mods/unfplap/hands/path_base.gd"
## Missionary caress path: the authored surface chain in `hands/paths/anchors.gd`.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")

const MISSIONARY_CARESS_LATERAL_M := 0.045
const MISSIONARY_CARESS_PALM_ROLL_DEG := 30.0

var _paths: Dictionary = {}
var _last_world: Dictionary = {}
var _path_pony_id := 0


func candidates(hand_side: String, context: Dictionary) -> Array:
	if not is_instance_valid(pony):
		return []
	return _precise_candidates(hand_side, context)


func debug_world(hand_side: String) -> Array:
	var world: Variant = _last_world.get(hand_side)
	return world if world is Array else []


func reset() -> void:
	_paths.clear()
	_last_world.clear()
	_path_pony_id = 0


func _precise_candidates(hand_side: String, context: Dictionary) -> Array:
	var path: Variant = _path_for(hand_side)
	if path == null:
		return []
	var world: Array = path.call("skinned")
	if world.size() < 3:
		return []
	_last_world[hand_side] = world
	var skeleton := _skeleton()
	if not is_instance_valid(skeleton):
		return []
	var lean := clampf(float(context.get("lean", 0.0)), -1.0, 1.0)
	var scale := maxf(float(context.get("scale", 1.0)), 0.1)
	var body_right: Vector3 = pony.global_basis.x.normalized()
	var body_axis := _body_axis(skeleton)
	var length := PATH.path_length(world)
	var u_wanted: float = PATH.u_for(lean, 0.0, float(path.get("belly_u")))
	var oval: Variant = context.get("oval", Vector2(0.01, 0.02))
	var radii: Vector2 = oval if oval is Vector2 else Vector2(0.01, 0.02)
	var hover := float(context.get("hover", 0.0))
	var phase := float(context.get("phase", 0.0))
	var reach: Variant = context.get("reach", {})
	var max_reach := 0.0
	var shoulder := Vector3.ZERO
	if reach is Dictionary and not (reach as Dictionary).is_empty():
		max_reach = _max_reach(reach as Dictionary)
		shoulder = (reach as Dictionary).get("origin", Vector3.ZERO)
	var chosen: Dictionary = {}
	var best: Dictionary = {}
	var best_distance := INF
	var steps := 32
	for i in steps:
		var try_u := u_wanted * (1.0 - float(i) / float(steps - 1))
		var sample := PATH.sample_world(world, try_u, hand_side, body_right)
		if sample.is_empty():
			continue
		var candidate := _precise_candidate(sample, hand_side, scale, body_axis)
		var candidate_point: Vector3 = candidate["point"]
		var candidate_normal: Vector3 = candidate["normal"]
		var contact := candidate_point \
			+ (candidate["oval_x"] as Vector3) * (cos(phase) * radii.x) \
			+ (candidate["oval_y"] as Vector3) * (sin(phase) * radii.y)
		var preview := HAND.place(contact, candidate_normal, candidate["finger"],
			hand_side, str(candidate["mode"]), float(candidate["roll"]), hover)
		if max_reach <= 0.0:
			chosen = candidate
			break
		var distance := shoulder.distance_to(preview.origin)
		if distance < best_distance:
			best_distance = distance
			best = candidate
		if distance <= max_reach:
			chosen = candidate
			break
	if chosen.is_empty():
		chosen = best
	if chosen.is_empty():
		return []
	return [chosen]


func _precise_candidate(sample: Dictionary, hand_side: String, scale: float,
		body_axis: Vector3) -> Dictionary:
	var normal: Vector3 = sample["normal"]
	var centre: Vector3 = sample["point"]
	var lateral: Vector3 = sample["side"]
	centre += lateral * (MISSIONARY_CARESS_LATERAL_M * scale * float(sample["lateral"]))
	var along := body_axis - normal * body_axis.dot(normal)
	if along.length_squared() < 0.0001:
		along = sample["finger"]
	if along.length_squared() < 0.0001:
		along = sample["side"]
	along = along.normalized()
	var across := lateral - normal * lateral.dot(normal)
	if across.length_squared() < 0.0001:
		across = normal.cross(along)
	across = across.normalized()
	var u := float(sample.get("u", 0.0))
	var mode := "fingertip" if u >= 0.75 else "palm"
	var roll := missionary_palm_roll_deg(hand_side) * float(sample["roll"])
	return {
		"point": centre,
		"normal": normal,
		"oval_x": along,
		"oval_y": across,
		"finger": along,
		"mode": mode,
		"roll": roll,
		"region": str(sample.get("region", "torso")),
		"u": u,
	}


func _path_for(hand_side: String) -> Variant:
	var path_id := str(SETTINGS.path_id.get_choice())
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_path_pony_id = pony_id
	var key := hand_side + "|" + path_id
	var path: Variant = _paths.get(key)
	if path != null and bool(path.get("valid")):
		return path
	var started := Time.get_ticks_usec()
	path = PATH.new()
	if not bool(path.call("build", pony, hand_side, _camera_position(), path_id)):
		return null
	_paths[key] = path
	if bool(SETTINGS.caress_debug.get_bool()):
		_log("caress path side=%s path=%s anchors=%d build_ms=%.1f" % [hand_side,
			path_id, (path.get("anchors") as Array).size(),
			float(Time.get_ticks_usec() - started) / 1000.0])
		for note: Variant in (path.get("debug_notes") as Array):
			_log("caress " + str(note))
		var world: Array = path.call("skinned")
		for anchor: Dictionary in world:
			_log("caress anchor %s pos=%s normal=%s" % [anchor["id"],
				str(anchor["position"]), str(anchor["normal"])])
	return path


func _skeleton() -> Skeleton3D:
	var value: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	return value as Skeleton3D


func _camera_position() -> Vector3:
	if facts == null:
		return Vector3.INF
	var value: Variant = facts.camera
	if value is Camera3D and is_instance_valid(value):
		return (value as Camera3D).global_position
	var main: Variant = facts.main
	if is_instance_valid(main) and main.has_method("camera"):
		var cam: Variant = main.call("camera")
		if cam is Camera3D and is_instance_valid(cam):
			return (cam as Camera3D).global_position
	return Vector3.INF


func _body_axis(skeleton: Skeleton3D) -> Vector3:
	var head := skeleton.find_bone("pony_head")
	var hips := skeleton.find_bone("pony_hips")
	if head < 0 or hips < 0:
		return Vector3.FORWARD
	var g := skeleton.global_transform
	var head_pos := g * skeleton.get_bone_global_pose(head).origin
	var hips_pos := g * skeleton.get_bone_global_pose(hips).origin
	var axis := head_pos - hips_pos
	if axis.length_squared() < 0.0001:
		return Vector3.FORWARD
	return axis.normalized()


func _max_reach(reach: Dictionary) -> float:
	if reach.is_empty():
		return 0.0
	var total := float(reach.get("upper", 0.0)) + float(reach.get("lower", 0.0)) \
		+ float(reach.get("hand", 0.0))
	total += maxf(float(SETTINGS.caress_reach_shoulder_m.get_num()), 0.0)
	return total


static func missionary_palm_roll_deg(side: String) -> float:
	return MISSIONARY_CARESS_PALM_ROLL_DEG if side == "right" \
		else -MISSIONARY_CARESS_PALM_ROLL_DEG


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
