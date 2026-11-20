extends Node3D
## Debug overlay for the coat line, drawn in the same local space the shader deforms.
## Unshaded and no-depth-test, so the line stays readable through the coat.

const REST_COLOR := Color(0.35, 0.55, 1.0, 0.55)
const LIVE_COLOR := Color(0.25, 1.0, 0.45, 0.95)
const STRETCH_COLOR := Color(1.0, 0.35, 0.15, 0.95)
const SQUASH_COLOR := Color(0.25, 0.75, 1.0, 0.95)
const FRAME_COLOR := Color(1.0, 0.85, 0.20, 0.85)
## Anatomy-local half-width of each cross-section marker.
const FRAME_SCALE := 0.012
const RING_PRIORITY := 11

var _mesh := ImmediateMesh.new()
var _instance := MeshInstance3D.new()
var _material := StandardMaterial3D.new()


func setup() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = RING_PRIORITY
	_instance.name = "CoatLineMesh"
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.extra_cull_margin = 2.0
	add_child(_instance)
	visible = false


## `data` is `coat_line.debug_data()`; empty hides the overlay.
func update(data: Dictionary, shown: bool) -> void:
	if not shown or data.is_empty():
		if visible:
			visible = false
			_mesh.clear_surfaces()
		return
	var rest: PackedVector3Array = data.get("rest", PackedVector3Array())
	var live: PackedVector3Array = data.get("live", PackedVector3Array())
	var basis_x: PackedVector3Array = data.get("basis_x", PackedVector3Array())
	var basis_z: PackedVector3Array = data.get("basis_z", PackedVector3Array())
	if rest.size() < 2 or live.size() != rest.size():
		visible = false
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in rest.size() - 1:
		_segment(rest[i], rest[i + 1], REST_COLOR)
		_segment(live[i], live[i + 1], _live_color(rest[i], rest[i + 1],
			live[i], live[i + 1]))
	for i in live.size():
		if i < basis_x.size():
			_segment(live[i] - basis_x[i] * FRAME_SCALE,
				live[i] + basis_x[i] * FRAME_SCALE, FRAME_COLOR)
		if i < basis_z.size():
			_segment(live[i] - basis_z[i] * FRAME_SCALE,
				live[i] + basis_z[i] * FRAME_SCALE, FRAME_COLOR)
	_mesh.surface_end()
	visible = true


## The live segment colour: green at rest, warm above, cool below.
func _live_color(rest_from: Vector3, rest_to: Vector3,
		live_from: Vector3, live_to: Vector3) -> Color:
	var rest_length := rest_from.distance_to(rest_to)
	var ratio := live_from.distance_to(live_to) / maxf(rest_length, 0.000001)
	if ratio >= 1.0:
		return LIVE_COLOR.lerp(STRETCH_COLOR, clampf(ratio - 1.0, 0.0, 1.0))
	return LIVE_COLOR.lerp(SQUASH_COLOR, clampf(1.0 - ratio, 0.0, 1.0))


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(to)
