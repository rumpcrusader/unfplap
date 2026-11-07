extends RefCounted
## Pure depth/stroke tracker for the mouse thrust. No scene access.
##
## Depth is 0..1 and clamped. A stroke is continuous movement in one direction; it closes on a
## real direction reversal or after `STROKE_TIMEOUT_S` without movement. A thrust is an inward
## stroke (shallow -> deep) that reaches `THRUST_MIN_TRAVEL`.
##
## `move()` returns events for strokes it closed and for the moment the inward stroke reaches its
## bottom. `tick()` returns those too when an idle stroke holds or times out. The caller drives
## the presentation from the `impact` event and the score from the `stroke` event.

const STROKE_TIMEOUT_S := 0.18
## A thrust must travel this far inward. `REVERSAL_HYSTERESIS` (0.06) is subtracted from every
## auto stroke after the first, so the 20% auto peak reaches 0.14 travel and still counts.
const THRUST_MIN_TRAVEL := 0.12
const MIN_THRUST_DURATION := 0.04
## A small pullback is hand jitter, not a new stroke. The reversal must travel this far from
## the stroke's peak before the stroke closes.
const REVERSAL_HYSTERESIS := 0.06
## The impact fires at the bottom of the inward stroke, not when it closes, so the plap and the
## body react with the motion. The stall clock follows the peak, so a pixel of jitter at the
## bottom cannot postpone it, and 40 ms covers a deliberate pause without the old 180 ms wait.
const IMPACT_STALL_S := 0.04
const IMPACT_STALL_MIN_TRAVEL := 0.001
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
## Rump/tail wobble: a closed full stroke moves the flank the same at any speed. The soft band
## fades the gentlest strokes almost out instead of letting the 0.3 stock floor keep them alive.
const JIGGLE_TRAVEL_REF := 0.9
const JIGGLE_SOFT_FLOOR := 0.04
const JIGGLE_SOFT_LOW := 0.18
const JIGGLE_SOFT_HIGH := 0.42
## His skin meets her coat in the last few centimetres of the reachable stroke. The margin is a
## distance, so the contact point follows the shaft length, the `Pelvis gap` and the pose's reach
## instead of being a fixed depth fraction.
const CONTACT_COMPRESSION_M := 0.025

var depth := 0.0

var _direction := 0
var _start_depth := 0.0
var _peak_depth := 0.0
var _start_time := 0.0
var _last_move := 0.0
## The depth at the last meaningful inward progress and when it happened. The impact stall clock
## measures from here, not from `_last_move`, so jitter that does not deepen the stroke is ignored.
var _progress_depth := 0.0
var _progress_time := 0.0
## True once this stroke's impact has fired (or when it is an outward stroke that needs none).
var _impact_fired := true
var _samples: Array[Vector2] = []


## Vertical mouse motion as hip travel in metres. `pixels_per_cm` is the player's sensitivity, so
## a full stroke is the shaft's length in centimetres, not a fixed pixel count.
static func pixels_to_metres(dy_pixels: float, pixels_per_cm: float, up_is_deep: bool) -> float:
	var sign := -1.0 if up_is_deep else 1.0
	return sign * dy_pixels / (maxf(1.0, pixels_per_cm) * 100.0)


## The public 0..1 depth from the measured penetration. Anything behind her lips — the `back_out`
## standoff included — is zero depth, so the standoff never dilutes the stroke scale.
static func penetration_to_depth(penetration_m: float, reach_m: float) -> float:
	if reach_m <= 0.0:
		return 0.0
	return clampf(penetration_m / reach_m, 0.0, 1.0)


## Wobble amount 0..1 from a closed stroke. Travel sets the amount, so a full stroke moves the
## flank the same at any speed; the soft band fades the gentlest thrusts to almost nothing.
static func jiggle_amount(travel: float, strength: float) -> float:
	var depth_factor := clampf(travel / JIGGLE_TRAVEL_REF, 0.0, 1.0)
	var soft := smoothstep(JIGGLE_SOFT_LOW, JIGGLE_SOFT_HIGH, clampf(strength, 0.0, 1.0))
	return depth_factor * lerpf(JIGGLE_SOFT_FLOOR, 1.0, soft)


## How much of his skin actually meets her coat at a stroke bottom, 0..1. It is 1 at the model's
## deepest point and 0 once the stroke stopped `CONTACT_COMPRESSION_M` short of it, so a shallow
## thrust has no body slap while a bottomed-out one does, whatever the shaft length or gap is.
static func contact_amount(penetration_m: float, reach_m: float) -> float:
	var remaining := maxf(reach_m - penetration_m, 0.0)
	return 1.0 - smoothstep(0.0, maxf(CONTACT_COMPRESSION_M, 0.001), remaining)


func reset() -> void:
	depth = 0.0
	_direction = 0
	_start_depth = 0.0
	_peak_depth = 0.0
	_start_time = 0.0
	_last_move = 0.0
	_progress_depth = 0.0
	_progress_time = 0.0
	_impact_fired = true
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
		# The bottom is here: fire the impact now, before the hysteresis wait, so the plap and the
		# body land with the motion instead of when the stroke finally closes.
		if _direction > 0 and not _impact_fired:
			var impact := _impact_event()
			if not impact.is_empty():
				events.append(impact)
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
		_progress_depth = before
		_start_time = now
		_progress_time = now
		_impact_fired = direction < 0
		_samples.clear()
		_samples.append(Vector2(now, before))

	depth = after
	if _direction > 0:
		if depth > _peak_depth:
			_peak_depth = depth
			# Only a real gain counts as progress; pixel jitter at the bottom never resets this.
			if depth - _progress_depth >= IMPACT_STALL_MIN_TRAVEL:
				_progress_depth = depth
				_progress_time = now
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
	# A held bottom fires the impact after the short stall, long before the stroke times out.
	if _direction > 0 and not _impact_fired and now - _progress_time >= IMPACT_STALL_S:
		var impact := _impact_event()
		if not impact.is_empty():
			events.append(impact)
	if now - _last_move <= STROKE_TIMEOUT_S:
		return events
	_append_sample(now, depth)
	var closed := _close(now)
	if not closed.is_empty():
		events.append(closed)
	return events


## The bottom of the stroke, as a presentation event. Strength and travel come from the peak
## itself (`_progress_time`), so a dwell before the reversal does not dilute the speed. A stroke
## that never reached a real thrust leaves `_impact_fired` false and simply gets none.
func _impact_event() -> Dictionary:
	var travel := absf(_peak_depth - _start_depth)
	if travel < THRUST_MIN_TRAVEL:
		return {}
	# A stroke that reached the bottom in one event has no peak duration; the floor keeps its
	# speed factor finite without rejecting a genuinely fast thrust.
	var duration := maxf(MIN_THRUST_DURATION, _progress_time - _start_time)
	_impact_fired = true
	var speed := travel / duration
	var speed_factor := clampf(speed / STRENGTH_SPEED_REF, STRENGTH_SPEED_MIN, STRENGTH_SPEED_MAX)
	return {
		"kind": "impact",
		"direction": 1,
		"start_depth": _start_depth,
		"end_depth": _peak_depth,
		"travel": travel,
		"duration": duration,
		"speed": speed,
		"peak_speed": speed,
		"strength": clampf(travel * speed_factor, 0.0, 1.0),
	}


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
		"kind": "stroke",
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
