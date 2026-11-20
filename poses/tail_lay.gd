extends SkeletonModifier3D
## Missionary: lay the visible tail flat on the mattress and straighten it, on whichever chain the
## skeleton owns. The tail stays out of the authored pose because tail rigs differ. The chain turns
## onto the bed plane and its root is never moved.
## Contract: `docs/poses.md`.

const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const FADE_SECONDS := 0.5
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")

var mare: Node3D
## The typed act view: the live bed frame. Absent outside a missionary act.
var facts: Variant
var amount := 0.0
var target_amount := 1.0

var _bones: Array[int] = []
var _saved: Dictionary = {}
var _cached := false
## A tail living off the game skeletons: its own root is turned and restored instead.
var _root: Node3D
var _root_saved := Transform3D.IDENTITY
var _root_direction := Vector3.BACK
var _root_ready := false
var _hook_family := ""
var _hook_profile := ""
var _hook_seen := false


## The pose-change hook: a shared keep leaves the chain, the saved bones and the fade alone. A
## family/profile change only resets the hook cache; the service restores the bones before a remove.
func pose_changed(view: Variant) -> void:
	if view == null:
		return
	var family := str(view.family)
	var modifiers_value: Variant = view.modifiers
	var profile := ""
	if modifiers_value is Dictionary:
		profile = str((modifiers_value as Dictionary).get("profile", ""))
	if _hook_seen and family == _hook_family and profile == _hook_profile:
		return
	_hook_seen = true
	_hook_family = family
	_hook_profile = profile


func _ready() -> void:
	_cache()


func _cache() -> void:
	_cached = true
	_bones.clear()
	_root = TAIL_CHAIN.custom_root(mare)
	_root_ready = is_instance_valid(_root)
	if _root_ready:
		_root_saved = _root.transform
		_root_direction = TAIL_CHAIN.root_direction(_root)
	var sk := get_skeleton()
	if sk == null:
		return
	var found: Dictionary = TAIL_CHAIN.chain(sk)
	var chain_bones: Variant = found.get("bones", [])
	for value: Variant in chain_bones:
		var bone := int(value)
		_bones.append(bone)
		if not _saved.has(bone):
			_saved[bone] = sk.get_bone_pose(bone)


## Hand the tail chain back as the game left it before the act; its own motion resumes next frame.
func restore_tail() -> void:
	var sk := get_skeleton()
	if sk != null:
		for bone: Variant in _saved:
			sk.set_bone_pose(int(bone), _saved[bone])
	if _root_ready and is_instance_valid(_root):
		_root.transform = _root_saved
		_root_ready = false


func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(mare):
		return
	if not _cached:
		_cache()
	if _root_ready and not is_instance_valid(_root):
		_root_ready = false
	if _bones.is_empty() and not _root_ready:
		return
	if amount <= 0.0 and target_amount <= 0.0:
		return
	amount = move_toward(amount, target_amount, delta / maxf(FADE_SECONDS, 0.01))
	if amount <= 0.001:
		return
	var world_back := Vector3.ZERO
	var frame: Variant = facts.bed_frame if facts != null else null
	if frame is Transform3D:
		world_back = -(frame as Transform3D).basis.z
	else:
		world_back = -mare.global_basis.z
	world_back.y = 0.0
	if world_back.length_squared() < 0.000001:
		return
	world_back = world_back.normalized()
	var weight := smoothstep(0.0, 1.0, amount)
	if _root_ready and is_instance_valid(_root):
		_lay_root(weight, world_back)
		return
	var sk := get_skeleton()
	if sk == null:
		return
	var to_sk := sk.global_transform.affine_inverse()
	var target := (to_sk.basis * world_back).normalized()
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


## Turn a custom tail root toward the bed frame, the same target the bone path uses.
func _lay_root(weight: float, world_back: Vector3) -> void:
	var parent := _root.get_parent() as Node3D
	var parent_basis := Basis.IDENTITY
	if is_instance_valid(parent):
		parent_basis = parent.global_transform.basis
	var direction := (_root_saved.basis * _root_direction).normalized()
	var target := (parent_basis.inverse() * world_back).normalized()
	if direction.length_squared() < 0.000001 or target.length_squared() < 0.000001:
		return
	var turn := Quaternion(direction, target)
	var rotation := Basis(Quaternion.IDENTITY.slerp(turn, weight))
	_root.transform = Transform3D(rotation * _root_saved.basis, _root_saved.origin)
