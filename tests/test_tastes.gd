extends SceneTree
## Every romanceable base-game mare has a valid, explicit taste profile.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_tastes.gd

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const TASTES := preload("res://mods/unfplap/character_tastes.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

## The base game's young ponies and the two adults whose identity resource does not match
## their written profile. They must stay out of the taste roster.
const EXCLUDED := [
	"twist", "fiddly_twang", "spike",
	"apple_bloom", "sweetie_belle", "scootaloo", "diamond_tiara", "silver_spoon",
	"dinky_doo", "ruby_pinch", "archer", "noi",
]
const STALLIONS := [
	"big_mcintosh", "braeburn", "caramel", "comet_tail", "compass_star", "double_diamond",
	"dr_caballeron", "drwhooves", "flash_sentry", "igneous_rock", "jackpot", "king_sombra",
	"night_light", "noteworthy", "party_favor", "pokey_pierce", "prince_blueblood",
	"shining_armor", "soarin", "sunburst", "thunderlane",
]
const TASTE_KEYS := [
	"intensity", "pattern", "touch", "dislikes", "talk", "warmth", "tolerance",
	"notes",
]

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
	check(TASTES.ORDER.size() == 102, "one hundred and two adult mares")
	check(TASTES.ORDER.size() == TASTES.NAMES.size(), "every mare has a display name")
	check(TASTES.ORDER.size() == TASTES.TEMPLATES.size(), "every mare has a template")

	var seen: Dictionary = {}
	for id: String in TASTES.ORDER:
		check(not seen.has(id), "unique id " + id)
		seen[id] = true
		check(TASTES.NAMES.has(id) and not str(TASTES.NAMES[id]).is_empty(),
			"display name for " + id)
		check(not id in EXCLUDED, "young or mislabelled pony stays out: " + id)
		check(not id in STALLIONS, "stallions stay out: " + id)
	for id: String in TASTES.NAMES:
		check(seen.has(id), "name has an order row: " + id)
	for id: String in TASTES.TEMPLATES:
		check(seen.has(id), "template has an order row: " + id)

	var signatures: Dictionary = {}
	var intensities: Dictionary = {}
	var patterns: Dictionary = {}
	var warmth: Dictionary = {}
	var tolerances: Dictionary = {}
	var mares_with_talk := 0
	var mares_with_dislikes := 0

	for id: String in TASTES.ORDER:
		var template: Dictionary = TASTES.TEMPLATES[id]
		check(template.has("taste"), id + " has a taste block")
		var taste: Dictionary = template.get("taste", {})
		var intensity := str(taste.get("intensity", ""))
		var pattern := str(taste.get("pattern", ""))
		var touch: Array = taste.get("touch", [])
		var talk: Array = taste.get("talk", [])
		var dislikes: Array = taste.get("dislikes", [])
		var warmth_value := str(taste.get("warmth", ""))
		var tolerance := str(taste.get("tolerance", "neutral"))
		var notes := str(taste.get("notes", ""))

		check(intensity in PREFERENCES.INTENSITIES, id + " intensity")
		check(pattern in PREFERENCES.PATTERNS, id + " pattern")
		check(warmth_value in PREFERENCES.WARMTHS, id + " warmth")
		check(tolerance in PREFERENCES.TOLERANCES, id + " tolerance")
		check(not touch.is_empty(), id + " likes at least one touch")
		check(notes.begins_with("You "), id + " notes are second person")
		check(notes.length() <= 260, id + " notes stay short")
		check(not taste.has("pose"), id + " has no legacy pose key")
		for key: Variant in taste:
			check(str(key) in TASTE_KEYS, id + " has no unknown taste key: " + str(key))

		for value: Variant in touch:
			check(str(value) in PREFERENCES.TOUCHES, id + " valid liked touch: " + str(value))
		for value: Variant in talk:
			check(str(value) in PREFERENCES.TALKS, id + " valid liked talk: " + str(value))
		for value: Variant in dislikes:
			check(str(value) in PREFERENCES.TOUCHES + PREFERENCES.TALKS,
				id + " valid dislike: " + str(value))
			check(not (str(value) in touch or str(value) in talk),
				id + " dislike is not also a like: " + str(value))

		if not talk.is_empty():
			mares_with_talk += 1
		if not dislikes.is_empty():
			mares_with_dislikes += 1
		signatures["%s/%s/%s/%s/%s/%s" % [intensity, pattern, warmth_value, tolerance,
			",".join(touch), ",".join(talk)]] = true
		intensities[intensity] = true
		patterns[pattern] = true
		warmth[warmth_value] = true
		tolerances[tolerance] = true

		var resolved := PREFERENCES.resolve(taste)
		check(str(resolved.get("notes", "")) == notes.strip_edges(), id + " notes survive resolve")

	check(TASTES.ORDER.size() > 80, "the roster is the full base-game mare cast")
	check(signatures.size() >= 30, "profiles are varied, not one copied template")
	check(intensities.size() == PREFERENCES.INTENSITIES.size(), "every intensity appears")
	check(patterns.size() == PREFERENCES.PATTERNS.size(), "every pattern appears")
	check(warmth.size() == PREFERENCES.WARMTHS.size(), "every warmth appears")
	check(tolerances.size() == PREFERENCES.TOLERANCES.size(), "every tolerance appears")
	check(mares_with_talk >= 80, "most mares score some kind of talk")
	check(mares_with_dislikes >= 10 and mares_with_dislikes <= 30,
		"dislikes stay characterful, not universal")

	var base: Dictionary = SETTINGS._filled_default()
	var maud := SETTINGS.profile_for(base, TASTES.TEMPLATES, "maud_pie")
	check(((maud["taste"] as Dictionary).get("talk", []) as Array).is_empty(), "Maud is quiet")
	var fluttershy := SETTINGS.profile_for(base, TASTES.TEMPLATES, "fluttershy")
	check(str((fluttershy["taste"] as Dictionary).get("tolerance", "")) == "timid",
		"Fluttershy is timid")
	var poses: Dictionary = fluttershy.get("poses", {})
	check(is_equal_approx(float((poses.get(CATALOG.MISSIONARY, {}) as Dictionary).get(
		"hind_spread", 0.0)), 0.45), "Fluttershy's pose override survives")
	var prompts: Dictionary = fluttershy.get("event_prompts", {})
	check(not str(prompts.get("climax", "")).is_empty(), "Fluttershy's event prompt survives")
	var aloe := SETTINGS.profile_for(base, TASTES.TEMPLATES, "aloe")
	check(str((aloe["taste"] as Dictionary).get("notes", "")).begins_with("You "),
		"a new mare merges through settings")

	print("TASTES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("TASTES_PASS")
	quit(0 if failures == 0 else 1)
