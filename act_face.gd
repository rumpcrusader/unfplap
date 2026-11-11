extends RefCounted
## Pure act expression mapping: face beats, the live climax style, blush levels and prompt hints.
## No scene access. Every face name is checked against the base game's expression table.

const FACE_POSES := preload("res://world/characters/hybrid_mare/face_poses.gd")
const TAGS := preload("res://world/ai/pony_dialogue_tags.gd")

const FACES := TAGS.NAMES

const MOOD_FACES := {
	"neutral": "",
	"happy": "happy",
	"amused": "amused",
	"relaxed": "relaxed",
	"shy": "shy",
	"sad": "sad",
	"annoyed": "annoyed",
	"angry": "angry",
	"surprised": "surprised",
	"confused": "confused",
}

## Auto climax style: a warm, well-matched act is flustered; a good physical act is open-mouthed;
## a poor, mismatched or distressed act keeps the wide-eyed stare.
const FLUSTER_MIN := 0.70
const OOO_MIN := 0.40

const START_HOLD_S := 2.5
const CLOSE_HOLD_S := 3.0
const CLIMAX_HOLD_S := 5.0
const AFTERGLOW_HOLD_S := 3.0
const WARNING_HOLD_S := 3.0
const OVERWHELMED_HOLD_S := 2.5


static func valid_face(face: String) -> bool:
	return FACE_POSES.LINE_FACES.has(face)


static func mood_face(mood: String) -> String:
	return str(MOOD_FACES.get(mood, ""))


## Act blush level. `enabled` false keeps the old full blush for the whole act.
static func blush_for(phase: String, readiness: float, enabled := true) -> float:
	if not enabled:
		return 1.0
	match phase:
		"posing_in":
			return 0.60
		"climax":
			return 1.0
		"afterglow":
			return 0.40
		"active":
			return clampf(0.55 + 0.45 * clampf(readiness, 0.0, 100.0) / 100.0, 0.0, 1.0)
	return 1.0


## Live quality for the auto climax face. Presentation only; the act summary owns history.
## `inputs` keys: intensity_total/right, pattern_total/right, both_matches, liked_touch,
## liked_talk, dislikes_total, distress, seeks_touch, seeks_talk, overwhelmed.
static func climax_style(inputs: Dictionary) -> Dictionary:
	var intensity_total := int(inputs.get("intensity_total", 0))
	var intensity_right := int(inputs.get("intensity_right", 0))
	var pattern_total := int(inputs.get("pattern_total", 0))
	var pattern_right := int(inputs.get("pattern_right", 0))
	var both_matches := int(inputs.get("both_matches", 0))
	var liked_touch := int(inputs.get("liked_touch", 0))
	var liked_talk := int(inputs.get("liked_talk", 0))
	var dislikes := int(inputs.get("dislikes_total", 0))
	var distress := float(inputs.get("distress", 0.0))

	var motion := 0.5
	if intensity_total > 0:
		motion = clampf(float(intensity_right) / float(intensity_total), 0.0, 1.0)
	if pattern_total > 0:
		motion = (motion + clampf(float(pattern_right) / float(pattern_total), 0.0, 1.0)) * 0.5
	var both := clampf(float(both_matches) / float(maxi(3, intensity_total)), 0.0, 1.0)
	var affection := clampf(float(liked_touch + liked_talk) / 3.0, 0.0, 1.0)
	var engagement := clampf(0.5 * float(mini(intensity_total, 6)) / 6.0
		+ (0.5 if liked_touch + liked_talk > 0 else 0.0), 0.0, 1.0)
	var penalty := float(dislikes) * 0.20 + distress * 0.05
	if bool(inputs.get("seeks_touch", false)) and liked_touch <= 0:
		penalty += 0.10
	if bool(inputs.get("seeks_talk", false)) and liked_talk <= 0:
		penalty += 0.10
	if bool(inputs.get("overwhelmed", false)):
		penalty += 0.20
	penalty = clampf(penalty, 0.0, 0.8)
	var score := clampf(0.35 * motion + 0.25 * both + 0.25 * affection
		+ 0.15 * engagement - penalty, 0.0, 1.0)
	var style := "wide"
	if score >= FLUSTER_MIN:
		style = "fluster"
	elif score >= OOO_MIN:
		style = "ooo"
	return {
		"style": style,
		"score": score,
		"motion": motion,
		"both": both,
		"affection": affection,
		"engagement": engagement,
		"penalty": penalty,
	}


## Forced debug modes win; "auto" or an unknown value uses the live score.
static func climax_style_for_mode(mode: String, inputs: Dictionary) -> Dictionary:
	var wanted := mode.to_lower()
	var result := climax_style(inputs)
	if wanted in ["fluster", "ooo", "wide"]:
		result["style"] = wanted
		result["forced"] = true
	else:
		result["forced"] = false
	return result


## One face beat. An empty plan means no act face for this moment.
static func plan_for(moment: String, ctx := {}) -> Dictionary:
	match moment:
		"start":
			var first := bool(ctx.get("first_time", false))
			return _plan("shy" if first else "relaxed", START_HOLD_S)
		"close":
			return _plan("anticipation", CLOSE_HOLD_S)
		"climax":
			var mode := str(ctx.get("mode", "auto"))
			var quality: Dictionary = {}
			var value: Variant = ctx.get("quality", {})
			if value is Dictionary:
				quality = value as Dictionary
			var style := climax_style_for_mode(mode, quality)
			var face := ""
			var fluster := 0.0
			var release := false
			match str(style.get("style", "wide")):
				"fluster":
					face = "shy"
					fluster = CLIMAX_HOLD_S
					release = true
				"ooo":
					face = "ooo"
			var out := _plan(face, CLIMAX_HOLD_S if not face.is_empty() else 0.0)
			out["fluster_s"] = fluster
			out["release_stare"] = release
			out["style"] = str(style.get("style", "wide"))
			out["score"] = float(style.get("score", 0.0))
			out["style_debug"] = style
			return out
		"afterglow":
			var summary: Dictionary = {}
			var summary_value: Variant = ctx.get("summary", {})
			if summary_value is Dictionary:
				summary = summary_value as Dictionary
			return _plan(face_for_afterglow(summary), AFTERGLOW_HOLD_S)
		"warning":
			return _plan(_displeasure_face(str(ctx.get("tolerance", "normal"))), WARNING_HOLD_S)
		"overwhelmed":
			return _plan(_displeasure_face(str(ctx.get("tolerance", "normal"))),
				OVERWHELMED_HOLD_S)
	return {}


static func _plan(face: String, hold_s: float) -> Dictionary:
	var known := valid_face(face)
	return {
		"face": face if known else "",
		"hold_s": hold_s if known else 0.0,
		"fluster_s": 0.0,
		"release_stare": false,
		"style": "",
		"score": 0.0,
		"style_debug": {},
	}


static func _displeasure_face(tolerance: String) -> String:
	return "sad" if tolerance == "forgiving" else "annoyed"


## The held face after an act. Positive and non-early neutral acts keep a light, relaxed face;
## bad acts show their summary mood. A short affectionate beat rides on the afterglow itself.
static func face_for_summary_hold(summary: Dictionary) -> String:
	if summary.is_empty():
		return ""
	if bool(summary.get("stopped", false)):
		return "angry" if str(summary.get("tolerance", "normal")) == "strict" else "annoyed"
	var severe := bool(summary.get("severe", false))
	var early := bool(summary.get("early", false))
	var grade := str(summary.get("grade", "neutral"))
	if severe:
		return "annoyed"
	if grade == "bad":
		return "sad"
	if early:
		return ""
	if bool(summary.get("reward", false)):
		return "relaxed"
	return ""


static func face_for_afterglow(summary: Dictionary) -> String:
	if summary.is_empty() or bool(summary.get("stopped", false)) \
			or bool(summary.get("early", false)):
		return ""
	if bool(summary.get("severe", false)):
		return "annoyed"
	var grade := str(summary.get("grade", "neutral"))
	if grade == "bad":
		return "sad"
	if bool(summary.get("reward", false)):
		return "affectionate" if bool(summary.get("positive", false)) else "relaxed"
	return ""


static func moment_faces(moment: String, mood := "") -> Array:
	match moment:
		"cue":
			match mood:
				"overwhelmed":
					return ["sad", "annoyed", "shy"]
				"close":
					return ["affectionate", "anticipation", "shy"]
			return ["relaxed", "shy", "affectionate", "amused", "happy", "ooo", "anticipation"]
		"climax":
			return ["shy", "delighted", "affectionate", "ooo"]
		"end_early":
			return ["sad", "annoyed", "relaxed"]
		"bystander":
			return ["amused", "surprised", "confused", "shy"]
		"ask":
			return ["shy", "anticipation", "affectionate", "amused"]
		"invite":
			return ["affectionate", "anticipation", "shy"]
		"tolerance_warning":
			return ["annoyed", "sad"]
		"tolerance_stop":
			return ["angry", "annoyed"]
		"history_refusal":
			return ["sad", "annoyed", "relaxed"]
	return []


## Short private prompt hint. Voice emotions stay in the prompt/fallback: they are a separate
## vocabulary from face names.
static func prompt_note(moment: String, mood := "") -> String:
	var names := moment_faces(moment, mood)
	if names.is_empty():
		return ""
	var tags: PackedStringArray = []
	for name: String in names:
		tags.append("[face:%s]" % name)
	return " Face: you may start the line with one of %s if it fits; never use [mood:...] in an act line." % ", ".join(tags)


## One-shot face for debug previews and witness reactions. A spoken line owns the face.
static func react(pony: Variant, face: String, seconds := 3.0) -> bool:
	if not valid_face(face) or not pony is Object or not is_instance_valid(pony):
		return false
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions) or not expressions.has_method("set_dialogue"):
		return false
	var current := ""
	var value: Variant = expressions.get("dialogue_face")
	if value is String:
		current = value
	if not current.is_empty() and current != face:
		return false
	expressions.call("set_dialogue", face)
	if seconds > 0.0 and expressions.has_method("finish_dialogue"):
		expressions.call("finish_dialogue", seconds)
	return true
