extends RefCounted
## Teats grown from the mare's own belly: a patch of her rest surface found by vertical rays,
## pushed into two lobes with nipples, then skinned with her own weights.
## `CUSTOM0.x` is the sway weight, 0 at the base and 1 at the tip, so the base holds.
## Vertex colour follows the old teats asset: G the skin/nipple mix, B the coat weight, fading
## out where the lobes rise. Sizes are in mare metres and scale with the body.

## The pair's centre on the mare body (her rest space): between the hind legs, on the belly.
const MARE_CENTRE := Vector3(0.0, 0.391, 0.180)
const SIZE_MAX := 1.4

## Grid: rings from the centre out (U_MAX past the lobes is the flat coat skirt) and segments round.
const RINGS := 60
const SEGMENTS := 120
const U_LOBES := 1.0
const U_MAX := 1.32
## How far the skirt floats off her coat (mare metres), so it never fights her body's depth.
const SKIN_LIFT := 0.0007

static var _cache: Dictionary = {}
static var _surfaces: Dictionary = {}


## The shape for a size 0..SIZE_MAX, in mare metres.
static func dims(size: float) -> Dictionary:
	var s := clampf(size, 0.0, SIZE_MAX)
	return {
		"spread": 0.0185 + 0.0085 * s,     # lobe centre from the midline
		"radius": 0.0195 + 0.0125 * s,     # lobe radius across her
		"length": 1.18,                    # lobe length along her, over its radius
		"height": 0.012 + 0.024 * s,       # how far a lobe hangs
		"droop": 0.35 + 0.25 * s,          # fuller ones hang lower at the tip than at the base
		"nipple_r": 0.0042 + 0.0016 * s,
		"nipple_len": 0.0055 + 0.0045 * s,
		"nipple_out": 0.18,                # nipple offset outward, over the lobe radius
		"nipple_back": 0.10,               # and back toward her legs
	}


## The teats for `body` (her MareBody), centred at `centre` in her rest space (the mare's for a
## mare body) and scaled by `scale`, or null when her belly is not found there.
static func build(body: MeshInstance3D, centre: Vector3, scale: float, size: float) -> ArrayMesh:
	if body == null or body.mesh == null or body.skin == null:
		return null
	# Every mare shares one body mesh, so a few rounded sizes cover a whole town.
	size = snappedf(clampf(size, 0.0, SIZE_MAX), 0.05)
	var key := "%d|%.4f|%.4f|%.4f|%.4f|%.3f" % [body.mesh.get_rid().get_id(), centre.x, centre.y, centre.z, scale, size]
	if _cache.has(key):
		return _cache[key]
	var surface_key := body.mesh.get_rid().get_id()
	if not _surfaces.has(surface_key):
		_surfaces[surface_key] = _Surface.new(body.mesh)
	var surface: _Surface = _surfaces[surface_key]
	if surface.tris.is_empty():
		return null
	var d := dims(size)
	var spread: float = d.spread * scale
	var radius: float = d.radius * scale
	var rz: float = radius * float(d.length)
	var height: float = d.height * scale
	var extent := Vector2(spread + radius, rz)
	# Her belly under the centre: the reference height every ray keeps close to.
	# The centre may be well off her belly on a body unlike the mare (the princesses' own), so it
	# looks far; at the midline there is nothing else facing down between her legs.
	var hit := surface.down_hit(Vector2(centre.x, centre.z), centre.y, 0.3 * scale)
	if hit.is_empty():
		return null
	var base_y: float = hit.point.y
	var per := surface.per
	var pos := PackedVector3Array()
	var base := PackedVector3Array()
	var base_n := PackedVector3Array()
	var colors := PackedColorArray()
	var sway := PackedFloat32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var uv := PackedVector2Array()
	var nipples := [Vector2(-(spread + radius * float(d.nipple_out)), radius * float(d.nipple_back)),
		Vector2(spread + radius * float(d.nipple_out), radius * float(d.nipple_back))]
	var rings: Array = []
	# Each ray keeps close to the one inside it at the same angle, so it follows her belly's curve
	# instead of jumping to another surface.
	var last_y := PackedFloat32Array(); last_y.resize(SEGMENTS); last_y.fill(base_y)
	# Where her surface turns away from the belly (the inner thighs), a ray carries on along the
	# belly's own plane from its last good hit instead: the patch then runs into her thigh, where
	# it is hidden, rather than climbing the leg or leaving a ragged edge.
	var belly_n: Vector3 = hit.normal
	var good: Array = []; good.resize(SEGMENTS)
	for r in RINGS + 1:
		var u := U_MAX * float(r) / float(RINGS)
		var ring: Array[int] = []
		var count := 1 if r == 0 else SEGMENTS
		for k in count:
			var angle := TAU * float(k) / float(SEGMENTS)
			var local := Vector2(cos(angle) * extent.x, sin(angle) * extent.y) * u
			var at := Vector2(centre.x, centre.z) + local
			var under := surface.down_hit(at, last_y[k % SEGMENTS], 0.02 * scale)
			if not under.is_empty() and (under.normal as Vector3).dot(belly_n) < 0.55:
				under = {}
			if r > 0:
				if not under.is_empty() and good[k] == null:
					good[k] = under
				elif under.is_empty() or good[k] is Dictionary and bool((good[k] as Dictionary).get("carried", false)):
					var last: Variant = good[k]
					if last is Dictionary:
						var lp: Vector3 = (last as Dictionary).point
						var ln: Vector3 = (last as Dictionary).normal
						# Her belly's plane at the last good hit, straight above or below this point.
						var ny := ln.y if absf(ln.y) > 0.2 else -0.2
						var y := lp.y - ((at.x - lp.x) * ln.x + (at.y - lp.z) * ln.z) / ny
						under = {"point": Vector3(at.x, y, at.y), "normal": ln,
							"weights": (last as Dictionary).weights, "carried": true}
						good[k] = under
				else:
					good[k] = under
			if not under.is_empty():
				if r == 0: last_y.fill(under.point.y)
				else: last_y[k] = under.point.y
			if under.is_empty():
				ring.append(-1)
				continue
			var p: Vector3 = under.point
			var n: Vector3 = under.normal
			# The lobes: two rounded domes, joined by a soft union with a shallow cleft between.
			var a := _dome(local, Vector2(-spread, 0.0), radius, rz)
			var b := _dome(local, Vector2(spread, 0.0), radius, rz)
			var lobe := pow(pow(a, 4.0) + pow(b, 4.0), 0.25)
			# The nipples, rounded at the tip, with a short fillet into the lobe.
			var nip := 0.0
			var on_nipple := false
			for c: Vector2 in nipples:
				var dn := local.distance_to(c) / (float(d.nipple_r) * scale)
				nip = maxf(nip, (1.0 - smoothstep(0.62, 1.25, dn)) + 0.18 * maxf(0.0, 1.0 - dn * dn / 0.36))
				on_nipple = on_nipple or dn < 1.12
			var rise := height * lobe + float(d.nipple_len) * scale * nip * smoothstep(0.15, 0.5, lobe)
			# Carried past her belly: only the lobes themselves go on (into her thigh, out of
			# sight); the flat skirt there would stand off her leg as a sheet.
			if bool(under.get("carried", false)) and lobe < 0.08:
				ring.append(-1)
				continue
			# They hang: the further from the belly, the more straight down (and a little back).
			var hang := (n.lerp(Vector3.DOWN, 0.55 + 0.25 * lobe) + Vector3(0.0, 0.0, 0.08 * float(d.droop) * lobe)).normalized()
			var outward := n * SKIN_LIFT * scale + hang * rise
			var out := p + outward
			pos.append(out)
			base.append(p)
			base_n.append(n)
			var coat := 1.0 - smoothstep(0.02, 0.22, rise / maxf(height, 0.0001))
			coat = maxf(coat, smoothstep(U_LOBES, U_MAX * 0.97, u))
			colors.append(Color(0.0, 0.9 if on_nipple and lobe > 0.15 else 0.7, coat, 1.0))
			# Sway: the tip swings, the base holds; a nipple swings with its tip.
			sway.append(pow(clampf(rise / maxf(height + float(d.nipple_len) * scale, 0.0001), 0.0, 1.0), 1.25))
			uv.append(Vector2(u, angle / TAU))
			var w: Dictionary = under.weights
			var keys := w.keys()
			keys.sort_custom(func(x, y): return w[x] > w[y])
			var total := 0.0
			for slot in mini(per, keys.size()): total += float(w[keys[slot]])
			for slot in per:
				if slot < keys.size() and total > 0.0:
					bones.append(int(keys[slot])); weights.append(float(w[keys[slot]]) / total)
				else:
					bones.append(0); weights.append(0.0)
			ring.append(pos.size() - 1)
		rings.append(ring)
	# Triangles: a fan round the centre, then quads ring to ring. Missing points leave holes only
	# where her belly was not found (off the edge of a strange body).
	var index := PackedInt32Array()
	var c0: int = (rings[0] as Array)[0]
	var first: Array = rings[1]
	for k in SEGMENTS:
		var a: int = first[k]
		var b: int = first[(k + 1) % SEGMENTS]
		if c0 >= 0 and a >= 0 and b >= 0: index.append_array([c0, b, a])
	for r in range(1, RINGS):
		var inner: Array = rings[r]
		var outer: Array = rings[r + 1]
		for k in SEGMENTS:
			var i0: int = inner[k]; var i1: int = inner[(k + 1) % SEGMENTS]
			var o0: int = outer[k]; var o1: int = outer[(k + 1) % SEGMENTS]
			if i0 >= 0 and i1 >= 0 and o0 >= 0: index.append_array([i0, i1, o0])
			if i1 >= 0 and o1 >= 0 and o0 >= 0: index.append_array([i1, o1, o0])
	if index.is_empty():
		return null
	# Winding: Godot's front faces wind clockwise seen from outside, so a face's cross product
	# points into her body (as on her own mesh).
	var t0 := index[0]; var t1 := index[1]; var t2 := index[2]
	var face := (pos[t1] - pos[t0]).cross(pos[t2] - pos[t0])
	if face.dot(base_n[t0]) > 0.0:
		for t in range(0, index.size(), 3):
			var keep := index[t + 1]; index[t + 1] = index[t + 2]; index[t + 2] = keep
	# Smooth normals from the shape, eased into her own normals over the skirt so the light on the
	# rim matches her coat.
	var normals := PackedVector3Array(); normals.resize(pos.size())
	for t in range(0, index.size(), 3):
		var fa := index[t]; var fb := index[t + 1]; var fc := index[t + 2]
		var fn := (pos[fc] - pos[fa]).cross(pos[fb] - pos[fa])
		normals[fa] += fn; normals[fb] += fn; normals[fc] += fn
	for i in pos.size():
		var shaped := normals[i].normalized() if normals[i].length_squared() > 0.0 else base_n[i]
		var blend := smoothstep(U_LOBES * 0.85, U_LOBES * 1.12, uv[i].x)
		normals[i] = shaped.lerp(base_n[i], blend).normalized()
	var custom := PackedFloat32Array()
	for i in pos.size(): custom.append_array([sway[i], 0.0, 0.0, 0.0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = index
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if per == 8: flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.resource_name = "UnfplapTeats"
	_cache[key] = mesh
	return mesh


## 0..1 dome over an oval of half-sizes rx, rz centred at `c`: rounded, flat at the edge.
static func _dome(p: Vector2, c: Vector2, rx: float, rz: float) -> float:
	var q := Vector2((p.x - c.x) / rx, (p.y - c.y) / rz)
	var d2 := q.length_squared()
	return pow(1.0 - d2, 1.6) if d2 < 1.0 else 0.0


## Her rest body for vertical rays: the downward-facing triangles in a grid over x/z.
class _Surface:
	const CELL := 0.01
	var verts: PackedVector3Array
	var normals: PackedVector3Array
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var per := 4
	var tris: PackedInt32Array
	var grid := {}

	func _init(mesh: Mesh) -> void:
		var arrays := mesh.surface_get_arrays(0)
		verts = arrays[Mesh.ARRAY_VERTEX]
		normals = arrays[Mesh.ARRAY_NORMAL]
		bones = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		weights = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or bones.is_empty():
			return
		per = bones.size() / verts.size()
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for t in range(0, index.size(), 3):
			var a := verts[index[t]]; var b := verts[index[t + 1]]; var c := verts[index[t + 2]]
			# The belly faces down; legs and flanks face sideways and are skipped.
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-14 or absf(n.normalized().y) < 0.25:
				continue
			var s := tris.size()
			tris.append_array([index[t], index[t + 1], index[t + 2]])
			var lo := Vector2i(int(floor(minf(a.x, minf(b.x, c.x)) / CELL)), int(floor(minf(a.z, minf(b.z, c.z)) / CELL)))
			var hi := Vector2i(int(floor(maxf(a.x, maxf(b.x, c.x)) / CELL)), int(floor(maxf(a.z, maxf(b.z, c.z)) / CELL)))
			for x in range(lo.x, hi.x + 1):
				for z in range(lo.y, hi.y + 1):
					var k := Vector2i(x, z)
					if not grid.has(k): grid[k] = PackedInt32Array()
					var list: PackedInt32Array = grid[k]
					list.append(s)
					grid[k] = list

	## The surface straight above or below `at` (x, z) whose height is nearest `near_y`, within
	## `window`, facing down: {point, normal, weights {bind: weight}}, or {}.
	func down_hit(at: Vector2, near_y: float, window: float) -> Dictionary:
		var list: Variant = grid.get(Vector2i(int(floor(at.x / CELL)), int(floor(at.y / CELL))))
		if list == null:
			return {}
		var best := {}
		var best_gap := window
		for s: int in (list as PackedInt32Array):
			var ia := tris[s]; var ib := tris[s + 1]; var ic := tris[s + 2]
			var a := verts[ia]; var b := verts[ib]; var c := verts[ic]
			var v0 := Vector2(b.x - a.x, b.z - a.z)
			var v1 := Vector2(c.x - a.x, c.z - a.z)
			var v2 := Vector2(at.x - a.x, at.y - a.z)
			var den := v0.x * v1.y - v1.x * v0.y
			if absf(den) < 1e-14:
				continue
			var v := (v2.x * v1.y - v1.x * v2.y) / den
			var w := (v0.x * v2.y - v2.x * v0.y) / den
			var u := 1.0 - v - w
			if v < -0.0001 or w < -0.0001 or u < -0.0001:
				continue
			var n := (normals[ia] * u + normals[ib] * v + normals[ic] * w).normalized()
			if n.y > -0.2 or absf(n.x) > 0.85:
				continue   # the top of a leg, the back or an inner thigh, not the belly
			var y := a.y * u + b.y * v + c.y * w
			var gap := absf(y - near_y)
			if gap >= best_gap:
				continue
			best_gap = gap
			var mix := {}
			for pair in [[ia, u], [ib, v], [ic, w]]:
				for k in per:
					var wt: float = weights[int(pair[0]) * per + k] * float(pair[1])
					if wt > 0.0:
						var bone := bones[int(pair[0]) * per + k]
						mix[bone] = float(mix.get(bone, 0.0)) + wt
			best = {"point": Vector3(at.x, y, at.y), "normal": n, "weights": mix}
		return best
