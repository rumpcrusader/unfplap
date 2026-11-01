extends SkeletonModifier3D
## Post-sex body language: lower head and tail for a short while after the act. Rotations only.

var pony: Node3D
var mode := "body"
var amount := 0.0
var target_amount := 1.0

var _neck: Array[int] = []
var _tail: Array[int] = []
var _cached := false


func _cache() -> void:
	_cached = true
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(pony):
		return
	_neck.clear()
	for name: String in ["pony_neck1", "pony_neck2", "pony_head"]:
		var bone := sk.find_bone(name)
		if bone >= 0:
			_neck.append(bone)
	_tail.clear()
	for i: int in range(1, 7):
		var bone := sk.find_bone("mTail%d" % i)
		if bone >= 0:
			_tail.append(bone)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(pony):
		return
	if not _cached:
		_cache()
	amount = move_toward(amount, target_amount, delta / 0.5)
	if amount <= 0.001:
		return
	var weight := smoothstep(0.0, 1.0, amount)
	if mode == "body":
		_head_down(sk, weight)
	else:
		_tail_down(sk, weight)


func _head_down(sk: Skeleton3D, weight: float) -> void:
	var right := (sk.global_basis.inverse() * pony.global_basis.x).normalized()
	var angles: Array[float] = [-0.38, -0.30, -0.20]
	for i: int in _neck.size():
		_rotate(sk, _neck[i], right, angles[mini(i, angles.size() - 1)] * weight)
	# Lift the face a little so she is not staring at the floor while the neck reaches forward.
	if not _neck.is_empty():
		_rotate(sk, _neck[_neck.size() - 1], right, 0.18 * weight)


## Tuck the tail down and forward between the hind legs, and straighten the chain toward that
## same direction instead of merely lowering the highest point.
func _tail_down(sk: Skeleton3D, weight: float) -> void:
	if _tail.is_empty():
		return
	var up := (sk.global_basis.inverse() * pony.global_basis.y).normalized()
	var forward := (sk.global_basis.inverse() * -pony.global_basis.z).normalized()
	var target := (-up + forward * 0.2).normalized()
	if target.length_squared() < 0.001:
		return
	var base_direction := target
	for i: int in _tail.size():
		var bone := _tail[i]
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if i + 1 < _tail.size():
			direction = sk.get_bone_global_pose(_tail[i + 1]).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		# Only the base gets the tuck angle; the rest align to that new base so the tail
		# straightens instead of curling hard toward the floor.
		var wanted := target if i == 0 else base_direction
		var axis := direction.cross(wanted)
		if axis.length_squared() < 0.0001:
			continue
		var angle := direction.angle_to(wanted) * weight
		if i == 0:
			angle = minf(angle, 0.9)
		else:
			angle *= 0.8
		pose.basis = Basis(axis.normalized(), angle) * pose.basis
		sk.set_bone_global_pose(bone, pose)
		if i == 0:
			base_direction = (Basis(axis.normalized(), angle) * direction).normalized()


func _rotate(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)
