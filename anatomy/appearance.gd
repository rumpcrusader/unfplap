extends RefCounted
## The anatomy material, skin tones, teats and the midline skin strip. It owns the skinned part
## meshes and their visibility; the controller owns placement and shape state.
##
## See `docs/anatomy.md` (`## Appearance`).

const GAME := preload("res://mods/unfplap/world/game.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const TEAT_JIGGLE := preload("res://mods/unfplap/anatomy/teat_jiggle.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const BODY_FIT := preload("res://mods/unfplap/anatomy/body_fit.gd")
const UDDER := preload("res://mods/unfplap/anatomy/udder.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/mare/"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"

## The princesses' own teat look: `size` 0..1 (1 = the "full" shape), `bounce` multiplies
## the sway, and `stiffness`/`damping` scale the spring (lower = slower, longer bounce).
const PRINCESS_TEATS := {
	"celestia": {"size": 1.0, "bounce": 1.3, "stiffness": 0.7, "damping": 0.75},
}

const WINKING_SLIT_HALF := 0.06
const TEAT_STRIP_END_Y := 0.384
const TEAT_STRIP_END_Z := Vector2(0.18, 0.175)
const STRIP_END_FADE := 0.03

var pony: Node3D
var rig: RIG
var dock_refresh := Callable()
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var shapes: RefCounted
## The presented body's form. Null keeps the default own form built from her identity.
var _form: BODY_FORM.BodyForm = null

var teats_mesh: MeshInstance3D
var skin_strip: MeshInstance3D
var teats_jiggle: TEAT_JIGGLE
## True when the teats are grown from her belly (anatomy/udder.gd) rather than the old asset.
var generated_teats := false
var _strip_span := Vector2(0.0, 1.0)
var _strip_gap := Vector2(2.0, 2.0)


func setup(pony_node: Node3D, shapes_node: RefCounted, rig_node: RIG,
		dock_refresh_callable := Callable()) -> void:
	pony = pony_node
	shapes = shapes_node
	rig = rig_node
	dock_refresh = dock_refresh_callable


## The presented form supplies the rig and the placement fit the teats and strip are built for.
func set_form(value: BODY_FORM.BodyForm) -> void:
	_form = value


## The typed rig of the body this appearance is built for.
func _rig() -> BODY_PROFILE.RigProfile:
	var current := _form if _form != null else BODY_FORM.default_form(pony)
	return current.rig


## The placement fit id the body's teats and strip follow.
func _fit_id() -> String:
	var current := _form if _form != null else BODY_FORM.default_form(pony)
	return current.fit_id


## The placement profile the body fit takes; empty for the ordinary rig.
func _profile() -> Array:
	var rig := _rig()
	if rig == null or rig.is_ordinary():
		return []
	return [rig.rear_y, rig.rear_z, rig.scale]


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node


## The material currently applied to the anatomy mesh, for the coat line and the dock copy.
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
	material.set_shader_parameter("fold_coloring",
		0.0 if missionary and SETTINGS.disable_fold_coloring.get_bool() else 1.0)
	var world_scale := maxf(mesh.global_transform.basis.get_scale().x, 0.001)
	material.set_shader_parameter("vulva_centre", GEOMETRY.WINKING_OPENING)
	material.set_shader_parameter("anal_centre", GEOMETRY.ANAL_SHADER_CENTRE)
	# The mesh carries the ponut shape in its blend keys; the coat side reads `anal_scale`.
	material.set_shader_parameter("anal_scale", 1.0)
	material.set_shader_parameter("lip_radius", shapes.lip_radius())
	material.set_shader_parameter("lip_outer", shapes.lip_radius() * GEOMETRY.LIP_OUTER_FACTOR)
	material.set_shader_parameter("lip_vertical",
		clampf(SETTINGS.lip_vertical.get_num(), 0.0, 1.0))
	material.set_shader_parameter("vulva_height", SETTINGS.vulva_height.get_num())
	var identity := rig.identity_of(pony)
	var coat_fill: Variant = identity.get("coat_fill") if identity != null else null
	var coat_shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color",
		coat_fill if coat_fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow",
		coat_shade if coat_shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("hole_target", shapes.wide() / world_scale)
	mesh.set_surface_override_material(0, material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GAME.exclude_from_outline(mesh)
	shapes.refresh_winking()
	apply_teats_material(material)
	if dock_refresh.is_valid():
		dock_refresh.call(pony)


func attach_parts() -> void:
	_attach_teats()
	_attach_skin_strip()
	if is_instance_valid(mesh) and mesh.get_surface_override_material(0) is ShaderMaterial:
		apply_teats_material(mesh.get_surface_override_material(0) as ShaderMaterial)


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
	var identity := rig.identity_of(pony)
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color", fill if fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow",
		shade if shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("contour_amount", 0.0)
	# The teats and strip are engine-skinned; the copy must not inherit the anatomy line.
	material.set_shader_parameter("line_count", 0)
	var teats_material := material
	if generated_teats:
		teats_material = material.duplicate() as ShaderMaterial
		teats_material.set_shader_parameter("sway_custom", 1.0)
	if is_instance_valid(teats_mesh):
		teats_mesh.set_surface_override_material(0, teats_material)
	if is_instance_valid(teats_jiggle):
		teats_jiggle.material = teats_material
	if is_instance_valid(skin_strip):
		var strip := material.duplicate() as ShaderMaterial
		strip.set_shader_parameter("span_from", _strip_span.x)
		strip.set_shader_parameter("span_to", _strip_span.y)
		strip.set_shader_parameter("span_fade", STRIP_END_FADE)
		strip.set_shader_parameter("gap_from", _strip_gap.x)
		strip.set_shader_parameter("gap_to", _strip_gap.y)
		strip.set_shader_parameter("strip_trim", 1.0)
		strip.set_shader_parameter("line_count", 0)
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
	var identity := rig.identity_of(pony)
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
	if not is_instance_valid(pony) or is_instance_valid(teats_mesh):
		return
	var profile := _profile()
	var who := _fit_id()
	var size := _teat_size()
	generated_teats = false
	var body := rig.body_of(pony)
	if is_instance_valid(skeleton) and body != null and body.skin != null:
		var body_size := float(profile[2]) if profile.size() >= 3 else 1.0
		var centre := BODY_FIT.base_map(profile, who) * UDDER.MARE_CENTRE
		var built := UDDER.build(body, centre, body_size, size)
		if built != null:
			teats_mesh = MeshInstance3D.new()
			teats_mesh.name = "UnfplapAnatomyTeats"
			teats_mesh.mesh = built
			skeleton.add_child(teats_mesh)
			teats_mesh.skin = body.skin
			teats_mesh.skeleton = teats_mesh.get_path_to(skeleton)
			teats_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			GAME.exclude_from_outline(teats_mesh)
			generated_teats = true
	if not generated_teats:
		teats_mesh = _skinned_part(TEATS_PATH, "UnfplapAnatomyTeats")
		if not is_instance_valid(teats_mesh):
			return
		if not profile.is_empty():
			var map := BODY_FIT.part_map(teats_mesh, body, profile, who)
			var skin: Skin = teats_mesh.skin
			for i in skin.get_bind_count():
				skin.set_bind_pose(i, skin.get_bind_pose(i) * map)
		var shape := clampf(size, 0.0, 1.0)
		teats_mesh.set_blend_shape_value(teats_mesh.find_blend_shape_by_name("mid"),
			1.0 - absf(shape * 2.0 - 1.0))
		teats_mesh.set_blend_shape_value(teats_mesh.find_blend_shape_by_name("full"),
			maxf(shape * 2.0 - 1.0, 0.0))
	teats_jiggle = TEAT_JIGGLE.new()
	teats_jiggle.name = "UnfplapAnatomyTeatJiggle"
	teats_jiggle.skeleton = skeleton
	teats_mesh.add_child(teats_jiggle)
	# Bigger ones swing further; the sway is in metres, so a bigger body's swing scales with her.
	# A princess's own look (PRINCESS_TEATS) adds bounce and a slower spring.
	var look: Dictionary = PRINCESS_TEATS.get(who, {}) if not profile.is_empty() else {}
	var body_size := float(profile[2]) if profile.size() >= 3 else 1.0
	teats_jiggle.swing = (1.0 + 2.0 * size) * body_size * float(look.get("bounce", 1.0))
	teats_jiggle.stiffness_scale = float(look.get("stiffness", 1.0))
	teats_jiggle.damping_scale = float(look.get("damping", 1.0))


func _attach_skin_strip() -> void:
	if not is_instance_valid(pony) or not _profile().is_empty() \
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
	var dock := rig.dock_of(pony)
	if is_instance_valid(dock) and dock.mesh != null:
		var box := dock.mesh.get_aabb()
		_strip_span.x = strip_at.call(Vector3(0.0, box.position.y, box.position.z + box.size.z * 0.5))
	var size := clampf(_teat_size(), 0.0, 1.0)
	_strip_span.y = strip_at.call(Vector3(0.0, TEAT_STRIP_END_Y,
		lerpf(TEAT_STRIP_END_Z.x, TEAT_STRIP_END_Z.y, size)))
	var parts := skeleton.get_bone_global_rest(skeleton.find_bone("pony_hips")) * mesh.transform
	var slit := Vector3(0.0, WINKING_SLIT_HALF, 0.0)
	var gap_a: float = strip_at.call(parts * slit)
	var gap_b: float = strip_at.call(parts * -slit)
	_strip_gap = Vector2(minf(gap_a, gap_b), maxf(gap_a, gap_b))


func _teat_size() -> float:
	var identity := rig.identity_of(pony)
	# Her Characters-tab preset (Teat size) wins over the automatic size.
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
	var chosen := SETTINGS.preferences(id).str_value("teat_size", "auto") \
		if not id.is_empty() else "auto"
	if PREFERENCES.TEAT_SIZE_VALUES.has(chosen):
		return float(PREFERENCES.TEAT_SIZE_VALUES[chosen])
	var look: Variant = PRINCESS_TEATS.get(_fit_id(), null)
	if look is Dictionary and (look as Dictionary).has("size"):
		return clampf(float((look as Dictionary)["size"]), 0.0, 1.0)
	# From her name, in quarter steps: a town of mares then shares a handful of built shapes.
	var name_id := str(identity.get("id")) if identity != null else ""
	return snappedf(float(absi(name_id.hash()) % 101) / 100.0, 0.25)


## A mesh modelled on the shared mare body and skinned with her own weights.
func _skinned_part(path: String, part_name: String) -> MeshInstance3D:
	var body := rig.body_of(pony)
	if not is_instance_valid(skeleton) or body == null:
		return null
	if body.skin == null:
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		LOG.error("anatomy: cannot load %s", [path])
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
	GAME.exclude_from_outline(mesh_node)
	return mesh_node
