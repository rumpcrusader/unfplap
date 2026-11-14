extends RefCounted
## Draws the Unfplap settings tabs from the declarations in `settings/service.gd` and injects the
## Unfplap tab into the game's settings page.
##
## This is the only file allowed to create the declaration-drawn settings widgets. Do not add a
## SpinBox, CheckButton or OptionButton control for a setting anywhere else: declare the setting
## instead and it appears here. The Characters form is `settings/characters_ui.gd`; the
## catalog-driven Integrations tab reads `shared/integrations.gd`; the Debug action buttons are
## `debug/ui.gd`. See docs/settings.md.
##
## Every section heading is a click-to-collapse button wearing the menu's open sidebar row (the
## `Tab` look: a pink accent while the section is open). Every setting is one of the settings
## page's own row cards (`world/ui/menu_style.gd` and `settings_page.gd`): the name with a Faint
## note, the control on the right, a switch beside its Off/On state, and a few short choices as
## Segment pills in a track. Settings render in declaration order, so the declarations double as
## the panel layout.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const CHARACTERS_UI := preload("res://mods/unfplap/settings/characters_ui.gd")
const INTEGRATIONS_CATALOG := preload("res://mods/unfplap/shared/integrations.gd")
const STYLE := preload("res://world/ui/menu_style.gd")

## Choices at most in a pill track, and the longest label one may hold: past either, the row keeps
## a dropdown, which cannot overflow the card.
const MOST_PILLS := 4
const PILL_LABEL_CHARS := 18

## Injected pages, the Debug block of each tab (toggled live by `debug_mode`) and the guard that
## keeps the game's own sidebar buttons from fighting the injected tab.
static var _injected: Array = []
static var _debug_sections: Array = []
## Anatomy tab content that depends on the visibility pill, so Never can grey it out live.
static var _anatomy_gates: Array = []
static var _switch_guard := false


## The game's own Controls capture, reduced to the one button the mod needs. It owns the key
## events only while `capturing`; Escape cancels and puts the old label back.
class KeyCaptureButton extends Button:
	signal captured(code: int)

	var capturing := false
	var normal_text := ""

	func _init() -> void:
		theme_type_variation = "Key"
		focus_mode = Control.FOCUS_ALL
		clip_text = true
		alignment = HORIZONTAL_ALIGNMENT_CENTER

	func set_key_text(value: String) -> void:
		normal_text = value
		text = value

	func start_capture() -> void:
		capturing = true
		text = "Press a key…"

	func _input(event: InputEvent) -> void:
		if not capturing or disabled or not is_visible_in_tree():
			return
		if not event is InputEventKey:
			return
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == KEY_ESCAPE:
			capturing = false
			text = normal_text
			get_viewport().set_input_as_handled()
			return
		capturing = false
		captured.emit(code)
		get_viewport().set_input_as_handled()


## Fill `list` with one tab's settings: the player-facing sections first, then one Debug section at
## the bottom holding that tab's debug settings under their own group names.
##
## The Debug section is always built and its visibility follows `debug_mode`, so the toggle takes
## effect without rebuilding the panel. `actions_builder` is called with the Debug body, the font
## size and the tab; `main` passes the `debug/ui.gd` builder. `debug_only` keeps only the Debug
## block, for a tab whose player-facing content another builder already drew. Returns the Debug
## section, or null when the tab has no debug settings.
static func build(list: VBoxContainer, tab: String, font_size: int, page: Node,
		changed: Callable, actions_builder := Callable(), debug_only := false) -> Control:
	var player: Array = []
	var debug: Array = []
	for setting: SETTINGS.Setting in SETTINGS.tab_settings(tab):
		if setting.hidden:
			continue
		(debug if setting.debug else player).append(setting)
	if debug_only:
		player.clear()
	var gate: VBoxContainer = null
	var gate_note: Label = null
	if tab == SETTINGS.ANATOMY:
		# The visibility pill stays interactive; everything it governs sits in one container.
		for index: int in range(player.size() - 1, -1, -1):
			var setting := player[index] as SETTINGS.Setting
			if setting != null and setting.name == "anatomy_mode":
				player.remove_at(index)
				_add_row(list, setting, font_size, page, changed)
				break
		gate_note = STYLE.label(
			"Choose During act only or Always to configure the anatomy.", "Faint",
			font_size - 5)
		gate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gate_note.visible = SETTINGS.anatomy_mode.get_choice() == "never"
		list.add_child(gate_note)
		gate = VBoxContainer.new()
		gate.name = "AnatomyGateContent"
		gate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gate.add_theme_constant_override("separation", 6)
		list.add_child(gate)
	_build_sections(gate if gate != null else list, tab, "", player, font_size, page, changed)
	var host: VBoxContainer = gate if gate != null else list
	var debug_section: Control = null
	if debug.is_empty():
		if gate != null:
			_register_anatomy_gate(gate, gate_note)
		return null
	if host.get_child_count() > 0:
		host.add_child(HSeparator.new())
	debug_section = VBoxContainer.new()
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
	host.add_child(debug_section)
	_build_sections(body, tab, "Debug/", debug, font_size, page, changed)
	if actions_builder.is_valid():
		actions_builder.call(body, font_size, tab)
	if gate != null:
		_register_anatomy_gate(gate, gate_note)
	return debug_section


static func _register_anatomy_gate(content: VBoxContainer, note: Label) -> void:
	_anatomy_gates.append({"content": content, "note": note})
	_set_enabled_deep(content, SETTINGS.anatomy_mode.get_choice() != "never")


## Grey out and disable the Anatomy content while the visibility pill is Never. The stored
## mouse filter and disabled state are restored when the pill moves to Act or Always.
static func _refresh_anatomy_gates() -> void:
	var enabled := SETTINGS.anatomy_mode.get_choice() != "never"
	var live: Array = []
	for entry: Dictionary in _anatomy_gates:
		var content: Variant = entry.get("content")
		var note: Variant = entry.get("note")
		if not is_instance_valid(content):
			continue
		live.append(entry)
		_set_enabled_deep(content as Node, enabled)
		if is_instance_valid(note):
			(note as CanvasItem).visible = not enabled
	_anatomy_gates = live


static func _set_enabled_deep(root: Node, enabled: bool) -> void:
	if root is CanvasItem:
		(root as CanvasItem).modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.75)
	for child: Node in root.get_children():
		if child is Control:
			var control := child as Control
			if not control.has_meta("unfplap_mouse_filter"):
				control.set_meta("unfplap_mouse_filter", control.mouse_filter)
			control.mouse_filter = int(control.get_meta("unfplap_mouse_filter")) \
				if enabled else Control.MOUSE_FILTER_IGNORE
			if control is BaseButton:
				var button := control as BaseButton
				if not button.has_meta("unfplap_disabled"):
					button.set_meta("unfplap_disabled", button.disabled)
				button.disabled = bool(button.get_meta("unfplap_disabled")) \
					if enabled else true
			elif control is SpinBox:
				var spin := control as SpinBox
				if not spin.has_meta("unfplap_editable"):
					spin.set_meta("unfplap_editable", spin.editable)
				spin.editable = bool(spin.get_meta("unfplap_editable")) if enabled else false
			elif control is Slider:
				var slider := control as Slider
				if not slider.has_meta("unfplap_editable"):
					slider.set_meta("unfplap_editable", slider.editable)
				slider.editable = bool(slider.get_meta("unfplap_editable")) if enabled else false
		_set_enabled_deep(child, enabled)


## The catalog-driven Integrations tab. Every supported mod gets its own collapsible section,
## named after the mod and open by default. The section body carries the verified version and that
## provider's player-facing feature flags; debug-only switches sit in the tab's Debug block at the
## bottom. There is no installed/mismatch status.
static func build_integrations(list: VBoxContainer, font_size: int, page: Node,
		changed: Callable) -> Control:
	_build_experimental_notice(list, font_size)
	var providers: Array[Dictionary] = INTEGRATIONS_CATALOG.all()
	if providers.is_empty():
		list.add_child(STYLE.label("No supported integrations in this build.", "Faint",
			font_size - 5))
	var drawn: Dictionary = {}
	for provider: Dictionary in providers:
		var mod_id := str(provider.get("mod_id", ""))
		var title := "%s by %s" % [str(provider.get("mod_name", "")),
			str(provider.get("author", ""))]
		var section_key := "Mods/" + (mod_id if not mod_id.is_empty() else title)
		var open := SETTINGS.section_open(SETTINGS.INTEGRATIONS, section_key)
		if list.get_child_count() > 0:
			list.add_child(HSeparator.new())
		var header := _heading(title, font_size, false, open)
		list.add_child(header)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		body.visible = open
		header.toggled.connect(func(on: bool) -> void:
			SETTINGS.set_section_open(SETTINGS.INTEGRATIONS, section_key, on)
			body.visible = on)
		list.add_child(body)
		_add_integration_version(body, provider, font_size)
		var features: Variant = provider.get("features", [])
		if features is Array:
			for raw: Variant in features as Array:
				var name := str(raw)
				var setting := SETTINGS.by_name(name)
				if setting == null or setting.debug or drawn.has(name):
					continue
				drawn[name] = true
				_add_row(body, setting, font_size, page, changed)
	# A declaration without a catalog entry must never become an invisible setting.
	for setting: SETTINGS.Setting in SETTINGS.tab_settings(SETTINGS.INTEGRATIONS):
		if setting.debug or drawn.has(setting.name):
			continue
		drawn[setting.name] = true
		_add_row(list, setting, font_size, page, changed)
	# Debug-only integration switches stay behind Enable debug, in the tab's one Debug block.
	return build(list, SETTINGS.INTEGRATIONS, font_size, page, changed, Callable(), true)


## The Integrations tab opens with the blue Experimental banner. It is the tab's only status
## block: the provider sections below stay catalog-driven and carry no installed/mismatch state.
static func _build_experimental_notice(list: VBoxContainer, font_size: int) -> void:
	var panel := PanelContainer.new()
	panel.name = "IntegrationsExperimental"
	var style := STYLE.box(Color(STYLE.SKY, 0.16), Color(STYLE.SKY, 0.8), 1)
	panel.add_theme_stylebox_override("panel", STYLE.rounded(style))
	var label := STYLE.label("Experimental", "", font_size - 4)
	label.add_theme_color_override("font_color", STYLE.SKY)
	panel.add_child(label)
	list.add_child(panel)


static func _add_integration_version(parent: VBoxContainer, provider: Dictionary,
		font_size: int) -> void:
	var hint := STYLE.label("Verified with version: %s" % str(provider.get("verified_version", "")),
		"Faint", font_size - 5)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)


## One section pass. `prefix` separates the Debug block's section state from the player sections.
static func _build_sections(list: VBoxContainer, tab: String, prefix: String, settings: Array,
		font_size: int, page: Node, changed: Callable) -> void:
	# The act key is a hidden numeric declaration because a capture is not one of the declaration
	# widgets. It is still the first row of the General tab, with no section heading.
	if tab == SETTINGS.GENERAL and prefix.is_empty():
		_build_act_key_row(list, font_size, page, changed)
	# Settings with no group are not a section: they sit at the top of the tab (or Debug block)
	# without a heading. A group needs at least three related settings to earn one.
	var loose: Array = []
	for raw: Variant in settings:
		var setting := raw as SETTINGS.Setting
		if setting != null and setting.group.is_empty():
			loose.append(setting)
	if not loose.is_empty():
		var loose_rows := VBoxContainer.new()
		loose_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		loose_rows.add_theme_constant_override("separation", 6)
		list.add_child(loose_rows)
		for raw: Variant in loose:
			_add_row(loose_rows, raw as SETTINGS.Setting, font_size, page, changed)
	# One heading per section name. A section whose declarations are interleaved with another
	# group folds its rows back into the first heading instead of drawing a duplicate.
	var sections: Dictionary = {}
	for group: String in _groups_of(settings):
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
			for raw: Variant in _settings_in(settings, group):
				_add_row(rows, raw as SETTINGS.Setting, font_size, page, changed)


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
			var setting := SETTINGS.by_path(
				"presentation.missionary.size.%s.%s" % [size, base])
			if setting != null:
				_add_row(values, setting, font_size, page, changed)
	var on_size := func() -> void:
		changed.call()
		rebuild.call()
	_size_selector(parent, SETTINGS.size_group, font_size, page, on_size)
	parent.add_child(values)
	rebuild.call()


## The Act Key row: the hidden `act_key` declaration is a physical keycode, so the generic number
## widget is skipped and this hand-built capture takes its place.
static func _build_act_key_row(list: VBoxContainer, font_size: int, page: Node,
		changed: Callable) -> void:
	if SETTINGS.act_key == null:
		return
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
	list.add_child(card)
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
	var label := STYLE.label(SETTINGS.act_key.label, "", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(label)
	var help := STYLE.label(SETTINGS.act_key.help, "Faint", font_size - 5)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(help)
	var button := KeyCaptureButton.new()
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.custom_minimum_size = Vector2(font_size * 7.0, font_size * 2.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_key_text(_act_key_label())
	if is_instance_valid(page) and bool(page.get("xr")):
		button.disabled = true
	button.captured.connect(func(code: int) -> void:
		SETTINGS.act_key.set_num(float(code))
		button.set_key_text(_act_key_label())
		if changed.is_valid():
			changed.call()
		_redraw(page))
	button.pressed.connect(func() -> void:
		button.start_capture()
		_redraw(page))
	row.add_child(button)


static func _act_key_label() -> String:
	return ACT_KEYS.label(int(SETTINGS.act_key.get_num()))


## The dropdown above the per-size rows, drawn in the page's row card. It always uses a dropdown,
## never the Segment pills the generic choice row would pick.
static func _size_selector(parent: VBoxContainer, setting: SETTINGS.ChoiceSetting,
		font_size: int, page: Node, changed: Callable) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_box(page, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var label := STYLE.label(setting.label, "", font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	for index: int in setting.options.size():
		option.add_item(setting.labels[index] if index < setting.labels.size()
			else setting.options[index])
		option.set_item_metadata(index, setting.options[index])
	var current := setting.get_choice()
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			option.select(index)
			break
	option.add_theme_font_size_override("font_size", font_size - 2)
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.item_selected.connect(func(index: int) -> void:
		_store(setting, str(option.get_item_metadata(index)), page, changed))
	row.add_child(option)
	parent.add_child(card)


## The settings-page injection entry point. The title and pause hosts add the page to the tree
## before calling `setup()`, so the actual injection is deferred and retries for a few frames.
static func inject(page: Node, actions_builder: Callable, live_character_ids: Callable,
		participation: Callable, changed: Callable, debug: Callable = Callable()) -> void:
	# Opening the page re-reads settings.json, so hand-edited values apply without a restart.
	SETTINGS.reload_file()
	if not is_instance_valid(page) or page.has_meta("unfplap_tab") \
			or page.has_meta("unfplap_pending"):
		return
	page.set_meta("unfplap_pending", true)
	_inject_after_layout.call_deferred(page, actions_builder, live_character_ids, participation,
		changed, debug)


static func _inject_after_layout(page: Node, actions_builder: Callable,
		live_character_ids: Callable, participation: Callable, changed: Callable,
		debug: Callable) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	for attempt: int in 10:
		if not is_instance_valid(page) or not page.is_inside_tree():
			if is_instance_valid(page):
				page.remove_meta("unfplap_pending")
			return
		if page.has_meta("unfplap_tab"):
			page.remove_meta("unfplap_pending")
			return
		if _page_ready(page):
			page.remove_meta("unfplap_pending")
			_inject_now(page, actions_builder, live_character_ids, participation, changed, debug)
			return
		if loop == null:
			break
		await loop.process_frame
	if is_instance_valid(page):
		page.remove_meta("unfplap_pending")
	_debug(debug, "settings tab: page internals unavailable; skipped")


static func _page_ready(page: Node) -> bool:
	if not is_instance_valid(page):
		return false
	var side_scroll: Variant = page.get("_side_scroll")
	var content: Variant = page.get("_content")
	var tabs: Variant = page.get("_tabs")
	var scroll: Variant = page.get("_scroll")
	var title: Variant = page.get("_tab_title")
	var icon: Variant = page.get("_tab_icon")
	return side_scroll is ScrollContainer and content is VBoxContainer and tabs is Array \
		and scroll is ScrollContainer and title is Label and icon is Control


## No game-script extension is used. If the page's internals are unavailable it skips rather
## than risking a release-breaking extension.
static func _inject_now(page: Node, actions_builder: Callable, live_character_ids: Callable,
		participation: Callable, changed: Callable, debug: Callable) -> void:
	if not is_instance_valid(page) or page.has_meta("unfplap_tab"):
		return
	if not _page_ready(page):
		_debug(debug, "settings tab: page internals unavailable; skipped")
		return
	if not page.has_method("_button") or not page.has_method("_redraw"):
		_debug(debug, "settings tab: page API unavailable; skipped")
		return
	var side_scroll := page.get("_side_scroll") as ScrollContainer
	var content := page.get("_content") as VBoxContainer
	var tabs: Array = page.get("_tabs")
	var title := page.get("_tab_title") as Label
	var icon := page.get("_tab_icon") as Control
	if side_scroll.get_child_count() == 0:
		_debug(debug, "settings tab: sidebar unavailable; skipped")
		return
	var side := side_scroll.get_child(0) as VBoxContainer
	if side == null:
		_debug(debug, "settings tab: sidebar layout unavailable; skipped")
		return
	var font_size := int(page.get("font_size"))
	if font_size <= 0:
		font_size = 20
	# The page captions its GROUPS sections; the injected row gets one too, so it does not float
	# under the last sidebar group.
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	side.add_child(gap)
	var caption := STYLE.label("Add-ons".to_upper(), "Faint", maxi(12, font_size - 7))
	caption.add_theme_constant_override("line_spacing", 0)
	side.add_child(caption)
	var button: Button = page.call("_button", side, "Unfplap",
		func() -> void: _show_settings_tab(page))
	button.theme_type_variation = "Tab"
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, font_size * 2.05)
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.expand_icon = false
	if page.has_method("_icon_texture"):
		button.icon = page.call("_icon_texture", "gem")
	var ui := VBoxContainer.new()
	ui.name = "UnfplapSettings"
	ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.add_theme_constant_override("separation", 10)
	ui.visible = false
	content.add_child(ui)
	# The page's title row already reads "Unfplap" with its gem icon, so the panel starts with
	# the sub-tabs instead of a second heading or intro card.
	var tabs_box := TabContainer.new()
	tabs_box.name = "UnfplapTabs"
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.add_child(tabs_box)
	var general_list := _settings_tab_list("General", tabs_box)
	_collect_debug_section(build(general_list, SETTINGS.GENERAL, font_size, page, changed,
		actions_builder))
	var anatomy_list := _settings_tab_list("Anatomy", tabs_box)
	_collect_debug_section(build(anatomy_list, SETTINGS.ANATOMY, font_size, page, changed,
		actions_builder))
	var world_list := _settings_tab_list("World", tabs_box)
	_collect_debug_section(build(world_list, SETTINGS.WORLD, font_size, page, changed,
		actions_builder))
	# Character preference is a per-mare profile form, not a global setting, so it keeps its own
	# hand-built Characters tab instead of a schema section.
	var char_list := _settings_tab_list("Characters", tabs_box)
	CHARACTERS_UI.build(char_list, font_size, live_character_ids, participation, changed, debug)
	# Supported mods and their one-switch-per-integration list; always visible, even when the
	# other mod is absent.
	var integrations_list := _settings_tab_list("Integrations", tabs_box)
	_collect_debug_section(build_integrations(integrations_list, font_size, page, changed))
	# Style the bar after it exists with its tabs: the container re-applies its theme to the
	# internal TabBar when the tree changes, which would shadow overrides set before that.
	_style_tabs(tabs_box, font_size)
	for tab: Variant in tabs:
		if tab is Button:
			(tab as Button).pressed.connect(func() -> void: _hide_settings_tab(page))
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem:
			(native_page as CanvasItem).visibility_changed.connect(
				func() -> void: _native_settings_shown(page))
	page.set_meta("unfplap_tab", true)
	page.set_meta("unfplap_ui", ui)
	page.set_meta("unfplap_button", button)
	_injected.append({"page": page, "button": button, "ui": ui, "sidebar": [gap, caption]})
	_debug(debug, "settings tab injected")


## Keep the Debug block a build returned, so `debug_mode` can show or hide it live.
static func _collect_debug_section(control: Variant) -> void:
	if control is Control:
		_debug_sections.append(control)


## Show or hide every Debug block after `debug_mode` changed.
static func refresh_debug_visibility() -> void:
	var on := SETTINGS.debug_mode.get_bool()
	for section: Variant in _debug_sections:
		if is_instance_valid(section):
			(section as Control).visible = on
	_refresh_anatomy_gates()


static func _settings_tab_list(title: String, tabs_box: TabContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs_box.add_child(scroll)
	# Room for a hovered row card's border inside the scroll's clip, as the page does for its rows.
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_left", 6)
	holder.add_theme_constant_override("margin_top", 4)
	holder.add_theme_constant_override("margin_bottom", 4)
	holder.add_theme_constant_override("margin_right", 14)
	scroll.add_child(holder)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	holder.add_child(list)
	return list


## The sub-tabs wear the page's "Segment" look: the chosen tab is a lit pill, the
## other a quiet one, and there is no tab strip or default panel behind either. The internal TabBar
## is a separate control, so its tab items are set on it directly (a theme resource would be
## inherited, but per-node overrides on the TabContainer are not).
static func _style_tabs(tabs: TabContainer, font_size: int) -> void:
	var empty := STYLE.rounded(StyleBoxEmpty.new())
	tabs.add_theme_stylebox_override("panel", empty)
	tabs.add_theme_stylebox_override("tabbar_background", empty)
	tabs.add_theme_constant_override("side_margin", 0)
	var bar := tabs.get_tab_bar()
	bar.add_theme_stylebox_override("tabbar_background", empty)
	var quiet := STYLE.rounded(STYLE.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 99, 14, 5))
	bar.add_theme_stylebox_override("tab_unselected", quiet)
	bar.add_theme_stylebox_override("tab_disabled", quiet)
	bar.add_theme_stylebox_override("tab_hovered", STYLE.rounded(STYLE.box(
		Color(1, 1, 1, 0.1), Color(STYLE.PINK, 0.5), 1, 99, 14, 5)))
	var lit := STYLE.box(STYLE.ROSE, Color(1, 1, 1, 0.55), 1, 99, 14, 5)
	lit.shadow_color = Color(STYLE.ROSE, 0.35)
	lit.shadow_size = 10
	lit.shadow_offset = Vector2(0, 2)
	bar.add_theme_stylebox_override("tab_selected", STYLE.rounded(lit))
	var ring := STYLE.box(Color.TRANSPARENT, Color(STYLE.PINK, 0.8), 2, 101)
	ring.set_expand_margin_all(2)
	bar.add_theme_stylebox_override("tab_focus", STYLE.rounded(ring))
	bar.add_theme_font_override("font", STYLE.BOLD)
	bar.add_theme_font_size_override("font_size", font_size - 3)
	bar.add_theme_color_override("font_selected_color", Color.WHITE)
	bar.add_theme_color_override("font_unselected_color", STYLE.MUTED)
	bar.add_theme_color_override("font_hovered_color", STYLE.CREAM)
	bar.add_theme_constant_override("tab_separation", 4)


static func _show_settings_tab(page: Node) -> void:
	if not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	var button: Variant = page.get_meta("unfplap_button")
	if not ui is Control or not button is Button:
		return
	_switch_guard = true
	_set_native_settings_visible(page, false)
	(ui as Control).visible = true
	var title: Variant = page.get("_tab_title")
	if title is Label:
		(title as Label).text = "Unfplap"
	var icon: Variant = page.get("_tab_icon")
	if icon is Control:
		(icon as Control).set("kind", "gem")
	var tabs: Variant = page.get("_tabs")
	if tabs is Array:
		for tab: Variant in tabs:
			if tab is Button:
				(tab as Button).set_pressed_no_signal(false)
	(button as Button).set_pressed_no_signal(true)
	page.call("_redraw")
	_switch_guard = false


static func _hide_settings_tab(page: Node) -> void:
	if _switch_guard or not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	var button: Variant = page.get_meta("unfplap_button")
	if ui is Control:
		(ui as Control).visible = false
	if button is Button:
		(button as Button).set_pressed_no_signal(false)


static func _native_settings_shown(page: Node) -> void:
	if _switch_guard or not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	if not ui is Control or not (ui as Control).visible:
		return
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem and (native_page as CanvasItem).visible:
			_hide_settings_tab(page)
			return


static func _set_native_settings_visible(page: Node, value: bool) -> void:
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem:
			(native_page as CanvasItem).visible = value


## Remove every injected tab. Called when the mod's entry node leaves the tree.
static func clear_pages() -> void:
	for entry: Dictionary in _injected:
		var page: Variant = entry.get("page")
		var ui: Variant = entry.get("ui")
		var button: Variant = entry.get("button")
		if is_instance_valid(ui) and (ui as Node).get_parent() != null:
			(ui as Node).queue_free()
		if is_instance_valid(button) and (button as Node).get_parent() != null:
			(button as Node).queue_free()
		var sidebar: Variant = entry.get("sidebar", [])
		if sidebar is Array:
			for node: Variant in sidebar:
				if is_instance_valid(node) and (node as Node).get_parent() != null:
					(node as Node).queue_free()
		if is_instance_valid(page):
			(page as Node).remove_meta("unfplap_tab")
			(page as Node).remove_meta("unfplap_ui")
			(page as Node).remove_meta("unfplap_button")
	_injected.clear()
	_debug_sections.clear()
	_anatomy_gates.clear()


static func _groups_of(settings: Array) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in settings:
		var setting := raw as SETTINGS.Setting
		if setting == null or setting.group.is_empty():
			continue
		if not out.has(setting.group):
			out.append(setting.group)
	return out


static func _settings_in(settings: Array, group: String) -> Array:
	var out: Array = []
	for raw: Variant in settings:
		var setting := raw as SETTINGS.Setting
		if setting != null and setting.group == group:
			out.append(setting)
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


static func _add_row(parent: VBoxContainer, setting: SETTINGS.Setting, font_size: int,
		page: Node, changed: Callable) -> void:
	if setting == null:
		return
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
	var label := STYLE.label(setting.label, "", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(label)
	if not setting.help.is_empty():
		var help := STYLE.label(setting.help, "Faint", font_size - 5)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(help)
	if setting is SETTINGS.FlagSetting:
		row.add_child(_check(setting as SETTINGS.FlagSetting, font_size, page, changed))
	elif setting is SETTINGS.NumSetting:
		var number := setting as SETTINGS.NumSetting
		if number.slider:
			row.add_child(_slider(number, font_size, page, changed))
		else:
			row.add_child(_spin(number, font_size, page, changed))
	elif setting is SETTINGS.ChoiceSetting:
		row.add_child(_choice(setting as SETTINGS.ChoiceSetting, font_size, page, changed))
	elif setting is SETTINGS.ColorSetting:
		row.add_child(_color(setting as SETTINGS.ColorSetting, font_size, page, changed))
	elif setting is SETTINGS.ListSetting:
		_add_list(block, setting as SETTINGS.ListSetting, font_size, page, changed)


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
static func _check(setting: SETTINGS.FlagSetting, font_size: int, page: Node,
		changed: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var state := STYLE.label("", "Muted", font_size - 2)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(state)
	var check := CheckButton.new()
	check.button_pressed = setting.get_bool()
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.set_meta("no_lift", true)
	check.toggled.connect(func(on: bool) -> void:
		state.text = "On" if on else "Off"
		_store(setting, on, page, changed))
	state.text = "On" if check.button_pressed else "Off"
	box.add_child(check)
	return box


## A colour swatch; its popup is Godot's ColorPicker with HSV/RGB sliders and the hex field.
static func _color(setting: SETTINGS.ColorSetting, font_size: int, page: Node,
		changed: Callable) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(float(font_size) * 5.0, float(font_size) * 1.6)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.edit_alpha = false
	button.color = setting.get_color()
	button.color_changed.connect(func(color: Color) -> void:
		_store(setting, color, page, changed))
	return button


static func _spin(setting: SETTINGS.NumSetting, font_size: int, page: Node,
		changed: Callable) -> SpinBox:
	var scale := setting.scale
	if is_zero_approx(scale):
		scale = 1.0
	var spin := SpinBox.new()
	spin.min_value = setting.low * scale
	spin.max_value = setting.high * scale
	spin.step = setting.step if setting.step > 0.0 else 0.01 * scale
	spin.suffix = setting.unit
	spin.add_theme_font_size_override("font_size", font_size - 2)
	spin.custom_minimum_size.x = float(font_size) * 10.0
	spin.value = setting.get_num() * scale
	spin.value_changed.connect(func(value: float) -> void:
		_store(setting, value / scale, page, changed))
	return spin


## A number as the page's own slider row: the track, then its value beside it. The stored value
## keeps the schema units; `scale` only changes what the player sees.
static func _slider(setting: SETTINGS.NumSetting, font_size: int, page: Node,
		changed: Callable) -> HBoxContainer:
	var scale := setting.scale
	if is_zero_approx(scale):
		scale = 1.0
	var unit := setting.unit
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var slider := HSlider.new()
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = setting.low * scale
	slider.max_value = setting.high * scale
	slider.step = setting.step if setting.step > 0.0 else 0.01 * scale
	slider.custom_minimum_size = Vector2(float(font_size) * 9.0, font_size * 1.6)
	slider.value = setting.get_num() * scale
	var value := STYLE.label("", "Muted", font_size - 2)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.custom_minimum_size.x = float(font_size) * 3.0
	value.text = _slider_text(slider.value, unit)
	slider.value_changed.connect(func(at: float) -> void:
		value.text = _slider_text(at, unit)
		_store(setting, at / scale, page, changed))
	box.add_child(slider)
	box.add_child(value)
	return box


static func _slider_text(value: float, unit: String) -> String:
	var rounded := roundf(value)
	var text := String.num(rounded, 0) if absf(value - rounded) < 0.001 else String.num(value, 1)
	return text + unit


## A choice: a few short values as the page's Segment pills in one track, otherwise the themed
## dropdown, which cannot overflow the row.
static func _choice(setting: SETTINGS.ChoiceSetting, font_size: int, page: Node,
		changed: Callable) -> Control:
	var texts: Array[String] = []
	for index: int in setting.options.size():
		texts.append(setting.labels[index] if index < setting.labels.size()
			else setting.options[index])
	if _pills_fit(texts, font_size, page):
		return _pills(setting, texts, font_size, page, changed)
	var option := OptionButton.new()
	for index: int in setting.options.size():
		option.add_item(texts[index])
		option.set_item_metadata(index, setting.options[index])
	var current := setting.get_choice()
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			option.select(index)
			break
	option.add_theme_font_size_override("font_size", font_size - 2)
	option.item_selected.connect(func(index: int) -> void:
		_store(setting, str(option.get_item_metadata(index)), page, changed))
	return option


## A few short choices fit side by side, measured as the page measures them: the pills, their
## padding and the track's, against the room a row's control has.
static func _pills_fit(texts: Array[String], font_size: int, page: Node) -> bool:
	if texts.size() < 2 or texts.size() > MOST_PILLS:
		return false
	for text: String in texts:
		if text.length() > PILL_LABEL_CHARS:
			return false
	var room := 0.0
	if is_instance_valid(page) and typeof(page.get("_room")) == TYPE_FLOAT:
		room = float(page.get("_room"))
	if room <= 0.0:
		return true
	var width := 10.0 + 4.0 * (texts.size() - 1)
	for text: String in texts:
		width += STYLE.BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size - 4).x + 30.0
	return width <= room


## Every value a pill in one track, the chosen one lit, one press picks another.
static func _pills(setting: SETTINGS.ChoiceSetting, texts: Array[String], font_size: int,
		page: Node, changed: Callable) -> Control:
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	var current := setting.get_choice()
	for index: int in setting.options.size():
		var pill := Button.new()
		pill.text = texts[index]
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 4)
		pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pill.button_pressed = setting.options[index] == current
		pill.pressed.connect(func() -> void:
			_choose_pill(pills, index, setting, page, changed))
		pills.add_child(pill)
	return track


static func _choose_pill(pills: HBoxContainer, index: int, setting: SETTINGS.ChoiceSetting,
		page: Node, changed: Callable) -> void:
	for at: int in pills.get_child_count():
		(pills.get_child(at) as Button).set_pressed_no_signal(at == index)
	_store(setting, setting.options[index], page, changed)


## A set of options stored as an array: one check per option, saved as the checked list.
static func _add_list(parent: VBoxContainer, setting: SETTINGS.ListSetting, font_size: int,
		page: Node, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var selected := setting.get_list()
	var checks: Dictionary = {}
	for option: String in setting.options:
		var check := CheckButton.new()
		check.text = option.capitalize()
		check.button_pressed = selected.has(option)
		check.add_theme_font_size_override("font_size", font_size - 3)
		row.add_child(check)
		checks[option] = check
	for key: String in checks:
		(checks[key] as CheckButton).toggled.connect(func(_on: bool) -> void:
			var values: Array[String] = []
			for name: String in checks:
				if (checks[name] as CheckButton).button_pressed:
					values.append(name)
			_store(setting, values, page, changed))


static func _store(setting: SETTINGS.Setting, value: Variant, page: Node,
		changed: Callable) -> void:
	setting.set_value(value)
	if changed.is_valid():
		changed.call()
	_redraw(page)


## Canvas hosts (the title screen, the pause menu) draw on demand, so an edit asks for a repaint.
static func _redraw(page: Node) -> void:
	if is_instance_valid(page) and page.has_method("_redraw"):
		page.call("_redraw")


static func _debug(callback: Callable, text: String) -> void:
	if callback.is_valid():
		callback.call(text)
