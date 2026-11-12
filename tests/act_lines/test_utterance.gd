extends SceneTree
## Pure prompt-format tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_lines/test_utterance.gd

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
	check(UTTER.is_demand("She wants a steadier rhythm."), "rhythm demand classified")
	check(UTTER.is_demand("She wants to be teased."), "tease demand classified")
	check(UTTER.is_demand("She needs you to move."), "need cue classified")
	check(not UTTER.is_demand("She likes that."), "positive cue is not a demand")
	check(not UTTER.is_demand("She wants you to keep going."), "trend fallback is not a demand")

	var text := UTTER.format("a {state} b {preferences} c {cue} d {recent} e {missing}", {
		"state": "S", "preferences": "T", "cue": "C", "recent": "R",
	})
	check(text == "a S b T c C d R e ", "format placeholders")
	var nested := UTTER.format("{a} {b}", {"a": "{b}", "b": "X"})
	check(nested == "{b} X", "a substituted value is not expanded again")

	var appended := UTTER.context_note("a {state}", {
		"state": "pose=missionary", "relationship": "You and Anon: friends.",
		"tone": "Warm: be fond.", "memory": "",
	})
	check(appended.contains("Private relationship note: You and Anon: friends."),
		"context adds a missing relationship note")
	check(appended.contains("Tone: Warm: be fond."), "context adds a missing tone")
	check(appended.contains("Do not mention these labels"), "context adds the privacy guard")
	check(not appended.contains("Current moment:"), "context does not repeat a used state")

	var reuse := UTTER.context_note("{relationship}. Do not mention relationship labels.", {
		"relationship": "You and Anon: friends.", "tone": "Warm: be fond.",
	})
	check(not reuse.contains("Private relationship note:"),
		"context does not duplicate a used relationship note")
	check(reuse.contains("Tone: Warm: be fond."), "context still adds an unused tone")
	check(not reuse.contains("Do not mention these labels"),
		"context does not repeat an existing privacy guard")

	var memory_only := UTTER.context_note("plain", {"relationship": "R", "memory": ""})
	check(not memory_only.contains("shared memory"), "empty memory adds nothing")

	var mismatch := UTTER.line_seed({
		"mood": "wanting", "intensity": "soft", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "steady",
	})
	check(mismatch.contains("rather he be firmer"), "a soft stroke asks for firm")
	check(not mismatch.contains("She wants"), "a seed is second person, not a HUD cue")
	check(mismatch.contains("private, not a script"), "a seed is explicitly private")
	var match := UTTER.line_seed({
		"mood": "wanting", "intensity": "firm", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "steady",
	})
	check(match.contains("what you wanted"), "a matching stroke is affirmed")
	var rhythm := UTTER.line_seed({
		"mood": "wanting", "intensity": "firm", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "quick",
	})
	check(rhythm.contains("quicker"), "a rhythm mismatch asks for the wanted tempo")
	var close := UTTER.line_seed({
		"mood": "close", "intensity": "soft", "wanted_intensity": "firm",
	})
	check(close.contains("You are close"), "closeness outranks a preference mismatch")
	var overwhelmed := UTTER.line_seed({"mood": "overwhelmed"})
	check(overwhelmed.contains("need a breath"), "overwhelmed outranks closeness")
	var touch := UTTER.line_seed({
		"mood": "wanting", "last_touch": "caress", "touch_likes": ["caress"],
	})
	check(touch.contains("liked his touch"), "a liked touch colors a quiet moment")
	var quiet := UTTER.line_seed({"mood": "warming"})
	check(quiet.contains("nothing needs fixing"), "a quiet moment does not invent a demand")

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
