extends RefCounted
## Smack hand choice and pose target: the flank/cheek query, jitter and the coat frame.

const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PORT := preload("res://mods/unfplap/hands/port.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")
const CONTACT := preload("res://mods/unfplap/hands/contact.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08

## The coordinator, held weakly: it owns this module, so a strong link back would be a cycle.
var _host_ref: WeakRef = null
var _coat := MODEL.CoatContext.new()


func _init(port: PORT = null) -> void:
	_host_ref = weakref(port)


## The coordinator, or null once it has released this module.
func _host() -> PORT:
	return _host_ref.get_ref() as PORT


## The smack hand: the free hand while one is busy, a random one while both are.
static func choose_hand(busy_left: bool, busy_right: bool, pick: float) -> MODEL.Side:
	if busy_left and busy_right:
		return MODEL.Side.LEFT if pick < 0.5 else MODEL.Side.RIGHT
	if busy_left:
		return MODEL.Side.RIGHT
	if busy_right:
		return MODEL.Side.LEFT
	return MODEL.Side.NONE


## The lean picks a cheek; a positive lean takes the left hand.
static func side_from_lean(lean_side: float) -> MODEL.Side:
	if lean_side > 0.0:
		return MODEL.Side.LEFT
	if lean_side < 0.0:
		return MODEL.Side.RIGHT
	return MODEL.Side.NONE


static func finger_hint(caressing: bool, forward: Vector3) -> Vector3:
	if caressing:
		var hint := forward.normalized()
		if hint.length_squared() > 0.5:
			return hint
		return Vector3.FORWARD
	return Vector3.DOWN


## Free-hand query offset from the cheek mark centre; both terms scale with the pony.
static func query_offset(height_m: float, hind_m: float, scale: float,
		up: Vector3, back: Vector3) -> Vector3:
	return up.normalized() * (height_m * scale) + back.normalized() * (hind_m * scale)


## Nearest point on the posed flank faces, for the free-hand smack query.
static func closest_flank_hit(faces: PackedVector3Array, normals: PackedVector3Array,
		point: Vector3) -> MODEL.FlankHit:
	if faces.size() < 3:
		return MODEL.FlankHit.new()
	var best := INF
	var best_point := Vector3.ZERO
	var best_normal := Vector3.ZERO
	var best_face := -1
	var triangles := int(faces.size() / 3.0)
	for triangle: int in triangles:
		var i := triangle * 3
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var closest := _closest_on_triangle(a, b, c, point)
		var distance := closest.distance_squared_to(point)
		if distance >= best:
			continue
		best = distance
		best_face = triangle
		best_point = closest
		var barycentric := _triangle_barycentric(a, b, c, closest)
		var normal := Vector3.ZERO
		if normals.size() >= i + 3:
			normal = normals[i] * barycentric.x + normals[i + 1] * barycentric.y \
				+ normals[i + 2] * barycentric.z
		if normal.length_squared() < 0.0001:
			normal = (b - a).cross(c - a)
		best_normal = normal.normalized()
	return MODEL.FlankHit.new(true, best_point, best_normal, sqrt(best), best_face)


## Resolve the swing for the current act: the hand, the pose target and its frames.
func target(caress_left: bool, caress_right: bool, reach_left: bool, reach_right: bool,
		lean_side: float, standing: bool) -> MODEL.SmackTarget:
	var out := MODEL.SmackTarget.new()
	out.standing = standing
	var busy_left := caress_left or reach_left
	var busy_right := caress_right or reach_right
	var side := choose_hand(busy_left, busy_right, randf())
	if side == MODEL.Side.NONE:
		side = side_from_lean(lean_side)
		if side == MODEL.Side.NONE:
			side = MODEL.Side.LEFT if randf() < 0.5 else MODEL.Side.RIGHT
	out.side = side
	out.index = MODEL.side_index(side)
	out.caressing = caress_left if side == MODEL.Side.LEFT else caress_right
	out.reaching = reach_left if side == MODEL.Side.LEFT else reach_right
	out.from_coat = out.caressing or out.reaching
	var flank := _host().flank() if _host() != null else null
	if not is_instance_valid(flank) or not flank.has_method("impact"):
		return out
	if _host().driver() == null:
		return out
	var hand_side := side
	out.from_frame = _host().hand_frame(hand_side)
	if not out.from_frame.is_finite():
		return out
	var at := Vector3.INF
	var normal := Vector3.UP
	var centers := CONTACT.flank_centers(flank)
	var normals := CONTACT.flank_normals(flank)
	if out.index < centers.size() and out.index < normals.size():
		var centre := centers[out.index]
		var normal_local := normals[out.index]
		var pony := _host().pony()
		if is_instance_valid(pony):
			# Map the pony's backward and world-up directions into the flank frame.
			var back_local: Vector3 = (flank.global_basis.inverse() * pony.global_basis.z).normalized()
			var up_local: Vector3 = (flank.global_basis.inverse() * Vector3.UP).normalized()
			var angle := randf() * TAU
			var radius := sqrt(randf()) * _host().smack_zone_radius()
			at = centre + back_local * (SMACK_BACK_M + cos(angle) * radius) \
				+ up_local * (SMACK_UP_M + sin(angle) * radius)
			var frame := CONTACT.flank_frame(flank)
			normal = (frame.basis.inverse().transposed() * normal_local).normalized()
			var outward: Vector3 = (frame * centre) - pony.global_position
			outward.y = 0.0
			if outward.length_squared() > 0.001 and normal.dot(outward.normalized()) < 0.0:
				normal = -normal
	# Standing targets the live caress point or the bottom of the chosen cheek, not the decal
	# centre. The cheek-centre target above remains the fallback when the patch is unavailable.
	if standing:
		var standing_target := _standing_target(hand_side, out.from_frame.origin, out.caressing)
		if standing_target != null:
			at = standing_target.local
			normal = standing_target.normal
	out.at = at
	out.normal = normal
	if not at.is_finite():
		return out
	var pony := _host().pony()
	var engine := _host().engine()
	if not is_instance_valid(pony) or engine == null:
		return out
	var world_centre: Vector3 = CONTACT.flank_frame(flank) * at
	var forward := -pony.global_basis.z.normalized()
	var context := _coat_context(hand_side)
	var clearance := PLACEMENT.palm_clearance_for(_host().body_scale(),
		SETTINGS.hover_m.get_num())
	out.target = engine.coat_frame(pony, hand_side, world_centre, normal,
		finger_hint(out.caressing, forward), clearance, context)
	out.valid = out.target.is_finite()
	return out


func _coat_context(side: MODEL.Side) -> MODEL.CoatContext:
	_coat.hover = PLACEMENT.palm_clearance_for(_host().body_scale(), SETTINGS.hover_m.get_num())
	_coat.contact_smooth = 0.0
	_coat.normal_deg_s = 0.0
	_coat.debug = _host().debug()
	_coat.ignore.clear()
	_coat.radial = true
	_coat.regions.clear()
	_coat.extra_hover = 0.0
	_coat.state_key = "smack:" + MODEL.side_key(side)
	_coat.delta = 0.016
	return _coat


## The standing smack target: the live caress point when the hand is already on the patch.
func _standing_target(side: MODEL.Side, hand_world: Vector3,
		caressing: bool) -> MODEL.FlankContact:
	var engine := _host().engine()
	if caressing and engine != null:
		var state := engine.contact_state(side)
		if state != null and state.source == "flank":
			if state.point.is_finite() and state.normal.length_squared() > 0.5:
				var out := MODEL.FlankContact.new()
				out.point = state.point
				out.normal = state.normal.normalized()
				out.local = CONTACT.flank_frame(_host().flank()).affine_inverse() * state.point
				return out
	var focus := hand_world
	if not caressing:
		var cheek := _lower_cheek_query(side)
		if cheek.is_finite():
			focus = cheek
	var hit := _closest_flank_contact(focus)
	if hit == null:
		return null
	var point_world := hit.point
	var normal := hit.normal
	var local := hit.local
	var radius := _host().smack_zone_radius()
	if radius > 0.0:
		var pony := _host().pony()
		if not is_instance_valid(pony):
			return hit
		var up := Vector3.UP.slide(normal)
		if up.length_squared() < 0.001:
			up = -pony.global_basis.z.slide(normal)
		up = up.normalized()
		var across := up.cross(normal).normalized()
		var angle := randf() * TAU
		var shift := (up * cos(angle) + across * sin(angle)) * (sqrt(randf()) * radius)
		var contact := CONTACT.contact(pony, point_world + shift, normal, _ignore())
		if contact.source == "flank":
			point_world = contact.point
			normal = contact.normal.normalized()
			local = CONTACT.flank_frame(_host().flank()).affine_inverse() * point_world
	hit.point = point_world
	hit.normal = normal
	hit.local = local
	return hit


## Nearest point on the posed FlankSurface patch; the body hull is deliberately not consulted.
func _closest_flank_contact(point_world: Vector3) -> MODEL.FlankContact:
	var flank := _host().flank() if _host() != null else null
	if not is_instance_valid(flank):
		return null
	var surface: Variant = CONTACT.flank_surface(flank)
	if surface == null:
		return null
	var frame := CONTACT.flank_frame(flank)
	if not frame.is_finite():
		return null
	var pony := _host().pony()
	CONTACT.flank_update(pony, flank)
	var faces := CONTACT.flank_faces(flank)
	var normals := CONTACT.flank_vertex_normals(flank)
	if faces.is_empty() or normals.is_empty():
		return null
	var local := frame.affine_inverse() * point_world
	var hit := closest_flank_hit(faces, normals, local)
	if not hit.hit:
		return null
	var local_point := hit.point
	var local_normal := hit.normal
	if local_normal.length_squared() < 0.5:
		local_normal = Vector3.UP
	# Refine onto the real triangle so the palm normal matches the coat at that point.
	var refined := CONTACT.flank_contact(flank, local_point, local_normal)
	if refined != null:
		local_point = refined.point
		local_normal = refined.normal
	var out := MODEL.FlankContact.new()
	out.point = frame * local_point
	out.normal = (frame.basis.inverse().transposed() * local_normal).normalized()
	var toward_hand := point_world - out.point
	if toward_hand.length_squared() > 0.0001 and out.normal.dot(toward_hand) < 0.0:
		out.normal = -out.normal
	out.local = local_point
	return out


## World query point for a free-hand smack: the chosen cheek centre offset by the act's settings.
func _lower_cheek_query(side: MODEL.Side) -> Vector3:
	var flank := _host().flank() if _host() != null else null
	if not is_instance_valid(flank):
		return Vector3.INF
	var centers := CONTACT.flank_centers(flank)
	var index := MODEL.side_index(side)
	if index < 0 or index >= centers.size():
		return Vector3.INF
	var world: Vector3 = CONTACT.flank_frame(flank) * centers[index]
	var back := Vector3.BACK
	var pony := _host().pony()
	if is_instance_valid(pony):
		back = pony.global_basis.z.normalized()
	var presentation := _host().presentation()
	return world + query_offset(presentation.height_m, presentation.hind_m, _host().body_scale(),
		Vector3.UP, back)


func _ignore() -> Array[String]:
	var out: Array[String] = []
	for value: String in SETTINGS.ignore.get_list():
		out.append(value)
	return out


## Closest point on triangle ABC to P, from Real-Time Collision Detection (Ericson).
static func _closest_on_triangle(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


static func _triangle_barycentric(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denominator := d00 * d11 - d01 * d01
	if absf(denominator) < 0.0000001:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * d20 - d01 * d21) / denominator
	var w := (d00 * d21 - d01 * d20) / denominator
	return Vector3(1.0 - v - w, v, w)
