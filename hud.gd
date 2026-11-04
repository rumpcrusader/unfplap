extends CanvasLayer
## Desktop HUD: prompt and a bottom-left controls/cue list.
## Buttons and words follow the game's own prompt row (world/ui/interaction_hints.gd): a cartoon
## key cap or controller icon beside light words with a dark outline, never a drop shadow.

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const READINESS_BAR := preload("res://mods/unfplap/readiness_bar.gd")
const ICON_PATH := "res://world/ui/prompts/%s.png"
## The offer words are the mod's pink accent, like the readiness fill.
const ACCENT := Color("ffa8c7")
## Prompt-row colours: ink words, a near-black outline, and muted words for modifiers.
const INK := Color("f4f1ff")
const SHADE := Color("1a1624")
const MUTED := Color(0.957, 0.945, 1.0, 0.6)
## Drawn caps match prompts/key_*.png: a dark cap, a pale edge and a light letter.
const CAP_BG := Color("1f1d26")
const CAP_EDGE := Color("9a97a8")
const KEYCAP_SIZE := Vector2(32.0, 28.0)
const ICON_EDGE := 28.0
## The game's carry card puts "Tap"/"Hold" in its own muted column.
const MODE_WIDTH := 38.0
## Center prompt: the game's prompt-row scale (52 px icon, 30 px words, 10 px outline).
const PROMPT_ICON_EDGE := 52.0
const PROMPT_FONT := 30
const PROMPT_OUTLINE := 10

var _prompt: CenterContainer
var _prompt_row: HBoxContainer
var _prompt_key := ""
var _hint: VBoxContainer
var _hint_title: Label
var _hint_status: Label
var _hint_readiness: Label
var _hint_gap: Control
var _readiness_bar: Control
var _y_label: Label
var _control_rows := {}


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "UnfplapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_prompt = CenterContainer.new()
	_prompt.name = "Prompt"
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -260.0
	_prompt.offset_top = -170.0
	_prompt.offset_right = 260.0
	_prompt.offset_bottom = -110.0
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	root.add_child(_prompt)

	_hint = VBoxContainer.new()
	_hint.name = "Hint"
	_hint.anchor_left = 0.0
	_hint.anchor_top = 1.0
	_hint.anchor_right = 0.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 28.0
	_hint.offset_top = -560.0
	_hint.offset_right = 620.0
	_hint.offset_bottom = -26.0
	_hint.add_theme_constant_override("separation", 6)
	_hint.alignment = BoxContainer.ALIGNMENT_END
	_hint.visible = false
	root.add_child(_hint)
	_hint_status = text_label("", 16)
	_hint_status.name = "HintStatus"
	_hint_status.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_status.visible = false
	_hint.add_child(_hint_status)
	_hint_readiness = text_label("", 14, MUTED, 4)
	_hint_readiness.name = "HintReadiness"
	_hint_readiness.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_readiness.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# The carry card names its mode above the rows.
	_hint_title = text_label("MAKE LOVE", 14, MUTED, 4)
	_hint_title.name = "HintTitle"
	_hint_title.visible = false
	_hint.add_child(_hint_title)
	_build_controls()
	# Cue line, readiness text, bar, then the separator, then the control card.
	_hint.move_child(_hint_status, 0)
	_hint.move_child(_hint_readiness, 1)
	_hint.move_child(_readiness_bar, 2)
	_hint.move_child(_hint_gap, 3)
	_hint.move_child(_hint_title, 4)


## Words in the game's prompt style: light ink, dark outline, no shadow.
static func text_label(text: String, size: int, colour := INK, outline := 5) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", SHADE)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A drawn key cap for a key the game has no icon for, like the G of "G · Carry".
static func keycap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = KEYCAP_SIZE
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CAP_BG
	style.border_color = CAP_EDGE
	style.set_border_width_all(2)
	style.border_width_bottom = 4
	style.set_corner_radius_all(7)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	cap.add_theme_stylebox_override("panel", style)
	var letter := text_label(key, 15, INK, 4)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(letter)
	return cap


## The game's own prompt icon (prompts/<name>.png), or null when it is missing.
static func button_icon(icon_name: String, edge: float) -> TextureRect:
	if icon_name.is_empty():
		return null
	var path := ICON_PATH % icon_name
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(edge, edge)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## One "icon + words" unit at the game's prompt-row scale, for the row under the crosshair.
## The action carries the mod's pink accent so the offer reads first.
static func prompt_row(icon_name: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := button_icon(icon_name, PROMPT_ICON_EDGE)
	if icon != null:
		row.add_child(icon)
	var label := text_label(text, PROMPT_FONT, ACCENT, PROMPT_OUTLINE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


## One row per control: a key cap/controller icon, a muted modifier column, and one description.
## Built once; only the Y row and the status line change with act state.
func _build_controls() -> void:
	_add_hint_row("thrust", "", "↕", "", "Thrust")
	_add_hint_row("forward", "", "W", "", "Lean forward")
	_add_hint_row("back", "", "S", "", "Lean back")
	_add_hint_row("left", "key_q", "Q", "", "Lean left · kiss / reach")
	_add_hint_row("right", "key_e", "E", "", "Lean right · reach")
	_add_hint_row("caress_left", "", "A", "", "Caress left")
	_add_hint_row("caress_right", "", "D", "", "Caress right")
	_add_hint_row("caress_move_left", "", "Z", "", "Caress movement left")
	_add_hint_row("caress_move_right", "key_c", "C", "", "Caress movement right")
	_add_hint_row("kiss", "key_f", "F", "Hold", "Kiss at full lean")
	_add_hint_row("smack", "mouse_right", "", "", "Smack flank")
	_y_label = _add_hint_row("y", "button_y", "Y", "Hold", "")


func _add_hint_row(key: String, icon_name: String, key_text: String, mode: String, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := button_icon(icon_name, ICON_EDGE)
	if icon != null:
		row.add_child(icon)
	else:
		row.add_child(keycap(key_text))
	var modifier := text_label(mode, 13, MUTED, 4)
	modifier.custom_minimum_size.x = MODE_WIDTH
	modifier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(modifier)
	var label := text_label(text, 17)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_hint.add_child(row)
	_control_rows[key] = row
	return label


func show_prompt(text: String, icon_name := "button_y") -> void:
	if _prompt == null:
		return
	var key := icon_name + "\u0000" + text
	if key != _prompt_key:
		_prompt_key = key
		if is_instance_valid(_prompt_row):
			_prompt.remove_child(_prompt_row)
			_prompt_row.queue_free()
		_prompt_row = prompt_row(icon_name, text)
		_prompt.add_child(_prompt_row)
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
	if _hint_title != null:
		_hint_title.visible = false
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
	if _hint_title != null:
		_hint_title.visible = _hint.visible
	if _y_label != null:
		var y_text := ""
		if state == STATE_ACTIVE:
			y_text = "Afterglow" if climaxes > 0 else "Stop"
		elif state == STATE_CLIMAX:
			y_text = "Afterglow"
		elif state == STATE_AFTERGLOW:
			y_text = "Exit"
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
## afterglow keeps only Y; standing afterglow keeps lean, reach, caress, kiss and Y.
func _apply_control_visibility(state: int, runtime: Node) -> void:
	var standing := str(runtime.get("pose_id")) == CATALOG.STANDING
	var afterglow := state == STATE_AFTERGLOW
	for key: String in _control_rows:
		var control := _control_rows[key] as Control
		if control == null:
			continue
		var show := true
		if afterglow:
			if standing:
				show = key in ["forward", "back", "left", "right", "caress_left",
					"caress_right", "caress_move_left", "caress_move_right", "kiss", "y"]
			else:
				show = key == "y"
		elif state == STATE_CLIMAX:
			show = true
		control.visible = show
