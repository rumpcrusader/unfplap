extends RefCounted
## Compatibility layer for the settings panel. The settings themselves are declared in
## `settings.gd`; this file only adapts them to the old path-keyed entry dictionaries while the
## panel is rebuilt to read the named settings directly. Do not add settings here.
##
## Debug settings keep reporting their old `debug` tab so the current panel still separates them.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const GENERAL_TAB := "general"
const ANATOMY_TAB := "anatomy"
const DEBUG_TAB := "debug"

static var _cache: Dictionary = {}
static var _cache_size := -1


static func all() -> Dictionary:
	var count := SETTINGS.all_settings().size()
	if _cache_size == count and not _cache.is_empty():
		return _cache
	_cache.clear()
	for s: Variant in SETTINGS.all_settings():
		var view: Dictionary = SETTINGS.entry_view(s)
		# The old panel has no World tab yet: keep its entries in General until the new panel lands.
		var home := str(view.get("tab", GENERAL_TAB))
		view["tab"] = DEBUG_TAB if bool(view.get("debug", false)) else (
			GENERAL_TAB if home == SETTINGS.WORLD else home)
		_cache[str(s.path)] = view
	_cache_size = count
	return _cache


static func has(path: String) -> bool:
	return all().has(path)


static func entry(path: String) -> Dictionary:
	var value: Variant = all().get(path, {})
	return value if value is Dictionary else {}


static func default_value(path: String) -> Variant:
	if not has(path):
		return null
	var value: Variant = entry(path).get("default")
	return (value as Array).duplicate() if value is Array else value


static func default_block(prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for path: String in all():
		if path.begins_with(prefix):
			write_path(out, path.substr(prefix.length()), default_value(path))
	return out


static func groups(tab: String) -> Array:
	var seen: Array = []
	for path: String in all():
		var item := entry(path)
		if str(item.get("tab", DEBUG_TAB)) != tab:
			continue
		var group := str(item.get("group", ""))
		if not group.is_empty() and not seen.has(group):
			seen.append(group)
	return seen


static func write_path(root: Dictionary, path: String, value: Variant) -> void:
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
