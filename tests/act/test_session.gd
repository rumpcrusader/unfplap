extends "res://mods/unfplap/tests/support/suite.gd"
## What this suite pins: the act session's one state writer, its timer verbs, its clock and its
## reset, plus the typed host/context seam and its no-op host. No tree and no act are needed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act/test_session.gd

const SESSION := preload("res://mods/unfplap/act/session.gd")
const HOST := preload("res://mods/unfplap/act/host.gd")
const CONTEXT := preload("res://mods/unfplap/act/context.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const INPUT := preload("res://mods/unfplap/act/input.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const FAKE_GATE := preload("res://mods/unfplap/tests/support/fakes/fake_act_gate.gd")

const State := ACT_STATE.State



## The one frame handle the schedule binds: it records the frame the session forwards.
class FakeTicker extends RefCounted:
	var frames: Array[String] = []
	var delta := 0.0

	func _init(log: Array[String]) -> void:
		frames = log

	func tick(value: float) -> void:
		delta = value
		frames.append("tick")

	func render(value: float) -> void:
		delta = value
		frames.append("render")


func _frame() -> Dictionary:
	var host: RefCounted = HOST.new()
	var context: RefCounted = CONTEXT.new()
	context.gate = SCENE_GATE.new()
	context.world = HANDLES.new()
	var session: RefCounted = SESSION.new()
	session.bind(host, context)
	return {"session": session, "host": host, "context": context}


## The hole command's one gate: the pose allows it, the act gate owns consent.
class FakePose extends POSE_SESSION:
	func request_command(_id: String) -> bool:
		return true


class FakeAnatomyHandle extends RefCounted:
	var target_value := 0
	var anus_calls := 0

	func can_target_vulva() -> bool:
		return true

	func target() -> int:
		return target_value

	func target_anus() -> void:
		anus_calls += 1
		target_value = 1

	func target_vulva() -> void:
		target_value = 0


class FakeHud extends HUD:
	var statuses: Array[String] = []

	## The base builds the live card and subscribes to settings; this suite drives no card.
	func _ready() -> void:
		pass

	func _exit_tree() -> void:
		pass

	func anatomy_status(text: String, _seconds := 2.0) -> void:
		statuses.append(text)


func run() -> void:
	var made := _frame()
	var session: RefCounted = made["session"]
	var host: RefCounted = made["host"]
	var context: RefCounted = made["context"]

	check(int(session.state) == State.IDLE, "a new session starts IDLE")
	check(session.state_name() == "IDLE", "the state name follows the state")
	check(session.host == host and session.context == context, "bind keeps the typed host and context")
	check(context.gate == context.gate and int(context.gate.state) == State.IDLE,
		"the gate is configured from the initial state")

	session._set_state(State.ACTIVE)
	check(int(session.state) == State.ACTIVE and session.state_name() == "ACTIVE",
		"_set_state writes the state")
	check(int(context.gate.state) == State.ACTIVE, "every state write refreshes the gate")

	# POSING_IN: the timer only reports its verdict; the runtime applies it.
	session.begin_pose_in()
	check(int(session.state) == State.POSING_IN, "begin_pose_in enters POSING_IN")
	check(is_equal_approx(float(session._pose_in_left), SESSION.POSE_IN_SECONDS),
		"begin_pose_in arms the pose timer")
	check(int(session.tick_timers(0.1)) == SESSION.PHASE_NONE, "a pending pose timer has no verdict")
	check(int(session.state) == State.POSING_IN, "tick_timers never writes the state")
	check(int(session.tick_timers(1.0)) == SESSION.ENTER_ACTIVE, "the elapsed pose timer enters ACTIVE")
	session.enter_active()
	check(int(session.state) == State.ACTIVE, "enter_active applies the verdict")

	# CLIMAX: the state, its whole timer and a zeroed progress.
	session.enter_climax()
	check(int(session.state) == State.CLIMAX, "enter_climax enters CLIMAX")
	check(is_equal_approx(float(session._climax_left), SESSION.CLIMAX_SECONDS),
		"enter_climax arms the climax timer")
	check(is_zero_approx(float(session._climax_progress)), "enter_climax clears the progress")
	session.tick_timers(SESSION.CLIMAX_SECONDS * 0.5)
	session.refresh_climax_progress()
	check(is_equal_approx(float(session._climax_progress), 0.5),
		"the climax progress is one minus the remaining half")
	check(is_equal_approx(session.climax_progress(), 0.5),
		"the typed progress read is what the render frame passes to the camera")
	check(int(session.tick_timers(SESSION.CLIMAX_SECONDS)) == SESSION.FINISH_CLIMAX,
		"the elapsed climax timer finishes the climax")
	session.enter_active()
	check(int(session.state) == State.ACTIVE, "the climax returns to ACTIVE by its own verb")

	# The two frame forwards hand the whole frame to the schedule and nothing else.
	var frames: Array[String] = []
	var ticker := FakeTicker.new(frames)
	session.ticker = ticker
	session.tick(0.02)
	session.render(0.02)
	check(frames == ["tick", "render"] and is_equal_approx(ticker.delta, 0.02),
		"the session forwards both frames to the one schedule")

	# AFTERGLOW then RESTORE: the restore timer has its own verb and a clean exit.
	session.enter_afterglow()
	check(int(session.state) == State.AFTERGLOW and session.state_name() == "AFTERGLOW",
		"enter_afterglow enters AFTERGLOW")
	check(int(session.tick_timers(1.0)) == SESSION.PHASE_NONE, "the afterglow has no phase timer")
	session.begin_restore()
	check(int(session.state) == State.RESTORE, "begin_restore enters RESTORE")
	check(is_equal_approx(float(session._restore_left), SESSION.RESTORE_SECONDS),
		"begin_restore arms the restore timer")
	check(int(session.tick_timers(1.0)) == SESSION.FINISH_RESTORE,
		"the elapsed restore timer finishes the restore")
	session.finish_restore()
	check(int(session.state) == State.IDLE, "finish_restore returns to IDLE")
	check(is_zero_approx(float(session._restore_left)), "finish_restore clears the restore timer")

	# The clock is monotonic and the check cadence fires once per interval.
	session.tick_clock(0.25)
	session.tick_clock(-1.0)
	check(is_equal_approx(float(session._clock_s), 0.25), "the clock clamps a negative delta")
	session.advance_act_seconds(2.0)
	check(is_equal_approx(float(session._act_seconds), 2.0), "the act seconds advance")
	check(not session.consume_check_clock(0.1) and not session.consume_check_clock(0.1),
		"the running check waits for its interval")
	check(session.consume_check_clock(0.1), "the running check fires on the interval")
	check(not session.consume_check_clock(0.1), "the running check restarts its accumulator")

	# reset_act clears the act's own values and keeps the processed clock.
	session.reset_act()
	check(is_zero_approx(float(session._act_seconds)), "reset_act clears the act seconds")
	check(is_zero_approx(float(session._pose_in_left)) and is_zero_approx(float(session._climax_left))
		and is_zero_approx(float(session._restore_left)), "reset_act clears every phase timer")
	check(is_equal_approx(float(session._clock_s), 0.25), "reset_act keeps the processed clock")

	session.clear_phase()
	session.enter_climax()
	session.clear_phase()
	check(is_zero_approx(float(session._climax_left)) and is_zero_approx(float(session._climax_progress)),
		"clear_phase drops a phase timer after a stop")
	session.enter_idle()
	check(int(session.state) == State.IDLE, "enter_idle ends the act")

	# The host is the only node surface and a node-less host is a quiet no-op.
	check(host.tree() == null, "a node-less host has no tree")
	check(host.viewport() == null, "a node-less host has no viewport")
	check(is_zero_approx(float(host.physics_delta())), "a node-less host has no physics delta")
	check(host.tween() == null, "a node-less host has no tween")
	var orphan := Node.new()
	host.add_child(orphan)
	check(orphan.get_parent() == null, "a node-less host parents nothing")
	orphan.free()

	_check_hole_command()
	finish()


## The desktop and VR paths share one hole command: without anal consent the target stays on the
## vulva and the HUD shows the refusal.
func _check_hole_command() -> void:
	var made := _frame()
	var session: RefCounted = made["session"]
	var host: RefCounted = made["host"]
	var context: RefCounted = made["context"]
	var gate := FAKE_GATE.new()
	context.world.act_gate = gate
	var pony := Node3D.new()
	root.add_child(pony)
	host.pony = pony
	var anatomy := FakeAnatomyHandle.new()
	var hud := FakeHud.new()
	root.add_child(hud)
	context.anatomy = anatomy
	context.hud = hud
	context.pose = FakePose.new()
	var input: RefCounted = INPUT.new()
	input.bind(host, context, session)
	session.input = input

	gate.consent_ok = false
	check(not input.command(ACT_COMMANDS.HOLE),
		"the hole command refuses without anal consent")
	check(anatomy.target_value == 0 and anatomy.anus_calls == 0,
		"a refused hole command leaves the target on the vulva")
	check(hud.statuses.size() == 1, "a refused hole command shows one status")
	gate.consent_ok = true
	check(input.command(ACT_COMMANDS.HOLE), "the hole command opens with anal consent")
	check(anatomy.target_value == 1 and anatomy.anus_calls == 1,
		"the allowed hole command turns the target")
	context.world.act_gate = null
	root.remove_child(pony)
	pony.free()
	root.remove_child(hud)
	hud.free()
	gate.free()
	context.pose = null
	input = null
