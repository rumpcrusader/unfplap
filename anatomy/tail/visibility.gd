extends Node
## Debug: collapse every loaded pony's tail bones while `debug_hide_tails` is on.
## Hiding the rig tail mesh alone is not enough, because the near and far LOD meshes merge it
## into a larger skinned mesh.
## The facade pushes the switch, so this node processes only while the toggle is on.

const TAIL_HIDE := preload("res://mods/unfplap/anatomy/tail/hide.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const GROUP := "ai_characters"
## Only the chain root is collapsed; every child bone inherits its scale, so the whole tail
## shrinks without stacking tiny scales down the chain.
const HAIR_BONES: Array[StringName] = [&"mTail1"]
const BODY_BONES: Array[StringName] = [&"pony_tail_01"]

var rig: RIG = null
var _clock := 0.0
## True while the Debug switch is on. The anatomy facade pushes it, so nothing reads Settings
## here per frame.
var _on := false
## pony -> the modifiers installed on its hair and body skeletons (`Array[TAIL_HIDE]`).
var _pairs: Dictionary[Node, Array] = {}


func setup(rig_node: RIG) -> void:
	rig = rig_node


func _ready() -> void:
	set_process(false)
	set_enabled(SETTINGS.debug_hide_tails.get_bool())


## The Debug switch. Called by the anatomy facade on every settings refresh.
func set_enabled(on: bool) -> void:
	if on == _on:
		return
	_on = on
	_clock = 0.0
	if on:
		_sync()
	else:
		_clear()
	set_process(on)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 0.25
	_sync()


func _sync() -> void:
	for pony: Node in get_tree().get_nodes_in_group(GROUP):
		if not is_instance_valid(pony):
			continue
		if not _pairs.has(pony):
			var fresh: Array[TAIL_HIDE] = []
			_pairs[pony] = fresh
		var pair: Array[TAIL_HIDE] = _pairs[pony]
		if rig == null:
			continue
		_attach(pair, rig.hair_skeleton_of(pony), HAIR_BONES)
		_attach(pair, rig.skeleton_of(pony), BODY_BONES)
	for pony: Node in _pairs.keys():
		if not is_instance_valid(pony):
			_pairs.erase(pony)


func _attach(pair: Array[TAIL_HIDE], skeleton: Skeleton3D,
		bones: Array[StringName]) -> void:
	if skeleton == null:
		return
	for entry: TAIL_HIDE in pair:
		if is_instance_valid(entry) and entry.get_parent() == skeleton:
			return
	var modifier := TAIL_HIDE.new()
	modifier.name = "UnfplapTailHide"
	modifier.bones = bones
	skeleton.add_child(modifier)
	modifier.set_hiding(true)
	pair.append(modifier)


func _clear() -> void:
	for pair: Array[TAIL_HIDE] in _pairs.values():
		for entry: TAIL_HIDE in pair:
			if not is_instance_valid(entry):
				continue
			entry.set_hiding(false)
			entry.queue_free()
	_pairs.clear()


func _exit_tree() -> void:
	_clear()
