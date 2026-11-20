extends RefCounted
## The one prompt-text renderer: it builds the part/slot graph of a prompt, validates it and
## expands every `{name}`. No other script parses a prompt placeholder.

const MAX_DEPTH := 32

static var _slot_regex: RegEx = null
static var _space_regex: RegEx = null


## Every structural failure in `document`, or no failures when it is a valid prompt graph.
static func validate(document: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for group: String in document:
		if group == "version":
			continue
		_validate_node(document[group], group, out)
	return out


## The rendered prompt, or "" for a malformed graph. A string is raw text.
static func render(prompt: Variant, values: Dictionary) -> String:
	if prompt is String:
		return _collapse(_expand_raw(prompt, values))
	if not prompt is Dictionary:
		return ""
	var node: Dictionary = prompt
	if not (node.get("template") is String) or not (node.get("slots") is Array):
		return ""
	var problems: Array[String] = []
	_validate_composite(node, "", problems)
	if not problems.is_empty():
		return ""
	return _collapse(_render_composite(node, values, 0))


## Every renderable prompt id in `document`, rendered with that id's own values by id.
static func render_document(document: Dictionary, values_by_id: Dictionary) -> Dictionary:
	var out := {}
	for group: String in document:
		if group == "version":
			continue
		_walk_document(document[group], group, values_by_id, out)
	return out


static func _validate_node(value: Variant, path: String, out: Array[String]) -> void:
	if value is String:
		_check_leaf(value, path, out)
	elif value is Array:
		_validate_pool(value, path, out)
	elif value is Dictionary:
		_validate_map(value, path, out)
	else:
		out.append("%s: not a prompt node" % path)


static func _validate_map(node: Dictionary, path: String, out: Array[String]) -> void:
	if node.has("template") or node.has("slots"):
		_validate_composite(node, path, out)
		return
	for key: String in node:
		_validate_node(node[key], "%s.%s" % [path, key], out)


static func _validate_pool(pool: Array, path: String, out: Array[String]) -> void:
	for index in range(pool.size()):
		var item: Variant = pool[index]
		if not item is String:
			out.append("%s[%d]: not a prompt string" % [path, index])
			continue
		_check_leaf(str(item), "%s[%d]" % [path, index], out)


static func _check_leaf(text: String, path: String, out: Array[String]) -> void:
	for name: String in _refs(text):
		out.append("%s: plain string references {%s}" % [path, name])


static func _validate_composite(node: Dictionary, path: String, out: Array[String]) -> void:
	if not (node.get("template") is String):
		out.append("%s: missing template" % path)
		return
	if not (node.get("slots") is Array):
		out.append("%s: missing slots" % path)
		return
	var slots := {}
	for item: Variant in (node["slots"] as Array):
		if not item is String or str(item).is_empty():
			out.append("%s: a slot name is not text" % path)
			continue
		if slots.has(str(item)):
			out.append("%s: duplicate slot %s" % [path, item])
			continue
		slots[str(item)] = true
	var parts := _parts(node)
	for name: String in parts:
		if slots.has(name):
			out.append("%s: %s is both a part and a slot" % [path, name])
		var part: Variant = parts[name]
		if not (part is String or part is Dictionary):
			out.append("%s: part %s is not a prompt" % [path, name])
	var template: String = node["template"]
	var refs := _refs(template)
	for name: String in refs:
		if not parts.has(name) and not slots.has(name):
			out.append("%s: unknown reference {%s}" % [path, name])
	var used := {}
	for name: String in refs:
		if slots.has(name):
			used[name] = true
	for name: String in parts:
		var part: Variant = parts[name]
		if part is String:
			for ref: String in _refs(str(part)):
				if not parts.has(ref) and not slots.has(ref):
					out.append("%s.%s: unknown reference {%s}" % [path, name, ref])
				elif slots.has(ref):
					used[ref] = true
		elif part is Dictionary:
			_validate_composite(part, "%s.%s" % [path, name], out)
	for name: String in slots:
		if not used.has(name):
			out.append("%s: unused slot %s" % [path, name])
	var reachable := _reachable(refs, parts)
	for name: String in parts:
		if not reachable.has(name):
			out.append("%s: part %s is unreachable" % [path, name])
	var marks := {}
	_cycle(refs, parts, marks, path, out)


# The template's own references are the root edges; a reached plain part adds its own edges.
static func _reachable(refs: Array[String], parts: Dictionary) -> Dictionary:
	var seen := {}
	var queue: Array[String] = []
	for name: String in refs:
		if parts.has(name):
			queue.append(name)
	while not queue.is_empty():
		var name: String = queue.pop_back()
		if seen.has(name):
			continue
		seen[name] = true
		var part: Variant = parts[name]
		if part is String:
			for ref: String in _refs(str(part)):
				if parts.has(ref) and not seen.has(ref):
					queue.append(ref)
	return seen


static func _cycle(refs: Array[String], parts: Dictionary, marks: Dictionary, path: String,
		out: Array[String]) -> void:
	for name: String in refs:
		if parts.has(name):
			_visit(name, parts, marks, path, out)


static func _visit(name: String, parts: Dictionary, marks: Dictionary, path: String,
		out: Array[String]) -> void:
	var mark := int(marks.get(name, 0))
	if mark == 2:
		return
	if mark == 1:
		out.append("%s: cycle through %s" % [path, name])
		return
	marks[name] = 1
	var part: Variant = parts[name]
	if part is String:
		_cycle(_refs(str(part)), parts, marks, path, out)
	marks[name] = 2


static func _render_composite(node: Dictionary, values: Dictionary, depth: int) -> String:
	var parts := _parts(node)
	var slots := {}
	for item: Variant in (node["slots"] as Array):
		slots[str(item)] = true
	var rendered := _render_template(str(node["template"]), parts, slots, values, {}, depth, false)
	return str(rendered["text"])


static func _render_template(template: String, parts: Dictionary, slots: Dictionary,
		values: Dictionary, cache: Dictionary, depth: int, as_part: bool) -> Dictionary:
	var out := ""
	var dropped := false
	var cursor := 0
	for found: RegExMatch in _slots().search_all(template):
		out += template.substr(cursor, found.get_start() - cursor)
		var name := found.get_string(1)
		if parts.has(name):
			var part := _render_part(name, parts, slots, values, cache, depth)
			if as_part and bool(part["dropped"]):
				dropped = true
			out += str(part["text"])
		elif slots.has(name):
			var value := str(values.get(name, ""))
			if as_part and value.strip_edges().is_empty():
				dropped = true
			out += value
		elif as_part:
			dropped = true
		cursor = found.get_end()
	out += template.substr(cursor)
	return {"text": "" if dropped else out, "dropped": dropped}


static func _render_part(name: String, parts: Dictionary, slots: Dictionary, values: Dictionary,
		cache: Dictionary, depth: int) -> Dictionary:
	if cache.has(name):
		return cache[name]
	if depth >= MAX_DEPTH:
		return {"text": "", "dropped": true}
	var part: Variant = parts[name]
	var rendered := {"text": "", "dropped": true}
	if part is String:
		rendered = _render_template(str(part), parts, slots, values, cache, depth + 1, true)
	elif part is Dictionary and part.get("template") is String:
		rendered = _render_nested(part, values, depth + 1)
	cache[name] = rendered
	return rendered


static func _render_nested(node: Dictionary, values: Dictionary, depth: int) -> Dictionary:
	var parts := _parts(node)
	var slots := {}
	for item: Variant in (node["slots"] as Array):
		slots[str(item)] = true
	return _render_template(str(node["template"]), parts, slots, values, {}, depth, true)


static func _expand_raw(template: String, values: Dictionary) -> String:
	var out := ""
	var cursor := 0
	for found: RegExMatch in _slots().search_all(template):
		out += template.substr(cursor, found.get_start() - cursor)
		out += str(values.get(found.get_string(1), ""))
		cursor = found.get_end()
	out += template.substr(cursor)
	return out


static func _walk_document(value: Variant, path: String, values_by_id: Dictionary,
		out: Dictionary) -> void:
	if value is String:
		out[path] = _collapse(str(value))
	elif value is Array:
		return
	elif value is Dictionary:
		var node: Dictionary = value
		if node.get("template") is String and node.get("slots") is Array:
			var own: Variant = values_by_id.get(path, {})
			out[path] = render(node, own if own is Dictionary else {})
		else:
			for key: String in node:
				_walk_document(node[key], "%s.%s" % [path, key], values_by_id, out)


static func _parts(node: Dictionary) -> Dictionary:
	var out := {}
	for key: String in node:
		if key != "template" and key != "slots":
			out[key] = node[key]
	return out


static func _refs(text: String) -> Array[String]:
	var out: Array[String] = []
	for found: RegExMatch in _slots().search_all(text):
		var name := found.get_string(1)
		if not out.has(name):
			out.append(name)
	return out


static func _collapse(text: String) -> String:
	var lines := text.split("\n")
	var out := PackedStringArray()
	for line: String in lines:
		out.append(_spaces().sub(line, " ", true).strip_edges())
	return "\n".join(out).strip_edges()


static func _slots() -> RegEx:
	if _slot_regex == null:
		_slot_regex = RegEx.new()
		_slot_regex.compile("\\{([a-z_][a-z0-9_]*)\\}")
	return _slot_regex


static func _spaces() -> RegEx:
	if _space_regex == null:
		_space_regex = RegEx.new()
		_space_regex.compile("[ \\t]+")
	return _space_regex
