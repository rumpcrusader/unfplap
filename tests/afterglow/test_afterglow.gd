extends SceneTree
## The afterglow facade (the standing close window and its reward) plus the runtime HUD surfaces
## that read it.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/afterglow/test_afterglow.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
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


func _facade(pose: String) -> Dictionary:
	var host := Host.new()
	var phase: RefCounted = AFTERGLOW.new()
	phase.caress_active = Callable(host, "is_caressing")
	phase.on_stay_close = Callable(host, "stay_close")
	phase.begin(pose, {"reward": true})
	return {"phase": phase, "host": host}


func _runtime(pose: String) -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.pose_id = pose
	runtime.state = 4 # AFTERGLOW
	runtime._preferences = PREF.resolve({})
	runtime._thrust_tracker = THRUST.new()
	return runtime


func run() -> void:
	var note_runtime: Node = _runtime("standing")
	note_runtime._id = "fluttershy"
	var idle_note: String = str(note_runtime.prompt_note())
	check(idle_note.contains("afterglow") and idle_note.contains("not caressing"),
		"afterglow prompt note carries the live state")
	check(idle_note.contains("[stay:"), "afterglow prompt note advertises the stay tag")
	var note_caress: Variant = note_runtime.call("_hand_controller")
	note_caress._caress_active = {"L": true, "R": false}
	check(note_runtime.prompt_note().contains("caressing your flank"), "caress note")
	note_caress._caress_active = {"L": false, "R": false}
	note_runtime._act_camera.lean_forward = 0.8
	check(note_runtime.prompt_note().contains("leaning in close"), "lean note")
	note_runtime.state = 2 # ACTIVE
	note_runtime._act_camera.lean_forward = 0.0
	check(note_runtime.prompt_note().contains("middle of sex"), "active prompt note")
	note_runtime.free()

	# The Y hint's End shade follows climaxes but only the earned caress reaches full pink.
	var pink_runtime: Node = _runtime("standing")
	check(near(pink_runtime.hud_y_pink(), 0.0), "End starts ink")
	pink_runtime.pony_climaxes = 2
	check(near(pink_runtime.hud_y_pink(), 0.5), "two climaxes shade End halfway")
	pink_runtime.pony_climaxes = 3
	check(near(pink_runtime.hud_y_pink(), HUD_LINES.Y_END_TINT_MAX),
		"three climaxes stop short of full pink")
	pink_runtime._afterglow.close_caress_earned = true
	check(near(pink_runtime.hud_y_pink(), 1.0), "the earned caress turns End fully pink")
	pink_runtime.pose_id = "missionary"
	check(near(pink_runtime.hud_y_pink(), HUD_LINES.Y_END_TINT_MAX),
		"missionary keeps the capped climax shade")
	pink_runtime.free()

	var active: Node = _runtime("standing")
	active.state = 2 # ACTIVE
	active.cue = "She is close."
	active._readiness.last_intensity = "firm"
	active._readiness.last_pattern = "steady"
	check(active.hud_cue_line(true) == "❤ 0/3 | She is close.", "HUD cue line")
	check(active.hud_cue_line(false) == "❤ 0/3", "HUD cue line without optional segments")
	check(active.hud_readiness_line(true) ==
		"Wants: firm & steady | You: firm & steady", "separate HUD readiness line")
	check(active.hud_readiness_line(false) == "", "readiness line hidden with readouts off")
	active.free()

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
	runtime_hint._afterglow.begin("standing", {})
	check(str(runtime_hint.call("close_hint")).contains("Stay close"),
		"the runtime forwards the close cue")
	runtime_hint.pose_id = "missionary"
	check(str(runtime_hint.call("close_hint")) == "", "the runtime hides the missionary cue")
	runtime_hint.free()

	# The facade owns the presentation row; the runtime only applies it.
	var standing_row: Dictionary = _facade("standing")["phase"].presentation()
	check(str(standing_row.get("pose_mode", "")) == "standing",
		"a standing afterglow keeps the standing pose")
	check(str(standing_row.get("afterglow_pose", "x")).is_empty(),
		"a standing afterglow carries no afterglow pose id")
	check(near(float(standing_row.get("tail_target", 0.0)), 0.55),
		"a standing afterglow lifts the tail")
	check(int(standing_row.get("tail_flicks", 0)) == 2, "a standing afterglow flicks the tail")
	check(str(standing_row.get("hud_state", "")) == "AFTERGLOW", "the row carries the HUD state")
	check(bool(standing_row.get("wings", false)), "the row asks for the wing return")
	var missionary_row: Dictionary = _facade("missionary")["phase"].presentation()
	check(str(missionary_row.get("pose_mode", "")) == "afterglow",
		"a missionary afterglow uses the afterglow pose")
	check(str(missionary_row.get("afterglow_pose", "")) == "missionary",
		"the afterglow pose id is the act's pose")
	check(near(float(missionary_row.get("tail_target", 0.0)), 0.35),
		"a missionary afterglow lowers the tail")
	check(int(missionary_row.get("tail_flicks", 1)) == 0,
		"a missionary afterglow does not flick the tail")

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
