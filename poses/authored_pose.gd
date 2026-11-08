extends RefCounted
## The hand-authored missionary base pose, read from `poses/missionary_pose.json`.
##
## Every transform in the file is stored in **bed space**: the origin is the middle of the mattress
## top, the axes are the bed's own, and `+Z` is the direction her head points. The runtime maps that
## space onto the real bed, so the pose is independent of where a bed is, which way it faces and
## which bed it is.
##
## Only the body bones the act owns are written: hips, spine, neck, legs and arms. The head, lids,
## ears, wings, mane and tail stay with the game and the act (see `PONY_BONES` in the pose lab).
## The pose is blended by weight every frame from whatever the game's `lie_down` settle has put on
## the skeleton, so the act's POSING_IN ramp still eases her into it.
##
## Body bones are **rotated only**: their position is always the rig's own rest. The authored pose
## cannot lengthen a limb or displace a joint, and an asset that carries a stale position cannot
## stretch her. Only the skeleton root is placed (see `pony_frame`).

const PATH := "res://mods/unfplap/poses/missionary_pose.json"
## Version 4 stores bed-relative transforms; version 6 stores every body bone, including the ones
## left at rest, because the runtime writes only what the file holds.
const MIN_VERSION := 6

## True once a valid asset is parsed and `error` is empty.
var available := false
var error := ""
var version := 0
var bed_size := Vector3.ZERO
## Skeleton root placement in bed space, and the bed-relative Anon rig placement.
var pony_frame := Transform3D.IDENTITY
var anon_frame := Transform3D.IDENTITY
var anon_rig := ""
## Bone name -> {rotation: Quaternion, position: Vector3}, in the bone's parent space.
var pony_bones: Dictionary = {}
var anon_bones: Dictionary = {}
## Authored shot camera positions in bed space, keyed `start`, `back`, `front`, `left`, `right`.
## Only the origins are used: the act aims them at her live face and vulva.
var shots: Dictionary = {}
var has_shots := false

static var _shared: Variant = null
var _indices: Dictionary = {}
var _index_skeleton := 0


## The one parsed instance for the process.
static func shared() -> Variant:
	if _shared == null:
		_shared = load("res://mods/unfplap/poses/authored_pose.gd").new()
		_shared.call("load_file")
	return _shared


## Re-reads the file in place, so a live pose modifier sees the new pose at once. Returns "" or the
## reason the file could not be used.
static func reload_file() -> String:
	return str(shared().call("load_file"))


func load_file() -> String:
	available = false
	error = ""
	shots.clear()
	has_shots = false
	pony_bones.clear()
	anon_bones.clear()
	_indices.clear()
	_index_skeleton = 0
	if not FileAccess.file_exists(PATH):
		error = "no pose at %s" % PATH
		return error
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		error = "bad JSON in %s" % PATH
		return error
	var data: Dictionary = parsed
	version = int(data.get("version", 0))
	if version < MIN_VERSION:
		error = "pose version %d is older than %d" % [version, MIN_VERSION]
		return error
	var pony: Variant = data.get("pony")
	if not pony is Dictionary:
		error = "pose has no pony block"
		return error
	pony_frame = _transform((pony as Dictionary).get("transform", ""))
	pony_bones = _bones((pony as Dictionary).get("bones", {}))
	if pony_bones.is_empty():
		error = "pose has no pony bones"
		return error
	var anon: Variant = data.get("anon")
	if anon is Dictionary:
		anon_frame = _transform((anon as Dictionary).get("transform", ""))
		anon_bones = _bones((anon as Dictionary).get("bones", {}))
		anon_rig = str((anon as Dictionary).get("rig", ""))
	var bed: Variant = data.get("bed")
	if bed is Dictionary:
		bed_size = _vec((bed as Dictionary).get("size", ""))
	var raw_shots: Variant = data.get("shots")
	if raw_shots is Dictionary:
		for key: Variant in (raw_shots as Dictionary):
			var shot := _transform((raw_shots as Dictionary)[key])
			if shot.origin.is_finite():
				shots[str(key)] = shot
	has_shots = not shots.is_empty()
	available = true
	return ""


## True when the asset carries a position for this lean (`start`, `back`, `front`, `left`,
## `right`).
func has_shot(id: String) -> bool:
	return shots.has(id)


## Applies the base pose to the pony's skeleton. `weight` blends from the game's current pose
## (0) to the authored pose (1) and the caller ramps it; `bed_frame` is the real bed's pose space
## and `body_scale` scales the placement offset so a larger pony still rests on the mattress.
func apply_pony(sk: Skeleton3D, weight: float, bed_frame: Transform3D, body_scale: float) -> bool:
	if not available or sk == null:
		return false
	_cache_indices(sk)
	var root := root_bone(sk)
	if root >= 0:
		var wanted: Transform3D = bed_frame * _scaled(pony_frame, body_scale)
		var desired := sk.global_transform.affine_inverse() * wanted
		var current := sk.get_bone_global_pose(root)
		sk.set_bone_global_pose(root, current.interpolate_with(desired, weight))
	for key: Variant in _indices:
		var bone := int(_indices[key])
		var name := str(key)
		var entry: Dictionary = pony_bones[name]
		var rotation: Quaternion = entry["rotation"]
		# Rotate only. The rig's rest position is the only length a bone may have; a stored position
		# is informational (the exporter writes rest), never a stretch.
		sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone).slerp(rotation, weight))
		sk.set_bone_pose_position(bone,
			sk.get_bone_pose_position(bone).lerp(sk.get_bone_rest(bone).origin, weight))
	return true


## The skeleton's root bone (the armature), or -1.
static func root_bone(sk: Skeleton3D) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_parent(i) < 0:
			return i
	return -1


## Bone indices are stable for the life of the skeleton, so resolve the names once per skeleton.
func _cache_indices(sk: Skeleton3D) -> void:
	var id := sk.get_instance_id()
	if id == _index_skeleton and not _indices.is_empty():
		return
	_indices.clear()
	for key: Variant in pony_bones:
		var name := str(key)
		var bone := sk.find_bone(name)
		if bone >= 0:
			_indices[name] = bone
	_index_skeleton = id


## Scales only the placement distance, never the rotation: a bigger pony's body sits the same way
## on the mattress, higher above it by her own size.
func _scaled(value: Transform3D, body_scale: float) -> Transform3D:
	var out := value
	out.origin *= body_scale
	return out


func _bones(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key: Variant in (raw as Dictionary):
		var entry: Variant = (raw as Dictionary)[key]
		if not entry is Dictionary:
			continue
		out[str(key)] = {
			"rotation": _quat((entry as Dictionary).get("rotation", "")),
			"position": _vec((entry as Dictionary).get("position", "")),
		}
	return out


func _transform(raw: Variant) -> Transform3D:
	var parsed: Variant = str_to_var(str(raw))
	return parsed if parsed is Transform3D else Transform3D.IDENTITY


func _vec(raw: Variant) -> Vector3:
	var parsed: Variant = str_to_var(str(raw))
	return parsed if parsed is Vector3 else Vector3.ZERO


func _quat(raw: Variant) -> Quaternion:
	var parsed: Variant = str_to_var(str(raw))
	return (parsed as Quaternion).normalized() if parsed is Quaternion else Quaternion.IDENTITY
