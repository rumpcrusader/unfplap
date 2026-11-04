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

	func hud_cue_line(_readouts := true) -> String:
		return "❤ 1/3 | She's close."

	func hud_readiness_line(_readouts := true) -> String:
		return "Wants: soft & steady | You: firm"


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
	var painter := cap.get_theme_stylebox("panel") as StyleBoxFlat
	check(painter != null and painter.bg_color == HUD.CAP_BG, "key cap uses the prompt cap colour")
	check(painter.border_width_bottom > painter.border_width_top, "key cap has the prompt bottom lip")
	check(painter.corner_radius_top_left > 0, "key cap is rounded")
	var icon: TextureRect = HUD.button_icon("key_q", 28.0)
	check(icon != null and icon.texture != null, "prompt icon resolves")
	check(HUD.button_icon("no_such_icon", 28.0) == null, "missing prompt icon is null")
	var label := HUD.text_label("Hold: Make love", 30)
	check(label.get_theme_constant("outline_size") > 0, "words use the prompt outline")
	check(label.get_theme_color("font_color") == HUD.INK, "words are ink")
	check(label.get_theme_color("font_outline_color") == HUD.SHADE, "outline is the prompt shade")
	var row: HBoxContainer = HUD.prompt_row("button_y", "Hold:", "Make love")
	check(row.get_child_count() == 2, "prompt row is icon plus words")
	var words := row.get_child(1) as HBoxContainer
	check(words != null and words.get_child_count() == 2, "prompt words are lead plus action")
	var lead := words.get_child(0) as Label
	check(lead != null and lead.text == "Hold:" and lead.get_theme_color("font_color") == HUD.INK,
		"prompt lead stays ink")
	var action := words.get_child(1) as Label
	check(action != null and action.text == "Make love", "prompt row reads the offer action")
	check(action.get_theme_color("font_color") == HUD.ACCENT, "offer action is the pink accent")
	check(row.get_child(0) is TextureRect, "prompt row starts with the game icon")


func _check_controls() -> void:
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	check(hud.get("_hint") != null, "HUD builds its hint stack")
	var title := hud.get("_hint_title") as Label
	check(title != null and title.text == "MAKE LOVE", "act card names the mode")
	var y_label := hud.get("_y_label") as Label
	check(y_label != null and y_label.text.is_empty(), "Y description starts empty")
	var stub := Stub.new()
	hud.call("update_from", stub, true)
	check(y_label.text == "Stop", "Y stops before the first climax")
	check(title.visible, "title shows during the act")
	var status := hud.get("_hint_status") as Label
	check(status.text.begins_with("❤ 1/3"), "cue line reaches the HUD")
	var readiness := hud.get("_hint_readiness") as Label
	check(readiness.text.begins_with("Wants:"), "readiness line reaches the HUD")
	check((hud.get("_readiness_bar") as Control).visible, "readiness bar shows while active")
	var rows: Dictionary = hud.get("_control_rows")
	var kiss := rows.get("kiss") as Control
	check(kiss != null and kiss.visible, "kiss row shows while active")
	var row_box := kiss as HBoxContainer
	check(row_box.get_child_count() == 3, "a control row is icon, modifier and words")
	var modifier := row_box.get_child(1) as Label
	check(modifier.text == "Hold", "hold controls say so in their own column")
	check((row_box.get_child(2) as Label).text == "Kiss at full lean", "kiss row reads its action")
	stub.pony_climaxes = 1
	hud.call("update_from", stub, true)
	check(y_label.text == "Afterglow", "Y offers afterglow after a climax")
	stub.state = 3
	hud.call("update_from", stub, true)
	check(y_label.text == "Afterglow", "Y offers afterglow during a climax")
	stub.state = 4
	hud.call("update_from", stub, true)
	check(y_label.text == "Exit", "Y ends the afterglow")
	check((rows.get("smack") as Control).visible == false, "standing afterglow hides the smack")
	check((rows.get("y") as Control).visible, "afterglow keeps Y")
	stub.pose_id = "missionary"
	hud.call("update_from", stub, true)
	check((rows.get("forward") as Control).visible == false, "missionary afterglow keeps only Y")
	hud.call("show_prompt", "Hold:", "Make love")
	check((hud.get("_prompt") as Control).visible, "fallback prompt shows")
	check((hud.get("_prompt_row") as HBoxContainer).get_child_count() == 2, "fallback prompt is a row")
	hud.call("hide_prompt")
	check(not (hud.get("_prompt") as Control).visible, "fallback prompt hides")
	hud.queue_free()
