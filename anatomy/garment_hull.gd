extends RefCounted
## The garment hull: a rear-facing outer depth field built from the anatomy mesh. A worn garment
## (the Pantyhose & Panties cloth) samples it in the vertex shader and lifts itself over the
## anatomy surface instead of letting the mesh poke through. The field is built once per source
## mesh, resolution and smoothing, and is shared by every mare; only the transform is per-mare.
##
## The mesh is read in anatomy-local space (+Z toward the tail). Only triangles whose local
## normal faces rearward (`n.z > OUTER_NORMAL_Z`) are kept, so the inner canal and cavity walls
## do not become part of the surface. Their X/Y projection is rasterised into a `resolution²`
## grid that stores the maximum Z per cell. The base mesh and every relevant blend shape are
## rasterised at full weight, so the field is the outer envelope of the shape range: the cloth
## never cuts into a closed lip, a wink, or an opened anal ring.
##
## The domain is the X/Y bounds of the retained outer triangles plus a small margin, not the
## full mesh AABB. The field is normalised over `z_min`/`z_max`; an empty cell keeps the
## `INVALID` marker and the shader skips it.
##
## Pure: it takes a mesh and plain numbers and reads no Node, scene or settings.
## See `docs/anatomy.md` (`## Garment hull`) and `docs/integrations.md`.

## The authored mesh's outer surface faces the tail on +Z. The base mesh's anal cavity and inner
## canal face the other way; a threshold above zero keeps them out of the field.
const OUTER_NORMAL_Z := 0.1
## Extra room around the retained outer triangles so the shader's edge fade has a border.
const DOMAIN_MARGIN := 0.004
## Dilation passes that fill the empty cells between rasterised triangles before smoothing.
const DILATE_PASSES := 6
## A cell the outer surface never covered. The shader reads a negative value and skips the cell.
const INVALID := -1.0
const MIN_RESOLUTION := 8
const MAX_RESOLUTION := 64
const MAX_SMOOTHING := 4
## The blend shapes that can move the visible outer surface. `stretch` is excluded: the mod
## always zeroes it (it would scale the whole mesh), so it is never a worn state.
const SHAPES := ["closed", "wink", "anal_open", "anal_stretch", "anal_overstretch",
	"anal_extreme", "ponut_scale"]

static var _cache: Dictionary = {}


## The built field. A typed value object so the controller and the service expose a strong
## signature; the shader-facing values are the texture, the domain, the Z range and the
## normalised field.
class Hull extends RefCounted:
	var field: PackedFloat32Array
	var domain: Rect2
	var z_min := 0.0
	var z_max := 0.0
	var resolution := 0
	var smoothing := 0
	var texture: ImageTexture


## Build (or return the cached) depth field for `mesh`. `field` is row-major over
## `resolution²`, normalised over `z_min`/`z_max`, with `INVALID` in an uncovered cell.
static func build(mesh: ArrayMesh, resolution: int, smoothing: int) -> Hull:
	if mesh == null:
		return null
	var res := clampi(resolution, MIN_RESOLUTION, MAX_RESOLUTION)
	var smooth := clampi(smoothing, 0, MAX_SMOOTHING)
	var key := "%d|%d|%d" % [mesh.get_rid().get_id(), res, smooth]
	var cached: Variant = _cache.get(key)
	if cached is Hull:
		return cached as Hull
	var built := _build(mesh, res, smooth)
	if built != null:
		_cache[key] = built
	return built


## Drop every cached field. The debug Rebuild button and a precision edit call this; the next
## `build()` is the one-time cost.
static func clear_cache() -> void:
	_cache.clear()


static func _build(mesh: ArrayMesh, res: int, smooth: int) -> Hull:
	var surfaces: Array[Dictionary] = []
	var x_min := INF
	var y_min := INF
	var x_max := -INF
	var y_max := -INF
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty() or indices.is_empty():
			continue
		var shapes: Array = mesh.surface_get_blend_shape_arrays(surface)
		var shape_verts: Array[PackedVector3Array] = []
		for i in shapes.size():
			var shape: Array = shapes[i]
			if shape.is_empty() or shape[Mesh.ARRAY_VERTEX] == null:
				shape_verts.append(PackedVector3Array())
				continue
			var sv: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			shape_verts.append(sv if sv.size() == verts.size() else PackedVector3Array())
		var tris: Array[Vector3i] = []
		for t in range(0, indices.size(), 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if a < 0 or b < 0 or c < 0:
				continue
			if a >= verts.size() or b >= verts.size() or c >= verts.size():
				continue
			var normal := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			if normal.length_squared() < 0.000000000001:
				continue
			normal = normal.normalized()
			# Orient with the authored vertex normals so a flipped winding cannot keep an inner
			# wall in the field.
			if normals.size() == verts.size():
				var authored := normals[a] + normals[b] + normals[c]
				if authored.length_squared() > 0.000000000001 \
						and normal.dot(authored.normalized()) < 0.0:
					normal = -normal
			if normal.z <= OUTER_NORMAL_Z:
				continue
			tris.append(Vector3i(a, b, c))
			for index: int in [a, b, c]:
				var p := verts[index]
				x_min = minf(x_min, p.x)
				y_min = minf(y_min, p.y)
				x_max = maxf(x_max, p.x)
				y_max = maxf(y_max, p.y)
		if tris.is_empty():
			continue
		surfaces.append({
			"verts": verts,
			"tris": tris,
			"shapes": shape_verts,
		})
	if surfaces.is_empty() or not is_finite(x_min) or x_max <= x_min or y_max <= y_min:
		return null
	var domain := Rect2(x_min - DOMAIN_MARGIN, y_min - DOMAIN_MARGIN,
		(x_max - x_min) + DOMAIN_MARGIN * 2.0, (y_max - y_min) + DOMAIN_MARGIN * 2.0)
	var cell := Vector2(domain.size.x / float(res), domain.size.y / float(res))
	var best := PackedFloat32Array()
	best.resize(res * res)
	best.fill(-INF)
	var z_min := INF
	var z_max := -INF
	for surface: Dictionary in surfaces:
		var verts: PackedVector3Array = surface["verts"]
		var tris: Array[Vector3i] = surface["tris"]
		var shapes: Array[PackedVector3Array] = surface["shapes"]
		var layers: Array[PackedVector3Array] = [verts]
		for i in shapes.size():
			if not str(mesh.get_blend_shape_name(i)) in SHAPES:
				continue
			var sv: PackedVector3Array = shapes[i]
			if not sv.is_empty():
				layers.append(sv)
		for layer: PackedVector3Array in layers:
			for tri: Vector3i in tris:
				var pa := layer[tri.x]
				var pb := layer[tri.y]
				var pc := layer[tri.z]
				z_min = minf(z_min, minf(pa.z, minf(pb.z, pc.z)))
				z_max = maxf(z_max, maxf(pa.z, maxf(pb.z, pc.z)))
				_rasterise(best, res, domain, cell, pa, pb, pc)
	if z_max <= z_min:
		return null
	best = _dilate(best, res)
	best = _smooth(best, res, smooth)
	var span := z_max - z_min
	if span <= 0.0:
		span = 1.0
	var field := PackedFloat32Array()
	field.resize(res * res)
	var image := Image.create(res, res, false, Image.FORMAT_RF)
	for j in res:
		for i in res:
			var index := j * res + i
			var value := best[index]
			var normalized := INVALID
			if value != -INF:
				normalized = clampf((value - z_min) / span, 0.0, 1.0)
			field[index] = normalized
			image.set_pixel(i, j, Color(normalized, 0.0, 0.0, 1.0))
	var hull := Hull.new()
	hull.field = field
	hull.domain = domain
	hull.z_min = z_min
	hull.z_max = z_max
	hull.resolution = res
	hull.smoothing = smooth
	hull.texture = ImageTexture.create_from_image(image)
	return hull


## Store the maximum Z of `pa`/`pb`/`pc` over the grid cells whose centre lies inside the
## triangle's X/Y projection, and at each corner's own cell so a thin triangle still lands.
static func _rasterise(best: PackedFloat32Array, res: int, domain: Rect2, cell: Vector2,
		pa: Vector3, pb: Vector3, pc: Vector3) -> void:
	var min_x := minf(pa.x, minf(pb.x, pc.x))
	var max_x := maxf(pa.x, maxf(pb.x, pc.x))
	var min_y := minf(pa.y, minf(pb.y, pc.y))
	var max_y := maxf(pa.y, maxf(pb.y, pc.y))
	var i0 := clampi(floori((min_x - domain.position.x) / cell.x), 0, res - 1)
	var i1 := clampi(floori((max_x - domain.position.x) / cell.x), 0, res - 1)
	var j0 := clampi(floori((min_y - domain.position.y) / cell.y), 0, res - 1)
	var j1 := clampi(floori((max_y - domain.position.y) / cell.y), 0, res - 1)
	var a2 := Vector2(pa.x, pa.y)
	var b2 := Vector2(pb.x, pb.y)
	var c2 := Vector2(pc.x, pc.y)
	var area := (b2 - a2).cross(c2 - a2)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if absf(area) <= 0.000000000001:
				continue
			var p := Vector2(domain.position.x + (float(i) + 0.5) * cell.x,
				domain.position.y + (float(j) + 0.5) * cell.y)
			var wa := (b2 - p).cross(c2 - p) / area
			var wb := (c2 - p).cross(a2 - p) / area
			var wc := (a2 - p).cross(b2 - p) / area
			if wa < -0.001 or wb < -0.001 or wc < -0.001:
				continue
			var index := j * res + i
			var z := wa * pa.z + wb * pb.z + wc * pc.z
			if z > best[index]:
				best[index] = z
	for p: Vector3 in [pa, pb, pc]:
		var i := clampi(floori((p.x - domain.position.x) / cell.x), 0, res - 1)
		var j := clampi(floori((p.y - domain.position.y) / cell.y), 0, res - 1)
		var index := j * res + i
		if p.z > best[index]:
			best[index] = p.z


## Fill empty cells with the maximum of their 8 neighbours. The field is a height map; a
## nearest-max fill keeps a bump from being cut by a hole between two rasterised triangles.
static func _dilate(best: PackedFloat32Array, res: int) -> PackedFloat32Array:
	for pass_n in DILATE_PASSES:
		var next := best.duplicate()
		var changed := false
		for j in res:
			for i in res:
				var index := j * res + i
				if best[index] != -INF:
					continue
				var value := -INF
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := i + di
						var jj := j + dj
						if ii < 0 or jj < 0 or ii >= res or jj >= res:
							continue
						var other := best[jj * res + ii]
						if other != -INF:
							value = maxf(value, other)
				if value != -INF:
					next[index] = value
					changed = true
		best = next
		if not changed:
			return best
	return best


## Average each covered cell with its covered neighbours, `passes` times. The margin covers the
## small pull-down a smoothing pass can cause; the debug slider chooses the amount.
static func _smooth(best: PackedFloat32Array, res: int, passes: int) -> PackedFloat32Array:
	for pass_n in passes:
		var next := best.duplicate()
		for j in res:
			for i in res:
				var index := j * res + i
				if best[index] == -INF:
					continue
				var total := best[index]
				var count := 1.0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						if di == 0 and dj == 0:
							continue
						var ii := i + di
						var jj := j + dj
						if ii < 0 or jj < 0 or ii >= res or jj >= res:
							continue
						var other := best[jj * res + ii]
						if other == -INF:
							continue
						total += other
						count += 1.0
				next[index] = total / count
		best = next
	return best
