extends RefCounted
## A satin tail bow at the base of a mare's tail, worn as a normal accessory: attached to the
## hair rig's `mTail1` through a BoneAttachment3D, registered in her `identity.accessories` like
## the game's own show pieces (Braeburn's hat, Vinyl's glasses), and rebuilt as one unskinned
## mesh so the merged near mesh leaves it alone and the far mesh carries it rigidly.
##
## The game's wardrobe (`pony_wardrobe.gd`) owns its own `KINDS` and slots; a mod cannot add one
## there without editing a game script, so this file owns the piece and its worn state instead.
## The state lives in `Mods.state("unfplap").tail_bows`, keyed by pony id.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const NODE_NAME := "TailBow"
const ATTACHMENT_NAME := "TailBowAttachment"
const TAIL_BONE := "mTail1"
const NEXT_BONE := "mTail2"
const VARIANT_TAG := "|tail-bow"
const STATE_KEY := "tail_bows"

## One design: two satin loops, a centre knot, two hanging tails and the band that ties it to
## the tail. Every length is at body scale 1.0 and multiplied by the wearer's size.
const LOOP_CX := 0.050
const LOOP_CY := 0.004
const LOOP_RX := 0.047
const LOOP_RY := 0.034
const LOOP_THICK := 0.0045
const LOOP_WIDTH := 0.013
const LOOP_SPLAY := 0.20
const LOOP_LIFT := 0.10
const KNOT_RADII := Vector3(0.017, 0.013, 0.012)
const TAIL_X := 0.013
const TAIL_Y := -0.013
const TAIL_Z := 0.004
const TAIL_LENGTH := 0.095
const TAIL_WIDTH_TOP := 0.026
const TAIL_WIDTH_END := 0.018
const TAIL_SPREAD := 0.024
const TAIL_DRAPE := 0.014
const TAIL_TIP_SKEW := 0.020
const BAND_TUBE := 0.006

## Satin dyes. The key is stored per pony, so a bow keeps its colour across worlds.
const COLOURS := {
	"rose": Color("d94b8a"),
	"pink": Color("ffa8c7"),
	"cream": Color("f4e8d6"),
	"purple": Color("8d6bd1"),
	"midnight": Color("2f3559"),
}
const DEFAULT_COLOUR := "rose"


static func feature_on() -> bool:
	return TUNABLES.get_bool("features.tail_bow")


# --- Worn state -----------------------------------------------------------------------------

## Every pony id wearing a bow: `{id: {"colour": String}}`.
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
	var node := build(colour(cfg), cfg)
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
		"outward_m": TUNABLES.get_float("presentation.tail_bow.outward_m"),
		"along_m": TUNABLES.get_float("presentation.tail_bow.along_m"),
		"outward_up": TUNABLES.get_float("presentation.tail_bow.outward_up"),
		"tilt_deg": TUNABLES.get_float("presentation.tail_bow.tilt_deg"),
		"yaw_deg": TUNABLES.get_float("presentation.tail_bow.yaw_deg"),
		"roll_deg": TUNABLES.get_float("presentation.tail_bow.roll_deg"),
		"band_radius": TUNABLES.get_float("presentation.tail_bow.band_radius"),
		"colour": TUNABLES.get_string("presentation.tail_bow.colour"),
	}


## The mesh transform under `mTail1`. The frame comes from the body's own back and up axes, not
## from the tail bones: the hair rig's rest pose holds the tail out behind her, while the live
## tail is spring-driven, so the bones only ever measure the spine of the moment.
static func local_transform(sk: Skeleton3D, pony: Node3D, cfg: Dictionary) -> Transform3D:
	var root_index := sk.find_bone(TAIL_BONE)
	if root_index < 0:
		return Transform3D.IDENTITY
	var root := sk.get_bone_global_rest(root_index)
	var frame := sk.global_basis.orthonormalized()
	var body := pony.global_basis.orthonormalized()
	return placement(root, frame.inverse() * body.z, frame.inverse() * body.y,
		cfg.get("size", 1.0), cfg)


## Pure placement: the bow's transform relative to the tail root bone. `back`/`up` are the body
## axes in the skeleton's own space. The bow faces up and back off the rump, its loops spread
## sideways and its tails hang down her body.
static func placement(root: Transform3D, back: Vector3, up: Vector3, size: float,
		cfg: Dictionary) -> Transform3D:
	var scale := maxf(size, 0.01)
	var outward := back.normalized() + up.normalized() * float(cfg.get("outward_up", 0.65))
	if outward.length() < 0.0001:
		outward = back.normalized()
	outward = outward.normalized()
	var z := -outward
	var y := up.normalized() - z * up.normalized().dot(z)
	if y.length() < 0.0001:
		y = Vector3.UP
	y = y.normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var basis := Basis(x, y, z)
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(float(cfg.get("tilt_deg", 0.0))),
		deg_to_rad(float(cfg.get("yaw_deg", 0.0))),
		deg_to_rad(float(cfg.get("roll_deg", 0.0)))))
	basis = basis.scaled(Vector3.ONE * scale)
	var origin := root.origin - y * float(cfg.get("along_m", 0.03)) * scale \
		+ outward * float(cfg.get("outward_m", 0.05)) * scale
	return root.affine_inverse() * Transform3D(basis, origin)


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

## The whole bow as one unskinned MeshInstance3D: loops and knot and band on satin surfaces, the
## tails on a two-sided one. The rig it hangs from is already scaled to her size, so only the
## `size` setting applies here.
static func build(colour: Color, cfg: Dictionary) -> MeshInstance3D:
	var s := maxf(float(cfg.get("size", 1.0)), 0.01)
	var mesh := ArrayMesh.new()
	_commit_loops(mesh, s, colour)
	_commit_tails(mesh, s, colour)
	_commit_knot(mesh, s, colour)
	_commit_band(mesh, s, colour.lightened(0.18),
		float(cfg.get("along_m", 0.03)) * s, float(cfg.get("outward_m", 0.05)) * s,
		float(cfg.get("band_radius", 0.042)) * s)
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
	material.roughness = 0.26
	material.metallic = 0.12
	material.rim_enabled = true
	material.rim = 0.45
	material.rim_tint = 0.35
	# Satin has no wrong side: both faces read as fabric, and winding cannot hide a surface.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _commit_loops(mesh: ArrayMesh, s: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_loop(st, s, -1.0)
	_add_loop(st, s, 1.0)
	_commit(mesh, st, satin(colour))


static func _commit_tails(mesh: ArrayMesh, s: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tail(st, s, -1.0)
	_add_tail(st, s, 1.0)
	_commit(mesh, st, satin(colour.darkened(0.12)))


static func _commit_knot(mesh: ArrayMesh, s: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_ellipsoid(st, Vector3.ZERO, KNOT_RADII * s, 8, 12)
	_commit(mesh, st, satin(colour.lightened(0.08)))


static func _commit_band(mesh: ArrayMesh, s: float, colour: Color, along: float, outward: float,
		radius: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_ring(st, Vector3(0.0, along, outward), radius, BAND_TUBE * s, 24, 8)
	_commit(mesh, st, satin(colour))


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


## One loop: a ribbon swept around an ellipse, pinched where it meets the knot.
static func _add_loop(st: SurfaceTool, s: float, side: float) -> void:
	var center := Vector3(LOOP_CX * s * side, LOOP_CY * s, 0.0)
	var rx := LOOP_RX * s
	var ry := LOOP_RY * s
	var thick := LOOP_THICK * s
	var width := LOOP_WIDTH * s
	var splay := Basis(Vector3.UP, -LOOP_SPLAY * side) * Basis(Vector3.BACK, LOOP_LIFT * side)
	var knot_angle := 0.0 if side < 0.0 else PI
	var steps := 32
	var cross := 10
	for i: int in steps:
		var t0 := TAU * float(i) / float(steps)
		var t1 := TAU * float(i + 1) / float(steps)
		for j: int in cross:
			var u0 := TAU * float(j) / float(cross)
			var u1 := TAU * float(j + 1) / float(cross)
			var p00 := _loop_point(center, rx, ry, thick, width, knot_angle, t0, u0)
			var p10 := _loop_point(center, rx, ry, thick, width, knot_angle, t1, u0)
			var p11 := _loop_point(center, rx, ry, thick, width, knot_angle, t1, u1)
			var p01 := _loop_point(center, rx, ry, thick, width, knot_angle, t0, u1)
			var n00 := _loop_normal(rx, ry, thick, width, knot_angle, t0, u0)
			var n10 := _loop_normal(rx, ry, thick, width, knot_angle, t1, u0)
			var n11 := _loop_normal(rx, ry, thick, width, knot_angle, t1, u1)
			var n01 := _loop_normal(rx, ry, thick, width, knot_angle, t0, u1)
			_quad(st,
				center + splay * (p00 - center), splay * n00,
				center + splay * (p10 - center), splay * n10,
				center + splay * (p11 - center), splay * n11,
				center + splay * (p01 - center), splay * n01)


static func _loop_point(center: Vector3, rx: float, ry: float, thick: float, width: float,
		knot_angle: float, t: float, u: float) -> Vector3:
	var path := center + Vector3(rx * cos(t), ry * sin(t), 0.0)
	var radial := Vector3(cos(t) * ry, sin(t) * rx, 0.0).normalized()
	return path + radial * (cos(u) * thick) + Vector3.BACK * (sin(u) * _loop_width(width, knot_angle, t))


static func _loop_normal(rx: float, ry: float, thick: float, width: float, knot_angle: float,
		t: float, u: float) -> Vector3:
	var radial := Vector3(cos(t) * ry, sin(t) * rx, 0.0).normalized()
	var half := maxf(_loop_width(width, knot_angle, t), 0.0001)
	return (radial * (cos(u) / maxf(thick, 0.0001)) + Vector3.BACK * (sin(u) / half)).normalized()


## The ribbon narrows where it is gathered at the knot.
static func _loop_width(width: float, knot_angle: float, t: float) -> float:
	var gap := absf(angle_difference(knot_angle, t))
	return width * lerpf(0.55, 1.0, smoothstep(0.0, PI, gap))


## One hanging tail: a strip that curves outward and drapes toward the coat, cut at an angle.
static func _add_tail(st: SurfaceTool, s: float, side: float) -> void:
	var base := Vector3(TAIL_X * s * side, TAIL_Y * s, TAIL_Z * s)
	var length := TAIL_LENGTH * s
	var steps := 8
	var rows: Array[Array] = []
	for i: int in steps + 1:
		var t := float(i) / float(steps)
		var point := base + Vector3(
			side * TAIL_SPREAD * s * t * t,
			-length * t,
			TAIL_DRAPE * s * t * t)
		var half := lerpf(TAIL_WIDTH_TOP, TAIL_WIDTH_END, t) * s * 0.5
		var across := Vector3.RIGHT.rotated(Vector3.UP, side * 0.16)
		rows.append([point - across * half, point + across * half, t])
	var last: Array = rows[rows.size() - 1]
	# Slanted cut: the outer edge hangs a little lower than the inner edge.
	var outer_low: Vector3 = (last[1] as Vector3) + Vector3.DOWN * TAIL_TIP_SKEW * s * side
	var inner_low: Vector3 = (last[0] as Vector3) + Vector3.DOWN * TAIL_TIP_SKEW * s * 0.35
	for i: int in steps:
		var a := rows[i]
		var b := rows[i + 1]
		var normal := _tail_normal(a[0] as Vector3, a[1] as Vector3, b[1] as Vector3)
		_quad(st, a[0] as Vector3, normal, a[1] as Vector3, normal,
			b[1] as Vector3, normal, b[0] as Vector3, normal)
	var tip_normal := _tail_normal(last[0] as Vector3, last[1] as Vector3, outer_low)
	_tri(st, last[0] as Vector3, tip_normal, outer_low, tip_normal, inner_low, tip_normal)


static func _tail_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(Vector3.BACK) < 0.0:
		normal = -normal
	return normal


static func _add_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, rings: int,
		segments: int) -> void:
	for i: int in rings:
		var phi0 := PI * float(i) / float(rings) - PI * 0.5
		var phi1 := PI * float(i + 1) / float(rings) - PI * 0.5
		for j: int in segments:
			var th0 := TAU * float(j) / float(segments)
			var th1 := TAU * float(j + 1) / float(segments)
			var p00 := _sphere_point(center, radii, phi0, th0)
			var p10 := _sphere_point(center, radii, phi1, th0)
			var p11 := _sphere_point(center, radii, phi1, th1)
			var p01 := _sphere_point(center, radii, phi0, th1)
			_quad(st, p00, _sphere_normal(radii, phi0, th0), p10, _sphere_normal(radii, phi1, th0),
				p11, _sphere_normal(radii, phi1, th1), p01, _sphere_normal(radii, phi0, th1))


static func _sphere_point(center: Vector3, radii: Vector3, phi: float, theta: float) -> Vector3:
	return center + Vector3(cos(phi) * cos(theta) * radii.x, sin(phi) * radii.y,
		cos(phi) * sin(theta) * radii.z)


static func _sphere_normal(radii: Vector3, phi: float, theta: float) -> Vector3:
	var normal := Vector3(cos(phi) * cos(theta) / radii.x, sin(phi) / radii.y,
		cos(phi) * sin(theta) / radii.z)
	return normal.normalized()


## The band that ties the bow around the tail, its axis along the tail.
static func _add_ring(st: SurfaceTool, center: Vector3, radius: float, tube: float,
		steps: int, cross: int) -> void:
	for i: int in steps:
		var u0 := TAU * float(i) / float(steps)
		var u1 := TAU * float(i + 1) / float(steps)
		for j: int in cross:
			var v0 := TAU * float(j) / float(cross)
			var v1 := TAU * float(j + 1) / float(cross)
			_quad(st,
				_ring_point(center, radius, tube, u0, v0), _ring_normal(u0, v0),
				_ring_point(center, radius, tube, u1, v0), _ring_normal(u1, v0),
				_ring_point(center, radius, tube, u1, v1), _ring_normal(u1, v1),
				_ring_point(center, radius, tube, u0, v1), _ring_normal(u0, v1))


static func _ring_point(center: Vector3, radius: float, tube: float, u: float, v: float) -> Vector3:
	var reach := radius + tube * cos(v)
	return center + Vector3(cos(u) * reach, tube * sin(v), sin(u) * reach)


static func _ring_normal(u: float, v: float) -> Vector3:
	return Vector3(cos(u) * cos(v), sin(v), sin(u) * cos(v))


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
