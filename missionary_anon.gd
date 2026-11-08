extends Node
## The act's Anon body: the game's own desktop `AnonBody`, placed in bed space and posed from the
## asset's `anon` block. He is a puppet for the act — his body IK and desktop pose driver are turned
## off and his bones are written at render time, exactly like the pony's, so nothing else on his rig
## wins. The act never moves his player node: only this body is placed on the bed.
##
## The asset carries every bone of his rig, so the file is the whole pose (see `poses/pose_lab.gd`).

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")

## The upper-body chain the lean bends, with the share of the lean each bone takes. Everything below
## the spine stays with the authored pose.
const LEAN_CHAIN := [["Spine", 0.20], ["Chest", 0.30], ["UpperChest", 0.20], ["Neck", 0.15],
	["Head", 0.15]]

var runtime: Node
var main: Variant
var avatar: Node3D
var skeleton: Skeleton3D
## True once a body was found and is being driven by this controller.
var active := false

var _body_ik: SkeletonModifier3D
var _body_ik_influence := 0.0
var _leg_hide: SkeletonModifier3D
var _leg_hide_influence := 0.0
var _driver: Variant
var _avatar_visible := true
var _avatar_process := Node.PROCESS_MODE_INHERIT
var _scale := Vector3.ONE
## The game's own eye offset relative to the head bone, captured before the act poses him, so the
## act camera sits exactly where the desktop camera does for this body.
var _eye_rel := Transform3D.IDENTITY
var _eye_saved := false
var _indices: Dictionary = {}
var _index_skeleton := 0


func install(runtime_node: Node) -> bool:
	runtime = runtime_node
	main = runtime.get("main") if is_instance_valid(runtime) else null
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return false
	avatar = main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return false
	skeleton = avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(skeleton):
		return false
	_avatar_visible = avatar.visible
	_avatar_process = avatar.process_mode
	_scale = avatar.scale
	# His own drivers: the desktop pose driver poses the torso and the body IK the limbs. Both are
	# parked for the act; the pose we write is the only pose.
	_driver = avatar.get("desktop_pose_driver")
	avatar.set("desktop_pose_driver", null)
	var ik: Variant = avatar.get("_body_ik")
	if not is_instance_valid(ik):
		ik = avatar.find_child("BodyIK", true, false)
	if ik is SkeletonModifier3D:
		_body_ik = ik as SkeletonModifier3D
		_body_ik_influence = _body_ik.influence
		_body_ik.influence = 0.0
	var legs: Variant = avatar.get("_leg_hide")
	if not is_instance_valid(legs):
		legs = avatar.find_child("LegHide", true, false)
	if legs is SkeletonModifier3D:
		_leg_hide = legs as SkeletonModifier3D
		_leg_hide_influence = _leg_hide.influence
		_leg_hide.influence = 0.0
	# The desktop camera relative to the head bone, taken from the game's own body before the act
	# moves anything. The act camera then follows the posed head rigidly.
	var head := skeleton.find_bone("Head")
	var camera: Variant = main.camera() if is_instance_valid(main) else null
	if head >= 0 and camera is Camera3D:
		_eye_rel = (skeleton.global_transform * skeleton.get_bone_global_pose(head)).affine_inverse() \
			* (camera as Camera3D).global_transform
		_eye_saved = true
	avatar.visible = true
	active = true
	return true


func remove() -> void:
	active = false
	if is_instance_valid(_body_ik):
		_body_ik.influence = _body_ik_influence
	if is_instance_valid(_leg_hide):
		_leg_hide.influence = _leg_hide_influence
	if is_instance_valid(avatar):
		avatar.set("desktop_pose_driver", _driver)
		avatar.visible = _avatar_visible
		avatar.process_mode = _avatar_process
	_body_ik = null
	_leg_hide = null
	avatar = null
	skeleton = null
	_indices.clear()
	_index_skeleton = 0


## Place and pose him from the asset, once per displayed frame.
func apply(bed_frame: Transform3D, body_scale: float) -> void:
	if not active or not is_instance_valid(avatar) or not is_instance_valid(skeleton):
		return
	var pose: Variant = AUTHORED.shared()
	if not bool(pose.get("available")):
		return
	# His body's path is authored as two bed-space placements (`anon.travel`): pulled out and fully
	# in. Without them he sits at the authored neutral placement and the alignment below supplies the
	# whole stroke on its own.
	var placement: Transform3D = pose.get("anon_frame")
	if pose.has_method("travel_at"):
		var travel: Variant = pose.call("travel_at", _depth())
		if travel is Transform3D:
			placement = travel
	placement.origin *= body_scale
	var placed: Transform3D = bed_frame * placement
	# The attached alignment asks for the pelvis offset that puts the shaft in her. The part is a
	# child of his Hips bone, so moving his body moves the part with it.
	var offset := _hip_offset()
	placed.origin += offset
	avatar.global_transform = Transform3D(placed.basis * Basis.from_scale(_scale), placed.origin)
	_note_hip_offset(offset)
	_apply_lean(placed)
	# The presentation parks the body every tick (invisible, processing off); the act needs it shown
	# and its skeleton updating, and its own IK/driver are already neutralised.
	if not avatar.visible:
		avatar.visible = true
	if avatar.process_mode != Node.PROCESS_MODE_INHERIT:
		avatar.process_mode = Node.PROCESS_MODE_INHERIT
	var bones: Dictionary = pose.get("anon_bones")
	if bones.is_empty():
		return
	_cache_indices(bones)
	for key: Variant in _indices:
		var entry: Variant = bones.get(key)
		if not (entry is Dictionary):
			continue
		var bone := int(_indices[key])
		skeleton.set_bone_pose_rotation(bone, (entry as Dictionary)["rotation"])
		skeleton.set_bone_pose_position(bone, (entry as Dictionary)["position"])


## Bend his chest and neck with the act's lean, leaving his hips and legs on the authored pose. The
## view is his head, so this is what makes leaning move the camera.
func _apply_lean(placed: Transform3D) -> void:
	if not is_instance_valid(runtime) or not is_instance_valid(skeleton):
		return
	var forward: Variant = runtime.call("shot_lean_forward")
	var side: Variant = runtime.get("_lean_view_side")
	var lean_forward := float(forward) if forward is float or forward is int else 0.0
	var lean_side := float(side) if side is float or side is int else 0.0
	if absf(lean_forward) < 0.001 and absf(lean_side) < 0.001:
		return
	var scale: Variant = runtime.call("_lean_size_scale")
	var lean_scale := float(scale) if scale is float or scale is int else 1.0
	# His body is lying, so the nod and the turn are the bed's own axes: nod along the mattress,
	# turn about the mattress normal. Both are converted into skeleton space once.
	var to_sk := skeleton.global_basis.inverse()
	var nod := (to_sk * placed.basis.x).normalized()
	var turn := (to_sk * placed.basis.y).normalized()
	var pitch := -deg_to_rad(MOTION.LEAN_PITCH_DEG * 3.0) * lean_forward * lean_scale
	var yaw := -deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG * 4.0) * lean_side * lean_scale
	for entry: Array in LEAN_CHAIN:
		var bone := skeleton.find_bone(str(entry[0]))
		if bone < 0:
			continue
		var share := float(entry[1])
		var rotated := skeleton.get_bone_pose_rotation(bone)
		rotated = Quaternion(nod, pitch * share) * rotated
		rotated = Quaternion(turn, yaw * share) * rotated
		skeleton.set_bone_pose_rotation(bone, rotated.normalized())


## The act camera's transform: his posed head plus the game's own eye offset.
func eye_transform() -> Variant:
	if not active or not is_instance_valid(skeleton):
		return null
	var head := skeleton.find_bone("Head")
	if head < 0:
		return null
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
	if not _eye_saved:
		return head_world
	return head_world * _eye_rel


## The act's depth, 0 (pulled out) to 1 (full).
func _depth() -> float:
	var value: Variant = runtime.get("depth") if is_instance_valid(runtime) else null
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else 0.0


## The pelvis offset the attached alignment asked for this frame, in world space.
func _hip_offset() -> Vector3:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if part == null or not bool(part.call("showing")):
		return Vector3.ZERO
	var wanted: Variant = part.call("hip_offset_wanted")
	if wanted is Vector3 and (wanted as Vector3).is_finite():
		return wanted
	return Vector3.ZERO


## Tell the part the offset was applied, so next frame it measures from the moved body.
func _note_hip_offset(offset: Vector3) -> void:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if part != null and bool(part.call("showing")):
		part.set("hip_offset_applied", offset)


## Bone indices are stable for the life of the skeleton, so resolve the names once per skeleton.
func _cache_indices(bones: Dictionary) -> void:
	var id := skeleton.get_instance_id()
	if id == _index_skeleton and not _indices.is_empty():
		return
	_indices.clear()
	for key: Variant in bones:
		var bone := skeleton.find_bone(str(key))
		if bone >= 0:
			_indices[str(key)] = bone
	_index_skeleton = id
