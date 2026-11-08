extends RefCounted
## Missionary pose: the hand-authored bed-space base pose plus the live overlays (nuzzle and the
## gaze solve). This is the only missionary implementation; there is no correction stack and no
## fallback pose. The asset is the pose.
##
## The base writes the skeleton root (placement) and the body bones. The head bone is reset to rest
## here, because the runtime owns the face: the gaze solve aims `pony_head`'s frame at Anon.

const MISSIONARY_NUZZLE_SCALE := 0.45
const NUZZLE_PERIOD := 7.0
const NUZZLE_DURATION := 2.4

var _config: Dictionary = {}


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	var authored: Variant = state.get("authored")
	var frame: Variant = state.get("bed_frame")
	if authored == null or not frame is Transform3D or not bool(authored.get("available")):
		return
	authored.call("apply_pony", sk, weight, frame, float(state.get("body_scale", 1.0)))
	_neutral_head(sk, weight)
	var pulse := 1.0 if bool(state.get("climaxing", false)) else _nuzzle_pulse(float(state.get("clock", 0.0)))
	if bool(state.get("climaxing", false)):
		pulse = 0.75 + 0.25 * sin(float(state.get("clock", 0.0)) * 4.0)
	var look_point: Vector3 = state.get("look_point", Vector3.ZERO)
	if pulse > 0.001 and look_point.is_finite():
		look_point = _nuzzle_look_point(rig, sk, look_point, pulse)
	_aim_gaze(rig, sk, weight, look_point)


## The head bone's own rotation comes from the game's lie animation and is not part of the authored
## pose. Reset it so the gaze solve shapes the face from a neutral head.
func _neutral_head(sk: Skeleton3D, weight: float) -> void:
	var head := sk.find_bone("pony_head")
	if head < 0:
		return
	var rest := sk.get_bone_rest(head).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(head, sk.get_bone_pose_rotation(head).slerp(rest, weight))


## Current skull frame in world space. The body's `pony_head` bone is mapped to the OpenPony
## head by HybridNeckLink with a fixed per-pair offset; applying that offset gives the same
## `mHead` frame the head skeleton will use after this pose.
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
				return {"origin": world.origin, "forward": world.basis.z.normalized(),
					"up": world.basis.y.normalized()}
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
				return {"origin": origin, "forward": (forward as Vector3).normalized(),
					"up": Vector3.UP}
	return {"origin": world.origin, "forward": world.basis.z.normalized(),
		"up": world.basis.y.normalized()}


## Rotate the neck/head chain by the shortest arc between her current face direction and Anon.
## Shortest-arc from the *current* pose, so it is independent of the bed and body orientation.
## `rotate_free` because the authored pose can sit outside the game's joint limits.
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
	# Blend target: at full weight the residual is zero. Keep the per-frame budget so an early
	# pose blend under-aims instead of snapping the head straight to Anon.
	var desired := forward.angle_to(to) * (1.0 - clampf(weight, 0.0, 1.0))
	var shares: Array[float] = [0.30, 0.36, 0.34]
	# The head origin moves as the neck bends, so one shortest-arc correction leaves a few
	# degrees behind. Re-read the body head + link offset and mop up that residual here; the head
	# skeleton has not updated yet inside this modifier.
	for _step: int in 3:
		frame = _head_gaze_frame(rig, sk)
		if frame.is_empty():
			break
		origin = frame["origin"]
		forward = frame["forward"]
		to = look_point - origin
		if to.length_squared() < 0.0001:
			break
		var error := forward.angle_to(to)
		if error <= desired + 0.0005:
			break
		var axis_world := forward.cross(to)
		if axis_world.length_squared() < 0.0000001:
			break
		var axis := (sk.global_basis.inverse() * axis_world.normalized()).normalized()
		var step_angle := error - desired
		for i: int in rig.neck.size():
			rig.rotate_free(sk, rig.neck[i], axis,
				step_angle * shares[mini(i, shares.size() - 1)])
	_level_head(rig, sk, weight)


## Keep her face upright. The aim only sets the face direction; a pose that rolls the neck leaves her
## staring at Anon sideways. Rolling the head about its own forward axis keeps the aim and puts her
## up with the world's.
func _level_head(rig, sk: Skeleton3D, weight: float) -> void:
	if rig.neck.is_empty() or weight <= 0.0001:
		return
	var frame := _head_gaze_frame(rig, sk)
	if frame.is_empty():
		return
	var forward: Vector3 = frame["forward"]
	var up: Vector3 = frame.get("up", Vector3.UP)
	var target_up := Vector3.UP - forward * Vector3.UP.dot(forward)
	if target_up.length_squared() < 0.0001 or up.length_squared() < 0.000001:
		return
	var angle: float = up.normalized().signed_angle_to(target_up.normalized(), forward)
	if absf(angle) < 0.002:
		return
	# Spread the roll down the neck the same way the aim is spread: rolling the head alone leaves the
	# neck joint twisted (a crooked neck), and three small turns read as one soft tilt.
	var shares: Array[float] = [0.30, 0.36, 0.34]
	var axis := (sk.global_basis.inverse() * forward).normalized()
	var total: float = angle * clampf(weight, 0.0, 1.0)
	for i: int in rig.neck.size():
		rig.rotate_free(sk, rig.neck[i], axis, total * shares[mini(i, shares.size() - 1)])


## A small off-target look for the nuzzle pulse, expressed as an angle at the target distance.
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
