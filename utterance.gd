extends RefCounted
## Pure prompt formatting for act lines. Admission and pacing belong to
## `utterance_scheduler.gd`; this file only turns values into prompt text.

## A demand cue asks Anon to change something. These get the longer repeat budget. The base
## fallback ("She wants you to keep going.") is a trend cue, not a demand, so it stays on the
## normal cue gap.
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


## Short private state line for the AI. No speed/depth units: the mood, the two preference axes
## and the last concrete input are what a partner would actually notice.
static func state_line(pose_id: String, mood: String, intensity: String, pattern: String,
		last_touch: String, last_talk: String, seconds: float, climaxes := 0) -> String:
	var motion := "unknown"
	if not intensity.is_empty() and not pattern.is_empty():
		motion = "%s %s" % [intensity, pattern]
	elif not intensity.is_empty():
		motion = intensity
	elif not pattern.is_empty():
		motion = pattern
	return "pose=%s, mood=%s, he is %s, last touch=%s, last talk=%s, climaxes=%d, %.0fs in" % [
		pose_id, mood, motion,
		last_touch if not last_touch.is_empty() else "none",
		last_talk if not last_talk.is_empty() else "none",
		climaxes, maxf(0.0, seconds),
	]
