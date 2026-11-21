extends RefCounted
## The bed face-sit contact driver: her pose follows his live mouth.
## Contract: `docs/poses.md`.

const LOG := preload("res://mods/unfplap/shared/log.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")

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
func bind(pony_node: Node3D, face: Callable, opening: Callable) -> void:
	pony = pony_node
	face_point = face
	opening_point = opening


## Capture the live frame, his mouth and her opening point. A missing frame or point still
## activates the driver, so a later tick can recover.
func begin(view: POSE_VIEW, frame: Variant) -> bool:
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
			view.contact_target = mouth
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
		view.contact_target = mouth
	return true


## Follow the live mouth at the act's `depth`. A missing provider holds the last offset and logs
## once; it never writes an invalid point.
func tick(delta: float, view: POSE_VIEW, depth: float, frame: Variant, pose_node: POSE) -> void:
	if not active or not captured:
		return
	if view == null or view.contact_kind != "face":
		return
	if not frame is Transform3D:
		return
	var mouth := _point(face_point)
	if not mouth.is_finite():
		_log_once("face contact: mouth provider is unavailable; holding the last offset")
		_write_offset(pose_node, frame as Transform3D)
		if view != null and _target.is_finite():
			view.contact_target = _target
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
	view.contact_target = mouth


## Zero the offset and the view's contact target once. A second call is a no-op.
func restore(view: POSE_VIEW, pose_node: POSE) -> void:
	if pose_node != null:
		pose_node.contact_offset = Vector3.ZERO
	if view != null:
		view.contact_target = Vector3.INF
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


func _write_offset(pose_node: POSE, frame: Transform3D) -> void:
	if pose_node == null:
		return
	pose_node.contact_offset = frame.basis * _offset


func _log_once(text: String) -> void:
	if _missing_logged:
		return
	_missing_logged = true
	LOG.debug(text)


func _point(callback: Callable) -> Vector3:
	if not callback.is_valid():
		return Vector3.INF
	var value: Variant = callback.call()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF
