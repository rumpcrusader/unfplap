extends RefCounted
## The typed pose transition edge: one validated wrapper per
## `poses/transitions/<from>__<to>.json` document. Private to `poses/`; the registry reads each
## file once, validates it and caches the wrapper, and `pose_state.gd` runs the validated
## document. It never reads settings, files or the scene. Contract: `docs/poses.md`.

const SELF := preload("res://mods/unfplap/poses/transition_spec.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const POSE_STATE := preload("res://mods/unfplap/poses/pose_state.gd")

const VERSION := 1
const CHANNELS := ["base", "anon", "contact", "camera", "controls", "audio", "presentation"]
const KINDS := ["hold", "blend", "delta", "path", "switch", "lock"]
const PHASES := ["active", "climax", "afterglow"]
const EASINGS := ["linear", "smoothstep"]
const EVENT_KINDS := ["status", "speech_stop", "viseme"]
const CLIMAX_POLICIES := ["hold"]
const TEARDOWN_POLICIES := ["abort", "finish"]
const REQUIRES_KEYS := ["features", "consent", "forms", "views"]

var id := ""
var version := 0
var from_id := ""
var to_id := ""
var phases: Array[String] = []
var requires: Dictionary = {}
## The document's own duration (0.0 when absent); a started Run owns the resolved clock.
var duration := 0.0
var easing := "smoothstep"
var channels: Dictionary = {}
var constraints: Array[String] = []
var events: Array = []
var interrupt: Dictionary = {}
## The validated document by reference: POSE_STATE.start_edge(data, from_id, to_id).
var data: Dictionary = {}


## A filled wrapper, or null when `errors()` is non-empty. The registry logs the errors.
static func from_dict(edge_id: String, document: Dictionary, specs: Dictionary = {}) -> Variant:
	var found := errors(edge_id, document, specs)
	if not found.is_empty():
		return null
	var edge: Variant = SELF.new()
	edge._fill(edge_id, document)
	return edge


## Every authoring problem, never only the first; an empty `specs` skips the endpoint, family and
## support checks but keeps the shape, id and timing rules, and timing resolves only after them.
static func errors(edge_id: String, document: Dictionary, specs: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var version_value: Variant = document.get("version")
	if not _is_number(version_value) or float(version_value) != float(VERSION):
		out.append("version is not %d" % VERSION)
	var from_value: Variant = document.get("from")
	var to_value: Variant = document.get("to")
	var id_value: Variant = document.get("id")
	var from_text := str(from_value) if from_value is String else ""
	var to_text := str(to_value) if to_value is String else ""
	var id_text := str(id_value) if id_value is String else ""
	var pattern := RegEx.new()
	pattern.compile(POSE_SPEC.ID_PATTERN)
	if not (id_value is String):
		out.append("id is not a string")
	elif id_text != edge_id:
		out.append("id %s does not match the file %s" % [id_text, edge_id])
	if not (from_value is String) or from_text.is_empty():
		out.append("from is empty")
	elif pattern.search(from_text) == null:
		out.append("from %s is not lower_snake_case" % from_text)
	if not (to_value is String) or to_text.is_empty():
		out.append("to is empty")
	elif pattern.search(to_text) == null:
		out.append("to %s is not lower_snake_case" % to_text)
	if not from_text.is_empty() and from_text == to_text:
		out.append("from and to are the same pose")
	var pair := from_text + "__" + to_text
	if not id_text.is_empty() and not from_text.is_empty() and not to_text.is_empty() \
			and id_text != pair:
		out.append("id %s is not %s" % [id_text, pair])
	var from_row: Variant = specs.get(from_text, null) if not specs.is_empty() else null
	var to_row: Variant = specs.get(to_text, null) if not specs.is_empty() else null
	if not specs.is_empty():
		if not from_text.is_empty() and not (from_row is Dictionary):
			out.append("from %s has no spec row" % from_text)
		if not to_text.is_empty() and not (to_row is Dictionary):
			out.append("to %s has no spec row" % to_text)
	if from_row is Dictionary and to_row is Dictionary:
		var from_family := str((from_row as Dictionary).get("family", ""))
		var to_family := str((to_row as Dictionary).get("family", ""))
		if not (from_family in POSE_SPEC.FAMILIES):
			out.append("from %s has unknown family %s" % [from_text, from_family])
		if not (to_family in POSE_SPEC.FAMILIES):
			out.append("to %s has unknown family %s" % [to_text, to_family])
		if from_family != to_family:
			out.append("from %s and to %s are different families" % [from_text, to_text])
	_check_phases(out, document)
	if document.has("requires"):
		var requires_value: Variant = document.get("requires")
		if not (requires_value is Dictionary):
			out.append("requires is not a dictionary")
		else:
			_check_requires(out, requires_value as Dictionary, from_row, to_row)
	if document.has("duration"):
		var duration_value: Variant = document.get("duration")
		if not _is_number(duration_value) or float(duration_value) < 0.0:
			out.append("duration is not a number at least 0")
	if document.has("easing"):
		var easing_value: Variant = document.get("easing")
		if not (easing_value is String) or not (easing_value in EASINGS):
			out.append("easing %s is unknown" % str(easing_value))
	if not document.has("channels"):
		out.append("channels is missing")
	else:
		_check_channels(out, document.get("channels"))
	if document.has("constraints"):
		var constraints_value: Variant = document.get("constraints")
		if not (constraints_value is Array):
			out.append("constraints is not an array")
		else:
			for item: Variant in constraints_value as Array:
				if not (item is String):
					out.append("constraints has a non-string entry")
	if out.is_empty() and POSE_STATE.start_edge(document, from_text, to_text) == null:
		out.append("channel timings or after constraints do not resolve")
	if document.has("events"):
		_check_events(out, document.get("events"))
	if document.has("interrupt"):
		_check_interrupt(out, document.get("interrupt"))
	return out


static func _check_phases(out: Array[String], document: Dictionary) -> void:
	var value: Variant = document.get("phases")
	if not (value is Array):
		out.append("phases is not an array")
		return
	var phases_value := value as Array
	if phases_value.is_empty():
		out.append("phases is empty")
	var seen: Dictionary = {}
	for item: Variant in phases_value:
		if not (item is String) or not (item in PHASES):
			out.append("phases has an unknown entry %s" % str(item))
			continue
		if seen.has(item):
			out.append("phases repeats %s" % str(item))
		seen[item] = true


static func _check_requires(out: Array[String], requires: Dictionary, from_row: Variant,
		to_row: Variant) -> void:
	for key_value: Variant in requires.keys():
		if not (key_value is String) or not (key_value in REQUIRES_KEYS):
			out.append("requires has an unknown key %s" % str(key_value))
	if requires.has("features"):
		var features_value: Variant = requires.get("features")
		if not (features_value is Array):
			out.append("requires.features is not an array")
		else:
			var seen: Dictionary = {}
			for item: Variant in features_value as Array:
				if not (item is String) or (item as String).is_empty():
					out.append("requires.features has an empty or non-string entry")
					continue
				if seen.has(item):
					out.append("requires.features repeats %s" % str(item))
				seen[item] = true
	if requires.has("consent"):
		if not (requires.get("consent") is String):
			out.append("requires.consent is not a string")
	_check_requires_list(out, requires, "forms", POSE_SPEC.FORMS, from_row, to_row)
	_check_requires_list(out, requires, "views", POSE_SPEC.VIEWS, from_row, to_row)


static func _check_requires_list(out: Array[String], requires: Dictionary, key: String,
		known: Array, from_row: Variant, to_row: Variant) -> void:
	if not requires.has(key):
		return
	var value: Variant = requires.get(key)
	if not (value is Array):
		out.append("requires.%s is not an array" % key)
		return
	var seen: Dictionary = {}
	for item: Variant in value as Array:
		if not (item is String) or not (item in known):
			out.append("requires.%s has an unknown entry %s" % [key, str(item)])
			continue
		if seen.has(item):
			out.append("requires.%s repeats %s" % [key, str(item)])
		seen[item] = true
		if not _row_supports(from_row, key, item) or not _row_supports(to_row, key, item):
			out.append("requires.%s %s is unsupported by an endpoint" % [key, str(item)])


## An endpoint supports a declared value when it declares the list and the list holds the value.
## A row without the list does not claim support either way.
static func _row_supports(row: Variant, key: String, value: Variant) -> bool:
	if not (row is Dictionary) or not (row as Dictionary).has(key):
		return true
	var declared: Variant = (row as Dictionary).get(key)
	if not (declared is Array):
		return true
	return (declared as Array).has(value)


static func _check_channels(out: Array[String], value: Variant) -> void:
	if not (value is Dictionary):
		out.append("channels is not a dictionary")
		return
	var channels := value as Dictionary
	if channels.is_empty():
		out.append("channels is empty")
	for name_value: Variant in channels.keys():
		if not (name_value is String) or not (name_value in CHANNELS):
			out.append("channels has an unknown channel %s" % str(name_value))
		var channel_value: Variant = channels[name_value]
		if not (channel_value is Dictionary):
			out.append("channel %s is not a dictionary" % str(name_value))
			continue
		_check_channel(out, str(name_value), channel_value as Dictionary)


static func _check_channel(out: Array[String], name: String, channel: Dictionary) -> void:
	var kind_value: Variant = channel.get("kind")
	var kind := str(kind_value) if kind_value is String else ""
	if not (kind in KINDS):
		out.append("%s.kind %s is unknown" % [name, str(kind_value)])
		return
	match kind:
		"switch":
			if not channel.has("at"):
				out.append("%s switch has no at" % name)
			elif not _is_number(channel.get("at")) or float(channel.get("at")) < 0.0:
				out.append("%s switch at is not a number at least 0" % name)
			for key: String in ["set", "profile", "to"]:
				if channel.has(key) and not (channel.get(key) is String):
					out.append("%s.switch.%s is not a string" % [name, key])
		"blend", "delta", "path":
			if channel.has("start") and (not _is_number(channel.get("start"))
					or float(channel.get("start")) < 0.0):
				out.append("%s.%s start is not a number at least 0" % [name, kind])
			if channel.has("duration") and (not _is_number(channel.get("duration"))
					or float(channel.get("duration")) < 0.0):
				out.append("%s.%s duration is not a number at least 0" % [name, kind])
			if channel.has("easing") and (not (channel.get("easing") is String)
					or not (str(channel.get("easing")) in EASINGS)):
				out.append("%s.%s easing %s is unknown" % [
					name, kind, str(channel.get("easing"))])
		"lock":
			for key: String in ["allow", "block"]:
				if channel.has(key):
					_check_string_array(out, channel.get(key), "%s.lock.%s" % [name, key])
			if channel.has("set") and not (channel.get("set") is String):
				out.append("%s.lock.set is not a string" % name)
		_:
			pass


static func _check_string_array(out: Array[String], value: Variant, label: String) -> void:
	if not (value is Array):
		out.append("%s is not an array" % label)
		return
	for item: Variant in value as Array:
		if not (item is String):
			out.append("%s has a non-string entry" % label)
			return


static func _check_events(out: Array[String], value: Variant) -> void:
	if not (value is Array):
		out.append("events is not an array")
		return
	var events_value := value as Array
	var last := 0.0
	var started := false
	for index in events_value.size():
		var item: Variant = events_value[index]
		if not (item is Dictionary):
			out.append("event %d is not a dictionary" % index)
			continue
		var event := item as Dictionary
		var at_value: Variant = event.get("at")
		if not _is_number(at_value) or float(at_value) < 0.0:
			out.append("event %d at is not a number at least 0" % index)
		else:
			var at := float(at_value)
			if started and at < last:
				out.append("event %d is earlier than the one before it" % index)
			last = at
			started = true
		var kind_value: Variant = event.get("kind")
		if not (kind_value is String) or not (kind_value in EVENT_KINDS):
			out.append("event %d kind %s is unknown" % [index, str(kind_value)])
			continue
		if kind_value in ["status", "viseme"]:
			var text_value: Variant = event.get("value")
			if not (text_value is String) or (text_value as String).is_empty():
				out.append("event %d %s has no value" % [index, str(kind_value)])


static func _check_interrupt(out: Array[String], value: Variant) -> void:
	if not (value is Dictionary):
		out.append("interrupt is not a dictionary")
		return
	var interrupt_value := value as Dictionary
	if interrupt_value.has("climax"):
		var climax_value: Variant = interrupt_value.get("climax")
		if not (climax_value is String) or not (climax_value in CLIMAX_POLICIES):
			out.append("interrupt.climax %s is unknown" % str(climax_value))
	if interrupt_value.has("teardown"):
		var teardown_value: Variant = interrupt_value.get("teardown")
		if not (teardown_value is String) or not (teardown_value in TEARDOWN_POLICIES):
			out.append("interrupt.teardown %s is unknown" % str(teardown_value))


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _fill(edge_id: String, document: Dictionary) -> void:
	id = edge_id
	var version_value: Variant = document.get("version", 0)
	version = int(version_value) if _is_number(version_value) else 0
	from_id = str(document.get("from", ""))
	to_id = str(document.get("to", ""))
	phases.assign(document.get("phases", []))
	var requires_value: Variant = document.get("requires", {})
	requires = requires_value as Dictionary if requires_value is Dictionary else {}
	var duration_value: Variant = document.get("duration", 0.0)
	duration = float(duration_value) if _is_number(duration_value) else 0.0
	easing = str(document.get("easing", "smoothstep"))
	var channels_value: Variant = document.get("channels", {})
	channels = channels_value as Dictionary if channels_value is Dictionary else {}
	constraints.assign(document.get("constraints", []))
	var events_value: Variant = document.get("events", [])
	events = events_value as Array if events_value is Array else []
	var interrupt_value: Variant = document.get("interrupt", {})
	interrupt = interrupt_value as Dictionary if interrupt_value is Dictionary else {}
	data = document
