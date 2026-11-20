extends RefCounted
## The three shipped documents, parsed once per process and returned detached.
## Preloading nothing keeps the pure modules out of a cycle.

const SETTINGS_FILE := "res://mods/unfplap/settings/settings.json"
const CHARACTERS_FILE := "res://mods/unfplap/settings/characters.json"
const PROMPTS_FILE := "res://mods/unfplap/settings/prompts.json"

static var _document_cache: Dictionary = {}
static var _document_loaded := false
static var _document_error := ""
static var _characters_cache: Dictionary = {}
static var _characters_loaded := false
static var _characters_error := ""
static var _prompts_cache: Dictionary = {}
static var _prompts_loaded := false
static var _prompts_error := ""


## The parsed settings document, or `{}` when the file is missing or malformed. `error()` says why.
static func document() -> Dictionary:
	if not _document_loaded:
		_document_loaded = true
		var loaded := _parse(SETTINGS_FILE)
		_document_cache = loaded["data"]
		_document_error = loaded["error"]
	return _document_cache


## The parsed characters document, or `{}` when the file is missing or malformed.
static func characters() -> Dictionary:
	if not _characters_loaded:
		_characters_loaded = true
		var loaded := _parse(CHARACTERS_FILE)
		_characters_cache = loaded["data"]
		_characters_error = loaded["error"]
	return _characters_cache


## The parsed prompts document, or `{}` when the file is missing or malformed.
static func prompts() -> Dictionary:
	if not _prompts_loaded:
		_prompts_loaded = true
		var loaded := _parse(PROMPTS_FILE)
		_prompts_cache = loaded["data"]
		_prompts_error = loaded["error"]
	return _prompts_cache


## True when the shipped settings document parsed as a JSON object.
static func valid() -> bool:
	document()
	return _document_error.is_empty()


## True when the shipped characters document parsed as a JSON object.
static func characters_valid() -> bool:
	characters()
	return _characters_error.is_empty()


## True when the shipped prompts document parsed as a JSON object.
static func prompts_valid() -> bool:
	prompts()
	return _prompts_error.is_empty()


## The first problem with the shipped settings document, or "" when it is valid.
static func error() -> String:
	document()
	return _document_error


## The first problem with the shipped characters document, or "" when it is valid.
static func characters_error() -> String:
	characters()
	return _characters_error


## The first problem with the shipped prompts document, or "" when it is valid.
static func prompts_error() -> String:
	prompts()
	return _prompts_error


## A detached nested block of the settings document under a dotted prefix, or `{}` when the prefix
## is absent or not a dictionary.
static func settings_block(prefix: String) -> Dictionary:
	return _block(document(), prefix)


## A detached nested block of the characters document under a dotted prefix.
static func characters_block(prefix: String) -> Dictionary:
	return _block(characters(), prefix)


## A detached nested block of the prompts document under a dotted prefix.
static func prompts_block(prefix: String) -> Dictionary:
	return _block(prompts(), prefix)


static func _block(data: Dictionary, prefix: String) -> Dictionary:
	var node: Variant = data
	for part: String in prefix.split(".", false):
		if not node is Dictionary or not (node as Dictionary).has(part):
			return {}
		node = (node as Dictionary)[part]
	return (node as Dictionary).duplicate(true) if node is Dictionary else {}


static func _parse(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"data": {}, "error": "cannot read %s" % path}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"data": {}, "error": "%s is not a JSON object" % path}
	return {"data": parsed, "error": ""}
