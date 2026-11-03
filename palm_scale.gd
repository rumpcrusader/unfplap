extends SkeletonModifier3D
## Pose-2 presentation: shrink the visible hands by scaling the hand bones themselves.
## Scaling a presentation marker would be discarded by `valve_body_ik.gd`, which orthonormalizes
## the hand target before writing the bone. The hand bone includes the palm and every finger.
##
## This modifier is added after the stock BodyIK modifier, caches the hand scales it finds, and
## restores them when the act ends.

const HAND_BONES := ["LeftHand", "RightHand"]

var skeleton: Skeleton3D
var factor := 1.0

var _bones: Array[int] = []
var _original: Array[Vector3] = []
var _cached := false


func _ready() -> void:
	if skeleton == null:
		skeleton = get_parent() as Skeleton3D
	process_priority = 10


func _process_modification() -> void:
	apply_scale()


func apply_scale() -> void:
	_ensure_cache()
	if skeleton == null:
		return
	for index: int in _bones.size():
		skeleton.set_bone_pose_scale(_bones[index], _original[index] * factor)


func restore() -> void:
	_ensure_cache()
	if skeleton == null:
		return
	for index: int in _bones.size():
		skeleton.set_bone_pose_scale(_bones[index], _original[index])


func _ensure_cache() -> void:
	if _cached:
		return
	_cached = true
	if skeleton == null:
		skeleton = get_skeleton()
	if skeleton == null:
		skeleton = get_parent() as Skeleton3D
	if skeleton == null:
		return
	for name: String in HAND_BONES:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			_bones.append(bone)
			_original.append(skeleton.get_bone_pose_scale(bone))
