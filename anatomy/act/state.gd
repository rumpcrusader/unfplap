extends RefCounted
## Pure act-anatomy decisions: the hole/oral mix, the shared shape drive and the wink scheduler.
## It takes plain numbers and returns plain numbers; the per-act controller owns the scene calls.
##
## See `docs/anatomy.md` (`## Act anatomy`).

const PULLED_OUT_PHASE := 0.35


## The non-oral, non-anal share of the shape drive. 1 is the vulva at rest, 0 is fully turned or
## fully anal.
static func front(hole_mix: float, oral_mix: float) -> float:
	return (1.0 - clampf(hole_mix, 0.0, 1.0)) * (1.0 - clampf(oral_mix, 0.0, 1.0))


## The hole-swap mix after one tick. `anal` selects the anal opening; the swap eases over
## `swap_s` seconds.
static func hole_mix_step(current: float, anal: bool, swap_s: float, delta: float) -> float:
	return move_toward(current, 1.0 if anal else 0.0, delta / maxf(swap_s, 0.001))


## The `closed` blend-shape value while the act drives the lips. 1 is closed, 0 is open. The
## lips keep a grip through the climax instead of snapping shut on nothing.
static func closed_for(fill: float, hole_mix: float, oral_mix: float, rest_open: float) -> float:
	return 1.0 - (1.0 - rest_open * (1.0 - clampf(fill, 0.0, 1.0))) \
		* front(hole_mix, oral_mix)


## The mouth anchor after one tick. Inactive: the anchor blends back from the last mouth point to
## the opening the turn started from as `mix` falls, so the part returns with her. Active but still
## turning: the opening holds, so the part does not chase her rump through the arc. Active and
## settled: the anchor eases to the live mouth under `rate`.
static func oral_anchor_step(anchor: Vector3, mouth: Vector3, opening: Vector3, mix: float,
		active: bool, rate: float, delta: float) -> Vector3:
	if not opening.is_finite():
		return anchor
	if not active:
		if not anchor.is_finite():
			return opening
		return opening.lerp(anchor, clampf(mix, 0.0, 1.0))
	if mix < 1.0 or not mouth.is_finite():
		return opening
	if not anchor.is_finite():
		return mouth
	return anchor.lerp(mouth, 1.0 - exp(-maxf(rate, 0.0) * delta))


## One open/close pulse layered on the live shape drive, from the remaining seconds of the beat.
static func wink_beat(remaining: float, total: float, beats: float) -> float:
	if total <= 0.0 or beats <= 0.0:
		return 0.0
	return absf(sin((1.0 - clampf(remaining / total, 0.0, 1.0)) * PI * beats))


## 0: nothing. 1: the tip is at her lips. 2: she has climaxed and he is below the pulled-out
## phase.
static func wink_mode(depth: float, touching: bool, climaxes: int,
		pulled_out_phase := PULLED_OUT_PHASE) -> int:
	if depth >= pulled_out_phase:
		return 0
	if touching:
		return 1
	return 2 if climaxes >= 1 else 0
