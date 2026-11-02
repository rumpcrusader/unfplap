extends RefCounted
## Pure utterance scheduling and prompt formatting. The runtime owns the director and the
## pending-line state; this file only decides where the points are and fills the template.

const START_FRACTION := 0.08
const END_FRACTION := 0.92
const MIN_GAP := 6.0
const MAX_LINES := 8


static func line_count(min_lines: int, max_lines: int, rng: RandomNumberGenerator = null) -> int:
	var low := clampi(mini(min_lines, max_lines), 0, MAX_LINES)
	var high := clampi(maxi(min_lines, max_lines), 0, MAX_LINES)
	if rng != null:
		return rng.randi_range(low, high)
	return randi_range(low, high)


## Satisfaction thresholds, sorted, within 8–92% of `climax_at`. A deterministic seed keeps tests
## repeatable; the runtime randomizes its own RNG per act.
static func schedule(climax_at: int, count: int, seed: int) -> Array[float]:
	var points: Array[float] = []
	if count <= 0 or climax_at <= 0:
		return points
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var start := float(climax_at) * START_FRACTION
	var end := float(climax_at) * END_FRACTION
	var span := maxf(0.01, end - start)
	var bin := span / float(count)
	var gap := minf(MIN_GAP, bin * 0.6)
	var previous := -INF
	for index in count:
		var base := start + bin * (float(index) + 0.5)
		var jittered := base + rng.randf_range(-bin * 0.15, bin * 0.15)
		var point := clampf(jittered, start, end)
		if previous > -INF:
			point = maxf(point, previous + gap)
		point = minf(point, end)
		points.append(point)
		previous = point
	return points


static func format(template: String, values: Dictionary) -> String:
	var regex := RegEx.new()
	regex.compile("\\{([a-z_]+)\\}")
	var out := template
	for found: RegExMatch in regex.search_all(template):
		var key := found.get_string(1)
		out = out.replace(found.get_string(0), str(values.get(key, "")))
	return out


static func state_line(pose_id: String, satisfaction: int, climax_at: int, depth: float,
		speed: float, zone: String, shape: String, seconds: float) -> String:
	var depth_word := "shallow"
	if depth >= 0.66:
		depth_word = "deep"
	elif depth >= 0.33:
		depth_word = "middle"
	var stroke := shape if not shape.is_empty() else "unknown"
	return "pose=%s, satisfaction=%d/%d, depth=%.2f (%s), speed=%.2f/s (%s), stroke=%s, %.0fs in" % [
		pose_id, satisfaction, climax_at, clampf(depth, 0.0, 1.0), depth_word,
		maxf(0.0, speed), zone, stroke, maxf(0.0, seconds),
	]
