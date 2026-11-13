extends SceneTree
## Pure preference/pattern/talk-classifier tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_preferences.gd

const PREF := preload("res://mods/unfplap/shared/preferences.gd")
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
	var neutral := PREF.resolve({})
	check(not ("curious" in PREF.TALKS), "curious talk is removed")
	check(str(neutral.get("intensity", "")) == "firm", "default intensity firm")
	check(str(neutral.get("pattern", "")) == "steady", "default pattern steady")
	check(str(neutral.get("warmth", "")) == "normal", "default warmth normal")
	check(str(neutral.get("tolerance", "")) == "normal", "default tolerance normal")
	check((neutral.get("touch", []) as Array).is_empty(), "default touch empty")
	check((neutral.get("talk", []) as Array).is_empty(), "default talk empty")

	check(PREF.intensity_for(0.10) == "soft", "soft intensity band")
	check(PREF.intensity_for(0.50) == "firm", "firm intensity band")
	check(PREF.intensity_for(0.60) == "rough", "rough starts at the retuned threshold")
	check(PREF.intensity_for(0.85) == "rough", "rough intensity band")

	check(PREF.intensity_for_travel(0.10) == "soft", "shallow travel reads soft")
	check(PREF.intensity_for_travel(0.50) == "firm", "mid travel reads firm")
	check(PREF.intensity_for_travel(0.65) == "rough", "deep travel starts at the rough band")
	check(PREF.intensity_for_travel(0.90) == "rough", "deep travel reads rough")

	check(PREF.pattern_for([]) == "", "no pattern without strokes")
	check(PREF.pattern_for(_strokes(0.60, 0.40, 3)) == "steady", "steady pattern")
	check(PREF.pattern_for(_strokes(0.30, 0.90, 3)) == "teasing", "teasing pattern")
	check(PREF.pattern_for(_strokes(0.50, 0.20, 3)) == "quick", "quick pattern")
	check(PREF.pattern_for(_strokes(0.90, 0.20, 3)) == "quick",
		"a deep fast stroke reads quick")
	check(PREF.pattern_for(_strokes(0.90, 0.90, 3)) == "teasing",
		"a deep slow stroke reads teasing")

	# The travel and tempo axes are independent: a manual stroke can reach all nine
	# intensity x pattern combinations. The physical strength is not part of the preference.
	var combos: Dictionary = {}
	for travel_step in range(1, 20):
		for duration_step in range(1, 20):
			var travel := float(travel_step) / 20.0
			var duration := float(duration_step) / 20.0
			combos[PREF.intensity_for_travel(travel) + "|" + PREF.pattern_for(_strokes(travel, duration, 3))] = true
	for intensity: String in PREF.INTENSITIES:
		for pattern: String in PREF.PATTERNS:
			check(combos.has(intensity + "|" + pattern),
				"manual travel and tempo reach " + intensity + " & " + pattern)

	check(PREF.classify_talk("you are so beautiful") == "praise", "praise classification")
	check(PREF.classify_talk("are you okay?") == "reassurance", "reassurance classification")
	check(PREF.classify_talk("i want you") == "dirty", "dirty classification")
	check(PREF.classify_talk("how do you feel?") == "", "questions are no longer a talk category")
	check(PREF.classify_talk("good girl") == "playful", "playful classification")
	check(PREF.classify_talk("hello") == "", "unrelated talk is neutral")
	check(PREF.classify_talk("") == "", "empty talk is neutral")

	var preference := PREF.resolve({
		"intensity": "rough",
		"pattern": "teasing",
		"touch": ["smack", "nonsense"],
		"dislikes": ["smack", "kiss"],
		"talk": ["praise", "nonsense"],
		"warmth": "quick",
		"tolerance": "strict",
		"notes": "  private  ",
	})
	check(str(preference.get("intensity", "")) == "rough", "valid intensity kept")
	check(str(preference.get("pattern", "")) == "teasing", "valid pattern kept")
	check(str(preference.get("warmth", "")) == "quick", "valid warmth kept")
	check(str(preference.get("tolerance", "")) == "strict", "valid tolerance kept")
	check((preference["touch"] as Array).has("smack"), "liked touch kept")
	check(not (preference["touch"] as Array).has("nonsense"), "unknown touch dropped")
	check(not (preference["dislikes"] as Array).has("smack"), "liked/disliked overlap removed")
	check((preference["dislikes"] as Array).has("kiss"), "valid dislike kept")
	check(str(preference.get("notes", "")) == "private", "notes trimmed")

	var described := PREF.describe(preference)
	check(described.contains("intensity: rough"), "describe intensity")
	check(described.contains("likes touch: smack"), "describe touch")
	check(described.contains("likes talk: praise"), "describe talk")
	check(described.contains("warmth: quick"), "describe warmth")
	check(described.contains("tolerance: strict"), "describe tolerance")
	check(PREF.warmth_scale(preference) > 1.0, "quick warmth scales up")
	check(PREF.warmth_scale(PREF.resolve({"warmth": "slow"})) < 1.0, "slow warmth scales down")
	check(PREF.tolerance_tier("timid") == "forgiving", "old timid maps to forgiving")
	check(PREF.tolerance_tier("neutral") == "normal", "old neutral maps to normal")
	check(str(PREF.resolve({"intensity": "nonsense"}).get("intensity", "")) == "firm",
		"unknown intensity falls back")

	print("PREFERENCES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PREFERENCES_PASS")
	quit(0 if failures == 0 else 1)


func _strokes(travel: float, duration: float, count: int) -> Array:
	var out: Array = []
	for _index in count:
		out.append({"travel": travel, "duration": duration})
	return out
