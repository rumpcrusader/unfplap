extends RefCounted
## Prototype: find the first intersection of the hair segment `mTail1 -> mPelvis` with the
## pony's coat. The coat is CPU-skinned for a small patch around the segment, so the result
## follows the current pose instead of the rest mesh.

const BODY_MESH := "MareBody"
## Rest-space radius around the `mTail1 -> mPelvis` segment that is skinned and tested.
const PATCH_RADIUS := 0.06
## Wider fallback used only when the tight patch misses.
const FALLBACK_RADIUS := 0.12

static var _cache: Dictionary = {}


static func point(pony: Node) -> Dictionary:
	var setup := _setup(pony)
	if setup.is_empty():
		return {}
	var skeleton: Skeleton3D = setup["skeleton"]
	var transforms: Array[Transform3D] = []
	transforms.resize(skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		transforms[i] = skeleton.get_bone_global_pose(i)
	var base := skeleton.global_transform
	var hit := _intersect(
		_triangles(setup["body"], skeleton, setup["hair"], setup["tail1_bone"],
			setup["pelvis_bone"], PATCH_RADIUS),
		transforms, base, setup["tail1"], setup["direction"], setup["length"])
	if hit.is_empty():
		hit = _intersect(
			_triangles(setup["body"], skeleton, setup["hair"], setup["tail1_bone"],
				setup["pelvis_bone"], FALLBACK_RADIUS),
			transforms, base, setup["tail1"], setup["direction"], setup["length"])
	if hit.is_empty():
		return {"ok": false, "position": Vector3.INF}
	return {
		"ok": true,
		"position": hit["position"],
		"triangle": hit["triangle"],
		"tail1": setup["tail1"],
		"pelvis": setup["pelvis"],
		"distance": setup["tail1"].distance_to(hit["position"]),
	}


## Fast path: test only the triangle that produced the previous hit. The follower calls this
## every frame and falls back to `point()` when the intersection leaves that triangle.
static func point_triangle(pony: Node, triangle: Array) -> Dictionary:
	if triangle.size() != 3:
		return {}
	var setup := _setup(pony)
	if setup.is_empty():
		return {}
	var skeleton: Skeleton3D = setup["skeleton"]
	var a := _skinned_single(skeleton, triangle[0])
	var b := _skinned_single(skeleton, triangle[1])
	var c := _skinned_single(skeleton, triangle[2])
	var result: Variant = Geometry3D.ray_intersects_triangle(
		setup["tail1"], setup["direction"], a, b, c)
	if result is Vector3:
		var distance := (setup["tail1"] as Vector3).distance_to(result)
		if distance <= float(setup["length"]):
			return {
				"ok": true,
				"position": result,
				"triangle": triangle,
				"tail1": setup["tail1"],
				"pelvis": setup["pelvis"],
				"distance": distance,
			}
	return {}


static func _setup(pony: Node) -> Dictionary:
	if not is_instance_valid(pony):
		return {}
	var hair: Variant = pony.get("hair_skeleton")
	var model: Variant = pony.get("_model")
	if not hair is Skeleton3D or not model is Node:
		return {}
	var hair_sk := hair as Skeleton3D
	var body := (model as Node).find_child(BODY_MESH, true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.mesh == null or body.skin == null:
		return {}
	var skeleton := body.get_node_or_null(body.skeleton) as Skeleton3D
	if not is_instance_valid(skeleton):
		return {}
	var tail1_bone := hair_sk.find_bone("mTail1")
	var pelvis_bone := hair_sk.find_bone("mPelvis")
	if tail1_bone < 0 or pelvis_bone < 0:
		return {}
	var tail1: Vector3 = hair_sk.global_transform \
		* hair_sk.get_bone_global_pose(tail1_bone).origin
	var pelvis: Vector3 = hair_sk.global_transform \
		* hair_sk.get_bone_global_pose(pelvis_bone).origin
	var direction := pelvis - tail1
	var length := direction.length()
	if length < 0.0001:
		return {}
	return {
		"hair": hair_sk,
		"body": body,
		"skeleton": skeleton,
		"tail1_bone": tail1_bone,
		"pelvis_bone": pelvis_bone,
		"tail1": tail1,
		"pelvis": pelvis,
		"direction": direction,
		"length": length,
	}


static func _intersect(triangles: Array, transforms: Array[Transform3D], base: Transform3D,
		tail1: Vector3, direction: Vector3, length: float) -> Dictionary:
	var best := INF
	var hit := Vector3.INF
	var best_triangle: Array = []
	for triangle: Array in triangles:
		var a := _skinned(transforms, base, triangle[0])
		var b := _skinned(transforms, base, triangle[1])
		var c := _skinned(transforms, base, triangle[2])
		var result: Variant = Geometry3D.ray_intersects_triangle(tail1, direction, a, b, c)
		if result is Vector3:
			var distance := tail1.distance_to(result)
			if distance <= length and distance < best:
				best = distance
				hit = result
				best_triangle = triangle
	if not hit.is_finite():
		return {}
	return {"position": hit, "triangle": best_triangle}


static func _triangles(body: MeshInstance3D, skeleton: Skeleton3D, hair: Skeleton3D,
		tail1_bone: int, pelvis_bone: int, radius: float) -> Array:
	var key := "%d:%d:%0.3f" % [body.mesh.get_instance_id(), skeleton.get_instance_id(), radius]
	if _cache.has(key):
		return _cache[key]
	var built := _build(body, skeleton, hair, tail1_bone, pelvis_bone, radius)
	_cache[key] = built
	return built


static func _build(body: MeshInstance3D, skeleton: Skeleton3D, hair: Skeleton3D,
		tail1_bone: int, pelvis_bone: int, radius: float) -> Array:
	var tail1_rest: Vector3 = hair.global_transform * hair.get_bone_global_rest(tail1_bone).origin
	var pelvis_rest: Vector3 = hair.global_transform * hair.get_bone_global_rest(pelvis_bone).origin
	var segment_a := skeleton.global_transform.affine_inverse() * tail1_rest
	var segment_b := skeleton.global_transform.affine_inverse() * pelvis_rest
	var triangles: Array = []
	for surface in body.mesh.get_surface_count():
		var arrays: Array = body.mesh.surface_get_arrays(surface)
		var vertices_v: Variant = arrays[Mesh.ARRAY_VERTEX]
		var indices_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var ids_v: Variant = arrays[Mesh.ARRAY_BONES]
		var weights_v: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if not (vertices_v is PackedVector3Array) or not (indices_v is PackedInt32Array) \
				or not (ids_v is PackedInt32Array) or not (weights_v is PackedFloat32Array):
			continue
		var vertices: PackedVector3Array = vertices_v
		var indices: PackedInt32Array = indices_v
		var ids: PackedInt32Array = ids_v
		var weights: PackedFloat32Array = weights_v
		var stride := ids.size() / maxi(1, vertices.size())
		var seen: Dictionary = {}
		for t in range(0, indices.size(), 3):
			var ia := indices[t]
			var ib := indices[t + 1]
			var ic := indices[t + 2]
			if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() \
					or ib >= vertices.size() or ic >= vertices.size():
				continue
			var centroid := (vertices[ia] + vertices[ib] + vertices[ic]) / 3.0
			if _distance_to_segment(centroid, segment_a, segment_b) > radius:
				continue
			var triangle: Array = []
			for index: int in [ia, ib, ic]:
				if not seen.has(index):
					seen[index] = _vertex(vertices[index], ids, weights, stride, index, body, skeleton)
				triangle.append(seen[index])
			triangles.append(triangle)
	return triangles


static func _vertex(position: Vector3, ids: PackedInt32Array, weights: PackedFloat32Array,
		stride: int, index: int, body: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var influences: Array = []
	for slot in stride:
		var at := index * stride + slot
		var weight := weights[at]
		if weight <= 0.0:
			continue
		var bind := ids[at]
		var bone_name := String(body.skin.get_bind_name(bind))
		var bone := skeleton.find_bone(bone_name) if not bone_name.is_empty() else -1
		if bone < 0:
			bone = body.skin.get_bind_bone(bind)
		if bone < 0:
			continue
		influences.append({
			"bone": bone,
			"bind": body.skin.get_bind_pose(bind),
			"weight": weight,
		})
	return {"position": position, "influences": influences}


static func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _skinned(transforms: Array[Transform3D], base: Transform3D, vertex: Dictionary) -> Vector3:
	var point := Vector3.ZERO
	for influence_v: Variant in vertex.get("influences", []):
		var influence: Dictionary = influence_v
		var bone := int(influence.get("bone", -1))
		if bone < 0 or bone >= transforms.size():
			continue
		point += (transforms[bone]
			* (influence.get("bind", Transform3D.IDENTITY) as Transform3D)
			* (vertex.get("position", Vector3.ZERO) as Vector3)) \
			* float(influence.get("weight", 0.0))
	return base * point


static func _skinned_single(skeleton: Skeleton3D, vertex: Dictionary) -> Vector3:
	var point := Vector3.ZERO
	for influence_v: Variant in vertex.get("influences", []):
		var influence: Dictionary = influence_v
		var bone := int(influence.get("bone", -1))
		if bone < 0:
			continue
		point += (skeleton.get_bone_global_pose(bone)
			* (influence.get("bind", Transform3D.IDENTITY) as Transform3D)
			* (vertex.get("position", Vector3.ZERO) as Vector3)) \
			* float(influence.get("weight", 0.0))
	return skeleton.global_transform * point
