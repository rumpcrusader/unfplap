extends RefCounted
## Standing caress, shoulder reach, flank smack and palm-on-coat contact. The runtime owns
## scoring and the act state; this controller only drives the desktop hands and contact frames.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35
## Standing A/D caress: an oval rub on the flank surface. The oval is wider along the body
## than up/down, so the hand reads as stroking instead of drawing a perfect circle.
const CARESS_RADIUS_M := 0.04125
const CARESS_SPEED_RAD_S := 3.6
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
## Backward lean reaches the rump top at this magnitude, not at a full -1 lean.
const CARESS_RUMP_LEAN := 0.5
const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08
const SMACK_ZONE_RADIUS_M := 0.035
const SMACK_COOLDOWN_MS := 200
const SMACK_SWING_SECONDS := 0.20
const SMACK_CONTACT_PHASE := 0.45
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## Pure palm geometry for tests and the controller.
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


## 0 = left cheek, 1 = right cheek, -1 = centered (caller picks at random).
static func smack_side_index(side: float) -> int:
	if side > 0.0:
		return 0
	if side < 0.0:
		return 1
	return -1


var runtime: Node
var main: Variant
var pony: Variant
var _presentation_cfg: Dictionary = {}
var _profile: Dictionary = {}
var _flank: Node

var _reach_shoulder := ""
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
var _caress_logged := {"L": false, "R": false}
var _caress_return_from := {"L": Transform3D.IDENTITY, "R": Transform3D.IDENTITY}
var _caress_return_started := {"L": 0, "R": 0}
var _caress_diag_at := 0
var _last_smack_ms := -10000
var _smack_active := false
var _smack_index := 0
var _smack_at := Vector3.INF
var _smack_side := ""
var _smack_from := Transform3D.IDENTITY
var _smack_to := Transform3D.IDENTITY
var _smack_started := 0
var _smack_impact_done := false
var _palm_contacts: Dictionary = {}

func _shoulder_hand_point(side: String) -> Dictionary:
	if side.is_empty() or not is_instance_valid(pony):
		return {}
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return {}
	var skeleton := sk as Skeleton3D
	var bone := skeleton.find_bone("pony_shoulder_" + side)
	if bone < 0:
		return {}
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == "L":
		outward = -outward
	return {"palm": shoulder.origin, "outward": outward}


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
	if _reach_hand_started <= 0:
		_reset_palm_contact(side)
	# Palm flat on the shoulder coat: the surface contact supplies the position/normal and the
	# shared frame helper keeps the fingers forward with the palm inward.
	var target := _palm_on_coat_frame(side, point, outward, -pony.global_basis.z)
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
	if str(runtime.get("pose_id")) != CATALOG.STANDING:
		_end_caress()
		return
	var keys := {
		"L": Input.is_physical_key_pressed(KEY_A),
		"R": Input.is_physical_key_pressed(KEY_D),
	}
	var motion_keys := {
		"L": KEY_Z,
		"R": KEY_C,
	}
	for side: String in ["L", "R"]:
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
		# The slapping hand owns the hold target during its swing. Freeze the oval phase so
		# the hand can return to the same caress point without a jump.
		if _smack_active and _smack_side == hand_side:
			continue
		var want := bool(_caress_latched[side])
		if want:
			if not bool(_caress_active[side]):
				_caress_active[side] = true
				_caress_phase[side] = 0.0
				_caress_logged[side] = false
				_caress_return_started[side] = 0
				_reset_palm_contact("left" if side == "L" else "right")
				_log("caress start side=%s" % side)
			_caress_phase[side] = caress_phase_step(
				float(_caress_phase[side]), bool(_caress_moving[side]), delta)
			_set_caress_hand(side)
			runtime.call("_on_touch", "caress")
		elif bool(_caress_active[side]):
			_end_caress_side(side)


func _end_caress_side(side: String) -> void:
	if not bool(_caress_active[side]):
		return
	var hand_side := "left" if side == "L" else "right"
	var driver: Node = runtime.call("_desktop_pose_driver")
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", hand_side)
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
	_caress_diag_at = 0


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
	var raw: Variant = (caress as Dictionary).get("ignore", [])
	if not raw is Array:
		return []
	var out: Array = []
	for region: Variant in raw:
		var name := str(region).to_lower()
		if name in SETTINGS.CARESS_IGNORE_REGIONS and not out.has(name):
			out.append(name)
	return out


static func _region_ignored(region: String, ignore: Array) -> bool:
	if ignore.is_empty():
		return false
	var name := region.to_lower()
	for value: Variant in ignore:
		var prefix := str(value).to_lower()
		if name == prefix or name.begins_with(prefix + "_"):
			return true
	return false


## PonyTouchBody.nearest() without the caress-ignored regions. Only used when the ignore list
## is non-empty; otherwise the game's own query is used unchanged.
func _nearest_touch(point: Vector3, ignore: Array) -> Dictionary:
	var touch: Variant = pony.get("touch_body") if is_instance_valid(pony) else null
	if touch == null or not touch.has_method("nearest"):
		return {}
	var near: Dictionary = touch.call("nearest", point)
	if ignore.is_empty():
		return near
	var entry: Variant = near.get("entry")
	if entry is Dictionary and not _region_ignored(
			str((entry as Dictionary).get("region", "")), ignore):
		return near
	var entries: Variant = touch.get("_entries")
	if not entries is Array:
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for e: Variant in entries:
		if not e is Dictionary:
			continue
		var ed: Dictionary = e
		if _region_ignored(str(ed.get("region", "")), ignore):
			continue
		var world: Variant = ed.get("world")
		if not world is Transform3D:
			continue
		var local: Vector3 = (world as Transform3D).affine_inverse() * point
		var a: Vector3 = ed.get("a", Vector3.ZERO)
		var b: Vector3 = ed.get("b", Vector3.ZERO)
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var away := local - (a + ab * t)
		var distance := away.length() - float(ed.get("r", 0.0))
		if distance < best_distance:
			best_distance = distance
			var normal := Vector3.UP
			if away.length() > 0.000001:
				normal = away.normalized()
			best = {"entry": ed, "distance": distance, "local": local, "normal": normal}
	return best


## Nearest coat point/normal for a palm. FlankSurface owns the flank/rump patch; the body
## hull query covers the shoulder and any point outside that patch.
func _coat_contact(point: Vector3, outward_hint: Vector3,
		ignore: Array = []) -> Dictionary:
	if not is_instance_valid(pony):
		return {"point": point, "normal": outward_hint, "source": "fallback"}
	var outward := outward_hint.normalized()
	if outward.length_squared() < 0.5:
		outward = pony.global_basis.x.normalized()
	if is_instance_valid(_flank):
		var surface: Variant = _flank.get("surface")
		var frame: Variant = _flank.get("frame")
		var sk: Variant = pony.get("skeleton")
		if surface != null and surface.has_method("contact") and frame is Transform3D:
			if surface.has_method("update_pose") and sk is Skeleton3D:
				surface.call("update_pose", sk, frame)
			var local_point: Vector3 = (frame as Transform3D).affine_inverse() * point
			var local_palm: Vector3 = ((frame as Transform3D).basis.inverse() * -outward).normalized()
			var radii: Variant = _flank.get("radii")
			var reach := float((radii as Vector3).z) if radii is Vector3 else 0.10
			var hit: Dictionary = surface.call("contact", local_point, local_point, local_palm, reach)
			var hit_local: Variant = hit.get("position")
			var normal_local: Variant = hit.get("normal")
			if hit_local is Vector3 and normal_local is Vector3:
				var hit_world: Vector3 = (frame as Transform3D) * (hit_local as Vector3)
				var hit_normal: Vector3 = ((frame as Transform3D).basis.inverse().transposed() \
					* (normal_local as Vector3)).normalized()
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
				return {"point": hit_world, "normal": hit_normal, "source": "flank"}
	var touch: Variant = pony.get("touch_body")
	if touch != null and touch.has_method("nearest"):
		var near: Dictionary = _nearest_touch(point, ignore)
		var entry: Variant = near.get("entry")
		var normal_local: Variant = near.get("normal")
		if entry is Dictionary and normal_local is Vector3:
			var world: Variant = (entry as Dictionary).get("world")
			if world is Transform3D:
				var hit_normal: Vector3 = ((world as Transform3D).basis \
					* (normal_local as Vector3)).normalized()
				var distance := float(near.get("distance", 0.0))
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
					distance = -distance
				return {"point": point - hit_normal * distance, "normal": hit_normal,
					"source": "hull"}
	return {"point": point, "normal": outward, "source": "fallback"}


func _palm_contact_state(side: String) -> Dictionary:
	if not _palm_contacts.has(side):
		_palm_contacts[side] = {
			"point": Vector3.INF, "normal": Vector3.UP, "basis": Basis.IDENTITY,
			"source": "", "switches": 0, "miss": 0, "logged": "",
			"normal_step": 0.0, "normal_out": 0.0,
		}
	return _palm_contacts[side]


func _reset_palm_contact(side: String) -> void:
	_palm_contacts.erase(side)


## Keep a genuine coat normal: blending toward a torso radial tilts the palm off the surface
## and presses its heel into the coat. The radial is only a fallback for a degenerate normal or
## one that points into the body.
func _palm_stable_outward(point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var wanted := hint.normalized()
	if wanted.length_squared() < 0.5:
		return _palm_radial_outward(point, hint)
	var radial := _palm_radial_outward(point, hint)
	if radial.length_squared() < 0.5:
		return wanted
	return radial if wanted.dot(radial) < 0.1 else wanted


func _palm_radial_outward(point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var scale := clampf(float(pony.get("body_scale")), 0.8, 1.6)
	var centre: Vector3 = pony.global_position + Vector3.UP * (0.55 * scale)
	var radial: Vector3 = point - centre
	if radial.length_squared() < 0.001:
		return Vector3.ZERO
	return radial.normalized()


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


func _palm_on_coat_frame(side: String, point: Vector3, outward_hint: Vector3,
		finger_hint: Vector3, smooth := true, ignore: Array = []) -> Transform3D:
	var hit := _coat_contact(point, outward_hint, ignore)
	var source := str(hit.get("source", "fallback"))
	var hit_point: Vector3 = hit.get("point", point)
	var hit_normal: Vector3 = hit.get("normal", outward_hint)
	if hit_normal.length_squared() < 0.5:
		hit_normal = outward_hint.normalized()
	hit_normal = _palm_stable_outward(hit_point, hit_normal)
	var clearance := _palm_clearance()
	if not smooth:
		return Transform3D(palm_surface_basis(side, hit_normal, finger_hint),
			hit_point + hit_normal * clearance)
	var state := _palm_contact_state(side)
	var last_point: Vector3 = state.point
	var last_normal: Vector3 = state.normal
	var have := last_point.is_finite()
	var changed := source != str(state.source)
	if changed:
		state.switches = int(state.switches) + 1
	else:
		state.switches = 0
	var accept := not changed or int(state.switches) >= PALM_CONTACT_SOURCE_HITS or not have
	if not changed and have and last_normal.dot(hit_normal) < -0.5:
		# A near-opposite normal under the same source is a bad triangle/hull frame; do not
		# let the palm rotate through the body. Smaller changes update the point and blend.
		hit_normal = last_normal
		accept = false
	if source == "fallback":
		state.miss = int(state.miss) + 1
		if have:
			accept = false
	else:
		state.miss = 0
	if not accept and have:
		hit_point = last_point
		hit_normal = last_normal
	if accept:
		state.source = source
	var smooth_point := hit_point
	var smooth_normal := hit_normal
	var normal_step := 0.0
	var normal_out := 0.0
	if have:
		var step := smooth_point - last_point
		if step.length() > PALM_CONTACT_MAX_STEP_M:
			smooth_point = last_point + step.normalized() * PALM_CONTACT_MAX_STEP_M
		var frame_delta := maxf(runtime.get_physics_process_delta_time(), 0.001)
		var alpha := 1.0 - exp(-PALM_CONTACT_SMOOTH * frame_delta)
		smooth_point = last_point.lerp(smooth_point, alpha)
		var blended := last_normal.lerp(hit_normal, alpha)
		if blended.length_squared() < 0.5:
			blended = hit_normal
		else:
			blended = blended.normalized()
		var max_step := deg_to_rad(PALM_NORMAL_MAX_DEG_S) * frame_delta
		smooth_normal = rotate_normal_toward(last_normal, blended, max_step)
		# A stale normal must never tuck the palm into the coat. Rotate back toward the
		# outward hint at the bounded rate; only a frame that is already bad snaps out.
		var outward := outward_hint.normalized()
		if outward.length_squared() < 0.5:
			outward = last_normal
		if outward.length_squared() > 0.5:
			normal_out = rad_to_deg(smooth_normal.angle_to(outward))
			if smooth_normal.dot(outward) < 0.1:
				smooth_normal = rotate_normal_toward(last_normal, outward, max_step)
				if smooth_normal.dot(outward) < 0.1:
					smooth_normal = outward
		normal_step = rad_to_deg(last_normal.angle_to(smooth_normal))
	# The palm plane is rebuilt from the final normal every frame, not slerped on its own,
	# so it cannot lag around and rotate into her between contact updates.
	var smooth_basis := palm_surface_basis(side, smooth_normal, finger_hint)
	state.point = smooth_point
	state.normal = smooth_normal
	state.basis = smooth_basis
	state.normal_step = normal_step
	state.normal_out = normal_out
	if str(state.logged) != source:
		state.logged = source
		_log("palm contact side=%s source=%s point=%s normal=%s" % [
			side, source, str(smooth_point), str(smooth_normal)])
	var palm := smooth_point + smooth_normal * clearance
	return Transform3D(smooth_basis, palm)


func _palm_clearance() -> float:
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = float(pony.get("body_scale"))
	var distance := PALM_ON_COAT_CLEARANCE_M
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		distance = float((caress as Dictionary).get("palm_distance", distance))
	return palm_clearance_for(scale, distance)


## Slow oval palm movement on the chosen flank/side.
func _set_caress_hand(side: String) -> void:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank):
		return
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	var index := 0 if side == "L" else 1
	if not centers is Array or index >= (centers as Array).size() \
			or not normals is Array or index >= (normals as Array).size():
		return
	var centre: Variant = (centers as Array)[index]
	var normal_local: Variant = (normals as Array)[index]
	if not centre is Vector3 or not normal_local is Vector3:
		return
	var frame: Transform3D = _flank.global_transform
	var centre_world: Vector3 = frame * (centre as Vector3)
	var normal: Vector3 = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
	if normal.length_squared() < 0.001:
		return
	# Keep the offset on the outside of the body even if the stored normal is inverted.
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == "L":
		outward = -outward
	if normal.dot(outward) < 0.0:
		normal = -normal
	var size := float(runtime.call("_size_scale"))
	var profile := _caress_profile()
	var flank_world: Vector3 = centre_world \
		+ Vector3.UP * (float(profile.get("up", 0.16)) + CARESS_UP_BIAS_M) \
		+ pony.global_basis.z.normalized() * float(profile.get("back", 0.08)) \
		+ outward * float(profile.get("out", 0.0))
	var shoulder_world: Vector3 = flank_world
	var shoulder_info := _shoulder_hand_point(side)
	if not shoulder_info.is_empty():
		shoulder_world = shoulder_info["palm"]
	var side_world: Vector3 = flank_world.lerp(shoulder_world, 0.5) + Vector3.DOWN * (0.06 * size)
	var rump_top: Vector3 = flank_world + Vector3.UP * (0.12 * size) + outward * (0.02 * size)
	var lean := clampf(float(runtime.get("_lean_forward")), -1.0, 1.0)
	var target_normal := outward
	if lean < 0.0:
		var t := clampf(-lean / CARESS_RUMP_LEAN, 0.0, 1.0)
		centre_world = flank_world.lerp(rump_top, t)
		target_normal = normal.lerp(Vector3.UP, t).normalized()
	elif lean <= 0.5:
		var t := lean * 2.0
		centre_world = flank_world.lerp(side_world, t)
		target_normal = normal.lerp(outward, t).normalized()
	else:
		var t := (lean - 0.5) * 2.0
		centre_world = side_world.lerp(shoulder_world, t)
	normal = target_normal
	var up := Vector3.UP.slide(normal)
	if up.length_squared() < 0.001:
		# On the rump top the world-up tangent collapses; use the body axis instead.
		up = -pony.global_basis.z.slide(normal)
	up = up.normalized()
	var across := up.cross(normal).normalized()
	var angle := float(_caress_phase[side])
	var offset := (across * (cos(angle) * CARESS_OVAL_ACROSS)
		+ up * (sin(angle) * CARESS_OVAL_UP)) * (CARESS_RADIUS_M * size)
	var hand_side := "left" if side == "L" else "right"
	var target := _palm_on_coat_frame(hand_side, centre_world + offset, normal,
		-pony.global_basis.z, true, _caress_ignore())
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
		_log("caress hand side=%s target=%s normal=%s x=%s y=%s z=%s lift=%.3f" % [
			hand_side, str(target.origin), str(normal), str(target.basis.x),
			str(target.basis.y), str(target.basis.z),
			(centre_world + offset).y - pony.global_position.y])
	if Time.get_ticks_msec() >= _caress_diag_at:
		_caress_diag_at = Time.get_ticks_msec() + 1000
		_caress_diag(hand_side, target, centre_world + offset, shoulder_world, side)
	var driver: Node = runtime.call("_desktop_pose_driver")
	if is_instance_valid(driver) and driver.has_method("set_hold_target"):
		driver.call("set_hold_target", hand_side, target, "rub")


## Once a second while a hand caresses: where the rub sits relative to her root/shoulder, how
## far the driven hand is from its target, and whether the contact is missing or switching.
func _caress_diag(hand_side: String, target: Transform3D, rub_point: Vector3,
		shoulder_point: Vector3, side: String) -> void:
	if not is_instance_valid(pony):
		return
	var root_y: float = pony.global_position.y
	var state := _palm_contact_state(hand_side)
	var hand_dist := -1.0
	var driver: Node = runtime.call("_desktop_pose_driver")
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var frame_v: Variant = driver.call("hand_frame", hand_side)
		if frame_v is Transform3D and (frame_v as Transform3D).is_finite():
			hand_dist = (frame_v as Transform3D).origin.distance_to(target.origin)
	_log("caress diag side=%s rub_h=%.3f shoulder_h=%.3f hand_dist=%.3f source=%s miss=%d switches=%d normal_step=%.1f normal_out=%.1f" % [
		side, rub_point.y - root_y, shoulder_point.y - root_y, hand_dist,
		str(state.source), int(state.miss), int(state.switches),
		float(state.get("normal_step", 0.0)), float(state.get("normal_out", 0.0))])


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
	var source := "caress" if _caress_active["L"] or _caress_active["R"] else "lean"
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
			var zone_radius := float(_profile.get("smack_zone_radius", SMACK_ZONE_RADIUS_M))
			var radius := sqrt(randf()) * maxf(0.0, zone_radius)
			at = (centre as Vector3) + back_local * (SMACK_BACK_M + cos(angle) * radius) \
				+ up_local * (SMACK_UP_M + sin(angle) * radius)
			var frame: Transform3D = _flank.global_transform
			normal = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
			var outward: Vector3 = (frame * (centre as Vector3)) - pony.global_position
			outward.y = 0.0
			if outward.length_squared() > 0.001 and normal.dot(outward.normalized()) < 0.0:
				normal = -normal
	_last_smack_ms = now
	if at.is_finite() and is_instance_valid(main) and is_instance_valid(main.player):
		var driver: Node = runtime.call("_desktop_pose_driver")
		var from_frame := Transform3D.IDENTITY
		if is_instance_valid(driver) and driver.has_method("hand_frame"):
			var current: Variant = driver.call("hand_frame", hand_side)
			if current is Transform3D and (current as Transform3D).is_finite():
				from_frame = current
		if is_instance_valid(driver) and from_frame.is_finite():
			var world_centre: Vector3 = _flank.global_transform * at
			var target := _palm_on_coat_frame(hand_side, world_centre, normal, Vector3.UP, false)
			_smack_from = from_frame
			_smack_to = target
			_smack_index = index
			_smack_at = at
			_smack_side = hand_side
			_smack_started = now
			_smack_impact_done = false
			_smack_active = true
			_log("smack swing side=%.2f cheek=%s at=%s hand=%s source=%s" % [
				float(runtime.get("_lean_side")), "L" if index == 0 else "R", str(at), hand_side, source])
			return
	_flank_impact_without_reaction(index, at)
	runtime.call("_on_touch", "smack")
	_log("smack side=%.2f cheek=%s at=%s (instant)" % [
		float(runtime.get("_lean_side")), "L" if index == 0 else "R", str(at)])


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


func _end_smack_swing() -> void:
	if not _smack_active:
		return
	if not _smack_side.is_empty():
		var driver: Node = runtime.call("_desktop_pose_driver")
		var caress_side := "L" if _smack_side == "left" else "R"
		if bool(_caress_active[caress_side]):
			# The smack may have moved the tail or another soft hull next to the rub point.
			# Drop the cached source/normal and reacquire the caress contact before returning.
			var from := _smack_to
			if is_instance_valid(driver) and driver.has_method("hand_frame"):
				var current: Variant = driver.call("hand_frame", _smack_side)
				if current is Transform3D and (current as Transform3D).is_finite():
					from = current
			_reset_palm_contact(_smack_side)
			_caress_return_from[caress_side] = from
			_caress_return_started[caress_side] = Time.get_ticks_msec()
			_set_caress_hand(caress_side)
			_log("smack return side=%s caress=%s target=%s" % [
				_smack_side, caress_side,
				str(_palm_contact_state(_smack_side).get("point", Vector3.INF))])
		elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _smack_side)
	_smack_active = false
	_smack_side = ""
	_smack_at = Vector3.INF
	_smack_impact_done = false


## Native impact, but with the pony's game reaction signals silenced. During an act those
## reactions can trigger a buck/fidget or hoof shuffle, which is not wanted for a sex smack.
func _flank_impact_without_reaction(index: int, at: Vector3) -> void:
	if not is_instance_valid(pony) or not pony.has_signal("physical_reaction"):
		_flank.call("impact", index, at)
		return
	var sig: Signal = pony.physical_reaction
	var links: Array = sig.get_connections()
	_log("smack reaction suppressed links=%d" % links.size())
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and sig.is_connected(callable):
			sig.disconnect(callable)
	_flank.call("impact", index, at)
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and not sig.is_connected(callable):
			sig.connect(callable)


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
	if not _reach_shoulder.is_empty():
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
	_reach_hand_returning = false
	_reach_hand_started = 0
	_reach_hand_logged = false
	_set_reach_hand()


func end_reach() -> void:
	_begin_reach_release()


func reset() -> void:
	_end_caress()
	_end_smack_swing()
	_clear_reach_hand()
	_reach_shoulder = ""
	_palm_contacts.clear()
	_caress_latched = {"L": false, "R": false}
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_diag_at = 0


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
