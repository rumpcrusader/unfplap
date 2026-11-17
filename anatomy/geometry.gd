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

## Cell size of the body-vertex lookup grid. The rump weights are smooth; 2 cm keeps the nearest
## body vertex inside the 5x5x5 neighbourhood around every line target.
const COAT_LINE_CELL_M := 0.02

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


## The line targets: `count` local points at x = 0, evenly spaced across the mesh's local Y range.
static func coat_line_targets(y_min: float, y_max: float, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if count < 1:
		return out
	out.resize(count)
	for i in count:
		var t := 0.0 if count == 1 else float(i) / float(count - 1)
		out[i] = Vector3(0.0, lerpf(y_min, y_max, t), 0.0)
	return out


## Resolve each line target, in body rest space, to its nearest body rest vertex. Returns
## `indices`, the nearest `points` and their normalized bind-name -> weight `influences`. A target
## with no vertex inside the 5x5x5 grid neighbourhood is skipped.
static func coat_line_samples(targets_body: PackedVector3Array,
		body_vertices: PackedVector3Array, body_bones: PackedInt32Array,
		body_weights: PackedFloat32Array, bone_names: PackedStringArray,
		grid: Dictionary, cell: float) -> Dictionary:
	var indices := PackedInt32Array()
	var points := PackedVector3Array()
	var influences: Array = []
	if targets_body.is_empty() or body_vertices.is_empty() or cell <= 0.0:
		return {"indices": indices, "points": points, "influences": influences}
	var stride := body_bones.size() / body_vertices.size() if body_vertices.size() > 0 else 0
	if stride <= 0 or body_weights.size() != body_bones.size() \
			or body_bones.size() != body_vertices.size() * stride:
		return {"indices": indices, "points": points, "influences": influences}
	var inv_cell := 1.0 / cell
	for target in targets_body:
		var index := _nearest_body_vertex(target, body_vertices, grid, inv_cell)
		if index < 0:
			continue
		indices.append(index)
		points.append(body_vertices[index])
		var row := {}
		var total := 0.0
		var start := index * stride
		for k in stride:
			var weight := body_weights[start + k]
			if weight <= 0.0:
				continue
			var bind := body_bones[start + k]
			if bind < 0 or bind >= bone_names.size():
				continue
			var bone := String(bone_names[bind])
			row[bone] = float(row.get(bone, 0.0)) + weight
			total += weight
		if total > 0.0:
			for bone: String in row.keys():
				row[bone] = float(row[bone]) / total
		influences.append(row)
	return {"indices": indices, "points": points, "influences": influences}


## The nearest body rest vertex inside a growing 5x5x5 cell neighbourhood, or -1.
static func _nearest_body_vertex(point: Vector3, vertices: PackedVector3Array,
		grid: Dictionary, inv_cell: float) -> int:
	var base := Vector3i(floori(point.x * inv_cell), floori(point.y * inv_cell),
		floori(point.z * inv_cell))
	for radius in [1, 2]:
		var best := -1
		var best_distance := INF
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					var key := base + Vector3i(dx, dy, dz)
					var bucket: Variant = grid.get(key)
					if not bucket is PackedInt32Array:
						continue
					for index: int in bucket:
						var distance := vertices[index].distance_squared_to(point)
						if distance < best_distance:
							best_distance = distance
							best = index
		if best >= 0:
			return best
	return -1


## The shortest-arc rotation taking `from` to `to`.
static func rotation_between(from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 0.000000000001 or to.length_squared() < 0.000000000001:
		return Basis.IDENTITY
	var a := from.normalized()
	var b := to.normalized()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.999999:
		return Basis.IDENTITY
	if dot < -0.999999:
		var opposite := a.cross(Vector3.RIGHT)
		if opposite.length_squared() < 0.000001:
			opposite = a.cross(Vector3.UP)
		if opposite.length_squared() < 0.000001:
			opposite = a.cross(Vector3.BACK)
		return Basis(opposite.normalized(), PI)
	return Basis(a.cross(b).normalized(), acos(dot))


## Fill one frame per line sample: the shortest-arc rotation from the rest tangent to the live
## tangent, scaled along the rest tangent by the segment stretch. Slots past the sample count copy
## the last frame. `basis_x/y/z` and `origin` are the shader's per-sample columns and offsets.
static func fill_line_frames(rest: PackedVector3Array, live: PackedVector3Array,
		basis_x: PackedVector3Array, basis_y: PackedVector3Array,
		basis_z: PackedVector3Array, origin: PackedVector3Array) -> void:
	var count := mini(rest.size(), live.size())
	var slots := basis_x.size()
	if count < 1 or slots < count or basis_y.size() < slots or basis_z.size() < slots \
			or origin.size() < slots:
		return
	for i in count:
		var prev := maxi(i - 1, 0)
		var next := mini(i + 1, count - 1)
		var rest_tangent := rest[next] - rest[prev]
		var live_tangent := live[next] - live[prev]
		var rest_length := rest_tangent.length()
		var stretch := 1.0
		var basis := Basis.IDENTITY
		if rest_length > 0.000001 and live_tangent.length_squared() > 0.000000000001:
			var tangent := rest_tangent / rest_length
			stretch = clampf(live_tangent.length() / rest_length, 0.5, 2.0)
			var shear := Basis.IDENTITY
			var amount := stretch - 1.0
			shear.x += tangent * (tangent.x * amount)
			shear.y += tangent * (tangent.y * amount)
			shear.z += tangent * (tangent.z * amount)
			basis = rotation_between(tangent, live_tangent) * shear
		basis_x[i] = basis.x
		basis_y[i] = basis.y
		basis_z[i] = basis.z
		origin[i] = live[i] - basis * rest[i]
	for i in range(count, slots):
		basis_x[i] = basis_x[count - 1]
		basis_y[i] = basis_y[count - 1]
		basis_z[i] = basis_z[count - 1]
		origin[i] = origin[count - 1]


## The segment index and blend factor a local Y falls in. -1 when the line has fewer than two
## samples. The index clamps to the last segment and the factor to 0…1.
static func _line_segment(y: float, rest: PackedVector3Array) -> Vector2:
	var count := rest.size()
	if count < 2:
		return Vector2(-1.0, 0.0)
	var index := 0
	for i in count:
		if rest[i].y <= y:
			index = i
	index = mini(index, count - 2)
	var span := maxf(rest[index + 1].y - rest[index].y, 0.00001)
	return Vector2(float(index), clampf((y - rest[index].y) / span, 0.0, 1.0))


## The line's frame at a local Y, mixed between its two neighbouring samples. Maps an
## anatomy-local point the same way `anatomy.gdshader` maps a vertex.
static func line_point_at(local: Vector3, rest: PackedVector3Array,
		basis_x: PackedVector3Array, basis_y: PackedVector3Array,
		basis_z: PackedVector3Array, origin: PackedVector3Array) -> Vector3:
	var segment := _line_segment(local.y, rest)
	if segment.x < 0.0:
		return local
	var i := int(segment.x)
	var f := segment.y
	var bx := basis_x[i].lerp(basis_x[i + 1], f)
	var by := basis_y[i].lerp(basis_y[i + 1], f)
	var bz := basis_z[i].lerp(basis_z[i + 1], f)
	var o := origin[i].lerp(origin[i + 1], f)
	return bx * local.x + by * local.y + bz * local.z + o


## The line's frame direction at a local Y, normalized.
static func line_direction_at(local: Vector3, rest: PackedVector3Array,
		basis_x: PackedVector3Array, basis_y: PackedVector3Array,
		basis_z: PackedVector3Array, _origin: PackedVector3Array) -> Vector3:
	var segment := _line_segment(local.y, rest)
	if segment.x < 0.0:
		return local.normalized()
	var i := int(segment.x)
	var f := segment.y
	var direction := basis_x[i].lerp(basis_x[i + 1], f) * local.x \
		+ basis_y[i].lerp(basis_y[i + 1], f) * local.y \
		+ basis_z[i].lerp(basis_z[i + 1], f) * local.z
	return direction.normalized() if direction.length_squared() > 0.000001 \
		else local.normalized()


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
