extends RefCounted
## Posed triangle contact surface for the caress. It builds a small, region-filtered patch of
## the visible coat around a body anchor, skins it from the live skeleton, and answers closest
## point/normal queries. The capsule hulls remain a broadphase/fallback; they are not the final
## contact. The source arrays are shared per mesh/skin/region/window; the posed positions belong
## to one patch.

const CACHE_LIMIT := 12
const UPDATE_MS := 33
## The exact query touches a few centimetres of coat. The normal blur walks the hit vertex's
## mesh ring instead of every posed vertex; a radius beyond the ring's proven reach keeps the
## full-scan fallback so a debug radius still averages the whole patch. Two rings already cover
## the 2 cm default radius; four rings would walk ~4x the vertices for no extra reach.
const BLUR_RING_RADIUS_M := 0.03
const BLUR_RING_DEPTH := 2

static var _source_cache: Dictionary = {}

var runtime: Node
var source: Dictionary = {}
var skeleton: Skeleton3D
var faces := PackedVector3Array()
var vertex_normals := PackedVector3Array()
var build_us := 0
var query_us := 0
var skin_us := 0
var tri_us := 0
var blur_us := 0
var closest_us := 0
var ray_hits := 0
var ray_misses := 0
var source_key := ""

var _rings: Array = []
var _pony_id := 0
var _region := ""
var _radius := 0.0
var _mesh: MeshInstance3D = null
var _mesh_id := 0
var _skeleton_id := 0
var _update_tick := -1
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
var _tri: TriangleMesh = null
var _tri_stamp := -1
var _pose_serial := 0
var _last_update := -1
var _cache_order: Array = []


## Build a stable patch for a body region. The patch is anchored to the rig's rest pose, not to
## the caller's query, so it does not change face sets while the hand moves. `region` is "torso",
## "neck", "head" or "body". Returns false when the pony/rig/region is unavailable.
func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


func ensure(pony: Variant, region: String, radius := 0.0) -> bool:
	var started := Time.get_ticks_usec()
	if not is_instance_valid(pony):
		return false
	# The same pony and region keep the same mesh, skeleton and rest anchor; skip the scene-tree
	# lookup and key build on every hand call.
	if _pony_id != 0 and _pony_id == int(pony.get_instance_id()) and _region == region \
			and is_equal_approx(_radius, radius) and not source.is_empty() \
			and is_instance_valid(_mesh) and _mesh.get_instance_id() == _mesh_id \
			and is_instance_valid(skeleton) and skeleton.get_instance_id() == _skeleton_id:
		_perf_note("caress_ensure", Time.get_ticks_usec() - started)
		return true
	var found := find_mesh(pony, region)
	if found.is_empty():
		return false
	var mesh: MeshInstance3D = found["mesh"]
	var sk: Variant = found["skeleton"]
	if not sk is Skeleton3D:
		return false
	skeleton = sk as Skeleton3D
	_mesh = mesh
	_mesh_id = mesh.get_instance_id()
	_skeleton_id = skeleton.get_instance_id()
	_pony_id = int(pony.get_instance_id())
	_region = region
	_radius = radius
	var anchor := _region_anchor(skeleton, region)
	if anchor.is_empty():
		return false
	var local_center: Vector3 = anchor["center"]
	var use_radius: float = radius if radius > 0.0 else float(anchor["radius"])
	var key := "%d|%d|%s|%d|%d|%d|%d" % [
		mesh.get_instance_id(), skeleton.get_instance_id(), region,
		int(round(use_radius * 100.0)), int(round(local_center.x * 100.0)),
		int(round(local_center.y * 100.0)), int(round(local_center.z * 100.0))]
	if key != source_key or source.is_empty():
		source_key = key
		var cache_key := "%d|%d|%s|%d|%d|%d|%d" % [
			mesh.mesh.get_instance_id(), mesh.skin.get_instance_id() if mesh.skin != null else 0,
			region, int(round(use_radius * 100.0)), int(round(local_center.x * 100.0)),
			int(round(local_center.y * 100.0)), int(round(local_center.z * 100.0))]
		if _source_cache.has(cache_key):
			source = _source_cache[cache_key]
		else:
			source = _gather(mesh, region, local_center, use_radius, skeleton)
			if source.is_empty() or (source.get("vertices", []) as Array).is_empty():
				source = {}
				return false
			_source_cache[cache_key] = source
			_cache_order.append(cache_key)
			while _cache_order.size() > CACHE_LIMIT:
				var old: Variant = _cache_order.pop_front()
				_source_cache.erase(old)
		_flatten()
		_last_update = -1
	_perf_note("caress_ensure", Time.get_ticks_usec() - started)
	return not source.is_empty() and not (source.get("vertices", []) as Array).is_empty()


func update_pose(force := false) -> void:
	if source.is_empty() or not is_instance_valid(skeleton):
		return
	# One patch update per physics tick even if both hands ask: the second hand shares it.
	var tick := Engine.get_physics_frames()
	if not force and _update_tick == tick:
		return
	_update_tick = tick
	var now := Time.get_ticks_msec()
	if not force and _last_update >= 0 and now - _last_update < UPDATE_MS:
		return
	var started := Time.get_ticks_usec()
	var base := skeleton.global_transform
	var count := _bindings.size()
	var transforms: Array[Transform3D] = []
	transforms.resize(count)
	var changed := _transforms.size() != count
	for i in count:
		var binding: Dictionary = _bindings[i]
		var bone := int(binding["bone"])
		var t := Transform3D.IDENTITY
		if bone < 0:
			changed = true
		else:
			t = base * skeleton.get_bone_global_pose(bone) \
				* (binding["bind"] as Transform3D)
		transforms[i] = t
		if not changed and not t.is_equal_approx(_transforms[i]):
			changed = true
	if not changed and not force:
		return
	_transforms = transforms
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
	_pose_serial += 1
	_tri = null
	_tri_stamp = -1
	_last_update = now
	skin_us = Time.get_ticks_usec() - started
	build_us = skin_us
	_perf_note("caress_skin", skin_us)


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
	closest_us = Time.get_ticks_usec() - started
	_perf_note("caress_closest", closest_us)
	query_us = closest_us
	return {
		"point": best_point,
		"normal": best_normal,
		"distance": sqrt(best),
		"inside": (point - best_point).dot(best_normal) < 0.0,
		"bary": best_bary,
	}


## Cast a short ray through the patch along the hand normal. Much cheaper than the full
## triangle loop for the palm/finger samples; `closest()` is the fallback.
func nearest(point: Vector3, outward: Vector3) -> Dictionary:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	var started := Time.get_ticks_usec()
	var hit := _cast(point + normal * 0.20, point - normal * 0.20)
	if hit.is_empty():
		ray_misses += 1
		return closest(point)
	ray_hits += 1
	query_us = Time.get_ticks_usec() - started
	_perf_note("caress_ray", query_us)
	var surface: Vector3 = hit.get("position", point)
	var hit_normal: Vector3 = hit.get("normal", normal)
	if hit_normal.length_squared() < 0.5:
		hit_normal = normal
	hit_normal = hit_normal.normalized()
	return {
		"point": surface,
		"normal": hit_normal,
		"distance": point.distance_to(surface),
		"inside": (point - surface).dot(hit_normal) < 0.0,
		"face": int(hit.get("face_index", -1)),
	}


## Distance-weighted average of the posed vertex normals around `point`, ignoring vertices whose
## normal faces away from `hint`. This smooths the normal across mesh creases; 0 radius or a
## cancelled sum returns Vector3.ZERO and the caller keeps the exact hit normal.
func normal_blur(point: Vector3, radius: float, hint: Vector3, seed := -1) -> Vector3:
	if radius <= 0.0 or _positions.is_empty():
		return Vector3.ZERO
	var started := Time.get_ticks_usec()
	var hint_normal := hint.normalized()
	if hint_normal.length_squared() < 0.5:
		hint_normal = Vector3.UP
	var r2 := radius * radius
	var sum := Vector3.ZERO
	var candidates := _blur_candidates(seed, radius)
	if candidates.is_empty():
		for i in _positions.size():
			var distance := _positions[i].distance_squared_to(point)
			if distance > r2:
				continue
			var normal: Vector3 = _normals[i]
			if normal.dot(hint_normal) < 0.2:
				continue
			sum += normal * (1.0 - distance / r2)
	else:
		for i: int in candidates:
			var distance := _positions[i].distance_squared_to(point)
			if distance > r2:
				continue
			var normal: Vector3 = _normals[i]
			if normal.dot(hint_normal) < 0.2:
				continue
			sum += normal * (1.0 - distance / r2)
	blur_us = Time.get_ticks_usec() - started
	_perf_note("caress_blur", blur_us)
	if sum.length_squared() < 0.0001:
		return Vector3.ZERO
	return sum.normalized()


## Cast an arbitrary world segment against the posed patch. Returns the ray hit dictionary
## (`position`, `normal`, `face_index`) or {}. `update_pose()` must have run for the current frame.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	return _cast(from, to)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	if faces.is_empty():
		return {}
	if _tri == null or _tri_stamp != _pose_serial:
		var tri_started := Time.get_ticks_usec()
		_tri = TriangleMesh.new()
		_tri.create_from_faces(faces)
		tri_us = Time.get_ticks_usec() - tri_started
		_perf_note("caress_tri", tri_us)
		_tri_stamp = _pose_serial
	var hit: Dictionary = _tri.intersect_segment(from, to)
	if hit.is_empty():
		return {}
	var i := int(hit.get("face_index", -1)) * 3
	if i < 0 or i + 2 >= faces.size() or i + 2 >= vertex_normals.size():
		return {}
	var a := faces[i]
	var b := faces[i + 1]
	var c := faces[i + 2]
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	var bary := _triangle_barycentric(a, b, c, point)
	var normal := vertex_normals[i] * bary.x + vertex_normals[i + 1] * bary.y \
		+ vertex_normals[i + 2] * bary.z
	if normal.length_squared() < 0.000001:
		normal = (b - a).cross(c - a)
	hit["normal"] = normal.normalized()
	return hit


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
	_build_rings()
	_positions.resize(_rest_positions.size())
	_normals.resize(_rest_positions.size())
	faces = PackedVector3Array()
	vertex_normals = PackedVector3Array()
	_tri = null
	_tri_stamp = -1
	_pose_serial += 1
	_transforms.clear()
	_last_update = -1
	_update_tick = -1


## Vertex adjacency of the flattened patch, built once per source. The blur walks only these
## rings around the hit face, so a centimetre query does not touch the whole patch.
func _build_rings() -> void:
	_rings.clear()
	_rings.resize(_rest_positions.size())
	for i in _rings.size():
		_rings[i] = []
	for t in range(0, _indices.size(), 3):
		_link_ring(_indices[t], _indices[t + 1])
		_link_ring(_indices[t], _indices[t + 2])
		_link_ring(_indices[t + 1], _indices[t + 2])


func _link_ring(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= _rings.size() or b >= _rings.size():
		return
	var ra: Array = _rings[a]
	if not ra.has(b):
		ra.append(b)
	var rb: Array = _rings[b]
	if not rb.has(a):
		rb.append(a)


## The hit face's neighbours out to BLUR_RING_DEPTH rings. A seed outside the ring set or a
## radius wider than the ring's proven reach returns an empty array so the caller keeps the
## full-scan average, which is what a debug radius expects.
func _blur_candidates(seed: int, radius: float) -> PackedInt32Array:
	if seed < 0 or seed >= _rings.size() or radius > BLUR_RING_RADIUS_M or _rings.is_empty():
		return PackedInt32Array()
	var seen := PackedInt32Array()
	var seen_set := {}
	var front: Array[int] = [seed]
	for _depth in BLUR_RING_DEPTH:
		var next: Array[int] = []
		for v: int in front:
			if seen_set.has(v):
				continue
			seen_set[v] = true
			seen.append(v)
			for n: int in _rings[v]:
				if not seen_set.has(n):
					next.append(n)
		front = next
		if front.is_empty():
			break
	return seen


func _perf_note(chunk: String, usec: int) -> void:
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", chunk, usec)


func face_count() -> int:
	return faces.size() / 3


func _region_anchor(skeleton: Skeleton3D, region: String) -> Dictionary:
	if region == "head":
		var head: Variant = _bone_global_rest(skeleton, ["mHead", "pony_head", "Head"])
		if head == null:
			return {}
		return {"center": (head as Transform3D).origin, "radius": 0.65}
	var spine: Variant = _bone_global_rest(skeleton, ["pony_hips", "pony_spine1", "pony_spine2"])
	if spine == null:
		return {}
	var center: Vector3 = (spine as Transform3D).origin
	var radius := 0.85
	var neck: Variant = _bone_global_rest(skeleton, ["pony_neck1", "pony_spine3"])
	if neck != null:
		var neck_origin: Vector3 = (neck as Transform3D).origin
		center = (center + neck_origin) * 0.5
		radius = center.distance_to(neck_origin) * 2.0 + 0.32
	return {"center": center, "radius": maxf(radius, 0.55)}


func _bone_global_rest(skeleton: Skeleton3D, names: Array) -> Variant:
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			return skeleton.get_bone_global_rest(bone)
	return null


static func find_mesh(pony: Variant, region: String) -> Dictionary:
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
		radius: float, skeleton: Skeleton3D) -> Dictionary:
	var skin: Skin = mesh.skin
	if skin == null or mesh.mesh == null or not is_instance_valid(skeleton):
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
				if region_allowed(region_for(role, bone), region):
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


static func region_for(role: String, bone: String) -> String:
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


static func region_allowed(region: String, wanted: String) -> bool:
	if wanted == "body":
		return region != "head" and region != ""
	if wanted == "torso":
		return region in ["back", "withers", "shoulder", "flank", "rump", "barrel", "belly",
			"neck"]
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
