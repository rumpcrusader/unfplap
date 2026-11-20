extends "res://mods/unfplap/tests/support/suite.gd"
## Pure act-line value tests: the demand classification, the seed branch and the state line.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/dialogue/test_utterance.gd

const UTTER := preload("res://mods/unfplap/dialogue/utterance.gd")


func run() -> void:
	check(UTTER.is_demand("She wants it firmer."), "demand cue classified")
	check(UTTER.is_demand("She wants a steadier rhythm."), "rhythm demand classified")
	check(UTTER.is_demand("She wants to be teased."), "tease demand classified")
	check(UTTER.is_demand("She needs you to move."), "need cue classified")
	check(not UTTER.is_demand("She likes that."), "positive cue is not a demand")
	check(not UTTER.is_demand("She wants you to keep going."), "trend fallback is not a demand")

	var mismatch := UTTER.line_seed({
		"mood": "wanting", "intensity": "soft", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "steady",
	})
	var too_rough := UTTER.line_seed({
		"mood": "wanting", "intensity": "rough", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "steady",
	})
	check(not mismatch.is_empty(), "a soft mismatch has a seed")
	check(mismatch != too_rough, "the two intensity directions choose different seeds")
	var match := UTTER.line_seed({
		"mood": "wanting", "intensity": "firm", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "steady",
	})
	check(match != mismatch, "a matched stroke has its own seed")
	var rhythm := UTTER.line_seed({
		"mood": "wanting", "intensity": "firm", "pattern": "steady",
		"wanted_intensity": "firm", "wanted_pattern": "quick",
	})
	var too_fast := UTTER.line_seed({
		"mood": "wanting", "intensity": "firm", "pattern": "quick",
		"wanted_intensity": "firm", "wanted_pattern": "teasing",
	})
	check(rhythm != too_fast, "the two tempo directions choose different seeds")
	check(rhythm != match, "a tempo mismatch is not a matched seed")
	var close := UTTER.line_seed({
		"mood": "close", "intensity": "soft", "wanted_intensity": "firm",
	})
	check(close != mismatch, "closeness outranks a preference mismatch")
	var overwhelmed := UTTER.line_seed({"mood": "overwhelmed"})
	check(overwhelmed != close, "overwhelmed outranks closeness")
	var touch := UTTER.line_seed({
		"mood": "wanting", "last_touch": "caress", "touch_likes": ["caress"],
	})
	var quiet := UTTER.line_seed({"mood": "warming"})
	check(not quiet.is_empty(), "a quiet moment has a seed")
	check(touch != quiet, "a liked touch colors a quiet moment")
	var disliked := UTTER.line_seed({
		"mood": "wanting", "last_touch": "smack", "touch_dislikes": ["smack"],
	})
	check(disliked != touch, "a disliked touch has its own seed")
	var talk := UTTER.line_seed({
		"mood": "wanting", "last_talk": "praise", "talk_likes": ["praise"],
	})
	check(talk != quiet, "liked talk has its own seed")

	var line := UTTER.state_line("missionary", "wanting", "firm", "teasing", "caress", "praise", 18.0, 2)
	check(line.contains("pose=missionary"), "state line pose")
	check(line.contains("mood=wanting"), "state line mood")
	check(line.contains("firm teasing"), "state line motion")
	check(line.contains("last touch=caress"), "state line touch")
	check(line.contains("last talk=praise"), "state line talk")
	check(line.contains("climaxes=2"), "state line climaxes")
	check(not line.contains("18s in"), "state line drops the elapsed seconds")
	check(not line.contains("/s"), "state line has no speed units")

	var empty := UTTER.state_line("standing", "warming", "", "", "", "", 0.0)
	check(empty.contains("he is unknown"), "state line handles no motion")
	check(empty.contains("last touch=none"), "state line handles no touch")
	check(empty.contains("last talk=none"), "state line handles no talk")

	if failures == 0:
		print("UTTERANCE_PASS")
	finish()
