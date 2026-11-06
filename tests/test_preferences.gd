extends SceneTree
## Pure taste/pattern/talk-classifier tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_preferences.gd

const PREF := preload("res://mods/unfplap/preferences.gd")
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

	check(PREF.pattern_for([]) == "", "no pattern without strokes")
	check(PREF.pattern_for(_strokes(0.60, 0.40, 3)) == "steady", "steady pattern")
	check(PREF.pattern_for(_strokes(0.30, 0.90, 3)) == "teasing", "teasing pattern")
	check(PREF.pattern_for(_strokes(0.50, 0.20, 3)) == "quick", "quick pattern")
	check(PREF.pattern_for(_strokes(0.90, 0.20, 3)) == "quick",
		"a deep fast stroke reads quick")
	check(PREF.pattern_for(_strokes(0.90, 0.90, 3)) == "teasing",
		"a deep slow stroke reads teasing")

	check(PREF.classify_talk("you are so beautiful") == "praise", "praise classification")
	check(PREF.classify_talk("are you okay?") == "reassurance", "reassurance classification")
	check(PREF.classify_talk("i want you") == "dirty", "dirty classification")
	check(PREF.classify_talk("how do you feel?") == "curious", "curious classification")
	check(PREF.classify_talk("good girl") == "playful", "playful classification")
	check(PREF.classify_talk("hello") == "", "unrelated talk is neutral")
	check(PREF.classify_talk("") == "", "empty talk is neutral")

	var taste := PREF.resolve({
		"intensity": "rough",
		"pattern": "teasing",
		"touch": ["smack", "nonsense"],
		"dislikes": ["smack", "kiss"],
		"talk": ["praise", "nonsense"],
		"warmth": "quick",
		"tolerance": "strict",
		"notes": "  private  ",
	})
	check(str(taste.get("intensity", "")) == "rough", "valid intensity kept")
	check(str(taste.get("pattern", "")) == "teasing", "valid pattern kept")
	check(str(taste.get("warmth", "")) == "quick", "valid warmth kept")
	check(str(taste.get("tolerance", "")) == "strict", "valid tolerance kept")
	check((taste["touch"] as Array).has("smack"), "liked touch kept")
	check(not (taste["touch"] as Array).has("nonsense"), "unknown touch dropped")
	check(not (taste["dislikes"] as Array).has("smack"), "liked/disliked overlap removed")
	check((taste["dislikes"] as Array).has("kiss"), "valid dislike kept")
	check(str(taste.get("notes", "")) == "private", "notes trimmed")

	var described := PREF.describe(taste)
	check(described.contains("intensity: rough"), "describe intensity")
	check(described.contains("likes touch: smack"), "describe touch")
	check(described.contains("likes talk: praise"), "describe talk")
	check(described.contains("warmth: quick"), "describe warmth")
	check(described.contains("tolerance: strict"), "describe tolerance")
	check(PREF.warmth_scale(taste) > 1.0, "quick warmth scales up")
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
