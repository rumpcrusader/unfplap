extends RefCounted
## Debug aim markers for the two openings and the player tip.
## Debug-only: they stay out of the act's normal state.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")

var parent: Node
var anatomy: CONTROLLER

var _vulva: MeshInstance3D
var _anus: MeshInstance3D
var _tip: MeshInstance3D


func setup(parent_node: Node, anatomy_node: CONTROLLER) -> void:
	parent = parent_node
	anatomy = anatomy_node
	_build()


func tick(part: PLAYER) -> void:
	if not SETTINGS.debug_aim_points.get_bool():
		if is_instance_valid(_vulva):
			clear()
		return
	if not is_instance_valid(_vulva):
		_build()
	var shown := is_instance_valid(anatomy) and is_instance_valid(anatomy.winking_mesh())
	for point: MeshInstance3D in [_vulva, _anus]:
		point.visible = shown
	if shown:
		_vulva.global_position = anatomy.hole_point(0.0)
		_anus.global_position = anatomy.hole_point(1.0)
	var tip_shown := is_instance_valid(part) and part.showing()
	if is_instance_valid(_tip):
		_tip.visible = tip_shown
		if tip_shown:
			_tip.global_position = part.tip_world()


func clear() -> void:
	for point: MeshInstance3D in [_vulva, _anus, _tip]:
		if is_instance_valid(point):
			point.queue_free()
	_vulva = null
	_anus = null
	_tip = null


func _build() -> void:
	if not is_instance_valid(parent) or not SETTINGS.debug_aim_points.get_bool():
		return
	_vulva = _sphere(Color(1.0, 0.1, 0.75))
	_anus = _sphere(Color(1.0, 0.35, 0.05))
	_tip = _sphere(Color(0.1, 1.0, 0.4))
	for point: MeshInstance3D in [_vulva, _anus, _tip]:
		parent.add_child(point)


func _sphere(color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	sphere.radial_segments = 8
	sphere.rings = 4
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.visible = false
	return mesh
