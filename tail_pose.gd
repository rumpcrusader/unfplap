extends SkeletonModifier3D
## Moves the tail aside and slightly up for the standing presentation, and can flick it.
## Runs on the hair skeleton after hybrid_tail_motion; only rotates bones.
##
## The side is chosen per act by `choose_side()` so the tail does not always sweep the same way.

const ASIDE_ANGLE := 0.55
const LIFT_ANGLE := 0.34
var aside_angle := ASIDE_ANGLE
var lift_angle := LIFT_ANGLE
const FLICK_SECONDS := 0.9
const FLICK_AMPLITUDE := 1.10

var mare: Node3D
var amount := 0.0
var target_amount := 0.0
## +1 or -1: which way the tail sweeps. Randomized per act.
var aside_sign := 1.0

var _bones: Array[int] = []
var _cached := false
var _flick_time := -1.0
var _flick_cycles := 2.0


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


## Two quick up/down swings. Called when the pose 2 afterglow starts.
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
	return sin(t * TAU * _flick_cycles) * FLICK_AMPLITUDE * sin(t * PI)


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
		sk.set_bone_global_pose(bone, pose)
