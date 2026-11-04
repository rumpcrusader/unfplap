extends RefCounted
## Persisted mod settings outside any world save: global DEBUG LOGS, feature flags, thrust
## controls, camera-thrust amounts, presentation tuning and the default/per-character templates.
## A character inherits every field it does not override.
##
## Pre-release: the schema is intentionally breaking. `taste` is the ACTIVE-stage profile,
## `thrust` holds the mouse-control settings, `camera_thrust` holds the two camera amounts and
## `presentation` is split into `missionary` and `standing` blocks.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const ID := "unfplap"
const FILE := "settings.json"
## One-release migration for settings written before the poses were renamed. These tables are
## the only place the legacy ids and keys are kept; remove them after the migration window.
const LEGACY_POSE_ID := "horse"
const LEGACY_FEATURE_KEYS := {
	"pose1_body_motion": "missionary_body_motion",
	"pose2_body_sway": "standing_body_sway",
}
const LEGACY_PRESENTATION_KEYS := {
	"pose1_forward": "forward",
	"pose1_height": "height",
	"pose1_side": "side",
	"pose1_pullback": "pullback",
	"pose1_side_lean": "side_lean",
	"pose1_pitch_deg": "pitch_deg",
}
const LEGACY_DROPPED_KEYS := ["pose1_camera"]

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

## Feature switches live in the tunable schema under `features.`. These helpers expose the
## feature-key view the runtime and the settings tab use.
static func feature_keys() -> Array:
	var out: Array = []
	for path: String in SCHEMA.all():
		if path.begins_with("features."):
			out.append(path.substr("features.".length()))
	return out


## Every feature switch with its schema default.
static func feature_defaults() -> Dictionary:
	return SCHEMA.default_block("features.")


## Player-facing flags: the Controls section of the Settings tab.
static func feature_user() -> Array:
	var out: Array = []
	for key: String in feature_keys():
		if str(SCHEMA.entry("features." + key).get("tab", "")) == SCHEMA.SETTINGS_TAB:
			out.append(key)
	return out


## One feature's schema entry, with label and help for a control row.
static func feature_info(name: String) -> Dictionary:
	return SCHEMA.entry("features." + name)


## Body-size presets exposed by the caress palm-scale selector.
const CARESS_SIZES := ["canon", "mounting", "same height", "hoers"]
## Regions the caress contact query may skip. `tail` is on by default.
const CARESS_IGNORE_REGIONS := ["tail", "mane", "wing", "leg"]

const DEFAULT_ACT_PROMPTS := {
	"utterance": "You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. Your taste is private, not a list to say. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
	"cue": "During sex with Anon, your body and voice show: {cue}. Private relationship note: {relationship}. Tone: {tone}. {memory} Let the relationship and memory color the line, but keep the cue's meaning. Do not mention relationship labels, levels, numbers, or that you are following a note. Do not invent a memory beyond the one given. Say ONE short line in your own voice, at most 14 words. Begin with [whispering] or [happy]. No narration, no stage directions, no anatomy. Your taste: {taste}. Do not repeat: {recent}.",
}

const DEFAULT_TEMPLATE := {
	"smack_zone_radius": 0.035,
	"aftercare_min": 10,
	"cue_gap": 12.0,
	"event_prompts": {
		"climax": "",
		"end_early": "",
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
	return bool(data.get("debug_logs", false))


static func save_debug_logs(on: bool) -> void:
	var data := _read()
	data["debug_logs"] = on
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
	var pixels := 1000.0
	var travel := 1.0
	if block is Dictionary:
		orientation = str((block as Dictionary).get("orientation", "up")).to_lower()
		pixels = float((block as Dictionary).get("pixels_per_full", 1000.0))
		travel = float((block as Dictionary).get("travel", 2.0))
	if orientation not in ["up", "down"]:
		orientation = "up"
	return {
		"orientation": orientation,
		"up": orientation == "up",
		"pixels_per_full": clampf(pixels, 240.0, 1200.0),
		"travel": clampf(travel, 0.0, 3.0),
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


## Save only the hip travel multiplier. The orientation and sensitivity are preserved.
static func save_thrust_travel(travel: float) -> void:
	var data := _read()
	var block: Variant = data.get("thrust", {})
	var controls: Dictionary = block if block is Dictionary else {}
	controls["travel"] = clampf(travel, 0.0, 3.0)
	data["thrust"] = controls
	_write(data)


## The shared rump wobble radius and thrust intensity. Read live; both are experimental.
static func jiggle_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("jiggle", {})
	var out: Dictionary = SCHEMA.default_block("jiggle.")
	if block is Dictionary:
		out["radius"] = float((block as Dictionary).get("radius", out["radius"]))
		out["intensity"] = float((block as Dictionary).get("intensity", out["intensity"]))
		out["smack_intensity"] = float((block as Dictionary).get(
			"smack_intensity", out["smack_intensity"]))
	out["radius"] = maxf(0.02, float(out["radius"]))
	out["intensity"] = maxf(0.0, float(out["intensity"]))
	out["smack_intensity"] = maxf(0.0, float(out["smack_intensity"]))
	return out


## Save the jiggle block. Other settings and character overrides are preserved.
static func save_jiggle_controls(values: Dictionary) -> void:
	var data := _read()
	var block: Variant = data.get("jiggle", {})
	var controls: Dictionary = block if block is Dictionary else {}
	controls["radius"] = maxf(0.02, float(values.get(
		"radius", controls.get("radius", SCHEMA.default_value("jiggle.radius")))))
	controls["intensity"] = maxf(0.0, float(values.get(
		"intensity", controls.get("intensity", SCHEMA.default_value("jiggle.intensity")))))
	controls["smack_intensity"] = maxf(0.0, float(values.get(
		"smack_intensity", controls.get("smack_intensity",
		SCHEMA.default_value("jiggle.smack_intensity")))))
	data["jiggle"] = controls
	_write(data)


## The two camera-thrust amounts. Read live; 0 disables that channel.
static func camera_thrust_controls() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("camera_thrust", {})
	var out: Dictionary = SCHEMA.default_block("camera_thrust.")
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
		"surge", controls.get("surge", 1.0))), 0.0, 1.0)
	controls["bob"] = clampf(float(values.get(
		"bob", controls.get("bob", 0.35))), 0.0, 1.0)
	data["camera_thrust"] = controls
	_write(data)


## One pose's presentation block, merged with that pose's defaults and read live.
static func presentation_controls(pose_id: String) -> Dictionary:
	var data := _read()
	var block: Variant = data.get("presentation", {})
	var pose_block: Variant = {}
	if block is Dictionary:
		pose_block = (block as Dictionary).get(pose_id, {})
	var defaults: Dictionary = SCHEMA.default_block("presentation." + pose_id + ".")
	var out: Dictionary = _merge(defaults,
		pose_block if pose_block is Dictionary else {})
	if pose_id == "standing":
		out["glance_back_speed"] = clampf(float(out.get(
			"glance_back_speed", 2.0)), 0.25, 3.0)
		out["idle_sway_side"] = maxf(0.0, float(out.get("idle_sway_side", 0.0)))
		var caress: Dictionary = out.get("caress", {})
		# The palm ball's radius is 4 cm; a smaller centre distance sinks the visible palm
		# into the coat.
		caress["palm_distance"] = clampf(float(caress.get("palm_distance", 0.04)),
			0.04, 0.2)
		caress["oval_across_m"] = maxf(0.0, float(caress.get(
			"oval_across_m", 0.04125 * 1.30)))
		caress["oval_up_m"] = maxf(0.0, float(caress.get(
			"oval_up_m", 0.04125 * 0.70)))
		var scales: Dictionary = caress.get("palm_scale", {})
		for size: String in CARESS_SIZES:
			scales[size] = clampf(float(scales.get(size, 1.0)), 0.25, 2.0)
		caress["palm_scale"] = scales
		var ignore: Array = []
		var raw_ignore: Variant = caress.get("ignore", [])
		if raw_ignore is Array:
			for region: Variant in raw_ignore:
				var name := str(region).to_lower()
				if name in CARESS_IGNORE_REGIONS and not ignore.has(name):
					ignore.append(name)
		caress["ignore"] = ignore
		out["caress"] = caress
		var smack: Dictionary = out.get("smack", {})
		smack["raise_m"] = maxf(0.0, float(smack.get("raise_m", 0.30)))
		smack["hind_m"] = maxf(0.0, float(smack.get("hind_m", 0.10)))
		smack["height_m"] = float(smack.get("height_m", -0.03))
		smack["arc_m"] = maxf(0.0, float(smack.get("arc_m", 0.06)))
		smack["pitch_deg"] = float(smack.get("pitch_deg", 12.0))
		smack["raise_speed"] = maxf(0.05, float(smack.get("raise_speed", 2.0)))
		smack["return_speed"] = maxf(0.05, float(smack.get("return_speed", 6.0)))
		out["smack"] = smack
		var kiss: Dictionary = out.get("kiss", {})
		kiss["mouth_right"] = clampf(float(kiss.get("mouth_right", 0.0)), -0.5, 0.5)
		kiss["mouth_drop"] = clampf(float(kiss.get("mouth_drop", 0.07)), -0.5, 0.5)
		kiss["mouth_forward"] = clampf(float(kiss.get("mouth_forward", 0.02)), -0.5, 0.5)
		kiss["camera_yaw_deg"] = clampf(float(kiss.get("camera_yaw_deg", 10.0)), -60.0, 60.0)
		kiss["lean_side"] = clampf(float(kiss.get("lean_side", 0.18)), 0.0, 0.8)
		kiss["lean_forward"] = clampf(float(kiss.get("lean_forward", 0.27)), 0.0, 0.8)
		kiss["lean_drop"] = clampf(float(kiss.get("lean_drop", 0.035)), 0.0, 0.3)
		var forelegs := str(kiss.get("forelegs", "planted")).to_lower()
		kiss["forelegs"] = forelegs if forelegs in ["planted", "base"] else "planted"
		out["kiss"] = kiss
	return out


## Write one presentation row. `values` may contain a nested `caress` dictionary; the merge
## preserves every sibling and the other pose's block.
static func save_presentation_controls(pose_id: String, values: Dictionary) -> void:
	var data := _read()
	var block: Variant = data.get("presentation", {})
	if not block is Dictionary:
		block = {}
	var poses: Dictionary = block
	var current: Variant = poses.get(pose_id, {})
	if not current is Dictionary:
		current = {}
	poses[pose_id] = _merge(current, values)
	data["presentation"] = poses
	_write(data)


## Move a settings block written with the legacy pose id onto the current pose id. The new key
## wins if a file already has both, so an interrupted migration cannot overwrite a newer value.
static func _normalize_pose_names(data: Dictionary) -> Dictionary:
	var blocks: Array = []
	if data.get("default") is Dictionary:
		blocks.append(data["default"])
	if data.get("characters") is Dictionary:
		for entry: Variant in (data["characters"] as Dictionary).values():
			if entry is Dictionary:
				blocks.append(entry)
	for block: Dictionary in blocks:
		var poses: Variant = block.get("poses")
		if poses is Dictionary and (poses as Dictionary).has(LEGACY_POSE_ID):
			if not (poses as Dictionary).has(CATALOG.STANDING):
				(poses as Dictionary)[CATALOG.STANDING] = (poses as Dictionary)[LEGACY_POSE_ID]
			(poses as Dictionary).erase(LEGACY_POSE_ID)
	var presentation: Variant = data.get("presentation")
	if presentation is Dictionary and (presentation as Dictionary).has(LEGACY_POSE_ID):
		if not (presentation as Dictionary).has(CATALOG.STANDING):
			(presentation as Dictionary)[CATALOG.STANDING] = (presentation as Dictionary)[LEGACY_POSE_ID]
		(presentation as Dictionary).erase(LEGACY_POSE_ID)
	return data


## Move a feature block written with the legacy pose keys onto the current keys.
static func _normalize_feature_names(data: Dictionary) -> Dictionary:
	var features: Variant = data.get("features")
	if not features is Dictionary:
		return data
	for old_key: String in LEGACY_FEATURE_KEYS:
		var new_key: String = LEGACY_FEATURE_KEYS[old_key]
		if (features as Dictionary).has(old_key):
			if not (features as Dictionary).has(new_key):
				(features as Dictionary)[new_key] = (features as Dictionary)[old_key]
			(features as Dictionary).erase(old_key)
	return data


## Move the pre-split flat presentation block into pose sections. Old unknown keys are dropped
## instead of being written back forever.
static func _normalize_presentation(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("presentation")
	if not raw is Dictionary:
		return data
	var block: Dictionary = raw
	if block.has("missionary") or block.has("standing"):
		for key: String in LEGACY_PRESENTATION_KEYS:
			block.erase(key)
		for key: String in LEGACY_DROPPED_KEYS:
			block.erase(key)
		data["presentation"] = block
		return data
	var out: Dictionary = SCHEMA.default_block("presentation.")
	var missionary: Dictionary = out["missionary"]
	var standing: Dictionary = out["standing"]
	for old_key: String in LEGACY_PRESENTATION_KEYS:
		var new_key: String = LEGACY_PRESENTATION_KEYS[old_key]
		missionary[new_key] = float(block.get(old_key, missionary[new_key]))
	standing["glance_back_speed"] = float(block.get(
		"glance_back_speed", standing["glance_back_speed"]))
	standing["torso_angle_deg"] = float(block.get(
		"torso_angle_deg", standing["torso_angle_deg"]))
	out["missionary"] = missionary
	out["standing"] = standing
	data["presentation"] = out
	return data


## One parse per process. Reads are cheap copies of this merged view; the file is written only
## when a value changes or when the merged defaults differ from what is on disk.
static var _cache: Dictionary = {}
static var _loaded := false
## Bumped on every load and every write. `tunables.gd` rebuilds its flat value table when it
## changes, so a save anywhere invalidates the cached tunable reads.
static var generation := 0


## Drop the in-memory copy so the next read reloads the file. The settings page calls this when
## it opens, so a hand-edited settings.json applies without restarting the game.
static func reload() -> void:
	_loaded = false


## The merged settings view.
static func data() -> Dictionary:
	return _read()


## Write one dotted path (`presentation.standing.smack.raise_m`) and save the file.
static func set_path(path: String, value: Variant) -> void:
	var data := _read()
	var parts := path.split(".", false)
	if parts.is_empty():
		return
	var node: Dictionary = data
	for index: int in parts.size() - 1:
		var key := parts[index]
		var child: Variant = node.get(key)
		if not child is Dictionary:
			child = {}
			node[key] = child
		node = child
	node[parts[parts.size() - 1]] = value
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


## The merged settings view. The first call parses the file, migrates it and writes the merged
## result back once; later calls return a copy so a caller can stage edits for `_write`.
static func _read() -> Dictionary:
	if not _loaded:
		_load()
	return _cache.duplicate(true)


static func _load() -> void:
	_loaded = true
	generation += 1
	var path := _path()
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	data = _normalize_pose_names(data)
	data = _normalize_feature_names(data)
	data = _normalize_presentation(data)
	data = _merge(_defaults(), data)
	_cache = data
	_write_file(data)


static func _defaults() -> Dictionary:
	return {
		"debug_logs": SCHEMA.default_value("debug_logs"),
		"features": SCHEMA.default_block("features."),
		"thrust": SCHEMA.default_block("thrust."),
		"jiggle": SCHEMA.default_block("jiggle."),
		"camera_thrust": SCHEMA.default_block("camera_thrust."),
		"presentation": SCHEMA.default_block("presentation."),
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
	}


## The merged feature switches. Unknown keys are ignored; missing keys use defaults.
static func features() -> Dictionary:
	var data := _read()
	var block: Variant = data.get("features", {})
	var out: Dictionary = feature_defaults()
	if block is Dictionary:
		for key: String in out:
			if (block as Dictionary).has(key):
				out[key] = bool((block as Dictionary)[key])
	return out


## Unknown switches read as off everywhere; the runtime must not disagree with this.
static func feature(name: String) -> bool:
	if not feature_defaults().has(name):
		return false
	return bool(features().get(name, false))


static func save_feature(name: String, value: bool) -> void:
	if not feature_defaults().has(name):
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
	_cache = data
	generation += 1
	_write_file(_cache)


static func _write_file(data: Dictionary) -> void:
	var path := _path()
	var folder := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
