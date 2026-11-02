extends SceneTree
## Pure utterance schedule/prompt tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_utterance.gd

const UTTER := preload("res://mods/unfplap/utterance.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for count in 9:
		var value := UTTER.line_count(count, count, rng)
		check(value == count, "line_count fixed %d" % count)
	check(UTTER.line_count(5, 2, rng) >= 2 and UTTER.line_count(5, 2, rng) <= 5, "line_count swaps range")
	check(UTTER.line_count(-3, 99, rng) >= 0 and UTTER.line_count(-3, 99, rng) <= 8, "line_count clamps")

	var points := UTTER.schedule(100, 5, 1234)
	check(points.size() == 5, "schedule count")
	var previous := -INF
	var sorted := true
	var in_range := true
	for point: float in points:
		if point <= previous:
			sorted = false
		if point < 8.0 or point > 92.0:
			in_range = false
		previous = point
	check(sorted, "points sorted")
	check(in_range, "points inside 8–92%")
	var too_close := false
	for index in range(1, points.size()):
		if points[index] - points[index - 1] < 5.0:
			too_close = true
	check(not too_close, "points separated")
	check(UTTER.schedule(100, 0, 1).is_empty(), "zero points")
	check(UTTER.schedule(1, 8, 1).size() == 8, "small climax still schedules")

	var text := UTTER.format("a {state} b {preferences} c {recent} d {missing}", {
		"state": "S", "preferences": "P", "recent": "R",
	})
	check(text == "a S b P c R d ", "format placeholders")

	var line := UTTER.state_line("missionary", 42, 100, 0.78, 0.9, "perfect", "ease_in", 18.0)
	check(line.contains("pose=missionary"), "state line pose")
	check(line.contains("depth=0.78 (deep)"), "state line depth")
	check(line.contains("speed=0.90/s (perfect)"), "state line speed")
	check(line.contains("stroke=ease_in"), "state line shape")
	check(line.contains("18s in"), "state line time")

	print("UTTERANCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("UTTERANCE_PASS")
	quit(0 if failures == 0 else 1)
