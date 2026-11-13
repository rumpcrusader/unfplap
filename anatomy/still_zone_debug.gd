extends Node3D
## Debug overlay for the two body-coat still zones. Four line rings: the outer ellipsoid and the
## fully-still core of the vulva and visible anal cup zones. anatomy/service.gd places them each frame
## through the pony_hips skinning transform; the rings are unshaded, no-depth-test overlays so
## they stay visible through the coat.

const SEGMENTS := 48
const VULVA_COLOR := Color(1.0, 0.35, 0.60, 0.90)
const ANAL_COLOR := Color(0.30, 0.85, 1.00, 0.90)
const CORE_ALPHA := 0.45
const RING_PRIORITY := 10

const VULVA := 0
const ANAL := 1

static var _ring_mesh: ArrayMesh

var _outer: Array[MeshInstance3D] = []
var _core: Array[MeshInstance3D] = []


func setup() -> void:
	name = "UnfplapStillZones"
	var mesh := _get_ring_mesh()
	for i in 2:
		var color := VULVA_COLOR if i == VULVA else ANAL_COLOR
		_outer.append(_make_ring(mesh, color))
		var core_color := color
		core_color.a = CORE_ALPHA
		_core.append(_make_ring(mesh, core_color))
	visible = false


func _make_ring(mesh: ArrayMesh, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = RING_PRIORITY
	ring.material_override = mat
	add_child(ring)
	return ring


## place the outer ellipsoid and its fully-still core. `axes` is the zone frame in body space;
## `body_to_world` is the pony_hips skinning transform (body local -> world).
func update(body_to_world: Transform3D, vulva_centre: Vector3, vulva_axes: Basis,
		vulva_radius: float, anal_centre: Vector3, anal_radius: float,
		oval: float, fade: float, shown: bool) -> void:
	if not shown or _outer.size() < 2:
		visible = false
		return
	visible = true
	_place(_outer[VULVA], body_to_world, vulva_centre, vulva_axes, vulva_radius, oval, 1.0)
	_place(_core[VULVA], body_to_world, vulva_centre, vulva_axes, vulva_radius, oval, 1.0 - fade)
	_place(_outer[ANAL], body_to_world, anal_centre, vulva_axes, anal_radius, oval, 1.0)
	_place(_core[ANAL], body_to_world, anal_centre, vulva_axes, anal_radius, oval, 1.0 - fade)


func _place(ring: MeshInstance3D, body_to_world: Transform3D, centre: Vector3,
		axes: Basis, radius: float, oval: float, fade_scale: float) -> void:
	if radius <= 0.0:
		ring.visible = false
		return
	ring.visible = true
	var radii := Vector3(radius, radius * maxf(oval, 0.05), radius) * fade_scale
	var basis := body_to_world.basis * axes * Basis.from_scale(radii)
	ring.global_transform = Transform3D(basis, body_to_world * centre)


## One unit-radius ring in each principal plane. The ellipsoid is the scaled transform of this
## mesh, so the vertices are built once and shared by every ring.
static func _get_ring_mesh() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var vertices := PackedVector3Array()
	for plane in 3:
		for i in SEGMENTS:
			var a := TAU * i / SEGMENTS
			var b := TAU * (i + 1) / SEGMENTS
			var p := Vector3.ZERO
			var q := Vector3.ZERO
			match plane:
				0:
					p = Vector3(cos(a), sin(a), 0.0)
					q = Vector3(cos(b), sin(b), 0.0)
				1:
					p = Vector3(cos(a), 0.0, sin(a))
					q = Vector3(cos(b), 0.0, sin(b))
				_:
					p = Vector3(0.0, cos(a), sin(a))
					q = Vector3(0.0, cos(b), sin(b))
			vertices.append(p)
			vertices.append(q)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_ring_mesh = mesh
	return mesh
