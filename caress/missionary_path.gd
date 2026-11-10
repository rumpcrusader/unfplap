extends "res://mods/unfplap/caress/caress_path_base.gd"
## Missionary caress path. The precise path is the authored surface chain in
## `caress/caress_path.gd`; the legacy hull path remains when the precise feature is off.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PATH := preload("res://mods/unfplap/caress/caress_path.gd")
const HAND := preload("res://mods/unfplap/caress/caress_hand.gd")
const COAT := preload("res://mods/unfplap/caress/coat.gd")

const MISSIONARY_CARESS_TRAVEL_M := 0.12
const MISSIONARY_CARESS_LATERAL_M := 0.045
const MISSIONARY_CARESS_LIFT_M := 0.18
const MISSIONARY_CARESS_PALM_ROLL_DEG := 30.0
const MISSIONARY_TORSO_REGIONS := ["back", "withers", "shoulder", "barrel", "belly", "rump"]

var _paths: Dictionary = {}
var _last_world: Dictionary = {}
var _path_pony_id := 0


func candidates(hand_side: String, context: Dictionary) -> Array:
	if not is_instance_valid(pony):
		return []
	if bool(context.get("precise", true)):
		var precise := _precise_candidates(hand_side, context)
		if not precise.is_empty():
			return precise
	return _legacy_candidates(hand_side, context)


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
	var along_setting := float(context.get("along_m", 0.0))
	var scale := maxf(float(context.get("scale", 1.0)), 0.1)
	var body_right: Vector3 = pony.global_basis.x.normalized()
	var body_axis := _body_axis(skeleton)
	var length := PATH.path_length(world)
	var u_wanted: float = PATH.u_for(lean, along_setting / maxf(length, 0.05),
		float(path.get("belly_u")))
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
		"precise": true,
		"u": u,
	}


func _legacy_candidates(hand_side: String, context: Dictionary) -> Array:
	var skeleton := _skeleton()
	if not is_instance_valid(skeleton):
		return []
	var scale := maxf(float(context.get("scale", 1.0)), 0.1)
	var lean := clampf(float(context.get("lean", 0.0)), -1.0, 1.0)
	var along_setting := float(context.get("along_m", 0.0))
	var path := _legacy_path(skeleton, skeleton.global_transform, hand_side, lean,
		along_setting, scale)
	if path.is_empty():
		return []
	var centre: Vector3 = path["point"]
	var hint: Vector3 = path["hint"]
	var lift: float = path["lift"]
	var regions: Array = path["regions"]
	var lateral: float = path["lateral"]
	var body_side: Vector3 = path["side"]
	var finger: Vector3 = path["finger"]
	centre += body_side * (MISSIONARY_CARESS_LATERAL_M * scale * lateral)
	var along := finger - hint * finger.dot(hint)
	if along.length_squared() < 0.0001:
		along = Vector3.UP - hint * Vector3.UP.dot(hint)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD - hint * Vector3.FORWARD.dot(hint)
	along = along.normalized()
	var across := along.cross(hint)
	if across.length_squared() < 0.0001:
		across = Vector3.RIGHT - hint * Vector3.RIGHT.dot(hint)
	across = across.normalized()
	var ignore: Array = context.get("ignore", []).duplicate() \
		if context.get("ignore", []) is Array else []
	if not ignore.has("leg"):
		ignore.append("leg")
	COAT.sync_touch(pony)
	return [{
		"point": centre,
		"normal": hint,
		"oval_x": along,
		"oval_y": across,
		"finger": finger,
		"mode": "palm",
		"roll": missionary_palm_roll_deg(hand_side) * float(path["roll"]),
		"region": "torso",
		"precise": false,
		"hull_lift": lift,
		"ignore": ignore,
		"regions": regions,
		"radial": false,
	}]


## Smooth caress path: lower belly -> belly -> chest -> side of the neck -> cheek. The returned
## point is the centreline anchor before the hand-side offset and oval.
func _legacy_path(skeleton: Skeleton3D, g: Transform3D, side: String,
		lean: float, along_m: float, scale: float) -> Dictionary:
	var hips_b := skeleton.find_bone("pony_hips")
	var belly_b := skeleton.find_bone("pony_spine2")
	var chest_b := skeleton.find_bone("pony_spine3")
	var neck1_b := skeleton.find_bone("pony_neck1")
	var neck2_b := skeleton.find_bone("pony_neck2")
	var head_b := skeleton.find_bone("pony_head")
	if hips_b < 0 or belly_b < 0 or head_b < 0:
		return {}
	var hips := g * skeleton.get_bone_global_pose(hips_b).origin
	var belly := g * skeleton.get_bone_global_pose(belly_b).origin
	var head_t := g * skeleton.get_bone_global_pose(head_b)
	var head := head_t.origin
	var chest := head.lerp(belly, 0.35)
	if chest_b >= 0:
		chest = g * skeleton.get_bone_global_pose(chest_b).origin
	var neck := chest.lerp(head, 0.5)
	if neck1_b >= 0 and neck2_b >= 0:
		neck = (g * skeleton.get_bone_global_pose(neck1_b).origin).lerp(
			g * skeleton.get_bone_global_pose(neck2_b).origin, 0.5)
	var head_dir := head - hips
	if head_dir.length_squared() < 0.0001:
		head_dir = -pony.global_basis.z
	head_dir = head_dir.normalized()
	var side_axis := head_dir.cross(Vector3.UP)
	if side_axis.length_squared() < 0.0001:
		side_axis = pony.global_basis.x
	side_axis = side_axis.normalized()
	var side_sign := -1.0 if side == "left" else 1.0
	var body_side := (side_axis * side_sign).normalized()
	var path_len := maxf(belly.distance_to(head), 0.001)
	var chest_t := clampf(belly.distance_to(chest) / path_len, 0.05, 0.70)
	var neck_t := clampf(belly.distance_to(neck) / path_len, chest_t + 0.05, 0.92)
	var travel := lean * path_len + along_m * scale
	if travel < 0.0:
		var lower := clampf(travel, -MISSIONARY_CARESS_TRAVEL_M * scale, 0.0)
		return {
			"point": belly + head_dir * lower,
			"hint": Vector3.UP,
			"lift": MISSIONARY_CARESS_LIFT_M * scale,
			"regions": MISSIONARY_TORSO_REGIONS,
			"surface_region": "torso",
			"mode": "palm",
			"lateral": 1.0,
			"roll": 1.0,
			"side": body_side,
			"finger": head_dir,
		}
	var t := clampf(travel / path_len, 0.0, 1.0)
	var head_side := head_t.basis.x.normalized()
	if head_side.dot(body_side) < 0.0:
		head_side = -head_side
	var point := belly
	var hint := Vector3.UP
	var lift := MISSIONARY_CARESS_LIFT_M * scale
	var regions: Array = MISSIONARY_TORSO_REGIONS
	var surface_region := "torso"
	var mode := "palm"
	var lateral := 1.0
	var roll := 1.0
	if t <= chest_t:
		var u := t / maxf(chest_t, 0.001)
		point = belly.lerp(chest, u)
	elif t <= neck_t:
		var u := (t - chest_t) / maxf(neck_t - chest_t, 0.001)
		point = chest.lerp(neck, u)
		hint = Vector3.UP.lerp(body_side, u).normalized()
		lift = lerpf(MISSIONARY_CARESS_LIFT_M, 0.10, u) * scale
		regions = MISSIONARY_TORSO_REGIONS + ["neck"]
		surface_region = "neck" if u >= 0.5 else "torso"
		lateral = 1.0 - u
		roll = 1.0 - u
	else:
		var u := (t - neck_t) / maxf(1.0 - neck_t, 0.001)
		point = neck.lerp(head, u)
		hint = body_side.lerp(head_side, u).normalized()
		lift = lerpf(0.10, 0.12, u) * scale
		regions = ["neck", "head"]
		surface_region = "head"
		mode = "fingertip"
		lateral = 0.0
		roll = 0.0
	return {
		"point": point,
		"hint": hint,
		"lift": lift,
		"regions": regions,
		"surface_region": surface_region,
		"mode": mode,
		"lateral": lateral,
		"roll": roll,
		"side": body_side,
		"finger": head_dir,
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
	var stretch := maxf(float(SETTINGS.caress_reach_stretch.get_num()), 1.0)
	var total := (float(reach.get("upper", 0.0)) + float(reach.get("lower", 0.0))
		+ float(reach.get("hand", 0.0))) * stretch
	total += maxf(float(SETTINGS.caress_reach_shoulder_m.get_num()), 0.0)
	total += maxf(float(SETTINGS.caress_reach_body_m.get_num()), 0.0)
	return total


static func missionary_palm_roll_deg(side: String) -> float:
	return MISSIONARY_CARESS_PALM_ROLL_DEG if side == "right" \
		else -MISSIONARY_CARESS_PALM_ROLL_DEG


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
