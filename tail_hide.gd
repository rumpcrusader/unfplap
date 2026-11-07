extends SkeletonModifier3D
## Debug: collapse a set of tail bones without splitting a mesh. Only the scale changes; each
## bone keeps its origin and rotation, so the skin follows and the mane is untouched.
##
## The modifier is appended to the hair skeleton after the game's tail solver. Act tail modifiers
## added later only rotate or translate, so they cannot undo this scale.

const HIDE_SCALE := 0.001

var bones: Array[StringName] = []

var _ids: Array[int] = []
var _saved: Array[Vector3] = []
var _resolved := false
var _active := false


func _ready() -> void:
	process_priority = 1000


func set_hiding(on: bool) -> void:
	_active = on
	if not on:
		restore()


func restore() -> void:
	if not _resolved:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	for i: int in _ids.size():
		var id := _ids[i]
		if id < 0 or id >= sk.get_bone_count():
			continue
		var pose := sk.get_bone_pose(id)
		sk.set_bone_pose(id,
			Transform3D(pose.basis.orthonormalized().scaled(_saved[i]), pose.origin))


func _process_modification() -> void:
	if not _active:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if not _resolved:
		_resolved = true
		for bone_name: StringName in bones:
			var id := sk.find_bone(bone_name)
			if id < 0:
				continue
			_ids.append(id)
			_saved.append(sk.get_bone_pose(id).basis.get_scale())
	if _ids.is_empty():
		return
	for i: int in _ids.size():
		var id := _ids[i]
		if id < 0 or id >= sk.get_bone_count():
			continue
		var pose := sk.get_bone_pose(id)
		sk.set_bone_pose(id, Transform3D(
			pose.basis.orthonormalized().scaled(_saved[i] * HIDE_SCALE), pose.origin))


func _exit_tree() -> void:
	restore()
