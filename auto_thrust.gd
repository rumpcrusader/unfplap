extends RefCounted
## Pure auto-thrust depth generator. No scene access.
##
## A cycle is one thrust: the phase advances at `pace` cycles per second and the output follows
## `wave(shape, phase)` from a bottom to `max_depth` and back. The runtime feeds the difference
## between successive outputs into the same `thrust.gd` tracker the mouse uses, so strength,
## readiness, intensity, pattern, audio, camera and presentation all stay unchanged.
##
## `max_depth` is the requested peak, set by the mouse. `_amplitude` is the smoothed peak the
## waveform actually uses, so scrolling depth does not inject a depth-speed spike.
##
## `shape` is the experiment switch: every shape starts and ends at the bottom and stays in 0..1,
## so a shape can never look like a jump or an invalid stroke to the tracker.

## Wheel bounds. Keep these equal to `settings.gd`'s `auto_thrust.*` bounds.
const PACE_MIN := 1.0
const PACE_MAX := 3.75
## One mouse-wheel notch while auto owns the stroke. Fixed: it is not a setting.
const PACE_STEP := 0.25
## `thrust.gd` closes a reversal only after `REVERSAL_HYSTERESIS` (0.06), so every automatic
## stroke after the first starts 0.06 above the bottom. The minimum peak keeps that stroke at
## or above `THRUST_MIN_TRAVEL` (0.12): 0.20 - 0.06 = 0.14.
const DEPTH_MIN := 0.20
const DEPTH_MAX := 1.0
## Low-pass on the requested peak depth. The shape already eases the ends of a stroke; this only
## keeps a mouse depth change from stepping the current depth in one frame.
const DEPTH_SMOOTH_S := 0.18
## Phase samples used to enter a running shape at the hand's depth without a jump.
const PHASE_SAMPLES := 64
## Every supported stroke waveform.
const SHAPES := ["cosine", "thrust", "tease", "saw", "hold", "double"]
## The narrowest depth band that still produces a real thrust: `THRUST_MIN_TRAVEL` (0.12) plus
## the reversal hysteresis (0.06) that the next stroke loses at the bottom. A narrower band would
## silently stop scoring.
const MIN_BAND := 0.18

var active := false
## Thrusts per second. One cycle is one inward stroke. Matches the declared default; `reset()`
## overwrites it with the configured act-start value.
var pace := 1.0
## Requested bottom and peak depth, 0..1 of the full tracker range. The stroke travels
## `max_depth - min_depth`, so the band must stay at least `MIN_BAND` wide.
var min_depth := 0.0
var max_depth := 0.5
## Stroke waveform id, one of `SHAPES`.
var shape := "cosine"

## Smoothed band the waveform actually uses, so a depth nudge does not step the stroke.
var _low := 0.0
var _amplitude := 0.9
var _phase := 0.0
var _depth := 0.0


## Back to the act-start defaults. Called by `runtime._reset_thrust_state()`.
func reset(default_pace: float, default_depth: float, default_shape := "cosine",
		default_min := 0.0) -> void:
	active = false
	pace = clampf(default_pace, PACE_MIN, PACE_MAX)
	shape = default_shape if SHAPES.has(default_shape) else "cosine"
	min_depth = clampf(default_min, 0.0, DEPTH_MAX - MIN_BAND)
	max_depth = clampf(maxf(default_depth, min_depth + MIN_BAND), DEPTH_MIN, DEPTH_MAX)
	min_depth = clampf(min_depth, 0.0, max_depth - MIN_BAND)
	_low = min_depth
	_amplitude = max_depth - min_depth
	_phase = 0.0
	_depth = min_depth


## Turn auto on from the hand's current depth instead of snapping to the cycle bottom. A peak
## shallower than his current depth would jump him backwards, so the peak is raised to match.
func begin(current_depth: float) -> void:
	active = true
	max_depth = clampf(maxf(max_depth, current_depth), DEPTH_MIN, DEPTH_MAX)
	min_depth = clampf(min_depth, 0.0, max_depth - MIN_BAND)
	var band := maxf(max_depth - min_depth, 0.001)
	var ratio := clampf((current_depth - min_depth) / band, 0.0, 1.0)
	_low = min_depth
	_amplitude = band
	_phase = phase_for(shape, ratio)
	_depth = clampf(current_depth, min_depth, max_depth)


## Advance one frame and return the absolute depth to feed the tracker.
func step(delta: float) -> float:
	if not active:
		return _depth
	var alpha := 1.0 - exp(-delta / maxf(DEPTH_SMOOTH_S, 0.001))
	_low = lerpf(_low, min_depth, alpha)
	_amplitude = lerpf(_amplitude, max_depth - min_depth, alpha)
	_phase = fposmod(_phase + pace * delta, 1.0)
	_depth = _low + maxf(_amplitude, 0.0) * wave(shape, _phase)
	return _depth


func stop() -> void:
	active = false


## Last depth the generator produced. `begin()` sets it to the hand's depth.
func current_depth() -> float:
	return _depth


func nudge_pace(amount: float) -> void:
	pace = clampf(pace + amount, PACE_MIN, PACE_MAX)


## Raise or lower the peak. The band stays at least `MIN_BAND` wide by pushing the bottom down.
func nudge_depth(amount: float) -> void:
	max_depth = clampf(max_depth + amount, maxf(DEPTH_MIN, min_depth + MIN_BAND), DEPTH_MAX)
	min_depth = minf(min_depth, max_depth - MIN_BAND)


## Raise or lower the bottom. The band stays at least `MIN_BAND` wide by pushing the peak up.
func nudge_min(amount: float) -> void:
	min_depth = clampf(min_depth + amount, 0.0, DEPTH_MAX - MIN_BAND)
	max_depth = maxf(max_depth, min_depth + MIN_BAND)


## Next shape in `SHAPES`, wrapping. Used by the hold-X `Z` key.
static func next_shape(name: String) -> String:
	var index := SHAPES.find(name)
	return SHAPES[(index + 1) % SHAPES.size()] if index >= 0 else SHAPES[0]


## Live `Auto shape` change; the current cycle keeps its phase and continues in the new shape.
func set_shape(name: String) -> void:
	if SHAPES.has(name):
		shape = name


## The stroke waveform: 0 is the bottom, 0.5 the top, 1 the bottom again. Every shape starts and
## ends at zero and stays in 0..1, so the tracker only sees a stroke's depth delta.
static func wave(name: String, phase: float) -> float:
	var p := fposmod(phase, 1.0)
	match name:
		"thrust":
			return _stroke(p, 0.35)
		"tease":
			return _stroke(p, 0.65)
		"saw":
			return _saw(p)
		"hold":
			return _hold(p)
		"double":
			return _stroke(fposmod(p * 2.0, 1.0), 0.5) * (1.0 if p < 0.5 else 0.6)
	return 0.5 - 0.5 * cos(TAU * p)


## One eased stroke. `duty` is the share of the cycle spent going in, so `thrust` drives in fast
## and out slow, `tease` the other way, and 0.5 is the symmetric cosine.
static func _stroke(phase: float, duty: float) -> float:
	var d := clampf(duty, 0.05, 0.95)
	if phase < d:
		return 0.5 - 0.5 * cos(PI * phase / d)
	return 0.5 + 0.5 * cos(PI * (phase - d) / (1.0 - d))


## Constant speed in and out, abrupt at both ends. The least natural, the easiest to feel.
static func _saw(phase: float) -> float:
	if phase < 0.5:
		return phase / 0.5
	return 1.0 - (phase - 0.5) / 0.5


## Quick in, a short dwell at full depth, quick out.
static func _hold(phase: float) -> float:
	if phase < 0.30:
		return 0.5 - 0.5 * cos(PI * phase / 0.30)
	if phase < 0.50:
		return 1.0
	return 0.5 + 0.5 * cos(PI * (phase - 0.50) / 0.50)


## The cycle phase whose depth is closest to `ratio`. Numeric, so every shape — including the
## two-peak `double` — can be entered at the hand's depth without a jump. The first match wins,
## so it enters on the inward half.
static func phase_for(name: String, ratio: float) -> float:
	var wanted := clampf(ratio, 0.0, 1.0)
	var best_distance := INF
	var best_phase := 0.0
	for i: int in PHASE_SAMPLES:
		var p := float(i) / float(PHASE_SAMPLES)
		var distance := absf(wave(name, p) - wanted)
		if distance < best_distance:
			best_distance = distance
			best_phase = p
	return best_phase
