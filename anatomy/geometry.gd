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
