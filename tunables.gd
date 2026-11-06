extends RefCounted
## The one API for reading and writing every global mod setting. See TUNING.md.
##
##   TUNABLES.get_bool("features.act_foley")
##   TUNABLES.get_float("presentation.standing.smack.raise_m")
##   TUNABLES.set_value("camera_thrust.surge", 0.5)
##   TUNABLES.block("features.")                    # nested dictionary for a snapshot
##
## The path is the settings.json path and must exist in `tunables_schema.gd`. Reads are flat
## dictionary lookups: the whole settings file is resolved once into `_values` and rebuilt only
## after a save or a reload. Unknown paths return the kind's zero value and log nothing.
##
## Debug numbers are never clamped. Only `user_num` schema entries have contract bounds.

const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

static var _values: Dictionary = {}
static var _generation := -1


## Debug actions. `method` is called on the entry node.
## Add an action here; it becomes a button in the Debug tab automatically. A hotkey is the
## exception, not the default: only add one when the action must fire while the world is unpaused
## and you are looking at the scene (the skeleton overlay is the example). `panel: false` keeps a
## hotkey-only action out of the button list.
const ACTIONS := {
	"bed_offer": {
		"label": "Trigger bed offer",
		"help": "Force a missionary offer for the aimed or nearest mare.",
		"method": "action_bed_offer",
	},
	"standing_offer": {
		"label": "Trigger standing offer",
		"help": "Force a standing offer for the aimed or nearest mare.",
		"method": "action_standing_offer",
	},
	"grant_lover_bond": {
		"label": "Grant lover bond",
		"help": "Give the aimed or nearest eligible mare the mod lover bond.",
		"method": "action_grant_lover_bond",
	},
	"clear_lover_bond": {
		"label": "Clear lover bond",
		"help": "Clear the aimed or nearest mare's mod lover bond.",
		"method": "action_clear_lover_bond",
	},
	"reset_act_history": {
		"label": "Reset act history",
		"help": "Clear the aimed or nearest mare's long-term act history and hurt.",
		"method": "action_reset_act_history",
	},
	"force_tolerance_warning": {
		"label": "Force tolerance warning",
		"help": "Trigger the active act's next tolerance warning.",
		"method": "action_force_tolerance_warning",
	},
	"force_tolerance_stop": {
		"label": "Force tolerance stop",
		"help": "Make the active mare stop the act through the tolerance path.",
		"method": "action_force_tolerance_stop",
	},
	"skeleton_overlay": {
		"label": "Skeleton overlay",
		"help": "Toggle the F10 skeleton overlay.",
		"method": "toggle_skeleton_debug",
		"hotkey": KEY_F10,
		"panel": false,
	},
}


## The action bound to a physical key code, or "" when none is.
static func hotkey_action(keycode: int) -> String:
	for name: String in ACTIONS:
		if int(ACTIONS[name].get("hotkey", 0)) == keycode:
			return name
	return ""


## Run one action on `target`. Returns its message, or "" when it cannot run.
static func run_action(name: String, target: Node) -> String:
	if not ACTIONS.has(name):
		return ""
	var method := str(ACTIONS[name].get("method", ""))
	if not is_instance_valid(target) or not target.has_method(method):
		return ""
	var result: Variant = target.call(method)
	return str(result) if result is String else ""


static func get_bool(path: String) -> bool:
	return bool(get_value(path))


static func get_float(path: String) -> float:
	var value: Variant = get_value(path)
	return float(value) if value is float or value is int else 0.0


static func get_int(path: String) -> int:
	return int(get_float(path))


static func get_string(path: String) -> String:
	var value: Variant = get_value(path)
	return str(value) if value is String else ""


static func get_list(path: String) -> Array:
	var value: Variant = get_value(path)
	return value if value is Array else []


## The typed value for a path. Unknown paths return false, because an unknown switch must never
## read as on.
static func get_value(path: String) -> Variant:
	_ensure()
	if not _values.has(path):
		return false
	return _values[path]


static func set_value(path: String, value: Variant) -> void:
	if not SCHEMA.has(path):
		return
	# Resolve the whole table first: a write before any read must not leave the cache holding
	# only this one path, or every other tunable would read as its zero value.
	_ensure()
	var coerced: Variant = _coerce(SCHEMA.entry(path), value)
	SETTINGS.write_setting(path, coerced)
	_values[path] = coerced
	_generation = SETTINGS.generation


## Put one path back to its schema default.
static func reset_value(path: String) -> void:
	if not SCHEMA.has(path):
		return
	set_value(path, SCHEMA.default_value(path))


## Nested dictionary of the values under a dotted prefix, e.g. `block("features.")` or
## `block("presentation.standing.")` for a per-act snapshot.
static func block(prefix: String) -> Dictionary:
	_ensure()
	var out: Dictionary = {}
	for path: String in SCHEMA.all():
		if path.begins_with(prefix):
			SCHEMA.write_path(out, path.substr(prefix.length()), _values.get(path))
	return out


## Re-read settings.json and drop the resolved values. Not named `reload`: `Script` already has
## `reload()`, and a preloaded script constant resolves the built-in instead of a static function.
static func reload_settings() -> void:
	SETTINGS.reload_file()
	_generation = -1
	_values.clear()


static func _ensure() -> void:
	if _generation == SETTINGS.generation and not _values.is_empty():
		return
	_generation = SETTINGS.generation
	var data := SETTINGS.data()
	_values.clear()
	for path: String in SCHEMA.all():
		var item := SCHEMA.entry(path)
		_values[path] = _coerce(item, _read_path(data, path, item.get("default")))


static func _read_path(data: Dictionary, path: String, fallback: Variant) -> Variant:
	var node: Variant = data
	for key: String in path.split(".", false):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return fallback
		node = (node as Dictionary)[key]
	return node


static func _coerce(item: Dictionary, value: Variant) -> Variant:
	var fallback: Variant = item.get("default")
	if value == null:
		return fallback
	match str(item.get("kind", "")):
		"bool":
			return bool(value)
		"num":
			var number := float(value)
			if not is_finite(number):
				return fallback
			if bool(item.get("clamp", false)):
				return clampf(number, float(item.get("low", -1000000.0)),
					float(item.get("high", 1000000.0)))
			return number
		"choice":
			var text := str(value)
			var options: Array = item.get("options", [])
			return text if options.has(text) else fallback
		"list":
			var out: Array = []
			var allowed: Array = item.get("options", [])
			if value is Array:
				for raw: Variant in value:
					var name := str(raw).to_lower()
					if allowed.has(name) and not out.has(name):
						out.append(name)
			return out
	return value
