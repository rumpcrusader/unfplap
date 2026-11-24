extends RefCounted
## Sphere-anchored caress path: one fitted sphere per authored area, sampled analytically.

const FIT := preload("res://mods/unfplap/hands/coat_fit.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ANCHORS_FILES := {
	"one": "res://mods/unfplap/hands/paths/anchors.json",
	"two": "res://mods/unfplap/hands/paths/anchors2.json",
}
const AREAS_FILE := "res://mods/unfplap/hands/areas/areas.json"
const BELLY_U := 0.25

static var _authored_data: Dictionary = {}
static var _areas_data: Dictionary = {}

## The background fit queue: one authored area per tick while an act poses.
static var _prefit: Array[MODEL.AnchorPoint] = []
static var _prefit_pony_id := 0

var anchors: Array[MODEL.Anchor] = []
var side: MODEL.Side = MODEL.Side.RIGHT
var valid := false
var area_mode := false
var single_mode := "palm"
var path_len := 0.0
var belly_u := BELLY_U
var debug_notes: Array[String] = []


## The authored slot chain in `anchors.json` / `anchors2.json`.
func build(pony_node: Node3D, hand_side: MODEL.Side, _camera_position := Vector3.INF,
		path_id := "one") -> bool:
	valid = false
	anchors.clear()
	area_mode = false
	path_len = 0.0
	belly_u = BELLY_U
	debug_notes.clear()
	side = hand_side
	if not is_instance_valid(pony_node):
		return false
	if not _authored_ready(hand_side, path_id):
		debug_notes.append("authored path %s missing" % path_id)
		return false
	anchors = _build_authored(pony_node, hand_side, path_id)
	_update_belly_u()
	if anchors.size() < 3:
		return false
	debug_notes.append(_rig_note(pony_node))
	path_len = path_length(skinned())
	valid = true
	return true


## The marked caress areas as a lean-sampled chain, one fitted sphere per area. The area file is
## written in her own body sides, so the hand side is taken as it stands; the slot chains are
## written from Anon's side instead, which is why the oral single area reads the other one.
func build_areas(pony_node: Node3D, hand_side: MODEL.Side, pose_name: String) -> bool:
	valid = false
	anchors.clear()
	area_mode = true
	path_len = 0.0
	belly_u = 0.0
	debug_notes.clear()
	side = hand_side
	if not is_instance_valid(pony_node):
		return false
	var data := _areas()
	var poses: Variant = data.get("poses", {})
	if not poses is Dictionary:
		return false
	var pose: Variant = (poses as Dictionary).get(pose_name, {})
	if not pose is Dictionary:
		return false
	var order: Variant = (pose as Dictionary).get("order", [])
	if not order is Array or (order as Array).size() < 2:
		return false
	var areas: Variant = data.get("areas", {})
	if not areas is Dictionary:
		return false
	var side_key := MODEL.side_key(hand_side)
	for slot_value: Variant in (order as Array):
		var slot := str(slot_value)
		var entry: Variant = (areas as Dictionary).get(slot, {})
		if not entry is Dictionary:
			continue
		var side_entry: Variant = (entry as Dictionary).get(side_key, {})
		if not side_entry is Dictionary:
			continue
		var position := _entry_position(side_entry)
		if not position.is_finite():
			continue
		var region := str((entry as Dictionary).get("region", "torso"))
		var roll := float((entry as Dictionary).get("roll", 1.0))
		var anchor := _anchor(pony_node, region, position)
		if anchor == null:
			debug_notes.append("area %s miss" % slot)
			continue
		_anchor_meta(anchor, slot, 1.0, roll, region)
		anchors.append(anchor)
	if anchors.size() < 3:
		return false
	var start := str((pose as Dictionary).get("start", ""))
	for i in anchors.size():
		if anchors[i].id == start:
			belly_u = float(i) / maxf(float(anchors.size() - 1), 1.0)
			break
	debug_notes.append(_rig_note(pony_node))
	path_len = path_length(skinned())
	valid = true
	return true


## One fixed area, for paths that hold a single node: no chain, start or lean sampling.
func build_single_area(pony_node: Node3D, hand_side: MODEL.Side, area_name: String) -> bool:
	valid = false
	anchors.clear()
	area_mode = true
	single_mode = "palm"
	path_len = 0.0
	belly_u = 0.0
	debug_notes.clear()
	side = hand_side
	if not is_instance_valid(pony_node):
		return false
	var data := _areas()
	var areas: Variant = data.get("areas", {})
	if not areas is Dictionary:
		return false
	var entry: Variant = (areas as Dictionary).get(area_name, {})
	if not entry is Dictionary:
		debug_notes.append("area %s missing" % area_name)
		return false
	var side_entry: Variant = (entry as Dictionary).get(MODEL.side_key(hand_side), {})
	if not side_entry is Dictionary:
		debug_notes.append("area %s has no %s side" % [area_name, MODEL.side_key(hand_side)])
		return false
	var position := _entry_position(side_entry)
	if not position.is_finite():
		debug_notes.append("area %s has no position" % area_name)
		return false
	var region := str((entry as Dictionary).get("region", "head"))
	var roll := float((entry as Dictionary).get("roll", 1.0))
	single_mode = str((entry as Dictionary).get("mode", "palm"))
	var anchor := _anchor(pony_node, region, position)
	if anchor == null:
		debug_notes.append("area %s miss" % area_name)
		return false
	_anchor_meta(anchor, area_name, 1.0, roll, region)
	anchors.append(anchor)
	debug_notes.append(_rig_note(pony_node))
	valid = true
	return true


## The only anchor of a `build_single_area()` path, or null.
func single() -> MODEL.Anchor:
	if anchors.is_empty():
		return null
	return anchors[0]


## Skin the stored anchors and sample the path.
func sample(lean: float, along_m: float, body_right: Vector3) -> MODEL.Sample:
	var world := skinned()
	if world.size() < 3:
		return null
	var length := path_length(world)
	path_len = length
	return sample_world(world, u_for(lean, along_m / maxf(length, 0.05), belly_u),
		side, body_right)


static func u_for(lean: float, along_u: float, belly := BELLY_U) -> float:
	var u := belly
	if lean >= 0.0:
		u = lerpf(belly, 1.0, clampf(lean, 0.0, 1.0))
	else:
		u = lerpf(belly, 0.0, clampf(-lean, 0.0, 1.0))
	return clampf(u + along_u, 0.0, 1.0)


## Pure sampler over already-skinned anchors: the coat point, its sphere and the frame.
static func sample_world(world: Array[MODEL.AnchorWorld], u: float, hand_side: MODEL.Side,
		body_right: Vector3) -> MODEL.Sample:
	var count := world.size() - 1
	if count < 1:
		return null
	var f := clampf(u, 0.0, 1.0) * count
	var i := int(floor(f))
	var t := f - i
	if i >= count:
		i = count - 1
		t = 1.0
	var p0 := world[maxi(i - 1, 0)].position
	var p1 := world[i].position
	var p2 := world[mini(i + 1, count)].position
	var p3 := world[mini(i + 2, count)].position
	var point := _catmull(p0, p1, p2, p3, t)
	var tangent := _catmull_tangent(p0, p1, p2, p3, t)
	if tangent.length_squared() < 0.000001:
		tangent = p2 - p1
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.UP
	tangent = tangent.normalized()
	var c0 := world[maxi(i - 1, 0)].center
	var c1 := world[i].center
	var c2 := world[mini(i + 1, count)].center
	var c3 := world[mini(i + 2, count)].center
	var center := _catmull(c0, c1, c2, c3, t)
	var a1 := world[i]
	var a2 := world[mini(i + 1, count)]
	var radius := lerpf(a1.radius, a2.radius, t)
	var normal := a1.normal.lerp(a2.normal, t)
	if normal.length_squared() < 0.000001:
		normal = a1.normal
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	normal = normal.normalized()
	var lateral := normal.cross(tangent)
	if lateral.length_squared() < 0.000001:
		lateral = tangent.cross(Vector3.UP)
	lateral = lateral.normalized()
	var wanted := body_right.normalized()
	if wanted.length_squared() < 0.5:
		wanted = Vector3.RIGHT
	if hand_side == MODEL.Side.LEFT:
		wanted = -wanted
	if lateral.dot(wanted) < 0.0:
		lateral = -lateral
	var out := MODEL.Sample.new()
	out.u = u
	out.point = point
	out.center = center
	out.radius = radius
	out.normal = normal
	out.finger = tangent
	out.side = lateral
	out.lateral = lerpf(a1.lateral, a2.lateral, t)
	out.roll = lerpf(a1.roll, a2.roll, t)
	out.region = a1.region if t < 0.5 else a2.region
	out.id = a1.id if t < 0.5 else a2.id
	return out


## Skin the anchors: each sphere centre and normal, with the coat point derived from them.
func skinned() -> Array[MODEL.AnchorWorld]:
	var world: Array[MODEL.AnchorWorld] = []
	for anchor: MODEL.Anchor in anchors:
		var sk: Skeleton3D = anchor.skeleton
		if not is_instance_valid(sk):
			return world
		var base := sk.global_transform
		var center := Vector3.ZERO
		var normal := Vector3.ZERO
		for influence: MODEL.Influence in anchor.influences:
			if influence.bone < 0:
				continue
			var transform: Transform3D = base * sk.get_bone_global_pose(influence.bone) \
				* influence.bind
			center += (transform * anchor.center) * influence.weight
			normal += (transform.basis * anchor.normal) * influence.weight
		if normal.length_squared() < 0.000001:
			normal = Vector3.UP
		normal = normal.normalized()
		var out := MODEL.AnchorWorld.new()
		out.id = anchor.id
		out.position = center + normal * (anchor.radius * base.basis.get_scale().x)
		out.center = center
		out.radius = anchor.radius * base.basis.get_scale().x
		out.normal = normal
		out.lateral = anchor.lateral
		out.roll = anchor.roll
		out.region = anchor.region
		world.append(out)
	return world


static func path_length(world: Array[MODEL.AnchorWorld]) -> float:
	var length := 0.0
	for i in range(1, world.size()):
		length += world[i].position.distance_to(world[i - 1].position)
	return length


## One fitted anchor: the area's sphere plus the skin that places it on the posed body.
func _anchor(pony_node: Node3D, region: String, position: Vector3) -> MODEL.Anchor:
	var found := FIT.find_mesh(pony_node, region)
	if found == null:
		return null
	var skeleton: Skeleton3D = found.skeleton
	if not is_instance_valid(skeleton):
		return null
	var placed := _body_position(pony_node, region, position)
	var primitive := FIT.primitive(pony_node, region, placed,
		_fit_distance(pony_node, region))
	if primitive == null:
		LOG.debug("caress area miss region=%s rig=%s authored=%s mapped=%s", [
			region, _rig(pony_node).id, str(position), str(placed)])
		return null
	var influences: Array[MODEL.Influence] = []
	for influence: MODEL.CoatInfluence in primitive.influences:
		var bone := skeleton.find_bone(influence.bone_name)
		if bone < 0:
			continue
		influences.append(MODEL.Influence.new(bone, influence.bind, influence.weight))
	if influences.is_empty():
		return null
	var out := MODEL.Anchor.new()
	out.skeleton = skeleton
	out.center = primitive.center
	out.normal = primitive.normal
	out.radius = primitive.radius
	out.influences = influences
	return out


## Authored areas are mare rest points; a winking body reads them through the anatomy rig map. A
## head area is exempt: the head is the game's own head on every body it sits on.
static func _body_position(pony_node: Node3D, region: String, position: Vector3) -> Vector3:
	if region == "head":
		return position
	var rig := _rig(pony_node)
	if rig == null or rig.is_ordinary():
		return position
	var size := maxf(rig.scale, 0.1)
	return Vector3(position.x * size,
		rig.rear_y + (position.y - BODY_PROFILE.WINKING_REAR_Y) * size,
		rig.rear_z + (position.z - BODY_PROFILE.WINKING_REAR_Z) * size)


## A remapped point may miss the coat by more than an authored one does, so it may snap farther.
static func _fit_distance(pony_node: Node3D, region: String) -> float:
	if region == "head":
		return FIT.MAX_DISTANCE_M
	var rig := _rig(pony_node)
	if rig == null or rig.is_ordinary():
		return FIT.MAX_DISTANCE_M
	return FIT.REMAPPED_DISTANCE_M


## The presented body's rig. A body-fit key with no princess profile falls back to the identity.
static func _rig(pony_node: Node3D) -> BODY_PROFILE.RigProfile:
	var rig := BODY_PROFILE.rig_for_pony(pony_node)
	if rig != null and not rig.is_ordinary():
		return rig
	var identity: Variant = pony_node.get("identity") if pony_node != null else null
	return BODY_PROFILE.rig_for_identity(identity)


static func _rig_note(pony_node: Node3D) -> String:
	var rig := _rig(pony_node)
	var fit := BODY_PROFILE.body_fit_id(pony_node) if pony_node != null else ""
	var character := ""
	var identity: Variant = pony_node.get("identity") if pony_node != null else null
	if identity != null:
		character = str(identity.get("character_id"))
	return "rig %s size=%.2f fit=%s character=%s" % [
		rig.id if rig != null else BODY_PROFILE.ORDINARY_RIG, rig.scale if rig != null else 1.0,
		fit, character]


## Fit one authored area per call while an act poses; true while entries remain for this pony.
static func prefit_tick(pony_node: Node3D) -> bool:
	if not is_instance_valid(pony_node):
		return false
	var id := int(pony_node.get_instance_id())
	if id != _prefit_pony_id:
		_prefit_pony_id = id
		_prefit = _area_points()
	if _prefit.is_empty():
		return false
	var entry: MODEL.AnchorPoint = _prefit.pop_front()
	var found := FIT.find_mesh(pony_node, entry.region)
	if found != null:
		FIT.primitive(pony_node, entry.region,
			_body_position(pony_node, entry.region, entry.position),
			_fit_distance(pony_node, entry.region))
	return not _prefit.is_empty()


## True while this pony's background fit queue still has entries.
static func prefit_pending(pony_node: Node3D) -> bool:
	return is_instance_valid(pony_node) \
		and int(pony_node.get_instance_id()) == _prefit_pony_id and not _prefit.is_empty()


## Every authored area point this body can carry, both hands and every pose, deduplicated.
static func _area_points() -> Array[MODEL.AnchorPoint]:
	var out: Array[MODEL.AnchorPoint] = []
	var seen := {}
	var areas: Variant = _areas().get("areas", {})
	if areas is Dictionary:
		for slot_value: Variant in (areas as Dictionary).values():
			if not slot_value is Dictionary:
				continue
			var entry: Dictionary = slot_value
			var region := str(entry.get("region", "torso"))
			for side_name: String in ["left", "right"]:
				_push_point(out, seen, region, _entry_position(entry.get(side_name, {})))
	for path_id: String in ANCHORS_FILES.keys():
		var data := _authored(path_id)
		var sides: Array[String] = ["left", "right", "shared"]
		for side_name: String in sides:
			var side_data: Variant = data.get(side_name, {})
			if not side_data is Dictionary:
				continue
			for slot_value: Variant in (side_data as Dictionary).values():
				if not slot_value is Dictionary:
					continue
				var entry: Dictionary = slot_value
				_push_point(out, seen, str(entry.get("region", "torso")),
					_entry_position(entry))
	return out


static func _push_point(out: Array[MODEL.AnchorPoint], seen: Dictionary, region: String,
		point: Vector3) -> void:
	if not point.is_finite():
		return
	var key := "%s|%d|%d|%d" % [region, int(round(point.x * 1000.0)),
		int(round(point.y * 1000.0)), int(round(point.z * 1000.0))]
	if seen.has(key):
		return
	seen[key] = true
	out.append(MODEL.AnchorPoint.new(region, point))


func _update_belly_u() -> void:
	belly_u = 0.0
	for i in anchors.size():
		if anchors[i].id == "belly":
			belly_u = float(i) / maxf(float(anchors.size() - 1), 1.0)
			return


static func _authored(path_id: String) -> Dictionary:
	if _authored_data.has(path_id):
		var cached: Variant = _authored_data[path_id]
		return cached if cached is Dictionary else {}
	var file_path := str(ANCHORS_FILES.get(path_id, ANCHORS_FILES["one"]))
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_authored_data[path_id] = parsed
		return parsed
	return {}


## The marked caress areas, parsed once per process and shared.
static func _areas() -> Dictionary:
	if not _areas_data.is_empty():
		return _areas_data
	var file := FileAccess.open(AREAS_FILE, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_areas_data = parsed
		return _areas_data
	return {}


func _authored_ready(hand_side: MODEL.Side, path_id: String) -> bool:
	var data := _authored(path_id)
	var order: Variant = data.get("order", [])
	if not order is Array or (order as Array).is_empty():
		return false
	var shared: Variant = data.get("shared", {})
	var side_data: Variant = data.get(MODEL.side_key(hand_side))
	if not side_data is Dictionary:
		return false
	for slot: Variant in (order as Array):
		var key := str(slot)
		var found := (side_data as Dictionary).get(key) is Dictionary
		if not found and shared is Dictionary:
			found = (shared as Dictionary).get(key) is Dictionary
		if not found:
			return false
	return true


## Authored path from the Blender vertex groups: each slot is one fitted sphere.
func _build_authored(pony_node: Node3D, hand_side: MODEL.Side,
		path_id: String) -> Array[MODEL.Anchor]:
	var data := _authored(path_id)
	var order: Variant = data.get("order", [])
	var out: Array[MODEL.Anchor] = []
	if not order is Array or (order as Array).is_empty():
		return out
	var shared: Dictionary = {}
	if data.get("shared") is Dictionary:
		shared = data["shared"]
	var side_data: Variant = data.get(MODEL.side_key(hand_side))
	if not side_data is Dictionary:
		return out
	for slot_value: Variant in (order as Array):
		var slot := str(slot_value)
		var entry: Variant = (side_data as Dictionary).get(slot)
		if not entry is Dictionary:
			entry = shared.get(slot)
		if not entry is Dictionary:
			return []
		var region := str((entry as Dictionary).get("region", "torso"))
		var position := _entry_position(entry)
		if not position.is_finite():
			return []
		var anchor := _anchor(pony_node, region, position)
		if anchor == null:
			debug_notes.append("authored %s miss" % slot)
			return []
		_anchor_meta(anchor, slot, 0.0, _authored_roll(slot), region)
		out.append(anchor)
	return out


static func _authored_roll(slot: String) -> float:
	if slot in ["lower", "flank", "belly"]:
		return 1.0
	if slot in ["chest", "shoulder"]:
		return 0.7
	if slot == "neck":
		return 0.2
	return 0.0


static func _entry_position(entry: Variant) -> Vector3:
	if not entry is Dictionary:
		return Vector3.INF
	var raw: Variant = (entry as Dictionary).get("position", [])
	if not raw is Array or (raw as Array).size() < 3:
		return Vector3.INF
	return Vector3(float((raw as Array)[0]), float((raw as Array)[1]),
		float((raw as Array)[2]))


static func _anchor_meta(anchor: MODEL.Anchor, id: String, lateral: float, roll: float,
		region: String) -> void:
	anchor.id = id
	anchor.lateral = lateral
	anchor.roll = roll
	anchor.region = region


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * p1 + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _catmull_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t: float) -> Vector3:
	var t2 := t * t
	return 0.5 * ((-p0 + p2) + 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t
		+ 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2)
