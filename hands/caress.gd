extends RefCounted
## Latch, stroke phase and contact credit for both palms.

const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PORT := preload("res://mods/unfplap/hands/port.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")
const ANCHORS := preload("res://mods/unfplap/hands/paths/anchors.gd")
const DEBUG_DRAW := preload("res://mods/unfplap/hands/debug_draw.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The coordinator, held weakly: it owns this module, so a strong link back would be a cycle.
var _host_ref: WeakRef = null
var _facts: ACT_FACTS = null
var _debug: DEBUG_DRAW = null
var _contexts: Array[MODEL.CaressContext] = [MODEL.CaressContext.new(), MODEL.CaressContext.new()]
var _active: Array[bool] = [false, false]
var _latched: Array[bool] = [false, false]
var _key_down: Array[bool] = [false, false]
var _moving: Array[bool] = [true, true]
var _move_key_down: Array[bool] = [false, false]
var _phase: Array[float] = [0.0, 0.0]
var _touch_seconds := 0.0
var _oral_was_active := false
var _oral_from: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _oral_started: Array[int] = [0, 0]
## Hands whose contact path still needs a warm build, one hand per tick while the act starts.
var _warm_sides: Array[MODEL.Side] = [MODEL.Side.LEFT, MODEL.Side.RIGHT]
var _profile: MODEL.CaressProfile = null
var _profile_size := ""
var _profile_scale := -1.0


func _init(port: PORT, facts: ACT_FACTS) -> void:
	_host_ref = weakref(port)
	_facts = facts
	_debug = DEBUG_DRAW.new(port)


## The coordinator, or null once it has released this module.
func _host() -> PORT:
	return _host_ref.get_ref() as PORT


func tick(delta: float) -> void:
	if _facts == null:
		return
	if _pose_family() not in ["bed", "standing"]:
		end()
		_oral_was_active = false
		return
	ANCHORS.prefit_tick(_host().pony())
	_oral_tick()
	warm()
	# Hold-X auto settings owns A/D and Z/C, so the keys freeze while the layer is open.
	var frozen := _host().frozen()
	var keys: Array[bool] = [
		Input.is_physical_key_pressed(KEY_A),
		Input.is_physical_key_pressed(KEY_D),
	]
	var motion_keys: Array[int] = [KEY_Z, KEY_C]
	for index in 2:
		var side := _side_for_index(index)
		if not frozen:
			var held: bool = keys[index]
			var pressed := held and not _key_down[index]
			_key_down[index] = held
			if pressed:
				_latched[index] = not _latched[index]
			var move_held := Input.is_physical_key_pressed(motion_keys[index])
			var move_pressed := move_held and not _move_key_down[index]
			_move_key_down[index] = move_held
			if move_pressed:
				_moving[index] = not _moving[index]
				LOG.debug("caress movement side=%s %s", [
					MODEL.side_letter(side), "on" if _moving[index] else "off"])
		# The slapping hand owns the hold target during its swing; a re-press starts after it.
		if _host().smack_owns(side):
			continue
		if _latched[index]:
			if not _active[index]:
				start(side)
			_phase[index] = MODEL.caress_phase_step(_phase[index], _moving[index], delta)
			_set_hand(side, true)
		elif _active[index]:
			end_side(side)
	_touch_tick(delta)


## Capture the live hand frame when the oral turn starts or ends, so the hand eases, not snaps.
func _oral_tick() -> void:
	var oral := _mouth_contact()
	if oral == _oral_was_active:
		return
	_oral_was_active = oral
	for index in 2:
		if not _active[index]:
			continue
		var side := _side_for_index(index)
		var frame := _host().hand_frame(side)
		if frame.is_finite():
			_oral_from[index] = frame
			_oral_started[index] = Time.get_ticks_msec()


## Count a held caress as one touch per `CARESS_TOUCH_SECONDS` of contact.
func _touch_tick(delta: float) -> void:
	var step := MODEL.caress_touch_step(_touch_seconds, any_active(), delta)
	_touch_seconds = step.seconds
	for _index in step.events:
		_host().touch("caress")


## Begin a held caress on one hand.
func start(side: MODEL.Side) -> void:
	var index := MODEL.side_index(side)
	if index < 0:
		return
	_active[index] = true
	_latched[index] = true
	_phase[index] = 0.0
	_host().engine().reset_hand(side)
	LOG.debug("caress start side=%s", [MODEL.side_letter(side)])


func end_side(side: MODEL.Side) -> void:
	var index := MODEL.side_index(side)
	if index < 0 or not _active[index]:
		return
	_host().release_hold(side)
	_host().engine().reset_hand(side)
	LOG.debug("caress stop side=%s", [MODEL.side_letter(side)])
	_active[index] = false
	_latched[index] = false
	_phase[index] = 0.0
	_oral_started[index] = 0


func end() -> void:
	end_side(MODEL.Side.LEFT)
	end_side(MODEL.Side.RIGHT)
	for index in 2:
		_key_down[index] = false
		_moving[index] = true
		_move_key_down[index] = false
		_phase[index] = 0.0
	_touch_seconds = 0.0


func active(side: MODEL.Side) -> bool:
	var index := MODEL.side_index(side)
	return index >= 0 and _active[index]


func any_active() -> bool:
	return _active[0] or _active[1]


func phase(side: MODEL.Side) -> float:
	var index := MODEL.side_index(side)
	return _phase[index] if index >= 0 else 0.0


## Warm one contact path per tick, so the first A/D of an act does not build it.
func warm() -> bool:
	if _facts == null or _warm_sides.is_empty():
		return false
	if _pose_family() not in ["bed", "standing"]:
		return false
	# The background fit fills the cache one area per tick; build each hand only when it is ready.
	if ANCHORS.prefit_pending(_host().pony()):
		return not _warm_sides.is_empty()
	var side: MODEL.Side = _warm_sides.pop_front()
	_set_hand(side, false)
	return not _warm_sides.is_empty()


## Re-arm the warm-up queue for both hands after a path change.
func warm_paths() -> void:
	_warm_sides.clear()
	_warm_sides.append(MODEL.Side.LEFT)
	_warm_sides.append(MODEL.Side.RIGHT)


func reset() -> void:
	end()
	_oral_was_active = false
	for index in 2:
		_oral_from[index] = Transform3D.IDENTITY
		_oral_started[index] = 0
	_warm_sides.clear()
	_warm_sides.append(MODEL.Side.LEFT)
	_warm_sides.append(MODEL.Side.RIGHT)
	_profile = null
	_profile_size = ""
	_profile_scale = -1.0
	_debug.clear()


func _set_hand(side: MODEL.Side, apply: bool) -> Transform3D:
	var pony := _host().pony()
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	var path := _host().path()
	if path == null:
		return Transform3D.IDENTITY
	var context := _context(side)
	PERF.begin("caress_precise")
	var target := _host().engine().frame(pony, path, side, context)
	PERF.end("caress_precise")
	if not target.is_finite() or target.origin.length_squared() < 0.0001:
		return Transform3D.IDENTITY
	if not apply:
		return target
	var index := MODEL.side_index(side)
	var oral_started := _oral_started[index]
	if oral_started > 0:
		var elapsed := float(Time.get_ticks_msec() - oral_started) / 1000.0
		if elapsed >= MODEL.CARESS_ORAL_BLEND_S:
			_oral_started[index] = 0
		else:
			target = MODEL.caress_oral_blend(_oral_from[index], target, elapsed)
	_host().hold(side, target)
	var debug := _host().engine().debug_state(side)
	if debug != null:
		_debug.draw(path, side, debug, target, context)
	return target


## Everything the pose-free engine needs for one hand this tick.
func _context(side: MODEL.Side) -> MODEL.CaressContext:
	var index := MODEL.side_index(side)
	if index < 0:
		return _contexts[0]
	var scale := _host().body_scale()
	var context := _contexts[index]
	context.side = side
	context.lean = clampf(float(_facts.lean_forward), -1.0, 1.0) if _facts != null else 0.0
	context.phase = _phase[index]
	context.scale = scale
	context.size = float(_facts.size_scale) if _facts != null else 1.0
	context.oval = Vector2(SETTINGS.oval_across_m.get_num(),
		SETTINGS.oval_up_m.get_num()) * scale
	context.hover = PLACEMENT.palm_clearance_for(scale, SETTINGS.hover_m.get_num())
	context.profile = _caress_profile()
	context.reach = _caress_reach(side)
	context.delta = float(_facts.physics_delta) if _facts != null else 0.016
	context.contact_smooth = SETTINGS.contact_smooth.get_num()
	context.normal_deg_s = SETTINGS.normal_deg_s.get_num()
	context.debug = _host().debug()
	context.path_id = SETTINGS.path_id.get_choice()
	context.reach_shoulder_m = SETTINGS.caress_reach_shoulder_m.get_num()
	return context


func _caress_profile() -> MODEL.CaressProfile:
	var size := str(_facts.size_name) if _facts != null else ""
	var height := float(_facts.same_height_scale) if _facts != null else 1.0
	if _profile == null or _profile_size != size or not is_equal_approx(_profile_scale, height):
		_profile = MODEL.caress_profile_for(size)
		if size == "same height":
			_profile = _profile.scaled(height)
		_profile_size = size
		_profile_scale = height
	return _profile


## The missionary body supplies the world shoulder and its bone lengths.
func _caress_reach(side: MODEL.Side) -> MODEL.ReachInfo:
	var driver := _host().driver()
	if not is_instance_valid(driver) or not driver.has_method("caress_reach"):
		return null
	var value: Variant = Callable(driver, "caress_reach").call(MODEL.side_key(side))
	if not value is Dictionary:
		return null
	var values: Dictionary = value
	if values.is_empty():
		return null
	var out := MODEL.ReachInfo.new()
	out.valid = true
	var origin: Variant = values.get("origin", Vector3.ZERO)
	if origin is Vector3:
		out.origin = origin
	out.upper = float(values.get("upper", 0.0))
	out.lower = float(values.get("lower", 0.0))
	out.hand = float(values.get("hand", 0.0))
	return out


func _pose_family() -> String:
	var view: Variant = _facts.pose_view if _facts != null else null
	return str(view.family) if view != null else ""


func _mouth_contact() -> bool:
	var view: Variant = _facts.pose_view if _facts != null else null
	return view != null and str(view.contact_kind) == "mouth"


func _side_for_index(index: int) -> MODEL.Side:
	return MODEL.Side.LEFT if index == 0 else MODEL.Side.RIGHT
