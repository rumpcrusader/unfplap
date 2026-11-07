extends Node
## Debug: keep every loaded pony's tail collapsed while `debug_hide_tails` is on.
##
## Hiding only the rig tail mesh is not enough: the near and far LOD meshes merge the tail into a
## larger skinned mesh. Collapsing the hair tail bones hides all of it, and the native tail bones
## cover the far bake's skeleton.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const TAIL_HIDE := preload("res://mods/unfplap/tail_hide.gd")
const GROUP := "ai_characters"
## Only the chain root is collapsed; every child bone inherits its scale, so the whole tail
## shrinks without stacking tiny scales down the chain.
const HAIR_BONES: Array[StringName] = [&"mTail1"]
const BODY_BONES: Array[StringName] = [&"pony_tail_01"]

var _clock := 0.0
## pony -> the modifiers installed on its hair and body skeletons.
var _pairs: Dictionary = {}


func _process(delta: float) -> void:
	var on := TUNABLES.get_bool("debug_hide_tails")
	if not on and _pairs.is_empty():
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 0.25
	if on:
		_sync()
	else:
		_clear()


func _sync() -> void:
	for pony: Variant in get_tree().get_nodes_in_group(GROUP):
		if not is_instance_valid(pony):
			continue
		var pair: Array = _pairs.get(pony, [])
		_attach(pony, pair, "hair_skeleton", HAIR_BONES)
		_attach(pony, pair, "skeleton", BODY_BONES)
		_pairs[pony] = pair
	for pony: Variant in _pairs.keys():
		if not is_instance_valid(pony):
			_pairs.erase(pony)


func _attach(pony: Node, pair: Array, property: String, bones: Array[StringName]) -> void:
	var skeleton: Variant = pony.get(property)
	if not skeleton is Skeleton3D:
		return
	for entry: Variant in pair:
		if is_instance_valid(entry) and (entry as Node).get_parent() == skeleton:
			return
	var modifier := TAIL_HIDE.new()
	modifier.name = "UnfplapTailHide"
	modifier.set("bones", bones)
	(skeleton as Skeleton3D).add_child(modifier)
	modifier.call("set_hiding", true)
	pair.append(modifier)


func _clear() -> void:
	for pair: Variant in _pairs.values():
		for entry: Variant in pair:
			if not is_instance_valid(entry):
				continue
			(entry as Node).call("set_hiding", false)
			(entry as Node).queue_free()
	_pairs.clear()


func _exit_tree() -> void:
	_clear()
