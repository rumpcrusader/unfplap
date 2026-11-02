extends RefCounted
## Pure depth/stroke tracker for the mouse pump. No scene access.
##
## Depth is 0..1 and clamped. A stroke is continuous movement in one direction; it closes on a
## direction reversal or after `STROKE_TIMEOUT_S` without movement. A pump is an inward stroke
## (shallow -> deep) that reaches `PUMP_MIN_TRAVEL`.
##
## `move()` returns events for strokes it closed. `tick()` returns an event when an idle stroke
## times out. The caller classifies intensity and rhythm from the event; there is no score here.

const STROKE_TIMEOUT_S := 0.18
const PUMP_MIN_TRAVEL := 0.25
const MIN_MOVE := 0.0000001
const MAX_SAMPLES := 240
## Physical thrust strength: travel matters most, peak speed gives a fast thrust more impact.
## The 0.35 floor keeps a slow deliberate stroke visible; the 1.5 ceiling stops flick input
## from saturating every value.
const STRENGTH_SPEED_REF := 1.0
const STRENGTH_SPEED_MIN := 0.35
const STRENGTH_SPEED_MAX := 1.5

var depth := 0.0

var _direction := 0
var _start_depth := 0.0
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
		_samples.append(Vector2(now, before))

	depth = after
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
	var peak_speed := 0.0
	for index: int in range(1, samples.size()):
		var dt := samples[index].x - samples[index - 1].x
		if dt <= 0.000001:
			continue
		peak_speed = maxf(peak_speed, absf(samples[index].y - samples[index - 1].y) / dt)
	var speed := travel / duration
	if peak_speed <= 0.0:
		peak_speed = speed
	var speed_factor := clampf(peak_speed / STRENGTH_SPEED_REF, STRENGTH_SPEED_MIN, STRENGTH_SPEED_MAX)
	var event := {
		"direction": direction,
		"start_depth": _start_depth,
		"end_depth": depth,
		"travel": travel,
		"duration": duration,
		"speed": speed,
		"peak_speed": peak_speed,
		"pump": direction > 0 and travel >= PUMP_MIN_TRAVEL,
		"strength": clampf(travel * speed_factor, 0.0, 1.0),
	}
	_direction = 0
	_samples.clear()
	return event
