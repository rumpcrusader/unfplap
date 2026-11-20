extends RefCounted
## The missionary view: one camera at the act body's eye, pushed out of her skull and muzzle. The
## live offsets and the free look ride on top. Contract: `docs/camera.md` (`## Missionary camera`).

const WORLD := preload("res://mods/unfplap/world/service.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The closest an Anon-eyes kiss lean-in may put the eye to her face point: her muzzle extends past
## it, and the view does not move for a kiss.
const KISS_CLEARANCE_M := 0.45

var facts: Variant
var pony: Variant
var bed: Variant

var _missionary_view: Camera3D
var _missionary_prev_camera: Camera3D
var _missionary_player_rotation := Vector3.ZERO
var _missionary_player_rot_saved := false
var _missionary_source_fov := 75.0
var _missionary_source_near := 0.05
var _missionary_source_far := 4000.0
var _missionary_source_cull := 0xFFFFFFFF
var _free_look_log_at := 0


## Read the live scene handles from the typed act view. The runtime rewrites the view before
## it hands the controller out, so this is a copy, not a read of the runtime node.
func _sync() -> void:
	if facts == null:
		pony = null
		bed = null
		return
	pony = facts.pony
	bed = facts.bed


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


## Mount the act's own view once the scene is settled. The frame owns the scene snapshot and the
## avatar hold, so this is the view node only.
func prepare() -> void:
	_sync()
	_make_missionary_view()


func view() -> Camera3D:
	return _missionary_view


func head_look_point(viewer: Camera3D) -> Vector3:
	return _missionary_head_look_point(viewer)


## Unmount the act's view and hand the game camera back.
func release() -> void:
	_free_missionary_view()


func tick() -> void:
	_sync()
	if not is_instance_valid(pony):
		return
	var look := Vector3.ZERO
	if facts != null and bool(facts.free_look_active):
		var rotation: Variant = facts.call_value(facts.free_look_rotation, Vector3.ZERO)
		if rotation is Vector3:
			look = rotation
	_tick_eye(facts.kiss_controller(), look)


## His own view: the camera is his posed head, so the lean (which bends his chest and neck) and the
## authored body are what move it. The kiss still leans the eye in towards the aim.
func _tick_eye(kiss: Variant, look: Vector3) -> void:
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	var body: Variant = facts.missionary_body() if facts != null else null
	if body == null:
		return
	var eye: Variant = body.call("eye_transform")
	if not (eye is Transform3D) or not (eye as Transform3D).origin.is_finite():
		return
	var basis := (eye as Transform3D).basis.orthonormalized()
	var at: Vector3 = (eye as Transform3D).origin
	if absf(look.x) > 0.00001 or absf(look.y) > 0.00001:
		basis = Basis(Vector3.UP, look.y) * basis * Basis(Vector3.RIGHT, look.x)
	# The same speed-driven surge/bob the standing camera uses; at rest both settle to zero.
	at += Vector3.UP * float(facts.bob)
	at -= basis.z * float(facts.lean)
	var aim: Vector3 = facts.call_value(facts.missionary_face_point, Vector3.INF)
	if aim.is_finite():
		at += basis.x * kiss.lateral_offset(float(facts.lean_size_scale))
		at.y -= kiss.lean_drop() * kiss.lean()
		if kiss.lean() > 0.0:
			var reach := (aim - at).length()
			at -= basis.z * minf(kiss.lean_distance(),
				maxf(0.0, reach - KISS_CLEARANCE_M * _missionary_body_scale()))
	at = _clear_live_head(at)
	_missionary_view.global_position = at
	_missionary_view.global_basis = basis
	facts.mark_camera_basis_ready()
	if (absf(look.x) > 0.00001 or absf(look.y) > 0.00001) \
			and Time.get_ticks_msec() >= _free_look_log_at:
		_free_look_log_at = Time.get_ticks_msec() + 2000
		LOG.debug("free look eye=%s rotation=%s", [str(at), str(look)])


func _missionary_body_scale() -> float:
	# The real body size, the same number the pose placement and the anatomy use. The body scales
	# with the rig, so the eye, the head clearance and the kiss distance must too; a floor keeps
	# a degenerate rig from dividing by zero.
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return maxf(float(pony.get("body_scale")), 0.1)
	return 1.0


## Public: the fluid ground for the act. The anatomy act receives this value in its facts context
## instead of reaching into the camera controller.
func bed_surface_top() -> float:
	return _bed_surface_top()


func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return INF
	var fallback: float = float(bed.get_meta("mattress_top", 0.6)) + float(bed.global_position.y)
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


## Push the eye out of her skull sphere and muzzle capsule. The surfaces move as she turns, so a
## point target cannot keep a close lean out of her head.
func _clear_live_head(at: Vector3) -> Vector3:
	var clearance := float(facts.head_clearance) if facts != null else 0.0
	if clearance <= 0.0001 or not is_instance_valid(pony):
		return at
	var boop: Variant = pony.get("boop_node")
	if boop == null or not is_instance_valid(boop):
		return at
	var skull: Variant = boop.call("skull_world")
	var nose: Variant = boop.call("nose_world")
	if not (skull is Vector3) or not (nose is Vector3):
		return at
	var scale := _missionary_body_scale()
	var point := _push_sphere(at, skull, 0.09 * scale + clearance)
	if boop.has_method("muzzle_world"):
		var muzzle: Variant = boop.call("muzzle_world")
		if muzzle is Vector3:
			point = _push_capsule(point, muzzle, nose, 0.04 * scale + clearance)
	return point


static func _push_sphere(p: Vector3, centre: Vector3, radius: float) -> Vector3:
	var offset := p - centre
	if offset.length_squared() >= radius * radius:
		return p
	if offset.length_squared() < 0.0000001:
		offset = Vector3.UP
	return centre + offset.normalized() * radius


static func _push_capsule(p: Vector3, a: Vector3, b: Vector3, radius: float) -> Vector3:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + ab * t
	var offset := p - closest
	if offset.length_squared() >= radius * radius:
		return p
	if offset.length_squared() < 0.0000001:
		offset = Vector3.UP
	return closest + offset.normalized() * radius


## Her head, for the aim and the runtime's gaze target.
func _missionary_head_transform() -> Transform3D:
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return Transform3D.IDENTITY
	var skeleton := sk as Skeleton3D
	var head := skeleton.find_bone("pony_head")
	if head < 0:
		return Transform3D.IDENTITY
	return skeleton.global_transform * skeleton.get_bone_global_pose(head)


## Where her gaze goes: a world point. Keep a minimum distance so Anon's face cannot sit inside her
## head and produce near-zero direction flips.
func head_look_point_at(point: Vector3) -> Vector3:
	if not point.is_finite():
		return Vector3.INF
	var head := _missionary_head_transform()
	if not head.origin.is_finite():
		return point
	var offset := point - head.origin
	var minimum := 0.45 * _missionary_body_scale()
	if offset.length() >= minimum:
		return point
	var direction: Vector3 = offset.normalized() if offset.length_squared() > 0.000001 \
		else -pony.global_basis.z.normalized()
	return head.origin + direction * minimum


## The standing/legacy path: the camera stands in for Anon's face.
func _missionary_head_look_point(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	return head_look_point_at(view.global_position)


func _make_missionary_view() -> void:
	if is_instance_valid(_missionary_view):
		return
	if facts == null or bool(facts.player_pony) or not is_instance_valid(pony):
		return
	if bool(WORLD.headset_view()):
		return
	_missionary_prev_camera = facts.viewport.get_camera_3d() \
		if facts.viewport != null else null
	_missionary_view = Camera3D.new()
	_missionary_view.name = "UnfplapMissionaryView"
	_missionary_view.top_level = true
	_missionary_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var source: Camera3D = WORLD.camera()
	if is_instance_valid(source):
		if not _missionary_player_rot_saved:
			_missionary_player_rotation = source.rotation
			_missionary_player_rot_saved = true
		_missionary_source_fov = source.fov
		_missionary_source_near = source.near
		_missionary_source_far = source.far
		_missionary_source_cull = source.cull_mask
		_missionary_view.fov = _missionary_source_fov
		_missionary_view.near = _missionary_source_near
		_missionary_view.far = _missionary_source_far
		_missionary_view.cull_mask = _missionary_source_cull
		LOG.debug("missionary view setup source_fov=%.1f near=%.3f far=%.0f", [
			source.fov, source.near, source.far])
	pony.add_child(_missionary_view)
	_missionary_view.current = true


func _free_missionary_view() -> void:
	if is_instance_valid(_missionary_view):
		_missionary_view.current = false
		_missionary_view.queue_free()
	_missionary_view = null
	if is_instance_valid(_missionary_prev_camera):
		_missionary_prev_camera.fov = _missionary_source_fov
		_missionary_prev_camera.near = _missionary_source_near
		_missionary_prev_camera.far = _missionary_source_far
		_missionary_prev_camera.cull_mask = _missionary_source_cull
		_missionary_prev_camera.make_current()
		LOG.debug("missionary view restore fov=%.1f near=%.3f far=%.0f", [
			_missionary_prev_camera.fov, _missionary_prev_camera.near,
			_missionary_prev_camera.far])
	_missionary_prev_camera = null
	if is_instance_valid(WORLD.player):
		var source: Camera3D = WORLD.camera()
		if _missionary_player_rot_saved and is_instance_valid(source):
			source.rotation = _missionary_player_rotation
	_missionary_player_rot_saved = false
