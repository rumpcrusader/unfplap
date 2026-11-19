extends SceneTree
## The act camera facade: the lean and its smoothing, the shot response, the free look, the
## free-camera lock, the eye override, the captured look and the shot geometry helpers.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_camera/test_camera.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const CAMERA := preload("res://mods/unfplap/camera/service.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/camera/missionary_camera.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

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


## The two values the authored-shot path reads: the live bed frame and the pose asset callable.
class FakeShotFacts extends RefCounted:
	var bed_frame: Variant = null
	var authored_pose_asset := Callable()

	func call_value(callback: Callable, fallback: Variant = null) -> Variant:
		if callback.is_valid():
			return callback.call()
		return fallback


class FakePlayer extends Node3D:
	var camera: Variant = null
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

	func standing_active() -> bool:
		return false

	func base_active() -> bool:
		return false

	func lean_kiss_tick() -> void:
		calls.append("lean_kiss_tick")

	func end_lean_kiss() -> void:
		calls.append("end_lean_kiss")

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

	func restore() -> void:
		calls.append("restore")

	func reset() -> void:
		calls.append("reset")

	func prepare() -> void:
		calls.append("prepare")

	func begin_facing(_transform: Transform3D) -> void:
		calls.append("begin_facing")


class FakePony extends Node3D:
	var skeleton: Variant = null
	var secondary: Variant = null
	var identity: Variant = null
	var body_scale := 1.0


class FakeSecondary extends RefCounted:
	func look_toward(_angles: Vector3, _seconds: float) -> void:
		pass


class FakeMissionaryCamera extends RefCounted:
	var calls: Array[String] = []

	func tick() -> void:
		calls.append("tick")

	func snapshot_yaw() -> float:
		return NAN

	func reset_look() -> void:
		calls.append("reset_look")


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
	WORLD.bind_player(main.player)
	main.view = Camera3D.new()
	main.add_child(main.view)
	player.camera = main.view
	root.add_child(main)
	var facts: RefCounted = FACTS.new()
	facts.player_pony = false
	facts.state = STATE_ACTIVE
	facts.features = {"idle_camera_sway": false}
	_pose(facts, "bed")
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


## Fill the pose read model the camera reads instead of the old raw facts.
func _pose(facts: RefCounted, family: String) -> void:
	var view: RefCounted = VIEW.new()
	view.family = family
	view.contact_kind = "opening"
	view.presentation = {"lean": "missionary" if family == "bed" else "standing"}
	view.camera = {
		"profile": "missionary_shots" if family == "bed" else "standing_procedural",
	}
	facts.pose_view = view


func run() -> void:
	_check_session()
	_check_shot()
	_check_missionary_shot_anchor()
	_check_facesit_shot_anchor()
	_check_lean()
	_check_oral_lean()
	_check_retarget()
	_check_lock_and_eye()
	_check_eye_line()
	_check_entrance()
	_check_look()
	_check_free_look()
	_check_motion()
	_check_neck()
	_check_standing_cache()

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
	camera.call("configure", {"surge": 1.0, "bob": 0.35})
	check(near(camera.camera_surge, 1.0) and near(camera.camera_bob, 0.35),
		"configure replaces the block")
	camera.lean = 0.2
	camera.bob = 0.2
	camera.back = 0.2
	camera.call("begin_session", "bed")
	check(not camera.camera_owned and not camera.look_captured, "a fresh session owns nothing")
	check(camera.look_restore_yaw, "missionary restores the captured yaw")
	check(near(camera.lean, 0.0) and near(camera.bob, 0.0) and near(camera.back, 0.0),
		"a fresh session starts the shot from rest")
	camera.call("begin_session", "standing")
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


## The authored missionary shot follows the asset's hips anchor and contact lift at every size;
## canon is the authored transform within 0.1 mm.
func _check_missionary_shot_anchor() -> void:
	_check_shot_anchor("poses/missionary_pose.json", "missionary")


## The face-sit asset uses the same bed camera and the same anchor/contact rule; its five shots
## are the ones the camera cuts to when the edge settles.
func _check_facesit_shot_anchor() -> void:
	_check_shot_anchor("poses/bed_facesit_pose.json", "face-sit")


func _check_shot_anchor(asset_path: String, label: String) -> void:
	var pose: Variant = AUTHORED.shared(asset_path)
	check(bool(pose.get("available")), "the %s asset is available for the shot" % label)
	if not bool(pose.get("available")):
		return
	var facts := FakeShotFacts.new()
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.65, -2.0))
	facts.bed_frame = frame
	facts.authored_pose_asset = func() -> Variant: return pose
	var camera: Variant = MISSIONARY_CAMERA.new(facts)
	var here: Vector3 = pose.call("anchor_world", frame).origin
	for shot_id: String in MISSIONARY_CAMERA.SHOT_IDS:
		var authored: Transform3D = (pose.get("shots") as Dictionary)[shot_id]
		var canon_world: Vector3 = (frame * authored).origin
		for size: float in [1.0, 1.7]:
			var lift := float(pose.call("body_lift", frame, size))
			var expected := here + (canon_world - here) * size + Vector3.UP * lift
			var got: Transform3D = camera.call("_shot_transform", shot_id, size)
			check(got.origin.distance_to(expected) <= 0.0001,
				"%s %s shot origin at %.2f follows the anchor" % [label, shot_id, size])
			check(got.basis.orthonormalized().is_equal_approx(
				(frame.basis * authored.basis).orthonormalized()),
				"%s %s shot keeps the authored basis" % [label, shot_id])


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
	_pose(facts, "bed")
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
	_pose(facts, "standing")
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
	_pose(facts, "standing")
	facts.pose_view.contact_kind = "mouth"
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
	check(kiss.calls.has("end_lean_kiss"), "oral ends a running lean kiss")
	check(not kiss.calls.has("lean_kiss_tick"), "oral never restarts the lean kiss")
	check(hands.calls.has("tick"), "oral keeps ticking the caress hands")
	check(not hands.calls.has("stop_inputs"), "oral never stops the caress input")
	check(standing.calls.has("apply_lean_look"), "oral keeps the standing look response")
	for _i in 200:
		camera.call("oral_lean_tick", 0.05)
	check(near(camera.lean_forward, 0.0) and near(camera.lean_side, 0.0)
		and near(camera.lean_view_forward, 0.0) and near(camera.lean_view_side, 0.0),
		"oral settles the lean at rest")


## A pose change retargets the shot family and retires the old lean action, while the camera session
## itself and the captured look stay. A steady repeat is a no-op.
func _check_retarget() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: RefCounted = made["facts"]
	var view: RefCounted = facts.pose_view
	camera.call("pose_changed", view)
	check(str(camera._hook_family) == "bed" and str(camera._hook_camera) == "missionary_shots",
		"the hook caches the bed shot profile")
	camera.lean_action_kind = "reach"
	camera.camera_basis_ready = true
	camera.call("begin_free")
	_pose(facts, "standing")
	camera.call("pose_changed", facts.pose_view)
	check(camera.lean_action_kind == "", "a family change retires the old lean action")
	check(not camera.camera_basis_ready, "a family change re-aims the next shot")
	check(camera.free_camera_active and camera.camera != null,
		"the camera keeps its session through the retarget")
	camera.lean_action_kind = "reach"
	camera.call("pose_changed", facts.pose_view)
	check(camera.lean_action_kind == "reach", "a steady repeat does not retarget again")
	check(not is_same(facts.pose_view, view) and str(camera._hook_family) == "standing",
		"the hook follows the live view")
	camera.call("close_shot")


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
	camera.call("apply_eye_override", "standing", false)
	check(near(camera.camera_target_eye, base * scale),
		"the standing eye target scales with the body preset")
	if near(base * scale, base):
		check(not camera.eye_override, "a unit size leaves the eye alone")
	else:
		check(camera.eye_override, "a size change owns the eye override")
		camera.call("restore_eye_override")
	check(near(player._stand_eye, 2.4), "the restored player keeps her own eye height")

	# Re-applying the same form must derive the target from the true base, never from the eye
	# this override already lowered. A custom low entrance forces a non-unit target in the suite.
	var lowered := BODY_FORM.BodyForm.new()
	lowered.rig = BODY_PROFILE.RigProfile.new("test_low",
		BODY_PROFILE.WINKING_REAR_Y - 0.14, BODY_PROFILE.WINKING_REAR_Z, 1.0)
	lowered.body_scale = 1.0
	player._stand_eye = 1.8
	player._eye_height = 1.8
	camera.call("apply_eye_override", "standing", false, lowered)
	var first_target: float = float(camera.camera_target_eye)
	check(camera.eye_override and first_target < 1.7,
		"a low entrance lowers the standing eye")
	camera.call("apply_eye_override", "standing", false, lowered)
	check(near(camera.camera_target_eye, first_target),
		"re-applying the same form does not compound the eye offset")
	camera.call("reset_for_form", "standing", false, lowered)
	check(near(camera.camera_target_eye, first_target),
		"a form reset keeps the same true-base target")
	var standing: FakeStandingCamera = made["standing"]
	check(standing.calls.has("restore") and standing.calls.has("reset"),
		"a standing form reset restores the old camera before resetting it")
	var base_eye := 1.8
	var eye_scale: float = camera.call("size_scale")
	var neutral := BODY_FORM.BodyForm.new()
	neutral.rig = BODY_PROFILE.RigProfile.new("test_neutral",
		BODY_PROFILE.WINKING_REAR_Y + base_eye * (1.0 - eye_scale),
		BODY_PROFILE.WINKING_REAR_Z, 1.0)
	neutral.body_scale = 1.0
	camera.call("apply_eye_override", "standing", false, neutral)
	check(near(player._stand_eye, base_eye) and not camera.eye_override,
		"a form that needs no crouch gives the true eye back")
	player._stand_eye = 2.4
	player._eye_height = 2.4
	camera.call("apply_eye_override", "bed", false)
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

	camera.call("apply_eye_override", "standing", true)
	check(near(camera.camera_target_eye, 0.0) and not camera.eye_override,
		"AnonPony keeps her own eye height")
	player.seat = Node3D.new()
	camera.call("apply_eye_override", "standing", false)
	check(not camera.eye_override, "a seated player keeps the seat camera")
	(player.seat as Node3D).free()
	player.seat = null
	main.remove_child(player)
	main.remove_child(main.view)
	player.free()
	(main.view as Camera3D).free()
	main.free()


## Her live rest head line can raise the standing eye, never above Anon's own. The target is
## relative to the player root, so a raised floor must not be read as a taller pony.
func _check_eye_line() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var player := made["player"] as FakePlayer
	var main := made["main"] as FakeMain
	player.global_position = Vector3.ZERO
	var pony := FakePony.new()
	root.add_child(pony)
	var skeleton := Skeleton3D.new()
	pony.add_child(skeleton)
	pony.skeleton = skeleton
	facts.pony = pony

	var base: float = camera.call("player_eye_height")
	var preset: float = base * float(camera.call("size_scale"))

	camera.call("apply_eye_override", "standing", false)
	check(near(camera.camera_target_eye, preset),
		"a skeleton without her head bone keeps the preset eye")
	camera.call("restore_eye_override")

	var head := skeleton.add_bone("pony_head")
	for line: float in [minf(preset, base) - 0.5, (preset + base) * 0.5, base + 0.5]:
		skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, Vector3(0.0, line, 0.0)))
		var expected := maxf(preset, minf(base, line))
		camera.call("apply_eye_override", "standing", false)
		check(near(camera.camera_target_eye, expected),
			"the standing eye follows her live line up to Anon's own eye")
		camera.call("restore_eye_override")

	# The same line from a raised player root is measured above that root, not in world space.
	player.global_position.y = 0.4
	var raised := base + 0.5
	skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, Vector3(0.0, raised + 0.4, 0.0)))
	camera.call("apply_eye_override", "standing", false)
	check(near(camera.camera_target_eye, maxf(preset, minf(base, raised))),
		"the live eye line is relative to the raised player root")
	camera.call("restore_eye_override")

	# A head parented under the neck reads its rest line in skeleton space: the neck's rest offset
	# is part of the line, so a pose that moves the neck carries the eye with it.
	player.global_position.y = 0.0
	skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0)))
	var local_eye: float = camera.call("pony_eye_height")
	var neck := skeleton.add_bone("pony_neck1")
	skeleton.set_bone_parent(head, neck)
	skeleton.set_bone_rest(neck, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)))
	var parented_eye: float = camera.call("pony_eye_height")
	check(near(parented_eye - local_eye, 1.2, 0.001),
		"a parented head measures its global rest line")

	root.remove_child(pony)
	pony.free()
	main.remove_child(player)
	main.remove_child(main.view)
	player.free()
	(main.view as Camera3D).free()
	main.free()


## A princess body's entrance sits higher or lower and further back than the mare's, and the
## offset follows the body she is wearing and her live scale.
func _check_entrance() -> void:
	var mare := FakePony.new()
	mare.identity = {"id": "an_ordinary_mare"}
	var ordinary := BODY_FORM.default_form(mare)
	check(CAMERA.entrance_offset_for(ordinary).is_equal_approx(Vector2.ZERO),
		"an ordinary form keeps the tuned entrance")
	check(CAMERA.entrance_offset_for(null).is_equal_approx(Vector2.ZERO),
		"no form has no entrance offset")
	mare.free()

	var celestia := FakePony.new()
	celestia.identity = {"id": "celestia"}
	var celestia_form := BODY_FORM.default_form(celestia)
	var cel := CAMERA.entrance_offset_for(celestia_form)
	check(near(cel.x, 0.312) and near(cel.y, 0.0368),
		"Celestia's entrance is higher and further back")
	celestia.body_scale = 1.5
	celestia_form.body_scale = 1.5
	check(near(CAMERA.entrance_offset_for(celestia_form).x, 0.312 * 1.5),
		"the entrance offset follows the form's body scale")
	celestia.free()

	var luna := FakePony.new()
	luna.identity = {"id": "luna"}
	var luna_form := BODY_FORM.default_form(luna)
	var lun := CAMERA.entrance_offset_for(luna_form)
	check(near(lun.x, 0.055) and near(lun.y, -0.0696),
		"Luna's entrance is lower and further forward")
	luna.free()

	# The offset follows the presented form: a copy on a princess body takes that body's
	# entrance, and a princess wearing an ordinary body takes the mare's.
	var copy := FakePony.new()
	copy.identity = {"id": "chrysalis", "character_id": "celestia"}
	var copy_form := BODY_FORM.default_form(copy)
	copy_form.rig = BODY_PROFILE.ordinary_rig()
	check(CAMERA.entrance_offset_for(copy_form).is_equal_approx(Vector2.ZERO),
		"a princess wearing an ordinary body uses the mare's entrance")
	copy_form.rig = BODY_PROFILE.rig_for_key("luna")
	check(near(CAMERA.entrance_offset_for(copy_form).x, 0.055),
		"a copy on a princess body uses that body's entrance")
	copy.free()


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
	camera.call("begin_session", "bed")
	camera.call("capture_look")
	player.rotation.y = 0.9
	player._pitch = 0.8
	camera.call("restore_look", "bed")
	check(not camera.look_captured, "the restore consumes the snapshot")
	check(near(player.rotation.y, 0.9), "missionary restores the captured yaw")
	check(near(float(player._pitch), 0.8), "missionary restores the captured pitch")

	# Standing leaves the act's final facing alone.
	camera.call("begin_session", "standing")
	camera.call("capture_look")
	player.rotation.y = 1.4
	camera.call("restore_look", "standing")
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
	_pose(facts, "bed")
	camera.call("apply_motion")
	check(missionary.calls.has("tick"), "missionary dispatches its own camera")
	_pose(facts, "standing")
	camera.call("apply_motion")
	check(standing.calls.has("tick"), "standing dispatches the player-camera shot")


## The shipped standing config with the test overrides, so the camera reads the same complete
## block the act provides.
func _standing_config(overrides := {}) -> Dictionary:
	var config: Dictionary = CATALOG.defaults(CATALOG.STANDING).duplicate(true)
	config.merge(overrides, true)
	return config


## The standing camera re-reads the view's config only on a settings-group or pose-id change, so the
## standing debug edge holds the live config and its glance/tail values do not snap. An unrelated
## config never wins over the view's.
func _check_standing_cache() -> void:
	var facts: RefCounted = FACTS.new()
	var view: RefCounted = VIEW.new()
	view.id = CATALOG.STANDING
	view.family = "standing"
	view.settings_group = "standing"
	facts.pose_view = view
	var stale: Dictionary = _standing_config({"glance_min": 1.0})
	var config_a: Dictionary = _standing_config({"glance_min": 5.0})
	var config_b: Dictionary = _standing_config({"glance_min": 7.0})
	var config_c: Dictionary = _standing_config({"glance_min": 9.0})
	view.from_config = config_a
	view.pose_config = config_a
	var standing: RefCounted = STANDING_CAMERA.new(facts)
	standing.call("_sync")
	check(is_same(standing._pose_cfg, config_a), "the standing camera reads the view config")
	check(not is_same(standing._pose_cfg, stale),
		"an unrelated config never wins")
	view.from_config = config_b
	view.pose_config = config_b
	standing.call("_sync")
	check(is_same(standing._pose_cfg, config_a),
		"an unchanged group and pose keep the cached config")
	view.from_config = config_c
	view.pose_config = config_c
	view.id = CATALOG.STANDING_TEST
	standing.call("_sync")
	check(is_same(standing._pose_cfg, config_c), "a pose change re-reads the view config")
	view.from_config = config_a
	view.pose_config = config_a
	standing.call("_sync")
	check(is_same(standing._pose_cfg, config_c),
		"a second sync with the new pose keeps the cached config")
	view.from_config = {}
	view.pose_config = config_b
	view.settings_group = "missionary"
	standing.call("_sync")
	check(is_same(standing._pose_cfg, config_b),
		"an empty from_config falls back to the view's pose_config, not the alias")
	check(not is_same(standing._pose_cfg, stale),
		"the fallback never reads an unrelated config")
	view.family = "bed"
	check(standing.call("_pose_family") == "bed",
		"a bed view is outside the standing controller")
	view.family = "standing"
	check(standing.call("_pose_family") == "standing",
		"the standing family still gates the controller")
	view.facing = Basis(Vector3.UP, 1.0)
	view.facing_amount = 0.75
	standing.call("sync_view_facing")
	check(standing._facing_override_on
		and standing._facing_override.is_equal_approx(Basis(Vector3.UP, 1.0)),
		"the standing camera follows the pose view's facing")
	view.facing_amount = 0.0
	standing.call("sync_view_facing")
	check(not standing._facing_override_on,
		"a zero facing amount returns the normal facing lock")

	# The standing start calls begin_facing before the pose session builds. The empty config must
	# not be read; the first drive tick arms the wait once the pose config exists.
	var early_view: RefCounted = VIEW.new()
	early_view.id = CATALOG.STANDING
	early_view.family = "standing"
	early_view.settings_group = "standing"
	var early_facts: RefCounted = FACTS.new()
	early_facts.pose_view = early_view
	early_facts.presentation_config = {"glance_back_speed": 1.0}
	var early_kiss := FakeKiss.new()
	early_facts.kiss = func() -> Variant: return early_kiss
	var early_pony := FakePony.new()
	early_pony.secondary = FakeSecondary.new()
	root.add_child(early_pony)
	early_facts.pony = early_pony
	early_facts.lean_forward = 1.0
	var early_camera: RefCounted = STANDING_CAMERA.new(early_facts)
	early_camera.call("begin_facing", Transform3D.IDENTITY)
	check(float(early_camera._glance_wait) < 0.0,
		"a start before the pose config arms its first glance later")
	early_camera.call("drive_glance", 0.1)
	check(not early_camera._glance_back,
		"an empty pose config does not arm the lean glance")
	check(float(early_camera._glance_wait) < 0.0,
		"the first wait stays armed until the pose config exists")
	early_pony.free()


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
