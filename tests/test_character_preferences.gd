extends SceneTree
## The base-game character catalog is an explicit, adult, well-formed preference profile for every
## roster mare. One validation pass per row, plus the settings merge for one catalog mare.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_character_preferences.gd

const PROFILES := preload("res://mods/unfplap/shared/character_preferences.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

## The base game's young ponies and the two adults whose identity resource does not match
## their written profile. They must stay out of the preference roster.
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
	var seen: Dictionary = {}
	var duplicates: PackedStringArray = []
	for id: Variant in PROFILES.ORDER:
		var key := str(id)
		if seen.has(key):
			duplicates.append(key)
		seen[key] = true
	check(duplicates.is_empty(), "roster ids are unique: " + ", ".join(duplicates))

	var unordered: PackedStringArray = []
	for id: Variant in PROFILES.NAMES:
		if not seen.has(str(id)):
			unordered.append("name " + str(id))
	for id: Variant in PROFILES.TEMPLATES:
		if not seen.has(str(id)):
			unordered.append("template " + str(id))
	check(unordered.is_empty(), "every name and template has an order row: " + ", ".join(unordered))

	var incomplete: PackedStringArray = []
	for id: Variant in PROFILES.ORDER:
		if not PROFILES.NAMES.has(id):
			incomplete.append("name " + str(id))
		if not PROFILES.TEMPLATES.has(id):
			incomplete.append("template " + str(id))
	check(incomplete.is_empty(), "every order row has a display name and a template: "
		+ ", ".join(incomplete))

	var unresolved: PackedStringArray = []
	for id: Variant in PROFILES.ORDER:
		var problem := _row_problem(str(id))
		check(problem.is_empty(), "row %s: %s" % [str(id), problem])
		var template: Dictionary = PROFILES.TEMPLATES.get(id, {})
		var notes := str((template.get("preferences", {}) as Dictionary).get("notes", ""))
		if str(PREFERENCES.resolve(template.get("preferences", {})).get("notes", "")) \
				!= notes.strip_edges():
			unresolved.append(str(id))
	check(unresolved.is_empty(), "resolve keeps every note: " + ", ".join(unresolved))

	var base: Dictionary = SETTINGS.data().get("default", {})
	var merged: Dictionary = SETTINGS.profile_for(base, {}, "aloe")
	var merged_preference: Dictionary = merged.get("preferences", {})
	check(str(merged_preference.get("notes", "")).begins_with("You ")
		and not (merged_preference.get("touch", []) as Array).is_empty(),
		"a catalog mare's profile merges through the settings service")

	print("CHARACTER_PREFERENCES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CHARACTER_PREFERENCES_PASS")
	quit(0 if failures == 0 else 1)


## The whole row schema. A non-empty result names the first broken rule; the caller prints it with
## the row id so one failing mare does not hide the rest.
func _row_problem(id: String) -> String:
	if id in EXCLUDED:
		return "a young or mislabelled pony is not romanceable"
	if id in STALLIONS:
		return "a stallion is not an adult mare"
	if str(PROFILES.NAMES.get(id, "")).strip_edges().is_empty():
		return "no display name"
	var template: Variant = PROFILES.TEMPLATES.get(id, null)
	if not template is Dictionary or (template as Dictionary).is_empty():
		return "no shipped template"
	var preference: Variant = (template as Dictionary).get("preferences", null)
	if not preference is Dictionary:
		return "no preferences block"
	var pref: Dictionary = preference
	for key: Variant in pref:
		var name := str(key)
		if name == "pose":
			return "has the legacy pose key"
		if not name in PREFERENCES.KEYS:
			return "unknown preference key " + name
	var intensity := str(pref.get("intensity", ""))
	if not intensity in PREFERENCES.INTENSITIES:
		return "invalid intensity " + intensity
	var pattern := str(pref.get("pattern", ""))
	if not pattern in PREFERENCES.PATTERNS:
		return "invalid pattern " + pattern
	var warmth := str(pref.get("warmth", ""))
	if not warmth in PREFERENCES.WARMTHS:
		return "invalid warmth " + warmth
	# The main cast predates the explicit tolerance row; its absence resolves to `normal`.
	var tolerance := str(pref.get("tolerance", "normal"))
	if not tolerance in PREFERENCES.TOLERANCES:
		return "invalid tolerance " + tolerance
	var touch: Variant = pref.get("touch", [])
	if not touch is Array or (touch as Array).is_empty():
		return "likes no touch"
	for value: Variant in (touch as Array):
		if not str(value) in PREFERENCES.TOUCHES:
			return "unknown liked touch " + str(value)
	var talk: Variant = pref.get("talk", [])
	if not talk is Array:
		return "talk is not a list"
	for value: Variant in (talk as Array):
		if not str(value) in PREFERENCES.TALKS:
			return "unknown talk " + str(value)
	var dislikes: Variant = pref.get("dislikes", [])
	if not dislikes is Array:
		return "dislikes is not a list"
	for value: Variant in (dislikes as Array):
		var key := str(value)
		if not (key in PREFERENCES.TOUCHES or key in PREFERENCES.TALKS):
			return "unknown dislike " + key
		if key in (touch as Array) or key in (talk as Array):
			return "a dislike is also a like: " + key
	var notes := str(pref.get("notes", ""))
	if not notes.begins_with("You "):
		return "notes are not second person"
	if notes.length() > 260:
		return "notes are too long"
	return ""
