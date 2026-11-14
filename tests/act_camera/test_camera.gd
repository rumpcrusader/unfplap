extends SceneTree
## The act camera facade: the lean and its smoothing, the shot response, the free look, the
## free-camera lock, the eye override, the captured look and the shot geometry helpers.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_camera/test_camera.gd

const CAMERA := preload("res://mods/unfplap/camera/service.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_AFTERGLOW := 4

var failures := 0
var checks := 0


class FakeMain extends Node:
	var player: Variant = null
	var view: Camera3D = null

	func camera() -> Camera3D:
		return view


class FakePlayer extends Node:
	var rotation := Vector3.ZERO
	var _stand_eye: Variant = 1.7
	var _eye_height: Variant = 1.7
	var _pitch: Variant = 0.0
	var controls_locked := false
	var mouse_sensitivity := 0.0022
	var invert_y := false
	var seat: Variant = null
	var form_driver: Variant = null

	func eye_height() -> float:
		return float(_stand_eye)


class FakeHands extends RefCounted:
	var calls: Array[String] = []

	func return_tick() -> void:
		calls.append("return_tick")

	func stop_inputs() -> void:
		calls.append("stop_inputs")

	func tick(_delta: float) -> void:
		calls.append("tick")

	func reset() -> void:
		calls.append("reset")

	func start_reach(side: String) -> void:
		calls.append("start_reach:" + side)

	func end_reach() -> void:
		calls.append("end_reach")


class FakeKiss extends RefCounted:
	var calls: Array[String] = []

	func lean_kiss_tick() -> void:
		calls.append("lean_kiss_tick")

	func reset() -> void:
		calls.append("reset")


class FakeStandingCamera extends RefCounted:
	var calls: Array[String] = []

	func apply_lean_look() -> void:
		calls.append("apply_lean_look")

	func hold_glance() -> void:
		calls.append("hold_glance")

	func clear_glance() -> void:
		calls.append("clear_glance")

	func tick() -> void:
		calls.append("tick")


class FakePony extends Node3D:
	var skeleton: Variant = null


class FakeMissionaryCamera extends RefCounted:
	var calls: Array[String] = []

	func tick() -> void:
		calls.append("tick")

	func snapshot_yaw() -> float:
		return NAN


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _fixture() -> Dictionary:
	var main := FakeMain.new()
	var player := FakePlayer.new()
	main.add_child(player)
	main.player = player
	main.view = Camera3D.new()
	main.add_child(main.view)
	root.add_child(main)
	var facts: RefCounted = FACTS.new()
	facts.main = main
	facts.player_pony = false
	facts.state = STATE_ACTIVE
	facts.pose_id = CATALOG.MISSIONARY
	facts.features = {"idle_camera_sway": false}
	var camera: RefCounted = CAMERA.new()
	var hands := FakeHands.new()
	var kiss := FakeKiss.new()
	var standing := FakeStandingCamera.new()
	var missionary := FakeMissionaryCamera.new()
	camera.bind(facts, hands, kiss, standing, missionary)
	return {
		"camera": camera, "facts": facts, "main": main, "player": player,
		"hands": hands, "kiss": kiss, "standing": standing, "missionary": missionary,
	}


func run() -> void:
	_check_session()
	_check_shot()
	_check_lean()
	_check_oral_lean()
	_check_lock_and_eye()
	_check_look()
	_check_free_look()
	_check_motion()
	_check_neck()

	print("ACT_CAMERA_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_CAMERA_PASS")
	quit(0 if failures == 0 else 1)


func _check_session() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	camera.call("configure", {"surge": 0.5, "bob": 0.25})
	check(near(camera.camera_surge, 0.5) and near(camera.camera_bob, 0.25),
		"the camera_thrust block reaches the facade")
	camera.call("configure", {})
	check(near(camera.camera_surge, 1.0) and near(camera.camera_bob, 0.35),
		"an empty block falls back to the shipped defaults")
	camera.lean = 0.2
	camera.bob = 0.2
	camera.back = 0.2
	camera.call("begin_session", CATALOG.MISSIONARY)
	check(not camera.camera_owned and not camera.look_captured, "a fresh session owns nothing")
	check(camera.look_restore_yaw, "missionary restores the captured yaw")
	check(near(camera.lean, 0.0) and near(camera.bob, 0.0) and near(camera.back, 0.0),
		"a fresh session starts the shot from rest")
	camera.call("begin_session", CATALOG.STANDING)
	check(not camera.look_restore_yaw, "standing leaves Anon facing where the act ends")
	camera.call("open_shot")
	check(camera.camera_owned and not camera.free_camera_active,
		"the shot opens before the desktop free camera")
	camera.lean_view_forward = 0.8
	camera.call("open_shot")
	check(near(camera.lean_view_forward, 0.0), "opening the shot resets the lean")
	camera.call("begin_free")
	check(camera.free_camera_active, "the free shot takes the camera")
	check(camera.camera == (made["main"] as FakeMain).view, "the free shot grabs the player camera")
	camera.call("close_shot")
	check(camera.camera == null, "closing the shot drops the camera")


func _check_shot() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	camera.call("configure", {"surge": 1.0, "bob": 1.0})
	for i in 200:
		camera.call("tick_shot", 0.02, STATE_ACTIVE, 4.0, 0.0)
	check(near(camera.lean, CAMERA.CAM_SURGE_M, 0.002),
		"a full-speed stroke reaches the authored surge")
	check(near(camera.bob, -CAMERA.CAM_BOB_M, 0.002),
		"a full-speed stroke dips the camera toward her")
	for i in 200:
		camera.call("tick_shot", 0.02, STATE_ACTIVE, -4.0, 0.0)
	check(near(camera.lean, -CAMERA.CAM_SURGE_M * CAMERA.CAM_BACK_RATIO, 0.002),
		"an outward stroke moves half the travel back")
	camera.back_target = 0.2
	for i in 60:
		camera.call("tick_shot", 0.02, STATE_ACTIVE, 0.0, 0.0)
	check(near(camera.back, 0.2, 0.0001), "the afterglow back-off eases out")
	camera.call("release_back")
	camera.back_target = 0.0
	for i in 60:
		camera.call("tick_shot", 0.02, STATE_ACTIVE, 0.0, 0.0)
	check(near(camera.back, 0.0, 0.0001), "the restore releases the back-off")
	for i in 200:
		camera.call("tick_shot", 0.02, STATE_AFTERGLOW, 0.0, 0.0)
	check(near(camera.lean, 0.0, 0.0001), "the shot settles when the stroke stops")
	for i in 20:
		camera.call("tick_shot", 0.02, 3, 0.0, 0.125)
	check(absf(camera.lean) > 0.0, "the climax wave moves the shot")
	camera.lean_sway = 0.02
	camera.lean_view_forward = 0.5
	check(near(camera.call("shot_lean_forward"), 0.52), "the shot adds the idle sway once")
	camera.lean_view_forward = 1.0
	camera.lean_sway = 0.5
	check(near(camera.call("shot_lean_forward"), 1.0), "the shot lean clamps at one")


func _check_lean() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var hands: FakeHands = made["hands"]
	var kiss: FakeKiss = made["kiss"]
	camera.call("open_shot")
	camera.call("begin_free")
	facts.state = STATE_IDLE
	hands.calls.clear()
	camera.call("tick_lean", 0.1, false, false)
	check(hands.calls.has("stop_inputs"), "an idle state drops the caress input")
	check(near(camera.lean_view_forward, 0.0) and near(camera.lean_view_side, 0.0),
		"an idle state holds the lean at rest")
	check(not bool(camera.call("at_actions_allowed")), "idle allows no act actions")
	facts.state = STATE_ACTIVE
	check(bool(camera.call("at_actions_allowed")), "an active act allows the lean")
	facts.state = STATE_AFTERGLOW
	check(bool(camera.call("at_actions_allowed")), "afterglow keeps the lean live")

	# The pose action latch: 75 percent fires, 60 percent releases.
	facts.state = STATE_ACTIVE
	facts.pose_id = CATALOG.MISSIONARY
	camera.lean_side = 0.74
	camera.call("tick_lean_action")
	check(not camera.lean_action_active, "below 75 percent fires no action")
	camera.lean_side = -0.75
	camera.call("tick_lean_action")
	check(camera.lean_action_active, "75 percent fires the action")
	check(camera.lean_action_kind == "", "missionary Q fires no pose action")
	camera.lean_side = -0.65
	camera.call("tick_lean_action")
	check(camera.lean_action_active, "the action holds above 60 percent")
	camera.lean_side = -0.60
	camera.call("tick_lean_action")
	check(not camera.lean_action_active, "the action releases at 60 percent")

	# Standing fires the shoulder reach with the glance hold and the hand.
	facts.pose_id = CATALOG.STANDING
	hands.calls.clear()
	var standing: FakeStandingCamera = made["standing"]
	standing.calls.clear()
	camera.lean_side = 0.8
	camera.call("tick_lean_action")
	check(camera.lean_action_active and camera.lean_action_kind == "reach",
		"standing fires the shoulder reach")
	check(hands.calls.has("start_reach:R"), "the reach starts on the lean side")
	check(standing.calls.has("hold_glance"), "the reach holds the over-the-shoulder glance")
	camera.lean_side = 0.0
	camera.call("tick_lean_action")
	check(hands.calls.has("end_reach") and standing.calls.has("clear_glance"),
		"releasing the reach clears the glance")

	# A fresh lean state drops the hands and the kiss.
	hands.calls.clear()
	kiss.calls.clear()
	camera.lean_forward = 1.0
	camera.call("reset_lean_state")
	check(hands.calls.has("reset") and kiss.calls.has("reset"),
		"the lean reset drops the hands and the kiss")
	check(near(camera.lean_forward, 0.0), "the lean reset returns to rest")


## Oral locks the body: no lean, no Q/E reach and no F lean kiss, while the caress keeps running.
func _check_oral_lean() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var hands: FakeHands = made["hands"]
	var kiss: FakeKiss = made["kiss"]
	var standing: FakeStandingCamera = made["standing"]
	facts.pose_id = CATALOG.STANDING
	facts.oral_active = true
	camera.lean_forward = 0.7
	camera.lean_side = -0.6
	camera.lean_view_forward = 0.7
	camera.lean_view_side = -0.6
	camera.lean_sway = 0.02
	camera.side_return_armed = true
	camera.lean_action_active = true
	camera.lean_action_kind = "reach"
	camera.lean_action_side = 0.8
	hands.calls.clear()
	kiss.calls.clear()
	standing.calls.clear()
	camera.call("oral_lean_tick", 0.1)
	check(not camera.lean_action_active, "oral ends an active lean action")
	check(hands.calls.has("end_reach"), "oral releases an active shoulder reach")
	check(standing.calls.has("clear_glance"), "oral clears the reach glance")
	check(camera.lean_forward < 0.7 and camera.lean_side > -0.6,
		"oral returns the lean toward rest")
	check(near(camera.lean_sway, 0.0), "oral zeroes the idle sway")
	check(not camera.side_return_armed, "oral drops the side return latch")
	check(kiss.calls.has("lean_kiss_tick"), "oral runs the lean kiss release")
	check(hands.calls.has("tick"), "oral keeps ticking the caress hands")
	check(not hands.calls.has("stop_inputs"), "oral never stops the caress input")
	check(standing.calls.has("apply_lean_look"), "oral keeps the standing look response")
	for _i in 200:
		camera.call("oral_lean_tick", 0.05)
	check(near(camera.lean_forward, 0.0) and near(camera.lean_side, 0.0)
		and near(camera.lean_view_forward, 0.0) and near(camera.lean_view_side, 0.0),
		"oral settles the lean at rest")


func _check_lock_and_eye() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var main := made["main"] as FakeMain
	var player := made["player"] as FakePlayer
	player.controls_locked = false
	camera.call("apply_free_camera_lock")
	check(player.controls_locked, "the free shot locks the player controls")
	camera.call("apply_free_camera_lock")
	check(player.controls_locked, "a second lock is idempotent")
	camera.call("release_free_camera_lock")
	check(not player.controls_locked, "the release restores the saved controls")

	# The standing eye override scales the player's eye with the body preset.
	player._stand_eye = 2.4
	player._eye_height = 2.4
	var base: float = camera.call("player_eye_height")
	var scale: float = camera.call("size_scale")
	camera.call("apply_eye_override", CATALOG.STANDING, false)
	check(near(camera.camera_target_eye, base * scale),
		"the standing eye target scales with the body preset")
	if near(base * scale, base):
		check(not camera.eye_override, "a unit size leaves the eye alone")
	else:
		check(camera.eye_override, "a size change owns the eye override")
		camera.call("restore_eye_override")
	check(near(player._stand_eye, 2.4), "the restored player keeps her own eye height")
	camera.call("apply_eye_override", CATALOG.MISSIONARY, false)
	check(near(camera.camera_target_eye, 0.0), "missionary never edits the eye")
	check(not camera.eye_override, "missionary never owns the eye override")

	# An owned override restores the saved values exactly.
	camera.eye_override = true
	camera.saved_stand_eye = 1.6
	camera.saved_eye_height = 1.6
	player._stand_eye = 2.1
	player._eye_height = 2.1
	camera.call("restore_eye_override")
	check(near(player._stand_eye, 1.6) and near(player._eye_height, 1.6),
		"the eye override restores both saved heights")
	check(not camera.eye_override, "the restore drops the ownership flag")

	camera.call("apply_eye_override", CATALOG.STANDING, true)
	check(near(camera.camera_target_eye, 0.0) and not camera.eye_override,
		"AnonPony keeps her own eye height")
	player.seat = Node3D.new()
	camera.call("apply_eye_override", CATALOG.STANDING, false)
	check(not camera.eye_override, "a seated player keeps the seat camera")
	(player.seat as Node3D).free()
	player.seat = null
	main.remove_child(player)
	main.remove_child(main.view)
	player.free()
	(main.view as Camera3D).free()
	main.free()


func _check_look() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var main := made["main"] as FakeMain
	var player := made["player"] as FakePlayer
	player.rotation.y = 0.1
	player._pitch = 0.2
	camera.call("capture_look")
	check(camera.look_captured, "the look snapshot is captured")
	check(near(camera.restore_yaw, 0.1) and near(camera.restore_pitch, 0.2),
		"the snapshot keeps the yaw and pitch")
	player.rotation.y = 0.9
	player._pitch = 0.8
	camera.call("begin_session", CATALOG.MISSIONARY)
	camera.call("capture_look")
	player.rotation.y = 0.9
	player._pitch = 0.8
	camera.call("restore_look", CATALOG.MISSIONARY)
	check(not camera.look_captured, "the restore consumes the snapshot")
	check(near(player.rotation.y, 0.9), "missionary restores the captured yaw")
	check(near(float(player._pitch), 0.8), "missionary restores the captured pitch")

	# Standing leaves the act's final facing alone.
	camera.call("begin_session", CATALOG.STANDING)
	camera.call("capture_look")
	player.rotation.y = 1.4
	camera.call("restore_look", CATALOG.STANDING)
	check(near(player.rotation.y, 1.4), "standing leaves Anon facing the act's end")
	main.remove_child(player)
	player.free()
	main.remove_child(main.view)
	(main.view as Camera3D).free()
	main.free()


func _check_free_look() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var player := made["player"] as FakePlayer
	facts.state = STATE_ACTIVE
	camera.call("look_input", Vector2(20.0, -10.0))
	check(near(camera.free_look_yaw, -20.0 * player.mouse_sensitivity),
		"free look yaw follows the mouse")
	check(near(camera.free_look_pitch, 10.0 * player.mouse_sensitivity),
		"free look pitch follows the mouse")
	var rotation: Vector3 = camera.call("free_look_rotation")
	check(near(rotation.y, camera.free_look_yaw) and near(rotation.x, camera.free_look_pitch),
		"the free-look rotation reports pitch and yaw")
	camera.free_look_was = true
	camera.call("tick_free_look")
	check(near(camera.free_look_yaw, 0.0) and near(camera.free_look_pitch, 0.0),
		"switching free look resets the rotation")


func _check_motion() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var standing: FakeStandingCamera = made["standing"]
	var missionary: FakeMissionaryCamera = made["missionary"]
	facts.state = STATE_IDLE
	check(not bool(camera.call("motion_ready")), "idle has no act shot")
	facts.state = STATE_ACTIVE
	camera.free_camera_active = false
	check(not bool(camera.call("motion_ready")), "no free camera has no act shot")
	camera.call("begin_free")
	check(bool(camera.call("motion_ready")), "an active free shot owns the view")
	facts.headset_view = true
	check(not bool(camera.call("motion_ready")), "a headset keeps the stock camera")
	facts.headset_view = false
	facts.pose_id = CATALOG.MISSIONARY
	camera.call("apply_motion")
	check(missionary.calls.has("tick"), "missionary dispatches its own camera")
	facts.pose_id = CATALOG.STANDING
	camera.call("apply_motion")
	check(standing.calls.has("tick"), "standing dispatches the player-camera shot")


func _check_neck() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var missing: Vector3 = camera.call("neck_midpoint")
	check(not missing.is_finite(), "a missing pony has no neck point")
	var pony := FakePony.new()
	root.add_child(pony)
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("pony_neck1")
	skeleton.add_bone("pony_neck2")
	pony.add_child(skeleton)
	skeleton.set_bone_pose_position(0, Vector3(0.0, 1.0, 0.0))
	skeleton.set_bone_pose_position(1, Vector3(0.0, 1.2, 0.0))
	pony.skeleton = skeleton
	(made["facts"] as Variant).pony = pony
	var midpoint: Vector3 = camera.call("neck_midpoint")
	check(near(midpoint.y, 1.1), "the neck point is the midpoint of both neck bones")
	var main := made["main"] as FakeMain
	var player := made["player"] as FakePlayer
	main.remove_child(player)
	player.free()
	main.remove_child(main.view)
	(main.view as Camera3D).free()
	main.free()
	root.remove_child(pony)
	pony.free()
