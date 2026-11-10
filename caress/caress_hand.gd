extends RefCounted
## The caress hand: a small sample shape around the palm marker, a palm/fingertip contact mode,
## and a penetration resolver against the posed surface. The marker is the game's palm frame;
## local -Z is the fingers, +Y the thumb, and the palm normal is +/-X per hand.

const PALM_RADIUS := 0.02
const HEEL_RADIUS := 0.02
const FINGER_RADIUS := 0.012
const THUMB_RADIUS := 0.015
const CLEARANCE_M := 0.02
const CONTACT_MARGIN := 0.002
const RESOLVE_ITERATIONS := 4
const FINGER_TIP := Vector3(0.015, 0.0, -0.09)

const PALM_SAMPLES := [
	{"name": "palm", "offset": Vector3(0.0, 0.0, 0.0), "radius": PALM_RADIUS},
	{"name": "heel", "offset": Vector3(0.0, 0.0, 0.03), "radius": HEEL_RADIUS},
	{"name": "index", "offset": Vector3(-0.045, 0.0, -0.09), "radius": FINGER_RADIUS},
	{"name": "middle", "offset": Vector3(-0.015, 0.0, -0.095), "radius": FINGER_RADIUS},
	{"name": "ring", "offset": Vector3(0.015, 0.0, -0.09), "radius": FINGER_RADIUS},
	{"name": "little", "offset": Vector3(0.045, 0.0, -0.085), "radius": FINGER_RADIUS},
	{"name": "thumb", "offset": Vector3(0.0, 0.03, -0.03), "radius": THUMB_RADIUS},
]
const FINGERTIP_SAMPLES := [
	{"name": "index", "offset": Vector3(-0.045, 0.0, -0.09), "radius": FINGER_RADIUS},
	{"name": "middle", "offset": Vector3(-0.015, 0.0, -0.095), "radius": FINGER_RADIUS},
	{"name": "ring", "offset": Vector3(0.015, 0.0, -0.09), "radius": FINGER_RADIUS},
	{"name": "little", "offset": Vector3(0.045, 0.0, -0.085), "radius": FINGER_RADIUS},
]


static func samples(mode: String) -> Array:
	return FINGERTIP_SAMPLES if mode == "fingertip" else PALM_SAMPLES


## Rotate `from` toward `to` by at most `max_step` radians. Keeps a palm normal from snapping
## when the contact source changes or the coat curvature jumps.
static func rotate_normal_toward(from: Vector3, to: Vector3, max_step: float) -> Vector3:
	var a := from.normalized()
	var b := to.normalized()
	if a.length_squared() < 0.5:
		return b
	if b.length_squared() < 0.5:
		return a
	var angle := a.angle_to(b)
	if angle <= 0.0001 or angle <= max_step:
		return b
	return a.slerp(b, clampf(max_step / angle, 0.0, 1.0)).normalized()


## Palm plane with the fingers on `finger_hint`. The palm normal is local +X for the left hand
## and -X for the right, matching the game's hand-marker convention.
static func palm_basis(side: String, outward: Vector3, finger_hint: Vector3,
		roll_deg := 0.0) -> Basis:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.RIGHT
	var x_axis := normal * (1.0 if side == "right" else -1.0)
	var fingers := finger_hint.normalized()
	fingers -= x_axis * fingers.dot(x_axis)
	if fingers.length_squared() < 0.0001:
		fingers = Vector3.FORWARD - x_axis * Vector3.FORWARD.dot(x_axis)
	if fingers.length_squared() < 0.0001:
		fingers = Vector3.UP - x_axis * Vector3.UP.dot(x_axis)
	fingers = fingers.normalized()
	var z_axis := -fingers
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	if absf(roll_deg) > 0.0001:
		basis = Basis(normal.normalized(), deg_to_rad(roll_deg)) * basis
	return basis


## Build the palm marker at a contact point. `hover` is the palm-centre distance from the coat
## for the single-point placement; the sample resolver adds its own radii instead.
static func place(contact: Vector3, outward: Vector3, finger_hint: Vector3, side: String,
		mode: String, roll_deg: float, hover: float) -> Transform3D:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	var basis := palm_basis(side, normal, finger_hint, roll_deg)
	var origin := contact + normal * hover
	if mode == "fingertip":
		origin -= basis * FINGER_TIP
	return Transform3D(basis, origin)


## Push the palm marker out until every sample sphere is outside the surface. `surface` is a
## CaressSurface (or any object with closest(point) -> {point, normal, distance, inside}).
## Returns {frame, penetration, contacts, resolved}.
static func resolve(surface: Variant, frame: Transform3D, mode: String,
		over_coat := 0.0, side := "right") -> Dictionary:
	if not is_instance_valid(surface) or not surface.has_method("closest"):
		return {"frame": frame, "penetration": 0.0, "contacts": [], "resolved": false}
	var result := frame
	var last_penetration := 0.0
	var contacts: Array = []
	var outward := (result.basis.x * (1.0 if side == "right" else -1.0)).normalized()
	var ray: bool = surface.has_method("nearest")
	for _iteration in RESOLVE_ITERATIONS:
		var deepest := 0.0
		var push := Vector3.ZERO
		contacts.clear()
		for sample: Dictionary in samples(mode):
			var offset: Vector3 = sample["offset"]
			var radius: float = sample["radius"]
			var world := result * offset
			var hit: Variant
			if ray:
				hit = surface.call("nearest", world, outward)
			else:
				hit = surface.call("closest", world)
			if not hit is Dictionary or (hit as Dictionary).is_empty():
				continue
			var point: Vector3 = (hit as Dictionary).get("point", world)
			var normal: Vector3 = (hit as Dictionary).get("normal", Vector3.UP)
			if normal.length_squared() < 0.5:
				normal = Vector3.UP
			normal = normal.normalized()
			var distance: float = (hit as Dictionary).get("distance", world.distance_to(point))
			var inside: bool = bool((hit as Dictionary).get("inside", false))
			var required := radius + CONTACT_MARGIN + maxf(over_coat, 0.0)
			var amount := required + distance if inside else required - distance
			contacts.append({
				"name": sample["name"], "distance": distance, "inside": inside,
				"required": required, "amount": amount,
			})
			if amount > deepest:
				deepest = amount
				push = normal * amount
		last_penetration = maxf(0.0, deepest)
		if deepest <= 0.0001:
			return {"frame": result, "penetration": 0.0, "contacts": contacts,
				"resolved": true}
		result.origin += push
	return {"frame": result, "penetration": last_penetration, "contacts": contacts,
		"resolved": false}
