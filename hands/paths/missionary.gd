extends "res://mods/unfplap/hands/path_base.gd"
## Missionary caress path: the authored area chain with the reach-aware walk back.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const MISSIONARY_CARESS_LATERAL_M := 0.045
const MISSIONARY_CARESS_PALM_ROLL_DEG := 30.0

var _paths: Dictionary = {}
var _last_world: Dictionary = {}
var _path_pony_id := 0


func candidates(hand_side: MODEL.Side,
		context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
	if not is_instance_valid(pony):
		return []
	return _precise_candidates(hand_side, context)


func debug_world(hand_side: MODEL.Side) -> Array[MODEL.AnchorWorld]:
	var out: Array[MODEL.AnchorWorld] = []
	var world: Variant = _last_world.get(MODEL.side_key(hand_side))
	if world is Array:
		for anchor: Variant in (world as Array):
			if anchor is MODEL.AnchorWorld:
				out.append(anchor)
	return out


func reset() -> void:
	_paths.clear()
	_last_world.clear()
	_path_pony_id = 0


func _precise_candidates(hand_side: MODEL.Side,
		context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
	var out: Array[MODEL.Candidate] = []
	var path := _path_for(hand_side, context)
	if path == null:
		return out
	var world := path.skinned()
	if world.size() < 3:
		return out
	_last_world[MODEL.side_key(hand_side)] = world
	var skeleton := _skeleton()
	if not is_instance_valid(skeleton):
		return out
	var lean := clampf(context.lean, -1.0, 1.0)
	var scale := maxf(context.scale, 0.1)
	var body_right: Vector3 = pony.global_basis.x.normalized()
	var body_axis := _body_axis(skeleton)
	var u_wanted: float = PATH.u_for(lean, 0.0, path.belly_u)
	var radii := context.oval
	var hover := context.hover
	var phase := context.phase
	var max_reach := 0.0
	var shoulder := Vector3.ZERO
	if context.reach != null and context.reach.valid:
		max_reach = _max_reach(context.reach, context.reach_shoulder_m)
		shoulder = context.reach.origin
	var chosen: MODEL.Candidate = null
	var best: MODEL.Candidate = null
	var best_distance := INF
	var steps := 32
	for i in steps:
		var try_u := u_wanted * (1.0 - float(i) / float(steps - 1))
		var sample := PATH.sample_world(world, try_u, hand_side, body_right)
		if sample == null:
			continue
		var candidate := _precise_candidate(sample, hand_side, scale, body_axis)
		var contact := candidate.point \
			+ candidate.oval_x * (cos(phase) * radii.x) \
			+ candidate.oval_y * (sin(phase) * radii.y)
		var preview := HAND.place(contact, candidate.normal, candidate.finger,
			MODEL.side_key(hand_side), candidate.mode, candidate.roll, hover)
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
	if chosen == null:
		chosen = best
	if chosen == null:
		return out
	out.append(chosen)
	return out


func _precise_candidate(sample: MODEL.Sample, hand_side: MODEL.Side, scale: float,
		body_axis: Vector3) -> MODEL.Candidate:
	var normal := sample.normal
	var centre := sample.point
	var center := sample.center
	var lateral := sample.side
	var offset := lateral * (MISSIONARY_CARESS_LATERAL_M * scale * sample.lateral)
	centre += offset
	center += offset
	var along := body_axis - normal * body_axis.dot(normal)
	if along.length_squared() < 0.0001:
		along = sample.finger
	if along.length_squared() < 0.0001:
		along = sample.side
	along = along.normalized()
	var across := lateral - normal * lateral.dot(normal)
	if across.length_squared() < 0.0001:
		across = normal.cross(along)
	across = across.normalized()
	var u := sample.u
	var mode := "fingertip" if u >= 0.75 else "palm"
	var out := MODEL.Candidate.new()
	out.point = centre
	out.center = center
	out.radius = sample.radius
	out.normal = normal
	out.oval_x = along
	out.oval_y = across
	out.finger = along
	out.mode = mode
	out.roll = missionary_palm_roll_deg(hand_side) * sample.roll
	out.region = sample.region
	out.u = u
	return out


func _path_for(hand_side: MODEL.Side, context: MODEL.CaressContext) -> PATH:
	var path_id := context.path_id
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_path_pony_id = pony_id
	var key := MODEL.side_key(hand_side) + "|" + path_id
	var path: PATH = _paths.get(key)
	if path != null and path.valid:
		return path
	PERF.begin("caress_path")
	path = PATH.new()
	var built := path.build(pony, hand_side, _camera_position(), path_id)
	PERF.end("caress_path")
	if not built:
		return null
	_paths[key] = path
	if context.debug:
		LOG.debug("caress path side=%s path=%s anchors=%d", [MODEL.side_key(hand_side),
			path_id, path.anchors.size()])
		for note: String in path.debug_notes:
			LOG.debug("caress %s", [note])
		var world := path.skinned()
		for anchor: MODEL.AnchorWorld in world:
			LOG.debug("caress anchor %s pos=%s normal=%s", [anchor.id,
				str(anchor.position), str(anchor.normal)])
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
	var cam: Camera3D = WORLD.camera()
	if cam != null:
		return cam.global_position
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


func _max_reach(reach: MODEL.ReachInfo, reach_shoulder_m: float) -> float:
	return reach.upper + reach.lower + reach.hand + maxf(reach_shoulder_m, 0.0)


static func missionary_palm_roll_deg(side: MODEL.Side) -> float:
	return MISSIONARY_CARESS_PALM_ROLL_DEG if side == MODEL.Side.RIGHT \
		else -MISSIONARY_CARESS_PALM_ROLL_DEG
