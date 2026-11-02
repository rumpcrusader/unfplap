extends SceneTree
## Pure pump-preference tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_preferences.gd

const PREF := preload("res://mods/unfplap/preferences.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	var neutral := PREF.resolve({})
	check(str(neutral.get("depth", "")) == "steady", "default depth steady")
	check(bool((neutral["speed"] as Dictionary).get("enabled", false)), "default speed enabled")
	check(near(float((neutral["speed"] as Dictionary).get("min", 0.0)), 0.001), "default min speed 0.001")
	check(not bool((neutral["shape"] as Dictionary).get("enabled", true)), "default shape disabled")
	check(near(PREF.depth_weight(neutral, 0.0), 1.0), "steady weight at 0")
	check(near(PREF.depth_weight(neutral, 0.5), 1.0), "steady weight at 0.5")
	check(near(PREF.depth_weight(neutral, 1.0), 1.0), "steady weight at 1")

	var deep := PREF.resolve({"depth": "deep"})
	check(PREF.depth_weight(deep, 0.9) > PREF.depth_weight(deep, 0.1), "deep favours the deep end")
	check(near(_sweep(neutral, 400), 2.0, 0.01), "steady full pump is 2.0")
	check(near(_sweep(deep, 400), 2.0, 0.01), "deep full pump is normalized to 2.0")
	check(near(_sweep(PREF.resolve({"depth": "shallow"}), 400), 2.0, 0.01), "shallow full pump is normalized")
	check(near(_sweep(PREF.resolve({"depth": "peak"}), 400), 2.0, 0.01), "peak full pump is normalized")

	var speed := PREF.resolve({"speed": {"enabled": true, "min": 0.30, "perfect": 0.80, "max": 1.20, "epsilon": 0.10}})
	check(PREF.speed_zone(speed, 0.80) == "perfect", "perfect speed band")
	check(PREF.speed_zone(speed, 0.20) == "slow", "slow speed zone")
	check(PREF.speed_zone(speed, 1.30) == "fast", "fast speed zone")
	check(PREF.speed_zone(speed, 0.55) == "ok", "between zones is ok")
	check(PREF.speed_zone(neutral, 99.0) == "fast", "default fast zone")

	var shape_pref := PREF.resolve({"shape": {"enabled": true, "likes": "ease_in", "dislikes": "ease_out", "like_gain": 1.2, "dislike_gain": 0.75}})
	check(near(PREF.shape_multiplier(shape_pref, "ease_in"), 1.2), "liked shape gain")
	check(near(PREF.shape_multiplier(shape_pref, "ease_out"), 0.75), "disliked shape gain")
	check(near(PREF.shape_multiplier(shape_pref, "steady"), 1.0), "neutral shape gain")
	var combined := PREF.resolve({
		"speed": {"enabled": true, "min": 0.3, "perfect": 0.8, "max": 1.2, "epsilon": 0.1},
		"shape": {"enabled": true, "likes": "ease_in", "like_gain": 1.2},
	})
	check(near(PREF.multiplier(combined, "perfect", "ease_in"), 1.56), "stacked multiplier")
	var capped := PREF.resolve({
		"speed": {"enabled": true, "min": 0.0, "perfect": 9.0, "max": 10.0, "epsilon": 9.0, "perfect_gain": 4.0},
		"shape": {"enabled": true, "likes": "ease_in", "like_gain": 4.0},
	})
	check(near(PREF.multiplier(capped, "perfect", "ease_in"), 1.80), "multiplier capped at 1.8")

	for name: String in ["steady", "ease_in", "ease_out", "ease_in_out"]:
		var result := PREF.classify_shape(_samples(name), 0.30, 0.18)
		check(str(result.get("shape", "")) == name, "classify %s" % name)
	var tiny := PREF.classify_shape(_samples("ease_in"), 1.2, 0.18)
	check(str(tiny.get("shape", "")) == PREF.MIXED, "too little travel is mixed")

	check(PREF.comfort_band(PREF.resolve({"depth": "deep"})) == Vector2(0.60, 1.00), "deep comfort band")
	check(PREF.comfort_band(PREF.resolve({"depth": "steady"})).x < 0.0, "steady has no depth band")

	var phased := PREF.resolve({
		"depth": "shallow",
		"notes": "base",
		"phases": [{
			"min_satisfaction": 0.75,
			"max_satisfaction": 1.0,
			"depth": "deep",
			"notes": "phase",
		}],
	})
	check(PREF.phase_index(phased, 0.74) == -1, "phase below threshold")
	check(PREF.phase_index(phased, 0.75) == 0, "phase at threshold")
	check(str(PREF.active(phased, 0.5).get("depth", "")) == "shallow", "base before phase")
	var phased_active := PREF.active(phased, 0.8)
	check(str(phased_active.get("depth", "")) == "deep", "phase depth override")
	check(str(phased_active.get("notes", "")) == "phase", "phase notes override")

	var merged := PREF.resolve({"depth": "deep", "notes": "  private  ", "shape": {"likes": "ease_in", "dislikes": "ease_in"}})
	check(str(merged.get("notes", "")) == "private", "notes trimmed")
	check(str((merged["shape"] as Dictionary).get("dislikes", "")) == "", "matching like/dislike clears dislike")
	check(str(PREF.resolve({"depth": "nonsense"}).get("depth", "")) == "steady", "unknown depth falls back")

	print("PREFERENCES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PREFERENCES_PASS")
	quit(0 if failures == 0 else 1)


func _sweep(pref: Dictionary, steps: int) -> float:
	var total := 0.0
	var previous := 0.0
	for index in range(1, steps + 1):
		var value := float(index) / float(steps)
		total += (value - previous) * PREF.depth_weight(pref, (previous + value) * 0.5)
		previous = value
	previous = 1.0
	for index in range(1, steps + 1):
		var value := 1.0 - float(index) / float(steps)
		total += (previous - value) * PREF.depth_weight(pref, (previous + value) * 0.5)
		previous = value
	return total


func _samples(name: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for index in range(21):
		var t := float(index) / 20.0
		out.append(Vector2(t, _curve(name, t)))
	return out


func _curve(name: String, t: float) -> float:
	match name:
		"ease_in":
			return t * t
		"ease_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"ease_in_out":
			return t * t * (3.0 - 2.0 * t)
	return t
