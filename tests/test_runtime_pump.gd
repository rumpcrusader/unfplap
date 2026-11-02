extends SceneTree
## Minimal integration test for the runtime scoring path, without a world.
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


func run() -> void:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime._preferences = PREF.resolve({"speed": {"enabled": false}, "shape": {"enabled": false}})
	runtime._pump_tracker = PUMP.new()
	runtime._pump_pixels_per_full = 420.0
	runtime._climax_at = 1000
	runtime.state = 2 # ACTIVE
	runtime._pump_move(1.0, 0.0)
	runtime._pump_move(-1.0, 0.5)
	runtime._pump_move(1.0, 1.0)
	check(runtime.satisfaction == 2, "full steady pump scores 2 satisfaction")
	check(runtime.stamina == 399, "one deep extreme costs one stamina")
	check(absf(runtime._satisfaction_frac) < 0.0001, "no fractional remainder")
	check(absf(float(runtime.depth) - 1.0) < 0.0001, "depth tracks the last move")
	runtime.free()

	var shaped: Node = RUNTIME.new()
	shaped.pony = Node3D.new()
	shaped._preferences = PREF.resolve({"shape": {"enabled": true, "likes": "ease_out"}})
	shaped._pump_tracker = PUMP.new()
	shaped._climax_at = 1000
	shaped.state = 2
	shaped._pump_move(1.0, 0.0)
	shaped._pump_move(-1.0, 0.5)
	check(str(shaped._last_stroke.get("shape", "")) != "", "shape classification path runs")
	shaped.free()

	print("RUNTIME_PUMP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("RUNTIME_PUMP_PASS")
	quit(0 if failures == 0 else 1)
