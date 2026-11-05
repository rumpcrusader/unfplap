extends SkeletonModifier3D
## Prototype: pin the dock base ring to the tail-coat intersection P and rotate the dock about P
## by the tail base direction's change since the act started. This keeps the dock's rump end on
## the coat while its outer end follows the tail base rotation.

const TAIL_COAT_POINT := preload("res://mods/unfplap/tail_coat_point.gd")

const HIPS := "pony_hips"
const TAIL1 := "mTail1"
const TAIL2 := "mTail2"
## Minimum gap between full coat queries; the cached-triangle fast path runs every frame.
const RECHECK_S := 0.25

var mare: Node3D
var runtime: Node

var _dock: MeshInstance3D
var _dock_base := Transform3D.IDENTITY
var _anchor_local := Vector3.INF
var _body_sk: Skeleton3D
var _hips := -1
var _hips_bind := Transform3D.IDENTITY
var _tail1 := -1
var _tail2 := -1
var _pelvis := -1
var _root_local := Vector3.INF
var _tail_dir0 := Vector3.ZERO
var _point := Vector3.INF
var _last_triangle: Array = []
var _recheck_at := 0
var _active := false
var _near_was_enabled := false
var _near_disabled := false
var _start_logged := false
var _log_at := 0


func _exit_tree() -> void:
	_stop()


func restore() -> void:
	_stop()


func _process_modification_with_delta(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	_follow()
	_note("dock_follow", started)


func _follow() -> void:
	if not is_instance_valid(mare) or not is_instance_valid(runtime):
		return
	if not _start():
		return
	var matched := false
	if not _last_triangle.is_empty():
		var fast_started := Time.get_ticks_usec()
		matched = _take(TAIL_COAT_POINT.point_triangle(mare, _last_triangle))
		_note("dock_fast", fast_started)
	# The full query skins the cached coat patch and costs milliseconds, so it only runs when
	# the cached triangle missed and RECHECK_S has passed. Between queries the previous point
	# stands; the tail axis feeds rotation only, and the rotation itself still reads the live
	# bones every frame, so the dock never freezes.
	if not matched and Time.get_ticks_msec() >= _recheck_at:
		_recheck_at = Time.get_ticks_msec() + int(RECHECK_S * 1000.0)
		var full_started := Time.get_ticks_usec()
		_take(TAIL_COAT_POINT.point(mare))
		_note("dock_full", full_started)
	if not _point.is_finite():
		return
	if _tail_dir0.length_squared() < 0.0001:
		_tail_dir0 = _tail_direction_from(_point)
	var direction := _tail_direction_from(_point)
	if direction.length_squared() < 0.0001 or _tail_dir0.length_squared() < 0.0001:
		return
	var rotation := Basis.IDENTITY
	var axis := _tail_dir0.cross(direction)
	if axis.length_squared() > 0.000001:
		rotation = Basis(axis.normalized(), _tail_dir0.angle_to(direction))
	var hair := get_skeleton()
	if hair == null or _pelvis < 0:
		return
	var pelvis_pose := hair.get_bone_global_pose(_pelvis)
	var tip_target: Vector3 = hair.global_transform \
		* (pelvis_pose.origin + pelvis_pose.basis * _root_local)
	var parent := _dock.get_parent()
	if not parent is Node3D:
		return
	var base_world: Transform3D = (parent as Node3D).global_transform * _dock_base
	var hips_pose := _body_sk.get_bone_global_pose(_hips)
	var local_anchor: Vector3 = hips_pose * _hips_bind * _anchor_local
	var basis := rotation * base_world.basis
	_dock.global_transform = Transform3D(basis, tip_target - basis * local_anchor)
	if Time.get_ticks_msec() >= _log_at:
		_log_at = Time.get_ticks_msec() + 1000
		_log("dock tail-coat P=%s tip=%s dir=%s angle=%.3f" % [
			str(_point), str(tip_target), str(direction),
			rad_to_deg(rotation.get_rotation_quaternion().get_angle())])


func _take(result: Dictionary) -> bool:
	var hit: Variant = result.get("position", Vector3.INF)
	if not (hit is Vector3) or not (hit as Vector3).is_finite():
		return false
	_point = hit
	_last_triangle = result.get("triangle", [])
	return true


func _start() -> bool:
	if _active and is_instance_valid(_dock):
		return true
	_active = false
	_cache()
	if not is_instance_valid(_dock) or not is_instance_valid(_body_sk) \
			or _hips < 0 or _tail1 < 0 or _tail2 < 0 or _pelvis < 0 \
			or not _root_local.is_finite() or not _anchor_local.is_finite():
		if not _start_logged:
			_start_logged = true
			_log("dock tail-coat start failed dock=%s body=%s hips=%d tail=%d/%d tip=%s" % [
				str(is_instance_valid(_dock)), str(is_instance_valid(_body_sk)), _hips,
				_tail1, _tail2, str(_anchor_local)])
		_note("dock_start_fail", Time.get_ticks_usec())
		return false
	_dock_base = _dock.transform
	_point = Vector3.INF
	_last_triangle = []
	var result := TAIL_COAT_POINT.point(mare)
	var hit: Variant = result.get("position", Vector3.INF)
	if hit is Vector3 and (hit as Vector3).is_finite():
		_point = hit
		_last_triangle = result.get("triangle", [])
	_tail_dir0 = _tail_direction_from(_point) if _point.is_finite() else Vector3.ZERO
	_near_was_enabled = bool(mare.get("near_mesh_enabled"))
	if _near_was_enabled and mare.has_method("set_near_mesh"):
		mare.call("set_near_mesh", false)
		_near_disabled = true
	_active = true
	_recheck_at = Time.get_ticks_msec() + int(RECHECK_S * 1000.0)
	if not _start_logged:
		_start_logged = true
		_log("dock tail-coat start tip=%s dir=%s near=%s" % [
			str(_anchor_local), str(_tail_dir0), str(_near_disabled)])
	return true


func _cache() -> void:
	_dock = null
	_body_sk = null
	_hips = -1
	_hips_bind = Transform3D.IDENTITY
	_tail1 = -1
	_tail2 = -1
	_pelvis = -1
	_root_local = Vector3.INF
	_anchor_local = Vector3.INF
	if not is_instance_valid(mare):
		return
	_dock = mare.find_child("OpenPonyDock", true, false) as MeshInstance3D
	if is_instance_valid(_dock) and _dock.mesh != null:
		_anchor_local = _dock_tip(_dock.mesh)
	var skeleton: Variant = mare.get("skeleton")
	if skeleton is Skeleton3D:
		_body_sk = skeleton as Skeleton3D
		_hips = _body_sk.find_bone(HIPS)
	if _hips >= 0:
		_hips_bind = _body_bind()
	var hair := get_skeleton()
	if hair != null:
		_tail1 = hair.find_bone(TAIL1)
		_tail2 = hair.find_bone(TAIL2)
		_pelvis = hair.find_bone("mPelvis")
		_root_local = _tail_root_local(hair)


func _body_bind() -> Transform3D:
	var model: Variant = mare.get("_model")
	if not model is Node or not is_instance_valid(_body_sk):
		return Transform3D.IDENTITY
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.skin == null:
		return Transform3D.IDENTITY
	for i in body.skin.get_bind_count():
		var name := String(body.skin.get_bind_name(i))
		var bone := _body_sk.find_bone(name) if not name.is_empty() else body.skin.get_bind_bone(i)
		if bone == _hips:
			return body.skin.get_bind_pose(i)
	return Transform3D.IDENTITY


## The pinned tail root cap centre in the hair `mPelvis` bone's local space.
func _tail_root_local(hair: Skeleton3D) -> Vector3:
	var hair_node: Variant = mare.get("hair")
	var identity: Variant = mare.get("identity")
	if not hair_node is Node or identity == null:
		return Vector3.INF
	var prefix := String(identity.get("hair_prefix"))
	var tail := (hair_node as Node).find_child(prefix + "DevkitTail", true, false) as MeshInstance3D
	if not is_instance_valid(tail) or tail.mesh == null or tail.skin == null:
		return Vector3.INF
	var pelvis := hair.find_bone("mPelvis")
	if pelvis < 0:
		return Vector3.INF
	var bind := -1
	for i in tail.skin.get_bind_count():
		var name := String(tail.skin.get_bind_name(i))
		var bone := hair.find_bone(name) if not name.is_empty() else tail.skin.get_bind_bone(i)
		if bone == pelvis:
			bind = i
			break
	if bind < 0:
		return Vector3.INF
	var bind_pose := tail.skin.get_bind_pose(bind)
	var centre := Vector3.ZERO
	var count := 0
	for surface in tail.mesh.get_surface_count():
		var pinned: Variant = tail.mesh.get_meta("pinned_" + str(surface), PackedInt32Array())
		if not pinned is PackedInt32Array:
			continue
		var indices: PackedInt32Array = pinned
		if indices.is_empty():
			continue
		var arrays: Array = tail.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index: int in indices:
			if index >= 0 and index < vertices.size():
				centre += bind_pose * vertices[index]
				count += 1
	if count == 0:
		return Vector3.INF
	return centre / float(count)


func _tail_direction_from(point: Vector3) -> Vector3:
	var hair := get_skeleton()
	if hair == null or _tail2 < 0 or not point.is_finite():
		return Vector3.ZERO
	var tail2: Vector3 = hair.global_transform * hair.get_bone_global_pose(_tail2).origin
	return (tail2 - point).normalized()


func _ring_centre(mesh: Mesh) -> Vector3:
	var ring: Variant = mesh.get_meta("base_indices", PackedInt32Array())
	if not ring is PackedInt32Array:
		return Vector3.INF
	var indices: PackedInt32Array = ring
	if indices.is_empty():
		return Vector3.INF
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var centre := Vector3.ZERO
	for index: int in indices:
		if index >= 0 and index < vertices.size():
			centre += vertices[index]
	return centre / float(indices.size())


func _dock_tip(mesh: Mesh) -> Vector3:
	var centre := _ring_centre(mesh)
	if not centre.is_finite():
		return Vector3.INF
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tip := centre
	var far := 0.0
	for vertex: Vector3 in vertices:
		var distance := vertex.distance_to(centre)
		if distance > far:
			far = distance
			tip = vertex
	return tip


func _stop() -> void:
	if not _active:
		return
	_active = false
	if is_instance_valid(_dock):
		_dock.transform = _dock_base
	if _near_disabled:
		_near_disabled = false
		if is_instance_valid(mare) and mare.is_inside_tree() and mare.has_method("set_near_mesh"):
			_end_rump_jiggle()
			_clear_mark_twins()
			mare.call("set_near_mesh", _near_was_enabled)


func _end_rump_jiggle() -> void:
	if not is_instance_valid(mare):
		return
	var flank: Variant = mare.get_node_or_null("FlankTouch")
	if flank == null or not flank.has_method("_end_jiggle"):
		return
	var index: Variant = flank.get("_jiggle_index")
	if index != null and int(index) >= 0:
		flank.call("_end_jiggle")


func _clear_mark_twins() -> void:
	if not is_instance_valid(mare):
		return
	for mi_v: Variant in mare.find_children("*", "MeshInstance3D", true, false):
		if not mi_v is MeshInstance3D:
			continue
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null or not String(mi.name).begins_with("Cutie mark"):
			continue
		for si in mi.mesh.get_surface_count():
			var mat: Variant = mi.get_active_material(si)
			if mat is Material and (mat as Material).has_meta("jiggle_twin"):
				(mat as Material).remove_meta("jiggle_twin")


func _note(key: String, started: int) -> void:
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", key, Time.get_ticks_usec() - started)


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
