extends RefCounted
## The anatomy material, skin tones, teats and the midline skin strip. It owns the skinned part
## meshes and their visibility; the controller owns placement and shape state.
##
## See `docs/anatomy.md` (`## Appearance`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const TEAT_JIGGLE := preload("res://mods/unfplap/anatomy/teat_jiggle.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/mare/"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"

const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
const ANAL_OPENING := Vector3(0.0, 0.071, 0.019)
const LIP_OUTER_FACTOR := 3.0
const WINKING_SLIT_HALF := 0.06
const TEAT_STRIP_END_Y := 0.384
const TEAT_STRIP_END_Z := Vector2(0.18, 0.175)
const STRIP_END_FADE := 0.03

var pony: Node3D
var dock_refresh := Callable()
var perf_note := Callable()
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var shapes: RefCounted

var teats_mesh: MeshInstance3D
var skin_strip: MeshInstance3D
var teats_jiggle: Node
var _strip_span := Vector2(0.0, 1.0)
var _strip_gap := Vector2(2.0, 2.0)


func setup(pony_node: Node3D, shapes_node: RefCounted,
		dock_refresh_callable := Callable(), perf_callable := Callable()) -> void:
	pony = pony_node
	shapes = shapes_node
	dock_refresh = dock_refresh_callable
	perf_note = perf_callable


func set_perf(perf_callable: Callable) -> void:
	perf_note = perf_callable
	if is_instance_valid(teats_jiggle):
		teats_jiggle.set("perf_note", perf_note)


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node


## The material currently applied to the anatomy mesh, for the coat follow and the dock copy.
func material() -> ShaderMaterial:
	if not is_instance_valid(mesh):
		return null
	return mesh.get_surface_override_material(0) as ShaderMaterial


## Build the anatomy material and apply it to the mesh. The shape module reapplies the blend
## shapes and the cut after the material exists. `missionary` selects the fold-coloring hack.
func apply_material(missionary: bool) -> void:
	if not is_instance_valid(mesh) or not is_instance_valid(pony) or shapes == null:
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://mods/unfplap/anatomy/anatomy.gdshader")
	var tones := _skin_tones()
	material.set_shader_parameter("skin_color", tones[0])
	material.set_shader_parameter("skin_shadow", tones[1])
	var inner_color := SETTINGS.vulva_inner_color.get_color()
	var clitoris_color := SETTINGS.clitoris_color.get_color()
	material.set_shader_parameter("inner_color", inner_color)
	material.set_shader_parameter("inner_shadow", inner_color.darkened(0.22))
	material.set_shader_parameter("clitoris_color", clitoris_color)
	material.set_shader_parameter("clitoris_shadow", clitoris_color.darkened(0.22))
	# Act hack: drop the vertex-alpha fold/clitoris masks so the whole mesh uses her skin tones.
	material.set_shader_parameter("fold_coloring",
		0.0 if missionary and SETTINGS.disable_fold_coloring.get_bool() else 1.0)
	var world_scale := maxf(mesh.global_transform.basis.get_scale().x, 0.001)
	material.set_shader_parameter("vulva_centre", WINKING_OPENING)
	material.set_shader_parameter("anal_centre", ANAL_OPENING)
	material.set_shader_parameter("anal_scale",
		1.0 if bool(shapes.v2_anal()) else SETTINGS.anal_scale.get_num())
	material.set_shader_parameter("lip_radius", shapes.lip_radius())
	material.set_shader_parameter("lip_outer", shapes.lip_radius() * LIP_OUTER_FACTOR)
	material.set_shader_parameter("lip_vertical",
		clampf(SETTINGS.lip_vertical.get_num(), 0.0, 1.0))
	material.set_shader_parameter("vulva_height", SETTINGS.vulva_height.get_num())
	# `coat_color` is the shader's `to_coat` fallback (the dock and the strip edges read it). It
	# must match her coat here, or those vertices render black.
	var identity: Variant = pony.get("identity")
	var coat_fill: Variant = identity.get("coat_fill") if identity != null else null
	var coat_shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color",
		coat_fill if coat_fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow",
		coat_shade if coat_shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("hole_target", shapes.wide() / world_scale)
	mesh.set_surface_override_material(0, material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(mesh)
	shapes.refresh_winking()
	apply_teats_material(material)
	if dock_refresh.is_valid():
		dock_refresh.call(pony)


func attach_parts() -> void:
	_attach_teats()
	_attach_skin_strip()
	if is_instance_valid(mesh) and mesh.get_surface_override_material(0) is ShaderMaterial:
		apply_teats_material(mesh.get_surface_override_material(0) as ShaderMaterial)


func apply_strip_scale() -> void:
	if not is_instance_valid(skin_strip):
		return
	var material := skin_strip.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("strip_scale", SETTINGS.strip_scale.get_num())


## Show or hide the teats and strip with the anatomy and their own switches.
func apply_visibility(show: bool, teats_on: bool, strip_on: bool) -> void:
	if is_instance_valid(teats_mesh):
		teats_mesh.visible = show and teats_on
	if is_instance_valid(skin_strip):
		skin_strip.visible = show and strip_on
	if is_instance_valid(teats_jiggle):
		teats_jiggle.set_physics_process(show and teats_on)


func apply_teats_material(base: ShaderMaterial) -> void:
	if not is_instance_valid(base):
		return
	if not is_instance_valid(teats_mesh) and not is_instance_valid(skin_strip):
		return
	var material := base.duplicate() as ShaderMaterial
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color", fill if fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow",
		shade if shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("contour_amount", 0.0)
	# The teats and strip are engine-skinned already; only the anatomy mesh carries custom0.
	material.set_shader_parameter("coat_follow_strength", 0.0)
	if is_instance_valid(teats_mesh):
		teats_mesh.set_surface_override_material(0, material)
	if is_instance_valid(teats_jiggle):
		teats_jiggle.set("material", material)
	if is_instance_valid(skin_strip):
		var strip := material.duplicate() as ShaderMaterial
		strip.set_shader_parameter("span_from", _strip_span.x)
		strip.set_shader_parameter("span_to", _strip_span.y)
		strip.set_shader_parameter("span_fade", STRIP_END_FADE)
		strip.set_shader_parameter("gap_from", _strip_gap.x)
		strip.set_shader_parameter("gap_to", _strip_gap.y)
		strip.set_shader_parameter("strip_trim", 1.0)
		strip.set_shader_parameter("strip_scale", SETTINGS.strip_scale.get_num())
		strip.set_shader_parameter("coat_follow_strength", 0.0)
		skin_strip.set_surface_override_material(0, strip)


func clear() -> void:
	if is_instance_valid(skin_strip):
		skin_strip.queue_free()
	skin_strip = null
	if is_instance_valid(teats_mesh):
		teats_mesh.queue_free()
	teats_mesh = null
	teats_jiggle = null


func _skin_tones() -> Array:
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	var base: Color = fill if fill is Color else Color(0.8, 0.8, 0.8)
	var dark: Color = shade if shade is Color else Color(0.68, 0.68, 0.68)
	# The old Coat / Darker / Dark values are the three anchors of one 0…1 slider.
	var tone := SETTINGS.skin_tone.get_num()
	var darker_fill := base.darkened(0.1)
	var darker_shade := dark.darkened(0.16)
	if tone <= 0.5:
		var k := tone / 0.5
		return [base.lerp(darker_fill, k), dark.lerp(darker_shade, k)]
	var k := (tone - 0.5) / 0.5
	return [darker_fill.lerp(Color(0.26, 0.22, 0.26), k),
		darker_shade.lerp(Color(0.17, 0.14, 0.18), k)]


func _attach_teats() -> void:
	if not is_instance_valid(pony) \
			or not IDENTITY.body_profile(pony.get("identity")).is_empty() \
			or is_instance_valid(teats_mesh):
		return
	teats_mesh = _skinned_part(TEATS_PATH, "UnfplapAnatomyTeats")
	if not is_instance_valid(teats_mesh):
		return
	teats_jiggle = TEAT_JIGGLE.new()
	teats_jiggle.name = "UnfplapAnatomyTeatJiggle"
	teats_jiggle.set("skeleton", skeleton)
	teats_jiggle.set("perf_note", perf_note)
	teats_mesh.add_child(teats_jiggle)
	var size := _teat_size()
	teats_mesh.set_blend_shape_value(teats_mesh.find_blend_shape_by_name("mid"),
		1.0 - absf(size * 2.0 - 1.0))
	teats_mesh.set_blend_shape_value(teats_mesh.find_blend_shape_by_name("full"),
		maxf(size * 2.0 - 1.0, 0.0))
	teats_jiggle.set("swing", 1.0 + 2.0 * size)


func _attach_skin_strip() -> void:
	if not is_instance_valid(pony) \
			or not IDENTITY.body_profile(pony.get("identity")).is_empty() \
			or is_instance_valid(skin_strip):
		return
	skin_strip = _skinned_part(STRIP_PATH, "UnfplapAnatomySkinStrip")
	if not is_instance_valid(skin_strip) or not is_instance_valid(mesh):
		return
	var arrays: Array = skin_strip.mesh.surface_get_arrays(0)
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
	var size := _teat_size()
	_strip_span.y = strip_at.call(Vector3(0.0, TEAT_STRIP_END_Y,
		lerpf(TEAT_STRIP_END_Z.x, TEAT_STRIP_END_Z.y, size)))
	var parts := skeleton.get_bone_global_rest(skeleton.find_bone("pony_hips")) * mesh.transform
	var slit := Vector3(0.0, WINKING_SLIT_HALF, 0.0)
	var gap_a: float = strip_at.call(parts * slit)
	var gap_b: float = strip_at.call(parts * -slit)
	_strip_gap = Vector2(minf(gap_a, gap_b), maxf(gap_a, gap_b))


func _teat_size() -> float:
	var identity: Variant = pony.get("identity")
	var id := str(identity.get("id")) if identity != null else ""
	return float(absi(id.hash()) % 101) / 100.0


## A mesh modelled on the shared mare body and skinned with her own weights.
func _skinned_part(path: String, part_name: String) -> MeshInstance3D:
	var model: Variant = pony.get("_model")
	if not is_instance_valid(skeleton) or not model is Node:
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
	var mesh_node: MeshInstance3D = meshes[0]
	var binds := {}
	for i in body.skin.get_bind_count():
		binds[String(body.skin.get_bind_name(i))] = body.skin.get_bind_pose(i)
	var skin := Skin.new()
	for i in mesh_node.skin.get_bind_count():
		var bone := String(mesh_node.skin.get_bind_name(i))
		skin.add_named_bind(bone, binds.get(bone, Transform3D.IDENTITY))
	mesh_node.owner = null
	if mesh_node.get_parent() != null:
		mesh_node.get_parent().remove_child(mesh_node)
	if part != mesh_node:
		part.queue_free()
	mesh_node.name = part_name
	skeleton.add_child(mesh_node)
	mesh_node.transform = Transform3D.IDENTITY
	mesh_node.skin = skin
	mesh_node.skeleton = mesh_node.get_path_to(skeleton)
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(mesh_node)
	return mesh_node
