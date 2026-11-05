extends SceneTree
## Pure prompt-format tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_utterance.gd

const UTTER := preload("res://mods/unfplap/utterance.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	check(UTTER.is_demand("She wants it firmer."), "demand cue classified")
	check(UTTER.is_demand("She needs you to move."), "need cue classified")
	check(not UTTER.is_demand("She likes that."), "positive cue is not a demand")

	var text := UTTER.format("a {state} b {taste} c {cue} d {recent} e {missing}", {
		"state": "S", "taste": "T", "cue": "C", "recent": "R",
	})
	check(text == "a S b T c C d R e ", "format placeholders")
	var nested := UTTER.format("{a} {b}", {"a": "{b}", "b": "X"})
	check(nested == "{b} X", "a substituted value is not expanded again")

	var line := UTTER.state_line("missionary", "wanting", "firm", "teasing", "caress", "praise", 18.0, 2)
	check(line.contains("pose=missionary"), "state line pose")
	check(line.contains("mood=wanting"), "state line mood")
	check(line.contains("firm teasing"), "state line motion")
	check(line.contains("last touch=caress"), "state line touch")
	check(line.contains("last talk=praise"), "state line talk")
	check(line.contains("climaxes=2"), "state line climaxes")
	check(line.contains("18s in"), "state line time")
	check(not line.contains("/s"), "state line has no speed units")

	var empty := UTTER.state_line("standing", "warming", "", "", "", "", 0.0)
	check(empty.contains("he is unknown"), "state line handles no motion")
	check(empty.contains("last touch=none"), "state line handles no touch")
	check(empty.contains("last talk=none"), "state line handles no talk")

	print("UTTERANCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("UTTERANCE_PASS")
	quit(0 if failures == 0 else 1)
