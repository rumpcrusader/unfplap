extends SceneTree
## The readiness facade's auto-thrust generator and hold-X layer: defaults, toggle, step, wheel,
## the panel actions and the reset. The runtime only supplies the key states and applies the
## returned depth.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_readiness_auto.gd

const READINESS := preload("res://mods/unfplap/readiness.gd")
const AUTO_THRUST := preload("res://mods/unfplap/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/auto_panel.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

var failures := 0
var checks := 0


class FakeState extends RefCounted:
	var value := STATE_IDLE

	func state_now() -> int:
		return value


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _readiness(state: FakeState) -> RefCounted:
	var readiness: RefCounted = READINESS.new()
	readiness.state = Callable(state, "state_now")
	readiness.log = Callable()
	readiness.configure_auto(1.5, 0.8, "thrust", 0.2)
	readiness.reset_auto()
	return readiness


func run() -> void:
	_check_defaults()
	_check_toggle_and_step()
	_check_panel()
	_check_reset()
	print("READINESS_AUTO_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("READINESS_AUTO_PASS")
	quit(0 if failures == 0 else 1)


func _check_defaults() -> void:
	var state := FakeState.new()
	var readiness := _readiness(state)
	check(not readiness.auto_active(), "auto starts off")
	check(near(readiness.auto_pace(), 1.5), "configure_auto keeps the pace")
	check(near(readiness.auto_min_depth(), 0.2), "configure_auto keeps the bottom")
	check(near(readiness.auto_max_depth(), 0.8), "configure_auto keeps the peak")
	check(readiness.auto_shape() == "thrust", "configure_auto keeps the shape")
	readiness.configure_auto(1.0, 0.5, "not_a_shape", 0.0)
	check(readiness.auto_shape() == "cosine", "an unknown shape falls back to cosine")
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
	var actions: Array[String] = readiness.auto_panel_tick(0.1, true, [], 0.3)
	check(actions.is_empty(), "the press alone does not toggle")
	actions = readiness.auto_panel_tick(0.1, false, [], 0.3)
	check(actions == ["toggle"], "a tap toggles auto")
	check(readiness.auto_active(), "the tap turned auto on")
	# A hold opens the layer; a key press inside it is one step.
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	check(readiness.auto_panel_open(), "a hold opens the layer")
	var before: float = readiness.auto_min_depth()
	var keys := [true, false, false, false, false, false, false]
	actions = readiness.auto_panel_tick(0.1, true, keys, 0.3)
	check(actions == ["min_up"], "the top row adds one step")
	check(near(readiness.auto_min_depth(), before + AUTO_PANEL.DEPTH_STEP),
		"the min step reaches the generator")
	readiness.auto_panel_tick(0.1, false, [], 0.3)
	check(readiness.auto_panel_open(), "the layer keeps its grace after release")
	readiness.auto_panel_tick(0.3, false, [], 0.3)
	check(not readiness.auto_panel_open(), "the layer closes after the grace")
	# The shape cycle is the one action the runtime still carries out.
	readiness.auto_set_shape("saw")
	check(readiness.auto_shape() == "saw", "the shape can be set")
	var shape_keys := [false, false, false, false, false, false, true]
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	actions = readiness.auto_panel_tick(0.1, true, shape_keys, 0.3)
	check(actions == ["shape_next"], "Z requests the shape cycle")
	check(readiness.auto_shape() == "saw", "the layer leaves the shape write to the runtime")
	# Leaving the act closes the layer and clears the keys.
	state.value = STATE_IDLE
	readiness.auto_panel_tick(0.1, true, [], 0.3)
	check(not readiness.auto_panel_open(), "the layer closes outside the act")


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
