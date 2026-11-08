extends SceneTree
## Pure relationship/tone and peak-memory gate tests.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_relationship_cue.gd

const REL := preload("res://mods/unfplap/relationship_cue.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func facts(overrides := {}) -> Dictionary:
	var out := {
		"friendship": "Good Friend",
		"friendship_level": 3,
		"love": "Marefriend",
		"love_level": 2,
		"stage": "dating",
		"mood": "happy",
		"first_time": false,
		"careful": false,
	}
	for key in overrides:
		out[key] = overrides[key]
	return out


func run() -> void:
	var base := REL.note(facts())
	check(base.contains("friendship Good Friend"), "note names the friendship level")
	check(base.contains("love Marefriend"), "note names the love level")
	check(base.contains("you are dating"), "note names the stage")
	check(base.contains("you have been together before"), "repeat note")
	check(base.contains("mood happy"), "note carries mood")
	check(not base.contains("2"), "note has no raw level number")

	var first := REL.note(facts({"first_time": true}))
	check(first.contains("first time together"), "first-time note")
	check(REL.note({}).is_empty(), "no facts gives no note")
	check(REL.lover_note(true) == "- You and Anon are lovers.", "bonded lover note")
	check(REL.lover_note(false) == "- You are not Anon's lover.", "unbonded lover note")
	check(not REL.lover_note(true).to_lower().contains("sex"),
		"the lover note does not mention sex")
	check(not REL.lover_note(false).to_lower().contains("sex"),
		"the unbonded lover note does not mention sex")

	check(REL.tone(facts({"first_time": true})) == "tender", "first time is tender")
	check(REL.tone(facts()) == "warm", "marefriend is warm")
	check(REL.tone(facts({"love_level": 3})) == "ardent", "head over hooves is ardent")
	check(REL.tone(facts({"love_level": 4})) == "open", "soulmates is open")
	check(REL.tone(facts({"careful": true})) == "careful", "hurt overrides depth")
	check(REL.tone(facts({"love_level": -1, "friendship_level": 1,
		"stage": "acquaintance"})) == "guarded", "an acquaintance is guarded")
	check(REL.tone(facts({"love_level": -1, "friendship_level": 3,
		"stage": "close_friend"})) == "friendly", "a friend is friendly, not warm")
	check(REL.tone(facts({"love_level": -1, "friendship_level": 0,
		"stage": ""})) == "guarded", "a stranger is guarded")
	check(REL.note(facts({"stage": "acquaintance"})).contains("you barely know each other"),
		"the acquaintance stage is phrased")
	check(REL.note(facts({"stage": "close_friend"})).contains("you are close friends"),
		"the close-friend stage is phrased")
	check(not REL.note(facts({"stage": "acquaintance"})).contains("acquaintance"),
		"the raw stage id is not sent")
	check(not REL.tone_line("warm").is_empty(), "tone line is present")
	check(REL.tone_line("guarded").contains("do not know him well"),
		"guarded tone line is present")
	check(REL.tone_line("friendly").contains("not romantic partners"),
		"friendly tone line is present")

	check(REL.memory_line("").is_empty(), "empty memory is dropped")
	check(REL.memory_line("a walk").contains("a walk"), "memory line carries text")
	var long := "x".repeat(200)
	var shortened := REL.memory_line(long)
	check(shortened.length() < long.length() + 50, "long memory is shortened")
	check(shortened.ends_with("..."), "shortened memory marks the cut")

	check(REL.peak_eligible(90.0, 0, 0), "high satisfaction is a peak")
	check(REL.peak_eligible(70.0, 6, 0), "six clean both-axis thrusts are a peak")
	check(not REL.peak_eligible(70.0, 5, 0), "ordinary act is not a peak")
	check(not REL.peak_eligible(100.0, 20, 1), "a dislike blocks the peak")
	check(REL.peak_score(100.0, 10, 2, 1, 0) > REL.peak_score(100.0, 4, 1, 1, 0),
		"more clean matches score higher")

	print("RELATIONSHIP_CUE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RELATIONSHIP_CUE_PASS")
	quit(0 if failures == 0 else 1)
