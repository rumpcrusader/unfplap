extends RefCounted
## Missionary framing. The runtime owns the act state, lean and camera selection; this
## controller owns the frozen shot, its aim, the Anon avatar hiding and the start snapshot.

const MOTION := preload("res://mods/unfplap/act_motion.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

const MISSIONARY_CAMERA_HEIGHT_M := 0.45
const MISSIONARY_CAMERA_BACK_M := 0.22
const MISSIONARY_CAMERA_PULLBACK_M := 0.22
const MISSIONARY_CAMERA_LIFT_M := 0.10
const MISSIONARY_START_LEAN := 1.0

var runtime: Node
var main: Variant
var pony: Variant
var bed: Variant
var _presentation_cfg: Dictionary = {}
var _pose_cfg: Dictionary = {}

var _missionary_look_point := Vector3.INF
var _missionary_camera := Vector3.INF
var _missionary_camera_applied := Vector3.INF
var _missionary_head_roll := 0.0
var _missionary_start_camera: Camera3D
var _missionary_start_camera_transform := Transform3D.IDENTITY
var _missionary_start_player_transform := Transform3D.IDENTITY
var _missionary_start_pony_transform := Transform3D.IDENTITY
var _missionary_start_pony_posture := ""
var _missionary_start_saved := false
var _missionary_basis_logged := false
var _missionary_camera_log_until := 0
var _missionary_camera_log_next := 0
var _missionary_view: Camera3D
var _missionary_source_fov := 75.0
var _missionary_source_near := 0.05
var _missionary_source_far := 4000.0
var _missionary_source_cull := 0xFFFFFFFF
var _missionary_view_basis := Basis.IDENTITY
var _missionary_last_view_basis := Basis.IDENTITY
var _missionary_last_view_pos := Vector3.INF
var _missionary_last_head := Transform3D.IDENTITY
var _missionary_camera_rebuilds := 0
var _missionary_snap_ready := false
var _missionary_aim_until := 0
var _missionary_prev_camera: Camera3D
var _missionary_player_rotation := Vector3.ZERO
var _missionary_player_rot_saved := false
var _anon_avatars: Array[Node3D] = []
var _anon_avatar_states: Array[bool] = []
var _desktop_presentation: Node
var _desktop_presentation_enabled := true

func _resume_missionary_cuddle() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) or not is_instance_valid(main.player):
		runtime.call("_stand_after_pose")
		return
	# Revert the exact scene captured at start: camera, player and pony transforms.
	if _missionary_start_saved:
		# Player/pony first, camera last: setting the player yaw rotates a child camera, so the
		# snapshot camera transform must be applied after the rig is back in place.
		main.player.global_transform = _missionary_start_player_transform
		pony.global_transform = _missionary_start_pony_transform
		pony.reset_physics_interpolation()
		if is_instance_valid(_missionary_start_camera):
			_missionary_start_camera.global_transform = _missionary_start_camera_transform
			_missionary_start_camera.make_current()
		_log("missionary restore: snapshot camera=%s player=%s pony=%s player_yaw=%.3f" % [
			str(_missionary_start_camera_transform.origin), str(_missionary_start_player_transform.origin),
			str(_missionary_start_pony_transform.origin),
			float(main.player.rotation.y)])
	var seat: Variant = main.player.get("seat")
	var couch: Variant = null
	if is_instance_valid(seat) and seat.has_meta("couch"):
		couch = seat.get_meta("couch")
	if is_instance_valid(couch) and couch.has_method("accept") and bool(couch.call("accept", pony)):
		_log("missionary restore: cuddle resumed")
		return
	_log("missionary restore: cuddle resume failed; restoring posture")
	if _missionary_start_saved and _missionary_start_pony_posture != "":
		pony.request_posture(_missionary_start_pony_posture)
	else:
		runtime.call("_stand_after_pose")



func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return INF
	var fallback: float = float(bed.get_meta("mattress_top", 0.6)) + float(bed.global_position.y)
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


## Change the player's own eye height for the act instead of writing camera.position.y. That keeps
## `desktop_player._set_eye_y` as the single owner of the camera height and avoids drift/teleports.
func _hide_anon_avatar_for_missionary() -> void:
	if str(runtime.get("pose_id")) != CATALOG.MISSIONARY or not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	# Collect every presentation body once and save its visible state before disabling anything:
	# CouchAnonBody (bed rest) and AnonBody (desktop rig).
	if _anon_avatars.is_empty():
		for node: Node in main.player.find_children("*AnonBody*", "", true, false):
			if node is Node3D:
				_anon_avatars.append(node as Node3D)
				_anon_avatar_states.append((node as Node3D).visible)
	# The desktop presentation is a second Anon body that re-shows itself from its own process.
	# Disabling it is the only reliable way to keep it out of the bed shot.
	if not is_instance_valid(_desktop_presentation) and is_instance_valid(main.game):
		var presentation: Variant = main.game.get("desktop_presentation")
		if is_instance_valid(presentation):
			_desktop_presentation = presentation as Node
			var enabled: Variant = presentation.get("_enabled")
			_desktop_presentation_enabled = bool(enabled) if enabled != null else true
			if _desktop_presentation_enabled:
				presentation.call("set_enabled", false)
	if is_instance_valid(_desktop_presentation) and _desktop_presentation_enabled \
			and bool(_desktop_presentation.get("_enabled")) == true:
		_desktop_presentation.call("set_enabled", false)
	for i in _anon_avatars.size():
		if is_instance_valid(_anon_avatars[i]) and _anon_avatars[i].visible:
			_anon_avatars[i].visible = false


func _restore_anon_avatar() -> void:
	if is_instance_valid(_desktop_presentation) and _desktop_presentation_enabled:
		_desktop_presentation.call("set_enabled", true)
	for i in _anon_avatars.size():
		if is_instance_valid(_anon_avatars[i]):
			_anon_avatars[i].visible = _anon_avatar_states[i]
	_anon_avatars.clear()
	_anon_avatar_states.clear()
	_desktop_presentation = null
	_desktop_presentation_enabled = true


## Remember the exact scene at missionary start so ending early can revert to it.
func _snapshot_missionary_start() -> void:
	_missionary_start_camera = runtime.get_viewport().get_camera_3d() if runtime.get_viewport() != null else null
	if is_instance_valid(_missionary_start_camera):
		_missionary_start_camera_transform = _missionary_start_camera.global_transform
	if is_instance_valid(main) and is_instance_valid(main.player):
		_missionary_start_player_transform = main.player.global_transform
	if is_instance_valid(pony):
		_missionary_start_pony_transform = pony.global_transform
		if pony.has_method("posture_status"):
			var status: Variant = pony.call("posture_status")
			if status is Dictionary:
				_missionary_start_pony_posture = str((status as Dictionary).get("requested", ""))
	_missionary_start_saved = true
	_log("missionary snapshot camera=%s player=%s pony=%s posture=%s player_yaw=%.3f" % [
		str(_missionary_start_camera_transform.origin), str(_missionary_start_player_transform.origin),
		str(_missionary_start_pony_transform.origin), _missionary_start_pony_posture,
		_missionary_start_player_transform.basis.get_euler().y])


func _make_missionary_view() -> void:
	if bool(runtime.get("_player_pony")) or not is_instance_valid(pony):
		return
	if is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view")):
		return
	_missionary_prev_camera = runtime.get_viewport().get_camera_3d() if runtime.get_viewport() != null else null
	_missionary_view = Camera3D.new()
	_missionary_view.name = "UnfplapMissionaryView"
	_missionary_view.top_level = true
	_missionary_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var source: Camera3D = main.camera() if is_instance_valid(main) else null
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
		_log("missionary view setup source_fov=%.1f near=%.3f far=%.0f" % [
			source.fov, source.near, source.far])
	# The missionary view settles its aim on her neck (`apply_camera_motion`); the player look controls
	# are left alone so the bed/seated camera is not disturbed.
	_missionary_look_point = runtime.call("_neck_midpoint")
	var forward: Vector3 = -pony.global_basis.z.normalized() if is_instance_valid(pony) else Vector3.FORWARD
	if not _missionary_look_point.is_finite() or not is_instance_valid(pony) \
			or (_missionary_look_point - _missionary_camera).dot(forward) < -0.05:
		_missionary_look_point = (pony.global_position if is_instance_valid(pony) else _missionary_camera) \
			+ forward * 0.20 + Vector3.UP * 0.10
	_missionary_view_basis = _missionary_aim_basis(_missionary_camera)
	_missionary_aim_until = Time.get_ticks_msec() + 1000
	_missionary_camera_log_until = Time.get_ticks_msec() + 10000
	_missionary_camera_log_next = 0
	_missionary_snap_ready = false
	_missionary_camera_rebuilds = 0
	pony.add_child(_missionary_view)
	_missionary_view.current = true
	_missionary_log_setup()


func _missionary_log_setup() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) or not bool(main.get("debug_logs")):
		return
	var seat: Variant = main.player.get("seat") if is_instance_valid(main.player) else null
	var rest: Variant = main.player.get("_couch_rest") if is_instance_valid(main.player) else null
	_log("missionary setup pony=%s pos=%s anchor=%s camera=%s bed=%s bed_top=%.2f seat=%s rest=%.2f" % [
		str(pony.name), str(pony.global_position), str(_missionary_camera),
		str(runtime.get("source")),
		str(bed.name) if is_instance_valid(bed) else "null", _bed_surface_top(),
		str(seat.name) if is_instance_valid(seat) else "null",
		float(rest.get("amount")) if is_instance_valid(rest) else -1.0])


func _free_missionary_view() -> void:
	if is_instance_valid(_missionary_view):
		_missionary_view.current = false
		_missionary_view.queue_free()
	_missionary_view = null
	if is_instance_valid(_missionary_prev_camera):
		# The game may have changed the player camera's projection during the act; restore the
		# exact projection captured before the mod-owned view took over.
		_missionary_prev_camera.fov = _missionary_source_fov
		_missionary_prev_camera.near = _missionary_source_near
		_missionary_prev_camera.far = _missionary_source_far
		_missionary_prev_camera.cull_mask = _missionary_source_cull
		_missionary_prev_camera.make_current()
		_log("missionary view restore fov=%.1f near=%.3f far=%.0f" % [
			_missionary_prev_camera.fov, _missionary_prev_camera.near, _missionary_prev_camera.far])
	_missionary_prev_camera = null
	if is_instance_valid(main) and is_instance_valid(main.player):
		var source: Camera3D = main.camera() if is_instance_valid(main) else null
		if _missionary_player_rot_saved and is_instance_valid(source):
			source.rotation = _missionary_player_rotation
	_missionary_player_rot_saved = false


## Stable missionary camera target: the middle of her neck. The live nose (`listen_point`) moves as
## she aims/nuzzles and could end up behind the camera, which made the camera look backwards.
func _missionary_look_target() -> Vector3:
	if _missionary_look_point.is_finite():
		return _missionary_look_point
	if not is_instance_valid(pony):
		return Vector3.INF
	var forward: Vector3 = -pony.global_basis.z.normalized()
	return pony.global_position + forward * 0.20 + Vector3.UP * 0.10


## The fixed missionary view orientation: from the camera anchor toward her neck. Computed once so the
## camera does not track the snout while she nuzzles; bob only moves its position.
func _missionary_aim_basis(from_position: Vector3) -> Basis:
	var look := _missionary_look_target()
	var dir := look - from_position
	if dir.length_squared() < 0.000001:
		return Basis.IDENTITY
	dir = dir.normalized()
	# Near-vertical views make the world-up roll undefined; tilt the target a little further
	# forward so the horizon stays level instead of rolling the camera 90 degrees.
	if absf(dir.dot(Vector3.UP)) > 0.985:
		look += -pony.global_basis.z * 0.30
		dir = (look - from_position).normalized()
	return Basis.looking_at(dir, Vector3.UP)


func _missionary_body_scale() -> float:
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return clampf(float(pony.get("body_scale")), 0.8, 1.6)
	return 1.0


func _missionary_pullback() -> float:
	var value := float(_presentation_cfg.get("pullback", MISSIONARY_CAMERA_PULLBACK_M))
	return value * _missionary_body_scale()


## Framing pitch after the frozen neck aim. Positive looks up; the anchor and settle target do
## not move, so this only tilts the shot and applies live.
func _missionary_pitch_basis() -> Basis:
	var degrees := float(_presentation_cfg.get("pitch_deg", 0.0))
	return Basis(Vector3.RIGHT, deg_to_rad(degrees))


func _missionary_camera_offsets() -> Vector3:
	return Vector3(
		float(_presentation_cfg.get("forward", 0.0)),
		float(_presentation_cfg.get("height", 0.0)),
		float(_presentation_cfg.get("side", 0.0)))


## Side lean also travels along the mattress toward her head, outside the view-axis clamp. The
## amount is metres at full Q/E and is live.
func _missionary_side_lean_forward() -> float:
	var amount := float(_presentation_cfg.get("side_lean", 0.0))
	return amount * absf(float(runtime.get("_lean_view_side"))) * float(runtime.call("_lean_size_scale"))


func _missionary_camera_target() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var root: Vector3 = pony.global_position
	var back: Vector3 = pony.global_basis.z.normalized()
	var body_scale := _missionary_body_scale()
	# Stay behind her neck, toward her rump. Anchoring ahead of the neck put the camera over her
	# head and aimed the shot back down her torso, away from her face. Larger ponies need a
	# proportionally higher and farther-back anchor so the shot does not sit inside her neck.
	var height := (float(_pose_cfg.get("camera_height", MISSIONARY_CAMERA_HEIGHT_M)) + MISSIONARY_CAMERA_LIFT_M) \
		* body_scale
	if runtime.call("_size_name") == "canon":
		height *= 0.9
	var target := root + Vector3.UP * height \
		+ back * float(_pose_cfg.get("camera_back", MISSIONARY_CAMERA_BACK_M)) * body_scale
	var bed_top := _bed_surface_top()
	if is_finite(bed_top) and bed_top <= root.y + 2.0:
		target.y = maxf(target.y, bed_top + 0.30 * body_scale)
	target.y = clampf(target.y, root.y + 0.30 * body_scale, root.y + 1.50 * body_scale)
	# Fine missionary framing: forward along her body, vertical, and her lateral axis. The
	# base anchor would otherwise sit behind her neck and too high for the close shot.
	var offsets := _missionary_camera_offsets()
	target += -back * offsets.x
	target.y += offsets.y
	target += pony.global_basis.x.normalized() * offsets.z
	if is_finite(bed_top) and bed_top <= root.y + 2.0:
		target.y = maxf(target.y, bed_top + 0.10 * body_scale)
	return target


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


## The missionary head aim uses the camera as Anon's face. Keep a minimum distance so a large pony's
## camera anchor can be near her head without producing near-zero direction flips.
func _missionary_head_look_point(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	var kiss: Variant = runtime.call("_kiss_controller")
	var point := view.global_position
	# Move the virtual partner with the displayed lean. Otherwise the framing camera slides
	# sideways while her head stays on the fixed player camera and appears to turn the other way.
	if is_instance_valid(_missionary_view) and view != _missionary_view:
		point += _missionary_view_basis.x * kiss.lateral_offset(float(runtime.call("_lean_size_scale")))
		if is_instance_valid(pony):
			var bed_forward: Vector3 = -pony.global_basis.z
			bed_forward.y = 0.0
			if bed_forward.length_squared() > 0.0001:
				point += bed_forward.normalized() * _missionary_side_lean_forward()
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


## Debug readout of how far her actual face points from the act look target. The link updates
## the OpenPony head after the pose modifier, so this is the previous frame's settled frame.
func _missionary_gaze_error() -> float:
	if not is_instance_valid(pony) or not is_instance_valid(runtime.get("_pose")) or not runtime.get("_pose").look_point.is_finite():
		return -1.0
	if not pony.has_method("awareness_forward"):
		return -1.0
	var forward: Variant = pony.call("awareness_forward")
	var boop: Variant = pony.get("boop_node")
	if not forward is Vector3 or boop == null or not boop.has_method("skull_world"):
		return -1.0
	var origin: Variant = boop.call("skull_world")
	if not origin is Vector3 or not (origin as Vector3).is_finite():
		return -1.0
	var to: Vector3 = runtime.get("_pose").look_point - (origin as Vector3)
	if to.length_squared() < 0.000001:
		return -1.0
	return rad_to_deg((forward as Vector3).angle_to(to))

func _sync() -> void:
	main = runtime.get("main") if is_instance_valid(runtime) else null
	pony = runtime.get("pony") if is_instance_valid(runtime) else null
	bed = runtime.get("bed") if is_instance_valid(runtime) else null
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var pose_cfg: Variant = runtime.get("_pose_cfg") if is_instance_valid(runtime) else null
	_pose_cfg = pose_cfg if pose_cfg is Dictionary else {}


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


func prepare() -> void:
	_sync()
	_missionary_camera = _missionary_camera_target()
	_missionary_camera_applied = _missionary_camera_offsets()
	_missionary_basis_logged = false
	_snapshot_missionary_start()
	_make_missionary_view()


func reset_look() -> void:
	_missionary_look_point = Vector3.INF


func view() -> Camera3D:
	return _missionary_view


func head_look_point(viewer: Camera3D) -> Vector3:
	return _missionary_head_look_point(viewer)


func hide_avatar() -> void:
	_hide_anon_avatar_for_missionary()


func apply_framing() -> void:
	_sync()
	if not is_instance_valid(pony) or not _missionary_camera.is_finite():
		return
	var offsets := _missionary_camera_offsets()
	if offsets.is_equal_approx(_missionary_camera_applied):
		return
	var delta := offsets - _missionary_camera_applied
	_missionary_camera += -pony.global_basis.z.normalized() * delta.x
	_missionary_camera.y += delta.y
	_missionary_camera += pony.global_basis.x.normalized() * delta.z
	_missionary_camera_applied = offsets
	if _missionary_look_point.is_finite():
		_missionary_view_basis = _missionary_aim_basis(_missionary_camera)


func release() -> void:
	_restore_anon_avatar()
	_free_missionary_view()


func snapshot_yaw() -> float:
	return _missionary_start_player_transform.basis.get_euler().y if _missionary_start_saved else NAN


func resume_cuddle() -> void:
	_sync()
	_resume_missionary_cuddle()


func tick() -> void:
	_sync()
	var kiss: Variant = runtime.call("_kiss_controller")

	if not is_instance_valid(pony):
		return
	var body_scale := _missionary_body_scale()
	var bed_top := _bed_surface_top()
	var rebuild := ""
	if not _missionary_camera.is_finite():
		rebuild = "invalid"
	elif _missionary_camera.distance_to(pony.global_position) > 3.0:
		rebuild = "distance"
	elif is_finite(bed_top) and _missionary_camera.y < bed_top - 0.05:
		rebuild = "below-bed"
	if not rebuild.is_empty():
		_missionary_camera = _missionary_camera_target()
		_missionary_camera_rebuilds += 1
		_log("missionary CAMERA REBUILD #%d reason=%s size=%s scale=%.2f pony=%s anchor=%s bed_top=%.2f" % [
			_missionary_camera_rebuilds, rebuild, runtime.call("_size_name"), body_scale,
			str(pony.global_position), str(_missionary_camera), bed_top])
	if not _missionary_camera.is_finite():
		return
	if is_finite(bed_top) and bed_top <= pony.global_position.y + 2.0 \
			and _missionary_camera.y < bed_top + 0.15 * body_scale:
		_missionary_camera.y = bed_top + 0.30 * body_scale
	_missionary_camera.y = clampf(_missionary_camera.y, pony.global_position.y + 0.30 * body_scale,
		pony.global_position.y + 1.50 * body_scale)
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	_missionary_view.global_position = _missionary_camera + Vector3.UP * float(runtime.get("_bob"))
	# Pull the whole shot back along its own view axis; the frozen aim still points at her neck.
	_missionary_view.global_position += _missionary_view_basis.z * _missionary_pullback()
	var lean_scale: float = float(runtime.call("_lean_size_scale"))
	var lean_forward := MOTION.lean_distance(float(runtime.get("_lean_view_forward")), lean_scale) \
		+ MOTION.lean_distance(MISSIONARY_START_LEAN, lean_scale)
	var to_target := _missionary_look_target() - _missionary_camera
	if lean_forward < 0.0:
		# Never let the shot cross its own neck target and flip the view backwards.
		var room := maxf(0.0, to_target.dot(-_missionary_view_basis.z) - 0.12)
		lean_forward = -minf(-lean_forward, room)
	# Stop 0.12 m before the neck instead of crossing it when the start offset is added.
	var forward_room := maxf(0.0, to_target.dot(-_missionary_view_basis.z)
		+ _missionary_pullback() - 0.12)
	lean_forward = minf(lean_forward, forward_room)
	var kiss_lean: float = kiss.lean_distance()
	if kiss_lean > 0.0:
		var view_room := maxf(0.0, to_target.dot(-_missionary_view_basis.z)
			+ _missionary_pullback() - 0.12 - maxf(lean_forward, 0.0))
		kiss_lean = minf(kiss_lean, view_room)
	_missionary_view.global_position -= _missionary_view_basis.z \
		* (-float(runtime.get("_back")) + lean_forward + kiss_lean)
	# The speed-driven surge runs along the mattress toward her head, not down the view axis.
	var bed_forward: Vector3 = -pony.global_basis.z
	bed_forward.y = 0.0
	if bed_forward.length_squared() > 0.0001:
		_missionary_view.global_position += bed_forward.normalized() \
			* (float(runtime.get("_lean")) + _missionary_side_lean_forward())
	_missionary_view.global_position.y -= kiss.lean_drop() * kiss.lean()
	_missionary_view.global_position += _missionary_view_basis.x \
		* kiss.lateral_offset(lean_scale)
	runtime.set("_camera_basis_ready", true)
	# Settle the aim on her neck while the act pose blends in. The target is her neck, not
	# the moving view, and the basis comes from the fixed anchor; no feedback loop.
	if Time.get_ticks_msec() < _missionary_aim_until:
		var neck: Vector3 = runtime.call("_neck_midpoint")
		var forward: Vector3 = -pony.global_basis.z.normalized()
		# Never re-aim at a neck point behind the anchor; that flips the shot back down her
		# torso. Keep the previous target when the pose puts the neck behind the camera.
		if neck.is_finite() and (neck - _missionary_camera).dot(forward) > 0.02:
			_missionary_look_point = neck
		_missionary_view_basis = _missionary_aim_basis(_missionary_camera)
	var lean := Basis.from_euler(Vector3(
		-deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(float(runtime.get("_lean_view_forward"))) * lean_scale,
		-deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG) * float(runtime.get("_lean_view_side")) * lean_scale,
		(-deg_to_rad(MOTION.LEAN_SIDE_ROLL_DEG) * float(runtime.get("_lean_view_side"))
			+ deg_to_rad(MOTION.LEAN_ROLL_DEG) * float(runtime.get("_lean_view_forward"))) * lean_scale))
	_missionary_view.global_basis = _missionary_view_basis * _missionary_pitch_basis() * lean
	var look_dir := _missionary_look_target() - _missionary_view.global_position
	var look_dot := (-_missionary_view.global_basis.z).dot(look_dir.normalized()) \
		if look_dir.length_squared() > 0.000001 else 1.0
	if not _missionary_basis_logged:
		_missionary_basis_logged = true
		_log("missionary camera base_euler=%s applied_basis=%s" % [
			str(_missionary_view_basis.get_euler()), str(_missionary_view.global_basis)])
	var now := Time.get_ticks_msec()
	if now < _missionary_camera_log_until and now >= _missionary_camera_log_next:
		_missionary_camera_log_next = now + 100
		var dot := (-_missionary_view.global_basis.z).dot(look_dir.normalized()) \
			if look_dir.length_squared() > 0.000001 else 0.0
		_log("missionary cam anchor=%s view=%s base_euler=%s target=%s dot=%.3f gaze=%.1f bed=%.2f pose=%.2f lean=%.2f/%.2f size=%s%.2f" % [
			str(_missionary_camera), str(_missionary_view.global_position),
			str(_missionary_view_basis.get_euler()), str(_missionary_look_target()), dot,
			_missionary_gaze_error(), bed_top, runtime.call("_pose_basis_amount"),
			float(runtime.get("_lean_view_forward")), float(runtime.get("_lean_view_side")), runtime.call("_size_name"), float(runtime.call("_size_scale"))])
	if is_instance_valid(main) and bool(main.get("debug_logs")):
		var view_basis := _missionary_view.global_basis
		if _missionary_snap_ready:
			var basis_delta := rad_to_deg(_missionary_last_view_basis.get_rotation_quaternion() \
				.angle_to(view_basis.get_rotation_quaternion()))
			var pos_delta := _missionary_last_view_pos.distance_to(_missionary_view.global_position)
			if basis_delta > 15.0 or pos_delta > 0.12:
				_log("missionary CAMERA SNAP basis=%.1fdeg pos=%.3fm view=%s anchor=%s target=%s dot=%.3f lean=%.2f/%.2f kiss=%.2f size=%s scale=%.2f" % [
					basis_delta, pos_delta, str(_missionary_view.global_position), str(_missionary_camera),
					str(_missionary_look_target()), look_dot, float(runtime.get("_lean_view_forward")), float(runtime.get("_lean_view_side")),
					kiss.lean(), runtime.call("_size_name"), body_scale])
			var head := _missionary_head_transform()
			if head.origin.is_finite():
				var head_angle := rad_to_deg(_missionary_last_head.basis.get_rotation_quaternion() \
					.angle_to(head.basis.get_rotation_quaternion()))
				var head_move := _missionary_last_head.origin.distance_to(head.origin)
				if head_angle > 18.0 or head_move > 0.05:
					_log("missionary HEAD SNAP angle=%.1fdeg move=%.3fm head=%s look=%s view=%s dot=%.3f size=%s scale=%.2f" % [
						head_angle, head_move, str(head.origin), str(runtime.get("_pose").look_point if is_instance_valid(runtime.get("_pose")) else Vector3.INF),
						str(_missionary_view.global_position), look_dot, runtime.call("_size_name"), body_scale])
				_missionary_last_head = head
		_missionary_last_view_basis = view_basis
		_missionary_last_view_pos = _missionary_view.global_position
		_missionary_snap_ready = true
	return


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
