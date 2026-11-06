extends Node
## integration: ported from PonyPussyParadise runtime anatomy attachment. One per adult mare,
## persistent across acts. The mesh and textures are local-only assets; if they are missing the
## controller stays empty and every public method is a no-op.

const TEAT_JIGGLE := preload("res://mods/unfplap/teat_jiggle.gd")
const DOCK := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/"
const WINKING_PATH := ASSET_DIR + "winking.scn"
const ANAL_PATH := ASSET_DIR + "anal.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"
const PLACE_PATH := "user://mods/data/unfplap/anatomy_place.json"

const WINKING_PINK := Color(0.97, 0.66, 0.74)
const WINKING_PINK_SHADE := Color(0.84, 0.47, 0.57)
const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
const ANAL_OPENING := Vector3(0.0, 0.071, 0.019)
const WINKING_HALF_HEIGHT := 0.0854
const WINKING_REAR_Y := 0.541
const WINKING_REAR_Z := 0.2961
const WINKING_TOUCH_Y := 0.52
const WINKING_DOCK_REF := -0.0311
const WINKING_CUT_DEPTH := 0.07
const WINKING_CUT_FILLED := 0.12
const WINKING_SLIT_HALF := 0.06
const TEAT_STRIP_END_Y := 0.384
const TEAT_STRIP_END_Z := Vector2(0.18, 0.175)
const STRIP_END_FADE := 0.03
const WINKING_BODIES := {"celestia": [0.853, 0.3329, 1.67], "luna": [0.596, 0.2265, 1.095]}

var pony: Node3D
var runtime: Node
var main: Node

var _mesh: MeshInstance3D
var _anal_mesh: MeshInstance3D
var _teats_mesh: MeshInstance3D
var _skin_strip: MeshInstance3D
var _teats_jiggle: Node
var _skeleton: Skeleton3D
var _bone_inverse := Transform3D.IDENTITY
var _pos := Vector3(-0.005, 0.52, 0.291)
var _pitch := 12.0
var _scale := 0.722
var _body: Array = []
var _lift := 0.0
var _dock_bottom := INF
var _closed := 1.0
var _rest := 1.0
var _fill := 0.0
var _wide := 0.0
var _tween: Tween
var _strip_span := Vector2(0.0, 1.0)
var _strip_gap := Vector2(2.0, 2.0)
var _missing_logged := false
var _attached := false


static func assets_exist() -> bool:
	return ResourceLoader.exists(WINKING_PATH) and ResourceLoader.exists(ANAL_PATH) \
		and ResourceLoader.exists(TEATS_PATH) and ResourceLoader.exists(STRIP_PATH)


## integration: only the modern taste roster gets anatomy. Identity filly/stallion checks stay,
## and the player's own pony never gets it. There is no separate age list.
static func eligible(pony_node: Node3D) -> bool:
	if not is_instance_valid(pony_node):
		return false
	if pony_node.name == "PlayerPony" or is_instance_valid(pony_node.get("rig")):
		return false
	var identity: Variant = pony_node.get("identity")
	if identity == null or bool(identity.get("filly")) or bool(identity.get("stallion")):
		return false
	var id := str(pony_node.get_meta("relationship_id", ""))
	if id.is_empty():
		id = str(identity.get("id"))
	return not id.is_empty() and id in SETTINGS.CHARACTER_ORDER


func setup(pony_node: Node3D, runtime_node: Node) -> void:
	pony = pony_node
	runtime = runtime_node
	main = runtime.get("main") if is_instance_valid(runtime) else null


func refresh() -> void:
	if not _enabled() or not eligible(pony):
		detach()
		return
	if not assets_exist():
		if not _missing_logged:
			_missing_logged = true
			_log("anatomy assets missing under %s; anatomy stays off" % ASSET_DIR)
		return
	_attach()


func _enabled() -> bool:
	return TUNABLES.get_bool("features.anatomy")


func _attach() -> void:
	if _attached:
		apply_live()
		return
	if not is_instance_valid(pony):
		return
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		return
	_skeleton = skeleton as Skeleton3D
	var bone := _skeleton.find_bone("pony_hips")
	if bone < 0:
		return
	var scene: PackedScene = load(WINKING_PATH)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	var mesh: MeshInstance3D = instance as MeshInstance3D
	if mesh == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			mesh = child as MeshInstance3D
			break
	if mesh == null:
		instance.queue_free()
		return
	mesh.owner = null
	if mesh.get_parent() != null:
		mesh.get_parent().remove_child(mesh)
	if instance != mesh:
		instance.queue_free()
	mesh.name = "UnfplapAnatomy"
	var anchor := BoneAttachment3D.new()
	anchor.name = "UnfplapAnatomyAnchor"
	anchor.bone_name = "pony_hips"
	_skeleton.add_child(anchor)
	anchor.add_child(mesh)
	_bone_inverse = _skeleton.get_bone_global_rest(bone).affine_inverse()
	_mesh = mesh
	_load_place()
	_lift = _tail_lift()
	var identity: Variant = pony.get("identity")
	_body = WINKING_BODIES.get(str(identity.get("id")) if identity != null else "", [])
	var dock := pony.find_child("OpenPonyDock", true, false) as MeshInstance3D
	if _body.is_empty() and is_instance_valid(dock) and dock.mesh != null:
		_dock_bottom = dock.mesh.get_aabb().position.y
	_apply_place()
	_apply_material()
	_attach_anal()
	_attach_teats()
	_attached = true
	set_process(true)
	_apply_visibility()
	_log("anatomy attached lift=%.3f dock_bottom=%.3f" % [_lift, _dock_bottom])


func _process(_delta: float) -> void:
	_apply_visibility()


func _apply_visibility() -> void:
	if not _attached or not is_instance_valid(pony):
		return
	var far := bool(pony.get("_far_mesh_shown")) if pony.get("_far_mesh_shown") != null else false
	var teats_on := TUNABLES.get_bool("anatomy.teats")
	if is_instance_valid(_mesh):
		_mesh.visible = not far
	if is_instance_valid(_anal_mesh):
		_anal_mesh.visible = not far
	if is_instance_valid(_teats_mesh):
		_teats_mesh.visible = not far and teats_on
	if is_instance_valid(_skin_strip):
		_skin_strip.visible = not far and teats_on


func _tail_lift() -> float:
	var at: Vector3 = DOCK.offset(pony)
	if at == Vector3.ZERO:
		return 0.0
	return clampf(at.y - WINKING_DOCK_REF, -0.05, 0.03)


func _apply_place() -> void:
	if not is_instance_valid(_mesh):
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), 0.0, 0.0)).scaled(Vector3.ONE * _scale)
	var lift := _lift
	if _dock_bottom < INF:
		var top := WINKING_TOUCH_Y + WINKING_HALF_HEIGHT * _scale * cos(deg_to_rad(_pitch))
		lift = clampf(_dock_bottom - top, -0.1, 0.06)
	var place := _pos + Vector3(0.0, lift, minf(lift, 0.0) * 0.2)
	if not _body.is_empty():
		var size: float = _body[2]
		place = Vector3(place.x * size, _body[0] + (place.y - WINKING_REAR_Y) * size,
			_body[1] + (place.z - WINKING_REAR_Z) * size)
		basis = basis.scaled(Vector3.ONE * size)
	_mesh.transform = _bone_inverse * Transform3D(basis, place)


func _load_place() -> void:
	if not FileAccess.file_exists(PLACE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACE_PATH))
	if not data is Dictionary:
		return
	var identity: Variant = pony.get("identity")
	var id := str(identity.get("id")) if identity != null else ""
	var row: Variant = (data as Dictionary).get(id, {})
	if not row is Dictionary:
		return
	var pos: Variant = (row as Dictionary).get("position")
	if pos is Array and (pos as Array).size() == 3:
		_pos = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_pitch = float((row as Dictionary).get("pitch", _pitch))
	_scale = float((row as Dictionary).get("scale", _scale))


func _apply_material() -> void:
	if not is_instance_valid(_mesh) or not is_instance_valid(pony):
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://mods/unfplap/anatomy.gdshader")
	var tones := _skin_tones()
	material.set_shader_parameter("skin_color", tones[0])
	material.set_shader_parameter("skin_shadow", tones[1])
	material.set_shader_parameter("inner_color", WINKING_PINK)
	material.set_shader_parameter("inner_shadow", WINKING_PINK_SHADE)
	_mesh.set_surface_override_material(0, material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(_mesh)
	if is_instance_valid(_anal_mesh):
		_anal_mesh.set_surface_override_material(0, material.duplicate())
	_apply_winking_shape()
	_apply_teats_material(material)


func _skin_tones() -> Array:
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	var base: Color = fill if fill is Color else Color(0.8, 0.8, 0.8)
	var dark: Color = shade if shade is Color else Color(0.68, 0.68, 0.68)
	match TUNABLES.get_string("anatomy.skin_tone"):
		"coat":
			return [base, dark]
		"dark":
			return [Color(0.26, 0.22, 0.26), Color(0.17, 0.14, 0.18)]
	return [base.darkened(0.1), dark.darkened(0.16)]


func _attach_anal() -> void:
	if not is_instance_valid(_mesh) or is_instance_valid(_anal_mesh):
		return
	var scene: PackedScene = load(ANAL_PATH)
	if scene == null:
		return
	var root: Node = scene.instantiate()
	var mesh: MeshInstance3D = root as MeshInstance3D
	if mesh == null:
		for child: Node in root.find_children("*", "MeshInstance3D", true, false):
			mesh = child as MeshInstance3D
			break
	if mesh == null:
		root.queue_free()
		return
	mesh.owner = null
	if mesh.get_parent() != null:
		mesh.get_parent().remove_child(mesh)
	if root != mesh:
		root.queue_free()
	mesh.name = "UnfplapAnatomyAnal"
	_mesh.add_child(mesh)
	mesh.transform = Transform3D.IDENTITY
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(mesh)
	_anal_mesh = mesh
	if _mesh.get_surface_override_material(0) is ShaderMaterial:
		mesh.set_surface_override_material(0,
			(_mesh.get_surface_override_material(0) as ShaderMaterial).duplicate())


## integration: a mesh modelled on the shared mare body and skinned with her own weights.
func _skinned_part(path: String, part_name: String) -> MeshInstance3D:
	var model: Variant = pony.get("_model")
	if not is_instance_valid(_skeleton) or not model is Node:
		return null
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	var scene: PackedScene = load(path)
	if body == null or body.skin == null or scene == null:
		return null
	var part: Node = scene.instantiate()
	var meshes: Array = part.find_children("*", "MeshInstance3D", true, false)
	if part is MeshInstance3D:
		meshes = [part]
	if meshes.is_empty() or (meshes[0] as MeshInstance3D).skin == null:
		part.queue_free()
		return null
	var mesh: MeshInstance3D = meshes[0]
	var binds := {}
	for i in body.skin.get_bind_count():
		binds[String(body.skin.get_bind_name(i))] = body.skin.get_bind_pose(i)
	var skin := Skin.new()
	for i in mesh.skin.get_bind_count():
		var bone := String(mesh.skin.get_bind_name(i))
		skin.add_named_bind(bone, binds.get(bone, Transform3D.IDENTITY))
	mesh.owner = null
	if mesh.get_parent() != null:
		mesh.get_parent().remove_child(mesh)
	if part != mesh:
		part.queue_free()
	mesh.name = part_name
	_skeleton.add_child(mesh)
	mesh.transform = Transform3D.IDENTITY
	mesh.skin = skin
	mesh.skeleton = mesh.get_path_to(_skeleton)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(mesh)
	return mesh


func _attach_teats() -> void:
	if not _body.is_empty() or is_instance_valid(_teats_mesh):
		return
	_teats_mesh = _skinned_part(TEATS_PATH, "UnfplapAnatomyTeats")
	if not is_instance_valid(_teats_mesh):
		return
	_teats_jiggle = TEAT_JIGGLE.new()
	_teats_jiggle.name = "UnfplapAnatomyTeatJiggle"
	_teats_jiggle.set("skeleton", _skeleton)
	_teats_mesh.add_child(_teats_jiggle)
	var size := _teat_size()
	_teats_mesh.set_blend_shape_value(_teats_mesh.find_blend_shape_by_name("mid"),
		1.0 - absf(size * 2.0 - 1.0))
	_teats_mesh.set_blend_shape_value(_teats_mesh.find_blend_shape_by_name("full"),
		maxf(size * 2.0 - 1.0, 0.0))
	_teats_jiggle.set("swing", 1.0 + 2.0 * size)
	_attach_skin_strip(size)
	if _mesh.get_surface_override_material(0) is ShaderMaterial:
		_apply_teats_material(_mesh.get_surface_override_material(0) as ShaderMaterial)


func _attach_skin_strip(size: float) -> void:
	_skin_strip = _skinned_part(STRIP_PATH, "UnfplapAnatomySkinStrip")
	if not is_instance_valid(_skin_strip) or not is_instance_valid(_mesh):
		return
	var arrays: Array = _skin_strip.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var strip_at := func(point: Vector3) -> float:
		var best := INF
		var along := 0.0
		for i in points.size():
			var distance := points[i].distance_squared_to(point)
			if distance < best:
				best = distance
				along = uvs[i].x
		return along
	var dock := pony.find_child("OpenPonyDock", true, false) as MeshInstance3D
	if is_instance_valid(dock) and dock.mesh != null:
		var box := dock.mesh.get_aabb()
		_strip_span.x = strip_at.call(Vector3(0.0, box.position.y, box.position.z + box.size.z * 0.5))
	_strip_span.y = strip_at.call(Vector3(0.0, TEAT_STRIP_END_Y,
		lerpf(TEAT_STRIP_END_Z.x, TEAT_STRIP_END_Z.y, size)))
	var parts := _skeleton.get_bone_global_rest(_skeleton.find_bone("pony_hips")) * _mesh.transform
	var slit := Vector3(0.0, WINKING_SLIT_HALF, 0.0)
	var gap_a: float = strip_at.call(parts * slit)
	var gap_b: float = strip_at.call(parts * -slit)
	_strip_gap = Vector2(minf(gap_a, gap_b), maxf(gap_a, gap_b))


func _teat_size() -> float:
	var identity: Variant = pony.get("identity")
	var id := str(identity.get("id")) if identity != null else ""
	return float(absi(id.hash()) % 101) / 100.0


func _apply_teats_material(base: ShaderMaterial) -> void:
	if not is_instance_valid(_teats_mesh) or not is_instance_valid(base):
		return
	var material := base.duplicate() as ShaderMaterial
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color", fill if fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow", shade if shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("contour_amount", 0.0)
	_teats_mesh.set_surface_override_material(0, material)
	if is_instance_valid(_teats_jiggle):
		_teats_jiggle.set("material", material)
	if is_instance_valid(_skin_strip):
		var strip := material.duplicate() as ShaderMaterial
		strip.set_shader_parameter("span_from", _strip_span.x)
		strip.set_shader_parameter("span_to", _strip_span.y)
		strip.set_shader_parameter("span_fade", STRIP_END_FADE)
		strip.set_shader_parameter("gap_from", _strip_gap.x)
		strip.set_shader_parameter("gap_to", _strip_gap.y)
		_skin_strip.set_surface_override_material(0, strip)


func apply_live() -> void:
	if not _attached:
		return
	_apply_material()
	_apply_place()
	_apply_visibility()


func detach() -> void:
	_attached = false
	set_process(false)
	if is_instance_valid(_skin_strip):
		_skin_strip.queue_free()
	_skin_strip = null
	if is_instance_valid(_teats_mesh):
		_teats_mesh.queue_free()
	_teats_mesh = null
	_teats_jiggle = null
	if is_instance_valid(_anal_mesh):
		_anal_mesh.queue_free()
	_anal_mesh = null
	if is_instance_valid(_mesh):
		var anchor := _mesh.get_parent()
		_mesh.queue_free()
		_mesh = null
		if is_instance_valid(anchor):
			anchor.queue_free()
	_skeleton = null


func winking_mesh() -> MeshInstance3D:
	return _mesh


func anal_mesh() -> MeshInstance3D:
	return _anal_mesh


func hole_local(mix: float) -> Vector3:
	return WINKING_OPENING.lerp(ANAL_OPENING, mix)


func hole_point(mix: float) -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.ZERO
	return _mesh.global_transform * hole_local(mix)


func hole_rear() -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.BACK
	return _mesh.global_basis.z.normalized()


func set_closed(value: float) -> void:
	_closed = clampf(value, 0.0, 1.0)
	_apply_winking_shape()


func drive(closed: float) -> void:
	_rest = clampf(closed, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	set_closed(_rest)


func animate(target: float, seconds: float) -> void:
	if not is_instance_valid(_mesh):
		return
	_rest = clampf(target, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(set_closed, _closed, _rest, seconds)


func wink(count := 1, seconds := 0.45) -> void:
	if not is_instance_valid(_mesh):
		return
	var peak := 0.25 if _rest > 0.5 else 0.85
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := _closed
	for _i in count:
		_tween.tween_method(set_closed, from, peak, seconds * 0.5)
		_tween.tween_method(set_closed, peak, _rest, seconds * 0.5)
		from = _rest


func set_stretch(wide: float) -> void:
	_wide = clampf(wide, 0.0, 1.4)
	if is_instance_valid(_mesh):
		var shape := _mesh.find_blend_shape_by_name("stretch")
		if shape >= 0:
			_mesh.set_blend_shape_value(shape, _wide)


func set_fill(fill: float) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	_apply_winking_shape()


func _apply_winking_shape() -> void:
	if not is_instance_valid(_mesh):
		return
	var shape := _mesh.find_blend_shape_by_name("closed")
	if shape >= 0:
		_mesh.set_blend_shape_value(shape, _closed)
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		var open := smoothstep(0.0, 0.4, 1.0 - _closed)
		var filled := lerpf(1.0, WINKING_CUT_FILLED, smoothstep(0.5, 1.0, _fill))
		material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * open * filled
			* _mesh.global_transform.basis.get_scale().x)


func set_anal_shape(fill: float, wide := 0.0) -> void:
	if not is_instance_valid(_anal_mesh):
		return
	_anal_mesh.set_blend_shape_value(_anal_mesh.find_blend_shape_by_name("stretch"), wide)
	_anal_mesh.set_blend_shape_value(_anal_mesh.find_blend_shape_by_name("open"),
		maxf(fill - wide, 0.0))
	var material := _anal_mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		var scale := _mesh.global_transform.basis.get_scale().x
		material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * scale
			* minf(fill * 4.0, 1.0) * lerpf(0.5, WINKING_CUT_FILLED, fill))


func react() -> void:
	if is_instance_valid(_mesh):
		wink(2)


func _clear_part() -> void:
	set_fill(0.0)
	set_stretch(0.0)
	set_anal_shape(0.0)
	_apply_winking_shape()


## integration: local placement calibration for the debug actions.
func nudge(axis: String, amount: float) -> void:
	match axis:
		"y": _pos.y += amount
		"z": _pos.z += amount
		"x": _pos.x += amount
		"pitch": _pitch += amount
		"scale": _scale = maxf(0.05, _scale + amount)
	_apply_place()


func place_text() -> String:
	return "position=(%.3f,%.3f,%.3f) pitch=%.1f scale=%.3f" % [
		_pos.x, _pos.y, _pos.z, _pitch, _scale]


func save_place() -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(PLACE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACE_PATH))
		if parsed is Dictionary:
			data = parsed
	var identity: Variant = pony.get("identity")
	var id := str(identity.get("id")) if identity != null else ""
	if id.is_empty():
		return
	data[id] = {"position": [_pos.x, _pos.y, _pos.z], "pitch": _pitch, "scale": _scale}
	DirAccess.make_dir_recursive_absolute(PLACE_PATH.get_base_dir())
	var file := FileAccess.open(PLACE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func reset_place() -> void:
	_pos = Vector3(-0.005, 0.52, 0.291)
	_pitch = 12.0
	_scale = 0.722
	_apply_place()



func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
