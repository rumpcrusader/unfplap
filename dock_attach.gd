extends SkeletonModifier3D
## CPU tail-cuff follower for the standard OpenPonyDock.
##
## The dock is a body-skinned mesh, not a second tail: its base belongs at the hair tail root and
## its outer end follows the first tail joint. This follower keeps the base on `mPelvis` and the
## outer end on `mTail1`, blending every dock vertex between them. It runs after the hair tail
## modifiers on the hair skeleton, so lift, aside, flick, tail lay and tail tuck all carry the
## dock with them. It never bridges body and tail, so sitting cannot stretch it.
##
## The dock is unskinned and its vertices are rewritten in the body skeleton's local space. The
## source mesh is 344 vertices, updated at 30 Hz only while the near mesh/dock is visible. An
## unchanged pelvis/tail pose skips the rebuild, which is most of the idle cost.

const DOCK_SEAT := preload("res://mods/unfplap/dock_seat.gd")
const UPDATE_DT := 1.0 / 30.0

var pony: Node3D
var dock: MeshInstance3D
var body: Skeleton3D
var hair: Skeleton3D
var rest_mesh: ArrayMesh
var dock_lift := 0.0

var _pelvis := -1
var _tail1 := -1
var _pelvis_rest_body := Transform3D.IDENTITY
var _tail_rest_body := Transform3D.IDENTITY
var _rest_vertices := PackedVector3Array()
var _rest_normals := PackedVector3Array()
var _rest_uv := PackedVector2Array()
var _rest_color := PackedColorArray()
var _rest_indices := PackedInt32Array()
var _rest_primitive := Mesh.PRIMITIVE_TRIANGLES
var _weights := PackedFloat32Array()
var _clock := 0.0
var _first := true
var _last_pelvis := Transform3D()
var _last_tail := Transform3D()
var _has_last := false
## Rolling counters, drained by the tail-seat perf summary.
var perf_updates := 0
var perf_skipped := 0
var perf_usec := 0
var perf_max_usec := 0
var perf_meshes := 0


func _ready() -> void:
	process_priority = 80
	_cache()
	_update()
	_first = false


func _process_modification_with_delta(delta: float) -> void:
	if not _ready_to_update():
		return
	_clock += delta
	if _clock < UPDATE_DT and not _first:
		return
	_clock = 0.0
	_first = false
	_update()


func _ready_to_update() -> bool:
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return false
	if not is_instance_valid(dock) or not dock.visible:
		return false
	if bool(pony.get("_far_mesh_shown")):
		return false
	return _pelvis >= 0 and _tail1 >= 0 and not _rest_vertices.is_empty()


func _cache() -> void:
	_pelvis = -1
	_tail1 = -1
	_rest_vertices = PackedVector3Array()
	if not is_instance_valid(pony) or not is_instance_valid(body) \
			or not is_instance_valid(hair) or rest_mesh == null:
		return
	_pelvis = hair.find_bone("mPelvis")
	_tail1 = hair.find_bone("mTail1")
	if _pelvis < 0 or _tail1 < 0:
		return
	_pelvis_rest_body = body.global_transform.affine_inverse() \
		* hair.global_transform * hair.get_bone_global_pose(_pelvis)
	_tail_rest_body = body.global_transform.affine_inverse() \
		* hair.global_transform * hair.get_bone_global_pose(_tail1)
	var arrays: Array = rest_mesh.surface_get_arrays(0).duplicate(true)
	_rest_vertices = arrays[Mesh.ARRAY_VERTEX]
	_rest_normals = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null \
		else PackedVector3Array()
	_rest_uv = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null \
		else PackedVector2Array()
	_rest_color = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null \
		else PackedColorArray()
	_rest_indices = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
		else PackedInt32Array()
	_rest_primitive = rest_mesh.surface_get_primitive_type(0)
	var ring: PackedInt32Array = rest_mesh.get_meta("base_indices", PackedInt32Array())
	if ring.is_empty() or _rest_vertices.is_empty():
		_rest_vertices = PackedVector3Array()
		return
	var base := Vector3.ZERO
	for index: int in ring:
		if index >= 0 and index < _rest_vertices.size():
			base += _rest_vertices[index]
	base /= float(ring.size())
	var tip := base
	var far := 0.0
	for vertex: Vector3 in _rest_vertices:
		var distance := vertex.distance_squared_to(base)
		if distance > far:
			far = distance
			tip = vertex
	var length := base.distance_to(tip)
	if length < 0.001:
		_rest_vertices = PackedVector3Array()
		return
	var axis := (tip - base) / length
	_weights.resize(_rest_vertices.size())
	for index in _rest_vertices.size():
		var along := clampf((_rest_vertices[index] - base).dot(axis) / length, 0.0, 1.0)
		_weights[index] = smoothstep(0.0, 1.0, along)
	for index: int in ring:
		if index >= 0 and index < _weights.size():
			_weights[index] = 0.0


func _update() -> void:
	if not _cache_ready():
		_has_last = false
		return
	var started := Time.get_ticks_usec()
	var into_body := body.global_transform.affine_inverse()
	var pelvis_current := into_body * hair.global_transform * hair.get_bone_global_pose(_pelvis)
	var tail_current := into_body * hair.global_transform * hair.get_bone_global_pose(_tail1)
	if _has_last and pelvis_current.is_equal_approx(_last_pelvis) \
			and tail_current.is_equal_approx(_last_tail):
		perf_skipped += 1
		return
	_has_last = true
	_last_pelvis = pelvis_current
	_last_tail = tail_current
	var pelvis_delta := pelvis_current * _pelvis_rest_body.affine_inverse()
	var tail_delta := tail_current * _tail_rest_body.affine_inverse()
	var offset := Vector3(0.0, dock_lift, 0.0)
	var vertices := PackedVector3Array()
	vertices.resize(_rest_vertices.size())
	for i in _rest_vertices.size():
		var rest := _rest_vertices[i]
		var on_root := pelvis_delta * rest
		var on_tail := tail_delta * rest
		vertices[i] = on_root.lerp(on_tail, _weights[i]) + offset
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = _rest_normals.duplicate()
	arrays[Mesh.ARRAY_TEX_UV] = _rest_uv
	if not _rest_color.is_empty():
		arrays[Mesh.ARRAY_COLOR] = _rest_color
	arrays[Mesh.ARRAY_INDEX] = _rest_indices
	DOCK_SEAT.recompute_normals(arrays)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(_rest_primitive, arrays)
	# Keep the dock metadata (`base_indices`, `pinned_*`) on the rebuilt mesh: the anatomy and
	# debug tools read it, and nested rebuilds (fit, snap, follow) all pass it along.
	for key: Variant in rest_mesh.get_meta_list():
		mesh.set_meta(key, rest_mesh.get_meta(key))
	dock.mesh = mesh
	perf_updates += 1
	perf_meshes += 1
	var elapsed := Time.get_ticks_usec() - started
	perf_usec += elapsed
	perf_max_usec = maxi(perf_max_usec, elapsed)


func _cache_ready() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(dock) or not is_instance_valid(body) \
			or not is_instance_valid(hair):
		return false
	return _pelvis >= 0 and _tail1 >= 0 and not _rest_vertices.is_empty()


## Drained by the tail-seat perf summary. Times are microseconds.
func take_perf() -> Dictionary:
	var out := {"updates": perf_updates, "skipped": perf_skipped, "usec": perf_usec,
		"max_usec": perf_max_usec, "meshes": perf_meshes}
	perf_updates = 0
	perf_skipped = 0
	perf_usec = 0
	perf_max_usec = 0
	perf_meshes = 0
	return out
