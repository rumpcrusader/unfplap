extends RefCounted
## The bed face-sit's contact driver: her authored pose follows his live mouth so her vulva stays on
## it as he leans, the size changes or the bed moves. `poses/service.gd` owns one and binds the live
## pony, the act body's `face_point()` and her `opening_point()`; the driver writes the pose node's
## `contact_offset` and the view's `contact_target`. It preloads nothing and never calls the camera,
## hands, anatomy or kiss. Contract: `docs/poses.md`.

## The offset eases at this exponential rate; a few centimetres of residual land in a few frames
## without dragging her across the mattress.
const OFFSET_RATE := 9.0
## The press toward his mouth at full depth and the lateral rock around that press. Code constants,
## not settings: the lab tunes the arrangement, not a per-player knob.
const PRESS_M := 0.025
const ROCK_M := 0.012
const ROCK_RATE := 2.4

var pony: Node3D = null
var face_point := Callable()
var opening_point := Callable()
var log := Callable()
## True between `begin()` and `restore()`. The service only ticks it while the view names `face`.
var active := false
## True when `begin()` captured a finite mouth and opening. A missing provider leaves the driver
## active but holds the last offset instead of moving her to an invalid point.
var captured := false

var _frame := Transform3D.IDENTITY
## The captured mouth and the opening-to-mouth direction, in the bed frame at begin.
var _captured_mouth := Vector3.ZERO
var _direction := Vector3.ZERO
## The residual that puts her opening on his mouth, in frame space.
var _base_offset := Vector3.ZERO
## The live eased offset, in frame space.
var _offset := Vector3.ZERO
var _target := Vector3.INF
var _clock := 0.0
var _missing_logged := false


## Point the driver at the live scene and the host reads. Called on every session access, so a
## suite can bind the callbacks after the session was built.
func bind(pony_node: Node3D, face: Callable, opening: Callable, logger := Callable()) -> void:
	pony = pony_node
	face_point = face
	opening_point = opening
	log = logger


## Capture the bed frame, his mouth and her opening. Returns false when the frame or a point is
## missing; the driver still activates so a later tick can recover. Called on the contact switch to
## `face` and on a pose that starts in face contact.
func begin(view: Variant, frame: Variant) -> bool:
	active = true
	captured = false
	_target = Vector3.INF
	_offset = Vector3.ZERO
	_clock = 0.0
	_missing_logged = false
	if not frame is Transform3D:
		_log_once("face contact: no bed frame")
		return false
	_frame = frame as Transform3D
	var mouth := _point(face_point)
	var opening := _point(opening_point)
	if not mouth.is_finite() or not opening.is_finite():
		_log_once("face contact: no mouth/opening provider")
		if view != null and mouth.is_finite():
			(view as RefCounted).set("contact_target", mouth)
		return false
	var inverse := _frame.affine_inverse()
	var mouth_frame := inverse * mouth
	var opening_frame := inverse * opening
	_captured_mouth = mouth_frame
	_base_offset = mouth_frame - opening_frame
	var gap := _base_offset
	_direction = gap.normalized() if gap.length_squared() > 0.0000001 else Vector3.ZERO
	_offset = _base_offset
	_target = mouth
	captured = true
	if view != null:
		(view as RefCounted).set("contact_target", mouth)
	return true


## Follow the live mouth. `depth` is the act's 0..1 depth; `frame` is the current bed frame and
## `pose_node` the pose modifier whose `contact_offset` the recipe applies. A missing provider holds
## the last valid offset and writes one diagnostic line, never an invalid point.
func tick(delta: float, view: Variant, depth: float, frame: Variant, pose_node: Variant) -> void:
	if not active or not captured:
		return
	if view == null or str((view as RefCounted).get("contact_kind")) != "face":
		return
	if not frame is Transform3D:
		return
	var mouth := _point(face_point)
	if not mouth.is_finite():
		_log_once("face contact: mouth provider is unavailable; holding the last offset")
		_write_offset(pose_node, frame as Transform3D)
		if view != null and _target.is_finite():
			(view as RefCounted).set("contact_target", _target)
		return
	_missing_logged = false
	_frame = frame as Transform3D
	var step := maxf(delta, 0.0)
	_clock += step
	var inverse := _frame.affine_inverse()
	var mouth_frame := inverse * mouth
	var wanted := _base_offset + (mouth_frame - _captured_mouth)
	var level := clampf(depth, 0.0, 1.0)
	if _direction.length_squared() > 0.0:
		wanted += _direction * (PRESS_M * level)
	var right := _frame.basis.x.normalized()
	wanted += right * (sin(_clock * ROCK_RATE) * ROCK_M * level)
	var blend := 1.0 - exp(-OFFSET_RATE * step)
	_offset = _offset.lerp(wanted, clampf(blend, 0.0, 1.0))
	_write_offset(pose_node, _frame)
	_target = mouth
	(view as RefCounted).set("contact_target", mouth)


## Clear the offset and the view's contact target once. The reverse contact switch, the reverse
## completion and the one act exit call it; a second call is a no-op.
func restore(view: Variant, pose_node: Variant) -> void:
	if pose_node != null:
		(pose_node as Object).set("contact_offset", Vector3.ZERO)
	if view != null:
		(view as RefCounted).set("contact_target", Vector3.INF)
	reset()


## Clear the live state without touching the view or a node. `begin()` calls it before a fresh act.
func reset() -> void:
	active = false
	captured = false
	_frame = Transform3D.IDENTITY
	_captured_mouth = Vector3.ZERO
	_direction = Vector3.ZERO
	_base_offset = Vector3.ZERO
	_offset = Vector3.ZERO
	_target = Vector3.INF
	_clock = 0.0
	_missing_logged = false


## The live frame-space offset, for the suite and a debug row.
func offset() -> Vector3:
	return _offset


## The last valid mouth point, for the suite.
func target() -> Vector3:
	return _target


func _write_offset(pose_node: Variant, frame: Transform3D) -> void:
	if pose_node == null:
		return
	(pose_node as Object).set("contact_offset", frame.basis * _offset)


func _log_once(text: String) -> void:
	if _missing_logged:
		return
	_missing_logged = true
	if log.is_valid():
		log.call(text)


func _point(callback: Callable) -> Vector3:
	if not callback.is_valid():
		return Vector3.INF
	var value: Variant = callback.call()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF
