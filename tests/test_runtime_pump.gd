extends SceneTree
## Minimal integration test for the ACTIVE readiness path, without a world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_runtime_pump.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const PUMP := preload("res://mods/unfplap/pump.gd")
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
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime._taste = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"talk": ["praise"],
		"warmth": "normal",
	})
	runtime._pump_tracker = PUMP.new()
	runtime.state = 2 # ACTIVE

	runtime._pump_move(1.0, 0.0)
	runtime._pump_move(-1.0, 0.5)
	runtime._pump_move(1.0, 1.0)
	check(near(runtime.satisfaction, 0.0), "strokes do not add readiness directly")
	check(not str(runtime._last_intensity).is_empty(), "stroke classifies intensity")
	check(absf(float(runtime.depth) - 1.0) < 0.0001, "depth tracks the last move")

	runtime._last_intensity = "firm"
	runtime._last_pattern = "steady"
	runtime._last_stroke_at = runtime._now_s()
	runtime._heat_tick(1.0)
	check(runtime.satisfaction > 1.0, "matching both axes adds readiness")
	var before: float = runtime.satisfaction
	runtime._on_touch("caress")
	check(runtime.satisfaction > before, "liked touch adds readiness")
	before = runtime.satisfaction
	runtime._on_talk("you are beautiful")
	check(runtime.satisfaction > before, "liked talk adds readiness")
	before = runtime.satisfaction
	runtime._on_touch("smack")
	check(near(runtime.satisfaction, before), "neutral touch does not add readiness")
	runtime._add_heat(999.0)
	check(near(runtime.satisfaction, 100.0), "readiness clamps at 100")
	check(int(runtime.state) == 2, "readiness never auto-climaxes")
	runtime.free()

	print("RUNTIME_PUMP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_PUMP_PASS")
	quit(0 if failures == 0 else 1)
