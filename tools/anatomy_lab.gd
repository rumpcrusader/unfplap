extends Node3D
## Anatomy placement lab. Dev only; never ships.
##
## One standing mare at a time, built from her real game scene. The tail stays at the game's
## default mount; a lab-only modifier adds the tail offset. The dock is a rigid child of the first
## tail joint, so it follows every frame with no CPU follower.
##
## A/D cycles mares, Q/E orbits, W/S zooms, the mouse wheel zooms.
## 1/2/3 selects Anatomy/Tail/Dock; G/R/S selects Move/Rotate/Scale.
## Save writes the current mare's block to tools/anatomy_placement.json.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const TAIL_OFFSET := preload("res://mods/unfplap/tools/tail_lab_offset.gd")
const POPULATION := preload("res://world/population/pony_population_config.gd")
const DOCK_MESH := preload("res://world/characters/hybrid_mare/openpony_dock.res")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const DOCK_TAIL_MOUNT := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const REFERENCE_PATH := "res://world/characters/hybrid_mare/dock_tail_mounts.json"

const JSON_PATH := "res://mods/unfplap/tools/anatomy_placement.json"
const GROUPS := ["anatomy", "tail", "dock"]
const POSITION_STEP := 0.001
const ROTATION_STEP := 0.1
const SCALE_STEP := 0.01
const GIZMO_SIZE := 0.15
const AXIS_COLORS := [Color(0.95, 0.2, 0.2), Color(0.2, 0.9, 0.3), Color(0.25, 0.45, 1.0)]

var _data: Dictionary
var _ids: Array[String] = []
var _index := 0
var _values: Dictionary = {}
var _building := false

var _pony: Node3D
var _anatomy: Node
var _hair: Skeleton3D
var _tail_offset: SkeletonModifier3D
var _tail_pose: SkeletonModifier3D
var _dock_attach: BoneAttachment3D
var _dock_node: Node3D
var _dock: MeshInstance3D
var _tail_mesh: MeshInstance3D
var _tail_mesh_original: ArrayMesh
var _cap_hidden := false
var _link: Node
var _original_pelvis := Transform3D.IDENTITY
var _anchor := Vector3.INF
var _hips_rest := Transform3D.IDENTITY
var _reference_cache := Vector3.INF

var _camera: Camera3D
var _camera_target := Vector3.ZERO
var _yaw := 0.55
var _pitch := 0.08
var _distance := 1.6

var _group := "anatomy"
var _mode := "move"
var _gizmo: Node3D
var _axes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _center: MeshInstance3D
var _drag: Dictionary = {}
var _field_widgets: Dictionary = {}
var _looking := false
var _look_last := Vector2.ZERO

var _mare_label: Label
var _status: Label
var _fields: VBoxContainer
var _aside: CheckButton
var _reference_seat: CheckButton
var _hide_cap: CheckButton


func _ready() -> void:
	SETTINGS.data()
	SETTINGS._cache["anatomy"]["anatomy_mode"] = "always"
	SETTINGS._cache["anatomy"]["show_dock"] = true
	SETTINGS._cache["anatomy"]["anatomy_fluid"] = false
	SETTINGS.generation += 1
	SETTINGS.placement_revision += 1

	var catalogue: Dictionary = POPULATION.catalogue()
	for id: String in SETTINGS.CHARACTER_ORDER:
		if catalogue.has(id):
			_ids.append(id)
	_load_data()
	_build_world()
	_build_ui()
	_build_gizmo()
	_build_mare()


func _load_data() -> void:
	_data = _fallback_data()
	if FileAccess.file_exists(JSON_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
		if parsed is Dictionary:
			_data = _sanitize_data(parsed)
	else:
		_write_data()
	var mares: Variant = _data.get("mares")
	if not mares is Dictionary:
		_data["mares"] = {}


func _fallback_data() -> Dictionary:
	return {
		"version": 1,
		"default": {
			"anatomy": {
				"position": [0.0, 0.505, 0.289],
				"rotation": [3.0, 0.0, 0.0],
				"scale": 0.682,
			},
			"tail": {
				"position": [0.0, 0.0, 0.0],
				"rotation": [0.0, 0.0, 0.0],
			},
			"dock": {
				"scale": 1.5,
				"position": [0.0, 0.0, 0.0],
				"rotation": [0.0, 0.0, 0.0],
			},
		},
		"mares": {},
	}


func _sanitize_data(source: Dictionary) -> Dictionary:
	var out := _fallback_data()
	var defaults: Dictionary = _fallback_data()["default"]
	var source_default: Variant = source.get("default")
	if source_default is Dictionary:
		for group: String in GROUPS:
			var block: Variant = (source_default as Dictionary).get(group)
			if block is Dictionary:
				out["default"][group] = _sanitize_group(group, block, defaults[group])
	var source_mares: Variant = source.get("mares")
	if source_mares is Dictionary:
		var mares: Dictionary = {}
		for id: Variant in (source_mares as Dictionary).keys():
			var raw: Variant = (source_mares as Dictionary)[id]
			if not raw is Dictionary:
				continue
			var block: Dictionary = {}
			for group: String in GROUPS:
				var part: Variant = (raw as Dictionary).get(group)
				if part is Dictionary:
					block[group] = _sanitize_group(group, part, defaults[group])
			if not block.is_empty():
				mares[str(id)] = block
		out["mares"] = mares
	return out


func _sanitize_group(group: String, source: Dictionary, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = fallback.duplicate(true)
	if group == "anatomy":
		out["position"] = _floats(source.get("position"), fallback["position"], 3)
		out["rotation"] = _floats(source.get("rotation"), fallback["rotation"], 3)
		out["scale"] = _float(source.get("scale"), float(fallback["scale"]))
	else:
		out["position"] = _floats(source.get("position"), fallback["position"], 3)
		out["rotation"] = _floats(source.get("rotation"), fallback["rotation"], 3)
	if group == "dock":
		out["scale"] = _float(source.get("scale"), float(fallback["scale"]))
	return out


func _floats(value: Variant, fallback: Variant, count: int) -> Array:
	var out: Array = []
	for i in count:
		var fallback_value: float = float((fallback as Array)[i]) if fallback is Array \
			and (fallback as Array).size() > i else 0.0
		out.append(_float((value as Array)[i] if value is Array and (value as Array).size() > i \
			else null, fallback_value))
	return out


func _float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return number
	return fallback


func _merged(id: String) -> Dictionary:
	var out: Dictionary = _data["default"].duplicate(true)
	var overrides: Variant = _data.get("mares")
	if overrides is Dictionary and (overrides as Dictionary).has(id):
		var block: Variant = (overrides as Dictionary)[id]
		if block is Dictionary:
			for group: String in GROUPS:
				var part: Variant = (block as Dictionary).get(group)
				if part is Dictionary:
					out[group] = _sanitize_group(group, part, out[group])
	return out


func _block_equals_default(block: Dictionary) -> bool:
	return JSON.stringify(block) == JSON.stringify(_data["default"])


func _write_data() -> void:
	var file := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("Cannot write %s" % JSON_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t") + "\n")
	file.close()


func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 28, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.09, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.85)
	environment.ambient_light_energy = 0.9
	world.environment = environment
	add_child(world)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	shape.shape = box
	shape.position.y = -0.1
	floor.add_child(shape)
	add_child(floor)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LabUI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -380.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = -16.0
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(348.0, 0.0)
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(330.0, 0.0)
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	var mare_row := HBoxContainer.new()
	column.add_child(mare_row)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func() -> void: _cycle(-1))
	mare_row.add_child(prev)
	_mare_label = Label.new()
	_mare_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mare_row.add_child(_mare_label)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func() -> void: _cycle(1))
	mare_row.add_child(next)

	var groups := HBoxContainer.new()
	column.add_child(groups)
	var group_buttons := ButtonGroup.new()
	for pair: Array in [["anatomy", "Anatomy"], ["tail", "Tail"], ["dock", "Dock"]]:
		var button := Button.new()
		button.text = str(pair[1])
		button.toggle_mode = true
		button.button_group = group_buttons
		button.button_pressed = _group == str(pair[0])
		button.pressed.connect(func() -> void: _set_group(str(pair[0])))
		groups.add_child(button)

	var modes := HBoxContainer.new()
	column.add_child(modes)
	var mode_buttons := ButtonGroup.new()
	for pair: Array in [["move", "Move"], ["rotate", "Rotate"], ["scale", "Scale"]]:
		var button := Button.new()
		button.text = str(pair[1])
		button.toggle_mode = true
		button.button_group = mode_buttons
		button.button_pressed = _mode == str(pair[0])
		button.pressed.connect(func() -> void: _set_mode(str(pair[0])))
		modes.add_child(button)

	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 4)
	column.add_child(_fields)

	_aside = CheckButton.new()
	_aside.text = "Tail aside"
	_aside.toggled.connect(_set_tail_aside)
	column.add_child(_aside)
	_reference_seat = CheckButton.new()
	_reference_seat.text = "Reference seat"
	_reference_seat.button_pressed = true
	_reference_seat.toggled.connect(func(_on: bool) -> void: _apply_seat())
	column.add_child(_reference_seat)
	_hide_cap = CheckButton.new()
	_hide_cap.text = "Hide root cap"
	_hide_cap.toggled.connect(_set_hide_cap)
	column.add_child(_hide_cap)
	var hint := Label.new()
	hint.text = "RMB look"
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.8))
	column.add_child(hint)

	var file_row := HBoxContainer.new()
	column.add_child(file_row)
	for pair: Array in [["Save", _save_current], ["Reset", _reset_current],
			["Reload", _reload_data]]:
		var button := Button.new()
		button.text = str(pair[0])
		button.pressed.connect(pair[1])
		file_row.add_child(button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320.0, 48.0)
	column.add_child(_status)
	_rebuild_fields()


func _set_group(group: String) -> void:
	_drag = {}
	_group = group
	_rebuild_fields()
	_update_gizmo()


func _set_mode(mode: String) -> void:
	_drag = {}
	_mode = mode
	_rebuild_fields()
	_update_gizmo()


func _rebuild_fields() -> void:
	if not is_instance_valid(_fields):
		return
	for child: Node in _fields.get_children():
		child.queue_free()
	_field_widgets.clear()
	var group_values: Dictionary = _values.get(_group, {})
	var label := Label.new()
	label.text = "%s  (%s)" % [_group.capitalize(), _mode]
	_fields.add_child(label)
	if _group == "dock":
		var scale_label := Label.new()
		scale_label.text = "Scale %.2fx (JSON)" % float(group_values.get("scale", 1.5))
		_fields.add_child(scale_label)
	for key: String in ["position", "rotation"]:
		var values: Variant = group_values.get(key)
		if not values is Array:
			continue
		for i in 3:
			var row := HBoxContainer.new()
			_fields.add_child(row)
			var field := Label.new()
			field.text = "%s %s" % [key.capitalize(), ["X", "Y", "Z"][i]]
			field.custom_minimum_size = Vector2(92.0, 0.0)
			row.add_child(field)
			var spin := SpinBox.new()
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.min_value = -2.0 if key == "position" else -180.0
			spin.max_value = 2.0 if key == "position" else 180.0
			spin.step = POSITION_STEP if key == "position" else ROTATION_STEP
			spin.value = float(values[i])
			spin.value_changed.connect(_on_field_changed.bind(_group, key, i))
			row.add_child(spin)
			_field_widgets["%s/%s/%d" % [_group, key, i]] = spin
	if _group == "anatomy":
		var row := HBoxContainer.new()
		_fields.add_child(row)
		var field := Label.new()
		field.text = "Scale"
		field.custom_minimum_size = Vector2(92.0, 0.0)
		row.add_child(field)
		var spin := SpinBox.new()
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.min_value = 0.05
		spin.max_value = 4.0
		spin.step = SCALE_STEP
		spin.value = float(group_values.get("scale", 0.682))
		spin.value_changed.connect(_on_field_changed.bind(_group, "scale", 0))
		row.add_child(spin)
		_field_widgets["anatomy/scale/0"] = spin


func _on_field_changed(value: float, group: String, key: String, index: int) -> void:
	if not _values.has(group):
		return
	if key == "scale":
		_values[group]["scale"] = clampf(value, 0.05, 4.0)
	else:
		var array: Array = _values[group].get(key, [0.0, 0.0, 0.0])
		array[index] = value
		_values[group][key] = array
	_apply_current()


func _sync_fields() -> void:
	for path: Variant in _field_widgets.keys():
		var spin: SpinBox = _field_widgets[path]
		var parts := str(path).split("/")
		var group := parts[0]
		var key := parts[1]
		var index := int(parts[2])
		if key == "scale":
			spin.set_value_no_signal(float(_values.get(group, {}).get("scale", 1.0)))
		else:
			var array: Variant = _values.get(group, {}).get(key)
			if array is Array:
				spin.set_value_no_signal(float((array as Array)[index]))


func _build_mare() -> void:
	if _building or _ids.is_empty():
		return
	_building = true
	_clear_mare()
	var id := _ids[_index]
	var path := str(POPULATION.catalogue().get(id, ""))
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		_set_status("No scene for %s" % id)
		_building = false
		return
	_pony = scene.instantiate() as Node3D
	_pony.name = "LabMare_%s" % id
	add_child(_pony)
	if _pony.has_method("set_body_scale"):
		_pony.set_body_scale(1.0)
	await get_tree().process_frame
	_hair = _pony.get("hair_skeleton") as Skeleton3D
	_setup_anatomy()
	_setup_tail()
	_apply_seat()
	_setup_dock()
	_values = _merged(id)
	_apply_current()
	_rebuild_fields()
	_sync_fields()
	_update_camera_target()
	_mare_label.text = "%d/%d  %s" % [_index + 1, _ids.size(),
		str(SETTINGS.CHARACTER_NAMES.get(id, id))]
	_set_status("Loaded %s" % id)
	_building = false


func _clear_mare() -> void:
	if is_instance_valid(_pony):
		_pony.queue_free()
	_pony = null
	_anatomy = null
	_hair = null
	_tail_offset = null
	_tail_pose = null
	_dock_attach = null
	_dock_node = null
	_dock = null
	_tail_mesh = null
	_tail_mesh_original = null
	_cap_hidden = false
	_link = null
	_anchor = Vector3.INF
	if is_instance_valid(_gizmo):
		_gizmo.visible = false
	if is_instance_valid(_aside):
		_aside.set_pressed_no_signal(false)


func _setup_anatomy() -> void:
	if not is_instance_valid(_pony):
		return
	_anatomy = ANATOMY.new()
	_anatomy.name = "LabAnatomy"
	_pony.add_child(_anatomy)
	_anatomy.call("setup", _pony, null)
	_anatomy.call("refresh")
	_anatomy.set_process(false)


func _setup_tail() -> void:
	if not is_instance_valid(_hair):
		return
	_tail_offset = TAIL_OFFSET.new()
	_tail_offset.name = "LabTailOffset"
	_tail_offset.process_priority = 100
	_hair.add_child(_tail_offset)
	var identity: Variant = _pony.get("identity")
	var hair_node: Variant = _pony.get("hair")
	if is_instance_valid(hair_node) and identity != null:
		_tail_mesh = (hair_node as Node).find_child(
			str(identity.get("hair_prefix")) + "DevkitTail", true, false) as MeshInstance3D
		if is_instance_valid(_tail_mesh):
			_tail_mesh_original = _tail_mesh.mesh as ArrayMesh
	_link = _pony.get("hair_link") as Node
	if is_instance_valid(_link) and _link.get("pelvis_offset") is Transform3D:
		_original_pelvis = _link.get("pelvis_offset") as Transform3D
	else:
		_link = null
	var skeleton: Skeleton3D = _pony.get("skeleton") as Skeleton3D
	if is_instance_valid(skeleton):
		var hips := skeleton.find_bone("pony_hips")
		if hips >= 0:
			_hips_rest = skeleton.get_bone_global_rest(hips)
	var measured: Dictionary = DOCK_TAIL_MOUNT.measure(_pony) if is_instance_valid(_pony) else {}
	var raw: Variant = measured.get("anchor")
	if raw is Array and (raw as Array).size() == 3:
		_anchor = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	else:
		_anchor = Vector3.INF
	if is_instance_valid(_hide_cap) and _hide_cap.button_pressed:
		_set_hide_cap(true)


func _reference_anchor() -> Vector3:
	if _reference_cache.is_finite():
		return _reference_cache
	if FileAccess.file_exists(REFERENCE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_PATH))
		if parsed is Dictionary:
			var value: Variant = (parsed as Dictionary).get("reference")
			if value is Array and (value as Array).size() == 3:
				_reference_cache = Vector3(float((value as Array)[0]),
					float((value as Array)[1]), float((value as Array)[2]))
	return _reference_cache


## Remove every near-tail face that touches a vertex weighted to the hair pelvis: the fully pinned
## cap and the blended root collar. The free strands remain; the body/dock covers the opening.
func _set_hide_cap(on: bool) -> void:
	if not is_instance_valid(_tail_mesh):
		return
	if on:
		if _cap_hidden:
			return
		if _tail_mesh_original == null:
			_tail_mesh_original = _tail_mesh.mesh as ArrayMesh
		var capped := _cap_less_mesh(_tail_mesh_original)
		if capped != null:
			_tail_mesh.mesh = capped
			_cap_hidden = true
	elif _cap_hidden:
		if _tail_mesh_original != null:
			_tail_mesh.mesh = _tail_mesh_original
		_cap_hidden = false


func _cap_less_mesh(source: ArrayMesh) -> ArrayMesh:
	if source == null:
		return null
	var mount := -1
	if is_instance_valid(_tail_mesh) and _tail_mesh.skin != null:
		for i in _tail_mesh.skin.get_bind_count():
			if _tail_mesh.skin.get_bind_name(i) == "mPelvis":
				mount = i
				break
	var out := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface).duplicate(true)
		var pinned: PackedInt32Array = source.get_meta("pinned_" + str(surface),
			PackedInt32Array())
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var stride := bones.size() / maxi(vertices.size(), 1)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		if index is PackedInt32Array:
			var list: PackedInt32Array = index
			var keep := PackedInt32Array()
			for at in range(0, list.size(), 3):
				var rooted := false
				for k in 3:
					var v := list[at + k]
					if mount >= 0:
						for i in stride:
							if bones[v * stride + i] == mount \
									and weights[v * stride + i] > 0.0001:
								rooted = true
								break
					elif pinned.has(v):
						rooted = true
					if rooted:
						break
				if rooted:
					continue
				keep.append(list[at])
				keep.append(list[at + 1])
				keep.append(list[at + 2])
			arrays[Mesh.ARRAY_INDEX] = keep
		var format := source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays,
			[], {}, format)
		out.surface_set_material(surface, source.surface_get_material(surface))
		out.surface_set_name(surface, source.surface_get_name(surface))
	for key: Variant in source.get_meta_list():
		out.set_meta(key, source.get_meta(key))
	return out


## Move the tail base to the game reference anchor (runtime seat) or restore the identity mount.
func _apply_seat() -> void:
	if not is_instance_valid(_link):
		return
	if is_instance_valid(_reference_seat) and _reference_seat.button_pressed:
		var reference := _reference_anchor()
		if reference.is_finite() and _anchor.is_finite():
			var next := _original_pelvis
			next.origin += _hips_rest.basis.inverse() * (reference - _anchor)
			_link.set("pelvis_offset", next)
	else:
		_link.set("pelvis_offset", _original_pelvis)
	if _link.has_method("_body_updated"):
		_link.call("_body_updated")
	_update_camera_target()


func _setup_dock() -> void:
	if not is_instance_valid(_hair):
		return
	var pivot: Vector3 = HYBRID_DOCK.pivot()
	_dock_attach = BoneAttachment3D.new()
	_dock_attach.name = "LabDockAttach"
	_dock_attach.bone_name = "mTail1"
	_hair.add_child(_dock_attach)
	_dock_node = Node3D.new()
	_dock_node.name = "LabDock"
	_dock_attach.add_child(_dock_node)
	_dock = MeshInstance3D.new()
	_dock.name = "LabDockMesh"
	_dock.mesh = DOCK_MESH
	_dock.skin = null
	_dock.position = -pivot
	_dock_node.add_child(_dock)
	_dock.set_surface_override_material(0, _dock_debug_material())


func _dock_debug_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.1, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	return material


func _apply_current() -> void:
	if _values.is_empty():
		return
	_apply_anatomy()
	_apply_tail()
	_apply_dock()
	_update_gizmo()


func _apply_anatomy() -> void:
	if not is_instance_valid(_anatomy):
		return
	var mesh: MeshInstance3D = _anatomy.call("winking_mesh") as MeshInstance3D
	if not is_instance_valid(mesh):
		return
	var values: Dictionary = _values["anatomy"]
	var position := _vec(values["position"])
	var rotation := _vec(values["rotation"])
	_anatomy.set("_pos", position)
	_anatomy.set("_pitch", rotation.x)
	_anatomy.set("_scale", maxf(0.05, float(values["scale"])))
	_anatomy.call("_apply_place")
	var extra := Basis.from_euler(Vector3(0.0, deg_to_rad(rotation.y), deg_to_rad(rotation.z)))
	mesh.transform = mesh.transform * Transform3D(extra, Vector3.ZERO)


func _apply_tail() -> void:
	if not is_instance_valid(_tail_offset):
		return
	var values: Dictionary = _values["tail"]
	_tail_offset.set("offset", _vec(values["position"]))
	var rotation := _vec(values["rotation"])
	_tail_offset.set("euler", Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y),
		deg_to_rad(rotation.z)))


func _apply_dock() -> void:
	if not is_instance_valid(_dock_node):
		return
	var values: Dictionary = _values["dock"]
	var rotation := _vec(values["rotation"])
	var basis := Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y),
		deg_to_rad(rotation.z))).scaled(Vector3.ONE * maxf(0.05, float(values["scale"])))
	_dock_node.transform = Transform3D(basis, _vec(values["position"]))


func _vec(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float((value as Array)[0]), float((value as Array)[1]),
			float((value as Array)[2]))
	return Vector3.ZERO


func _set_tail_aside(on: bool) -> void:
	if on:
		if is_instance_valid(_tail_pose) or not is_instance_valid(_hair):
			return
		_tail_pose = TAIL.new()
		_tail_pose.name = "LabTailAside"
		_tail_pose.set("mare", _pony)
		_tail_pose.set("amount", 1.0)
		_tail_pose.set("target_amount", 1.0)
		_tail_pose.set("aside_angle", 0.95)
		_tail_pose.set("lift_angle", 0.75)
		_tail_pose.set("aside_sign", 1.0)
		_hair.add_child(_tail_pose)
	elif is_instance_valid(_tail_pose):
		_tail_pose.queue_free()
		_tail_pose = null


func _cycle(delta: int) -> void:
	if _building or _ids.is_empty():
		return
	_index = wrapi(_index + delta, 0, _ids.size())
	_build_mare()


func _update_camera_target() -> void:
	if not is_instance_valid(_hair):
		return
	var pelvis := _hair.find_bone("mPelvis")
	if pelvis < 0:
		return
	_camera_target = (_hair.global_transform * _hair.get_bone_global_pose(pelvis)).origin


func _process(delta: float) -> void:
	if _looking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_looking = false
	if Input.is_key_pressed(KEY_Q):
		_yaw += delta * 1.6
	if Input.is_key_pressed(KEY_E):
		_yaw -= delta * 1.6
	if Input.is_key_pressed(KEY_W):
		_distance = maxf(_distance - delta * 1.5, 0.5)
	if Input.is_key_pressed(KEY_S):
		_distance = minf(_distance + delta * 1.5, 6.0)
	_update_camera()
	_update_gizmo()


func _update_camera() -> void:
	if not is_instance_valid(_camera):
		return
	if is_instance_valid(_hair):
		_update_camera_target()
	var offset := Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, _distance)
	_camera.global_position = _camera_target + offset
	_camera.look_at(_camera_target)


func _build_gizmo() -> void:
	_gizmo = Node3D.new()
	_gizmo.name = "LabGizmo"
	add_child(_gizmo)
	_gizmo.visible = false
	for i in 3:
		var axis := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 0.5
		cylinder.top_radius = 0.008
		cylinder.bottom_radius = 0.008
		cylinder.radial_segments = 6
		axis.mesh = cylinder
		axis.material_override = _gizmo_material(AXIS_COLORS[i])
		axis.position = _axis(i) * 0.25
		axis.rotation = _axis_rotation(i)
		_gizmo.add_child(axis)
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.height = 0.09
		cone.top_radius = 0.0
		cone.bottom_radius = 0.025
		cone.radial_segments = 8
		tip.mesh = cone
		tip.material_override = _gizmo_material(AXIS_COLORS[i])
		tip.position = _axis(i) * 0.545
		tip.rotation = _axis_rotation(i)
		_gizmo.add_child(tip)
		_axes.append(axis)
		_axes.append(tip)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.43
		torus.outer_radius = 0.45
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = _gizmo_material(AXIS_COLORS[i])
		ring.rotation = _axis_rotation(i)
		_gizmo.add_child(ring)
		_rings.append(ring)
	_center = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	_center.mesh = sphere
	_center.material_override = _gizmo_material(Color(0.95, 0.9, 0.2))
	_gizmo.add_child(_center)


func _gizmo_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material


func _axis(i: int) -> Vector3:
	match i:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK


func _axis_rotation(i: int) -> Vector3:
	match i:
		0:
			return Vector3(0.0, 0.0, -PI * 0.5)
		1:
			return Vector3.ZERO
		_:
			return Vector3(PI * 0.5, 0.0, 0.0)


func _gizmo_frame() -> Dictionary:
	if not is_instance_valid(_pony):
		return {}
	var basis := Basis.IDENTITY
	var origin := Vector3.ZERO
	match _group:
		"anatomy":
			var mesh: MeshInstance3D = _anatomy.call("winking_mesh") as MeshInstance3D \
				if is_instance_valid(_anatomy) else null
			if not is_instance_valid(mesh):
				return {}
			var anchor := mesh.get_parent() as Node3D
			var bone_inverse: Variant = _anatomy.get("_bone_inverse")
			if not is_instance_valid(anchor) or not bone_inverse is Transform3D:
				return {}
			var frame: Transform3D = anchor.global_transform * (bone_inverse as Transform3D)
			basis = frame.basis.orthonormalized()
			origin = mesh.global_transform.origin
		"tail":
			if not is_instance_valid(_hair):
				return {}
			var pelvis := _hair.find_bone("mPelvis")
			if pelvis < 0:
				return {}
			var base := _hair.get_bone_global_pose(pelvis).origin
			origin = _hair.global_transform * (base + _vec(_values["tail"]["position"]))
			basis = _hair.global_transform.basis.orthonormalized()
		"dock":
			if not is_instance_valid(_dock_attach) or not is_instance_valid(_dock_node):
				return {}
			origin = _dock_node.global_transform.origin
			basis = _dock_attach.global_transform.basis.orthonormalized()
	return {"origin": origin, "basis": basis}


func _update_gizmo() -> void:
	if not is_instance_valid(_gizmo):
		return
	var frame := _gizmo_frame()
	if frame.is_empty():
		_gizmo.visible = false
		return
	_gizmo.visible = true
	var origin: Vector3 = frame["origin"]
	var basis: Basis = frame["basis"]
	_gizmo.global_transform = Transform3D(basis, origin)
	var size := maxf(_camera.global_position.distance_to(origin) * GIZMO_SIZE, 0.05)
	_gizmo.scale = Vector3.ONE * size
	for axis in _axes:
		axis.visible = _mode == "move"
	for ring in _rings:
		ring.visible = _mode == "rotate"
	_center.visible = _mode == "scale" and _group == "anatomy"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_A:
			_cycle(-1)
		KEY_D:
			_cycle(1)
		KEY_1:
			_set_group("anatomy")
		KEY_2:
			_set_group("tail")
		KEY_3:
			_set_group("dock")
		KEY_G:
			_set_mode("move")
		KEY_R:
			_set_mode("rotate")
		KEY_T:
			_set_mode("scale")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = maxf(_distance - 0.1, 0.5)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = minf(_distance + 0.1, 6.0)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_looking = button.pressed
			_look_last = button.position
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_start_drag(button.position)
			else:
				_drag = {}
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _looking:
			var delta := motion.position - _look_last
			_look_last = motion.position
			_yaw -= delta.x * 0.005
			_pitch = clampf(_pitch - delta.y * 0.005, -1.2, 1.2)
			get_viewport().set_input_as_handled()
		elif not _drag.is_empty():
			_drag_motion(motion.position)
			get_viewport().set_input_as_handled()


func _start_drag(mouse: Vector2) -> void:
	var pick := _pick_handle(mouse)
	if pick.is_empty():
		return
	var frame := _gizmo_frame()
	if frame.is_empty():
		return
	var origin: Vector3 = frame["origin"]
	var basis: Basis = frame["basis"]
	_drag = {
		"kind": pick["kind"],
		"axis": int(pick.get("axis", 0)),
		"origin": origin,
		"basis": basis,
		"start": _values[_group].duplicate(true),
		"mouse": mouse,
	}
	if pick["kind"] == "move":
		var direction := basis * _axis(int(pick["axis"]))
		_drag["hit"] = _axis_hit(origin, direction, mouse)
	elif pick["kind"] == "rotate":
		var normal := basis * _axis(int(pick["axis"]))
		_drag["angle"] = _ring_angle(origin, normal, mouse)
	get_viewport().set_input_as_handled()


func _drag_motion(mouse: Vector2) -> void:
	var kind := str(_drag.get("kind", ""))
	var axis := int(_drag.get("axis", 0))
	var origin: Vector3 = _drag["origin"]
	var basis: Basis = _drag["basis"]
	var start: Dictionary = _drag["start"]
	if kind == "move":
		var direction := basis * _axis(axis)
		var hit := _axis_hit(origin, direction, mouse)
		var delta := (hit - (_drag["hit"] as Vector3)).dot(direction)
		var array: Array = (start["position"] as Array).duplicate()
		array[axis] = float(array[axis]) + delta
		_values[_group]["position"] = array
	elif kind == "rotate":
		var normal := basis * _axis(axis)
		var angle := _ring_angle(origin, normal, mouse)
		var delta := rad_to_deg(angle - float(_drag["angle"]))
		var array: Array = (start["rotation"] as Array).duplicate()
		array[axis] = wrapf(float(array[axis]) + delta, -180.0, 180.0)
		_values[_group]["rotation"] = array
	elif kind == "scale":
		var factor := exp((float(_drag["mouse"].y) - mouse.y) * 0.01)
		_values[_group]["scale"] = clampf(float(start["scale"]) * factor, 0.05, 4.0)
	_apply_current()
	_sync_fields()


func _pick_handle(mouse: Vector2) -> Dictionary:
	if not is_instance_valid(_gizmo) or not _gizmo.visible:
		return {}
	var frame := _gizmo_frame()
	if frame.is_empty():
		return {}
	var origin: Vector3 = frame["origin"]
	var basis: Basis = frame["basis"]
	var size := _gizmo.scale.x
	if _mode == "scale" and _group == "anatomy":
		if _camera.unproject_position(origin).distance_to(mouse) < 16.0:
			return {"kind": "scale"}
	elif _mode == "move":
		var best := 999.0
		var best_axis := -1
		for i in 3:
			var direction := basis * _axis(i)
			var a := _camera.unproject_position(origin)
			var b := _camera.unproject_position(origin + direction * (0.55 * size))
			var distance := _segment_distance(mouse, a, b)
			if distance < best and distance < 14.0:
				best = distance
				best_axis = i
		if best_axis >= 0:
			return {"kind": "move", "axis": best_axis}
	elif _mode == "rotate":
		var best := 999.0
		var best_axis := -1
		for i in 3:
			var normal := basis * _axis(i)
			var radius := 0.44 * size
			var previous := Vector2.ZERO
			for step in 33:
				var angle := TAU * float(step) / 32.0
				var point := origin + _ring_point(basis, i, radius, angle)
				var screen := _camera.unproject_position(point)
				if step > 0:
					var distance := _segment_distance(mouse, previous, screen)
					if distance < best and distance < 9.0:
						best = distance
						best_axis = i
				previous = screen
		if best_axis >= 0:
			return {"kind": "rotate", "axis": best_axis}
	return {}


func _ring_point(basis: Basis, axis: int, radius: float, angle: float) -> Vector3:
	var a := cos(angle)
	var b := sin(angle)
	match axis:
		0:
			return basis * ((Vector3.UP * a + Vector3.BACK * b) * radius)
		1:
			return basis * ((Vector3.RIGHT * a + Vector3.BACK * b) * radius)
		_:
			return basis * ((Vector3.RIGHT * a + Vector3.UP * b) * radius)


func _axis_hit(origin: Vector3, direction: Vector3, mouse: Vector2) -> Vector3:
	var ray_origin := _camera.project_ray_origin(mouse)
	var ray_direction := _camera.project_ray_normal(mouse)
	var w0 := origin - ray_origin
	var a := direction.dot(direction)
	var b := direction.dot(ray_direction)
	var c := ray_direction.dot(ray_direction)
	var d := direction.dot(w0)
	var e := ray_direction.dot(w0)
	var denominator := a * c - b * b
	if absf(denominator) < 0.000001:
		return origin
	var t := (b * e - c * d) / denominator
	return origin + direction * t


func _ring_angle(origin: Vector3, normal: Vector3, mouse: Vector2) -> float:
	var ray_origin := _camera.project_ray_origin(mouse)
	var ray_direction := _camera.project_ray_normal(mouse)
	var denominator := normal.dot(ray_direction)
	if absf(denominator) < 0.000001:
		return 0.0
	var t := normal.dot(origin - ray_origin) / denominator
	var point := ray_origin + ray_direction * t
	var u := normal.cross(Vector3.UP)
	if u.length_squared() < 0.0001:
		u = normal.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := normal.cross(u).normalized()
	var d := point - origin
	return atan2(d.dot(v), d.dot(u))


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _save_current() -> void:
	if _values.is_empty():
		return
	var id := _ids[_index]
	if _block_equals_default(_values):
		(_data["mares"] as Dictionary).erase(id)
	else:
		(_data["mares"] as Dictionary)[id] = _values.duplicate(true)
	_write_data()
	_set_status("Saved %s" % id)


func _reset_current() -> void:
	_values = _data["default"].duplicate(true)
	_sync_fields()
	_apply_current()
	_set_status("Reset to default (not saved)")


func _reload_data() -> void:
	_load_data()
	if not _ids.is_empty():
		_values = _merged(_ids[_index])
		_rebuild_fields()
		_sync_fields()
		_apply_current()
	_set_status("Reloaded %s" % JSON_PATH)


func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text
