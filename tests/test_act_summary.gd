extends SceneTree
## Pure act-outcome scoring: per-act action checklist, good/bad bands, early end and silence.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_summary.gd

const SUMMARY := preload("res://mods/unfplap/act_summary.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func base_taste() -> Dictionary:
	return {
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
	}


func snapshot(overrides := {}) -> Dictionary:
	var out := {
		"taste": base_taste(),
		"seconds": 120.0,
		"thrusts": 20,
		"pony_climaxes": 1,
		"talk_liked": 1,
		"talk_dislikes": 0,
		"touches_liked": 1,
		"touch_dislikes": {},
		"player_lines": 1,
		"intensity_total": 10,
		"intensity_right": 10,
		"pattern_total": 10,
		"pattern_right": 10,
		"ended_early": false,
		"forced": false,
	}
	for key: Variant in overrides:
		out[key] = overrides[key]
	return out


func evaluate(overrides := {}) -> Dictionary:
	return SUMMARY.evaluate(snapshot(overrides), SUMMARY.DEFAULT_RULES)


func run() -> void:
	var clean := evaluate()
	check(clean.grade == "good", "a clean act is good")
	check(clean.positive, "a clean act is positive")
	check(int(clean.romance) == 2, "a good act gives romance +2")
	check(str(clean.mood) == "happy", "a good act is happy")
	check(is_equal_approx(float(clean.quality), 1.0), "a clean act scores 1.0")
	check(str(clean.hud).contains("wanted"), "good HUD is feeling words")

	var great := evaluate({"pony_climaxes": 2})
	check(great.grade == "great", "two climaxes with no misses is great")
	check(int(great.romance) == 2, "a great act gives romance +2")

	var silent := evaluate({"talk_liked": 0, "player_lines": 0})
	check(silent.grade == "neutral", "silence alone is neutral for a talk-seeker, not bad")
	check(not silent.positive, "silence with a talk-seeker is not a good act")
	check("silent_talk" in (silent.reasons as Array), "silence reason is named")

	var quiet_taste := base_taste()
	quiet_taste["talk"] = []
	var non_seeker := evaluate({"taste": quiet_taste, "talk_liked": 0, "player_lines": 0})
	check(non_seeker.grade == "good", "silence is not counted for a mare with no talk preference")

	var bad := evaluate({"talk_liked": 0, "player_lines": 0, "touch_dislikes": {"smack": 2}})
	check(bad.grade == "bad", "repeated disliked handling plus silence is bad")
	check(float(bad.quality) <= 0.20, "a bad act is at or below the 0.20 band")
	check(bool(bad.severe), "repeated disliked handling is severe")
	check(int(bad.romance) == -1, "a bad act gives romance -1")
	check(str(bad.mood) == "annoyed", "a severe bad act is annoyed")

	var stopped := evaluate({"stopped_by_her": true, "tolerance": "strict",
		"touch_dislikes": {"smack": 1}})
	check(stopped.grade == "bad", "a partner stop is always bad")
	check(bool(stopped.severe), "a stopped act is severe")
	check(int(stopped.romance) == -1, "a stopped act gives no romance")
	check(str(stopped.mood) == "angry", "a strict stop uses angry")
	check(str(stopped.hud).is_empty(), "a stopped act has no HUD summary")
	check("stopped_by_her" in (stopped.reasons as Array), "the stop reason is recorded")
	check(not str(stopped.text).contains(" you "),
		"a partner stop event has no second-person body")

	var stopped_neutral := evaluate({"stopped_by_her": true, "tolerance": "neutral"})
	check(str(stopped_neutral.mood) == "annoyed", "a neutral stop is annoyed")

	var one_dislike := evaluate({"touch_dislikes": {"smack": 1}})
	check(one_dislike.grade == "neutral", "one dislike only is neutral")
	check(int(one_dislike.romance) == 1, "a neutral act still gives romance +1")

	var early := evaluate({"pony_climaxes": 0, "ended_early": true})
	check(early.grade == "neutral", "a clean early end is neutral")
	check(bool(early.early), "early end is marked")
	check(int(early.romance) == 0, "early end gives no romance")
	check("ended_early" in (early.reasons as Array), "early end reason is named")

	var early_silent := evaluate({"pony_climaxes": 0, "ended_early": true,
		"talk_liked": 0, "player_lines": 0})
	var early_text := str(early_silent.text)
	var early_thought := str(early_silent.thought)
	check(not early_text.contains("ended it before you finished"),
		"the early event does not repeat its opening sentence")
	check(not early_thought.contains(" you "), "the early thought stays in first person")
	check(early_text.contains("Anon did not speak when she needed to hear him"),
		"the event says Anon did not speak")
	check(early_thought.contains("He did not speak to me when I needed to hear him"),
		"the thought says He did not speak to her")
	var bad_silent := evaluate({"talk_liked": 0, "player_lines": 0,
		"touch_dislikes": {"smack": 2}})
	check(not str(bad_silent.thought).contains(" you "),
		"a bad thought stays in first person")
	check(not str(clean.text).contains(" you "),
		"a good event text has no second-person body")
	check(not str(early_text).contains(" you "),
		"an early event text has no second-person body")
	check(not str(bad.text).contains(" you "),
		"a bad event text has no second-person body")

	var forced := evaluate({"forced": true})
	check(bool(forced.skip), "a forced stop is skipped")
	check(not forced.positive, "a forced stop is not positive")

	var short := evaluate({"seconds": 5.0, "thrusts": 0})
	check(bool(short.skip), "a very short act is skipped")

	var no_touch := base_taste()
	no_touch["touch"] = []
	no_touch["dislikes"] = []
	var bare := evaluate({"taste": no_touch, "touches_liked": 0})
	check(bare.grade == "good", "no touch preference omits the touch check")

	var mismatch := evaluate({"intensity_right": 1, "pattern_right": 1})
	check(mismatch.grade != "good", "a motion mismatch cannot be good")
	check("intensity_mismatch" in (mismatch.reasons as Array), "intensity mismatch is named")
	check("pattern_mismatch" in (mismatch.reasons as Array), "pattern mismatch is named")

	var no_liked_touch := evaluate({"touches_liked": 0})
	check(no_liked_touch.grade != "good", "a touch preference that was never met is not good")
	check("no_liked_touch" in (no_liked_touch.reasons as Array), "missing liked touch is named")

	print("ACT_SUMMARY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_SUMMARY_PASS")
	quit(0 if failures == 0 else 1)
