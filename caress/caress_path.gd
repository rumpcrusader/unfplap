extends RefCounted
## Surface-anchored missionary caress path. The anchors are rest-space vertices on the visible
## body/head mesh; every tick they are skinned with the live skeleton, so the path follows the
## coat instead of guessing from bone origins and world up. No triangle query is needed for the
## single-point placement.

const SURFACE := preload("res://mods/unfplap/caress/caress_surface.gd")
const BELLY_U := 0.25
const CACHE_LIMIT := 16

static var _cache: Dictionary = {}
static var _cache_order: Array = []

var anchors: Array = []
var side := "right"
var valid := false
var path_len := 0.0


func build(pony: Variant, hand_side: String) -> bool:
	valid = false
	anchors.clear()
	path_len = 0.0
	side = hand_side
	if not is_instance_valid(pony):
		return false
	var body := SURFACE.find_mesh(pony, "body")
	if body.is_empty():
		return false
	var head := SURFACE.find_mesh(pony, "head")
	var body_mesh: MeshInstance3D = body["mesh"]
	var head_mesh: MeshInstance3D = head["mesh"] if not head.is_empty() else null
	var key := "%d|%d|%s" % [
		body_mesh.get_instance_id(),
		head_mesh.get_instance_id() if head_mesh != null else 0, hand_side]
	var cached: Variant = _cache.get(key)
	if cached is Array and not (cached as Array).is_empty():
		var cache_ok := true
		for cached_anchor: Dictionary in (cached as Array):
			if not is_instance_valid(cached_anchor.get("skeleton")):
				cache_ok = false
				break
		if cache_ok:
			anchors = (cached as Array).duplicate()
			valid = anchors.size() >= 3
			return valid
	anchors = _build_anchors(pony, body, head, hand_side)
	if anchors.size() < 3:
		return false
	_cache[key] = anchors.duplicate()
	_cache_order.append(key)
	while _cache_order.size() > CACHE_LIMIT:
		var old: Variant = _cache_order.pop_front()
		_cache.erase(old)
	valid = true
	return true


## Skin the stored anchors and sample the path. `along_m` moves along the path in metres, and
## `body_right` is the pony's world right used to choose the hand-side lateral axis.
func sample(lean: float, along_m: float, body_right: Vector3) -> Dictionary:
	var world := skinned()
	if world.size() < 3:
		return {}
	var length := path_length(world)
	path_len = length
	return sample_world(world, u_for(lean, along_m / maxf(length, 0.05)), side, body_right)


static func u_for(lean: float, along_u: float) -> float:
	var u := BELLY_U
	if lean >= 0.0:
		u = lerpf(BELLY_U, 1.0, clampf(lean, 0.0, 1.0))
	else:
		u = lerpf(BELLY_U, 0.0, clampf(-lean, 0.0, 1.0))
	return clampf(u + along_u, 0.0, 1.0)


## Pure sampler over already-skinned anchors: {position, normal, lateral, roll, region}.
static func sample_world(world: Array, u: float, hand_side: String,
		body_right: Vector3) -> Dictionary:
	var count := world.size() - 1
	if count < 1:
		return {}
	var f := clampf(u, 0.0, 1.0) * count
	var i := int(floor(f))
	var t := f - i
	if i >= count:
		i = count - 1
		t = 1.0
	var p0 := _point(world[maxi(i - 1, 0)])
	var p1 := _point(world[i])
	var p2 := _point(world[mini(i + 1, count)])
	var p3 := _point(world[mini(i + 2, count)])
	var point := _catmull(p0, p1, p2, p3, t)
	var tangent := _catmull_tangent(p0, p1, p2, p3, t)
	if tangent.length_squared() < 0.000001:
		tangent = p2 - p1
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.UP
	tangent = tangent.normalized()
	var a1: Dictionary = world[i]
	var a2: Dictionary = world[mini(i + 1, count)]
	var n1: Vector3 = a1["normal"]
	var n2: Vector3 = a2["normal"]
	var normal := n1.lerp(n2, t)
	if normal.length_squared() < 0.000001:
		normal = n1
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
	if hand_side == "left":
		wanted = -wanted
	if lateral.dot(wanted) < 0.0:
		lateral = -lateral
	return {
		"u": u,
		"point": point,
		"normal": normal,
		"finger": tangent,
		"side": lateral,
		"lateral": lerpf(float(a1["lateral"]), float(a2["lateral"]), t),
		"roll": lerpf(float(a1["roll"]), float(a2["roll"]), t),
		"region": str(a1["region"]) if t < 0.5 else str(a2["region"]),
	}


func skinned() -> Array:
	var world: Array = []
	for anchor: Dictionary in anchors:
		var sk: Skeleton3D = anchor.get("skeleton")
		if not is_instance_valid(sk):
			return []
		var base := sk.global_transform
		var point := Vector3.ZERO
		var normal := Vector3.ZERO
		var rest_position: Vector3 = anchor["position"]
		var rest_normal: Vector3 = anchor["normal"]
		for influence: Dictionary in anchor.get("influences", []):
			var bone := int(influence.get("bone", -1))
			if bone < 0:
				continue
			var bind: Transform3D = influence["bind"]
			var transform: Transform3D = base * sk.get_bone_global_pose(bone) * bind
			var weight := float(influence.get("weight", 0.0))
			point += (transform * rest_position) * weight
			normal += (transform.basis * rest_normal) * weight
		if normal.length_squared() < 0.000001:
			normal = Vector3.UP
		world.append({
			"id": str(anchor.get("id", "")),
			"position": point,
			"normal": normal.normalized(),
			"lateral": float(anchor.get("lateral", 1.0)),
			"roll": float(anchor.get("roll", 1.0)),
			"region": str(anchor.get("region", "torso")),
		})
	return world


static func path_length(world: Array) -> float:
	var length := 0.0
	for i in range(1, world.size()):
		length += _point(world[i]).distance_to(_point(world[i - 1]))
	return length


func _build_anchors(pony: Variant, body: Dictionary, head: Dictionary,
		hand_side: String) -> Array:
	var sk: Skeleton3D = body["skeleton"]
	var spine2: Variant = _rest(sk, ["pony_spine2", "pony_spine1", "pony_hips"])
	var spine3: Variant = _rest(sk, ["pony_spine3", "pony_neck1"])
	var neck1: Variant = _rest(sk, ["pony_neck1", "pony_spine3"])
	var hips_rest: Variant = _rest(sk, ["pony_hips", "pony_spine1"])
	if spine2 == null:
		return []
	var belly_origin: Vector3 = (spine2 as Transform3D).origin
	var torso_forward := Vector3.FORWARD
	if hips_rest != null:
		var hips_origin: Vector3 = (hips_rest as Transform3D).origin
		if hips_origin.distance_squared_to(belly_origin) > 0.0001:
			torso_forward = (belly_origin - hips_origin).normalized()
	var chest_origin := belly_origin
	if spine3 != null:
		chest_origin = (spine3 as Transform3D).origin
	var neck_t: Transform3D = spine2 as Transform3D
	if neck1 != null:
		neck_t = neck1 as Transform3D
	var side_sign := 1.0 if hand_side == "right" else -1.0
	var down := -Vector3.UP
	var out: Array = []
	var body_surface: Variant = SURFACE.new()
	if bool(body_surface.call("ensure", pony, "torso")):
		var body_source: Dictionary = body_surface.get("source")
		var body_faces := _source_faces(body_source)
		if not body_faces.is_empty():
			var body_tri := TriangleMesh.new()
			body_tri.create_from_faces(body_faces)
			var body_specs := [
				{"id": "lower", "inside": belly_origin - torso_forward * 0.15,
					"out": down, "lateral": 1.0, "roll": 1.0},
				{"id": "belly", "inside": belly_origin, "out": down,
					"lateral": 1.0, "roll": 1.0},
				{"id": "chest", "inside": chest_origin,
					"out": (down + torso_forward * 0.35).normalized(),
					"lateral": 0.8, "roll": 0.7},
				{"id": "neck", "inside": neck_t.origin,
					"out": _lateral_axis(neck_t) * side_sign,
					"lateral": 0.3, "roll": 0.2},
			]
			for spec: Dictionary in body_specs:
				var inside: Vector3 = spec["inside"]
				var outward: Vector3 = spec["out"]
				var anchor := _ray_anchor(body_source, body_tri, sk,
					inside + outward * 1.0, inside - outward * 1.0)
				if anchor.is_empty():
					continue
				anchor["id"] = spec["id"]
				anchor["lateral"] = spec["lateral"]
				anchor["roll"] = spec["roll"]
				anchor["region"] = "torso"
				out.append(anchor)
	if not head.is_empty():
		var hsk: Skeleton3D = head["skeleton"]
		var head_t: Variant = _rest(hsk, ["mHead", "pony_head", "Head"])
		if head_t != null:
			var head_surface: Variant = SURFACE.new()
			if bool(head_surface.call("ensure", pony, "head")):
				var head_source: Dictionary = head_surface.get("source")
				var head_faces := _source_faces(head_source)
				if not head_faces.is_empty():
					var head_tri := TriangleMesh.new()
					head_tri.create_from_faces(head_faces)
					var head_origin: Vector3 = (head_t as Transform3D).origin
					var head_out := _lateral_axis(head_t as Transform3D) * side_sign
					var anchor := _ray_anchor(head_source, head_tri, hsk,
						head_origin + head_out * 0.6, head_origin - head_out * 0.6)
					if not anchor.is_empty():
						anchor["id"] = "cheek"
						anchor["lateral"] = 0.0
						anchor["roll"] = 0.0
						anchor["region"] = "head"
						out.append(anchor)
	return out


func _source_faces(source: Dictionary) -> PackedVector3Array:
	var vertices: Array = source.get("vertices", [])
	var indices: PackedInt32Array = source.get("indices", PackedInt32Array())
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		var index := indices[i]
		if index < 0 or index >= vertices.size():
			faces[i] = Vector3.ZERO
			continue
		faces[i] = vertices[index]["position"]
	return faces


## Cast a rest-space ray from outside the body toward the inside. The first triangle is the
## desired near surface and its normal faces the ray origin, so the side and normal are explicit.
func _ray_anchor(source: Dictionary, tri: TriangleMesh, skeleton: Skeleton3D,
		outer: Vector3, inner: Vector3) -> Dictionary:
	var hit: Variant = tri.intersect_segment(outer, inner)
	if not hit is Dictionary or (hit as Dictionary).is_empty():
		return {}
	var indices: PackedInt32Array = source.get("indices", PackedInt32Array())
	var vertices: Array = source.get("vertices", [])
	var face := int((hit as Dictionary).get("face_index", -1)) * 3
	if face < 0 or face + 2 >= indices.size():
		return {}
	var hit_point: Vector3 = (hit as Dictionary).get("position", Vector3.ZERO)
	var best_index := -1
	var best_distance := INF
	for j in 3:
		var index := indices[face + j]
		if index < 0 or index >= vertices.size():
			continue
		var point: Vector3 = vertices[index]["position"]
		var distance := point.distance_squared_to(hit_point)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		return {}
	var vertex: Dictionary = vertices[best_index]
	var point: Vector3 = vertex["position"]
	var normal: Vector3 = vertex["normal"]
	if normal.length_squared() < 0.5:
		normal = (hit as Dictionary).get("normal", Vector3.UP)
	if normal.dot(outer - point) < 0.0:
		normal = -normal
	var influences: Array = []
	var bindings: Array = source.get("bindings", [])
	for influence: Vector2 in vertex["influence"]:
		var binding: Dictionary = bindings[int(influence.x)]
		influences.append({
			"bone": int(binding["bone"]),
			"bind": binding["bind"],
			"weight": float(influence.y),
		})
	return {
		"skeleton": skeleton,
		"position": point,
		"normal": normal,
		"influences": influences,
	}


func _rest(skeleton: Skeleton3D, names: Array) -> Variant:
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			return skeleton.get_bone_global_rest(bone)
	return null


static func _lateral_axis(transform: Transform3D) -> Vector3:
	var axis := transform.basis.x.normalized()
	if axis.dot(Vector3.RIGHT) < 0.0:
		axis = -axis
	return axis


static func _point(anchor: Dictionary) -> Vector3:
	var point: Vector3 = anchor["position"]
	return point


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
