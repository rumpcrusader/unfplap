extends RefCounted
## Shared, pure act motion math: lean mapping and travel, pose action mapping, glance fade and
## hip-phase smoothing. The camera, caress and runtime controllers call these; none touch the
## scene.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const LEAN_RAMP_SECONDS := 0.5
const LEAN_RETURN_SECONDS := 1.6
const LEAN_FORWARD_M := 0.24
## Backing off is half the forward travel so Anon cannot pull too far from her.
const LEAN_BACK_M := 0.08
const LEAN_SIDE_M := 0.18
const LEAN_PITCH_DEG := 6.0
const LEAN_ROLL_DEG := 1.5
const LEAN_SIDE_ROLL_DEG := 8.0
const LEAN_SIDE_YAW_DEG := 3.0
const HOLD_SWAY_FORWARD := 0.010
const HOLD_SWAY_SIDE := 0.0
const LEAN_FIRE := 0.75
const LEAN_RELEASE := 0.60
const HIP_SMOOTH_S := 0.04
const GLANCE_BACK_FADE := 0.45
## Yaw limit for a look-back glance. She turns farther over her shoulder than a normal glance.
const GLANCE_BACK_YAW := 1.62


## Pure mapping for tests: vector x is side, y is forward. Q/E contribute both.
static func lean_targets(move_x: float, move_y: float) -> Vector2:
	var side := clampf(move_x, -1.0, 1.0)
	var forward := clampf(-move_y + absf(side), -1.0, 1.0)
	return Vector2(forward, side)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size;
## smaller ponies need a longer lean to reach the same place. Canon (`0.66`) is +34%.
static func lean_size_scale_for(size_scale: float) -> float:
	return clampf(2.0 - size_scale, 0.75, 1.5)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size.
static func lean_distance(forward: float, size_scale := 1.0) -> float:
	var metres := LEAN_FORWARD_M if forward >= 0.0 else LEAN_BACK_M
	return metres * forward * size_scale


## The lean always holds a released position. `return_to_zero` is only used by the explicit
## S shoulder recentre; forced end-of-act returns bypass this helper.
static func lean_step(current: float, target: float, delta: float,
		return_to_zero := false) -> float:
	if is_zero_approx(target):
		if not return_to_zero:
			return current
		return move_toward(current, 0.0, delta / maxf(LEAN_RETURN_SECONDS, 0.001))
	return move_toward(current, target, delta / maxf(LEAN_RAMP_SECONDS, 0.001))


## Pose support for the threshold-triggered side action.
static func lean_action_kind(pose: String, side: float) -> String:
	if pose == CATALOG.MISSIONARY and side < 0.0:
		return "kiss"
	if pose == CATALOG.STANDING:
		return "reach"
	return ""


## Multiplier-based glance-back speed. Higher speed means a shorter fade.
static func glance_back_fade_for(speed: float) -> float:
	return GLANCE_BACK_FADE / clampf(speed, 0.25, 3.0)


## Pure hip smoothing for tests: depth is the input, this only removes single-frame steps.
static func hip_phase_step(current: float, depth_value: float, delta: float) -> float:
	var alpha := 1.0 - exp(-delta / maxf(HIP_SMOOTH_S, 0.001))
	return lerpf(current, clampf(depth_value, 0.0, 1.0), alpha)
