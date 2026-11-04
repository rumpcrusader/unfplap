extends SkeletonModifier3D
## Moves the tail aside and slightly up for the standing presentation, and can flick it.
## Runs on the hair skeleton after hybrid_tail_motion; only rotates bones.
##
## The side is chosen per act by `choose_side()` so the tail does not always sweep the same way.

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
## dock and tail instead of leaving the tail rigid.
const JIGGLE_DECAY := 3.6
const JIGGLE_FREQ := 18.0
const JIGGLE_PITCH := 0.16
const JIGGLE_YAW := 0.08

var mare: Node3D
var runtime: Node
var amount := 0.0
var target_amount := 0.0
## +1 or -1: which way the tail sweeps. Randomized per act.
var aside_sign := 1.0

var _bones: Array[int] = []
var _cached := false
var _flick_time := -1.0
var _flick_cycles := 2.0
var _rock := 0.0
var _rock_velocity := 0.0
var _thrust_strength := 0.0
var _thrust_clock := 0.0


func _ready() -> void:
	_cache()


func _cache() -> void:
	_cached = true
	var sk := get_skeleton()
	if sk == null:
		return
	_bones.clear()
	for i: int in range(1, 7):
		var bone := sk.find_bone("mTail%d" % i)
		if bone >= 0:
			_bones.append(bone)


## Pick a fresh side for this act.
func choose_side() -> void:
	aside_sign = 1.0 if randf() < 0.5 else -1.0


## A thrust restarts the tail's short jiggle at the same strength as the rump shader.
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
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _cached:
		_cache()
	if _bones.is_empty():
		return
	var speed := 0.6 if target_amount > amount else 0.4
	amount = move_toward(amount, target_amount, delta / maxf(speed, 0.01))
	var flick := _flick_angle(delta)
	if amount <= 0.001:
		return
	var weight := smoothstep(0.0, 1.0, amount)
	var up := (sk.global_basis.inverse() * mare.global_basis.y).normalized()
	var right := (sk.global_basis.inverse() * mare.global_basis.x).normalized()
	# The body sway already rocks the spine; let the tail carry the same thrust cadence with a
	# damped spring so it swings back/forth and slightly up/down instead of staying rigid.
	var depth_value := 0.0
	if is_instance_valid(runtime):
		depth_value = clampf(float(runtime.get("depth")), 0.0, 1.0)
	var rock_target := -depth_value
	var accel := -ROCK_STIFFNESS * (_rock - rock_target) - ROCK_DAMPING * _rock_velocity
	_rock_velocity += accel * delta
	_rock += _rock_velocity * delta
	_thrust_clock += delta
	var thrust_envelope := exp(-_thrust_clock * JIGGLE_DECAY)
	if thrust_envelope < 0.001:
		_thrust_strength = 0.0
	var flicking := absf(flick) > 0.0001
	for i: int in _bones.size():
		var bone := _bones[i]
		var falloff := 1.0 - float(i) * 0.10
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
			# The dock (mTail1) takes the strongest impulse; the wave lags slightly down the chain.
			var wave := sin(_thrust_clock * JIGGLE_FREQ - float(i) * 0.55)
			var impulse := _thrust_strength * thrust_envelope * wave * weight * falloff
			pose.basis = Basis(right, lift_sign * impulse * JIGGLE_PITCH) * pose.basis
			pose.basis = Basis(up, impulse * JIGGLE_YAW) * pose.basis
		sk.set_bone_global_pose(bone, pose)
