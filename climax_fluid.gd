extends Node3D
## integration: ported from PonyPussyParadise climax_fluid.gd. Droplets with real motion: they fly
## under gravity and drag, stick where they hit her body and creep down it, drop off her underside,
## and pool on the ground before fading. Her body is an ellipsoid that rides her hips, so stuck
## drops move with her.

const MAX_DROPS := 220
const GRAVITY := 3.4
const DRAG := 0.5
const CREEP := 0.035
const POOL_SECONDS := 16.0
const FADE_SECONDS := 4.0
const LET_GO := -0.72
## integration: her rear half in the shared body's rest space, scaled by the pony's body_scale.
const BODY_CENTRE := Vector3(0.0, 0.47, 0.12)
const BODY_RADII := Vector3(0.165, 0.175, 0.215)

enum { FLYING, STUCK, POOLED }

var skeleton: Skeleton3D
var ground_y := 0.0
## integration: the shared body ellipsoid is authored at scale 1.
var body_scale := 1.0
var runtime: Node

var _hips := -1
var _drops: Array[Dictionary] = []
var _leaks: Array[Dictionary] = []
var _multi: MultiMesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 5
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	material.metallic_specular = 0.9
	material.emission_enabled = true
	material.emission = Color(0.34, 0.34, 0.32)
	mesh.material = material
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.mesh = mesh
	_multi.instance_count = MAX_DROPS
	_multi.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = _multi
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.custom_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)
	add_child(view)


func _centre() -> Vector3:
	return BODY_CENTRE * body_scale


func _radii() -> Vector3:
	return BODY_RADII * body_scale


func spray(at: Vector3, direction: Vector3, count: int, speed: float, size: float, color: Color) -> void:
	for i in count:
		var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.2
		var along := (direction.normalized() + spread).normalized()
		_add(at, along * speed * randf_range(0.55, 1.0), size * randf_range(0.7, 1.3), color)


func drip(source: Callable, seconds: float, per_second: float, size: float, color: Color) -> void:
	_leaks.append({"source": source, "left": seconds, "rate": per_second, "due": 0.0,
		"size": size, "color": color})


func clear() -> void:
	_drops.clear()
	_leaks.clear()
	if is_instance_valid(_multi):
		_multi.visible_instance_count = 0


func _add(at: Vector3, velocity: Vector3, size: float, color: Color) -> void:
	if _drops.size() >= MAX_DROPS:
		_drops.remove_at(0)
	_drops.append({"at": at, "velocity": velocity, "size": size, "color": color, "state": FLYING,
		"local": Vector3.ZERO, "age": 0.0})


## integration: rest space to the world through her hips, as they are posed now.
func _body_frame() -> Transform3D:
	if not is_instance_valid(skeleton):
		return Transform3D.IDENTITY
	if _hips < 0:
		_hips = skeleton.find_bone("pony_hips")
	if _hips < 0:
		return skeleton.global_transform
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hips) \
		* skeleton.get_bone_global_rest(_hips).affine_inverse()


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	for leak: Dictionary in _leaks:
		leak.left -= delta
		leak.due += delta * float(leak.rate)
		while leak.due >= 1.0:
			leak.due -= 1.0
			var point: Vector3 = (leak.source as Callable).call()
			_add(point, Vector3(randf_range(-0.03, 0.03), -0.05, randf_range(-0.03, 0.03)),
				float(leak.size) * randf_range(0.8, 1.25), leak.color)
	_leaks = _leaks.filter(func(leak: Dictionary) -> bool:
		return leak.left > 0.0 and (leak.source as Callable).is_valid())
	var frame := _body_frame()
	var inverse := frame.affine_inverse()
	var kept: Array[Dictionary] = []
	for drop: Dictionary in _drops:
		drop.age += delta
		match int(drop.state):
			FLYING:
				_fly(drop, frame, inverse, delta)
			STUCK:
				_creep(drop, frame, inverse, delta)
		if int(drop.state) != POOLED or float(drop.age) < POOL_SECONDS + FADE_SECONDS:
			kept.append(drop)
	_drops = kept
	_draw_drops()
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "climax_fluid", Time.get_ticks_usec() - started)


func _fly(drop: Dictionary, frame: Transform3D, inverse: Transform3D, delta: float) -> void:
	var velocity: Vector3 = drop.velocity
	velocity += Vector3.DOWN * GRAVITY * delta - velocity * DRAG * delta
	var at: Vector3 = drop.at + velocity * delta
	drop.velocity = velocity
	drop.at = at
	if at.y <= ground_y + 0.002:
		drop.at = Vector3(at.x, ground_y + 0.002, at.z)
		drop.state = POOLED
		drop.age = 0.0
		return
	var local: Vector3 = inverse * at
	var inside: Vector3 = (local - _centre()) / _radii()
	if inside.length() < 1.0:
		drop.local = _centre() + inside.normalized() * _radii()
		drop.state = STUCK
		drop.at = frame * (drop.local as Vector3)


func _creep(drop: Dictionary, frame: Transform3D, inverse: Transform3D, delta: float) -> void:
	var local: Vector3 = drop.local
	var unit: Vector3 = ((local - _centre()) / _radii()).normalized()
	var normal: Vector3 = (unit / _radii()).normalized()
	var down: Vector3 = (inverse.basis * Vector3.DOWN).normalized()
	var slide := down - normal * down.dot(normal)
	local += slide * CREEP * delta
	drop.local = _centre() + ((local - _centre()) / _radii()).normalized() * _radii()
	drop.at = frame * (drop.local as Vector3)
	if normal.dot(-down) < LET_GO:
		drop.state = FLYING
		drop.velocity = Vector3.DOWN * 0.1


func _draw_drops() -> void:
	_multi.visible_instance_count = _drops.size()
	for i in _drops.size():
		var drop: Dictionary = _drops[i]
		var size: float = drop.size
		var shape := Basis.IDENTITY.scaled(Vector3.ONE * size)
		var color: Color = drop.color
		match int(drop.state):
			FLYING:
				var velocity: Vector3 = drop.velocity
				if velocity.length() > 0.2:
					var along := velocity.normalized()
					var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
					shape = Basis(side, along.cross(side), along) * Basis.IDENTITY.scaled(
						Vector3(size, size, size * (1.0 + minf(velocity.length(), 2.0))))
			POOLED:
				var fade := clampf((POOL_SECONDS + FADE_SECONDS - float(drop.age)) / FADE_SECONDS,
					0.0, 1.0)
				var spread := size * (1.8 + minf(float(drop.age), 3.0) * 0.4)
				shape = Basis.IDENTITY.scaled(Vector3(spread, size * 0.25, spread))
				color.a *= fade
		_multi.set_instance_transform(i, Transform3D(shape, drop.at))
		_multi.set_instance_color(i, color)
