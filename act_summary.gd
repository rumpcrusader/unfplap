extends RefCounted
## Pure per-act outcome scoring. No scene access.
##
## The score is the weighted fraction of the actions that apply to one act and went right:
## a climax, talk for a talk-seeker, touch, matching motion, and not ending early. Scored
## disliked touch/talk, repeated disliked handling and silence subtract. A good act is at
## least 0.80; a bad act is at most 0.20. The middle is neutral and changes no history.
##
## `evaluate` is pure. `rules` reads the debug tunables, and the caller may override them.

const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")

const DEFAULT_RULES := {
	"good_min": 0.80,
	"bad_max": 0.20,
	"w_climax": 0.30,
	"w_talk": 0.20,
	"w_touch": 0.20,
	"w_motion": 0.15,
	"w_not_early": 0.15,
	"p_dislike": 0.10,
	"p_severe": 0.15,
	"p_silence": 0.15,
	"p_miss": 0.10,
	"early_grace_s": 20.0,
	"min_thrusts": 2,
}


## Reason sentences for the private note: [profile-safe world event, private thought]. The event
## text must read correctly after the profile's "You and Anon " -> "You and <name>" rewrite, so it
## uses no second-person pronouns; the thought is her own voice (He/I).
## Short private beats for afterglow. The HUD and the impression keep the full summary; these
## only give the model a mood, never a review or a request list. 40% of rolls return nothing.
const AFTERGLOW_BEATS := {
	"great": ["You are warm and quiet.", "You feel close to him.",
		"You are sleepy and comfortable.", "You are a little pleased with yourself."],
	"good": ["You are warm and quiet.", "You feel close to him.",
		"You are sleepy and comfortable.", "You are a little pleased with yourself."],
	"neutral": ["You are still catching your breath.", "You are quiet, not sure what to say.",
		"You are comfortable but thoughtful."],
	"bad": ["You are quiet and a little raw.", "You need a moment before you talk.",
		"You are hurt but not ready to explain."],
}

const REASON_LINES := {
	"no_climax": ["She did not get there.", "I did not get there."],
	"silent_talk": ["Anon did not speak when she needed to hear him.",
		"He did not speak to me when I needed to hear him."],
	"talk_miss": ["Anon did not say the kind of thing she needs to hear.",
		"He did not say the kind of thing I need to hear."],
	"no_liked_touch": ["Anon did not touch the way she likes.",
		"He did not touch me the way I like."],
	"intensity_mismatch": ["Anon did not use the pressure she wanted.",
		"He did not use the pressure I wanted."],
	"pattern_mismatch": ["Anon did not keep the rhythm she wanted.",
		"He did not keep the rhythm I wanted."],
	"too_many_dislikes": ["Anon kept doing things she does not like.",
		"He kept doing things I do not like."],
}


## The live debug rules. Missing schema paths fall back to the module defaults.
static func rules() -> Dictionary:
	var out := DEFAULT_RULES.duplicate(true)
	for key: String in DEFAULT_RULES:
		var path := "history." + key
		if SCHEMA.has(path):
			out[key] = TUNABLES.get_float(path)
	return out


## Score one act. The snapshot keys are produced by runtime._summary_snapshot():
##   preferences, seconds, thrusts, pony_climaxes, talk_liked, talk_dislikes,
##   touches_liked, touch_dislikes, player_lines, intensity_total, intensity_right,
##   pattern_total, pattern_right, ended_early, forced.
static func evaluate(snapshot: Dictionary, rule_set := {}) -> Dictionary:
	var rules: Dictionary = DEFAULT_RULES.duplicate(true)
	for key: Variant in rule_set:
		rules[key] = rule_set[key]
	if bool(snapshot.get("forced", false)):
		return _skipped("forced")
	var preferences: Dictionary = {}
	var preference_value: Variant = snapshot.get("preferences", {})
	if preference_value is Dictionary:
		preferences = preference_value
	if bool(snapshot.get("stopped_by_her", false)):
		return _stopped(preferences, snapshot)
	var seconds := float(snapshot.get("seconds", 0.0))
	var thrusts := int(snapshot.get("thrusts", 0))
	if seconds < float(rules.get("early_grace_s", 20.0)) \
			and thrusts < int(rules.get("min_thrusts", 2)):
		return _skipped("short_act")

	var seeks_talk := PREFERENCES.seeks_talk(preferences)
	var seeks_touch := PREFERENCES.seeks_touch(preferences)
	var has_touch_likes := not (preferences.get("touch", []) as Array).is_empty()
	var pony_climaxes := int(snapshot.get("pony_climaxes", 0))
	var ended_early := bool(snapshot.get("ended_early", false))
	var talk_liked := int(snapshot.get("talk_liked", 0))
	var talk_dislikes := int(snapshot.get("talk_dislikes", 0))
	var touches_liked := int(snapshot.get("touches_liked", 0))
	var touch_dislikes: Dictionary = {}
	var touch_value: Variant = snapshot.get("touch_dislikes", {})
	if touch_value is Dictionary:
		touch_dislikes = touch_value
	var touch_dislikes_total := 0
	for count: Variant in touch_dislikes.values():
		touch_dislikes_total += int(count)
	var dislikes_total := touch_dislikes_total + talk_dislikes
	var player_lines := int(snapshot.get("player_lines", 0))
	var intensity_total := int(snapshot.get("intensity_total", 0))
	var intensity_right := int(snapshot.get("intensity_right", 0))
	var pattern_total := int(snapshot.get("pattern_total", 0))
	var pattern_right := int(snapshot.get("pattern_right", 0))
	var motion_known := pattern_total > 0
	var intensity_ok := intensity_total > 0 and intensity_right * 2 >= intensity_total
	var pattern_ok := pattern_total > 0 and pattern_right * 2 >= pattern_total

	var climax_ok := pony_climaxes > 0
	var talk_ok := talk_liked > 0 and talk_dislikes == 0
	var touch_ok := touch_dislikes_total == 0 and (not has_touch_likes or touches_liked > 0)
	var motion_ok := intensity_ok and pattern_ok
	var early_ok := not ended_early

	var weighted: Array = [
		{"key": "climax", "ok": climax_ok, "weight": float(rules.get("w_climax", 0.30))},
		{"key": "not_early", "ok": early_ok, "weight": float(rules.get("w_not_early", 0.15))},
	]
	if seeks_talk:
		weighted.append({"key": "talk", "ok": talk_ok,
			"weight": float(rules.get("w_talk", 0.20))})
	if seeks_touch:
		weighted.append({"key": "touch", "ok": touch_ok,
			"weight": float(rules.get("w_touch", 0.20))})
	if motion_known:
		weighted.append({"key": "motion", "ok": motion_ok,
			"weight": float(rules.get("w_motion", 0.15))})

	var applicable := 0.0
	var passed := 0.0
	var checks: Dictionary = {}
	var right := 0
	var total := 0
	for row: Variant in weighted:
		var item: Dictionary = row
		var weight := float(item.get("weight", 0.0))
		if weight <= 0.0:
			continue
		applicable += weight
		total += 1
		var ok := bool(item.get("ok", false))
		checks[str(item.get("key", ""))] = ok
		if ok:
			passed += weight
			right += 1

	var severe := false
	for count: Variant in touch_dislikes.values():
		if int(count) >= 2:
			severe = true
	if dislikes_total >= 3:
		severe = true
	var silent := seeks_talk and player_lines == 0
	var penalties := minf(dislikes_total * float(rules.get("p_dislike", 0.10)), 0.20)
	if severe:
		penalties += float(rules.get("p_severe", 0.15))
	if silent:
		penalties += float(rules.get("p_silence", 0.15))
	# A touch preference that was never met, or motion that did not match, is a real miss.
	# It is not enough to make the act bad by itself, but it keeps it out of the good band.
	if seeks_touch and has_touch_likes and touches_liked <= 0 and touch_dislikes_total == 0 \
			and not ended_early:
		penalties += float(rules.get("p_miss", 0.10))
	if motion_known and not motion_ok:
		penalties += float(rules.get("p_miss", 0.10))
	var quality := clampf((passed - penalties) / maxf(applicable, 0.01), 0.0, 1.0)

	var grade := "neutral"
	if quality >= float(rules.get("good_min", 0.80)):
		grade = "good"
	elif quality <= float(rules.get("bad_max", 0.20)):
		grade = "bad"
	var great := grade == "good" and pony_climaxes >= 2 and dislikes_total == 0 \
		and not silent and not ended_early
	if great:
		grade = "great"

	var reasons: Array[String] = []
	if ended_early:
		reasons.append("ended_early")
	elif pony_climaxes <= 0:
		reasons.append("no_climax")
	if seeks_talk and not talk_ok:
		reasons.append("silent_talk" if player_lines == 0 else "talk_miss")
	for kind: Variant in touch_dislikes:
		var count := int(touch_dislikes[kind])
		if count <= 0:
			continue
		reasons.append("disliked_" + str(kind))
		if count >= 2:
			reasons.append("severe_" + str(kind))
	if dislikes_total >= 3:
		reasons.append("too_many_dislikes")
	if has_touch_likes and touches_liked <= 0 and not ended_early:
		reasons.append("no_liked_touch")
	if motion_known and not intensity_ok:
		reasons.append("intensity_mismatch")
	if motion_known and not pattern_ok:
		reasons.append("pattern_mismatch")

	var romance := 0
	if grade == "bad":
		romance = -1
	elif grade == "good" or grade == "great":
		romance = 2
	elif not ended_early:
		romance = 1
	var mood := "relaxed"
	if grade == "bad":
		mood = "annoyed" if severe else "sad"
	elif grade == "good" or grade == "great":
		mood = "happy"
	var wants := _wants(preferences, reasons)
	var text := _text(grade, ended_early, reasons)
	var thought := _thought(grade, ended_early, reasons)
	return {
		"skip": false,
		"quality": quality,
		"grade": grade,
		"positive": grade == "good" or grade == "great",
		"reward": grade == "good" or grade == "great" or (grade == "neutral" and not ended_early),
		"romance": romance,
		"mood": mood,
		"severe": severe,
		"early": ended_early,
		"stopped": false,
		"reasons": reasons,
		"checks": checks,
		"right": right,
		"total": total,
		"text": text,
		"thought": thought,
		"wants": wants,
		"hud": _hud(grade, severe),
	}


## One short private afterglow beat, or "" when the roll asks for silence. The summary stays in
## the HUD and the impression; this is never a review.
static func afterglow_beat(summary: Dictionary, roll: float) -> String:
	if summary.is_empty() or roll < 0.4:
		return ""
	var grade := str(summary.get("grade", "neutral"))
	var pool: Variant = AFTERGLOW_BEATS.get(grade, AFTERGLOW_BEATS["neutral"])
	if not pool is Array or (pool as Array).is_empty():
		return ""
	var beats: Array = pool
	var pick := int(((clampf(roll, 0.4, 0.9999) - 0.4) / 0.6) * float(beats.size()))
	return str(beats[clampi(pick, 0, beats.size() - 1)])


## The early-end reaction asks for a moment, not a summary or a next-time list.
static func early_end_prompt(summary: Dictionary) -> String:
	if bool(summary.get("severe", false)):
		return "Anon stopped early and you are hurt. Say one short, quiet sentence. Do not explain or negotiate. Saying nothing is fine."
	return "Anon stopped before the act finished. Say one short sentence about how you feel right now, in your own voice. Do not review the act, do not list what you want next time, and do not lecture. One sentence, at most 10 words. Saying nothing is fine."


static func _skipped(reason: String) -> Dictionary:
	return {
		"skip": true,
		"quality": 0.0,
		"grade": "neutral",
		"positive": false,
		"reward": false,
		"romance": 0,
		"mood": "neutral",
		"severe": false,
		"early": false,
		"stopped": false,
		"reasons": [reason],
		"checks": {},
		"right": 0,
		"total": 0,
		"text": "",
		"thought": "",
		"wants": "",
		"hud": "",
	}


## A stop is always a severe bad act, even if the surrounding action checklist would be clean.
static func _stopped(preferences: Dictionary, snapshot: Dictionary) -> Dictionary:
	var reasons: Array[String] = ["stopped_by_her"]
	var touch_dislikes: Dictionary = {}
	var touch_value: Variant = snapshot.get("touch_dislikes", {})
	if touch_value is Dictionary:
		touch_dislikes = touch_value
	for kind: Variant in touch_dislikes:
		var count := int(touch_dislikes[kind])
		if count <= 0:
			continue
		reasons.append("disliked_" + str(kind))
		if count >= 2:
			reasons.append("severe_" + str(kind))
	if int(snapshot.get("talk_dislikes", 0)) > 0:
		reasons.append("talk_miss")
	var wants := _wants(preferences, reasons)
	var tolerance := str(snapshot.get("tolerance", "normal"))
	var mood := "angry" if tolerance == "strict" else "annoyed"
	return {
		"skip": false,
		"quality": 0.0,
		"grade": "bad",
		"positive": false,
		"reward": false,
		"romance": -1,
		"mood": mood,
		"severe": true,
		"early": false,
		"stopped": true,
		"stopped_by_her": true,
		"tolerance": tolerance,
		"reasons": reasons,
		"checks": {},
		"right": 0,
		"total": 0,
		"text": "Anon kept doing something she does not like, so the act stopped.",
		"thought": "He kept doing something I do not like; I stopped him.",
		"wants": wants,
		"hud": "",
	}


static func _hud(grade: String, severe: bool) -> String:
	match grade:
		"great":
			return "Great · she felt adored"
		"good":
			return "Good · she felt wanted"
		"bad":
			return "Bad · she felt used and hurt" if severe else "Bad · she felt used"
		_:
			return "Neutral · she wanted more"


static func _text(grade: String, ended_early: bool, reasons: Array[String]) -> String:
	var text := "You and Anon were together. It was nice, but something was missing."
	if ended_early:
		text = "Anon stopped before the act finished, and she was left wanting."
	elif grade == "bad":
		text = "You and Anon had sex, but it did not give what was needed, and she felt used."
	elif grade == "great":
		text = "You and Anon made love more than once, and she was ecstatic about it."
	elif grade == "good":
		text = "You and Anon made love, and she loved every moment."
	var reason := _reason_sentence(reasons, false)
	if not reason.is_empty():
		text += " " + reason
	return text


static func _thought(grade: String, ended_early: bool, reasons: Array[String]) -> String:
	var thought := "It was nice, but I wanted more."
	if ended_early:
		thought = "He stopped before I finished; I was left wanting."
	elif grade == "bad":
		thought = "He did not give me what I need; I felt used."
	elif grade == "great":
		thought = "He gave me everything I needed; I felt adored."
	elif grade == "good":
		thought = "He gave me what I needed; I felt wanted."
	var reason := _reason_sentence(reasons, true)
	if not reason.is_empty():
		thought += " " + reason
	return thought.left(240)


static func _reason_sentence(reasons: Array[String], first_person: bool) -> String:
	var parts: PackedStringArray = []
	for reason: String in reasons:
		# The opening sentence already states an early end; repeating it here was the bug.
		if reason == "ended_early":
			continue
		var pair: Variant = REASON_LINES.get(reason)
		if pair is Array:
			parts.append(str((pair as Array)[1 if first_person else 0]))
		elif reason.begins_with("severe_") or reason.begins_with("disliked_"):
			parts.append("He kept doing things I do not like." if first_person
				else "Anon kept doing things she does not like.")
	if parts.is_empty():
		return ""
	# Keep the note short and non-repetitive; one or two facts is enough.
	var unique: PackedStringArray = []
	for part: String in parts:
		if not part in unique:
			unique.append(part)
	return " ".join(unique.slice(0, 2))


static func _wants(preferences: Dictionary, reasons: Array[String]) -> String:
	var wants: PackedStringArray = []
	if "silent_talk" in reasons or "talk_miss" in reasons:
		wants.append("talk to me while we move")
	if "severe_smack" in reasons or "disliked_smack" in reasons:
		wants.append("be gentle with me")
	if "no_liked_touch" in reasons:
		wants.append("touch me the way I like")
	if "intensity_mismatch" in reasons:
		var intensity := str(preferences.get("intensity", "firm"))
		match intensity:
			"soft":
				wants.append("take me softer")
			"rough":
				wants.append("take me harder")
			_:
				wants.append("take me firmer")
	if "pattern_mismatch" in reasons:
		var pattern := str(preferences.get("pattern", "steady"))
		match pattern:
			"teasing":
				wants.append("tease me more")
			"quick":
				wants.append("keep it quicker")
			_:
				wants.append("keep a steadier rhythm")
	if "ended_early" in reasons:
		wants.append("let me finish")
	if wants.is_empty():
		return "keep doing what you did"
	return " and ".join(wants.slice(0, 2))
