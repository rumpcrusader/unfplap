extends RefCounted
## Pure per-mare pump preferences: depth curves, speed windows, acceleration shapes and the
## private attitude note. No scene access, so the rules can be tested headlessly.
##
## Depth profiles are normalized to an integral of 1.0 over 0..1. A full 0->1->0 pump therefore
## stays exactly 2.0 base gain at every profile; the profile only redistributes where the gain is.

const DEPTH_PROFILES := ["steady", "deep", "shallow", "peak"]
const SHAPES := ["steady", "ease_in", "ease_out", "ease_in_out"]
const MIXED := "mixed"

const DEFAULTS := {
	"depth": "steady",
	"speed": {
		"enabled": true,
		"min": 0.001,
		"perfect": 0.80,
		"max": 1.60,
		"epsilon": 0.15,
		"slow_gain": 0.70,
		"fast_gain": 0.70,
		"perfect_gain": 1.30,
	},
	"shape": {
		"enabled": false,
		"likes": "",
		"dislikes": "",
		"like_gain": 1.20,
		"dislike_gain": 0.75,
		"min_travel": 0.30,
		"max_rmse": 0.18,
	},
	"notes": "",
	"phases": [],
}

const RAW_DEPTH := {
	"steady": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	"deep": [0.55, 0.65, 0.80, 1.00, 1.20, 1.40, 1.60, 1.80],
	"shallow": [1.80, 1.60, 1.40, 1.20, 1.00, 0.80, 0.65, 0.55],
	"peak": [0.60, 0.80, 1.10, 1.40, 1.50, 1.30, 1.00, 0.70],
}

## Comfort bands for the reactive depth lines. `steady` has no band.
const BANDS := {
	"deep": Vector2(0.60, 1.00),
	"shallow": Vector2(0.00, 0.40),
	"peak": Vector2(0.50, 0.85),
}

static var _depth_cache: Dictionary = {}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## Merge an arbitrary `preferences.pump` block with the defaults and validate it. Bad or unknown
## values fall back to the neutral default rather than failing an act.
static func resolve(raw: Variant) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if raw is Dictionary:
		out = _merge(out, raw)
	var depth := str(out.get("depth", "steady")).to_lower()
	if depth not in DEPTH_PROFILES:
		depth = "steady"
	out["depth"] = depth

	var speed_value: Variant = out.get("speed", {})
	var speed: Dictionary = speed_value if speed_value is Dictionary else {}
	speed["enabled"] = bool(speed.get("enabled", true))
	speed["min"] = maxf(0.0, float(speed.get("min", 0.001)))
	speed["perfect"] = maxf(0.0, float(speed.get("perfect", 0.80)))
	speed["max"] = maxf(float(speed.get("min", 0.001)), float(speed.get("max", 1.60)))
	speed["epsilon"] = maxf(0.0, float(speed.get("epsilon", 0.15)))
	speed["slow_gain"] = clampf(float(speed.get("slow_gain", 0.70)), 0.05, 4.0)
	speed["fast_gain"] = clampf(float(speed.get("fast_gain", 0.70)), 0.05, 4.0)
	speed["perfect_gain"] = clampf(float(speed.get("perfect_gain", 1.30)), 0.05, 4.0)
	out["speed"] = speed

	var shape_value: Variant = out.get("shape", {})
	var shape: Dictionary = shape_value if shape_value is Dictionary else {}
	shape["enabled"] = bool(shape.get("enabled", false))
	var likes := str(shape.get("likes", "")).to_lower()
	var dislikes := str(shape.get("dislikes", "")).to_lower()
	shape["likes"] = likes if likes in SHAPES else ""
	shape["dislikes"] = dislikes if dislikes in SHAPES else ""
	if str(shape["likes"]) == str(shape["dislikes"]):
		shape["dislikes"] = ""
	shape["like_gain"] = clampf(float(shape.get("like_gain", 1.20)), 0.05, 4.0)
	shape["dislike_gain"] = clampf(float(shape.get("dislike_gain", 0.75)), 0.05, 4.0)
	shape["min_travel"] = clampf(float(shape.get("min_travel", 0.30)), 0.0, 1.0)
	shape["max_rmse"] = clampf(float(shape.get("max_rmse", 0.18)), 0.01, 1.0)
	out["shape"] = shape
	out["notes"] = str(out.get("notes", "")).strip_edges()
	var phases_value: Variant = out.get("phases", [])
	var phases: Array = []
	if phases_value is Array:
		for entry: Variant in phases_value:
			if not entry is Dictionary:
				continue
			var phase: Dictionary = (entry as Dictionary).duplicate(true)
			phase["min_satisfaction"] = clampf(float(phase.get("min_satisfaction", 0.0)), 0.0, 1.0)
			phase["max_satisfaction"] = clampf(float(phase.get("max_satisfaction", 1.0)), 0.0, 1.0)
			if float(phase["min_satisfaction"]) >= float(phase["max_satisfaction"]):
				continue
			phases.append(phase)
	out["phases"] = phases
	return out


## Index of the last matching satisfaction phase, or -1. `progress` is satisfaction/climax_at.
static func phase_index(pref: Dictionary, progress: float) -> int:
	var phases: Variant = pref.get("phases", [])
	if not phases is Array:
		return -1
	var chosen := -1
	for index in (phases as Array).size():
		var phase: Variant = (phases as Array)[index]
		if not phase is Dictionary:
			continue
		var low := float((phase as Dictionary).get("min_satisfaction", 0.0))
		var high := float((phase as Dictionary).get("max_satisfaction", 1.0))
		if progress >= low and progress < high:
			chosen = index
	return chosen


## Merge the active satisfaction phase over the base preferences.
static func active(pref: Dictionary, progress: float) -> Dictionary:
	var base: Dictionary = pref.duplicate(true)
	var phases: Variant = base.get("phases", [])
	var chosen := phase_index(pref, progress)
	base.erase("phases")
	if chosen >= 0 and phases is Array:
		var phase: Variant = (phases as Array)[chosen]
		if phase is Dictionary:
			base = _merge(base, phase)
	return resolve(base)


## Piecewise-linear depth weight. Normalized so its integral over 0..1 is 1.0.
static func depth_weight(pref: Dictionary, depth: float) -> float:
	var values := _depth_array(str(pref.get("depth", "steady")))
	var n := values.size()
	if n == 0:
		return 1.0
	var x := clampf(depth, 0.0, 1.0) * float(n - 1)
	var index := mini(int(floor(x)), n - 1)
	if index >= n - 1:
		return float(values[n - 1])
	var t := x - float(index)
	return lerpf(float(values[index]), float(values[index + 1]), t)


## Comfort band for depth feedback, or (-1, -1) when there is no preference.
static func comfort_band(pref: Dictionary) -> Vector2:
	var key := str(pref.get("depth", "steady"))
	return BANDS.get(key, Vector2(-1.0, -1.0))


## "slow", "perfect", "ok" or "fast". Disabled speed preference is always "ok".
static func speed_zone(pref: Dictionary, speed: float) -> String:
	var cfg: Dictionary = pref.get("speed", {})
	if not bool(cfg.get("enabled", false)):
		return "ok"
	var value := maxf(0.0, speed)
	var perfect := float(cfg.get("perfect", 0.80))
	var epsilon := float(cfg.get("epsilon", 0.15))
	if absf(value - perfect) <= epsilon:
		return "perfect"
	if value < float(cfg.get("min", 0.35)):
		return "slow"
	if value > float(cfg.get("max", 1.60)):
		return "fast"
	return "ok"


static func speed_multiplier(pref: Dictionary, zone: String) -> float:
	var cfg: Dictionary = pref.get("speed", {})
	if not bool(cfg.get("enabled", false)):
		return 1.0
	match zone:
		"slow":
			return float(cfg.get("slow_gain", 0.70))
		"fast":
			return float(cfg.get("fast_gain", 0.70))
		"perfect":
			return float(cfg.get("perfect_gain", 1.30))
	return 1.0


static func shape_multiplier(pref: Dictionary, shape: String) -> float:
	var cfg: Dictionary = pref.get("shape", {})
	if not bool(cfg.get("enabled", false)):
		return 1.0
	if shape == str(cfg.get("likes", "")) and shape != "":
		return float(cfg.get("like_gain", 1.20))
	if shape == str(cfg.get("dislikes", "")) and shape != "":
		return float(cfg.get("dislike_gain", 0.75))
	return 1.0


## Combined speed and shape multiplier, capped so preferences cannot make an act absurdly short
## or long.
static func multiplier(pref: Dictionary, zone: String, shape: String) -> float:
	return clampf(speed_multiplier(pref, zone) * shape_multiplier(pref, shape), 0.40, 1.80)


## Classify an inward stroke's (time, depth) samples against the four shape templates.
## Returns shape = "mixed" when there are too few samples, too little travel, or no close match.
static func classify_shape(samples: PackedVector2Array, min_travel := 0.30, max_rmse := 0.18) -> Dictionary:
	var result := {"shape": MIXED, "rmse": INF, "travel": 0.0, "duration": 0.0}
	if samples.size() < 4:
		return result
	var first := samples[0]
	var last := samples[samples.size() - 1]
	var travel := absf(last.y - first.y)
	var duration := last.x - first.x
	result["travel"] = travel
	result["duration"] = duration
	if travel < min_travel or duration <= 0.001:
		return result
	var span := last.y - first.y
	var best := MIXED
	var best_rmse := INF
	for name: String in SHAPES:
		var error := 0.0
		for sample: Vector2 in samples:
			var t := clampf((sample.x - first.x) / duration, 0.0, 1.0)
			var d := clampf((sample.y - first.y) / span, 0.0, 1.0)
			var predicted := _shape_value(name, t)
			error += (d - predicted) * (d - predicted)
		var rmse := sqrt(error / float(samples.size()))
		if rmse < best_rmse:
			best_rmse = rmse
			best = name
	if best_rmse > max_rmse:
		best = MIXED
	result["shape"] = best
	result["rmse"] = best_rmse
	return result


## Human-readable private preference summary for the utterance prompt.
static func describe(pref: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("depth: %s" % str(pref.get("depth", "steady")))
	var speed: Dictionary = pref.get("speed", {})
	if bool(speed.get("enabled", false)):
		parts.append("speed: perfect around %.2f/s (band %.2f), slow below %.2f, too fast above %.2f" % [
			float(speed.get("perfect", 0.80)),
			float(speed.get("epsilon", 0.15)),
			float(speed.get("min", 0.35)),
			float(speed.get("max", 1.60)),
		])
	var shape: Dictionary = pref.get("shape", {})
	if bool(shape.get("enabled", false)):
		var likes := str(shape.get("likes", ""))
		var dislikes := str(shape.get("dislikes", ""))
		if not likes.is_empty():
			parts.append("likes the %s stroke" % likes)
		if not dislikes.is_empty():
			parts.append("dislikes the %s stroke" % dislikes)
	var notes := str(pref.get("notes", "")).strip_edges()
	if not notes.is_empty():
		parts.append("attitude: " + notes)
	return "\n".join(parts)


static func _shape_value(name: String, t: float) -> float:
	match name:
		"ease_in":
			return t * t
		"ease_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"ease_in_out":
			return t * t * (3.0 - 2.0 * t)
	return t


static func _depth_array(name: String) -> Array:
	if _depth_cache.has(name):
		return _depth_cache[name]
	var raw: Array = RAW_DEPTH.get(name, RAW_DEPTH["steady"])
	var values: Array = []
	for value: Variant in raw:
		values.append(float(value))
	var count := values.size()
	var area := 0.0
	if count > 1:
		var step := 1.0 / float(count - 1)
		for index in range(count - 1):
			area += (float(values[index]) + float(values[index + 1])) * 0.5 * step
	if area <= 0.0001:
		area = 1.0
	for index in count:
		values[index] = float(values[index]) / area
	_depth_cache[name] = values
	return values


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = _merge(out[key], value)
		else:
			out[key] = value
	return out
