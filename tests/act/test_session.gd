extends "res://mods/unfplap/tests/support/suite.gd"
## What this suite pins: the act session's one state writer, its timer verbs, its clock and its
## reset, plus the typed host/context seam and its no-op host. No tree and no act are needed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act/test_session.gd

const SESSION := preload("res://mods/unfplap/act/session.gd")
const HOST := preload("res://mods/unfplap/act/host.gd")
const CONTEXT := preload("res://mods/unfplap/act/context.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/api.gd")
const INPUT := preload("res://mods/unfplap/act/input.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const HUD := preload("res://mods/unfplap/hud/api.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const SUMMARY := preload("res://mods/unfplap/summary/api.gd")
const ACT_METER := preload("res://mods/unfplap/shared/act_meter.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const FAKE_GATE := preload("res://mods/unfplap/tests/support/fakes/fake_act_gate.gd")

const State := ACT_STATE.State
const PROGRESS_KEYS: Array[String] = [
	"act_id", "climaxes", "duration_s", "form_id", "heat", "mood",
	"pony_id", "pose", "schema", "state",
]
const RESULT_KEYS: Array[String] = [
	"act_id", "climaxes", "duration_s", "form_id", "forms", "grade",
	"outcome", "pony_id", "pose", "schema", "stop_reasons", "thrusts",
]
const OUTCOME_KEYS: Array[String] = ["mood", "romance"]
const PROGRESS_TYPES := {
	"schema": TYPE_INT,
	"act_id": TYPE_INT,
	"state": TYPE_STRING,
	"pony_id": TYPE_STRING,
	"form_id": TYPE_STRING,
	"pose": TYPE_STRING,
	"duration_s": TYPE_FLOAT,
	"mood": TYPE_STRING,
	"climaxes": TYPE_DICTIONARY,
	"heat": TYPE_BOOL,
}
const CLIMAX_TYPES := {"current": TYPE_INT, "limit": TYPE_INT}
const RESULT_TYPES := {
	"schema": TYPE_INT,
	"act_id": TYPE_INT,
	"pony_id": TYPE_STRING,
	"form_id": TYPE_STRING,
	"pose": TYPE_STRING,
	"duration_s": TYPE_FLOAT,
	"thrusts": TYPE_INT,
	"climaxes": TYPE_DICTIONARY,
	"grade": TYPE_STRING,
	"forms": TYPE_ARRAY,
	"stop_reasons": TYPE_ARRAY,
	"outcome": TYPE_DICTIONARY,
}
const OUTCOME_TYPES := {
	"romance": TYPE_INT,
	"mood": TYPE_STRING,
}



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


## Release the frame's one Node: its context's gate.
func _free_frame(made: Dictionary) -> void:
	var context: RefCounted = made["context"]
	(context.gate as Node).free()


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


## The summary commit's view seam: the act's own values, one readiness read and the route's
## ending, with no tree and no context.
class FakeView extends RefCounted:
	var meter := ACT_METER.new()

	func summary_snapshot(session: Variant) -> SUMMARY.ActSnapshot:
		var ending := SUMMARY.ActSnapshot.Ending.COMPLETE
		if session.stopped_by_her:
			ending = SUMMARY.ActSnapshot.Ending.STOPPED
		elif session.ended_early:
			ending = SUMMARY.ActSnapshot.Ending.EARLY
		var out := SUMMARY.ActSnapshot.new(str(session.pony_id), str(session.event_id), ending)
		out.seconds = float(session.act_seconds())
		out.preferences = session.preferences
		out.meter = meter
		return out

	func summary_exchange() -> SUMMARY.Exchange:
		return SUMMARY.Exchange.new(-1e9, "")


## The peak record's line read; the suite has no spoken line.
class FakeDialogue extends DIALOGUE:
	func last_spoken_at() -> float:
		return -1e9

	func last_spoken_line() -> String:
		return ""


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

	_check_report()
	_check_form_sequence()
	_check_states()
	_check_hole_command()
	_free_frame(made)
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
	context.pose.free()
	context.pose = null
	input = null
	_free_frame(made)


## The cross-mod reports: the progress change key, the final IDLE, and the one committed result.
func _check_report() -> void:
	var made := _frame()
	var session: RefCounted = made["session"]
	var context: RefCounted = made["context"]
	var readiness := READINESS.new()
	var summary := SUMMARY.new()
	var dialogue := FakeDialogue.new()
	context.readiness = readiness
	context.summary = summary
	context.dialogue = dialogue
	summary.wire(null)
	session.view = FakeView.new()
	session.ticker = FakeTicker.new([])
	session.pony_id = "chrysalis"
	session.serial = 12
	session.pose_id = "missionary"
	session.event_id = "intimacy_chrysalis_12"
	var form := BODY_FORM.BodyForm.new()
	form.pony_id = "chrysalis"
	form.form_name = "Chrysalis"
	var progress: Array[Dictionary] = []
	var results: Array[Dictionary] = []
	session.progress.connect(func(data: Dictionary) -> void: progress.append(data))
	session.result.connect(func(data: Dictionary) -> void: results.append(data))
	session.advance_act_seconds(18.6)
	session._set_state(State.POSING_IN)
	session.adopt_display_name(form, null)
	session.tick(0.02)

	check_size(progress, 1, "the first frame emits one progress update")
	var first: Dictionary = progress[0] if not progress.is_empty() else {}
	check_eq(_keys(first), PROGRESS_KEYS, "the progress payload key surface")
	check_eq(int(first.get("schema", 0)), 1, "the progress schema")
	check_eq(int(first.get("act_id", 0)), 12, "the act serial correlates the payload")
	check_eq(str(first.get("state", "")), "POSING_IN", "the start state is reported")
	check_eq(str(first.get("pony_id", "")), "chrysalis", "the stable pony id is reported")
	check_eq(str(first.get("form_id", "")), "chrysalis", "her own form normalizes to the pony id")
	check_eq(str(first.get("pose", "")), "missionary", "the running pose is reported")
	check_approx(float(first.get("duration_s", -1.0)), 18.6, "the act duration is a snapshot")
	check_eq(str(first.get("mood", "")), "warming", "the readiness mood is reported")
	check_eq(first.get("climaxes"), {"current": 0, "limit": 0}, "the climax pair is reported")
	check_eq(bool(first.get("heat", true)), false, "heat is reported")
	_check_types(first, PROGRESS_TYPES, "progress")
	_check_types(first.get("climaxes", {}) as Dictionary, CLIMAX_TYPES, "progress.climaxes")

	session.tick(0.02)
	check_size(progress, 1, "an unchanged tick emits no progress")
	readiness.mood = "close"
	session.tick(0.02)
	check_size(progress, 2, "a mood change emits one progress update")
	check_eq(str(progress[1].get("mood", "")), "close", "the changed mood is reported")
	readiness.pony_climaxes = 1
	session.tick(0.02)
	check_size(progress, 3, "a climax change emits one progress update")
	check_eq(progress[2].get("climaxes"), {"current": 1, "limit": 0},
		"the changed climax count is reported")
	session.cycle_heat = true
	session.tick(0.02)
	check_size(progress, 4, "a heat flip emits one progress update")
	check_eq(bool(progress[3].get("heat", false)), true, "the changed heat is reported")
	form.form_id = "fluttershy"
	form.form_name = "Fluttershy"
	session.adopt_display_name(form, null)
	session.tick(0.02)
	check_size(progress, 5, "a form change emits one progress update")
	check_eq(str(progress[4].get("form_id", "")), "fluttershy", "the borrowed form is reported")

	session.pose_id = ""
	session.enter_idle()
	session.tick(0.02)
	check_size(progress, 6, "the final IDLE emits one progress update")
	check_eq(str(progress[5].get("state", "")), "IDLE", "the end state is reported")
	check_eq(str(progress[5].get("pose", "")), "", "the final pose is already restored")
	readiness.mood = "relaxed"
	readiness.satisfaction = 40.0
	session.tick(0.02)
	check_size(progress, 6, "the after-act IDLE decay emits no progress")

	readiness.act_thrusts = 143
	readiness.pony_climaxes = 2
	session.pose_id = "missionary"
	session.advance_act_seconds(167.8)
	var view: FakeView = session.view
	view.meter.thrusts = 143
	view.meter.pony_climaxes = 2
	session.finish()
	check_size(results, 1, "the normal end emits one result")
	var result: Dictionary = results[0] if not results.is_empty() else {}
	check_eq(_keys(result), RESULT_KEYS, "the result payload key surface")
	check_eq(int(result.get("schema", 0)), 1, "the result schema")
	check_eq(int(result.get("act_id", 0)), 12, "the result keeps the act serial")
	check_eq(str(result.get("form_id", "")), "fluttershy", "the form at the commit is reported")
	check_eq(result.get("forms"), ["chrysalis", "fluttershy"],
		"the forms start with her own and keep their order")
	check_eq(str(result.get("pose", "")), "missionary", "the act pose is reported")
	check_approx(float(result.get("duration_s", -1.0)), 186.4, "the act duration at the commit")
	check_eq(int(result.get("thrusts", 0)), 143, "her real strokes are reported")
	check_eq(result.get("climaxes"), {"current": 2, "limit": 0}, "the commit climax pair")
	check_eq(str(result.get("grade", "")), "great", "the grade is reported")
	check_eq(result.get("stop_reasons"), [], "a clean act has no stop reasons")
	check_eq(_keys(result.get("outcome", {}) as Dictionary), OUTCOME_KEYS,
		"the outcome key surface")
	check_eq(result.get("outcome"), {"romance": 2, "mood": "happy"},
		"the outcome is the summary's own values")
	_check_types(result, RESULT_TYPES, "result")
	_check_types(result.get("climaxes", {}) as Dictionary, CLIMAX_TYPES, "result.climaxes")
	_check_types(result.get("outcome", {}) as Dictionary, OUTCOME_TYPES, "result.outcome")
	_check_string_array(result.get("forms"), "result.forms")
	_check_string_array(result.get("stop_reasons"), "result.stop_reasons")

	session.finish()
	check_size(results, 1, "a second commit emits no second result")
	check(session.act_score != null and not bool(session.act_score.skipped),
		"the session holds the act's verdict")

	session.reset_act()
	check(session.act_score == null, "reset_act clears the verdict")
	session.serial = 13
	session.pose_id = "missionary"
	session.event_id = "intimacy_chrysalis_13"
	session.advance_act_seconds(42.0)
	readiness.act_thrusts = 20
	readiness.pony_climaxes = 1
	session.preferences = {"tolerance": "strict", "intensity": "soft", "pattern": "steady",
		"talk": [], "touch": [], "dislikes": ["smack"]}
	view.meter.thrusts = 20
	view.meter.pony_climaxes = 1
	view.meter.touch_dislikes = {"smack": 2}
	session.stopped_by_her = true
	session.adopt_display_name(form, null)
	session.finish()
	check_size(results, 2, "her stop emits one result")
	var early: Dictionary = results[1] if results.size() > 1 else {}
	check_eq(early.get("stop_reasons"), ["stopped_by_her", "disliked_smack", "severe_smack"],
		"the summary's reasons are copied to the result")
	check_eq(early.get("outcome"), {"romance": -1, "mood": "angry"},
		"the stopped outcome is reported")
	check_eq(early.get("forms"), ["fluttershy"],
		"a new act starts its sequence from the form in use")

	session.reset_act()
	session.stopped_by_her = false
	check(not bool(session._result_emitted), "reset_act clears the result guard")
	check_empty(session._forms_taken, "reset_act clears the form sequence")
	view.meter.thrusts = 0
	view.meter.pony_climaxes = 0
	view.meter.touch_dislikes = {}
	session.preferences = {}
	session.finish()
	check(session.act_score != null and bool(session.act_score.skipped),
		"an act with no time and no strokes is a skipped verdict")
	check_size(results, 2, "a skipped act emits no result")

	context.readiness = null
	context.summary = null
	context.dialogue = null
	readiness.free()
	summary.free()
	dialogue.free()
	_free_frame(made)


## The literal change sequence: the form at act start first, then one entry per change, repeats
## included; a disguised start begins with the form she was wearing.
func _check_form_sequence() -> void:
	var made := _frame()
	var session: RefCounted = made["session"]
	var context: RefCounted = made["context"]
	var readiness := READINESS.new()
	var summary := SUMMARY.new()
	var dialogue := FakeDialogue.new()
	context.readiness = readiness
	context.summary = summary
	context.dialogue = dialogue
	summary.wire(null)
	session.view = FakeView.new()
	session.ticker = FakeTicker.new([])
	session.pony_id = "chrysalis"
	session.serial = 21
	session.pose_id = "missionary"
	session.event_id = "intimacy_chrysalis_21"
	var results: Array[Dictionary] = []
	session.result.connect(func(data: Dictionary) -> void: results.append(data))
	var form := BODY_FORM.BodyForm.new()
	form.pony_id = "chrysalis"
	form.form_name = "Chrysalis"
	session.adopt_display_name(form, null)
	form.form_id = "fluttershy"
	form.form_name = "Fluttershy"
	session.adopt_display_name(form, null)
	form.form_id = ""
	form.form_name = "Chrysalis"
	session.adopt_display_name(form, null)
	form.form_id = "rarity"
	form.form_name = "Rarity"
	session.adopt_display_name(form, null)
	session.advance_act_seconds(60.0)
	var view: FakeView = session.view
	view.meter.thrusts = 10
	session.finish()
	check_size(results, 1, "the literal sequence emits one result")
	var data: Dictionary = results[0] if not results.is_empty() else {}
	check_eq(data.get("forms"), ["chrysalis", "fluttershy", "chrysalis", "rarity"],
		"the forms keep every change in order, repeats included")
	check_eq(str(data.get("form_id", "")), "rarity", "the result form is the current form")

	session.reset_act()
	session.serial = 22
	session.event_id = "intimacy_chrysalis_22"
	form.form_id = "fluttershy"
	form.form_name = "Fluttershy"
	session.adopt_display_name(form, null)
	form.form_id = ""
	form.form_name = "Chrysalis"
	session.adopt_display_name(form, null)
	session.advance_act_seconds(60.0)
	session.finish()
	check_size(results, 2, "the disguised start emits one result")
	var disguised: Dictionary = results[1] if results.size() > 1 else {}
	check_eq(disguised.get("forms"), ["fluttershy", "chrysalis"],
		"a disguised start begins with the form in use, not a synthetic own form")
	check_eq(str(disguised.get("form_id", "")), "chrysalis",
		"the revealed result form is her own")

	context.readiness = null
	context.summary = null
	context.dialogue = null
	readiness.free()
	summary.free()
	dialogue.free()
	_free_frame(made)


## Every act state reports once, and an unchanged tick adds none.
func _check_states() -> void:
	var made := _frame()
	var session: RefCounted = made["session"]
	var context: RefCounted = made["context"]
	var readiness := READINESS.new()
	context.readiness = readiness
	session.ticker = FakeTicker.new([])
	var progress: Array[Dictionary] = []
	session.progress.connect(func(data: Dictionary) -> void: progress.append(data))
	var seen := progress.size()
	session.begin_pose_in()
	session.tick(0.02)
	_check_state(progress, seen, "POSING_IN", "the pose-in transition")
	seen = progress.size()
	session.tick(0.02)
	check_size(progress, seen, "an unchanged tick after a transition adds no progress")
	seen = progress.size()
	session.enter_active()
	session.tick(0.02)
	_check_state(progress, seen, "ACTIVE", "the active transition")
	seen = progress.size()
	session.enter_climax()
	session.tick(0.02)
	_check_state(progress, seen, "CLIMAX", "the climax transition")
	seen = progress.size()
	session.enter_active()
	session.tick(0.02)
	_check_state(progress, seen, "ACTIVE", "the climax return")
	seen = progress.size()
	session.enter_afterglow()
	session.tick(0.02)
	_check_state(progress, seen, "AFTERGLOW", "the afterglow transition")
	seen = progress.size()
	session.begin_restore()
	session.tick(0.02)
	_check_state(progress, seen, "RESTORE", "the restore transition")
	seen = progress.size()
	session.enter_idle()
	session.tick(0.02)
	_check_state(progress, seen, "IDLE", "the idle transition")
	seen = progress.size()
	session.tick(0.02)
	check_size(progress, seen, "the settled act emits no further progress")
	check_size(progress, 7, "each act state emits exactly one progress update")

	context.readiness = null
	readiness.free()
	_free_frame(made)


func _check_state(progress: Array[Dictionary], before: int, expected: String,
		label: String) -> void:
	check_size(progress, before + 1, "%s emits one progress update" % label)
	var data: Dictionary = progress[before] if progress.size() > before else {}
	check_eq(str(data.get("state", "")), expected, "%s reports %s" % [label, expected])


func _check_types(data: Dictionary, types: Dictionary, label: String) -> void:
	for key: String in types:
		check_eq(typeof(data.get(key)), int(types[key]), "%s.%s payload type" % [label, key])


func _check_string_array(value: Variant, label: String) -> void:
	check(value is Array, "%s is an array" % label)
	if not value is Array:
		return
	for item: Variant in value:
		check_eq(typeof(item), TYPE_STRING, "%s element is a string" % label)


func _keys(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: Variant in data.keys():
		out.append(str(key))
	out.sort()
	return out
