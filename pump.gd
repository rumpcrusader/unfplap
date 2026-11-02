extends RefCounted
## Pure depth/stroke tracker for the mouse pump. No scene access.
##
## Depth is 0..1 and clamped. A stroke is continuous movement in one direction; it closes on a
## direction reversal or after `STROKE_TIMEOUT_S` without movement. A pump is an inward stroke
## (shallow -> deep) that reaches `PUMP_MIN_TRAVEL`.
##
## `move()` returns events for strokes it closed. `tick()` returns an event when an idle stroke
## times out. `base_gain` is the weighted distance for that stroke; the caller applies speed and
## shape multipliers when the event arrives.

const STROKE_TIMEOUT_S := 0.18
const PUMP_MIN_TRAVEL := 0.25
const MIN_MOVE := 0.0000001
const MAX_SAMPLES := 240

var depth := 0.0

var _direction := 0
var _start_depth := 0.0
var _start_time := 0.0
var _last_move := 0.0
var _samples: Array[Vector2] = []
var _base_gain := 0.0


static func mouse_to_depth(dy_pixels: float, pixels_per_full: float, up_is_deep: bool) -> float:
	var sign := -1.0 if up_is_deep else 1.0
	return sign * dy_pixels / maxf(1.0, pixels_per_full)


func reset() -> void:
	depth = 0.0
	_direction = 0
	_start_depth = 0.0
	_start_time = 0.0
	_last_move = 0.0
	_samples.clear()
	_base_gain = 0.0


func move(amount: float, now: float, weight: Callable) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if absf(amount) < MIN_MOVE:
		return events
	var before := depth
	var after := clampf(before + amount, 0.0, 1.0)
	var applied := after - before
	if absf(applied) < MIN_MOVE:
		return events
	var direction := 1 if applied > 0.0 else -1

	if _direction != 0 and direction != _direction:
		_append_sample(now, before)
		var closed := _close(now)
		if not closed.is_empty():
			events.append(closed)
		_direction = 0

	if _direction == 0:
		_direction = direction
		_start_depth = before
		_start_time = now
		_samples.clear()
		_base_gain = 0.0
		_samples.append(Vector2(now, before))

	depth = after
	var middle := (before + after) * 0.5
	if weight.is_valid():
		_base_gain += absf(applied) * float(weight.call(middle))
	else:
		_base_gain += absf(applied)
	_samples.append(Vector2(now, depth))
	_last_move = maxf(_last_move, now)
	return events


func tick(now: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _direction == 0:
		return events
	if now - _last_move <= STROKE_TIMEOUT_S:
		return events
	_append_sample(now, depth)
	var closed := _close(now)
	if not closed.is_empty():
		events.append(closed)
	return events


func _append_sample(now: float, value: float) -> void:
	if _samples.is_empty():
		_samples.append(Vector2(now, value))
		return
	var last := _samples[_samples.size() - 1]
	if now < last.x:
		return
	if absf(now - last.x) < 0.000001 and absf(value - last.y) < 0.000001:
		return
	if _samples.size() >= MAX_SAMPLES:
		var reduced: Array[Vector2] = []
		for index in range(0, _samples.size(), 2):
			reduced.append(_samples[index])
		_samples = reduced
	_samples.append(Vector2(now, value))


func _close(now: float) -> Dictionary:
	if _direction == 0:
		return {}
	var direction := _direction
	var travel := absf(depth - _start_depth)
	var duration := maxf(0.001, now - _start_time)
	var samples := PackedVector2Array(_samples)
	if samples.is_empty() or samples[samples.size() - 1].x < now:
		samples.append(Vector2(now, depth))
	var event := {
		"direction": direction,
		"start_depth": _start_depth,
		"end_depth": depth,
		"travel": travel,
		"duration": duration,
		"speed": travel / duration,
		"samples": samples,
		"base_gain": _base_gain,
		"pump": direction > 0 and travel >= PUMP_MIN_TRAVEL,
	}
	_direction = 0
	_samples.clear()
	_base_gain = 0.0
	return event
