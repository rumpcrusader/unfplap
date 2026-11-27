extends CanvasLayer
## Scope: world
## Desktop HUD: the idle offer's hint, the centred prompt a headset uses instead, and a bottom-left
## controls/cue list.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")
const GAME := preload("res://mods/unfplap/hud/game.gd")

const STATE_IDLE := ACT_STATE.State.IDLE
const STATE_POSING_IN := ACT_STATE.State.POSING_IN
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW
const STATE_RESTORE := ACT_STATE.State.RESTORE
const ICON_PATH := "res://world/ui/prompts/%s.png"
## The game's own speech caption; the entry forwards every one to `caption_node()`.
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0
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
## The key of the mod's own stack inside the corner card.
const CARD_SECTION := "unfplap"
## A delta that finishes the card's own fade at once, for a hint no longer wanted this frame.
const CARD_HIDE_DELTA := 1.0

var _prompt: CenterContainer
var _prompt_row: HBoxContainer
var _prompt_key := ""
var _hint: VBoxContainer
var _hint_status: Label
var _hint_readiness: Label
var _hint_form: Label
var _hint_auto: Label
var _hint_gap: Control
var _controls: VBoxContainer
var _act_key := "6"
var _y_label: Label
var _auto_label: Label
var _control_rows := {}
## Hold-X layer rows, shown instead of the normal card while the auto settings are open.
var _layer_rows := {}
var _layer_labels := {}
## The game's corner card and the line the mod puts on it: the words last applied and their cap.
var _card: GAME.Card
var _card_text := ""
var _card_key := ""
var _card_rows: Array = []
var _toast_label: Label
var _toast_serial := 0
## The toast's own hide timer. A tree timer would outlive the HUD that armed it.
var _toast_timer: Timer = null
## instance id -> WeakRef for every SpeechCaption the mod may move to the top.
var _captions: Dictionary = {}
## Cached captions_on_top so the per-frame caption tick never rereads settings.json.
var _captions_on_top := false
## The live act state the entry last reported, so a caption that appears mid-act is placed.
var _act_state := STATE_IDLE
## The one "Dance Mod uses Y" note is shown once per world.
var _dance_hint_shown := false
## The act borrowed the game's quick-slot card: what it found, so it can be put back.
var _inventory_hidden := false
var _inventory_hud_saved := false
var _inventory_hotbar_visible := true
var _inventory_hud_layer_visible := true


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
	# The form-change invitation uses the existing talk channel, never a new key. Kept empty in the
	# card so the row order never shifts; the reveal and the gift stay a discovery, never a label.
	_hint_form = text_label("", 15, ACCENT, 5)
	_hint_form.name = "HintForm"
	_hint_form.custom_minimum_size = Vector2(580.0, 0.0)
	_hint_form.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_form.visible = false
	_hint.add_child(_hint_form)
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
	# Cue line, readiness text, form hint, auto readout, then the separator, then the control rows.
	_hint.move_child(_hint_status, 0)
	_hint.move_child(_hint_readiness, 1)
	_hint.move_child(_hint_form, 2)
	_hint.move_child(_hint_auto, 3)
	_hint.move_child(_hint_gap, 4)
	# The HUD reacts to the settings service's game channel, never the autoload: only the speech
	# setting concerns the caption move.
	CHANGE.on_game_changed(Callable(self, "_on_game_setting_changed"))
	CHANGE.on_changed(Callable(self, "apply_settings"))
	apply_settings()


func _exit_tree() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))
	CHANGE.off_game_changed(Callable(self, "_on_game_setting_changed"))


## Refresh the two settings the HUD caches.
func apply_settings() -> void:
	set_act_key(_act_key_label())
	_apply_caption_top()


func on_world(_host: Node) -> void:
	_dance_hint_shown = false
	hide_all()


func on_world_closed() -> void:
	hide_all()


## The player exists: one key note per world. The act key is the one control the player has to
## find before the act, and the bundled Dance Mod already owns `Y` in the same world.
func on_player(_body: Node) -> void:
	if _dance_hint_shown:
		return
	_dance_hint_shown = true
	if int(SETTINGS.act_key.get_num()) == KEY_Y or not _dance_mod_active():
		return
	_show_toast("Dance Mod uses Y; %s starts the act." % _act_key_label(), 5.0)


## The `CanvasLayer` is the entry's one non-base service; the base's fourth no-op lives here.
func shutdown() -> void:
	pass


## Every `SpeechCaption` the game builds, tracked so the act can move it to the top.
func caption_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_captions[node.get_instance_id()] = weakref(node)
	_caption_top_tick()


## One frame of the caption move, with the live act state from the entry.
## The entry's process priority keeps this after the caption's own `_process`.
func caption_tick(act_state: int) -> void:
	_act_state = act_state
	_caption_top_tick()


## Show one toast line; a caller without a live HUD never calls this.
func toast(text: String, seconds := 4.0) -> void:
	if text.is_empty():
		return
	WORLD.menu().show_toast(self, text, seconds)


## integration: the anatomy status line, two seconds unless the caller says otherwise. An
## out-of-tree HUD has no toast line, so the act's own debug logger carries it.
func anatomy_status(text: String, seconds := 2.0) -> void:
	if is_inside_tree():
		WORLD.menu().show_toast(self, text, seconds)
	else:
		LOG.debug(text)


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


## A drawn key cap for a key the game has no icon for, like the G of "G · Carry". `scale` enlarges
## the whole cap for the 52 px prompt row.
static func keycap(key: String, scale := 1.0) -> PanelContainer:
	var size := maxf(scale, 0.1)
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(
		maxf(KEYCAP_SIZE.x, 20.0 + 8.0 * float(key.length())) * size, KEYCAP_SIZE.y * size)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CAP_BG
	style.border_color = CAP_EDGE
	style.set_border_width_all(maxi(1, roundi(2.0 * size)))
	style.border_width_bottom = maxi(2, roundi(4.0 * size))
	style.set_corner_radius_all(maxi(2, roundi(7.0 * size)))
	style.content_margin_left = 4.0 * size
	style.content_margin_right = 4.0 * size
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	cap.add_theme_stylebox_override("panel", style)
	var letter := text_label(key, maxi(10, roundi(15.0 * size)), INK, maxi(2, roundi(4.0 * size)))
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


## One icon-plus-words unit for the prompt row under the crosshair.
## The pink accent makes the offer read first; `cap` draws a key cap without an icon.
static func prompt_row(icon_name: String, text: String, cap := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := button_icon(icon_name, PROMPT_ICON_EDGE)
	if icon != null:
		row.add_child(icon)
	elif not cap.is_empty():
		row.add_child(keycap(cap, PROMPT_ICON_EDGE / KEYCAP_SIZE.y))
	var label := text_label(text, PROMPT_FONT, ACCENT, PROMPT_OUTLINE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


## One row per control: its key caps/icons, a muted modifier column, and one description.
## Built once; the thrust, auto and act-key rows change with act state.
func _build_controls() -> void:
	_add_hint_row("thrust", [{"cap": "↕"}], "", "Thrust")
	_auto_label = _add_hint_row("auto", [{"cap": "X"}], "", "Switch to auto")
	# The hold layer is auto-only, so this hint sits right under the toggle and hides with it.
	_add_hint_row("auto_settings", [{"cap": "X"}], "Hold", "Auto settings")
	_add_hint_row("lean", [{"cap": "W"}, {"cap": "S"}], "", "Lean")
	_add_hint_row("reach", [{"cap": "Q"}, {"cap": "E"}], "", "Reach")
	_add_hint_row("caress", [{"cap": "A"}, {"cap": "D"}], "", "Caress")
	_add_hint_row("caress_move", [{"cap": "Z"}, {"cap": "C"}], "",
		"Caress movement")
	_add_hint_row("kiss", [{"cap": "F"}], "Hold", "Kiss")
	_add_hint_row("smack", [{"cap": "RMB"}, {"cap": "G"}], "", "Smack")
	# integration: anatomy rows; hidden unless their feature and state allow them.
	_add_hint_row("anatomy_hole", [{"cap": "V"}], "", "Switch hole")
	_add_hint_row("anatomy_oral", [{"cap": "N"}], "", "Oral")
	# The act key is the context control, so it stays at the bottom of the card.
	_y_label = _add_hint_row("y", [{"cap": _act_key}], "Hold", "")
	# Hold-X auto settings. Built here so the card swaps in place; hidden until the layer opens.
	var layer_text := {
		"layer_head": "Auto settings",
		"min": "Min depth",
		"max": "Max depth",
		"pace": "Pace",
		"shape": "Shape",
	}
	var layer_keys := {
		"layer_head": [{"cap": "X"}],
		"min": [{"cap": "Q"}, {"cap": "A"}],
		"max": [{"cap": "W"}, {"cap": "S"}],
		"pace": [{"cap": "E"}, {"cap": "D"}],
		"shape": [{"cap": "Z"}],
	}
	for key: String in ["layer_head", "min", "max", "pace", "shape"]:
		var mode := "Hold" if key == "layer_head" else ""
		var label := _add_hint_row("layer_" + key, layer_keys[key], mode, str(layer_text[key]))
		_layer_labels[key] = label
		var row := _control_rows.get("layer_" + key) as Control
		_control_rows.erase("layer_" + key)
		_layer_rows[key] = row
		if row != null:
			row.visible = false


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
	if not mode.is_empty():
		var modifier := text_label(mode, 13, MUTED, 4)
		modifier.custom_minimum_size.x = MODE_WIDTH
		modifier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(modifier)
	var label := text_label(text, 17)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_controls.add_child(row)
	_control_rows[key] = row
	return label


func show_prompt(text: String, icon_name := "button_y", cap := "") -> void:
	if _prompt == null:
		return
	var key := icon_name + "\u001f" + cap + "\u001f" + text
	if key != _prompt_key:
		_prompt_key = key
		if is_instance_valid(_prompt_row):
			_prompt.remove_child(_prompt_row)
			_prompt_row.queue_free()
		_prompt_row = prompt_row(icon_name, text, cap)
		_prompt.add_child(_prompt_row)
	_prompt.visible = true


## Swap the act-key row's cap without rebuilding the card when the setting changes.
func set_act_key(label: String) -> void:
	var text := label if not label.is_empty() else "6"
	if text == _act_key:
		return
	_act_key = text
	var row := _control_rows.get("y") as HBoxContainer
	if row == null or row.get_child_count() == 0:
		return
	var old := row.get_child(0)
	row.remove_child(old)
	old.queue_free()
	var cap := keycap(text)
	row.add_child(cap)
	row.move_child(cap, 0)


func hide_prompt() -> void:
	if _prompt != null:
		_prompt.visible = false


## The idle offer's hint, drawn as one line of the game's corner card: the act key's cap and the
## words, or the words alone for a blocked offer. Empty words fade the line away; a headset has no
## card and gets the centred prompt. The card is told the same words every frame so it can fade, so
## a steady frame builds nothing.
func offer_hint(text: String, key_label: String, delta: float) -> void:
	if WORLD.headset_view():
		_card_off(CARD_HIDE_DELTA)
		if text.is_empty():
			hide_prompt()
		else:
			show_prompt(text, "", key_label)
		return
	if _prompt != null and _prompt.visible:
		hide_prompt()
	if text.is_empty() and _card_text.is_empty() and not _has_card():
		return
	if not _has_card():
		_card = GAME.control_card(self)
		if not _has_card():
			return
	if text != _card_text or key_label != _card_key:
		_card_text = text
		_card_key = key_label
		_card_rows = [[key_label, "", text]] if not key_label.is_empty() else [["", "", text]]
	_card.section(CARD_SECTION, not text.is_empty(), _card_rows, delta)


## Fade the card's line away at once, for a view that shows its hint elsewhere.
func _card_off(delta: float) -> void:
	if not _has_card() or _card_text.is_empty():
		return
	_card_text = ""
	_card.section(CARD_SECTION, false, _card_rows, delta)


func _has_card() -> bool:
	return _card != null and _card.valid()


func show_act(view: RefCounted) -> void:
	_hint.visible = true
	update_from(view)


func hide_act() -> void:
	if _hint != null:
		_hint.visible = false
	if _hint_status != null:
		_hint_status.visible = false
	if _hint_readiness != null:
		_hint_readiness.visible = false
	if _hint_form != null:
		_hint_form.visible = false
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
	offer_hint("", "", CARD_HIDE_DELTA)


## integration: short anatomy status line in the corner. The public sink is `toast()`.
func _show_toast(text: String, seconds := 2.0) -> void:
	if _toast_label == null:
		return
	_toast_serial += 1
	_toast_label.text = text
	_toast_label.visible = not text.is_empty()
	if text.is_empty() or seconds <= 0.0:
		return
	if _toast_timer == null:
		_toast_timer = Timer.new()
		_toast_timer.one_shot = true
		_toast_timer.timeout.connect(_hide_toast)
		add_child(_toast_timer)
	_toast_timer.wait_time = maxf(seconds, 0.001)
	_toast_timer.start()


func _hide_toast() -> void:
	if is_instance_valid(_toast_label):
		_toast_label.visible = false
		_toast_label.text = ""


func set_state(_kind: String) -> void:
	if _hint == null:
		return


## True only for an act and the explicit bottom-caption mode.
## "Over the head" and "auto" are left alone; afterglow returns to the bottom.
func _caption_top_enabled() -> bool:
	if not _captions_on_top:
		return false
	if _act_state not in [STATE_POSING_IN, STATE_ACTIVE, STATE_CLIMAX]:
		return false
	return SETTINGS.caption_mode() == "caption"


## Move the game's caption card after its own layout pass. The stock caption keeps its text,
## wrapping, roll and fade; only its y position changes. The settings-page preview is skipped.
func _caption_top_tick() -> void:
	if not _caption_top_enabled():
		return
	for id: int in _captions.keys():
		var ref: Variant = _captions[id]
		var node: Variant = ref.get_ref() if ref is WeakRef else null
		if not is_instance_valid(node):
			_captions.erase(id)
			continue
		if GAME.caption_preview(node):
			continue
		var card := GAME.caption_card(node)
		if card == null:
			continue
		GAME.place_caption(card, CAPTION_TOP_MARGIN, GAME.caption_scale(node))


## Re-read the mode the player chose, then place the captions it allows.
func _apply_caption_top() -> void:
	if not is_inside_tree():
		return
	_captions_on_top = SETTINGS.captions_on_top.get_bool()
	_caption_top_tick()


func _on_game_setting_changed(key: String) -> void:
	if key == "access/speech_text":
		_apply_caption_top()


## The act key's cap text.
func _act_key_label() -> String:
	return ACT_KEYS.label(int(SETTINGS.act_key.get_num()))


## True while the bundled Dance Mod is on. It is another pack, so the game's mods host answers;
## the host is looked up rather than assumed.
func _dance_mod_active() -> bool:
	return WORLD.mods().active("dance_mod")


## The auto shape's display label, from the raw generator value in the act view.
func _auto_shape_label(value: String) -> String:
	var index := SETTINGS.curve.options.find(value)
	if index >= 0 and index < SETTINGS.curve.labels.size():
		return str(SETTINGS.curve.labels[index])
	return value


## Refresh the card from the typed act view.
## The view carries every value, so nothing is probed on the runtime.
func update_from(view: RefCounted) -> void:
	if _hint == null or view == null:
		return
	var state := int(view.state)
	var climaxes := int(view.pony_climaxes)
	var readouts := bool(view.hud_readouts)
	var shape_label := _auto_shape_label(str(view.auto_shape))
	_hint.visible = state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]
	_apply_control_visibility(state, view)
	if _y_label != null:
		var y_text := ""
		if state == STATE_ACTIVE:
			y_text = "End" if climaxes > 0 else "End early"
		elif state in [STATE_CLIMAX, STATE_AFTERGLOW]:
			y_text = "End"
		_y_label.text = y_text
		var pink := 0.0
		if y_text == "End":
			pink = clampf(HUD_LINES.y_pink_for(view), 0.0, 1.0)
		_y_label.add_theme_color_override("font_color", INK.lerp(ACCENT, pink))

	var line := ""
	if _hint.visible:
		line = HUD_LINES.cue_line_for(view, readouts)
	_hint_status.text = line
	_hint_status.visible = not line.is_empty()
	var readiness_line := ""
	if _hint.visible:
		readiness_line = HUD_LINES.readiness_line_for(view, readouts)
	_hint_readiness.text = readiness_line
	_hint_readiness.visible = not readiness_line.is_empty()
	var form_text := ""
	if _hint.visible:
		form_text = str(view.form_hint)
	_hint_form.text = form_text
	_hint_form.visible = not form_text.is_empty()
	var auto_text := ""
	if _hint.visible and bool(view.auto_on):
		auto_text = HUD_LINES.auto_text_for(view, shape_label)
	_hint_auto.text = auto_text
	_hint_auto.visible = not auto_text.is_empty()
	if _auto_label != null:
		_auto_label.text = "Switch to manual" if bool(view.auto_on) else "Switch to auto"
	if bool(view.auto_layer_open):
		for kind: String in ["min", "max", "pace", "shape"]:
			var label := _layer_labels.get(kind) as Label
			if label != null:
				label.text = HUD_LINES.auto_panel_label(kind, float(view.auto_min_depth),
					float(view.auto_max_depth), float(view.auto_pace), shape_label)


## Hide or restore the game's quick-slot card for the act. Idempotent, and it gives back exactly
## the state it found, so a start that failed early runs the same call.
func set_inventory_hidden(hidden: bool) -> void:
	var briefcase := WORLD.inventory()
	var bar: Variant = briefcase.hotbar()
	if hidden:
		if _inventory_hidden:
			return
		_inventory_hidden = true
		_inventory_hud_saved = briefcase.hud_hidden()
		briefcase.set_hud_hidden(true)
		if is_instance_valid(bar):
			_inventory_hotbar_visible = briefcase.hotbar_visible(bar)
			var layer: CanvasLayer = briefcase.hotbar_layer(bar)
			if layer != null:
				_inventory_hud_layer_visible = layer.visible
			briefcase.set_hotbar_layer_visible(bar, false)
			briefcase.set_hotbar_visible(bar, false)
		return
	if not _inventory_hidden:
		return
	briefcase.set_hud_hidden(_inventory_hud_saved)
	if is_instance_valid(bar):
		briefcase.set_hotbar_visible(bar, _inventory_hotbar_visible)
		var layer: CanvasLayer = briefcase.hotbar_layer(bar)
		if layer != null:
			layer.visible = _inventory_hud_layer_visible
	# Let the inventory re-evaluate its own HUD state after restoring `hud_hidden`: a stale saved
	# layer flag from a bed/menu start must not keep the quick slots hidden.
	briefcase.place_hotbar()
	_inventory_hidden = false
	LOG.debug("inventory HUD restored hud_hidden=%s hotbar=%s layer=%s", [
		str(_inventory_hud_saved), str(_inventory_hotbar_visible),
		str(_inventory_hud_layer_visible)])


## True while the act has the quick-slot card hidden. The idle safety check reads it.
func inventory_hidden() -> bool:
	return _inventory_hidden


## The idle safety check: restore the borrowed quick slots only when no runtime is mid-act. Every
## idle sibling sees the same borrowed flag, so the live act owner decides.
func ensure_act_inventory_visible(act_owner: Node) -> void:
	if not _inventory_hidden:
		return
	if is_instance_valid(act_owner):
		var session: Variant = act_owner.get("act")
		var owner_state: Variant = session.state if session != null else null
		if owner_state != null and int(owner_state) != STATE_IDLE:
			return
	set_inventory_hidden(false)


## Afterglow is mostly passive: hide controls that cannot do anything in that state. Missionary
## afterglow keeps lean, caress and the act key; standing keeps lean, reach, caress, kiss and it.
func _apply_control_visibility(state: int, view: RefCounted) -> void:
	var hints_on := bool(view.hud_controls)
	if _controls != null:
		_controls.visible = hints_on and _hint.visible
	if _hint_gap != null:
		_hint_gap.visible = hints_on and _hint.visible
	var pose_view: Variant = view.pose_view
	var standing := pose_view != null and str(pose_view.family) == "standing"
	var missionary := pose_view != null and str(pose_view.family) == "bed"
	var afterglow := state == STATE_AFTERGLOW
	var layer := bool(view.auto_layer_open)
	var auto_on := bool(view.auto_on)
	for key: String in _control_rows:
		var control := _control_rows[key] as Control
		if control == null:
			continue
		var show := true
		if afterglow:
			if standing:
				show = key in ["lean", "reach", "caress", "caress_move", "kiss", "y"]
			elif missionary:
				show = key in ["lean", "caress", "caress_move", "y"]
			else:
				show = key == "y"
		elif state == STATE_CLIMAX:
			show = true
		# integration: anatomy rows exist only while their feature is live.
		if key in ["anatomy_hole", "anatomy_oral"]:
			show = _extra_row_visible(key, state, standing, view)
		# Auto owns the stroke, so the mouse no longer sets its depth: hide the thrust row there.
		if key == "thrust" and auto_on:
			show = false
		# The hold layer only exists while auto runs.
		if key == "auto_settings" and not auto_on:
			show = false
		# The hold-X layer replaces the whole card: its keys mean something else while it is open.
		control.visible = show and not layer
	for key: String in _layer_rows:
		var row := _layer_rows[key] as Control
		if row != null:
			row.visible = layer and hints_on and _hint.visible


func _extra_row_visible(key: String, state: int, _standing: bool, view: RefCounted) -> bool:
	if state == STATE_AFTERGLOW:
		return false
	match key:
		"anatomy_hole":
			return bool(view.hole_ready)
		"anatomy_oral":
			return bool(view.oral_ready)
	return false
