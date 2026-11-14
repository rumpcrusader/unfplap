extends SceneTree
## HUD style and control rows.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hud/test_hud.gd

const HUD := preload("res://mods/unfplap/hud/service.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")

var failures := 0
var checks := 0


## The typed act view the card reads. The runtime writes the same fields; the test sets them.
func _view() -> RefCounted:
	var facts: RefCounted = ACT_FACTS.new()
	facts.state = 2
	facts.pose_id = "standing"
	facts.max_pony_climaxes = 3
	facts.pony_climaxes = 0
	facts.cue = "She is close."
	facts.last_intensity = "firm"
	facts.last_pattern = "steady"
	facts.preferences = {"intensity": "soft", "pattern": "steady"}
	facts.hud_readouts = true
	facts.hud_controls = true
	facts.auto_shape = "Normal"
	facts.auto_min_depth = 0.2
	facts.auto_max_depth = 0.9
	facts.auto_pace = 1.5
	return facts


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_style()
	_check_controls()
	print("HUD_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("HUD_PASS")
	quit(0 if failures == 0 else 1)


func _check_style() -> void:
	var cap: PanelContainer = HUD.keycap("W")
	var letter := cap.get_child(0) as Label
	check(letter != null and letter.text == "W", "drawn key cap keeps its key")
	check(letter.get_theme_color("font_color") == HUD.INK, "key cap letter is ink")
	var wide_cap: PanelContainer = HUD.keycap("RMB")
	check(wide_cap.custom_minimum_size.x > cap.custom_minimum_size.x,
		"a multi-character cap is wider")
	var painter := cap.get_theme_stylebox("panel") as StyleBoxFlat
	check(painter != null and painter.bg_color == HUD.CAP_BG, "key cap uses the prompt cap colour")
	check(painter.border_width_bottom > painter.border_width_top, "key cap has the prompt bottom lip")
	check(painter.corner_radius_top_left > 0, "key cap is rounded")
	var icon: TextureRect = HUD.button_icon("key_q", 28.0)
	check(icon != null and icon.texture != null, "prompt icon resolves")
	check(HUD.button_icon("no_such_icon", 28.0) == null, "missing prompt icon is null")
	var label := HUD.text_label("Make love", 30)
	check(label.get_theme_constant("outline_size") > 0, "words use the prompt outline")
	check(label.get_theme_color("font_color") == HUD.INK, "words are ink")
	check(label.get_theme_color("font_outline_color") == HUD.SHADE, "outline is the prompt shade")
	var row: HBoxContainer = HUD.prompt_row("button_y", "Make love")
	check(row.get_child_count() == 2, "prompt row is icon plus words")
	var action := row.get_child(1) as Label
	check(action != null and action.text == "Make love", "prompt row reads the offer action")
	check(action.get_theme_color("font_color") == HUD.ACCENT, "offer action is the pink accent")
	check(row.get_child(0) is TextureRect, "prompt row starts with the game icon")
	var capped: HBoxContainer = HUD.prompt_row("", "Make love", "6")
	check(capped.get_child_count() == 2, "a capped prompt row is cap plus words")
	var prompt_cap := capped.get_child(0) as PanelContainer
	check(prompt_cap != null, "a key with no prompt icon draws a cap")
	check(prompt_cap.custom_minimum_size.y >= HUD.PROMPT_ICON_EDGE,
		"the prompt cap matches the game icon height")
	var capped_text := capped.get_child(1) as Label
	check(capped_text != null and capped_text.text == "Make love", "the capped row keeps its words")


func _check_controls() -> void:
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	check(hud.get("_hint") != null, "HUD builds its hint stack")
	check(hud.get("_hint_title") == null, "act card has no separate title")
	var y_label := hud.get("_y_label") as Label
	check(y_label != null and y_label.text.is_empty(), "the act-key description starts empty")
	var view := _view()
	hud.call("update_from", view)
	check(y_label.text == "End early", "the act key offers an early end before the first climax")
	check(y_label.get_theme_color("font_color") == HUD.INK, "early end is ink")
	var status := hud.get("_hint_status") as Label
	check(status.text.begins_with("❤ 0/3"), "cue line reaches the HUD")
	var readiness := hud.get("_hint_readiness") as Label
	check(readiness.text.begins_with("Wants:"), "readiness line reaches the HUD")
	var controls := hud.get("_controls") as Control
	check(controls != null and controls.visible, "control card shows while active")
	view.hud_controls = false
	hud.call("update_from", view)
	check(not controls.visible, "control hints switch hides the card")
	check((hud.get("_hint_readiness") as Control).visible, "readouts stay when hints are off")
	view.hud_controls = true
	hud.call("update_from", view)
	check(controls.visible, "control hints switch shows the card")
	var rows: Dictionary = hud.get("_control_rows")
	var kiss := rows.get("kiss") as Control
	check(kiss != null and kiss.visible, "kiss row shows while active")
	var row_box := kiss as HBoxContainer
	check(row_box.get_child_count() == 3, "a single-key row is icon, modifier and words")
	var modifier := row_box.get_child(1) as Label
	check(modifier.text == "Hold", "hold controls say so in their own column")
	check((row_box.get_child(2) as Label).text == "Kiss", "kiss row reads its action")
	var lean := rows.get("lean") as Control
	check(lean != null and lean.visible, "lean row shows while active")
	var lean_box := lean as HBoxContainer
	check(lean_box.get_child_count() == 3, "a key-pair row is two keys and words")
	check((lean_box.get_child(2) as Label).text == "Lean",
		"lean row does not spell out both directions")
	var smack := rows.get("smack") as HBoxContainer
	check(smack != null and smack.get_child_count() == 3,
		"a two-key row has both caps and the words")
	check((smack.get_child(2) as Label).text == "Smack", "G and RMB both read Smack")
	var auto_row := rows.get("auto") as Control
	check(auto_row != null and auto_row.visible, "auto thrust row shows while active")
	check(not (hud.get("_hint_auto") as Control).visible, "auto readout hides while manual")
	view.auto_on = true
	hud.call("update_from", view)
	check((hud.get("_hint_auto") as Control).visible, "auto readout shows while auto is on")
	check(not (rows.get("thrust") as Control).visible,
		"auto hides the mouse thrust row, which no longer sets depth")
	check((rows.get("auto_settings") as Control).visible,
		"the hold-X hint shows while auto runs")
	check((hud.get("_auto_label") as Label).text == "Switch to manual",
		"X offers manual while auto runs")
	view.auto_on = false
	view.state = 4
	hud.call("update_from", view)
	check(auto_row.visible == false, "afterglow hides auto thrust")
	view.state = 2
	hud.call("update_from", view)
	check((hud.get("_auto_label") as Label).text == "Switch to auto",
		"X offers auto while manual")
	check(not (rows.get("auto_settings") as Control).visible,
		"manual mode hides the hold-X hint")
	check((rows.get("thrust") as Control).visible, "manual mode shows the mouse thrust row")
	# The hold-X layer swaps the whole card for its four live rows.
	var layer_rows: Dictionary = hud.get("_layer_rows")
	check(not (layer_rows.get("min") as Control).visible,
		"the auto settings layer is hidden while closed")
	view.auto_on = true
	view.auto_layer_open = true
	hud.call("update_from", view)
	check((layer_rows.get("min") as Control).visible,
		"the layer replaces the card while X is held")
	check(not (rows.get("lean") as Control).visible,
		"normal rows hide while the layer is open")
	var layer_labels: Dictionary = hud.get("_layer_labels")
	check((layer_labels.get("min") as Label).text == "Min depth 20%",
		"the layer row shows its live value")
	check((layer_labels.get("shape") as Label).text.begins_with("Shape"),
		"the shape row shows its value")
	view.auto_layer_open = false
	view.auto_on = false
	hud.call("update_from", view)
	check(not (layer_rows.get("min") as Control).visible,
		"closing the layer hides its rows")
	check((rows.get("lean") as Control).visible, "the normal card returns")
	view.pony_climaxes = 1
	view.y_pink = 0.25
	hud.call("update_from", view)
	check(y_label.text == "End", "the act key offers the end after a climax")
	check(not y_label.get_theme_color("font_color").is_equal_approx(HUD.INK),
		"End warms after a climax")
	view.y_pink = 1.0
	hud.call("update_from", view)
	check(y_label.get_theme_color("font_color").is_equal_approx(HUD.ACCENT),
		"an earned caress turns End fully pink")
	view.state = 3
	hud.call("update_from", view)
	check(y_label.text == "End", "the act key ends during a climax")
	view.state = 4
	hud.call("update_from", view)
	check(y_label.text == "End", "the act key ends the afterglow")
	check((rows.get("smack") as Control).visible == false, "standing afterglow hides the smack")
	check((rows.get("y") as Control).visible, "afterglow keeps the act-key row")
	check(_act_cap(rows).text == "6", "the act-key row starts on the default cap")
	hud.call("set_act_key", "Y")
	check(_act_cap(rows).text == "Y", "the act-key row follows the setting")
	hud.call("set_act_key", "F")
	check(_act_cap(rows).text == "F", "the act-key row follows a captured key")
	hud.call("set_act_key", "6")
	check(_act_cap(rows).text == "6", "the act-key row returns to 6")
	view.pose_id = "missionary"
	hud.call("update_from", view)
	check((rows.get("lean") as Control).visible, "missionary afterglow keeps the lean")
	check((rows.get("caress") as Control).visible, "missionary afterglow keeps the caress")
	check((rows.get("caress_move") as Control).visible,
		"missionary afterglow keeps caress movement")
	check((rows.get("kiss") as Control).visible == false, "missionary afterglow hides the kiss")
	view.state = 2
	hud.call("update_from", view)
	check((rows.get("kiss") as Control).visible, "missionary shows the kiss (front lean)")
	check((rows.get("anatomy_finish") as Control).visible == false,
		"the finish control is hidden for now")
	view.pose_id = "standing"
	hud.call("update_from", view)
	check((rows.get("kiss") as Control).visible, "standing shows the kiss")
	hud.call("show_prompt", "Make love")
	check((hud.get("_prompt") as Control).visible, "fallback prompt shows")
	check((hud.get("_prompt_row") as HBoxContainer).get_child_count() == 2, "fallback prompt is a row")
	hud.call("hide_prompt")
	check(not (hud.get("_prompt") as Control).visible, "fallback prompt hides")
	hud.queue_free()


## The first child of the act-key row is its drawn cap.
func _act_cap(rows: Dictionary) -> Label:
	var row := rows.get("y") as HBoxContainer
	return (row.get_child(0) as PanelContainer).get_child(0) as Label
