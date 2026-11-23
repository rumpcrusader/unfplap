extends RefCounted
## The one coat reader: one fitted sphere per authored area, skinned at runtime.

const BODY_COAT := preload("res://mods/unfplap/shared/body_coat.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The coat neighbourhood the radius is fitted to, in rest-space metres.
const FIT_RADIUS_M := 0.06
## The radius scan bounds; a patch flatter than the cap is treated as a plane.
const MIN_RADIUS_M := 0.03
const MAX_RADIUS_M := 1.0
const SCAN_STEPS := 24
const REFINE_STEPS := 8
## Faces on the far side of a thin part are not the same coat.
const MIN_NORMAL_DOT := 0.5
## An authored area farther than this from the coat is a miss for this body, not a fit elsewhere.
const MAX_DISTANCE_M := 0.06
## How far a point can miss once mapped onto a body these areas did not come from.
const REMAPPED_DISTANCE_M := 0.12
const CACHE_LIMIT := 32

static var _cache: Dictionary = {}
static var _order: Array = []


## The mesh and skeleton the caress reads for one coat region.
static func find_mesh(pony: Node3D, region: String) -> MODEL.CoatMesh:
	if region == "head":
		var head: Variant = pony.get("head")
		if head == null:
			return null
		var model: Variant = head.get("model")
		var sk: Variant = head.get("skeleton")
		if not is_instance_valid(model) or not sk is Skeleton3D:
			return null
		var mesh := (model as Node).find_child("Head", true, false) as MeshInstance3D
		if mesh == null:
			return null
		var out := MODEL.CoatMesh.new()
		out.mesh = mesh
		out.skeleton = sk
		out.surface = -1
		return out
	return _found_mesh(BODY_COAT.resolve(pony))


static func _found_mesh(found: Dictionary) -> MODEL.CoatMesh:
	if found.is_empty():
		return null
	var out := MODEL.CoatMesh.new()
	out.mesh = found["mesh"]
	out.skeleton = found["skeleton"]
	out.surface = int(found.get("surface", 0))
	return out


## The fitted sphere for one authored coat point, cached per skin/mesh.
static func primitive(pony: Node3D, region: String, position: Vector3,
		max_distance := MAX_DISTANCE_M) -> MODEL.CoatPrimitive:
	if not is_instance_valid(pony):
		return null
	var found := find_mesh(pony, region)
	if found == null:
		return null
	var mesh: MeshInstance3D = found.mesh
	var sk: Skeleton3D = found.skeleton
	if not is_instance_valid(mesh) or mesh.mesh == null or mesh.skin == null \
			or not is_instance_valid(sk):
		return null
	# The skin carries the bind poses, so a fit serves one pony, not every pony sharing the mesh.
	var key := "%d|%s|%d|%d|%d" % [mesh.skin.get_instance_id(), region,
		int(round(position.x * 1000.0)), int(round(position.y * 1000.0)),
		int(round(position.z * 1000.0))]
	if _cache.has(key):
		return _cache[key]
	PERF.begin("caress_fit")
	var fitted := _fit(mesh, sk, position, found.surface, max_distance)
	PERF.end("caress_fit")
	if fitted == null:
		return null
	_cache[key] = fitted
	_order.append(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())
	LOG.debug("caress fit mesh=%s region=%s r=%.3f err=%.2fmm snap=%.1fmm at=%s", [
		mesh.name, region, fitted.radius, fitted.residual_mm, fitted.snap_mm,
		str(position)])
	return fitted


## Fit one sphere to the coat around `position`; the nearest vertex fixes the normal and skin.
static func _fit(mesh: MeshInstance3D, skeleton: Skeleton3D, position: Vector3,
		surface_index: int, max_distance: float) -> MODEL.CoatPrimitive:
	var skin: Skin = mesh.skin
	var best_surface := -1
	var best_vertex := -1
	var best_distance := INF
	var first := surface_index if surface_index >= 0 else 0
	var last := (surface_index + 1) if surface_index >= 0 else mesh.mesh.get_surface_count()
	for si in range(first, last):
		var arrays := mesh.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			var distance := vs[i].distance_squared_to(position)
			if distance < best_distance:
				best_distance = distance
				best_surface = si
				best_vertex = i
	if best_vertex < 0 or best_distance > max_distance * max_distance:
		return null
	var arrays := mesh.mesh.surface_get_arrays(best_surface)
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ab: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var aw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if vs.is_empty():
		return null
	var point := vs[best_vertex]
	var normal: Vector3 = ns[best_vertex] if best_vertex < ns.size() else Vector3.UP
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var near := PackedVector3Array()
	var r2 := FIT_RADIUS_M * FIT_RADIUS_M
	for i in vs.size():
		if vs[i].distance_squared_to(point) > r2:
			continue
		var vertex_normal: Vector3 = ns[i] if i < ns.size() else Vector3.UP
		if vertex_normal.dot(normal) < MIN_NORMAL_DOT:
			continue
		near.append(vs[i])
	var fitted := MODEL.CoatPrimitive.new()
	fitted.normal = normal
	fitted.radius = _fit_radius(point, normal, near)
	fitted.center = point - normal * fitted.radius
	fitted.residual_mm = sqrt(_radius_error(point, normal, near, fitted.radius)
		/ maxf(float(near.size()), 1.0)) * 1000.0
	fitted.snap_mm = sqrt(best_distance) * 1000.0 \
		if best_distance > MAX_DISTANCE_M * MAX_DISTANCE_M else 0.0
	fitted.influences = _influences(skin, skeleton, ab, aw, vs.size(), best_vertex)
	if fitted.influences.is_empty():
		return null
	return fitted


## The radius whose centre `point - normal * r` best fits the neighbourhood.
static func _fit_radius(point: Vector3, normal: Vector3,
		near: PackedVector3Array) -> float:
	if near.size() < 4:
		return MAX_RADIUS_M
	var best := MAX_RADIUS_M
	var best_error := INF
	for step in SCAN_STEPS:
		var radius := MIN_RADIUS_M * pow(MAX_RADIUS_M / MIN_RADIUS_M,
			float(step) / float(SCAN_STEPS - 1))
		var error := _radius_error(point, normal, near, radius)
		if error < best_error:
			best_error = error
			best = radius
	var span := best * 0.10
	for step in REFINE_STEPS:
		var radius := clampf(best - span + span * 2.0 * float(step)
			/ float(REFINE_STEPS - 1), MIN_RADIUS_M, MAX_RADIUS_M)
		var error := _radius_error(point, normal, near, radius)
		if error < best_error:
			best_error = error
			best = radius
	return best


static func _radius_error(point: Vector3, normal: Vector3, near: PackedVector3Array,
		radius: float) -> float:
	var center := point - normal * radius
	var error := 0.0
	for v in near:
		var delta := center.distance_to(v) - radius
		error += delta * delta
	return error


## The skin influences of one vertex, with the bone name kept so a cache serves any pony.
static func _influences(skin: Skin, skeleton: Skeleton3D, ab: PackedInt32Array,
		aw: PackedFloat32Array, vertex_count: int, vertex: int) -> Array[MODEL.CoatInfluence]:
	var out: Array[MODEL.CoatInfluence] = []
	var stride := ab.size() / vertex_count if vertex_count > 0 else 0
	for k in stride:
		var at := vertex * stride + k
		if at >= ab.size() or at >= aw.size():
			continue
		var weight := aw[at]
		if weight <= 0.0:
			continue
		var bind := ab[at]
		if bind < 0 or bind >= skin.get_bind_count():
			continue
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name.is_empty():
			var bone := skin.get_bind_bone(bind)
			bone_name = skeleton.get_bone_name(bone) if bone >= 0 else ""
		if bone_name.is_empty():
			continue
		out.append(MODEL.CoatInfluence.new(bone_name, skin.get_bind_pose(bind), weight))
	return out
