extends SkeletonModifier3D
## Keeps the dock attached to the tail instead of the rump. `tail_pose` applies a share of the
## tail's aside/lift to the hair pelvis, which is also what the game's tail anchor pins the
## hair root to. This follower reads that pelvis motion relative to the body hips (so body
## motion is not applied twice) and carries the dock with it. The rump shader jiggle stays on
## the dock, so the coat still ripples under it.
##
## The game's merged near mesh draws its own dock copy, so the acting pony shows her unmerged
## rig while this runs. The previous near-mesh state is restored when it stops or the act ends.

const PELVIS := "mPelvis"
const HIPS := "pony_hips"

var runtime: Node
var mare: Node3D

var _dock: MeshInstance3D
var _dock_base := Transform3D.IDENTITY
var _body_sk: Skeleton3D
var _pelvis := -1
var _hips := -1
var _baseline := Transform3D.IDENTITY
var _has_baseline := false
var _near_was_enabled := false
var _near_disabled := false
var _active := false
var _log_at := 0


func _ready() -> void:
	_cache()


func _exit_tree() -> void:
	_stop()


func restore() -> void:
	_stop()


func _cache() -> void:
	_pelvis = -1
	_hips = -1
	_body_sk = null
	var sk := get_skeleton()
	if sk != null:
		_pelvis = sk.find_bone(PELVIS)
	if is_instance_valid(mare):
		var body: Variant = mare.get("skeleton")
		if body is Skeleton3D:
			_body_sk = body as Skeleton3D
			_hips = _body_sk.find_bone(HIPS)


func _feature_on() -> bool:
	if is_instance_valid(runtime) and runtime.has_method("_feature"):
		return bool(runtime.call("_feature", "dock_tail_follow"))
	return false


## The hair pelvis in the body's hip frame. The hair link writes the pelvis from the body
## every update; the tail pose adds its base share on top. Taking the ratio to the hips removes
## the body motion the dock already follows.
func _pelvis_relative_to_hips() -> Transform3D:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(_body_sk) or _pelvis < 0 or _hips < 0:
		return Transform3D.IDENTITY
	var pelvis_body: Transform3D = _body_sk.global_transform.affine_inverse() \
		* (sk.global_transform * sk.get_bone_global_pose(_pelvis))
	var hips_pose: Transform3D = _body_sk.get_bone_global_pose(_hips)
	return hips_pose.affine_inverse() * pelvis_body


func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(mare) or not is_instance_valid(runtime):
		return
	if not _feature_on():
		_stop()
		return
	if not _start():
		return
	var rel := _pelvis_relative_to_hips()
	if not _has_baseline:
		_baseline = rel
		_has_baseline = true
	var motion := rel * _baseline.affine_inverse()
	var hips_world: Transform3D = _body_sk.global_transform * _body_sk.get_bone_global_pose(_hips)
	var world_motion := hips_world * motion * hips_world.affine_inverse()
	var parent := _dock.get_parent()
	if not is_instance_valid(parent) or not parent is Node3D:
		return
	# The dock already follows the body through its skin; this adds only the tail-base motion
	# relative to the body hips, so the dock and the pinned hair root share one transform.
	var base_world := (parent as Node3D).global_transform * _dock_base
	_dock.global_transform = world_motion * base_world
	if Time.get_ticks_msec() >= _log_at:
		_log_at = Time.get_ticks_msec() + 1000
		if runtime.has_method("_log"):
			var angle := rad_to_deg(motion.basis.get_rotation_quaternion().get_angle())
			runtime.call("_log", "dock tail base=%.1f deg shift=%.3f near=%s" % [
				angle, motion.origin.length(), str(not _near_disabled)])


func _start() -> bool:
	if _active and is_instance_valid(_dock):
		return true
	_active = false
	if not is_instance_valid(_body_sk) or _pelvis < 0 or _hips < 0:
		_cache()
	if not is_instance_valid(_body_sk) or _pelvis < 0 or _hips < 0:
		return false
	_dock = mare.find_child("OpenPonyDock", true, false) as MeshInstance3D
	if not is_instance_valid(_dock):
		return false
	_dock_base = _dock.transform
	_has_baseline = false
	_active = true
	_near_was_enabled = bool(mare.get("near_mesh_enabled"))
	if _near_was_enabled and mare.has_method("set_near_mesh"):
		mare.call("set_near_mesh", false)
		_near_disabled = true
	return true


func _stop() -> void:
	if not _active:
		return
	_active = false
	if is_instance_valid(_dock):
		_dock.transform = _dock_base
	_dock = null
	_has_baseline = false
	if _near_disabled:
		_near_disabled = false
		if is_instance_valid(mare) and mare.is_inside_tree() and mare.has_method("set_near_mesh"):
			# The base-game wobble swaps the cutie-mark material to its mark shader; the
			# near-mesh plan expects the original material and would reject the whole body
			# group. End the wobble and drop its cached twin metadata first so the reattach
			# succeeds.
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


## `pony_flank_touch._mark_twin()` caches its shader twin on the source material's metadata.
## `hybrid_near_mesh._same_material()` compares storage properties, metadata included, so one
## marked cutie material no longer matches its pair and the body group is refused on reattach.
## Dropping the cache is safe: the next wobble rebuilds the twin.
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
