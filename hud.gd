extends CanvasLayer
## Desktop HUD: prompt and a bottom-left controls/cue list.
## Buttons and words follow the game's own prompt row (world/ui/interaction_hints.gd): a cartoon
## key cap or controller icon beside light words with a dark outline, never a drop shadow.

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const ICON_PATH := "res://world/ui/prompts/%s.png"
## The offer words are the mod's pink accent, like the control card's earned-caress `End`.
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
var _hint_status: Label
var _hint_readiness: Label
var _hint_auto: Label
var _hint_gap: Control
var _controls: VBoxContainer
var _y_label: Label
var _thrust_label: Label
var _finish_label: Label
var _auto_label: Label
var _control_rows := {}
var _toast_label: Label
var _toast_serial := 0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "UnfplapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# integration: transient anatomy action feedback.
	_toast_label = text_label("", 16)
	_toast_label.name = "Toast"
	_toast_label.position = Vector2(28.0, 26.0)
	_toast_label.visible = false
	root.add_child(_toast_label)

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
	_hint_auto = text_label("", 14, MUTED, 4)
	_hint_auto.name = "HintAuto"
	_hint_auto.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_auto.visible = false
	_hint.add_child(_hint_auto)
	_hint_gap = Control.new()
	_hint_gap.custom_minimum_size.y = 10.0
	_hint_gap.visible = false
	_hint.add_child(_hint_gap)
	_controls = VBoxContainer.new()
	_controls.name = "Controls"
	_controls.add_theme_constant_override("separation", 6)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.visible = false
	_hint.add_child(_controls)
	_build_controls()
	# Cue line, readiness text, auto readout, then the separator, then the control rows.
	_hint.move_child(_hint_status, 0)
	_hint.move_child(_hint_readiness, 1)
	_hint.move_child(_hint_auto, 2)
	_hint.move_child(_hint_gap, 3)


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
	cap.custom_minimum_size = Vector2(
		maxf(KEYCAP_SIZE.x, 20.0 + 8.0 * float(key.length())), KEYCAP_SIZE.y)
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


## One row per control: its key caps/icons, a muted modifier column, and one description.
## Built once; the thrust, auto and Y rows change with act state.
func _build_controls() -> void:
	_thrust_label = _add_hint_row("thrust", [{"cap": "↕"}], "", "Thrust")
	_auto_label = _add_hint_row("auto", [{"cap": "X"}], "", "Switch to auto")
	_add_hint_row("lean", [{"cap": "W"}, {"cap": "S"}], "", "Lean")
	_add_hint_row("reach", [{"cap": "Q"}, {"cap": "E"}], "", "Reach")
	_add_hint_row("caress", [{"cap": "A"}, {"cap": "D"}], "", "Caress")
	_add_hint_row("caress_move", [{"cap": "Z"}, {"cap": "C"}], "",
		"Caress movement")
	_add_hint_row("kiss", [{"cap": "F"}], "Hold", "Kiss")
	_add_hint_row("smack", [{"cap": "RMB"}], "", "Smack")
	_y_label = _add_hint_row("y", [{"cap": "Y"}], "Hold", "")
	# integration: anatomy rows; hidden unless their feature and state allow them.
	_add_hint_row("anatomy_hole", [{"cap": "V"}], "", "Switch hole")
	_add_hint_row("anatomy_oral", [{"cap": "N"}], "", "Oral")
	_finish_label = _add_hint_row("anatomy_finish", [{"cap": "B"}], "", "Finish: in")


func _add_hint_row(key: String, keys: Array, mode: String, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in keys:
		var icon := button_icon(str(entry.get("icon", "")), ICON_EDGE)
		if icon != null:
			row.add_child(icon)
		else:
			row.add_child(keycap(str(entry.get("cap", ""))))
	var modifier := text_label(mode, 13, MUTED, 4)
	if not mode.is_empty():
		modifier.custom_minimum_size.x = MODE_WIDTH
		modifier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(modifier)
	var label := text_label(text, 17)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_controls.add_child(row)
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
	if _hint_status != null:
		_hint_status.visible = false
	if _hint_readiness != null:
		_hint_readiness.visible = false
	if _hint_auto != null:
		_hint_auto.visible = false
	if _hint_gap != null:
		_hint_gap.visible = false
	if _controls != null:
		_controls.visible = false
		_controls.modulate.a = 1.0


func hide_all() -> void:
	hide_prompt()
	hide_act()


## integration: short anatomy status line in the corner.
func toast(text: String, seconds := 2.0) -> void:
	if _toast_label == null:
		return
	_toast_serial += 1
	var serial := _toast_serial
	_toast_label.text = text
	_toast_label.visible = not text.is_empty()
	if text.is_empty() or seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree():
		return
	if is_instance_valid(_toast_label) and serial == _toast_serial:
		_toast_label.visible = false
		_toast_label.text = ""


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
			y_text = "End" if climaxes > 0 else "End early"
		elif state in [STATE_CLIMAX, STATE_AFTERGLOW]:
			y_text = "End"
		_y_label.text = y_text
		var pink := 0.0
		if y_text == "End" and runtime.has_method("hud_y_pink"):
			pink = clampf(float(runtime.call("hud_y_pink")), 0.0, 1.0)
		_y_label.add_theme_color_override("font_color", INK.lerp(ACCENT, pink))

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
	var auto_text := ""
	if _hint.visible and runtime.has_method("auto_hud_text"):
		auto_text = str(runtime.call("auto_hud_text"))
	_hint_auto.text = auto_text
	_hint_auto.visible = not auto_text.is_empty()
	var auto_on := false
	if runtime.has_method("auto_active"):
		auto_on = bool(runtime.call("auto_active"))
	if _thrust_label != null:
		_thrust_label.text = "Max depth" if auto_on else "Thrust"
	if _auto_label != null:
		_auto_label.text = "Switch to manual" if auto_on else "Switch to auto"
	var finish_out := false
	if runtime.has_method("anatomy_finish_pull_out"):
		finish_out = bool(runtime.call("anatomy_finish_pull_out"))
	if _finish_label != null:
		_finish_label.text = "Finish: out" if finish_out else "Finish: in"


## The act setting that shows or hides the control card. The cue and readiness line are
## separate.
func _controls_hints_on(runtime: Node) -> bool:
	return not runtime.has_method("hud_controls") or bool(runtime.call("hud_controls"))


## Afterglow is mostly passive: hide controls that cannot do anything in that state. Missionary
## afterglow keeps only Y; standing afterglow keeps lean, reach, caress, kiss and Y.
func _apply_control_visibility(state: int, runtime: Node) -> void:
	var hints_on := _controls_hints_on(runtime)
	if _controls != null:
		_controls.visible = hints_on and _hint.visible
	if _hint_gap != null:
		_hint_gap.visible = hints_on and _hint.visible
	var standing := str(runtime.get("pose_id")) == CATALOG.STANDING
	var afterglow := state == STATE_AFTERGLOW
	for key: String in _control_rows:
		var control := _control_rows[key] as Control
		if control == null:
			continue
		var show := true
		if afterglow:
			if standing:
				show = key in ["lean", "reach", "caress", "caress_move", "kiss", "y"]
			else:
				show = key == "y"
		elif state == STATE_CLIMAX:
			show = true
		# integration: anatomy rows exist only while their feature is live.
		if key in ["anatomy_hole", "anatomy_oral", "anatomy_finish"]:
			show = _extra_row_visible(key, state, standing, runtime)
		control.visible = show


func _extra_row_visible(key: String, state: int, standing: bool, runtime: Node) -> bool:
	if state == STATE_AFTERGLOW:
		return false
	# integration: use the runtime's precise readiness so missing anatomy assets hide the rows.
	match key:
		"anatomy_hole":
			return runtime.has_method("anatomy_hole_ready") and bool(runtime.call("anatomy_hole_ready"))
		"anatomy_oral":
			return runtime.has_method("anatomy_oral_ready") and bool(runtime.call("anatomy_oral_ready"))
		"anatomy_finish":
			return runtime.has_method("anatomy_finish_ready") and bool(runtime.call("anatomy_finish_ready"))
	return false
