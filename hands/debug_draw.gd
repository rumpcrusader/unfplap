extends RefCounted
## The caress debug overlay: path anchors, contact target and the actual hand.

const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PORT := preload("res://mods/unfplap/hands/port.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")

## The coordinator, held weakly: it owns this module, so a strong link back would be a cycle.
var _host_ref: WeakRef = null
var _draw_mesh: MeshInstance3D = null
var _depth_mesh: MeshInstance3D = null
var _immediate: ImmediateMesh = null


func _init(port: PORT) -> void:
	_host_ref = weakref(port)


## The coordinator, or null once it has released this module.
func _host() -> PORT:
	return _host_ref.get_ref() as PORT


func draw(path: PATH_BASE, side: MODEL.Side, chosen: MODEL.DebugState,
		target: Transform3D, context: MODEL.CaressContext) -> void:
	if not context.debug or _host() == null:
		return
	var pony := _host().pony()
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	if path == null:
		return
	var world := path.debug_world(side)
	var tree: SceneTree = pony.get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return
	if not is_instance_valid(_immediate):
		_immediate = ImmediateMesh.new()
	if not is_instance_valid(_draw_mesh) or not _draw_mesh.is_inside_tree():
		_draw_mesh = _make_overlay(scene, "UnfplapCaressDebug", false)
	if not is_instance_valid(_depth_mesh) or not _depth_mesh.is_inside_tree():
		_depth_mesh = _make_overlay(scene, "UnfplapCaressDebugDepth", true)
	_draw_mesh.mesh = _immediate
	_depth_mesh.mesh = _immediate
	var immediate := _immediate
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := Vector3.ZERO
	var have_previous := false
	for anchor: MODEL.AnchorWorld in world:
		if not anchor.position.is_finite():
			continue
		var color := _anchor_color(anchor.id)
		_cross(immediate, anchor.position, color)
		_segment(immediate, anchor.position, anchor.position + anchor.normal * 0.08, color)
		if have_previous:
			_segment(immediate, previous, anchor.position, Color.WHITE)
		previous = anchor.position
		have_previous = true
	if chosen != null and chosen.contact.is_finite():
		_cross(immediate, chosen.contact, Color(0.2, 1.0, 1.0), 0.035)
		_segment(immediate, chosen.contact, chosen.contact + chosen.normal * 0.10,
			Color(0.2, 1.0, 1.0))
	if target.is_finite():
		_cross(immediate, target.origin, Color(1.0, 0.55, 0.15), 0.04)
		_segment(immediate, target.origin, target.origin + target.basis.y * 0.06,
			Color(1.0, 0.55, 0.15))
	# White is the actual hand palm; gray is the gap between it and the requested target.
	var hand := _host().hand_frame(side)
	if hand.is_finite() and hand.origin.length_squared() > 0.0001:
		_cross(immediate, hand.origin, Color.WHITE, 0.045)
		_segment(immediate, hand.origin, target.origin, Color(0.6, 0.6, 0.6))
	immediate.surface_end()


func clear() -> void:
	if is_instance_valid(_draw_mesh):
		_draw_mesh.queue_free()
	if is_instance_valid(_depth_mesh):
		_depth_mesh.queue_free()
	_draw_mesh = null
	_depth_mesh = null
	_immediate = null


func _make_overlay(scene: Node, overlay_name: String, depth: bool) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = overlay_name
	overlay.top_level = true
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = not depth
	material.albedo_color = Color.WHITE if depth else Color(0.28, 0.28, 0.28)
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(overlay)
	overlay.global_transform = Transform3D.IDENTITY
	return overlay


func _segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)


func _cross(mesh: ImmediateMesh, point: Vector3, color: Color, size := 0.025) -> void:
	_segment(mesh, point - Vector3.RIGHT * size, point + Vector3.RIGHT * size, color)
	_segment(mesh, point - Vector3.UP * size, point + Vector3.UP * size, color)
	_segment(mesh, point - Vector3.FORWARD * size, point + Vector3.FORWARD * size, color)


func _anchor_color(id: String) -> Color:
	match id:
		"lower":
			return Color(1.0, 0.2, 0.2)
		"flank":
			return Color(1.0, 0.45, 0.1)
		"shoulder":
			return Color(0.2, 0.8, 1.0)
		"belly":
			return Color(0.2, 1.0, 0.2)
		"chest":
			return Color(0.2, 0.5, 1.0)
		"neck":
			return Color(1.0, 1.0, 0.2)
		"cheek":
			return Color(1.0, 0.2, 1.0)
		_:
			return Color.WHITE
