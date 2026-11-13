extends RefCounted
## Draws the Debug block's action buttons and the Anatomy placement-target pill. The settings panel
## supplies this builder and owns where the block goes; the action registry stays in
## `debug/service.gd`. See docs/debug.md.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const STYLE := preload("res://world/ui/menu_style.gd")


## The Debug block's action buttons, plus the last result. Actions that share a `row` are drawn
## compactly on one line under the row's caption, so the block stays short.
static func build_actions(list: VBoxContainer, font_size: int, main: Node, tab := "general") -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	box.add_child(HSeparator.new())
	var heading := STYLE.label("ACTIONS", "Faint", maxi(12, font_size - 7))
	heading.add_theme_constant_override("line_spacing", 0)
	box.add_child(heading)
	if tab == SETTINGS.GENERAL:
		var hint := STYLE.label("Middle click in play: action wheel", "Faint",
			maxi(11, font_size - 8))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
	if tab == SETTINGS.ANATOMY:
		box.add_child(_placement_target_row(font_size))
	var status := STYLE.label("", "Faint", font_size - 6)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row_name := ""
	var row_box: HBoxContainer = null
	for name: String in DEBUG_ACTIONS.ACTIONS:
		var action: Dictionary = DEBUG_ACTIONS.ACTIONS[name]
		if not bool(action.get("panel", true)):
			continue
		if str(action.get("tab", "general")) != tab:
			continue
		var row := str(action.get("row", ""))
		if row.is_empty():
			row_name = ""
			row_box = null
			box.add_child(_action_button(name, action, font_size, main, status, false))
			continue
		if row != row_name or row_box == null:
			row_name = row
			row_box = HBoxContainer.new()
			row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_box.add_theme_constant_override("separation", 6)
			var caption := STYLE.label(row, "Faint", maxi(12, font_size - 8))
			caption.custom_minimum_size = Vector2(112, 0)
			caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row_box.add_child(caption)
			box.add_child(row_box)
		row_box.add_child(_action_button(name, action, font_size, main, status, true))
	box.add_child(status)
	list.add_child(box)


## The placement target pill sits above the Anatomy place actions. The backing setting is hidden
## from the declaration rows; this hand-built control is its one widget.
static func _placement_target_row(font_size: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var caption := STYLE.label("Placement target", "Faint", maxi(12, font_size - 8))
	caption.custom_minimum_size = Vector2(112, 0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	row.add_child(track)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	var buttons: Array = []
	for value: String in ["default", "mare"]:
		var pill := Button.new()
		pill.text = "Default" if value == "default" else "Pointed mare"
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 3)
		pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pill.button_pressed = SETTINGS.edit_target.get_choice() == value
		pill.set_meta("value", value)
		pill.pressed.connect(_select_placement_target.bind(value, buttons))
		buttons.append(pill)
		pills.add_child(pill)
	return row


static func _select_placement_target(value: String, buttons: Array) -> void:
	SETTINGS.edit_target.set_choice(value)
	for other: Variant in buttons:
		if other is Button:
			(other as Button).set_pressed_no_signal(str(other.get_meta("value")) == value)


static func _action_button(name: String, action: Dictionary, font_size: int, main: Node,
		status: Label, compact: bool) -> Button:
	var button := Button.new()
	button.text = DEBUG_ACTIONS.action_short(name, main) if compact \
		else DEBUG_ACTIONS.action_label(name, main)
	button.tooltip_text = str(action.get("help", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.pressed.connect(func() -> void:
		var result := DEBUG_ACTIONS.run_action(name, main)
		status.text = result
		_debug(main, "action %s %s" % [name, result]))
	return button


static func _debug(main: Node, text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
