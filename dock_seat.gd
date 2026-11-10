extends RefCounted
## Snap the fitted dock's base ring to the rump surface.
##
## The dock is a body-skinned mesh, not a second skeleton tail: its 102 base-ring vertices are
## weighted 100% to `pony_hips`. The game's `reach_rump()` only pushes the frontmost vertices
## forward along Z, so most of the ring can stay 5-33 mm behind the rump. This module moves every
## base-ring vertex to `hybrid_dock.rump_z(y) - EMBED`, then blends that correction over the first
## FALLOFF of the dock so the base stretches into the coat instead of creasing.

const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")

const EMBED := 0.004
const FALLOFF := 0.35


## Return a copy of `mesh` with its base ring seated in the rump. `body` is "mare" or "stallion"
## (the rump table selects the body). A mesh with no base-ring metadata is returned unchanged.
static func snap_base(mesh: ArrayMesh, body: String) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var ring: PackedInt32Array = mesh.get_meta("base_indices", PackedInt32Array())
	if ring.is_empty():
		return mesh
	var arrays: Array = mesh.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return mesh
	var valid := PackedInt32Array()
	for index: int in ring:
		if index >= 0 and index < vertices.size():
			valid.append(index)
	if valid.is_empty():
		return mesh

	var body_name := body if body in ["mare", "stallion"] else "mare"
	var base := Vector3.ZERO
	for index: int in valid:
		base += vertices[index]
	base /= float(valid.size())
	var tip := base
	var far := 0.0
	for vertex: Vector3 in vertices:
		var distance := vertex.distance_squared_to(base)
		if distance > far:
			far = distance
			tip = vertex
	var length := base.distance_to(tip)
	if length < 0.001:
		return mesh
	var axis := (tip - base) / length

	var corrections: Dictionary = {}
	var ring_points: Array[Vector3] = []
	for index: int in valid:
		var vertex := vertices[index]
		var surface_z: float = HYBRID_DOCK.rump_z(body_name, vertex.y)
		corrections[index] = surface_z - EMBED - vertex.z
		ring_points.append(vertex)

	for index: int in vertices.size():
		var vertex := vertices[index]
		var correction := 0.0
		if corrections.has(index):
			correction = float(corrections[index])
		else:
			var nearest := 0
			var nearest_distance := INF
			for at: int in valid.size():
				var distance := vertex.distance_squared_to(ring_points[at])
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = at
			var along := clampf((vertex - base).dot(axis) / length, 0.0, 1.0)
			var falloff := 1.0 - smoothstep(0.0, FALLOFF, along)
			correction = float(corrections[valid[nearest]]) * falloff
		vertex.z += correction
		vertices[index] = vertex
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_recompute_normals(arrays)

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(mesh.surface_get_primitive_type(0), arrays, [], {},
		mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	out.surface_set_material(0, mesh.surface_get_material(0))
	out.surface_set_name(0, mesh.surface_get_name(0))
	for key: Variant in mesh.get_meta_list():
		out.set_meta(key, mesh.get_meta(key))
	out.set_meta("dock_base_snap", true)
	return out


## Rebuild outward normals after the base ring moves. `reach_rump()` leaves the old normals;
## this keeps the stretched base lit correctly. The topology winding is consistent, so the
## original normals decide the sign.
static func _recompute_normals(arrays: Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Accumulate in an Array: GDScript Packed arrays are value types, so a PackedVector3Array
	# passed to `_accumulate()` would only be modified locally.
	var normals: Array = []
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices is PackedInt32Array and (indices as PackedInt32Array).size() >= 3:
		var list: PackedInt32Array = indices
		for at in range(0, list.size(), 3):
			_accumulate(normals, vertices, list[at], list[at + 1], list[at + 2])
	else:
		for at in range(0, vertices.size() - 2, 3):
			_accumulate(normals, vertices, at, at + 1, at + 2)
	var original: Variant = arrays[Mesh.ARRAY_NORMAL]
	var sign := 1.0
	if original is PackedVector3Array and (original as PackedVector3Array).size() == normals.size():
		var original_normals: PackedVector3Array = original
		var dot_sum := 0.0
		for i in normals.size():
			var normal: Vector3 = normals[i]
			if normal.length_squared() > 0.0000000001:
				dot_sum += normal.normalized().dot(original_normals[i])
		if dot_sum < 0.0:
			sign = -1.0
	var packed := PackedVector3Array()
	packed.resize(normals.size())
	for i in normals.size():
		var normal: Vector3 = normals[i]
		if normal.length_squared() > 0.0000000001:
			packed[i] = normal.normalized() * sign
		else:
			packed[i] = Vector3.UP
	arrays[Mesh.ARRAY_NORMAL] = packed


static func _accumulate(normals: Array, vertices: PackedVector3Array,
		a: int, b: int, c: int) -> void:
	if a < 0 or b < 0 or c < 0 or a >= vertices.size() or b >= vertices.size() \
			or c >= vertices.size():
		return
	var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	normals[a] += normal
	normals[b] += normal
	normals[c] += normal
