extends RefCounted
## The live pose's bed and ground space and the follow that keeps a frame with the moving scene.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

## The absent pose frame: a real transform whose infinite origin no reader mistakes for space.
const NO_FRAME := Transform3D(Basis.IDENTITY, Vector3.INF)

var _session: Variant = null
var _bed_node: Node3D = null
var _bed_frame: Variant = null
var _bed_source := Transform3D.IDENTITY
var _bed_saved := false
var _ground_frame: Variant = null
var _ground_source := Transform3D.IDENTITY
var _ground_saved := false


func _init(session: Variant) -> void:
	_session = session


## Seed the live pose's one space: the bed frame from the start bed, or the ground frame from her
## root. The bed branch leaves the ground frame and the size name untouched.
func begin(bed: Variant, pony: Node3D) -> void:
	_bed_node = bed if bed is Node3D else null
	var view: POSE_VIEW = _session._view
	var pose_node: Variant = _session._pose_node
	if str(view.frame) == "bed":
		var bed_space := _missionary_frame()
		if has_frame(bed_space):
			_bed_frame = bed_space
			_bed_saved = is_instance_valid(_bed_node)
		else:
			_bed_frame = null
			_bed_saved = false
		if _bed_saved:
			_bed_source = (_bed_node as Node3D).global_transform
		pose_node.bed_frame = _bed_frame
		view.bed_frame = _bed_frame
	else:
		var ground := _ground_frame_from(pony)
		if has_frame(ground):
			_ground_frame = ground
			_ground_saved = is_instance_valid(pony)
		else:
			_ground_frame = null
			_ground_saved = false
		if _ground_saved:
			_ground_source = (pony as Node3D).global_transform
		pose_node.ground_frame = _ground_frame


## Keep the family's frame with the moving scene.
func sync(family: String) -> void:
	if family == "bed":
		_sync_bed()
	else:
		_sync_ground()


## The live pose frame: the bed's mattress space or the pony root's ground space.
func frame(view: POSE_VIEW) -> Transform3D:
	if str(view.frame) == "ground":
		return _ground_frame if _ground_frame is Transform3D else NO_FRAME
	if str(view.frame) == "bed":
		return _bed_frame if _bed_frame is Transform3D else NO_FRAME
	return NO_FRAME


## Drop both frames and the bed source for a pose-start leave or the one act exit.
func reset() -> void:
	_bed_frame = null
	_bed_saved = false
	_bed_source = Transform3D.IDENTITY
	_session._view.bed_frame = null
	_ground_frame = null
	_ground_saved = false
	_ground_source = Transform3D.IDENTITY


## True when a pose frame is real space: the absent frame carries an infinite origin.
func has_frame(frame: Transform3D) -> bool:
	return frame.origin.is_finite()


## Bed space for the authored pose: the middle of the real mattress top, in the bed's axes, the
## pillow end at -Z. An absent frame means no bed pose is live, so the procedural driver stays out.
func _missionary_frame() -> Transform3D:
	if str(_session._view.frame) != "bed" or not is_instance_valid(_bed_node):
		return NO_FRAME
	var fallback: float = float(_bed_node.get_meta("mattress_top", 0.6)) \
		+ float(_bed_node.global_position.y)
	var points: Array[Vector3] = [_bed_node.global_position]
	var top: float = WORLD.bed(_bed_node).surface_top(points, fallback)
	if not is_finite(top):
		return NO_FRAME
	var at: Vector3 = _bed_node.global_position
	var basis: Basis = _bed_node.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


## Ground space for an authored ground pose, seeded from the pony root. Like the bed frame with its
## bed, it is carried by the root from then on.
func _ground_frame_from(pony: Node3D) -> Transform3D:
	if not is_instance_valid(pony):
		return NO_FRAME
	return Transform3D(pony.global_basis.orthonormalized(), pony.global_position)


## Carry the bed-space pose, act body and anatomy placement with a bed that moves under the act
## (CloudDrift); the delta is rigid, so the top height is not measured again.
func _sync_bed() -> void:
	if str(_session._view.frame) != "bed" or not is_instance_valid(_bed_node) \
			or not _bed_saved or not _bed_frame is Transform3D:
		return
	var now: Transform3D = _bed_node.global_transform
	if now.is_equal_approx(_bed_source):
		return
	var delta: Transform3D = now * _bed_source.affine_inverse()
	_bed_frame = delta * (_bed_frame as Transform3D)
	_bed_source = now
	if is_instance_valid(_session._pose_node):
		_session._pose_node.bed_frame = _bed_frame
	_session._view.bed_frame = _bed_frame


## Turn the ground frame with the pony root each tick; the oral turn moves the root, so the frame
## turns with her exactly once.
func _sync_ground() -> void:
	var pony: Node3D = _session._pony()
	if str(_session._view.frame) != "ground" or not is_instance_valid(pony) \
			or not _ground_saved or not _ground_frame is Transform3D:
		return
	var now: Transform3D = (pony as Node3D).global_transform
	if now.is_equal_approx(_ground_source):
		return
	var delta: Transform3D = now * _ground_source.affine_inverse()
	_ground_frame = delta * (_ground_frame as Transform3D)
	_ground_source = now
	if is_instance_valid(_session._pose_node):
		_session._pose_node.ground_frame = _ground_frame
