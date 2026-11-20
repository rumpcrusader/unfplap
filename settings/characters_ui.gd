extends RefCounted
## The hand-built Characters preference form, drawn with the setting rows' own card, switch and
## pill pieces so it does not read as a different panel. The entry hands it the live off-roster ids
## and a participation lookup.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const STYLE := preload("res://world/ui/menu_style.gd")
## The game's in-page dropdown. An OptionButton's popup is a bare desktop window a headset cannot
## reach, and its list runs past the settings window.
const PICKER := preload("res://world/ui/menu_picker.gd")
## Height cap of the unfolded pony list; the page scrolls the rest.
const PICKER_LIST_HEIGHT := 260.0
## The picker groups its entries on a "group/name" text, so off-roster mares share one header.
const OTHER_MARES := "Other mares"

## The tri-state preference row: one pill per state.
const PREFERENCE_STATES: Array[String] = ["dislike", "none", "like"]
const PREFERENCE_STATE_LABELS := {
	"dislike": "Dislikes",
	"none": "No preference",
	"like": "Likes",
}


## Fill the Characters tab; `changed` applies a saved preset to a live act.
static func build(list: VBoxContainer, font_size: int, live_character_ids: Callable,
		participation: Callable, changed: Callable, debug: Callable = Callable()) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	list.add_child(stack)
	var intro := STYLE.label("Saved preset changes apply live during an act.", "Faint", font_size - 5)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(intro)
	var selector: Control = PICKER.new()
	selector.placeholder = "Choose a pony"
	selector.font_size = font_size - 2
	selector.list_height = PICKER_LIST_HEIGHT
	stack.add_child(selector)
	var last_id := ""

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	stack.add_child(buttons)
	var save := Button.new()
	save.text = "Save preset"
	save.theme_type_variation = "Primary"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.add_theme_font_size_override("font_size", font_size - 2)
	buttons.add_child(save)
	var reset := Button.new()
	reset.text = "Reset to default"
	reset.theme_type_variation = "Danger"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.add_theme_font_size_override("font_size", font_size - 2)
	buttons.add_child(reset)
	var status := STYLE.label("", "Faint", font_size - 6)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(status)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 8)
	stack.add_child(form)
	var intensity := _preference_pills(form, "Intensity", PREFERENCES.INTENSITIES, font_size)
	var pattern := _preference_pills(form, "Pattern", PREFERENCES.PATTERNS, font_size)
	var warmth := _preference_pills(form, "Warmth", PREFERENCES.WARMTHS, font_size, {},
		"How fast arousal builds.")
	var tolerance := _preference_pills(form, "Neglect tolerance", PREFERENCES.TOLERANCES, font_size, {},
		"How she responds to things she dislikes.")
	var teat_size := _preference_pills(form, "Teat size", PREFERENCES.TEAT_SIZES, font_size, {},
		"Auto keeps the size picked for her. Applies the next time she appears.")
	var touch: Dictionary = {}
	for action: String in PREFERENCES.TOUCHES:
		touch[action] = _preference_pills(form, action.capitalize(), PREFERENCE_STATES, font_size,
			PREFERENCE_STATE_LABELS)
	var talk: Dictionary = {}
	for action: String in PREFERENCES.TALKS:
		var label := "Dirty talk" if action == "dirty" else action.capitalize()
		talk[action] = _preference_pills(form, label, PREFERENCE_STATES, font_size,
			PREFERENCE_STATE_LABELS)
	# integration: per-mare consent for the optional anatomy actions.
	# One row of checks, the same widget the list settings (Ignore body parts) use.
	var consent_buttons := _check_row(form, "Okay with", "consent", CONSENT.KEYS,
		CONSENT.LABELS, font_size)
	# integration: per-mare participation. A subtractive capability layer; a provider's `eligible`
	# assertion is read-only and only shown when the provider overrides it.
	var participation_buttons := _check_row(form, "Takes part in", "participation",
		PARTICIPATION.KEYS, PARTICIPATION.LABELS, font_size)
	var participation_hint := STYLE.label("", "Faint", font_size - 6)
	participation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	participation_hint.visible = false
	form.add_child(participation_hint)
	var assertion_label := _form_label("Provider assertion", font_size)
	assertion_label.visible = false
	var assertion_hint := STYLE.label("", "Faint", font_size - 6)
	assertion_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assertion_hint.visible = false
	form.add_child(assertion_label)
	form.add_child(assertion_hint)
	var notes := TextEdit.new()
	notes.custom_minimum_size = Vector2(0.0, 76.0)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_theme_font_size_override("font_size", font_size - 2)
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_form_label("Notes", font_size))
	stack.add_child(notes)

	var refs := {
		"selector": selector,
		"intensity": intensity,
		"pattern": pattern,
		"warmth": warmth,
		"tolerance": tolerance,
		"teat_size": teat_size,
		"touch": touch,
		"talk": talk,
		"notes": notes,
		"participation_hint": participation_hint,
		"assertion_label": assertion_label,
		"assertion_hint": assertion_hint,
		"status": status,
		"reset": reset,
		"refreshing": false,
		"live_character_ids": live_character_ids,
		"participation": participation,
		"changed": changed,
		"debug": debug,
	}
	refs.merge(consent_buttons)
	refs.merge(participation_buttons)
	selector.item_selected.connect(func(index: int) -> void:
		last_id = str(selector.get_item_metadata(index))
		_refresh_preference_form(refs)
		_show_selector_name(selector))
	for pills: HBoxContainer in [intensity, pattern, warmth, tolerance, teat_size]:
		for pill: Node in pills.get_children():
			(pill as Button).pressed.connect(_choose_preference_pill.bind(
				pills, str(pill.get_meta("value")), refs))
	for group: Dictionary in [touch, talk]:
		for action: String in group:
			var pills: HBoxContainer = group[action]
			for pill: Node in pills.get_children():
				(pill as Button).pressed.connect(_choose_preference_pill.bind(
					pills, str(pill.get_meta("value")), refs))
	# integration: consent edits stage with the rest of the preset.
	for button: CheckButton in consent_buttons.values():
		button.toggled.connect(func(_on: bool) -> void: _mark_preference_dirty(refs))
	for button: CheckButton in participation_buttons.values():
		button.toggled.connect(func(_on: bool) -> void: _mark_preference_dirty(refs))
	notes.text_changed.connect(func() -> void: _mark_preference_dirty(refs))
	notes.focus_exited.connect(func() -> void: _mark_preference_dirty(refs))
	save.pressed.connect(func() -> void: _save_preference_form(refs))
	reset.pressed.connect(func() -> void: _reset_preference_form(refs))
	var fill_selector := func() -> void:
		var current := _selected_preference_id(refs)
		if current.is_empty():
			current = last_id
		selector.clear()
		for id: String in SETTINGS.CHARACTER_ORDER:
			_add_character_selector_item(selector, id, current)
		var live := refs["live_character_ids"] as Callable
		if live.is_valid():
			var ids: Variant = live.call()
			if ids is Array:
				for raw: Variant in ids:
					_add_character_selector_item(selector, str(raw), current, OTHER_MARES)
		if selector.selected < 0 and selector.item_count > 0:
			selector.select(0)
		if selector.item_count == 0:
			if status is Label:
				(status as Label).text = "No pony is available."
			_update_preference_reset(refs)
		else:
			_refresh_preference_form(refs)
	fill_selector.call()


## One selector entry; the metadata carries the stable pony id, so an off-roster mare edits the
## same form. The group prefix only becomes the picker's section header.
static func _add_character_selector_item(selector: Control, id: String, current: String,
		group := "") -> void:
	var display := SETTINGS.character_name(id)
	selector.add_item(display if group.is_empty() else "%s/%s" % [group, display])
	var index := int(selector.item_count) - 1
	selector.set_item_metadata(index, id)
	if id == current:
		selector.select(index)
		_show_selector_name(selector)


## The picker's head shows the whole entry text, which carries the group prefix. Put the plain
## pony name back on the closed row.
static func _show_selector_name(selector: Control) -> void:
	var index := int(selector.selected)
	if index < 0:
		return
	var text := str(selector.get_item_text(index))
	var named := text.get_slice("/", 1) if text.contains("/") else text
	(selector.head() as Button).text = named


## A form row's name, with a setting row's type and width so the control sits at the right edge.
## It must not autowrap: in a GridContainer a wrapping label reports a one-character minimum.
static func _form_label(text: String, font_size: int) -> Label:
	var label := STYLE.label(text, "", font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## One form row of per-key checks. The refs are `<prefix>_<key>`, so the refresh and save code
## follows the shared key table instead of a copied list.
static func _check_row(form: GridContainer, label_text: String, prefix: String, keys: Array,
		labels: Dictionary, font_size: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var out: Dictionary = {}
	for key: Variant in keys:
		var name := str(key)
		var button := CheckButton.new()
		button.text = str(labels.get(name, name.capitalize()))
		button.add_theme_font_size_override("font_size", font_size - 3)
		row.add_child(button)
		out[prefix + "_" + name] = button
	form.add_child(_form_label(label_text, font_size))
	form.add_child(row)
	return out


## Short values as one track of Segment pills, the chosen one lit, with an optional hint under the
## row's name.
static func _preference_pills(parent: GridContainer, label_text: String, values: Array,
		font_size: int, pill_labels: Dictionary = {}, hint: String = "") -> HBoxContainer:
	var label_box := VBoxContainer.new()
	label_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_box.add_theme_constant_override("separation", 2)
	var label := _form_label(label_text, font_size)
	label_box.add_child(label)
	if not hint.is_empty():
		var help := STYLE.label(hint, "Faint", font_size - 6)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_box.add_child(help)
	parent.add_child(label_box)
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	parent.add_child(track)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	for value: Variant in values:
		var pill := Button.new()
		pill.text = str(pill_labels.get(str(value), str(value).capitalize()))
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 3)
		pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pill.set_meta("value", str(value))
		pills.add_child(pill)
	return pills


## One pill of a preference row picks the value for the whole row and stages the edit.
static func _choose_preference_pill(pills: HBoxContainer, value: String, refs: Dictionary) -> void:
	for pill: Node in pills.get_children():
		(pill as Button).set_pressed_no_signal(str(pill.get_meta("value")) == value)
	_mark_preference_dirty(refs)


## Set every action row's tri-state pill from the saved likes and dislikes.
static func _set_preference_actions(control: Variant, likes: Variant, values: Array,
		dislikes: Variant) -> void:
	if not control is Dictionary:
		return
	var groups: Dictionary = control
	var liked: Array = likes if likes is Array else []
	var disliked: Array = dislikes if dislikes is Array else []
	for value: Variant in values:
		var key := str(value)
		var state := "none"
		if key in liked:
			state = "like"
		elif key in disliked:
			state = "dislike"
		var pills: Variant = groups.get(key)
		if pills is HBoxContainer:
			_select_preference_value(pills, state)


static func _selected_preference_id(refs: Dictionary) -> String:
	var selector: Variant = refs.get("selector")
	if not selector is Control:
		return ""
	var picker := selector as Control
	var index := int(picker.selected)
	if index < 0:
		return ""
	return str(picker.get_item_metadata(index))


static func _refresh_preference_form(refs: Dictionary) -> void:
	var id := _selected_preference_id(refs)
	if id.is_empty():
		refs["refreshing"] = false
		return
	refs["refreshing"] = true
	var preferences := SETTINGS.preferences(id)
	_select_preference_value(refs.get("intensity"), str(preferences.get("intensity", "firm")))
	_select_preference_value(refs.get("pattern"), str(preferences.get("pattern", "steady")))
	_select_preference_value(refs.get("warmth"), str(preferences.get("warmth", "normal")))
	_select_preference_value(refs.get("tolerance"), str(preferences.get("tolerance", "normal")))
	_select_preference_value(refs.get("teat_size"), str(preferences.get("teat_size", "auto")))
	_set_preference_actions(refs.get("touch"), preferences.get("touch", []), PREFERENCES.TOUCHES,
		preferences.get("dislikes", []))
	_set_preference_actions(refs.get("talk"), preferences.get("talk", []), PREFERENCES.TALKS,
		preferences.get("dislikes", []))
	var notes: Variant = refs.get("notes")
	if notes is TextEdit:
		(notes as TextEdit).text = str(preferences.get("notes", ""))
	var consent := SETTINGS.consent(id)
	for key: String in CONSENT.KEYS:
		var button: Variant = refs.get("consent_" + key)
		if button is CheckButton:
			(button as CheckButton).set_pressed_no_signal(bool(consent.get(key, false)))
	var resolved: Dictionary = {}
	var participation := refs["participation"] as Callable
	if participation.is_valid():
		var value: Variant = participation.call(id)
		if value is Dictionary:
			resolved = value
	for key: String in PARTICIPATION.KEYS:
		var button: Variant = refs.get("participation_" + key)
		if button is CheckButton:
			(button as CheckButton).set_pressed_no_signal(bool(resolved.get(key, true)))
	var sources := SETTINGS.provider_sources(id)
	var participation_hint: Variant = refs.get("participation_hint")
	if participation_hint is Label:
		(participation_hint as Label).visible = not sources.is_empty()
		if not sources.is_empty():
			(participation_hint as Label).text = "Overridden by %s" % ", ".join(sources)
	var assertion: Variant = SETTINGS.profile_eligible(id)
	var assertion_label: Variant = refs.get("assertion_label")
	var assertion_hint: Variant = refs.get("assertion_hint")
	var show_assertion := assertion is bool
	if assertion_label is Label:
		(assertion_label as Label).visible = show_assertion
		if show_assertion:
			(assertion_label as Label).text = "Provider assertion: %s" % (
				"eligible" if assertion else "not eligible")
	if assertion_hint is Label:
		(assertion_hint as Label).visible = show_assertion
		if show_assertion:
			(assertion_hint as Label).text = "Overridden by %s" % (
				", ".join(sources) if not sources.is_empty() else "a provider")
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Editing %s" % SETTINGS.character_name(id)
	refs["refreshing"] = false
	_update_preference_reset(refs)


static func _select_preference_value(control: Variant, selected_value: String) -> void:
	if not control is HBoxContainer:
		return
	for pill: Node in (control as HBoxContainer).get_children():
		(pill as Button).set_pressed_no_signal(str(pill.get_meta("value")) == selected_value)


static func _mark_preference_dirty(refs: Dictionary) -> void:
	if bool(refs.get("refreshing", false)):
		return
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Unsaved changes"


## Disable Reset while the saved preset already matches her own character template.
static func _update_preference_reset(refs: Dictionary) -> void:
	var reset: Variant = refs.get("reset")
	if not reset is Button:
		return
	var id := _selected_preference_id(refs)
	var disabled := id.is_empty() or (
		SETTINGS.preferences_match(SETTINGS.preferences(id), SETTINGS.default_preferences(id))
		and _participation_matches(id, refs["participation"] as Callable))
	(reset as Button).disabled = disabled


static func _preference_form_values(refs: Dictionary) -> Dictionary:
	var touch: Variant = refs.get("touch")
	var talk: Variant = refs.get("talk")
	var touch_groups: Dictionary = touch if touch is Dictionary else {}
	var talk_groups: Dictionary = talk if talk is Dictionary else {}
	var touch_likes: Array = []
	var talk_likes: Array = []
	var dislikes: Array = []
	for action: String in PREFERENCES.TOUCHES:
		var state := _picked_preference_value(touch_groups.get(action), "none")
		if state == "like":
			touch_likes.append(action)
		elif state == "dislike":
			dislikes.append(action)
	for action: String in PREFERENCES.TALKS:
		var state := _picked_preference_value(talk_groups.get(action), "none")
		if state == "like":
			talk_likes.append(action)
		elif state == "dislike":
			dislikes.append(action)
	var notes: Variant = refs.get("notes")
	return {
		"intensity": _picked_preference_value(refs.get("intensity"), "firm"),
		"pattern": _picked_preference_value(refs.get("pattern"), "steady"),
		"touch": touch_likes,
		"dislikes": dislikes,
		"talk": talk_likes,
		"warmth": _picked_preference_value(refs.get("warmth"), "normal"),
		"tolerance": _picked_preference_value(refs.get("tolerance"), "normal"),
		"teat_size": _picked_preference_value(refs.get("teat_size"), "auto"),
		"notes": str((notes as TextEdit).text).strip_edges() if notes is TextEdit else "",
	}


static func _preference_consent_values(refs: Dictionary) -> Dictionary:
	var out := CONSENT.empty()
	for key: String in CONSENT.KEYS:
		var button: Variant = refs.get("consent_" + key)
		if button is CheckButton:
			out[key] = (button as CheckButton).button_pressed
	return out


static func _preference_participation_values(refs: Dictionary) -> Dictionary:
	var out := PARTICIPATION.defaults()
	for key: String in PARTICIPATION.KEYS:
		var button: Variant = refs.get("participation_" + key)
		if button is CheckButton:
			out[key] = (button as CheckButton).button_pressed
	return out


static func _participation_matches(id: String, participation: Callable) -> bool:
	var resolved := {}
	if participation.is_valid():
		var value: Variant = participation.call(id)
		if value is Dictionary:
			resolved = value
	var defaults := SETTINGS.default_participation(id)
	for key: String in PARTICIPATION.KEYS:
		if bool(resolved.get(key, true)) != bool(defaults.get(key, true)):
			return false
	return true


static func _save_preference_form(refs: Dictionary) -> void:
	if bool(refs.get("refreshing", false)):
		return
	var id := _selected_preference_id(refs)
	if id.is_empty():
		return
	var preferences := _preference_form_values(refs)
	# A preset identical to her own character default needs no saved override.
	if SETTINGS.preferences_match(preferences, SETTINGS.default_preferences(id)):
		SETTINGS.reset_preferences(id)
	else:
		SETTINGS.save_preferences(id, preferences)
	SETTINGS.save_consent(id, _preference_consent_values(refs))
	SETTINGS.save_participation(id, _preference_participation_values(refs))
	var changed := refs["changed"] as Callable
	if changed.is_valid():
		changed.call()
	_refresh_preference_form(refs)
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Saved %s" % SETTINGS.character_name(id)
	_debug(refs, "preference saved id=%s" % id)


static func _reset_preference_form(refs: Dictionary) -> void:
	var id := _selected_preference_id(refs)
	if id.is_empty():
		return
	SETTINGS.reset_preferences(id)
	SETTINGS.reset_participation(id)
	_refresh_preference_form(refs)
	var changed := refs["changed"] as Callable
	if changed.is_valid():
		changed.call()
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Reset %s to its character default" % SETTINGS.character_name(id)
	_debug(refs, "preference reset id=%s" % id)


## The lit pill of a preference choice row, or the fallback when the row is not built yet.
static func _picked_preference_value(control: Variant, fallback: String) -> String:
	if not control is HBoxContainer:
		return fallback
	for pill: Node in (control as HBoxContainer).get_children():
		if (pill as Button).button_pressed:
			return str(pill.get_meta("value"))
	return fallback


static func _debug(refs: Dictionary, text: String) -> void:
	var callback := refs["debug"] as Callable
	if callback.is_valid():
		callback.call(text)
