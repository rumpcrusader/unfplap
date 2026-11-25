extends "res://mods/unfplap/tests/support/suite.gd"
## What this suite pins: the act render frame's fixed order — the view refresh, the pose space
## follow, the pose write and the render trace, then the look and the shot. No tree and no act.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act/test_tick.gd

const TICK := preload("res://mods/unfplap/act/tick.gd")
const SESSION := preload("res://mods/unfplap/act/session.gd")
const HOST := preload("res://mods/unfplap/act/host.gd")
const CONTEXT := preload("res://mods/unfplap/act/context.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/api.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const CAMERA := preload("res://mods/unfplap/camera/api.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const HANDOVER := preload("res://mods/unfplap/body_change/act.gd")

const State := ACT_STATE.State


## The session's read model: its two render writes record into the order log.
class FakeView extends RefCounted:
	var order: Array[String] = []

	func _init(log: Array[String]) -> void:
		order = log

	func refresh(_facts: Variant, _session: Variant) -> void:
		order.append("refresh_view")

	func pose_render(_session: Variant) -> void:
		order.append("pose_render")


## The pose session's two render reads: the live family and the space follow.
class FakePose extends POSE_SESSION:
	var order: Array[String] = []
	var live: POSE_VIEW = null
	var diag: POSE_SESSION.PoseDiagnostics = null

	func _init(log: Array[String], view_in: POSE_VIEW, diag_in: POSE_SESSION.PoseDiagnostics) -> void:
		order = log
		live = view_in
		diag = diag_in

	func view() -> POSE_VIEW:
		return live

	func follow_space(family: String) -> void:
		order.append("follow_space:%s" % family)

	func diagnostics() -> POSE_SESSION.PoseDiagnostics:
		return diag


## The diagnostics handle's one render write.
class FakeDiagnostics extends POSE_SESSION.PoseDiagnostics:
	var order: Array[String] = []

	func _init(log: Array[String]) -> void:
		order = log

	func trace_sample(_state: int) -> void:
		order.append("trace_sample")


## The context's camera view: the look clamp and the speed read.
class FakeCameraView extends CAMERA_VIEW:
	var order: Array[String] = []

	func _init(log: Array[String]) -> void:
		order = log

	func clamp_look() -> void:
		order.append("clamp_look")

	func speed() -> float:
		return 0.0


## The act camera: the look target and the shot.
class FakeCamera extends CAMERA:
	var order: Array[String] = []

	func _init(log: Array[String]) -> void:
		order = log

	func write_look_target() -> void:
		order.append("write_look_target")

	func tick_shot(_delta: float, _state: int, _speed: float, _climax_progress: float) -> void:
		order.append("tick_shot")


## The act audio: the one render tick.
class FakeAudio extends RefCounted:
	var order: Array[String] = []

	func _init(log: Array[String]) -> void:
		order = log

	func tick(_delta: float, _state: int, _rate: float) -> void:
		order.append("audio_tick")


## The body-change handover: no suspension, so the render branch runs its work.
class FakeHandover extends HANDOVER:
	func _init() -> void:
		pass


func run() -> void:
	var order: Array[String] = []
	var host: RefCounted = HOST.new()
	var context: RefCounted = CONTEXT.new()
	context.gate = SCENE_GATE.new()
	context.world = HANDLES.new()
	var session: RefCounted = SESSION.new()
	session.bind(host, context)
	var tick: RefCounted = TICK.new()
	tick.bind(host, context, session, null)

	var view := POSE_VIEW.new()
	view.family = "bed"
	var pose := FakePose.new(order, view, FakeDiagnostics.new(order))
	var camera := FakeCamera.new(order)
	var readiness: READINESS = READINESS.new()
	context.pose = pose
	context.handover = FakeHandover.new()
	context.view = FakeCameraView.new(order)
	context.camera = camera
	context.audio = FakeAudio.new(order)
	context.readiness = readiness
	session.view = FakeView.new(order)
	session._set_state(State.ACTIVE)

	tick.render(0.0)

	check_eq(", ".join(order),
		"refresh_view, follow_space:bed, pose_render, trace_sample, clamp_look, "
		+ "write_look_target, tick_shot, audio_tick",
		"the render frame refreshes the view, follows the pose space, writes the pose and "
		+ "traces it before the look and the shot")

	context.gate.free()
	pose.free()
	camera.free()
	readiness.free()
	finish()
