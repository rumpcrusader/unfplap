extends "res://mods/unfplap/tests/support/suite.gd"
## Pure act-face mapping: face beats, the live climax style, blush levels and prompt hints.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/face/test_act_face.gd

const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const MOOD_FACE := preload("res://mods/unfplap/face/mood_face.gd")


class FakeExpressions extends Node:
	var dialogue_face := ""
	var set_calls := 0
	var clear_calls := 0

	func set_dialogue(value: String) -> void:
		dialogue_face = value
		set_calls += 1

	func clear_dialogue() -> void:
		dialogue_face = ""
		clear_calls += 1

	func finish_dialogue(_delay := 3.0) -> void:
		pass


class FakeMoodPony extends Node3D:
	var expressions: Variant = null
	var boop_node: Variant = null

func _quality(overrides := {}) -> Dictionary:
	var base := {
		"intensity_total": 6,
		"intensity_right": 6,
		"pattern_total": 6,
		"pattern_right": 6,
		"both_matches": 6,
		"liked_touch": 0,
		"liked_talk": 0,
		"dislikes_total": 0,
		"distress": 0.0,
		"seeks_touch": false,
		"seeks_talk": false,
		"overwhelmed": false,
	}
	for key: Variant in overrides:
		base[key] = overrides[key]
	return base


func run() -> void:
	for face: String in ACT_FACE.FACES:
		check(ACT_FACE.valid_face(face), "valid face %s" % face)
	check(not ACT_FACE.valid_face("not_a_face"), "unknown face is rejected")

	for mood: String in ACT_FACE.MOOD_FACES:
		var face := str(ACT_FACE.MOOD_FACES[mood])
		check(face.is_empty() or ACT_FACE.valid_face(face), "mood %s maps to a face" % mood)

	check(near(ACT_FACE.blush_for("posing_in", 0.0), 0.60, 0.001), "posing-in blush")
	check(near(ACT_FACE.blush_for("active", 0.0), 0.55, 0.001), "active blush at zero")
	check(near(ACT_FACE.blush_for("active", 100.0), 1.0, 0.001), "active blush at full readiness")
	check(near(ACT_FACE.blush_for("climax", 0.0), 1.0, 0.001), "climax blush")
	check(near(ACT_FACE.blush_for("afterglow", 0.0), 0.40, 0.001), "afterglow blush")
	check(near(ACT_FACE.blush_for("active", 0.0, false), 1.0, 0.001), "disabled arc is full blush")

	var perfect := ACT_FACE.climax_style(_quality())
	check(str(perfect.get("style", "")) == "ooo", "perfect physical act is round-mouthed")
	check(near(float(perfect.get("score", 0.0)), 0.675, 0.001), "perfect physical score")

	var warm := ACT_FACE.climax_style(_quality({"liked_touch": 1}))
	check(str(warm.get("style", "")) == "fluster", "warm matched act is flustered")
	check_approx(float(warm.get("score", 0.0)), 0.833, "warm matched score", 0.001)

	var poor := ACT_FACE.climax_style(_quality({
		"intensity_right": 1, "pattern_right": 0, "both_matches": 0,
	}))
	check(str(poor.get("style", "")) == "wide", "poor match stays wide-eyed")

	var disliked := ACT_FACE.climax_style(_quality({"liked_touch": 1, "dislikes_total": 2}))
	check(str(disliked.get("style", "")) == "ooo", "dislikes pull a warm act down")
	var broken := ACT_FACE.climax_style(_quality({
		"liked_touch": 1, "dislikes_total": 3, "distress": 8.0,
	}))
	check(str(broken.get("style", "")) == "wide", "severe dislike and distress stay wide")

	var forced := ACT_FACE.climax_style_for_mode("fluster", _quality())
	check(str(forced.get("style", "")) == "fluster" and bool(forced.get("forced", false)),
		"forced fluster wins")
	var forced_auto := ACT_FACE.climax_style_for_mode("auto", _quality())
	check(not bool(forced_auto.get("forced", true)), "auto is not forced")

	var start_first := ACT_FACE.plan_for("start", {"first_time": true})
	check(str(start_first.get("face", "")) == "shy", "first time starts shy")
	var start_repeat := ACT_FACE.plan_for("start", {"first_time": false})
	check(str(start_repeat.get("face", "")) == "relaxed", "repeat starts relaxed")
	var close := ACT_FACE.plan_for("close")
	check(str(close.get("face", "")) == "anticipation", "close face is anticipation")

	var climax_warm := ACT_FACE.plan_for("climax", {"mode": "auto", "quality": _quality({"liked_touch": 1})})
	check(str(climax_warm.get("face", "")) == "shy", "warm climax uses shy")
	check(near(float(climax_warm.get("fluster_s", 0.0)), 5.0, 0.001), "warm climax flusters")
	check(bool(climax_warm.get("release_stare", false)), "warm climax releases the stare")
	var climax_ooo := ACT_FACE.plan_for("climax", {"mode": "auto", "quality": _quality()})
	check(str(climax_ooo.get("face", "")) == "ooo", "physical climax uses ooo")
	check(not bool(climax_ooo.get("release_stare", true)), "round mouth keeps the stare")
	var climax_wide := ACT_FACE.plan_for("climax", {"mode": "auto", "quality": poor})
	check(str(climax_wide.get("face", "")) == "", "poor climax has no extra face")

	var positive := {"grade": "great", "positive": true, "reward": true, "severe": false, "early": false}
	var neutral := {"grade": "neutral", "positive": false, "reward": true, "severe": false, "early": false}
	var bad := {"grade": "bad", "positive": false, "reward": false, "severe": false, "early": false}
	var severe := {"grade": "bad", "positive": false, "reward": false, "severe": true, "early": false}
	var early := {"grade": "neutral", "positive": false, "reward": false, "severe": false, "early": true}
	check(ACT_FACE.face_for_afterglow(positive) == "affectionate", "positive afterglow")
	check(ACT_FACE.face_for_afterglow(neutral) == "relaxed", "neutral afterglow")
	check(ACT_FACE.face_for_afterglow(bad) == "sad", "bad afterglow")
	check(ACT_FACE.face_for_afterglow(early) == "", "early afterglow has no face")
	check(ACT_FACE.face_for_summary_hold(positive) == "relaxed", "positive held face")
	check(ACT_FACE.face_for_summary_hold(neutral) == "relaxed", "neutral held face")
	check(ACT_FACE.face_for_summary_hold(bad) == "sad", "bad held face")
	check(ACT_FACE.face_for_summary_hold(severe) == "annoyed", "severe held face")
	check(ACT_FACE.face_for_summary_hold(early) == "", "early held face is empty")
	var stopped_strict := {"stopped": true, "tolerance": "strict"}
	var stopped_normal := {"stopped": true, "tolerance": "normal"}
	check(ACT_FACE.face_for_summary_hold(stopped_strict) == "angry", "strict stop face")
	check(ACT_FACE.face_for_summary_hold(stopped_normal) == "annoyed", "normal stop face")
	check(ACT_FACE.face_for_summary_hold({}) == "", "empty summary has no face")

	var moments := ["cue", "climax", "end_early", "bystander", "ask", "invite",
		"tolerance_warning", "tolerance_stop", "history_refusal"]
	for moment: String in moments:
		var names := ACT_FACE.moment_faces(moment)
		check(not names.is_empty(), "%s has face hints" % moment)
		for face: String in names:
			check(ACT_FACE.valid_face(face), "%s suggests a valid face" % moment)
	var cue_note := ACT_FACE.prompt_note("cue", "overwhelmed")
	check(cue_note.contains("[face:"), "cue note names a face tag")
	check(cue_note.contains("feeling tag after your spoken words"),
		"cue note allows the base-game feeling tag after speech")
	check(ACT_FACE.prompt_note("unknown").is_empty(), "unknown moment has no note")

	# The held mood-face node: apply, yield to a line, return, and clear only its own face.
	var mood_pony := FakeMoodPony.new()
	var expressions := FakeExpressions.new()
	mood_pony.add_child(expressions)
	mood_pony.expressions = expressions
	root.add_child(mood_pony)
	var node: Node = MOOD_FACE.new()
	node.set("pony", mood_pony)
	node.set("face", "relaxed")
	node.set("mood", "")
	node.set("blush", 0.0)
	root.add_child(node)
	node.set_physics_process(false)
	check(expressions.dialogue_face == "relaxed", "mood face applies on start")
	check(expressions.set_calls >= 1, "mood face sets the face once")
	expressions.dialogue_face = "happy"
	node.call("_physics_process", 0.1)
	check(expressions.dialogue_face == "happy", "mood face yields to a spoken line")
	expressions.dialogue_face = ""
	node.call("_physics_process", 0.1)
	check(expressions.dialogue_face == "relaxed", "mood face returns after the line")
	node.call("_finish", "test")
	check(expressions.dialogue_face == "", "mood face clears only its own face")
	check(expressions.clear_calls == 1, "mood face clears once")

	var other_pony := FakeMoodPony.new()
	var other_expressions := FakeExpressions.new()
	other_pony.add_child(other_expressions)
	other_pony.expressions = other_expressions
	root.add_child(other_pony)
	var other_node: Node = MOOD_FACE.new()
	other_node.set("pony", other_pony)
	other_node.set("face", "relaxed")
	other_node.set("mood", "")
	other_node.set("blush", 0.0)
	root.add_child(other_node)
	other_node.set_physics_process(false)
	other_expressions.dialogue_face = "happy"
	other_node.call("_finish", "test")
	check(other_expressions.dialogue_face == "happy",
		"mood face never clears another owner's face")
	node.queue_free()
	other_node.queue_free()
	mood_pony.queue_free()
	other_pony.queue_free()

	if failures == 0:
		print("ACT_FACE_PASS")
	finish()
