extends RefCounted
## Persisted mod settings outside any world save: global DEBUG LOGS, feature flags, thrust
## controls, camera-thrust amounts, and the default/per-character templates. A character
## inherits every field it does not override.
##
## Pre-release: the schema is intentionally breaking. `taste` is the ACTIVE-stage profile,
## `thrust` holds the mouse-control settings, `camera_thrust` holds the two camera amounts and
## `presentation` holds shared act settings such as the glance-back speed.

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
const FEATURE_DEFAULTS := {
	"hud_readouts": true,
	"idle_camera_sway": true,
	"captions_on_top": true,
	"pose2_body_sway": true,
	"pose1_body_motion": true,
	"thrust_ear_twitch": true,
	"allow_act_during_cuddle": true,
	"mute_ponese_audio": true,
	"settings_tab": true,
}

## Human labels and help for the injected settings tab. `live` flags apply without a new act.
const FEATURE_INFO := {
	"hud_readouts": {
		"label": "HUD readouts",
		"help": "Show the mood cue, readiness bar and Wants/You line. Hearts and the afterglow close prompt stay visible.",
	},
	"idle_camera_sway": {
		"label": "Idle camera sway",
		"help": "Add a slow sway when you are not leaning.",
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

## Camera-thrust amounts, 0..1. `surge` is the forward speed-driven travel; `bob` is the
## vertical speed-driven travel. Both are read live and scale the runtime amplitudes.
const CAMERA_THRUST_DEFAULTS := {
	"surge": 1.0,
	"bob": 0.35,
}

## Shared act presentation. `glance_back_speed` is a multiplier; higher is faster.
## Missionary framing: forward/height/side move the frozen anchor; pullback is the distance
## along its own view axis. All are metres and read live.
## `torso_angle_deg` hinges Anon's pose-2 upper body forward over her.
const PRESENTATION_DEFAULTS := {
	"glance_back_speed": 2.0,
	"pose1_forward": 0.10,
	"pose1_height": -0.10,
	"pose1_side": 0.0,
	"pose1_pullback": 0.22,
	"pose1_side_lean": 0.10,
	"torso_angle_deg": 0.0,
}

const DEFAULT_ACT_PROMPTS := {
	"utterance": "You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. Your taste is private, not a list to say. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
	"cue": "During sex with Anon, your body and voice show: {cue}. Private relationship note: {relationship}. Tone: {tone}. {memory} Let the relationship and memory color the line, but keep the cue's meaning. Do not mention relationship labels, levels, numbers, or that you are following a note. Do not invent a memory beyond the one given. Say ONE short line in your own voice, at most 14 words. Begin with [whispering] or [happy]. No narration, no stage directions, no anatomy. Your taste: {taste}. Do not repeat: {recent}.",
	"talk_cue": "During sex with Anon, you want to hear his voice. Ask him ONE short question in your own voice, at most 10 words. Begin with [whispering]. No narration, no anatomy. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
}

const DEFAULT_TEMPLATE := {
	"smack_zone_radius": 0.035,
	"aftercare_min": 10,
	"cue_gap": 12.0,
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
	var pixels := 800.0
	if block is Dictionary:
		orientation = str((block as Dictionary).get("orientation", "up")).to_lower()
		pixels = float((block as Dictionary).get("pixels_per_full", 800.0))
	if orientation not in ["up", "down"]:
		orientation = "up"
	return {
		"orientation": orientation,
		"up": orientation == "up",
		"pixels_per_full": clampf(pixels, 240.0, 1200.0),
	}


## Save only the thrust block. Other settings and character overrides are preserved.
static func save_thrust_controls(up: bool, pixels_per_full: float) -> void:
	var data := _read()
	var block: Variant = data.get("thrust", {})
	if not block is Dictionary:
		block = {}
	var controls: Dictionary = block
	controls["orientation"] = "up" if up else "down"
	controls["pixels_per_full"] = clampf(pixels_per_full, 240.0, 1200.0)
	data["thrust"] = controls
	_write(data)


## The two camera-thrust amounts. Read live; 0 disables that channel.
static func camera_thrust_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("camera_thrust", {})
	var out: Dictionary = CAMERA_THRUST_DEFAULTS.duplicate(true)
	if block is Dictionary:
		for key: String in out:
			if (block as Dictionary).has(key):
				out[key] = float((block as Dictionary)[key])
	out["surge"] = clampf(float(out["surge"]), 0.0, 1.0)
	out["bob"] = clampf(float(out["bob"]), 0.0, 1.0)
	return out


## Save only the camera-thrust block. Other settings and character overrides are preserved.
static func save_camera_thrust_controls(values: Dictionary) -> void:
	var data := _read()
	var block: Variant = data.get("camera_thrust", {})
	var controls: Dictionary = block if block is Dictionary else {}
	controls["surge"] = clampf(float(values.get(
		"surge", controls.get("surge", CAMERA_THRUST_DEFAULTS["surge"]))), 0.0, 1.0)
	controls["bob"] = clampf(float(values.get(
		"bob", controls.get("bob", CAMERA_THRUST_DEFAULTS["bob"]))), 0.0, 1.0)
	data["camera_thrust"] = controls
	_write(data)


## Shared presentation timings. Read by the runtime and applied live.
static func presentation_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("presentation", {})
	var speed := float(PRESENTATION_DEFAULTS["glance_back_speed"])
	var forward := float(PRESENTATION_DEFAULTS["pose1_forward"])
	var height := float(PRESENTATION_DEFAULTS["pose1_height"])
	var side := float(PRESENTATION_DEFAULTS["pose1_side"])
	var pullback := float(PRESENTATION_DEFAULTS["pose1_pullback"])
	var side_lean := float(PRESENTATION_DEFAULTS["pose1_side_lean"])
	var torso_angle := float(PRESENTATION_DEFAULTS["torso_angle_deg"])
	if block is Dictionary:
		speed = float((block as Dictionary).get("glance_back_speed", speed))
		forward = float((block as Dictionary).get("pose1_forward", forward))
		height = float((block as Dictionary).get("pose1_height", height))
		side = float((block as Dictionary).get("pose1_side", side))
		pullback = float((block as Dictionary).get("pose1_pullback", pullback))
		side_lean = float((block as Dictionary).get("pose1_side_lean", side_lean))
		torso_angle = float((block as Dictionary).get("torso_angle_deg", torso_angle))
	# Only the user-facing glance multiplier is bounded. The missionary framing and torso
	# controls are experimental and intentionally pass through unbounded values.
	return {
		"glance_back_speed": clampf(speed, 0.25, 3.0),
		"pose1_forward": forward,
		"pose1_height": height,
		"pose1_side": side,
		"pose1_pullback": pullback,
		"pose1_side_lean": side_lean,
		"torso_angle_deg": torso_angle,
	}


static func save_presentation_controls(values: Dictionary) -> void:
	var data := _read()
	var block: Variant = data.get("presentation", {})
	var controls: Dictionary = block if block is Dictionary else {}
	# Each row writes its own value; keep the other row instead of resetting it to default.
	controls["glance_back_speed"] = clampf(float(values.get(
		"glance_back_speed", controls.get("glance_back_speed",
			PRESENTATION_DEFAULTS["glance_back_speed"]))), 0.25, 3.0)
	controls["pose1_forward"] = float(values.get(
		"pose1_forward", controls.get("pose1_forward",
			PRESENTATION_DEFAULTS["pose1_forward"])))
	controls["pose1_height"] = float(values.get(
		"pose1_height", controls.get("pose1_height",
			PRESENTATION_DEFAULTS["pose1_height"])))
	controls["pose1_side"] = float(values.get(
		"pose1_side", controls.get("pose1_side",
			PRESENTATION_DEFAULTS["pose1_side"])))
	controls["pose1_pullback"] = float(values.get(
		"pose1_pullback", controls.get("pose1_pullback",
			PRESENTATION_DEFAULTS["pose1_pullback"])))
	controls["pose1_side_lean"] = float(values.get(
		"pose1_side_lean", controls.get("pose1_side_lean",
			PRESENTATION_DEFAULTS["pose1_side_lean"])))
	controls["torso_angle_deg"] = float(values.get(
		"torso_angle_deg", controls.get("torso_angle_deg",
			PRESENTATION_DEFAULTS["torso_angle_deg"])))
	data["presentation"] = controls
	_write(data)


static func aftercare_min(id: String) -> int:
	return clampi(int(template_for(id).get("aftercare_min", 10)), 0, 100)


## A cue line cannot repeat faster than this per mare. Values outside the band are clamped so
## a hand-edited settings file cannot make her speak over every touch.
static func cue_gap_value(value: float) -> float:
	return clampf(value, 8.0, 30.0)


static func cue_gap(id: String) -> float:
	return cue_gap_value(float(template_for(id).get("cue_gap", 12.0)))


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
	selected["taste"] = PREFERENCES.resolve(selected.get("taste", {}))
	selected = _fill_prompts(selected)
	return _fill_pose_defaults(selected)


static func pose(id: String, pose_id: String) -> Dictionary:
	var poses: Variant = template_for(id).get("poses", {})
	if poses is Dictionary and (poses as Dictionary).has(pose_id):
		var value: Variant = (poses as Dictionary)[pose_id]
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return CATALOG.defaults(pose_id)


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
		"thrust": {
			"orientation": "up",
			"pixels_per_full": 800.0,
		},
		"camera_thrust": CAMERA_THRUST_DEFAULTS.duplicate(true),
		"presentation": PRESENTATION_DEFAULTS.duplicate(true),
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
	}


## The merged feature switches. Unknown keys are ignored; missing keys use defaults.
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


## Default template plus catalog pose/taste/prompt defaults. Kept as a function so the
## catalogs are read at run time instead of baked into a const expression.
static func _filled_default() -> Dictionary:
	var out: Dictionary = DEFAULT_TEMPLATE.duplicate(true)
	out["poses"] = CATALOG.POSE_DEFAULTS.duplicate(true)
	out["taste"] = PREFERENCES.defaults()
	out["act_prompts"] = DEFAULT_ACT_PROMPTS.duplicate(true)
	return out


## Keep only current prompt keys.
static func _fill_prompts(template: Dictionary) -> Dictionary:
	var out: Dictionary = template.duplicate(true)
	var prompts: Dictionary = DEFAULT_ACT_PROMPTS.duplicate(true)
	var raw: Variant = out.get("act_prompts", {})
	if raw is Dictionary:
		for key: String in DEFAULT_ACT_PROMPTS:
			if (raw as Dictionary).has(key):
				prompts[key] = str((raw as Dictionary)[key])
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
