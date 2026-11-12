extends RefCounted
## In-memory provider registry for mare templates. The cross-mod API contract is `docs/api.md`.
##
## Another mod's entry script registers one mare id and a character-template-shaped descriptor.
## This module validates it, layers it over the built-in template, and lets `settings.gd` resolve
## the same data it already resolves for a base-game mare. Provider data is never written to
## `settings.json`: the player's saved block always wins, and removing the provider leaves the
## player's choices intact.
##
## The registry is process-wide and main-thread only. It is empty until a provider registers, so
## tests and a run without other mods behave exactly as before.

const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const PARTICIPATION := preload("res://mods/unfplap/participation.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy_placement.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

## The descriptor shape this build understands. A provider asking for a newer schema is rejected
## rather than silently half-applied.
const SCHEMA := 1
## `default` and `anon` are reserved by the placement block, so they can never be mare ids.
const RESERVED_IDS := ["default", "anon"]
const PROMPT_KEYS := ["cue", "utterance"]
const EVENT_PROMPT_KEYS := ["climax", "end_early"]
const TEMPLATE_KEYS := [
	"preferences", "consent", "adult", "profile", "placement", "poses",
	"act_prompts", "event_prompts", "cue_gap", "aftercare_min", "smack_zone_radius",
]
const TOP_KEYS := [
	"schema", "id", "source", "name",
	"preferences", "consent", "adult", "profile", "placement", "poses",
	"act_prompts", "event_prompts", "cue_gap", "aftercare_min", "smack_zone_radius",
]

## mare id -> Array of layers, in registration order. A layer is
## {owner: int, source: String, name: String, template: Dictionary, order: int}.
static var _layers: Dictionary = {}
static var _next_order := 0


## Validate and add one provider layer. Re-registering the same owner + id replaces that layer
## in place, so a provider can refresh its template without changing precedence.
static func register(owner_id: int, descriptor: Dictionary) -> Dictionary:
	var warnings: Array = []
	var errors: Array = []
	var id := ""
	var source := ""
	var raw_id: Variant = descriptor.get("id", "")
	if raw_id is String:
		id = str(raw_id).strip_edges()
		_check_id(id, errors)
	else:
		errors.append("id: expected a string")
	var raw_source: Variant = descriptor.get("source", "")
	if raw_source is String:
		source = str(raw_source).strip_edges()
		_check_source(source, errors)
	else:
		errors.append("source: expected a string")
	if owner_id == 0:
		errors.append("owner: must be a valid Node inside the scene tree")
	var raw_schema: Variant = descriptor.get("schema", SCHEMA)
	if not (raw_schema is int or raw_schema is float):
		errors.append("schema: expected a number")
	elif int(raw_schema) < 1 or int(raw_schema) > SCHEMA:
		errors.append("schema: this build understands %d, got %d" % [SCHEMA, int(raw_schema)])
	var name := ""
	if descriptor.has("name"):
		var raw_name: Variant = descriptor["name"]
		if raw_name is String:
			name = str(raw_name).strip_edges()
		else:
			errors.append("name: expected a string")
	for key: Variant in descriptor.keys():
		if not str(key) in TOP_KEYS:
			warnings.append("%s: unknown key" % str(key))

	var template: Dictionary = {}
	for key: String in TEMPLATE_KEYS:
		if not descriptor.has(key):
			continue
		var raw: Variant = descriptor[key]
		match key:
			"preferences":
				var clean := _validate_preferences(raw, warnings, errors)
				if not clean.is_empty() or raw is Dictionary:
					template[key] = clean
			"consent":
				var clean := _validate_consent(raw, warnings, errors)
				if not clean.is_empty() or raw is Dictionary:
					template[key] = clean
			"adult":
				var clean: Variant = _validate_adult(raw, errors)
				if clean != null:
					template[key] = clean
			"profile":
				var clean := _validate_profile(raw, warnings, errors)
				if not clean.is_empty() or raw is Dictionary:
					template[key] = clean
			"placement":
				var clean := _validate_placement(raw, warnings, errors)
				if not clean.is_empty() or raw is Dictionary:
					template[key] = clean
			"poses":
				var clean := _validate_poses(raw, warnings, errors)
				if not clean.is_empty() or raw is Dictionary:
					template[key] = clean
			"act_prompts":
				template[key] = _validate_prompts(raw, PROMPT_KEYS,
					"act_prompts", warnings, errors)
			"event_prompts":
				template[key] = _validate_prompts(raw, EVENT_PROMPT_KEYS,
					"event_prompts", warnings, errors)
			"cue_gap", "aftercare_min", "smack_zone_radius":
				if not _valid_number(raw):
					errors.append("%s: expected a finite number" % key)
				else:
					template[key] = float(raw) if key != "aftercare_min" else int(raw)

	var result := {
		"ok": false, "id": id, "source": source, "replaced": false,
		"warnings": warnings, "errors": errors,
	}
	if not errors.is_empty():
		return result
	var layer := {
		"owner": owner_id, "source": source, "name": name, "template": template,
		"order": 0,
	}
	var list: Array = _layers.get(id, [])
	var replaced := false
	for index: int in list.size():
		var existing: Variant = list[index]
		if existing is Dictionary and int((existing as Dictionary).get("owner", 0)) == owner_id:
			layer["order"] = int((existing as Dictionary).get("order", 0))
			list[index] = layer
			replaced = true
			break
	if not replaced:
		_next_order += 1
		layer["order"] = _next_order
		list.append(layer)
	_layers[id] = list
	result["ok"] = true
	result["replaced"] = replaced
	return result


## Remove only this owner's layer. Returns true when a layer was present.
static func unregister(owner_id: int, id: String) -> bool:
	var key := id.strip_edges()
	var list: Array = _layers.get(key, [])
	for index: int in list.size():
		var existing: Variant = list[index]
		if existing is Dictionary and int((existing as Dictionary).get("owner", 0)) == owner_id:
			list.remove_at(index)
			if list.is_empty():
				_layers.erase(key)
			else:
				_layers[key] = list
			return true
	return false


## Remove every layer owned by one Node. Called when a provider leaves the tree.
static func unregister_owner(owner_id: int) -> int:
	var removed := 0
	for key: Variant in _layers.keys():
		var id := str(key)
		var list: Array = _layers[id]
		for index: int in range(list.size() - 1, -1, -1):
			var existing: Variant = list[index]
			if existing is Dictionary and int((existing as Dictionary).get("owner", 0)) == owner_id:
				list.remove_at(index)
				removed += 1
		if list.is_empty():
			_layers.erase(id)
		else:
			_layers[id] = list
	return removed


## The merged provider template for one id. Empty when no provider registered her.
static func template_for(id: String) -> Dictionary:
	var out: Dictionary = {}
	var list: Array = _layers.get(id, [])
	for layer: Variant in list:
		if not layer is Dictionary:
			continue
		var raw: Variant = (layer as Dictionary).get("template", {})
		if raw is Dictionary:
			out = _merge(out, raw)
	return out


## The merged provider placement block for one id, or an empty dictionary.
static func placement(id: String) -> Dictionary:
	var out: Dictionary = {}
	var list: Array = _layers.get(id, [])
	for layer: Variant in list:
		if not layer is Dictionary:
			continue
		var template: Variant = (layer as Dictionary).get("template", {})
		if not template is Dictionary:
			continue
		var raw: Variant = (template as Dictionary).get("placement", {})
		if raw is Dictionary:
			out = _merge(out, raw)
	return out


## Provider display name for an id, preferring the most recently registered non-empty name.
static func name_for(id: String) -> String:
	var out := ""
	var list: Array = _layers.get(id, [])
	for layer: Variant in list:
		if not layer is Dictionary:
			continue
		var value := str((layer as Dictionary).get("name", "")).strip_edges()
		if not value.is_empty():
			out = value
	return out


static func has(id: String) -> bool:
	return _layers.has(id) and not (_layers[id] as Array).is_empty()


static func ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _layers.keys():
		out.append(str(key))
	out.sort()
	return out


## Provider mod ids for one mare, in resolution order. One source appears once.
static func sources(id: String) -> Array[String]:
	var out: Array[String] = []
	var list: Array = _layers.get(id, [])
	for layer: Variant in list:
		if not layer is Dictionary:
			continue
		var source := str((layer as Dictionary).get("source", "")).strip_edges()
		if not source.is_empty() and not out.has(source):
			out.append(source)
	return out


## Drop every provider layer. Called when the API node shuts down.
static func reset() -> void:
	_layers.clear()
	_next_order = 0


static func _check_id(id: String, errors: Array) -> void:
	if id.is_empty():
		errors.append("id: required")
		return
	if id.length() > 64:
		errors.append("id: must be at most 64 characters")
	if id in RESERVED_IDS:
		errors.append("id: %s is reserved" % id)
	if id.contains(".") or id.contains(":"):
		errors.append("id: must not contain '.' or ':'")


static func _check_source(source: String, errors: Array) -> void:
	if source.is_empty():
		errors.append("source: required")
		return
	if source.length() > 64:
		errors.append("source: must be at most 64 characters")
	if source.contains(".") or source.contains(":"):
		errors.append("source: must not contain '.' or ':'")


static func _validate_preferences(raw: Variant, warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("preferences: expected an object")
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		var value: Variant = (raw as Dictionary)[key]
		match name:
			"intensity":
				_check_enum(name, value, PREFERENCES.INTENSITIES, out, errors)
			"pattern":
				_check_enum(name, value, PREFERENCES.PATTERNS, out, errors)
			"warmth":
				_check_enum(name, value, PREFERENCES.WARMTHS, out, errors)
			"tolerance":
				_check_enum(name, value, PREFERENCES.TOLERANCES, out, errors)
			"touch":
				_check_list(name, value, PREFERENCES.TOUCHES, out, warnings, errors)
			"talk":
				_check_list(name, value, PREFERENCES.TALKS, out, warnings, errors)
			"dislikes":
				_check_list(name, value, PREFERENCES.TOUCHES + PREFERENCES.TALKS,
					out, warnings, errors)
			"notes":
				if not value is String:
					errors.append("preferences.notes: expected a string")
				else:
					out["notes"] = str(value).strip_edges()
			_:
				warnings.append("preferences.%s: unknown key" % name)
	return out


static func _validate_consent(raw: Variant, warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("consent: expected an object")
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		if not name in ["public", "anal", "oral"]:
			warnings.append("consent.%s: unknown key" % name)
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not value is bool:
			errors.append("consent.%s: expected true or false" % name)
		else:
			out[name] = bool(value)
	return out


## A provider's `adult` assertion. It is a tri-state: `true`/`false` is a provider assertion, and
## absent means the pony's identity decides. It is never a player field.
static func _validate_adult(raw: Variant, errors: Array) -> Variant:
	if raw is bool:
		return raw
	errors.append("adult: expected true or false")
	return null


static func _validate_profile(raw: Variant, warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("profile: expected an object")
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		if name != "participation":
			warnings.append("profile.%s: unknown key" % name)
			continue
		var raw_participation: Variant = (raw as Dictionary)[key]
		if not raw_participation is Dictionary:
			errors.append("profile.participation: expected an object")
			continue
		var participation: Dictionary = {}
		for part_key: Variant in (raw_participation as Dictionary).keys():
			var part_name := str(part_key)
			if not part_name in PARTICIPATION.KEYS:
				warnings.append("profile.participation.%s: unknown key" % part_name)
				continue
			var value: Variant = (raw_participation as Dictionary)[part_key]
			if not value is bool:
				errors.append("profile.participation.%s: expected true or false" % part_name)
			else:
				participation[part_name] = bool(value)
		out["participation"] = participation
	return out


static func _validate_placement(raw: Variant, warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("placement: expected an object")
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		if not name in PLACEMENT.KEYS:
			warnings.append("placement.%s: unknown key" % name)
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not _valid_number(value):
			errors.append("placement.%s: expected a finite number" % name)
			continue
		var number := float(value)
		if name in ["scale", "dock_scale"] and number <= 0.0:
			errors.append("placement.%s: must be greater than zero" % name)
			continue
		out[name] = number
	return out


static func _validate_poses(raw: Variant, warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("poses: expected an object")
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		if not name in CATALOG.all():
			warnings.append("poses.%s: unknown pose" % name)
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not value is Dictionary:
			errors.append("poses.%s: expected an object" % name)
		else:
			out[name] = (value as Dictionary).duplicate(true)
	return out


static func _validate_prompts(raw: Variant, allowed: Array, label: String,
		warnings: Array, errors: Array) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		errors.append("%s: expected an object" % label)
		return out
	for key: Variant in (raw as Dictionary).keys():
		var name := str(key)
		if not name in allowed:
			warnings.append("%s.%s: unknown key" % [label, name])
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not value is String:
			errors.append("%s.%s: expected a string" % [label, name])
		else:
			out[name] = str(value)
	return out


static func _check_enum(name: String, value: Variant, allowed: Array, out: Dictionary,
		errors: Array) -> void:
	if not value is String:
		errors.append("preferences.%s: expected a string" % name)
		return
	var text := str(value).to_lower()
	if not text in allowed:
		errors.append("preferences.%s: expected one of %s" % [name, ", ".join(allowed)])
		return
	out[name] = text


static func _check_list(name: String, value: Variant, allowed: Array, out: Dictionary,
		warnings: Array, errors: Array) -> void:
	if not value is Array:
		errors.append("preferences.%s: expected an array" % name)
		return
	var clean: Array = []
	for item: Variant in value:
		if not item is String:
			errors.append("preferences.%s: entries must be strings" % name)
			continue
		var text := str(item).to_lower()
		if not text in allowed:
			warnings.append("preferences.%s: unknown value %s" % [name, text])
			continue
		if not clean.has(text):
			clean.append(text)
	out[name] = clean


static func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over.keys():
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = _merge(out[key], value)
		else:
			out[key] = value
	return out
