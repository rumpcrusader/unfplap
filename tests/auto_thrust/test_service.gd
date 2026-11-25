extends "res://mods/unfplap/tests/support/suite.gd"
## The auto-thrust service: the settings defaults at the act start, the toggle, the generated
## movement, the wheel, the hold-X layer and its own shape write.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/auto_thrust/test_service.gd

const AUTO := preload("res://mods/unfplap/auto_thrust/api.gd")
const GENERATOR := preload("res://mods/unfplap/auto_thrust/auto_thrust.gd")
const PANEL := preload("res://mods/unfplap/auto_thrust/auto_panel.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")

## No layer key held; an untyped `[]` cannot cross the typed key array.
var no_keys: Array[bool] = []


func run() -> void:
	_check_defaults()
	_check_toggle_and_step()
	_check_panel()
	_check_panel_repeat()
	_check_stop()
	if failures == 0:
		print("AUTO_THRUST_SERVICE_PASS")
	finish()


## The starting values an act reads, written first and handed back for the restore.
func _start(auto: AUTO) -> Dictionary:
	var saved := {
		"pace": SETTINGS.pace.get_num(), "max": SETTINGS.max_depth.get_num(),
		"min": SETTINGS.min_depth.get_num(), "shape": SETTINGS.curve.get_choice(),
	}
	SETTINGS.pace.set_num(1.5)
	SETTINGS.max_depth.set_num(0.8)
	SETTINGS.min_depth.set_num(0.2)
	SETTINGS.curve.set_choice("thrust")
	auto.start_act()
	return saved


func _restore(saved: Dictionary) -> void:
	SETTINGS.pace.set_num(float(saved["pace"]))
	SETTINGS.max_depth.set_num(float(saved["max"]))
	SETTINGS.min_depth.set_num(float(saved["min"]))
	SETTINGS.curve.set_choice(str(saved["shape"]))


func _check_defaults() -> void:
	var auto: AUTO = AUTO.new()
	var saved := _start(auto)
	var readout := auto.readout()
	check(not readout.on and not readout.active, "auto starts off")
	check(near(readout.pace, 1.5), "the act start reads the pace")
	check(near(readout.min_depth, 0.2), "the act start reads the bottom")
	check(near(readout.max_depth, 0.8), "the act start reads the peak")
	check(readout.shape == "thrust", "the act start reads the shape")
	check(not readout.panel_open, "the layer starts closed")
	check_same(auto.readout(), readout, "the readout is the one instance")
	_restore(saved)
	auto.free()


func _check_toggle_and_step() -> void:
	var auto: AUTO = AUTO.new()
	var saved := _start(auto)
	auto.toggle(0.3)
	check(auto.readout().on and auto.readout().active, "the toggle turns auto on")
	var movement := auto.step(1.0 / 60.0, 0.3)
	check(is_finite(movement), "an enabled step returns a movement")
	check(absf(movement) > 0.0, "the step moves the stroke")
	check(is_zero_approx(auto.step(0.0, 0.3 + movement)), "a still frame moves nothing")
	var pace := auto.readout().pace
	auto.wheel(1)
	check(near(auto.readout().pace, pace + GENERATOR.PACE_STEP), "the wheel nudges the pace")
	auto.toggle(0.4)
	check(not auto.readout().on and not auto.readout().active, "a second toggle stops auto")
	check(is_zero_approx(auto.step(1.0 / 60.0, 0.4)), "a stopped generator moves nothing")
	_restore(saved)
	auto.free()


func _check_panel() -> void:
	var auto: AUTO = AUTO.new()
	var saved := _start(auto)
	# A tap: press and release under HOLD_S returns one toggle.
	var actions: Array[String] = auto.panel(0.1, true, no_keys, 0.3)
	check(actions.is_empty(), "the press alone does not toggle")
	actions = auto.panel(0.1, false, no_keys, 0.3)
	check(actions == ["toggle"], "a tap toggles auto")
	check(auto.readout().on, "the tap turned auto on")
	# A hold opens the layer; a key press inside it is one step.
	auto.panel(0.1, true, no_keys, 0.3)
	auto.panel(0.1, true, no_keys, 0.3)
	auto.panel(0.1, true, no_keys, 0.3)
	check(auto.readout().panel_open, "a hold opens the layer")
	var before := auto.readout().min_depth
	var keys: Array[bool] = [true, false, false, false, false, false, false]
	actions = auto.panel(0.1, true, keys, 0.3)
	check(actions == ["min_up"], "the top row adds one step")
	check(near(auto.readout().min_depth, before + PANEL.DEPTH_STEP),
		"the min step reaches the band")
	auto.panel(0.1, false, no_keys, 0.3)
	check(auto.readout().panel_open, "the layer keeps its grace after release")
	auto.panel(0.3, false, no_keys, 0.3)
	check(not auto.readout().panel_open, "the layer closes after the grace")
	# The shape cycle is the layer's own settings write.
	var saved_shape := SETTINGS.curve.get_choice()
	var shape_keys: Array[bool] = [false, false, false, false, false, false, true]
	auto.panel(0.1, true, no_keys, 0.3)
	auto.panel(0.1, true, no_keys, 0.3)
	auto.panel(0.1, true, no_keys, 0.3)
	var before_shape: String = str(auto.readout().shape)
	actions = auto.panel(0.1, true, shape_keys, 0.3)
	check(actions == ["shape_next"], "Z reports the shape cycle")
	var next_shape: String = GENERATOR.next_shape(before_shape)
	check(auto.readout().shape == next_shape, "the layer advances the shape")
	check(SETTINGS.curve.get_choice() == next_shape, "the shape write lands in settings")
	SETTINGS.curve.set_choice(saved_shape)
	_restore(saved)
	auto.free()


func _check_panel_repeat() -> void:
	var auto: AUTO = AUTO.new()
	var saved := _start(auto)
	# Auto off: a tap toggles, but a held X has nothing to open.
	for i: int in 4:
		auto.panel(0.1, true, no_keys, 0.3)
	check(not auto.readout().panel_open, "a hold cannot open the layer while auto is off")
	auto.toggle(0.3)
	for i: int in 4:
		auto.panel(0.1, true, no_keys, 0.3)
	check(auto.readout().panel_open, "the layer opens for the repeat keys")
	# A layer key steps on press, then repeats after the delay at the repeat rate.
	var dt := 1.0 / 60.0
	var keys: Array[bool] = [true, false, false, false, false, false, false]
	var actions: Array[String] = auto.panel(dt, true, keys, 0.3)
	check(actions == ["min_up"], "a layer key steps on press")
	actions = []
	for i: int in int(PANEL.REPEAT_DELAY_S / dt) - 1:
		actions.append_array(auto.panel(dt, true, keys, 0.3))
	check(actions.is_empty(), "no repeat before the delay")
	actions = []
	for i: int in int(0.2 / dt):
		actions.append_array(auto.panel(dt, true, keys, 0.3))
	check(actions.size() >= 2, "a held key keeps repeating")
	_restore(saved)
	auto.free()


func _check_stop() -> void:
	var auto: AUTO = AUTO.new()
	var saved := _start(auto)
	auto.toggle(0.3)
	auto.wheel(1)
	var pace := auto.readout().pace
	auto.stop()
	check(not auto.readout().on and not auto.readout().active, "the stop ends the stroke")
	check(near(auto.readout().pace, pace), "the stop keeps the tuned band")
	check(not auto.readout().panel_open, "the stop closes the layer")
	auto.start_act()
	check(near(auto.readout().pace, 1.5), "a fresh act restores the settings pace")
	check(near(auto.readout().max_depth, 0.8), "a fresh act restores the settings peak")
	_restore(saved)
	auto.free()
