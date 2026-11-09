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
	anchors = _build_anchors(body, head, hand_side)
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
	var world := _skin_anchors()
	if world.size() < 3:
		return {}
	var length := 0.0
	for i in range(1, world.size()):
		length += _point(world[i]).distance_to(_point(world[i - 1]))
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
		"point": point,
		"normal": normal,
		"finger": tangent,
		"side": lateral,
		"lateral": lerpf(float(a1["lateral"]), float(a2["lateral"]), t),
		"roll": lerpf(float(a1["roll"]), float(a2["roll"]), t),
		"region": str(a1["region"]) if t < 0.5 else str(a2["region"]),
	}


func _skin_anchors() -> Array:
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
			"position": point,
			"normal": normal.normalized(),
			"lateral": float(anchor.get("lateral", 1.0)),
			"roll": float(anchor.get("roll", 1.0)),
			"region": str(anchor.get("region", "torso")),
		})
	return world


func _build_anchors(body: Dictionary, head: Dictionary, hand_side: String) -> Array:
	var sk: Skeleton3D = body["skeleton"]
	var body_mesh: MeshInstance3D = body["mesh"]
	var spine2: Variant = _rest(sk, ["pony_spine2", "pony_spine1", "pony_hips"])
	var spine3: Variant = _rest(sk, ["pony_spine3", "pony_neck1"])
	var neck1: Variant = _rest(sk, ["pony_neck1", "pony_spine3"])
	var hips_rest: Variant = _rest(sk, ["pony_hips", "pony_spine1"])
	if spine2 == null:
		return []
	var lower_t: Transform3D = spine2
	var belly_origin := lower_t.origin
	# The spine sits along the back. Bias the body anchors toward the underside/barrel so the
	# nearest vertex is the belly or chest, not the back. The lower anchor also sits a little
	# toward the tail so the path tangent points toward her head.
	var torso_forward := Vector3.FORWARD
	if hips_rest != null:
		var hips_origin: Vector3 = (hips_rest as Transform3D).origin
		if hips_origin.distance_squared_to(belly_origin) > 0.0001:
			torso_forward = (belly_origin - hips_origin).normalized()
	var belly := belly_origin - Vector3.UP * 0.22
	var chest := belly_origin - Vector3.UP * 0.22
	if spine3 != null:
		chest = (spine3 as Transform3D).origin - Vector3.UP * 0.18
	var neck_t: Transform3D = lower_t
	if neck1 != null:
		neck_t = neck1 as Transform3D
	var side_sign := 1.0 if hand_side == "right" else -1.0
	var neck := neck_t.origin + _lateral_axis(neck_t) * (side_sign * 0.09)
	var lower := belly_origin - torso_forward * 0.15 - Vector3.UP * 0.28
	var specs := [
		{"target": lower, "lateral": 1.0, "roll": 1.0},
		{"target": belly, "lateral": 1.0, "roll": 1.0},
		{"target": chest, "lateral": 0.8, "roll": 0.7},
		{"target": neck, "lateral": 0.3, "roll": 0.2},
	]
	var out: Array = []
	for spec: Dictionary in specs:
		var target: Vector3 = spec["target"]
		var anchor := _nearest(body_mesh, sk, target, "torso")
		if anchor.is_empty():
			continue
		anchor["lateral"] = spec["lateral"]
		anchor["roll"] = spec["roll"]
		anchor["region"] = "torso"
		out.append(anchor)
	if not head.is_empty():
		var hsk: Skeleton3D = head["skeleton"]
		var hm: MeshInstance3D = head["mesh"]
		var head_t: Variant = _rest(hsk, ["mHead", "pony_head", "Head"])
		if head_t != null:
			var cheek := (head_t as Transform3D).origin \
				+ _lateral_axis(head_t as Transform3D) * (side_sign * 0.10)
			var anchor := _nearest(hm, hsk, cheek, "head")
			if not anchor.is_empty():
				anchor["lateral"] = 0.0
				anchor["roll"] = 0.0
				anchor["region"] = "head"
				out.append(anchor)
	return out


func _nearest(mesh: MeshInstance3D, skeleton: Skeleton3D, target: Vector3,
		region: String) -> Dictionary:
	var skin: Skin = mesh.skin
	if skin == null or mesh.mesh == null:
		return {}
	var role := "head_Head" if region == "head" else "body"
	var best_distance := INF
	var best: Dictionary = {}
	for surface_index in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.is_empty():
			continue
		var stride := bones.size() / vertices.size()
		for id in vertices.size():
			var best_bind := -1
			var best_weight := 0.0
			for k in stride:
				var at := id * stride + k
				var weight := weights[at]
				if weight > best_weight:
					best_weight = weight
					best_bind = bones[at]
			if best_bind < 0 or best_bind >= skin.get_bind_count():
				continue
			var bone := skin.get_bind_bone(best_bind)
			var bind_name := String(skin.get_bind_name(best_bind))
			if not bind_name.is_empty():
				var found := skeleton.find_bone(bind_name)
				if found >= 0:
					bone = found
			if bone < 0:
				continue
			# Materialised vertices may have no vertex normal; the bind pose still gives the
			# rest position needed for the nearest search.
			var bone_name := skeleton.get_bone_name(bone)
			if not SURFACE.region_allowed(SURFACE.region_for(role, bone_name), region):
				continue
			var rest: Transform3D = skeleton.get_bone_global_rest(bone) \
				* skin.get_bind_pose(best_bind)
			var point: Vector3 = rest * vertices[id]
			var distance := point.distance_squared_to(target)
			if distance >= best_distance:
				continue
			best_distance = distance
			var mesh_normal: Vector3 = normals[id] if id < normals.size() else Vector3.UP
			var rest_normal: Vector3 = (rest.basis * mesh_normal).normalized()
			if rest_normal.dot(point - target) < 0.0:
				mesh_normal = -mesh_normal
			best = {
				"skeleton": skeleton,
				"position": vertices[id],
				"normal": mesh_normal,
				"influences": _influences(skin, skeleton, bones, weights, stride, id),
			}
	return best


func _influences(skin: Skin, skeleton: Skeleton3D, bones: PackedInt32Array,
		weights: PackedFloat32Array, stride: int, id: int) -> Array:
	var out: Array = []
	for k in stride:
		var at := id * stride + k
		var weight := weights[at]
		if weight <= 0.0:
			continue
		var bind := bones[at]
		if bind < 0 or bind >= skin.get_bind_count():
			continue
		var bone := skin.get_bind_bone(bind)
		var bind_name := String(skin.get_bind_name(bind))
		if not bind_name.is_empty():
			var found := skeleton.find_bone(bind_name)
			if found >= 0:
				bone = found
		if bone < 0:
			continue
		out.append({"bone": bone, "bind": skin.get_bind_pose(bind), "weight": weight})
	return out


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
