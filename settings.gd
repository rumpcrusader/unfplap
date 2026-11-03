extends RefCounted
## Persisted mod settings outside any world save: global DEBUG LOGS, feature flags, thrust
## controls, camera-rock constants, and the default/per-character templates. A character
## inherits every field it does not override.
##
## Pre-release: the schema is intentionally breaking. `taste` is the ACTIVE-stage profile,
## `thrust` holds the mouse-control settings and `camera_rock` holds the rock spring.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const ID := "unfplap"
const FILE := "settings.json"

## Stable order for the settings-tab pony selector.
const CHARACTER_ORDER := [
	"twilight_sparkle",
	"fluttershy",
	"rarity",
	"pinkie_pie",
	"applejack",
	"rainbow_dash",
	"derpy_hooves",
	"lyra_heartstrings",
	"octavia_melody",
	"vinyl_scratch",
	"berry_punch",
	"cheerilee",
	"maud_pie",
	"trixie",
	"zecora",
	"spitfire",
]

const CHARACTER_NAMES := {
	"twilight_sparkle": "Twilight Sparkle",
	"fluttershy": "Fluttershy",
	"rarity": "Rarity",
	"pinkie_pie": "Pinkie Pie",
	"applejack": "Applejack",
	"rainbow_dash": "Rainbow Dash",
	"derpy_hooves": "Derpy Hooves",
	"lyra_heartstrings": "Lyra Heartstrings",
	"octavia_melody": "Octavia Melody",
	"vinyl_scratch": "Vinyl Scratch",
	"berry_punch": "Berry Punch",
	"cheerilee": "Cheerilee",
	"maud_pie": "Maud Pie",
	"trixie": "Trixie",
	"zecora": "Zecora",
	"spitfire": "Spitfire",
}

## Feature switches. Keep this as the single list; runtime reads it once per act.
## Renamed without migration: old keys are pruned on the next settings read.
const FEATURE_DEFAULTS := {
	"hud_readouts": true,
	"thrust_camera_rock": true,
	"idle_camera_sway": false,
	"captions_on_top": true,
	"pose2_body_sway": true,
	"pose1_body_motion": true,
	"thrust_ear_twitch": true,
	"allow_act_during_cuddle": true,
	"mute_ponese_audio": false,
	"settings_tab": true,
}

## Human labels and help for the injected settings tab. `live` flags apply without a new act.
const FEATURE_INFO := {
	"hud_readouts": {
		"label": "HUD readouts",
		"help": "Show the mood cue, readiness bar and Wants/You line. Hearts and the afterglow close prompt stay visible.",
	},
	"thrust_camera_rock": {
		"label": "Thrust camera rock",
		"help": "Pitch the camera on each thrust. Tuning is under Camera rock.",
	},
	"idle_camera_sway": {
		"label": "Idle camera sway",
		"help": "Add a slow sway when lean auto-return is off.",
	},
	"captions_on_top": {
		"label": "Captions on top",
		"help": "Move the explicit bottom dialogue caption to the top. Overhead and auto captions are unchanged.",
		"live": true,
	},
	"pose2_body_sway": {
		"label": "Pose 2 body sway",
		"help": "Move her upper body with the thrust while the forehooves stay planted.",
	},
	"pose1_body_motion": {
		"label": "Pose 1 body motion",
		"help": "Slide her body along the bed and nod her head on the thrust.",
	},
	"thrust_ear_twitch": {
		"label": "Thrust ear twitch",
		"help": "Flick both ears on some thrusts.",
	},
	"allow_act_during_cuddle": {
		"label": "Allow acts during cuddles",
		"help": "End an active cuddle when an act starts instead of blocking it.",
	},
	"mute_ponese_audio": {
		"label": "Mute Ponese audio",
		"help": "Keep the act's generated text but silence the Ponese voice for that act.",
	},
	"settings_tab": {
		"label": "Unfplap settings tab",
		"help": "Show the Unfplap settings page. Turning this off hides it on the next settings open; edit settings.json to restore it.",
	},
}

## Camera-rock spring. `impulse` is the kick in radians per second; `limit` is the maximum
## absolute angle in radians. `roll_ratio` defaults to zero so the thrust rock is pitch-only;
## set it back toward 1.0 to bring the roll back.
const CAMERA_ROCK_DEFAULTS := {
	"impulse": 0.50,
	"stiffness": 45.0,
	"damping": 8.0,
	"limit": 0.055,
	"pitch_ratio": 1.0,
	"roll_ratio": 0.0,
}

const DEFAULT_ACT_PROMPTS := {
	"utterance": "You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. Your taste is private, not a list to say. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
	"cue": "During sex with Anon, your body and voice show: {cue} Say ONE short line in your own voice, at most 12 words. Begin with [whispering], [happy], [annoyed] or [surprised]. No narration, no stage directions, no anatomy. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
	"talk_cue": "During sex with Anon, you want to hear his voice. Ask him ONE short question in your own voice, at most 10 words. Begin with [whispering]. No narration, no anatomy. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
}

const DEFAULT_TEMPLATE := {
	"smack_zone_radius": 0.035,
	"aftercare_min": 10,
	"event_prompts": {
		"climax": "",
		"end_early": "",
		"inside": "",
		"stay_close": "",
	},
	"act_prompts": {},
	"taste": {},
}

## Explicit character examples; every other pony inherits the neutral default.
const CHARACTER_TEMPLATES := {
	"fluttershy": {
		"event_prompts": {
			"climax": "You have just climaxed during intimacy with Anon. Say ONE short sentence, at most 12 words, in your own voice. Something like \"Oh goodness, oh goodness...\" fits, but keep the flustered baseline. Do not describe anatomy.",
		},
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress"],
			"dislikes": ["smack"],
			"talk": ["reassurance"],
			"warmth": "slow",
			"recovery": 12,
			"notes": "You are secretly overwhelmed by how much you enjoy being taken hard and deep. You would never admit it plainly: praise comes out flustered and reluctant, and complaints are apologetic rather than demanding.",
		},
		"poses": {"missionary": {"hind_spread": 0.45}},
	},
	"rarity": {
		"taste": {
			"intensity": "soft",
			"pattern": "steady",
			"touch": ["caress"],
			"dislikes": ["smack", "dirty"],
			"talk": ["praise"],
			"warmth": "normal",
			"recovery": 18,
			"notes": "You want slow, deliberate, elegant lovemaking. Brute force is crude; you say so with dry, refined disdain, never panic or whining.",
		},
	},
	"twilight_sparkle": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["kiss"],
			"talk": ["curious", "praise"],
			"warmth": "normal",
			"recovery": 20,
			"notes": "You like being understood. Ask what he notices, praise effort, and let curiosity lead. Deliberate beats rough.",
		},
	},
	"derpy_hooves": {
		"taste": {
			"intensity": "rough",
			"pattern": "quick",
			"touch": ["smack"],
			"talk": ["playful"],
			"warmth": "quick",
			"recovery": 35,
			"notes": "You are unpretentious and playful. You like being handled, laugh easily, and never want the moment to feel solemn.",
		},
	},
	"pinkie_pie": {
		"taste": {
			"intensity": "firm",
			"pattern": "quick",
			"touch": ["smack"],
			"talk": ["playful"],
			"warmth": "quick",
			"recovery": 35,
			"notes": "You want it playful and a little silly. Laughter belongs here; keep it light, eager and never solemn.",
		},
	},
	"applejack": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress", "smack"],
			"talk": ["praise", "reassurance"],
			"warmth": "normal",
			"recovery": 24,
			"notes": "You are honest and grounded. A firm, equal hand and plain praise land best.",
		},
	},
	"rainbow_dash": {
		"taste": {
			"intensity": "rough",
			"pattern": "quick",
			"touch": ["smack"],
			"talk": ["praise", "playful"],
			"warmth": "quick",
			"recovery": 30,
			"notes": "You are competitive and bold. Momentum, a challenge and being told you are impressive matter more than softness.",
		},
	},
	"lyra_heartstrings": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress", "kiss"],
			"talk": ["curious", "playful"],
			"warmth": "normal",
			"recovery": 22,
			"notes": "You are curious about everything, especially him. Ask questions, follow tangents and keep it a little strange.",
		},
	},
	"octavia_melody": {
		"taste": {
			"intensity": "soft",
			"pattern": "steady",
			"touch": ["caress"],
			"dislikes": ["smack", "dirty"],
			"talk": ["praise"],
			"warmth": "slow",
			"recovery": 15,
			"notes": "You want a measured, elegant pace and to be appreciated for your restraint. Crudeness breaks the mood.",
		},
	},
	"vinyl_scratch": {
		"taste": {
			"intensity": "rough",
			"pattern": "quick",
			"touch": ["smack", "kiss"],
			"talk": ["playful"],
			"warmth": "quick",
			"recovery": 32,
			"notes": "You are loud, casual and physical. You like momentum, teasing and not taking any of it too seriously.",
		},
	},
	"berry_punch": {
		"taste": {
			"intensity": "rough",
			"pattern": "quick",
			"touch": ["smack"],
			"talk": ["playful", "dirty"],
			"warmth": "quick",
			"recovery": 30,
			"notes": "You are uninhibited and mischievous. You say what you want and like being grabbed, teased and answered in kind.",
		},
	},
	"cheerilee": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress"],
			"talk": ["praise", "reassurance"],
			"warmth": "normal",
			"recovery": 20,
			"notes": "You are warm, patient and encouraging. You notice when he listens and like being told you are doing well.",
		},
	},
	"maud_pie": {
		"taste": {
			"intensity": "soft",
			"pattern": "steady",
			"touch": ["caress"],
			"dislikes": ["smack", "dirty"],
			"talk": [],
			"warmth": "slow",
			"recovery": 10,
			"notes": "You are stone-steady and spare with words. Affection is stillness and small deliberate touches. Do not fill the silence.",
		},
	},
	"trixie": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["kiss"],
			"talk": ["praise", "playful"],
			"warmth": "quick",
			"recovery": 28,
			"notes": "You are theatrical and proud. You want admiration and applause, and get flustered when he sees through the act.",
		},
	},
	"zecora": {
		"taste": {
			"intensity": "firm",
			"pattern": "steady",
			"touch": ["caress"],
			"dislikes": ["smack"],
			"talk": ["curious", "reassurance"],
			"warmth": "slow",
			"recovery": 18,
			"notes": "You are measured, private and poetic. You like real questions and time to answer; do not rush the words.",
		},
	},
	"spitfire": {
		"taste": {
			"intensity": "rough",
			"pattern": "quick",
			"touch": ["smack"],
			"talk": ["praise", "playful"],
			"warmth": "normal",
			"recovery": 26,
			"notes": "You are competitive and direct. You like confidence, a firm hand and being told you can take it.",
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


static func taste(id: String) -> Dictionary:
	var template := template_for(id)
	var value: Variant = template.get("taste", {})
	if value is Dictionary:
		return PREFERENCES.resolve(value)
	return PREFERENCES.defaults()


static func character_name(id: String) -> String:
	if CHARACTER_NAMES.has(id):
		return str(CHARACTER_NAMES[id])
	return id.replace("_", " ").capitalize()


## Save only the taste block. Character prompts and pose settings are preserved.
static func save_taste(id: String, taste: Dictionary) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	var roster: Dictionary = characters
	var entry: Variant = roster.get(id, {})
	if not entry is Dictionary:
		entry = {}
	var character: Dictionary = entry
	character["taste"] = PREFERENCES.resolve(taste)
	roster[id] = character
	data["characters"] = roster
	_write(data)


## Remove only the taste override; the generated/default taste returns. Prompts and poses stay.
static func reset_taste(id: String) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	var roster: Dictionary = characters
	var entry: Variant = roster.get(id, {})
	if entry is Dictionary:
		(entry as Dictionary).erase("taste")
		if (entry as Dictionary).is_empty():
			roster.erase(id)
		else:
			roster[id] = entry
	else:
		roster.erase(id)
	data["characters"] = roster
	_write(data)


## One read for the global thrust controls; oriented so the runtime and HUD share the same flag.
static func thrust_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("thrust", {})
	var orientation := "up"
	var pixels := 480.0
	var camera_bob := false
	var camera_motion := false
	if block is Dictionary:
		orientation = str((block as Dictionary).get("orientation", "up")).to_lower()
		pixels = float((block as Dictionary).get("pixels_per_full", 480.0))
		# Old combined toggle: both split toggles inherit it until the next save.
		var legacy_bobs := bool((block as Dictionary).get("bobs", false))
		camera_bob = bool((block as Dictionary).get("camera_bob", legacy_bobs))
		camera_motion = bool((block as Dictionary).get("camera_motion", legacy_bobs))
	if orientation not in ["up", "down"]:
		orientation = "up"
	return {
		"orientation": orientation,
		"up": orientation == "up",
		"pixels_per_full": clampf(pixels, 240.0, 1200.0),
		"camera_bob": camera_bob,
		"camera_motion": camera_motion,
	}


## Save only the thrust block. Other settings and character overrides are preserved.
static func save_thrust_controls(up: bool, pixels_per_full: float,
		camera_bob: bool, camera_motion: bool) -> void:
	var data := _read()
	var block: Variant = data.get("thrust", {})
	if not block is Dictionary:
		block = {}
	var controls: Dictionary = block
	controls["orientation"] = "up" if up else "down"
	controls["pixels_per_full"] = clampf(pixels_per_full, 240.0, 1200.0)
	controls["camera_bob"] = camera_bob
	controls["camera_motion"] = camera_motion
	controls.erase("bobs")
	data["thrust"] = controls
	_write(data)


## One read for the camera-rock constants; the runtime reads it once per act.
static func camera_rock_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("camera_rock", {})
	var out: Dictionary = CAMERA_ROCK_DEFAULTS.duplicate(true)
	if block is Dictionary:
		for key: String in out:
			if (block as Dictionary).has(key):
				out[key] = float((block as Dictionary)[key])
	out["impulse"] = clampf(float(out["impulse"]), 0.0, 2.0)
	out["stiffness"] = clampf(float(out["stiffness"]), 5.0, 200.0)
	out["damping"] = clampf(float(out["damping"]), 0.0, 50.0)
	out["limit"] = clampf(float(out["limit"]), 0.0, 0.35)
	out["pitch_ratio"] = clampf(float(out["pitch_ratio"]), 0.0, 2.0)
	out["roll_ratio"] = clampf(float(out["roll_ratio"]), 0.0, 2.0)
	return out


## Save only the camera-rock block. Other settings and character overrides are preserved.
static func save_camera_rock_controls(values: Dictionary) -> void:
	var data := _read()
	var block: Variant = data.get("camera_rock", {})
	if not block is Dictionary:
		block = {}
	var controls: Dictionary = block
	controls["impulse"] = clampf(float(values.get(
		"impulse", CAMERA_ROCK_DEFAULTS["impulse"])), 0.0, 2.0)
	controls["stiffness"] = clampf(float(values.get(
		"stiffness", CAMERA_ROCK_DEFAULTS["stiffness"])), 5.0, 200.0)
	controls["damping"] = clampf(float(values.get(
		"damping", CAMERA_ROCK_DEFAULTS["damping"])), 0.0, 50.0)
	controls["limit"] = clampf(float(values.get(
		"limit", CAMERA_ROCK_DEFAULTS["limit"])), 0.0, 0.35)
	controls["pitch_ratio"] = clampf(float(values.get(
		"pitch_ratio", CAMERA_ROCK_DEFAULTS["pitch_ratio"])), 0.0, 2.0)
	controls["roll_ratio"] = clampf(float(values.get(
		"roll_ratio", CAMERA_ROCK_DEFAULTS["roll_ratio"])), 0.0, 2.0)
	data["camera_rock"] = controls
	_write(data)


static func aftercare_min(id: String) -> int:
	return clampi(int(template_for(id).get("aftercare_min", 10)), 0, 100)


## The merged default + per-character template actually used at runtime, with pose and taste
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
	selected = _fill_taste(selected)
	selected = _fill_prompts(selected)
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
	_migrate_thrust_block(data)
	data = _merge(_defaults(), data)
	data["features"] = prune_features(data.get("features", {}))
	_write(data)
	return data


## Split the old combined `thrust.bobs` into its two controls before defaults are merged.
static func _migrate_thrust_block(data: Dictionary) -> void:
	var block: Variant = data.get("thrust", {})
	if not block is Dictionary:
		return
	var thrust_block: Dictionary = block
	if not thrust_block.has("bobs"):
		return
	var legacy := bool(thrust_block["bobs"])
	# Until this split existed, `bobs` was the only source of truth. Let it win over any
	# default-written camera keys, then drop it.
	thrust_block["camera_bob"] = legacy
	thrust_block["camera_motion"] = legacy
	thrust_block.erase("bobs")
	data["thrust"] = thrust_block


static func _defaults() -> Dictionary:
	return {
		"debug_logs": true,
		"features": FEATURE_DEFAULTS.duplicate(true),
		"thrust": {
			"orientation": "up",
			"pixels_per_full": 480.0,
			"camera_bob": false,
			"camera_motion": false,
		},
		"camera_rock": CAMERA_ROCK_DEFAULTS.duplicate(true),
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
	}


## Keep only current flags, fill missing defaults, and drop retired/renamed keys. Shared by
## the disk read path and the pure settings tests.
static func prune_features(block: Variant) -> Dictionary:
	var out: Dictionary = FEATURE_DEFAULTS.duplicate(true)
	if block is Dictionary:
		for key: String in FEATURE_DEFAULTS:
			if (block as Dictionary).has(key):
				out[key] = bool((block as Dictionary)[key])
	return out


## The merged feature switches. Unknown/missing keys are pruned to the current flag set.
static func features() -> Dictionary:
	var data := _read()
	return prune_features(data.get("features", {}))


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


## Default template plus catalog pose/taste/prompt defaults. Kept as a function so the
## catalogs are read at run time instead of baked into a const expression.
static func _filled_default() -> Dictionary:
	var out: Dictionary = DEFAULT_TEMPLATE.duplicate(true)
	out["poses"] = CATALOG.POSE_DEFAULTS.duplicate(true)
	out["taste"] = PREFERENCES.defaults()
	out["act_prompts"] = DEFAULT_ACT_PROMPTS.duplicate(true)
	return out


static func _fill_taste(template: Dictionary) -> Dictionary:
	var out: Dictionary = template.duplicate(true)
	out["taste"] = PREFERENCES.resolve(out.get("taste", {}))
	return out


## Keep only current prompt keys. Old per-stroke prompt keys are ignored, and an old
## `{preferences}` utterance is replaced rather than sent to the model with a missing value.
static func _fill_prompts(template: Dictionary) -> Dictionary:
	var out: Dictionary = template.duplicate(true)
	var prompts: Dictionary = DEFAULT_ACT_PROMPTS.duplicate(true)
	var raw: Variant = out.get("act_prompts", {})
	if raw is Dictionary:
		for key: String in DEFAULT_ACT_PROMPTS:
			if (raw as Dictionary).has(key):
				prompts[key] = str((raw as Dictionary)[key])
	if str(prompts.get("utterance", "")).contains("{preferences}"):
		prompts["utterance"] = str(DEFAULT_ACT_PROMPTS["utterance"])
	out["act_prompts"] = prompts
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
