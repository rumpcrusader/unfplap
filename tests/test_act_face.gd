extends SceneTree
## Pure act-face mapping: face beats, the live climax style, blush levels and prompt hints.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_face.gd

const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


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
	check(ACT_FACE.FACES.size() == 22, "22 expression faces")
	for face: String in ACT_FACE.FACES:
		check(ACT_FACE.valid_face(face), "valid face %s" % face)
	check(not ACT_FACE.valid_face("not_a_face"), "unknown face is rejected")

	check(ACT_FACE.MOOD_FACES.size() == 10, "all ten base moods are mapped")
	for mood: String in ACT_FACE.MOOD_FACES:
		var face := str(ACT_FACE.MOOD_FACES[mood])
		check(face.is_empty() or ACT_FACE.valid_face(face), "mood %s maps to a face" % mood)

	check(near(ACT_FACE.blush_for("posing_in", 0.0), 0.60), "posing-in blush")
	check(near(ACT_FACE.blush_for("active", 0.0), 0.55), "active blush at zero")
	check(near(ACT_FACE.blush_for("active", 100.0), 1.0), "active blush at full readiness")
	check(near(ACT_FACE.blush_for("climax", 0.0), 1.0), "climax blush")
	check(near(ACT_FACE.blush_for("afterglow", 0.0), 0.40), "afterglow blush")
	check(near(ACT_FACE.blush_for("active", 0.0, false), 1.0), "disabled arc is full blush")

	var perfect := ACT_FACE.climax_style(_quality())
	check(str(perfect.get("style", "")) == "ooo", "perfect physical act is round-mouthed")
	check(near(float(perfect.get("score", 0.0)), 0.675), "perfect physical score")

	var warm := ACT_FACE.climax_style(_quality({"liked_touch": 1}))
	check(str(warm.get("style", "")) == "fluster", "warm matched act is flustered")
	check(near(float(warm.get("score", 0.0)), 0.833), "warm matched score")

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
	check(near(float(climax_warm.get("fluster_s", 0.0)), 5.0), "warm climax flusters")
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
	check(cue_note.contains("never use [mood:"), "cue note forbids a mood tag")
	check(ACT_FACE.prompt_note("unknown").is_empty(), "unknown moment has no note")

	print("ACT_FACE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FACE_PASS")
	quit(0 if failures == 0 else 1)
