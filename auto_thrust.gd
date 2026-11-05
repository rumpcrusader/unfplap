extends RefCounted
## Pure auto-thrust depth generator. No scene access.
##
## A cycle is one thrust: the phase advances at `pace` cycles per second and the output follows
## a raised cosine from 0 to `max_depth` and back. The runtime feeds the difference between
## successive outputs into the same `thrust.gd` tracker the mouse uses, so strength, readiness,
## intensity, pattern, audio, camera and presentation all stay unchanged.
##
## `max_depth` is the requested peak, set by the mouse. `_amplitude` is the smoothed peak the
## waveform actually uses, so scrolling depth does not inject a depth-speed spike.

## Wheel bounds. Keep these equal to `tunables_schema.gd`'s `auto_thrust.*` `user_num` bounds.
const PACE_MIN := 0.5
const PACE_MAX := 5.0
## `thrust.gd` closes a reversal only after `REVERSAL_HYSTERESIS` (0.06), so every automatic
## stroke after the first starts 0.06 above the bottom. The minimum peak keeps that stroke at
## or above `THRUST_MIN_TRAVEL` (0.25): 0.32 - 0.06 = 0.26.
const DEPTH_MIN := 0.32
const DEPTH_MAX := 1.0
## Low-pass on the requested peak depth. The cosine already eases the ends of a stroke; this
## only keeps a mouse depth change from stepping the current depth in one frame.
const DEPTH_SMOOTH_S := 0.18

var active := false
## Thrusts per second. One cycle is one inward stroke.
var pace := 1.5
## Requested peak depth, 0..1 of the full tracker range.
var max_depth := 0.9

var _amplitude := 0.9
var _phase := 0.0
var _depth := 0.0


## Back to the act-start defaults. Called by `runtime._reset_thrust_state()`.
func reset(default_pace: float, default_depth: float) -> void:
	active = false
	pace = clampf(default_pace, PACE_MIN, PACE_MAX)
	max_depth = clampf(default_depth, DEPTH_MIN, DEPTH_MAX)
	_amplitude = max_depth
	_phase = 0.0
	_depth = 0.0


## Turn auto on from the hand's current depth instead of snapping to the cycle bottom. A peak
## shallower than his current depth would jump him backwards, so the peak is raised to match.
func begin(current_depth: float) -> void:
	active = true
	max_depth = clampf(maxf(max_depth, current_depth), DEPTH_MIN, DEPTH_MAX)
	_amplitude = max_depth
	var ratio := clampf(current_depth / maxf(max_depth, 0.0001), 0.0, 1.0)
	# The raised cosine has two phases for one depth; the 0..0.5 half is the inward stroke.
	_phase = acos(clampf(1.0 - 2.0 * ratio, -1.0, 1.0)) / TAU
	_depth = clampf(current_depth, 0.0, max_depth)


## Advance one frame and return the absolute depth to feed the tracker.
func step(delta: float) -> float:
	if not active:
		return _depth
	var alpha := 1.0 - exp(-delta / maxf(DEPTH_SMOOTH_S, 0.001))
	_amplitude = lerpf(_amplitude, max_depth, alpha)
	_phase = fposmod(_phase + pace * delta, 1.0)
	_depth = _amplitude * (0.5 - 0.5 * cos(TAU * _phase))
	return _depth


func stop() -> void:
	active = false


## Last depth the generator produced. `begin()` sets it to the hand's depth.
func current_depth() -> float:
	return _depth


func nudge_pace(amount: float) -> void:
	pace = clampf(pace + amount, PACE_MIN, PACE_MAX)


func nudge_depth(amount: float) -> void:
	max_depth = clampf(max_depth + amount, DEPTH_MIN, DEPTH_MAX)
