extends RefCounted
## Pure prompt formatting for the runtime. Scheduling now belongs to readiness cues and
## touch/talk events, not to a satisfaction-threshold timeline.

static func format(template: String, values: Dictionary) -> String:
	var regex := RegEx.new()
	regex.compile("\\{([a-z_]+)\\}")
	var out := template
	for found: RegExMatch in regex.search_all(template):
		var key := found.get_string(1)
		out = out.replace(found.get_string(0), str(values.get(key, "")))
	return out


## Short private state line for the AI. No speed/depth units: the mood, the two taste axes
## and the last concrete input are what a partner would actually notice.
static func state_line(pose_id: String, mood: String, intensity: String, pattern: String,
		last_touch: String, last_talk: String, seconds: float) -> String:
	var motion := "unknown"
	if not intensity.is_empty() and not pattern.is_empty():
		motion = "%s %s" % [intensity, pattern]
	elif not intensity.is_empty():
		motion = intensity
	elif not pattern.is_empty():
		motion = pattern
	return "pose=%s, mood=%s, he is %s, last touch=%s, last talk=%s, %.0fs in" % [
		pose_id, mood, motion,
		last_touch if not last_touch.is_empty() else "none",
		last_talk if not last_talk.is_empty() else "none",
		maxf(0.0, seconds),
	]
