extends RefCounted
## Persisted mod settings outside any world save: global DEBUG LOGS plus per-pony templates.
## The default template holds every pony-related setting; `characters` only needs overrides.

const ID := "unfunfunf"
const FILE := "settings.json"

const DEFAULT_TEMPLATE := {
	"chattiness": 0.6,
	"event_prompts": {
		"climax": "",
		"end_early": "",
		"inside": "",
	},
}

## Fluttershy is the only character with a custom prompt for now. Everything else is inherited
## from DEFAULT_TEMPLATE, so her settings stay in sync with the defaults.
const CHARACTER_TEMPLATES := {
	"fluttershy": {
		"event_prompts": {
			"climax": "You have just climaxed during intimacy with Anon. Say something like \"Oh goodness, oh goodness...\" in your own voice. Be creative, but keep that flustered baseline. Do not describe anatomy.",
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


static func chattiness(id: String) -> float:
	return clampf(float(template_for(id).get("chattiness", 0.6)), 0.0, 1.0)


static func event_prompt(id: String, event: String) -> String:
	var prompts: Variant = template_for(id).get("event_prompts", {})
	if prompts is Dictionary:
		return str((prompts as Dictionary).get(event, ""))
	return ""


## The merged default + per-character template actually used at runtime.
static func template_for(id: String) -> Dictionary:
	var data := _read()
	var base: Dictionary = data.get("default", DEFAULT_TEMPLATE.duplicate(true))
	var characters: Variant = data.get("characters", {})
	if characters is Dictionary and (characters as Dictionary).has(id):
		var over: Variant = (characters as Dictionary)[id]
		if over is Dictionary:
			return _merge(base, over)
	return base.duplicate(true)


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
		"default": DEFAULT_TEMPLATE.duplicate(true),
		"characters": CHARACTER_TEMPLATES.duplicate(true),
	}


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
