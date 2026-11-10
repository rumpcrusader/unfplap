extends RefCounted
## The caress palm marker. Local `-Z` is the fingers, `+Y` the thumb, and the palm normal is
## `+X` on the left hand / `-X` on the right. The contact is a single palm-centre point placed at
## the requested hover above the coat; there is no sample resolver.

const FINGER_TIP := Vector3(0.015, 0.0, -0.09)


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


## Palm plane with the fingers on `finger_hint`.
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


## Build the palm marker at a contact point. `hover` is the palm-centre distance from the coat.
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
