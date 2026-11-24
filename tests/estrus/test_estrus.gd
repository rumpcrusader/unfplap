extends "res://mods/unfplap/tests/support/suite.gd"
## The estrus service: the debug override, the phase fallback and the tracked schedule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/estrus/test_estrus.gd

const ESTRUS := preload("res://mods/unfplap/estrus/api.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const CYCLE_STATE := preload("res://mods/unfplap/shared/cycle_state.gd")


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
	check(CYCLE_STATE.phase(pony, false, NAN) == CYCLE.HEAT,
		"the shared derivation honours the override with the feature off")
	service.debug_set_phase(pony, "")
	check(service.phase(pony) == CYCLE.NORMAL, "clearing the override restores normal")
	check(CYCLE_STATE.phase(pony, true, NAN) == CYCLE.NORMAL,
		"the shared derivation reads the automatic phase")

	service.track(pony)
	service.track(pony)
	service._process(0.1)
	service.untrack(pony)
	check(service.get_process_delta_time() >= 0.0, "one tick is safe without an anatomy link")

	service.shutdown()
	root.remove_child(pony)
	pony.free()
	root.remove_child(service)
	service.free()
	finish()
