extends RefCounted
## Compatibility layer over `settings.gd`: path-keyed reads for call sites that have not been
## converted to the named accessors yet, plus the debug action table. Do not add settings here.

const SETTINGS := preload("res://mods/unfplap/settings.gd")


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
	"force_heat": {
		"label": "Force heat",
		"help": "Put the aimed or nearest mare in heat for this session.",
		"method": "action_force_heat",
	},
	"force_diestrus": {
		"label": "Force diestrus",
		"help": "Turn the aimed or nearest mare off for this session.",
		"method": "action_force_diestrus",
	},
	"clear_cycle_override": {
		"label": "Clear forced cycle",
		"help": "Resume the aimed or nearest mare's automatic estrus cycle.",
		"method": "action_clear_cycle_override",
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
	"show_act_history": {
		"label": "Show act history",
		"help": "Print the aimed or nearest mare's act history to the debug log.",
		"method": "action_show_act_history",
	},
	"reset_act_prompts": {
		"label": "Reset act prompts",
		"help": "Remove saved act-line prompt overrides and return to the built-in prompts.",
		"method": "action_reset_act_prompts",
	},
	"force_tolerance_warning": {
		"label": "Force neglect warning",
		"help": "Trigger the active act's next neglect warning.",
		"method": "action_force_tolerance_warning",
	},
	"force_tolerance_stop": {
		"label": "Force neglect stop",
		"help": "Make the active mare stop the act through the neglect path.",
		"method": "action_force_tolerance_stop",
	},
	"skeleton_overlay": {
		"label": "Skeleton overlay",
		"help": "Toggle the F10 skeleton overlay.",
		"method": "toggle_skeleton_debug",
		"hotkey": KEY_F10,
		"panel": false,
	},
	# integration: local anatomy placement calibration.
	"anatomy_up": {"label": "Anatomy up", "help": "Move the aimed mare's anatomy up 5 mm.",
		"method": "action_anatomy_up"},
	"anatomy_down": {"label": "Anatomy down", "help": "Move the aimed mare's anatomy down 5 mm.",
		"method": "action_anatomy_down"},
	"anatomy_forward": {"label": "Anatomy forward", "help": "Move the anatomy forward 5 mm.",
		"method": "action_anatomy_forward"},
	"anatomy_back": {"label": "Anatomy back", "help": "Move the anatomy back 5 mm.",
		"method": "action_anatomy_back"},
	"anatomy_pitch_up": {"label": "Anatomy pitch up", "help": "Pitch the anatomy up 1 degree.",
		"method": "action_anatomy_pitch_up"},
	"anatomy_pitch_down": {"label": "Anatomy pitch down", "help": "Pitch down 1 degree.",
		"method": "action_anatomy_pitch_down"},
	"anatomy_scale_up": {"label": "Anatomy bigger", "help": "Scale the anatomy up by 0.02.",
		"method": "action_anatomy_scale_up"},
	"anatomy_scale_down": {"label": "Anatomy smaller", "help": "Scale the anatomy down by 0.02.",
		"method": "action_anatomy_scale_down"},
	"anatomy_save": {"label": "Save anatomy place", "help": "Save this mare's placement.",
		"method": "action_anatomy_save"},
	"anatomy_reset": {"label": "Reset anatomy place", "help": "Restore the default placement.",
		"method": "action_anatomy_reset"},
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
	return bool(SETTINGS.get_value_at(path))


static func get_float(path: String) -> float:
	var value: Variant = SETTINGS.get_value_at(path)
	return float(value) if value is float or value is int else 0.0


static func get_int(path: String) -> int:
	return int(get_float(path))


static func get_string(path: String) -> String:
	var value: Variant = SETTINGS.get_value_at(path)
	return str(value) if value is String else ""


static func get_list(path: String) -> Array:
	var value: Variant = SETTINGS.get_value_at(path)
	return value if value is Array else []


## The declared default for a number path. Use it where a settings block can be empty, so the
## fallback cannot drift from the declaration.
static func default_number(path: String) -> float:
	var value: Variant = SETTINGS.default_at(path)
	return float(value) if value is float or value is int else 0.0


## The coerced value for a path. Compatibility only: gameplay code uses the named accessor.
static func get_value(path: String) -> Variant:
	return SETTINGS.get_value_at(path)


static func set_value(path: String, value: Variant) -> void:
	SETTINGS.set_value_at(path, value)


## Put one path back to its declared default.
static func reset_value(path: String) -> void:
	SETTINGS.set_value_at(path, SETTINGS.default_at(path))


## Nested dictionary of the values under a dotted prefix, e.g. `block("features.")` or
## `block("presentation.standing.")` for a per-act snapshot.
static func block(prefix: String) -> Dictionary:
	return SETTINGS.block(prefix)


## Re-read settings.json and drop the resolved values.
static func reload_settings() -> void:
	SETTINGS.reload_file()


## Coerce one value against a schema entry. Compatibility only: kept for the tests and for callers
## that still hold an entry dictionary.
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
