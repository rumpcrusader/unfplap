extends SceneTree
## Horse afterglow close window and act-line keep rule.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_afterglow.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
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
	check(MEMORY.keep_active_line("speaking", "line", "line", true), "speaking line is kept")
	check(not MEMORY.keep_active_line("thinking", "line", "line", true), "thinking line is dropped")
	check(not MEMORY.keep_active_line("speaking", "other", "line", true), "inactive line is dropped")
	check(not MEMORY.keep_active_line("speaking", "line", "line", false), "cancel-all drops even speaking")

	var active: Node = _runtime("horse")
	active.state = 2 # ACTIVE
	active.cue = "She's close."
	active._last_intensity = "firm"
	active._last_pattern = "steady"
	check(active.hud_cue_line(true) ==
		"❤ 0/5 | She's close. | Wants: firm & steady | You: firm & steady",
		"combined HUD cue line")
	check(active.hud_cue_line(false) == "❤ 0/5", "combined line without optional segments")
	active.free()

	var horse: Node = _runtime("horse")
	horse._begin_close_window()
	check(near(horse._close_left, RUNTIME.STAY_CLOSE_SECONDS), "horse close window starts")
	var hint := str(horse.call("close_hint"))
	check(hint.contains("Stay close") and hint.contains("caress"), "close cue names caressing")
	horse._caress_active = {"L": true, "R": false}
	horse._afterglow_tick(0.5)
	check(horse._close_caress_seconds > 0.4, "caress time is counted")
	check(horse._close_left < RUNTIME.STAY_CLOSE_SECONDS, "close window counts down")
	horse._close_left = 0.01
	horse._close_caress_seconds = 3.0
	horse._afterglow_tick(0.02)
	check(horse._close_rewarded, "reaching the window grants the reward")
	check(horse.close_hint() == "She seems content.", "reward cue")
	horse._afterglow_tick(1.0)
	check(horse._close_rewarded, "reward is not granted twice")
	horse.free()

	var early: Node = _runtime("horse")
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

	print("AFTERGLOW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("AFTERGLOW_PASS")
	quit(0 if failures == 0 else 1)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps
