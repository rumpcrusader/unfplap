extends "res://mods/unfplap/tests/support/suite.gd"
## The act frame's player contract: the pure solve for one standing and one missionary start, and
## the plan's player-only shape. The live placement stays pinned by the teardown suite.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_frame/test_frame.gd

const FRAME := preload("res://mods/unfplap/act/frame.gd")
const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")



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


func near(a: float, b: float, epsilon := 0.0001) -> bool:
	return absf(a - b) <= epsilon


func run() -> void:
	_check_standing()
	_check_missionary()
	_check_head_clearance()
	_check_publish()
	_check_scene_token()
	_check_canonical_start()
	_check_world_aim()
	_check_round_trip()
	_check_plan_shape()
	if failures == 0:
		print("ACT_FRAME_PASS")
	finish()


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


## The bed plan carries the pad his head keeps out of her skull and muzzle; a standing act has none.
func _check_head_clearance() -> void:
	var frame := FRAME.new()
	var rig := FRAME.Rig.new()
	rig.head_clearance = 0.05
	rig.act_body_transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.5, 2.0))
	var plan := frame.solve(FRAME.pose("missionary"), rig)
	check(near(plan.head_clearance, 0.05), "the bed plan carries the head clearance")
	var standing := FRAME.Rig.new()
	standing.head_clearance = 0.05
	standing.forward = Vector3(0.0, 0.0, -1.0)
	standing.eye = 1.6
	standing.neck_height = 1.4
	var stand_plan := frame.solve(FRAME.pose("standing"), standing)
	check(near(stand_plan.head_clearance, 0.0),
		"a standing act carries no head clearance")


## The solved plan's player values reach the typed view the live modules read.
func _check_publish() -> void:
	var facts: RefCounted = FACTS.new()
	var context := ACT_CONTEXT.new()
	context.facts = facts
	var frame := FRAME.new()
	frame.bind(ACT_HOST.new(), context, ACT_SESSION.new())
	var rig := FRAME.Rig.new()
	rig.head_clearance = 0.05
	frame.begin(FRAME.pose("missionary"), rig)
	check(near(float(facts.head_clearance), 0.05),
		"the bed plan publishes the head clearance for the live view")
	frame.end()
	var standing := FRAME.Rig.new()
	standing.forward = Vector3(0.0, 0.0, -1.0)
	standing.gap = 0.42
	standing.eye = 1.6
	standing.neck_height = 1.4
	frame.begin(FRAME.pose("standing"), standing)
	check(near(float(facts.player_eye_height), 1.6),
		"the standing plan publishes his eye line")
	check(near(float(facts.head_clearance), 0.0),
		"a standing act publishes no head clearance")
	frame.end()


## The frame keeps the scene the act found: the player, her and the bed, and a moving bed carries
## the whole restore with it.
func _check_scene_token() -> void:
	var player := FakePlayer.new()
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	root.add_child(player)
	WORLD.bind_player(player)
	var pony := Node3D.new()
	root.add_child(pony)
	var bed := Node3D.new()
	root.add_child(bed)
	var host := ACT_HOST.new()
	host.bind(root)
	host.pony = pony
	var session := ACT_SESSION.new()
	session.bed = bed
	var frame := FRAME.new()
	frame.bind(host, ACT_CONTEXT.new(), session)
	player.global_position = Vector3(1.0, 0.0, 2.0)
	pony.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(3.0, 0.0, 4.0))
	bed.global_position = Vector3(5.0, 0.0, 6.0)
	frame.snapshot_scene()
	player.global_position = Vector3.ZERO
	pony.global_position = Vector3.ZERO
	bed.global_position = Vector3(5.5, 0.0, 6.0)
	frame.restore_scene()
	check(player.global_position.is_equal_approx(Vector3(1.5, 0.0, 2.0)),
		"the scene token puts the player back with the bed")
	check(pony.global_position.is_equal_approx(Vector3(3.5, 0.0, 4.0)),
		"the scene token puts her back with the bed")
	root.remove_child(player)
	root.remove_child(pony)
	root.remove_child(bed)
	player.free()
	pony.free()
	bed.free()


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
	check(names.has("head_clearance"), "the plan carries the head clearance")
	check(not names.has("fit"),
		"the plan carries no whole-body fit")
	check(not names.has("camera_transform") and not names.has("shot"),
		"the plan carries no camera transform or shot")
