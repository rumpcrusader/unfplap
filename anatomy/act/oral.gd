extends RefCounted
## The standing oral mouth/contact provider: her mouth point, the base opening, the D viseme and
## the clear action. It owns no turn, no mix, no facing and no pose keys; the pose service's oral
## turn drives the frame and the contact anchor. Contract: `docs/anatomy.md`.

const ORAL_MOUTH := "D"
const ORAL_BELOW_NOSE_M := 0.03

var pony: Node3D = null
var anatomy: Node = null
## The player's size scale, written by the act each tick from its typed facts.
var size_scale := 1.0

var _viseme := ""


func setup(pony_node: Node3D, anatomy_node: Node) -> void:
	pony = pony_node
	anatomy = anatomy_node
	reset()


func reset() -> void:
	size_scale = 1.0
	_viseme = ""


func teardown() -> void:
	_viseme = ""


func set_scale(value: float) -> void:
	size_scale = value


## The mouth anchor the pose turn aims the player part at once the turn has settled: just below
## her nose, in world space.
func mouth_point() -> Vector3:
	var ends := _head_ends()
	if ends.is_empty():
		return opening()
	return (ends[1] as Vector3) + Vector3.DOWN * ORAL_BELOW_NOSE_M * size_scale


## The base vulva opening, independent of the live hole mix. The pose turn captures it as the
## opening the turn starts from.
func opening() -> Vector3:
	if is_instance_valid(anatomy) and anatomy.has_method("hole_point"):
		var point: Variant = anatomy.call("hole_point", 0.0)
		if point is Vector3 and (point as Vector3).is_finite():
			return point
	return Vector3.ZERO


func set_viseme(letter: String) -> void:
	_viseme = letter
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("set_viseme"):
		mouth_rig.call("set_viseme", letter)


## Re-apply the current mouth shape after a speech stop. The base game restores its rest viseme
## and the oral segment owns the open mouth only while the edge holds it.
func hold_viseme() -> void:
	if _viseme.is_empty():
		return
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("set_viseme"):
		mouth_rig.call("set_viseme", _viseme)


func clear() -> void:
	_viseme = ""
	var mouth_rig: Variant = _pony_mouth()
	if mouth_rig != null and mouth_rig.has_method("clear"):
		mouth_rig.call("clear")


func _head_ends() -> Array:
	if not is_instance_valid(pony):
		return []
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
	var head: Variant = pony.get("head") if is_instance_valid(pony) else null
	return head.get("mouth") if head != null else null
