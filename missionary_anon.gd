extends Node
## The act's Anon body: the game's own desktop `AnonBody`, placed in bed space and posed from the
## asset's `anon` block. He is a puppet for the act — his body IK and desktop pose driver are turned
## off and his bones are written at render time, exactly like the pony's, so nothing else on his rig
## wins. The act never moves his player node: only this body is placed on the bed.
##
## The asset carries every bone of his rig, so the file is the whole pose (see `poses/pose_lab.gd`).

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

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
	var placement: Transform3D = pose.get("anon_frame")
	placement.origin *= body_scale
	var placed: Transform3D = bed_frame * placement
	avatar.global_transform = Transform3D(placed.basis * Basis.from_scale(_scale), placed.origin)
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
