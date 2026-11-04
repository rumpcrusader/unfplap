extends SkeletonModifier3D
## Missionary lying-body response. The standing body_sway modifier is intentionally not reused:
## a pony on a bed slides a little along the mattress on each thrust and nods her head, instead
## of rocking her chest forward and back over planted hooves.

const SLIDE_M := 0.022
const SLIDE_STIFFNESS := 62.0
const SLIDE_DAMPING := 14.0
const NOD_DEG := 3.0
const NOD_STIFFNESS := 70.0
const NOD_DAMPING := 15.0
## Flip if the slide should follow the other end of the bed on a given body orientation.
const SLIDE_SIGN := -1.0

var mare: Node3D
var runtime: Node

var _spine := -1
var _base_local_origin := Vector3.ZERO
var _cached := false
var _slide := 0.0
var _slide_velocity := 0.0
var _nod := 0.0
var _nod_velocity := 0.0


func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(mare) or not is_instance_valid(runtime):
		return
	if int(runtime.get("state")) not in [2, 3]: # ACTIVE / CLIMAX
		return
	var depth_value: Variant = runtime.get("depth")
	if depth_value == null:
		return
	var depth := clampf(float(depth_value), 0.0, 1.0)
	var slide_target := SLIDE_SIGN * depth * SLIDE_M
	var slide_accel := -SLIDE_STIFFNESS * (_slide - slide_target) - SLIDE_DAMPING * _slide_velocity
	_slide_velocity += slide_accel * delta
	_slide += _slide_velocity * delta
	var nod_target := -deg_to_rad(NOD_DEG) * depth
	var nod_accel := -NOD_STIFFNESS * (_nod - nod_target) - NOD_DAMPING * _nod_velocity
	_nod_velocity += nod_accel * delta
	_nod += _nod_velocity * delta
	if absf(_slide) < 0.00001 and absf(_slide_velocity) < 0.00001 \
			and absf(_nod) < 0.00001 and absf(_nod_velocity) < 0.00001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if not _cached:
		_spine = sk.find_bone("pony_spine1")
		if _spine >= 0:
			_base_local_origin = sk.get_bone_pose(_spine).origin
		_cached = true
	if _spine < 0:
		return
	# The skeleton pose persists between frames; reset the spine origin before adding this
	# frame's slide, or the offset accumulates every modifier pass.
	var base := sk.get_bone_pose(_spine)
	base.origin = _base_local_origin
	sk.set_bone_pose(_spine, base)
	var forward := (sk.global_basis.inverse() * -mare.global_basis.z).normalized()
	if forward.length_squared() > 0.5:
		var body := sk.get_bone_global_pose(_spine)
		body.origin += forward * _slide
		sk.set_bone_global_pose(_spine, body)
	var right := (sk.global_basis.inverse() * mare.global_basis.x).normalized()
	if right.length_squared() < 0.5:
		return
	var neck := sk.find_bone("pony_neck2")
	var head := sk.find_bone("pony_head")
	if neck >= 0:
		var neck_pose := sk.get_bone_global_pose(neck)
		neck_pose.basis = Basis(right, _nod * 0.35) * neck_pose.basis
		sk.set_bone_global_pose(neck, neck_pose)
	if head >= 0:
		var head_pose := sk.get_bone_global_pose(head)
		head_pose.basis = Basis(right, _nod * 0.65) * head_pose.basis
		sk.set_bone_global_pose(head, head_pose)
