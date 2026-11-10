extends RefCounted
## Smack action for the act hands. The coordinator supplies the target frame and mode; this
## controller owns the swing phases, native impact audio and the return to the live caress.

const SMACK_AUDIO := preload("res://mods/unfplap/audio/act/smack/catalogue.gd")

const SMACK_COOLDOWN_MS := 200
const SMACK_SWING_SECONDS := 0.20
const SMACK_CONTACT_PHASE := 0.45
const SMACK_RAISE_SPEED_M_S := 2.0
const SMACK_RAISE_MIN_S := 0.12
const SMACK_RAISE_MAX_S := 0.30
const SMACK_RETURN_SPEED_M_S := 6.0
const SMACK_STRIKE_MIN_S := 0.06
const SMACK_STRIKE_MAX_S := 0.20
const SMACK_PITCH_DEG := 12.0
const SMACK_RAISE_BACK_M := 0.05
const SMACK_ARC_M := 0.06
const SMACK_SWING_DOWN_RATIO := 0.55
const SMACK_SWING_OUT_RATIO := 0.15
const SMACK_CONTACT_HOLD_SECONDS := 0.03
const SMACK_REST_RETURN_SECONDS := 0.20
const SMACK_IMPACT_STRENGTH := 0.8
const SMACK_PHASE_NONE := 0
const SMACK_PHASE_RAISE := 1
const SMACK_PHASE_STRIKE := 2
const SMACK_PHASE_CONTACT := 3
const SMACK_PHASE_RECOVER := 4
const SMACK_VOLUME_DB := -7.0
const SMACK_PITCH_MIN := 0.97
const SMACK_PITCH_MAX := 1.03

var hand: Variant

var _active := false
var _index := 0
var _at := Vector3.INF
var _side := ""
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _started := 0
var _impact_done := false
var _phase := SMACK_PHASE_NONE
var _phase_started := 0
var _contact := Transform3D.IDENTITY
var _raised := Transform3D.IDENTITY
var _rest := Transform3D.IDENTITY
var _outward := Vector3.UP
var _raise_seconds := SMACK_RAISE_MIN_S
var _strike_seconds := 0.10
var _caress := false
var _standing := false
var _last_ms := -10000
var _streams: Array[AudioStream] = []
var _stream_last := -1
var _sound_restore: Dictionary = {}
var _sound_installed := false


func _init(hand_node: Variant = null) -> void:
	hand = hand_node


static func side_index(side: float) -> int:
	if side > 0.0:
		return 0
	if side < 0.0:
		return 1
	return -1


static func pitch_basis(straight: Basis, pitch_deg: float) -> Basis:
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


static func raise_frame(contact: Transform3D, outward: Vector3, raise_m: float,
		back_m: float, back: Vector3, pitch_deg: float) -> Transform3D:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	var rear := back.normalized()
	if rear.length_squared() < 0.5:
		rear = contact.basis.z
	return Transform3D(pitch_basis(contact.basis, pitch_deg),
		contact.origin + normal * raise_m + rear * back_m)


static func finger_hint(caressing: bool, forward: Vector3) -> Vector3:
	if caressing:
		var hint := forward.normalized()
		if hint.length_squared() > 0.5:
			return hint
		return Vector3.FORWARD
	return Vector3.DOWN


static func swing_raise_frame(contact: Transform3D, outward: Vector3, back: Vector3,
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
	return Transform3D(pitch_basis(contact.basis, pitch_deg), origin)


static func raise_blend(from: Transform3D, to: Transform3D, back: Vector3,
		t: float) -> Transform3D:
	var eased := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var origin := from.origin.lerp(to.origin, eased) + back * sin(eased * PI)
	var basis := from.basis.slerp(to.basis, eased).orthonormalized()
	return Transform3D(basis, origin)


static func strike_blend(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	var clamped := clampf(t, 0.0, 1.0)
	var basis := from.basis.slerp(to.basis, pow(clamped, 2.0)).orthonormalized()
	return Transform3D(basis, from.origin.lerp(to.origin, pow(clamped, 3.0)))


static func recover_blend(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	return from.interpolate_with(to, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))


func can_start(now: int) -> bool:
	return not _active and now - _last_ms >= SMACK_COOLDOWN_MS


func active() -> bool:
	return _active


func owns_hand(hand_side: String) -> bool:
	return _active and _side == hand_side


func begin(hand_side: String, index: int, at: Vector3, from_frame: Transform3D,
		target: Transform3D, outward: Vector3, caressing: bool, standing: bool,
		now: int) -> void:
	_index = index
	_at = at
	_side = hand_side
	_from = from_frame
	_contact = target
	_outward = outward.normalized()
	_rest = from_frame
	_caress = caressing
	_standing = standing
	_started = now
	_last_ms = now
	_impact_done = false
	_active = true
	if standing:
		_start_standing()
	else:
		_phase = SMACK_PHASE_NONE


func tick(_delta: float) -> void:
	if not _active:
		return
	if _side.is_empty():
		_active = false
		return
	var driver: Node = hand.call("hand_driver") if is_instance_valid(hand) else null
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_end_swing()
		return
	if _standing:
		_phase_tick(driver)
		return
	var phase := clampf(float(Time.get_ticks_msec() - _started)
		/ (SMACK_SWING_SECONDS * 1000.0), 0.0, 1.0)
	var arc := sin(phase * PI)
	var frame := _from.interpolate_with(_to, arc)
	driver.call("set_hold_target", _side, frame, "rub")
	if not _impact_done and phase >= SMACK_CONTACT_PHASE:
		_impact_done = true
		_impact()
	if phase >= 1.0:
		_end_swing()


func instant(index: int, at: Vector3) -> void:
	_impact_at(index, at)


func cancel() -> void:
	_end_swing()


func reset() -> void:
	_end_swing()
	_restore_sound()


func _start_standing() -> void:
	_caress = bool(hand.call("caress_active", _side))
	_rest = _from
	if _caress:
		var scale := float(hand.call("smack_body_scale"))
		_raised = raise_frame(_contact, _outward, _raise_m(),
			SMACK_RAISE_BACK_M * scale, _back_dir(), _pitch_deg())
	else:
		_raised = swing_raise_frame(_contact, _outward, _back_dir(), _raise_m(), _pitch_deg())
	var distance := _from.origin.distance_to(_raised.origin)
	_raise_seconds = clampf(distance / _raise_speed(), SMACK_RAISE_MIN_S, SMACK_RAISE_MAX_S)
	var return_distance := _raised.origin.distance_to(_contact.origin)
	_strike_seconds = clampf(return_distance / _return_speed(), SMACK_STRIKE_MIN_S,
		SMACK_STRIKE_MAX_S)
	_phase = SMACK_PHASE_RAISE
	_phase_started = Time.get_ticks_msec()


func _phase_tick(driver: Node) -> void:
	var now := Time.get_ticks_msec()
	var elapsed := float(now - _phase_started) / 1000.0
	match _phase:
		SMACK_PHASE_RAISE:
			var t := clampf(elapsed / maxf(_raise_seconds, 0.001), 0.0, 1.0)
			var frame := raise_blend(_from, _raised, _back_dir(), t)
			driver.call("set_hold_target", _side, frame, "rub")
			if t >= 1.0:
				_phase = SMACK_PHASE_STRIKE
				_phase_started = now
		SMACK_PHASE_STRIKE:
			var t := clampf(elapsed / maxf(_strike_seconds, 0.001), 0.0, 1.0)
			var frame := strike_blend(_raised, _contact, t)
			driver.call("set_hold_target", _side, frame, "rub")
			if t >= 1.0:
				driver.call("set_hold_target", _side, _contact, "rub")
				_impact()
				_impact_done = true
				_phase = SMACK_PHASE_CONTACT
				_phase_started = now
		SMACK_PHASE_CONTACT:
			driver.call("set_hold_target", _side, _contact, "rub")
			if elapsed >= SMACK_CONTACT_HOLD_SECONDS:
				_phase = SMACK_PHASE_RECOVER
				_phase_started = now
				hand.call("caress_reset_hand", _side)
		SMACK_PHASE_RECOVER:
			var target := _recover_target()
			var duration := float(hand.call("caress_return_seconds")) \
				if _keep_caress() else SMACK_REST_RETURN_SECONDS
			var t := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
			var frame := recover_blend(_contact, target, t)
			driver.call("set_hold_target", _side, frame, "rub")
			if t >= 1.0:
				_finish(driver)


func _recover_target() -> Transform3D:
	var caress_side := "L" if _side == "left" else "R"
	if _keep_caress():
		var target: Transform3D = hand.call("caress_set_hand", caress_side, false)
		if not target.is_equal_approx(Transform3D.IDENTITY):
			return target
	return _rest


func _keep_caress() -> bool:
	var caress_side := "L" if _side == "left" else "R"
	return _caress and bool(hand.call("caress_latched", caress_side))


func _finish(driver: Node) -> void:
	var caress_side := "L" if _side == "left" else "R"
	if _keep_caress():
		hand.call("caress_finish_keep", caress_side)
	elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", _side)
	_active = false
	_side = ""
	_at = Vector3.INF
	_phase = SMACK_PHASE_NONE
	_caress = false


func _end_swing() -> void:
	if not _active:
		return
	if not _side.is_empty():
		var driver: Node = hand.call("hand_driver") if is_instance_valid(hand) else null
		var caress_side := "L" if _side == "left" else "R"
		if bool(hand.call("caress_active", caress_side)):
			var from := _contact if _phase != SMACK_PHASE_NONE else _to
			if is_instance_valid(driver) and driver.has_method("hand_frame"):
				var current: Variant = driver.call("hand_frame", _side)
				if current is Transform3D and (current as Transform3D).is_finite():
					from = current
			hand.call("caress_begin_return", caress_side, from)
		elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _side)
	_active = false
	_side = ""
	_at = Vector3.INF
	_impact_done = false
	_phase = SMACK_PHASE_NONE
	_caress = false
	_contact = Transform3D.IDENTITY
	_raised = Transform3D.IDENTITY
	_rest = Transform3D.IDENTITY
	_outward = Vector3.UP


func _impact() -> void:
	_impact_at(_index, _at)


func _impact_at(index: int, at: Vector3) -> void:
	var flank := _flank()
	if not is_instance_valid(flank):
		return
	_install_sound()
	var pony: Variant = hand.get("pony") if is_instance_valid(hand) else null
	if not is_instance_valid(pony) or not pony.has_signal("physical_reaction"):
		flank.call("impact", index, at, SMACK_IMPACT_STRENGTH)
		_notify_jiggle()
		return
	var sig: Signal = pony.physical_reaction
	var links: Array = sig.get_connections()
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and sig.is_connected(callable):
			sig.disconnect(callable)
	flank.call("impact", index, at, SMACK_IMPACT_STRENGTH)
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and not sig.is_connected(callable):
			sig.connect(callable)
	_notify_jiggle()
	if is_instance_valid(hand):
		var runtime: Node = hand.get("runtime")
		if is_instance_valid(runtime):
			runtime.call("_on_touch", "smack")


func _notify_jiggle() -> void:
	if is_instance_valid(hand):
		var runtime: Node = hand.get("runtime")
		if is_instance_valid(runtime) and runtime.has_method("_on_smack_impact"):
			runtime.call("_on_smack_impact", SMACK_IMPACT_STRENGTH)


func _flank() -> Node:
	return hand.call("smack_flank") if is_instance_valid(hand) else null


func _back_dir() -> Vector3:
	var pony: Variant = hand.get("pony") if is_instance_valid(hand) else null
	if not is_instance_valid(pony):
		return Vector3.BACK
	var back: Vector3 = pony.global_basis.z.normalized()
	back -= _outward * back.dot(_outward)
	if back.length_squared() < 0.0001:
		back = _contact.basis.z
	return back.normalized()


func _setting(name: String, fallback: float) -> float:
	var cfg: Dictionary = hand.call("smack_presentation") if is_instance_valid(hand) else {}
	var smack: Variant = cfg.get("smack", {})
	return float((smack as Dictionary).get(name, fallback)) if smack is Dictionary else fallback


func _raise_m() -> float:
	return maxf(0.0, _setting("raise_m", 0.30)) * float(hand.call("smack_body_scale"))


func _pitch_deg() -> float:
	return _setting("pitch_deg", SMACK_PITCH_DEG)


func _raise_speed() -> float:
	return maxf(0.05, _setting("raise_speed", SMACK_RAISE_SPEED_M_S))


func _return_speed() -> float:
	return maxf(0.05, _setting("return_speed", SMACK_RETURN_SPEED_M_S))


func _sound_player() -> AudioStreamPlayer3D:
	var flank := _flank()
	if not is_instance_valid(flank):
		return null
	var player: Variant = flank.get("sound")
	if not player is AudioStreamPlayer3D:
		player = flank.get_node_or_null("sound")
	return player if player is AudioStreamPlayer3D else null


func _load_streams() -> void:
	if not _streams.is_empty():
		return
	for path: String in SMACK_AUDIO.PATHS:
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_streams.append(stream)


func _next_stream(count: int) -> int:
	if count <= 1:
		return 0
	var index := randi() % count
	if index == _stream_last:
		index = (index + 1) % count
	_stream_last = index
	return index


func _install_sound() -> void:
	var player := _sound_player()
	if player == null:
		return
	_load_streams()
	if _streams.is_empty():
		_restore_sound()
		return
	if not _sound_installed:
		_sound_restore = {
			"stream": player.stream,
			"volume_db": player.volume_db,
			"pitch_scale": player.pitch_scale,
		}
		_sound_installed = true
	var index := _next_stream(_streams.size())
	player.stream = _streams[index]
	player.volume_db = SMACK_VOLUME_DB
	player.pitch_scale = randf_range(SMACK_PITCH_MIN, SMACK_PITCH_MAX)


func _restore_sound() -> void:
	if not _sound_installed:
		return
	_sound_installed = false
	var player := _sound_player()
	if player != null and not _sound_restore.is_empty():
		var stock: Variant = _sound_restore.get("stream")
		player.stream = stock if stock is AudioStream else null
		player.volume_db = float(_sound_restore.get("volume_db", player.volume_db))
		player.pitch_scale = float(_sound_restore.get("pitch_scale", player.pitch_scale))
	_sound_restore.clear()
