extends "res://world/relationships/shared_bed.gd"
## Bed compatibility.
## 1. Stock cuddles refuse any pony whose body scale is over 1.05, blocking every
##    JRHNBR/Same Height/Hoers size preset. The gate only needs the numeric value for the
##    synchronous eligibility call; the real scale is restored immediately.
## 2. The bed's authored `side_local` is its intended approach. The stock order tries the
##    generic +x side first, which in Golden Oak's guest nook is behind the bed.


func eligible(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var scale: Variant = actor.get("body_scale")
	if scale == null or float(scale) <= 1.05:
		return super(actor)
	actor.set("body_scale", 1.0)
	var ok: bool = super(actor)
	actor.set("body_scale", scale)
	return ok


## The bed's authored `side_local` is its intended approach. The stock order tries the generic
## +x side first, which in Golden Oak's guest nook is behind the bed: the navigator reaches the
## far side and seating never gets within its 0.6 m hop radius.
func _front_for(actor: CharacterBody3D) -> Vector3:
	var z := (_frame.affine_inverse() * _mare_rest.origin).z
	var candidates: Array[Vector3] = []
	if _bed.has_meta("side_local"):
		candidates.append(_bed.to_global(Vector3(_bed.get_meta("side_local"))))
	candidates.append(_frame * Vector3(_side * (_half.x + 0.55), 0.0, z))
	candidates.append(_frame * Vector3(_lane + _side * BESIDE, 0.0, _half.z + 0.6))
	var clearance := float(actor.profile.clearance)
	var radius := float(actor.profile.radius)
	for at: Vector3 in candidates:
		var floor_at: Vector3 = EXIT.clear_floor(actor, at, clearance, radius)
		if floor_at.is_finite() and absf(floor_at.y - actor.global_position.y) < 0.5:
			return floor_at
	return Vector3.INF
