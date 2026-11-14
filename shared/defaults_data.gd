extends RefCounted
## The shipped settings document, `settings/defaults.json`: the declared settings at the root and
## the global `default` profile under `default`.
##
## The file is tracked, packed and read-only in a build. It is parsed once per process and shared;
## every caller gets a detached copy of the block it asks for. This module preloads nothing, so the
## pure modules (`preferences`, `pose_catalog`) and `settings/service.gd` can all read it without a
## cycle.

const FILE := "res://mods/unfplap/settings/defaults.json"

static var _cache: Dictionary = {}
static var _loaded := false
static var _error := ""


## The parsed document, or `{}` when the file is missing or malformed. `error()` says why.
static func document() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var text := FileAccess.get_file_as_string(FILE)
	if text.is_empty():
		_error = "cannot read %s" % FILE
		return _cache
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_error = "%s is not a JSON object" % FILE
		return _cache
	_cache = parsed
	return _cache


## True when the shipped document parsed as a JSON object.
static func valid() -> bool:
	document()
	return _error.is_empty()


## The first problem with the shipped document, or "" when it is valid.
static func error() -> String:
	document()
	return _error


## A detached nested block under a dotted prefix, or `{}` when the prefix is absent or not a
## dictionary.
static func block(prefix: String) -> Dictionary:
	var node: Variant = document()
	for part: String in prefix.split(".", false):
		if not node is Dictionary or not (node as Dictionary).has(part):
			return {}
		node = (node as Dictionary)[part]
	return (node as Dictionary).duplicate(true) if node is Dictionary else {}
