extends Node
## integration: ported from PonyPussyParadise runtime anatomy attachment. One per adult mare,
## persistent across acts. The mesh and textures are local-only assets; if they are missing the
## controller stays empty and every public method is a no-op.

const TEAT_JIGGLE := preload("res://mods/unfplap/teat_jiggle.gd")
const CLIMAX_FLUID := preload("res://mods/unfplap/climax_fluid.gd")
const DOCK := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/"
const WINKING_PATH := ASSET_DIR + "winking.scn"
const ANAL_PATH := ASSET_DIR + "anal.scn"
const ANAL_RING_PATH := ASSET_DIR + "anal_ring.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"
const PLACE_PATH := "user://mods/data/unfplap/anatomy_place.json"
## Placements saved before the 5 mm forward default are shifted once on load, so every mare keeps
## the same calibration without re-tuning each one by hand.
const PLACE_FORWARD_M := 0.005
const PLACE_VERSION := 1

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
## Shader widening applied to the vulva per unit of stretch, so the anal bulb never scales with it.
## How far outside the rim the widening fades out. The measured mound ends ~4.5 cm from the
## opening and the anal bulb starts ~8 cm out, so this keeps the bulb out of the deformation.
const LIP_OUTER_FACTOR := 3.0
## Anal cup rim fallback, in its own mesh units, replaced by the measured value at attach.
const ANAL_LIP := 0.022
## Outer-radius factor for the original cup model.
const ANAL_OUTER_FACTOR := 2.2
const WINKING_CUT_FILLED := 0.9
const WINKING_SLIT_HALF := 0.06
const TEAT_STRIP_END_Y := 0.384
const TEAT_STRIP_END_Z := Vector2(0.18, 0.175)
const STRIP_END_FADE := 0.03
const WINKING_BODIES := {"celestia": [0.853, 0.3329, 1.67], "luna": [0.596, 0.2265, 1.095]}
## integration: global placement calibrated on Fluttershy. A per-mare saved row still wins.
const DEFAULT_PLACE := Vector3(-0.005, 0.525, 0.286)
const DEFAULT_PITCH := -6.0
const DEFAULT_SCALE := 0.662

var pony: Node3D
var runtime: Node
var main: Node

var _mesh: MeshInstance3D
var _anal_mesh: MeshInstance3D
var _teats_mesh: MeshInstance3D
var _skin_strip: MeshInstance3D
var _teats_jiggle: Node
var _fluid: Node3D
var _skeleton: Skeleton3D
var _bone_inverse := Transform3D.IDENTITY
var _pos := DEFAULT_PLACE
var _pitch := DEFAULT_PITCH
var _scale := DEFAULT_SCALE
var _body: Array = []
var _lift := 0.0
var _dock_bottom := INF
## The tail dock mesh; with genitals attached it reads as a stray blob above the ponut.
var _dock: MeshInstance3D
var _dock_was_visible := true
## Mean radius of the lip band in mesh-local units, measured once so the opening can be solved
## exactly against the shaft's radius instead of scaled by a constant.
var _lip_radius := 0.03
## The anal cup's ring radius, measured the same way, so its opening is solved against the shaft
## instead of a constant.
var _anal_lip_radius := ANAL_LIP
## True when the experimental ring model is loaded instead of the original cup.
var _anal_ring := false
## Anon's shaft, published every frame for the collision projection.
var _shaft_pivot := Vector3.ZERO
var _shaft_axis := Vector3.ZERO
var _shaft_length := 0.0
var _shaft_radii := PackedFloat32Array()
var _closed := 1.0
var _rest := 1.0
var _fill := 0.0
var _wide := 0.0
var _tween: Tween
var _strip_span := Vector2(0.0, 1.0)
var _strip_gap := Vector2(2.0, 2.0)
var _missing_logged := false
var _attached := false
## integration: visibility is polled, not rewritten every frame, and act-only can hide it.
const VISIBILITY_POLL_S := 0.2
var _visibility_clock := 0.0
var _visibility_init := false
var _last_shown := false
var _last_teats_shown := false


static func assets_exist() -> bool:
	return ResourceLoader.exists(WINKING_PATH) and ResourceLoader.exists(ANAL_PATH) \
		and ResourceLoader.exists(TEATS_PATH) and ResourceLoader.exists(STRIP_PATH)


## integration: only the modern preference roster gets anatomy. Identity filly/stallion checks stay,
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
	_dock = dock
	if is_instance_valid(dock):
		_dock_was_visible = dock.visible
	if _body.is_empty() and is_instance_valid(dock) and dock.mesh != null:
		_dock_bottom = dock.mesh.get_aabb().position.y
	_apply_place()
	_lip_radius = _measure_lip_radius()
	_apply_material()
	_attach_anal()
	_attach_teats()
	_attached = true
	_visibility_init = false
	set_process(true)
	_apply_visibility()
	_log("anatomy attached lift=%.3f dock_bottom=%.3f" % [_lift, _dock_bottom])


func _process(delta: float) -> void:
	_visibility_clock -= delta
	if _visibility_clock > 0.0:
		return
	_visibility_clock = VISIBILITY_POLL_S
	_refresh_anal_ring()
	_apply_anal_place()
	var started := Time.get_ticks_usec()
	_apply_visibility()
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_visibility", Time.get_ticks_usec() - started)


## integration: act-only visibility. POSING_IN, ACTIVE, CLIMAX and AFTERGLOW are the act.
func _act_visible() -> bool:
	if not TUNABLES.get_bool("anatomy.act_only"):
		return true
	if not is_instance_valid(runtime):
		return true
	var state := int(runtime.get("state"))
	return state in [1, 2, 3, 4]


func _apply_visibility() -> void:
	if not _attached or not is_instance_valid(pony):
		return
	var far := bool(pony.get("_far_mesh_shown")) if pony.get("_far_mesh_shown") != null else false
	var teats_on := TUNABLES.get_bool("anatomy.teats")
	var show := not far and _act_visible()
	var teats_show := show and teats_on
	if _visibility_init and show == _last_shown and teats_show == _last_teats_shown:
		return
	_visibility_init = true
	_last_shown = show
	_last_teats_shown = teats_show
	if is_instance_valid(_mesh):
		_mesh.visible = show
	if is_instance_valid(_anal_mesh):
		_anal_mesh.visible = show
	_apply_dock(show)
	if is_instance_valid(_teats_mesh):
		_teats_mesh.visible = teats_show
	if is_instance_valid(_skin_strip):
		_skin_strip.visible = teats_show
	if is_instance_valid(_teats_jiggle):
		_teats_jiggle.set_physics_process(teats_show)


## The dock is a skinned mesh, so hiding it is the only reliable way to stop it reading as a
## stray blob above the ponut once the anatomy is visible.
func _apply_dock(anatomy_shown: bool) -> void:
	if not is_instance_valid(_dock):
		return
	if not anatomy_shown:
		_dock.visible = _dock_was_visible
		return
	_dock.visible = not TUNABLES.get_bool("anatomy.hide_dock")


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
	data = _migrate_place(data)
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


## One-time shift of the saved per-mare placements onto the current forward default.
func _migrate_place(data: Dictionary) -> Dictionary:
	if int(data.get("version", 0)) >= PLACE_VERSION:
		return data
	for id: Variant in data.keys():
		if str(id) == "version":
			continue
		var row: Variant = data[id]
		if not row is Dictionary:
			continue
		var pos: Variant = (row as Dictionary).get("position")
		if pos is Array and (pos as Array).size() == 3:
			(row as Dictionary)["position"] = [
				float(pos[0]), float(pos[1]), float(pos[2]) + PLACE_FORWARD_M]
	data["version"] = PLACE_VERSION
	var file := FileAccess.open(PLACE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	return data


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
	var world_scale := maxf(_mesh.global_transform.basis.get_scale().x, 0.001)
	material.set_shader_parameter("cover_depth",
		TUNABLES.get_float("anatomy.cover_depth_m") / world_scale)
	material.set_shader_parameter("vulva_centre", WINKING_OPENING)
	material.set_shader_parameter("lip_radius", _lip_radius)
	material.set_shader_parameter("lip_outer", _lip_radius * LIP_OUTER_FACTOR)
	material.set_shader_parameter("lip_vertical",
		clampf(TUNABLES.get_float("anatomy.lip_vertical"), 0.0, 1.0))
	material.set_shader_parameter("anal_swell_centre", ANAL_OPENING)
	material.set_shader_parameter("anal_swell", 0.0)
	# `_wide` is the world shaft radius; the shader works in mesh units.
	material.set_shader_parameter("hole_target", _wide / world_scale)
	_mesh.set_surface_override_material(0, material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(_mesh)
	if is_instance_valid(_anal_mesh):
		_configure_anal_material(material)
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
	_anal_ring = TUNABLES.get_bool("anatomy.anal_ring")
	if _anal_ring and not ResourceLoader.exists(ANAL_RING_PATH):
		_anal_ring = false
	var scene: PackedScene = load(ANAL_RING_PATH if _anal_ring else ANAL_PATH)
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
	if _anal_ring:
		_anal_lip_radius = _measure_ring_radius(mesh, ANAL_OPENING, ANAL_LIP)
	_apply_anal_place()
	if _mesh.get_surface_override_material(0) is ShaderMaterial:
		_configure_anal_material(_mesh.get_surface_override_material(0) as ShaderMaterial)


## Swap the anal asset when the ring toggle changes (the model is picked at attach, so a live
## toggle detaches and re-attaches it). Falls back to the cup when the ring asset is missing.
func _refresh_anal_ring() -> void:
	var want := TUNABLES.get_bool("anatomy.anal_ring") and ResourceLoader.exists(ANAL_RING_PATH)
	if want == _anal_ring:
		return
	if is_instance_valid(_anal_mesh):
		_anal_mesh.queue_free()
		_anal_mesh = null
	_attach_anal()


## Share one anal material setup between attach and later re-applies. The original cup keeps its
## authored rim and outer factor; the ring solves against its measured rim.
func _configure_anal_material(base: ShaderMaterial) -> void:
	if not is_instance_valid(_anal_mesh) or base == null:
		return
	var anal_material := base.duplicate() as ShaderMaterial
	anal_material.set_shader_parameter("vulva_centre", ANAL_OPENING)
	if _anal_ring:
		anal_material.set_shader_parameter("lip_radius", _anal_lip_radius)
		anal_material.set_shader_parameter("lip_outer", _anal_lip_radius * LIP_OUTER_FACTOR)
		_fade_anal_rim(anal_material)
	else:
		anal_material.set_shader_parameter("lip_radius", ANAL_LIP)
		anal_material.set_shader_parameter("lip_outer", ANAL_LIP * ANAL_OUTER_FACTOR)
	anal_material.set_shader_parameter("hole_target", 0.0)
	_anal_mesh.set_surface_override_material(0, anal_material)


## The anal overlay fades its outer rim to `coat_color`. Point that at the anatomy skin rather
## than her coat, so the rim disappears into the vulva mesh behind it; the shader also scales its
## silhouette contour by `1 - to_coat`, so this stops the overlay edge drawing a ring.
func _fade_anal_rim(material: ShaderMaterial) -> void:
	var skin: Variant = material.get_shader_parameter("skin_color")
	if skin is Color:
		material.set_shader_parameter("coat_color", skin)
	var shade: Variant = material.get_shader_parameter("skin_shadow")
	if shade is Color:
		material.set_shader_parameter("coat_shadow", shade)


## Place the anal mesh from its live controls: height, side offset and a tilt about the opening.
## They move the node, so the mesh's own space (and the shader's `vulva_centre`) stays on
## ANAL_OPENING. Positive height is up, and positive `anal_tilt_deg` turns the outward normal
## toward local -Y (down). Applies to both the cup and the ring.
func _apply_anal_place() -> void:
	if not is_instance_valid(_anal_mesh):
		return
	var height := TUNABLES.get_float("anatomy.anal_height_mm") / 1000.0
	var side := TUNABLES.get_float("anatomy.anal_side_mm") / 1000.0
	var tilt := deg_to_rad(TUNABLES.get_float("anatomy.anal_tilt_deg"))
	var basis := Basis(Vector3.RIGHT, tilt)
	var offset := Vector3(side, height, 0.0)
	_anal_mesh.transform = Transform3D(basis, ANAL_OPENING - basis * ANAL_OPENING + offset)


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
	_teats_jiggle.set("runtime", runtime)
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
	_refresh_anal_ring()
	_apply_anal_place()
	_apply_visibility()


func detach() -> void:
	_attached = false
	_visibility_init = false
	set_process(false)
	if is_instance_valid(_fluid):
		_fluid.queue_free()
	_fluid = null
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


## integration: one persistent fluid node per pony, reused by every act.
func fluid() -> Node3D:
	if not _enabled() or not is_instance_valid(pony):
		return null
	if not is_instance_valid(_fluid):
		_fluid = CLIMAX_FLUID.new()
		_fluid.name = "UnfplapAnatomyFluid"
		_fluid.set("runtime", runtime)
		pony.add_child(_fluid)
	_fluid.set("runtime", runtime)
	_fluid.set("skeleton", pony.get("skeleton"))
	_fluid.set("body_scale",
		float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0)
	return _fluid


func anal_mesh() -> MeshInstance3D:
	return _anal_mesh


func hole_local(mix: float) -> Vector3:
	return WINKING_OPENING.lerp(ANAL_OPENING, mix)


func hole_point(mix: float) -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.ZERO
	var point := _mesh.global_transform * WINKING_OPENING
	if not is_instance_valid(_anal_mesh):
		return point
	# The anal mesh can be moved and tilted on its own, so its opening is not the vulva mesh's
	# transform applied to ANAL_OPENING.
	return point.lerp(_anal_mesh.global_transform * ANAL_OPENING, clampf(mix, 0.0, 1.0))


func hole_rear(mix := 0.0) -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.BACK
	var rear := _mesh.global_basis.z.normalized()
	if not is_instance_valid(_anal_mesh):
		return rear
	var anal := _anal_mesh.global_basis.z.normalized()
	var blended := rear.lerp(anal, clampf(mix, 0.0, 1.0))
	return blended.normalized() if blended.length_squared() > 0.000001 else rear


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


## Open the lips to the shaft's actual radius. `shaft_radius` is world metres; the mesh works in
## local units, so it is converted with the mesh scale and solved against the measured lip radius:
## the lip band is remapped from the rim out to `lip_outer`, so the opening reaches exactly that
## radius while the outer silhouette keeps its shape.
func set_grip(shaft_radius: float) -> void:
	_wide = maxf(shaft_radius, 0.0)
	if not is_instance_valid(_mesh):
		return
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	var scale := maxf(_mesh.global_transform.basis.get_scale().x, 0.0001)
	var local := shaft_radius / scale
	# No blend shape at all: it scales the whole mesh. The shader opens the hole by translating
	# the rim band outward to the measured shaft radius.
	var shape := _mesh.find_blend_shape_by_name("stretch")
	if shape >= 0:
		_mesh.set_blend_shape_value(shape, 0.0)
	material.set_shader_parameter("hole_target", local)


## Publish Anon's shaft so the shader can project any vertex that ends up inside it back onto the
## surface. `radii` are world metres, sampled evenly from base to tip.
func set_shaft(pivot: Vector3, axis: Vector3, length: float, radii: PackedFloat32Array) -> void:
	_shaft_pivot = pivot
	_shaft_axis = axis
	_shaft_length = length
	_shaft_radii = radii
	_push_shaft(_mesh)
	_push_shaft(_anal_mesh)


func _push_shaft(target: MeshInstance3D) -> void:
	if not is_instance_valid(target):
		return
	var material := target.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("shaft_pivot", _shaft_pivot)
	material.set_shader_parameter("shaft_axis", _shaft_axis)
	material.set_shader_parameter("shaft_length", _shaft_length)
	material.set_shader_parameter("shaft_radii", _shaft_radii)


func clear_shaft() -> void:
	var zeros := PackedFloat32Array()
	zeros.resize(8)
	set_shaft(Vector3.ZERO, Vector3.ZERO, 0.0, zeros)


## The lip band's mean radius in local units, used by the grip solve and by tuning readouts.
func lip_radius() -> float:
	return _lip_radius


## Measure the inner lip ring from the mesh geometry. The vertex colours cannot be used: 90 % of
## the mesh carries the lip flag. The rim is the first radius whose vertex density is high, found
## by binning the planar distance from the opening.
func _measure_lip_radius() -> float:
	return _measure_ring_radius(_mesh, WINKING_OPENING, 0.03)


func _measure_ring_radius(target: MeshInstance3D, centre: Vector3, fallback: float) -> float:
	if not is_instance_valid(target) or target.mesh == null:
		return fallback
	var arrays := target.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return fallback
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return fallback
	const STEP := 0.002
	const BINS := 40
	var bin_counts := PackedInt32Array()
	bin_counts.resize(BINS)
	for v: Vector3 in verts:
		var radius := Vector2(v.x - centre.x, v.y - centre.y).length()
		var bin := int(radius / STEP)
		if bin >= 0 and bin < BINS:
			bin_counts[bin] += 1
	var peak := 0
	for bin: int in BINS:
		peak = maxi(peak, bin_counts[bin])
	if peak == 0:
		return fallback
	# Walk inward from the densest band until the density collapses: that edge is the rim.
	var dense := int(float(peak) * 0.25)
	var rim_bin := 0
	for bin: int in BINS:
		if bin_counts[bin] >= dense:
			rim_bin = bin
			break
	return maxf(float(rim_bin) * STEP, 0.004)


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
			* TUNABLES.get_float("anatomy.hole_depth")
			* _mesh.global_transform.basis.get_scale().x)


## Scale the whole vulva model about the anal opening while the anal is in use, so the ponut
## swells with the shaft. Called by the act with the live `_hole_mix`; 0 restores the vulva.
func set_anal_swell(amount: float) -> void:
	if not is_instance_valid(_mesh):
		return
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("anal_swell", clampf(amount, 0.0, 1.0))


## The cup's ring is opened by the same shader solve as the vulva's lips: `shaft_radius` is world
## metres, converted to mesh units and solved against the measured rim. No blend shape is used;
## the authored `open`/`stretch` shapes are left at zero.
func set_anal_grip(shaft_radius: float) -> void:
	if not is_instance_valid(_anal_mesh) or not _anal_ring:
		return
	var material := _anal_mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	var scale := maxf(_anal_mesh.global_transform.basis.get_scale().x, 0.0001)
	material.set_shader_parameter("hole_target", maxf(shaft_radius, 0.0) / scale)
	# Also grow the pucker's depth with the widening, so the ring scales as a mound around the
	# shaft instead of staying a flat sheet. Live, like the grip.
	material.set_shader_parameter("hole_depth_scale",
		maxf(TUNABLES.get_float("anatomy.anal_depth"), 0.0))


## `fill` is the old `anal * 1.4` cut amount; `wide` is the old `anal` stretch amount. The ring
## model uses `wide` for the cut depth and is opened by `set_anal_grip()`; the original cup keeps
## its authored `open`/`stretch` blend shapes and local widening.
func set_anal_shape(fill: float, wide := 0.0) -> void:
	if not is_instance_valid(_anal_mesh):
		return
	var material := _anal_mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	var scale := _mesh.global_transform.basis.get_scale().x
	var hug := maxf(TUNABLES.get_float("anatomy.anal_hug"), 0.01)
	if _anal_ring:
		material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * scale
			* minf(wide * 4.0, 1.0) * lerpf(0.5, WINKING_CUT_FILLED / hug, minf(wide, 1.0)))
		return
	var stretch := _anal_mesh.find_blend_shape_by_name("stretch")
	if stretch >= 0:
		_anal_mesh.set_blend_shape_value(stretch, wide)
	var open := _anal_mesh.find_blend_shape_by_name("open")
	if open >= 0:
		_anal_mesh.set_blend_shape_value(open, maxf(fill - wide, 0.0))
	material.set_shader_parameter("hole_target", wide * ANAL_LIP * 1.6)
	material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * scale
		* minf(fill * 4.0, 1.0) * lerpf(0.5, WINKING_CUT_FILLED / hug, minf(fill, 1.0)))


func react() -> void:
	if is_instance_valid(_mesh):
		wink(2)


func _clear_part() -> void:
	set_fill(0.0)
	set_grip(0.0)
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
	data["version"] = PLACE_VERSION
	DirAccess.make_dir_recursive_absolute(PLACE_PATH.get_base_dir())
	var file := FileAccess.open(PLACE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func reset_place() -> void:
	_pos = DEFAULT_PLACE
	_pitch = DEFAULT_PITCH
	_scale = DEFAULT_SCALE
	_apply_place()



func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
