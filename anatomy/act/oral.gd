extends RefCounted
## The standing act's oral turn: the consent-gated turn about UP, the mouth anchor, the style
## motion and the oral pose keys. It owns the turn's transform and facing; the act owns shapes.
##
## See `docs/anatomy.md` (`## Act anatomy`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const STATE := preload("res://mods/unfplap/anatomy/act/state.gd")

const ORAL_TURN_S := 1.6
const ORAL_MOUTH := "D"
const ORAL_STYLE_MIN_S := 3.5
const ORAL_STYLE_MAX_S := 8.0
const ORAL_STYLE_BLEND := 2.0
const ORAL_ANCHOR_RATE := 0.8
const ORAL_BELOW_NOSE_M := 0.03
const ORAL_STYLES := [
	[Vector3(0.085, 0.16, 0.04), 1.0],
	[Vector3(0.05, 0.14, 0.26), 0.85],
	[Vector3(0.06, 0.08, 0.34), 0.75],
	[Vector3(0.03, 0.08, 0.12), 1.6],
	[Vector3(0.1, 0.22, 0.1), 0.6],
]

var pony: Node3D
var anatomy: Node
var pose := ""
var consent := Callable()
var status := Callable()

var _facts: RefCounted
var _active := false
var _mix := 0.0
var _style: Array = ORAL_STYLES[0]
var _style_left := 0.0
var _now := Vector3.ZERO
var _speed := 1.0
var _clock := 0.0
var _side := 1.0
var _anchor := Vector3.INF
## The opening the current turn started from: the part holds here while she turns, and the
## release blends back to it.
var _opening := Vector3.INF
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _from_basis := Basis.IDENTITY
var _turn_started := false
var _pose_delta: Dictionary = {}
var _facing: Dictionary = {}


func setup(pony_node: Node3D, anatomy_node: Node, pose_id: String,
		consent_callable := Callable(), status_callable := Callable()) -> void:
	pony = pony_node
	anatomy = anatomy_node
	pose = pose_id
	consent = consent_callable
	status = status_callable
	reset()


func reset() -> void:
	_facts = null
	_active = false
	_mix = 0.0
	_style = ORAL_STYLES[0]
	_style_left = 0.0
	_now = Vector3.ZERO
	_speed = 1.0
	_clock = 0.0
	_side = 1.0
	_anchor = Vector3.INF
	_opening = Vector3.INF
	_from = Vector3.ZERO
	_to = Vector3.ZERO
	_from_basis = Basis.IDENTITY
	_turn_started = false
	_pose_delta.clear()
	_facing.clear()


func set_facts(facts: RefCounted) -> void:
	_facts = facts


func active() -> bool:
	return _active or _mix > 0.0


func mix() -> float:
	return _mix


func pose_delta() -> Dictionary:
	return _pose_delta.duplicate()


## The mouth anchor the act aims the player part at: the captured opening while she turns and the
## release runs, the smoothed live mouth once the turn has settled.
func anchor() -> Vector3:
	if _anchor.is_finite():
		return _anchor
	if _opening.is_finite():
		return _opening
	return anatomy.call("hole_point", 0.0) if is_instance_valid(anatomy) else Vector3.ZERO


## Write or erase the three oral pose keys on the live config in place, so a released turn cannot
## leave stale neck/head keys behind and no dictionary copy is made per tick.
func write_pose_delta(config: Dictionary) -> void:
	if _pose_delta.is_empty():
		config.erase("oral_pitch")
		config.erase("oral_yaw")
		config.erase("oral_roll")
		return
	config["oral_pitch"] = float(_pose_delta.get("oral_pitch", 0.0))
	config["oral_yaw"] = float(_pose_delta.get("oral_yaw", 0.0))
	config["oral_roll"] = float(_pose_delta.get("oral_roll", 0.0))


func facing() -> Dictionary:
	return _facing.duplicate()


## Start or stop the oral turn. Returns true when this call started it.
func toggle(state: int) -> bool:
	if not SETTINGS.anatomy_oral.get_bool() or state != 2 or pose != CATALOG.STANDING:
		return false
	if not _consent("oral"):
		_status("%s is not into that" % _display_name())
		return false
	var ends := _head_ends()
	if ends.is_empty():
		return false
	if not _active and _mix <= 0.0:
		_turn_started = true
		var mouth: Vector3 = pony.global_transform.affine_inverse() * _mouth_point()
		var scale: Vector3 = pony.global_transform.basis.get_scale()
		var turned := Basis(Vector3.UP, PI) * pony.global_transform.basis.orthonormalized()
		var opening: Vector3 = anatomy.call("hole_point", 0.0)
		var to: Vector3 = opening - turned * (mouth * scale)
		_opening = opening
		_anchor = opening
		_from = pony.global_position
		_to = Vector3(to.x, pony.global_position.y, to.z)
		_from_basis = pony.global_transform.basis.orthonormalized()
	_active = not _active
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null:
		if _active and mouth_rig.has_method("set_viseme"):
			mouth_rig.call("set_viseme", ORAL_MOUTH)
		elif not _active and mouth_rig.has_method("clear"):
			mouth_rig.call("clear")
	return _active


## Re-apply the oral mouth shape after a speech stop. The turn owns D only while it is active;
## the release already clears the mouth, so this is a no-op then.
func hold_viseme() -> void:
	if not _active:
		return
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("set_viseme"):
		mouth_rig.call("set_viseme", ORAL_MOUTH)


func tick(delta: float) -> void:
	var mix := move_toward(_mix, 1.0 if _active else 0.0, delta / ORAL_TURN_S)
	if mix != _mix:
		_mix = mix
		if _mix <= 0.0:
			_pose_delta.clear()
			if not _active:
				_anchor = Vector3.INF
				_turn_started = false
		var eased := smoothstep(0.0, 1.0, _mix)
		var basis: Basis = Basis(Vector3.UP, PI * eased) * _from_basis
		_facing = {"basis": basis, "amount": eased}
		pony.global_position = _from.lerp(_to, eased)
	if _mix > 0.0:
		_motion_tick(delta)


func end() -> void:
	if _turn_started and is_instance_valid(pony):
		pony.global_position = _from
	_active = false
	_mix = 0.0
	_turn_started = false
	_anchor = _opening
	_pose_delta.clear()
	_facing = {"basis": Basis.IDENTITY, "amount": 0.0}
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("clear"):
		mouth_rig.call("clear")


func teardown() -> void:
	_active = false
	_mix = 0.0
	_turn_started = false
	_pose_delta.clear()
	_facing.clear()
	_anchor = Vector3.INF
	_opening = Vector3.INF


func _motion_tick(delta: float) -> void:
	_style_left -= delta
	if _style_left <= 0.0:
		_style_left = randf_range(ORAL_STYLE_MIN_S, ORAL_STYLE_MAX_S)
		_style = ORAL_STYLES.pick_random()
		_side = -_side
	var blend := 1.0 - exp(-delta * ORAL_STYLE_BLEND)
	_now = _now.lerp(_style[0], blend)
	_speed = lerpf(_speed, float(_style[1]), blend)
	var pace := maxf(0.8, _facts.auto_pace if _facts != null else 1.0)
	_clock = fposmod(_clock + delta * pace * _speed, 16.0)
	var turn := TAU * _clock
	var mix := smoothstep(0.0, 1.0, _mix)
	var mouth := _mouth_point()
	_anchor = STATE.oral_anchor_step(_anchor, mouth, _opening, _mix, _active,
		ORAL_ANCHOR_RATE, delta)
	_pose_delta["oral_pitch"] = cos(turn) * _now.y * mix
	_pose_delta["oral_yaw"] = (sin(turn * 0.5) * _now.z + _side * _now.z * 0.5) * mix
	_pose_delta["oral_roll"] = sin(turn * 0.5 + 1.1) * _now.z * 0.6 * mix


func _size_scale() -> float:
	return _facts.size_scale if _facts != null else 1.0


func _display_name() -> String:
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	if identity != null and identity.get("display_name") != null:
		return str(identity.get("display_name"))
	return str(pony.name) if is_instance_valid(pony) else "the pony"


func _consent(key: String) -> bool:
	return bool(consent.call(key)) if consent.is_valid() else false


func _status(text: String) -> void:
	if status.is_valid():
		status.call(text)


func _head_ends() -> Array:
	var boop: Variant = pony.get("boop_node")
	var head: Variant = boop.get("head_skeleton") if boop != null else null
	if not head is Skeleton3D:
		return []
	var skeleton := head as Skeleton3D
	var bone := skeleton.find_bone("mHead")
	if bone < 0:
		return []
	return [skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin,
		boop.call("nose_world")]


func _pony_mouth() -> Variant:
	var head: Variant = pony.get("head")
	return head.get("mouth") if head != null else null


func _mouth_point() -> Vector3:
	var ends := _head_ends()
	if ends.is_empty():
		return anatomy.call("hole_point", 0.0)
	return (ends[1] as Vector3) + Vector3.DOWN * ORAL_BELOW_NOSE_M * _size_scale()
