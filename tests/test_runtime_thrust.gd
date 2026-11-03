extends SceneTree
## Minimal integration test for ACTIVE readiness and pony-climax separation, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_runtime_thrust.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
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


func _runtime() -> Node:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime._taste = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
		"warmth": "normal",
		"recovery": 25,
	})
	runtime._thrust_tracker = THRUST.new()
	runtime.state = 2 # ACTIVE
	runtime._last_touch_at = -1000.0
	runtime._last_talk_at = -1000.0
	return runtime


func run() -> void:
	var runtime: Node = _runtime()
	runtime._thrust_move(0.10, 0.0)
	runtime._thrust_move(-0.15, 0.1)
	check(str(runtime._last_intensity).is_empty(), "tiny stroke does not feed the axes")
	runtime._thrust_move(1.0, 0.2)
	runtime._thrust_move(-1.0, 0.45)
	check(not str(runtime._last_intensity).is_empty(), "real thrust classifies intensity")
	check(near(runtime.satisfaction, 0.7), "a single matching axis adds only the one-axis chunk")

	runtime._last_intensity = "firm"
	runtime._last_pattern = "steady"
	runtime._last_stroke_at = runtime._now_s()
	runtime._last_thrust_score_at = -1000.0
	runtime._score_thrust()
	check(runtime.satisfaction > 1.0, "matching both axes adds readiness")
	var before: float = runtime.satisfaction
	runtime._readiness_tick(10.0)
	check(near(runtime.satisfaction, before), "readiness does not decay on its own")

	before = runtime.satisfaction
	runtime._on_touch("caress")
	check(runtime.satisfaction > before, "liked touch adds readiness")
	before = runtime.satisfaction
	runtime._on_talk("you are beautiful")
	check(runtime.satisfaction > before, "liked talk adds readiness")
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(near(runtime.satisfaction, before), "shared touch cooldown blocks a second chunk")
	runtime._last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("kiss")
	check(near(runtime.satisfaction, before), "neutral touch does not change readiness")
	runtime._last_touch_at = -1000.0
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(runtime.satisfaction < before, "disliked touch lowers readiness")

	runtime.satisfaction = 59.0
	runtime._last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, 60.0), "liked touch clamps at the assist cap")
	before = runtime.satisfaction
	runtime._last_touch_at = -1000.0
	runtime._on_touch("caress")
	check(near(runtime.satisfaction, before), "caress cannot pass the assist cap")
	check(runtime._receptive_until > runtime._now_s(), "liked touch opens the receptive window")

	runtime._add_heat(999.0)
	check(near(runtime.satisfaction, 100.0), "readiness clamps at 100")
	runtime._readiness_tick(0.1)
	check(int(runtime.state) == 3, "100 readiness starts a pony climax")
	check(runtime.pony_climaxes == 1, "pony climax count increments")
	var climax_readiness: float = runtime.satisfaction
	runtime._on_stroke({
		"direction": 1, "thrust": true, "travel": 0.5, "duration": 0.5,
		"speed": 1.0, "peak_speed": 1.0, "strength": 0.5,
	})
	check(near(runtime.satisfaction, climax_readiness), "thrusting during climax does not score")
	check(int(runtime.state) == 3, "thrusting during climax does not end it")

	runtime._finish_climax()
	check(int(runtime.state) == 2, "first climax returns to ACTIVE")
	check(near(runtime.satisfaction, 25.0), "recovery resets readiness to the mare's value")
	check(runtime.pony_climaxes == 1, "climax count survives the return to ACTIVE")

	runtime.pony_climaxes = 2
	runtime.satisfaction = 100.0
	runtime._climax()
	runtime._finish_climax()
	check(int(runtime.state) == 4, "third climax auto-enters AFTERGLOW")
	runtime.free()

	print("RUNTIME_THRUST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_THRUST_PASS")
	quit(0 if failures == 0 else 1)
