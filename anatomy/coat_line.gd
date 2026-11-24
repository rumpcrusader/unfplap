extends RefCounted
## Per-pony coat line: the mesh's own vertical axis, bent by the hind legs, with the shader
## bending every cross-section to match.

const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

const HIPS_BONE := "pony_hips"
## Must match `LINE_N` in `anatomy/anatomy.gdshader`; a source test pins the pair.
const LINE_SAMPLES := 8
## The hind-leg tip bones, in fallback order per side.
const LEG_TIPS := ["pony_tibia_", "pony_femur_", "pony_flank_"]
## How much of the leg tip's horizontal travel the line follows, and its local cap.
const BEND_GAIN := 0.8
const BEND_MAX_M := 0.04

var pony: Node3D
var placement: RefCounted
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var material: ShaderMaterial

var last_error := ""

var _hips_index := -1
var _hips_rest := Transform3D.IDENTITY
var _built_place := Transform3D.IDENTITY
var _built_mesh_id := 0
var _built := false
## A missing mesh or skeleton is a stable condition; do not scan for it every frame.
var _retry_at_msec := 0

## The line in anatomy-local space: the rest axis and the bent one, padded to the sample
## count with the last frame.
var _rest_local := PackedVector3Array()
var _live := PackedVector3Array()
var _leg_tips := PackedInt32Array()
var _leg_rests := PackedVector3Array()

## The shader's per-sample columns and offsets, preallocated to `LINE_SAMPLES`.
var _basis_x := PackedVector3Array()
var _basis_y := PackedVector3Array()
var _basis_z := PackedVector3Array()
var _origin := PackedVector3Array()
var _line_count := 0
## The debug toggle. Off uploads `line_count = 0`, so the mesh stays rigid.
var _enabled := false
## The last visibility the controller passed. The skeleton signal skips while hidden.
var _hidden := true
## True once the signal has supplied a final (modifier-applied) pose.
var _pose_ready := false


func setup(pony_node: Node3D, placement_node: RefCounted) -> void:
	pony = pony_node
	placement = placement_node


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	mesh = mesh_node
	skeleton = skeleton_node
	if is_instance_valid(skeleton) \
			and not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_retry_at_msec = 0
	_enabled = false
	_hidden = true
	_pose_ready = false


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
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	pony = null
	placement = null
	mesh = null
	skeleton = null
	material = null
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_retry_at_msec = 0
	_enabled = false
	_hidden = true
	_pose_ready = false
	_rest_local = PackedVector3Array()
	_live = PackedVector3Array()
	_leg_tips = PackedInt32Array()
	_leg_rests = PackedVector3Array()
	last_error = ""


## The debug toggle. Off uploads `line_count = 0` so the mesh stays rigid; on re-uploads the line
## and lets the next pose compute the frames.
func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	_pose_ready = false
	if not enabled:
		_hidden = true
		_reset_frames()
		_upload_frames()
	_upload_static()


func is_enabled() -> bool:
	return _enabled


## Called every frame; builds the line lazily and lets the pose signal fill it.
func tick(visible: bool) -> void:
	_hidden = not visible or not _enabled
	if _hidden:
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
	if not _pose_ready:
		_compute_frames()


## The skeleton's final pose, after every `SkeletonModifier3D`. Outside this signal the skeleton
## reports its unmodified pose, so the coat's own stretch and fidget rotations would be missed.
func _on_skeleton_updated() -> void:
	if _hidden:
		return
	_compute_frames()
	_pose_ready = true


## Bend the line from the hind-leg tip travel relative to the pelvis and build its frames.
func _compute_frames() -> void:
	if not _enabled or not _built or _line_count < 2 or not is_instance_valid(skeleton) \
			or not is_instance_valid(material):
		return
	var hips_delta := skeleton.get_bone_global_pose(_hips_index) * _hips_rest.affine_inverse()
	var inv_hips := hips_delta.affine_inverse()
	var inv_place := _built_place.affine_inverse()
	var bend := Vector3.ZERO
	var best := 0.0
	for i in _leg_tips.size():
		var pose := skeleton.get_bone_global_pose(_leg_tips[i])
		var live_local := inv_place * inv_hips * pose.origin
		var rest_local := inv_place * _leg_rests[i]
		var delta := live_local - rest_local
		var horizontal := Vector3(delta.x, 0.0, delta.z)
		var length := horizontal.length()
		if length > best:
			best = length
			bend = horizontal
	if best > 0.000001:
		bend = bend / best * minf(best * BEND_GAIN, BEND_MAX_M)
	GEOMETRY.coat_line_bend(_rest_local, bend, _live)
	GEOMETRY.fill_line_frames(_rest_local, _live, _basis_x, _basis_y, _basis_z, _origin)
	_upload_frames()


## Rebuild the line from the anatomy mesh's local Y range. Called on attach, a mesh swap or a
## placement change; not per frame.
func rebuild() -> bool:
	_built = false
	_built_mesh_id = 0
	_line_count = 0
	_pose_ready = false
	_rest_local = PackedVector3Array()
	_live = PackedVector3Array()
	_leg_tips = PackedInt32Array()
	_leg_rests = PackedVector3Array()
	last_error = ""
	if not is_instance_valid(mesh) or not is_instance_valid(skeleton) \
			or not is_instance_valid(placement):
		last_error = "no anatomy mesh"
		return false
	var source := mesh.mesh as ArrayMesh
	if source == null or source.get_surface_count() != 1:
		last_error = "anatomy mesh is not one surface"
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
	_rest_local = GEOMETRY.coat_line_targets(y_min, y_max, LINE_SAMPLES)
	if _rest_local.size() < 2:
		last_error = "coat line samples collapse"
		return false
	_line_count = _rest_local.size()
	_live.resize(_line_count)
	for side: String in ["L", "R"]:
		var tip := -1
		for prefix: String in LEG_TIPS:
			tip = skeleton.find_bone(prefix + side)
			if tip >= 0:
				break
		if tip >= 0:
			_leg_tips.append(tip)
			_leg_rests.append(skeleton.get_bone_global_rest(tip).origin)
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
	material.set_shader_parameter("line_count", _line_count if _enabled else 0)


func _upload_frames() -> void:
	if not is_instance_valid(material):
		return
	_ensure_upload_arrays()
	material.set_shader_parameter("line_basis_x", _basis_x)
	material.set_shader_parameter("line_basis_y", _basis_y)
	material.set_shader_parameter("line_basis_z", _basis_z)
	material.set_shader_parameter("line_origin", _origin)
