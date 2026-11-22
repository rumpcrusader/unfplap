extends "res://mods/unfplap/poses/pose_driver.gd"
## Missionary pose: the hand-authored bed-space base plus the live nuzzle and gaze overlays.
## The asset is the pose, with no correction stack and no fallback. The runtime owns the face, so the
## base resets the head bone to rest and the gaze solve aims its frame at Anon.

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")

var _config: Dictionary = {}


## This recipe splits its base from its overlays, so a pose with a delta keeps base, delta, overlay.
func splits_base() -> bool:
	return true


func apply(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	if not apply_base(rig, sk, weight, state):
		return
	apply_overlay(rig, sk, weight, state)


## The authored base: the bed-space body and the neutral head. False when the asset or the frame is
## unavailable; the overlay is then skipped too, exactly as the whole-pose path returns.
func apply_base(_rig, sk: Skeleton3D, weight: float, state: Dictionary) -> bool:
	_config = state.get("config", {})
	var authored: AUTHORED = state.get("authored")
	var frame: Variant = state.get("bed_frame")
	if authored == null or not frame is Transform3D or not authored.available:
		return false
	authored.apply_pony(sk, weight, frame as Transform3D, float(state.get("body_scale", 1.0)),
		str(state.get("size_name", "")))
	_apply_contact_offset(sk, weight, state)
	_neutral_head(sk, weight)
	return true


## Move her armature root by the driver's world-space residual: the authored placement already sits
## on the bed, so only the live mouth/opening error is left. Weighted so a blend eases it in.
func _apply_contact_offset(sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	var value: Variant = state.get("contact_offset", Vector3.ZERO)
	if not value is Vector3:
		return
	var offset: Vector3 = value
	if not offset.is_finite() or offset.length_squared() < 0.0000001:
		return
	var root := sk.find_bone("pony_hips")
	while root >= 0:
		var parent := sk.get_bone_parent(root)
		if parent < 0:
			break
		root = parent
	if root < 0:
		return
	var pose := sk.get_bone_global_pose(root)
	pose.origin += sk.global_basis.inverse() * (offset * clampf(weight, 0.0, 1.0))
	sk.set_bone_global_pose(root, pose)


## The moveable overlays: the nuzzle pulse, the gaze aim and the head level. The two-base form
## calls this after the blended base; the single path calls it from `apply()`.
func apply_overlay(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
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


## The skull frame in world space. The body head bone is mapped to the OpenPony head by a fixed
## per-pair offset, so that offset must be applied to match the frame the head skeleton will use.
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
		var forward := GAME.awareness_forward(mare)
		var origin := WORLD.pony(mare).skull_world()
		if forward.length_squared() > 0.000001 and origin.is_finite():
			return {"origin": origin, "forward": forward.normalized(), "up": Vector3.UP}
	return {"origin": world.origin, "forward": world.basis.z.normalized(),
		"up": world.basis.y.normalized()}


## Swing the neck chain toward the look point by the shortest arc from its current pose, so the bed
## and body orientation drop out. `rotate_free()` because the authored pose exceeds the joint limits.
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


## Roll the head about its own forward axis until her head is level with the world; aiming alone
## fixes only the face direction and leaves the head tilted when the pose rolls the neck.
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
	var degrees := _value("nuzzle_scale") * 8.0 * clampf(pulse, 0.0, 1.0)
	if absf(degrees) < 0.01:
		return look_point
	var right: Vector3 = (sk.global_basis * rig.right_axis(sk)).normalized()
	var up: Vector3 = (sk.global_basis * rig.up_axis(sk)).normalized()
	var offset: Vector3 = (right + up * 0.25).normalized() * tan(deg_to_rad(degrees)) * distance
	return look_point + offset


func _nuzzle_pulse(clock: float) -> float:
	var period := maxf(0.1, _value("nuzzle_period"))
	var duration := maxf(0.05, _value("nuzzle_duration"))
	var phase := fmod(clock, period)
	if phase > duration:
		return 0.0
	return sin(phase / duration * PI)


func _value(key: String) -> float:
	return float(_config[key])
