extends CanvasLayer
## Desktop HUD: prompt, hint, and three vertical meters on the right:
## penetration, her satisfaction (debug only), and Anon's stamina.

const HUD_PUMP := preload("res://mods/unfplap/hud_pump.gd")
const HUD_BAR := preload("res://mods/unfplap/hud_bar.gd")
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

var _prompt: Label
var _hint: Label
var _bars: HBoxContainer
var _depth_col: VBoxContainer
var _satisfaction_col: VBoxContainer
var _stamina_col: VBoxContainer
var _depth: Control
var _satisfaction: Control
var _stamina: Control


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

	_bars = HBoxContainer.new()
	_bars.name = "Meters"
	_bars.anchor_left = 1.0
	_bars.anchor_right = 1.0
	_bars.anchor_top = 0.5
	_bars.anchor_bottom = 0.5
	_bars.offset_left = -360.0
	_bars.offset_right = -24.0
	_bars.offset_top = -230.0
	_bars.offset_bottom = 230.0
	_bars.alignment = BoxContainer.ALIGNMENT_END
	_bars.add_theme_constant_override("separation", 12)
	_bars.visible = false
	root.add_child(_bars)

	_depth = HUD_PUMP.new()
	_depth.name = "DepthBar"
	_depth.custom_minimum_size = Vector2(40.0, 400.0)
	_depth_col = _make_column("Penetration", _depth)

	_satisfaction = HUD_BAR.new()
	_satisfaction.name = "SatisfactionBar"
	_satisfaction.custom_minimum_size = Vector2(40.0, 400.0)
	_satisfaction.set("fill_color", Color(1.0, 0.45, 0.70))
	_satisfaction_col = _make_column("Satisfaction", _satisfaction)

	_stamina = HUD_BAR.new()
	_stamina.name = "StaminaBar"
	_stamina.custom_minimum_size = Vector2(40.0, 400.0)
	_stamina.set("fill_color", Color(0.42, 0.68, 1.0))
	_stamina_col = _make_column("Stamina", _stamina)

	_hint = _make_label("")
	_hint.name = "Hint"
	_hint.anchor_left = 0.0
	_hint.anchor_top = 1.0
	_hint.anchor_right = 0.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 28.0
	_hint.offset_top = -54.0
	_hint.offset_right = 430.0
	_hint.offset_bottom = -26.0
	_hint.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_hint.visible = false
	root.add_child(_hint)


func _make_column(title: String, bar: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var label := _make_label(title)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	column.add_child(bar)
	_bars.add_child(column)
	return column


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func show_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false


func show_act(runtime: Node, show_satisfaction := true) -> void:
	_bars.visible = false
	_hint.visible = true
	update_from(runtime, show_satisfaction)


func hide_act() -> void:
	if _bars != null:
		_bars.visible = false
	if _hint != null:
		_hint.visible = false


func hide_all() -> void:
	hide_prompt()
	hide_act()


func set_state(kind: String) -> void:
	if _hint == null:
		return
	if kind == "CLIMAX":
		_hint.text = ""
	elif kind == "AFTERGLOW":
		_hint.text = "Hold Q · End"
		if _bars != null:
			_bars.visible = false


func update_from(runtime: Node, show_satisfaction := true) -> void:
	if _bars == null or not is_instance_valid(runtime):
		return
	var state := int(runtime.get("state"))
	var active := state in [STATE_ACTIVE, STATE_CLIMAX]
	_bars.visible = active
	_depth_col.visible = state == STATE_ACTIVE
	_satisfaction_col.visible = active and show_satisfaction
	_stamina_col.visible = active
	if active:
		if state == STATE_ACTIVE:
			_depth.call("set_depth", float(runtime.get("depth")), bool(runtime.get("pump_up")))
		_satisfaction.call("set_value", float(runtime.get("satisfaction")), 100.0)
		_stamina.call("set_value", float(runtime.get("stamina")), 400.0)
	_hint.visible = state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]
	if state == STATE_ACTIVE:
		_hint.text = "Mouse ↕ · Pump    Hold Q · Stop"
	elif state == STATE_CLIMAX:
		_hint.text = ""
	elif state == STATE_AFTERGLOW:
		_hint.text = "Hold Q · End"
	else:
		_hint.text = ""
