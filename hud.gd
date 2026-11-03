extends CanvasLayer
## Desktop HUD: prompt and a bottom-left controls/cue list.

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const READINESS_BAR := preload("res://mods/unfplap/readiness_bar.gd")
const ICON_PATH := "res://world/ui/prompts/%s.png"
const KEYCAP_SIZE := Vector2(30.0, 26.0)

var _prompt: Label
var _hint: VBoxContainer
var _hint_status: Label
var _hint_readiness: Label
var _hint_gap: Control
var _readiness_bar: Control
var _y_label: Label
var _hint_icons := {}
var _control_rows := {}


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "UnfplapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -120.0
	_prompt.offset_top = -150.0
	_prompt.offset_right = 120.0
	_prompt.offset_bottom = -120.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.86, 0.94))
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.visible = false
	root.add_child(_prompt)

	_hint = VBoxContainer.new()
	_hint.name = "Hint"
	_hint.anchor_left = 0.0
	_hint.anchor_top = 1.0
	_hint.anchor_right = 0.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 28.0
	_hint.offset_top = -430.0
	_hint.offset_right = 620.0
	_hint.offset_bottom = -26.0
	_hint.add_theme_constant_override("separation", 2)
	_hint.alignment = BoxContainer.ALIGNMENT_END
	_hint.visible = false
	root.add_child(_hint)
	_hint_status = _make_label("")
	_hint_status.name = "HintStatus"
	_hint_status.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_status.add_theme_font_size_override("font_size", 16)
	_hint_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_status.visible = false
	_hint.add_child(_hint_status)
	_hint_readiness = _make_label("")
	_hint_readiness.name = "HintReadiness"
	_hint_readiness.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_readiness.add_theme_font_size_override("font_size", 14)
	_hint_readiness.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_readiness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_readiness.visible = false
	_hint.add_child(_hint_readiness)
	_hint_gap = Control.new()
	_hint_gap.custom_minimum_size.y = 10.0
	_hint_gap.visible = false
	_hint.add_child(_hint_gap)
	_readiness_bar = READINESS_BAR.new()
	_readiness_bar.name = "Readiness"
	_readiness_bar.visible = false
	_hint.add_child(_readiness_bar)
	_build_controls()
	# Cue line, readiness text, bar, then the separator, then the controls.
	_hint.move_child(_hint_status, 0)
	_hint.move_child(_hint_readiness, 1)
	_hint.move_child(_readiness_bar, 2)
	_hint.move_child(_hint_gap, 3)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## One row per control: a keycap/controller icon and one description. Built once; only the
## Y row and the status line change with act state.
func _build_controls() -> void:
	_add_hint_row("thrust", "", "↕", "Thrust (mouse)")
	_add_hint_row("forward", "", "W", "Lean forward")
	_add_hint_row("back", "", "S", "Lean back")
	_add_hint_row("left", "key_q", "Q", "Lean left · kiss / reach")
	_add_hint_row("right", "key_e", "E", "Lean right · reach")
	_add_hint_row("caress_left", "", "A", "Caress left")
	_add_hint_row("caress_right", "", "D", "Caress right")
	_add_hint_row("kiss", "key_f", "F", "Hold to kiss at full lean")
	_add_hint_row("smack", "mouse_right", "", "Smack flank")
	_add_hint_row("talk", "", "T", "Answer her when asked")
	_y_label = _add_hint_row("y", "button_y", "Y", "")


func _add_hint_row(key: String, icon_name: String, key_text: String, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := _hint_icon(icon_name)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = KEYCAP_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		row.add_child(_keycap(key_text))
	var label := _make_label(text)
	label.add_theme_font_size_override("font_size", 16)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_hint.add_child(row)
	_control_rows[key] = row
	return label


func _keycap(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = KEYCAP_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	style.border_color = Color(1.0, 1.0, 1.0, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	panel.add_theme_stylebox_override("panel", style)
	var label := _make_label(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


func _hint_icon(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if _hint_icons.has(name):
		return _hint_icons[name] as Texture2D
	var path := ICON_PATH % name
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_hint_icons[name] = texture
	return texture


func show_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false


func show_act(runtime: Node, show_readouts := true) -> void:
	_hint.visible = true
	update_from(runtime, show_readouts)


func hide_act() -> void:
	if _hint != null:
		_hint.visible = false
	if _hint_status != null:
		_hint_status.visible = false
	if _hint_readiness != null:
		_hint_readiness.visible = false
	if _hint_gap != null:
		_hint_gap.visible = false
	if _readiness_bar != null:
		_readiness_bar.visible = false


func hide_all() -> void:
	hide_prompt()
	hide_act()


func set_state(_kind: String) -> void:
	if _hint == null:
		return


func update_from(runtime: Node, show_readouts := true) -> void:
	if _hint == null or not is_instance_valid(runtime):
		return
	var state := int(runtime.get("state"))
	var climaxes := int(runtime.get("pony_climaxes"))
	_hint.visible = state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]
	_apply_control_visibility(state, runtime)
	if _y_label != null:
		var y_text := ""
		if state == STATE_ACTIVE:
			y_text = "Hold: afterglow" if climaxes > 0 else "Hold: stop"
		elif state == STATE_CLIMAX:
			y_text = "Hold: afterglow"
		elif state == STATE_AFTERGLOW:
			y_text = "Hold: exit"
		_y_label.text = y_text

	var show_readout := show_readouts and state in [STATE_ACTIVE, STATE_CLIMAX]
	if _readiness_bar != null:
		_readiness_bar.visible = show_readout
		if show_readout and _readiness_bar.has_method("set_value"):
			_readiness_bar.call("set_value", float(runtime.get("satisfaction")))

	var line := ""
	if _hint.visible and runtime.has_method("hud_cue_line"):
		line = str(runtime.call("hud_cue_line", show_readouts))
	_hint_status.text = line
	_hint_status.visible = not line.is_empty()
	var readiness_line := ""
	if _hint.visible and runtime.has_method("hud_readiness_line"):
		readiness_line = str(runtime.call("hud_readiness_line", show_readouts))
	_hint_readiness.text = readiness_line
	_hint_readiness.visible = not readiness_line.is_empty()
	if _hint_gap != null:
		_hint_gap.visible = _hint.visible


## Afterglow is mostly passive: hide controls that cannot do anything in that state. Missionary
## afterglow keeps only Y; horse afterglow keeps lean, reach, caress, kiss and Y.
func _apply_control_visibility(state: int, runtime: Node) -> void:
	var horse := str(runtime.get("pose_id")) == CATALOG.HORSE
	var afterglow := state == STATE_AFTERGLOW
	for key: String in _control_rows:
		var control := _control_rows[key] as Control
		if control == null:
			continue
		var show := true
		if afterglow:
			if horse:
				show = key in ["forward", "back", "left", "right", "caress_left",
					"caress_right", "kiss", "y"]
			else:
				show = key == "y"
		elif state == STATE_CLIMAX:
			show = key != "talk"
		control.visible = show
