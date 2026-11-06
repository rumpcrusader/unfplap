extends SceneTree
## HUD style and control rows.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_hud.gd

const HUD := preload("res://mods/unfplap/hud.gd")

var failures := 0
var checks := 0


class Stub extends Node:
	var state := 2
	var pony_climaxes := 0
	var pose_id := "standing"
	var satisfaction := 40.0
	var auto_on := false
	var kiss_fade := false
	var controls_on := true
	var y_pink := 0.0

	func hud_cue_line(_readouts := true) -> String:
		return "❤ 1/3 | She is close."

	func hud_readiness_line(_readouts := true) -> String:
		return "Wants: soft & steady | You: firm"

	func auto_active() -> bool:
		return auto_on

	func auto_hud_text() -> String:
		return "Auto · wheel pace 1.5/s · depth 90%" if auto_on else ""

	func hud_controls_fade() -> bool:
		return kiss_fade

	func hud_y_pink() -> float:
		return y_pink

	func hud_controls() -> bool:
		return controls_on


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


func _check_controls() -> void:
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	check(hud.get("_hint") != null, "HUD builds its hint stack")
	check(hud.get("_hint_title") == null, "act card has no separate title")
	var y_label := hud.get("_y_label") as Label
	check(y_label != null and y_label.text.is_empty(), "Y description starts empty")
	var stub := Stub.new()
	hud.call("update_from", stub, true)
	check(y_label.text == "End early", "Y offers an early end before the first climax")
	check(y_label.get_theme_color("font_color") == HUD.INK, "early end is ink")
	var status := hud.get("_hint_status") as Label
	check(status.text.begins_with("❤ 1/3"), "cue line reaches the HUD")
	var readiness := hud.get("_hint_readiness") as Label
	check(readiness.text.begins_with("Wants:"), "readiness line reaches the HUD")
	var controls := hud.get("_controls") as Control
	check(controls != null and controls.visible, "control card shows while active")
	stub.controls_on = false
	hud.call("update_from", stub, true)
	check(not controls.visible, "control hints switch hides the card")
	check((hud.get("_hint_readiness") as Control).visible, "readouts stay when hints are off")
	stub.controls_on = true
	hud.call("update_from", stub, true)
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
	check(smack != null and smack.get_child_count() == 2,
		"a row without a modifier has no empty column")
	var auto_row := rows.get("auto") as Control
	check(auto_row != null and auto_row.visible, "auto thrust row shows while active")
	check(not (hud.get("_hint_auto") as Control).visible, "auto readout hides while manual")
	stub.auto_on = true
	hud.call("update_from", stub, true)
	check((hud.get("_hint_auto") as Control).visible, "auto readout shows while auto is on")
	check((hud.get("_thrust_label") as Label).text == "Max depth",
		"thrust row sets depth in auto")
	check((hud.get("_auto_label") as Label).text == "Switch to manual",
		"X offers manual while auto runs")
	stub.auto_on = false
	stub.state = 4
	hud.call("update_from", stub, true)
	check(auto_row.visible == false, "afterglow hides auto thrust")
	stub.state = 2
	hud.call("update_from", stub, true)
	check((hud.get("_auto_label") as Label).text == "Switch to auto",
		"X offers auto while manual")
	stub.kiss_fade = true
	hud.call("update_from", stub, true)
	check(is_equal_approx(float(hud.get("_controls_alpha")), hud.CONTROLS_FADE_ALPHA),
		"controls fade while leaning")
	stub.kiss_fade = false
	hud.call("update_from", stub, true)
	check(is_equal_approx(float(hud.get("_controls_alpha")), 1.0),
		"controls come back after the kiss")
	stub.pony_climaxes = 1
	stub.y_pink = 0.25
	hud.call("update_from", stub, true)
	check(y_label.text == "End", "Y offers the end after a climax")
	check(not y_label.get_theme_color("font_color").is_equal_approx(HUD.INK),
		"End warms after a climax")
	stub.y_pink = 1.0
	hud.call("update_from", stub, true)
	check(y_label.get_theme_color("font_color").is_equal_approx(HUD.ACCENT),
		"an earned caress turns End fully pink")
	stub.state = 3
	hud.call("update_from", stub, true)
	check(y_label.text == "End", "Y ends during a climax")
	stub.state = 4
	hud.call("update_from", stub, true)
	check(y_label.text == "End", "Y ends the afterglow")
	check((rows.get("smack") as Control).visible == false, "standing afterglow hides the smack")
	check((rows.get("y") as Control).visible, "afterglow keeps Y")
	stub.pose_id = "missionary"
	hud.call("update_from", stub, true)
	check((rows.get("lean") as Control).visible == false, "missionary afterglow keeps only Y")
	hud.call("show_prompt", "Make love")
	check((hud.get("_prompt") as Control).visible, "fallback prompt shows")
	check((hud.get("_prompt_row") as HBoxContainer).get_child_count() == 2, "fallback prompt is a row")
	hud.call("hide_prompt")
	check(not (hud.get("_prompt") as Control).visible, "fallback prompt hides")
	hud.queue_free()
