extends RefCounted
## Posed triangle contact surface for the caress. It builds a small, region-filtered patch of
## the visible coat around a body anchor, skins it from the live skeleton, and answers closest
## point/normal queries. The caress always ends on this surface; the capsule hulls remain for
## the smack and reach contacts. The source arrays are shared per mesh/skin/region/window; the
## posed positions belong to one patch.

const CACHE_LIMIT := 12
## The patch is skinned at most once per update_ms, and the blur walks blur_depth rings. The
## caress quality setting lowers both; the default keeps the exact miss fallback.
const BLUR_RING_RADIUS_M := 0.03
## `features.caress_local`: the region source stays stable, but each hand skins and raycasts only
## a rest-space window around its intended point. The window re-centres when the point leaves its
## core, so the contact never sees the window boundary. The cell size equals the window radius, so
## one 3x3x3 cell block always covers the whole window.
const LOCAL_RADIUS_M := 0.12
const LOCAL_CORE_SCALE := 0.5
## A refresh is skipped while every bound bone is within these of the last skinned pose. The
## patch is skinned at most once per `update_ms` anyway, so this only stops a still body from
## paying for a skin, a soup write and a BVH rebuild: at `update_ms` = 33 ms the existing cadence
## already allows 33 ms of contact lag, and 0.8 mm is what a slow thrust covers in that time.
const POSE_EPS_M := 0.0008
## 0.15 degrees, as the sine of the basis-axis difference.
const POSE_EPS_SIN := 0.002618
var update_ms := 33
var blur_depth := 2
var accurate_miss := true
var local_enabled := false

static var _source_cache: Dictionary = {}

var facts: Variant
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
## The candidate transforms of the current refresh; swapped with `_transforms` on a commit so a
## skipped refresh allocates nothing.
var _scratch: Array[Transform3D] = []
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

## The local window. `_cells` buckets the stable rest-space faces; `_local_faces`/`_local_verts`
## are the active window, `_mask` marks the skinned vertices for the normal blur, and
## `_soup_dirty` forces the next update to rebuild the soup for a new window.
var _cells: Dictionary = {}
var _all_verts := PackedInt32Array()
var _local_verts := PackedInt32Array()
var _local_faces := PackedInt32Array()
var _mask := PackedByteArray()
var _local_center := Vector3.INF
var _local_radius := LOCAL_RADIUS_M
var _local_valid := false
var _soup_dirty := true


## Build a stable patch for a body region. The full patch is anchored to the rig's rest pose, not
## to the caller's query; `features.caress_local` then picks a window of that patch around the
## intended point instead of skinning all of it. `region` is "torso", "neck", "head" or "body".
## Returns false when the pony/rig/region is unavailable.
func _init(facts_context: Variant = null) -> void:
	facts = facts_context


## Apply the player's caress quality. Precise keeps the exact miss fallback; fast accepts the
## intended oval point on a ray miss and refreshes the patch less often.
func set_quality(quality: String) -> void:
	match quality:
		"fast":
			update_ms = 66
			blur_depth = 1
			accurate_miss = false
		_:
			update_ms = 33
			blur_depth = 2
			accurate_miss = true


## Enable or disable the local window. A change rebuilds the active soup on the next update.
func set_local(on: bool) -> void:
	if local_enabled == on:
		return
	local_enabled = on
	if not on:
		_local_valid = false
	_soup_dirty = true


## Pick the local window for one world query. Cheap when the point is still inside the current
## window; a new window is skinned by the next `update_pose()`. Called before the pose update so
## the first hand of the frame never skins the old window.
func select(point: Vector3) -> void:
	if not local_enabled or _cells.is_empty() or not is_instance_valid(skeleton):
		if _local_valid:
			_local_valid = false
			_soup_dirty = true
		return
	var local_point: Vector3 = skeleton.global_transform.affine_inverse() * point
	if _local_valid:
		var core := _local_radius * LOCAL_CORE_SCALE
		if local_point.distance_squared_to(_local_center) <= core * core:
			return
	var started := Time.get_ticks_usec()
	var collected := _collect_faces(local_point)
	if collected.is_empty():
		# A point beyond the source keeps the full patch, which is the old behaviour.
		if _local_valid:
			_local_valid = false
			_soup_dirty = true
		_perf_note("caress_select", Time.get_ticks_usec() - started)
		return
	_build_local(collected, local_point)
	_perf_note("caress_select", Time.get_ticks_usec() - started)


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
	# One patch update per physics tick per surface. Each hand owns its surface, so a local
	# window is skinned at most once per tick.
	var tick := Engine.get_physics_frames()
	if not force and not _soup_dirty and _update_tick == tick:
		return
	_update_tick = tick
	var now := Time.get_ticks_msec()
	if not force and not _soup_dirty and _last_update >= 0 and now - _last_update < update_ms:
		return
	var started := Time.get_ticks_usec()
	var base := skeleton.global_transform
	var count := _bindings.size()
	if _scratch.size() != count:
		_scratch.resize(count)
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
		_scratch[i] = t
		if not changed and not _pose_close(t, _transforms[i]):
			changed = true
	if not changed and not force and not _soup_dirty:
		# The body barely moved since the last skin; keep the posed patch and retry next tick.
		return
	var previous := _transforms
	_transforms = _scratch
	_scratch = previous
	var verts := _local_verts if _local_valid else _all_verts
	var rest_positions := _rest_positions
	var rest_normals := _rest_normals
	var offsets := _offsets
	var bones := _bones
	var weights := _weights
	var transforms := _transforms
	for i: int in verts:
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var rest := rest_positions[i]
		var normal := rest_normals[i]
		var to := offsets[i + 1]
		for k in range(offsets[i], to):
			var pose: Transform3D = transforms[bones[k]]
			var weight := weights[k]
			p += (pose * rest) * weight
			n += (pose.basis * normal) * weight
		_positions[i] = p
		_normals[i] = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	_write_soup()
	_soup_dirty = false
	_pose_serial += 1
	_tri = null
	_tri_stamp = -1
	_last_update = now
	skin_us = Time.get_ticks_usec() - started
	build_us = skin_us
	_perf_note("caress_skin", skin_us)


## True when two bound-bone transforms differ by less than the refresh tolerance. Two basis axes
## are enough: any rotation of more than the tolerance changes at least one of them.
static func _pose_close(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > POSE_EPS_M * POSE_EPS_M:
		return false
	if a.basis.x.distance_squared_to(b.basis.x) > POSE_EPS_SIN * POSE_EPS_SIN:
		return false
	return a.basis.y.distance_squared_to(b.basis.y) <= POSE_EPS_SIN * POSE_EPS_SIN


## Copy the active posed vertices into the triangle soup. Local mode only touches the window's
## faces; full mode keeps the source index order the authored anchor build reads back.
func _write_soup() -> void:
	if _local_valid:
		var count := _local_faces.size()
		var local_faces := _local_faces
		var indices := _indices
		var positions := _positions
		var normals := _normals
		faces.resize(count * 3)
		vertex_normals.resize(count * 3)
		for k in count:
			var i := local_faces[k] * 3
			for j in 3:
				var v := indices[i + j]
				faces[k * 3 + j] = positions[v]
				vertex_normals[k * 3 + j] = normals[v]
		return
	var indices := _indices
	var positions := _positions
	var normals := _normals
	faces.resize(indices.size())
	vertex_normals.resize(indices.size())
	for i in indices.size():
		var v := indices[i]
		faces[i] = positions[v]
		vertex_normals[i] = normals[v]


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
	# A direct caller may skip the placement's pre-update; a new window must be skinned first.
	select(point)
	if _soup_dirty:
		update_pose(true)
	var started := Time.get_ticks_usec()
	var hit := _cast(point + normal * 0.20, point - normal * 0.20)
	if hit.is_empty():
		ray_misses += 1
		if accurate_miss:
			return closest(point)
		query_us = Time.get_ticks_usec() - started
		_perf_note("caress_ray", query_us)
		return {
			"point": point,
			"normal": normal,
			"distance": 0.0,
			"inside": false,
			"face": -1,
		}
	ray_hits += 1
	query_us = Time.get_ticks_usec() - started
	_perf_note("caress_ray", query_us)
	var surface: Vector3 = hit.get("position", point)
	var hit_normal: Vector3 = hit.get("normal", normal)
	if hit_normal.length_squared() < 0.5:
		hit_normal = normal
	hit_normal = hit_normal.normalized()
	var face := int(hit.get("face_index", -1))
	return {
		"point": surface,
		"normal": hit_normal,
		"distance": point.distance_to(surface),
		"inside": (point - surface).dot(hit_normal) < 0.0,
		"face": face,
		"seed": _face_vertex(face, 0),
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
	var indices := _blur_candidates(seed, radius)
	if indices.is_empty():
		indices = _local_verts if _local_valid else _all_verts
	# A hand-built test patch has positions but no index list; scan the stored normals.
	var dense := indices.is_empty()
	var count := _positions.size() if dense else indices.size()
	for n in count:
		var i := n if dense else indices[n]
		if _local_valid and not dense and _mask[i] == 0:
			continue
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
## (`position`, `normal`, `face_index`) or {}. The authored-anchor build maps `face_index` back
## to a source vertex, so this always uses the full patch, never a local window.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	if _local_valid or _soup_dirty:
		_local_valid = false
		_soup_dirty = true
		update_pose(true)
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
	# The rings and the face buckets depend only on the shared source, so the second hand's
	# surface reuses them instead of building a second copy.
	if source.has("rings"):
		_rings = source["rings"]
	else:
		_build_rings()
		source["rings"] = _rings
	_all_verts.resize(_rest_positions.size())
	for i in _all_verts.size():
		_all_verts[i] = i
	if source.has("cells"):
		_cells = source["cells"]
	else:
		_build_cells()
		source["cells"] = _cells
	_local_faces = PackedInt32Array()
	_local_verts = PackedInt32Array()
	_mask.clear()
	_local_center = Vector3.INF
	_local_valid = false
	_soup_dirty = true
	_positions.resize(_rest_positions.size())
	_normals.resize(_rest_positions.size())
	faces = PackedVector3Array()
	vertex_normals = PackedVector3Array()
	_tri = null
	_tri_stamp = -1
	_pose_serial += 1
	_transforms.clear()
	_scratch.clear()
	_last_update = -1
	_update_tick = -1


## Bucket the stable patch's faces by rest-space centroid. The cell size is the window radius,
## so the 3x3x3 neighbourhood of a point always contains the whole window.
func _build_cells() -> void:
	_cells.clear()
	var cell := maxf(_local_radius, 0.001)
	for f in range(0, _indices.size(), 3):
		var centroid := (_rest_positions[_indices[f]]
			+ _rest_positions[_indices[f + 1]]
			+ _rest_positions[_indices[f + 2]]) / 3.0
		var key := Vector3i(floori(centroid.x / cell), floori(centroid.y / cell),
			floori(centroid.z / cell))
		var list: Variant = _cells.get(key)
		if list == null:
			list = []
			_cells[key] = list
		(list as Array).append(f / 3)


## The window's face ids: the 3x3x3 rest-space cells around the point, filtered by the exact
## centroid distance. Face ids index `_indices` in triples.
func _collect_faces(local_point: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _indices.is_empty():
		return out
	var radius := maxf(_local_radius, 0.001)
	var r2 := radius * radius
	var base := Vector3i(floori(local_point.x / radius), floori(local_point.y / radius),
		floori(local_point.z / radius))
	for dx in 3:
		for dy in 3:
			for dz in 3:
				var list: Variant = _cells.get(base + Vector3i(dx - 1, dy - 1, dz - 1))
				if list == null:
					continue
				for f: int in (list as Array):
					var i := f * 3
					var centroid := (_rest_positions[_indices[i]]
						+ _rest_positions[_indices[i + 1]]
						+ _rest_positions[_indices[i + 2]]) / 3.0
					if centroid.distance_squared_to(local_point) > r2:
						continue
					out.append(f)
	return out


## Build the active window from the collected faces. The vertex set carries one ring beyond the
## faces so the normal blur never reads a posed vertex outside the window.
func _build_local(face_ids: PackedInt32Array, center: Vector3) -> void:
	var seen := {}
	var verts := PackedInt32Array()
	for f: int in face_ids:
		var i := f * 3
		for j in 3:
			var v := _indices[i + j]
			if seen.has(v):
				continue
			seen[v] = true
			verts.append(v)
	var face_verts := verts.size()
	for n in face_verts:
		for ring: int in _rings[verts[n]]:
			if seen.has(ring):
				continue
			seen[ring] = true
			verts.append(ring)
	_local_faces = face_ids
	_local_verts = verts
	_local_center = center
	_local_valid = true
	_mask.resize(_rest_positions.size())
	_mask.fill(0)
	for v: int in verts:
		_mask[v] = 1
	_soup_dirty = true


## Source vertex of one corner of a soup face. The soup face index is window-relative in local
## mode, so map it back through `_local_faces` first.
func _face_vertex(face: int, corner: int) -> int:
	if face < 0:
		return -1
	if _local_valid:
		if face >= _local_faces.size():
			return -1
		face = _local_faces[face]
	var at := face * 3 + corner
	if at < 0 or at >= _indices.size():
		return -1
	return _indices[at]


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


## The hit face's neighbours out to `blur_depth` rings. A seed outside the ring set or a radius
## wider than the ring's proven reach returns an empty array so the caller keeps the full-patch
## average (the window's vertices in local mode), which is what a debug radius expects.
func _blur_candidates(seed: int, radius: float) -> PackedInt32Array:
	if seed < 0 or seed >= _rings.size() or radius > BLUR_RING_RADIUS_M or _rings.is_empty():
		return PackedInt32Array()
	var seen := PackedInt32Array()
	var seen_set := {}
	var front: Array[int] = [seed]
	for _depth in blur_depth:
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
	if facts != null:
		facts.perf(chunk, usec)


func face_count() -> int:
	return faces.size() / 3


## Faces in the stable region source, before the local window.
func patch_face_count() -> int:
	return _indices.size() / 3


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
