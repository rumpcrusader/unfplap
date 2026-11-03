extends SkeletonModifier3D
## EXPERIMENTAL (feature: ear_twitch). A small, eased ear twitch on a thrust, layered on top of the
## act's pinned ears. The shape is a short forward/back plus mirrored sideways flick of both ear
## roots, not a change of expression weight, so it cannot fight the fluster/line-face ear system.

const TWITCH_CHANCE := 0.22
const TWITCH_ANGLE := 0.20
const TWITCH_SIDE_RATIO_MIN := 0.30
const TWITCH_SIDE_RATIO_MAX := 0.60
const TWITCH_MIN_S := 0.18
const TWITCH_MAX_S := 0.48
const COOLDOWN_MIN_S := 0.45
const COOLDOWN_MAX_S := 1.80
const TWITCH_GAIN_MIN := 0.75
const TWITCH_GAIN_MAX := 1.15

var mare: Node3D

var _left := -1
var _right := -1
var _cached := false
var _time := -1.0
var _duration := 0.0
var _strength := 1.0
var _sign := 1.0
var _pitch_sign := 1.0
var _side_ratio := 0.45
var _left_gain := 1.0
var _right_gain := 1.0
var _cooldown := 0.0


func try_trigger(strength: float) -> void:
	if _time >= 0.0 or _cooldown > 0.0:
		return
	if randf() > TWITCH_CHANCE:
		return
	_time = 0.0
	_duration = randf_range(TWITCH_MIN_S, TWITCH_MAX_S)
	_strength = clampf(strength, 0.25, 1.0)
	# Side sign: +1 both ears outward, -1 both ears toward the head.
	_sign = 1.0 if randf() < 0.5 else -1.0
	_pitch_sign = 1.0 if randf() < 0.5 else -1.0
	_side_ratio = randf_range(TWITCH_SIDE_RATIO_MIN, TWITCH_SIDE_RATIO_MAX)
	_left_gain = randf_range(TWITCH_GAIN_MIN, TWITCH_GAIN_MAX)
	_right_gain = randf_range(TWITCH_GAIN_MIN, TWITCH_GAIN_MAX)
	_cooldown = randf_range(COOLDOWN_MIN_S, COOLDOWN_MAX_S)


func _process_modification_with_delta(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _time < 0.0:
		return
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _cached:
		_left = sk.find_bone("mFaceEar1Left")
		_right = sk.find_bone("mFaceEar1Right")
		_cached = true
	_time += delta
	if _time >= _duration:
		_time = -1.0
		return
	var envelope := sin(PI * _time / maxf(_duration, 0.01))
	var pitch_angle := TWITCH_ANGLE * _strength * envelope * _pitch_sign
	var side_magnitude := TWITCH_ANGLE * _strength * envelope * _side_ratio
	if absf(pitch_angle) < 0.00001 and side_magnitude < 0.00001:
		return
	var right_axis := sk.global_basis.x.normalized()
	var forward_axis := -sk.global_basis.z.normalized()
	if right_axis.length_squared() < 0.000001 or forward_axis.length_squared() < 0.000001:
		return
	var left_origin := sk.get_bone_global_pose(_left).origin if _left >= 0 else Vector3.ZERO
	var right_origin := sk.get_bone_global_pose(_right).origin if _right >= 0 else Vector3.ZERO
	var center := (left_origin + right_origin) * 0.5
	# Same forward/back flick on both ears. The side flick is derived per ear so both roots
	# move outward together or toward the head together, never both to the same world side.
	if _left >= 0:
		_twitch_side(sk, _left, right_axis, forward_axis, center, pitch_angle * _left_gain,
			side_magnitude * _left_gain, -1.0)
	if _right >= 0:
		_twitch_side(sk, _right, right_axis, forward_axis, center, pitch_angle * _right_gain,
			side_magnitude * _right_gain, 1.0)


func _twitch_side(sk: Skeleton3D, bone: int, right_axis: Vector3, forward_axis: Vector3,
		center: Vector3, pitch_angle: float, side_magnitude: float, fallback_side: float) -> void:
	var pose := sk.get_bone_global_pose(bone)
	var outward := signf((pose.origin - center).dot(right_axis))
	if is_zero_approx(outward):
		outward = fallback_side
	# `_sign` +1 means both ears outward; -1 means both toward the head.
	var target := right_axis * outward * _sign
	var turn_sign := signf(forward_axis.cross(pose.basis.y).dot(target))
	if is_zero_approx(turn_sign):
		turn_sign = outward * _sign
	_twitch(sk, bone, right_axis, forward_axis, pitch_angle, side_magnitude * turn_sign)


func _twitch(sk: Skeleton3D, bone: int, right_axis: Vector3, forward_axis: Vector3,
		pitch_angle: float, side_angle: float) -> void:
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(right_axis, pitch_angle) * Basis(forward_axis, side_angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)
