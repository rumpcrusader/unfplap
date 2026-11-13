extends SkeletonModifier3D
## Sweep the spread standing wings slightly backwards around the pony's up axis. Runs after the
## game's WingTuck modifier, which owns the base wing pose.

var amount := 0.0
var angle_deg := 10.0
var _left := -1
var _right := -1


func setup(skeleton: Skeleton3D, degrees: float) -> void:
	angle_deg = degrees
	_left = skeleton.find_bone("pony_WingBase_L")
	_right = skeleton.find_bone("pony_WingBase_R")


func _process_modification_with_delta(_delta: float) -> void:
	if absf(amount) < 0.001:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var angle := deg_to_rad(angle_deg * amount)
	# Rotate the wing roots around the body up axis; opposite signs sweep both wings back.
	_sweep(skeleton, _left, -angle)
	_sweep(skeleton, _right, angle)


func _sweep(skeleton: Skeleton3D, bone: int, angle: float) -> void:
	if bone < 0:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(Vector3.UP, angle) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
