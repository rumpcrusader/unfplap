extends RefCounted
## Posed triangle contact surface for the caress. It builds a small, region-filtered patch of
## the visible coat around a body anchor, skins it from the live skeleton, and answers closest
## point/normal queries. The capsule hulls remain a broadphase/fallback; they are not the final
## contact. The source arrays are shared per mesh/skin/region/window; the posed positions belong
## to one patch.

const CACHE_LIMIT := 12
const UPDATE_MS := 33

static var _source_cache: Dictionary = {}

var source: Dictionary = {}
var skeleton: Skeleton3D
var faces := PackedVector3Array()
var vertex_normals := PackedVector3Array()
var build_us := 0
var query_us := 0
var source_key := ""

var _bindings: Array = []
var _transforms: Array[Transform3D] = []
var _rest_positions := PackedVector3Array()
var _rest_normals := PackedVector3Array()
var _offsets := PackedInt32Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _indices := PackedInt32Array()
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _last_update := -1
var _cache_order: Array = []


## Build/refresh a patch for a region around `center_world`. `region` is "torso", "neck",
## "head" or "body". Returns false when the pony/rig/region is unavailable.
func ensure(pony: Variant, region: String, center_world: Vector3,
		radius := 0.45) -> bool:
	if not is_instance_valid(pony) or not center_world.is_finite():
		return false
	var found := _find_mesh(pony, region)
	if found.is_empty():
		return false
	var mesh: MeshInstance3D = found["mesh"]
	var sk: Variant = found["skeleton"]
	if not sk is Skeleton3D:
		return false
	skeleton = sk as Skeleton3D
	var local_center := skeleton.global_transform.affine_inverse() * center_world
	var key := "%d|%d|%s|%d|%d|%d" % [
		mesh.get_instance_id(), skeleton.get_instance_id(), region,
		int(round(local_center.x * 10.0)), int(round(local_center.y * 10.0)),
		int(round(local_center.z * 10.0))]
	if key != source_key or source.is_empty():
		source_key = key
		var cache_key := "%d|%d|%s|%d|%d|%d|%d|%d" % [
			mesh.mesh.get_instance_id(), mesh.skin.get_instance_id() if mesh.skin != null else 0,
			region, int(radius * 100.0),
			int(round(local_center.x * 10.0)), int(round(local_center.y * 10.0)),
			int(round(local_center.z * 10.0)), 0]
		if _source_cache.has(cache_key):
			source = _source_cache[cache_key]
		else:
			source = _gather(mesh, region, local_center, radius)
			if source.is_empty():
				return false
			_source_cache[cache_key] = source
			_cache_order.append(cache_key)
			while _cache_order.size() > CACHE_LIMIT:
				var old: Variant = _cache_order.pop_front()
				_source_cache.erase(old)
		_flatten()
		_last_update = -1
	return not source.is_empty()


func update_pose(force := false) -> void:
	if source.is_empty() or not is_instance_valid(skeleton):
		return
	var now := Time.get_ticks_msec()
	if not force and _last_update >= 0 and now - _last_update < UPDATE_MS:
		return
	var started := Time.get_ticks_usec()
	var base := skeleton.global_transform
	var changed := _transforms.size() != _bindings.size()
	if not changed:
		for i in _bindings.size():
			var binding: Dictionary = _bindings[i]
			var bone := int(binding["bone"])
			if bone < 0:
				changed = true
				break
			var t: Transform3D = base * skeleton.get_bone_global_pose(bone) \
				* (binding["bind"] as Transform3D)
			if not t.is_equal_approx(_transforms[i]):
				_transforms[i] = t
				changed = true
	if not changed and not force:
		return
	if _transforms.size() != _bindings.size():
		_transforms.resize(_bindings.size())
	for i in _bindings.size():
		var binding: Dictionary = _bindings[i]
		var bone := int(binding["bone"])
		_transforms[i] = base * skeleton.get_bone_global_pose(bone) \
			* (binding["bind"] as Transform3D)
	for i in _rest_positions.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var rest := _rest_positions[i]
		var normal := _rest_normals[i]
		for k in range(_offsets[i], _offsets[i + 1]):
			var pose: Transform3D = _transforms[_bones[k]]
			var weight := _weights[k]
			p += (pose * rest) * weight
			n += (pose.basis * normal) * weight
		_positions[i] = p
		_normals[i] = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	faces.resize(_indices.size())
	vertex_normals.resize(_indices.size())
	for i in _indices.size():
		var v := _indices[i]
		faces[i] = _positions[v]
		vertex_normals[i] = _normals[v]
	_last_update = now
	build_us = Time.get_ticks_usec() - started


## Closest point on the posed patch. Returns {} when the patch is empty. `inside` is true when
## the query is behind the surface normal at the closest point.
func closest(point: Vector3) -> Dictionary:
	if faces.is_empty():
		return {}
	var started := Time.get_ticks_usec()
	var best := INF
	var best_point := Vector3.ZERO
	var best_normal := Vector3.ZERO
	var best_index := -1
	var best_bary := Vector3.ZERO
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var p := _closest_on_triangle(a, b, c, point)
		var d := p.distance_squared_to(point)
		if d >= best:
			continue
		best = d
		best_point = p
		best_index = i
		var bary := _triangle_barycentric(a, b, c, p)
		best_bary = bary
		var normal := vertex_normals[i] * bary.x + vertex_normals[i + 1] * bary.y \
			+ vertex_normals[i + 2] * bary.z
		if normal.length_squared() < 0.000001:
			normal = (b - a).cross(c - a)
		best_normal = normal.normalized()
	if best_index < 0:
		return {}
	query_us = Time.get_ticks_usec() - started
	return {
		"point": best_point,
		"normal": best_normal,
		"distance": sqrt(best),
		"inside": (point - best_point).dot(best_normal) < 0.0,
		"bary": best_bary,
	}


func _flatten() -> void:
	_rest_positions = PackedVector3Array()
	_rest_normals = PackedVector3Array()
	_offsets = PackedInt32Array()
	_bones = PackedInt32Array()
	_weights = PackedFloat32Array()
	_indices = PackedInt32Array()
	_positions = PackedVector3Array()
	_normals = PackedVector3Array()
	_bindings = []
	var bind_map := {}
	for b: Dictionary in source.get("bindings", []):
		bind_map[int(b["index"])] = _bindings.size()
		_bindings.append({"bone": int(b["bone"]), "bind": b["bind"]})
	var vertices: Array = source.get("vertices", [])
	for v: Dictionary in vertices:
		_rest_positions.append(v["position"])
		_rest_normals.append(v["normal"])
		_offsets.append(_bones.size())
		for influence: Vector2 in v["influence"]:
			var mapped: Variant = bind_map.get(int(influence.x))
			if mapped == null:
				continue
			_bones.append(int(mapped))
			_weights.append(float(influence.y))
	_offsets.append(_bones.size())
	_indices = source.get("indices", PackedInt32Array())
	_positions.resize(_rest_positions.size())
	_normals.resize(_rest_positions.size())
	faces = PackedVector3Array()
	vertex_normals = PackedVector3Array()
	_transforms.clear()
	_last_update = -1


func _find_mesh(pony: Variant, region: String) -> Dictionary:
	if region == "head":
		var head: Variant = pony.get("head")
		if head == null:
			return {}
		var model: Node = head.get("model")
		var sk: Variant = head.get("skeleton")
		if not is_instance_valid(model) or not sk is Skeleton3D:
			return {}
		var mesh := model.find_child("Head", true, false) as MeshInstance3D
		if mesh == null:
			return {}
		return {"mesh": mesh, "skeleton": sk}
	var model: Node = pony.get("_model")
	if not is_instance_valid(model):
		return {}
	var body := model.find_child("MareBody", true, false) as MeshInstance3D
	if body == null:
		return {}
	var sk: Variant = body.get_node_or_null(body.skeleton)
	if not sk is Skeleton3D:
		sk = pony.get("skeleton")
	return {"mesh": body, "skeleton": sk}


func _gather(mesh: MeshInstance3D, region: String, center: Vector3,
		radius: float) -> Dictionary:
	var skin: Skin = mesh.skin
	if skin == null or mesh.mesh == null:
		return {}
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if skeleton == null:
		skeleton = mesh.get_parent() as Skeleton3D
	if skeleton == null:
		return {}
	var vertices: Array = []
	var indices := PackedInt32Array()
	var bindings := {}
	var role := "body"
	if region == "head":
		role = "head_Head"
	var r2 := radius * radius
	for si in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var ab: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var aw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if ids.is_empty():
			continue
		var stride: int = ab.size() / vs.size() if vs.size() > 0 else 0
		var mapped := {}
		for t in range(0, ids.size(), 3):
			var centroid := (vs[ids[t]] + vs[ids[t + 1]] + vs[ids[t + 2]]) / 3.0
			if centroid.distance_squared_to(center) > r2:
				continue
			var hit := false
			for j in 3:
				var id := ids[t + j]
				var bone := _dominant_bone(id, ab, aw, stride, skin, skeleton)
				if _region_allowed(_region_for(role, bone), region):
					hit = true
					break
			if not hit:
				continue
			for j in 3:
				var id := ids[t + j]
				if not mapped.has(id):
					var influence: Array = []
					for k in stride:
						var at := id * stride + k
						var w: float = aw[at]
						if w <= 0.0:
							continue
						var bind := ab[at]
						if bind < 0 or bind >= skin.get_bind_count():
							continue
						if not bindings.has(bind):
							var bone_id := skin.get_bind_bone(bind)
							var bone_name := String(skin.get_bind_name(bind))
							if not bone_name.is_empty():
								bone_id = skeleton.find_bone(bone_name)
							bindings[bind] = {
								"bone": bone_id,
								"bind": skin.get_bind_pose(bind),
								"index": bindings.size(),
							}
						influence.append(Vector2(bindings[bind]["index"], w))
					mapped[id] = vertices.size()
					vertices.append({
						"position": vs[id],
						"normal": ns[id] if id < ns.size() else Vector3.UP,
						"influence": influence,
					})
				indices.append(mapped[id])
	return {"vertices": vertices, "indices": indices, "bindings": bindings.values()}


func _dominant_bone(id: int, ab: PackedInt32Array, aw: PackedFloat32Array,
		stride: int, skin: Skin, rig: Skeleton3D) -> String:
	var best := 0.0
	var best_bind := -1
	for k in stride:
		var at := id * stride + k
		if at >= ab.size() or at >= aw.size():
			continue
		if aw[at] > best:
			best = aw[at]
			best_bind = ab[at]
	if best_bind < 0 or best_bind >= skin.get_bind_count():
		return ""
	var name := String(skin.get_bind_name(best_bind))
	if name.is_empty() and is_instance_valid(rig):
		var bone := skin.get_bind_bone(best_bind)
		name = rig.get_bone_name(bone)
	return name


static func _region_for(role: String, bone: String) -> String:
	if role.begins_with("head"):
		return "head"
	if bone.begins_with("pony_neck") or bone == "pony_head":
		return "neck"
	if bone == "pony_spine3":
		return "withers"
	if bone in ["pony_spine1", "pony_spine2"]:
		return "back"
	if bone == "pony_hips":
		return "rump"
	if bone.begins_with("pony_shoulder"):
		return "shoulder"
	if bone.begins_with("pony_flank"):
		return "flank"
	if "femur" in bone or "tibia" in bone or "legLower" in bone or "hoof" in bone \
			or "tarsal" in bone or "upperArm" in bone or "lowerArm" in bone \
			or "wrist" in bone or "hand_" in bone or "finger" in bone:
		return "leg"
	return ""


static func _region_allowed(region: String, wanted: String) -> bool:
	if wanted == "body":
		return region != "head" and region != ""
	if wanted == "torso":
		return region in ["back", "withers", "shoulder", "flank", "rump", "barrel", "belly"]
	if wanted == "neck":
		return region == "neck"
	if wanted == "head":
		return region == "head"
	return region == wanted


static func _closest_on_triangle(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


static func _triangle_barycentric(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 0.0000001:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)
