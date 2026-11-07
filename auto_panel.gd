extends RefCounted
## Hold-X auto settings layer. Pure: the caller feeds the key state in and executes the actions.
##
## A short press of X toggles auto thrust, as it always did. Holding it for `HOLD_S` opens the
## layer, which stays open while X is pressed; releasing keeps it open for `GRACE_S` so a re-press
## does not flicker, and closes it otherwise. A press that ever opened the layer can never toggle,
## so a slow release never surprises the player.
##
## Layer keys are positional: top row adds, home row subtracts, in the same order the HUD shows.

const HOLD_S := 0.28
const GRACE_S := 0.28
## First repeat after this delay, then one step this often while the key is held.
const REPEAT_DELAY_S := 0.4
const REPEAT_RATE_S := 0.08
## One step of each adjustment. Depth is a share of the reach; pace matches the wheel notch.
const DEPTH_STEP := 0.05
const PACE_STEP := 0.25
## Actions, in key order. The caller maps each to its runtime call.
const ACTIONS := ["min_up", "min_down", "max_up", "max_down", "pace_up", "pace_down", "shape_next"]
const KEY_COUNT := 7

var open := false

var _held_s := 0.0
var _was_down := false
var _opened := false
var _grace_left := 0.0
var _key_down: Array[bool] = []
var _key_repeat: Array[float] = []


func _init() -> void:
	reset()


func reset() -> void:
	open = false
	_held_s = 0.0
	_was_down = false
	_opened = false
	_grace_left = 0.0
	_key_down = []
	_key_repeat = []
	_key_down.resize(KEY_COUNT)
	_key_repeat.resize(KEY_COUNT)
	for i: int in KEY_COUNT:
		_key_down[i] = false
		_key_repeat[i] = 0.0


## One frame. `x_down` is the hold key, `keys` the layer keys in `ACTIONS` order. `allow_open`
## is false while auto is off: the tap still toggles, but there is nothing to adjust.
func tick(delta: float, x_down: bool, keys: Array, allow_open: bool) -> Array[String]:
	var actions: Array[String] = []
	if x_down:
		if not _was_down:
			_held_s = 0.0
			_grace_left = 0.0
		_held_s += delta
		if allow_open and _held_s >= HOLD_S:
			open = true
			_opened = true
	elif _was_down:
		# Released: a tap toggles, a layer press starts the grace instead.
		if _opened:
			_grace_left = GRACE_S
		elif _held_s < HOLD_S:
			actions.append("toggle")
	if not allow_open:
		close()
	if open and not x_down:
		_grace_left -= delta
		if _grace_left <= 0.0:
			close()
	if open and x_down:
		_collect_repeats(delta, keys, actions)
	_was_down = x_down
	return actions


func close() -> void:
	open = false
	_opened = false
	_grace_left = 0.0
	for i: int in KEY_COUNT:
		_key_down[i] = false
		_key_repeat[i] = 0.0


## Layer keys: one step on press, then `REPEAT_DELAY_S` and `REPEAT_RATE_S` while held.
func _collect_repeats(delta: float, keys: Array, actions: Array[String]) -> void:
	for i: int in KEY_COUNT:
		var held := i < keys.size() and bool(keys[i])
		if not held:
			_key_down[i] = false
			_key_repeat[i] = 0.0
			continue
		if not _key_down[i]:
			_key_down[i] = true
			_key_repeat[i] = REPEAT_DELAY_S
			actions.append(ACTIONS[i])
			continue
		_key_repeat[i] -= delta
		if _key_repeat[i] <= 0.0:
			_key_repeat[i] = REPEAT_RATE_S
			actions.append(ACTIONS[i])
