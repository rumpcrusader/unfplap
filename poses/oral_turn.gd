extends RefCounted
## The standing oral actor/frame turn: the captured root and facing, the eased half-turn about UP,
## the opening/mouth contact anchor, the style motion that drives the oral delta and the soft-kiss
## idle timer. `poses/service.gd` owns one and drives it from the edge weight; the host supplies
## the mouth and opening points and the runtime callbacks. It preloads nothing: the points and the
## kiss are host callables, so the frame turn never reaches into the anatomy or the runtime.
## Contract: `docs/poses.md`.

const ORAL_ANCHOR_RATE := 0.8
const ORAL_STYLE_MIN_S := 3.5
const ORAL_STYLE_MAX_S := 8.0
const ORAL_STYLE_BLEND := 2.0
const ORAL_KISS_IDLE_MIN_S := 2.5
const ORAL_KISS_IDLE_MAX_S := 4.5
const ORAL_STYLES := [
	[Vector3(0.085, 0.16, 0.04), 1.0],
	[Vector3(0.05, 0.14, 0.26), 0.85],
	[Vector3(0.06, 0.08, 0.34), 0.75],
	[Vector3(0.03, 0.08, 0.12), 1.6],
	[Vector3(0.1, 0.22, 0.1), 0.6],
]

var pony: Node3D = null
## True between `begin()` and `restore()`: the forward edge settles, the reverse edge restores.
var active := false
var forward := true
## The live values the session writes into the pose view each tick.
var facing := Basis.IDENTITY
var facing_amount := 0.0
var contact_target := Vector3.INF

var mouth_point := Callable()
var opening_point := Callable()
var oral_kiss := Callable()

var _captured := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _from_basis := Basis.IDENTITY
var _opening := Vector3.INF
var _anchor := Vector3.INF
var _style: Array = ORAL_STYLES[0]
var _style_left := 0.0
var _now := Vector3.ZERO
var _speed := 1.0
var _clock := 0.0
var _side := 1.0
var _kiss_left := 0.0
var _pose_delta: Dictionary = {}


## Point the module at the live scene and the host callbacks. Called on every session access, so a
## suite can bind the values after the session was built.
func bind(pony_node: Node3D, mouth: Callable, opening: Callable, kiss: Callable) -> void:
	pony = pony_node
	mouth_point = mouth
	opening_point = opening
	oral_kiss = kiss


## Start the forward or reverse turn. The forward capture is the only place the root, the facing,
## the opening and the mirrored target are read; a reverse edge reuses them. Returns false only
## when there is no pony to drive.
func begin(is_forward: bool, view: Variant) -> bool:
	if not is_instance_valid(pony):
		return false
	forward = is_forward
	active = true
	_kiss_left = 0.0
	if is_forward:
		_capture()
	elif not _captured:
		_capture()
		_to = _from
	if view != null:
		view.contact_target = _opening if _opening.is_finite() else Vector3.INF
	return _captured


func _capture() -> void:
	_from = pony.global_position
	_from_basis = pony.global_transform.basis.orthonormalized()
	_opening = _point(opening_point)
	var mouth := _point(mouth_point)
	if mouth.is_finite() and _opening.is_finite():
		var scale: Vector3 = pony.global_transform.basis.get_scale()
		var local: Vector3 = pony.global_transform.affine_inverse() * mouth
		var turned: Basis = Basis(Vector3.UP, PI) * _from_basis
		var to: Vector3 = _opening - turned * (local * scale)
		_to = Vector3(to.x, _from.y, to.z)
	else:
		_to = _from
	_anchor = _opening
	_style = ORAL_STYLES[0]
	_style_left = 0.0
	_now = Vector3.ZERO
	_speed = 1.0
	_clock = 0.0
	_side = 1.0
	_captured = true


## Advance the turn. `weight` is the edge's base weight: the forward edge eases 0 -> 1, the reverse
## edge eases the same clock back from the turned frame to the captured one. The view receives the
## live facing and contact target; the style motion writes the three keys into the live config and
## the target snapshot, so the delta's to side sees them too.
func tick(delta: float, view: Variant, weight: float) -> void:
	if not active or not _captured or not is_instance_valid(pony):
		return
	var eased := smoothstep(0.0, 1.0, clampf(weight, 0.0, 1.0))
	if not forward:
		eased = 1.0 - eased
	facing = Basis(Vector3.UP, PI * eased) * _from_basis
	facing_amount = eased
	pony.global_position = _from.lerp(_to, eased)
	var mouth := _point(mouth_point)
	var mouth_contact := view != null and str(view.contact_kind) == "mouth"
	if forward and mouth_contact and eased >= 0.999:
		_anchor = _anchor_step(_anchor, mouth, _opening, 1.0, true, ORAL_ANCHOR_RATE, delta)
	else:
		_anchor = _opening
	if forward and (mouth_contact or eased < 0.999):
		_motion_tick(delta)
	if forward and mouth_contact:
		_kiss_tick(delta)
	else:
		_kiss_left = 0.0
	if view == null:
		return
	view.facing = facing
	view.facing_amount = facing_amount
	view.contact_target = _anchor if _anchor.is_finite() else mouth
	_write_keys(view)


## The afterglow releases the mouth contact but keeps the turned frame and the neck pose: stop the
## kiss timer and point the contact back at the opening, without restoring the capture.
func release_contact(view: Variant) -> void:
	_kiss_left = 0.0
	_anchor = _opening
	if view != null and _opening.is_finite():
		view.contact_target = _opening


## Put the captured root and facing back and erase the oral keys once. The reverse edge's
## completion, a release and the one act exit all call it; a second call is a no-op.
func restore(view: Variant) -> void:
	if _captured and is_instance_valid(pony):
		pony.global_position = _from
		var scale: Vector3 = pony.global_transform.basis.get_scale()
		pony.global_transform.basis = _from_basis.scaled(scale)
	if view != null:
		_erase_keys(view)
		view.facing = Basis.IDENTITY
		view.facing_amount = 0.0
		view.contact_target = Vector3.INF
	active = false
	forward = true
	_captured = false
	_anchor = Vector3.INF
	_opening = Vector3.INF
	_from = Vector3.ZERO
	_to = Vector3.ZERO
	_from_basis = Basis.IDENTITY
	_kiss_left = 0.0
	_pose_delta.clear()
	facing = Basis.IDENTITY
	facing_amount = 0.0
	contact_target = Vector3.INF


## Clear the live state without moving the pony. `begin()` calls it before a fresh act, after the
## one act exit restored the capture.
func reset() -> void:
	active = false
	forward = true
	_captured = false
	_from = Vector3.ZERO
	_to = Vector3.ZERO
	_from_basis = Basis.IDENTITY
	_opening = Vector3.INF
	_anchor = Vector3.INF
	_style = ORAL_STYLES[0]
	_style_left = 0.0
	_now = Vector3.ZERO
	_speed = 1.0
	_clock = 0.0
	_side = 1.0
	_kiss_left = 0.0
	_pose_delta.clear()
	facing = Basis.IDENTITY
	facing_amount = 0.0
	contact_target = Vector3.INF


## Re-apply the live keys after the target snapshot was refreshed. A live settings edit replaces
## the target config's contents, which drops the keys until the next tick; this keeps a mid-edge
## edit from dropping one frame of the delta.
func write_config(view: Variant) -> void:
	if active and view != null:
		_write_keys(view)


## The mouth anchor after one tick: the opening holds while she turns or the contact is released,
## and the live mouth is followed once the turn is settled under `rate`.
static func _anchor_step(anchor: Vector3, mouth: Vector3, opening: Vector3, mix: float,
		active_now: bool, rate: float, delta: float) -> Vector3:
	if not opening.is_finite():
		return anchor
	if not active_now:
		if not anchor.is_finite():
			return opening
		return opening.lerp(anchor, clampf(mix, 0.0, 1.0))
	if mix < 1.0 or not mouth.is_finite():
		return opening
	if not anchor.is_finite():
		return mouth
	return anchor.lerp(mouth, 1.0 - exp(-maxf(rate, 0.0) * delta))


func _motion_tick(delta: float) -> void:
	_style_left -= delta
	if _style_left <= 0.0:
		_style_left = randf_range(ORAL_STYLE_MIN_S, ORAL_STYLE_MAX_S)
		_style = ORAL_STYLES.pick_random()
		_side = -_side
	var blend := 1.0 - exp(-delta * ORAL_STYLE_BLEND)
	_now = _now.lerp(_style[0], blend)
	_speed = lerpf(_speed, float(_style[1]), blend)
	_clock = fposmod(_clock + delta * _speed, 16.0)
	var turn := TAU * _clock
	_pose_delta["oral_pitch"] = cos(turn) * _now.y
	_pose_delta["oral_yaw"] = sin(turn * 0.5) * _now.z + _side * _now.z * 0.5
	_pose_delta["oral_roll"] = sin(turn * 0.5 + 1.1) * _now.z * 0.6


func _kiss_tick(delta: float) -> void:
	if _kiss_left <= 0.0:
		_kiss_left = randf_range(ORAL_KISS_IDLE_MIN_S, ORAL_KISS_IDLE_MAX_S)
		return
	_kiss_left -= delta
	if _kiss_left > 0.0:
		return
	_kiss_left = randf_range(ORAL_KISS_IDLE_MIN_S, ORAL_KISS_IDLE_MAX_S)
	if oral_kiss.is_valid():
		oral_kiss.call()


func _write_keys(view: Variant) -> void:
	var pitch := float(_pose_delta.get("oral_pitch", 0.0))
	var yaw := float(_pose_delta.get("oral_yaw", 0.0))
	var roll := float(_pose_delta.get("oral_roll", 0.0))
	_put_key(view.from_config, "oral_pitch", pitch)
	_put_key(view.from_config, "oral_yaw", yaw)
	_put_key(view.from_config, "oral_roll", roll)
	if not is_same(view.to_config, view.from_config):
		_put_key(view.to_config, "oral_pitch", pitch)
		_put_key(view.to_config, "oral_yaw", yaw)
		_put_key(view.to_config, "oral_roll", roll)


func _erase_keys(view: Variant) -> void:
	_erase_from(view.from_config)
	if not is_same(view.to_config, view.from_config):
		_erase_from(view.to_config)


func _put_key(config: Variant, key: String, value: float) -> void:
	if config is Dictionary:
		(config as Dictionary)[key] = value


func _erase_from(config: Variant) -> void:
	if not config is Dictionary:
		return
	var data := config as Dictionary
	data.erase("oral_pitch")
	data.erase("oral_yaw")
	data.erase("oral_roll")


func _point(callback: Callable) -> Vector3:
	if not callback.is_valid():
		return Vector3.INF
	var value: Variant = callback.call()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF
