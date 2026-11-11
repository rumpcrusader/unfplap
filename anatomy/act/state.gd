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
