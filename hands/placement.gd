extends RefCounted
## Pose-free palm placement. A path supplies where the hand should be on the body; this
## engine applies the oval, snaps it to the coat, smooths the contact and builds the palm frame.
## It never reads the pose, the input or the camera.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SURFACE := preload("res://mods/unfplap/hands/surface.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")
const COAT := preload("res://mods/unfplap/hands/contact.gd")

const PALM_CONTACT_MAX_STEP_M := 0.06
const PALM_CONTACT_SOURCE_HITS := 2

var facts: Variant

var _surfaces: Dictionary = {}
var _states: Dictionary = {}
var _last: Dictionary = {}
var _logged: Dictionary = {}
var _debug: Dictionary = {}


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


## Build the palm frame for one hand. `path` is a hand path (see hands/path_base.gd), and
## `context` carries lean, oval phase/radii, hover and the snap state. Returns an invalid
## transform when the path and the last good target are both unavailable.
func frame(pony: Variant, path: Variant, hand_side: String, context: Dictionary) -> Transform3D:
	if not is_instance_valid(pony) or path == null:
		return _last_or_invalid(hand_side)
	var list: Variant = path.call("candidates", hand_side, context)
	if not list is Array or (list as Array).is_empty():
		return _last_or_invalid(hand_side)
	for candidate_value: Variant in (list as Array):
		if not candidate_value is Dictionary:
			continue
		var candidate: Dictionary = candidate_value
		var target := _place_candidate(pony, hand_side, candidate, context)
		if target.is_finite() and target.origin.length_squared() > 0.0001:
			_last[hand_side] = target
			return target
	return _last_or_invalid(hand_side)


## Hull placement used by the reach hand and the smack recovery. `smooth` false keeps the
## exact contact for a one-shot frame.
func coat_frame(pony: Variant, hand_side: String, point: Vector3, outward_hint: Vector3,
		finger: Vector3, clearance: float, smooth := true, delta := 0.016,
		ignore: Array = [], radial := true, regions: Array = [],
		extra_hover := 0.0, state_key := "") -> Transform3D:
	var key := state_key if not state_key.is_empty() else hand_side
	var hit := COAT.contact(pony, point, outward_hint, ignore, regions)
	var source := str(hit.get("source", "fallback"))
	var hit_point: Vector3 = hit.get("point", point)
	var hit_normal: Vector3 = hit.get("normal", outward_hint)
	if hit_normal.length_squared() < 0.5:
		hit_normal = outward_hint.normalized()
	hit_normal = COAT.stable_outward(pony, hit_point, hit_normal, radial)
	var target_kind := "palm"
	if not smooth:
		return HAND.place(hit_point, hit_normal, finger, hand_side, target_kind, 0.0,
			clearance + extra_hover)
	var state := _state(key)
	var smoothed := _smooth_hull(state, hit_point, hit_normal, source, maxf(delta, 0.001))
	var target := HAND.place(smoothed["point"], smoothed["normal"], finger, hand_side,
		target_kind, 0.0, clearance + extra_hover)
	return target


## The per-hand hull state, used by the smack target to reuse the live flank contact.
func contact_state(hand_side: String) -> Dictionary:
	if not _states.has(hand_side):
		return {}
	return _states[hand_side]


func debug_state(hand_side: String) -> Dictionary:
	var value: Variant = _debug.get(hand_side)
	return value if value is Dictionary else {}


func last(hand_side: String) -> Transform3D:
	var value: Variant = _last.get(hand_side)
	if value is Transform3D and (value as Transform3D).is_finite():
		return value
	return Transform3D(Basis(), Vector3(INF, INF, INF))


func reset_hand(hand_side: String) -> void:
	_states.erase(hand_side)
	_last.erase(hand_side)
	_logged.erase(hand_side)
	_debug.erase(hand_side)


func reset() -> void:
	_surfaces.clear()
	_states.clear()
	_last.clear()
	_logged.clear()
	_debug.clear()


func _place_candidate(pony: Variant, hand_side: String, candidate: Dictionary,
		context: Dictionary) -> Transform3D:
	var point: Vector3 = candidate.get("point", Vector3.INF)
	if not point.is_finite():
		return Transform3D(Basis(), Vector3(INF, INF, INF))
	var normal: Vector3 = candidate.get("normal", Vector3.UP)
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var oval: Variant = context.get("oval", Vector2(0.01, 0.02))
	var radii: Vector2 = oval if oval is Vector2 else Vector2(0.01, 0.02)
	var oval_x: Vector3 = candidate.get("oval_x", Vector3.RIGHT)
	var oval_y: Vector3 = candidate.get("oval_y", Vector3.UP)
	if oval_x.length_squared() < 0.0001:
		oval_x = normal.cross(Vector3.UP)
	if oval_y.length_squared() < 0.0001:
		oval_y = normal.cross(oval_x)
	oval_x = oval_x.normalized()
	oval_y = oval_y.normalized()
	var phase := float(context.get("phase", 0.0))
	var intended := point \
		+ oval_x * (cos(phase) * (radii as Vector2).x) \
		+ oval_y * (sin(phase) * (radii as Vector2).y)
	var finger: Vector3 = candidate.get("finger", Vector3.FORWARD)
	var mode := str(candidate.get("mode", "palm"))
	var roll := float(candidate.get("roll", 0.0))
	var region := str(candidate.get("region", "torso"))
	var hover := float(context.get("hover", 0.0))
	return _place_precise(pony, hand_side, candidate, context, intended, normal,
		finger, mode, roll, region, hover)


func _place_precise(pony: Variant, hand_side: String, candidate: Dictionary,
		context: Dictionary, intended: Vector3, normal: Vector3, finger: Vector3,
		mode: String, roll: float, region: String, hover: float) -> Transform3D:
	var surface_started := Time.get_ticks_usec()
	var surface: Variant = _surface(pony, region, hand_side, intended)
	if not is_instance_valid(surface):
		_perf_note("caress_surface", Time.get_ticks_usec() - surface_started)
		return _last_or_invalid(hand_side)
	var hit: Variant = surface.call("nearest", intended, normal)
	if not hit is Dictionary or (hit as Dictionary).is_empty():
		_perf_note("caress_surface", Time.get_ticks_usec() - surface_started)
		return _last_or_invalid(hand_side)
	var hit_point: Vector3 = (hit as Dictionary).get("point", intended)
	var hit_normal: Vector3 = (hit as Dictionary).get("normal", normal)
	if hit_normal.length_squared() < 0.5:
		hit_normal = normal
	hit_normal = hit_normal.normalized()
	var scale := maxf(float(context.get("scale", 1.0)), 0.1)
	var blur := maxf(float(SETTINGS.normal_blur_m.get_num()) * scale, 0.0)
	var face := int(hit.get("face", -1))
	var seed := int(hit.get("seed", -1))
	if blur > 0.0 and face >= 0:
		var blurred: Vector3 = surface.call("normal_blur", hit_point, blur, hit_normal, seed)
		if blurred.length_squared() > 0.5:
			hit_normal = blurred.normalized()
	_perf_note("caress_surface", Time.get_ticks_usec() - surface_started)
	var delta := maxf(float(context.get("delta", 0.001)), 0.001)
	var smoothed := _smooth_precise(_state(hand_side), intended, hit_point, hit_normal, delta)
	var contact: Vector3 = smoothed["point"]
	var contact_normal: Vector3 = smoothed["normal"]
	var target := HAND.place(contact, contact_normal, finger, hand_side, mode, roll, hover)
	_debug[hand_side] = {
		"candidate": candidate,
		"intended": intended,
		"contact": contact,
		"normal": contact_normal,
		"target": target,
		"surface": surface,
	}
	_log_precise(hand_side, mode, surface, target, roll, hover, contact_normal, finger,
		float(candidate.get("u", 0.0)))
	return target


func _surface(pony: Variant, region: String, hand_side: String, point: Vector3) -> Variant:
	# With the local window each hand keeps its own patch: the hands caress opposite flanks, so
	# one shared window would re-centre on every tick. The stable source cache still shares the
	# mesh gather. With the window off the hands share one full patch, as before.
	var local := _local_patch()
	var key := (region + "|" + hand_side) if local else region
	var surface: Variant = _surfaces.get(key)
	if not is_instance_valid(surface):
		surface = SURFACE.new(facts)
		_surfaces[key] = surface
	if not bool(surface.call("ensure", pony, region)):
		return null
	surface.call("set_local", local)
	surface.call("select", point)
	surface.call("set_quality", _quality())
	surface.call("update_pose")
	return surface


## `caress_quality` from the act snapshot. A bare engine (tests) keeps the precise default.
func _quality() -> String:
	if facts == null:
		return "precise"
	return str(facts.caress_quality)


## `features.caress_local` from the act snapshot. A bare engine (tests) keeps the full patch.
func _local_patch() -> bool:
	if facts == null:
		return false
	return bool(facts.feature("caress_local", true))


func _state(key: String) -> Dictionary:
	if not _states.has(key):
		_states[key] = {
			"point": Vector3.INF,
			"normal": Vector3.UP,
			"source": "",
			"switches": 0,
			"miss": 0,
			"offset": Vector3.ZERO,
			"offset_valid": false,
			"normal_valid": false,
		}
	return _states[key]


## The intended contact is never delayed: only the correction from the intended point to the
## exact surface hit is low-passed. A moving oval therefore keeps its size and speed, while a
## triangle flip at a crease is eased.
func _smooth_precise(state: Dictionary, intended: Vector3, hit: Vector3, normal: Vector3,
		delta: float) -> Dictionary:
	var fresh := str(state.get("source", "")) != "precise" \
		or not bool(state.get("offset_valid", false))
	var offset := hit - intended
	if fresh:
		state["offset"] = offset
	else:
		var rate := maxf(float(SETTINGS.contact_smooth.get_num()), 0.0)
		if rate > 0.0:
			var alpha := 1.0 - exp(-rate * delta)
			state["offset"] = (state["offset"] as Vector3).lerp(offset, alpha)
		else:
			state["offset"] = offset
	var point := intended + (state["offset"] as Vector3)
	var final_normal := normal
	var max_turn := deg_to_rad(maxf(float(SETTINGS.normal_deg_s.get_num()), 0.0)) * delta
	if not fresh and bool(state.get("normal_valid", false)) and max_turn > 0.0:
		final_normal = HAND.rotate_normal_toward(state["normal"] as Vector3, normal, max_turn)
	elif not fresh and bool(state.get("normal_valid", false)):
		final_normal = normal
	state["point"] = point
	state["normal"] = final_normal
	state["normal_valid"] = true
	state["source"] = "precise"
	state["offset_valid"] = true
	return {"point": point, "normal": final_normal}


func _smooth_hull(state: Dictionary, hit_point: Vector3, hit_normal: Vector3,
		source: String, delta: float) -> Dictionary:
	var last_point: Vector3 = state.get("point", Vector3.INF)
	var last_normal: Vector3 = state.get("normal", Vector3.UP)
	var have := last_point.is_finite()
	var changed := source != str(state.get("source", ""))
	if changed:
		state["switches"] = int(state.get("switches", 0)) + 1
	else:
		state["switches"] = 0
	var accept := not changed or int(state.get("switches", 0)) >= PALM_CONTACT_SOURCE_HITS \
		or not have
	if not changed and have and last_normal.dot(hit_normal) < -0.5:
		# A near-opposite normal under the same source is a bad triangle/hull frame; do not
		# let the palm rotate through the body. Smaller changes update the point and blend.
		hit_normal = last_normal
		accept = false
	if source == "fallback":
		state["miss"] = int(state.get("miss", 0)) + 1
		if have:
			accept = false
	else:
		state["miss"] = 0
	if not accept and have:
		hit_point = last_point
		hit_normal = last_normal
	if accept:
		state["source"] = source
	var smooth_point := hit_point
	var smooth_normal := hit_normal
	if have:
		var step := smooth_point - last_point
		if step.length() > PALM_CONTACT_MAX_STEP_M:
			smooth_point = last_point + step.normalized() * PALM_CONTACT_MAX_STEP_M
		var rate := maxf(float(SETTINGS.contact_smooth.get_num()), 0.0)
		var alpha := 1.0 - exp(-rate * delta) if rate > 0.0 else 1.0
		smooth_point = last_point.lerp(smooth_point, alpha)
		var blended := last_normal.lerp(hit_normal, alpha)
		if blended.length_squared() < 0.5:
			blended = hit_normal
		else:
			blended = blended.normalized()
		var max_step := deg_to_rad(maxf(float(SETTINGS.normal_deg_s.get_num()), 0.0)) * delta
		if max_step > 0.0:
			smooth_normal = HAND.rotate_normal_toward(last_normal, blended, max_step)
		else:
			smooth_normal = blended
		# A stale normal must never tuck the palm into the coat. Rotate back toward the
		# resolved contact normal at the bounded rate.
		var outward := hit_normal.normalized()
		if outward.length_squared() > 0.5:
			if smooth_normal.dot(outward) < 0.1:
				if max_step > 0.0:
					smooth_normal = HAND.rotate_normal_toward(last_normal, outward, max_step)
				else:
					smooth_normal = outward
				if smooth_normal.dot(outward) < 0.1:
					smooth_normal = outward
	state["point"] = smooth_point
	state["normal"] = smooth_normal
	state["normal_valid"] = true
	return {"point": smooth_point, "normal": smooth_normal}


func _last_or_invalid(hand_side: String) -> Transform3D:
	var value: Variant = _last.get(hand_side)
	if value is Transform3D and (value as Transform3D).is_finite():
		return value
	return Transform3D(Basis(), Vector3(INF, INF, INF))


func _log_precise(hand_side: String, mode: String, surface: Variant, frame: Transform3D,
		roll_deg: float, hover: float, normal: Vector3, finger: Vector3,
		u: float) -> void:
	if not bool(SETTINGS.caress_debug.get_bool()):
		return
	if bool(_logged.get(hand_side, false)):
		return
	_logged[hand_side] = true
	var info := "anchors"
	if is_instance_valid(surface) and surface is SURFACE:
		info = "faces=%d/%d build_us=%d query_us=%d ray_hit=%d ray_miss=%d" % [
			int(surface.call("face_count")), int(surface.call("patch_face_count")),
			int(surface.get("build_us")), int(surface.get("query_us")),
			int(surface.get("ray_hits")), int(surface.get("ray_misses"))]
	_log("precise caress side=%s mode=%s u=%.2f target=%s normal=%s finger=%s roll=%.0f over=%.3f surface=%s" % [
		hand_side, mode, u, str(frame.origin), str(normal), str(finger), roll_deg, hover, info])


func _perf_note(chunk: String, usec: int) -> void:
	if facts != null:
		facts.perf(chunk, usec)


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
	else:
		print("[unfplap] " + text)
