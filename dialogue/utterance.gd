extends RefCounted
## Pure prompt formatting for act lines. Admission and pacing belong to
## `dialogue/utterance_scheduler.gd`; this file picks the line's values, `prompt_text` words them.

const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

## A demand cue asks Anon to change something and gets the longer repeat budget; the trend
## fallback stays on the normal cue gap.
const INTENSITY_ORDER := ["soft", "firm", "rough"]
const PATTERN_ORDER := ["teasing", "steady", "quick"]


static func is_demand(text: String) -> bool:
	return text.begins_with("She wants it") or text.begins_with("She wants a ") \
		or text.begins_with("She wants to be teased") or text.begins_with("She needs")


## A private line seed. The HUD cue is shorthand; this says what the moment means to her, in
## second person, so the line is not a status report or an order.
static func line_seed(facts: Dictionary) -> String:
	var key := ""
	match str(facts.get("mood", "")):
		"overwhelmed":
			key = "overwhelmed"
		"close":
			key = "close"
	if key.is_empty():
		var intensity := str(facts.get("intensity", ""))
		var wanted_intensity := str(facts.get("wanted_intensity", "firm"))
		if not intensity.is_empty() and intensity != wanted_intensity:
			if _intensity_rank(intensity) > _intensity_rank(wanted_intensity):
				key = "too_rough"
			else:
				key = "too_gentle"
		else:
			var pattern := str(facts.get("pattern", ""))
			var wanted_pattern := str(facts.get("wanted_pattern", "steady"))
			if not pattern.is_empty() and pattern != wanted_pattern:
				key = "too_fast" if _pattern_rank(pattern) > _pattern_rank(wanted_pattern) \
					else "too_slow"
			elif not intensity.is_empty() and not pattern.is_empty() \
					and intensity == wanted_intensity and pattern == wanted_pattern:
				key = "matched"
	if key.is_empty():
		var last_touch := str(facts.get("last_touch", ""))
		var touch_likes: Array = facts.get("touch_likes", []) if facts.get("touch_likes", []) is Array else []
		var touch_dislikes: Array = facts.get("touch_dislikes", []) if facts.get("touch_dislikes", []) is Array else []
		if not last_touch.is_empty() and last_touch in touch_likes:
			key = "touch_liked"
		elif not last_touch.is_empty() and last_touch in touch_dislikes:
			key = "touch_disliked"
	if key.is_empty():
		var last_talk := str(facts.get("last_talk", ""))
		var talk_likes: Array = facts.get("talk_likes", []) if facts.get("talk_likes", []) is Array else []
		if not last_talk.is_empty() and last_talk in talk_likes:
			key = "talk_liked"
	if key.is_empty():
		key = "quiet"
	var seeds: Dictionary = DEFAULTS_DATA.prompts_block("act.seed")
	return PROMPT_TEXT.render(str(seeds.get(key, "")), {})


## The two felt intensity lines choose by direction, so there is no middle "firmer" line.
static func _intensity_rank(value: String) -> int:
	var index := INTENSITY_ORDER.find(value)
	return index if index >= 0 else 1


## Tempo order: teasing is slowest, then steady, then quick.
static func _pattern_rank(value: String) -> int:
	var index := PATTERN_ORDER.find(value)
	return index if index >= 0 else 1


## Short private state line for the AI. No speed/depth units: the mood, the two preference axes
## and the last concrete input are what a partner would actually notice.
static func state_line(pose: String, mood: String, intensity: String, pattern: String,
		last_touch: String, last_talk: String, _seconds: float, climaxes := 0) -> String:
	var motion := "unknown"
	if not intensity.is_empty() and not pattern.is_empty():
		motion = "%s %s" % [intensity, pattern]
	elif not intensity.is_empty():
		motion = intensity
	elif not pattern.is_empty():
		motion = pattern
	var row: Dictionary = DEFAULTS_DATA.prompts_block("act.state_line")
	return PROMPT_TEXT.render(row, {
		"pose": pose, "mood": mood, "motion": motion,
		"last_touch": last_touch if not last_touch.is_empty() else "none",
		"last_talk": last_talk if not last_talk.is_empty() else "none",
		"climaxes": climaxes,
	})
