extends SkeletonModifier3D
## Debug-only head pitch for Alt+7 / Alt+8. Applied after the normal game or act pose, so the
## chin key works while standing, lying, or during the act. It only rotates `pony_head`.

var mare: Node3D
var chin_deg := 0.0

var _bone := -1
var _cached := false


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare) or absf(chin_deg) < 0.0001:
		return
	if not _cached:
		_bone = sk.find_bone("pony_head")
		_cached = true
	if _bone < 0:
		return
	var right := (sk.global_basis.inverse() * mare.global_basis.x).normalized()
	if right.length_squared() < 0.000001:
		return
	var pose := sk.get_bone_global_pose(_bone)
	pose.basis = Basis(right, deg_to_rad(chin_deg)) * pose.basis
	sk.set_bone_global_pose(_bone, pose)
