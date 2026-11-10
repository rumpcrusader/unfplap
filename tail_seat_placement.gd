extends RefCounted
## Per-mare tail seat exceptions.
##
## The automatic seat is the game's exact reference anchor. An exception stores only a Y/Z
## offset from that anchor, in metres, under `anatomy.tail_seat.<id>` in settings.json:
##
##   "tail_seat": {"minuette": {"offset_y": 0.012, "offset_z": -0.003}}
##
## Only non-zero keys are written, so an empty offset removes the row.

const KEYS := ["offset_y", "offset_z"]
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


## The exact reference anchor plus the global tail lift and one mare's exception. The reference
## carries X.
static func target(reference: Vector3, offset: Vector2, lift := 0.0) -> Vector3:
	return Vector3(reference.x, reference.y + lift + offset.x, reference.z + offset.y)


## The translation needed to put an anchor on the reference plus its lift and exception.
static func delta(anchor: Vector3, reference: Vector3, offset: Vector2, lift := 0.0) -> Vector3:
	return target(reference, offset, lift) - anchor


static func text(offset: Vector2) -> String:
	return "y=%+.0fmm z=%+.0fmm" % [offset.x * 1000.0, offset.y * 1000.0]
