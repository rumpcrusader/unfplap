extends "res://mods/unfplap/tests/support/suite.gd"
## The readiness facade's auto-thrust generator and hold-X layer: defaults, toggle, step, wheel,
## the panel actions and the reset. The runtime only supplies the key states and applies the
## returned depth.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_readiness_auto.gd

const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const AUTO_THRUST := preload("res://mods/unfplap/readiness/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/readiness/auto_panel.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## No layer key held; an untyped `[]` cannot cross the typed key array.
var no_keys: Array[bool] = []


class FakeState extends RefCounted:
	var value := STATE_IDLE

	func state_now() -> int:
		return value


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _readiness(state: FakeState) -> RefCounted:
	var readiness: RefCounted = READINESS.new()
	readiness.state = Callable(state, "state_now")
	readiness.configure_auto(1.5, 0.8, "thrust", 0.2)
	readiness.reset_auto()
	return readiness


func run() -> void:
	_check_defaults()
	_check_toggle_and_step()
	_check_panel()
	_check_panel_repeat()
	_check_reset()
	if failures == 0:
		print("READINESS_AUTO_PASS")
	finish()


func _check_defaults() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	check(not readiness.auto_active(), "auto starts off")
	check(near(readiness.auto_pace(), 1.5), "configure_auto keeps the pace")
	check(near(readiness.auto_min_depth(), 0.2), "configure_auto keeps the bottom")
	check(near(readiness.auto_max_depth(), 0.8), "configure_auto keeps the peak")
	check(readiness.auto_shape() == "thrust", "configure_auto keeps the shape")
	readiness.configure_auto(1.0, 0.5, "cosine", 0.0)
	check(readiness.auto_shape() == "cosine", "configure_auto replaces the shape")
	check(not readiness.auto_panel_open(), "the layer starts closed")


func _check_toggle_and_step() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	state.value = STATE_IDLE
	readiness.toggle_auto(0.3)
	check(not readiness.auto_active(), "X outside an act changes nothing")
	state.value = STATE_ACTIVE
	readiness.toggle_auto(0.3)
	check(readiness.auto_active(), "X enables auto in ACTIVE")
	var depth: float = readiness.auto_step(1.0 / 60.0)
	check(is_finite(depth), "an enabled step returns a depth")
	check(depth >= readiness.auto_min_depth() and depth <= readiness.auto_max_depth(),
		"the step stays inside the band")
	var before: float = readiness.auto_pace()
	readiness.auto_wheel(1)
	check(near(readiness.auto_pace(), before + AUTO_THRUST.PACE_STEP), "the wheel nudges the pace")
	state.value = STATE_CLIMAX
	readiness.toggle_auto(0.4)
	check(not readiness.auto_active(), "a second X stops auto")
	check(is_nan(readiness.auto_step(1.0 / 60.0)), "a stopped generator returns NAN")
	state.value = STATE_IDLE
	readiness.toggle_auto(0.3)
	check(not readiness.auto_active(), "auto does not start outside ACTIVE/CLIMAX")


func _check_panel() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	state.value = STATE_ACTIVE
	# A tap: press and release under HOLD_S returns one toggle.
	var actions: Array[String] = readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	check(actions.is_empty(), "the press alone does not toggle")
	actions = readiness.auto_panel_tick(0.1, false, no_keys, 0.3)
	check(actions == ["toggle"], "a tap toggles auto")
	check(readiness.auto_active(), "the tap turned auto on")
	# A hold opens the layer; a key press inside it is one step.
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	check(readiness.auto_panel_open(), "a hold opens the layer")
	var before: float = readiness.auto_min_depth()
	var keys: Array[bool] = [true, false, false, false, false, false, false]
	actions = readiness.auto_panel_tick(0.1, true, keys, 0.3)
	check(actions == ["min_up"], "the top row adds one step")
	check(near(readiness.auto_min_depth(), before + AUTO_PANEL.DEPTH_STEP),
		"the min step reaches the generator")
	readiness.auto_panel_tick(0.1, false, no_keys, 0.3)
	check(readiness.auto_panel_open(), "the layer keeps its grace after release")
	readiness.auto_panel_tick(0.3, false, no_keys, 0.3)
	check(not readiness.auto_panel_open(), "the layer closes after the grace")
	# The shape cycle is the layer's own settings write.
	readiness.auto_set_shape("saw")
	check(readiness.auto_shape() == "saw", "the shape can be set")
	var saved_shape := SETTINGS.curve.get_choice()
	var shape_keys: Array[bool] = [false, false, false, false, false, false, true]
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	actions = readiness.auto_panel_tick(0.1, true, shape_keys, 0.3)
	check(actions == ["shape_next"], "Z reports the shape cycle")
	var next_shape: String = AUTO_THRUST.next_shape("saw")
	check(readiness.auto_shape() == next_shape, "the layer advances the shape")
	check(SETTINGS.curve.get_choice() == next_shape, "the shape write lands in settings")
	SETTINGS.curve.set_choice(saved_shape)
	# Leaving the act closes the layer and clears the keys.
	state.value = STATE_IDLE
	readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	check(not readiness.auto_panel_open(), "the layer closes outside the act")


func _check_panel_repeat() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	state.value = STATE_ACTIVE
	# Auto off: a tap toggles, but a held X has nothing to open.
	for i: int in 4:
		readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	check(not readiness.auto_panel_open(), "a hold cannot open the layer while auto is off")
	readiness.toggle_auto(0.3)
	for i: int in 4:
		readiness.auto_panel_tick(0.1, true, no_keys, 0.3)
	check(readiness.auto_panel_open(), "the layer opens for the repeat keys")
	# A layer key steps on press, then repeats after the delay at the repeat rate.
	var dt := 1.0 / 60.0
	var keys: Array[bool] = [true, false, false, false, false, false, false]
	var actions: Array[String] = readiness.auto_panel_tick(dt, true, keys, 0.3)
	check(actions == ["min_up"], "a layer key steps on press")
	actions = []
	for i: int in int(AUTO_PANEL.REPEAT_DELAY_S / dt) - 1:
		actions.append_array(readiness.auto_panel_tick(dt, true, keys, 0.3))
	check(actions.is_empty(), "no repeat before the delay")
	actions = []
	for i: int in int(0.2 / dt):
		actions.append_array(readiness.auto_panel_tick(dt, true, keys, 0.3))
	check(actions.size() >= 2, "a held key keeps repeating")


func _check_reset() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	state.value = STATE_ACTIVE
	readiness.toggle_auto(0.3)
	readiness.auto_wheel(1)
	readiness.auto_set_shape("hold")
	readiness.reset_auto()
	check(not readiness.auto_active(), "the reset clears auto")
	check(near(readiness.auto_pace(), 1.5), "the reset restores the pace")
	check(near(readiness.auto_min_depth(), 0.2), "the reset restores the bottom")
	check(near(readiness.auto_max_depth(), 0.8), "the reset restores the peak")
	check(readiness.auto_shape() == "hold", "the reset keeps the last chosen shape")
	check(not readiness.auto_panel_open(), "the reset closes the layer")
