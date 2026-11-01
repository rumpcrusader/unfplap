extends CanvasLayer
## Desktop HUD: the L prompt, the Climax/Capacity bars, and the afterglow hint.

const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

var _prompt: Label
var _panel: VBoxContainer
var _climax: ProgressBar
var _capacity: ProgressBar
var _climax_label: Label
var _capacity_label: Label
var _hint: Label


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "UnfunfunfRoot"
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

	_panel = VBoxContainer.new()
	_panel.name = "Bars"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 28.0
	_panel.offset_top = -70.0
	_panel.offset_right = 300.0
	_panel.offset_bottom = 70.0
	_panel.visible = false
	root.add_child(_panel)

	_climax_label = _make_label("Climax")
	_panel.add_child(_climax_label)
	_climax = _make_bar(Color(1.0, 0.45, 0.70))
	_panel.add_child(_climax)
	_capacity_label = _make_label("Capacity")
	_panel.add_child(_capacity_label)
	_capacity = _make_bar(Color(0.42, 0.68, 1.0))
	_panel.add_child(_capacity)
	_hint = _make_label("")
	_hint.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_panel.add_child(_hint)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(240.0, 18.0)
	bar.modulate = color
	return bar


func show_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false


func show_act(runtime: Node) -> void:
	if _panel == null:
		return
	_panel.visible = true
	_hint.visible = true
	_climax.visible = true
	_capacity.visible = true
	_climax_label.visible = true
	_capacity_label.visible = true
	update_from(runtime)


func hide_act() -> void:
	if _panel != null:
		_panel.visible = false


func hide_all() -> void:
	hide_prompt()
	hide_act()


func set_state(kind: String) -> void:
	if _panel == null:
		return
	if kind == "CLIMAX":
		_hint.text = ""
	elif kind == "AFTERGLOW":
		_hint.text = "Q · End"
		_climax.visible = false
		_capacity.visible = false
		_climax_label.visible = false
		_capacity_label.visible = false


func update_from(runtime: Node) -> void:
	if _panel == null or not is_instance_valid(runtime):
		return
	var state := int(runtime.get("state"))
	if state == STATE_AFTERGLOW:
		_panel.visible = true
		_hint.text = "Q · End"
		_climax.visible = false
		_capacity.visible = false
		_climax_label.visible = false
		_capacity_label.visible = false
		return
	_climax.visible = true
	_capacity.visible = true
	_climax_label.visible = true
	_capacity_label.visible = true
	_climax.value = float(runtime.get("satisfaction"))
	_capacity.value = float(runtime.get("capacity"))
	if state == STATE_CLIMAX:
		_hint.text = ""
	else:
		_hint.text = "F · Pump    Q · Stop"
