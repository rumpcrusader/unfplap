extends SkeletonModifier3D
## Presentation-only pose for the act. Rotates bones; never translates or scales a limb.
##
## HOW TO READ THIS FILE
## ---------------------
## There are three layers, applied in this order. Keeping them separate is what lets the same
## pose work both in the floating F9 preview and on a real bed.
##
## 1. PLACEMENT — context-independent: `_roll_root()`, `_lift_root()`.
##    This is the correct way to place/rotate the whole pony: rotate or translate the root bone
##    about the hips. Do it first, from the pony's current world state. Everything else inherits
##    it. If you need a new body orientation, add it here, not in the pose content.
##
## 2. CONTEXT CORRECTIONS — undo a pose the game already applied; keep them measured, not fixed.
##    The game poses her before this modifier runs. On a bed that is `lie_down` (pelvis, spine and
##    neck curled, torso rolled); floating in F9 there is no such pose. These helpers read the
##    *current* pose and neutralise it, so they are no-ops when there is nothing to undo:
##      - `_straighten_spine_neck()` resets pelvis/spine/neck to their rest rotations;
##      - `_level_body_roll()` / `_level_chest_roll()` level the hip and shoulder lines against the
##        bed plane, because rest skeleton + `lie_down` leaves a residual roll.
##    Add a correction here only when a specific placement needs it. Never bake bed angles into
##    the act pose itself, and never apply a correction that cannot measure itself from the pose.
##
## 3. POSE CONTENT — what the act should look like: `_align_chain_straight()`,
##    `_raise_hind_legs()`, `_hug_forelegs()`, `_bend_forelegs()`, `_bow()`, `_aim_head()`,
##    `_lift_neck()`, `_raise_head()`, `_turn_head()`, `_spread_hind()`, plus `tail_pose.gd` for
##    the tail. These are deliberate tuned angles and must use body-relative axes
##    (`_right_axis`, `_up_axis`, `_forward_axis`), never world axes.
##
## Rule of thumb: a value that says where the pony is in the world is PLACEMENT; a value that
## exists only to fight a pose the game already applied is a CORRECTION; a value that describes
## the act itself is POSE CONTENT.
##
## Pose 2 opens with `_standing()`: no placement or correction layer, just pose content.
## Pose 1 opens with `_missionary()`; its afterglow reuses `_missionary()` with a relaxed variant.

## Pose 2 stance: easy to tune without touching the rest of the code.
const STANDING_BOW := 2.4
const STANDING_FORELEG := 2.0
const STANDING_HIND_SPREAD := 0.16
## Pose 1: spread of the raised hind legs around the body axis. 0.24 is a modest presentation
## spread; larger values open her legs further toward the camera.
const POSE1_HIND_SPREAD := 0.42
## Pose 1: aim the head at Anon's camera, with a periodic reach toward it (deep-kiss nuzzle).
const POSE1_LOOK_SCALE := 0.55
const POSE1_NUZZLE_SCALE := 0.45
const NUZZLE_PERIOD := 7.0
const NUZZLE_DURATION := 2.4
## Temporary pose-1 diagnostics; set false when the neck/bones are tuned.
const DEBUG_POSE1_DUMP := true
## Extra roll around her long axis after levelling, in radians. Positive rolls one side down.
## CORRECTION tuning knob: adjust only if the measured bed levelling still leaves a small tilt.
const POSE1_ROLL_TWEAK := 0.0

var mare: Node3D
var mode := "pose1"
var style := "side_lying"
var afterglow_pose := 1
var look_point := Vector3.ZERO
var head_back := 0.0
var amount := 0.0
var target_amount := 0.0

var _root := -1
var _hips := -1
var _spine: Array[int] = []
var _neck: Array[int] = []
var _fore: Array[Dictionary] = []
var _hind: Array[Dictionary] = []
var _limits: Variant = null
var _cached := false
var _debug_dumped := false
var _last_roll := 0.0
var _last_chest_roll := 0.0
var _clock := 0.0


func _ready() -> void:
	_cache()


## Cache the bone indices and joint-limit helper for the pony's standard skeleton.
func _cache() -> void:
	_cached = true
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	_limits = mare.get("joint_limits")
	_hips = sk.find_bone("pony_hips")
	_root = _hips
	while _root >= 0:
		var parent := sk.get_bone_parent(_root)
		if parent < 0:
			break
		_root = parent
	_spine.clear()
	for name: String in ["pony_spine1", "pony_spine2", "pony_spine3"]:
		var bone := sk.find_bone(name)
		if bone >= 0:
			_spine.append(bone)
	_neck.clear()
	for name: String in ["pony_neck1", "pony_neck2", "pony_head"]:
		var bone := sk.find_bone(name)
		if bone >= 0:
			_neck.append(bone)
	_fore.clear()
	for side: String in ["L", "R"]:
		var upper := sk.find_bone("pony_upperArm_" + side)
		var lower := sk.find_bone("pony_lowerArm_" + side)
		if upper >= 0 and lower >= 0:
			_fore.append({"upper": upper, "lower": lower})
	_hind.clear()
	for side: String in ["L", "R"]:
		var femur := sk.find_bone("pony_femur_" + side)
		var lower := sk.find_bone("pony_legLower_" + side)
		if femur >= 0:
			_hind.append({"femur": femur, "lower": lower})


## Ease `amount` toward `target_amount`, then dispatch to the pose for the current mode.
## `weight` is the eased 0–1 blend and is passed to every layer so transitions stay smooth.
func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _cached:
		_cache()
	var speed := 0.6 if target_amount > amount else 0.4
	amount = move_toward(amount, target_amount, delta / maxf(speed, 0.01))
	if amount <= 0.001:
		return
	var weight := smoothstep(0.0, 1.0, amount)
	_clock += delta
	if mode == "pose2":
		_standing(sk, weight)
	elif mode == "afterglow":
		_afterglow(sk, weight)
	elif mode == "pose1":
		_missionary(sk, weight)
	else:
		_bed(sk, weight)


## Pose 1 (missionary): supine placement → bed corrections → act pose.
## The order is load-bearing:
##   1. placement is context-independent and comes from the current world state;
##   2. corrections neutralise the game's own lie pose and the rest skeleton's roll;
##   3. pose content shapes the act on top of the now-clean body.
func _missionary(sk: Skeleton3D, weight: float) -> void:
	# PLACEMENT: supine roll plus just enough lift to keep the back off the mattress. Head and
	# rump should rest on the bed. This is the part that would work on any surface.
	_roll_root(sk, PI * weight)
	_lift_root(sk, weight, 0.05)
	# CORRECTION (bed `lie_down` + rest roll): no-ops in the floating F9 preview, because there is
	# no lie pose to undo. Do not treat these angles as part of the design of the pose.
	_straighten_spine_neck(sk, weight)
	_align_chain_straight(sk, weight)
	_level_body_roll(sk, weight)
	_level_chest_roll(sk, weight)
	# POSE CONTENT: the act presentation itself.
	_bend_forelegs(sk, weight, 0.3)
	_raise_hind_legs(sk, weight)
	_hug_forelegs(sk, weight)
	# POSE CONTENT: look up at Anon's camera and periodically reach toward it (nuzzle).
	_aim_head(sk, weight, POSE1_LOOK_SCALE)
	var pulse := _nuzzle_pulse()
	if pulse > 0.001:
		_aim_head(sk, weight * pulse, POSE1_NUZZLE_SCALE)
	# NOTE: positive neck lift (the old 0.10/0.08/0.06 here) is the head-back effect. It is
	# intentionally not applied in pose 1; keep it for a future thrown-back-head pose.
	# _lift_neck(sk, weight)
	# _aim_head(sk, weight, 0.05)
	if weight > 0.9 and not _debug_dumped and DEBUG_POSE1_DUMP:
		_debug_dumped = true
		_dump_pose1(sk)


## DIAGNOSTICS ONLY (F9 / first full-weight frame). Prints one line for the body, one for the
## chain deviations, and one for the linked head. Not part of posing.
func _dump_pose1(sk: Skeleton3D) -> void:
	var body := _forward_axis(sk)
	body.y = 0.0
	if body.length_squared() > 0.0001:
		body = body.normalized()
	print("[unfunfunf] POSE1 root=%s mare=%s scale=%.2f roll pelvis=%.1f° chest=%.1f°" % [
		str(sk.global_basis), str(mare.global_basis), float(mare.body_scale),
		rad_to_deg(_last_roll), rad_to_deg(_last_chest_roll)])
	var chain: Array[int] = []
	if _hips >= 0:
		chain.append(_hips)
	chain.append_array(_spine)
	chain.append_array(_neck)
	var parts: PackedStringArray = []
	for i: int in chain.size():
		var bone := chain[i]
		if bone < 0 or i + 1 >= chain.size():
			continue
		var origin := sk.get_bone_global_pose(bone).origin
		var next := sk.get_bone_global_pose(chain[i + 1]).origin
		var direction := next - origin
		if direction.length_squared() < 0.000001:
			continue
		direction = direction.normalized()
		parts.append("%s %.0f°" % [sk.get_bone_name(bone).trim_prefix("pony_"),
			rad_to_deg(direction.angle_to(body))])
	print("[unfunfunf] POSE1 chain %s (deviation from body axis)" % " | ".join(parts))
	var boop: Variant = mare.get("boop_node")
	var hs: Variant = boop.get("head_skeleton") if boop != null else null
	if hs is Skeleton3D:
		var head_bone := (hs as Skeleton3D).find_bone("mHead")
		if head_bone >= 0:
			var head_pose := (hs as Skeleton3D).get_bone_global_pose(head_bone)
			print("[unfunfunf] POSE1 head mHead origin=%s dir=%s" % [
				str(head_pose.origin), str(head_pose.basis.z)])
	else:
		print("[unfunfunf] POSE1 head_skeleton unavailable")


## CORRECTION (bed `lie_down`): remove the native lie-down curl from the pelvis, spine and neck.
## The pelvis (hips) must be included: the bed's lie pose rotates it too, and leaving that in makes
## the rump/hip line sit at an angle even when the spine and shoulders are straight. The floating
## F9 preview has no lie pose, which is why it looked correct while the bed did not.
func _straighten_spine_neck(sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	if _hips >= 0:
		bones.append(_hips)
	bones.append_array(_spine)
	bones.append_array(_neck)
	for bone: int in bones:
		if bone < 0:
			continue
		var rest := sk.get_bone_rest(bone).basis.get_rotation_quaternion()
		var current := sk.get_bone_pose_rotation(bone)
		sk.set_bone_pose_rotation(bone, current.slerp(rest, weight))


## POSE CONTENT (straight body line): force the spine and neck into one straight line along the
## body's long axis. Run this after the lie pose has been neutralised; it shapes the act pose, it
## is not a placement step.
func _align_chain_straight(sk: Skeleton3D, weight: float) -> void:
	var bones: Array[int] = []
	bones.append_array(_spine)
	bones.append_array(_neck)
	if bones.is_empty():
		return
	# `pony_head` stays in the list only so `pony_neck2` measures its direction toward the head's
	# origin. It is never rotated: its `basis.z` is not the face axis, and rotating it there
	# twisted the head 90 degrees. The head follows neck2 through its rest offset.
	var head := sk.find_bone("pony_head")
	var target := _forward_axis(sk)
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


## CORRECTION HELPER: angle (radians, wrapped to ±90°) needed to level the left/right line between
## two joint origins against the bed plane. Shared by both levelling corrections below.
## A left/right line has no direction: +180° and -180° describe the same line, so always pick the
## branch nearest to level or the correction flips her from belly-up to belly-down.
func _line_roll(sk: Skeleton3D, left: Vector3, right: Vector3) -> float:
	var forward := _forward_axis(sk)
	var lateral := right - left
	# Ignore any along-body component; only the roll around that axis is being corrected.
	lateral -= forward * lateral.dot(forward)
	if lateral.length_squared() < 0.000001:
		return 0.0
	var up := _up_axis(sk)
	var side := forward.cross(up)
	if side.length_squared() < 0.000001:
		return 0.0
	var angle := atan2(lateral.dot(up), lateral.dot(side.normalized()))
	if angle > PI * 0.5:
		angle -= PI
	elif angle < -PI * 0.5:
		angle += PI
	return angle


## CORRECTION (bed contact, pelvis): roll the whole body around its long axis until her left/right
## hip line is level with the bed. `_roll_root(PI)` turns her supine, but the rest skeleton's own
## roll leaves the torso tilted a few tens of degrees, so one side's legs sink into the mattress
## while the other side floats. The hind-leg roots sit on the pelvis, so their line is the cleanest
## measure of pelvis roll. Applied to the ROOT because the pelvis must carry the whole body.
## Not part of placement: this measures and removes an existing tilt, it does not choose one.
func _level_body_roll(sk: Skeleton3D, weight: float) -> void:
	if _root < 0 or _hips < 0 or _hind.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(_hind[0].femur)).origin
	var right := sk.get_bone_global_pose(int(_hind[1].femur)).origin
	var angle := (_line_roll(sk, left, right) + POSE1_ROLL_TWEAK) * weight
	_last_roll = angle
	if absf(angle) < 0.0001:
		return
	var forward := _forward_axis(sk)
	var pivot := sk.get_bone_global_pose(_hips).origin
	var pose := sk.get_bone_global_pose(_root)
	var turn := Basis(forward, angle)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(_root, pose)


## CORRECTION (bed contact, chest): level the shoulder line separately. Straightening the spine can
## leave the chest rolled relative to the pelvis, which shows up as correct shoulders over an angled
## rump. Rotating the first spine bone about the body axis carries the whole upper body without
## moving the pelvis. Like `_level_body_roll()`, this removes a measured tilt rather than setting one.
func _level_chest_roll(sk: Skeleton3D, weight: float) -> void:
	if _spine.is_empty() or _fore.size() < 2:
		return
	var left := sk.get_bone_global_pose(int(_fore[0].upper)).origin
	var right := sk.get_bone_global_pose(int(_fore[1].upper)).origin
	var angle := _line_roll(sk, left, right) * weight
	_last_chest_roll = angle
	if absf(angle) < 0.0001:
		return
	var bone := _spine[0]
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(_forward_axis(sk), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)


## POSE CONTENT (unused): negative neck angles lower the muzzle toward the bed line after the supine
## roll. Superseded by `_align_chain_straight()`; kept as a small, local neck adjustment.
func _level_neck(sk: Skeleton3D, weight: float) -> void:
	var right := _right_axis(sk)
	var angles: Array[float] = [-0.14, -0.12, -0.10]
	for i: int in _neck.size():
		_rotate(sk, _neck[i], right, angles[mini(i, angles.size() - 1)] * weight)


## POSE CONTENT: positive neck angles throw the neck/head back (used by the pose-2 glance). Kept for
## pose 1 as the reusable "head back" effect; currently unused there.
func _lift_neck(sk: Skeleton3D, weight: float) -> void:
	var right := _right_axis(sk)
	var angles: Array[float] = [0.10, 0.08, 0.06]
	for i: int in _neck.size():
		_rotate(sk, _neck[i], right, angles[mini(i, angles.size() - 1)] * weight)


## PLACEMENT: raise or lower the whole pony along the world up axis. Root translation only.
func _lift_root(sk: Skeleton3D, weight: float, metres: float) -> void:
	if _root < 0:
		return
	var pose := sk.get_bone_global_pose(_root)
	pose.origin += _up_axis(sk) * metres * weight
	sk.set_bone_global_pose(_root, pose)


## POSE CONTENT: raise both hind legs toward the camera and spread them apart.
func _raise_hind_legs(sk: Skeleton3D, weight: float) -> void:
	if _hind.is_empty():
		return
	var right := _right_axis(sk)
	var up := _up_axis(sk)
	var forward := _forward_axis(sk)
	var target := (up * 0.75 + forward * 0.45).normalized()
	for leg: Dictionary in _hind:
		var bone := int(leg.femur)
		var lower := int(leg.get("lower", -1))
		if bone < 0:
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
			_rotate(sk, bone, axis.normalized(), direction.angle_to(target) * 0.75 * weight)
		# Spread the raised leg outward around the body forward axis.
		var outward := pose.origin - sk.get_bone_global_pose(_hips).origin
		outward.y = 0.0
		var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
		_rotate(sk, bone, forward, sign * POSE1_HIND_SPREAD * weight)
		# Bend the knee toward the body so the hooves are in the air.
		if lower >= 0:
			_rotate(sk, lower, right, -0.55 * weight)


## POSE CONTENT: bring the front legs in and spread them, as if hugging Anon.
func _hug_forelegs(sk: Skeleton3D, weight: float) -> void:
	var right := _right_axis(sk)
	var up := _up_axis(sk)
	var forward := _forward_axis(sk)
	for leg: Dictionary in _fore:
		var upper := int(leg.upper)
		var lower := int(leg.lower)
		if upper >= 0 and _hips >= 0:
			var pose := sk.get_bone_global_pose(upper)
			var outward := pose.origin - sk.get_bone_global_pose(_hips).origin
			outward.y = 0.0
			var direction := sk.get_bone_global_pose(lower).origin - pose.origin
			var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
			_rotate(sk, upper, forward, sign * 0.45 * weight)
		_rotate(sk, upper, right, -0.55 * weight)
		_rotate(sk, lower, right, 1.1 * weight)
		_rotate(sk, upper, up, 0.18 * weight)
		_rotate(sk, lower, forward, 0.35 * weight)


## POSE CONTENT helper: 0→1→0 pulse once per `NUZZLE_PERIOD`, peaking for `NUZZLE_DURATION`.
## Drives the extra reach toward Anon's camera in pose 1.
func _nuzzle_pulse() -> float:
	var phase := fmod(_clock, NUZZLE_PERIOD)
	if phase > NUZZLE_DURATION:
		return 0.0
	return sin(phase / NUZZLE_DURATION * PI)


## POSE CONTENT: aim neck/head at `look_point` with both yaw and pitch. Closely related to the carry
## kiss reach. In pose 1 `look_point` is Anon's camera, so this is her looking up at him; calling it
## again with a pulsed scale produces the nuzzle.
func _aim_head(sk: Skeleton3D, weight: float, scale: float) -> void:
	if _neck.is_empty() or not look_point.is_finite():
		return
	var head := _neck[_neck.size() - 1]
	var head_pose := sk.get_bone_global_pose(head)
	var head_world := sk.global_transform * head_pose
	var to := look_point - head_world.origin
	if to.length_squared() < 0.0001:
		return
	var right := _right_axis(sk)
	var up := _up_axis(sk)
	var local := sk.global_basis.inverse() * to
	var flat := Vector2(local.x, local.z).length()
	var yaw := atan2(-local.x, -local.z) if flat > 0.001 else 0.0
	var pitch := atan2(local.y, flat)
	var shares: Array[float] = [0.30, 0.36, 0.34]
	for i: int in _neck.size():
		var share := shares[mini(i, shares.size() - 1)] * weight * scale
		_rotate(sk, _neck[i], up, clampf(yaw, -1.1, 1.1) * share)
		_rotate(sk, _neck[i], right, clampf(pitch, -0.8, 0.8) * share)


## Fallback presentation for the B29 preview: side-lying. PLACEMENT (`_roll_root`) + POSE CONTENT
## only — no bed corrections, because it starts from the game's own lie pose.
func _bed(sk: Skeleton3D, weight: float) -> void:
	var roll := 0.9 if style != "supine" else 2.55
	_roll_root(sk, roll * weight)
	_bow(sk, weight, 0.18)
	_turn_head(sk, weight, 0.85)
	_bend_forelegs(sk, weight, 0.35)


## POSE CONTENT only: pose 2 standing presentation, reverted to the initial neck and glance
## behaviour (`_bow`) while the straight-neck variant is parked for later.
func _standing(sk: Skeleton3D, weight: float) -> void:
	_bow(sk, weight, STANDING_BOW)
	_bend_forelegs(sk, weight, STANDING_FORELEG)
	_spread_hind(sk, weight, STANDING_HIND_SPREAD)
	if head_back > 0.001:
		_raise_head(sk, weight * head_back)


## POSE CONTENT: extra head-back rotation for the full carried-style throw-back glance.
func _raise_head(sk: Skeleton3D, weight: float) -> void:
	var axis := _right_axis(sk)
	var angles: Array[float] = [0.24, 0.22, 0.18]
	for i: int in _neck.size():
		_rotate(sk, _neck[i], axis, angles[mini(i, angles.size() - 1)] * weight)


## Pose-1 afterglow reuses the full `_missionary()` pipeline, so placement, bed corrections and pose
## content stay consistent; the relaxed differences are the eye/expression work in runtime.gd.
func _afterglow(sk: Skeleton3D, weight: float) -> void:
	if afterglow_pose == 1:
		# Keep her on her back; relax the raised legs and hugging forelegs a little.
		_missionary(sk, weight)
	else:
		_bow(sk, weight, 0.35)
		_bend_forelegs(sk, weight, 0.4)
		_turn_head(sk, weight, 0.45)


## PLACEMENT: roll the whole pony around the body's long axis, pivoted at the hips.
## This is the correct primitive for "put her on her back / side / front". Use it before any
## correction or pose-content step, and pass the desired angle for the current weight.
func _roll_root(sk: Skeleton3D, angle: float) -> void:
	if _root < 0 or _hips < 0 or absf(angle) < 0.0001:
		return
	var axis := _forward_axis(sk)
	var pivot := sk.get_bone_global_pose(_hips).origin
	var pose := sk.get_bone_global_pose(_root)
	pose.origin = pivot + Basis(axis, angle) * (pose.origin - pivot)
	pose.basis = Basis(axis, angle) * pose.basis
	pose.origin += _up_axis(sk) * (0.03 * absf(angle))
	sk.set_bone_global_pose(_root, pose)


## POSE CONTENT: gentle spine/neck bow used by the standing and fallback poses.
func _bow(sk: Skeleton3D, weight: float, scale: float) -> void:
	_bow_spine(sk, weight, scale)
	var axis := _right_axis(sk)
	var neck_angles: Array[float] = [-0.08, -0.06, -0.04]
	for i: int in _neck.size():
		var angle := neck_angles[mini(i, neck_angles.size() - 1)] * weight * scale
		_rotate(sk, _neck[i], axis, angle)


## POSE CONTENT: spine part of `_bow()`, shared with the pose-2 neck line so the neck does not get
## a second, conflicting curl on top of it.
func _bow_spine(sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis := _right_axis(sk)
	var spine_angles: Array[float] = [-0.05, -0.06, -0.04]
	for i: int in _spine.size():
		var angle := spine_angles[mini(i, spine_angles.size() - 1)] * weight * scale
		_rotate(sk, _spine[i], axis, angle)


## POSE CONTENT: small foreleg bend shared by the poses.
func _bend_forelegs(sk: Skeleton3D, weight: float, scale: float) -> void:
	var axis := _right_axis(sk)
	for leg: Dictionary in _fore:
		_rotate(sk, int(leg.upper), axis, -0.06 * weight * scale)
		_rotate(sk, int(leg.lower), axis, 0.10 * weight * scale)


## Slight hind-leg spread: rotate each femur outward around the body's forward axis.
func _spread_hind(sk: Skeleton3D, weight: float, angle: float) -> void:
	if _hind.is_empty() or _hips < 0:
		return
	var hips_origin := sk.get_bone_global_pose(_hips).origin
	var forward := _forward_axis(sk)
	for leg: Dictionary in _hind:
		var bone := int(leg.femur)
		if bone < 0:
			continue
		var pose := sk.get_bone_global_pose(bone)
		var outward := pose.origin - hips_origin
		outward.y = 0.0
		var direction := -_up_axis(sk)
		var lower := int(leg.get("lower", -1))
		if lower >= 0:
			direction = sk.get_bone_global_pose(lower).origin - pose.origin
		# Rotate about forward. Pick the sign that moves this leg away from the hips.
		var sign := 1.0 if forward.cross(direction).dot(outward) >= 0.0 else -1.0
		_rotate(sk, bone, forward, sign * angle * weight)


## POSE CONTENT: turn the neck/head horizontally toward `look_point` (glances).
func _turn_head(sk: Skeleton3D, weight: float, scale: float) -> void:
	if _neck.is_empty() or not look_point.is_finite():
		return
	var head := _neck[_neck.size() - 1]
	var head_pose := sk.get_bone_global_pose(head)
	var head_world := sk.global_transform * head_pose
	var to := look_point - head_world.origin
	to.y = 0.0
	var forward := -head_world.basis.z
	forward.y = 0.0
	if to.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return
	to = to.normalized()
	forward = forward.normalized()
	var up := _up_axis(sk)
	var angle := atan2(up.dot(forward.cross(to)), forward.dot(to))
	angle = clampf(angle, -0.95, 0.95) * weight * scale
	var shares: Array[float] = [0.32, 0.36, 0.32]
	for i: int in _neck.size():
		_rotate(sk, _neck[i], up, angle * shares[mini(i, shares.size() - 1)])


## Rotate a bone in skeleton space, then clamp it with the pony's joint limits.
## Used by POSE CONTENT for limb shaping; corrections write global poses directly because the
## joint limits would undo a measured levelling rotation.
func _rotate(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.00001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)
	_limit(sk, bone)


## Joint-limit clamp for `_rotate()`; skipped for direct global-pose corrections.
func _limit(sk: Skeleton3D, bone: int) -> void:
	if _limits == null:
		return
	if not _limits.has_method("constrain"):
		return
	var held: Basis = _limits.call("constrain", bone, Basis(sk.get_bone_pose_rotation(bone)))
	sk.set_bone_pose_rotation(bone, held.get_rotation_quaternion())


## BODY-RELATIVE AXES (in skeleton space). Always pose with these, never with raw world axes:
## the same numbers then work after any placement roll.
##   right: her lateral axis (horizontal, to her right).
##   up:    world up, expressed in skeleton space (gravity, not her rolled dorsal axis).
##   forward: her facing/heading (horizontal).
func _right_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * mare.global_basis.x).normalized()


func _up_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * mare.global_basis.y).normalized()


func _forward_axis(sk: Skeleton3D) -> Vector3:
	return (sk.global_basis.inverse() * -mare.global_basis.z).normalized()
