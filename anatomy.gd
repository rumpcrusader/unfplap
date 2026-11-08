extends Node
## integration: ported from PonyPussyParadise runtime anatomy attachment. One per adult mare,
## persistent across acts. The mesh and textures are local-only assets; if they are missing the
## controller stays empty and every public method is a no-op.

const TEAT_JIGGLE := preload("res://mods/unfplap/teat_jiggle.gd")
const CLIMAX_FLUID := preload("res://mods/unfplap/climax_fluid.gd")
const DOCK := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const STILL_ZONE_DEBUG := preload("res://mods/unfplap/still_zone_debug.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/"
const WINKING_PATH := ASSET_DIR + "winking.scn"
const MARE_BITS_V2_PATH := ASSET_DIR + "mare_bits_v2.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"
const PLACE_PATH := "user://mods/data/unfplap/anatomy_place.json"
## Placements saved before the 5 mm forward default are shifted once on load, so every mare keeps
## the same calibration without re-tuning each one by hand.
const PLACE_FORWARD_M := 0.005
## The old global calibration also carried a 5 mm lateral bias. The rump crease is the model's
## x = 0 plane, so saved rows are shifted back onto it once.
const PLACE_RIGHT_M := 0.005
const PLACE_VERSION := 2

const WINKING_PINK := Color(0.97, 0.66, 0.74)
const WINKING_PINK_SHADE := Color(0.84, 0.47, 0.57)
const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
## Authored lip band radius. The density walk is unreliable on the denser V2 mesh, which
## can collapse the measured value to the 4 mm floor and make the shader open a huge ring.
const WINKING_LIP_RADIUS := 0.018
## The authored `closed` shape also pulls the anal rim. The runtime rebuild masks that out.
const WINK_ANAL_FROM_Y := 0.020
const WINK_ANAL_TO_Y := 0.050
## How open a heat mare rests between winks, as a share of the authored wink shape.
const HEAT_REST_OPEN := 0.20
const ANAL_OPENING := Vector3(0.0, 0.071, 0.019)
## The V2 mesh owns the anus, so its ring centre is not the old cup's ANAL_OPENING. These are
## the measured outer-ring centres (Godot mesh local) at each additive anal key.
const V2_ANAL_RING_BASE := Vector3(0.00275, 0.06314, 0.01908)
const V2_ANAL_RING_OPEN := Vector3(0.00262, 0.06183, 0.01908)
const V2_ANAL_RING_STRETCH := Vector3(0.00272, 0.06286, 0.01908)
const V2_ANAL_RING_OVER := Vector3(0.00279, 0.05955, 0.01908)
const V2_ANAL_RING_EXTREME := Vector3(0.00303, 0.03996, 0.03310)
const V2_ANAL_RING_PONUT := Vector3(0.00296, 0.06515, 0.03310)
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
## Anal rim fallback, in mesh units. The V2 mesh owns the anal opening now.
const ANAL_LIP := 0.022
## V2 anal blend-shape radii, mesh-local. Each key starts where the previous one ends.
const ANAL_OPEN_R := 0.008
const ANAL_STRETCH_R := 0.020
const ANAL_OVER_R := 0.028
const ANAL_EXTREME_R := 0.056
## Outer-radius factor for the original cup model.
const ANAL_OUTER_FACTOR := 2.2
const WINKING_CUT_FILLED := 0.9
const WINKING_SLIT_HALF := 0.06
const TEAT_STRIP_END_Y := 0.384
const TEAT_STRIP_END_Z := Vector2(0.18, 0.175)
const STRIP_END_FADE := 0.03
const WINKING_BODIES := {"celestia": [0.853, 0.3329, 1.67], "luna": [0.596, 0.2265, 1.095]}
## Runtime patch of the rig coat shader. It swaps only the flank_jiggle include and call in a
## duplicated Shader, so no game source is edited and the cel shader is not copied.
const BODY_COAT_PATCH := preload("res://mods/unfplap/body_coat_patch.gd")
## The visible ponut is the pony body, not the genitals overlay. These are body-local: the
## Blender body.glb anus centre (0, -0.299, 0.572) maps to Godot (0, 0.572, 0.299).
const BODY_ANAL_CENTRE := Vector3(0.0, 0.572, 0.299)
const BODY_ANAL_REACH := 0.09
## The body coat gives under the stretched vulva rim by this much per unit of lip opening.
const VULVA_RELIEF_M := 0.002
## The no-jiggle zone never goes below this body-local radius, so a small vulva still has a
## stable still patch instead of a pinprick.
const JIGGLE_STILL_MIN_M := 0.05

## integration: global placement calibrated on Fluttershy. The rump crease is the body's x = 0
## plane, so the anatomy has no lateral offset. A per-mare saved row still wins.
const DEFAULT_PLACE := Vector3(0.0, 0.525, 0.286)
const DEFAULT_PITCH := -6.0
const DEFAULT_SCALE := 0.742

var pony: Node3D
var runtime: Node
var main: Node

var _mesh: MeshInstance3D
var _body_mesh: MeshInstance3D
var _body_material: ShaderMaterial
var _body_outline: ShaderMaterial
var _body_original_shader: Shader
var _body_outline_original_shader: Shader
var _body_patched := false
## Debug overlay for the two still zones.
var _zone_debug: Node3D
var _zone_vulva_centre := Vector3.ZERO
var _zone_anal_centre := Vector3.ZERO
var _zone_axes := Basis.IDENTITY
var _zone_vulva_radius := 0.0
var _zone_anal_radius := 0.0
var _zone_oval := 0.7
var _zone_fade := 0.25
## pony_hips bind pose from the body skin: anatomy-local -> body-local (NearBody) space.
var _hips_bind := Transform3D.IDENTITY
var _hips_bind_ready := false
var _mare_bits_path_loaded := ""
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
## True when the loaded mare mesh is the V2 anatomy with the anal shape keys.
var _v2_anal := false
## Last anal opening radius in mesh units; re-applied when the ponut scale changes.
var _anal_local := 0.0
## Current V2 ring centre in mesh local, tracked through the additive anal keys.
var _anal_mouth := V2_ANAL_RING_BASE
## Anon's shaft, published every frame for the collision projection.
var _shaft_pivot := Vector3.ZERO
var _shaft_axis := Vector3.ZERO
var _shaft_length := 0.0
var _shaft_radii := PackedFloat32Array()
var _closed := 1.0
var _rest := 1.0
## 0 = the authored closed shape, 1 = the authored `wink` shape. Idle heat crossfades these.
var _wink_amount := 0.0
var _fill := 0.0
var _wide := 0.0
## The solved anatomy-local opening radius last pushed by set_grip; the body coat spread uses
## the same value so the hug setting stays consistent between the lips and the coat.
var _hole_target := 0.0
var _tween: Tween
var _strip_span := Vector2(0.0, 1.0)
var _strip_gap := Vector2(2.0, 2.0)
var _missing_logged := false
var _attached := false
## integration: visibility is polled, not rewritten every frame, and act-only can hide it.
const VISIBILITY_POLL_S := 0.2
## How often the idle heat tick re-reads the estrus phase.
const HEAT_PHASE_POLL_S := 2.0
const IDLE_FLUID_SIZE := 0.0055
const IDLE_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)
var _visibility_clock := 0.0
var _visibility_init := false
var _last_shown := false
var _last_teats_shown := false
var _last_strip_shown := false
## integration: idle heat display. POSING_IN, ACTIVE and CLIMAX suppress it because the act
## controller owns the mesh then; IDLE, AFTERGLOW, RESTORE and sleeping allow it.
var _heat_phase := ""
var _heat_phase_clock := 0.0
var _heat_wink_clock := 0.0
var _heat_suppressed := false


static func assets_exist() -> bool:
	return ResourceLoader.exists(WINKING_PATH) and ResourceLoader.exists(TEATS_PATH) \
		and ResourceLoader.exists(STRIP_PATH)


## integration: the V2 model is optional; fall back to the original PPP mesh when absent.
static func selected_mare_bits_path() -> String:
	if SETTINGS.mare_bits.get_choice() == "v2" \
			and ResourceLoader.exists(MARE_BITS_V2_PATH):
		return MARE_BITS_V2_PATH
	return WINKING_PATH


static var _refined_winking_meshes := {}


## integration: rebuild each winking source mesh once and share it across mares. The authored
## `closed` and `wink` shapes both pull the anal rim; the rebuild masks that out so only the
## vulva moves. Keyed by source so the original and V2 models can coexist.
static func refined_winking_mesh(source: ArrayMesh) -> ArrayMesh:
	if source == null:
		return null
	if _refined_winking_meshes.has(source):
		return _refined_winking_meshes[source] as ArrayMesh
	var rebuilt := ArrayMesh.new()
	rebuilt.blend_shape_mode = source.blend_shape_mode
	var closed_index := -1
	var wink_index := -1
	for i in source.get_blend_shape_count():
		var shape_name := source.get_blend_shape_name(i)
		rebuilt.add_blend_shape(shape_name)
		if shape_name == &"closed":
			closed_index = i
		elif shape_name == &"wink":
			wink_index = i
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var shapes: Array = source.surface_get_blend_shape_arrays(surface)
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var typed_shapes: Array[Array] = []
		for s in shapes.size():
			var shape: Array = shapes[s]
			var shape_verts: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			if (s == closed_index or s == wink_index) and shape_verts.size() == base.size():
				for i in shape_verts.size():
					var p := base[i]
					var anal := 1.0 - smoothstep(WINK_ANAL_FROM_Y, WINK_ANAL_TO_Y, p.y)
					var delta := shape_verts[i] - p
					shape_verts[i] = p + delta * anal
				shape[Mesh.ARRAY_VERTEX] = shape_verts
			typed_shapes.append(shape)
		rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(surface),
			arrays, typed_shapes, {}, 0)
		rebuilt.surface_set_material(surface, source.surface_get_material(surface))
		rebuilt.surface_set_name(surface, source.surface_get_name(surface))
	_refined_winking_meshes[source] = rebuilt
	return rebuilt


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
	return SETTINGS.anatomy_on()


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
	var selected := selected_mare_bits_path()
	var scene: PackedScene = load(selected)
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
	_mare_bits_path_loaded = selected
	_v2_anal = selected == MARE_BITS_V2_PATH
	_anal_mouth = V2_ANAL_RING_BASE
	var refined := refined_winking_mesh(mesh.mesh as ArrayMesh)
	if refined != null:
		mesh.mesh = refined
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
	_attach_teats()
	_attach_skin_strip(_teat_size())
	if _mesh.get_surface_override_material(0) is ShaderMaterial:
		_apply_teats_material(_mesh.get_surface_override_material(0) as ShaderMaterial)
	_apply_anal_shape(0.0)
	_attached = true
	_visibility_init = false
	if pony.has_signal("physical_reaction") \
			and not pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.connect(_on_physical_reaction)
	set_process(true)
	_apply_visibility()
	_log("anatomy attached lift=%.3f dock_bottom=%.3f" % [_lift, _dock_bottom])


## A stock flank smack (outside the act) never reaches the runtime's thrust/smack path, and
## FlankTouch does not recognise the mod-owned near-body shader. Re-add the targets when she is
## slapped so the near body and its outline wobble too.
func _on_physical_reaction(kind: String) -> void:
	if kind != "flank_smack":
		return
	if is_instance_valid(runtime) and runtime.has_method("_attach_body_coat_jiggle_target"):
		runtime.call("_attach_body_coat_jiggle_target")


func _process(delta: float) -> void:
	_heat_idle_tick(delta)
	_debug_zones_tick()
	_visibility_clock -= delta
	if _visibility_clock > 0.0:
		return
	_visibility_clock = VISIBILITY_POLL_S
	_apply_place()
	_apply_anal_shape(_anal_local)
	_apply_body_coat()
	_apply_strip_scale()
	var started := Time.get_ticks_usec()
	_apply_visibility()
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_visibility", Time.get_ticks_usec() - started)


## integration: the visibility pill. `act` shows her only during the act's states: POSING_IN,
## ACTIVE, CLIMAX and AFTERGLOW.
func _act_visible() -> bool:
	match SETTINGS.anatomy_mode.get_choice():
		"always":
			return true
		"act":
			if not is_instance_valid(runtime):
				return true
			return int(runtime.get("state")) in [1, 2, 3, 4]
	return false


func _apply_visibility() -> void:
	if not _attached or not is_instance_valid(pony):
		return
	var far := bool(pony.get("_far_mesh_shown")) if pony.get("_far_mesh_shown") != null else false
	var teats_on := SETTINGS.teats.get_bool()
	var strip_on := SETTINGS.skin_strip.get_bool()
	var show := not far and _act_visible()
	var teats_show := show and teats_on
	var strip_show := show and strip_on
	if _visibility_init and show == _last_shown and teats_show == _last_teats_shown \
			and strip_show == _last_strip_shown:
		return
	_visibility_init = true
	_last_shown = show
	_last_teats_shown = teats_show
	_last_strip_shown = strip_show
	if is_instance_valid(_mesh):
		_mesh.visible = show
	_apply_dock(show)
	if is_instance_valid(_teats_mesh):
		_teats_mesh.visible = teats_show
	if is_instance_valid(_skin_strip):
		_skin_strip.visible = strip_show
	if is_instance_valid(_teats_jiggle):
		_teats_jiggle.set_physics_process(teats_show)


func _heat_idle_tick(delta: float) -> void:
	if not _attached or not is_instance_valid(runtime) or not is_instance_valid(pony):
		return
	# POSING_IN, ACTIVE and CLIMAX are the act; it owns the mesh. AFTERGLOW and RESTORE are free.
	var state := int(runtime.get("state"))
	if state in [1, 2, 3]:
		if not _heat_suppressed:
			_heat_suppressed = true
			_heat_phase = ""
			_heat_phase_clock = 0.0
			_heat_wink_clock = CYCLE.wink_interval()
		return
	_heat_suppressed = false
	if not _heat_visible():
		return

	_heat_phase_clock -= delta
	if _heat_phase_clock <= 0.0:
		_heat_phase_clock = HEAT_PHASE_POLL_S
		var phase := str(runtime.call("cycle_phase"))
		if phase != _heat_phase:
			_heat_phase = phase
			_heat_wink_clock = CYCLE.wink_interval() if phase == CYCLE.HEAT else 0.0

	# Heat rests slightly open; normal and diestrus rest closed. Do not fight a wink tween.
	if _tween == null or not _tween.is_running():
		var idle_rest := HEAT_REST_OPEN if _heat_phase == CYCLE.HEAT else 0.0
		if not is_equal_approx(_wink_amount, idle_rest):
			set_idle_wink(idle_rest)

	if _heat_phase != CYCLE.HEAT:
		return

	_heat_wink_clock -= delta
	if _heat_wink_clock > 0.0:
		return
	_heat_wink_clock = CYCLE.wink_interval()
	var count := CYCLE.wink_burst_count(randf())
	wink_burst(count)
	idle_drip(count)


## True when the mesh is actually shown. Far meshes and act-only hiding both skip idle display.
func _heat_visible() -> bool:
	return _last_shown and is_instance_valid(_mesh) and not bool(
		pony.get("_far_mesh_shown") if pony.get("_far_mesh_shown") != null else false)


## The dock is a skinned mesh, so hiding it is the only reliable way to stop it reading as a
## stray blob above the ponut once the anatomy is visible.
func _apply_dock(anatomy_shown: bool) -> void:
	if not is_instance_valid(_dock):
		return
	if not anatomy_shown:
		_dock.visible = _dock_was_visible
		return
	_dock.visible = SETTINGS.show_dock.get_bool()


## The calibrated lift used by every mare. The dock/tail base is not a reliable reference: some
## tails (Derpy's) sit lower and pulled the whole anatomy into the rump. Keep one value so the
## anatomy's size and position are identical across mares.
func _tail_lift() -> float:
	return 0.03


func _apply_place() -> void:
	if not is_instance_valid(_mesh):
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), 0.0, 0.0)).scaled(Vector3.ONE * _scale)
	var lift := _lift
	# The dock-bottom alignment only matters while the dock is drawn. With `hide_dock` on it
	# would pull the anatomy down for a dock nobody sees, and Derpy's dock sits lower than the
	# others', which buried her anatomy.
	if _dock_bottom < INF and SETTINGS.show_dock.get_bool():
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
	var version := int((data as Dictionary).get("version", 0))
	data = migrate_place(data)
	if int((data as Dictionary).get("version", 0)) != version:
		var file := FileAccess.open(PLACE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(data, "\t"))
			file.close()
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


## One-time shift of the saved per-mare placements onto the current global default. Pure: the
## caller writes the result back when the version changed.
static func migrate_place(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version >= PLACE_VERSION:
		return data
	var shift := Vector3.ZERO
	if version < 1:
		shift.z = PLACE_FORWARD_M
	if version < 2:
		shift.x = PLACE_RIGHT_M
	for id: Variant in data.keys():
		if str(id) == "version":
			continue
		var row: Variant = data[id]
		if not row is Dictionary:
			continue
		var pos: Variant = (row as Dictionary).get("position")
		if pos is Array and (pos as Array).size() == 3:
			(row as Dictionary)["position"] = [
				float(pos[0]) + shift.x, float(pos[1]) + shift.y, float(pos[2]) + shift.z]
	data["version"] = PLACE_VERSION
	return data


func _apply_material() -> void:
	if not is_instance_valid(_mesh) or not is_instance_valid(pony):
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://mods/unfplap/anatomy.gdshader")
	var tones := _skin_tones()
	material.set_shader_parameter("skin_color", tones[0])
	material.set_shader_parameter("skin_shadow", tones[1])
	var inner_color := SETTINGS.vulva_inner_color.get_color()
	var clitoris_color := SETTINGS.clitoris_color.get_color()
	material.set_shader_parameter("inner_color", inner_color)
	material.set_shader_parameter("inner_shadow", inner_color.darkened(0.22))
	material.set_shader_parameter("clitoris_color", clitoris_color)
	material.set_shader_parameter("clitoris_shadow", clitoris_color.darkened(0.22))
	var world_scale := maxf(_mesh.global_transform.basis.get_scale().x, 0.001)
	material.set_shader_parameter("vulva_centre", WINKING_OPENING)
	material.set_shader_parameter("anal_centre", ANAL_OPENING)
	material.set_shader_parameter("anal_scale",
		1.0 if _v2_anal else SETTINGS.anal_scale.get_num())
	material.set_shader_parameter("lip_radius", _lip_radius)
	material.set_shader_parameter("lip_outer", _lip_radius * LIP_OUTER_FACTOR)
	material.set_shader_parameter("lip_vertical",
		clampf(SETTINGS.lip_vertical.get_num(), 0.0, 1.0))
	material.set_shader_parameter("vulva_height", SETTINGS.vulva_height.get_num())
	# `_wide` is the world shaft radius; the shader works in mesh units.
	material.set_shader_parameter("hole_target", _wide / world_scale)
	_mesh.set_surface_override_material(0, material)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(_mesh)
	_apply_winking_shape()
	_apply_teats_material(material)


func _skin_tones() -> Array:
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	var base: Color = fill if fill is Color else Color(0.8, 0.8, 0.8)
	var dark: Color = shade if shade is Color else Color(0.68, 0.68, 0.68)
	# The old Coat / Darker / Dark values are the three anchors of one 0…1 slider, with every
	# point between them interpolated.
	var tone := SETTINGS.skin_tone.get_num()
	var darker_fill := base.darkened(0.1)
	var darker_shade := dark.darkened(0.16)
	if tone <= 0.5:
		var k := tone / 0.5
		return [base.lerp(darker_fill, k), dark.lerp(darker_shade, k)]
	var k := (tone - 0.5) / 0.5
	return [darker_fill.lerp(Color(0.26, 0.22, 0.26), k),
		darker_shade.lerp(Color(0.17, 0.14, 0.18), k)]


## The anal opening is part of the V2 mesh now; the old cup/ring attachment is gone.
## The shape keys are driven from the real shaft radius in set_anal_grip().



## True while the anatomy owns the near-body material. A detached anatomy must not re-apply it.
func is_attached() -> bool:
	return _attached


## The visible rig coat and its outline. The runtime uses these to put the runtime-patched
## materials back into FlankTouch's jiggle target list.
func body_coat_mesh() -> MeshInstance3D:
	return _body_mesh if _body_patched and is_instance_valid(_body_mesh) else null

func body_coat_material() -> ShaderMaterial:
	return _body_material if _body_patched and is_instance_valid(_body_material) else null

func body_outline_material() -> ShaderMaterial:
	return _body_outline if _body_patched and is_instance_valid(_body_outline) else null


## pony_hips bind pose from the body skin. `body_local_point` maps a point from the anatomy's
## bone-local space (the mesh's own transform) into the rig coat's vertex space, which is the
## space the patched cel shader writes in. The bind pose is cached because the skin is immutable.
func _hips_bind_pose() -> Transform3D:
	if _hips_bind_ready:
		return _hips_bind
	var model: Variant = pony.get("_model") if is_instance_valid(pony) else null
	if not model is Node:
		return _hips_bind
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.skin == null:
		return _hips_bind
	for i in body.skin.get_bind_count():
		if String(body.skin.get_bind_name(i)) == "pony_hips":
			_hips_bind = body.skin.get_bind_pose(i)
			_hips_bind_ready = true
			break
	return _hips_bind


static func body_local_point(bind: Transform3D, mesh_transform: Transform3D,
		point: Vector3) -> Vector3:
	return bind.affine_inverse() * (mesh_transform * point)


static func body_local_direction(bind: Transform3D, mesh_transform: Transform3D,
		direction: Vector3) -> Vector3:
	return (bind.basis.inverse() * (mesh_transform.basis * direction)).normalized()


## Body-local radius of the visible anal cup's still zone. The cup's own outer ring sets the
## size; the 1.3 margin reaches the coat around it and the floor keeps a small cup usable.
static func anal_still_radius_for(lip: float, outer_factor: float, scale: float,
		multiplier: float) -> float:
	return maxf(lip * outer_factor * scale * 1.3, 0.045) * multiplier


func _apply_strip_scale() -> void:
	if not is_instance_valid(_skin_strip):
		return
	var material := _skin_strip.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("strip_scale", SETTINGS.strip_scale.get_num())


## Push the body coat's anal mound, vulva spread and no-jiggle zone into the rig material and
## its outline. `_hole_target` is anatomy-local; `_lip_radius` is too, so their ratio is unitless.
func _apply_body_coat_uniforms() -> void:
	if not _body_patched or not is_instance_valid(_body_material) \
			or not is_instance_valid(_mesh) or not _hips_bind_ready:
		return
	var scale := maxf(_mesh.transform.basis.get_scale().x, 0.0001)
	var centre := body_local_point(_hips_bind, _mesh.transform, WINKING_OPENING)
	var right_axis := body_local_direction(_hips_bind, _mesh.transform, Vector3.RIGHT)
	var out_axis := body_local_direction(_hips_bind, _mesh.transform, Vector3.BACK)
	var up_axis := body_local_direction(_hips_bind, _mesh.transform, Vector3.UP)
	var spread := maxf(_hole_target / maxf(_lip_radius, 0.004), 1.0)
	spread = 1.0 + (spread - 1.0) * SETTINGS.coat_spread.get_num()
	var reach := maxf(_lip_radius * LIP_OUTER_FACTOR * scale * 1.1, 0.02)
	var depth := (spread - 1.0) * VULVA_RELIEF_M
	var still_centre := centre + up_axis * (SETTINGS.still_height_mm.get_num() / 1000.0)
	var still_radius := maxf(_lip_radius * LIP_OUTER_FACTOR * scale * 1.3,
			JIGGLE_STILL_MIN_M) * SETTINGS.jiggle_still.get_num()
	var anal_centre := BODY_ANAL_CENTRE
	var anal_extreme := maxf(0.0, (_anal_local - ANAL_OVER_R) / (ANAL_EXTREME_R - ANAL_OVER_R))
	if _v2_anal:
		anal_centre = body_local_point(_hips_bind, _mesh.transform, _anal_mouth)
	var anal_still_centre := anal_centre
	var anal_still_radius := anal_still_radius_for(ANAL_LIP, ANAL_OUTER_FACTOR, scale,
		SETTINGS.anal_still.get_num()) * (1.0 + anal_extreme)
	_zone_vulva_centre = still_centre
	_zone_anal_centre = anal_still_centre
	_zone_vulva_radius = still_radius
	_zone_anal_radius = anal_still_radius
	_zone_axes = Basis(right_axis, up_axis, out_axis)
	_zone_oval = SETTINGS.still_oval.get_num()
	_zone_fade = SETTINGS.still_fade.get_num()
	# Follow the extrapolated V2 extreme so the visible body mound wraps the same ring.
	var anal_scale := SETTINGS.anal_scale.get_num() * (1.0 + anal_extreme)
	for material in [_body_material, _body_outline]:
		if not is_instance_valid(material):
			continue
		var mat := material as ShaderMaterial
		mat.set_shader_parameter("body_coat_anal_centre", anal_centre)
		mat.set_shader_parameter("body_coat_anal_scale", anal_scale)
		mat.set_shader_parameter("body_coat_anal_reach", BODY_ANAL_REACH)
		mat.set_shader_parameter("body_coat_anal_out", out_axis)
		mat.set_shader_parameter("body_coat_anal_depth",
			SETTINGS.anal_body_depth_mm.get_num() / 1000.0 * (1.0 + anal_extreme))
		# Keep the body under the V2 lip: the indent must not reach past the outer lip.
		mat.set_shader_parameter("body_coat_anal_hole_reach",
			maxf(_anal_local, ANAL_OPEN_R) * scale)
		mat.set_shader_parameter("body_coat_vulva_centre", centre)
		mat.set_shader_parameter("body_coat_vulva_out", out_axis)
		mat.set_shader_parameter("body_coat_vulva_scale", spread)
		mat.set_shader_parameter("body_coat_vulva_reach", reach)
		mat.set_shader_parameter("body_coat_vulva_depth", depth)
		mat.set_shader_parameter("body_coat_still_centre", still_centre)
		mat.set_shader_parameter("body_coat_still_radius", still_radius)
		mat.set_shader_parameter("body_coat_anal_still_centre", anal_still_centre)
		mat.set_shader_parameter("body_coat_anal_still_radius", anal_still_radius)
		mat.set_shader_parameter("body_coat_still_right", right_axis)
		mat.set_shader_parameter("body_coat_still_up", up_axis)
		mat.set_shader_parameter("body_coat_still_oval", SETTINGS.still_oval.get_num())
		mat.set_shader_parameter("body_coat_still_fade", SETTINGS.still_fade.get_num())


## integration: the ponut and vulva are on the pony body, not the genitals overlay. The rig
## coat (MareBody) is the visible one; NearBody is only the cutie-mark merge. The game shader is
## patched at runtime by body_coat_patch.gd, so no source is edited and no cel shader is copied.
func _apply_body_coat() -> void:
	if not SETTINGS.body_coat_deform.get_bool():
		_restore_body_coat()
		return
	if not is_instance_valid(pony):
		_restore_body_coat()
		return
	var model: Variant = pony.get("_model")
	if not model is Node:
		_restore_body_coat()
		return
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.mesh == null:
		_restore_body_coat()
		return
	if not _hips_bind_ready:
		_hips_bind_pose()
	if _body_mesh != body or not is_instance_valid(_body_material) \
			or body.get_active_material(0) != _body_material:
		_restore_body_coat()
		# The body material is shared between ponies of one identity. FlankTouch owns the
		# per-pony copies and keeps the outline in the pony's outline list.
		var flank := pony.get_node_or_null("FlankTouch")
		if flank != null and flank.has_method("_own_body_materials"):
			flank.call("_own_body_materials")
		var source := body.get_active_material(0) as ShaderMaterial
		if source == null:
			return
		if not source.has_meta("jiggle_own"):
			source = source.duplicate() as ShaderMaterial
			var own_hull := source.next_pass as ShaderMaterial
			if own_hull != null:
				source.next_pass = own_hull.duplicate()
			source.set_meta("jiggle_own", true)
			body.set_surface_override_material(0, source)
		_body_mesh = body
		_body_material = source
		_body_original_shader = source.shader
		var hull := source.next_pass as ShaderMaterial
		_body_outline = hull
		_body_outline_original_shader = hull.shader if hull != null else null
	if not _body_patched:
		var patched := BODY_COAT_PATCH.patched(_body_original_shader)
		if patched == null:
			return
		_body_material.shader = patched
		if _body_outline != null and _body_outline_original_shader != null:
			var hull_patched := BODY_COAT_PATCH.patched(_body_outline_original_shader)
			if hull_patched != null:
				_body_outline.shader = hull_patched
		_body_patched = true
	_ensure_zone_debug()
	_apply_body_coat_uniforms()


## Put the game shaders back. The per-pony material copies stay; only the shader resource and
## the mod uniforms are undone.
func _restore_body_coat() -> void:
	if _body_patched:
		if is_instance_valid(_body_material) and is_instance_valid(_body_original_shader):
			_body_material.shader = _body_original_shader
		if is_instance_valid(_body_outline) and is_instance_valid(_body_outline_original_shader):
			_body_outline.shader = _body_outline_original_shader
	_body_patched = false
	if is_instance_valid(_zone_debug):
		_zone_debug.visible = false
	_body_material = null
	_body_outline = null
	_body_mesh = null
	_body_original_shader = null
	_body_outline_original_shader = null


## Debug-only rings for the two still zones. Created lazily once the body coat is patched and
## hidden whenever the debug toggle or the body coat flag is off.
func _ensure_zone_debug() -> void:
	if is_instance_valid(_zone_debug) or not is_instance_valid(pony):
		return
	_zone_debug = STILL_ZONE_DEBUG.new()
	pony.add_child(_zone_debug)
	_zone_debug.call("setup")


func _debug_zones_tick() -> void:
	if not is_instance_valid(_zone_debug):
		_zone_debug = null
		return
	var show := SETTINGS.draw_still_zones.get_bool() and _body_patched \
		and SETTINGS.body_coat_deform.get_bool() and _hips_bind_ready \
		and is_instance_valid(_skeleton) and is_instance_valid(_mesh)
	if not show:
		_zone_debug.visible = false
		return
	var hip := _skeleton.find_bone("pony_hips")
	if hip < 0:
		_zone_debug.visible = false
		return
	# The zone centres are body-local; the hips skinning transform puts the rings on the posed
	# rump. The rump coat is dominated by this bone, so this is the useful debug frame.
	var body_to_world := _skeleton.global_transform \
		* _skeleton.get_bone_global_pose(hip) * _hips_bind
	_zone_debug.call("update", body_to_world, _zone_vulva_centre, _zone_axes,
		_zone_vulva_radius, _zone_anal_centre, _zone_anal_radius, _zone_oval,
		_zone_fade, true)


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


func _attach_skin_strip(size: float) -> void:
	if not _body.is_empty() or is_instance_valid(_skin_strip):
		return
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
	if not is_instance_valid(base):
		return
	if not is_instance_valid(_teats_mesh) and not is_instance_valid(_skin_strip):
		return
	var material := base.duplicate() as ShaderMaterial
	var identity: Variant = pony.get("identity")
	var fill: Variant = identity.get("coat_fill") if identity != null else null
	var shade: Variant = identity.get("coat_shade") if identity != null else null
	material.set_shader_parameter("coat_color", fill if fill is Color else Color(0.8, 0.8, 0.8))
	material.set_shader_parameter("coat_shadow", shade if shade is Color else Color(0.68, 0.68, 0.68))
	material.set_shader_parameter("contour_amount", 0.0)
	if is_instance_valid(_teats_mesh):
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
		strip.set_shader_parameter("strip_trim", 1.0)
		strip.set_shader_parameter("strip_scale", SETTINGS.strip_scale.get_num())
		_skin_strip.set_surface_override_material(0, strip)


func apply_live() -> void:
	if not _attached:
		return
	if selected_mare_bits_path() != _mare_bits_path_loaded:
		_reload_mare_bits_mesh()
	_apply_material()
	_apply_place()
	_apply_anal_shape(_anal_local)
	_apply_body_coat()
	_apply_visibility()


## integration: swap the winking mesh in place when the model choice changes. The anchor,
## material override, placement and current shape values stay with the existing mesh node.
func _reload_mare_bits_mesh() -> void:
	if not is_instance_valid(_mesh):
		return
	var selected := selected_mare_bits_path()
	if selected == _mare_bits_path_loaded:
		return
	var scene: PackedScene = load(selected)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	var source: MeshInstance3D = instance as MeshInstance3D
	if source == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			source = child as MeshInstance3D
			break
	if source == null or source.mesh == null:
		instance.queue_free()
		return
	var refined := refined_winking_mesh(source.mesh as ArrayMesh)
	if refined == null:
		instance.queue_free()
		return
	_mesh.mesh = refined
	_mare_bits_path_loaded = selected
	_v2_anal = selected == MARE_BITS_V2_PATH
	_anal_local = 0.0
	_anal_mouth = V2_ANAL_RING_BASE
	_lip_radius = _measure_lip_radius()
	_apply_winking_shape()
	_apply_anal_shape(0.0)
	instance.queue_free()


func detach() -> void:
	_attached = false
	if is_instance_valid(pony) and pony.has_signal("physical_reaction") \
			and pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.disconnect(_on_physical_reaction)
	var body_mesh := _body_mesh
	var body_material := _body_material
	_restore_body_coat()
	if is_instance_valid(_zone_debug):
		_zone_debug.queue_free()
	_zone_debug = null
	if is_instance_valid(body_mesh) and is_instance_valid(body_material):
		body_mesh.set_surface_override_material(0, null)
	_hips_bind_ready = false
	_mare_bits_path_loaded = ""
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
	_v2_anal = false
	_anal_local = 0.0
	_anal_mouth = V2_ANAL_RING_BASE
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


## Idle heat drip: one leak per wink burst, scaled a little by the burst size. The fluid node is
## persistent, so the drops keep their motion and pool on the ground under her.
func idle_drip(count: int) -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree() or not is_instance_valid(_mesh):
		return
	var node := fluid()
	if not is_instance_valid(node):
		return
	node.set("ground_y", pony.global_position.y)
	node.call("drip", Callable(self, "hole_point").bind(0.0),
		1.5 + 0.7 * float(count), 1.0 + 0.2 * float(count),
		IDLE_FLUID_SIZE, IDLE_FLUID_COLOR)


func anal_mesh() -> MeshInstance3D:
	return _mesh if _v2_anal else null


func hole_local(mix: float) -> Vector3:
	var anal := _anal_mouth if _v2_anal else ANAL_OPENING
	var t := clampf(mix, 0.0, 1.0)
	var local := WINKING_OPENING.lerp(anal, t)
	if _v2_anal and is_instance_valid(_mesh):
		var scale := maxf(_mesh.global_transform.basis.get_scale().y, 0.0001)
		local += Vector3(0.0, SETTINGS.anal_aim_mm.get_num() / 1000.0 * t / scale, 0.0)
	return local


func hole_point(mix: float) -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.ZERO
	var point := _mesh.global_transform * WINKING_OPENING
	if not _v2_anal:
		return point
	var t := clampf(mix, 0.0, 1.0)
	var anal := _mesh.global_transform * _anal_mouth
	anal += _mesh.global_transform.basis.y.normalized() \
		* (SETTINGS.anal_aim_mm.get_num() / 1000.0)
	return point.lerp(anal, t)


func hole_rear(mix := 0.0) -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.BACK
	return _mesh.global_basis.z.normalized()


func set_closed(value: float) -> void:
	_closed = clampf(value, 0.0, 1.0)
	_apply_winking_shape()


## Idle heat crossfade: 0 is resting, 1 is the authored `wink` shape. Only the authored shape
## moves. The depth cut stays out of the idle rest: it pulls the pink interior toward the camera,
## and the clitoris sits in that mask, so a partial cut drags it out through the lips.
func set_idle_wink(amount: float) -> void:
	_wink_amount = clampf(amount, 0.0, 1.0)
	# The idle rest always sits on the fully closed shape, which also repairs a closed value the
	# act left behind; the authored `wink` shape carries the opening.
	_closed = 1.0
	_apply_winking_shape()


func drive(closed: float) -> void:
	_wink_amount = 0.0
	_rest = clampf(closed, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	set_closed(_rest)


func animate(target: float, seconds: float) -> void:
	if not is_instance_valid(_mesh):
		return
	_wink_amount = 0.0
	_rest = clampf(target, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	_apply_winking_shape()
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


## Idle heat wink. Each beat gets its own depth and timing, so a double or triple never reads as
## one repeated motion. The act's `wink()` stays tuned for its reaction and climax beats.
func wink_burst(count: int) -> void:
	if not is_instance_valid(_mesh):
		return
	if _tween != null:
		_tween.kill()
	# AFTERGLOW/RESTORE can still hold the act's grip. Clear it so the idle wink reads as a wink.
	if _fill > 0.0 or _wide > 0.0:
		_clear_part()
	var rest := clampf(HEAT_REST_OPEN, 0.0, 1.0)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := _wink_amount
	for i in count:
		var peak := randf_range(0.45, 0.88)
		# Accelerated expansion, a short hold, then an accelerated retraction.
		var opening := _tween.tween_method(set_idle_wink, from, peak, randf_range(0.18, 0.38))
		opening.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_interval(randf_range(0.08, 0.18))
		var closing := _tween.tween_method(set_idle_wink, peak, rest, randf_range(0.22, 0.45))
		closing.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if i < count - 1:
			_tween.tween_interval(randf_range(0.08, 0.18))
		from = rest


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
	# The hug pads the lip radius away from the shaft: positive leaves a gap, negative grips.
	var hug := SETTINGS.vulva_hug_mm.get_num() / 1000.0 if shaft_radius > 0.0 else 0.0
	var local := maxf(shaft_radius + hug, 0.0) / scale
	_hole_target = local
	# No blend shape at all: it scales the whole mesh. The shader opens the hole by translating
	# the rim band outward to the measured shaft radius.
	var shape := _mesh.find_blend_shape_by_name("stretch")
	if shape >= 0:
		_mesh.set_blend_shape_value(shape, 0.0)
	material.set_shader_parameter("hole_target", local)
	_apply_body_coat_uniforms()


## Publish Anon's shaft so the shader can project any vertex that ends up inside it back onto the
## surface. `radii` are world metres, sampled evenly from base to tip.
func set_shaft(pivot: Vector3, axis: Vector3, length: float, radii: PackedFloat32Array) -> void:
	_shaft_pivot = pivot
	_shaft_axis = axis
	_shaft_length = length
	_shaft_radii = radii
	_push_shaft(_mesh)


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
	return stable_lip_radius(_measure_ring_radius(_mesh, WINKING_OPENING, WINKING_LIP_RADIUS))


## The V2 mesh's inner folds/high-res patch can make the density walk pick the wrong
## inner bin. Keep the authored band unless the measurement lands near it.
static func stable_lip_radius(measured: float) -> float:
	if not is_finite(measured):
		return WINKING_LIP_RADIUS
	if measured < WINKING_LIP_RADIUS * 0.65 or measured > WINKING_LIP_RADIUS * 1.8:
		return WINKING_LIP_RADIUS
	return measured


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
	var wink_shape := _mesh.find_blend_shape_by_name("wink")
	if wink_shape >= 0:
		_mesh.set_blend_shape_value(wink_shape, _wink_amount)
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		# The depth cut is the act's shaft opening only. `closed` is what the act drives; the idle
		# wink shape must not pull the interior (and the clitoris) out through the resting lips.
		var open := smoothstep(0.0, 0.4, 1.0 - _closed)
		var filled := lerpf(1.0, WINKING_CUT_FILLED, smoothstep(0.5, 1.0, _fill))
		material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * open * filled
			* _mesh.global_transform.basis.get_scale().x)


## Drive the V2 anal blend shapes from the real shaft radius. Each key starts where the
## previous one ends, so the hole grows continuously into the overstretch and extreme scales.
func set_anal_grip(shaft_radius: float) -> void:
	if not is_instance_valid(_mesh) or not _v2_anal:
		return
	var scale := maxf(_mesh.global_transform.basis.get_scale().x, 0.0001)
	var hug := SETTINGS.anal_hug_mm.get_num() / 1000.0 if shaft_radius > 0.0 else 0.0
	_anal_local = maxf(shaft_radius + hug, 0.0) / scale
	_apply_anal_shape(_anal_local)


## Set the four anal keys and the independent ponut scale key. The extreme key already carries
## its own 2x scale, so the ponut scale is faded out as the extreme comes in.
func _apply_anal_shape(local: float) -> void:
	if not is_instance_valid(_mesh) or not _v2_anal:
		return
	var open := clampf(local / ANAL_OPEN_R, 0.0, 1.0)
	var stretch := clampf((local - ANAL_OPEN_R) / (ANAL_STRETCH_R - ANAL_OPEN_R), 0.0, 1.0)
	var over := clampf((local - ANAL_STRETCH_R) / (ANAL_OVER_R - ANAL_STRETCH_R), 0.0, 1.0)
	# No upper clamp: an oversized shaft extrapolates the extreme so the ring can still wrap it.
	var extreme := maxf(0.0, (local - ANAL_OVER_R) / (ANAL_EXTREME_R - ANAL_OVER_R))
	# The ponut key is a 2x scale, so the setting maps 0.5..1.5 to -0.5..0.5 weight.
	# Negative weights shrink the mound; the extreme key already carries its own 2x scale.
	var ponut := (SETTINGS.anal_scale.get_num() - 1.0) * maxf(0.0, 1.0 - extreme)
	_anal_mouth = V2_ANAL_RING_BASE \
		+ (V2_ANAL_RING_OPEN - V2_ANAL_RING_BASE) * open \
		+ (V2_ANAL_RING_STRETCH - V2_ANAL_RING_OPEN) * stretch \
		+ (V2_ANAL_RING_OVER - V2_ANAL_RING_STRETCH) * over \
		+ (V2_ANAL_RING_EXTREME - V2_ANAL_RING_OVER) * extreme \
		+ (V2_ANAL_RING_PONUT - V2_ANAL_RING_BASE) * ponut
	for pair: Array in [["anal_open", open], ["anal_stretch", stretch],
			["anal_overstretch", over], ["anal_extreme", extreme],
			["ponut_scale", ponut]]:
		var index := _mesh.find_blend_shape_by_name(str(pair[0]))
		if index >= 0:
			_mesh.set_blend_shape_value(index, float(pair[1]))


## Kept for the act's call order; the old cup's cut depth is gone and the shape keys do the work.
func set_anal_shape(_fill: float, _wide := 0.0) -> void:
	pass


func react() -> void:
	if is_instance_valid(_mesh):
		wink(2)


func _clear_part() -> void:
	set_fill(0.0)
	set_grip(0.0)
	set_anal_grip(0.0)
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
