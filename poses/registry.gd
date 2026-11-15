extends RefCounted
## The pose registry: the validated spec table and the edge table. Private to `poses/`; the
## session caches one registry and the suites read it. It reads the authored edge documents once,
## on the first lookup, and never mutates the catalog or settings. Contract: `docs/poses.md`.

const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const TRANSITION_SPEC := preload("res://mods/unfplap/poses/transition_spec.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const TRANSITIONS_DIR := "res://mods/unfplap/poses/transitions"

var _specs: Dictionary = {}
var _edges: Dictionary = {}
var _edge_order: Array[String] = []
var _edge_errors: Array[String] = []
var _built := false


## One typed spec per shipped id, then the authored edges. An invalid row or edge stays out of the
## cache; `validate()` reports it. The files are read here once, never on a tick.
func _build() -> void:
	if _built:
		return
	_built = true
	_specs.clear()
	for id: String in SPECS.ids():
		var spec: Variant = POSE_SPEC.from_dict(id, SPECS.spec(id), SPECS.SPECS)
		if spec != null:
			_specs[id] = spec
	_load_edges()


## Read each `poses/transitions/*.json` in sorted filename order, validate it against the raw spec
## table and cache the wrapper by id. Every problem is prefixed with the filename.
func _load_edges() -> void:
	_edges.clear()
	_edge_order.clear()
	_edge_errors.clear()
	if not DirAccess.dir_exists_absolute(TRANSITIONS_DIR):
		return
	var names := DirAccess.get_files_at(TRANSITIONS_DIR)
	names.sort()
	for name: String in names:
		if not name.ends_with(".json"):
			continue
		var path := TRANSITIONS_DIR.path_join(name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_edge_errors.append("%s: empty or unreadable" % name)
			continue
		var parser := JSON.new()
		if parser.parse(text) != OK:
			_edge_errors.append("%s: parse error %s at line %d" % [name,
				parser.get_error_message(), parser.get_error_line()])
			continue
		var data: Variant = parser.data
		if not (data is Dictionary):
			_edge_errors.append("%s: the document is not an object" % name)
			continue
		var edge_id := name.trim_suffix(".json")
		var found := TRANSITION_SPEC.errors(edge_id, data, SPECS.SPECS)
		if not found.is_empty():
			for message: String in found:
				_edge_errors.append("%s: %s" % [name, message])
			continue
		var edge: Variant = TRANSITION_SPEC.from_dict(edge_id, data, SPECS.SPECS)
		if edge == null:
			_edge_errors.append("%s: the edge did not build" % name)
			continue
		if _edges.has(edge.id):
			_edge_errors.append("%s: duplicate edge id %s" % [name, edge.id])
			continue
		_edges[edge.id] = edge
		_edge_order.append(edge.id)
	_edge_order.sort()


func spec(id: String) -> Variant:
	_build()
	return _specs.get(id, null)


func all() -> Array:
	_build()
	var out: Array = []
	for id: String in SPECS.ids():
		if _specs.has(id):
			out.append(_specs[id])
	return out


func ids() -> Array[String]:
	_build()
	var out: Array[String] = []
	for id: String in SPECS.ids():
		if _specs.has(id):
			out.append(id)
	return out


## The authored edges in sorted id order. A second call returns the same wrapper objects.
func edges() -> Array:
	_build()
	var out: Array = []
	for id: String in _edge_order:
		if _edges.has(id):
			out.append(_edges[id])
	return out


## One cached edge wrapper, or null when the id has no valid document.
func edge(id: String) -> Variant:
	_build()
	return _edges.get(id, null)


## The shipped table plus the catalog membership plus the edge documents. One line per problem.
func validate() -> Array[String]:
	_build()
	var out: Array[String] = check_table(SPECS.ids(), SPECS.SPECS, CATALOG.all(), CATALOG.every())
	# `CATALOG.all()` is the `default.poses` block list (the settings suite pins that), so a
	# public id with no block and a block with no public id are both reported by `check_table`.
	for id: String in _specs.keys():
		var spec: Variant = _specs[id]
		if spec.public_pose and CATALOG.defaults(spec.settings_group).is_empty():
			out.append("public pose %s has no default.poses block" % id)
	out.append_array(_edge_errors)
	return out


## The table check, shared with the suites so a synthetic table uses the shipped rules.
static func check_table(table_ids: Array, specs: Dictionary, public_ids: Array,
		every_ids: Array) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for id_value: Variant in table_ids:
		var id := str(id_value)
		if seen.has(id):
			out.append("duplicate pose id %s" % id)
			continue
		seen[id] = true
		var row: Variant = specs.get(id)
		if not (row is Dictionary):
			out.append("pose %s has no spec row" % id)
			continue
		var data: Dictionary = row
		out.append_array(POSE_SPEC.errors(id, data, specs))
		var is_public := bool(data.get("public", false))
		if is_public and not (id in public_ids):
			out.append("public pose %s is not in CATALOG.all()" % id)
		if not is_public and (id in public_ids):
			out.append("internal pose %s is in CATALOG.all()" % id)
		if not (id in every_ids):
			out.append("CATALOG.every() lacks pose %s" % id)
	for id_value: Variant in public_ids:
		var id := str(id_value)
		if not seen.has(id):
			out.append("CATALOG.all() id %s has no spec" % id)
			continue
		var row: Variant = specs.get(id)
		if row is Dictionary and not bool((row as Dictionary).get("public", false)):
			out.append("CATALOG.all() id %s is not public" % id)
	return out
