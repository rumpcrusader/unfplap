extends "res://mods/unfplap/tests/support/suite.gd"
## The act camera facade and the live view: the lean and its smoothing, the shot response, the free
## look, the standing offsets, the missionary eye view and the head clearance.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_camera/test_camera.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const CAMERA := preload("res://mods/unfplap/camera/service.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const CAMERA_CONFIG := preload("res://mods/unfplap/camera/config.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4



class FakeMain extends Node:
	var player: Variant = null
	var view: Camera3D = null

	func camera() -> Camera3D:
		return view


class FakeGame extends Node:
	var headset_view := false


## Her head surfaces, in world space: the skull sphere and the muzzle capsule.
class FakeBoop extends Node:
	var skull := Vector3.ZERO
	var nose := Vector3.ZERO
	var muzzle := Vector3.ZERO

	func skull_world() -> Vector3:
		return skull

	func nose_world() -> Vector3:
		return nose

	func muzzle_world() -> Vector3:
		return muzzle


## The posed Anon body's eye: the transform `missionary_anon.gd` caches for the frame.
class FakeActBody extends Node:
	var eye: Variant = Transform3D.IDENTITY

	func eye_transform() -> Variant:
		return eye


class FakePlayer extends Node3D:
	var camera: Variant = null
	var _stand_eye: Variant = 1.7
	var _eye_height: Variant = 1.7
	var _pitch: Variant = 0.0
	var controls_locked := false
	var mouse_sensitivity := 0.0022
	var invert_y := false
	var headset_view := false
	var seat: Variant = null
	var form_driver: Variant = null

	func eye_height() -> float:
		return float(_stand_eye)


class FakeHands extends HANDS:
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


class FakeKiss extends KISS:
	var calls: Array[String] = []

	func lean() -> float:
		return 0.0

	func lean_drop() -> float:
		return 0.0

	func lean_distance() -> float:
		return 0.0

	func side() -> float:
		return 1.0

	func lateral_offset(_scale: float) -> float:
		return 0.0

	func camera_yaw_deg() -> float:
		return 12.0

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


class FakeView extends CAMERA_VIEW:
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

	func mount() -> void:
		calls.append("mount")

	func unmount() -> void:
		calls.append("unmount")

	func begin_facing(_transform: Transform3D) -> void:
		calls.append("begin_facing")


class FakePony extends Node3D:
	var skeleton: Variant = null
	var secondary: Variant = null
	var identity: Variant = null
	var boop_node: Variant = null
	var eye_motion: Variant = null
	var body_scale := 1.0


class FakeSecondary extends Node:
	var looks: Array[Vector3] = []
	var weight := 0.0

	func look_toward(angles: Vector3, seconds: float) -> void:
		looks.append(angles)
		weight = seconds


## Her navigator: the stale face point and the conversation aim the facing lock clears.
class FakeNavigator extends Node:
	var face_point: Vector3 = Vector3.ZERO
	var conversation_clears := 0

	func set_conversation_target(_target: Variant, _turn: bool) -> void:
		conversation_clears += 1


## The native eye modifier: the pupil target the glance writes.
class FakeEyes extends Node:
	var target_world := Vector3.ZERO
	var target_weight := 0.0


## A form driver with its own view limit.
class FakeForm extends Node:
	var clamps := 0

	func clamp_view() -> void:
		clamps += 1


## The act pose node: the standing head throw-back the glance writes.
class FakePose extends Node:
	var head_back := 0.0


## A body with its own ear point.
class FakeListener extends Node3D:
	func listen_point() -> Vector3:
		return Vector3(0.5, 1.5, 0.5)

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
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	var facts: RefCounted = FACTS.new()
	facts.player_pony = false
	facts.state = STATE_ACTIVE
	facts.features = {"idle_camera_sway": false}
	_pose(facts, "bed")
	var camera: RefCounted = CAMERA.new()
	var hands := FakeHands.new()
	var kiss := FakeKiss.new()
	var view := FakeView.new()
	camera.bind(facts, hands, kiss, view)
	return {
		"camera": camera, "facts": facts, "main": main, "player": player,
		"hands": hands, "kiss": kiss, "view": view, "game": game,
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
	_check_missionary_eye()
	_check_missionary_look_path()
	_check_head_clearance()
	_check_accessors()
	_check_lean()
	_check_oral_lean()
	_check_standing_shot_offsets()
	_check_view_writes()
	_check_retarget()
	_check_eye_line()
	_check_entrance()
	_check_free_look()
	_check_motion()
	_check_neck()
	_check_standing_cache()
	_check_look_target()

	if failures == 0:
		print("ACT_CAMERA_PASS")
	finish()


func _check_session() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	camera.configure(CAMERA_CONFIG.Config.from_dict({"surge": 0.5, "bob": 0.25}))
	check(near(camera.camera_surge, 0.5) and near(camera.camera_bob, 0.25),
		"the camera_thrust block reaches the facade")
	camera.configure(CAMERA_CONFIG.Config.from_dict({"surge": 1.0, "bob": 0.35}))
	check(near(camera.camera_surge, 1.0) and near(camera.camera_bob, 0.35),
		"configure replaces the block")
	camera.lean = 0.2
	camera.bob = 0.2
	camera.back = 0.2
	check(not bool(camera.call("begin_act", "bed", false, false)),
		"a desktop bed act opens the view")
	check(camera.camera_owned and camera.free_camera_active, "the act takes its view")
	check(camera.camera == (made["main"] as FakeMain).view,
		"the act grabs the player camera")
	check(near(camera.lean, 0.0) and near(camera.bob, 0.0) and near(camera.back, 0.0),
		"the act starts the shot from rest")
	camera.lean_view_forward = 0.8
	camera.call("begin_act", "bed", false, false)
	check(near(camera.lean_view_forward, 0.0), "opening the act resets the lean")
	camera.call("finish_act")
	check(not bool(camera.call("begin_act", "standing", false, false)),
		"a desktop standing act opens the view")
	check((made["view"] as FakeView).calls.has("prepare"),
		"a standing act prepares the player camera")
	camera.call("finish_act")
	check(not camera.camera_owned and camera.camera == null,
		"finishing the act drops the camera")
	check((made["view"] as FakeView).calls.has("unmount")
		and (made["view"] as FakeView).calls.has("restore"),
		"finishing the act unmounts and restores the view")
	camera.call("finish_act")
	check(not camera.camera_owned, "a second finish is a no-op")
	# A headset standing act asks the anatomy bridge to start VR; AnonPony keeps the stock view.
	check(bool(camera.call("begin_act", "standing", false, true)),
		"a headset standing act starts VR")
	check(not bool(camera.call("begin_act", "standing", true, false)),
		"a player-pony act takes no camera")
	camera.call("finish_act")


func _check_shot() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	camera.configure(CAMERA_CONFIG.Config.from_dict({"surge": 1.0, "bob": 1.0}))
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


## The missionary view is the act body's own eye, with no authored shot left to pick.
func _check_missionary_eye() -> void:
	var made := _eye_fixture()
	var camera: RefCounted = made["camera"]
	var body: FakeActBody = made["body"]
	var view: Camera3D = camera.call("view")
	check(is_instance_valid(view) and view.get_parent() == made["pony"],
		"the act view is mounted once on her")
	check(camera.has_method("head_look_point_at") and camera.has_method("bed_surface_top"),
		"the view keeps the gaze and fluid-ground reads")
	var module: Script = CAMERA_VIEW
	check(camera.has_method("_shot_basis") and module.get_script_constant_map().has("SHOT_IDS"),
		"the view reads the authored look path")
	check(not camera.has_method("_tick_authored") and not camera.has_method("_shot_transform")
		and not camera.has_method("_blend_shots") and not camera.has_method("_shot_position"),
		"no shot position or separate authored camera path")
	body.eye = Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 2.0, 3.0))
	camera.call("write_eye")
	check(view.global_position.is_equal_approx(body.eye.origin),
		"the view sits at the act body's eye")
	check(view.global_basis.is_equal_approx(body.eye.basis.orthonormalized()),
		"a missing look path keeps the eye basis")
	# Free look turns the eye where it stands, and nothing else does.
	made["facts"].free_look_active = true
	made["facts"].free_look_rotation = func() -> Vector3: return Vector3(0.2, 0.3, 0.0)
	camera.call("write_eye")
	check(not view.global_basis.is_equal_approx(body.eye.basis.orthonormalized()),
		"free look turns the eye")
	made["facts"].free_look_active = false
	made["facts"].free_look_rotation = Callable()
	camera.call("unmount")
	check(camera.call("view") == null, "the release drops the act view")
	_free_eye_fixture(made)


## His head is pushed out of her skull sphere and muzzle capsule by the frame's clearance.
## The missionary view keeps Anon's eye position and takes its orientation from the authored look
## path: rest, forward, back and both sides select the saved shot bases.
func _check_missionary_look_path() -> void:
	var asset: Variant = AUTHORED.shared()
	check(asset != null and bool(asset.get("has_shots")),
		"the authored missionary asset still carries its look path")
	if asset == null:
		return
	var frame := Transform3D(Basis(Vector3.UP, 0.3), Vector3(1.0, 2.0, 3.0))
	var facts := FACTS.new()
	facts.authored_pose_asset = func() -> Variant: return asset
	facts.bed_frame = frame
	facts.missionary_face_point = func() -> Vector3: return Vector3(0.0, 1.0, 0.0)
	var view: RefCounted = CAMERA_VIEW.new(facts)
	var shots: Dictionary = asset.get("shots")
	var at := Vector3.ZERO
	var rest: Basis = view.call("_shot_basis", at, Basis.IDENTITY)
	check(rest.is_equal_approx(_shot_world(frame, shots, "start")),
		"the rest view uses the authored start look")
	facts.shot_lean_forward = 1.0
	var front: Basis = view.call("_shot_basis", at, Basis.IDENTITY)
	check(front.is_equal_approx(_shot_world(frame, shots, "front")),
		"a forward lean uses the front look")
	facts.shot_lean_forward = -1.0
	var back: Basis = view.call("_shot_basis", at, Basis.IDENTITY)
	check(back.is_equal_approx(_shot_world(frame, shots, "back")),
		"a backward lean uses the back look")
	facts.shot_lean_forward = 0.0
	facts.lean_view_side = 1.0
	var left: Basis = view.call("_shot_basis", at, Basis.IDENTITY)
	check(left.is_equal_approx(_shot_world(frame, shots, "left")),
		"a side lean uses the left look")
	facts.lean_view_side = -1.0
	var right: Basis = view.call("_shot_basis", at, Basis.IDENTITY)
	check(right.is_equal_approx(_shot_world(frame, shots, "right")),
		"the other side uses the right look")


static func _shot_world(frame: Transform3D, shots: Dictionary, id: String) -> Basis:
	var shot: Transform3D = shots[id]
	return (frame.basis * shot.basis).orthonormalized()


func _check_head_clearance() -> void:
	var made := _eye_fixture()
	var camera: RefCounted = made["camera"]
	var body: FakeActBody = made["body"]
	var pony: FakePony = made["pony"]
	var facts: RefCounted = made["facts"]
	var view: Camera3D = camera.call("view")
	var boop := FakeBoop.new()
	pony.boop_node = boop

	# A clearance of zero leaves the eye exactly where the pose put it.
	facts.head_clearance = 0.0
	body.eye = Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 1.0))
	boop.skull = Vector3(1.0, 1.0, 1.0)
	camera.call("write_eye")
	check(view.global_position.is_equal_approx(Vector3(1.0, 1.0, 1.0)),
		"no clearance leaves the eye on the pose")

	# The skull sphere: the pad is the clearance over her own radius, scaled with her body.
	facts.head_clearance = 0.05
	camera.call("write_eye")
	var pushed := view.global_position.distance_to(boop.skull)
	check(near(pushed, 0.09 + 0.05), "the skull pushes the eye out by her radius and the pad")
	pony.body_scale = 2.0
	body.eye = Transform3D(Basis.IDENTITY, boop.skull)
	camera.call("write_eye")
	check(near(view.global_position.distance_to(boop.skull), 0.18 + 0.05),
		"her body scale scales the skull radius")
	pony.body_scale = 1.0

	# The muzzle capsule: a point between her muzzle and nose is pushed off the segment.
	boop.skull = Vector3(5.0, 5.0, 5.0)
	boop.muzzle = Vector3(0.0, 0.0, 0.0)
	boop.nose = Vector3(0.0, 0.0, 0.4)
	body.eye = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.2))
	camera.call("write_eye")
	var to_axis := view.global_position.distance_to(Vector3(0.0, 0.0, 0.2))
	check(near(to_axis, 0.04 + 0.05), "her muzzle pushes the eye off the capsule axis")
	boop.free()
	_free_eye_fixture(made)


## One live scene for the missionary view: the player rig, the game, her and the posed act body.
func _eye_fixture() -> Dictionary:
	var main := FakeMain.new()
	var player := FakePlayer.new()
	main.add_child(player)
	main.player = player
	WORLD.bind_player(main.player)
	main.view = Camera3D.new()
	main.add_child(main.view)
	player.camera = main.view
	root.add_child(main)
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	var pony := FakePony.new()
	root.add_child(pony)
	var facts: RefCounted = FACTS.new()
	facts.player_pony = false
	facts.state = STATE_ACTIVE
	facts.features = {}
	facts.pony = pony
	facts.viewport = root
	facts.head_clearance = 0.0
	var body := FakeActBody.new()
	facts.missionary_anon = func() -> Variant: return body
	var kiss := FakeKiss.new()
	facts.kiss = func() -> Variant: return kiss
	_pose(facts, "bed")
	var camera: RefCounted = CAMERA_VIEW.new(facts)
	camera.call("mount")
	return {
		"camera": camera, "facts": facts, "body": body, "pony": pony,
		"main": main, "game": game, "player": player,
	}


func _free_eye_fixture(made: Dictionary) -> void:
	var main: FakeMain = made["main"]
	var player: FakePlayer = made["player"]
	var pony: FakePony = made["pony"]
	var game: FakeGame = made["game"]
	var body: FakeActBody = made["body"]
	WORLD.unbind()
	root.remove_child(pony)
	pony.free()
	root.remove_child(game)
	game.free()
	main.remove_child(player)
	main.remove_child(main.view)
	player.free()
	(main.view as Camera3D).free()
	main.free()
	body.free()


func _check_lean() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: Variant = made["facts"]
	var hands: FakeHands = made["hands"]
	var kiss: FakeKiss = made["kiss"]
	camera.free_camera_active = true
	camera.camera = (made["main"] as FakeMain).view
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
	var view: FakeView = made["view"]
	view.calls.clear()
	camera.lean_side = 0.8
	camera.call("tick_lean_action")
	check(camera.lean_action_active and camera.lean_action_kind == "reach",
		"standing fires the shoulder reach")
	check(hands.calls.has("start_reach:R"), "the reach starts on the lean side")
	check(view.calls.has("hold_glance"), "the reach holds the over-the-shoulder glance")
	camera.lean_side = 0.0
	camera.call("tick_lean_action")
	check(hands.calls.has("end_reach") and view.calls.has("clear_glance"),
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
	var view: FakeView = made["view"]
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
	view.calls.clear()
	camera.call("oral_lean_tick", 0.1)
	check(not camera.lean_action_active, "oral ends an active lean action")
	check(hands.calls.has("end_reach"), "oral releases an active shoulder reach")
	check(view.calls.has("clear_glance"), "oral clears the reach glance")
	check(camera.lean_forward < 0.7 and camera.lean_side > -0.6,
		"oral returns the lean toward rest")
	check(near(camera.lean_sway, 0.0), "oral zeroes the idle sway")
	check(not camera.side_return_armed, "oral drops the side return latch")
	check(kiss.calls.has("end_lean_kiss"), "oral ends a running lean kiss")
	check(not kiss.calls.has("lean_kiss_tick"), "oral never restarts the lean kiss")
	check(hands.calls.has("tick"), "oral keeps ticking the caress hands")
	check(not hands.calls.has("stop_inputs"), "oral never stops the caress input")
	check(view.calls.has("apply_lean_look"), "oral keeps the standing look response")
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
	check(str(camera._hook_family) == "bed", "the hook caches the bed family")
	camera.lean_action_kind = "reach"
	camera.camera_basis_ready = true
	camera.free_camera_active = true
	camera.camera = (made["main"] as FakeMain).view
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


## Her live rest head line is read relative to the player root, from the global rest pose. The
## frame's stance target is the one that raises or caps it.
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
	check(not is_finite(float(camera.call("pony_eye_height"))),
		"a skeleton without her head bone has no eye line")

	var head := skeleton.add_bone("pony_head")
	for line: float in [minf(preset, base) - 0.5, (preset + base) * 0.5, base + 0.5]:
		skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, Vector3(0.0, line, 0.0)))
		check(near(float(camera.call("pony_eye_height")), line),
			"her eye line is the global rest head height above his root")

	# The same line from a raised player root is measured above that root, not in world space.
	player.global_position.y = 0.4
	var raised := base + 0.5
	skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, Vector3(0.0, raised + 0.4, 0.0)))
	check(near(float(camera.call("pony_eye_height")), raised),
		"the live eye line is relative to the raised player root")

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
	var view: FakeView = made["view"]
	facts.state = STATE_IDLE
	check(not bool(camera.call("motion_ready")), "idle has no act view")
	facts.state = STATE_ACTIVE
	camera.free_camera_active = false
	check(not bool(camera.call("motion_ready")), "no free camera has no act view")
	camera.free_camera_active = true
	camera.camera = (made["main"] as FakeMain).view
	check(bool(camera.call("motion_ready")), "an active free view owns the view")
	facts.headset_view = true
	check(not bool(camera.call("motion_ready")), "a headset keeps the stock camera")
	facts.headset_view = false
	_pose(facts, "bed")
	camera.call("apply_motion")
	check(not view.calls.has("tick"), "the bed view is written at render time, not in physics")
	_pose(facts, "standing")
	camera.call("apply_motion")
	check(view.calls.has("tick"), "standing dispatches the player-camera view")


## The shipped standing config with the test overrides, so the camera reads the same complete
## block the act provides.
func _standing_config(overrides := {}) -> Dictionary:
	var config: Dictionary = CATALOG.defaults(CATALOG.STANDING).duplicate(true)
	config.merge(overrides, true)
	return config


## The live shot moves the player camera with the thrust: the surge is a forward offset and the
## bob a vertical one, on top of the base local position.
func _check_standing_shot_offsets() -> void:
	var made := _fixture()
	var facts: RefCounted = made["facts"]
	var main: FakeMain = made["main"]
	var player: FakePlayer = made["player"]
	var view: Camera3D = main.view
	_pose(facts, "standing")
	facts.camera = view
	facts.free_camera_active = true
	facts.player_eye_height = 1.7
	facts.size_name = "same height"
	facts.presentation_config = {"camera_forward_m": 0.0, "camera_pitch_deg": 0.0}
	facts.look_captured = true
	facts.kiss = func() -> Variant: return made["kiss"]
	view.position = Vector3(0.0, 1.7, 0.0)
	var standing: RefCounted = CAMERA_VIEW.new(facts)
	standing.call("prepare")
	var base: Vector3 = view.position
	facts.lean = 0.06
	facts.bob = 0.02
	standing.call("tick")
	check(not view.position.is_equal_approx(base), "the live shot moves the camera")
	check(near(view.position.z, base.z - 0.06),
		"the thrust surge moves the camera forward")
	check(near(view.position.y, base.y + 0.02),
		"the thrust bob moves the camera vertically")
	check(near(view.position.x, base.x), "no side lean keeps the camera on its line")
	main.queue_free()


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
	var standing: RefCounted = CAMERA_VIEW.new(facts)
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
	var early_secondary := FakeSecondary.new()
	early_pony.secondary = early_secondary
	root.add_child(early_pony)
	early_facts.pony = early_pony
	early_facts.lean_forward = 1.0
	var early_camera: RefCounted = CAMERA_VIEW.new(early_facts)
	early_camera.call("begin_facing", Transform3D.IDENTITY)
	check(float(early_camera._glance_wait) < 0.0,
		"a start before the pose config arms its first glance later")
	early_camera.call("drive_glance", 0.1)
	check(not early_camera._glance_back,
		"an empty pose config does not arm the lean glance")
	check(float(early_camera._glance_wait) < 0.0,
		"the first wait stays armed until the pose config exists")
	early_pony.free()
	early_secondary.free()


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


## Every accessor the view reads: the live answer, and the typed zero when the member is gone.
func _check_accessors() -> void:
	var body := FakePlayer.new()
	root.add_child(body)
	check(near(GAME.pitch(body), 0.0), "the rig's pitch reads")
	GAME.set_pitch(body, 0.4)
	check(near(GAME.pitch(body), 0.4), "the pitch write lands")
	body._pitch = null
	check(not is_finite(GAME.pitch(body)), "a rig without a pitch answers NAN")
	GAME.set_pitch(body, 1.0)
	check(body._pitch == null, "a rig without a pitch takes no write")
	check(not is_finite(GAME.pitch(null)), "no rig has no pitch")

	var form := FakeForm.new()
	root.add_child(form)
	check(GAME.form_of(null) == null, "no rig has no form")
	check(GAME.form_of(body) == null, "a plain rig has no form driver")
	body.form_driver = form
	check(GAME.form_of(body) == form, "the rig's form driver reads")
	GAME.clamp_view(form)
	check(form.clamps == 1, "the form applies its own view limit")
	GAME.clamp_view(null)

	var pony := FakePony.new()
	root.add_child(pony)
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	GAME.clear_facing(pony)
	var face: Vector3 = nav.face_point
	check(not face.is_finite(), "the facing clear drops her stale face point")
	check(nav.conversation_clears == 1, "one facing clear drops her conversation aim too")

	var bare := FakePony.new()
	root.add_child(bare)
	var bare_nav := Node.new()
	bare_nav.name = "Navigator"
	bare.add_child(bare_nav)
	GAME.clear_facing(bare)
	check(bare_nav.get("face_point") == null, "a navigator without the member takes no write")
	var no_nav := FakePony.new()
	root.add_child(no_nav)
	GAME.clear_facing(no_nav)
	check(no_nav.get_child_count() == 0, "a body without a navigator takes both clears")

	var secondary := FakeSecondary.new()
	root.add_child(secondary)
	check(not GAME.look_toward(null, Vector3.ZERO, 0.4), "no gaze controller answers false")
	check(not GAME.look_toward(bare, Vector3.ZERO, 0.4), "a body without a gaze answers false")
	check(GAME.look_toward(secondary, Vector3(0.1, 0.2, 0.0), 0.4),
		"a gaze controller takes the turn")
	check(secondary.looks.size() == 1 and near(secondary.weight, 0.4),
		"the glance carries its angles and weight")

	var eyes := FakeEyes.new()
	root.add_child(eyes)
	GAME.aim_eyes(eyes, Vector3(1.0, 2.0, 3.0))
	check(eyes.target_world.is_equal_approx(Vector3(1.0, 2.0, 3.0))
		and near(eyes.target_weight, 1.0),
		"the eye aim writes the world target at full weight")
	GAME.aim_eyes(null, Vector3.ZERO)

	pony.global_position = Vector3(1.0, 2.0, 3.0)
	check(GAME.listen_point(pony).is_equal_approx(Vector3(1.0, 3.0, 3.0)),
		"a body without a listen point answers above its root")
	check(not GAME.listen_point(null).is_finite(), "no body has no listen point")
	var listener := FakeListener.new()
	root.add_child(listener)
	check(GAME.listen_point(listener).is_equal_approx(Vector3(0.5, 1.5, 0.5)),
		"a body with an ear point answers it")

	var posed := FakeActBody.new()
	root.add_child(posed)
	var eye := Transform3D(Basis(Vector3.UP, 0.2), Vector3(1.0, 2.0, 3.0))
	posed.eye = eye
	check(GAME.eye_transform(posed).is_equal_approx(eye), "the act body's eye reads")
	posed.eye = null
	check(not GAME.eye_transform(posed).is_finite(), "an unposed act body answers a non-finite eye")
	check(not GAME.eye_transform(bare).is_finite(), "a body without an eye answers a non-finite eye")

	var boop := FakeBoop.new()
	root.add_child(boop)
	boop.skull = Vector3(1.0, 2.0, 3.0)
	boop.nose = Vector3(1.0, 2.0, 4.0)
	check(GAME.skull_world(boop).is_equal_approx(Vector3(1.0, 2.0, 3.0)), "her skull reads")
	check(GAME.nose_world(boop).is_equal_approx(Vector3(1.0, 2.0, 4.0)), "her nose reads")
	check(not GAME.nose_world(bare).is_finite(), "a body without head surfaces answers INF")
	check(not GAME.muzzle_world(null).is_finite(), "no body has no muzzle")

	for node: Node in [body, form, pony, bare, no_nav, secondary, eyes, listener, posed, boop]:
		node.free()


## The standing view's writes: the pitch clamp, the facing clear, the glance weights and the camera
## aim all reach the game through the accessors.
func _check_view_writes() -> void:
	var main := FakeMain.new()
	var player := FakePlayer.new()
	main.add_child(player)
	main.player = player
	WORLD.bind_player(main.player)
	main.view = Camera3D.new()
	main.add_child(main.view)
	main.view.position = Vector3(0.0, 1.6, -0.4)
	player.camera = main.view
	root.add_child(main)
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	var pony := FakePony.new()
	root.add_child(pony)
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var eyes := FakeEyes.new()
	pony.eye_motion = eyes
	var secondary := FakeSecondary.new()
	pony.secondary = secondary
	var form := FakeForm.new()
	root.add_child(form)
	var pose := FakePose.new()
	root.add_child(pose)

	var facts := FACTS.new()
	facts.state = STATE_ACTIVE
	facts.pony = pony
	facts.free_camera_active = true
	facts.look_yaw = 0.0
	facts.look_pitch = 0.1
	facts.player_eye_height = 1.7
	facts.presentation_config = {"camera_pitch_deg": 0.0, "glance_back_speed": 1.0}
	facts.kiss = func() -> Variant: return FakeKiss.new()
	facts.pose = pose
	facts.set_head_back = func(value: float) -> void: pose.head_back = value
	var pose_view: RefCounted = VIEW.new()
	pose_view.id = CATALOG.STANDING
	pose_view.family = "standing"
	pose_view.settings_group = "standing"
	var config: Dictionary = _standing_config()
	pose_view.from_config = config
	pose_view.pose_config = config
	facts.pose_view = pose_view
	var view: RefCounted = CAMERA_VIEW.new(facts)
	view.call("_sync")

	# The free-look clamp holds the base look plus 45 degrees.
	player._pitch = 1.2
	view.call("clamp_look")
	check(near(float(player._pitch), float(facts.look_pitch) + CAMERA_VIEW.LOOK_PITCH_LIMIT),
		"the look pitch clamps at the cone edge")
	player.headset_view = true
	player._pitch = 1.2
	view.call("clamp_look")
	check(near(float(player._pitch), 1.2), "a headset keeps the look pitch")
	player.headset_view = false
	player._pitch = null
	view.call("clamp_look")
	check(player._pitch == null, "a rig without a pitch takes no look clamp")
	player._pitch = 0.0
	player.form_driver = form
	view.call("clamp_look")
	check(form.clamps == 1, "the view asks the form for its own view limit")
	player.form_driver = null

	# The facing lock clears her navigator and holds the act's basis.
	view.call("begin_facing", Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO))
	nav.face_point = Vector3.ZERO
	view.call("lock_facing")
	var face: Vector3 = nav.face_point
	check(not face.is_finite(), "the facing lock clears her face point")
	check(nav.conversation_clears == 1, "the facing lock clears her conversation aim")
	check(pony.global_basis.is_equal_approx(Basis(Vector3.UP, 0.5)),
		"the facing lock holds the act's facing")

	# The glance: the forced look and the lean-up look carry their own weights, and the pupils
	# follow Anon's camera.
	facts.forced_glance = "L"
	view.call("drive_glance", 0.1)
	check(secondary.looks.size() == 1 and near(secondary.weight, 0.4),
		"the forced glance turns her gaze at 0.4")
	check(eyes.target_weight > 0.0
		and eyes.target_world.is_equal_approx(main.view.global_position),
		"the glance aims her pupils at Anon's camera")
	check(pose.head_back > 0.0, "the glance eases the head throw-back")
	facts.forced_glance = ""
	facts.lean_forward = 1.0
	facts.lean_side = 0.0
	view.call("drive_glance", 0.1)
	check(secondary.looks.size() == 2 and near(secondary.weight, 0.3),
		"a full forward lean turns her gaze at 0.3")
	pony.eye_motion = null
	facts.forced_glance = "R"
	view.call("drive_glance", 0.1)
	check(secondary.looks.size() == 3, "the glance turns without an eye controller")

	# The standing lean look: the rig pitch and, for a plain rig, the player camera.
	facts.forced_glance = ""
	facts.lean_forward = 0.0
	facts.look_pitch = 0.1
	player._pitch = 0.0
	player.rotation.y = 0.0
	main.view.rotation.x = 0.0
	view.call("apply_lean_look")
	check(near(player.rotation.y, 0.0) and near(float(player._pitch), 0.1),
		"the standing lean writes the rig pitch")
	check(near(main.view.rotation.x, 0.1), "a plain rig aims the player camera")
	player.form_driver = form
	main.view.rotation.x = 0.0
	view.call("apply_lean_look")
	check(near(main.view.rotation.x, 0.0), "her form driver keeps the camera pitch")
	player.form_driver = null

	root.remove_child(pony)
	pony.free()
	root.remove_child(eyes)
	eyes.free()
	root.remove_child(secondary)
	secondary.free()
	root.remove_child(form)
	form.free()
	root.remove_child(pose)
	pose.free()
	WORLD.unbind()
	main.remove_child(player)
	main.remove_child(main.view)
	player.free()
	(main.view as Camera3D).free()
	main.free()
	root.remove_child(game)
	game.free()


## The camera's rendered look write lands on the typed pose node: the standing look goes to the
## player camera, and the kiss amount and climax flag follow the frame's state.
func _check_look_target() -> void:
	var made := _fixture()
	var camera: Variant = made["camera"]
	var facts: RefCounted = made["facts"]
	var pose := POSE.new()
	_pose(facts, "standing")
	camera.write_look_target(pose)
	check(pose.look_point.is_equal_approx((made["main"] as FakeMain).view.global_position),
		"the standing look target is the player camera")
	check(not pose.climaxing and near(pose.kiss, 0.0), "a kissless active frame writes no climax")
	facts.state = STATE_CLIMAX
	camera.write_look_target(pose)
	check(pose.climaxing, "the climax frame marks the pose")
	_pose(facts, "bed")
	camera.write_look_target(pose)
	check(not pose.look_point.is_finite(),
		"the bed gaze with no anatomy callback stays infinite")
	pose.free()
