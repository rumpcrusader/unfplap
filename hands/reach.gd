extends RefCounted
## The standing shoulder reach: hold, release blend and the smack hand cancellation.

const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PORT := preload("res://mods/unfplap/hands/port.gd")
const FLANK_PATH := preload("res://mods/unfplap/hands/paths/standing.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35

## The coordinator, held weakly: it owns this module, so a strong link back would be a cycle.
var _host_ref: WeakRef = null
var _facts: ACT_FACTS = null
var _shoulder: MODEL.Side = MODEL.Side.NONE
var _holding := false
var _hand_from := Transform3D.IDENTITY
var _hand_rest := Transform3D.IDENTITY
var _hand_rest_valid := false
var _hand_started := 0
var _hand_logged := false
var _returning := false
var _return_from := Transform3D.IDENTITY
var _return_started := 0
var _return_side: MODEL.Side = MODEL.Side.NONE
var _coat := MODEL.CoatContext.new()


func _init(port: PORT, facts: ACT_FACTS) -> void:
	_host_ref = weakref(port)
	_facts = facts


## The coordinator, or null once it has released this module.
func _host() -> PORT:
	return _host_ref.get_ref() as PORT


## Start or hold the shoulder reach on one hand.
func start(side: MODEL.Side) -> void:
	if _host() == null or side == MODEL.Side.NONE:
		return
	_shoulder = side
	_holding = true
	_returning = false
	_hand_started = 0
	_hand_logged = false
	_hold()


## Release the hold and ease the hand home.
func settle() -> void:
	if _shoulder == MODEL.Side.NONE:
		_holding = false
		return
	var side := _shoulder
	_holding = false
	_return_from = _hand_from
	var current := _host().hand_frame(side)
	if current.is_finite():
		_return_from = current
	if not _hand_rest_valid or not _return_from.is_finite():
		_clear_hand()
		return
	_return_side = side
	_return_started = Time.get_ticks_msec()
	_returning = true


## One tick: ease a released reach home, then hold a live one on the shoulder.
func tick() -> void:
	if _returning:
		_return_tick()
		return
	if _holding:
		_hold()


func active() -> bool:
	return _holding


func owns(side: MODEL.Side) -> bool:
	return _holding and _shoulder == side


## The smack took the reaching hand: drop the shoulder hold so it does not come back.
func cancel(side: MODEL.Side) -> void:
	if not owns(side):
		return
	_holding = false
	_clear_hand()
	_shoulder = MODEL.Side.NONE


func reset() -> void:
	_clear_hand()
	_shoulder = MODEL.Side.NONE
	_holding = false


func _hold() -> void:
	if _shoulder == MODEL.Side.NONE:
		return
	var pony := _host().pony()
	if not is_instance_valid(pony):
		return
	var shoulder := _shoulder_point(_shoulder)
	if shoulder == null:
		return
	var side := _shoulder
	var side_key := MODEL.side_key(side)
	var reach_key := "reach:" + side_key
	var delta := float(_facts.physics_delta) if _facts != null else 0.016
	var engine := _host().engine()
	if engine == null:
		return
	if _hand_started <= 0:
		engine.reset_hand(side, reach_key)
	var clearance := PLACEMENT.palm_clearance_for(_host().body_scale(),
		SETTINGS.hover_m.get_num())
	var context := _coat_context(reach_key, delta)
	# Palm flat on the shoulder coat: the shared hull frame keeps the fingers forward with the
	# palm inward.
	var target := engine.coat_frame(pony, side, shoulder.palm, shoulder.outward,
		-pony.global_basis.z, clearance, context)
	if _hand_started <= 0:
		_hand_started = Time.get_ticks_msec()
		_hand_from = Transform3D.IDENTITY
		var from_frame := _host().hand_frame(side)
		if from_frame.is_finite():
			_hand_from = from_frame
		_hand_rest = _hand_from
		_hand_rest_valid = _hand_from.is_finite()
	var frame := target
	if _hand_started > 0 and _hand_from.is_finite():
		var t := clampf(float(Time.get_ticks_msec() - _hand_started)
			/ (REACH_HAND_BLEND_S * 1000.0), 0.0, 1.0)
		frame = _hand_from.interpolate_with(target, smoothstep(0.0, 1.0, t))
	if not _hand_logged:
		_hand_logged = true
		var palm_normal: Vector3 = target.basis.x * (1.0 if side == MODEL.Side.LEFT else -1.0)
		LOG.debug("reach hand side=%s target=%s x=%s y=%s z=%s fingers=%s palm=%s", [
			side_key, str(target.origin), str(target.basis.x), str(target.basis.y),
			str(target.basis.z), str(-target.basis.z), str(palm_normal)])
	_host().hold(side, frame)


func _return_tick() -> void:
	if _return_side == MODEL.Side.NONE:
		_returning = false
		return
	var driver := _host().driver()
	if not is_instance_valid(driver):
		_returning = false
		return
	var t := clampf(float(Time.get_ticks_msec() - _return_started)
		/ (REACH_HAND_RELEASE_S * 1000.0), 0.0, 1.0)
	if t >= 1.0:
		_returning = false
		_host().release_hold(_return_side)
		_return_side = MODEL.Side.NONE
		_hand_started = 0
		_hand_from = Transform3D.IDENTITY
		return
	var frame := _return_from.interpolate_with(_hand_rest, smoothstep(0.0, 1.0, t))
	_host().hold(_return_side, frame)


func _clear_hand() -> void:
	var side := _shoulder
	if side == MODEL.Side.NONE:
		side = _return_side
	_returning = false
	_return_side = MODEL.Side.NONE
	_hand_started = 0
	_hand_logged = false
	_hand_from = Transform3D.IDENTITY
	_hand_rest_valid = false
	if side == MODEL.Side.NONE:
		return
	_host().release_hold(side)


func _shoulder_point(side: MODEL.Side) -> MODEL.ShoulderPoint:
	if side == MODEL.Side.NONE:
		return null
	var path := _host().path()
	if path == null or not (path is FLANK_PATH):
		return null
	return (path as FLANK_PATH).shoulder_point(side)


func _coat_context(key: String, delta: float) -> MODEL.CoatContext:
	_coat.hover = PLACEMENT.palm_clearance_for(_host().body_scale(), SETTINGS.hover_m.get_num())
	_coat.contact_smooth = SETTINGS.contact_smooth.get_num()
	_coat.normal_deg_s = SETTINGS.normal_deg_s.get_num()
	_coat.debug = _host().debug()
	_coat.ignore.clear()
	_coat.radial = true
	_coat.regions.clear()
	_coat.extra_hover = 0.0
	_coat.state_key = key
	_coat.delta = delta
	return _coat
