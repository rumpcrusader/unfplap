extends SkeletonModifier3D
## Moves the visible tail aside and slightly up for the standing presentation, and can flick it.
## Runs on the hair skeleton after hybrid_tail_motion, or on the body skeleton for a fitted tail;
## only rotates bones.
##
## The side is chosen per act by `choose_side()` so the tail does not always sweep the same way.

const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const ASIDE_ANGLE := 0.55
const LIFT_ANGLE := 0.42
var aside_angle := ASIDE_ANGLE
var lift_angle := LIFT_ANGLE
var flick_amplitude := FLICK_AMPLITUDE
const FLICK_SECONDS := 0.9
const FLICK_AMPLITUDE := 1.10
## Tail follows the thrust/body rock: a sagittal swing plus a smaller lateral wag.
const ROCK_STIFFNESS := 90.0
const ROCK_DAMPING := 16.0
const ROCK_PITCH := 0.12
const ROCK_YAW := 0.08
## Thrust impulse: a short decaying wave down the tail so the rump jiggle is carried into the
## tail instead of leaving it rigid.
const JIGGLE_DECAY := 3.6
const JIGGLE_FREQ := 18.0
const JIGGLE_PITCH := 0.16
const JIGGLE_YAW := 0.08
## The game pins the tail base to the hair pelvis, so the bone wave alone cannot move it. Push the
## hair pelvis by the rump shader's wave, then restore the mane bones.
const JIGGLE_BASE_M := 0.02
const JIGGLE_BASE_FREQ := 28.0
const JIGGLE_BASE_DECAY := 4.2
const JIGGLE_BASE_BOB_FREQ := 24.0
const JIGGLE_BASE_BOB_DECAY := 3.6
const JIGGLE_BASE_BOB_DELAY := 0.035
const JIGGLE_BASE_NORMAL := 0.8

var mare: Node3D
## The typed act view: the live depth. Absent outside an act.
var facts: Variant
var amount := 0.0
var target_amount := 0.0
## Hinge the whole tail at `mTail1` and leave the rest rigid instead of spreading a falloff. The
## post-refusal tuck needs the base to pivot.
var base_pivot := false
## +1 or -1: which way the tail sweeps. Randomized per act.
var aside_sign := 1.0

var _bones: Array[int] = []
var _saved: Dictionary = {}
var _cached := false
## A tail living off the game skeletons: its own root is rotated and restored instead.
var _root: Node3D
var _root_saved := Transform3D.IDENTITY
var _root_direction := Vector3.BACK
var _root_ready := false
var _flick_time := -1.0
var _flick_cycles := 2.0
var _rock := 0.0
var _rock_velocity := 0.0
var _thrust_strength := 0.0
var _thrust_clock := 0.0
var _pelvis := -1
var _mane: Array[int] = []
var _hook_family := ""
var _hook_profile := ""
var _hook_seen := false


## The pose-change hook: a shared keep leaves the chain, the side and the fade alone. A family or
## profile change drops the cached bones so the next pose's rig is read fresh.
func pose_changed(view: POSE_VIEW) -> void:
	if view == null:
		return
	var family := view.family
	var profile := str(view.modifiers.get("profile", ""))
	if _hook_seen and family == _hook_family and profile == _hook_profile:
		return
	_hook_seen = true
	_hook_family = family
	_hook_profile = profile
	_cached = false


func _ready() -> void:
	_cache()


func _cache() -> void:
	_cached = true
	_root = TAIL_CHAIN.custom_root(mare)
	_root_ready = is_instance_valid(_root)
	if _root_ready:
		_root_saved = _root.transform
		_root_direction = TAIL_CHAIN.root_direction(_root)
	var sk := get_skeleton()
	if sk == null:
		return
	var found: Dictionary = TAIL_CHAIN.chain(sk)
	_bones.clear()
	var chain_bones: Variant = found.get("bones", [])
	for value: Variant in chain_bones:
		var bone := int(value)
		_bones.append(bone)
		if not _saved.has(bone):
			_saved[bone] = sk.get_bone_pose(bone)
	# Only the devkit hair tail has the pinned mPelvis and the mane sharing its skeleton. A body
	# tail rotates from pony_tail_01 and must not translate the hips.
	_pelvis = -1
	_mane.clear()
	if bool(found.get("hair", false)):
		_pelvis = sk.find_bone("mPelvis")
		for name: String in ["mChest", "mNeck", "mHead"]:
			var mane_bone := sk.find_bone(name)
			if mane_bone >= 0:
				_mane.append(mane_bone)


## Pick a fresh side for this act. With an Anon position, sweep the tail away from him:
## he on her left -> tail right, he on her right -> tail left. No clear side falls back to random.
func choose_side(anchor := Vector3.INF) -> void:
	if anchor.is_finite() and is_instance_valid(mare):
		var side := (anchor - mare.global_position).dot(mare.global_basis.x)
		if absf(side) > 0.05:
			aside_sign = 1.0 if side > 0.0 else -1.0
			return
	aside_sign = 1.0 if randf() < 0.5 else -1.0


## Hand the tail chain back as the game left it before the act; its own motion resumes next frame.
func restore_tail() -> void:
	var sk := get_skeleton()
	if sk != null:
		for bone: Variant in _saved:
			sk.set_bone_pose(int(bone), _saved[bone])
	if _root_ready and is_instance_valid(_root):
		_root.transform = _root_saved
		_root_ready = false


## A thrust restarts the tail's short jiggle, matched to the rump shader's strength.
func thrust(strength: float) -> void:
	_thrust_strength = maxf(_thrust_strength, clampf(strength, 0.0, 1.0))
	_thrust_clock = 0.0


## Two quick up/down swings. Called when the standing afterglow starts.
func flick(times := 2) -> void:
	_flick_cycles = float(maxi(1, times))
	_flick_time = 0.0


func _flick_angle(delta: float) -> float:
	if _flick_time < 0.0:
		return 0.0
	_flick_time += delta
	var t := _flick_time / FLICK_SECONDS
	if t >= 1.0:
		_flick_time = -1.0
		return 0.0
	return sin(t * TAU * _flick_cycles) * flick_amplitude * sin(t * PI)


func _process_modification_with_delta(delta: float) -> void:
	PERF.begin("tail_pose")
	_apply(delta)
	PERF.end("tail_pose")


func _apply(delta: float) -> void:
	if not is_instance_valid(mare):
		return
	if not _cached:
		_cache()
	if _root_ready and not is_instance_valid(_root):
		_root_ready = false
	if _bones.is_empty() and not _root_ready:
		return
	var sk := get_skeleton()
	var speed := 0.6 if target_amount > amount else 0.4
	amount = move_toward(amount, target_amount, delta / maxf(speed, 0.01))
	var flick := _flick_angle(delta)
	if amount <= 0.001:
		return
	var weight := smoothstep(0.0, 1.0, amount)
	var up := mare.global_basis.y.normalized()
	var right := mare.global_basis.x.normalized()
	if sk != null:
		up = (sk.global_basis.inverse() * mare.global_basis.y).normalized()
		right = (sk.global_basis.inverse() * mare.global_basis.x).normalized()
	# The body sway already rocks the spine; let the tail carry the same thrust cadence with a
	# damped spring so it swings back/forth and slightly up/down instead of staying rigid.
	var depth_value := 0.0
	if facts != null:
		depth_value = clampf(float(facts.depth), 0.0, 1.0)
	var rock_target := -depth_value
	var accel := -ROCK_STIFFNESS * (_rock - rock_target) - ROCK_DAMPING * _rock_velocity
	_rock_velocity += accel * delta
	_rock += _rock_velocity * delta
	_thrust_clock += delta
	var thrust_envelope := exp(-_thrust_clock * JIGGLE_DECAY)
	if thrust_envelope < 0.001:
		_thrust_strength = 0.0
	var base_offset := Vector3.ZERO
	if _thrust_strength > 0.001:
		var t := _thrust_clock
		var wave := -exp(-JIGGLE_BASE_DECAY * t) * sin(JIGGLE_BASE_FREQ * t)
		var bob := exp(-JIGGLE_BASE_BOB_DECAY * t) \
			* sin(JIGGLE_BASE_BOB_FREQ * maxf(t - JIGGLE_BASE_BOB_DELAY, 0.0))
		var world_back := mare.global_basis.z.normalized()
		var world_up := mare.global_basis.y.normalized()
		base_offset = (world_back * (wave * JIGGLE_BASE_NORMAL) + world_up * bob) \
			* (JIGGLE_BASE_M * _thrust_strength * weight)
	var flicking := absf(flick) > 0.0001
	if _root_ready and is_instance_valid(_root):
		_apply_root(weight, flick, flicking, base_offset)
		return
	if base_offset.length_squared() > 0.0000001 and _pelvis >= 0:
		var mane_poses: Array = []
		for bone in _mane:
			mane_poses.append([bone, sk.get_bone_global_pose(bone)])
		var pelvis_pose := sk.get_bone_global_pose(_pelvis)
		pelvis_pose.origin += sk.global_transform.affine_inverse().basis * base_offset
		sk.set_bone_global_pose(_pelvis, pelvis_pose)
		# The mane is copied from the head link; keep it where that link put it.
		for entry: Array in mane_poses:
			sk.set_bone_global_pose(entry[0], entry[1])
	for i: int in _bones.size():
		if base_pivot and i > 0:
			# The children keep their unchanged local transforms; rotating mTail1 moves them.
			break
		var bone := _bones[i]
		var falloff := 1.0 if base_pivot else 1.0 - float(i) * 0.10
		var pose := sk.get_bone_global_pose(bone)
		var direction := pose.basis.z
		if i + 1 < _bones.size():
			direction = sk.get_bone_global_pose(_bones[i + 1]).origin - pose.origin
		# Rotating about `right` by a positive angle raises the tail when (right x direction)
		# already points up; derive the sign so the lift always goes up.
		var lift_sign := 1.0 if right.cross(direction).dot(up) >= 0.0 else -1.0
		pose.basis = Basis(up, aside_angle * weight * aside_sign * falloff) * pose.basis
		var lift := lift_angle * weight + (flick * weight if flicking else 0.0)
		pose.basis = Basis(right, lift_sign * lift * falloff) * pose.basis
		pose.basis = Basis(right, lift_sign * _rock * ROCK_PITCH * weight * falloff) * pose.basis
		pose.basis = Basis(up, _rock * ROCK_YAW * weight * falloff) * pose.basis
		if _thrust_strength > 0.001 and thrust_envelope > 0.001:
			# The tail root (mTail1) takes the strongest impulse; the wave lags slightly down the chain.
			var wave := sin(_thrust_clock * JIGGLE_FREQ - float(i) * 0.55)
			var impulse := _thrust_strength * thrust_envelope * wave * weight * falloff
			pose.basis = Basis(right, lift_sign * impulse * JIGGLE_PITCH) * pose.basis
			pose.basis = Basis(up, impulse * JIGGLE_YAW) * pose.basis
		sk.set_bone_global_pose(bone, pose)


## Rotate a custom tail root by the same lift/aside/rock/flick the bone path applies. The saved
## local transform is the base every frame, so the rotation never accumulates.
func _apply_root(weight: float, flick: float, flicking: bool,
		base_offset: Vector3) -> void:
	var parent := _root.get_parent() as Node3D
	var parent_basis := Basis.IDENTITY
	if is_instance_valid(parent):
		parent_basis = parent.global_transform.basis
	var local_up := (parent_basis.inverse() * mare.global_basis.y).normalized()
	var local_right := (parent_basis.inverse() * mare.global_basis.x).normalized()
	var world_up := mare.global_basis.y.normalized()
	var world_right := mare.global_basis.x.normalized()
	var world_direction := (parent_basis * (_root_saved.basis * _root_direction)).normalized()
	var lift_sign := 1.0 if world_right.cross(world_direction).dot(world_up) >= 0.0 else -1.0
	var rotation := Basis(local_up, aside_angle * weight * aside_sign)
	var lift := lift_angle * weight + (flick * weight if flicking else 0.0)
	rotation = Basis(local_right, lift_sign * lift) * rotation
	rotation = Basis(local_right, lift_sign * _rock * ROCK_PITCH * weight) * rotation
	rotation = Basis(local_up, _rock * ROCK_YAW * weight) * rotation
	if _thrust_strength > 0.001:
		var impulse := _thrust_strength * exp(-_thrust_clock * JIGGLE_DECAY) \
			* sin(_thrust_clock * JIGGLE_FREQ) * weight
		rotation = Basis(local_right, lift_sign * impulse * JIGGLE_PITCH) * rotation
		rotation = Basis(local_up, impulse * JIGGLE_YAW) * rotation
	var origin := _root_saved.origin
	if base_offset.length_squared() > 0.0000001:
		origin += parent_basis.inverse() * base_offset
	_root.transform = Transform3D(rotation * _root_saved.basis, origin)
