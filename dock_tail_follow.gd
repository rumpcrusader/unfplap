extends SkeletonModifier3D
## Keeps the dock attached to the tail instead of the rump. The hair tail root (`mTail1`) is
## compared with its act-start baseline and the difference rotates `OpenPonyDock` about the tail
## root. The rump shader jiggle stays on the dock, so the coat still ripples under it.
##
## The game's merged near mesh draws its own dock copy, so the acting pony shows her unmerged rig
## while this runs. The previous near-mesh state is restored when it stops or the act ends.

const PELVIS := "mPelvis"
const TAIL_ROOT := "mTail1"

var runtime: Node
var mare: Node3D

var _dock: MeshInstance3D
var _dock_base := Transform3D.IDENTITY
var _pelvis := -1
var _tail_root := -1
var _baseline := Transform3D.IDENTITY
var _has_baseline := false
var _near_was_enabled := false
var _near_disabled := false
var _active := false


func _ready() -> void:
	_cache()


func _exit_tree() -> void:
	_stop()


func restore() -> void:
	_stop()


func _cache() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_pelvis = sk.find_bone(PELVIS)
	_tail_root = sk.find_bone(TAIL_ROOT)


func _feature_on() -> bool:
	if is_instance_valid(runtime) and runtime.has_method("_feature"):
		return bool(runtime.call("_feature", "dock_tail_follow"))
	return false


func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(mare) or not is_instance_valid(runtime):
		return
	if not _feature_on():
		_stop()
		return
	if not _start():
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _pelvis < 0 or _tail_root < 0:
		_cache()
		if _pelvis < 0 or _tail_root < 0:
			return
	var pelvis_pose := sk.get_bone_global_pose(_pelvis)
	var tail_pose := sk.get_bone_global_pose(_tail_root)
	# Tail pose in pelvis space. The act-start baseline removes the authored mount offset and
	# keeps the dock aligned to its own rest; only motion after the act starts moves it.
	var rel := pelvis_pose.affine_inverse() * tail_pose
	if not _has_baseline:
		_baseline = rel
		_has_baseline = true
	var delta := rel * _baseline.affine_inverse()
	var pelvis_basis := pelvis_pose.basis.orthonormalized()
	var skel_basis := sk.global_transform.basis.orthonormalized()
	var delta_world := skel_basis * pelvis_basis * delta.basis \
		* pelvis_basis.inverse() * skel_basis.inverse()
	var pivot := sk.global_transform * tail_pose.origin
	var parent := _dock.get_parent()
	if not is_instance_valid(parent) or not parent is Node3D:
		return
	# Rotate the dock's normal frame about the tail root. The Hips base bob is excluded because
	# it cancels between the pelvis and the tail root; the dock's rump end stays seated.
	var base_world := (parent as Node3D).global_transform * _dock_base
	_dock.global_transform = Transform3D(delta_world, pivot) \
		* Transform3D(Basis.IDENTITY, -pivot) * base_world


func _start() -> bool:
	if _active and is_instance_valid(_dock):
		return true
	_active = false
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
