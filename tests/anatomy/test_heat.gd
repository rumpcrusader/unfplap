extends "res://mods/unfplap/tests/support/suite.gd"
## The idle heat animation: the resting open shape, one wink burst and the act suppression. The
## estrus service owns the schedule; `tests/estrus` pins that half.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_heat.gd

const HEAT := preload("res://mods/unfplap/anatomy/heat.gd")
const SHAPES := preload("res://mods/unfplap/anatomy/shapes.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")


func run() -> void:
	var pony := Node3D.new()
	var host := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(pony)
	root.add_child(host)
	host.add_child(mesh)
	var shapes := SHAPES.new()
	shapes.setup(pony, host)
	shapes.set_mesh(mesh)
	var heat := HEAT.new()
	heat.setup(shapes)

	var rest_open := clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)
	heat.set_rest(rest_open)
	check(is_equal_approx(float(shapes.wink_amount()), rest_open),
		"the heat rest is the configured share of the open shape")
	check(is_equal_approx(float(shapes.state().get("closed", -1.0)), 1.0 - rest_open),
		"the heat rest opens the closed lips by the same share")

	heat.set_suppressed(true)
	heat.wink_burst(2, Callable())
	check(not shapes.tween_running(), "an act suppresses the idle wink")

	heat.set_suppressed(false)
	heat.wink_burst(2, Callable())
	check(shapes.tween_running(), "an idle burst builds its tween")
	shapes.drive(0.5)
	check(is_equal_approx(float(shapes.wink_amount()), 0.0), "the act's drive clears the idle wink")

	root.remove_child(pony)
	pony.free()
	root.remove_child(host)
	host.free()
	finish()
