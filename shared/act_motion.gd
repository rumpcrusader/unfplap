extends RefCounted
## Shared, pure act motion math: lean mapping and travel, pose action mapping, glance fade and
## hip-phase smoothing. The camera, caress and runtime controllers call these; none touch the
## scene.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const LEAN_RAMP_SECONDS := 0.5
const LEAN_RETURN_SECONDS := 1.6
const LEAN_FORWARD_M := 0.24
const LEAN_SIDE_M := 0.18
const LEAN_PITCH_DEG := 6.0
const LEAN_ROLL_DEG := 1.5
const LEAN_SIDE_ROLL_DEG := 8.0
const LEAN_SIDE_YAW_DEG := 3.0
const HOLD_SWAY_FORWARD := 0.010
const LEAN_FIRE := 0.75
const LEAN_RELEASE := 0.60
const HIP_SMOOTH_S := 0.04
const GLANCE_BACK_FADE := 0.45
## Yaw limit for a look-back glance. She turns farther over her shoulder than a normal glance.
const GLANCE_BACK_YAW := 1.62
## The kiss lean's own distances, in metres at the reference height; callers scale by the actor.
const KISS_LEAN_M := 0.27
const KISS_LEAN_SIDE_M := 0.18
const KISS_LEAN_DROP_M := 0.035
## The camera's yaw toward her at a full kiss lean, in degrees.
const KISS_CAMERA_YAW_DEG := 10.0
## The lean the standing and missionary keys ask for, in the leaning axis' own units.
const STANDING_KISS_LEAN := 0.90
const MISSIONARY_KISS_LEAN := 0.90


## Pure mapping for tests: vector x is side, y is forward. Q/E contribute both.
static func lean_targets(move_x: float, move_y: float) -> Vector2:
	var side := clampf(move_x, -1.0, 1.0)
	var forward := clampf(-move_y + absf(side), -1.0, 1.0)
	return Vector2(forward, side)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size;
## smaller ponies need a longer lean to reach the same place. Canon (`0.66`) is +34%.
static func lean_size_scale_for(size_scale: float) -> float:
	return clampf(2.0 - size_scale, 0.75, 1.5)


## Only a forward lean travels. Backing off is a shoulder recentre, not camera travel.
static func lean_distance(forward: float, size_scale := 1.0) -> float:
	return LEAN_FORWARD_M * maxf(forward, 0.0) * size_scale


## The lean always holds a released position. `return_to_zero` is only used by the explicit
## S shoulder recentre; forced end-of-act returns bypass this helper.
static func lean_step(current: float, target: float, delta: float,
		return_to_zero := false) -> float:
	if is_zero_approx(target):
		if not return_to_zero:
			return current
		return move_toward(current, 0.0, delta / maxf(LEAN_RETURN_SECONDS, 0.001))
	return move_toward(current, target, delta / maxf(LEAN_RAMP_SECONDS, 0.001))


## The side-lean action a pose profile fires at full lean. Kissing is not a lean action; both poses
## use the front/shoulder lean with F held.
static func lean_action_kind(profile: String, _side: float) -> String:
	if profile == CATALOG.STANDING:
		return "reach"
	return ""


## Whether the key and the lean ask for a kiss in this family. Pure, so the trigger is testable
## without a scene; `forward_down` is required because the lean map folds a side press into the
## forward axis.
static func kiss_wanted(family: String, key_down: bool, forward_down: bool,
		lean_side: float, lean_forward: float) -> bool:
	if not key_down:
		return false
	if family == "standing":
		return absf(lean_side) >= STANDING_KISS_LEAN
	if family == "bed":
		return forward_down and lean_forward >= MISSIONARY_KISS_LEAN
	return false


## Her head tilt is the opposite world side to his; a centred lean leaves the side to her.
static func kiss_pony_side(lean_side: float) -> float:
	if absf(lean_side) <= 0.001:
		return 0.0
	return signf(lean_side)


## The side travel blended by the amount; the camera and his hip share one implementation.
static func kiss_lateral_offset(lean_side: float, kiss_side: float, amount: float,
		size_scale: float, kiss_side_m: float) -> float:
	var blend := clampf(amount, 0.0, 1.0)
	var lean := LEAN_SIDE_M * lean_side * size_scale
	var kiss := kiss_side_m * kiss_side
	return lerpf(lean, kiss, blend)


## Multiplier-based glance-back speed. Higher speed means a shorter fade.
static func glance_back_fade_for(speed: float) -> float:
	return GLANCE_BACK_FADE / clampf(speed, 0.25, 3.0)


## Pure hip smoothing for tests: depth is the input, this only removes single-frame steps.
static func hip_phase_step(current: float, depth_value: float, delta: float) -> float:
	var alpha := 1.0 - exp(-delta / maxf(HIP_SMOOTH_S, 0.001))
	return lerpf(current, clampf(depth_value, 0.0, 1.0), alpha)
