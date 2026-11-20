extends SceneTree
## The act frame's player contract: the pure solve for one standing and one missionary start, and
## the plan's player-only shape. The live placement stays pinned by the teardown suite.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_frame/test_frame.gd

const FRAME := preload("res://mods/unfplap/act/frame.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")

var failures := 0
var checks := 0


class FakePlayer extends Node3D:
	var camera: Camera3D = null
	var form_driver: Variant = null
	var _pitch := 0.0
	var _stand_eye := 1.6
	var _eye_height := 1.6
	var eye_pushes: Array[float] = []

	func eye_height() -> float:
		return _stand_eye

	func _set_eye_y(value: float) -> void:
		eye_pushes.append(value)
		if camera != null:
			camera.position.y = value


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, epsilon := 0.0001) -> bool:
	return absf(a - b) <= epsilon


func run() -> void:
	_check_standing()
	_check_missionary()
	_check_canonical_start()
	_check_world_aim()
	_check_round_trip()
	_check_plan_shape()
	print("ACT_FRAME_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FRAME_PASS")
	quit(0 if failures == 0 else 1)


## Her forward is -Z and the gap is 0.42 m: Anon lands exactly on her centreline behind her,
## with no whole-body fit pulling him into the rump.
func _check_standing() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("standing")
	check(pose.family == "standing", "the standing row names its family")
	var rig := FRAME.Rig.new()
	rig.forward = Vector3(0.0, 0.0, -1.0)
	rig.pony_position = Vector3(0.0, 0.0, 0.0)
	rig.player_position = Vector3(0.0, 0.0, 0.42)
	rig.gap = 0.42
	rig.eye = 1.6
	rig.neck_height = 1.4
	var plan := frame.solve(pose, rig)
	check(plan.family == "standing", "the standing solve keeps its family")
	check(near(plan.gap, 0.42), "the solve carries the act gap")
	check(plan.root_transform.origin.is_equal_approx(Vector3(0.0, 0.0, 0.42)),
		"the standing plan places Anon at the gap, centered behind her")
	check(near(plan.yaw, 0.0), "the standing plan faces Anon along her forward")
	check(near(plan.aim_pitch, atan2(1.4 - 1.6, 0.42)),
		"the standing plan aims at her neck line from the placed eye")
	check(near(plan.look_yaw, plan.yaw) and near(plan.look_pitch, plan.aim_pitch),
		"the plan owns the captured look")
	check(near(plan.eye, 1.6), "the plan carries the stance eye")


## The missionary plan carries the act body's placement only: the player rig stays parked.
func _check_missionary() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("missionary")
	check(pose.family == "bed", "the missionary row names its family")
	var rig := FRAME.Rig.new()
	rig.act_body_transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.5, 2.0))
	var plan := frame.solve(pose, rig)
	check(plan.family == "bed", "the missionary solve keeps its family")
	check(plan.act_body_transform.is_equal_approx(rig.act_body_transform),
		"the missionary plan places the act body from the asset")
	check(plan.root_transform.is_equal_approx(Transform3D.IDENTITY),
		"the missionary plan never moves the player rig")


## Two starts from the same pony, pose and stance but from different pre-act positions and looks
## produce the same plan: the solve reads the canonical stance, never the old view.
func _check_canonical_start() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("standing")
	var first := _stance_rig(Vector3(0.0, 0.0, 0.9), 0.3, 0.2)
	var second := _stance_rig(Vector3(2.0, 0.0, -1.0), -1.2, -0.5)
	var plan_a := frame.solve(pose, first)
	var plan_b := frame.solve(pose, second)
	check(plan_a.root_transform.is_equal_approx(plan_b.root_transform),
		"the pre-act position does not move the solved player root")
	check(near(plan_a.yaw, plan_b.yaw) and near(plan_a.aim_pitch, plan_b.aim_pitch),
		"the pre-act look does not move the solved aim")
	check(near(frame.stance_eye(first), 1.7) and near(frame.stance_eye(second), 1.7),
		"the standing eye line ignores the pre-act look")
	check(near(plan_a.root_transform.origin.z, 0.42),
		"the canonical placement keeps the base gap")
	first.player.free()
	second.player.free()


## Her authored neck above his eye is a world-space aim: the same stance at a different world
## height must not change the pitch (the old local/world mix clamped it at 57 degrees).
func _check_world_aim() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("standing")
	var low := _stance_rig(Vector3(0.0, -11.25, 0.42), 0.3, 0.2)
	low.pony_position = Vector3(0.0, -11.25, 0.0)
	low.neck_point = Vector3(0.0, -9.9, 0.0)
	var high := _stance_rig(Vector3(0.0, -1.25, 0.42), 0.3, 0.2)
	high.pony_position = Vector3(0.0, -1.25, 0.0)
	high.neck_point = Vector3(0.0, 0.1, 0.0)
	var plan_low := frame.solve(pose, low)
	var plan_high := frame.solve(pose, high)
	check(plan_low.aim_pitch > -1.0 and plan_low.aim_pitch < 0.0,
		"the world neck aim stays inside the clamp")
	check(near(plan_low.aim_pitch, plan_high.aim_pitch),
		"the aim is invariant to a world-height shift")
	low.player.free()
	high.player.free()


## A start places the player and a matching end gives him back: the eye line always, the look only
## for a bed act.
func _check_round_trip() -> void:
	var player := FakePlayer.new()
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	root.add_child(player)
	WORLD.bind_player(player)
	player.rotation.y = 0.3
	player._pitch = 0.2
	player._stand_eye = 1.7
	player._eye_height = 1.7
	var frame := FRAME.new()
	var rig := FRAME.Rig.new()
	rig.player = player
	rig.forward = Vector3(0.0, 0.0, -1.0)
	rig.pony_position = Vector3.ZERO
	rig.player_position = player.global_position
	rig.gap = 0.42
	rig.eye = 1.6
	rig.neck_height = 1.4
	var plan := frame.begin(FRAME.pose("standing"), rig)
	check(near(player.rotation.y, plan.yaw) and near(player._pitch, plan.aim_pitch),
		"the start writes the plan's stance on the player")
	check(near(player._stand_eye, 1.6) and near(player.camera.rotation.x, plan.aim_pitch),
		"the start writes the stance eye and the camera follows")
	check(player.global_position.is_equal_approx(plan.root_transform.origin),
		"the start writes the plan's root")
	frame.end()
	check(near(player._stand_eye, 1.7) and near(player._eye_height, 1.7),
		"the end restores the player's own eye line")
	check(near(player.rotation.y, plan.yaw),
		"a standing end leaves Anon facing where the act ended")
	var eye_pushes := player.eye_pushes.size()
	frame.end()
	check(player.eye_pushes.size() == eye_pushes, "a second end is a no-op")

	player.rotation.y = 0.4
	player._pitch = 0.1
	var bed_rig := FRAME.Rig.new()
	bed_rig.player = player
	frame.begin(FRAME.pose("missionary"), bed_rig)
	player.rotation.y = 1.1
	player._pitch = -0.3
	frame.end()
	check(near(player.rotation.y, 0.4) and near(player._pitch, 0.1),
		"a bed end restores the player's captured look")
	root.remove_child(player)
	player.free()


## One canonical standing rig: her forward and gap, and the pre-act player position and look
## carried only as the old stance.
func _stance_rig(player_at: Vector3, look_yaw: float, look_pitch: float) -> FRAME.Rig:
	var rig := FRAME.Rig.new()
	rig.player = _fake_player(look_yaw, look_pitch)
	rig.forward = Vector3(0.0, 0.0, -1.0)
	rig.pony_position = Vector3.ZERO
	rig.player_position = player_at
	rig.gap = 0.42
	rig.eye = 1.6
	rig.neck_height = 1.4
	return rig


func _fake_player(look_yaw: float, look_pitch: float) -> FakePlayer:
	var player := FakePlayer.new()
	player.rotation.y = look_yaw
	player._pitch = look_pitch
	player._stand_eye = 1.7
	player._eye_height = 1.7
	return player


## The plan is player-only: it carries no camera transform, shot or eye-override step.
func _check_plan_shape() -> void:
	var names: Array[String] = []
	for field: Dictionary in FRAME.PlayerPlan.new().get_property_list():
		names.append(str(field["name"]))
	check(names.has("root_transform") and names.has("yaw") and names.has("aim_pitch"),
		"the plan carries the player placement and look")
	check(names.has("stand_eye") and names.has("eye_height"),
		"the plan carries the standing stance")
	check(not names.has("fit"),
		"the plan carries no whole-body fit")
	check(not names.has("camera_transform") and not names.has("shot"),
		"the plan carries no camera transform or shot")
