extends RefCounted
## Draws the Unfplap Settings and Debug panels from `tunables_schema.gd`.
##
## This is the only file allowed to create settings widgets. Do not add a SpinBox, CheckButton or
## OptionButton control for a setting anywhere else: add a schema line instead and it appears here.
## See TUNING.md.
##
## Every section heading is a click-to-collapse button. Entries render in schema order, so the
## schema file doubles as the panel layout.

const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const SECTION_EXTRA := 2
const SUBSECTION_EXTRA := 1


## Fill `list` with one tab's sections. `changed` runs after every edit; `page` is redrawn when it
## has the settings page's `_redraw`.
static func build(list: VBoxContainer, tab: String, font_size: int, page: Node,
		changed: Callable) -> void:
	var section := ""
	var section_rows: Array = []
	for group: String in SCHEMA.groups(tab):
		var split := group.split("›", true, 1)
		var section_name := split[0].strip_edges()
		if section_name != section:
			section = section_name
			section_rows = []
			if list.get_child_count() > 0:
				list.add_child(HSeparator.new())
			var header := _heading(section_name, font_size + SECTION_EXTRA)
			header.toggled.connect(func(on: bool) -> void:
				for box: Variant in section_rows:
					if is_instance_valid(box):
						(box as CanvasItem).visible = on)
			list.add_child(header)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 6)
		section_rows.append(rows)
		if split.size() > 1:
			var sub_header := _heading("      " + split[1].strip_edges(), font_size + SUBSECTION_EXTRA)
			sub_header.toggled.connect(func(on: bool) -> void:
				rows.visible = on)
			list.add_child(sub_header)
		list.add_child(rows)
		for path: String in _paths(tab, group):
			_add_row(rows, path, font_size, page, changed)


## The Actions section: one button per `TUNABLES.ACTIONS` entry, plus its last result.
static func build_actions(list: VBoxContainer, font_size: int, main: Node) -> void:
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", font_size - 4)
	for name: String in TUNABLES.ACTIONS:
		var action: Dictionary = TUNABLES.ACTIONS[name]
		var button := Button.new()
		button.text = str(action.get("label", name))
		button.tooltip_text = str(action.get("help", ""))
		button.pressed.connect(func() -> void:
			var method := str(action.get("method", ""))
			if not is_instance_valid(main) or not main.has_method(method):
				status.text = "Action %s is not available." % name
				return
			var result: Variant = main.call(method)
			status.text = str(result) if result is String else ""
			_debug(main, "action %s" % name))
		list.add_child(button)
	list.add_child(status)


static func _paths(tab: String, group: String) -> Array:
	var out: Array = []
	for path: String in SCHEMA.all():
		var item := SCHEMA.entry(path)
		if str(item.get("tab", SCHEMA.DEBUG_TAB)) == tab \
				and str(item.get("group", "")) == group:
			out.append(path)
	return out


static func _heading(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = true
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", font_size)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


static func _add_row(parent: VBoxContainer, path: String, font_size: int, page: Node,
		changed: Callable) -> void:
	var item := SCHEMA.entry(path)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	block.add_child(row)
	var label := Label.new()
	label.text = str(item.get("label", path))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	row.add_child(label)
	match str(item.get("kind", "")):
		"bool":
			row.add_child(_check(path, font_size, page, changed))
		"num":
			row.add_child(_spin(path, item, font_size, page, changed))
		"choice":
			row.add_child(_choice(path, item, font_size, page, changed))
		"list":
			_add_list(block, path, item, font_size, page, changed)
	var help_text := str(item.get("help", ""))
	if not help_text.is_empty():
		var help := Label.new()
		help.text = help_text
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.add_theme_font_size_override("font_size", font_size - 5)
		help.modulate = Color(1.0, 1.0, 1.0, 0.72)
		block.add_child(help)


static func _check(path: String, font_size: int, page: Node, changed: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.button_pressed = TUNABLES.get_bool(path)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.add_theme_font_size_override("font_size", font_size - 2)
	check.toggled.connect(func(on: bool) -> void: _store(path, on, page, changed))
	return check


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
	spin.value = TUNABLES.get_float(path) * scale
	spin.value_changed.connect(func(value: float) -> void:
		_store(path, value / scale, page, changed))
	return spin


static func _choice(path: String, item: Dictionary, font_size: int, page: Node,
		changed: Callable) -> OptionButton:
	var options: Array = item.get("options", [])
	var labels: Array = item.get("labels", [])
	var option := OptionButton.new()
	for index: int in options.size():
		var text := str(labels[index]) if index < labels.size() else str(options[index])
		option.add_item(text)
		option.set_item_metadata(index, options[index])
	var current := TUNABLES.get_string(path)
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			option.select(index)
			break
	option.add_theme_font_size_override("font_size", font_size - 2)
	option.item_selected.connect(func(index: int) -> void:
		_store(path, str(option.get_item_metadata(index)), page, changed))
	return option


## A set of options stored as an array: one check per option, saved as the checked list.
static func _add_list(parent: VBoxContainer, path: String, item: Dictionary, font_size: int,
		page: Node, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var options: Array = item.get("options", [])
	var selected := TUNABLES.get_list(path)
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


static func _store(path: String, value: Variant, page: Node, changed: Callable) -> void:
	TUNABLES.set_value(path, value)
	if changed.is_valid():
		changed.call()
	if is_instance_valid(page) and page.has_method("_redraw"):
		page.call("_redraw")


static func _debug(main: Node, text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
