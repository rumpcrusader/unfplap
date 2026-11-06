extends RefCounted
## Missionary (Missionary) skeleton recipe. Order is load-bearing; see ROTATION.md.

const ROT := preload("res://mods/unfplap/poses/rotation.gd")

const MISSIONARY_HIND_SPREAD := 0.42
const MISSIONARY_RUMP_DROP_DEG := 35.0
const MISSIONARY_NUZZLE_SCALE := 0.45
const NUZZLE_PERIOD := 7.0
const NUZZLE_DURATION := 2.4
const MISSIONARY_ROLL_TWEAK := 0.0
## integration: the bed finish pose, ported from the fork's missionary additions.
const WRAP_OUT := 0.85
const WRAP_UP := 0.25
const WRAP_BACK := 0.35
const WRAP_KNEE := 0.9
const CURL_SHARES: Array[float] = [0.5, 0.3, 0.2]
const RUMP_LEVER_M := 0.45
## Extra neck lift off the mattress before the gaze solve. In the standing model this is the
## chin-down direction; the supine body turns it into an upward head lift.
const MISSIONARY_NECK_LIFT_DEG := 15.0

var last_roll := 0.0
var last_chest_roll := 0.0
var _config: Dictionary = {}


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	_roll_root(rig, sk, PI * weight)
	_lift_root(rig, sk, weight, _value("bed_lift_m", 0.05))
	_straighten_spine_neck(rig, sk, weight)
	_align_chain_straight(rig, sk, weight)
	_level_body_roll(rig, sk, weight)
	_level_chest_roll(rig, sk, weight)
	# integration: her rump rises as she moves, and an optional pelvic curl fixes the bed angle.
	_pitch_body_about_shoulders(rig, sk, weight,
		_value("rump_drop_deg", MISSIONARY_RUMP_DROP_DEG)
		- rad_to_deg(_value("rump_rise_m", 0.0) / RUMP_LEVER_M))
	_curl_pelvis(rig, sk, weight, _value("pelvis_curl_deg", 0.0))
	_bend_forelegs(rig, sk, weight, 0.3)
	_raise_hind_legs(rig, sk, weight)
	_hug_forelegs(rig, sk, weight)
	var lift := _value("neck_lift_deg", MISSIONARY_NECK_LIFT_DEG)
	_neck_bend(rig, sk, weight,
		_value("neck1_deg", lift * 0.5), _value("neck2_deg", lift * 0.5))
	_neck_roll(rig, sk, weight, _value("neck_roll_deg", 0.0))
	var pulse := 1.0 if bool(state.get("climaxing", false)) else _nuzzle_pulse(float(state.get("clock", 0.0)))
	if bool(state.get("climaxing", false)):
		pulse = 0.75 + 0.25 * sin(float(state.get("clock", 0.0)) * 4.0)
	var look_point: Vector3 = state.get("look_point", Vector3.ZERO)
	if pulse > 0.001 and look_point.is_finite():
		look_point = _nuzzle_look_point(rig, sk, look_point, pulse)
	_aim_gaze(rig, sk, weight, look_point)
	_head_pitch(rig, sk, weight, _value("head_pitch_deg", 0.0))
	_roll_head(rig, sk, weight, float(state.get("head_roll", 0.0)))


func _roll_root(rig, sk: Skeleton3D, angle: float) -> void:
	if rig.root < 0 or rig.hips < 0 or absf(angle) < 0.0001:
		return
	var axis: Vector3 = rig.forward_axis(sk)
	var pivot := sk.get_bone_global_pose(rig.hips).origin
	var pose := sk.get_bone_global_pose(rig.root)
	pose.origin = pivot + Basis(axis, angle) * (pose.origin - pivot)
	pose.basis = Basis(axis, angle) * pose.basis
	pose.origin += rig.up_axis(sk) * (0.03 * absf(angle))
	sk.set_bone_global_pose(rig.root, pose)


func _lift_root(rig, sk: Skeleton3D, weight: float, metres: float) -> void:
	if rig.root < 0:
		return
	var pose := sk.get_bone_global_pose(rig.root)
	pose.origin += rig.up_axis(sk) * metres * weight
	sk.set_bone_global_pose(rig.root, pose)


## integration: tips her pelvis up toward him, with the spine taking the turn back.
func _curl_pelvis(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	var angle := deg_to_rad(degrees) * weight
	if rig.hips < 0 or absf(angle) < 0.0001:
		return
	var right: Vector3 = rig.right_axis(sk)
	var pose := sk.get_bone_global_pose(rig.hips)
	pose.basis = Basis(right, -angle) * pose.basis
	sk.set_bone_global_pose(rig.hips, pose)
	for i: int in mini(rig.spine.size(), CURL_SHARES.size()):
		var bone: int = rig.spine[i]
		pose = sk.get_bone_global_pose(bone)
		pose.basis = Basis(right, angle * CURL_SHARES[i]) * pose.basis
		sk.set_bone_global_pose(bone, pose)


func _straighten_spine_neck(rig, sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	if rig.hips >= 0:
		bones.append(rig.hips)
	bones.append_array(rig.spine)
	bones.append_array(rig.neck)
	for bone: int in bones:
		if bone < 0:
			continue
		var rest := sk.get_bone_rest(bone).basis.get_rotation_quaternion()
		var current := sk.get_bone_pose_rotation(bone)
		sk.set_bone_pose_rotation(bone, current.slerp(rest, weight))


func _align_chain_straight(rig, sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	bones.append_array(rig.spine)
	bones.append_array(rig.neck)
	if bones.is_empty():
		return
	var head := sk.find_bone("pony_head")
	var target: Vector3 = rig.forward_axis(sk)
	target.y = 0.0
	if target.length_squared() < 0.0001:
		return
	target = target.normalized()
	for i: int in bones.size():
		var bone := bones[i]
		if bone < 0 or bone == head:
			continue
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if i + 1 < bones.size():
			direction = sk.get_bone_global_pose(bones[i + 1]).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var axis := direction.cross(target)
		if axis.length_squared() < 0.0001:
			continue
		var angle := direction.angle_to(target) * weight
		pose.basis = Basis(axis.normalized(), angle) * pose.basis
		sk.set_bone_global_pose(bone, pose)


func _line_roll(rig, sk: Skeleton3D, left: Vector3, right: Vector3) -> float:
	return ROT.line_roll(rig.forward_axis(sk), rig.up_axis(sk), left, right)


func _pitch_body_about_shoulders(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if rig.root < 0 or rig.fore.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.fore[0].upper)).origin
	var right := sk.get_bone_global_pose(int(rig.fore[1].upper)).origin
	var pivot := (left + right) * 0.5
	var angle := deg_to_rad(degrees) * weight
	if absf(angle) < 0.0001:
		return
	var pose := sk.get_bone_global_pose(rig.root)
	var turn := Basis(rig.right_axis(sk), angle)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(rig.root, pose)


func _level_body_roll(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.root < 0 or rig.hips < 0 or rig.hind.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.hind[0].femur)).origin
	var right := sk.get_bone_global_pose(int(rig.hind[1].femur)).origin
	var angle := (_line_roll(rig, sk, left, right) + _value("roll_tweak", MISSIONARY_ROLL_TWEAK)) * weight
	last_roll = angle
	if absf(angle) < 0.0001:
		return
	var forward: Vector3 = rig.forward_axis(sk)
	var pivot := sk.get_bone_global_pose(rig.hips).origin
	var pose := sk.get_bone_global_pose(rig.root)
	var turn := Basis(forward, angle)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(rig.root, pose)


func _level_chest_roll(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.spine.is_empty() or rig.fore.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(rig.fore[0].upper)).origin
	var right := sk.get_bone_global_pose(int(rig.fore[1].upper)).origin
	var angle := _line_roll(rig, sk, left, right) * weight
	last_chest_roll = angle
	if absf(angle) < 0.0001:
		return
	var bone: int = rig.spine[0]
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(rig.forward_axis(sk), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)


func _bend_forelegs(rig, sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis: Vector3 = rig.right_axis(sk)
	for leg: Dictionary in rig.fore:
		rig.rotate(sk, int(leg.upper), axis, -0.06 * weight * scale)
		rig.rotate(sk, int(leg.lower), axis, 0.10 * weight * scale)


func _raise_hind_legs(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.hind.is_empty():
		return
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	var target := (up * 0.75 + forward * 0.45).normalized()
	for leg: Dictionary in rig.hind:
		var bone := int(leg.femur)
		var lower := int(leg.get("lower", -1))
		if bone < 0:
			continue
		# integration: the bed finish pose opens her hind legs around him.
		if _value("legs_wrap", 0.0) > 0.0:
			_wrap_leg(rig, sk, weight, bone, lower)
			continue
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if lower >= 0:
			direction = sk.get_bone_global_pose(lower).origin - pose.origin
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var axis := direction.cross(target)
		if axis.length_squared() > 0.0001:
			rig.rotate(sk, bone, axis.normalized(), direction.angle_to(target) * 0.75 * weight)
		var outward := pose.origin - sk.get_bone_global_pose(rig.hips).origin
		outward.y = 0.0
		var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
		rig.rotate(sk, bone, forward, sign * _value("hind_spread", MISSIONARY_HIND_SPREAD) * weight)
		if lower >= 0:
			rig.rotate(sk, lower, right, -0.55 * weight)


## integration: opens her hind leg out and back around him. The target is written straight to
## the femur, like the recipe's other body-relative corrections, then the knee bends.
func _wrap_leg(rig, sk: Skeleton3D, weight: float, bone: int, lower: int) -> void:
	var right: Vector3 = rig.right_axis(sk)
	var pose := sk.get_bone_global_pose(bone)
	var side: float = signf((pose.origin - sk.get_bone_global_pose(rig.hips).origin).dot(right))
	var target: Vector3 = (right * side * WRAP_OUT + rig.up_axis(sk) * WRAP_UP
		- rig.forward_axis(sk) * WRAP_BACK).normalized()
	var direction := pose.basis.z
	if lower >= 0:
		direction = sk.get_bone_global_pose(lower).origin - pose.origin
	if direction.length_squared() < 0.0001:
		return
	pose.basis = Basis(Quaternion(direction.normalized(), target)).slerp(Basis.IDENTITY,
		1.0 - weight) * pose.basis
	sk.set_bone_global_pose(bone, pose)
	if lower >= 0:
		rig.rotate(sk, lower, right, -WRAP_KNEE * weight)


func _hug_forelegs(rig, sk: Skeleton3D, weight: float) -> void:
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	for leg: Dictionary in rig.fore:
		var upper := int(leg.upper)
		var lower := int(leg.lower)
		if upper >= 0 and rig.hips >= 0:
			var pose := sk.get_bone_global_pose(upper)
			var outward := pose.origin - sk.get_bone_global_pose(rig.hips).origin
			outward.y = 0.0
			var direction := sk.get_bone_global_pose(lower).origin - pose.origin
			var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
			rig.rotate(sk, upper, forward, sign * 0.45 * weight)
		rig.rotate(sk, upper, right, -0.55 * weight)
		rig.rotate(sk, lower, right, 1.1 * weight)
		rig.rotate(sk, upper, up, 0.18 * weight)
		rig.rotate(sk, lower, forward, 0.35 * weight)


## Current skull frame in world space. The body's `pony_head` bone is mapped to the OpenPony
## head by HybridNeckLink with a fixed per-pair offset; applying that offset gives the same
## `mHead` frame the head skeleton will use after this pose. This is why the gaze solve can use
## the *current* pose instead of last frame's linked head.
func _head_gaze_frame(rig, sk: Skeleton3D) -> Dictionary:
	if rig.neck.is_empty():
		return {}
	var head: int = rig.neck[rig.neck.size() - 1]
	var world := sk.global_transform * sk.get_bone_global_pose(head)
	var mare: Variant = rig.mare
	if mare != null:
		var link: Variant = mare.get("neck_link")
		if link != null:
			var offsets: Variant = link.get("_offsets")
			if offsets is Array and (offsets as Array).size() >= 3:
				var head_offset: Transform3D = (offsets as Array)[2]
				world = world * head_offset
				return {"origin": world.origin, "forward": world.basis.z.normalized()}
		# A headless/test rig may not have the link. Fall back to the head skeleton's own gaze
		# from the last update, then to the body bone.
		if mare.has_method("awareness_forward"):
			var forward: Variant = mare.call("awareness_forward")
			var boop: Variant = mare.get("boop_node")
			var origin: Variant = null
			if boop != null and boop.has_method("skull_world"):
				origin = boop.call("skull_world")
			if forward is Vector3 and (forward as Vector3).length_squared() > 0.000001 \
					and origin is Vector3 and (origin as Vector3).is_finite():
				return {"origin": origin, "forward": (forward as Vector3).normalized()}
	return {"origin": world.origin, "forward": world.basis.z.normalized()}


## Rotate the neck/head chain by the shortest arc between her current face direction and Anon.
## Unlike the old absolute yaw/pitch solve this is independent of the body's rest orientation,
## so the lying missionary pose does not leave her staring at the ceiling. The shares keep the
## bend distributed through the chain and `rig.rotate()` applies the native joint limits.
func _aim_gaze(rig, sk: Skeleton3D, weight: float, look_point: Vector3) -> void:
	if rig.neck.is_empty() or not look_point.is_finite() or weight <= 0.0001:
		return
	var frame := _head_gaze_frame(rig, sk)
	if frame.is_empty():
		return
	var origin: Vector3 = frame["origin"]
	var forward: Vector3 = frame["forward"]
	var to := look_point - origin
	if to.length_squared() < 0.0001 or forward.length_squared() < 0.000001:
		return
	# Blend target: at full weight the residual is zero. Keep the per-frame budget so an
	# early pose blend under-aims instead of snapping the head straight to Anon.
	var desired := forward.angle_to(to) * (1.0 - clampf(weight, 0.0, 1.0))
	var shares: Array[float] = [0.30, 0.36, 0.34]
	# The head origin moves as the neck bends, so one shortest-arc correction leaves a few
	# degrees behind. Re-read the body head + link offset and mop up that residual here;
	# the head skeleton has not updated yet inside this modifier.
	for _step: int in 3:
		frame = _head_gaze_frame(rig, sk)
		if frame.is_empty():
			return
		origin = frame["origin"]
		forward = frame["forward"]
		to = look_point - origin
		if to.length_squared() < 0.0001:
			return
		var error := forward.angle_to(to)
		if error <= desired + 0.0005:
			return
		var axis_world := forward.cross(to)
		if axis_world.length_squared() < 0.0000001:
			return
		var axis := (sk.global_basis.inverse() * axis_world.normalized()).normalized()
		var step_angle := error - desired
		for i: int in rig.neck.size():
			rig.rotate(sk, rig.neck[i], axis,
				step_angle * shares[mini(i, shares.size() - 1)])


## A small off-target look for the nuzzle pulse, expressed as an angle at the target distance.
## Base gaze stays locked on Anon; nuzzling briefly wanders a few degrees and returns.
func _nuzzle_look_point(rig, sk: Skeleton3D, look_point: Vector3, pulse: float) -> Vector3:
	var frame := _head_gaze_frame(rig, sk)
	if frame.is_empty():
		return look_point
	var origin: Vector3 = frame["origin"]
	var distance := origin.distance_to(look_point)
	if distance < 0.01:
		return look_point
	var degrees := _value("nuzzle_scale", MISSIONARY_NUZZLE_SCALE) * 8.0 * clampf(pulse, 0.0, 1.0)
	if absf(degrees) < 0.01:
		return look_point
	var right: Vector3 = (sk.global_basis * rig.right_axis(sk)).normalized()
	var up: Vector3 = (sk.global_basis * rig.up_axis(sk)).normalized()
	var offset: Vector3 = (right + up * 0.25).normalized() * tan(deg_to_rad(degrees)) * distance
	return look_point + offset


## Bend each neck bone separately. Positive angles lift the head off the mattress in the supine
## pose; zero straightens the neck. It runs before `_aim_gaze()` so it changes position, not the
## final face direction.
func _neck_bend(rig, sk: Skeleton3D, weight: float, neck1_deg: float, neck2_deg: float) -> void:
	if rig.neck.size() < 2:
		return
	var right: Vector3 = rig.right_axis(sk)
	if absf(neck1_deg) > 0.0001:
		rig.rotate(sk, rig.neck[0], right, deg_to_rad(neck1_deg) * weight)
	if absf(neck2_deg) > 0.0001:
		rig.rotate(sk, rig.neck[1], right, deg_to_rad(neck2_deg) * weight)


## Roll the neck away from the mattress about the body's long axis. The gaze solve runs after
## this, so the face returns to Anon while the nape shifts sideways.
func _neck_roll(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if rig.neck.size() < 2 or absf(degrees) < 0.0001:
		return
	var angle := deg_to_rad(degrees) * weight
	var forward: Vector3 = rig.forward_axis(sk)
	rig.rotate(sk, rig.neck[0], forward, angle * 0.5)
	rig.rotate(sk, rig.neck[1], forward, angle * 0.5)


## Final head pitch after the gaze solve. This intentionally trades a little exact aim for a
## natural head angle; the presentation control is a debug offset.
func _head_pitch(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if rig.neck.is_empty() or absf(degrees) < 0.0001:
		return
	var head: int = rig.neck[rig.neck.size() - 1]
	if head < 0:
		return
	rig.rotate(sk, head, rig.right_axis(sk), deg_to_rad(degrees) * weight)


func _nuzzle_pulse(clock: float) -> float:
	var period := maxf(0.1, _value("nuzzle_period", NUZZLE_PERIOD))
	var duration := maxf(0.05, _value("nuzzle_duration", NUZZLE_DURATION))
	var phase := fmod(clock, period)
	if phase > duration:
		return 0.0
	return sin(phase / duration * PI)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback


func _roll_head(rig, sk: Skeleton3D, weight: float, degrees: float) -> void:
	if absf(degrees) < 0.0001 or rig.neck.is_empty():
		return
	var head: int = rig.neck[rig.neck.size() - 1]
	if head < 0:
		return
	var pose := sk.get_bone_global_pose(head)
	pose.basis = Basis(rig.forward_axis(sk), deg_to_rad(degrees) * weight) * pose.basis
	sk.set_bone_global_pose(head, pose)
