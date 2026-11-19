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


## The runtime's post-act face path without the runtime wrapper: the afterglow's plan carries
## the values, the face facade owns the face.
func _start_post_act_face(runtime: Node) -> void:
	var summary: Dictionary = runtime._summary_service.summary
	var plan: RefCounted = runtime._afterglow.post_act(false, runtime.satisfaction,
		runtime._act.aftercare_min, not summary.is_empty(), bool(summary.get("positive", false)))
	runtime._face.start_post_act(plan.face_context(summary))


func _end_mood_face(runtime: Node) -> void:
	runtime._face.end_mood_face()


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	var expressions := FakeExpressions.new()
	pony.add_child(expressions)
	pony.expressions = expressions
	root.add_child(pony)
	runtime.pony = pony
	runtime._act.features = {}
	runtime._act.preferences = {"tolerance": "normal", "intensity": "firm",
		"pattern": "steady", "touch": [], "talk": []}
	runtime._readiness.tolerance = FakeTolerance.new()
	runtime._act.climax_mode = "auto"
	runtime._act.first_time = true
	runtime._set_state(2) # ACTIVE
	return {"runtime": runtime, "pony": pony, "expressions": expressions}


func run() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var pony: Node3D = f["pony"]
	var expressions: FakeExpressions = f["expressions"]

	runtime._act.face_beat("start")
	check(expressions.dialogue_face == "shy", "first-time start is shy")
	check(int(expressions.finish_calls) == 1, "start face has a release hold")

	runtime._act.face_beat("close")
	check(expressions.dialogue_face == "anticipation", "close is anticipation")

	runtime._act.face_beat("warning")
	check(expressions.dialogue_face == "annoyed", "normal warning is annoyed")
	runtime._act.preferences["tolerance"] = "forgiving"
	runtime._act.face_beat("warning")
	check(expressions.dialogue_face == "sad", "forgiving warning is sad")

	runtime._summary_service.summary = {"grade": "great", "positive": true, "reward": true,
		"severe": false, "early": false, "mood": "happy"}
	runtime._act.face_beat("afterglow")
	check(expressions.dialogue_face == "affectionate", "positive afterglow is affectionate")

	runtime._act.preferences["tolerance"] = "normal"
	runtime._readiness.act_intensity_total = 6
	runtime._readiness.act_intensity_right = 6
	runtime._readiness.act_pattern_total = 6
	runtime._readiness.act_pattern_right = 6
	runtime._readiness.act_both_matches = 6
	runtime._readiness.act_liked_touch = 1
	runtime._act.face_beat("climax")
	check(expressions.dialogue_face == "shy", "warm climax uses shy")
	check(int(expressions.fluster_calls) == 1, "warm climax calls fluster")
	check(float(runtime._face.stare_release_until) > float(runtime._act.clock_s()),
		"warm climax releases the stare")

	runtime._act.climax_mode = "wide"
	runtime._act.face_beat("climax")
	check(expressions.dialogue_face == "", "forced wide climax clears the act face")

	expressions.dialogue_face = "happy"
	check(not bool(runtime._face.set_act_face("relaxed", 1.0)),
		"a spoken line keeps its face")

	expressions.dialogue_face = ""
	runtime._face.act_face = ""
	check(bool(runtime._face.set_act_face("relaxed", 1.0)), "an idle face can be set")
	expressions.dialogue_face = "amused"
	runtime._face.end_face()
	check(expressions.dialogue_face == "amused", "teardown never clears a line face")

	root.add_child(runtime)
	runtime.set_process(false)
	runtime.set_physics_process(false)
	expressions.dialogue_face = ""
	runtime.satisfaction = 100.0
	runtime._act.aftercare_min = 10
	runtime._summary_service.summary = {"grade": "great", "positive": true, "reward": true,
		"severe": false, "early": false, "mood": "happy"}
	_start_post_act_face(runtime)
	check(is_instance_valid(runtime._face.mood_face), "positive act starts the mood face")
	check(expressions.dialogue_face == "relaxed", "positive mood face is relaxed")
	check(bool(runtime._face.warm_note), "positive mood face sets the warm note")
	if is_instance_valid(runtime._face.mood_face):
		runtime._face.mood_face.set_physics_process(false)
	_end_mood_face(runtime)
	check(runtime._face.mood_face == null and not bool(runtime._face.warm_note),
		"mood face clears on a new act")

	expressions.dialogue_face = ""
	runtime._summary_service.summary = {"grade": "bad", "positive": false, "reward": false,
		"severe": false, "early": false, "mood": "sad"}
	_start_post_act_face(runtime)
	check(is_instance_valid(runtime._face.mood_face), "bad act starts the mood face")
	check(expressions.dialogue_face == "sad", "bad mood face is sad")
	check(not bool(runtime._face.warm_note), "bad mood face has no warm note")
	if is_instance_valid(runtime._face.mood_face):
		runtime._face.mood_face.set_physics_process(false)
	_end_mood_face(runtime)

	# The lids and the smile live in the facade: the runtime only gathers the state.
	runtime._set_state(2) # ACTIVE
	expressions.stare_calls = 0
	runtime._face.eyes_tick({"state": runtime.state, "close_rewarded": runtime._afterglow.close_rewarded, "eyes_active": runtime._kiss.eyes_active()})
	check(expressions.stare_on and is_equal_approx(expressions.stare_lids, FACE.ACT_LIDS),
		"ACTIVE holds the act lids")
	runtime._set_state(3) # CLIMAX
	expressions.stare_lids = -1.0
	runtime._face.eyes_tick({"state": runtime.state, "close_rewarded": runtime._afterglow.close_rewarded, "eyes_active": runtime._kiss.eyes_active()})
	check(expressions.stare_on and is_equal_approx(expressions.stare_lids, FACE.CLIMAX_LIDS),
		"CLIMAX opens the lids")
	runtime._set_state(4) # AFTERGLOW
	runtime._afterglow.close_rewarded = true
	expressions.stare_lids = -1.0
	runtime._face.eyes_tick({"state": runtime.state, "close_rewarded": runtime._afterglow.close_rewarded, "eyes_active": runtime._kiss.eyes_active()})
	check(is_equal_approx(expressions.stare_lids, FACE.AFTERGLOW_CLOSE_LIDS),
		"a rewarded close uses the sleepier afterglow lids")
	runtime._afterglow.close_rewarded = false
	runtime._set_state(0) # IDLE
	expressions.stare_calls = 0
	runtime._face.eyes_tick({"state": runtime.state, "close_rewarded": runtime._afterglow.close_rewarded, "eyes_active": runtime._kiss.eyes_active()})
	check(expressions.stare_calls == 0, "IDLE leaves the lids alone")
	runtime._set_state(2) # ACTIVE
	expressions.touch_calls = 0
	runtime._face.set_face(0.5, 0.4, 0.05)
	check(expressions.touch_kind == "unfplap_state" and is_equal_approx(expressions.touch_amount, 0.5),
		"the smile reaches the expressions node")
	check(is_instance_valid(runtime._face.face_timer), "a held smile starts the face timer")
	check(runtime._face.face_timer.time_left > 0.0, "the hold is running")
	runtime._face.clear_face()
	check(is_equal_approx(runtime._face.face_timer.time_left, 0.0), "clearing the face stops the timer")
	check(expressions.released == "unfplap_state", "clearing the face releases the touch")

	# The climax quality shape is the facade's; the runtime only gathers its counters.
	var quality: FACE.ActQuality = runtime._face.quality_for(runtime._readiness)
	check(is_equal_approx(quality.intensity_total, 6.0), "climax quality keeps the gathered intensity")
	check(is_equal_approx(quality.pattern_right, 6.0), "climax quality keeps the pattern matches")
	check(int(quality.dislikes_total) == 0 and not quality.overwhelmed,
		"climax quality reads the live dislike and overwhelm flags")

	root.remove_child(runtime)

	pony.free()
	runtime.free()
	print("RUNTIME_FACE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_FACE_PASS")
	quit(0 if failures == 0 else 1)
