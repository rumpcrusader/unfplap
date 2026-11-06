extends SceneTree
## Standing afterglow close window and act-line keep rule.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_afterglow.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
const PREF := preload("res://mods/unfplap/preferences.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _runtime(pose: String) -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.pose_id = pose
	runtime.state = 4 # AFTERGLOW
	runtime._taste = PREF.resolve({})
	runtime._thrust_tracker = THRUST.new()
	return runtime


func run() -> void:
	var mission_text := MEMORY.afterglow_text("missionary")
	var standing_text := MEMORY.afterglow_text("standing")
	check(mission_text.contains("lying close"), "missionary afterglow context")
	check(standing_text.contains("standing close"), "standing afterglow context")
	check(mission_text.contains("not finished yet"), "afterglow context keeps the moment open")
	check(not mission_text.contains("Do not start another act"), "afterglow context is not a scripted line")
	var note_runtime: Node = _runtime("standing")
	note_runtime._id = "fluttershy"
	var idle_note: String = str(note_runtime.prompt_note())
	check(idle_note.contains("afterglow") and idle_note.contains("not caressing"),
		"afterglow prompt note carries the live state")
	check(idle_note.contains("[stay:"), "afterglow prompt note advertises the stay tag")
	var note_caress: Variant = note_runtime.call("_caress_controller")
	note_caress._caress_active = {"L": true, "R": false}
	check(note_runtime.prompt_note().contains("caressing your flank"), "caress note")
	note_caress._caress_active = {"L": false, "R": false}
	note_runtime._lean_forward = 0.8
	check(note_runtime.prompt_note().contains("leaning in close"), "lean note")
	note_runtime.state = 2 # ACTIVE
	note_runtime._lean_forward = 0.0
	check(note_runtime.prompt_note().contains("middle of sex"), "active prompt note")
	note_runtime.free()

	# The Y hint's End shade follows climaxes but only the earned caress reaches full pink.
	var pink_runtime: Node = _runtime("standing")
	check(near(pink_runtime.hud_y_pink(), 0.0), "End starts ink")
	pink_runtime.pony_climaxes = 2
	check(near(pink_runtime.hud_y_pink(), 0.5), "two climaxes shade End halfway")
	pink_runtime.pony_climaxes = 3
	check(near(pink_runtime.hud_y_pink(), RUNTIME.Y_END_TINT_MAX),
		"three climaxes stop short of full pink")
	pink_runtime._close_caress_earned = true
	check(near(pink_runtime.hud_y_pink(), 1.0), "the earned caress turns End fully pink")
	pink_runtime.pose_id = "missionary"
	check(near(pink_runtime.hud_y_pink(), RUNTIME.Y_END_TINT_MAX),
		"missionary keeps the capped climax shade")
	pink_runtime.free()

	check(RUNTIME.self_end_chance(true) < RUNTIME.self_end_chance(false),
		"holding her lowers the self-end chance")
	var held: Node = _runtime("standing")
	held._afterglow_elapsed = 100.0
	held._afterglow_hold_until = held._now_s() + 60.0
	held._self_end_tick(1.0)
	check(held.state == 4, "an accepted stay pauses the self-end roll")
	held.free()
	var early_end: Node = _runtime("standing")
	early_end._afterglow_elapsed = 15.0
	early_end._self_end_tick(1.0)
	check(early_end.state == 4, "no self-end before the minimum time")
	early_end.free()
	var stayed: Node = _runtime("standing")
	stayed._afterglow_elapsed = 100.0
	stayed._action_executor = FakeExecutor.new()
	stayed._on_action_outcome({"type": "stay", "status": "accepted"})
	check(stayed._afterglow_hold_until > stayed._now_s() + 50.0,
		"an accepted stay extends the afterglow hold")
	stayed._action_executor.free()
	stayed.free()

	check(MEMORY.keep_active_line("speaking", "line", "line", true), "speaking line is kept")
	check(not MEMORY.keep_active_line("thinking", "line", "line", true), "thinking line is dropped")
	check(not MEMORY.keep_active_line("speaking", "other", "line", true), "inactive line is dropped")
	check(not MEMORY.keep_active_line("speaking", "line", "line", false), "cancel-all drops even speaking")

	var active: Node = _runtime("standing")
	active.state = 2 # ACTIVE
	active.cue = "She is close."
	active._last_intensity = "firm"
	active._last_pattern = "steady"
	check(active.hud_cue_line(true) == "❤ 0/3 | She is close.", "HUD cue line")
	check(active.hud_cue_line(false) == "❤ 0/3", "HUD cue line without optional segments")
	check(active.hud_readiness_line(true) ==
		"Wants: firm & steady | You: firm & steady", "separate HUD readiness line")
	check(active.hud_readiness_line(false) == "", "readiness line hidden with readouts off")
	active.free()

	var standing: Node = _runtime("standing")
	standing._begin_close_window()
	check(near(standing._close_left, RUNTIME.STAY_CLOSE_SECONDS), "standing close window starts")
	var hint := str(standing.call("close_hint"))
	check(hint.contains("Stay close") and hint.contains("caress"), "close cue names caressing")
	var standing_caress: Variant = standing.call("_caress_controller")
	standing_caress._caress_active = {"L": true, "R": false}
	standing._afterglow_tick(0.5)
	check(standing._close_caress_seconds > 0.4, "caress time is counted")
	check(standing._close_left < RUNTIME.STAY_CLOSE_SECONDS, "close window counts down")
	standing._close_left = 0.01
	standing._close_caress_seconds = 3.0
	standing._afterglow_tick(0.02)
	check(standing._close_rewarded, "reaching the window grants the reward")
	check(standing.close_hint() == "She seems content.", "reward cue")
	standing._afterglow_tick(1.0)
	check(standing._close_rewarded, "reward is not granted twice")
	standing.free()

	var early: Node = _runtime("standing")
	early._begin_close_window()
	early._close_cancel()
	check(near(early._close_left, 0.0), "early exit cancels the window")
	check(not early._close_rewarded, "early exit grants no reward")
	early.free()

	var mission: Node = _runtime("missionary")
	mission._begin_close_window()
	check(near(mission._close_left, 0.0), "missionary has no close window")
	check(mission.close_hint() == "", "missionary has no close cue")
	mission.free()

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


class FakeExecutor extends Node:
	var movement := {"duration_s": 60.0}


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
