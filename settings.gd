extends RefCounted
## The one settings module: every global setting, the settings file, and the per-mare profiles.
##
##   const SETTINGS := preload("res://mods/unfplap/settings.gd")
##   if SETTINGS.act_foley.get_bool(): ...
##   SETTINGS.smack_raise.set(0.25)
##
## Every setting is declared once in the declarations block below: name, JSON path, label, help,
## tab, group, default and bounds. Call sites use the typed accessor on the named setting and
## never a string; the JSON path lives only in the declaration. A setting gains the debug flag
## with `.as_debug()`, which also removes its clamp. See TUNING.md.
##
## The same file owns the per-mare profile data (`preferences`, `poses`, `consent`, prompts),
## because it shares the file, the generation counter and the migration pipeline.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CONSENT := preload("res://mods/unfplap/consent.gd")
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
## One-release migration for the tolerance tier names and their setting paths.
const LEGACY_TOLERANCE_KEYS := {
	"timid_warning": "forgiving_warning",
	"neutral_warning_1": "normal_warning_1",
	"neutral_warning_2": "normal_warning_2",
	"neutral_stop": "normal_stop",
	"neutral_cooldown_s": "normal_cooldown_s",
}
## One-release migration for the old three-value genital tone. The slider keeps those exact
## values as its anchors: Coat at 0, Darker at 0.5 and Dark at 1.
const LEGACY_SKIN_TONES := {
	"coat": 0.0,
	"darker": 0.5,
	"dark": 1.0,
}
## One-release migration for act prompts that used to be written into settings.json. A saved value
## that exactly matches one of these is removed so the current DEFAULT_ACT_PROMPTS applies.
const LEGACY_ACT_PROMPTS := {
	"cue": [
		"During sex with Anon, your body and voice show: {cue} Say ONE short line in your own voice, at most 12 words. Begin with [whispering], [happy], [annoyed] or [surprised]. No narration, no stage directions, no anatomy. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
		"During sex with Anon, your body and voice show that you {cue}. Say ONE short line in your own voice, at most 12 words. Begin with [whispering], [happy], [annoyed] or [surprised]. No narration, no stage directions, no anatomy. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
	],
	"utterance": [
		"You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. Your taste is private, not a list to say. Current moment: {state}. Your taste: {taste}. Do not repeat: {recent}.",
		"You are in the middle of sex with Anon, not kissing him. Say ONE short line in your own voice, at most 18 words. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. These preferences are private feelings, not a list to say. Current moment: {state}. Your preferences: {preferences}. Do not repeat: {recent}.",
	],
}

## Character names, order and preference templates live in `character_preferences.gd`; the settings view
## and the runtime merge read them through these aliases.
const CHARACTERS := preload("res://mods/unfplap/character_preferences.gd")
const CHARACTER_ORDER := CHARACTERS.ORDER
const CHARACTER_NAMES := CHARACTERS.NAMES

## Tabs, in panel order. Characters is the hand-built per-mare form, not a settings tab.
const GENERAL := "general"
const ANATOMY := "anatomy"
const WORLD := "world"


# ---------------------------------------------------------------- settings
## One setting, declared once below. Call sites use the typed accessor on the named setting:
## `SETTINGS.act_foley.get_bool()`; the JSON path appears only in the declaration.
class Setting:
	var name: String
	var path: String
	var label: String
	var help: String
	var tab: String
	var group: String
	var default: Variant
	var debug := false
	var _get: Callable
	var _set: Callable

	func get_value() -> Variant:
		return _get.call()

	func set_value(value: Variant) -> void:
		_set.call(value)

	## Back to the declared default.
	func reset() -> void:
		set_value(default)

	## A debug setting is shown only behind debug mode and never clamps its own value.
	func as_debug() -> Setting:
		debug = true
		return self


class FlagSetting extends Setting:
	func get_bool() -> bool:
		return bool(get_value())

	func set_bool(on: bool) -> void:
		set_value(on)

	func as_debug() -> FlagSetting:
		debug = true
		return self


class NumSetting extends Setting:
	var unit := ""
	var step := 0.0
	var scale := 1.0
	var low := -1000000.0
	var high := 1000000.0
	var slider := false

	func get_num() -> float:
		var value: Variant = get_value()
		var number := float(value) if value is float or value is int else float(default)
		if not is_finite(number):
			return float(default)
		# The bounds are the player-facing contract. A debug number is never clamped.
		return number if debug else clampf(number, low, high)

	func set_num(v: float) -> void:
		var number := float(v)
		if not is_finite(number):
			number = float(default)
		set_value(number if debug else clampf(number, low, high))

	func with_unit(value: String) -> NumSetting:
		unit = value
		return self

	func with_step(value: float) -> NumSetting:
		step = value
		return self

	func with_scale(value: float) -> NumSetting:
		scale = value
		return self

	func with_range(lo: float, hi: float) -> NumSetting:
		low = lo
		high = hi
		return self

	func with_slider() -> NumSetting:
		slider = true
		return self

	func as_debug() -> NumSetting:
		debug = true
		return self


class ChoiceSetting extends Setting:
	var options: Array = []
	var labels: Array = []

	func get_choice() -> String:
		var value := str(get_value())
		return value if options.has(value) else str(default)

	func set_choice(value: String) -> void:
		if options.has(value):
			set_value(value)

	func as_debug() -> ChoiceSetting:
		debug = true
		return self


class ListSetting extends Setting:
	var options: Array = []

	func get_list() -> Array:
		var value: Variant = get_value()
		return value if value is Array else []

	func set_list(values: Array) -> void:
		var out: Array = []
		for raw: Variant in values:
			var name := str(raw).to_lower()
			if options.has(name) and not out.has(name):
				out.append(name)
		set_value(out)

	func toggle(item: String) -> void:
		var current := get_list()
		if current.has(item):
			current.erase(item)
		else:
			current.append(item)
		set_list(current)

	func as_debug() -> ListSetting:
		debug = true
		return self


class ColorSetting extends Setting:
	func get_color() -> Color:
		var value: Variant = get_value()
		if value is Color:
			return value
		return Color.from_string(str(value), Color.from_string(str(default), Color.WHITE))

	func set_color(value: Color) -> void:
		set_value(value)


static var _registry: Array = []
static var _by_path: Dictionary = {}
static var _by_name: Dictionary = {}
## One flat path -> value table, rebuilt only when the file's generation changes.
static var _flat: Dictionary = {}
static var _flat_generation := -1


static func flag(n: String, path: String, on: bool, label: String, help: String,
		tab: String, group: String) -> FlagSetting:
	var s := FlagSetting.new()
	_bind(s, n, path, label, help, tab, group, on)
	return s


static func num(n: String, path: String, value: float, label: String, help: String,
		tab: String, group: String) -> NumSetting:
	var s := NumSetting.new()
	_bind(s, n, path, label, help, tab, group, value)
	return s


static func choice(n: String, path: String, value: String, options: Array, labels: Array,
		label: String, help: String, tab: String, group: String) -> ChoiceSetting:
	var s := ChoiceSetting.new()
	s.options = options
	s.labels = labels
	_bind(s, n, path, label, help, tab, group, value)
	return s


static func list(n: String, path: String, value: Array, options: Array, label: String,
		help: String, tab: String, group: String) -> ListSetting:
	var s := ListSetting.new()
	s.options = options
	_bind(s, n, path, label, help, tab, group, value)
	return s


static func color(n: String, path: String, value: Color, label: String, help: String,
		tab: String, group: String) -> ColorSetting:
	var s := ColorSetting.new()
	_bind(s, n, path, label, help, tab, group, value.to_html())
	return s


static func _bind(s: Setting, n: String, path: String, label: String, help: String,
		tab: String, group: String, default: Variant) -> void:
	s.name = n
	s.path = path
	s.label = label
	s.help = help
	s.tab = tab
	s.group = group
	s.default = default
	# Not a per-instance module reference: an inner class cannot see the outer script's statics,
	# so each setting carries the two calls it needs.
	s._get = func() -> Variant: return _setting_value(s)
	s._set = func(value: Variant) -> void: _setting_write(s, value)
	if _by_path.has(path):
		push_error("unfplap settings: duplicate path %s" % path)
	_registry.append(s)
	_by_path[path] = s
	_by_name[n] = s


## True when the anatomy is shown at all: the `anatomy_mode` pill is not `never`.
static func anatomy_on() -> bool:
	return anatomy_mode.get_choice() != "never"


## Every setting in declaration order.
static func all_settings() -> Array:
	return _registry


## The setting at a JSON path, or null. Never use this from gameplay code.
static func by_path(path: String) -> Variant:
	return _by_path.get(path)


static func by_name(n: String) -> Variant:
	return _by_name.get(n)


static func _default_at(path: String) -> Variant:
	var s: Variant = _by_path.get(path)
	return null if s == null else s.default


## Nested dictionary of every value under a dotted prefix, e.g. `block("features.")` for a
## per-act snapshot.
static func block(prefix: String) -> Dictionary:
	_ensure_flat()
	var out: Dictionary = {}
	for path: String in _by_path.keys():
		if path.begins_with(prefix):
			_write_path(out, path.substr(prefix.length()), _flat.get(path))
	return out


## The default block under a dotted prefix.
static func default_block(prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for path: String in _by_path.keys():
		if path.begins_with(prefix):
			_write_path(out, path.substr(prefix.length()), (_by_path[path] as Setting).default)
	return out


## Settings in one tab, in declaration order.
static func tab_settings(tab: String) -> Array:
	var out: Array = []
	for s: Setting in _registry:
		if s.tab == tab:
			out.append(s)
	return out


## Read one dotted path out of a settings dictionary, or `fallback` when it is absent.
static func _read_path(data: Dictionary, path: String, fallback: Variant) -> Variant:
	var node: Variant = data
	for key: String in path.split(".", false):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return fallback
		node = (node as Dictionary)[key]
	return node


static func _setting_value(s: Setting) -> Variant:
	_ensure_flat()
	return _flat.get(s.path, s.default)


static func _setting_write(s: Setting, value: Variant) -> void:
	write_setting(s.path, _coerce(s, value))


## Validate one value against its setting. Bools take the truthiness, numbers take the contract
## bounds unless debug, choices must be an option and lists are filtered to their options.
static func _coerce(s: Setting, value: Variant) -> Variant:
	if s is FlagSetting:
		return bool(value)
	if s is NumSetting:
		var number := float(value) if value is float or value is int else float(s.default)
		if not is_finite(number):
			return s.default
		var n := s as NumSetting
		return number if n.debug else clampf(number, n.low, n.high)
	if s is ChoiceSetting:
		var text := str(value)
		var c := s as ChoiceSetting
		return text if c.options.has(text) else c.default
	if s is ColorSetting:
		var color_value: Color = value if value is Color else Color.from_string(str(value), Color.WHITE)
		return color_value.to_html()
	if s is ListSetting:
		var l := s as ListSetting
		var out: Array = []
		if value is Array:
			for raw: Variant in value:
				var name := str(raw).to_lower()
				if l.options.has(name) and not out.has(name):
					out.append(name)
		return out
	return value


static func _ensure_flat() -> void:
	if _flat_generation == generation and not _flat.is_empty():
		return
	_flat_generation = generation
	_flat.clear()
	var data := _read()
	for s: Setting in _registry:
		_flat[s.path] = _read_path(data, s.path, s.default)


static func _write_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".", false)
	if parts.is_empty():
		return
	var node: Dictionary = root
	for index: int in parts.size() - 1:
		var key := parts[index]
		var child: Variant = node.get(key)
		if not child is Dictionary:
			child = {}
			node[key] = child
		node = child
	node[parts[parts.size() - 1]] = value


# ---------------------------------------------------------------- section state
## A section's open state, remembered in the user settings under `ui.sections`. The Debug block
## starts collapsed; every other section starts open.
static func section_open(tab: String, group: String) -> bool:
	if not _loaded:
		_load()
	var ui: Variant = _cache.get("ui")
	var sections: Variant = (ui as Dictionary).get("sections") if ui is Dictionary else null
	if not sections is Dictionary:
		return group != "Debug"
	return bool((sections as Dictionary).get(tab + "/" + group, group != "Debug"))


static func set_section_open(tab: String, group: String, open: bool) -> void:
	var data := _read()
	var ui: Variant = data.get("ui")
	if not ui is Dictionary:
		ui = {}
	var sections: Variant = (ui as Dictionary).get("sections")
	if not sections is Dictionary:
		sections = {}
	(ui as Dictionary)["sections"] = sections
	(sections as Dictionary)[tab + "/" + group] = open
	data["ui"] = ui
	_write(data)


# ---------------------------------------------------------------- declarations
## Every setting, declared once. Order here is the panel order. `debug` entries are shown in the
## tab's Debug block only; see TUNING.md.







# ======================================================== General

# -- (ungrouped)
static var sex_start := choice("sex_start", "relationship.sex_start", "try_luck",
	["when_available", "try_luck"], ["When Available", "Try Your Luck"],
	"Starting Sex",
	"When to show the \u201cMake love\u201d button. When Available needs the Promiscuity stage and a lover bond; Try Your Luck drops both, but the mare can still refuse.", GENERAL, "")
static var act_controls := flag("act_controls", "features.act_controls", true, "Show controls",
	"Show the act's control list. Off keeps the cue and climax readouts.", GENERAL, "")
static var hud_readouts := flag("hud_readouts", "features.hud_readouts", true, "Show HUD readouts",
	"Show the mood cue and Wants/You line. Hearts and the afterglow close prompt stay visible.", GENERAL, "")
static var captions_on_top := flag("captions_on_top", "features.captions_on_top", true,
	"Show captions on top",
	"Move the explicit bottom dialogue caption to the top. Overhead and auto captions are unchanged.", GENERAL, "")
static var mute_ponese_audio := flag("mute_ponese_audio", "features.mute_ponese_audio", true,
	"Mute Ponese audio",
	"Keep the act's generated text but silence the Ponese voice for that act.", GENERAL, "")
static var act_lines := flag("act_lines", "features.act_lines", true, "Allow act lines",
	"Let her speak unprompted lines during sex. Off keeps normal dialogue and the HUD cue.", GENERAL, "")
static var act_history := flag("act_history", "features.act_history", true, "Remember acts",
	"Remember how each act went; repeated good sex builds trust and desire, while repeated neglect makes her reluctant.", GENERAL, "")
static var max_pony_climaxes := num("max_pony_climaxes", "thrust.max_pony_climaxes", 3.0,
	"Climax limit", "How many times a mare can climax in one act. 0 is unlimited.", GENERAL, "") \
	.with_step(1.0).with_range(0.0, 20.0)
static var pixels_per_cm := num("pixels_per_cm", "thrust.pixels_per_cm", 100.0,
	"Sensitivity",
	"Mouse travel for each centimetre the cock moves. A full stroke is his shaft length, so a "
	+ "longer part needs proportionally more travel.", GENERAL, "") \
	.with_unit("px per cm").with_step(10.0).with_range(20.0, 400.0)
static var orientation := choice("orientation", "thrust.orientation", "up", ["up", "down"],
	["Mouse Up", "Mouse Down"], "Thrust direction",
	"Which mouse direction deepens the thrust.", GENERAL, "")
static var anatomy_bed_body := flag("anatomy_bed_body", "features.anatomy_bed_body", true,
	"Use Anon bed body",
	"Use Anon's own body on the bed and view the missionary act from his eyes instead of the current shot.", GENERAL, "")
static var anatomy_vr := flag("anatomy_vr", "features.anatomy_vr", true, "Use VR act",
	"The standing act in VR, with hip-tracker depth and controller actions. Untested on this build.", GENERAL, "")
static var anatomy_holes := flag("anatomy_holes", "features.anatomy_holes", true, "Allow hole switch",
	"Let V switch between the front and the anal cup.", GENERAL, "")
static var anatomy_oral := flag("anatomy_oral", "features.anatomy_oral", true, "Allow oral",
	"Let N turn her round for oral in the standing pose.", GENERAL, "")
static var anatomy_finish := flag("anatomy_finish", "features.anatomy_finish", true,
	"Allow finish control", "Let B choose whether Anon finishes inside or pulls out.", GENERAL, "")
static var debug_mode := flag("debug_mode", "debug_mode", false, "Enable debug",
	"Enable the Debug section at the bottom of every tab and print the mod's diagnostics. Disabling it keeps the other settings as they are.", GENERAL, "")

# -- (ungrouped)  (debug)
static var debug_perf := flag("debug_perf", "debug_perf", false, "Print perf logs",
	"Print the per-second performance block. Requires Enable debug.", GENERAL, "") \
	.as_debug()
static var act_ear_pin := flag("act_ear_pin", "features.act_ear_pin", false, "Pin act ears",
	"Debug: pin her ears back during acts. Off keeps the normal ear pose and still applies the act's blush, gaze and ear twitch.", GENERAL, "") \
	.as_debug()
static var max_depth := num("max_depth", "auto_thrust.max_depth", 0.5, "Auto depth",
	"Starting auto-thrust peak depth. Mouse up/down sets it during an act.", GENERAL, "") \
	.with_unit("%").with_step(5.0).with_scale(100.0).with_range(0.2, 1.0).as_debug()
static var min_depth := num("min_depth", "auto_thrust.min_depth", 0.0, "Auto min depth",
	"Starting auto-thrust bottom depth. Hold X then Q/A sets it during an act; the band stays at "
	+ "least 18 % wide so every stroke still counts.", GENERAL, "") \
	.with_unit("%").with_step(5.0).with_scale(100.0).with_range(0.0, 0.82).as_debug()
static var pace := num("pace", "auto_thrust.pace", 1.0, "Auto pace",
	"Starting auto-thrust pace in thrusts per second. The mouse wheel changes it during an act.",
	GENERAL, "") \
	.with_unit("/s").with_step(0.25).with_range(1.0, 3.75).as_debug()
static var curve := choice("curve", "auto_thrust.curve", "cosine",
	["cosine", "thrust", "tease", "saw", "hold"],
	["Normal", "Thrust", "Tease", "Saw", "Hold"],
	"Auto shape",
	"Shape of every automatic stroke. Normal is the symmetric ease; Thrust drives in fast and out "
	+ "slow, Tease the other way; Saw has no easing; Hold pauses at full depth.", GENERAL, "") \
	.as_debug()
static var contact_gap_m := num("contact_gap_m", "thrust.contact_gap_m", 0.05, "Contact gap",
	"How close a stroke must come to its deepest point before his skin meets her coat and the body "
	+ "slap plays. Raise it to hear plaps on shorter strokes.", GENERAL, "") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).with_range(0.0, 0.12).as_debug()
static var travel := num("travel", "thrust.travel", 1.0, "Hip back-off",
	"How far the hips retreat between thrusts.", GENERAL, "") \
	.with_unit("\u00d7").with_step(0.05).with_range(0.25, 2.0).as_debug()
static var allow_act_during_cuddle := flag("allow_act_during_cuddle",
	"features.allow_act_during_cuddle", true, "Allow acts during cuddles",
	"End an active cuddle when an act starts instead of blocking it.", GENERAL, "") \
	.as_debug()

# -- Audio  (debug)
static var act_climax := flag("act_climax", "features.act_climax", false, "Play wet climax",
	"Add the pack wet finish sound at her climax. Off keeps only the current climax squeak.",
	GENERAL, "Audio") \
	.as_debug()
static var act_foley := flag("act_foley", "features.act_foley", true, "Play act foley",
	"Use the pack's thrust, slide, bed/fabric, mouth-kiss and flank-smack sounds. Off restores the current kiss-sample plap and the stock flank slap.",
	GENERAL, "Audio") \
	.as_debug()
static var act_vocals := flag("act_vocals", "features.act_vocals", false, "Play act vocals",
	"Add the pack moan only at her climax. Off keeps the pony breath, Ponese voice and current climax squeak unchanged.",
	GENERAL, "Audio") \
	.as_debug()

# -- Camera  (debug)
static var bob := num("bob", "camera_thrust.bob", 0.35, "Bob",
	"Vertical camera dip on the inward stroke.", GENERAL, "Camera") \
	.with_unit("%").with_step(5.0).with_scale(100.0).with_range(0.0, 1.0).as_debug()
static var surge := num("surge", "camera_thrust.surge", 1.0, "Surge",
	"Forward camera travel on the inward stroke.", GENERAL, "Camera") \
	.with_unit("%").with_step(5.0).with_scale(100.0).with_range(0.0, 1.0).as_debug()
static var idle_camera_sway := flag("idle_camera_sway", "features.idle_camera_sway", true,
	"Sway the idle camera", "Add a slow sway when you are not leaning.", GENERAL, "Camera") \
	.as_debug()

# -- Talk & cues  (debug)
static var base_stable_seconds := num("base_stable_seconds", "cues.base_stable_seconds", 2.0,
	"Base stability", "How long a base cue must hold before it can be spoken.", GENERAL,
	"Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()
static var demand_gap_seconds := num("demand_gap_seconds", "cues.demand_gap_seconds", 28.0,
	"Demand gap", "Minimum time between demand lines.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var demand_repeat_seconds := num("demand_repeat_seconds", "cues.demand_repeat_seconds",
	45.0, "Demand repeat", "How long the same demand text is locked out.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var max_age_seconds := num("max_age_seconds", "cues.max_age_seconds", 20.0,
	"Cue max age", "Drop a queued cue that has not reached audio by this age.", GENERAL,
	"Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var override_seconds := num("override_seconds", "cues.override_seconds", 10.0,
	"Override lifetime", "How long a touch or talk cue replaces the base cue.", GENERAL,
	"Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var override_stable_seconds := num("override_stable_seconds",
	"cues.override_stable_seconds", 0.5, "Override stability",
	"How long a touch or talk cue must hold before it can be spoken.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()
static var overwhelmed_seconds := num("overwhelmed_seconds", "cues.overwhelmed_seconds", 1.2,
	"Overwhelmed cue", "How long a disliked input keeps the overwhelmed cue.", GENERAL,
	"Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()
static var reaction_max_age_seconds := num("reaction_max_age_seconds",
	"cues.reaction_max_age_seconds", 30.0, "Reaction max age",
	"Drop a queued reaction that has not reached audio by this age.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var release_hold_seconds := num("release_hold_seconds", "cues.release_hold_seconds", 1.0,
	"Release hold", "Keep the line slot reserved after speech stops.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()
static var utterance_gap_seconds := num("utterance_gap_seconds", "cues.utterance_gap_seconds",
	18.0, "Line gap", "Minimum time between any two generated act lines.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var receptive_seconds := num("receptive_seconds", "talk.receptive_seconds", 8.0,
	"Receptive window", "How long a liked touch or talk makes thrusts land harder.", GENERAL,
	"Talk & cues") \
	.with_unit("s").with_step(0.5).as_debug()
static var talk_cooldown_seconds := num("talk_cooldown_seconds", "talk.talk_cooldown_seconds",
	8.0, "Talk cooldown", "Minimum time between talk readiness chunks.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()
static var touch_cooldown_seconds := num("touch_cooldown_seconds",
	"talk.touch_cooldown_seconds", 4.0, "Touch cooldown",
	"Minimum time between touch readiness chunks.", GENERAL, "Talk & cues") \
	.with_unit("s").with_step(0.1).as_debug()

# -- Missionary  (debug)
static var missionary_body_motion := flag("missionary_body_motion",
	"features.missionary_body_motion", true, "Missionary body motion",
	"Slide her body along the bed and nod her head on the thrust.", GENERAL, "Missionary") \
	.as_debug()
static var forward := num("forward", "presentation.missionary.forward", 0.3,
	"Missionary forward", "Shift the frozen shot forward along her body.", GENERAL, "Missionary") \
	.with_unit("m").with_step(0.01).as_debug()
static var height := num("height", "presentation.missionary.height", 0.25, "Missionary height",
	"Raise the frozen shot.", GENERAL, "Missionary") \
	.with_unit("m").with_step(0.01).as_debug()
static var pitch_deg := num("pitch_deg", "presentation.missionary.pitch_deg", -15.0,
	"Missionary pitch", "Tilt the frozen view; positive looks up.", GENERAL, "Missionary") \
	.with_unit("°").with_step(0.5).as_debug()
static var pullback := num("pullback", "presentation.missionary.pullback", 0.22,
	"Missionary pullback", "Pull the shot back along its own view axis.", GENERAL, "Missionary") \
	.with_unit("m").with_step(0.01).as_debug()
static var side := num("side", "presentation.missionary.side", 0.0, "Missionary side",
	"Shift the frozen shot sideways; positive is her right.", GENERAL, "Missionary") \
	.with_unit("m").with_step(0.01).as_debug()
static var side_lean := num("side_lean", "presentation.missionary.side_lean", 0.1,
	"Side lean forward", "Extra travel toward her head on a side lean.", GENERAL, "Missionary") \
	.with_unit("m").with_step(0.01).as_debug()

# -- Missionary › Neck angles  (debug)
static var head_pitch_deg := num("head_pitch_deg", "presentation.missionary.head_pitch_deg",
	90.0, "Head pitch", "Tilt the head about the body right axis after the gaze solve.", GENERAL,
	"Missionary › Neck angles") \
	.with_unit("°").with_step(1.0).as_debug()
static var head_roll_deg := num("head_roll_deg", "presentation.missionary.head_roll_deg", 90.0,
	"Head roll", "Roll the head last, in degrees.", GENERAL, "Missionary › Neck angles") \
	.with_unit("°").with_step(1.0).as_debug()
static var neck1_deg := num("neck1_deg", "presentation.missionary.neck1_deg", 0.0,
	"Neck 1 angle", "Bend pony_neck1 about the body right axis.", GENERAL,
	"Missionary › Neck angles") \
	.with_unit("°").with_step(1.0).as_debug()
static var neck2_deg := num("neck2_deg", "presentation.missionary.neck2_deg", 45.0,
	"Neck 2 angle", "Bend pony_neck2 about the body right axis.", GENERAL,
	"Missionary › Neck angles") \
	.with_unit("°").with_step(1.0).as_debug()
static var neck_roll_deg := num("neck_roll_deg", "presentation.missionary.neck_roll_deg", 0.0,
	"Neck roll", "Roll both neck bones about the body forward axis.", GENERAL,
	"Missionary › Neck angles") \
	.with_unit("°").with_step(1.0).as_debug()

# -- Standing  (debug)
static var standing_play_bow := flag("standing_play_bow", "features.standing_play_bow", false,
	"Use play-bow stance",
	"Standing: stretch the front legs forward with the chest down and head low instead of the tucked act stance.", GENERAL, "Standing") \
	.as_debug()
static var chin_up_deg := num("chin_up_deg", "presentation.standing.chin_up_deg", 30.0,
	"Chin up", "Standing head lift at the chin.", GENERAL, "Standing") \
	.with_unit("°").with_step(1.0).as_debug()
static var neck_down_deg := num("neck_down_deg", "presentation.standing.neck_down_deg", 15.0,
	"Neck down", "Standing neck reach down/forward.", GENERAL, "Standing") \
	.with_unit("°").with_step(1.0).as_debug()
static var tail_pitch_deg := num("tail_pitch_deg", "presentation.standing.tail.pitch_deg", 32.0,
	"Tail lift (pitch)", "How far the standing tail lifts up. Pairs with Tail aside.", GENERAL, "Standing") \
	.with_unit("°").with_step(1.0).with_range(0.0, 90.0).as_debug()
static var yaw_deg := num("yaw_deg", "presentation.standing.tail.yaw_deg", 45.0,
	"Tail aside (yaw)", "How far the standing tail sweeps aside from her centreline.", GENERAL, "Standing") \
	.with_unit("°").with_step(1.0).with_range(0.0, 90.0).as_debug()

# -- Standing › Motion  (debug)
static var standing_body_sway := flag("standing_body_sway", "features.standing_body_sway", true,
	"Sway her body",
	"Move her body with the thrust while the hooves stay planted; Anon's hips follow so the contact rocks with her.",
	GENERAL, "Standing › Motion") \
	.as_debug()
static var standing_plant_feet := flag("standing_plant_feet", "features.standing_plant_feet",
	false, "Plant Anon's lower body",
	"Hold Anon's hips and both feet at their act-start positions, 15 cm behind him. Off restores the game's stepping and lean foot motion.",
	GENERAL, "Standing › Motion") \
	.as_debug()
static var thrust_ear_twitch := flag("thrust_ear_twitch", "features.thrust_ear_twitch", true,
	"Twitch her ears", "Flick both ears on some thrusts.", GENERAL, "Standing › Motion") \
	.as_debug()
static var camera_forward_m := num("camera_forward_m", "presentation.standing.camera_forward_m",
	0.0, "Camera forward",
	"Slide Anon's view forward relative to his chest so his own body sits behind the camera.",
	GENERAL, "Standing › Motion") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var camera_pitch_deg := num("camera_pitch_deg", "presentation.standing.camera_pitch_deg",
	-6.0, "Camera pitch", "Tilt Anon's standing view up or down; positive looks up.", GENERAL,
	"Standing › Motion") \
	.with_unit("°").with_step(0.5).as_debug()
static var chest_back_m := num("chest_back_m", "presentation.standing.chest_back_m", 0.0,
	"Chest back", "Push Anon's chest back from the camera in the standing act. 0 is off.",
	GENERAL, "Standing › Motion") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var gap_offset_m := num("gap_offset_m", "presentation.standing.gap_offset_m", 0.15,
	"Gap offset", "Move Anon closer (negative) or farther (positive) when a standing act starts.",
	GENERAL, "Standing › Motion") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var glance_back_speed := num("glance_back_speed",
	"presentation.standing.glance_back_speed", 2.0, "Glance-back speed",
	"How fast a look-back glance eases in and out.", GENERAL, "Standing › Motion") \
	.with_unit("×").with_step(0.05).with_range(0.25, 3.0).as_debug()
static var hip_drop_m := num("hip_drop_m", "presentation.standing.hip_drop_m", 0.0, "Hip drop",
	"Lower Anon's standing hips; use this when his body sits too high. 0 is off.", GENERAL,
	"Standing › Motion") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var plant_spread_m := num("plant_spread_m", "presentation.standing.plant_spread_m", 0.4,
	"Planted stance width", "How far apart Anon's planted feet are held during a standing act.",
	GENERAL, "Standing › Motion") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var torso_angle_deg := num("torso_angle_deg", "presentation.standing.torso_angle_deg",
	0.0, "Anon torso lean",
	"Hinge Anon's upper body forward over her; the lower body stays planted.", GENERAL,
	"Standing › Motion") \
	.with_unit("°").with_step(1.0).as_debug()

# -- Standing › Caress  (debug)
static var ignore := list("ignore", "presentation.standing.caress.ignore", ["tail", "wing"],
	["tail", "mane", "wing", "leg"], "Ignore body parts",
	"Regions the caress contact query skips.", GENERAL, "Standing › Caress") \
	.as_debug()
static var oval_across_m := num("oval_across_m", "presentation.standing.caress.oval_across_m",
	0.01, "Oval across", "Caress stroke length along the body.", GENERAL, "Standing › Caress") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var oval_up_m := num("oval_up_m", "presentation.standing.caress.oval_up_m", 0.02,
	"Oval up", "Caress stroke height.", GENERAL, "Standing › Caress") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var palm_distance := num("palm_distance", "presentation.standing.caress.palm_distance",
	0.02, "Palm distance", "Palm centre distance from the coat.", GENERAL, "Standing › Caress") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var canon := num("canon", "presentation.standing.caress.palm_scale.canon", 0.75,
	"Palm scale (Canon)", "Standing hand scale for Canon-size Anon.", GENERAL,
	"Standing › Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var hoers := num("hoers", "presentation.standing.caress.palm_scale.hoers", 1.0,
	"Palm scale (Hoers)", "Standing hand scale for the Hoers size.", GENERAL, "Standing › Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var mounting := num("mounting", "presentation.standing.caress.palm_scale.mounting", 0.9,
	"Palm scale (Mounting)", "Standing hand scale for mounting size.", GENERAL,
	"Standing › Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var same_height := num("same_height",
	"presentation.standing.caress.palm_scale.same height", 1.0, "Palm scale (Same height)",
	"Standing hand scale at Anon's own height.", GENERAL, "Standing › Caress") \
	.with_unit("×").with_step(0.01).as_debug()

# -- Standing › Kiss  (debug)
static var camera_yaw_deg := num("camera_yaw_deg", "presentation.standing.kiss.camera_yaw_deg",
	12.0, "Kiss camera yaw", "Over-the-shoulder yaw toward her at the kiss.", GENERAL,
	"Standing › Kiss") \
	.with_unit("°").with_step(1.0).as_debug()
static var lean_drop := num("lean_drop", "presentation.standing.kiss.lean_drop", 0.04,
	"Kiss lean drop", "How far he drops over her at the kiss.", GENERAL, "Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var lean_forward := num("lean_forward", "presentation.standing.kiss.lean_forward", 0.25,
	"Kiss forward lean", "Forward kiss lean.", GENERAL, "Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var lean_side := num("lean_side", "presentation.standing.kiss.lean_side", 0.46,
	"Kiss side lean", "Sideways kiss lean toward the shoulder side.", GENERAL, "Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var mouth_drop := num("mouth_drop", "presentation.standing.kiss.mouth_drop", 0.0,
	"Kiss mouth down", "Anon's mouth target drop at the kiss.", GENERAL, "Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var mouth_forward := num("mouth_forward", "presentation.standing.kiss.mouth_forward",
	0.0, "Kiss mouth forward", "Anon's mouth target forward at the kiss.", GENERAL,
	"Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var mouth_right := num("mouth_right", "presentation.standing.kiss.mouth_right", 0.0,
	"Kiss mouth right", "Anon's mouth target sideways at the kiss.", GENERAL, "Standing › Kiss") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()

# -- Standing › Smack  (debug)
static var arc_m := num("arc_m", "presentation.standing.smack.arc_m", 0.1, "Palm arc",
	"Bow of the lift path toward her rump.", GENERAL, "Standing › Smack") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var height_m := num("height_m", "presentation.standing.smack.height_m", 0.05, "Height",
	"Move the target up or down the cheek.", GENERAL, "Standing › Smack") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var hind_m := num("hind_m", "presentation.standing.smack.hind_m", 0.09, "Hind offset",
	"Move the target toward her rump.", GENERAL, "Standing › Smack") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var smack_pitch_deg := num("smack_pitch_deg", "presentation.standing.smack.pitch_deg",
	0.0, "Palm pitch", "Pitch the raised palm down from the contact basis.", GENERAL,
	"Standing › Smack") \
	.with_unit("°").with_step(1.0).as_debug()
static var raise_m := num("raise_m", "presentation.standing.smack.raise_m", 0.3, "Max raise",
	"Hand lift at the top of the wind-up.", GENERAL, "Standing › Smack") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var raise_speed := num("raise_speed", "presentation.standing.smack.raise_speed", 1.5,
	"Raise speed", "Wind-up speed in metres per second.", GENERAL, "Standing › Smack") \
	.with_unit("m/s").with_step(0.1).as_debug()
static var return_speed := num("return_speed", "presentation.standing.smack.return_speed", 4.0,
	"Return speed", "Strike speed in metres per second.", GENERAL, "Standing › Smack") \
	.with_unit("m/s").with_step(0.1).as_debug()

# -- Thrust jiggle  (debug)
static var center_back_m := num("center_back_m", "jiggle.center_back_m", 0.15, "Center back",
	"Backward center from the hind-femur midpoint; raise it to move the wobble toward the dock.",
	GENERAL, "Thrust jiggle") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var center_height_m := num("center_height_m", "jiggle.center_height_m", 0.1,
	"Center height",
	"Taller center above the hind-femur midpoint; raise it to move the wobble up the rump.",
	GENERAL, "Thrust jiggle") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var intensity := num("intensity", "jiggle.intensity", 0.2, "Intensity",
	"Thrust amount of the rump wobble.", GENERAL, "Thrust jiggle") \
	.with_unit("×").with_step(0.05).as_debug()
static var radius := num("radius", "jiggle.radius", 0.26, "Radius",
	"Spread of the rump wobble across the flank.", GENERAL, "Thrust jiggle") \
	.with_unit("cm").with_step(1.0).with_scale(100.0).as_debug()
static var smack_intensity := num("smack_intensity", "jiggle.smack_intensity", 0.45,
	"Smack intensity", "Act-smack amount of the rump wobble.", GENERAL, "Thrust jiggle") \
	.with_unit("×").with_step(0.05).as_debug()

# ======================================================== Anatomy

# -- (ungrouped)
static var anatomy_mode := choice("anatomy_mode", "anatomy.anatomy_mode", "never",
	["never", "act", "always"], ["Never", "During act only", "Always"], "Anatomy",
	"Show the mare anatomy always, only while an act is running, or never.", ANATOMY, "")
static var show_dock := flag("show_dock", "anatomy.show_dock", true, "Show tail docks",
	"Show the tail dock above the ponut. Off hides it while the anatomy is shown.", ANATOMY, "")
static var skin_strip := flag("skin_strip", "anatomy.skin_strip", true, "Show skin strip",
	"Show the midline skin strip that joins the teats toward the vulva.", ANATOMY, "")
static var teats := flag("teats", "anatomy.teats", false, "Show teats", "Show the optional teats.", ANATOMY, "")
static var anatomy_fluid := flag("anatomy_fluid", "features.anatomy_fluid", true, "Show fluids",
	"Show the optional climax and finish droplets.", ANATOMY, "")
static var body_coat_deform := flag("body_coat_deform", "features.body_coat_deform", false,
	"Body coat deform",
	"Patch the rig coat shader at runtime so the area under the vulva stays still and the coat spreads as the opening widens. Off leaves the game shader untouched.",
	ANATOMY, "").as_debug()
static var skin_tone := num("skin_tone", "anatomy.skin_tone", 0.5, "Skin tone",
	"0% keeps her coat; 50% is the old Darker tone; 100% is the old Dark tone.", ANATOMY, "") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0).with_slider()
static var mare_bits := choice("mare_bits", "anatomy.mare_bits", "original",
	["original", "v2"], ["Original PPP", "V2"],
	"Mare bits",
	"Choose the full mare genitals mesh. V2 uses the smoothed model when its asset is present; otherwise the original PPP mesh is used.", ANATOMY, "")
static var vulva_height := num("vulva_height", "anatomy.vulva_height", 1.0,
	"Vulva height",
	"Scale the vulva vertically around its opening. Below 1 shortens it; above 1 lengthens it.", ANATOMY, "") \
	.with_unit("×").with_step(0.05).with_range(0.5, 1.5)
static var vulva_inner_color := color("vulva_inner_color", "anatomy.vulva_inner_color",
	Color.from_string("#f7a8bd", Color.WHITE), "Vulva inner colour",
	"Colour of the inner folds. The shader derives its shadow.", ANATOMY, "")
static var clitoris_color := color("clitoris_color", "anatomy.clitoris_color",
	Color.from_string("#d67891", Color.WHITE), "Clitoris colour",
	"Colour of the clitoris. The shader derives its shadow.", ANATOMY, "")

# -- Anon
static var player_scale := num("player_scale", "anatomy.player_scale", 1.5, "Size",
	"Scale the player part relative to its default size.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.25, 3.0)
static var part_length_scale := num("part_length_scale", "anatomy.part_length_scale", 1.0,
	"Length",
	"Stretch the shaft along its length. The head, hole grip and fluid point follow it.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_base_scale := num("part_base_scale", "anatomy.part_base_scale", 1.3,
	"Base radius", "Thickness of the cock where it leaves his body.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_mid_scale := num("part_mid_scale", "anatomy.part_mid_scale", 0.8,
	"Mid radius", "Thickness of the cock around its middle.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_head_scale := num("part_head_scale", "anatomy.part_head_scale", 1.3,
	"Head radius", "Thickness of the glans at the end of the shaft.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_throb := num("part_throb", "anatomy.part_throb", 1.0, "Throb",
	"Heartbeat-like pulse of the shaft, with a slight upward beat while it is outside her. "
	+ "1 is subtle; 0 turns it off.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.0, 3.0)
static var back_out_m := num("back_out_m", "anatomy.back_out_m", 0.0, "Back-out gap",
	"How far the tip rests behind her lips before the first thrust. 0 keeps it at her entrance.",
	ANATOMY, "Anon") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).with_range(0.0, 5.0)

# -- (ungrouped)  (debug)
static var part_front_m := num("part_front_m", "anatomy.part_front_m", 0.02, "Cock forward",
	"Slide the cock's base forward from the hips so it sits on the front of the pelvis.", ANATOMY, "") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).with_range(-20.0, 20.0) \
	.as_debug()
static var pelvis_gap_m := num("pelvis_gap_m", "anatomy.pelvis_gap_m", 0.03, "Pelvis gap",
	"Keep the pelvis at least this far behind her rear surface; the depth gives way instead.", ANATOMY, "") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).with_range(0.0, 10.0) \
	.as_debug()
static var strip_scale := num("strip_scale", "anatomy.strip_scale", 1.0, "Skin strip scale",
	"Scale the midline skin strip under the vulva sideways around its centre. 1 is the modelled width.", ANATOMY, "") \
	.with_unit("×").with_step(0.05).as_debug()
static var debug_aim_points := flag("debug_aim_points", "features.debug_aim_points", false,
	"Show aim points", "Show the vulva, anus and cock-tip markers during an act.", ANATOMY, "") \
	.as_debug()
static var debug_hide_tails := flag("debug_hide_tails", "debug_hide_tails", false, "Hide tails",
	"Collapse every loaded pony's tail for debugging. The small tail root cap pinned to her pelvis may remain.", ANATOMY, "") \
	.as_debug()

# -- Holes  (debug)
static var anal_height_mm := num("anal_height_mm", "anatomy.anal_height_mm", -15.0,
	"Anal opening height",
	"Vertical placement of the anal mesh and its opening; positive is higher, negative lower.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-20.0, 20.0) \
	.as_debug()
static var anal_scale := num("anal_scale", "anatomy.anal_scale", 1.0,
	"Anal scale",
	"Scale the anal cup around its opening. Below 1 tucks the outer rim into the mound; above 1 spreads it out.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.5, 1.5) \
	.as_debug()
static var vulva_hug_mm := num("vulva_hug_mm", "anatomy.vulva_hug_mm", 0.0,
	"Vulva hug",
	"Pad the gap between the cock and the vulva lips. Positive opens the lips wider; negative grips tighter.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-5.0, 5.0) \
	.as_debug()
static var anal_hug_mm := num("anal_hug_mm", "anatomy.anal_hug_mm", 0.0,
	"Anal hug",
	"Pad the gap between the cock and the anal opening. Positive opens it wider; negative grips tighter.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-5.0, 5.0) \
	.as_debug()
static var anal_ring := flag("anal_ring", "anatomy.anal_ring", false,
	"Use ring model (experimental)", "Use the re-modelled anal ring instead of the original cup.", ANATOMY, "Holes") \
	.as_debug()
static var lip_vertical := num("lip_vertical", "anatomy.lip_vertical", 1.0,
	"Lip vertical share",
	"How much of the opening happens top to bottom. Lower keeps the top and bottom lips tight on the shaft while the sides part.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 1.0) \
	.as_debug()
static var coat_spread := num("coat_spread", "anatomy.coat_spread", 1.0,
	"Coat spread",
	"Multiplier for the body coat stretching around the vulva as the opening widens.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 2.0) \
	.as_debug()
static var jiggle_still := num("jiggle_still", "anatomy.jiggle_still", 1.0,
	"Jiggle still zone",
	"Multiplier for the no-jiggle zone around the vulva. 0 turns the still zone off.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 2.0) \
	.as_debug()

# ======================================================== World

# -- (ungrouped)
static var promiscuity := choice("promiscuity", "relationship.promiscuity", "any",
	["soulmates", "head_over_hooves", "marefriend", "new_couple", "crush", "any"],
	["Soulmates", "Head Over Hooves", "Marefriend / Coltfriend", "New Couple", "Crush", "Any Adult"],
	"Promiscuity", "Lowest relationship level for a lover bond and sex.", WORLD, "")
static var estrus_cycle := flag("estrus_cycle", "features.estrus_cycle", false, "Use estrus cycle",
	"Give mares a 30-day cycle: seven days of heat, two days turned off, then normal. In heat they warm faster and offer sooner; in diestrus they refuse sex.", WORLD, "")

# -- (ungrouped)  (debug)
static var act_bystanders := flag("act_bystanders", "features.act_bystanders", true,
	"Show bystander lines",
	"Let an adult pony who can perceive the act say one short line. Uses the modern witness rules; young ponies never speak.", WORLD, "") \
	.as_debug()
static var act_public_offer := flag("act_public_offer", "features.act_public_offer", true,
	"Allow public offers",
	"Let a mare who is comfortable with others around still offer sex in public.", WORLD, "") \
	.as_debug()
static var body_yaw_deg := num("body_yaw_deg", "player.body_yaw_deg", 0.0, "Body yaw",
	"Rotate Anon's body left or right for testing; the camera and pose are unchanged.", WORLD, "") \
	.with_unit("°").with_step(1.0).as_debug()
static var act_line_angles := flag("act_line_angles", "features.act_line_angles", true,
	"Use line angles",
	"Give cue lines one fresh angle: something from your personality, your day with Anon, or a tender beat. Off keeps every line on the private moment alone.", WORLD, "") \
	.as_debug()
static var act_speech_feel := flag("act_speech_feel", "features.act_speech_feel", false,
	"Add speech interjections",
	"Describe how Anon's current strokes break up her speech with interjections. Off keeps her sentences whole.", WORLD, "") \
	.as_debug()

# -- History › Points  (debug)
static var apology_repair := num("apology_repair", "history.apology_repair", 1.0,
	"Apology repair", "Hurt removed by one sincere apology per day.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var bad_hurt := num("bad_hurt", "history.bad_hurt", 1.0, "Bad hurt",
	"Hurt added by a bad act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var decay_amount := num("decay_amount", "history.decay_amount", 1.0, "Decay amount",
	"Hurt removed by one decay step.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var decay_days := num("decay_days", "history.decay_days", 2.0, "Decay days",
	"In-game days per hurt decay step.", WORLD, "History › Points") \
	.with_unit("days").with_step(0.5).as_debug()
static var good_comfort := num("good_comfort", "history.good_comfort", 1.0, "Good comfort",
	"Comfort added by a good act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var good_repair := num("good_repair", "history.good_repair", 1.0, "Good repair",
	"Hurt removed by a good act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var great_comfort := num("great_comfort", "history.great_comfort", 2.0, "Great comfort",
	"Comfort added by a great act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var great_repair := num("great_repair", "history.great_repair", 2.0, "Great repair",
	"Hurt removed by a great act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var max_comfort := num("max_comfort", "history.max_comfort", 8.0, "Comfort cap",
	"Maximum stored comfort points.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var max_hurt := num("max_hurt", "history.max_hurt", 8.0, "Hurt cap",
	"Maximum stored hurt points.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var mild_hurt := num("mild_hurt", "history.mild_hurt", 1.0, "Early-end hurt",
	"Hurt added by a neutral early end.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var offer_block_hurt := num("offer_block_hurt", "history.offer_block_hurt", 4.0,
	"No offers at", "Hurt points at which a mare stops asking for sex.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var reminder_hurt := num("reminder_hurt", "history.reminder_hurt", 2.0, "Reminder at",
	"Hurt points at which a mare starts reminding Anon.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var severe_hurt := num("severe_hurt", "history.severe_hurt", 2.0, "Severe hurt",
	"Hurt added by a severe act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()
static var withdraw_hurt := num("withdraw_hurt", "history.withdraw_hurt", 6.0, "Not tonight at",
	"Hurt points at which a mare gently refuses an act.", WORLD, "History › Points") \
	.with_step(1.0).as_debug()

# -- History › Score  (debug)
static var bad_max := num("bad_max", "history.bad_max", 0.2, "Bad threshold",
	"Fraction of the applicable actions at or below which an act is bad.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var early_grace_s := num("early_grace_s", "history.early_grace_s", 20.0, "Early grace",
	"Seconds before an intentional early end counts as a summary.", WORLD, "History › Score") \
	.with_unit("s").with_step(1.0).as_debug()
static var good_min := num("good_min", "history.good_min", 0.8, "Good threshold",
	"Fraction of the applicable actions that must go right for a good act.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var min_thrusts := num("min_thrusts", "history.min_thrusts", 2.0, "Minimum thrusts",
	"Real thrusts that make a very short act scoreable.", WORLD, "History › Score") \
	.with_step(1.0).as_debug()
static var p_dislike := num("p_dislike", "history.p_dislike", 0.1, "Dislike penalty",
	"Subtract per scored disliked touch or talk.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var p_miss := num("p_miss", "history.p_miss", 0.1, "Missed-preference penalty",
	"Extra penalty for a missed touch or movement preference.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var p_severe := num("p_severe", "history.p_severe", 0.15, "Severe penalty",
	"Extra penalty for repeated disliked handling.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var p_silence := num("p_silence", "history.p_silence", 0.15, "Silence penalty",
	"Extra penalty for silent sex with a mare who likes to talk.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var w_climax := num("w_climax", "history.w_climax", 0.3, "Climax weight",
	"Score weight for her reaching climax.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var w_motion := num("w_motion", "history.w_motion", 0.15, "Motion weight",
	"Weight for matching both of her motion preferences.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var w_not_early := num("w_not_early", "history.w_not_early", 0.15, "Not-early weight",
	"Weight for not ending before a mare finishes.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var w_talk := num("w_talk", "history.w_talk", 0.2, "Talk weight",
	"Score weight for talk that a talk-seeking mare enjoys.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()
static var w_touch := num("w_touch", "history.w_touch", 0.2, "Touch weight",
	"Score component for touch that matches her preference.", WORLD, "History › Score") \
	.with_step(0.01).with_range(0.0, 1.0).as_debug()

# -- History › Offers  (debug)
static var offer_base_s := num("offer_base_s", "history.offer_base_s", 600.0, "Offer cooldown",
	"Base seconds between proactive offers.", WORLD, "History › Offers") \
	.with_unit("s").with_step(10.0).as_debug()
static var offer_comfort_scale := num("offer_comfort_scale", "history.offer_comfort_scale",
	0.05, "Comfort cooldown", "Cooldown reduction per comfort point.", WORLD, "History › Offers") \
	.with_step(0.01).as_debug()
static var offer_min_s := num("offer_min_s", "history.offer_min_s", 300.0, "Cooldown floor",
	"Shortest cooldown at high comfort.", WORLD, "History › Offers") \
	.with_unit("s").with_step(10.0).as_debug()
static var offer_weight_base := num("offer_weight_base", "history.offer_weight_base", 0.7,
	"Offer weight", "Base chance weight for a proactive offer.", WORLD, "History › Offers") \
	.with_step(0.01).as_debug()
static var offer_weight_comfort := num("offer_weight_comfort", "history.offer_weight_comfort",
	0.05, "Comfort weight", "Offer weight added per comfort point.", WORLD, "History › Offers") \
	.with_step(0.01).as_debug()
static var offer_weight_hurt := num("offer_weight_hurt", "history.offer_weight_hurt", 0.12,
	"Hurt weight", "Offer weight removed per hurt point.", WORLD, "History › Offers") \
	.with_step(0.01).as_debug()

# -- Neglect tolerance  (debug)
static var tolerance_decay_amount := num("tolerance_decay_amount", "tolerance.decay_amount",
	1.0, "Decay amount", "Distress removed per decay step.", WORLD, "Neglect tolerance") \
	.with_step(0.1).as_debug()
static var decay_seconds := num("decay_seconds", "tolerance.decay_seconds", 25.0,
	"Decay interval", "Seconds per passive distress decay step.", WORLD, "Neglect tolerance") \
	.with_unit("s").with_step(1.0).as_debug()
static var dislike_amount := num("dislike_amount", "tolerance.dislike_amount", 1.0,
	"Dislike amount", "Distress added by each actual disliked touch or talk.", WORLD, "Neglect tolerance") \
	.with_step(0.1).as_debug()
static var forgiving_warning := num("forgiving_warning", "tolerance.forgiving_warning", 4.0,
	"Forgiving warning", "Distress at which a forgiving mare gives her one warning.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()
static var like_relief := num("like_relief", "tolerance.like_relief", 1.0, "Like relief",
	"Distress removed by each actual liked touch or talk.", WORLD, "Neglect tolerance") \
	.with_step(0.1).as_debug()
static var normal_cooldown_s := num("normal_cooldown_s", "tolerance.normal_cooldown_s", 300.0,
	"Normal cooldown", "Sex-only cooldown after a normal mare stops.", WORLD, "Neglect tolerance") \
	.with_unit("s").with_step(10.0).as_debug()
static var normal_stop := num("normal_stop", "tolerance.normal_stop", 10.0, "Normal stop",
	"Distress at which a normal mare stops the act.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()
static var normal_warning_1 := num("normal_warning_1", "tolerance.normal_warning_1", 1.0,
	"Normal warning 1", "First warning for a normal mare.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()
static var normal_warning_2 := num("normal_warning_2", "tolerance.normal_warning_2", 4.0,
	"Normal warning 2", "Second warning for a normal mare.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()
static var strict_cooldown_s := num("strict_cooldown_s", "tolerance.strict_cooldown_s", 600.0,
	"Strict cooldown", "Sex-only cooldown after a strict mare stops.", WORLD, "Neglect tolerance") \
	.with_unit("s").with_step(10.0).as_debug()
static var strict_stop := num("strict_stop", "tolerance.strict_stop", 3.0, "Strict stop",
	"Distress at which a strict mare stops the act.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()
static var strict_warning := num("strict_warning", "tolerance.strict_warning", 1.0,
	"Strict warning", "Warning threshold for a strict mare.", WORLD, "Neglect tolerance") \
	.with_step(1.0).as_debug()

const DEFAULT_ACT_PROMPTS := {
	"utterance": "You are in the middle of sex with Anon, not kissing him. The private moment is: {seed} Current moment: {state}. Private relationship note: {relationship}. Tone: {tone}. {memory} Say ONE short line in your own voice, at most 18 words. React to him and to the moment as the mare you are; you do not have to describe the sensation or narrate the moment; you can ask for something, tease him, say something tender, or say nothing about the mechanics. Begin with exactly [whispering] unless the moment calls for [calm], [happy], [annoyed] or [surprised]. You may start with one [face:...] tag. No narration, no stage directions, no anatomy, no questions that need an answer, and do not end the act. Your preferences are private, not a list to say. Your preferences: {preferences}. Do not repeat: {recent}.",
	"cue": "During sex with Anon, the private moment is: {seed} Current moment: {state}. Private relationship note: {relationship}. Tone: {tone}. {memory} Say ONE short line in your own voice, at most 14 words. React to him and to the moment as the mare you are; you do not have to describe the sensation or narrate the moment; you can ask for something, tease him, say something tender, or say nothing about the mechanics. Let the relationship and the memory color it without naming labels, levels, numbers, or the note. Do not invent a memory beyond the one given. Begin with [whispering] or [happy]. No narration, no stage directions, no anatomy. Your preferences: {preferences}. Do not repeat: {recent}.",
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
	"preferences": {},
}

## Every spawnable adult mare's preference template lives in the same catalog.
const CHARACTER_TEMPLATES := CHARACTERS.TEMPLATES

## The settings file's schema version. Bump it when `_migrate()` gains a one-time step, so an old
## file runs the step exactly once.
const SCHEMA_VERSION := 3

## Retired settings, declared where their replacement lives. `map` receives the stored value and
## returns the dictionary to merge, or an empty dictionary to drop it. The loader applies every
## entry before the defaults merge, so a retired key cannot linger in the file.
static var _deprecated := [
	# The dock used to be hidden by a `true` switch; keep the player's choice across the rename.
	deprecated("anatomy.hide_dock",
		func(value: Variant) -> Dictionary: return {"anatomy.show_dock": not bool(value)}),
	# The separate log switch folded into the debug switch.
	deprecated("debug_logs", func(_value: Variant) -> Dictionary: return {}),
	# Thrust sensitivity is now a physical scale: pixels per centimetre of hip travel. The old
	# value was pixels for one full stroke; 20 cm is the reference shaft, so its feel is kept.
	deprecated("thrust.pixels_per_full",
		func(value: Variant) -> Dictionary: return {"thrust.pixels_per_cm": float(value) / 20.0}),
]


## One retired setting. Add the entry to `_deprecated` above.
static func deprecated(path: String, map: Callable) -> Dictionary:
	return {"path": path, "map": map}

static func _path() -> String:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		var mods: Node = loop.root.get_node_or_null("Mods")
		if mods != null and mods.has_method("data_folder"):
			return str(mods.call("data_folder", ID)).path_join(FILE)
	return "user://mods/data/%s/%s" % [ID, FILE]


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
	var value: Variant = template.get("preferences", {})
	if value is Dictionary:
		return PREFERENCES.resolve(value)
	return PREFERENCES.defaults()


## The character's own preference template, before any player override. Empty for an id with no
## template. Reset to default and the form's comparison both use this.
static func character_default_preferences(id: String) -> Dictionary:
	var template: Variant = CHARACTER_TEMPLATES.get(id, {})
	if template is Dictionary:
		var raw: Variant = (template as Dictionary).get("preferences", {})
		if raw is Dictionary:
			return PREFERENCES.resolve(raw)
	return {}


## The preference profile a character returns to when her saved override is removed: her own
## template for a known mare, the global default profile otherwise.
static func default_preferences_for(base: Dictionary, id: String) -> Dictionary:
	var character := character_default_preferences(id)
	if not character.is_empty():
		return character
	return PREFERENCES.resolve(base.get("preferences", {}))


static func default_preferences(id: String) -> Dictionary:
	var data := _read()
	return default_preferences_for(data.get("default", _filled_default()), id)


## Compare two preference profiles. Arrays are sets, so a reordered saved list still matches.
static func preferences_match(a: Dictionary, b: Dictionary) -> bool:
	var left := PREFERENCES.resolve(a)
	var right := PREFERENCES.resolve(b)
	for key: String in ["intensity", "pattern", "warmth", "tolerance", "notes"]:
		if str(left.get(key, "")) != str(right.get(key, "")):
			return false
	for key: String in ["touch", "talk", "dislikes"]:
		if not _same_set(left.get(key, []), right.get(key, [])):
			return false
	return true


static func _same_set(a: Variant, b: Variant) -> bool:
	var left: Array = a if a is Array else []
	var right: Array = b if b is Array else []
	if left.size() != right.size():
		return false
	var seen: Dictionary = {}
	for item: Variant in left:
		seen[str(item)] = true
	for item: Variant in right:
		if not seen.has(str(item)):
			return false
	return true


## integration: her consent for the optional anatomy actions. A per-character override wins;
## otherwise the deterministic id defaults apply.
static func consent(id: String) -> Dictionary:
	var template := template_for(id)
	return CONSENT.resolve(id, template.get("consent", {}))


## integration: save only the consent block. Preferences, prompts and poses are preserved.
static func save_consent(id: String, values: Dictionary) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	var roster: Dictionary = characters
	var entry: Variant = roster.get(id, {})
	if not entry is Dictionary:
		entry = {}
	var character: Dictionary = entry
	character["consent"] = CONSENT.clean(values)
	roster[id] = character
	data["characters"] = roster
	_write(data)


static func character_name(id: String) -> String:
	if CHARACTER_NAMES.has(id):
		return str(CHARACTER_NAMES[id])
	return id.replace("_", " ").capitalize()


## Save only the preference block. Character prompts and pose settings are preserved.
static func save_preferences(id: String, preferences: Dictionary) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	var roster: Dictionary = characters
	var entry: Variant = roster.get(id, {})
	if not entry is Dictionary:
		entry = {}
	var character: Dictionary = entry
	character["preferences"] = PREFERENCES.resolve(preferences)
	roster[id] = character
	data["characters"] = roster
	_write(data)


## Remove only the preference override; the generated/default preference returns. Prompts and poses stay.
static func reset_preferences(id: String) -> void:
	var data := _read()
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary:
		characters = {}
	var roster: Dictionary = characters
	var entry: Variant = roster.get(id, {})
	if entry is Dictionary:
		(entry as Dictionary).erase("preferences")
		if (entry as Dictionary).is_empty():
			roster.erase(id)
		else:
			roster[id] = entry
	else:
		roster.erase(id)
	data["characters"] = roster
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


## Split the old line-variety flag. Its speech-feel choice is preserved; the angle half follows the
## new default. The old key is erased so it cannot linger in settings.json.
static func _normalize_line_variety(data: Dictionary) -> Dictionary:
	var features: Variant = data.get("features")
	if not features is Dictionary:
		return data
	var block: Dictionary = features
	if not block.has("act_line_variety"):
		return data
	var old_value := bool(block["act_line_variety"])
	if not block.has("act_speech_feel"):
		block["act_speech_feel"] = old_value
	block.erase("act_line_variety")
	return data


## Drop obsolete prompt keys and known old built-ins so the current defaults apply. A custom value
## for a current key is preserved.
static func _normalize_act_prompts(data: Dictionary) -> Dictionary:
	var blocks: Array = []
	if data.get("default") is Dictionary:
		blocks.append(data["default"])
	if data.get("characters") is Dictionary:
		for entry: Variant in (data["characters"] as Dictionary).values():
			if entry is Dictionary:
				blocks.append(entry)
	for block: Dictionary in blocks:
		var raw: Variant = block.get("act_prompts")
		if not raw is Dictionary:
			continue
		var prompts: Dictionary = raw
		for key: Variant in prompts.keys():
			var name := str(key)
			if not DEFAULT_ACT_PROMPTS.has(name):
				prompts.erase(key)
				continue
			var legacy: Variant = LEGACY_ACT_PROMPTS.get(name, [])
			if str(prompts[key]) in legacy:
				prompts.erase(key)
		if prompts.is_empty():
			block.erase("act_prompts")
	return data


## Remove saved prompt overrides and return to the built-in prompts. Preferences, poses, consent
## and event prompts are untouched.
static func reset_act_prompts() -> bool:
	var data := _read()
	var changed := false
	if data.get("default") is Dictionary and (data["default"] as Dictionary).has("act_prompts"):
		(data["default"] as Dictionary).erase("act_prompts")
		changed = true
	if data.get("characters") is Dictionary:
		for entry: Variant in (data["characters"] as Dictionary).values():
			if entry is Dictionary and (entry as Dictionary).has("act_prompts"):
				(entry as Dictionary).erase("act_prompts")
				changed = true
	if changed:
		_write(data)
	return changed


## Move the old `taste` block onto `preferences` for the default template and every character.
static func _normalize_character_preferences(data: Dictionary) -> Dictionary:
	var blocks: Array = []
	if data.get("default") is Dictionary:
		blocks.append(data["default"])
	if data.get("characters") is Dictionary:
		for entry: Variant in (data["characters"] as Dictionary).values():
			if entry is Dictionary:
				blocks.append(entry)
	for block: Dictionary in blocks:
		if block.has("taste"):
			if not block.has("preferences"):
				block["preferences"] = block["taste"]
			block.erase("taste")
	# The global default profile carries a generic private note. A settings file written before
	# the note existed has an empty string, so fill only that empty default note. A saved
	# character note is never touched, because a player may intentionally clear one.
	if data.get("default") is Dictionary:
		var default_block: Dictionary = data["default"]
		var preferences: Variant = default_block.get("preferences")
		if preferences is Dictionary \
				and str((preferences as Dictionary).get("notes", "")).strip_edges().is_empty():
			(preferences as Dictionary)["notes"] = PREFERENCES.DEFAULTS["notes"]
	return data


## Move the tolerance block's old tier keys onto the renamed paths.
static func _normalize_tolerance(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("tolerance")
	if not raw is Dictionary:
		return data
	var block: Dictionary = raw
	for old_key: String in LEGACY_TOLERANCE_KEYS:
		var new_key: String = LEGACY_TOLERANCE_KEYS[old_key]
		if block.has(old_key):
			if not block.has(new_key):
				block[new_key] = block[old_key]
			block.erase(old_key)
	data["tolerance"] = block
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
	var out: Dictionary = default_block("presentation.")
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
## Bumped on every load and every write. The flat value table rebuilds when it
## changes, so a save anywhere invalidates the cached setting reads.
static var generation := 0


## Drop the in-memory copy so the next read reloads the file. The settings page calls this when
## it opens, so a hand-edited settings.json applies without restarting the game.
## Not named `reload`: `Script` already has `reload()`, and a preloaded script constant resolves
## the built-in instead of a same-named static function.
static func reload_file() -> void:
	_loaded = false


## The merged settings view.
static func data() -> Dictionary:
	return _read()


## Write one dotted path (`presentation.standing.smack.raise_m`) and save the file.
## Not named `set_path`: `Script` already has `set_path(path)`, and a preloaded script constant
## resolves the built-in instead of a same-named static function.
static func write_setting(path: String, value: Variant) -> void:
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
	# A known mare's preference block starts from her own template, so removing her saved
	# preference override restores that profile instead of the global default.
	var character_default := character_default_preferences(id)
	if not character_default.is_empty():
		selected["preferences"] = character_default.duplicate(true)
	if characters is Dictionary and (characters as Dictionary).has(id):
		var over: Variant = (characters as Dictionary)[id]
		if over is Dictionary:
			selected = _merge(selected, over)
	selected["preferences"] = PREFERENCES.resolve(selected.get("preferences", {}))
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
	data = _migrate(data, int(data.get("version", 0)))
	data = _merge(_defaults(), data)
	data["version"] = SCHEMA_VERSION
	_cache = data
	_write_file(data)


static func _defaults() -> Dictionary:
	var out: Dictionary = {
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
		"ui": {"sections": {}},
	}
	for s: Setting in _registry:
		_write_path(out, s.path, s.default)
	return out


## The old flat entry dictionary, for the compatibility layer only.
static func entry_view(s: Setting) -> Dictionary:
	var out: Dictionary = {
		"kind": "bool" if s is FlagSetting else "num" if s is NumSetting else
			"choice" if s is ChoiceSetting else "color" if s is ColorSetting else "list",
		"default": s.default, "label": s.label, "help": s.help, "group": s.group,
		"tab": s.tab, "debug": s.debug,
	}
	if s is NumSetting:
		var n := s as NumSetting
		out["unit"] = n.unit
		out["step"] = n.step
		out["scale"] = n.scale
		out["low"] = n.low
		out["high"] = n.high
		out["clamp"] = not n.debug
		out["slider"] = n.slider
	if s is ChoiceSetting:
		var c := s as ChoiceSetting
		out["options"] = c.options
		out["labels"] = c.labels
	if s is ListSetting:
		out["options"] = (s as ListSetting).options
	return out


## Default template plus catalog pose/preference/prompt defaults. Kept as a function so the
## catalogs are read at run time instead of baked into a const expression.
static func _filled_default() -> Dictionary:
	var out: Dictionary = DEFAULT_TEMPLATE.duplicate(true)
	out["poses"] = CATALOG.POSE_DEFAULTS.duplicate(true)
	out["preferences"] = PREFERENCES.defaults()
	# Act prompts are code defaults; settings.json stores only overrides. `_fill_prompts()`
	# supplies the current built-ins at read time so a release can update them.
	return out


## Retired settings, then the one-time structural steps. Add a step here for a renamed key and bump
## `SCHEMA_VERSION`; a current file skips the structural chain. `deprecated()` entries always run,
## whatever the version, so a retired key can never linger in the file.
static func _migrate(data: Dictionary, version := 0) -> Dictionary:
	for entry: Variant in _deprecated:
		var path := str((entry as Dictionary).get("path", ""))
		var value: Variant = _read_path(data, path, null)
		if value == null:
			continue
		var mapped: Variant = ((entry as Dictionary).get("map") as Callable).call(value)
		_erase_path(data, path)
		if mapped is Dictionary:
			for key: Variant in (mapped as Dictionary).keys():
				_write_path(data, str(key), (mapped as Dictionary)[key])
	if version >= SCHEMA_VERSION:
		return data
	data = _normalize_anatomy_visibility(data)
	data = _normalize_pose_names(data)
	data = _normalize_feature_names(data)
	data = _normalize_line_variety(data)
	data = _normalize_presentation(data)
	data = _normalize_tolerance(data)
	data = _normalize_character_preferences(data)
	data = _normalize_act_prompts(data)
	data = _normalize_anatomy(data)
	return data


## Remove one dotted path, leaving the rest of its block.
static func _erase_path(data: Dictionary, path: String) -> void:
	var parts := path.split(".", false)
	if parts.is_empty():
		return
	var node: Dictionary = data
	for index: int in parts.size() - 1:
		var key := parts[index]
		var child: Variant = node.get(key)
		if not child is Dictionary:
			return
		node = child
	node.erase(parts[parts.size() - 1])


## The anatomy used to be a master switch plus an "only during acts" switch; both fold into the
## one `anatomy.anatomy_mode` pill. Runs once, before the defaults merge.
static func _normalize_anatomy_visibility(data: Dictionary) -> Dictionary:
	var features: Variant = data.get("features")
	var was_on := false
	if features is Dictionary and (features as Dictionary).has("anatomy"):
		was_on = bool((features as Dictionary)["anatomy"])
		(features as Dictionary).erase("anatomy")
	var anatomy: Variant = data.get("anatomy")
	if not anatomy is Dictionary:
		return data
	var block := anatomy as Dictionary
	if block.has("act_only"):
		var act_only := bool(block["act_only"])
		if not block.has("anatomy_mode"):
			block["anatomy_mode"] = "never" if not was_on else ("act" if act_only else "always")
		block.erase("act_only")
	data["anatomy"] = block
	return data


## One-off migrations for anatomy keys: the vertical placement was first a downward drop, and a
## batch of controls was later removed. Unknown keys are inert, but keep the file clean.
static func _normalize_anatomy(data: Dictionary) -> Dictionary:
	var anatomy: Variant = data.get("anatomy", {})
	if not anatomy is Dictionary:
		return data
	var block := anatomy as Dictionary
	# The old `winking_model` choice became the full-genitals `mare_bits` choice.
	if block.has("winking_model"):
		var old_model := str(block["winking_model"])
		if not block.has("mare_bits"):
			block["mare_bits"] = "v2" if old_model == "sculpted" or old_model == "v2" else "original"
		block.erase("winking_model")
	if block.has("mare_bits") and str(block["mare_bits"]) == "sculpted":
		block["mare_bits"] = "v2"
	if block.has("anal_drop_mm"):
		if not block.has("anal_height_mm"):
			block["anal_height_mm"] = -float(block["anal_drop_mm"])
		block.erase("anal_drop_mm")
	var tone: Variant = block.get("skin_tone")
	if tone is String:
		block["skin_tone"] = float(LEGACY_SKIN_TONES.get(str(tone),
			_default_at("anatomy.skin_tone")))
	# The strip used to follow the teats switch. Keep an existing teats-off file fully off once;
	# from then on the two switches are independent.
	if block.has("teats") and not bool(block["teats"]) and not block.has("skin_strip"):
		block["skin_strip"] = false
	for key: String in ["anal_swell", "anal_depth", "anal_pitch_deg", "anal_side_mm",
			"anal_tilt_deg", "cover_depth_m", "max_back_m", "player_pitch_deg",
			"player_yaw_deg", "player_roll_deg", "hole_depth", "anal_hug", "hug",
			"vulva_hug", "pair_limit", "genital_yaw_deg", "max_depth_m"]:
		block.erase(key)
	data["anatomy"] = block
	return data


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
