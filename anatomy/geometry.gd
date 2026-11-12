extends RefCounted
## Pure anatomy geometry: the winking-mesh rebuild, the lip-radius stability rule, the body-local
## mapping and the V2 anal ring. It takes transforms, vertices and plain values; it reads no Node,
## scene or settings.
##
## See `docs/anatomy.md` (`## Act anatomy`).

## The authored `closed` shape also pulls the anal rim. The runtime rebuild masks that out.
const WINK_ANAL_FROM_Y := 0.020
const WINK_ANAL_TO_Y := 0.050

## Authored lip band radius. The density walk is unreliable on the denser V2 mesh, which can
## collapse the measured value to the 4 mm floor and make the shader open a huge ring.
const WINKING_LIP_RADIUS := 0.018

## Anal rim fallback, in mesh units. The V2 mesh owns the anal opening.
const ANAL_LIP := 0.022
const ANAL_OUTER_FACTOR := 2.2

## V2 anal blend-shape radii, mesh-local. Each key starts where the previous one ends.
const ANAL_OPEN_R := 0.008
const ANAL_STRETCH_R := 0.020
const ANAL_OVER_R := 0.028
const ANAL_EXTREME_R := 0.056

## The measured V2 outer-ring centres (Godot mesh local) at each additive anal key.
const V2_ANAL_RING_BASE := Vector3(0.00275, 0.06314, 0.01908)
const V2_ANAL_RING_OPEN := Vector3(0.00262, 0.06183, 0.01908)
const V2_ANAL_RING_STRETCH := Vector3(0.00272, 0.06286, 0.01908)
const V2_ANAL_RING_OVER := Vector3(0.00279, 0.05955, 0.01908)
const V2_ANAL_RING_EXTREME := Vector3(0.00303, 0.03996, 0.03310)
const V2_ANAL_RING_PONUT := Vector3(0.00296, 0.06515, 0.03310)

## The leg bones the anatomy follows, in the custom0 order the shader reads.
const COAT_FOLLOW_BONES := ["pony_flank_L", "pony_flank_R", "pony_femur_L", "pony_femur_R"]

## Cell size of the body-vertex lookup grid. The rump weights are smooth; 2 cm keeps the nearest
## three body vertices inside the 3x3x3 neighbourhood around every anatomy vertex.
const COAT_FOLLOW_CELL_M := 0.02

static var _refined_winking_meshes := {}


## Rebuild each winking source mesh once and share it across mares. The authored `closed` and
## `wink` shapes both pull the anal rim; the rebuild masks that out so only the vulva moves.
static func refined_winking_mesh(source: ArrayMesh) -> ArrayMesh:
	if source == null:
		return null
	if _refined_winking_meshes.has(source):
		return _refined_winking_meshes[source] as ArrayMesh
	var rebuilt := ArrayMesh.new()
	rebuilt.blend_shape_mode = source.blend_shape_mode
	var closed_index := -1
	var wink_index := -1
	for i in source.get_blend_shape_count():
		var shape_name := source.get_blend_shape_name(i)
		rebuilt.add_blend_shape(shape_name)
		if shape_name == &"closed":
			closed_index = i
		elif shape_name == &"wink":
			wink_index = i
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var shapes: Array = source.surface_get_blend_shape_arrays(surface)
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var typed_shapes: Array[Array] = []
		for s in shapes.size():
			var shape: Array = shapes[s]
			var shape_verts: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			if (s == closed_index or s == wink_index) and shape_verts.size() == base.size():
				for i in shape_verts.size():
					var p := base[i]
					var anal := 1.0 - smoothstep(WINK_ANAL_FROM_Y, WINK_ANAL_TO_Y, p.y)
					var delta := shape_verts[i] - p
					shape_verts[i] = p + delta * anal
				shape[Mesh.ARRAY_VERTEX] = shape_verts
			typed_shapes.append(shape)
		rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(surface),
			arrays, typed_shapes, {}, 0)
		rebuilt.surface_set_material(surface, source.surface_get_material(surface))
		rebuilt.surface_set_name(surface, source.surface_get_name(surface))
	_refined_winking_meshes[source] = rebuilt
	return rebuilt


## The V2 mesh's inner folds/high-res patch can make the density walk pick the wrong inner bin.
## Keep the authored band unless the measurement lands near it.
static func stable_lip_radius(measured: float) -> float:
	if not is_finite(measured):
		return WINKING_LIP_RADIUS
	if measured < WINKING_LIP_RADIUS * 0.65 or measured > WINKING_LIP_RADIUS * 1.8:
		return WINKING_LIP_RADIUS
	return measured


static func body_local_point(bind: Transform3D, mesh_transform: Transform3D,
		point: Vector3) -> Vector3:
	return bind.affine_inverse() * (mesh_transform * point)


static func body_local_direction(bind: Transform3D, mesh_transform: Transform3D,
		direction: Vector3) -> Vector3:
	return (bind.basis.inverse() * (mesh_transform.basis * direction)).normalized()


## Body-local radius of the visible anal cup's still zone. The cup's own outer ring sets the
## size; the 1.3 margin reaches the coat around it and the floor keeps a small cup usable.
static func anal_still_radius_for(lip: float, outer_factor: float, scale: float,
		multiplier: float) -> float:
	return maxf(lip * outer_factor * scale * 1.3, 0.045) * multiplier


## Bucket body rest vertices by cell so the anatomy's weight sample is a handful of distance
## checks instead of a full scan. Pure: the caller owns the vertices.
static func body_weight_grid(vertices: PackedVector3Array, cell: float) -> Dictionary:
	var grid := {}
	if vertices.is_empty() or cell <= 0.0:
		return grid
	for i in vertices.size():
		var key := Vector3i(
			floori(vertices[i].x / cell),
			floori(vertices[i].y / cell),
			floori(vertices[i].z / cell))
		var bucket: PackedInt32Array = grid.get(key, PackedInt32Array())
		bucket.append(i)
		grid[key] = bucket
	return grid


## Sample the body coat's four leg weights for every anatomy vertex. `body_to_local` maps the
## anatomy mesh into the body mesh's rest space; the nearest three body vertices are averaged by
## inverse distance, so a seam between vertex groups does not snap. The four bytes are the
## custom0 RGBA8 weights in `COAT_FOLLOW_BONES` order; the remaining weight is the pelvis.
static func sample_coat_weights(vertices: PackedVector3Array, body_to_local: Transform3D,
		body_vertices: PackedVector3Array, body_bones: PackedInt32Array,
		body_weights: PackedFloat32Array, bone_names: PackedStringArray,
		grid: Dictionary, cell: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(vertices.size() * 4)
	if vertices.is_empty() or body_vertices.is_empty() or cell <= 0.0:
		return out
	var stride := body_bones.size() / body_vertices.size() if body_vertices.size() > 0 else 0
	if stride <= 0 or body_weights.size() != body_bones.size() \
			or body_bones.size() != body_vertices.size() * stride:
		return out
	var leg_binds: Array[int] = [-1, -1, -1, -1]
	var any := false
	for i in bone_names.size():
		var index := COAT_FOLLOW_BONES.find(String(bone_names[i]))
		if index >= 0 and leg_binds[index] < 0:
			leg_binds[index] = i
			any = true
	if not any:
		return out
	var inv_cell := 1.0 / cell
	for v in vertices.size():
		var p: Vector3 = body_to_local * vertices[v]
		var base := Vector3i(floori(p.x * inv_cell), floori(p.y * inv_cell),
			floori(p.z * inv_cell))
		var candidates: Array[int] = []
		var distances: Array[float] = []
		for radius in [1, 2]:
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						var key := base + Vector3i(dx, dy, dz)
						var bucket: Variant = grid.get(key)
						if not bucket is PackedInt32Array:
							continue
						for index: int in bucket:
							var d: float = body_vertices[index].distance_squared_to(p)
							if candidates.size() < 3:
								candidates.append(index)
								distances.append(d)
								continue
							var worst := 0
							for k in 3:
								if distances[k] > distances[worst]:
									worst = k
							if d < distances[worst]:
								candidates[worst] = index
								distances[worst] = d
			if not candidates.is_empty():
				break
		if candidates.is_empty():
			continue
		var inverse_total := 0.0
		for c in candidates.size():
			inverse_total += 1.0 / maxf(distances[c], 0.00000001)
		var sums := [0.0, 0.0, 0.0, 0.0]
		for c in candidates.size():
			var weight := (1.0 / maxf(distances[c], 0.00000001)) / inverse_total
			var start := candidates[c] * stride
			for k in stride:
				var bind := body_bones[start + k]
				var amount := body_weights[start + k] * weight
				if amount <= 0.0:
					continue
				for j in 4:
					if bind == leg_binds[j]:
						sums[j] += amount
						break
		var total := float(sums[0]) + float(sums[1]) + float(sums[2]) + float(sums[3])
		var scale := 1.0 if total <= 1.0 else 1.0 / total
		for j in 4:
			out[v * 4 + j] = clampi(roundi(float(sums[j]) * scale * 255.0), 0, 255)
	return out


## One mesh with the sampled weights on its unused custom0 channel. The anatomy has one surface
## and no custom attributes today; a surface that cannot take the weights is left to the caller
## (the coat follow then stays off rather than collapsing the mesh).
static func mesh_with_coat_weights(source: ArrayMesh, weights: PackedByteArray) -> ArrayMesh:
	if source == null or source.get_surface_count() != 1:
		return null
	if weights.size() != source.surface_get_array_len(0) * 4:
		return null
	var rebuilt := ArrayMesh.new()
	rebuilt.blend_shape_mode = source.blend_shape_mode
	for i in source.get_blend_shape_count():
		rebuilt.add_blend_shape(source.get_blend_shape_name(i))
	var arrays: Array = source.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX:
		return null
	arrays[Mesh.ARRAY_CUSTOM0] = weights
	var shapes: Array = source.surface_get_blend_shape_arrays(0)
	rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(0), arrays, shapes, {}, 0)
	rebuilt.surface_set_material(0, source.surface_get_material(0))
	rebuilt.surface_set_name(0, source.surface_get_name(0))
	return rebuilt


## The four bone transforms in the anatomy mesh's local space, relative to the pelvis. `poses`
## and `rests` are the live and rest skeleton poses of the same four leg bones; `hips` and
## `hips_rest` are the pelvis. `base_place` maps anatomy local into skeleton rest space. At rest
## every returned matrix is the identity, so no coat follow means no motion.
static func coat_follow_matrices(hips: Transform3D, hips_rest: Transform3D,
		poses: Array[Transform3D], rests: Array[Transform3D],
		base_place: Transform3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var hips_delta := hips * hips_rest.affine_inverse()
	var inv_delta := hips_delta.affine_inverse()
	var inv_place := base_place.affine_inverse()
	for i in poses.size():
		var pose := poses[i]
		var rest := rests[i] if i < rests.size() else Transform3D.IDENTITY
		var delta := pose * rest.affine_inverse()
		out.append(inv_place * inv_delta * delta * base_place)
	return out


## The five additive V2 anal keys for a local penetration radius. The first four start where the
## previous one ends; the ponut key is a 2x ponut-only scale that fades under the extreme key. No
## upper clamp: an oversized shaft extrapolates the extreme key.
static func anal_ring_weights(local: float, anal_scale: float) -> Dictionary:
	var open := clampf(local / ANAL_OPEN_R, 0.0, 1.0)
	var stretch := clampf((local - ANAL_OPEN_R) / (ANAL_STRETCH_R - ANAL_OPEN_R), 0.0, 1.0)
	var over := clampf((local - ANAL_STRETCH_R) / (ANAL_OVER_R - ANAL_STRETCH_R), 0.0, 1.0)
	var extreme := maxf(0.0, (local - ANAL_OVER_R) / (ANAL_EXTREME_R - ANAL_OVER_R))
	var ponut := (anal_scale - 1.0) * maxf(0.0, 1.0 - extreme)
	return {"open": open, "stretch": stretch, "over": over, "extreme": extreme,
		"ponut": ponut}


## The V2 anal ring centre for the weights from `anal_ring_weights()`.
static func anal_ring_centre(weights: Dictionary) -> Vector3:
	return V2_ANAL_RING_BASE \
		+ (V2_ANAL_RING_OPEN - V2_ANAL_RING_BASE) * float(weights.get("open", 0.0)) \
		+ (V2_ANAL_RING_STRETCH - V2_ANAL_RING_OPEN) * float(weights.get("stretch", 0.0)) \
		+ (V2_ANAL_RING_OVER - V2_ANAL_RING_STRETCH) * float(weights.get("over", 0.0)) \
		+ (V2_ANAL_RING_EXTREME - V2_ANAL_RING_OVER) * float(weights.get("extreme", 0.0)) \
		+ (V2_ANAL_RING_PONUT - V2_ANAL_RING_BASE) * float(weights.get("ponut", 0.0))
