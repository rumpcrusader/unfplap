extends RefCounted
## Carries a mare-shaped part onto another body, changing only its skin binds.
## The rest map is the anatomy's own; the height is found by rays against both bellies.
## Pure: reads only the meshes it is given and the shared mare body scene.

const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const MARE_BODY := "res://world/characters/body_shapes/mare.scn"

## Hand placement per body-fit key, in her rest space (metres at her own size).
const PART_OFFSETS := {
	"celestia": Vector3(0.0, 0.0, 0.0759),
}

static var _mare: Array = []        # [verts, index] of the mare body, loaded once
static var _maps: Dictionary = {}   # "<her body mesh rid>|<part mesh rid>|<fit id>" -> Transform3D


## Mare rest space -> her rest space: scaled about her anatomy anchor like the anatomy itself, plus
## her hand placement (PART_OFFSETS). IDENTITY for an ordinary body (empty profile).
static func base_map(profile: Array, who := "") -> Transform3D:
	if profile.size() < 3:
		return Transform3D.IDENTITY
	var size := float(profile[2])
	var anchor := Vector3(0.0, float(profile[0]), float(profile[1]))
	var mare_anchor := Vector3(0.0, BODY_PROFILE.WINKING_REAR_Y, BODY_PROFILE.WINKING_REAR_Z)
	var map := Transform3D(Basis.from_scale(Vector3.ONE * size), anchor - mare_anchor * size)
	var offset: Variant = PART_OFFSETS.get(who, null)
	if offset is Vector3:
		map.origin += offset
	return map


## The mare-rest -> her-rest map for `part` on `body` with her `profile`, or IDENTITY when it
## cannot be made.
static func part_map(part: MeshInstance3D, body: MeshInstance3D, profile: Array,
		who := "") -> Transform3D:
	if profile.size() < 3 or part == null or part.mesh == null or body == null or body.mesh == null:
		return Transform3D.IDENTITY
	var key := "%d|%d|%s" % [body.mesh.get_rid().get_id(), part.mesh.get_rid().get_id(), who]
	if _maps.has(key):
		return _maps[key]
	var size := float(profile[2])
	var map := base_map(profile, who)
	# Where the part meets the body: its top vertices. At rest her skin puts a part vertex v at
	# map * v, so each one is measured against the mare's belly above v and hers above map * v,
	# and the median difference moves the part onto her.
	var part_arrays := _arrays(part.mesh)
	var box := part.mesh.get_aabb()
	var mare := _mare_body()
	var her: Array = _arrays(body.mesh)
	var shifts: Array[float] = []
	if not mare.is_empty() and not her.is_empty() and not part_arrays.is_empty():
		var points: PackedVector3Array = part_arrays[0]
		var step := maxi(1, points.size() / 400)
		for n in range(0, points.size(), step):
			var p := points[n]
			if p.y < box.end.y - box.size.y * 0.15:
				continue
			var mare_y := _surface_y(mare[0], mare[1], p)
			var at := map * p
			var her_y := _surface_y(her[0], her[1], at)
			if not is_finite(mare_y) or not is_finite(her_y):
				continue
			shifts.append((her_y - (mare_y - p.y) * size) - at.y)
	var shift := 0.0
	if not shifts.is_empty():
		shifts.sort()
		shift = shifts[shifts.size() / 2]
		map.origin.y += shift
	_maps[key] = map
	LOG.debug("%s fitted to a body: size %.3f, belly shift %+.3f m (%d points)", [
		part.name, size, shift, shifts.size()])
	return map


## The height of the body surface straight above or below `at` that is nearest to it, or INF.
static func _surface_y(verts: PackedVector3Array, index: PackedInt32Array, at: Vector3) -> float:
	var best := INF
	var best_gap := INF
	for t in range(0, index.size(), 3):
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		if at.x < minf(a.x, minf(b.x, c.x)) or at.x > maxf(a.x, maxf(b.x, c.x)) \
				or at.z < minf(a.z, minf(b.z, c.z)) or at.z > maxf(a.z, maxf(b.z, c.z)):
			continue
		# Barycentric in the horizontal plane.
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(at.x - a.x, at.z - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var v := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if v < 0.0 or w < 0.0 or v + w > 1.0:
			continue
		var y := a.y + (b.y - a.y) * v + (c.y - a.y) * w
		var gap := absf(y - at.y)
		if gap < best_gap:
			best_gap = gap
			best = y
	return best


static func _arrays(mesh: Mesh) -> Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return []
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
			if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var start := verts.size()
		verts.append_array(v)
		if i.is_empty():
			for n in v.size():
				index.append(start + n)
		else:
			for n in i:
				index.append(start + n)
	return [verts, index]


static func _mare_body() -> Array:
	if not _mare.is_empty():
		return _mare
	var scene := load(MARE_BODY) as PackedScene
	var holder: Node = scene.instantiate() if scene != null else null
	var body := holder.find_child("MareBody", true, false) as MeshInstance3D \
		if holder != null else null
	if body != null:
		_mare = _arrays(body.mesh)
	if holder != null:
		holder.free()
	return _mare
