extends SkeletonModifier3D
## Missionary: lay the hair tail flat on the mattress and straighten it. The tail is not part of
## the authored body pose because every pony's tail rig differs; this runs on the hair skeleton
## after the game's own tail motion and uses whichever `mTail1..6` bones exist.
##
## The root is left where the rig put it; only the chain is turned onto the bed plane. The target
## follows the authored bed frame, so the tail lies toward her rump on any bed orientation.

const FADE_SECONDS := 0.5
const BONE_NAMES := ["mTail1", "mTail2", "mTail3", "mTail4", "mTail5", "mTail6"]
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")

var mare: Node3D
var runtime: Node
var amount := 0.0
var target_amount := 1.0

var _bones: Array[int] = []
var _cached := false


func _ready() -> void:
	_cache()


func _cache() -> void:
	_cached = true
	_bones.clear()
	var sk := get_skeleton()
	if sk == null:
		return
	for name: String in BONE_NAMES:
		var bone := sk.find_bone(name)
		if bone >= 0:
			_bones.append(bone)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _cached:
		_cache()
	if _bones.is_empty():
		return
	if amount <= 0.0 and target_amount <= 0.0:
		return
	amount = move_toward(amount, target_amount, delta / maxf(FADE_SECONDS, 0.01))
	if amount <= 0.001:
		return
	var world_back := Vector3.ZERO
	var frame: Variant = runtime.get("_bed_pose_frame") if is_instance_valid(runtime) else null
	if frame is Transform3D:
		world_back = -(frame as Transform3D).basis.z
	else:
		world_back = -mare.global_basis.z
	world_back.y = 0.0
	if world_back.length_squared() < 0.000001:
		return
	world_back = world_back.normalized()
	var to_sk := sk.global_transform.affine_inverse()
	var target := (to_sk.basis * world_back).normalized()
	var weight := smoothstep(0.0, 1.0, amount)
	for i: int in _bones.size():
		var bone := _bones[i]
		var pose := sk.get_bone_global_pose(bone)
		var direction: Vector3
		if i + 1 < _bones.size():
			direction = sk.get_bone_global_pose(_bones[i + 1]).origin - pose.origin
		else:
			direction = pose.basis.z
		if direction.length_squared() < 0.000001:
			continue
		var turn := Quaternion(direction.normalized(), target)
		pose.basis = Basis(Quaternion.IDENTITY.slerp(turn, weight)) * pose.basis
		RIG.set_global(sk, bone, pose)
