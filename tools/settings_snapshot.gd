extends SceneTree
## Dump the shipped settings schema and defaults as one JSON line for `/sync-settings`.
## Run with a throwaway XDG_DATA_HOME so loading the settings module cannot touch the player's
## profile:
##
##   XDG_DATA_HOME=<scratch> godot --headless --xr-mode off --path <project> \
##       --script res://mods/unfplap/tools/settings_snapshot.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")


func _initialize() -> void:
	var settings: Array = []
	for setting: SETTINGS.Setting in SETTINGS.all_settings():
		var row: Dictionary = setting.to_row()
		row["name"] = setting.name
		row["path"] = setting.path
		settings.append(row)
	var defaults: Dictionary = SETTINGS._defaults()
	# The profile file stores only per-mare differences now, but the sync analyzer still needs the
	# full shipped templates to compare each character leaf against its real default.
	defaults["characters"] = SETTINGS.CHARACTER_TEMPLATES.duplicate(true)
	# The profile file holds act-prompt overrides next to the built-ins. The comparison needs the
	# built-in text, not the empty override table.
	var default_block: Dictionary = defaults.get("default", {})
	default_block["act_prompts"] = SETTINGS.DEFAULT_ACT_PROMPTS.duplicate(true)
	defaults["default"] = default_block
	var consents := {}
	for id: String in SETTINGS.CHARACTER_ORDER:
		consents[id] = CONSENT.defaults(id)
	var out := {
		"schema": SETTINGS.SCHEMA_VERSION,
		"settings": settings,
		"defaults": defaults,
		"order": SETTINGS.CHARACTER_ORDER,
		"consent": consents,
	}
	print("SETTINGS_SNAPSHOT " + JSON.stringify(out))
	quit(0)
