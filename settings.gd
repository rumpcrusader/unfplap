extends RefCounted
## Persisted mod settings outside any world save: global DEBUG LOGS, experimental feature flags,
## pump controls, and the default/per-character templates. A character inherits every field it
## does not override.
##
## Pre-release: the schema is intentionally breaking. `chattiness` is gone; do not add a fallback.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const ID := "unfplap"
const FILE := "settings.json"

## Experimental switches. Keep this as the single list; runtime reads it once per act.
const FEATURE_DEFAULTS := {
	"settings_tab": true,
	"lean_return": true,
	"camera_inertia": true,
	"camera_rock": true,
	"body_sway": true,
	"rump_blush": true,
	"ear_twitch": true,
	"cuddle_override": true,
	"act_text_only_ponese": false,
}

const DEFAULT_ACT_PROMPTS := {
	"utterance": "You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. These preferences are private feelings, not a list to say. Current moment: {state}. Your preferences: {preferences}. Do not repeat: {recent}.",

	"speed_perfect": "During sex with Anon, he has found the rhythm you like. Tell him to keep it, in your own voice, at most 8 words (for example: \"Just like that, Anon\"). Begin with [happy] or [whispering]. Current moment: {state}.",
	"shape_like": "During sex with Anon, he just moved in the way you like. Ask for more of that, in your own voice, at most 10 words. Begin with [happy] or [whispering]. Current moment: {state}.",
	"shape_dislike": "During sex with Anon, he just moved in a way you do not like. Complain briefly, in your own voice, at most 10 words. Begin with [annoyed]. Current moment: {state}.",
	"depth_deep": "During sex with Anon, he is going deeper than you like. Ask him to ease back, in your own voice, at most 10 words. Begin with [annoyed] or [surprised]. Current moment: {state}.",
	"bored": "During sex with Anon, he has been going too slowly for a while. Ask him what is going on in your own voice, at most 12 words. Begin with [sad] or [annoyed]. Current moment: {state}.",
}

const DEFAULT_TEMPLATE := {
	"min_utterances": 2,
	"max_utterances": 3,
	"smack_zone_radius": 0.035,
	"climax_at": 100,
	"aftercare_min": 10,
	"event_prompts": {
		"climax": "",
		"end_early": "",
		"inside": "",
	},
	"act_prompts": {},
	"preferences": {},
}

## Three explicit character examples; every other pony inherits the neutral default.
const CHARACTER_TEMPLATES := {
	"fluttershy": {
		"min_utterances": 1,
		"max_utterances": 3,
		"event_prompts": {
			"climax": "You have just climaxed during intimacy with Anon. Say ONE short sentence, at most 12 words, in your own voice. Something like \"Oh goodness, oh goodness...\" fits, but keep the flustered baseline. Do not describe anatomy.",
		},
		"preferences": {
			"pump": {
				"depth": "deep",
				"speed": {
					"enabled": true,
					"min": 0.40,
					"perfect": 1.20,
					"max": 2.00,
					"epsilon": 0.22,
				},
				"shape": {
					"enabled": true,
					"likes": "ease_out",
					"dislikes": "ease_in_out",
				},
				"notes": "You are secretly overwhelmed by how much you enjoy being taken hard and deep. You would never admit it plainly: praise comes out flustered and reluctant, and complaints are apologetic rather than demanding.",
				"phases": [
					{
						"min_satisfaction": 0.75,
						"max_satisfaction": 1.0,
						"depth": "deep",
						"speed": {
							"enabled": true,
							"min": 0.60,
							"perfect": 1.60,
							"max": 2.60,
							"epsilon": 0.28,
						},
						"shape": {
							"enabled": true,
							"likes": "ease_out",
							"dislikes": "ease_in_out",
						},
						"notes": "Above three quarters you stop hiding it: you want it harder and faster, and you say so, still flustered.",
					},
				],
			},
		},
		"poses": {"missionary": {"hind_spread": 0.45}},
	},
	"rarity": {
		"min_utterances": 2,
		"max_utterances": 3,
		"preferences": {
			"pump": {
				"depth": "shallow",
				"speed": {
					"enabled": true,
					"min": 0.20,
					"perfect": 0.50,
					"max": 1.00,
					"epsilon": 0.10,
				},
				"shape": {
					"enabled": true,
					"likes": "ease_in_out",
					"dislikes": "ease_out",
				},
				"notes": "You want slow, deliberate, elegant lovemaking. Brute force is crude; you say so with dry, refined disdain, never panic or whining.",
			},
		},
	},
	"twilight_sparkle": {
		"min_utterances": 2,
		"max_utterances": 3,
		"preferences": {
			"pump": {
				"notes": "You have no strong preference; you respond to the moment and to Anon.",
			},
		},
	},
}


static func _path() -> String:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		var mods: Node = loop.root.get_node_or_null("Mods")
		if mods != null and mods.has_method("data_folder"):
			return str(mods.call("data_folder", ID)).path_join(FILE)
	return "user://mods/data/%s/%s" % [ID, FILE]


static func load_debug_logs() -> bool:
	var data := _read()
	return bool(data.get("debug_logs", true))


static func save_debug_logs(value: bool) -> void:
	var data := _read()
	data["debug_logs"] = value
	_write(data)


static func utterance_range(id: String) -> Vector2i:
	var template := template_for(id)
	var low := clampi(int(template.get("min_utterances", 2)), 0, 3)
	var high := clampi(int(template.get("max_utterances", 3)), 0, 3)
	if low > high:
		var swap := low
		low = high
		high = swap
	return Vector2i(low, high)


static func act_prompt(id: String, key: String) -> String:
	var prompts: Variant = template_for(id).get("act_prompts", {})
	if prompts is Dictionary:
		return str((prompts as Dictionary).get(key, ""))
	return ""


static func event_prompt(id: String, event: String) -> String:
	var prompts: Variant = template_for(id).get("event_prompts", {})
	if prompts is Dictionary:
		return str((prompts as Dictionary).get(event, ""))
	return ""


static func preferences(id: String) -> Dictionary:
	var template := template_for(id)
	var prefs: Variant = template.get("preferences", {})
	if prefs is Dictionary:
		var pump: Variant = (prefs as Dictionary).get("pump", {})
		if pump is Dictionary:
			return (pump as Dictionary).duplicate(true)
	return PREFERENCES.defaults()


## One read for the global pump controls; oriented so the runtime and HUD share the same flag.
static func pump_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("pump", {})
	var orientation := "up"
	var pixels := 600.0
	var bobs := false
	if block is Dictionary:
		orientation = str((block as Dictionary).get("orientation", "up")).to_lower()
		pixels = float((block as Dictionary).get("pixels_per_full", 600.0))
		bobs = bool((block as Dictionary).get("bobs", false))
	if orientation not in ["up", "down"]:
		orientation = "up"
	return {
		"orientation": orientation,
		"up": orientation == "up",
		"pixels_per_full": clampf(pixels, 80.0, 2000.0),
		"bobs": bobs,
	}


static func climax_at(id: String) -> int:
	return clampi(int(template_for(id).get("climax_at", 100)), 1, 100)


static func aftercare_min(id: String) -> int:
	return clampi(int(template_for(id).get("aftercare_min", 10)), 0, 100)


## The merged default + per-character template actually used at runtime, with pose and preference
## blocks filled from their catalogs.
static func template_for(id: String) -> Dictionary:
	var data := _read()
	return profile_for(
		data.get("default", _filled_default()),
		data.get("characters", {}),
		id)


## Pure merge for tests and for `template_for`.
static func profile_for(base: Dictionary, characters: Variant, id: String) -> Dictionary:
	var selected: Dictionary = base.duplicate(true)
	if characters is Dictionary and (characters as Dictionary).has(id):
		var over: Variant = (characters as Dictionary)[id]
		if over is Dictionary:
			selected = _merge(selected, over)
	selected = _fill_preferences(selected)
	return _fill_pose_defaults(selected)


static func pose(id: String, pose_id: String) -> Dictionary:
	var poses: Variant = template_for(id).get("poses", {})
	if poses is Dictionary and (poses as Dictionary).has(pose_id):
		var value: Variant = (poses as Dictionary)[pose_id]
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return CATALOG.defaults(pose_id)


static func set_character_override(id: String, override: Dictionary) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	characters[id] = override
	data["characters"] = characters
	_write(data)


static func _read() -> Dictionary:
	var path := _path()
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	data = _merge(_defaults(), data)
	_write(data)
	return data


static func _defaults() -> Dictionary:
	return {
		"debug_logs": true,
		"features": FEATURE_DEFAULTS.duplicate(true),
		"pump": {
			"orientation": "up",
			"pixels_per_full": 600.0,
			"bobs": false,
		},
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
	}


## The merged experimental feature switches, with unknown/missing keys off.
static func features() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("features", {})
	var out: Dictionary = FEATURE_DEFAULTS.duplicate(true)
	if block is Dictionary:
		for key: String in FEATURE_DEFAULTS:
			if (block as Dictionary).has(key):
				out[key] = bool((block as Dictionary)[key])
	return out


static func feature(name: String) -> bool:
	if not FEATURE_DEFAULTS.has(name):
		return false
	return bool(features().get(name, false))


static func save_feature(name: String, value: bool) -> void:
	if not FEATURE_DEFAULTS.has(name):
		return
	var data := _read()
	var block: Variant = data.get("features", {})
	if not block is Dictionary:
		block = {}
	(block as Dictionary)[name] = value
	data["features"] = block
	_write(data)


## Default template plus catalog pose/preference/prompt defaults. Kept as a function so the
## catalogs are read at run time instead of baked into a const expression.
static func _filled_default() -> Dictionary:
	var out: Dictionary = DEFAULT_TEMPLATE.duplicate(true)
	out["poses"] = CATALOG.POSE_DEFAULTS.duplicate(true)
	out["preferences"] = {"pump": PREFERENCES.defaults()}
	out["act_prompts"] = DEFAULT_ACT_PROMPTS.duplicate(true)
	return out


static func _fill_preferences(template: Dictionary) -> Dictionary:
	var out: Dictionary = template.duplicate(true)
	var prefs: Variant = out.get("preferences", {})
	if not prefs is Dictionary:
		prefs = {}
	var pump: Variant = (prefs as Dictionary).get("pump", {})
	(prefs as Dictionary)["pump"] = PREFERENCES.resolve(pump)
	out["preferences"] = prefs
	return out


static func _fill_pose_defaults(template: Dictionary) -> Dictionary:
	var out: Dictionary = template.duplicate(true)
	var poses: Variant = out.get("poses", {})
	var merged: Dictionary = {}
	for pose_id: String in CATALOG.all():
		var over: Variant = (poses as Dictionary).get(pose_id, {}) if poses is Dictionary else {}
		var base: Dictionary = CATALOG.defaults(pose_id)
		merged[pose_id] = _merge(base, over if over is Dictionary else {})
	out["poses"] = merged
	return out


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = _merge(out[key], value)
		else:
			out[key] = value
	return out


static func _write(data: Dictionary) -> void:
	var path := _path()
	var folder := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
