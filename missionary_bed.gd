extends Node
## integration: optional Anon bed body, ported from PonyPussyParadise. With the flag off it is not
## created and the current missionary camera is untouched. With it on, Anon's own body is placed
## on the bed from her anatomy and the frozen view follows his eyes.

const ANON_THRUST := preload("res://mods/unfplap/anon_thrust.gd")
const CAESS := preload("res://mods/unfplap/standing_caress.gd")

var runtime: Node
var main: Node
var pony: Node3D
var avatar: Node3D
var _driver: Node3D
var _original: Node
var _hip: Node3D
var _head: Node3D
var _left_foot: Node3D
var _right_foot: Node3D
var _legs: SkeletonModifier3D
var _leg_influence := 0.0
var _avatar_visible := true
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _body := Basis.IDENTITY


func install(runtime_node: Node) -> bool:
	remove()
	runtime = runtime_node
	main = runtime.get("main")
	pony = runtime.get("pony")
	if not is_instance_valid(main) or not is_instance_valid(main.player) \
			or not is_instance_valid(pony):
		return false
	avatar = main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return false
	_original = avatar.get("desktop_pose_driver")
	if not is_instance_valid(_original):
		return false
	_avatar_visible = avatar.visible
	_driver = ANON_THRUST.new()
	_driver.name = "UnfplapBedAnonThrust"
	_driver.set("original", _original)
	_driver.set("runtime", runtime)
	main.player.add_child(_driver)
	avatar.set("desktop_pose_driver", _driver)
	_hip = avatar.get("_hip_target") as Node3D
	_head = avatar.get("_head_target") as Node3D
	_left_foot = avatar.get("_left_foot") as Node3D
	_right_foot = avatar.get("_right_foot") as Node3D
	var legs: Variant = avatar.get("_leg_hide")
	if legs is SkeletonModifier3D:
		_legs = legs as SkeletonModifier3D
		_leg_influence = _legs.influence
		_legs.influence = 0.0
	avatar.visible = true
	return is_instance_valid(_hip)


func active() -> bool:
	return is_instance_valid(_driver) and is_instance_valid(_hip)


func apply(hip: Node3D, _facing: Basis) -> void:
	if not active() or not is_instance_valid(hip):
		return
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	var act: Variant = runtime.get("_anatomy_act")
	if not is_instance_valid(part) or not bool(part.call("showing")) or not is_instance_valid(act):
		return
	var opening: Vector3 = act.call("hole_point")
	var rear: Vector3 = act.call("hole_rear")
	if rear.length_squared() < 0.0001:
		return
	var unit_rear := rear.normalized()
	var forward := Vector3(-unit_rear.x, 0.0, -unit_rear.z).normalized()
	var level := Basis.looking_at(forward, Vector3.UP, true)
	var aim := Quaternion(level * (part.call("axis") as Vector3), -unit_rear)
	var square := Basis(Quaternion.IDENTITY.slerp(aim, 1.0)) * level
	var depth := clampf(float(runtime.get("depth")), 0.0, 1.0)
	var root: Vector3 = part.call("root_for", opening, unit_rear, depth)
	var wanted: Vector3 = part.call("hip_for", root, square)
	var amount := clampf(float(runtime.call("_pose_basis_amount")), 0.0, 1.0)
	hip.global_position = hip.global_position.lerp(wanted, amount)
	hip.global_basis = hip.global_basis.orthonormalized().slerp(square, amount)
	_body = square
	if is_instance_valid(_head):
		var spine: float = float(part.call("spine_length"))
		var lean: float = float(runtime.call("_anon_torso_forward"))
		var ahead := -unit_rear * (spine * 0.82 + lean)
		var head_at := hip.global_position + ahead + Vector3.UP * maxf(0.05, spine * 0.55)
		_head.global_position = _head.global_position.lerp(head_at, amount)
		_eye = head_at + (Vector3.UP * 0.089 - forward * 0.05) \
			* float(runtime.call("_size_scale"))
		_look = opening
	# integration: his hands rest beside her ribs on the mattress.
	var camera: Variant = runtime.call("_missionary_camera_controller")
	if camera != null and camera.has_method("_bed_surface_top") and is_instance_valid(_driver):
		var top: Variant = camera.call("_bed_surface_top")
		if top is float and is_finite(top):
			var centre := opening - forward * 0.12
			for pair: Array in [["left", -1.0], ["right", 1.0]]:
				var at := Vector3(centre.x, top + 0.02, centre.z) + forward.cross(Vector3.UP) \
					* float(pair[1]) * 0.16
				_driver.call("set_hold_target", pair[0],
					Transform3D(CAESS.palm_surface_basis(pair[0], Vector3.UP, forward), at), "rub")


func tick_view() -> void:
	if not active() or _eye == Vector3.ZERO:
		return
	var camera: Variant = runtime.call("_missionary_camera_controller")
	if camera == null or not camera.has_method("view"):
		return
	var view: Camera3D = (camera.call("view") as Camera3D)
	if not is_instance_valid(view):
		return
	var rear := Vector3(-_body.z.x, 0.0, -_body.z.z).normalized()
	var up := (rear + Vector3.UP * 0.5).normalized()
	view.global_position = view.global_position.lerp(_eye, 0.85)
	view.global_basis = view.global_basis.orthonormalized().slerp(
		Basis.looking_at(_look - _eye, up), 0.85)


func remove() -> void:
	if is_instance_valid(avatar) and is_instance_valid(_original) \
			and avatar.get("desktop_pose_driver") == _driver:
		avatar.set("desktop_pose_driver", _original)
	if is_instance_valid(_legs):
		_legs.influence = _leg_influence
	if is_instance_valid(avatar):
		avatar.visible = _avatar_visible
	if is_instance_valid(_driver):
		_driver.queue_free()
	_driver = null
	_original = null
	_hip = null
	_head = null
	_legs = null
	_eye = Vector3.ZERO
	_look = Vector3.ZERO
	_body = Basis.IDENTITY
