extends SceneTree
## The pure HUD text: hearts/cue, readiness, auto and the End tint.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hud/test_hud_lines.gd

const LINES := preload("res://mods/unfplap/hud/lines.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001


func run() -> void:
	_check_cue()
	_check_readiness()
	_check_auto()
	_check_y()

	print("HUD_LINES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("HUD_LINES_PASS")
	quit(0 if failures == 0 else 1)


func _check_cue() -> void:
	check(LINES.cue_line(0, 0, 3, "warming", "", "", true) == "",
		"an idle act has no cue line")
	var active := LINES.cue_line(2, 1, 3, "She wants it firmer.", "", "", true)
	check(active.begins_with("❤ 1/3 | "), "the cue line starts with the hearts")
	check(active.ends_with("She wants it firmer."), "the cue line carries the cue")
	var muted := LINES.cue_line(2, 1, 3, "She wants it firmer.", "", "", false)
	check(muted == "❤ 1/3", "readouts off keeps only the hearts")
	var unlimited := LINES.cue_line(3, 2, 0, "", "", "", true)
	check(unlimited == "❤ 2/∞ | —", "the unlimited hearts and the empty cue dash")
	var closing := LINES.cue_line(4, 2, 3, "cue", "Close: Y", "", false)
	check(closing == "❤ 2/3 | Close: Y", "the close prompt survives readouts off")
	var summary := LINES.cue_line(4, 2, 3, "cue", "", "summary", false)
	check(summary == "❤ 2/3 | summary", "the afterglow summary replaces the cue")
	var close_wins := LINES.cue_line(4, 2, 3, "cue", "Close: Y", "summary", true)
	check(close_wins.ends_with("Close: Y"), "the close prompt wins over the summary")


func _check_readiness() -> void:
	check(LINES.readiness_line(0, true, "", "", "firm", "steady", false, "", "") == "",
		"an idle act has no readiness line")
	var line := LINES.readiness_line(2, true, "soft", "quick", "firm", "steady", false, "", "")
	check(line == "Wants: firm & steady | You: soft & quick", "the readiness line compares both")
	var heat := LINES.readiness_line(3, true, "", "", "firm", "steady", true, "", "")
	check(heat.ends_with(" | In heat"), "heat is appended")
	var off := LINES.readiness_line(2, false, "soft", "quick", "firm", "steady", false, "", "")
	check(off == "", "readouts off hides the readiness line")
	check(LINES.readiness_line(4, true, "", "", "firm", "steady", false, "", "summary") == "",
		"an afterglow without the close prompt keeps the summary in the cue")
	check(LINES.readiness_line(4, true, "", "", "firm", "steady", false, "close", "summary")
		== "summary", "an afterglow with the close prompt shows the summary below it")


func _check_auto() -> void:
	check(LINES.auto_text(0.2, 0.8, 1.5, "Normal") == "Auto · 20–80% · 1.50/s · Normal",
		"the auto readout formats depth, pace and shape")
	check(LINES.auto_text(0.0, 0.5, 1.0, "Thrust") == "Auto · 0–50% · 1.00/s · Thrust",
		"the auto readout keeps the exact step values")


func _check_y() -> void:
	check(near(LINES.y_pink(false, false, false, 0, 3), 0.0), "no climax is no tint")
	check(near(LINES.y_pink(false, false, false, 3, 3), LINES.Y_END_TINT_MAX),
		"the climax limit reaches the tint cap")
	check(near(LINES.y_pink(false, false, false, 1, 0), LINES.Y_END_TINT_MAX / 3.0),
		"the unlimited limit uses the 3-climax reference")
	check(near(LINES.y_pink(true, true, true, 0, 3), 1.0),
		"the earned standing afterglow caress is full pink")
	check(near(LINES.y_pink(true, true, false, 1, 3), LINES.Y_END_TINT_MAX / 3.0),
		"an unearned standing afterglow keeps the normal tint")
