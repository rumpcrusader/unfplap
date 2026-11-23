extends "res://mods/unfplap/hands/path_base.gd"
## Standing caress path: the marked-area chain with the procedural flank/rump fallback.

const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const CONTACT := preload("res://mods/unfplap/hands/contact.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const CARESS_UP_BIAS_M := 0.05
## Backward lean reaches the rump top at this magnitude, not at a full -1 lean.
const CARESS_RUMP_LEAN := 0.5

var _flank: Node = null
var _paths: Dictionary = {}
var _path_failed: Dictionary = {}
var _path_pony_id := 0
var _last_world: Dictionary = {}
var _last_centres: Dictionary = {}
var _last_normals: Dictionary = {}


func candidates(hand_side: MODEL.Side,
		context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
	var out: Array[MODEL.Candidate] = []
	if not is_instance_valid(pony):
		return out
	var lean := clampf(context.lean, -1.0, 1.0)
	var authored := _authored_candidates(hand_side, context, lean)
	if not authored.is_empty():
		return authored
	var candidate := _procedural_candidate(hand_side, context)
	if candidate != null:
		out.append(candidate)
	return out


## The marked-area path moves from the flank at no lean through the shoulder to the neck base.
func _authored_candidates(hand_side: MODEL.Side, context: MODEL.CaressContext,
		lean: float) -> Array[MODEL.Candidate]:
	var out: Array[MODEL.Candidate] = []
	var path := _path_for(hand_side, context)
	if path == null:
		return out
	var world := path.skinned()
	if world.size() < 3:
		return out
	var body_right: Vector3 = pony.global_basis.x.normalized()
	var u: float = PATH.u_for(lean, 0.0, path.belly_u)
	var sample := PATH.sample_world(world, u, hand_side, body_right)
	if sample == null:
		return out
	var normal: Vector3 = sample.normal
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var up := Vector3.UP.slide(normal)
	if up.length_squared() < 0.001:
		up = -pony.global_basis.z.slide(normal)
	up = up.normalized()
	var across := up.cross(normal).normalized()
	_last_world[MODEL.side_key(hand_side)] = world
	var candidate := MODEL.Candidate.new()
	candidate.point = sample.point
	candidate.center = sample.center
	candidate.radius = sample.radius
	candidate.normal = normal
	candidate.oval_x = across
	candidate.oval_y = up
	candidate.finger = -pony.global_basis.z.normalized()
	candidate.mode = "palm"
	candidate.roll = 0.0
	candidate.region = sample.region
	candidate.u = u
	out.append(candidate)
	return out


func _procedural_candidate(hand_side: MODEL.Side,
		context: MODEL.CaressContext) -> MODEL.Candidate:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank):
		return null
	var centers := CONTACT.flank_centers(_flank)
	var normals := CONTACT.flank_normals(_flank)
	var index := MODEL.side_index(hand_side)
	if index < 0 or index >= centers.size() or index >= normals.size():
		return null
	var frame: Transform3D = _flank.global_transform
	var centre_world: Vector3 = frame * centers[index]
	var normal: Vector3 = (frame.basis.inverse().transposed() * normals[index]).normalized()
	if normal.length_squared() < 0.001:
		return null
	# Keep the offset on the outside of the body even if the stored normal is inverted.
	var outward: Vector3 = pony.global_basis.x.normalized()
	if hand_side == MODEL.Side.LEFT:
		outward = -outward
	if normal.dot(outward) < 0.0:
		normal = -normal
	var size := maxf(context.size, 0.1)
	var profile: MODEL.CaressProfile = context.profile
	var up := 0.16
	var back := 0.08
	var out_m := 0.0
	if profile != null:
		up = profile.up
		back = profile.back
		out_m = profile.out
	var flank_world: Vector3 = centre_world \
		+ Vector3.UP * (up + CARESS_UP_BIAS_M) \
		+ pony.global_basis.z.normalized() * back \
		+ outward * out_m
	var shoulder_info := shoulder_point(hand_side)
	var shoulder_world: Vector3 = flank_world
	if shoulder_info != null:
		shoulder_world = shoulder_info.palm
	var side_world: Vector3 = flank_world.lerp(shoulder_world, 0.5) + Vector3.DOWN * (0.06 * size)
	var rump_top: Vector3 = flank_world + Vector3.UP * (0.12 * size) + outward * (0.02 * size)
	var lean := clampf(context.lean, -1.0, 1.0)
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
	var up_axis := Vector3.UP.slide(normal)
	if up_axis.length_squared() < 0.001:
		# On the rump top the world-up tangent collapses; use the body axis instead.
		up_axis = -pony.global_basis.z.slide(normal)
	up_axis = up_axis.normalized()
	var across := up_axis.cross(normal).normalized()
	_last_world.erase(MODEL.side_key(hand_side))
	_last_centres[MODEL.side_key(hand_side)] = centre_world
	_last_normals[MODEL.side_key(hand_side)] = normal
	var candidate := MODEL.Candidate.new()
	candidate.point = centre_world
	candidate.center = centre_world
	candidate.radius = 0.0
	candidate.normal = normal
	candidate.oval_x = across
	candidate.oval_y = up_axis
	candidate.finger = -pony.global_basis.z.normalized()
	candidate.mode = "palm"
	candidate.roll = 0.0
	candidate.region = "torso"
	return candidate


func _path_for(hand_side: MODEL.Side, context: MODEL.CaressContext) -> PATH:
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_path_failed.clear()
		_last_world.clear()
		_path_pony_id = pony_id
	var key := MODEL.side_key(hand_side) + "|areas"
	if bool(_path_failed.get(key, false)):
		return null
	var path: PATH = _paths.get(key)
	if path != null and path.valid:
		return path
	PERF.begin("caress_path")
	path = PATH.new()
	var built := path.build_areas(pony, hand_side, "standing")
	PERF.end("caress_path")
	if not built:
		_path_failed[key] = true
		return null
	_paths[key] = path
	if context.debug:
		LOG.debug("caress path side=%s path=areas anchors=%d", [
			MODEL.side_key(hand_side), path.anchors.size()])
		for note: String in path.debug_notes:
			LOG.debug("caress %s", [note])
		var world := path.skinned()
		for anchor: MODEL.AnchorWorld in world:
			LOG.debug("caress anchor %s pos=%s normal=%s", [anchor.id,
				str(anchor.position), str(anchor.normal)])
	return path


## The typed count of built per-hand area chains; the warm-up seam uses it.
func built_hand_count() -> int:
	return _paths.size()


func shoulder_point(side: MODEL.Side) -> MODEL.ShoulderPoint:
	if side == MODEL.Side.NONE or not is_instance_valid(pony):
		return null
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return null
	var skeleton := sk as Skeleton3D
	var bone := skeleton.find_bone("pony_shoulder_" + MODEL.side_letter(side))
	if bone < 0:
		return null
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == MODEL.Side.LEFT:
		outward = -outward
	return MODEL.ShoulderPoint.new(shoulder.origin, outward)


func debug_world(hand_side: MODEL.Side) -> Array[MODEL.AnchorWorld]:
	var out: Array[MODEL.AnchorWorld] = []
	var world: Variant = _last_world.get(MODEL.side_key(hand_side))
	if world is Array and not (world as Array).is_empty():
		for anchor: Variant in (world as Array):
			if anchor is MODEL.AnchorWorld:
				out.append(anchor)
		return out
	var centre: Variant = _last_centres.get(MODEL.side_key(hand_side))
	if centre is Vector3 and (centre as Vector3).is_finite():
		var normal: Variant = _last_normals.get(MODEL.side_key(hand_side), Vector3.UP)
		out.append(MODEL.AnchorWorld.new())
		out[0].id = "caress"
		out[0].position = centre as Vector3
		out[0].normal = normal if normal is Vector3 else Vector3.UP
	return out


func reset() -> void:
	_flank = null
	_paths.clear()
	_path_failed.clear()
	_path_pony_id = 0
	_last_world.clear()
	_last_centres.clear()
	_last_normals.clear()
