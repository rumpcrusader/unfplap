extends RefCounted
## Caress in both poses, shoulder reach, flank smack and palm-on-coat contact. The runtime owns
## scoring and the act state; this controller only drives the desktop hands and contact frames.
## Standing rubs the flank; missionary rubs her chest, neck and cheek. A and D toggle their
## hand independently, so both can caress at once.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CAESS_SYSTEM := preload("res://mods/unfplap/caress/caress_system.gd")
const FLANK_PATH := preload("res://mods/unfplap/caress/flank_path.gd")
const MISSIONARY_PATH := preload("res://mods/unfplap/caress/missionary_path.gd")
const COAT := preload("res://mods/unfplap/caress/coat.gd")
const CAESS_HAND := preload("res://mods/unfplap/caress/caress_hand.gd")
const SMACK_AUDIO := preload("res://mods/unfplap/audio/act/smack/catalogue.gd")

## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35
## Standing A/D caress: an oval rub on the flank surface. The oval is wider along the body
## than up/down, so the hand reads as stroking instead of drawing a perfect circle.
const CARESS_RADIUS_M := 0.04125
const CARESS_SPEED_RAD_S := 3.6
## A caress is one continuous action, not a per-frame sample: five seconds of contact count as
## one liked or disliked touch. The runtime's scoring and tolerance paths see discrete events.
const CAESS_TOUCH_SECONDS := 5.0
const CARESS_OVAL_ACROSS := 1.30
const CARESS_OVAL_UP := 0.70
## The rub centre is lifted this far above each size profile's `up` point. The cutie-mark
## anchor sits low on the flank; this keeps the stroke on the barrel instead of the belly.
const CARESS_UP_BIAS_M := 0.05
## A smack swings the caress hand to the cheek and back; ease the return so the contact reset
## does not read as a teleport.
const CARESS_RETURN_SECONDS := 0.12
## The palm ball's own collision radius (anon_body.gd hand sweep). The palm marker is its
## centre, so this is how far the centre sits above the coat when the visible palm touches.
const PALM_ON_COAT_CLEARANCE_M := 0.04
const PALM_CONTACT_SMOOTH := 18.0
const PALM_CONTACT_MAX_STEP_M := 0.06
const PALM_CONTACT_SOURCE_HITS := 2
## A palm normal may turn this fast when the coat normal moves or the contact source changes.
## Fast enough to track the coat, slow enough to avoid snapping.
const PALM_NORMAL_MAX_DEG_S := 120.0
## Caress-point offsets are per size preset, in metres before the body scale is applied to
## only the circle radius. `out` moves each hand out from the flank; both hands together gain
## twice that amount. JRHNBR (`mounting`) is 4 cm wider; Canon sits lower.
const CARESS_PROFILES := {
	"canon": {"up": 0.08, "back": 0.06, "out": 0.0},
	"mounting": {"up": 0.16, "back": 0.08, "out": 0.02},
	"same height": {"up": 0.18, "back": 0.09, "out": 0.03},
	"hoers": {"up": 0.20, "back": 0.10, "out": 0.04},
}
## Missionary caress: one hand on her belly at rest, W sliding it toward her chest and S toward the
## lower belly along the posed body axis. The anchor is lifted above the spine before the coat query
## snaps the palm onto her surface. All distances scale with her body.
const MISSIONARY_CARESS_TRAVEL_M := 0.12
const MISSIONARY_CARESS_LATERAL_M := 0.045
## The query starts roughly at the barrel radius, not above the chest: a higher lift makes the
## chest/withers hull the nearest contact.
const MISSIONARY_CARESS_LIFT_M := 0.18
## The palm rolls about its coat normal: counter-clockwise for Anon's right hand, clockwise for
## his left, so the fingers lie comfortably across the chest instead of straight up her body.
const MISSIONARY_CARESS_PALM_ROLL_DEG := 30.0
## Torso hulls the missionary caress may use. The neck, head, legs, tail, wings and mane cannot
## steal the palm when the query sits near the chest.
const MISSIONARY_TORSO_REGIONS := ["back", "withers", "shoulder", "barrel", "belly", "rump"]
const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08
const SMACK_ZONE_RADIUS_M := 0.035
const SMACK_COOLDOWN_MS := 200
## Missionary keeps the old hidden-hand swing; the standing hand uses the phases below.
const SMACK_SWING_SECONDS := 0.20
const SMACK_CONTACT_PHASE := 0.45
## Standing smack: lift off the coat, accelerate into the contact, hold for a frame or two,
## then return to the live caress point or the rest hand. The raise distance is the debug
## `presentation.standing.smack.raise_m` value, scaled by the pony's body size.
const SMACK_RAISE_SPEED_M_S := 2.0
const SMACK_RAISE_MIN_S := 0.12
const SMACK_RAISE_MAX_S := 0.30
const SMACK_RETURN_SPEED_M_S := 6.0
const SMACK_STRIKE_MIN_S := 0.06
const SMACK_STRIKE_MAX_S := 0.20
const SMACK_PITCH_DEG := 12.0
const SMACK_RAISE_BACK_M := 0.05
## Non-caress smack: the query is offset vertically from the cheek centre by
## `presentation.standing.smack.height_m` (positive up, default -0.03 = 3 cm below), and the
## wind-up is a backswing from behind/below rather than an outward lift. All distances scale
## with the pony.
const SMACK_HEIGHT_M := -0.03
const SMACK_HIND_M := 0.10
const SMACK_ARC_M := 0.06
const SMACK_SWING_DOWN_RATIO := 0.55
const SMACK_SWING_OUT_RATIO := 0.15
const SMACK_CONTACT_HOLD_SECONDS := 0.03
const SMACK_REST_RETURN_SECONDS := 0.20
## Native impact strength for the smack; also drives the tail jiggle propagation.
const SMACK_IMPACT_STRENGTH := 0.8
const SMACK_PHASE_NONE := 0
const SMACK_PHASE_RAISE := 1
const SMACK_PHASE_STRIKE := 2
const SMACK_PHASE_CONTACT := 3
const SMACK_PHASE_RECOVER := 4
## The stock flank slap is bright and compressed. Install a peak-normalised OpenNSFW hand-smack
## variant on the native FlankTouch player; the stock stream, level and pitch are restored at
## act end.
const SMACK_VOLUME_DB := -7.0
const SMACK_PITCH_MIN := 0.97
const SMACK_PITCH_MAX := 1.03
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## Pure palm geometry for tests and the controller.
static func _region_ignored(region: String, ignore: Array) -> bool:
	return COAT.region_ignored(region, ignore)


static func _region_allowed(region: String, allowed: Array) -> bool:
	return COAT.region_allowed(region, allowed)


static func palm_clearance_for(body_scale: float,
		distance := PALM_ON_COAT_CLEARANCE_M) -> float:
	return distance * clampf(body_scale, 0.5, 2.0)


## Per-size caress-point offsets. Unknown presets use the JRHNBR reference.
static func caress_profile_for(size_name: String) -> Dictionary:
	var profile: Dictionary = CARESS_PROFILES.get(size_name, CARESS_PROFILES["mounting"])
	return profile


## Advance the oval phase only while that hand is moving. Stopping keeps the palm at the
## current point instead of resetting the stroke.
static func caress_phase_step(phase: float, moving: bool, delta: float) -> float:
	if not moving:
		return phase
	return fmod(phase + CARESS_SPEED_RAD_S * delta, TAU)


## One caress tick: accumulate contact time and report `[seconds_left, events]`, where events is
## how many CAESS_TOUCH_SECONDS actions this tick completed. A stopped caress keeps no credit.
static func caress_touch_step(seconds: float, active: bool, delta: float) -> Array:
	if not active:
		return [0.0, 0]
	var left := maxf(0.0, seconds) + maxf(0.0, delta)
	var events := 0
	while left >= CAESS_TOUCH_SECONDS:
		left -= CAESS_TOUCH_SECONDS
		events += 1
	return [left, events]


## 0 = left cheek, 1 = right cheek, -1 = centered (caller picks at random).
static func smack_side_index(side: float) -> int:
	if side > 0.0:
		return 0
	if side < 0.0:
		return 1
	return -1


## Roll about the coat normal, in degrees. The right hand turns counter-clockwise and the left
## clockwise as seen from above.
static func missionary_palm_roll_deg(side: String) -> float:
	return MISSIONARY_CARESS_PALM_ROLL_DEG if side == "right" \
		else -MISSIONARY_CARESS_PALM_ROLL_DEG


## Pitch the palm about its own normal (local X). Positive values lower the fingers; negative
## values raise them. The palm normal is unchanged, so this is a wrist pitch, not a roll around
## the finger/arm axis (local Z).
static func smack_pitch_basis(straight: Basis, pitch_deg: float) -> Basis:
	if absf(pitch_deg) < 0.0001:
		return straight
	var axis := straight.x.normalized()
	if axis.length_squared() < 0.5:
		return straight
	var angle := deg_to_rad(absf(pitch_deg))
	var positive := straight.rotated(axis, angle)
	var negative := straight.rotated(axis, -angle)
	var positive_down := (-positive.z).y
	var negative_down := (-negative.z).y
	var down := positive if positive_down < negative_down else negative
	var up := negative if positive_down < negative_down else positive
	return down if pitch_deg > 0.0 else up


## Raised palm frame: lift along the coat normal and pull slightly toward her rump. The palm
## is pitched down by `pitch_deg` about its normal so the wind-up is not a roll.
static func smack_raise_frame(contact: Transform3D, outward: Vector3, raise_m: float,
		back_m: float, back: Vector3, pitch_deg: float) -> Transform3D:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	var rear := back.normalized()
	if rear.length_squared() < 0.5:
		rear = contact.basis.z
	return Transform3D(smack_pitch_basis(contact.basis, pitch_deg),
		contact.origin + normal * raise_m + rear * back_m)


## Caressing keeps the palm in the caress plane (fingers forward). A free-hand smack comes
## from behind/below, so the fingers point down along the coat.
static func smack_finger_hint(caressing: bool, forward: Vector3) -> Vector3:
	if caressing:
		var hint := forward.normalized()
		if hint.length_squared() > 0.5:
			return hint
		return Vector3.FORWARD
	return Vector3.DOWN


## Non-caress wind-up: a backswing from behind and below the contact, with the fingers down.
static func smack_swing_raise_frame(contact: Transform3D, outward: Vector3, back: Vector3,
		raise_m: float, pitch_deg: float) -> Transform3D:
	var distance := raise_m
	var rear := back.normalized()
	if rear.length_squared() < 0.5:
		rear = contact.basis.z
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = contact.basis.x
	var origin := contact.origin + rear * distance \
		+ Vector3.DOWN * (distance * SMACK_SWING_DOWN_RATIO) \
		+ normal * (distance * SMACK_SWING_OUT_RATIO)
	return Transform3D(smack_pitch_basis(contact.basis, pitch_deg), origin)


## Medium-speed lift with a backward bow. `back` is the bow vector toward her rump; its length
## is `smack.arc_m` × body scale. Zero gives a straight blend.
static func smack_raise_blend(from: Transform3D, to: Transform3D, back: Vector3,
		t: float) -> Transform3D:
	var eased := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var origin := from.origin.lerp(to.origin, eased) + back * sin(eased * PI)
	var basis := from.basis.slerp(to.basis, eased).orthonormalized()
	return Transform3D(basis, origin)


## Snappy strike: cubic travel, so the palm accelerates into the coat instead of sliding
## linearly. The basis turns a little faster than the position.
static func smack_strike_blend(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	var clamped := clampf(t, 0.0, 1.0)
	var basis := from.basis.slerp(to.basis, pow(clamped, 2.0)).orthonormalized()
	return Transform3D(basis, from.origin.lerp(to.origin, pow(clamped, 3.0)))


static func smack_recover_blend(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	return from.interpolate_with(to, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))


## Closest point on the posed FlankSurface triangle soup. `faces` holds three vertices per
## triangle and `normals` the matching vertex normals, both in the space of `point`. The
## returned normal is the interpolated surface normal at that point.
static func closest_flank_hit(faces: PackedVector3Array, normals: PackedVector3Array,
		point: Vector3) -> Dictionary:
	if faces.size() < 3:
		return {}
	var best := INF
	var best_point := Vector3.ZERO
	var best_normal := Vector3.ZERO
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
		best_point = closest
		var barycentric := _triangle_barycentric(a, b, c, closest)
		var normal := Vector3.ZERO
		if normals.size() >= i + 3:
			normal = normals[i] * barycentric.x + normals[i + 1] * barycentric.y \
				+ normals[i + 2] * barycentric.z
		if normal.length_squared() < 0.0001:
			normal = (b - a).cross(c - a)
		best_normal = normal.normalized()
	return {"point": best_point, "normal": best_normal, "distance": sqrt(best)}


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


var runtime: Node
var main: Variant
var pony: Variant
var _presentation_cfg: Dictionary = {}
var _profile: Dictionary = {}
var _flank: Node

var _reach_shoulder := ""
var _reach_holding := false
var _reach_hand_from := Transform3D.IDENTITY
var _reach_hand_rest := Transform3D.IDENTITY
var _reach_hand_rest_valid := false
var _reach_hand_started := 0
var _reach_hand_logged := false
var _reach_hand_returning := false
var _reach_hand_return_from := Transform3D.IDENTITY
var _reach_hand_return_started := 0
var _reach_hand_return_side := ""
var _caress_active := {"L": false, "R": false}
var _caress_latched := {"L": false, "R": false}
var _caress_key_down := {"L": false, "R": false}
var _caress_moving := {"L": true, "R": true}
var _caress_move_key_down := {"L": false, "R": false}
var _caress_phase := {"L": 0.0, "R": 0.0}
var _caress_touch_seconds := 0.0
var _caress_logged := {"L": false, "R": false}
var _caress_return_from := {"L": Transform3D.IDENTITY, "R": Transform3D.IDENTITY}
var _caress_return_started := {"L": 0, "R": 0}
var _last_smack_ms := -10000
var _smack_active := false
var _smack_index := 0
var _smack_at := Vector3.INF
var _smack_side := ""
var _smack_from := Transform3D.IDENTITY
var _smack_to := Transform3D.IDENTITY
var _smack_started := 0
var _smack_impact_done := false
var _caress_engine: RefCounted
var _flank_path: RefCounted
var _missionary_path: RefCounted
var _debug_draw_mesh: MeshInstance3D = null
var _debug_draw_depth_mesh: MeshInstance3D = null
var _debug_immediate: ImmediateMesh = null
var _smack_phase := SMACK_PHASE_NONE
var _smack_phase_started := 0
var _smack_contact := Transform3D.IDENTITY
var _smack_raised := Transform3D.IDENTITY
var _smack_rest := Transform3D.IDENTITY
var _smack_outward := Vector3.UP
var _smack_raise_seconds := SMACK_RAISE_MIN_S
var _smack_strike_seconds := 0.10
var _smack_caress := false
var _smack_streams: Array[AudioStream] = []
var _smack_stream_last := -1
var _smack_sound_restore: Dictionary = {}
var _smack_sound_installed := false

func _shoulder_hand_point(side: String) -> Dictionary:
	if side.is_empty() or not is_instance_valid(pony):
		return {}
	var path: Variant = _path_for_pose()
	if path == null or not path.has_method("shoulder_point"):
		return {}
	return path.call("shoulder_point", "left" if side == "L" else "right")


## Approximate phase-1 hand placement: the palm rests on the named shoulder. This uses the
## desktop hold-target path, so it does not need `request_action` or release `controls_locked`.
func _set_reach_hand() -> void:
	if _reach_shoulder.is_empty() or not is_instance_valid(pony):
		return
	var driver: Node = runtime.call("_desktop_pose_driver")
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		return
	var info := _shoulder_hand_point(_reach_shoulder)
	if info.is_empty():
		return
	var outward: Vector3 = info["outward"]
	var point: Vector3 = info["palm"]
	var side := "left" if _reach_shoulder == "L" else "right"
	var reach_key := "reach:" + side
	if _reach_hand_started <= 0:
		_engine().reset_hand(reach_key)
	# Palm flat on the shoulder coat: the shared hull frame keeps the fingers forward with the
	# palm inward.
	var delta := runtime.get_physics_process_delta_time() if is_instance_valid(runtime) else 0.016
	var target: Transform3D = _engine().coat_frame(pony, side, point, outward,
		-pony.global_basis.z, _palm_clearance(), true, delta, [], true, [], 0.0, reach_key)
	if _reach_hand_started <= 0:
		_reach_hand_started = Time.get_ticks_msec()
		_reach_hand_from = Transform3D.IDENTITY
		if driver.has_method("hand_frame"):
			var from_frame: Variant = driver.call("hand_frame", side)
			if from_frame is Transform3D:
				_reach_hand_from = from_frame
		_reach_hand_rest = _reach_hand_from
		_reach_hand_rest_valid = _reach_hand_from.is_finite()
	var frame := target
	if _reach_hand_started > 0 and _reach_hand_from.is_finite():
		var t := clampf(float(Time.get_ticks_msec() - _reach_hand_started)
			/ (REACH_HAND_BLEND_S * 1000.0), 0.0, 1.0)
		frame = _reach_hand_from.interpolate_with(target, smoothstep(0.0, 1.0, t))
	if not _reach_hand_logged:
		_reach_hand_logged = true
		var palm_normal: Vector3 = target.basis.x * (1.0 if side == "left" else -1.0)
		_log("reach hand side=%s target=%s x=%s y=%s z=%s fingers=%s palm=%s" % [
			side, str(target.origin), str(target.basis.x), str(target.basis.y),
			str(target.basis.z), str(-target.basis.z), str(palm_normal)])
	driver.call("set_hold_target", side, frame, "rub")


func _caress_tick(delta: float) -> void:
	var pose := str(runtime.get("pose_id"))
	if pose not in [CATALOG.STANDING, CATALOG.MISSIONARY]:
		_end_caress()
		return
	# Hold-X auto settings owns A/D and Z/C, so the keys freeze while the layer is open. The
	# hands keep their current state and the caress keeps scoring; only the input is ignored.
	var frozen := runtime.has_method("auto_panel_open") and bool(runtime.call("auto_panel_open"))
	var keys := {
		"L": Input.is_physical_key_pressed(KEY_A),
		"R": Input.is_physical_key_pressed(KEY_D),
	}
	var motion_keys := {
		"L": KEY_Z,
		"R": KEY_C,
	}
	for side: String in ["L", "R"]:
		if not frozen:
			var held := bool(keys[side])
			var pressed := held and not bool(_caress_key_down[side])
			_caress_key_down[side] = held
			if pressed:
				_caress_latched[side] = not bool(_caress_latched[side])
			var move_held := Input.is_physical_key_pressed(motion_keys[side])
			var move_pressed := move_held and not bool(_caress_move_key_down[side])
			_caress_move_key_down[side] = move_held
			if move_pressed:
				_caress_moving[side] = not bool(_caress_moving[side])
				_log("caress movement side=%s %s" % [
					side, "on" if bool(_caress_moving[side]) else "off"])
		var hand_side := "left" if side == "L" else "right"
		# The slapping hand owns the hold target during its swing. Keep the oval phase moving
		# so the hand can return to the current caress point instead of the one it left.
		if _smack_active and _smack_side == hand_side:
			if bool(_caress_active[side]) and bool(_caress_moving[side]):
				_caress_phase[side] = caress_phase_step(
					float(_caress_phase[side]), true, delta)
			continue
		var want := bool(_caress_latched[side])
		if want:
			if not bool(_caress_active[side]):
				_caress_active[side] = true
				_caress_phase[side] = 0.0
				_caress_logged[side] = false
				_caress_return_started[side] = 0
				_engine().reset_hand(hand_side)
				_log("caress start side=%s" % side)
			_caress_phase[side] = caress_phase_step(
				float(_caress_phase[side]), bool(_caress_moving[side]), delta)
			_set_caress_hand(side)
		elif bool(_caress_active[side]):
			_end_caress_side(side)
	_caress_touch_tick(delta)


## Count a held caress as one touch per CAESS_TOUCH_SECONDS of contact instead of one per physics
## tick. Short taps score nothing; five seconds of rubbing score once.
func _caress_touch_tick(delta: float) -> void:
	var step := caress_touch_step(_caress_touch_seconds, any_active(), delta)
	_caress_touch_seconds = float(step[0])
	for _index in int(step[1]):
		runtime.call("_on_touch", "caress")


func _end_caress_side(side: String) -> void:
	if not bool(_caress_active[side]):
		return
	var hand_side := "left" if side == "L" else "right"
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", hand_side)
	_engine().reset_hand(hand_side)
	_log("caress stop side=%s" % side)
	_caress_active[side] = false
	_caress_latched[side] = false
	_caress_phase[side] = 0.0
	_caress_logged[side] = false
	_caress_return_started[side] = 0


func _end_caress() -> void:
	_end_caress_side("L")
	_end_caress_side("R")
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_touch_seconds = 0.0


## Hand-marker basis with the palm flat on the coat: local -Z is the fingers, and the palm
## normal (local -X right / +X left) points inward along -outward. No custom roll.
static func palm_surface_basis(side: String, outward: Vector3, finger_hint: Vector3) -> Basis:
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
	return Basis(x_axis, y_axis, z_axis)


## Caress contact exclusions. The tail flick after a smack can put a tail hull beside the rub
## point; without this the fallback nearest() would snap the palm onto the tail.
func _caress_ignore() -> Array:
	var caress: Variant = _presentation_cfg.get("caress", {})
	if not caress is Dictionary:
		return []
	# The ignore list setting keeps only the known region names, so this needs no filtering.
	var raw: Variant = (caress as Dictionary).get("ignore", [])
	return raw if raw is Array else []


static func rotate_normal_toward(from: Vector3, to: Vector3, max_step: float) -> Vector3:
	return CAESS_HAND.rotate_normal_toward(from, to, max_step)


func _palm_clearance() -> float:
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = float(pony.get("body_scale"))
	var distance := PALM_ON_COAT_CLEARANCE_M
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		distance = float((caress as Dictionary).get("palm_distance", distance))
	return palm_clearance_for(scale, distance)


## Oval radii at body scale 1.0. The old radius × ratio constants are the fallback.
func _caress_oval_across_m() -> float:
	var value := CARESS_RADIUS_M * CARESS_OVAL_ACROSS
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		value = float((caress as Dictionary).get("oval_across_m", value))
	return value


func _caress_oval_up_m() -> float:
	var value := CARESS_RADIUS_M * CARESS_OVAL_UP
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		value = float((caress as Dictionary).get("oval_up_m", value))
	return value


## Place one caress hand. The path decides where the caress is; the shared engine does the
## contact and palm frame. This function only blends the smack return and hands the frame to the
## pose's palm holder.
func _set_caress_hand(side: String, apply := true) -> Transform3D:
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	var hand_side := "left" if side == "L" else "right"
	var path: Variant = _path_for_pose()
	if path == null:
		return Transform3D.IDENTITY
	var started := Time.get_ticks_usec()
	var target: Transform3D = _engine().frame(pony, path, hand_side,
		_caress_context(side, hand_side))
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "caress_precise", Time.get_ticks_usec() - started)
	if not target.is_finite() or target.origin.length_squared() < 0.0001:
		return Transform3D.IDENTITY
	if not apply:
		return target
	var return_started := int(_caress_return_started.get(side, 0))
	if return_started > 0:
		var elapsed := float(Time.get_ticks_msec() - return_started) / 1000.0
		if elapsed >= CARESS_RETURN_SECONDS:
			_caress_return_started[side] = 0
		else:
			var t := smoothstep(0.0, 1.0, elapsed / CARESS_RETURN_SECONDS)
			var from: Transform3D = _caress_return_from[side]
			target = from.interpolate_with(target, t)
	if not bool(_caress_logged[side]):
		_caress_logged[side] = true
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("set_hold_target"):
		driver.call("set_hold_target", hand_side, target, "rub")
	var debug: Dictionary = _engine().debug_state(hand_side)
	if not debug.is_empty():
		_draw_caress_debug(path, hand_side, debug, target)
	return target


## Everything the pose-free engine needs for one hand this tick. Only the pose-specific path
## receives the lean and path settings; the engine sees one oval, one hover and one mode.
func _caress_context(side: String, hand_side: String) -> Dictionary:
	var pose := str(runtime.get("pose_id")) if is_instance_valid(runtime) else ""
	var missionary := pose == CATALOG.MISSIONARY
	var scale := _smack_body_scale()
	var size := 1.0
	if is_instance_valid(runtime) and runtime.has_method("_size_scale"):
		size = float(runtime.call("_size_scale"))
	var body_scale := scale if missionary else size
	var oval_scale := maxf(float(SETTINGS.oval_scale.get_num()), 0.01) if missionary else 1.0
	var oval := Vector2(_caress_oval_across_m(), _caress_oval_up_m()) \
		* body_scale * oval_scale
	return {
		"lean": clampf(float(runtime.get("_lean_forward")), -1.0, 1.0),
		"along_m": float(SETTINGS.along_m.get_num()),
		"phase": float(_caress_phase.get(side, 0.0)),
		"scale": scale,
		"size": size,
		"oval": oval,
		"hover": _precise_hover(),
		"clearance": _palm_clearance(),
		"hull_extra": float(SETTINGS.over_coat_m.get_num()) if missionary else 0.0,
		"precise": _precise_on(),
		"hand_shape": _hand_shape_on(),
		"ignore": _caress_ignore(),
		"profile": _caress_profile(),
		"reach": _caress_reach(hand_side),
		"delta": runtime.get_physics_process_delta_time() if is_instance_valid(runtime) else 0.016,
	}


func _engine() -> RefCounted:
	if _caress_engine == null:
		_caress_engine = CAESS_SYSTEM.new(runtime)
	return _caress_engine


func _path_for_pose() -> Variant:
	if not is_instance_valid(runtime) or not is_instance_valid(pony):
		return null
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		if _missionary_path == null:
			_missionary_path = MISSIONARY_PATH.new()
		if _missionary_path.get("pony") != pony:
			_missionary_path.call("setup", pony, runtime)
			_missionary_path.call("reset")
		return _missionary_path
	if _flank_path == null:
		_flank_path = FLANK_PATH.new()
	if _flank_path.get("pony") != pony:
		_flank_path.call("setup", pony, runtime)
		_flank_path.call("reset")
	return _flank_path


func _caress_reach(hand_side: String) -> Dictionary:
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("caress_reach"):
		var value: Variant = driver.call("caress_reach", hand_side)
		if value is Dictionary:
			return value
	return {}


func _precise_on() -> bool:
	return is_instance_valid(runtime) and runtime.has_method("_feature") \
		and bool(runtime.call("_feature", "caress_surface"))


func _hand_shape_on() -> bool:
	return is_instance_valid(runtime) and runtime.has_method("_feature") \
		and bool(runtime.call("_feature", "caress_hand_shape"))


## The visible palm-centre hover. Standing keeps the tuned `Palm distance`; missionary uses the
## signed `Raise over coat` value as its total hover.
func _precise_hover() -> float:
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		return float(SETTINGS.over_coat_m.get_num())
	return _palm_clearance()


func _draw_caress_debug(path: Variant, hand_side: String, chosen: Dictionary,
		target: Transform3D) -> void:
	if not bool(SETTINGS.caress_debug.get_bool()):
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	var world: Variant = path.call("debug_world", hand_side)
	if not world is Array:
		world = []
	var tree: SceneTree = pony.get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return
	if not is_instance_valid(_debug_immediate):
		_debug_immediate = ImmediateMesh.new()
	if not is_instance_valid(_debug_draw_mesh) or not _debug_draw_mesh.is_inside_tree():
		_debug_draw_mesh = _make_debug_overlay(scene, "UnfplapCaressDebug", false)
	if not is_instance_valid(_debug_draw_depth_mesh) \
			or not _debug_draw_depth_mesh.is_inside_tree():
		_debug_draw_depth_mesh = _make_debug_overlay(scene, "UnfplapCaressDebugDepth", true)
	_debug_draw_mesh.mesh = _debug_immediate
	_debug_draw_depth_mesh.mesh = _debug_immediate
	var immediate := _debug_immediate
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := Vector3.ZERO
	var have_previous := false
	for anchor_value: Variant in (world as Array):
		if not anchor_value is Dictionary:
			continue
		var anchor: Dictionary = anchor_value
		var point: Vector3 = anchor["position"]
		var normal: Vector3 = anchor["normal"]
		var color := _anchor_debug_color(str(anchor["id"]))
		_debug_cross(immediate, point, color)
		_debug_segment(immediate, point, point + normal * 0.08, color)
		if have_previous:
			_debug_segment(immediate, previous, point, Color.WHITE)
		previous = point
		have_previous = true
	if not chosen.is_empty():
		var contact: Vector3 = chosen["contact"]
		var contact_normal: Vector3 = chosen["normal"]
		_debug_cross(immediate, contact, Color(0.2, 1.0, 1.0), 0.035)
		_debug_segment(immediate, contact, contact + contact_normal * 0.10,
			Color(0.2, 1.0, 1.0))
	if target.is_finite():
		_debug_cross(immediate, target.origin, Color(1.0, 0.55, 0.15), 0.04)
		_debug_segment(immediate, target.origin, target.origin + target.basis.y * 0.06,
			Color(1.0, 0.55, 0.15))
	# White is the actual hand palm; gray is the gap between it and the requested target.
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var hand: Transform3D = driver.call("hand_frame", hand_side)
		if hand.is_finite() and hand.origin.length_squared() > 0.0001:
			_debug_cross(immediate, hand.origin, Color.WHITE, 0.045)
			_debug_segment(immediate, hand.origin, target.origin, Color(0.6, 0.6, 0.6))
	immediate.surface_end()


func _make_debug_overlay(scene: Node, overlay_name: String, depth: bool) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = overlay_name
	overlay.top_level = true
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = not depth
	material.albedo_color = Color.WHITE if depth else Color(0.28, 0.28, 0.28)
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(overlay)
	overlay.global_transform = Transform3D.IDENTITY
	return overlay


func _debug_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)


func _debug_cross(mesh: ImmediateMesh, point: Vector3, color: Color, size := 0.025) -> void:
	_debug_segment(mesh, point - Vector3.RIGHT * size, point + Vector3.RIGHT * size, color)
	_debug_segment(mesh, point - Vector3.UP * size, point + Vector3.UP * size, color)
	_debug_segment(mesh, point - Vector3.FORWARD * size, point + Vector3.FORWARD * size, color)


func _anchor_debug_color(id: String) -> Color:
	match id:
		"lower":
			return Color(1.0, 0.2, 0.2)
		"flank":
			return Color(1.0, 0.45, 0.1)
		"shoulder":
			return Color(0.2, 0.8, 1.0)
		"belly":
			return Color(0.2, 1.0, 0.2)
		"chest":
			return Color(0.2, 0.5, 1.0)
		"neck":
			return Color(1.0, 1.0, 0.2)
		"cheek":
			return Color(1.0, 0.2, 1.0)
		_:
			return Color.WHITE


func _clear_debug_draw() -> void:
	if is_instance_valid(_debug_draw_mesh):
		_debug_draw_mesh.queue_free()
	if is_instance_valid(_debug_draw_depth_mesh):
		_debug_draw_depth_mesh.queue_free()
	_debug_draw_mesh = null
	_debug_draw_depth_mesh = null
	_debug_immediate = null


## The act camera position; the path anchors are chosen on the side it actually sees.
func _hand_driver() -> Node:
	if not is_instance_valid(runtime):
		return null
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		if not runtime.has_method("missionary_anon_body"):
			return null
		var body: Variant = runtime.call("missionary_anon_body")
		if is_instance_valid(body) and body is Node:
			return body as Node
		return null
	var driver: Variant = runtime.call("_desktop_pose_driver")
	if is_instance_valid(driver) and driver is Node:
		return driver as Node
	return null


## Release from the shoulder smoothly rather than teleporting back.
func _begin_reach_release() -> void:
	if _reach_shoulder.is_empty():
		return
	var side := "left" if _reach_shoulder == "L" else "right"
	var driver: Node = runtime.call("_desktop_pose_driver")
	_reach_hand_return_from = _reach_hand_from
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var current: Variant = driver.call("hand_frame", side)
		if current is Transform3D and (current as Transform3D).is_finite():
			_reach_hand_return_from = current
	if not _reach_hand_rest_valid or not _reach_hand_return_from.is_finite():
		_clear_reach_hand()
		return
	_reach_hand_return_side = side
	_reach_hand_return_started = Time.get_ticks_msec()
	_reach_hand_returning = true


func _reach_hand_return_tick() -> void:
	if not _reach_hand_returning:
		return
	if _reach_hand_return_side.is_empty():
		_reach_hand_returning = false
		return
	var driver: Node = runtime.call("_desktop_pose_driver")
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_reach_hand_returning = false
		return
	var t := clampf(float(Time.get_ticks_msec() - _reach_hand_return_started)
		/ (REACH_HAND_RELEASE_S * 1000.0), 0.0, 1.0)
	if t >= 1.0:
		_reach_hand_returning = false
		if driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _reach_hand_return_side)
		_reach_hand_return_side = ""
		_reach_hand_started = 0
		_reach_hand_from = Transform3D.IDENTITY
		return
	var frame: Transform3D = _reach_hand_return_from.interpolate_with(
		_reach_hand_rest, smoothstep(0.0, 1.0, t))
	driver.call("set_hold_target", _reach_hand_return_side, frame, "rub")


func _clear_reach_hand() -> void:
	var side := ""
	if not _reach_shoulder.is_empty():
		side = "left" if _reach_shoulder == "L" else "right"
	elif not _reach_hand_return_side.is_empty():
		side = _reach_hand_return_side
	_reach_hand_returning = false
	_reach_hand_return_side = ""
	_reach_hand_started = 0
	_reach_hand_logged = false
	_reach_hand_from = Transform3D.IDENTITY
	_reach_hand_rest_valid = false
	if side.is_empty():
		return
	var driver: Node = runtime.call("_desktop_pose_driver")
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", side)


func _smack_zone_radius() -> float:
	return maxf(0.0, float(_profile.get("smack_zone_radius", SMACK_ZONE_RADIUS_M)))


## The posed FlankTouch frame. `frame` is the current hip frame even while the decal/sound
## node is parked; `global_transform` can lag there, so prefer the stored frame.
func _flank_frame() -> Transform3D:
	if not is_instance_valid(_flank):
		return Transform3D.IDENTITY
	var value: Variant = _flank.get("frame")
	if value is Transform3D and (value as Transform3D).is_finite():
		return value
	return _flank.global_transform


## Nearest point on the posed FlankSurface patch to a world point. The patch is the cheek
## region of her flank; the body hull is deliberately not consulted, so a shoulder or belly
## caress still smacks the flank.
func _closest_flank_contact(point_world: Vector3) -> Dictionary:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank):
		return {}
	var surface: Variant = _flank.get("surface")
	if surface == null:
		return {}
	var frame := _flank_frame()
	if not frame.is_finite():
		return {}
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D and surface.has_method("update_pose"):
		surface.call("update_pose", sk, frame)
	var faces_value: Variant = surface.get("faces")
	var normals_value: Variant = surface.get("vertex_normals")
	if not faces_value is PackedVector3Array or not normals_value is PackedVector3Array:
		return {}
	var faces: PackedVector3Array = faces_value
	var normals: PackedVector3Array = normals_value
	var local := frame.affine_inverse() * point_world
	var hit := closest_flank_hit(faces, normals, local)
	if hit.is_empty():
		return {}
	var local_point: Vector3 = hit["point"]
	var local_normal: Vector3 = hit["normal"]
	if local_normal.length_squared() < 0.5:
		local_normal = Vector3.UP
	# Refine onto the real triangle so the palm normal matches the coat at that point.
	if surface.has_method("contact"):
		var radii: Variant = _flank.get("radii")
		var reach := 0.10
		if radii is Vector3:
			reach = float((radii as Vector3).z)
		var raw: Variant = surface.call("contact", local_point, local_point,
			-local_normal, reach)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var raw_point: Variant = (raw as Dictionary).get("position")
			var raw_normal: Variant = (raw as Dictionary).get("normal")
			if raw_point is Vector3 and raw_normal is Vector3:
				var point_v: Vector3 = raw_point
				var normal_v: Vector3 = raw_normal
				local_point = point_v
				local_normal = normal_v.normalized()
	var world_point := frame * local_point
	var world_normal := (frame.basis.inverse().transposed() * local_normal).normalized()
	var toward_hand := point_world - world_point
	if toward_hand.length_squared() > 0.0001 and world_normal.dot(toward_hand) < 0.0:
		world_normal = -world_normal
	return {"point": world_point, "normal": world_normal, "local": local_point}


## Standing smack target: the live caress point when that hand is already on the flank patch,
## otherwise the bottom of the chosen cheek for a free-hand smack, jittered within the
## character's smack zone. Empty only when the flank patch is unavailable.
func _standing_smack_target(hand_side: String, hand_world: Vector3,
		caressing: bool) -> Dictionary:
	var caress_side := "L" if hand_side == "left" else "R"
	var state: Dictionary = _engine().contact_state(hand_side)
	if caressing and str(state.get("source", "")) == "flank":
		var point_v: Variant = state.get("point", Vector3.INF)
		var normal_v: Variant = state.get("normal", Vector3.UP)
		if point_v is Vector3 and normal_v is Vector3:
			var point: Vector3 = point_v
			var normal: Vector3 = normal_v
			if point.is_finite() and normal.length_squared() > 0.5:
				var frame := _flank_frame()
				return {"local": frame.affine_inverse() * point,
					"normal": normal.normalized()}
	var focus := hand_world
	if not caressing:
		var cheek := _lower_cheek_query(hand_side)
		if cheek.is_finite():
			focus = cheek
	var hit := _closest_flank_contact(focus)
	if hit.is_empty():
		return {}
	var point_world: Vector3 = hit["point"]
	var normal: Vector3 = hit["normal"]
	var local: Vector3 = hit["local"]
	var radius := _smack_zone_radius()
	if radius > 0.0:
		var up := Vector3.UP.slide(normal)
		if up.length_squared() < 0.001:
			up = -pony.global_basis.z.slide(normal)
		up = up.normalized()
		var across := up.cross(normal).normalized()
		var angle := randf() * TAU
		var shift := (up * cos(angle) + across * sin(angle)) * (sqrt(randf()) * radius)
		var jittered := COAT.contact(pony, point_world + shift, normal, _caress_ignore())
		if str(jittered.get("source", "")) == "flank":
			point_world = jittered.get("point", point_world)
			var jittered_normal: Variant = jittered.get("normal", normal)
			if jittered_normal is Vector3:
				var jn: Vector3 = jittered_normal
				normal = jn.normalized()
			local = _flank_frame().affine_inverse() * point_world
	return {"local": local, "normal": normal}


## Free-hand query offset from the cheek mark centre: `height_m` is signed (positive up) and
## `hind_m` moves toward her rump. Both scale with the pony.
static func smack_query_offset(height_m: float, hind_m: float, scale: float,
		up: Vector3, back: Vector3) -> Vector3:
	return up.normalized() * (height_m * scale) + back.normalized() * (hind_m * scale)


## World query point for a free-hand smack: the chosen cheek centre offset by the act's height
## and hind settings, so the nearest surface point is a cheek rather than the leg.
func _lower_cheek_query(hand_side: String) -> Vector3:
	if not is_instance_valid(_flank):
		return Vector3.INF
	var centers: Variant = _flank.get("centers")
	var index := 0 if hand_side == "left" else 1
	if not centers is Array or index >= (centers as Array).size():
		return Vector3.INF
	var centre: Variant = (centers as Array)[index]
	if not centre is Vector3:
		return Vector3.INF
	var world: Vector3 = _flank_frame() * (centre as Vector3)
	var back := Vector3.BACK
	if is_instance_valid(pony):
		back = pony.global_basis.z.normalized()
	var scale := _smack_body_scale()
	return world + smack_query_offset(_smack_height_m(), _smack_hind_m(), scale,
		Vector3.UP, back)


func _smack() -> void:
	if int(runtime.get("state")) not in [STATE_ACTIVE, STATE_CLIMAX]:
		return
	var now := Time.get_ticks_msec()
	if _smack_active or now - _last_smack_ms < SMACK_COOLDOWN_MS:
		return
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank) or not _flank.has_method("impact"):
		return
	# If a hand is already resting on the flank, slap with that hand. Both on the flank: pick
	# one at random. Otherwise keep the lean-based cheek/hand mapping.
	var hand_side := ""
	if _caress_active["L"] and _caress_active["R"]:
		hand_side = "left" if randf() < 0.5 else "right"
	elif _caress_active["L"]:
		hand_side = "left"
	elif _caress_active["R"]:
		hand_side = "right"
	var index := 0 if hand_side == "left" else (1 if hand_side == "right" else smack_side_index(float(runtime.get("_lean_side"))))
	if index < 0:
		index = 0 if randf() < 0.5 else 1
		hand_side = "left" if index == 0 else "right"
	elif hand_side.is_empty():
		hand_side = "left" if index == 0 else "right"
	var caress_side := "L" if hand_side == "left" else "R"
	var caressing := bool(_caress_active[caress_side])
	var driver: Node = runtime.call("_desktop_pose_driver")
	var from_frame := Transform3D.IDENTITY
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var current: Variant = driver.call("hand_frame", hand_side)
		if current is Transform3D and (current as Transform3D).is_finite():
			from_frame = current
	var at := Vector3.INF
	var normal := Vector3.UP
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	if centers is Array and index < (centers as Array).size() \
			and normals is Array and index < (normals as Array).size():
		var centre: Variant = (centers as Array)[index]
		var normal_local: Variant = (normals as Array)[index]
		if centre is Vector3 and normal_local is Vector3 and is_instance_valid(pony):
			# The mark centres are local to FlankTouch. Map the pony's backward and world-up
			# directions into that frame so the offset is right regardless of model axes.
			var back_local: Vector3 = (_flank.global_basis.inverse() * pony.global_basis.z).normalized()
			var up_local: Vector3 = (_flank.global_basis.inverse() * Vector3.UP).normalized()
			var angle := randf() * TAU
			var radius := sqrt(randf()) * _smack_zone_radius()
			at = (centre as Vector3) + back_local * (SMACK_BACK_M + cos(angle) * radius) \
				+ up_local * (SMACK_UP_M + sin(angle) * radius)
			var frame := _flank_frame()
			normal = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
			var outward: Vector3 = (frame * (centre as Vector3)) - pony.global_position
			outward.y = 0.0
			if outward.length_squared() > 0.001 and normal.dot(outward.normalized()) < 0.0:
				normal = -normal
	# Standing targets the live caress point or the bottom of the chosen cheek, not the decal
	# centre. The cheek-centre target above remains the fallback when the patch is unavailable.
	if str(runtime.get("pose_id")) == CATALOG.STANDING and from_frame.is_finite():
		var standing_target := _standing_smack_target(hand_side, from_frame.origin, caressing)
		if not standing_target.is_empty():
			at = standing_target.get("local", at)
			normal = standing_target.get("normal", normal)
	_last_smack_ms = now
	if at.is_finite() and is_instance_valid(main) and is_instance_valid(main.player):
		if is_instance_valid(driver) and from_frame.is_finite():
			var world_centre: Vector3 = _flank_frame() * at
			var target: Transform3D = _engine().coat_frame(pony, hand_side, world_centre, normal,
				_smack_finger_hint(caressing), _palm_clearance(), false, 0.0, [], true, [],
				0.0, "smack:" + hand_side)
			_smack_index = index
			_smack_at = at
			_smack_side = hand_side
			_smack_started = now
			_smack_impact_done = false
			_smack_active = true
			if str(runtime.get("pose_id")) == CATALOG.STANDING:
				_start_standing_smack(hand_side, from_frame, target, normal, now)
			else:
				_smack_from = from_frame
				_smack_to = target
			return
	_flank_impact_without_reaction(index, at)
	runtime.call("_on_touch", "smack")


func _smack_swing_tick() -> void:
	if not _smack_active:
		return
	if _smack_side.is_empty():
		_smack_active = false
		return
	var driver: Node = runtime.call("_desktop_pose_driver")
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_end_smack_swing()
		return
	if str(runtime.get("pose_id")) == CATALOG.STANDING:
		_smack_phase_tick(driver)
		return
	var phase := clampf(float(Time.get_ticks_msec() - _smack_started)
		/ (SMACK_SWING_SECONDS * 1000.0), 0.0, 1.0)
	var arc := sin(phase * PI)
	var frame := _smack_from.interpolate_with(_smack_to, arc)
	driver.call("set_hold_target", _smack_side, frame, "rub")
	if not _smack_impact_done and phase >= SMACK_CONTACT_PHASE:
		_smack_impact_done = true
		_flank_impact_without_reaction(_smack_index, _smack_at)
		runtime.call("_on_touch", "smack")
	if phase >= 1.0:
		_end_smack_swing()


## Standing smack: lift, strike, contact, then return to the live caress point or the rest
## hand. The impact fires exactly when the strike reaches the contact frame.
func _smack_phase_tick(driver: Node) -> void:
	var now := Time.get_ticks_msec()
	var elapsed := float(now - _smack_phase_started) / 1000.0
	match _smack_phase:
		SMACK_PHASE_RAISE:
			var t := clampf(elapsed / maxf(_smack_raise_seconds, 0.001), 0.0, 1.0)
			var bow := _smack_back_dir() * _smack_arc_m()
			var frame := smack_raise_blend(_smack_from, _smack_raised, bow, t)
			driver.call("set_hold_target", _smack_side, frame, "rub")
			if t >= 1.0:
				_smack_phase = SMACK_PHASE_STRIKE
				_smack_phase_started = now
		SMACK_PHASE_STRIKE:
			var t := clampf(elapsed / maxf(_smack_strike_seconds, 0.001), 0.0, 1.0)
			var frame := smack_strike_blend(_smack_raised, _smack_contact, t)
			driver.call("set_hold_target", _smack_side, frame, "rub")
			if t >= 1.0:
				driver.call("set_hold_target", _smack_side, _smack_contact, "rub")
				_flank_impact_without_reaction(_smack_index, _smack_at)
				runtime.call("_on_touch", "smack")
				_smack_phase = SMACK_PHASE_CONTACT
				_smack_phase_started = now
		SMACK_PHASE_CONTACT:
			driver.call("set_hold_target", _smack_side, _smack_contact, "rub")
			if elapsed >= SMACK_CONTACT_HOLD_SECONDS:
				_smack_phase = SMACK_PHASE_RECOVER
				_smack_phase_started = now
				# The smack may have moved the tail or another soft hull next to the rub
				# point. Reacquire the live caress contact before returning to it.
				_engine().reset_hand(_smack_side)
		SMACK_PHASE_RECOVER:
			var target := _smack_recover_target()
			var duration := CARESS_RETURN_SECONDS if _smack_keep_caress() \
				else SMACK_REST_RETURN_SECONDS
			var t := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
			var frame := smack_recover_blend(_smack_contact, target, t)
			driver.call("set_hold_target", _smack_side, frame, "rub")
			if t >= 1.0:
				_finish_smack_recovery(driver)


func _start_standing_smack(hand_side: String, from_frame: Transform3D, contact: Transform3D,
		outward: Vector3, now: int) -> void:
	_smack_from = from_frame
	_smack_contact = contact
	_smack_outward = outward.normalized()
	_smack_rest = from_frame
	_smack_caress = bool(_caress_active["L" if hand_side == "left" else "R"])
	if _smack_caress:
		var scale := _smack_body_scale()
		_smack_raised = smack_raise_frame(contact, _smack_outward, _smack_raise_m(),
			SMACK_RAISE_BACK_M * scale, _smack_back_dir(), _smack_pitch_deg())
	else:
		_smack_raised = smack_swing_raise_frame(contact, _smack_outward,
			_smack_back_dir(), _smack_raise_m(), _smack_pitch_deg())
	var distance := from_frame.origin.distance_to(_smack_raised.origin)
	_smack_raise_seconds = clampf(distance / _smack_raise_speed(),
		SMACK_RAISE_MIN_S, SMACK_RAISE_MAX_S)
	var return_distance := _smack_raised.origin.distance_to(contact.origin)
	_smack_strike_seconds = clampf(return_distance / _smack_return_speed(),
		SMACK_STRIKE_MIN_S, SMACK_STRIKE_MAX_S)
	_smack_phase = SMACK_PHASE_RAISE
	_smack_phase_started = now


func _smack_recover_target() -> Transform3D:
	var caress_side := "L" if _smack_side == "left" else "R"
	if _smack_keep_caress() and is_instance_valid(_flank):
		var target := _set_caress_hand(caress_side, false)
		if not target.is_equal_approx(Transform3D.IDENTITY):
			return target
	return _smack_rest


func _smack_keep_caress() -> bool:
	var caress_side := "L" if _smack_side == "left" else "R"
	return _smack_caress and bool(_caress_latched.get(caress_side, false))


func _finish_smack_recovery(driver: Node) -> void:
	var caress_side := "L" if _smack_side == "left" else "R"
	var keep_caress := _smack_keep_caress()
	if keep_caress:
		_caress_return_started[caress_side] = 0
	elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", _smack_side)
	_smack_active = false
	_smack_side = ""
	_smack_at = Vector3.INF
	_smack_phase = SMACK_PHASE_NONE
	_smack_caress = false


func _smack_back_dir() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.BACK
	var back: Vector3 = pony.global_basis.z.normalized()
	back -= _smack_outward * back.dot(_smack_outward)
	if back.length_squared() < 0.0001:
		back = _smack_contact.basis.z
	return back.normalized()


func _smack_body_scale() -> float:
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return clampf(float(pony.get("body_scale")), 0.5, 2.0)
	return 1.0


func _smack_finger_hint(caressing: bool) -> Vector3:
	var forward := Vector3.FORWARD
	if is_instance_valid(pony):
		forward = -pony.global_basis.z.normalized()
	return smack_finger_hint(caressing, forward)


func _smack_setting(name: String, fallback: float) -> float:
	var smack: Variant = _presentation_cfg.get("smack", {})
	if smack is Dictionary:
		return float((smack as Dictionary).get(name, fallback))
	return fallback


func _smack_raise_m() -> float:
	return maxf(0.0, _smack_setting("raise_m", 0.30)) * _smack_body_scale()


func _smack_hind_m() -> float:
	return maxf(0.0, _smack_setting("hind_m", SMACK_HIND_M))


func _smack_height_m() -> float:
	return _smack_setting("height_m", SMACK_HEIGHT_M)


func _smack_arc_m() -> float:
	return maxf(0.0, _smack_setting("arc_m", SMACK_ARC_M)) * _smack_body_scale()


func _smack_pitch_deg() -> float:
	return _smack_setting("pitch_deg", SMACK_PITCH_DEG)


func _smack_raise_speed() -> float:
	return maxf(0.05, _smack_setting("raise_speed", SMACK_RAISE_SPEED_M_S))


func _smack_return_speed() -> float:
	return maxf(0.05, _smack_setting("return_speed", SMACK_RETURN_SPEED_M_S))


func _end_smack_swing() -> void:
	if not _smack_active:
		return
	if not _smack_side.is_empty():
		var driver: Node = runtime.call("_desktop_pose_driver")
		var caress_side := "L" if _smack_side == "left" else "R"
		if bool(_caress_active[caress_side]):
			# The smack may have moved the tail or another soft hull next to the rub point.
			# Drop the cached source/normal and reacquire the caress contact before returning.
			var from := _smack_contact if _smack_phase != SMACK_PHASE_NONE else _smack_to
			if is_instance_valid(driver) and driver.has_method("hand_frame"):
				var current: Variant = driver.call("hand_frame", _smack_side)
				if current is Transform3D and (current as Transform3D).is_finite():
					from = current
			_engine().reset_hand(_smack_side)
			_caress_return_from[caress_side] = from
			_caress_return_started[caress_side] = Time.get_ticks_msec()
			_set_caress_hand(caress_side)
		elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _smack_side)
	_smack_active = false
	_smack_side = ""
	_smack_at = Vector3.INF
	_smack_impact_done = false
	_smack_phase = SMACK_PHASE_NONE
	_smack_caress = false
	_smack_contact = Transform3D.IDENTITY
	_smack_raised = Transform3D.IDENTITY
	_smack_rest = Transform3D.IDENTITY
	_smack_outward = Vector3.UP


func _smack_sound_player() -> AudioStreamPlayer3D:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank):
		return null
	var player: Variant = _flank.get("sound")
	if not player is AudioStreamPlayer3D:
		player = _flank.get_node_or_null("sound")
	return player if player is AudioStreamPlayer3D else null


func _load_smack_streams() -> void:
	if not _smack_streams.is_empty():
		return
	for path: String in SMACK_AUDIO.PATHS:
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_smack_streams.append(stream)


## Pick a variant without repeating the previous one, so two fast smacks never sound alike.
func _next_smack_stream(count: int) -> int:
	if count <= 1:
		return 0
	var index := randi() % count
	if index == _smack_stream_last:
		index = (index + 1) % count
	_smack_stream_last = index
	return index


## Install one pack smack variant on the native player immediately before `impact()`, so the
## sound lands on the same frame as the decal and blush.
func _install_smack_sound() -> void:
	var player := _smack_sound_player()
	if player == null:
		return
	_load_smack_streams()
	if _smack_streams.is_empty():
		_restore_smack_sound()
		return
	if not _smack_sound_installed:
		_smack_sound_restore = {
			"stream": player.stream,
			"volume_db": player.volume_db,
			"pitch_scale": player.pitch_scale,
		}
		_smack_sound_installed = true
	var index := _next_smack_stream(_smack_streams.size())
	player.stream = _smack_streams[index]
	player.volume_db = SMACK_VOLUME_DB
	player.pitch_scale = randf_range(SMACK_PITCH_MIN, SMACK_PITCH_MAX)


## Put the stock slap stream, level and pitch back. Called at every act exit.
func _restore_smack_sound() -> void:
	if not _smack_sound_installed:
		return
	_smack_sound_installed = false
	var player := _smack_sound_player()
	if player != null and not _smack_sound_restore.is_empty():
		var stock: Variant = _smack_sound_restore.get("stream")
		if stock is AudioStream:
			player.stream = stock
		else:
			player.stream = null
		player.volume_db = float(_smack_sound_restore.get("volume_db", player.volume_db))
		player.pitch_scale = float(_smack_sound_restore.get("pitch_scale", player.pitch_scale))
	_smack_sound_restore.clear()


## Native impact, but with the pony's game reaction signals silenced. During an act those
## reactions can trigger a buck/fidget or hoof shuffle, which is not wanted for a sex smack.
func _flank_impact_without_reaction(index: int, at: Vector3) -> void:
	_install_smack_sound()
	if not is_instance_valid(pony) or not pony.has_signal("physical_reaction"):
		_flank.call("impact", index, at, SMACK_IMPACT_STRENGTH)
		_notify_smack_jiggle()
		return
	var sig: Signal = pony.physical_reaction
	var links: Array = sig.get_connections()
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and sig.is_connected(callable):
			sig.disconnect(callable)
	_flank.call("impact", index, at, SMACK_IMPACT_STRENGTH)
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and not sig.is_connected(callable):
			sig.connect(callable)
	_notify_smack_jiggle()


## Carry the native cheek jiggle into the same tail-base propagation as a thrust.
func _notify_smack_jiggle() -> void:
	if is_instance_valid(runtime) and runtime.has_method("_on_smack_impact"):
		runtime.call("_on_smack_impact", SMACK_IMPACT_STRENGTH)


## Refresh cached scene references once per public call. Pony and settings can change between
## acts or when the settings tab edits a caress value live.
func _sync() -> void:
	pony = runtime.get("pony") if is_instance_valid(runtime) else null
	main = runtime.get("main") if is_instance_valid(runtime) else null
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var profile: Variant = runtime.get("_profile") if is_instance_valid(runtime) else null
	_profile = profile if profile is Dictionary else {}
	if not is_instance_valid(_flank) and is_instance_valid(pony):
		_flank = pony.get_node_or_null("FlankTouch")


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


## One physics tick: ease the reach hand home, hold it on the shoulder, then run the caress
## and the smack swing in the same order the runtime used before.
## Return easing runs at the top of every lean tick, even while the act is leaving the
## actionable states, so a released reach still blends home.
func return_tick() -> void:
	if not is_instance_valid(runtime):
		return
	_reach_hand_return_tick()


func tick(delta: float) -> void:
	if not is_instance_valid(runtime):
		return
	_sync()
	if _reach_holding:
		_set_reach_hand()
	_caress_tick(delta)
	_smack_swing_tick()


## Stop input-driven contact without clearing the reach release.
func stop_inputs() -> void:
	_end_caress()
	_end_smack_swing()


func start_reach(shoulder: String) -> void:
	_sync()
	_reach_shoulder = shoulder
	_reach_holding = true
	_reach_hand_returning = false
	_reach_hand_started = 0
	_reach_hand_logged = false
	_set_reach_hand()


func end_reach() -> void:
	_reach_holding = false
	_begin_reach_release()


func reset() -> void:
	_end_caress()
	_end_smack_swing()
	_restore_smack_sound()
	_clear_reach_hand()
	_reach_shoulder = ""
	_reach_holding = false
	_engine().reset()
	if _missionary_path != null:
		_missionary_path.call("reset")
	if _flank_path != null:
		_flank_path.call("reset")
	_clear_debug_draw()
	_caress_latched = {"L": false, "R": false}
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_touch_seconds = 0.0


func any_active() -> bool:
	return bool(_caress_active.get("L", false)) or bool(_caress_active.get("R", false))


func active(side: String) -> bool:
	return bool(_caress_active.get(side, false))


func smack() -> void:
	_sync()
	_smack()


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)


## Per-size caress-point offsets, scaled for the "same height" preset.
func _caress_profile() -> Dictionary:
	var size := str(runtime.call("_size_name"))
	var profile := caress_profile_for(size).duplicate(true)
	if size == "same height":
		var scale := float(runtime.call("_same_height_scale"))
		for key: String in ["up", "back", "out"]:
			profile[key] = float(profile.get(key, 0.0)) * scale
	return profile
