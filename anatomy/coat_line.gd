extends RefCounted
## Per-pony coat line: the anatomy follows a vertical line sampled on the body coat, so a bent
## coat bends every cross-section of the mesh and a stretched coat stretches it along the line.
## The act's hole point and normal use the same frames, so the visible vulva and anus, the shaft
## and the fluid stay together.
##
## The line is sampled once from the body mesh's own rest vertices and skin, and the frames are
## refreshed from the live skeleton each tick. See `docs/anatomy.md` (`## Coat line`).

const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

const BODY_NAME := "MareBody"
const HIPS_BONE := "pony_hips"
## Must match `LINE_N` in `anatomy/anatomy.gdshader`; a source test pins the pair.
const LINE_SAMPLES := 8
## Samples closer than this in local Y are the same cross-section.
const LINE_MIN_DUPLICATE_M := 0.002

var pony: Node3D
var placement: RefCounted
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var material: ShaderMaterial

var last_error := ""

## Body mesh/skin id -> rest vertices, skin data and the vertex grid. The body resources are
## shared by every standard mare, so the 7,625-vertex grid is built once.
static var _body_cache: Dictionary = {}

var _body_vertices := PackedVector3Array()
var _body_bones := PackedInt32Array()
var _body_weights := PackedFloat32Array()
var _body_names := PackedStringArray()
var _body_binds: Array[Transform3D] = []
var _grid: Dictionary = {}
var _grid_cell := GEOMETRY.COAT_LINE_CELL_M

var _hips_index := -1
var _hips_rest := Transform3D.IDENTITY
var _built_place := Transform3D.IDENTITY
var _built_mesh_id := 0
var _built := false
## A body without a usable coat is a stable condition; do not scan for it every frame.
var _retry_at_msec := 0

## Line build, in anatomy-local space. Valid samples are `_rest_local.size()` long; the shader
## arrays are padded to `LINE_SAMPLES` with the last frame.
var _rest_body := PackedVector3Array()
var _rest_local := PackedVector3Array()
var _sample_bone_slots: Array[PackedInt32Array] = []
var _sample_weights: Array[PackedFloat32Array] = []
var _unique_bones := PackedInt32Array()
var _bone_bind: Array[Transform3D] = []
var _bone_matrices: Array[Transform3D] = []
var _bone_slot: Dictionary = {}
var _live := PackedVector3Array()

## The shader's per-sample columns and offsets, preallocated to `LINE_SAMPLES`.
var _basis_x := PackedVector3Array()
var _basis_y := PackedVector3Array()
var _basis_z := PackedVector3Array()
var _origin := PackedVector3Array()
var _line_count := 0


func setup(pony_node: Node3D, placement_node: RefCounted) -> void:
	pony = pony_node
	placement = placement_node


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_retry_at_msec = 0


## The material is recreated whenever the anatomy appearance changes; the line keeps its state on
## the new one. Frames stay identity until the next tick.
func set_material(material_node: ShaderMaterial) -> void:
	material = material_node
	if not is_instance_valid(material):
		return
	_upload_static()
	_reset_frames()
	_upload_frames()


## One debug line for the attach log: the sample count and its local Y range.
func summary() -> String:
	if not _built or _rest_local.is_empty():
		return "not built: %s" % last_error
	return "samples=%d y=%.3f..%.3f" % [_rest_local.size(),
		_rest_local[0].y, _rest_local[_rest_local.size() - 1].y]


func clear() -> void:
	pony = null
	placement = null
	mesh = null
	skeleton = null
	material = null
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_retry_at_msec = 0
	_rest_body = PackedVector3Array()
	_rest_local = PackedVector3Array()
	_live = PackedVector3Array()
	_sample_bone_slots = []
	_sample_weights = []
	_unique_bones = PackedInt32Array()
	_bone_bind = []
	_bone_matrices = []
	_bone_slot = {}
	_grid = {}
	last_error = ""


## Called every frame by the controller. Builds the line lazily and refreshes the frames from the
## live skeleton. A missing body or skin leaves the anatomy rigid.
func tick(hidden: bool) -> void:
	if hidden:
		return
	if not is_instance_valid(mesh) or not is_instance_valid(skeleton) \
			or not is_instance_valid(placement) or not is_instance_valid(material):
		return
	var base_value: Variant = placement.base_place()
	if not base_value is Transform3D:
		return
	var base := base_value as Transform3D
	if not _built or _built_mesh_id == 0 or not is_instance_valid(mesh.mesh) \
			or mesh.mesh.get_instance_id() != _built_mesh_id \
			or not base.is_equal_approx(_built_place):
		var now := Time.get_ticks_msec()
		if now < _retry_at_msec:
			return
		if not rebuild():
			_retry_at_msec = now + 2000
			return
	var hips_delta := skeleton.get_bone_global_pose(_hips_index) * _hips_rest.affine_inverse()
	var to_local := base.affine_inverse() * hips_delta.affine_inverse()
	for i in _unique_bones.size():
		_bone_matrices[i] = skeleton.get_bone_global_pose(_unique_bones[i]) * _bone_bind[i]
	for i in _rest_body.size():
		var skinned := Vector3.ZERO
		var slots := _sample_bone_slots[i]
		var weights := _sample_weights[i]
		for k in slots.size():
			skinned += (_bone_matrices[slots[k]] * _rest_body[i]) * weights[k]
		_live[i] = to_local * skinned
	GEOMETRY.fill_line_frames(_rest_local, _live, _basis_x, _basis_y, _basis_z, _origin)
	_upload_frames()


## Re-find the body mesh, resample the line and rebuild the frames. Called on attach, a mesh swap
## or a placement change; not per frame.
func rebuild() -> bool:
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_rest_body = PackedVector3Array()
	_rest_local = PackedVector3Array()
	_live = PackedVector3Array()
	_sample_bone_slots = []
	_sample_weights = []
	_unique_bones = PackedInt32Array()
	_bone_bind = []
	_bone_matrices = []
	_bone_slot = {}
	last_error = ""
	if not is_instance_valid(mesh) or not is_instance_valid(skeleton) \
			or not is_instance_valid(placement):
		last_error = "no anatomy mesh"
		return false
	var source := mesh.mesh as ArrayMesh
	if source == null or source.get_surface_count() != 1:
		last_error = "anatomy mesh is not one surface"
		return false
	if not _read_body():
		return false
	var base_value: Variant = placement.base_place()
	if not base_value is Transform3D:
		last_error = "no anatomy placement"
		return false
	var base := base_value as Transform3D
	var hips_index := skeleton.find_bone(HIPS_BONE)
	if hips_index < 0:
		last_error = "no pony_hips bone"
		return false
	var arrays: Array = source.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
		last_error = "anatomy mesh has no vertices"
		return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		last_error = "anatomy mesh has no vertices"
		return false
	var y_min := vertices[0].y
	var y_max := vertices[0].y
	for vertex in vertices:
		y_min = minf(y_min, vertex.y)
		y_max = maxf(y_max, vertex.y)
	var targets := GEOMETRY.coat_line_targets(y_min, y_max, LINE_SAMPLES)
	var targets_body := PackedVector3Array()
	targets_body.resize(targets.size())
	for i in targets.size():
		targets_body[i] = base * targets[i]
	var samples := GEOMETRY.coat_line_samples(targets_body, _body_vertices,
		_body_bones, _body_weights, _body_names, _grid, _grid_cell)
	var indices: PackedInt32Array = samples.get("indices", PackedInt32Array())
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var influences: Array = samples.get("influences", [])
	if indices.size() < 2:
		last_error = "no body coat at the anatomy"
		return false
	var inv_base := base.affine_inverse()
	var rows: Array = []
	for i in indices.size():
		rows.append({"body": points[i], "local": inv_base * points[i],
			"influence": influences[i]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Vector3 = a["local"]
		var right: Vector3 = b["local"]
		return left.y < right.y)
	var keep: Array = []
	var last_y := -INF
	for row: Dictionary in rows:
		var local: Vector3 = row["local"]
		if not keep.is_empty() and local.y - last_y < LINE_MIN_DUPLICATE_M:
			continue
		keep.append(row)
		last_y = local.y
	if keep.size() < 2:
		last_error = "coat line samples collapse"
		return false
	for row: Dictionary in keep:
		var local: Vector3 = row["local"]
		var body: Vector3 = row["body"]
		var influence: Dictionary = row["influence"]
		var slots := PackedInt32Array()
		var weights := PackedFloat32Array()
		var total := 0.0
		for bone_name: String in influence.keys():
			var weight := float(influence[bone_name])
			if weight <= 0.0:
				continue
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				continue
			var slot := int(_bone_slot.get(bone, -1))
			if slot < 0:
				slot = _unique_bones.size()
				_bone_slot[bone] = slot
				_unique_bones.append(bone)
				_bone_bind.append(_bind_pose(bone_name))
				_bone_matrices.append(Transform3D.IDENTITY)
			slots.append(slot)
			weights.append(weight)
			total += weight
		if slots.is_empty():
			continue
		if total > 0.0:
			for k in weights.size():
				weights[k] /= total
		_rest_body.append(body)
		_rest_local.append(local)
		_sample_bone_slots.append(slots)
		_sample_weights.append(weights)
	_line_count = _rest_body.size()
	if _line_count < 2:
		last_error = "anatomy bones are missing"
		return false
	_live.resize(_line_count)
	_hips_index = hips_index
	_hips_rest = skeleton.get_bone_global_rest(_hips_index)
	_built_mesh_id = mesh.mesh.get_instance_id()
	_built_place = base
	_built = true
	_retry_at_msec = 0
	_reset_frames()
	_upload_static()
	_upload_frames()
	return true


## Debug-only view of the built line in anatomy-local space. Empty when the line is not built.
func debug_data() -> Dictionary:
	if not _built or _line_count < 2:
		return {}
	return {
		"rest": _rest_local,
		"live": _live,
		"basis_x": _basis_x,
		"basis_z": _basis_z,
	}


## The deformed local point for the act's hole anchor. Matches the shader's mapping.
func deform_point(local: Vector3) -> Vector3:
	if not _built or _line_count < 2:
		return local
	return GEOMETRY.line_point_at(local, _rest_local, _basis_x, _basis_y, _basis_z, _origin)


## The deformed local direction for the act's opening normal. Matches the shader's mapping.
func deform_direction(local: Vector3) -> Vector3:
	if not _built or _line_count < 2:
		return local
	return GEOMETRY.line_direction_at(local, _rest_local, _basis_x, _basis_y,
		_basis_z, _origin)


## The body bind pose for a bone name, in the body skin's bind order.
func _bind_pose(bone_name: String) -> Transform3D:
	var index := _body_names.find(bone_name)
	if index < 0 or index >= _body_binds.size():
		return Transform3D.IDENTITY
	return _body_binds[index]


func _ensure_upload_arrays() -> void:
	if _basis_x.size() != LINE_SAMPLES:
		_basis_x.resize(LINE_SAMPLES)
		_basis_y.resize(LINE_SAMPLES)
		_basis_z.resize(LINE_SAMPLES)
		_origin.resize(LINE_SAMPLES)


func _reset_frames() -> void:
	_ensure_upload_arrays()
	for i in LINE_SAMPLES:
		_basis_x[i] = Vector3.RIGHT
		_basis_y[i] = Vector3.UP
		_basis_z[i] = Vector3.BACK
		_origin[i] = Vector3.ZERO


func _upload_static() -> void:
	if not is_instance_valid(material):
		return
	var padded := PackedVector3Array()
	padded.resize(LINE_SAMPLES)
	var last := _rest_local[_rest_local.size() - 1] if not _rest_local.is_empty() \
		else Vector3.ZERO
	for i in LINE_SAMPLES:
		padded[i] = _rest_local[mini(i, _rest_local.size() - 1)] if not _rest_local.is_empty() \
			else last
	material.set_shader_parameter("line_rest", padded)
	material.set_shader_parameter("line_count", _line_count)


func _upload_frames() -> void:
	if not is_instance_valid(material):
		return
	_ensure_upload_arrays()
	material.set_shader_parameter("line_basis_x", _basis_x)
	material.set_shader_parameter("line_basis_y", _basis_y)
	material.set_shader_parameter("line_basis_z", _basis_z)
	material.set_shader_parameter("line_origin", _origin)


## The body coat's rest vertices, skin data and bind poses. The body mesh and skin resources are
## shared by every standard mare; the grid is built once and reused by every pony's line.
func _read_body() -> bool:
	if not is_instance_valid(pony):
		last_error = "no pony"
		return false
	var model: Variant = pony.get("_model")
	if not model is Node:
		last_error = "no pony model"
		return false
	var body := (model as Node).find_child(BODY_NAME, true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.mesh == null or body.skin == null:
		last_error = "no skinned body coat"
		return false
	if body.mesh.get_surface_count() < 1:
		last_error = "body coat has no surface"
		return false
	var key := "%d:%d" % [body.mesh.get_instance_id(), body.skin.get_instance_id()]
	var cached: Variant = _body_cache.get(key)
	if not cached is Dictionary:
		cached = _build_body(body)
		if (cached as Dictionary).is_empty():
			return false
		_body_cache[key] = cached
	var row := cached as Dictionary
	_body_vertices = row.get("vertices", PackedVector3Array())
	_body_bones = row.get("bones", PackedInt32Array())
	_body_weights = row.get("weights", PackedFloat32Array())
	_body_names = row.get("names", PackedStringArray())
	_body_binds = []
	var bind_row: Variant = row.get("binds", [])
	if bind_row is Array:
		for bind: Transform3D in bind_row:
			_body_binds.append(bind)
	_grid = row.get("grid", {})
	if _body_vertices.is_empty() or _body_bones.is_empty() or _body_weights.is_empty():
		last_error = "body coat has no skin data"
		return false
	return true


## Build the immutable body-side data once per body mesh and skin.
func _build_body(body: MeshInstance3D) -> Dictionary:
	var arrays: Array = body.mesh.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null \
			or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
		last_error = "body coat is not skinned"
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if vertices.is_empty() or bones.is_empty() or weights.is_empty():
		last_error = "body coat has no skin data"
		return {}
	var skin: Skin = body.skin
	var names := PackedStringArray()
	var binds: Array[Transform3D] = []
	for i in skin.get_bind_count():
		names.append(String(skin.get_bind_name(i)))
		binds.append(skin.get_bind_pose(i))
	return {
		"vertices": vertices,
		"bones": bones,
		"weights": weights,
		"names": names,
		"binds": binds,
		"grid": GEOMETRY.body_weight_grid(vertices, _grid_cell),
	}
