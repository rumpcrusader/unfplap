extends RefCounted
## Per-mare tail seat exceptions.
##
## The automatic seat is the game's exact reference anchor. An exception stores a Y/Z offset from
## that anchor, in metres, plus an optional dock-only distance, under `anatomy.tail_seat.<id>`:
##
##   "tail_seat": {"minuette": {"offset_y": 0.012, "offset_z": -0.003,
##                               "dock_y": -0.008, "dock_scale": 1.06}}
##
## Only non-default keys are written, so an empty offset removes the row. `dock_y` moves the
## standard dock toward (+) or away from (-) the tail without moving the tail itself.
## `dock_scale` scales the dock about its base ring (1.0 is the authored size).

const KEYS := ["offset_y", "offset_z"]
const DOCK_KEY := "dock_y"
const DOCK_SCALE_KEY := "dock_scale"
const DOCK_SCALE_MIN := 0.05
const DOCK_SCALE_MAX := 4.0
const EPSILON := 0.000001


## Read one stored row. Missing, malformed and non-finite values are zero.
static func read(row: Variant) -> Vector2:
	var out := Vector2.ZERO
	if not row is Dictionary:
		return out
	for i in KEYS.size():
		var key: String = KEYS[i]
		if not (row as Dictionary).has(key):
			continue
		var value: Variant = (row as Dictionary)[key]
		if not (value is float or value is int):
			continue
		var number := float(value)
		if is_finite(number):
			out[i] = number
	return out


## Accept a Vector2, a stored row or a malformed value; always return a finite pair.
static func sanitize(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	var out := fallback if fallback.is_finite() else Vector2.ZERO
	if value is Vector2:
		out = value
	elif value is Dictionary:
		out = read(value)
	if not is_finite(out.x):
		out.x = fallback.x if is_finite(fallback.x) else 0.0
	if not is_finite(out.y):
		out.y = fallback.y if is_finite(fallback.y) else 0.0
	return out


## Store only the components that differ from the exact reference.
static func diff(value: Vector2) -> Dictionary:
	var out: Dictionary = {}
	if absf(value.x) > EPSILON:
		out[KEYS[0]] = value.x
	if absf(value.y) > EPSILON:
		out[KEYS[1]] = value.y
	return out


static func same(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= EPSILON and absf(a.y - b.y) <= EPSILON


## One mare's dock-only distance, in metres. Missing, malformed and non-finite values are zero.
static func dock(row: Variant) -> float:
	if not row is Dictionary:
		return 0.0
	var value: Variant = (row as Dictionary).get(DOCK_KEY)
	if not (value is float or value is int):
		return 0.0
	var number := float(value)
	return number if is_finite(number) else 0.0


## Store only a non-zero dock distance; zero removes the key.
static func dock_diff(value: float) -> Dictionary:
	var number := value if is_finite(value) else 0.0
	if absf(number) <= EPSILON:
		return {}
	return {DOCK_KEY: number}


static func same_dock(a: float, b: float) -> bool:
	return absf(a - b) <= EPSILON


static func dock_text(value: float) -> String:
	return "dock=%+.0fmm" % (value * 1000.0)


## One mare's dock scale. Missing, malformed and non-finite values are 1.0; the floor keeps a
## hand-edited zero from collapsing the cuff.
static func dock_scale(row: Variant) -> float:
	if not row is Dictionary:
		return 1.0
	var value: Variant = (row as Dictionary).get(DOCK_SCALE_KEY)
	if not (value is float or value is int):
		return 1.0
	var number := float(value)
	if not is_finite(number):
		return 1.0
	return clampf(number, DOCK_SCALE_MIN, DOCK_SCALE_MAX)


## Store only a scale that differs from the authored 1.0; 1.0 removes the key.
static func dock_scale_diff(value: float) -> Dictionary:
	var number := dock_scale({DOCK_SCALE_KEY: value})
	if absf(number - 1.0) <= EPSILON:
		return {}
	return {DOCK_SCALE_KEY: number}


static func same_scale(a: float, b: float) -> bool:
	return absf(a - b) <= EPSILON


static func scale_text(value: float) -> String:
	return "scale=%.2fx" % value


## The exact reference anchor plus the global tail lift and one mare's exception. The reference
## carries X.
static func target(reference: Vector3, offset: Vector2, lift := 0.0) -> Vector3:
	return Vector3(reference.x, reference.y + lift + offset.x, reference.z + offset.y)


## The translation needed to put an anchor on the reference plus its lift and exception.
static func delta(anchor: Vector3, reference: Vector3, offset: Vector2, lift := 0.0) -> Vector3:
	return target(reference, offset, lift) - anchor


static func text(offset: Vector2) -> String:
	return "y=%+.0fmm z=%+.0fmm" % [offset.x * 1000.0, offset.y * 1000.0]
