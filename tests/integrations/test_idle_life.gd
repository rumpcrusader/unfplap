extends SceneTree
## The Idle Life provider: feature, pose, external-mod and binding gates, and the one pose write
## it asks the integrations facade to make.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_idle_life.gd

const PROVIDER := preload("res://mods/unfplap/integrations/idle_life.gd")
const CONTEXT := preload("res://mods/unfplap/integrations/context.gd")
const ACTION := preload("res://mods/unfplap/integrations/action.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _context() -> RefCounted:
	var context: RefCounted = CONTEXT.new()
	context.pose_id = "standing"
	context.mod_active = true
	context.features = {"idle_life_stretch": true}
	context.bindings = {"pose": true}
	return context


func run() -> void:
	var provider: RefCounted = PROVIDER.new()
	var context := _context()
	check(provider.call("available", context), "the full gate opens the provider")
	context.features = {"idle_life_stretch": false}
	check(not provider.call("available", context), "the act feature gates the provider")
	context.features = {"idle_life_stretch": true}
	context.pose_id = "missionary"
	check(not provider.call("available", context), "only the standing pose stretches")
	context.pose_id = "standing"
	context.mod_active = false
	check(not provider.call("available", context), "the external mod must be active")
	context.mod_active = true
	context.bindings = {"pose": false}
	check(not provider.call("available", context), "a missing pose binding gates the provider")
	context.bindings = {"pose": true}
	check(not provider.call("holds_excitement"), "the stretch does not own the excitement Beat")

	var out: Array = []
	provider.call("start_actions", context, out)
	check(out.size() == 1, "start asks for exactly one write")
	if out.size() == 1:
		var action: Variant = out[0]
		check(str(action.get("kind")) == ACTION.SET, "the write is a set")
		check(str(action.get("binding")) == "pose", "the write targets the act pose")
		check(str(action.get("property")) == "stretch", "the write switches stretch mode")
		check(bool(action.get("value")), "the write turns stretch on")
	out.clear()
	provider.call("tick_actions", context, 0.1, out)
	check(out.is_empty(), "the stretch has no per-tick writes")
	provider.call("afterglow_actions", context, out)
	check(out.is_empty(), "the stretch has no afterglow write")
	out.clear()
	provider.call("start_actions", context, out)
	provider.call("start_actions", context, out)
	check(out.size() == 2 and out[0] == out[1],
		"the provider reuses its one action object")
	print("IDLE_LIFE_PROVIDER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("IDLE_LIFE_PROVIDER_PASS")
	quit(0 if failures == 0 else 1)