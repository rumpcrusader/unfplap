extends "res://mods/unfplap/tests/support/suite.gd"
## The estrus service: the debug override, the phase fallback and the tracked schedule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/estrus/test_estrus.gd

const ESTRUS := preload("res://mods/unfplap/estrus/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")


func run() -> void:
	var service: Node = ESTRUS.new()
	root.add_child(service)
	var pony := Node3D.new()
	root.add_child(pony)

	# Without a relationship runtime the automatic phase is normal; the debug override still wins.
	check(service.phase(pony) == CYCLE.NORMAL, "no bond day is normal")
	check(service.debug_set_phase(pony, CYCLE.HEAT) == CYCLE.HEAT,
		"the debug override forces heat")
	check(service.phase(pony) == CYCLE.HEAT, "the phase reads the override")
	check(ESTRUS.phase_for(pony) == CYCLE.HEAT, "the static read reaches the bound service")
	service.debug_set_phase(pony, "")
	check(service.phase(pony) == CYCLE.NORMAL, "clearing the override restores normal")

	service.track(pony)
	service.track(pony)
	service._process(0.1)
	service.untrack(pony)
	check(service.get_process_delta_time() >= 0.0, "one tick is safe without an anatomy link")

	service.shutdown()
	check(ESTRUS.bound == null, "shutdown unbinds the static service")
	root.remove_child(pony)
	pony.free()
	root.remove_child(service)
	service.free()
	finish()
