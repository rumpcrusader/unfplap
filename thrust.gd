extends RefCounted
## Pure depth/stroke tracker for the mouse thrust. No scene access.
##
## Depth is 0..1 and clamped. A stroke is continuous movement in one direction; it closes on a
## real direction reversal or after `STROKE_TIMEOUT_S` without movement. A thrust is an inward
## stroke (shallow -> deep) that reaches `THRUST_MIN_TRAVEL`.
##
## `move()` returns events for strokes it closed. `tick()` returns an event when an idle stroke
## times out. The caller classifies intensity and rhythm from the event; there is no score here.

const STROKE_TIMEOUT_S := 0.18
const THRUST_MIN_TRAVEL := 0.25
const MIN_THRUST_DURATION := 0.04
## A small pullback is hand jitter, not a new stroke. The reversal must travel this far from
## the stroke's peak before the stroke closes.
const REVERSAL_HYSTERESIS := 0.06
const MIN_MOVE := 0.0000001
const MAX_SAMPLES := 240
## Physical thrust strength: travel matters most, average stroke speed scales it. The 8.0
## reference makes a normal full stroke firm, a deliberately slow one soft, and a fast one
## rough. The value is calibrated against real stroke logs (normal full strokes land around
## 3.5–5.0 units/s). Peak speed is still logged and capped, but does not saturate scoring.
const STRENGTH_SPEED_REF := 8.0
const STRENGTH_SPEED_MIN := 0.15
const STRENGTH_SPEED_MAX := 1.5
const PEAK_SPEED_CAP := 2.0

var depth := 0.0

var _direction := 0
var _start_depth := 0.0
var _peak_depth := 0.0
var _start_time := 0.0
var _last_move := 0.0
var _samples: Array[Vector2] = []


static func mouse_to_depth(dy_pixels: float, pixels_per_full: float, up_is_deep: bool) -> float:
	var sign := -1.0 if up_is_deep else 1.0
	return sign * dy_pixels / maxf(1.0, pixels_per_full)


func reset() -> void:
	depth = 0.0
	_direction = 0
	_start_depth = 0.0
	_peak_depth = 0.0
	_start_time = 0.0
	_last_move = 0.0
	_samples.clear()


func move(amount: float, now: float) -> Array[Dictionary]:
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
		# Ignore a small pullback: the hand is still inside the same stroke.
		if absf(after - _peak_depth) < REVERSAL_HYSTERESIS:
			depth = after
			_append_sample(now, depth)
			_last_move = now
			return events
		var closed := _close(now)
		if not closed.is_empty():
			events.append(closed)
		_direction = 0

	if _direction == 0:
		_direction = direction
		_start_depth = before
		_peak_depth = before
		_start_time = now
		_samples.clear()
		_samples.append(Vector2(now, before))

	depth = after
	if _direction > 0:
		_peak_depth = maxf(_peak_depth, depth)
	else:
		_peak_depth = minf(_peak_depth, depth)
	_append_sample(now, depth)
	_last_move = now
	return events


## Live, in-progress stroke readings for presentation. `strength` mirrors the closed-stroke
## formula, but uses the travel and duration so far.
func live_travel() -> float:
	if _direction == 0:
		return 0.0
	return absf(depth - _start_depth)


func live_speed(now: float) -> float:
	var travel := live_travel()
	if travel <= 0.0:
		return 0.0
	return travel / maxf(0.001, now - _start_time)


func live_strength(now: float) -> float:
	var travel := live_travel()
	if travel <= 0.0:
		return 0.0
	var speed := live_speed(now)
	var speed_factor := clampf(speed / STRENGTH_SPEED_REF, STRENGTH_SPEED_MIN, STRENGTH_SPEED_MAX)
	return clampf(travel * speed_factor, 0.0, 1.0)


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
	var travel := absf(_peak_depth - _start_depth)
	var duration := maxf(0.001, now - _start_time)
	var samples := PackedVector2Array(_samples)
	if samples.is_empty() or samples[samples.size() - 1].x < now:
		samples.append(Vector2(now, _peak_depth))
	var peak_speed := 0.0
	for index: int in range(1, samples.size()):
		var dt := samples[index].x - samples[index - 1].x
		if dt <= 0.004:
			continue
		peak_speed = maxf(peak_speed, absf(samples[index].y - samples[index - 1].y) / dt)
	var speed := travel / duration
	if peak_speed <= 0.0:
		peak_speed = speed
	peak_speed = minf(peak_speed, speed * PEAK_SPEED_CAP)
	var speed_factor := clampf(speed / STRENGTH_SPEED_REF, STRENGTH_SPEED_MIN, STRENGTH_SPEED_MAX)
	var event := {
		"direction": direction,
		"start_depth": _start_depth,
		"end_depth": _peak_depth,
		"travel": travel,
		"duration": duration,
		"speed": speed,
		"peak_speed": peak_speed,
		"thrust": direction > 0 and travel >= THRUST_MIN_TRAVEL and duration >= MIN_THRUST_DURATION,
		"strength": clampf(travel * speed_factor, 0.0, 1.0),
	}
	_direction = 0
	_samples.clear()
	return event
