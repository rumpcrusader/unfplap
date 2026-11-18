extends SceneTree
## The idle heat display: the act-state suppression, the phase poll, the rest shape and the wink
## schedule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_heat.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

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
	# Idle heat: active act states suppress the display, idle allows it, and a due timer winks.
	var heat_facts := FACTS.new()
	heat_facts.cycle_phase = "heat"
	var heat_anatomy: Node = ANATOMY.new()
	var heat_pony := Node3D.new()
	var wink_mesh := MeshInstance3D.new()
	wink_mesh.mesh = BoxMesh.new()
	heat_anatomy.add_child(wink_mesh)
	get_root().add_child(heat_anatomy)
	heat_anatomy.set_process(false)
	heat_anatomy.set("pony", heat_pony)
	heat_anatomy.set("facts", heat_facts)
	heat_anatomy.attach.setup(heat_anatomy, heat_pony, heat_facts)
	heat_anatomy.attach.attached = true
	heat_anatomy.attach.mesh = wink_mesh
	heat_anatomy.shapes.set_mesh(wink_mesh)
	heat_anatomy.attach.apply_visibility(true)
	heat_facts.state = 2
	heat_anatomy.call("_heat_idle_tick", 0.1)
	check(heat_anatomy.heat.suppressed(), "active act suppresses idle heat")
	heat_facts.state = 0
	heat_anatomy.call("_heat_idle_tick", 2.1)
	check(heat_anatomy.heat.phase() == CYCLE.HEAT, "the idle heat poll adopts the phase")
	var gap_lo := minf(SETTINGS.wink_min_s.get_num(), SETTINGS.wink_max_s.get_num())
	check(heat_anatomy.heat.wink_clock() >= gap_lo,
		"an idle heat wink resets the interval")
	heat_anatomy.call("_heat_idle_tick", heat_anatomy.heat.wink_clock() + 0.01)
	check(heat_anatomy.shapes.tween_running(), "an idle heat wink builds its tween")
	heat_anatomy.set_idle_wink(0.0)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"the default rest clears the wink shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)), 1.0),
		"the default rest is the authored closed shape")
	var rest_open := clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)
	heat_anatomy.set_idle_wink(rest_open)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), rest_open),
		"heat rests at the configured share of the open shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)),
		1.0 - rest_open), "the heat rest opens the closed lips by the same share")
	check(bool(heat_anatomy.shapes.state().get("idle_wink", false)),
		"the idle rest owns the shapes")
	heat_anatomy.drive(0.5)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"acts clear the idle wink shape")
	check(not bool(heat_anatomy.shapes.state().get("idle_wink", true)),
		"an act clears the idle cut suppression")
	heat_anatomy.free()
	heat_pony.free()

	print("ANATOMY_HEAT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
