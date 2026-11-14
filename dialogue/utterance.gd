extends RefCounted
## Pure prompt formatting for act lines. Admission and pacing belong to
## `dialogue/utterance_scheduler.gd`; this file only turns values into prompt text.

## A demand cue asks Anon to change something. These get the longer repeat budget. The base
## fallback ("She wants you to keep going.") is a trend cue, not a demand, so it stays on the
## normal cue gap.
const INTENSITY_ORDER := ["soft", "firm", "rough"]
const PATTERN_ORDER := ["teasing", "steady", "quick"]


static func is_demand(text: String) -> bool:
	return text.begins_with("She wants it") or text.begins_with("She wants a ") \
		or text.begins_with("She wants to be teased") or text.begins_with("She needs")


static func format(template: String, values: Dictionary) -> String:
	var regex := RegEx.new()
	regex.compile("\\{([a-z_]+)\\}")
	var out := ""
	var cursor := 0
	for found: RegExMatch in regex.search_all(template):
		out += template.substr(cursor, found.get_start() - cursor)
		out += str(values.get(found.get_string(1), ""))
		cursor = found.get_end()
	out += template.substr(cursor)
	return out


## Context that must not depend on the shape of a saved prompt. Append only the blocks the
## template did not reference; formatted values are already private text.
static func context_note(template: String, blocks: Dictionary) -> String:
	var parts: PackedStringArray = []
	var private_context := false
	for key: String in ["state", "relationship", "tone", "memory"]:
		var text := str(blocks.get(key, "")).strip_edges()
		if key in ["relationship", "tone", "memory"] and not text.is_empty():
			private_context = true
		if template.contains("{" + key + "}"):
			continue
		if text.is_empty():
			continue
		match key:
			"state":
				parts.append("Current moment: " + text + ".")
			"relationship":
				parts.append("Private relationship note: " + text)
			"tone":
				parts.append("Tone: " + text)
			"memory":
				parts.append(text)
	if private_context and not template.contains("Do not mention relationship labels"):
		parts.append("Do not mention these labels, levels or numbers, or that you are following a note. Do not invent a memory beyond the one given.")
	return "" if parts.is_empty() else "\n" + "\n".join(parts)


## A private line seed. The HUD cue is shorthand; this says what the moment means to her, in
## second person, so the line is not a status report or an order.
static func line_seed(facts: Dictionary) -> String:
	var need := ""
	match str(facts.get("mood", "")):
		"overwhelmed":
			need = "That was too much; you need a breath before more."
		"close":
			need = "You are close, and it is hard to think about anything else."
	if need.is_empty():
		var intensity := str(facts.get("intensity", ""))
		var wanted_intensity := str(facts.get("wanted_intensity", "firm"))
		if not intensity.is_empty() and intensity != wanted_intensity:
			if _intensity_rank(intensity) > _intensity_rank(wanted_intensity):
				need = "He is being too rough with you, and it hurts."
			else:
				need = "He is being too gentle with you, and you barely feel anything."
		else:
			var pattern := str(facts.get("pattern", ""))
			var wanted_pattern := str(facts.get("wanted_pattern", "steady"))
			if not pattern.is_empty() and pattern != wanted_pattern:
				if _pattern_rank(pattern) > _pattern_rank(wanted_pattern):
					need = "He is going too fast for you to enjoy the build; you want him to slow " \
						+ "down and tease."
				else:
					need = "He is taking his time, and you want it faster."
			elif not intensity.is_empty() and not pattern.is_empty() \
					and intensity == wanted_intensity and pattern == wanted_pattern:
				need = "This is what you wanted; let yourself feel it."
	if need.is_empty():
		var last_touch := str(facts.get("last_touch", ""))
		var touch_likes: Array = facts.get("touch_likes", []) if facts.get("touch_likes", []) is Array else []
		var touch_dislikes: Array = facts.get("touch_dislikes", []) if facts.get("touch_dislikes", []) is Array else []
		if not last_touch.is_empty() and last_touch in touch_likes:
			need = "You liked his touch."
		elif not last_touch.is_empty() and last_touch in touch_dislikes:
			need = "That did not sit right."
	if need.is_empty():
		var last_talk := str(facts.get("last_talk", ""))
		var talk_likes: Array = facts.get("talk_likes", []) if facts.get("talk_likes", []) is Array else []
		if not last_talk.is_empty() and last_talk in talk_likes:
			need = "What he said landed."
	if need.is_empty():
		need = "You are here with him; nothing needs fixing."
	return need + " This is private; let it colour one short line, or let it pass unsaid."


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
static func state_line(pose_id: String, mood: String, intensity: String, pattern: String,
		last_touch: String, last_talk: String, _seconds: float, climaxes := 0) -> String:
	var motion := "unknown"
	if not intensity.is_empty() and not pattern.is_empty():
		motion = "%s %s" % [intensity, pattern]
	elif not intensity.is_empty():
		motion = intensity
	elif not pattern.is_empty():
		motion = pattern
	return "pose=%s, mood=%s, he is %s, last touch=%s, last talk=%s, climaxes=%d" % [
		pose_id, mood, motion,
		last_touch if not last_touch.is_empty() else "none",
		last_talk if not last_talk.is_empty() else "none",
		climaxes,
	]
