extends RefCounted
## A satin tail bow at the base of a mare's tail, worn as a normal accessory: attached to the
## hair rig's `mTail1` through a BoneAttachment3D, registered in her `identity.accessories` like
## the game's own show pieces (Braeburn's hat, Vinyl's glasses), and rebuilt as one unskinned
## mesh so the merged near mesh leaves it alone and the far mesh carries it rigidly.
##
## The game's wardrobe (`pony_wardrobe.gd`) owns its own `KINDS` and slots; a mod cannot add one
## there without editing a game script, so this file owns the piece and its worn state instead.
## The state lives in `Mods.state("unfplap").tail_bows`, keyed by pony id.
##
## The design is a tied cheer bow: the ribbon is wound twice around the tail, gathered into a
## knot on the outside, and two flat loops spiral out of the gather. Each loop is a wide ribbon
## band wound in a flat spiral, so the face reads as folded satin with a crease and a cut end
## instead of a ring. The bow hangs in the plane square to her tail, centred on the tail itself.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const NODE_NAME := "TailBow"
const ATTACHMENT_NAME := "TailBowAttachment"
const TAIL_BONE := "mTail1"
const NEXT_BONE := "mTail2"
const VARIANT_TAG := "|tail-bow"
const STATE_KEY := "tail_bows"
## Fallback tail radius when the mesh cannot be measured (identity.tail_segment_radii mid value).
const FALLBACK_RADIUS := 0.065
const RADIUS_WINDOW := 0.010
const RADIUS_PERCENTILE := 0.45

## Satin dyes. The key is stored in settings; the bow keeps its colour for every pony.
const COLOURS := {
	"red": Color("c8102e"),
	"rose": Color("d94b8a"),
	"pink": Color("ffa8c7"),
	"cream": Color("f4e8d6"),
	"purple": Color("8d6bd1"),
	"midnight": Color("2f3559"),
}
const DEFAULT_COLOUR := "red"

## Measured tail radii, keyed by pony identity and the point down the tail.
static var _radii: Dictionary = {}


static func feature_on() -> bool:
	return TUNABLES.get_bool("features.tail_bow")


# --- Worn state -----------------------------------------------------------------------------

## Every pony id wearing a bow: `{id: {}}`.
static func worn() -> Dictionary:
	var mods := _mods()
	if mods == null or not mods.has_method("state"):
		return {}
	var state: Variant = mods.call("state", "unfplap")
	if not state is Dictionary:
		return {}
	var rows: Variant = (state as Dictionary).get(STATE_KEY)
	if not rows is Dictionary:
		rows = {}
		(state as Dictionary)[STATE_KEY] = rows
	return rows


static func worn_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


static func wears_id(id: String) -> bool:
	return not id.is_empty() and worn().has(id)


static func wears(pony: Node) -> bool:
	return wears_id(worn_id(pony))


## Put a bow on a pony's worn record or take it off, then save the world.
static func set_worn(id: String, on: bool) -> void:
	if id.is_empty():
		return
	var rows := worn()
	if on:
		rows[id] = {}
	else:
		rows.erase(id)
	var mods := _mods()
	if mods != null and mods.has_method("save_changed"):
		mods.call("save_changed")


## The satin dye: `presentation.tail_bow.colour` names one key of `COLOURS`.
static func colour(cfg: Dictionary) -> Color:
	return COLOURS.get(str(cfg.get("colour", DEFAULT_COLOUR)), COLOURS[DEFAULT_COLOUR])


# --- Attach ---------------------------------------------------------------------------------

## The bow currently on this pony, or null.
static func piece(pony: Node) -> MeshInstance3D:
	if not is_instance_valid(pony):
		return null
	var found := pony.find_child(NODE_NAME, true, false)
	return found as MeshInstance3D if found is MeshInstance3D else null


## Attach the bow to `pony`'s tail root and register it as one of her accessories.
## Returns the mesh, or null when her hair rig is not ready yet.
static func attach(pony: Node3D) -> MeshInstance3D:
	if not is_instance_valid(pony):
		return null
	var existing := piece(pony)
	if is_instance_valid(existing):
		return existing
	var sk := hair_skeleton(pony)
	if sk == null or sk.find_bone(TAIL_BONE) < 0:
		return null
	var cfg := config()
	var node := build(colour(cfg), cfg, tail_radius(pony, float(cfg.get("along_m", 0.02))))
	var attachment := BoneAttachment3D.new()
	attachment.name = ATTACHMENT_NAME
	attachment.bone_name = TAIL_BONE
	sk.add_child(attachment)
	attachment.add_child(node)
	node.transform = local_transform(sk, pony, cfg)
	_register_accessory(pony, true)
	return node


## Remove the bow and forget the accessory entry. The worn record is the caller's business.
static func detach(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var node := piece(pony)
	if is_instance_valid(node):
		var attachment := node.get_parent()
		if attachment != null:
			attachment.free()
		else:
			node.free()
	_register_accessory(pony, false)


static func refresh(pony: Node) -> void:
	detach(pony)
	attach(pony)


static func hair_skeleton(pony: Node) -> Skeleton3D:
	if not is_instance_valid(pony):
		return null
	var rig: Variant = pony.get("hair_skeleton")
	return rig as Skeleton3D if rig is Skeleton3D else null


## The bow's placement settings, read once per rebuild.
static func config() -> Dictionary:
	return {
		"size": TUNABLES.get_float("presentation.tail_bow.size"),
		"along_m": TUNABLES.get_float("presentation.tail_bow.along_m"),
		"margin_m": TUNABLES.get_float("presentation.tail_bow.margin_m"),
		"loop_scale": TUNABLES.get_float("presentation.tail_bow.loop_scale"),
		"splay_deg": TUNABLES.get_float("presentation.tail_bow.splay_deg"),
		"tilt_deg": TUNABLES.get_float("presentation.tail_bow.tilt_deg"),
		"colour": TUNABLES.get_string("presentation.tail_bow.colour"),
	}


## The tail's radius at `along` metres down the tail, measured from her own tail mesh once and
## cached per identity. The hair fan is much wider than the physics tube, and it differs a lot
## between mares, so the wrap is sized from the visible tail rather than a constant.
static func tail_radius(pony: Node3D, along: float) -> float:
	var identity: Variant = pony.get("identity")
	var key := "%s:%.3f" % [str(identity.get("id")) if identity != null else str(pony.name), along]
	if _radii.has(key):
		return float(_radii[key])
	var measured := _measure_radius(pony, along)
	if measured <= 0.0 and identity != null:
		var radii: Variant = identity.get("tail_segment_radii")
		if radii is Array and (radii as Array).size() > 1:
			measured = float((radii as Array)[1])
	if measured <= 0.0:
		measured = FALLBACK_RADIUS
	_radii[key] = measured
	return measured


## The mesh transform under `mTail1`: centred on the tail axis at `along`, square to the tail,
## with the loops level with her body. Built from the tail bone's rest frame and her body axes,
## so it does not depend on how she was posed when the bow was tied on.
static func local_transform(sk: Skeleton3D, pony: Node3D, cfg: Dictionary) -> Transform3D:
	var root_index := sk.find_bone(TAIL_BONE)
	if root_index < 0:
		return Transform3D.IDENTITY
	var root := sk.get_bone_global_rest(root_index)
	var axis := tail_axis(sk, root_index)
	var frame := sk.global_basis.orthonormalized()
	var body := pony.global_basis.orthonormalized()
	return placement(root, axis, frame.inverse() * body.z, frame.inverse() * body.y,
		cfg.get("size", 1.0), cfg)


## The tail bone's own direction (down her tail) in the hair skeleton's space.
static func tail_axis(sk: Skeleton3D, root_index: int) -> Vector3:
	var next := sk.find_bone(NEXT_BONE)
	if next >= 0:
		var span := sk.get_bone_global_rest(next).origin - sk.get_bone_global_rest(root_index).origin
		if span.length() > 0.0001:
			return span.normalized()
	return Vector3.DOWN


## Pure placement: the bow's transform relative to the tail root bone. `axis` is down her tail,
## `back`/`up` are her body axes in the skeleton's own space.
static func placement(root: Transform3D, axis: Vector3, back: Vector3, up: Vector3,
		size: float, cfg: Dictionary) -> Transform3D:
	var scale := maxf(size, 0.01)
	var z := axis.normalized()
	if z.length() < 0.0001:
		z = Vector3.DOWN
	var y := up.normalized() - z * up.normalized().dot(z)
	if y.length() < 0.0001:
		y = back.normalized() - z * back.normalized().dot(z)
	y = y.normalized()
	var x := y.cross(z).normalized()
	var basis := Basis(x, y, z)
	# The bow hangs in the plane square to the tail; the tilt leans the loops up or back.
	basis = basis * Basis(Vector3.RIGHT, deg_to_rad(float(cfg.get("tilt_deg", 0.0))))
	basis = basis.scaled(Vector3.ONE * scale)
	var origin := root.origin + z * float(cfg.get("along_m", 0.02)) * scale
	return root.affine_inverse() * Transform3D(basis, origin)


static func _measure_radius(pony: Node3D, along: float) -> float:
	var sk := hair_skeleton(pony)
	if sk == null:
		return 0.0
	var root_index := sk.find_bone(TAIL_BONE)
	if root_index < 0:
		return 0.0
	var tail := _tail_mesh(pony)
	if tail == null or tail.mesh == null or tail.skin == null:
		return 0.0
	var skin := tail.skin
	# Bind transforms are constant: resolve them once per bind, not once per vertex.
	var binds: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		var bone := sk.find_bone(skin.get_bind_name(i))
		if bone < 0:
			bone = skin.get_bind_bone(i)
		binds.append(sk.get_bone_global_rest(bone) * skin.get_bind_pose(i))
	var root_bind := -1
	for i: int in skin.get_bind_count():
		var bone := sk.find_bone(skin.get_bind_name(i))
		if bone < 0:
			bone = skin.get_bind_bone(i)
		if bone == root_index:
			root_bind = i
			break
	var root_rest := sk.get_bone_global_rest(root_index)
	var frame := root_rest.affine_inverse()
	var axis := tail_axis(sk, root_index)
	var radii := PackedFloat32Array()
	for surface: int in tail.mesh.get_surface_count():
		var arrays: Array = tail.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or ids.is_empty():
			continue
		var stride := ids.size() / verts.size()
		for v: int in verts.size():
			var point := Vector3.ZERO
			for k: int in stride:
				var w := weights[v * stride + k]
				if w > 0.0:
					point += (binds[ids[v * stride + k]] * verts[v]) * w
			var local := frame * point
			var reach := local.dot(axis)
			if absf(reach - along) > RADIUS_WINDOW:
				continue
			radii.append((local - axis * reach).length())
	if radii.is_empty():
		return 0.0
	radii.sort()
	# The widest strand of a bushy tail is not its body: use the mass of the cross-section.
	return radii[clampi(int(float(radii.size() - 1) * RADIUS_PERCENTILE), 0, radii.size() - 1)]


static func _tail_mesh(pony: Node3D) -> MeshInstance3D:
	var hair: Variant = pony.get("hair")
	var identity: Variant = pony.get("identity")
	if not hair is Node3D or identity == null:
		return null
	var found := (hair as Node3D).find_child(str(identity.get("hair_prefix")) + "DevkitTail",
		true, false)
	if found is MeshInstance3D:
		return found as MeshInstance3D
	for node: Node in (hair as Node3D).find_children("*", "MeshInstance3D", true, false):
		if str(node.name).contains("Tail") and not str(node.name).ends_with("LOD1"):
			return node as MeshInstance3D
	return null


static func _register_accessory(pony: Node, on: bool) -> void:
	var identity: Variant = pony.get("identity")
	if identity is Resource:
		var current: Resource = identity as Resource
		var names: Variant = current.get("accessories")
		if names is Array:
			var kept: Array[String] = []
			for name: Variant in names:
				if str(name) != NODE_NAME:
					kept.append(str(name))
			var has := kept.size() != (names as Array).size()
			if on == has:
				return
			if on:
				kept.append(NODE_NAME)
			var copy := current.duplicate() as Resource
			if copy == null:
				return
			# `accessories` is a typed Array[String]; an untyped array would be rejected.
			copy.set("accessories", kept)
			pony.set("identity", copy)
	_refresh_variant(pony, on)


## Both merged meshes cache by geometry variant, so a new accessory needs a fresh key.
static func _refresh_variant(pony: Node, on: bool) -> void:
	if not pony.has_method("refresh_geometry_variant"):
		return
	var variant := str(pony.get_meta("geometry_variant", "")).replace(VARIANT_TAG, "")
	if on:
		variant += VARIANT_TAG
	pony.call("refresh_geometry_variant", variant)


# --- Mesh -----------------------------------------------------------------------------------

const LOOP_SAMPLES := 16
const LOOP_CROSS := 8
const LOOP_REACH := 1.72
const LOOP_WIDTH := 0.92
const LOOP_PINCH := 0.16
const LOOP_THICK := 0.0018
## One tight band around the dock and tail base: the knot and the two loops sit on it, and there
## are no extra winding turns.
const WRAP_TURNS := 1
const WRAP_WIDTH := 0.34
const WRAP_THICK := 0.0022
const WRAP_STEP := 0.0
const KNOT_RADII := Vector3(0.30, 0.24, 0.22)


## The whole bow as one unskinned MeshInstance3D. `radius` is the measured tail radius at the
## tie point; the rig it hangs from is already scaled to her size.
static func build(colour: Color, cfg: Dictionary, radius: float) -> MeshInstance3D:
	var r := maxf(radius, 0.01)
	var mesh := ArrayMesh.new()
	var splay := deg_to_rad(float(cfg.get("splay_deg", 14.0)))
	var loop_scale := maxf(float(cfg.get("loop_scale", 1.0)), 0.05) \
		* maxf(float(cfg.get("size", 1.0)), 0.05)
	_commit_wraps(mesh, r, cfg, colour)
	_commit_loops(mesh, r, loop_scale, splay, colour)
	_commit_knot(mesh, r, colour)
	var node := MeshInstance3D.new()
	node.name = NODE_NAME
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = 0.4
	return node


static func satin(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.3
	material.metallic = 0.1
	material.rim_enabled = true
	material.rim = 0.5
	material.rim_tint = 0.3
	# Satin has no wrong side: both faces read as fabric, and winding cannot hide a surface.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## The band cinched around the dock and tail base. It hugs the measured surface with a few
## millimetres of clearance, so it reads as pulled tight rather than resting on the fur.
static func _commit_wraps(mesh: ArrayMesh, r: float, cfg: Dictionary, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var margin := float(cfg.get("margin_m", 0.002))
	var band := r + margin
	for turn: int in WRAP_TURNS:
		var centre := Vector3(0.0, 0.0, (float(turn) - 0.5) * WRAP_STEP * r)
		_add_ring(st, centre, band, WRAP_WIDTH * r * 0.5, WRAP_THICK * r / 0.05,
			Basis.IDENTITY, 40, 6)
	_commit(mesh, st, satin(colour.darkened(0.08)))


## Two folded satin petals, gathered at the knot: each one is a solid leaf with a ridge down its
## length and a rolled rim where the ribbon folds back, which is what makes it read as a bow.
static func _commit_loops(mesh: ArrayMesh, r: float, loop_scale: float, splay: float,
		colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := r * LOOP_REACH * loop_scale
	var half_width := r * LOOP_WIDTH * loop_scale
	var knot := Vector3(0.0, r * 0.80, 0.0)
	for side: float in [-1.0, 1.0]:
		# Each loop starts outboard of the knot, so the two read as separate wings.
		var base := knot + Vector3(side * r * 0.52, 0.0, 0.0)
		_add_petal(st, base, side, length, half_width, splay, r)
	_commit(mesh, st, satin(colour))


static func _add_petal(st: SurfaceTool, knot: Vector3, side: float, length: float,
		half_width: float, splay: float, r: float) -> void:
	var thick := LOOP_THICK * r / 0.05
	# Each petal points outward and a little up, then opens away from its twin.
	var direction := Vector3(side, 0.16, 0.0).normalized()
	var frame := Basis(Vector3.BACK, atan2(direction.y, direction.x))
	frame = frame * Basis(Vector3.UP, side * splay) * Basis(Vector3.RIGHT, -0.16)
	var face: Vector3 = frame * Vector3.BACK
	var lining: Vector3 = frame * -Vector3.BACK
	var edge: Vector3 = frame * Vector3.UP
	var rows: Array[Array] = []
	for i: int in LOOP_SAMPLES + 1:
		var u := float(i) / float(LOOP_SAMPLES)
		var shape := smoothstep(0.0, 0.18, u) * (1.0 - 0.88 * smoothstep(0.55, 1.0, u))
		var half := half_width * lerpf(LOOP_PINCH, 1.0, shape)
		var along := length * u
		var bulge := sin(PI * u) * length * 0.10
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		for v: int in LOOP_CROSS + 1:
			var t := float(v) / float(LOOP_CROSS) * 2.0 - 1.0
			# The ribbon folds down the middle of the loop and rolls back at its rim.
			var ridge := half_width * 0.17 * pow(1.0 - absf(t), 1.6) - half_width * 0.10 \
				* smoothstep(0.72, 1.0, absf(t))
			var roll := thick + ridge
			var offset := Vector3(along - length * 0.16, t * half, bulge)
			front.append(knot + frame * (offset + Vector3(0.0, 0.0, roll)))
			back.append(knot + frame * (offset - Vector3(0.0, 0.0, roll)))
		rows.append([front, back])
	for i: int in LOOP_SAMPLES:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		var front_a: PackedVector3Array = a[0]
		var front_b: PackedVector3Array = b[0]
		var back_a: PackedVector3Array = a[1]
		var back_b: PackedVector3Array = b[1]
		for v: int in LOOP_CROSS:
			_quad(st, front_a[v], face, front_a[v + 1], face, front_b[v + 1], face,
				front_b[v], face)
			_quad(st, back_a[v], lining, back_b[v], lining, back_b[v + 1], lining,
				back_a[v + 1], lining)
		# The rolled rim on both edges.
		_quad(st, back_a[0], -edge, front_a[0], -edge, front_b[0], -edge, back_b[0], -edge)
		_quad(st, front_a[LOOP_CROSS], edge, back_a[LOOP_CROSS], edge,
			back_b[LOOP_CROSS], edge, front_b[LOOP_CROSS], edge)
	# Close the outer end of the leaf.
	var last: Array = rows[rows.size() - 1]
	var front_end: PackedVector3Array = last[0]
	var back_end: PackedVector3Array = last[1]
	for v: int in LOOP_CROSS:
		_quad(st, front_end[v], edge, back_end[v], edge, back_end[v + 1], edge,
			front_end[v + 1], edge)


## The gathered knot: a pinched satin bundle with a ribbon crossing over it.
static func _commit_knot(mesh: ArrayMesh, r: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, r * 0.92, 0.0)
	_add_ellipsoid(st, centre, KNOT_RADII * r, 8, 14)
	# The band that gathers the loops, crossing the knot on the diagonal like a tied ribbon.
	_add_ring(st, centre, r * 0.34, r * 0.13, r * 0.08,
		Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.UP, 0.45), 24, 6)
	_commit(mesh, st, satin(colour.lightened(0.06)))


static func _commit(mesh: ArrayMesh, st: SurfaceTool, material: Material) -> void:
	var index := mesh.get_surface_count()
	st.commit(mesh)
	mesh.surface_set_material(index, material)


static func _tri(st: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3,
		c: Vector3, nc: Vector3) -> void:
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3,
		c: Vector3, nc: Vector3, d: Vector3, nd: Vector3) -> void:
	_tri(st, a, na, b, nb, c, nc)
	_tri(st, a, na, c, nc, d, nd)


static func _add_ellipsoid(st: SurfaceTool, centre: Vector3, radii: Vector3, rings: int,
		segments: int) -> void:
	for i: int in rings:
		var phi0 := PI * float(i) / float(rings) - PI * 0.5
		var phi1 := PI * float(i + 1) / float(rings) - PI * 0.5
		for j: int in segments:
			var th0 := TAU * float(j) / float(segments)
			var th1 := TAU * float(j + 1) / float(segments)
			_quad(st,
				_ellipsoid_point(centre, radii, phi0, th0),
				_ellipsoid_normal(radii, phi0, th0),
				_ellipsoid_point(centre, radii, phi1, th0),
				_ellipsoid_normal(radii, phi1, th0),
				_ellipsoid_point(centre, radii, phi1, th1),
				_ellipsoid_normal(radii, phi1, th1),
				_ellipsoid_point(centre, radii, phi0, th1),
				_ellipsoid_normal(radii, phi0, th1))


static func _ellipsoid_point(centre: Vector3, radii: Vector3, phi: float, theta: float) -> Vector3:
	return centre + Vector3(cos(phi) * cos(theta) * radii.x, sin(phi) * radii.y,
		cos(phi) * sin(theta) * radii.z)


static func _ellipsoid_normal(radii: Vector3, phi: float, theta: float) -> Vector3:
	return Vector3(cos(phi) * cos(theta) / radii.x, sin(phi) / radii.y,
		cos(phi) * sin(theta) / radii.z).normalized()


## A band of ribbon around the tail: an open flat ring, its width along the tail axis.
static func _add_ring(st: SurfaceTool, centre: Vector3, radius: float, half_width: float,
		half_thick: float, lean: Basis, steps: int, cross: int) -> void:
	for i: int in steps:
		var u0 := TAU * float(i) / float(steps)
		var u1 := TAU * float(i + 1) / float(steps)
		for j: int in cross:
			var v0 := TAU * float(j) / float(cross)
			var v1 := TAU * float(j + 1) / float(cross)
			_quad(st,
				centre + lean * _ring_point(radius, half_width, half_thick, u0, v0),
				lean * _ring_normal(u0, v0),
				centre + lean * _ring_point(radius, half_width, half_thick, u1, v0),
				lean * _ring_normal(u1, v0),
				centre + lean * _ring_point(radius, half_width, half_thick, u1, v1),
				lean * _ring_normal(u1, v1),
				centre + lean * _ring_point(radius, half_width, half_thick, u0, v1),
				lean * _ring_normal(u0, v1))


## Ring point in the XY plane with the ribbon's width along Z and its thickness radial.
static func _ring_point(radius: float, half_width: float, half_thick: float, u: float,
		v: float) -> Vector3:
	var reach := radius + half_thick * cos(v)
	return Vector3(cos(u) * reach, sin(u) * reach, half_width * sin(v))


static func _ring_normal(u: float, v: float) -> Vector3:
	return Vector3(cos(u) * cos(v), sin(u) * cos(v), sin(v))


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
