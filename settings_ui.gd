extends RefCounted
## Draws the Unfplap settings tabs from the declarations in `settings.gd`.
##
## This is the only file allowed to create settings widgets. Do not add a SpinBox, CheckButton or
## OptionButton control for a setting anywhere else: declare the setting instead and it appears
## here. See TUNING.md.
##
## Every section heading is a click-to-collapse button wearing the menu's open sidebar row (the
## `Tab` look: a pink accent while the section is open). Every setting is one of the settings
## page's own row cards (`world/ui/menu_style.gd` and `settings_page.gd`): the name with a Faint
## note, the control on the right, a switch beside its Off/On state, and a few short choices as
## Segment pills in a track. Settings render in declaration order, so the declarations double as
## the panel layout.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug_actions.gd")
const STYLE := preload("res://world/ui/menu_style.gd")

## Choices at most in a pill track, and the longest label one may hold: past either, the row keeps
## a dropdown, which cannot overflow the card.
const MOST_PILLS := 4
const PILL_LABEL_CHARS := 18


## Fill `list` with one tab's settings: the player-facing sections first, then one Debug section at
## the bottom holding that tab's debug settings under their own group names.
##
## The Debug section is always built and its visibility follows `debug_mode`, so the toggle takes
## effect without rebuilding the panel. `actions_owner` adds the Debug action buttons inside the
## section; pass it only for the General tab. Returns the Debug section, or null when the tab has
## no debug settings.
static func build(list: VBoxContainer, tab: String, font_size: int, page: Node,
		changed: Callable, actions_owner: Node = null) -> Control:
	var player: Array = []
	var debug: Array = []
	for setting: Variant in SETTINGS.tab_settings(tab):
		if bool(setting.hidden):
			continue
		(debug if bool(setting.debug) else player).append(setting.path)
	_build_sections(list, tab, "", player, font_size, page, changed)
	if debug.is_empty():
		return null
	if list.get_child_count() > 0:
		list.add_child(HSeparator.new())
	var debug_section := VBoxContainer.new()
	debug_section.name = "DebugSection"
	debug_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_section.add_theme_constant_override("separation", 6)
	debug_section.visible = SETTINGS.debug_mode.get_bool()
	var open := SETTINGS.section_open(tab, "Debug")
	var header := _heading("Debug", font_size, false, open)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	body.visible = open
	header.toggled.connect(func(on: bool) -> void:
		SETTINGS.set_section_open(tab, "Debug", on)
		body.visible = on)
	debug_section.add_child(header)
	debug_section.add_child(body)
	list.add_child(debug_section)
	_build_sections(body, tab, "Debug/", debug, font_size, page, changed)
	if is_instance_valid(actions_owner):
		build_actions(body, font_size, actions_owner, tab)
	return debug_section


## One section pass. `prefix` separates the Debug block's section state from the player sections.
static func _build_sections(list: VBoxContainer, tab: String, prefix: String, paths: Array,
		font_size: int, page: Node, changed: Callable) -> void:
	# Settings with no group are not a section: they sit at the top of the tab (or Debug block)
	# without a heading. A group needs at least three related settings to earn one.
	var loose: Array = []
	for path: String in paths:
		var setting: Variant = SETTINGS.by_path(path)
		if setting != null and str(setting.group).is_empty():
			loose.append(path)
	if not loose.is_empty():
		var loose_rows := VBoxContainer.new()
		loose_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		loose_rows.add_theme_constant_override("separation", 6)
		list.add_child(loose_rows)
		for path: String in loose:
			_add_row(loose_rows, path, font_size, page, changed)
	# One heading per section name. A section whose declarations are interleaved with another
	# group folds its rows back into the first heading instead of drawing a duplicate.
	var sections: Dictionary = {}
	for group: String in _groups_of(paths):
		var split := group.split("›", true, 1)
		var section_name := split[0].strip_edges()
		var section_key := prefix + section_name
		var section_rows: Array
		if sections.has(section_name):
			section_rows = sections[section_name]
		else:
			section_rows = []
			sections[section_name] = section_rows
			if list.get_child_count() > 0:
				list.add_child(HSeparator.new())
			var open := SETTINGS.section_open(tab, section_key)
			var header := _heading(section_name, font_size, false, open)
			header.toggled.connect(func(on: bool) -> void:
				SETTINGS.set_section_open(tab, section_key, on)
				for box: Variant in section_rows:
					if is_instance_valid(box):
						(box as CanvasItem).visible = on)
			list.add_child(header)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 6)
		rows.visible = SETTINGS.section_open(tab, section_key)
		section_rows.append(rows)
		if split.size() > 1:
			var sub_key := prefix + group
			var sub_open := SETTINGS.section_open(tab, sub_key)
			var sub_header := _heading(split[1].strip_edges(), font_size, true, sub_open)
			sub_header.toggled.connect(func(on: bool) -> void:
				SETTINGS.set_section_open(tab, sub_key, on)
				rows.visible = on)
			list.add_child(sub_header)
		list.add_child(rows)
		if group == SETTINGS.MISSIONARY_SIZE_GROUP:
			_build_missionary_size(rows, font_size, page, changed)
		else:
			for path: String in _paths_in(paths, group):
				_add_row(rows, path, font_size, page, changed)


## The six missionary geometry settings are per pony size. One dropdown picks which size is edited;
## the six rows below belong to that size. The act always reads the game's current preset, so this
## only chooses which preset's values are being edited.
static func _build_missionary_size(parent: VBoxContainer, font_size: int, page: Node,
		changed: Callable) -> void:
	var values := VBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.add_theme_constant_override("separation", 6)
	var rebuild := func() -> void:
		for child: Node in values.get_children():
			values.remove_child(child)
			child.queue_free()
		var size: String = SETTINGS.size_group.get_choice()
		for base: String in SETTINGS.MISSIONARY_SIZE_BASES:
			_add_row(values, "presentation.missionary.size.%s.%s" % [size, base], font_size, page, changed)
	var on_size := func() -> void:
		changed.call()
		rebuild.call()
	_size_selector(parent, "presentation.missionary.size_group", font_size, page, on_size)
	parent.add_child(values)
	rebuild.call()


## The dropdown above the per-size rows, drawn in the page's row card. It always uses a dropdown,
## never the Segment pills the generic choice row would pick.
static func _size_selector(parent: VBoxContainer, path: String, font_size: int, page: Node,
		changed: Callable) -> void:
	var item: Dictionary = SETTINGS.entry_view(SETTINGS.by_path(path))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_box(page, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var label := STYLE.label(str(item.get("label", "Size")), "", font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	var options: Array = item.get("options", [])
	var labels: Array = item.get("labels", [])
	for index: int in options.size():
		option.add_item(str(labels[index]) if index < labels.size() else str(options[index]))
		option.set_item_metadata(index, options[index])
	var current: String = SETTINGS.size_group.get_choice()
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			option.select(index)
			break
	option.add_theme_font_size_override("font_size", font_size - 2)
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.item_selected.connect(func(index: int) -> void:
		_store(path, str(option.get_item_metadata(index)), page, changed))
	row.add_child(option)
	parent.add_child(card)


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
	button.text = str(action.get("short", action.get("label", name))) if compact \
		else str(action.get("label", name))
	button.tooltip_text = str(action.get("help", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.pressed.connect(func() -> void:
		var result := DEBUG_ACTIONS.run_action(name, main)
		status.text = result
		_debug(main, "action %s %s" % [name, result]))
	return button


static func _groups_of(paths: Array) -> Array:
	var out: Array = []
	for path: String in paths:
		var setting: Variant = SETTINGS.by_path(path)
		if setting == null or str(setting.group).is_empty():
			continue
		if not out.has(setting.group):
			out.append(setting.group)
	return out


static func _paths_in(paths: Array, group: String) -> Array:
	var out: Array = []
	for path: String in paths:
		var setting: Variant = SETTINGS.by_path(path)
		if setting != null and str(setting.group) == group:
			out.append(path)
	return out


## A collapsible section heading in the menu's own open-row look: the `Tab` variation draws the
## pink accent and tint while the section is open, and a quiet row while it is closed. A section
## keeps its declared wording (like the page's own sidebar rows); a subheading is smaller and
## indented under it.
static func _heading(text: String, font_size: int, sub: bool, open := true) -> Button:
	var button := Button.new()
	button.text = ("        " + text) if sub else text
	button.toggle_mode = true
	button.button_pressed = open
	button.theme_type_variation = "Tab"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.add_theme_font_size_override("font_size", maxi(12, font_size - (5 if sub else 2)))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


static func _add_row(parent: VBoxContainer, path: String, font_size: int, page: Node,
		changed: Callable) -> void:
	var item: Dictionary = SETTINGS.entry_view(SETTINGS.by_path(path))
	var card := PanelContainer.new()
	var idle := _row_box(page, false)
	var hover := _row_box(page, true)
	card.add_theme_stylebox_override("panel", idle)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", hover)
		_redraw(page))
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", idle)
		_redraw(page))
	parent.add_child(card)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	card.add_child(block)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	block.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)
	var label := STYLE.label(str(item.get("label", path)), "", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(label)
	var help_text := str(item.get("help", ""))
	if not help_text.is_empty():
		var help := STYLE.label(help_text, "Faint", font_size - 5)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(help)
	match str(item.get("kind", "")):
		"bool":
			row.add_child(_check(path, font_size, page, changed))
		"num":
			if bool(item.get("slider", false)):
				row.add_child(_slider(path, item, font_size, page, changed))
			else:
				row.add_child(_spin(path, item, font_size, page, changed))
		"choice":
			row.add_child(_choice(path, item, font_size, page, changed))
		"color":
			row.add_child(_color(path, font_size, page, changed))
		"list":
			_add_list(block, path, item, font_size, page, changed)


## A row's card: the page's own idle/hover box when it exposes them (it stores both at setup),
## else the same box built from the menu style.
static func _row_box(page: Node, hover: bool) -> StyleBox:
	var stored: Variant = null
	if is_instance_valid(page):
		stored = page.get("_row_hover" if hover else "_row_idle")
	if stored is StyleBox:
		return stored as StyleBox
	if hover:
		return STYLE.rounded(STYLE.box(Color(1, 1, 1, 0.085), Color(STYLE.PINK, 0.45), 1, 16, 16, 9))
	return STYLE.rounded(STYLE.box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.07), 1, 16, 16, 9))


## A switch and its Off/On state, as the page's boolean rows show them.
static func _check(path: String, font_size: int, page: Node, changed: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var state := STYLE.label("", "Muted", font_size - 2)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(state)
	var check := CheckButton.new()
	check.button_pressed = _setting(path).get_bool()
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.set_meta("no_lift", true)
	check.toggled.connect(func(on: bool) -> void:
		state.text = "On" if on else "Off"
		_store(path, on, page, changed))
	state.text = "On" if check.button_pressed else "Off"
	box.add_child(check)
	return box


## A colour swatch; its popup is Godot's ColorPicker with HSV/RGB sliders and the hex field.
static func _color(path: String, font_size: int, page: Node, changed: Callable) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(float(font_size) * 5.0, float(font_size) * 1.6)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.edit_alpha = false
	var setting: Variant = _setting(path)
	if setting is SETTINGS.ColorSetting:
		button.color = (setting as SETTINGS.ColorSetting).get_color()
	button.color_changed.connect(func(color: Color) -> void:
		_store(path, color, page, changed))
	return button


static func _spin(path: String, item: Dictionary, font_size: int, page: Node,
		changed: Callable) -> SpinBox:
	var scale := float(item.get("scale", 1.0))
	if is_zero_approx(scale):
		scale = 1.0
	var spin := SpinBox.new()
	spin.min_value = float(item.get("low", -1000000.0)) * scale
	spin.max_value = float(item.get("high", 1000000.0)) * scale
	var step := float(item.get("step", 0.0))
	spin.step = step if step > 0.0 else 0.01 * scale
	spin.suffix = str(item.get("unit", ""))
	spin.add_theme_font_size_override("font_size", font_size - 2)
	spin.custom_minimum_size.x = float(font_size) * 10.0
	spin.value = _setting(path).get_num() * scale
	spin.value_changed.connect(func(value: float) -> void:
		_store(path, value / scale, page, changed))
	return spin


## A number as the page's own slider row: the track, then its value beside it. The stored value
## keeps the schema units; `scale` only changes what the player sees.
static func _slider(path: String, item: Dictionary, font_size: int, page: Node,
		changed: Callable) -> HBoxContainer:
	var scale := float(item.get("scale", 1.0))
	if is_zero_approx(scale):
		scale = 1.0
	var unit := str(item.get("unit", ""))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var slider := HSlider.new()
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = float(item.get("low", 0.0)) * scale
	slider.max_value = float(item.get("high", 1.0)) * scale
	var step := float(item.get("step", 0.0))
	slider.step = step if step > 0.0 else 0.01 * scale
	slider.custom_minimum_size = Vector2(float(font_size) * 9.0, font_size * 1.6)
	slider.value = _setting(path).get_num() * scale
	var value := STYLE.label("", "Muted", font_size - 2)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.custom_minimum_size.x = float(font_size) * 3.0
	value.text = _slider_text(slider.value, unit)
	slider.value_changed.connect(func(at: float) -> void:
		value.text = _slider_text(at, unit)
		_store(path, at / scale, page, changed))
	box.add_child(slider)
	box.add_child(value)
	return box


static func _slider_text(value: float, unit: String) -> String:
	var rounded := roundf(value)
	var text := String.num(rounded, 0) if absf(value - rounded) < 0.001 else String.num(value, 1)
	return text + unit


## A choice: a few short values as the page's Segment pills in one track, otherwise the themed
## dropdown, which cannot overflow the row.
static func _choice(path: String, item: Dictionary, font_size: int, page: Node,
		changed: Callable) -> Control:
	var options: Array = item.get("options", [])
	var labels: Array = item.get("labels", [])
	var texts: Array = []
	for index: int in options.size():
		texts.append(str(labels[index]) if index < labels.size() else str(options[index]))
	if _pills_fit(texts, font_size, page):
		return _pills(path, options, texts, font_size, page, changed)
	var option := OptionButton.new()
	for index: int in options.size():
		option.add_item(str(texts[index]))
		option.set_item_metadata(index, options[index])
	var current: String = _setting(path).get_choice()
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			option.select(index)
			break
	option.add_theme_font_size_override("font_size", font_size - 2)
	option.item_selected.connect(func(index: int) -> void:
		_store(path, str(option.get_item_metadata(index)), page, changed))
	return option


## A few short choices fit side by side, measured as the page measures them: the pills, their
## padding and the track's, against the room a row's control has.
static func _pills_fit(texts: Array, font_size: int, page: Node) -> bool:
	if texts.size() < 2 or texts.size() > MOST_PILLS:
		return false
	for text: Variant in texts:
		if str(text).length() > PILL_LABEL_CHARS:
			return false
	var room := 0.0
	if is_instance_valid(page) and typeof(page.get("_room")) == TYPE_FLOAT:
		room = float(page.get("_room"))
	if room <= 0.0:
		return true
	var width := 10.0 + 4.0 * (texts.size() - 1)
	for text: Variant in texts:
		width += STYLE.BOLD.get_string_size(str(text), HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size - 4).x + 30.0
	return width <= room


## Every value a pill in one track, the chosen one lit, one press picks another.
static func _pills(path: String, options: Array, texts: Array, font_size: int, page: Node,
		changed: Callable) -> Control:
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	var current: String = _setting(path).get_choice()
	for index: int in options.size():
		var pill := Button.new()
		pill.text = str(texts[index])
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 4)
		pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pill.button_pressed = str(options[index]) == current
		pill.pressed.connect(_choose_pill.bind(pills, index, path, options, page, changed))
		pills.add_child(pill)
	return track


static func _choose_pill(pills: HBoxContainer, index: int, path: String, options: Array,
		page: Node, changed: Callable) -> void:
	for at: int in pills.get_child_count():
		(pills.get_child(at) as Button).set_pressed_no_signal(at == index)
	_store(path, str(options[index]), page, changed)


## A set of options stored as an array: one check per option, saved as the checked list.
static func _add_list(parent: VBoxContainer, path: String, item: Dictionary, font_size: int,
		page: Node, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var options: Array = item.get("options", [])
	var selected: Array = _setting(path).get_list()
	var checks: Dictionary = {}
	for option: Variant in options:
		var key := str(option)
		var check := CheckButton.new()
		check.text = key.capitalize()
		check.button_pressed = selected.has(key)
		check.add_theme_font_size_override("font_size", font_size - 3)
		row.add_child(check)
		checks[key] = check
	for key: String in checks:
		(checks[key] as CheckButton).toggled.connect(func(_on: bool) -> void:
			var values: Array = []
			for name: String in checks:
				if (checks[name] as CheckButton).button_pressed:
					values.append(name)
			_store(path, values, page, changed))


## The declaration behind a row. The panel is generic, so it resolves the setting once here.
static func _setting(path: String) -> Variant:
	return SETTINGS.by_path(path)


static func _store(path: String, value: Variant, page: Node, changed: Callable) -> void:
	_setting(path).set_value(value)
	if changed.is_valid():
		changed.call()
	_redraw(page)


## Canvas hosts (the title screen, the pause menu) draw on demand, so an edit asks for a repaint.
static func _redraw(page: Node) -> void:
	if is_instance_valid(page) and page.has_method("_redraw"):
		page.call("_redraw")


static func _debug(main: Node, text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
