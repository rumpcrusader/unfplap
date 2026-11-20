extends RefCounted
## Typed caress and smack payloads for the hands system. Contract: `docs/hands.md` (`## Typed view`).


## One body preset's caress-point offsets in metres, before the body scale reaches the oval radius only.
class CaressProfile extends RefCounted:
	var up: float
	var back: float
	var out: float

	func _init(up_m := 0.0, back_m := 0.0, out_m := 0.0) -> void:
		up = up_m
		back = back_m
		out = out_m

	func scaled(scale: float) -> CaressProfile:
		return CaressProfile.new(up * scale, back * scale, out * scale)


## One caress tick's accumulated contact time and the number of five-second actions it completed.
class TouchStep extends RefCounted:
	var seconds: float
	var events: int

	func _init(left := 0.0, count := 0) -> void:
		seconds = left
		events = count


## Nearest posed flank face to a point: the hit flag, the point, its normal, the distance and the
## triangle index. A miss leaves `hit` false and the rest at zero.
class FlankHit extends RefCounted:
	var hit := false
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var distance := 0.0
	var face := -1

	func _init(found := false, at := Vector3.ZERO, towards := Vector3.ZERO,
			range := 0.0, index := -1) -> void:
		hit = found
		point = at
		normal = towards
		distance = range
		face = index


## The smack's presentation values. The pose spec supplies the raw document; each default matches
## the constant its consumer used before the record.
class SmackPresentation extends RefCounted:
	var raise_m := 0.30
	var pitch_deg := 12.0
	var arc_m := 0.06
	var height_m := -0.03
	var hind_m := 0.10
	var raise_speed := 2.0
	var return_speed := 6.0

	static func from_dict(values: Dictionary) -> SmackPresentation:
		var out := SmackPresentation.new()
		out.raise_m = float(values.get("raise_m", out.raise_m))
		out.pitch_deg = float(values.get("pitch_deg", out.pitch_deg))
		out.arc_m = float(values.get("arc_m", out.arc_m))
		out.height_m = float(values.get("height_m", out.height_m))
		out.hind_m = float(values.get("hind_m", out.hind_m))
		out.raise_speed = float(values.get("raise_speed", out.raise_speed))
		out.return_speed = float(values.get("return_speed", out.return_speed))
		return out
