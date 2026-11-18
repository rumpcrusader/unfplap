extends SceneTree
## The afterglow facade (the standing close window and its reward) plus the runtime HUD surfaces
## that read it.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/afterglow/test_afterglow.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
var failures := 0
var checks := 0


class Host extends RefCounted:
	var caressing := false
	var rewards: Array = []

	func is_caressing() -> bool:
		return caressing

	func stay_close(caressed: bool, reward: bool) -> void:
		rewards.append({"caressed": caressed, "reward": reward})


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _view(pose: String) -> RefCounted:
	var view: RefCounted = VIEW.new()
	view.id = pose
	view.family = "bed" if pose == "missionary" else "standing"
	view.afterglow = {"close_window": pose == "standing"}
	return view


func _facade(pose: String) -> Dictionary:
	var host := Host.new()
	var phase: RefCounted = AFTERGLOW.new()
	phase.caress_active = Callable(host, "is_caressing")
	phase.on_stay_close = Callable(host, "stay_close")
	phase.bind_view(_view(pose))
	phase.begin({"reward": true})
	return {"phase": phase, "host": host}


func _runtime(pose: String) -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.pose_id = pose
	runtime.state = 4 # AFTERGLOW
	runtime._preferences = PREF.resolve({})
	runtime._snapshot_settings()
	runtime._thrust_tracker = THRUST.new()
	return runtime


func run() -> void:
	var note_runtime: Node = _runtime("standing")
	note_runtime._id = "fluttershy"
	var idle_note: String = str(note_runtime.prompt_note())
	check(idle_note.contains("afterglow") and idle_note.contains("still close"),
		"afterglow prompt note carries the live state")
	check(not idle_note.contains("[stay:"), "afterglow prompt note does not advertise a stay tag")
	var note_caress: Variant = note_runtime.call("_hand_controller")
	note_caress._caress_active = {"L": true, "R": false}
	check(note_runtime.prompt_note().contains("caressing your flank"), "caress note")
	note_caress._caress_active = {"L": false, "R": false}
	note_runtime._act_camera.lean_forward = 0.8
	check(note_runtime.prompt_note().contains("leaning in close"), "lean note")
	note_runtime.state = 2 # ACTIVE
	note_runtime._act_camera.lean_forward = 0.0
	check(note_runtime.prompt_note().contains("having sex"), "active prompt note")
	note_runtime.free()

	# The oral afterglow holds the turned pose but opens no standing close window.
	var oral := _facade("standing_oral")
	var oral_phase: RefCounted = oral["phase"]
	check(not oral_phase.close_window, "the oral afterglow opens no close window")
	check(is_zero_approx(oral_phase.close_left), "the oral close window never starts")
	check(oral_phase.hint().is_empty(), "the oral afterglow shows no stay-close cue")
	var oral_row: Dictionary = oral_phase.presentation()
	check(near(float(oral_row.get("tail_target", 0.0)), 0.55),
		"the oral afterglow keeps the standing tail row")

	var standing := _facade("standing")
	var standing_phase: RefCounted = standing["phase"]
	check(near(standing_phase.close_left, AFTERGLOW.STAY_CLOSE_SECONDS),
		"standing close window starts")
	var hint: String = standing_phase.hint()
	check(hint.contains("Stay close") and hint.contains("caress"), "close cue names caressing")
	standing["host"].caressing = true
	standing_phase.close_tick(0.5)
	check(standing_phase.close_caress_seconds > 0.4, "caress time is counted")
	check(standing_phase.close_left < AFTERGLOW.STAY_CLOSE_SECONDS, "close window counts down")
	standing_phase.close_left = 0.01
	standing_phase.close_caress_seconds = 3.0
	standing_phase.close_tick(0.02)
	check(standing_phase.close_rewarded, "reaching the window grants the reward")
	check(standing["host"].rewards.size() == 1, "the reward is reported once")
	var reward: Dictionary = standing["host"].rewards[0]
	check(bool(reward.get("caressed", false)) and bool(reward.get("reward", false)),
		"the reward carries the caress and the positive act")
	check(standing_phase.hint() == "She seems content.", "reward cue")
	standing_phase.close_tick(1.0)
	check(standing["host"].rewards.size() == 1, "reward is not granted twice")

	var early := _facade("standing")
	early["phase"].cancel_close()
	check(near(early["phase"].close_left, 0.0), "early exit cancels the window")
	check(not early["phase"].close_rewarded, "early exit grants no reward")

	var mission := _facade("missionary")
	check(near(mission["phase"].close_left, 0.0), "missionary has no close window")
	check(mission["phase"].hint() == "", "missionary has no close cue")

	var runtime_hint: Node = _runtime("standing")
	runtime_hint._afterglow.bind_view(_view("standing"))
	runtime_hint._afterglow.begin({})
	check(str(runtime_hint.call("close_hint")).contains("Stay close"),
		"the runtime forwards the close cue")
	runtime_hint.pose_id = "missionary"
	check(str(runtime_hint.call("close_hint")) == "", "the runtime hides the missionary cue")
	runtime_hint.free()

	# The facade owns the presentation row; the runtime only applies it. The row names no pose:
	# the act's current pose holds through the afterglow.
	var standing_row: Dictionary = _facade("standing")["phase"].presentation()
	check(not standing_row.has("pose_mode") and not standing_row.has("afterglow_pose"),
		"a standing afterglow row names no pose mode")
	check(near(float(standing_row.get("tail_target", 0.0)), 0.55),
		"a standing afterglow lifts the tail")
	check(int(standing_row.get("tail_flicks", 0)) == 2, "a standing afterglow flicks the tail")
	check(str(standing_row.get("hud_state", "")) == "AFTERGLOW", "the row carries the HUD state")
	check(bool(standing_row.get("wings", false)), "the row asks for the wing return")
	var missionary_row: Dictionary = _facade("missionary")["phase"].presentation()
	check(not missionary_row.has("pose_mode") and not missionary_row.has("afterglow_pose"),
		"a missionary afterglow row names no pose mode")
	check(near(float(missionary_row.get("tail_target", 0.0)), 0.35),
		"a missionary afterglow lowers the tail")
	check(int(missionary_row.get("tail_flicks", 1)) == 0,
		"a missionary afterglow does not flick the tail")

	# The row follows the active view family only; without a view it falls back to the bed row.
	var no_view := AFTERGLOW.new()
	no_view.begin({"reward": true})
	var no_view_row: Dictionary = no_view.presentation()
	check(near(float(no_view_row.get("tail_target", 0.0)), 0.35),
		"an absent view lowers the tail")
	check(int(no_view_row.get("tail_flicks", 1)) == 0,
		"an absent view does not flick the tail")

	# The runtime writes no pose mode: the evaluator pair holds and only the weight is re-asserted.
	var held: Node = _runtime("standing")
	var fake_pose := FakePose.new()
	held._pose_session.pose_node = fake_pose
	held._pose_session.view().id = "standing"
	held._pose_session.view().pose_state = VIEW.STEADY
	held.call("_apply_afterglow_presentation", standing_row)
	check(fake_pose.written.is_empty(), "the afterglow runtime writes no pose mode")
	check(near(fake_pose.amount, 1.0) and near(fake_pose.target_amount, 1.0),
		"the afterglow runtime re-asserts the pose weight")
	check(held._pose_session.view().id == "standing"
		and held._pose_session.view().pose_state == VIEW.STEADY,
		"the pose view stays on the current pose")
	fake_pose.free()
	held.free()

	var wings := FakeWings.new()
	root.add_child(wings)
	var winged = WING.new()
	winged._winged = true
	winged._wing_hold = true
	winged._wings_node = wings
	winged.begin_afterglow()
	check(winged._wing_returning, "afterglow starts the slow wing return")
	check(wings.released, "afterglow releases the wing hold")
	check(not wings.opened, "afterglow targets folded wings")
	winged._wing_return_tick(WING.WING_AFTERGLOW_RETURN_SECONDS * 0.5)
	check(wings.tuck > 0.0 and wings.tuck < 1.0, "wings fold through the midpoint")
	winged._wing_return_tick(WING.WING_AFTERGLOW_RETURN_SECONDS)
	check(near(wings.tuck, 1.0), "wings reach the folded tuck")
	check(near(wings.half, 0.0), "wing half-open blend returns to zero")
	check(winged._wing_return_done, "wing return completes")
	winged.release()
	check(not winged._wing_returning and winged._wings_node == null,
		"wing return state clears on release")
	wings.free()

	print("AFTERGLOW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("AFTERGLOW_PASS")
	quit(0 if failures == 0 else 1)


## A pose node with the weight fields and no pose mode: a write to `mode`/`afterglow_pose` lands
## in `written` instead of succeeding.
class FakePose extends Node:
	var target_amount := 0.0
	var amount := 0.0
	var written: Array[String] = []

	func _set(property: StringName, _value: Variant) -> bool:
		written.append(str(property))
		return false


class FakeWings extends Node:
	var tuck := 0.0
	var half := 1.0
	var opened := true
	var released := false

	func release_hold(_owner: String) -> void:
		released = true

	func set_open(value: bool) -> void:
		opened = value


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps
