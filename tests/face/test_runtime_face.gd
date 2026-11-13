extends SceneTree
## Runtime face beats with a fake expressions node: start, close, warning, afterglow, climax and
## the line-face ownership rule. No live world is needed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/face/test_runtime_face.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
var checks := 0
var failures := 0


class FakeExpressions extends Node:
	var dialogue_face := ""
	var fluster_amount := 0.0
	var fluster_calls := 0
	var finish_calls := 0
	var clear_calls := 0
	var stare_calls := 0
	var stare_on := false
	var stare_lids := -1.0
	var touch_calls := 0
	var touch_kind := ""
	var touch_amount := 0.0
	var released := ""

	func set_dialogue(value: String) -> void:
		dialogue_face = value

	func finish_dialogue(_delay := 3.0) -> void:
		finish_calls += 1

	func clear_dialogue() -> void:
		clear_calls += 1
		dialogue_face = ""

	func fluster(_seconds := 1.0, _peeks := true) -> void:
		fluster_calls += 1
		fluster_amount = 1.0

	func stare(on: bool, lids := -1.0) -> void:
		stare_calls += 1
		stare_on = on
		stare_lids = lids

	func touch(kind: String, amount := 1.0, _duration := 0.0) -> void:
		touch_calls += 1
		touch_kind = kind
		touch_amount = amount

	func release_touch(kind: String) -> void:
		released = kind


class FakePony extends Node3D:
	var expressions: Variant = null


class FakeTolerance:
	var distress := 0.0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	var expressions := FakeExpressions.new()
	pony.add_child(expressions)
	pony.expressions = expressions
	root.add_child(pony)
	runtime.pony = pony
	runtime._features = {"act_faces": true}
	runtime._preferences = {"tolerance": "normal", "intensity": "firm",
		"pattern": "steady", "touch": [], "talk": []}
	runtime._tolerance = FakeTolerance.new()
	runtime._act_climax_mode = "auto"
	runtime._first_time = true
	runtime.state = 2 # ACTIVE
	return {"runtime": runtime, "pony": pony, "expressions": expressions}


func run() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var pony: Node3D = f["pony"]
	var expressions: FakeExpressions = f["expressions"]

	runtime.call("_act_face_beat", "start")
	check(expressions.dialogue_face == "shy", "first-time start is shy")
	check(int(expressions.finish_calls) == 1, "start face has a release hold")

	runtime.call("_act_face_beat", "close")
	check(expressions.dialogue_face == "anticipation", "close is anticipation")

	runtime.call("_act_face_beat", "warning")
	check(expressions.dialogue_face == "annoyed", "normal warning is annoyed")
	runtime._preferences["tolerance"] = "forgiving"
	runtime.call("_act_face_beat", "warning")
	check(expressions.dialogue_face == "sad", "forgiving warning is sad")

	runtime._summary = {"grade": "great", "positive": true, "reward": true,
		"severe": false, "early": false, "mood": "happy"}
	runtime.call("_act_face_beat", "afterglow")
	check(expressions.dialogue_face == "affectionate", "positive afterglow is affectionate")

	runtime._preferences["tolerance"] = "normal"
	runtime._act_intensity_total = 6
	runtime._act_intensity_right = 6
	runtime._act_pattern_total = 6
	runtime._act_pattern_right = 6
	runtime._act_both_matches = 6
	runtime._act_liked_touch = 1
	runtime.call("_act_face_beat", "climax")
	check(expressions.dialogue_face == "shy", "warm climax uses shy")
	check(int(expressions.fluster_calls) == 1, "warm climax calls fluster")
	check(float(runtime._stare_release_until) > float(runtime.call("_now_s")),
		"warm climax releases the stare")

	runtime._act_climax_mode = "wide"
	runtime.call("_act_face_beat", "climax")
	check(expressions.dialogue_face == "", "forced wide climax clears the act face")

	expressions.dialogue_face = "happy"
	check(not bool(runtime.call("_set_act_face", "relaxed", 1.0)),
		"a spoken line keeps its face")

	expressions.dialogue_face = ""
	runtime._act_face = ""
	check(bool(runtime.call("_set_act_face", "relaxed", 1.0)), "an idle face can be set")
	expressions.dialogue_face = "amused"
	runtime.call("_end_act_face")
	check(expressions.dialogue_face == "amused", "teardown never clears a line face")

	root.add_child(runtime)
	runtime.set_process(false)
	runtime.set_physics_process(false)
	expressions.dialogue_face = ""
	runtime.satisfaction = 100.0
	runtime._aftercare_min = 10
	runtime._summary = {"grade": "great", "positive": true, "reward": true,
		"severe": false, "early": false, "mood": "happy"}
	runtime.call("_start_post_act_face")
	check(is_instance_valid(runtime._mood_face), "positive act starts the mood face")
	check(expressions.dialogue_face == "relaxed", "positive mood face is relaxed")
	check(bool(runtime._warm_note), "positive mood face sets the warm note")
	if is_instance_valid(runtime._mood_face):
		runtime._mood_face.set_physics_process(false)
	runtime.call("_end_mood_face")
	check(runtime._mood_face == null and not bool(runtime._warm_note),
		"mood face clears on a new act")

	expressions.dialogue_face = ""
	runtime._summary = {"grade": "bad", "positive": false, "reward": false,
		"severe": false, "early": false, "mood": "sad"}
	runtime.call("_start_post_act_face")
	check(is_instance_valid(runtime._mood_face), "bad act starts the mood face")
	check(expressions.dialogue_face == "sad", "bad mood face is sad")
	check(not bool(runtime._warm_note), "bad mood face has no warm note")
	if is_instance_valid(runtime._mood_face):
		runtime._mood_face.set_physics_process(false)
	runtime.call("_end_mood_face")

	# The lids and the smile live in the facade: the runtime only gathers the state.
	runtime.state = 2 # ACTIVE
	expressions.stare_calls = 0
	runtime.call("_eyes_tick")
	check(expressions.stare_on and is_equal_approx(expressions.stare_lids, FACE.ACT_LIDS),
		"ACTIVE holds the act lids")
	runtime.state = 3 # CLIMAX
	expressions.stare_lids = -1.0
	runtime.call("_eyes_tick")
	check(expressions.stare_on and is_equal_approx(expressions.stare_lids, FACE.CLIMAX_LIDS),
		"CLIMAX opens the lids")
	runtime.state = 4 # AFTERGLOW
	runtime._close_rewarded = true
	expressions.stare_lids = -1.0
	runtime.call("_eyes_tick")
	check(is_equal_approx(expressions.stare_lids, FACE.AFTERGLOW_CLOSE_LIDS),
		"a rewarded close uses the sleepier afterglow lids")
	runtime._close_rewarded = false
	runtime.state = 0 # IDLE
	expressions.stare_calls = 0
	runtime.call("_eyes_tick")
	check(expressions.stare_calls == 0, "IDLE leaves the lids alone")
	runtime.state = 2 # ACTIVE
	expressions.touch_calls = 0
	runtime.call("_set_face", 0.5, 0.4, 0.05)
	check(expressions.touch_kind == "unfplap_state" and is_equal_approx(expressions.touch_amount, 0.5),
		"the smile reaches the expressions node")
	check(is_instance_valid(runtime._face.face_timer), "a held smile starts the face timer")
	check(runtime._face.face_timer.time_left > 0.0, "the hold is running")
	runtime.call("_clear_face")
	check(is_equal_approx(runtime._face.face_timer.time_left, 0.0), "clearing the face stops the timer")
	check(expressions.released == "unfplap_state", "clearing the face releases the touch")

	# The climax quality shape is the facade's; the runtime only gathers its counters.
	var quality: Dictionary = runtime.call("_climax_quality_inputs")
	for key: String in ["intensity_total", "intensity_right", "pattern_total",
			"pattern_right", "both_matches", "liked_touch", "liked_talk", "dislikes_total",
			"distress", "seeks_touch", "seeks_talk", "overwhelmed"]:
		check(quality.has(key), "climax quality carries %s" % key)
	check(is_equal_approx(float(quality.get("intensity_total", -1.0)), 6.0),
		"climax quality keeps the gathered intensity")

	# The act-face gate is the facade's: act_faces off skips the beat.
	runtime._features = {"act_faces": false}
	expressions.dialogue_face = ""
	runtime.call("_act_face_beat", "start")
	check(expressions.dialogue_face == "", "act faces off skips the beat")
	runtime._features = {"act_faces": true}

	root.remove_child(runtime)

	pony.free()
	runtime.free()
	print("RUNTIME_FACE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_FACE_PASS")
	quit(0 if failures == 0 else 1)
