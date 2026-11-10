extends RefCounted
## The one settings module: every global setting, the settings file, and the per-mare profiles.
##
##   const SETTINGS := preload("res://mods/unfplap/settings.gd")
##   if SETTINGS.act_vocals.get_bool(): ...
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
const PLACEMENT := preload("res://mods/unfplap/anatomy_placement.gd")
const TAIL_PLACEMENT := preload("res://mods/unfplap/tail_seat_placement.gd")
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
	"pose1_pitch_deg": "pitch_deg",
}
const LEGACY_DROPPED_KEYS := ["pose1_camera", "pose1_side_lean"]
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
		"During sex with Anon, the private moment is: {seed} Current moment: {state}. Private relationship note: {relationship}. Tone: {tone}. {memory} Say ONE short line in your own voice, at most 14 words. React to him and to the moment as the mare you are; you do not have to describe the sensation or narrate the moment; you can ask for something, tease him, say something tender, or say nothing about the mechanics. Let the relationship and the memory color it without naming labels, levels, numbers, or the note. Do not invent a memory beyond the one given. Begin with [whispering] or [happy]. No narration, no stage directions, no anatomy. Your preferences: {preferences}. Do not repeat: {recent}.",
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
## `SETTINGS.act_vocals.get_bool()`; the JSON path appears only in the declaration.
class Setting:
	var name: String
	var path: String
	var label: String
	var help: String
	var tab: String
	var group: String
	var default: Variant
	var debug := false
	## Hidden settings are still real, persisted settings; a hand-built control elsewhere in
	## `settings_ui.gd` draws them (the placement target pill).
	var hidden := false
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

	## Keep the setting out of the declaration-drawn rows; a hand-built control owns the widget.
	func as_hidden() -> Setting:
		hidden = true
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

	func as_hidden() -> ChoiceSetting:
		hidden = true
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


# ---------------------------------------------------------------- anatomy placement
## The five keys of one placement block, complete and validated.
static func _declared_placement_defaults() -> Dictionary:
	return {
		"offset_x": float(offset_x.default),
		"offset_y": float(offset_y.default),
		"offset_z": float(offset_z.default),
		"pitch_deg": float(pitch_deg.default),
		"scale": float(scale.default),
	}


static func _placement_default_values() -> Dictionary:
	var declared := _declared_placement_defaults()
	if not _placement_draft.is_empty():
		return PLACEMENT.sanitize(_placement_draft, declared)
	return PLACEMENT.sanitize({
		"offset_x": offset_x.get_num(),
		"offset_y": offset_y.get_num(),
		"offset_z": offset_z.get_num(),
		"pitch_deg": pitch_deg.get_num(),
		"scale": scale.get_num(),
	}, declared)


## The placement a mare gets from the global default and the shipped per-mare table, before any
## player override. `use_draft` includes the unsaved default preview from the Anatomy place
## actions; saving a per-mare override compares against the persisted default instead.
static func anatomy_placement_default(id: String, use_draft := true) -> Dictionary:
	var base := _persisted_placement_default_values()
	if use_draft:
		base = _placement_default_values()
	var shipped: Variant = PLACEMENT.MARE_DEFAULTS.get(id, {})
	return PLACEMENT.merge(base, shipped)


static func _persisted_placement_default_values() -> Dictionary:
	var declared := _declared_placement_defaults()
	return PLACEMENT.sanitize({
		"offset_x": offset_x.get_num(),
		"offset_y": offset_y.get_num(),
		"offset_z": offset_z.get_num(),
		"pitch_deg": pitch_deg.get_num(),
		"scale": scale.get_num(),
	}, declared)


## The placement a mare actually uses: her player override, then the shipped per-mare default,
## then the global default.
static func anatomy_placement(id: String) -> Dictionary:
	var base := anatomy_placement_default(id)
	var data := _read()
	var anatomy: Variant = data.get("anatomy", {})
	if not anatomy is Dictionary:
		return base
	var placement: Variant = (anatomy as Dictionary).get("placement", {})
	if not placement is Dictionary:
		return base
	var over: Variant = (placement as Dictionary).get(id, {})
	return PLACEMENT.merge(base, over)


static func anatomy_placement_has_override(id: String) -> bool:
	var data := _read()
	var anatomy: Variant = data.get("anatomy", {})
	if not anatomy is Dictionary:
		return false
	var placement: Variant = (anatomy as Dictionary).get("placement", {})
	if not placement is Dictionary:
		return false
	var over: Variant = (placement as Dictionary).get(id, {})
	if not over is Dictionary or (over as Dictionary).is_empty():
		return false
	var base := anatomy_placement_default(id, false)
	return not PLACEMENT.same(PLACEMENT.merge(base, over), base)


## The player-part placement. It is one global block, never per-mare.
static func anon_placement() -> Dictionary:
	return PLACEMENT.sanitize({
		"offset_x": anon_offset_x.get_num(),
		"offset_y": anon_offset_y.get_num(),
		"offset_z": anon_offset_z.get_num(),
		"pitch_deg": anon_pitch_deg.get_num(),
		"scale": anon_scale.get_num(),
	}, {
		"offset_x": float(anon_offset_x.default),
		"offset_y": float(anon_offset_y.default),
		"offset_z": float(anon_offset_z.default),
		"pitch_deg": float(anon_pitch_deg.default),
		"scale": float(anon_scale.default),
	})


## Store only the keys that differ from the mare's default. An empty diff removes the override.
static func save_anatomy_placement(id: String, values: Dictionary) -> void:
	if id.is_empty() or id == "default" or id == "anon":
		return
	var base := anatomy_placement_default(id, false)
	var current := PLACEMENT.sanitize(values, base)
	var over := PLACEMENT.diff(current, base)
	var data := _read()
	var anatomy: Variant = data.get("anatomy", {})
	var block: Dictionary = anatomy if anatomy is Dictionary else {}
	var placement: Variant = block.get("placement", {})
	var rows: Dictionary = placement if placement is Dictionary else {}
	if over.is_empty():
		rows.erase(id)
	else:
		rows[id] = over
	if rows.is_empty():
		block.erase("placement")
	else:
		block["placement"] = rows
	if block.is_empty():
		data.erase("anatomy")
	else:
		data["anatomy"] = block
	_write(data)


## Persist the unsaved default preview.
static func save_anatomy_placement_default(values: Dictionary) -> void:
	var current := PLACEMENT.sanitize(values, _declared_placement_defaults())
	_placement_draft = {}
	offset_x.set_num(float(current["offset_x"]))
	offset_y.set_num(float(current["offset_y"]))
	offset_z.set_num(float(current["offset_z"]))
	pitch_deg.set_num(float(current["pitch_deg"]))
	scale.set_num(maxf(0.05, float(current["scale"])))
	placement_revision += 1


## Preview the declaration defaults without saving them.
static func reset_anatomy_placement_default() -> void:
	_placement_draft = _declared_placement_defaults()
	placement_revision += 1


static func set_anatomy_placement_draft(values: Dictionary) -> void:
	_placement_draft = PLACEMENT.sanitize(values, _declared_placement_defaults())
	placement_revision += 1


static func clear_anatomy_placement_draft() -> void:
	if _placement_draft.is_empty():
		return
	_placement_draft = {}
	placement_revision += 1


static func has_anatomy_placement_draft() -> bool:
	return not _placement_draft.is_empty()


static func anatomy_placement_draft_values() -> Dictionary:
	return _placement_default_values()


# ---------------------------------------------------------------- tail seat exceptions
## The pointed mare's saved exception from the exact reference anchor, zero when she has none.
static func tail_seat_offset(id: String) -> Vector2:
	var row: Variant = _tail_seat_row(id)
	if not row is Dictionary:
		return Vector2.ZERO
	return TAIL_PLACEMENT.read(row)


## One mare's dock-only distance in metres, zero when she has none.
static func tail_seat_dock(id: String) -> float:
	var row: Variant = _tail_seat_row(id)
	if not row is Dictionary:
		return 0.0
	return TAIL_PLACEMENT.dock(row)


## One mare's dock scale, 1.0 when she has none.
static func tail_seat_dock_scale(id: String) -> float:
	var row: Variant = _tail_seat_row(id)
	if not row is Dictionary:
		return 1.0
	return TAIL_PLACEMENT.dock_scale(row)


static func tail_seat_has_override(id: String) -> bool:
	return not TAIL_PLACEMENT.same(tail_seat_offset(id), Vector2.ZERO) \
		or not TAIL_PLACEMENT.same_dock(tail_seat_dock(id), 0.0) \
		or not TAIL_PLACEMENT.same_scale(tail_seat_dock_scale(id), 1.0)


## Store only the non-default Y/Z offset, dock distance and dock scale; default removes the row.
static func save_tail_seat(id: String, offset: Vector2, dock := 0.0, dock_scale := 1.0) -> void:
	if id.is_empty() or id == "default" or id == "anon":
		return
	var data := _read()
	var anatomy: Variant = data.get("anatomy", {})
	var block: Dictionary = anatomy if anatomy is Dictionary else {}
	var seats: Variant = block.get("tail_seat", {})
	var rows: Dictionary = seats if seats is Dictionary else {}
	var row := TAIL_PLACEMENT.diff(TAIL_PLACEMENT.sanitize(offset))
	row.merge(TAIL_PLACEMENT.dock_diff(dock))
	row.merge(TAIL_PLACEMENT.dock_scale_diff(dock_scale))
	if row.is_empty():
		rows.erase(id)
	else:
		rows[id] = row
	if rows.is_empty():
		block.erase("tail_seat")
	else:
		block["tail_seat"] = rows
	if block.is_empty():
		data.erase("anatomy")
	else:
		data["anatomy"] = block
	_write(data)


## Offset-only save keeps the mare's existing dock distance and scale.
static func save_tail_seat_offset(id: String, offset: Vector2) -> void:
	save_tail_seat(id, offset, tail_seat_dock(id), tail_seat_dock_scale(id))


## The raw stored row, or {} when the id is a preview key or has no exception.
static func _tail_seat_row(id: String) -> Variant:
	if id.is_empty() or id == "default" or id == "anon":
		return {}
	if not _loaded:
		_load()
	var anatomy: Variant = _cache.get("anatomy", {})
	if not anatomy is Dictionary:
		return {}
	var seats: Variant = (anatomy as Dictionary).get("tail_seat", {})
	if not seats is Dictionary:
		return {}
	return (seats as Dictionary).get(id, {})


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
static var pixels_per_cm := num("pixels_per_cm", "thrust.pixels_per_cm", 50.0,
	"Sensitivity",
	"Mouse travel for each centimetre the cock moves. A full stroke is his shaft length, so a "
	+ "longer part needs proportionally more travel.", GENERAL, "") \
	.with_unit("px per cm").with_step(10.0).with_range(20.0, 400.0)
static var orientation := choice("orientation", "thrust.orientation", "up", ["up", "down"],
	["Mouse Up", "Mouse Down"], "Thrust direction",
	"Which mouse direction deepens the thrust.", GENERAL, "")
static var anatomy_vr := flag("anatomy_vr", "features.anatomy_vr", true, "Use VR act",
	"The standing act in VR, with hip-tracker depth and controller actions. Untested on this build.", GENERAL, "")
static var anatomy_holes := flag("anatomy_holes", "features.anatomy_holes", true, "Allow hole switch",
	"Let V switch between the front and the anal cup.", GENERAL, "")
static var anatomy_oral := flag("anatomy_oral", "features.anatomy_oral", false, "Allow oral",
	"Let N turn her round for oral in the standing pose.", GENERAL, "")
static var anatomy_finish := flag("anatomy_finish", "features.anatomy_finish", false,
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
static var curve := choice("curve", "auto_thrust.curve", "tease",
	["cosine", "thrust", "tease", "saw", "hold"],
	["Normal", "Thrust", "Tease", "Saw", "Hold"],
	"Auto shape",
	"Shape of every automatic stroke. Normal is the symmetric ease; Thrust drives in fast and out "
	+ "slow, Tease the other way; Saw has no easing; Hold pauses at full depth.", GENERAL, "") \
	.as_debug()
static var contact_gap_m := num("contact_gap_m", "thrust.contact_gap_m", 0.0, "Contact gap",
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

# -- Caress  (debug)
static var caress_surface := flag("caress_surface", "features.caress_surface", false,
	"Use precise caress",
	"Place the caress hand from the visible body/head surface instead of the capsule hull.",
	GENERAL, "Caress").as_debug()
static var path_id := choice("path_id", "presentation.missionary.caress.path_id", "one",
	["one", "two"], ["Path one: belly/chest/neck/cheek", "Path two: flank/shoulder/neck"],
	"Missionary path",
	"Switch between the two authored missionary caress paths. Path one is belly/chest/neck/cheek; path two is flank/shoulder/neck.",
	GENERAL, "Caress").as_debug()
static var caress_debug := flag("caress_debug", "features.caress_debug", false,
	"Print caress contact",
	"Log the caress path, surface source, hand mode and contact once per hand per act.", GENERAL,
	"Caress").as_debug()
static var caress_reach_shoulder_m := num("caress_reach_shoulder_m",
	"features.caress_reach_shoulder_m", 0.02, "Missionary reach shoulder",
	"Maximum shoulder shift used to reach a caress target in missionary. 0 keeps the shoulder fixed; the path stops at the reachable point either way.",
	GENERAL, "Caress").with_unit("cm").with_step(1.0).with_scale(100.0).as_debug()
static var hover_m := num("hover_m", "caress.hover_m", 0.02, "Palm hover",
	"Palm-centre distance from her coat in both poses, in centimetres. Positive raises it, negative presses it into the coat.",
	GENERAL, "Caress").with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var ignore := list("ignore", "caress.ignore", ["tail", "wing"],
	["tail", "mane", "wing", "leg"], "Ignore body parts",
	"Regions the hull caress contact query skips. The precise surface uses fixed torso/head regions.",
	GENERAL, "Caress").as_debug()
static var normal_blur_m := num("normal_blur_m", "caress.normal_blur_m", 0.02,
	"Normal blur",
	"Average the coat normal over this radius so mesh creases do not snap the palm. 0 keeps the exact hit normal.",
	GENERAL, "Caress").with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var normal_deg_s := num("normal_deg_s", "caress.normal_deg_s", 120.0,
	"Normal turn",
	"Maximum palm normal turn rate. 0 disables the temporal normal clamp.",
	GENERAL, "Caress").with_unit("°/s").with_step(10.0).as_debug()
static var contact_smooth := num("contact_smooth", "caress.contact_smooth", 18.0,
	"Contact smooth",
	"Low-pass rate for the surface snap correction. 0 keeps the exact contact; the intended oval motion is never delayed.",
	GENERAL, "Caress").with_unit("/s").with_step(1.0).as_debug()
static var oval_across_m := num("oval_across_m", "caress.oval_across_m", 0.01,
	"Oval across", "Caress stroke length along the body.", GENERAL, "Caress") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var oval_up_m := num("oval_up_m", "caress.oval_up_m", 0.02,
	"Oval up", "Caress stroke height.", GENERAL, "Caress") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var canon := num("canon", "caress.palm_scale.canon", 0.75,
	"Palm scale (Canon)", "Caress hand scale for Canon-size Anon.", GENERAL, "Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var hoers := num("hoers", "caress.palm_scale.hoers", 1.0,
	"Palm scale (Hoers)", "Caress hand scale for the Hoers size.", GENERAL, "Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var mounting := num("mounting", "caress.palm_scale.mounting", 0.9,
	"Palm scale (Mounting)", "Caress hand scale for mounting size.", GENERAL, "Caress") \
	.with_unit("×").with_step(0.01).as_debug()
static var same_height := num("same_height", "caress.palm_scale.same height", 1.0,
	"Palm scale (Same height)", "Caress hand scale at Anon's own height.", GENERAL, "Caress") \
	.with_unit("×").with_step(0.01).as_debug()

# -- Audio  (debug)
static var act_climax := flag("act_climax", "features.act_climax", false, "Play wet climax",
	"Add the pack wet finish sound at her climax. Off keeps only the current climax squeak.",
	GENERAL, "") \
	.as_debug()
static var act_vocals := flag("act_vocals", "features.act_vocals", false, "Play act vocals",
	"Add the pack moan only at her climax. Off keeps the pony breath, Ponese voice and current climax squeak unchanged.",
	GENERAL, "") \
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
static var anon_size_match := num("anon_size_match",
	"presentation.missionary.anon_size_match", 0.0,
	"Anon size match",
	"How much Anon's body scales with the pony in missionary. 0 keeps him human-sized; 1 scales him with her.",
	GENERAL, "Missionary").with_range(0.0, 1.0).with_step(0.01).with_slider().as_debug()
static var disable_fold_coloring := flag("disable_fold_coloring",
	"presentation.missionary.disable_fold_coloring", true,
	"Hack: Disable fold coloring",
	"Draw the whole vulva in her outer skin color during the missionary act; the pink folds and clitoris colors are off.",
	GENERAL, "Missionary").as_debug()
static var camera_mode := choice("camera_mode", "presentation.missionary.camera_mode", "shots",
	["eye", "shots"], ["Anon eyes", "Authored shots"], "Camera",
	"Anon eyes: the view is his posed head, and leaning hinges his upper body at the spine. Authored shots: the eye follows the pose lab's camera positions.",
	GENERAL, "Missionary").as_debug()
static var third_person := flag("third_person", "presentation.missionary.third_person", false,
	"Third-person views",
	"Let the missionary shot lean and surge off the authored camera positions, so the eye drifts around the two bodies. Off keeps the camera on the authored trajectory.",
	GENERAL, "Missionary").as_debug()
static var free_look := flag("free_look", "presentation.missionary.free_look", false,
	"Use free look",
	"Turn the act shot where it stands, so the pose can be inspected. The mouse stops driving thrust.",
	GENERAL, "Missionary").as_debug()
static var part_inset_m := num("part_inset_m", "presentation.missionary.part_inset_m", -0.08,
	"Cock base inset",
	"Slide the cock base back toward Anon in missionary, in centimetres. Negative moves it into the pelvis; use it to hide the base and close the hip gap.",
	GENERAL, "Missionary").with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()

# -- Missionary size  (debug)
## The six geometry values are tuned per pony size. The dropdown above them picks which size is
## edited; the act always reads the size the game is currently set to. Every size starts at the old
## single default, so an unedited file behaves the same at every size.
const MISSIONARY_SIZES := ["canon", "mounting", "same height", "hoers"]
const MISSIONARY_SIZE_LABELS := ["Canon", "JRHNBR", "Same height", "Hoers"]
const MISSIONARY_SIZE_BASES := ["vulva_shift_mm", "vulva_pitch_deg", "vulva_depth_shift_mm",
	"vulva_hug_mm", "head_clearance_mm", "gaze_offset_mm"]
const MISSIONARY_SIZE_GROUP := "Missionary › Size"
static var size_group := choice("size_group", "presentation.missionary.size_group", "canon",
	MISSIONARY_SIZES, MISSIONARY_SIZE_LABELS, "Size",
	"The pony size these missionary values are for.", GENERAL, MISSIONARY_SIZE_GROUP).as_debug()
static var vulva_shift_mm_canon := num("vulva_shift_mm_canon",
	"presentation.missionary.size.canon.vulva_shift_mm", 70.0, "Vulva shift",
	"Raise or lower the vulva mesh only while the missionary act runs. Signed, unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var vulva_shift_mm_mounting := num("vulva_shift_mm_mounting",
	"presentation.missionary.size.mounting.vulva_shift_mm", 70.0, "Vulva shift",
	"Raise or lower the vulva mesh only while the missionary act runs. Signed, unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var vulva_shift_mm_same_height := num("vulva_shift_mm_same_height",
	"presentation.missionary.size.same height.vulva_shift_mm", 70.0, "Vulva shift",
	"Raise or lower the vulva mesh only while the missionary act runs. Signed, unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var vulva_shift_mm_hoers := num("vulva_shift_mm_hoers",
	"presentation.missionary.size.hoers.vulva_shift_mm", 70.0, "Vulva shift",
	"Raise or lower the vulva mesh only while the missionary act runs. Signed, unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var vulva_pitch_deg_canon := num("vulva_pitch_deg_canon",
	"presentation.missionary.size.canon.vulva_pitch_deg", 20.0, "Vulva pitch",
	"Tilt the vulva mesh only while the missionary act runs. Signed, unclamped degrees.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("°").with_step(0.5).as_debug()
static var vulva_pitch_deg_mounting := num("vulva_pitch_deg_mounting",
	"presentation.missionary.size.mounting.vulva_pitch_deg", 20.0, "Vulva pitch",
	"Tilt the vulva mesh only while the missionary act runs. Signed, unclamped degrees.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("°").with_step(0.5).as_debug()
static var vulva_pitch_deg_same_height := num("vulva_pitch_deg_same_height",
	"presentation.missionary.size.same height.vulva_pitch_deg", 20.0, "Vulva pitch",
	"Tilt the vulva mesh only while the missionary act runs. Signed, unclamped degrees.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("°").with_step(0.5).as_debug()
static var vulva_pitch_deg_hoers := num("vulva_pitch_deg_hoers",
	"presentation.missionary.size.hoers.vulva_pitch_deg", 20.0, "Vulva pitch",
	"Tilt the vulva mesh only while the missionary act runs. Signed, unclamped degrees.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("°").with_step(0.5).as_debug()
static var vulva_depth_shift_mm_canon := num("vulva_depth_shift_mm_canon",
	"presentation.missionary.size.canon.vulva_depth_shift_mm", 20.0, "Vulva depth shift",
	"Move the vulva vertically with the thrust: millimetres at 100% depth, easing in after 20%. Negative pushes it down.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var vulva_depth_shift_mm_mounting := num("vulva_depth_shift_mm_mounting",
	"presentation.missionary.size.mounting.vulva_depth_shift_mm", 20.0, "Vulva depth shift",
	"Move the vulva vertically with the thrust: millimetres at 100% depth, easing in after 20%. Negative pushes it down.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var vulva_depth_shift_mm_same_height := num("vulva_depth_shift_mm_same_height",
	"presentation.missionary.size.same height.vulva_depth_shift_mm", 20.0, "Vulva depth shift",
	"Move the vulva vertically with the thrust: millimetres at 100% depth, easing in after 20%. Negative pushes it down.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var vulva_depth_shift_mm_hoers := num("vulva_depth_shift_mm_hoers",
	"presentation.missionary.size.hoers.vulva_depth_shift_mm", 20.0, "Vulva depth shift",
	"Move the vulva vertically with the thrust: millimetres at 100% depth, easing in after 20%. Negative pushes it down.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var missionary_vulva_hug_mm_canon := num("missionary_vulva_hug_mm_canon",
	"presentation.missionary.size.canon.vulva_hug_mm", -2.0, "Hack: Vulva hug",
	"Missionary-only pad between the cock and the vulva lips. Positive opens, negative grips; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var missionary_vulva_hug_mm_mounting := num("missionary_vulva_hug_mm_mounting",
	"presentation.missionary.size.mounting.vulva_hug_mm", -2.0, "Hack: Vulva hug",
	"Missionary-only pad between the cock and the vulva lips. Positive opens, negative grips; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var missionary_vulva_hug_mm_same_height := num("missionary_vulva_hug_mm_same_height",
	"presentation.missionary.size.same height.vulva_hug_mm", -2.0, "Hack: Vulva hug",
	"Missionary-only pad between the cock and the vulva lips. Positive opens, negative grips; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var missionary_vulva_hug_mm_hoers := num("missionary_vulva_hug_mm_hoers",
	"presentation.missionary.size.hoers.vulva_hug_mm", -2.0, "Hack: Vulva hug",
	"Missionary-only pad between the cock and the vulva lips. Positive opens, negative grips; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(0.5).as_debug()
static var head_clearance_mm_canon := num("head_clearance_mm_canon",
	"presentation.missionary.size.canon.head_clearance_mm", 100.0, "Head clearance",
	"Keep the act camera this far outside her live skull and muzzle. Unclamped millimetres; 0 turns the guard off.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var head_clearance_mm_mounting := num("head_clearance_mm_mounting",
	"presentation.missionary.size.mounting.head_clearance_mm", 100.0, "Head clearance",
	"Keep the act camera this far outside her live skull and muzzle. Unclamped millimetres; 0 turns the guard off.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var head_clearance_mm_same_height := num("head_clearance_mm_same_height",
	"presentation.missionary.size.same height.head_clearance_mm", 100.0, "Head clearance",
	"Keep the act camera this far outside her live skull and muzzle. Unclamped millimetres; 0 turns the guard off.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var head_clearance_mm_hoers := num("head_clearance_mm_hoers",
	"presentation.missionary.size.hoers.head_clearance_mm", 100.0, "Head clearance",
	"Keep the act camera this far outside her live skull and muzzle. Unclamped millimetres; 0 turns the guard off.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var gaze_offset_mm_canon := num("gaze_offset_mm_canon",
	"presentation.missionary.size.canon.gaze_offset_mm", -250.0, "Gaze height",
	"Raise or lower where she looks at Anon during the act. Positive looks higher, negative lower; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var gaze_offset_mm_mounting := num("gaze_offset_mm_mounting",
	"presentation.missionary.size.mounting.gaze_offset_mm", -250.0, "Gaze height",
	"Raise or lower where she looks at Anon during the act. Positive looks higher, negative lower; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var gaze_offset_mm_same_height := num("gaze_offset_mm_same_height",
	"presentation.missionary.size.same height.gaze_offset_mm", -250.0, "Gaze height",
	"Raise or lower where she looks at Anon during the act. Positive looks higher, negative lower; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()
static var gaze_offset_mm_hoers := num("gaze_offset_mm_hoers",
	"presentation.missionary.size.hoers.gaze_offset_mm", -250.0, "Gaze height",
	"Raise or lower where she looks at Anon during the act. Positive looks higher, negative lower; unclamped millimetres.",
	GENERAL, MISSIONARY_SIZE_GROUP).with_unit("mm").with_step(1.0).as_debug()

## The size preset the game is currently set to. The game's Settings autoload is cached; the preset
## is the same for every pony of that size (a stallion is 1.2x the preset, not a preset of its own).
static var _game_settings: Node = null

static func pony_size_name() -> String:
	if not is_instance_valid(_game_settings):
		var loop := Engine.get_main_loop() as SceneTree
		_game_settings = loop.root.get_node_or_null("Settings") if loop != null else null
	if _game_settings == null:
		return "canon"
	return str(_game_settings.call("get_value", "ponies/size"))

static func vulva_shift_mm_for(size: String) -> float:
	match size:
		"mounting": return vulva_shift_mm_mounting.get_num()
		"same height": return vulva_shift_mm_same_height.get_num()
		"hoers": return vulva_shift_mm_hoers.get_num()
	return vulva_shift_mm_canon.get_num()

static func vulva_pitch_deg_for(size: String) -> float:
	match size:
		"mounting": return vulva_pitch_deg_mounting.get_num()
		"same height": return vulva_pitch_deg_same_height.get_num()
		"hoers": return vulva_pitch_deg_hoers.get_num()
	return vulva_pitch_deg_canon.get_num()

static func vulva_depth_shift_mm_for(size: String) -> float:
	match size:
		"mounting": return vulva_depth_shift_mm_mounting.get_num()
		"same height": return vulva_depth_shift_mm_same_height.get_num()
		"hoers": return vulva_depth_shift_mm_hoers.get_num()
	return vulva_depth_shift_mm_canon.get_num()

static func vulva_hug_mm_for(size: String) -> float:
	match size:
		"mounting": return missionary_vulva_hug_mm_mounting.get_num()
		"same height": return missionary_vulva_hug_mm_same_height.get_num()
		"hoers": return missionary_vulva_hug_mm_hoers.get_num()
	return missionary_vulva_hug_mm_canon.get_num()

static func head_clearance_mm_for(size: String) -> float:
	match size:
		"mounting": return head_clearance_mm_mounting.get_num()
		"same height": return head_clearance_mm_same_height.get_num()
		"hoers": return head_clearance_mm_hoers.get_num()
	return head_clearance_mm_canon.get_num()

static func gaze_offset_mm_for(size: String) -> float:
	match size:
		"mounting": return gaze_offset_mm_mounting.get_num()
		"same height": return gaze_offset_mm_same_height.get_num()
		"hoers": return gaze_offset_mm_hoers.get_num()
	return gaze_offset_mm_canon.get_num()

# -- Standing  (debug)
static var standing_play_bow := flag("standing_play_bow", "features.standing_play_bow", false,
	"Use play-bow stance",
	"Standing: stretch the front legs forward with the chest down and head low instead of the tucked act stance.", GENERAL, "Standing") \
	.as_debug()
static var chin_up_deg := num("chin_up_deg", "presentation.standing.chin_up_deg", 30.0,
	"Chin up", "Standing head lift at the chin.", GENERAL, "Standing") \
	.with_unit("°").with_step(1.0).as_debug()
static var neck_down_deg := num("neck_down_deg", "presentation.standing.neck_down_deg", 30.0,
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
	"Show the tail dock while the anatomy is shown. Off hides it; the anatomy does not move.",
	ANATOMY, "")
static var dock_color := choice("dock_color", "anatomy.dock_color", "coat",
	["coat", "genitals"], ["Coat", "Genitals"], "Dock colour",
	"Choose the standard dock's colour: her coat, or the same skin as her genitals.",
	ANATOMY, "")
static var reseat_tails := flag("reseat_tails", "anatomy.reseat_tails", true,
	"Re-seat tails and docks",
	"Seat every mare's hair tail at the reference dock and snap the dock base to her rump. Off restores the game's original tail mount and dock.",
	ANATOMY, "")
static var skin_strip := flag("skin_strip", "anatomy.skin_strip", false, "Show skin strip",
	"Show the midline skin strip that joins the teats toward the vulva.", ANATOMY, "")
static var teats := flag("teats", "anatomy.teats", false, "Show teats", "Show the optional teats.", ANATOMY, "")
static var anatomy_fluid := flag("anatomy_fluid", "features.anatomy_fluid", true, "Show fluids",
	"Show the optional climax and finish droplets.", ANATOMY, "")
static var body_coat_deform := flag("body_coat_deform", "features.body_coat_deform", true,
	"Body coat deform",
	"Patch the rig coat shader at runtime so the area under the vulva stays still and the coat spreads as the opening widens. Off leaves the game shader untouched.",
	ANATOMY, "").as_debug()
static var tail_offset_mm := num("tail_offset_mm", "anatomy.tail_offset_mm", 0.0, "Tail offset",
	"Move every re-seated tail up (+) or down (-) by this many millimetres. Stored verbatim; no clamp.",
	ANATOMY, "").with_unit("mm").with_step(1.0).as_debug()
static var dock_offset_mm := num("dock_offset_mm", "anatomy.dock_offset_mm", 0.0, "Dock offset",
	"Trim every re-seated dock up (+) or down (-) from its cuff position under the tail base. Stored verbatim; no clamp.",
	ANATOMY, "").with_unit("mm").with_step(1.0).as_debug()
static var skin_tone := num("skin_tone", "anatomy.skin_tone", 0.67, "Skin tone",
	"0% keeps her coat; 50% is the old Darker tone; 100% is the old Dark tone.", ANATOMY, "") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0).with_slider()
static var mare_bits := choice("mare_bits", "anatomy.mare_bits", "v2",
	["original", "v2"], ["Original PPP", "V2"],
	"Mare bits",
	"Choose the full mare genitals mesh. V2 uses the smoothed model when its asset is present; otherwise the original PPP mesh is used.", ANATOMY, "")
static var vulva_height := num("vulva_height", "anatomy.vulva_height", 0.75,
	"Vulva height",
	"Scale the vulva vertically around its opening. Below 1 shortens it; above 1 lengthens it.", ANATOMY, "") \
	.with_unit("×").with_step(0.05).with_range(0.5, 1.5)
static var vulva_inner_color := color("vulva_inner_color", "anatomy.vulva_inner_color",
	Color.from_string("#cf577d", Color.WHITE), "Vulva inner colour",
	"Colour of the inner folds. The shader derives its shadow.", ANATOMY, "")
static var clitoris_color := color("clitoris_color", "anatomy.clitoris_color",
	Color.from_string("#d87690", Color.WHITE), "Clitoris colour",
	"Colour of the clitoris. The shader derives its shadow.", ANATOMY, "")

# -- Placement  (debug)
## The anatomy place actions read this pill. It is hidden from the declaration rows because the
## pill above those actions owns the widget.
static var edit_target := choice("edit_target", "anatomy.placement_target", "mare",
	["default", "mare"], ["Default", "Pointed mare"], "Placement target",
	"Choose whether the Anatomy place actions change the global default or the pointed mare.",
	ANATOMY, "Placement").as_debug().as_hidden()
static var offset_x := num("offset_x", "anatomy.placement.default.offset_x", 0.0,
	"Default X", "Model-space placement used when a mare has no override.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var offset_y := num("offset_y", "anatomy.placement.default.offset_y", 0.525,
	"Default Y", "Model-space placement used when a mare has no override.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var offset_z := num("offset_z", "anatomy.placement.default.offset_z", 0.289,
	"Default Z", "Model-space placement used when a mare has no override.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var pitch_deg := num("pitch_deg", "anatomy.placement.default.pitch_deg", -6.0,
	"Default pitch", "Pitch of the anatomy mesh when a mare has no override.", ANATOMY, "Placement") \
	.with_unit("°").with_step(1.0).as_debug()
static var scale := num("scale", "anatomy.placement.default.scale", 0.742,
	"Default scale", "Scale of the anatomy mesh when a mare has no override.", ANATOMY, "Placement") \
	.with_unit("×").with_step(0.01).as_debug()
static var anon_offset_x := num("anon_offset_x", "anatomy.placement.anon.offset_x", 0.0,
	"Anon X", "Model-space placement of the player part.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var anon_offset_y := num("anon_offset_y", "anatomy.placement.anon.offset_y", 0.74,
	"Anon Y", "Model-space placement of the player part.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var anon_offset_z := num("anon_offset_z", "anatomy.placement.anon.offset_z", 0.085,
	"Anon Z", "Model-space placement of the player part.", ANATOMY, "Placement") \
	.with_unit("cm").with_step(0.5).with_scale(100.0).as_debug()
static var anon_pitch_deg := num("anon_pitch_deg", "anatomy.placement.anon.pitch_deg", 0.0,
	"Anon pitch", "Pitch of the player part.", ANATOMY, "Placement") \
	.with_unit("°").with_step(1.0).as_debug()
static var anon_scale := num("anon_scale", "anatomy.placement.anon.scale", 0.2,
	"Anon scale", "Scale of the player part.", ANATOMY, "Placement") \
	.with_unit("×").with_step(0.01).as_debug()

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
static var part_mid_scale := num("part_mid_scale", "anatomy.part_mid_scale", 0.75,
	"Mid radius", "Thickness of the cock around its middle.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_head_scale := num("part_head_scale", "anatomy.part_head_scale", 1.3,
	"Head radius", "Thickness of the glans at the end of the shaft.", ANATOMY, "Anon") \
	.with_unit("×").with_step(0.05).with_range(0.1, 3.0)
static var part_throb := num("part_throb", "anatomy.part_throb", 1.2, "Throb",
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
static var pelvis_gap_m := num("pelvis_gap_m", "anatomy.pelvis_gap_m", 0.025, "Pelvis gap",
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
static var anal_scale := num("anal_scale", "anatomy.anal_scale", 0.9,
	"Ponut scale",
	"Scale the visible ponut mound. The vulva and the opening stay put.", ANATOMY, "") \
	.with_unit("×").with_step(0.05).with_range(0.5, 1.5)
static var vulva_hug_mm := num("vulva_hug_mm", "anatomy.vulva_hug_mm", 2.0,
	"Vulva hug",
	"Pad the gap between the cock and the vulva lips. Positive opens the lips wider; negative grips tighter.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-5.0, 5.0) \
	.as_debug()
static var anal_hug_mm := num("anal_hug_mm", "anatomy.anal_hug_mm", 2.0,
	"Anal hug",
	"Pad the gap between the cock and the anal opening. Positive opens it wider; negative grips tighter.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-5.0, 5.0) \
	.as_debug()
static var anal_aim_mm := num("anal_aim_mm", "anatomy.anal_aim_mm", -20.0,
	"Anal aim height",
	"Raise or lower the V2 anal penetration point. Negative lowers it; the mesh itself does not move.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-40.0, 40.0) \
	.as_debug()
static var anal_body_depth_mm := num("anal_body_depth_mm", "anatomy.anal_body_depth_mm", 20.0,
	"Anal body depth",
	"Push the visible body ponut inward around the anal opening so the V2 hole and an oversized shaft stop clipping the body.", ANATOMY, "Holes") \
	.with_unit("mm").with_step(1.0).with_range(0.0, 60.0) \
	.as_debug()
static var lip_vertical := num("lip_vertical", "anatomy.lip_vertical", 0.7,
	"Lip vertical share",
	"How much of the opening happens top to bottom. Lower keeps the top and bottom lips tight on the shaft while the sides part.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 1.0) \
	.as_debug()
static var coat_spread := num("coat_spread", "anatomy.coat_spread", 2.0,
	"Coat spread",
	"Multiplier for the body coat stretching around the vulva as the opening widens.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 2.0) \
	.as_debug()
static var jiggle_still := num("jiggle_still", "anatomy.jiggle_still", 1.5,
	"Jiggle still zone",
	"Multiplier for the no-jiggle zone around the vulva. 0 turns the still zone off.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 2.0) \
	.as_debug()
static var anal_still := num("anal_still", "anatomy.anal_still", 0.0,
	"Anal still zone",
	"Multiplier for the no-jiggle zone around the visible ponut. 0 turns the still zone off.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.0, 2.0) \
	.as_debug()
static var still_oval := num("still_oval", "anatomy.still_oval", 1.5,
	"Still zone oval",
	"Vertical half-axis of both still zones as a share of the lateral one. Lower makes them flatter.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.05).with_range(0.2, 1.5) \
	.as_debug()
static var still_fade := num("still_fade", "anatomy.still_fade", 0.6,
	"Still zone fade",
	"Share of each still zone used to blend back to full jiggle at the rim. Higher is softer.", ANATOMY, "Holes") \
	.with_unit("×").with_step(0.01).with_range(0.02, 0.6) \
	.as_debug()
static var vulva_out_mm := num("vulva_out_mm", "anatomy.vulva_out_mm", 0.0,
	"Vulva out",
	"Push the whole anatomy mesh out of her coat along its own normal, so a pose that tucks it in does not clip her.",
	ANATOMY, "Holes").with_unit("mm").with_step(1.0).as_debug()
static var still_height_mm := num("still_height_mm", "anatomy.still_height_mm", 25.0,
	"Still zone height",
	"Vertical placement of the vulva still zone from its opening; positive is higher, negative lower.",
	ANATOMY, "Holes") \
	.with_unit("mm").with_step(0.5).with_range(-50.0, 50.0) \
	.as_debug()
static var draw_still_zones := flag("draw_still_zones", "anatomy.draw_still_zones", false,
	"Draw still zones",
	"Overlay the vulva and visible-ponut still-zone ellipsoids on the body coat.",
	ANATOMY, "Holes").as_debug()

# -- Heat  (debug)
static var wink_min_s := num("wink_min_s", "anatomy.wink_min_s", 17.0, "Wink min gap",
	"Shortest gap between idle heat winks, in seconds.", ANATOMY, "Heat") \
	.with_unit("s").with_step(0.5).with_range(1.0, 120.0).as_debug()
static var wink_max_s := num("wink_max_s", "anatomy.wink_max_s", 34.0, "Wink max gap",
	"Longest gap between idle heat winks, in seconds.", ANATOMY, "Heat") \
	.with_unit("s").with_step(0.5).with_range(1.0, 120.0).as_debug()
static var heat_rest_open := num("heat_rest_open", "anatomy.heat_rest_open", 0.3, "Rest open",
	"How open she rests between winks, as a share of the authored open shape. 0 is fully closed.",
	ANATOMY, "Heat") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0).as_debug()
static var wink_open_min := num("wink_open_min", "anatomy.wink_open_min", 0.9,
	"Wink open min",
	"Shallowest opening of an idle wink, as a share of the authored open shape.",
	ANATOMY, "Heat") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0).as_debug()
static var wink_open_max := num("wink_open_max", "anatomy.wink_open_max", 0.9,
	"Wink open max",
	"Deepest opening of an idle wink, as a share of the authored open shape.",
	ANATOMY, "Heat") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0).as_debug()
static var wink_timing := num("wink_timing", "anatomy.wink_timing", 1.2, "Wink timing",
	"Scale the open, hold and close times of each idle wink. Below 1 is quicker; above 1 is slower.",
	ANATOMY, "Heat") \
	.with_unit("×").with_step(0.05).with_range(0.25, 4.0).as_debug()
static var fluid_size := num("fluid_size", "anatomy.fluid_size", 0.01, "Fluid size",
	"Size of each idle heat droplet.", ANATOMY, "Heat") \
	.with_unit("mm").with_step(0.5).with_scale(1000.0).with_range(0.0005, 0.02).as_debug()
static var fluid_y_speed := num("fluid_y_speed", "anatomy.fluid_y_speed", -0.03,
	"Fluid Y speed",
	"Vertical speed of each idle heat droplet in metres per second. Negative falls, positive rises; not clamped.",
	ANATOMY, "Heat") \
	.with_unit("m/s").with_step(0.01).as_debug()
static var drip := num("drip", "anatomy.drip", 0.1, "Discharge",
	"Scale the idle heat discharge: droplet count and speed. 0 turns it off.",
	ANATOMY, "Heat") \
	.with_unit("×").with_step(0.05).with_range(0.0, 3.0).as_debug()
static var fluid_alpha := num("fluid_alpha", "anatomy.fluid_alpha", 0.5, "Fluid opacity",
	"Multiply the opacity of every fluid droplet.", ANATOMY, "Heat") \
	.with_unit("%").with_step(1.0).with_scale(100.0).with_range(0.0, 1.0) \
	.with_slider().as_debug()

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
	"cue": "During sex with Anon, the private moment is: {seed} Current moment: {state}. Private relationship note: {relationship}. Tone: {tone}. {memory} Say ONE short line in your own voice, at most 14 words. React to him and to the moment as the mare you are; you do not have to describe the sensation or narrate the moment; you can ask for something, tease him, say something tender, or say nothing about the mechanics. Let the relationship and the memory color it without naming labels, levels, numbers, or the note. Do not invent a memory beyond the one given. Begin with [whispering] or [happy]. No narration, no stage directions, no anatomy. Your preferences are private, not a list to say. Your preferences: {preferences}. Do not repeat: {recent}.",
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
const SCHEMA_VERSION := 7

## Retired settings, declared where their replacement lives. `map` receives the stored value and
## returns the dictionary to merge, or an empty dictionary to drop it. The loader applies every
## entry before the defaults merge, so a retired key cannot linger in the file.
static var _deprecated := [
	# Caress settings moved from pose blocks to one shared `caress.*` block.
	deprecated("presentation.standing.caress.palm_distance",
		func(value: Variant) -> Dictionary: return {"caress.hover_m": value}),
	deprecated("presentation.missionary.caress.over_coat_m",
		func(value: Variant) -> Dictionary: return {"caress.hover_m": value}),
	deprecated("presentation.missionary.caress.normal_blur_m",
		func(value: Variant) -> Dictionary: return {"caress.normal_blur_m": value}),
	deprecated("presentation.missionary.caress.normal_deg_s",
		func(value: Variant) -> Dictionary: return {"caress.normal_deg_s": value}),
	deprecated("presentation.missionary.caress.contact_smooth",
		func(value: Variant) -> Dictionary: return {"caress.contact_smooth": value}),
	deprecated("presentation.standing.caress.ignore",
		func(value: Variant) -> Dictionary: return {"caress.ignore": value}),
	deprecated("presentation.standing.caress.oval_across_m",
		func(value: Variant) -> Dictionary: return {"caress.oval_across_m": value}),
	deprecated("presentation.standing.caress.oval_up_m",
		func(value: Variant) -> Dictionary: return {"caress.oval_up_m": value}),
	deprecated("presentation.standing.caress.palm_scale.canon",
		func(value: Variant) -> Dictionary: return {"caress.palm_scale.canon": value}),
	deprecated("presentation.standing.caress.palm_scale.mounting",
		func(value: Variant) -> Dictionary: return {"caress.palm_scale.mounting": value}),
	deprecated("presentation.standing.caress.palm_scale.same height",
		func(value: Variant) -> Dictionary: return {"caress.palm_scale.same height": value}),
	deprecated("presentation.standing.caress.palm_scale.hoers",
		func(value: Variant) -> Dictionary: return {"caress.palm_scale.hoers": value}),
	# Retired caress switches and tuning with no replacement.
	deprecated("features.caress_hand_shape",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("features.caress_reach_body_m",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("features.caress_reach_stretch",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.caress.along_m",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.caress.oval_scale",
		func(_value: Variant) -> Dictionary: return {}),
	# The dock used to be hidden by a `true` switch; keep the player's choice across the rename.
	deprecated("anatomy.hide_dock",
		func(value: Variant) -> Dictionary: return {"anatomy.show_dock": not bool(value)}),
	# The separate log switch folded into the debug switch.
	deprecated("debug_logs", func(_value: Variant) -> Dictionary: return {}),
	# Missionary is one authored pose and one authored shot now; the correction stack, its neck
	# offsets and its frozen-shot tuning are retired.
	deprecated("presentation.missionary.authored_base",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.forward", func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.height", func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.pitch_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.pullback",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.side", func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.pose_hold",
		func(_value: Variant) -> Dictionary: return {}),
	# The authored pose holds the belly; the tilt is retired.
	deprecated("presentation.missionary.belly_down_deg",
		func(_value: Variant) -> Dictionary: return {}),
	# The authored shots are the whole framing now: the live shot offsets, the side-lean travel and
	# the upper-body base lean are retired.
	deprecated("presentation.missionary.side_lean",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.upper_lean_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.shot_forward",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.shot_height",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.shot_side",
		func(_value: Variant) -> Dictionary: return {}),
	# The vulva trim moved from Anatomy to the Missionary section; keep a tuned value.
	deprecated("anatomy.vulva_pose_shift_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_shift_mm": float(value)}),
	deprecated("anatomy.vulva_pose_pitch_deg",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_pitch_deg": float(value)}),
	# The six missionary geometry values became per-size. The old single value seeds Canon.
	deprecated("presentation.missionary.vulva_shift_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_shift_mm": float(value)}),
	deprecated("presentation.missionary.vulva_pitch_deg",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_pitch_deg": float(value)}),
	deprecated("presentation.missionary.vulva_depth_shift_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_depth_shift_mm": float(value)}),
	deprecated("presentation.missionary.vulva_hug_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.vulva_hug_mm": float(value)}),
	deprecated("presentation.missionary.head_clearance_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.head_clearance_mm": float(value)}),
	deprecated("presentation.missionary.gaze_offset_mm",
		func(value: Variant) -> Dictionary:
			return {"presentation.missionary.size.canon.gaze_offset_mm": float(value)}),
	# The act always shows and poses Anon's body, so the anatomy master no longer gates it.
	deprecated("features.anatomy_bed_body", func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.head_pitch_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.head_roll_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.neck1_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.neck2_deg",
		func(_value: Variant) -> Dictionary: return {}),
	deprecated("presentation.missionary.neck_roll_deg",
		func(_value: Variant) -> Dictionary: return {}),
	# Pack foley is always on; the switch is retired.
	deprecated("features.act_foley", func(_value: Variant) -> Dictionary: return {}),
	# Thrust sensitivity is now a physical scale: pixels per centimetre of hip travel. The old
	# value was pixels for one full stroke; 20 cm is the reference shaft, so its feel is kept.
	deprecated("thrust.pixels_per_full",
		func(value: Variant) -> Dictionary: return {"thrust.pixels_per_cm": float(value) / 20.0}),
	# The single wink multiplier became an explicit opening range. Map the old 45-88% authored
	# spread through the saved multiplier so the same beats are kept.
	deprecated("anatomy.wink_peak", func(value: Variant) -> Dictionary:
		var peak := maxf(float(value), 0.0)
		return {
			"anatomy.wink_open_min": clampf(0.45 * peak, 0.0, 1.0),
			"anatomy.wink_open_max": clampf(0.88 * peak, 0.0, 1.0),
		}),
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
## The old precise-caress reach default pulled the upper arm 12 cm off the chest. The safe
## default is 2 cm, so migrate only the shipped old default and leave a tuned value alone.
static func _normalize_caress_reach(data: Dictionary) -> Dictionary:
	var path := "features.caress_reach_shoulder_m"
	var value: Variant = _read_path(data, path, null)
	if value is float or value is int:
		if is_equal_approx(float(value), 0.12):
			_write_path(data, path, 0.02)
	return data


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
## Bumped whenever the placement view can have changed: a settings load/write or an unsaved
## default preview. The anatomy controller re-reads its resolved placement on the change.
static var placement_revision := 0
## Unsaved global-default preview from the Anatomy place actions. Session-only by design.
static var _placement_draft: Dictionary = {}


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
	var file_version := int(data.get("version", 0))
	data = _migrate(data, file_version)
	# A current file still imports a legacy placement file that appeared after the schema bump
	# (for example a copied profile); the files are archived after the write below.
	if file_version >= SCHEMA_VERSION:
		data = _normalize_anatomy_placement(data)
	data = _merge(_defaults(), data)
	data["version"] = SCHEMA_VERSION
	_cache = data
	placement_revision += 1
	if _write_file(data):
		_finish_legacy_placement_import()


static func _defaults() -> Dictionary:
	var out: Dictionary = {
		"default": _filled_default(),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
		"ui": {"sections": {}},
	}
	for s: Setting in _registry:
		_write_path(out, s.path, s.default)
	for id: Variant in PLACEMENT.MARE_DEFAULTS:
		var name := str(id)
		if name == "default" or name == "anon":
			continue
		_write_path(out, "anatomy.placement." + name, PLACEMENT.MARE_DEFAULTS[id])
	return out


## The old flat entry dictionary, for the compatibility layer only.
static func entry_view(s: Setting) -> Dictionary:
	var out: Dictionary = {
		"kind": "bool" if s is FlagSetting else "num" if s is NumSetting else
			"choice" if s is ChoiceSetting else "color" if s is ColorSetting else "list",
		"default": s.default, "label": s.label, "help": s.help, "group": s.group,
		"tab": s.tab, "debug": s.debug, "hidden": s.hidden,
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
		# A dictionary at a retired leaf is the new nested block that shares its name, not a value
		# to convert; leave it for the declarations that own it.
		if value == null or value is Dictionary:
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
	data = _normalize_caress_reach(data)
	data = _normalize_presentation(data)
	data = _normalize_tolerance(data)
	data = _normalize_character_preferences(data)
	data = _normalize_act_prompts(data)
	data = _normalize_anatomy(data)
	data = _normalize_anatomy_placement(data)
	data = _normalize_retired_keys(data)
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


## Legacy placement files imported during `_migrate`; renamed only after the settings write.
static var _legacy_mare_placement_pending := false
static var _legacy_anon_placement_pending := false
static var _legacy_mare_placement_path := ""
static var _legacy_anon_placement_path := ""


## Move the old anatomy_place.json and anon_place.json rows into the one anatomy.placement block.
## Rows that already equal the resolved default are skipped, so the old "every mare has a row"
## file collapses to real overrides.
static func _normalize_anatomy_placement(data: Dictionary) -> Dictionary:
	_legacy_mare_placement_pending = false
	_legacy_anon_placement_pending = false
	_legacy_mare_placement_path = ""
	_legacy_anon_placement_path = ""
	var folder := _path().get_base_dir()
	var mare_path := folder.path_join("anatomy_place.json")
	var anon_path := folder.path_join("anon_place.json")
	if FileAccess.file_exists(mare_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mare_path))
		if parsed is Dictionary:
			var legacy := PLACEMENT.migrate_legacy(parsed)
			var base := _legacy_placement_default(data, "anatomy.placement.default")
			for id: Variant in legacy.keys():
				var name := str(id)
				if name == "version":
					continue
				var row: Variant = legacy[id]
				if not row is Dictionary:
					continue
				var expected := PLACEMENT.merge(base, PLACEMENT.MARE_DEFAULTS.get(name, {}))
				var values := PLACEMENT.row_to_placement(row)
				var over := PLACEMENT.diff(PLACEMENT.sanitize(values, expected), expected)
				if over.is_empty():
					continue
				var existing: Variant = _read_path(data, "anatomy.placement." + name, {})
				var merged := PLACEMENT.merge(expected, over)
				merged = PLACEMENT.merge(merged, existing)
				var final_over := PLACEMENT.diff(merged, expected)
				if not final_over.is_empty():
					_write_path(data, "anatomy.placement." + name, final_over)
			_legacy_mare_placement_pending = true
			_legacy_mare_placement_path = mare_path
	if FileAccess.file_exists(anon_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(anon_path))
		if parsed is Dictionary:
			var base := _legacy_placement_default(data, "anatomy.placement.anon")
			var values := PLACEMENT.row_to_placement(parsed)
			var over := PLACEMENT.diff(PLACEMENT.sanitize(values, base), base)
			if not over.is_empty():
				var existing: Variant = _read_path(data, "anatomy.placement.anon", {})
				var merged := PLACEMENT.merge(base, over)
				merged = PLACEMENT.merge(merged, existing)
				var final_over := PLACEMENT.diff(merged, base)
				if not final_over.is_empty():
					_write_path(data, "anatomy.placement.anon", final_over)
			_legacy_anon_placement_pending = true
			_legacy_anon_placement_path = anon_path
	return data


static func _legacy_placement_default(data: Dictionary, path: String) -> Dictionary:
	var base := default_block(path + ".")
	var raw: Variant = _read_path(data, path, null)
	if raw is Dictionary:
		base = PLACEMENT.merge(base, raw)
	return base


static func _finish_legacy_placement_import() -> void:
	if _legacy_mare_placement_pending:
		_archive_legacy_placement(_legacy_mare_placement_path)
		_legacy_mare_placement_pending = false
	if _legacy_anon_placement_pending:
		_archive_legacy_placement(_legacy_anon_placement_path)
		_legacy_anon_placement_pending = false


static func _archive_legacy_placement(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var target := path + ".migrated"
	var index := 1
	while FileAccess.file_exists(target):
		index += 1
		target = "%s.migrated%d" % [path, index]
	var source_global := ProjectSettings.globalize_path(path)
	var target_global := ProjectSettings.globalize_path(target)
	if DirAccess.rename_absolute(source_global, target_global) != OK:
		push_warning("unfplap settings: could not archive %s" % path)


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
	var tone: Variant = block.get("skin_tone")
	if tone is String:
		block["skin_tone"] = float(LEGACY_SKIN_TONES.get(str(tone),
			_default_at("anatomy.skin_tone")))
	# The strip used to follow the teats switch. Keep an existing teats-off file fully off once;
	# from then on the two switches are independent.
	if block.has("teats") and not bool(block["teats"]) and not block.has("skin_strip"):
		block["skin_strip"] = false
	for key: String in ["anal_swell", "anal_depth", "anal_height_mm", "anal_ring",
			"anal_pitch_deg", "anal_side_mm",
			"anal_tilt_deg", "cover_depth_m", "max_back_m", "player_pitch_deg",
			"player_yaw_deg", "player_roll_deg", "hole_depth", "anal_hug", "hug",
			"vulva_hug", "pair_limit", "genital_yaw_deg", "max_depth_m"]:
		block.erase(key)
	data["anatomy"] = block
	return data


## Keys the mod no longer reads. Erased once on a schema upgrade so a settings file cannot carry
## them forever; `_load()` writes the merged cache back, so an ignored key would otherwise persist.
const RETIRED_PATHS := [
	"features.act_chat",
	"features.act_text_only_ponese",
	"features.anatomy_align",
	"features.bed_creaks",
	"features.body_sway",
	"features.camera_inertia",
	"features.camera_rock",
	"features.cuddle_override",
	"features.dock_tail_follow",
	"features.ear_twitch",
	"features.hold_sway",
	"features.lean_return",
	"features.pose1_ignore_bed_collision",
	"features.press_y_starts_sex",
	"features.readiness_hud",
	"features.rump_blush",
	"features.settings_tab",
	"features.thrust_camera_rock",
	"features.thrust_tail_dock_jiggle",
	"anatomy.anal_height_mm",
	"anatomy.anal_ring",
	"anatomy.strip_width",
	"presentation.lean_back_m",
	"presentation.standing.idle_sway_side",
	"presentation.standing.kiss.forelegs",
	"presentation.standing.max_shaft_angle_deg",
	"presentation.standing.rump_follow",
	"presentation.standing.smack.sound",
	"thrust.camera_bob",
	"thrust.camera_motion",
	"auto_thrust.pace_step",
]


## Erase every retired path and drop the sub-blocks it leaves empty.
static func _normalize_retired_keys(data: Dictionary) -> Dictionary:
	for path: String in RETIRED_PATHS:
		_erase_path(data, path)
	for parent: String in ["presentation.standing.kiss", "presentation.standing.smack"]:
		var node: Variant = _read_path(data, parent, null)
		if node is Dictionary and (node as Dictionary).is_empty():
			_erase_path(data, parent)
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
	placement_revision += 1
	_write_file(_cache)


## Write through a temporary file first, so a placement save cannot truncate the whole profile.
## Returns false only when neither the rename nor the direct fallback could write.
static func _write_file(data: Dictionary) -> bool:
	var path := _path()
	var folder := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var text := JSON.stringify(data, "\t") + "\n"
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
		var source_global := ProjectSettings.globalize_path(temp)
		var target_global := ProjectSettings.globalize_path(path)
		if DirAccess.rename_absolute(source_global, target_global) == OK:
			return true
		DirAccess.remove_absolute(source_global)
	# Windows can refuse to rename over an existing file. The direct write is the fallback, not
	# the normal path.
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		return false
	direct.store_string(text)
	direct.close()
	return true
