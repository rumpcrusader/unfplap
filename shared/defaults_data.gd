extends RefCounted
## The shipped settings data, read once per process:
##
##   settings/defaults.json   the declared settings at the root and the global `default` profile
##   settings/catalogs.json   provider-overridable content: built-in act prompts, per-mare
##                            character templates and per-mare placement rows
##
## Both files are tracked, packed and read-only in a build. `defaults.json` is the player-settings
## document; `catalogs.json` is content and never reaches `defaults()`, `data()` or the player file.
## Every caller gets a detached copy of the block it asks for. This module preloads nothing, so the
## pure modules (`preferences`, `pose_catalog`, `character_preferences`) and `settings/service.gd`
## can all read it without a cycle.

const DEFAULTS_FILE := "res://mods/unfplap/settings/defaults.json"
const CATALOG_FILE := "res://mods/unfplap/settings/catalogs.json"

static var _document_cache: Dictionary = {}
static var _document_loaded := false
static var _document_error := ""
static var _catalog_cache: Dictionary = {}
static var _catalog_loaded := false
static var _catalog_error := ""


## The parsed defaults document, or `{}` when the file is missing or malformed. `error()` says why.
static func document() -> Dictionary:
	if not _document_loaded:
		_document_loaded = true
		var loaded := _parse(DEFAULTS_FILE)
		_document_cache = loaded["data"]
		_document_error = loaded["error"]
	return _document_cache


## The parsed catalog document, or `{}` when the file is missing or malformed.
static func catalog() -> Dictionary:
	if not _catalog_loaded:
		_catalog_loaded = true
		var loaded := _parse(CATALOG_FILE)
		_catalog_cache = loaded["data"]
		_catalog_error = loaded["error"]
	return _catalog_cache


## True when the shipped defaults document parsed as a JSON object.
static func valid() -> bool:
	document()
	return _document_error.is_empty()


## True when the shipped catalog document parsed as a JSON object.
static func catalog_valid() -> bool:
	catalog()
	return _catalog_error.is_empty()


## The first problem with the shipped defaults document, or "" when it is valid.
static func error() -> String:
	document()
	return _document_error


## The first problem with the shipped catalog document, or "" when it is valid.
static func catalog_error() -> String:
	catalog()
	return _catalog_error


## A detached nested block of the defaults document under a dotted prefix, or `{}` when the prefix
## is absent or not a dictionary.
static func block(prefix: String) -> Dictionary:
	return _block(document(), prefix)


## A detached nested block of the catalog under a dotted prefix.
static func catalog_block(prefix: String) -> Dictionary:
	return _block(catalog(), prefix)


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
