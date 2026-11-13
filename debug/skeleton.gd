extends Node3D
## Debug skeleton overlay, enabled by the Anatomy Debug flag while DEBUG LOGS are on. Draws the
## body, face and hair/tail skeletons of nearby loaded ponies as thick unshaded lines with joint
## circles. Hovering a joint turns it red; clicking one prints its bone name and pose properties.

const BODY_COLOR := Color(0.38, 1.0, 0.62)
const FACE_COLOR := Color(1.0, 0.83, 0.36)
const HAIR_COLOR := Color(1.0, 0.54, 0.85)
const HOVER_COLOR := Color(1.0, 0.12, 0.12)
const JOINT_SEGMENTS := 12
## Thick enough to read clearly, without turning the skeleton into a solid mass.
const JOINT_RADIUS := 0.018
const LINE_HALF_WIDTH := 0.0015
const UPDATE_HZ := 30.0
const MAX_DISTANCE_M := 15.0
const HOVER_MIN_PX := 9.0

var main: Node
var enabled := false:
	set(value):
		enabled = value
		set_process(value)
		if is_instance_valid(_instance):
			_instance.visible = value
		if not value:
			_hover.clear()
			_joints.clear()
			_clear()

var _mesh := ImmediateMesh.new()
var _instance := MeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _clock := 0.0
var _joints: Array[Dictionary] = []
var _hover: Dictionary = {}


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_instance.name = "UnfplapSkeletonMesh"
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.extra_cull_margin = 4.0
	_instance.visible = enabled
	add_child(_instance)
	set_process(enabled)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 1.0 / UPDATE_HZ:
		return
	_clock = 0.0
	_rebuild()


func _rebuild() -> void:
	_clear()
	_joints.clear()
	if not is_instance_valid(main):
		_hover.clear()
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camera) and main.has_method("camera"):
		camera = main.call("camera")
	if not is_instance_valid(camera):
		_hover.clear()
		return
	var at: Vector3 = camera.global_position
	var right: Vector3 = camera.global_basis.x.normalized()
	var up: Vector3 = camera.global_basis.y.normalized()
	var list: Array = main.call("mares") if main.has_method("mares") else []
	var drawables: Array[Dictionary] = []
	for pony: Variant in list:
		if not is_instance_valid(pony) or not pony is Node3D:
			continue
		if (pony as Node3D).global_position.distance_to(at) > MAX_DISTANCE_M:
			continue
		var body: Variant = pony.get("skeleton")
		if body is Skeleton3D:
			drawables.append({"skeleton": body, "color": BODY_COLOR, "label": "body"})
		var boop: Variant = pony.get("boop_node")
		var face: Variant = boop.get("head_skeleton") if boop != null else null
		if face is Skeleton3D and face != body:
			drawables.append({"skeleton": face, "color": FACE_COLOR, "label": "face"})
		var hair: Variant = pony.get("hair_skeleton")
		if hair is Skeleton3D and hair != body:
			drawables.append({"skeleton": hair, "color": HAIR_COLOR, "label": "hair"})
	if drawables.is_empty():
		_hover.clear()
		return
	for entry: Dictionary in drawables:
		var skeleton: Skeleton3D = entry["skeleton"]
		var label := str(entry["label"])
		_collect_joints(skeleton, label, camera, right, up)
	if _joints.is_empty():
		_hover.clear()
		return
	_update_hover()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for entry: Dictionary in drawables:
		var skeleton: Skeleton3D = entry["skeleton"]
		var color: Color = entry["color"]
		var label := str(entry["label"])
		_draw_skeleton(skeleton, label, color, right, up, at)
	_mesh.surface_end()


func _collect_joints(skeleton: Skeleton3D, label: String, camera: Camera3D,
		right: Vector3, up: Vector3) -> void:
	var space: Transform3D = skeleton.global_transform
	for index: int in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(index)
		var point := space * pose.origin
		var screen := Vector2.INF
		var radius := HOVER_MIN_PX
		if not camera.is_position_behind(point):
			screen = camera.unproject_position(point)
			var edge := camera.unproject_position(point + right * JOINT_RADIUS)
			radius = maxf(HOVER_MIN_PX, screen.distance_to(edge))
		_joints.append({
			"skeleton": skeleton,
			"label": label,
			"bone": index,
			"world": point,
			"screen": screen,
			"radius": radius,
		})


func _update_hover() -> void:
	_hover.clear()
	if _joints.is_empty():
		return
	var pointer := _pointer_screen()
	var best := INF
	for joint: Dictionary in _joints:
		var screen: Vector2 = joint["screen"]
		if not screen.is_finite():
			continue
		var distance := screen.distance_to(pointer)
		if distance <= float(joint["radius"]) and distance < best:
			best = distance
			_hover = joint


func _pointer_screen() -> Vector2:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_mouse_position()


func _draw_skeleton(skeleton: Skeleton3D, label: String, color: Color,
		right: Vector3, up: Vector3, camera_pos: Vector3) -> void:
	var space: Transform3D = skeleton.global_transform
	for index: int in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(index)
		var point := space * pose.origin
		var joint_color := HOVER_COLOR if _is_hovered(skeleton, label, index) else color
		_joint(point, joint_color, right, up, camera_pos)
		var parent := skeleton.get_bone_parent(index)
		if parent < 0:
			continue
		var parent_point := space * skeleton.get_bone_global_pose(parent).origin
		_line(parent_point, point, color, camera_pos)


func _is_hovered(skeleton: Skeleton3D, label: String, index: int) -> bool:
	return not _hover.is_empty() and _hover.get("skeleton") == skeleton \
		and int(_hover.get("bone", -1)) == index and str(_hover.get("label", "")) == label


func _line(from: Vector3, to: Vector3, color: Color, camera_pos: Vector3) -> void:
	var delta := to - from
	if delta.length_squared() < 0.00000001:
		return
	var direction := delta.normalized()
	var view := (from + to) * 0.5 - camera_pos
	var side := direction.cross(view)
	if side.length_squared() < 0.000001:
		side = direction.cross(Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		side = direction.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		return
	side = side.normalized() * LINE_HALF_WIDTH
	var a := from - side
	var b := from + side
	var c := to + side
	var d := to - side
	_triangle(a, b, c, color)
	_triangle(a, c, d, color)


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(c)


func _joint(at: Vector3, color: Color, right: Vector3, up: Vector3, camera_pos: Vector3) -> void:
	for segment: int in JOINT_SEGMENTS:
		var a := TAU * float(segment) / float(JOINT_SEGMENTS)
		var b := TAU * float(segment + 1) / float(JOINT_SEGMENTS)
		var p := at + (right * cos(a) + up * sin(a)) * JOINT_RADIUS
		var q := at + (right * cos(b) + up * sin(b)) * JOINT_RADIUS
		_line(p, q, color, camera_pos)


## Called by the mod input owner on a left click. Returns true when a joint is under the pointer.
func handle_click() -> bool:
	if not enabled or _hover.is_empty():
		return false
	var skeleton: Skeleton3D = _hover["skeleton"]
	if not is_instance_valid(skeleton):
		return false
	var index := int(_hover["bone"])
	if index < 0 or index >= skeleton.get_bone_count():
		return false
	var label := str(_hover["label"])
	var pose := skeleton.get_bone_global_pose(index)
	var parent := skeleton.get_bone_parent(index)
	var parent_name := str(skeleton.get_bone_name(parent)) if parent >= 0 else "none"
	var line := "JOINT skeleton=%s bone=%s index=%d parent=%s world=%s local=%s rot=%s scale=%s rest=%s" % [
		label, str(skeleton.get_bone_name(index)), index, parent_name,
		str(skeleton.global_transform * pose.origin), str(pose.origin),
		str(pose.basis.get_euler()), str(pose.basis.get_scale()),
		str(skeleton.get_bone_rest(index).origin)]
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", line)
	return true


func _clear() -> void:
	_mesh.clear_surfaces()
