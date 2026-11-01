extends SkeletonModifier3D
## Post-sex body language: lower head and tail for a short while after the act. Rotations only.

var pony: Node3D
var mode := "body"
var amount := 0.0
var target_amount := 1.0

var _neck: Array[int] = []
var _tail: Array[int] = []
var _cached := false
var _tail_logged := false


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


## Lower the tail in aftercare: the whole chain (including the base) angles down and slightly back.
## No between-the-legs tuck. Logs the base direction once so a missing/angled base is visible.
func _tail_down(sk: Skeleton3D, weight: float) -> void:
	if _tail.is_empty():
		return
	var up := (sk.global_basis.inverse() * pony.global_basis.y).normalized()
	var back := (sk.global_basis.inverse() * pony.global_basis.z).normalized()
	var target := (-up + back * 0.20).normalized()
	if target.length_squared() < 0.001:
		return
	var base_before := sk.get_bone_global_pose(_tail[0]).basis.z
	for i: int in _tail.size():
		var bone := _tail[i]
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if i + 1 < _tail.size():
			direction = sk.get_bone_global_pose(_tail[i + 1]).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var axis := direction.cross(target)
		if axis.length_squared() < 0.0001:
			continue
		var angle := direction.angle_to(target) * weight
		pose.basis = Basis(axis.normalized(), angle) * pose.basis
		sk.set_bone_global_pose(bone, pose)
	if not _tail_logged and weight > 0.5:
		_tail_logged = true
		var base_after := sk.get_bone_global_pose(_tail[0]).basis.z
		print("[unfplap] aftercare tail bones=%d base before=%s after=%s target=%s angle=%.1f°" % [
			_tail.size(), str(base_before), str(base_after), str(target),
			rad_to_deg(base_before.normalized().angle_to(target))])


func _rotate(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)
