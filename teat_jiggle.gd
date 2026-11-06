extends Node
## integration: ported from PonyPussyParadise teat_jiggle.gd. Springy sway for the teats mesh. It
## only offsets the mesh in its shader; her own skin carries the shape through her poses.

const STIFFNESS := 130.0
const DAMPING := 7.0
const INERTIA := 0.08
const MAX_ACCELERATION := 60.0
const TELEPORT_SPEED := 6.0
const KICK_SPEED := 0.12
const MAX_SWAY_M := 0.014

var material: ShaderMaterial
var skeleton: Skeleton3D
## integration: bigger ones swing further.
var swing := 1.0

var _hips := -1
var _sides := [{"uniform": "sway_left", "lag": Vector3.ZERO, "speed": Vector3.ZERO},
	{"uniform": "sway_right", "lag": Vector3.ZERO, "speed": Vector3.ZERO}]
var _last_position := Vector3.INF
var _last_velocity := Vector3.ZERO


## integration: a thrust pushes both along the body, by stroke strength from 0 to 1.
func kick(direction: Vector3, strength: float) -> void:
	for side: Dictionary in _sides:
		side.speed += direction * KICK_SPEED * swing * clampf(strength, 0.0, 1.0) \
			* (0.8 + randf() * 0.4)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(skeleton) or not is_instance_valid(material) or delta <= 0.0:
		return
	if _hips < 0:
		_hips = skeleton.find_bone("pony_hips")
		if _hips < 0:
			return
	var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(_hips).origin
	var velocity := Vector3.ZERO if _last_position == Vector3.INF else (at - _last_position) / delta
	if velocity.length() > TELEPORT_SPEED:
		velocity = Vector3.ZERO
	var acceleration := ((velocity - _last_velocity) / delta).limit_length(MAX_ACCELERATION)
	_last_position = at
	_last_velocity = velocity
	var to_local := skeleton.global_basis.inverse()
	for side: Dictionary in _sides:
		var lag: Vector3 = side.lag
		var speed: Vector3 = side.speed
		speed += (-acceleration * INERTIA * swing - lag * STIFFNESS - speed * DAMPING) * delta
		lag = (lag + speed * delta).limit_length(MAX_SWAY_M * swing)
		side.lag = lag
		side.speed = speed
		material.set_shader_parameter(side.uniform, to_local * lag)
