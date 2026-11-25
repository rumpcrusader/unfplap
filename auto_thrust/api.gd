extends Node
## Scope: pony
## The automatic stroke: the band, the pace, the shape and the hold-X layer. It generates the
## movement the mouse would and the act feeds it into the same tracker, so scoring, intensity,
## pattern and presentation stay one path. Nothing here is about her.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const AUTO_THRUST := preload("res://mods/unfplap/auto_thrust/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/auto_thrust/auto_panel.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## One act's automatic stroke, as the HUD and the input gate read it.
class Readout extends RefCounted:
	## The player's intent: the machine is on and owns the stroke.
	var on := false
	## The intent the act could still honour, so the mouse stays off and the layer may open.
	var active := false
	var pace := 0.0
	var min_depth := 0.0
	var max_depth := 0.0
	var shape := ""
	var panel_open := false


## The live values, rewritten in place; no caller allocates a second copy.
var _readout := Readout.new()
var _generator: AUTO_THRUST = AUTO_THRUST.new()
var _panel: AUTO_PANEL = AUTO_PANEL.new()


## A new act begins from the declared starting values, off, with the layer closed.
func start_act() -> void:
	_readout.on = false
	_readout.active = false
	_generator.reset(SETTINGS.pace.get_num(), SETTINGS.max_depth.get_num(),
		SETTINGS.curve.get_choice(), SETTINGS.min_depth.get_num())
	_panel.reset()
	_sync()


## End the stroke and close the layer; the tuned band survives, so a body swap restarts it.
func stop() -> void:
	_readout.on = false
	_readout.active = false
	_generator.stop()
	_panel.reset()
	_sync()


## Turn it on from the hand's current share, or off.
func toggle(share: float) -> void:
	_readout.on = not _readout.on
	_readout.active = _readout.on
	if _readout.on:
		_generator.begin(share)
	else:
		_generator.stop()
	_sync()
	LOG.debug("auto thrust %s pace=%.2f/s depth=%.0f%%", [
		"on" if _readout.on else "off", _readout.pace, _readout.max_depth * 100.0])


## One wheel notch of pace while it owns the stroke.
func wheel(direction: int) -> void:
	if not _readout.on:
		return
	_generator.nudge_pace(float(direction) * AUTO_THRUST.PACE_STEP)
	_sync()


## One frame: the movement to feed the tracker this frame, 0 while it is off.
func step(delta: float, share: float) -> float:
	if not _readout.on:
		return 0.0
	var next := _generator.step(delta)
	_sync()
	return next - share


## One hold-X frame; it applies its own actions and returns them for the log.
func panel(delta: float, x_down: bool, keys: Array[bool], share: float) -> Array[String]:
	var actions: Array[String] = _panel.tick(delta, x_down, keys, _readout.on)
	for action: String in actions:
		match action:
			"toggle":
				toggle(share)
			"min_up", "min_down":
				_generator.nudge_min(AUTO_PANEL.DEPTH_STEP if action == "min_up"
					else -AUTO_PANEL.DEPTH_STEP)
			"max_up", "max_down":
				_generator.nudge_depth(AUTO_PANEL.DEPTH_STEP if action == "max_up"
					else -AUTO_PANEL.DEPTH_STEP)
			"pace_up", "pace_down":
				_generator.nudge_pace(AUTO_PANEL.PACE_STEP if action == "pace_up"
					else -AUTO_PANEL.PACE_STEP)
			"shape_next":
				_cycle_shape()
	_sync()
	if not actions.is_empty():
		LOG.debug("auto layer %s min=%.0f%% max=%.0f%% pace=%.2f/s", [
			",".join(actions), _readout.min_depth * 100.0, _readout.max_depth * 100.0,
			_readout.pace])
	return actions


## The live values, the same instance every call.
func readout() -> Readout:
	return _readout


## The layer's shape key: the next waveform, kept in the settings after the act.
func _cycle_shape() -> void:
	var next := AUTO_THRUST.next_shape(_generator.shape)
	SETTINGS.curve.set_choice(next)
	_generator.set_shape(next)
	LOG.debug("auto shape %s", [_generator.shape])


## Mirror the generator and the layer into the one readout the callers hold.
func _sync() -> void:
	_readout.pace = _generator.pace
	_readout.min_depth = _generator.min_depth
	_readout.max_depth = _generator.max_depth
	_readout.shape = _generator.shape
	_readout.panel_open = _panel.open
