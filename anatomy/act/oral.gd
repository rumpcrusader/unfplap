extends RefCounted
## The standing oral mouth/contact provider: her mouth point, the base opening, the D viseme and
## the clear action. It owns no turn, no mix, no facing and no pose keys; the pose service's oral
## turn drives the frame and the contact anchor. Contract: `docs/anatomy.md`.

const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")

const ORAL_MOUTH := "D"
const ORAL_BELOW_NOSE_M := 0.03


var pony: Node3D = null
var anatomy: CONTROLLER = null
var rig: RIG = null
## The player's size scale, written by the act each tick from its typed facts.
var size_scale := 1.0

var _viseme := ""


func setup(pony_node: Node3D, anatomy_node: CONTROLLER, rig_node: RIG) -> void:
	pony = pony_node
	anatomy = anatomy_node
	rig = rig_node
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
	if is_instance_valid(anatomy):
		var point := anatomy.hole_point(0.0)
		if point.is_finite():
			return point
	return Vector3.ZERO


func set_viseme(letter: String) -> void:
	_viseme = letter
	if rig != null:
		rig.set_viseme(_pony_mouth(), letter)


## Re-apply the current mouth shape after a speech stop. The base game restores its rest viseme
## and the oral segment owns the open mouth only while the edge holds it.
func hold_viseme() -> void:
	if _viseme.is_empty() or rig == null:
		return
	rig.set_viseme(_pony_mouth(), _viseme)


func clear() -> void:
	_viseme = ""
	if rig != null:
		rig.clear_viseme(_pony_mouth())


func _head_ends() -> Array:
	if not is_instance_valid(pony) or rig == null:
		return []
	var boop := rig.boop_of(pony)
	var skeleton := rig.head_skeleton_of(boop)
	if skeleton == null:
		return []
	var bone := skeleton.find_bone("mHead")
	if bone < 0:
		return []
	return [skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin,
		rig.nose_world(boop)]


func _pony_mouth() -> Node:
	return rig.mouth_of(rig.head_of(pony))
