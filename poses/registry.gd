extends RefCounted
## The pose registry: the validated spec table and the edge table. Private to `poses/`; the
## session caches one registry and the suites read it. It never mutates the catalog or settings.
## Contract: `docs/poses.md`.

const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var _specs: Dictionary = {}
var _built := false


## One typed spec per shipped id. An invalid row stays out of the cache; `validate()` reports it.
func _build() -> void:
	if _built:
		return
	_built = true
	_specs.clear()
	for id: String in SPECS.ids():
		var spec: Variant = POSE_SPEC.from_dict(id, SPECS.spec(id))
		if spec != null:
			_specs[id] = spec


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


## The shipped table plus the catalog membership. Returns one line per problem.
func validate() -> Array[String]:
	_build()
	var out: Array[String] = check_table(SPECS.ids(), SPECS.SPECS, CATALOG.all(), CATALOG.every())
	# `CATALOG.all()` is the `default.poses` block list (the settings suite pins that), so a
	# public id with no block and a block with no public id are both reported by `check_table`.
	for id: String in _specs.keys():
		var spec: Variant = _specs[id]
		if spec.public_pose and CATALOG.defaults(spec.settings_group).is_empty():
			out.append("public pose %s has no default.poses block" % id)
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
		out.append_array(POSE_SPEC.errors(id, data))
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


## The authored edges. The JSON edge loading is Phase A3; the empty stubs keep the shape stable.
func edges() -> Array:
	return []


func edge(_id: String) -> Variant:
	return null