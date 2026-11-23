extends "res://mods/unfplap/hands/path_base.gd"
## Standing oral: a single authored node per hand on her head side, no chain and no fallback.

const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const ORAL_PALM_ROLL_DEG := 24.0

var _paths: Dictionary = {}
var _failed: Dictionary = {}
var _last_world: Dictionary = {}
var _path_pony_id := 0


func candidates(hand_side: MODEL.Side,
		context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
	var out: Array[MODEL.Candidate] = []
	if not is_instance_valid(pony):
		return out
	# Anon faces her, like in missionary, so his left hand holds her right side and his right
	# hand holds her left. The head area is mare-PoV, so read the opposite side.
	var anchor_side := MODEL.side_other(hand_side)
	var path := _path_for(anchor_side, context)
	if path == null:
		return out
	var world := path.skinned()
	if world.size() != 1:
		return out
	var anchor := world[0]
	_last_world[MODEL.side_key(hand_side)] = world
	var normal := anchor.normal
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var forward: Vector3 = (-pony.global_basis.z).normalized()
	var along := forward - normal * forward.dot(normal)
	if along.length_squared() < 0.0001:
		along = normal.cross(Vector3.UP)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	along = along.normalized()
	var across := normal.cross(along)
	if across.length_squared() < 0.0001:
		across = normal.cross(Vector3.RIGHT)
	across = across.normalized()
	var candidate := MODEL.Candidate.new()
	candidate.point = anchor.position
	candidate.center = anchor.center
	candidate.radius = anchor.radius
	candidate.normal = normal
	candidate.oval_x = along
	candidate.oval_y = across
	candidate.finger = along
	candidate.mode = path.single_mode
	candidate.roll = oral_palm_roll_deg(hand_side) * anchor.roll
	candidate.region = anchor.region
	candidate.exact = true
	candidate.u = 0.0
	out.append(candidate)
	return out


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
	_failed.clear()
	_last_world.clear()
	_path_pony_id = 0


func _path_for(anchor_side: MODEL.Side, context: MODEL.CaressContext) -> PATH:
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_failed.clear()
		_last_world.clear()
		_path_pony_id = pony_id
	var key := MODEL.side_key(anchor_side)
	if bool(_failed.get(key, false)):
		return null
	var path: PATH = _paths.get(key)
	if path != null and path.valid:
		return path
	PERF.begin("caress_path")
	path = PATH.new()
	var built := path.build_single_area(pony, anchor_side, "head_side")
	PERF.end("caress_path")
	if not built:
		_failed[key] = true
		LOG.debug("caress oral head_side missing side=%s", [key])
		for note: String in path.debug_notes:
			LOG.debug("caress %s", [note])
		return null
	_paths[key] = path
	if context.debug:
		LOG.debug("caress path side=%s path=oral anchors=1", [key])
		var world := path.skinned()
		for anchor: MODEL.AnchorWorld in world:
			LOG.debug("caress anchor %s pos=%s normal=%s", [anchor.id,
				str(anchor.position), str(anchor.normal)])
	return path


static func oral_palm_roll_deg(side: MODEL.Side) -> float:
	return ORAL_PALM_ROLL_DEG if side == MODEL.Side.RIGHT else -ORAL_PALM_ROLL_DEG
