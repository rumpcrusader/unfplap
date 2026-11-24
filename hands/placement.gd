extends RefCounted
## Pose-free palm placement: oval, sphere snap, smoothing and the single-point palm frame.

const PERF := preload("res://mods/unfplap/shared/perf.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")
const COAT := preload("res://mods/unfplap/hands/contact.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const PALM_CONTACT_MAX_STEP_M := 0.06
const PALM_CONTACT_SOURCE_HITS := 2
## The most path candidates one hand tries in a frame.
const MAX_CANDIDATES := 3

var _states: Dictionary[String, MODEL.ContactState] = {}
var _last: Dictionary[String, Transform3D] = {}
var _logged: Dictionary[String, bool] = {}
var _debug: Dictionary[String, MODEL.DebugState] = {}


## Pure palm clearance: the setting distance scaled by the pony's body scale.
static func palm_clearance_for(body_scale: float, distance := 0.02) -> float:
	return distance * clampf(body_scale, 0.5, 2.0)


## Build the palm frame for one hand from the path's ordered candidates.
func frame(pony: Node3D, path: PATH_BASE, side: MODEL.Side,
		context: MODEL.CaressContext) -> Transform3D:
	if not is_instance_valid(pony) or path == null:
		return _last_or_invalid(side)
	var candidates: Array[MODEL.Candidate] = path.candidates(side, context)
	if candidates.is_empty():
		return _last_or_invalid(side)
	for index in mini(candidates.size(), MAX_CANDIDATES):
		var candidate: MODEL.Candidate = candidates[index]
		var target := _place_candidate(side, candidate, context)
		if target.is_finite() and target.origin.length_squared() > 0.0001:
			_last[side_key(side)] = target
			return target
	return _last_or_invalid(side)


## Hull placement used by the reach hand and the smack recovery. The caress never comes through
## here: a contact that only the body hull could give is not a caress.
func coat_frame(pony: Node3D, side: MODEL.Side, point: Vector3, outward_hint: Vector3,
		finger: Vector3, clearance: float, context: MODEL.CoatContext) -> Transform3D:
	var key := context.state_key if not context.state_key.is_empty() else side_key(side)
	var hit := COAT.contact(pony, point, outward_hint, context.ignore, context.regions)
	var source := hit.source
	var hit_point := hit.point
	var hit_normal := hit.normal
	if hit_normal.length_squared() < 0.5:
		hit_normal = outward_hint.normalized()
	hit_normal = COAT.stable_outward(pony, hit_point, hit_normal, context.radial)
	if context.contact_smooth <= 0.0:
		return HAND.place(hit_point, hit_normal, finger, side_key(side), "palm", 0.0,
			clearance + context.extra_hover)
	var state := _state(key)
	var smoothed := _smooth_hull(state, hit_point, hit_normal, source,
		maxf(context.delta, 0.001), context)
	return HAND.place(smoothed.point, smoothed.normal, finger, side_key(side), "palm", 0.0,
		clearance + context.extra_hover)


## The per-hand hull state, used by the smack target to reuse the live flank contact.
func contact_state(side: MODEL.Side) -> MODEL.ContactState:
	var state: MODEL.ContactState = _states.get(side_key(side))
	return state


func debug_state(side: MODEL.Side) -> MODEL.DebugState:
	var debug: MODEL.DebugState = _debug.get(side_key(side))
	return debug


func last(side: MODEL.Side) -> Transform3D:
	var value: Transform3D = _last.get(side_key(side), Transform3D(Basis(), Vector3(INF, INF, INF)))
	return value


func reset_hand(side: MODEL.Side, key := "") -> void:
	var state_key := key if not key.is_empty() else side_key(side)
	_states.erase(state_key)
	_last.erase(state_key)
	_logged.erase(state_key)
	_debug.erase(state_key)


func reset() -> void:
	_states.clear()
	_last.clear()
	_logged.clear()
	_debug.clear()


func _place_candidate(side: MODEL.Side, candidate: MODEL.Candidate,
		context: MODEL.CaressContext) -> Transform3D:
	var point := candidate.point
	if not point.is_finite():
		return Transform3D(Basis(), Vector3(INF, INF, INF))
	var normal := candidate.normal
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var radii := context.oval
	var oval_x := candidate.oval_x
	var oval_y := candidate.oval_y
	if oval_x.length_squared() < 0.0001:
		oval_x = normal.cross(Vector3.UP)
	if oval_y.length_squared() < 0.0001:
		oval_y = normal.cross(oval_x)
	oval_x = oval_x.normalized()
	oval_y = oval_y.normalized()
	var intended := point \
		+ oval_x * (cos(context.phase) * radii.x) \
		+ oval_y * (sin(context.phase) * radii.y)
	# Skipping the projection keeps a moving head path exact.
	if candidate.exact:
		var exact_target := HAND.place(intended, normal, candidate.finger, side_key(side),
			candidate.mode, candidate.roll, context.hover)
		var debug := MODEL.DebugState.new()
		debug.candidate = candidate
		debug.intended = intended
		debug.contact = intended
		debug.normal = normal
		debug.target = exact_target
		_debug[side_key(side)] = debug
		return exact_target
	return _place_precise(side, candidate, context, intended, normal)


## Project the intended oval point onto the candidate's fitted sphere, then place the palm.
func _place_precise(side: MODEL.Side, candidate: MODEL.Candidate,
		context: MODEL.CaressContext, intended: Vector3, normal: Vector3) -> Transform3D:
	PERF.begin("caress_contact")
	var contact := intended
	var contact_normal := normal
	if candidate.center.is_finite() and candidate.radius > 0.0:
		var direction: Vector3 = intended - candidate.center
		if direction.length_squared() > 0.000001:
			contact_normal = direction.normalized()
			contact = candidate.center + contact_normal * candidate.radius
	PERF.end("caress_contact")
	var delta := maxf(context.delta, 0.001)
	var smoothed := _smooth_precise(_state(side_key(side)), intended, contact, contact_normal,
		delta, context)
	var target := HAND.place(smoothed.point, smoothed.normal, candidate.finger, side_key(side),
		candidate.mode, candidate.roll, context.hover)
	var debug := MODEL.DebugState.new()
	debug.candidate = candidate
	debug.intended = intended
	debug.contact = smoothed.point
	debug.normal = smoothed.normal
	debug.target = target
	debug.radius = candidate.radius
	_debug[side_key(side)] = debug
	_log_precise(side, candidate, target, context)
	return target


func _state(key: String) -> MODEL.ContactState:
	if not _states.has(key):
		_states[key] = MODEL.ContactState.new()
	return _states[key]


## Only the correction from the intended point to the sphere hit is low-passed.
func _smooth_precise(state: MODEL.ContactState, intended: Vector3, hit: Vector3,
		normal: Vector3, delta: float, context: MODEL.CaressContext) -> MODEL.ContactState:
	var fresh := state.source != "precise" or not state.offset_valid
	var offset := hit - intended
	if fresh:
		state.offset = offset
	else:
		var rate := maxf(context.contact_smooth, 0.0)
		if rate > 0.0:
			var alpha := 1.0 - exp(-rate * delta)
			state.offset = state.offset.lerp(offset, alpha)
		else:
			state.offset = offset
	var point := intended + state.offset
	var final_normal := normal
	var max_turn := deg_to_rad(maxf(context.normal_deg_s, 0.0)) * delta
	if not fresh and state.normal_valid and max_turn > 0.0:
		final_normal = HAND.rotate_normal_toward(state.normal, normal, max_turn)
	elif not fresh and state.normal_valid:
		final_normal = normal
	state.point = point
	state.normal = final_normal
	state.normal_valid = true
	state.source = "precise"
	state.offset_valid = true
	return state


func _smooth_hull(state: MODEL.ContactState, hit_point: Vector3, hit_normal: Vector3,
		source: String, delta: float, context: MODEL.CoatContext) -> MODEL.ContactState:
	var last_point := state.point
	var last_normal := state.normal
	var have := last_point.is_finite()
	var changed := source != state.source
	if changed:
		state.switches += 1
	else:
		state.switches = 0
	var accept := not changed or state.switches >= PALM_CONTACT_SOURCE_HITS or not have
	if not changed and have and last_normal.dot(hit_normal) < -0.5:
		# A near-opposite normal under the same source is a bad triangle/hull frame; do not
		# let the palm rotate through the body.
		hit_normal = last_normal
		accept = false
	if source == "fallback":
		state.miss += 1
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
	if have:
		var step := smooth_point - last_point
		if step.length() > PALM_CONTACT_MAX_STEP_M:
			smooth_point = last_point + step.normalized() * PALM_CONTACT_MAX_STEP_M
		var rate := maxf(context.contact_smooth, 0.0)
		var alpha := 1.0 - exp(-rate * delta) if rate > 0.0 else 1.0
		smooth_point = last_point.lerp(smooth_point, alpha)
		var blended := last_normal.lerp(hit_normal, alpha)
		if blended.length_squared() < 0.5:
			blended = hit_normal
		else:
			blended = blended.normalized()
		var max_step := deg_to_rad(maxf(context.normal_deg_s, 0.0)) * delta
		if max_step > 0.0:
			smooth_normal = HAND.rotate_normal_toward(last_normal, blended, max_step)
		else:
			smooth_normal = blended
		# A stale normal must never tuck the palm into the coat.
		var outward := hit_normal.normalized()
		if outward.length_squared() > 0.5 and smooth_normal.dot(outward) < 0.1:
			if max_step > 0.0:
				smooth_normal = HAND.rotate_normal_toward(last_normal, outward, max_step)
			else:
				smooth_normal = outward
			if smooth_normal.dot(outward) < 0.1:
				smooth_normal = outward
	state.point = smooth_point
	state.normal = smooth_normal
	state.normal_valid = true
	return state


func _last_or_invalid(side: MODEL.Side) -> Transform3D:
	var value: Transform3D = _last.get(side_key(side), Transform3D(Basis(), Vector3(INF, INF, INF)))
	return value


func _log_precise(side: MODEL.Side, candidate: MODEL.Candidate, frame: Transform3D,
		context: MODEL.CaressContext) -> void:
	if not context.debug:
		return
	var key := side_key(side)
	if bool(_logged.get(key, false)):
		return
	_logged[key] = true
	LOG.debug("precise caress side=%s mode=%s u=%.2f target=%s normal=%s finger=%s roll=%.0f over=%.3f r=%.3f", [
		key, candidate.mode, candidate.u, str(frame.origin), str(candidate.normal),
		str(candidate.finger), candidate.roll, context.hover, candidate.radius])


static func side_key(side: MODEL.Side) -> String:
	return MODEL.side_key(side)
