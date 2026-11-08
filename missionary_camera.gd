extends RefCounted
## Missionary framing and the act avatar hiding. There is one shot: the **authored** one. The eye
## blends between five bed-relative camera positions authored in the pose lab, selected by the lean,
## and the aim slides from her live face to her vulva. See ROTATION.md.
##
## Free look (debug) turns the shot where it stands.
##
## The eye stays on that trajectory unless **Third-person views** (debug) is on: then the lean also
## tilts the eye and the thrust surge travels along the mattress, so the shot drifts around the two
## bodies instead of following the authored positions.

const MOTION := preload("res://mods/unfplap/act_motion.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

const SHOT_IDS := ["start", "back", "front", "left", "right"]

var runtime: Node
var main: Variant
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
var _missionary_start_camera: Camera3D
var _missionary_start_camera_transform := Transform3D.IDENTITY
var _missionary_start_player_transform := Transform3D.IDENTITY
var _missionary_start_pony_transform := Transform3D.IDENTITY
var _missionary_start_pony_posture := ""
var _missionary_start_saved := false
var _desktop_presentation: Node
var _desktop_presentation_enabled := true
var _shot_offsets_logged := Vector3.INF
var _free_look_log_at := 0
## Shot ids already reported missing from the asset in this act.
var _missing_shots_logged: Dictionary = {}


func _sync() -> void:
	main = runtime.get("main") if is_instance_valid(runtime) else null
	pony = runtime.get("pony") if is_instance_valid(runtime) else null
	bed = runtime.get("bed") if is_instance_valid(runtime) else null


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


func prepare() -> void:
	_sync()
	_missing_shots_logged.clear()
	_snapshot_missionary_start()
	_make_missionary_view()
	_log_shot_setup()


func reset_look() -> void:
	pass


func view() -> Camera3D:
	return _missionary_view


func head_look_point(viewer: Camera3D) -> Vector3:
	return _missionary_head_look_point(viewer)


func hide_avatar() -> void:
	_hide_anon_avatar_for_missionary()


func release() -> void:
	_restore_anon_avatar()
	_free_missionary_view()


func snapshot_yaw() -> float:
	return _missionary_start_player_transform.basis.get_euler().y if _missionary_start_saved else NAN


func restore_scene() -> void:
	_sync()
	_restore_scene()


func tick() -> void:
	_sync()
	if not is_instance_valid(pony):
		return
	var look := Vector3.ZERO
	if is_instance_valid(runtime) and runtime.has_method("free_look_active") \
			and bool(runtime.call("free_look_active")):
		var rotation: Variant = runtime.call("free_look_rotation")
		if rotation is Vector3:
			look = rotation
	_tick_authored(runtime.call("_kiss_controller"), look)


## The authored shot. The eye blends between the five authored positions as offsets from `start`,
## selected by the lean (S → her pelvis, W → her face, Q/E → her sides), and the aim slides from her
## live face to her vulva as S grows. W is where the kiss lives.
func _tick_authored(kiss: Variant, look: Vector3) -> void:
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	var scale := _missionary_body_scale()
	var start := _shot_position("start", scale)
	if not start.is_finite():
		return
	var face: Vector3 = runtime.call("missionary_face_point")
	if not face.is_finite():
		face = _missionary_head_transform().origin
	var vulva: Vector3 = runtime.call("missionary_vulva_point")
	if not vulva.is_finite():
		vulva = face
	var lean_forward: float = float(runtime.call("shot_lean_forward"))
	var lean_side := float(runtime.get("_lean_view_side"))
	var lean_scale: float = float(runtime.call("_lean_size_scale"))
	var pos := start
	var aim := face
	var forward := clampf(lean_forward, -1.0, 1.0)
	if forward < 0.0:
		var back := _shot_position("back", scale)
		if back.is_finite():
			pos += (back - start) * (-forward)
			aim = face.lerp(vulva, -forward)
	elif forward > 0.0:
		var front := _shot_position("front", scale)
		if front.is_finite():
			pos += (front - start) * forward
	var side := clampf(lean_side, -1.0, 1.0)
	if absf(side) > 0.0001:
		var beside := _shot_position("left" if side < 0.0 else "right", scale)
		if beside.is_finite():
			pos += (beside - start) * absf(side)
	var offsets := _shot_offsets()
	if offsets.length_squared() > 0.000001:
		pos += -_bed_back_direction() * offsets.x * scale \
			+ Vector3.UP * offsets.y * scale + _bed_side_direction() * offsets.z * scale
	var direction := aim - pos
	if direction.length_squared() < 0.000001:
		return
	var dir := direction.normalized()
	# `looking_at` needs a pole that is not parallel to the view. The full S shot looks almost
	# straight down at her pelvis, and with world up as the pole the basis is degenerate there and
	# snaps 180°. Hand the roll reference over to the mattress line as the view steepens.
	var steep := smoothstep(0.55, 0.95, absf(dir.dot(Vector3.UP)))
	var pole := Vector3.UP.lerp(_bed_head_direction(), steep)
	if pole.length_squared() < 0.0001:
		pole = Vector3.UP
	var basis := Basis.looking_at(dir, pole.normalized())
	var view_basis := basis
	var at := pos
	if SETTINGS.third_person.get_bool():
		# Third-person views: the lean tilts the eye, the speed-driven surge travels along the
		# mattress toward her head and a side lean travels with it. This is what makes the shot
		# drift off the authored trajectory and look around the joined bodies.
		var lean := Basis.from_euler(Vector3(
			-deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(lean_forward) * lean_scale,
			-deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG) * lean_side * lean_scale,
			(-deg_to_rad(MOTION.LEAN_SIDE_ROLL_DEG) * lean_side
				+ deg_to_rad(MOTION.LEAN_ROLL_DEG) * lean_forward) * lean_scale))
		view_basis = basis * lean
		at = pos + Vector3.UP * float(runtime.get("_bob"))
		at += _bed_head_direction() \
			* (float(runtime.get("_lean")) + _missionary_side_lean_forward())
		at += view_basis.x * kiss.lateral_offset(lean_scale)
		at.y -= kiss.lean_drop() * kiss.lean()
	if absf(look.x) > 0.00001 or absf(look.y) > 0.00001:
		# Debug free look: turn this shot where it stands. The act owns `controls_locked`, so the
		# stock player look is dead, and the player camera is wherever the game left his rig.
		view_basis = Basis(Vector3.UP, look.y) * view_basis * Basis(Vector3.RIGHT, look.x)
	# The kiss leans the eye in toward the aim, but never closer than 0.30 m to it.
	if kiss.lean() > 0.0:
		var reach: float = (aim - at).length()
		at -= view_basis.z * minf(kiss.lean_distance(), maxf(0.0, reach - 0.30))
	var top := _bed_surface_top()
	if is_finite(top):
		at.y = maxf(at.y, top + 0.10 * scale)
	_missionary_view.global_position = at
	_missionary_view.global_basis = view_basis
	if (absf(look.x) > 0.00001 or absf(look.y) > 0.00001) \
			and Time.get_ticks_msec() >= _free_look_log_at:
		_free_look_log_at = Time.get_ticks_msec() + 2000
		_log("free look base=%s rotation=%s" % [str(at), str(look)])
	runtime.set("_camera_basis_ready", true)


## The shot's live offsets (their own settings).
func _shot_offsets() -> Vector3:
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	if not cfg is Dictionary:
		return Vector3.ZERO
	return Vector3(
		float((cfg as Dictionary).get("shot_forward", 0.0)),
		float((cfg as Dictionary).get("shot_height", 0.0)),
		float((cfg as Dictionary).get("shot_side", 0.0)))


## One end of the shot in world space: the lab's bed-relative camera position when the asset
## carries one for this lean, otherwise a fixed point (never her live body).
## One end of the authored shot in world space. A shot that is not authored falls back to a fixed
## bed-relative point, never to her live body: the eye then only ever moves between fixed positions,
## and the log names what is still missing.
func _shot_position(id: String, scale: float) -> Vector3:
	var asset: Variant = runtime.call("authored_pose_asset") if is_instance_valid(runtime) else null
	var frame: Variant = _bed_frame()
	if asset != null and frame is Transform3D and bool(asset.call("has_shot", id)):
		var shot: Transform3D = (asset.get("shots") as Dictionary)[id]
		shot.origin *= scale
		return (frame as Transform3D) * shot.origin
	var start := _fallback_start(asset, frame, scale)
	if id == "start" or not start.is_finite():
		return start
	if not _missing_shots_logged.has(id):
		_missing_shots_logged[id] = true
		_log("missionary camera: shot '%s' is not authored; using the fixed bed-relative fallback" % id)
	var back := _bed_back_direction()
	var side := _bed_side_direction()
	match id:
		"back":
			return start + back * -0.45 * scale + Vector3.DOWN * 0.18 * scale
		"front":
			return start - back * 1.60 * scale + Vector3.DOWN * 0.10 * scale
		"left":
			return start - side * 0.60 * scale
		"right":
			return start + side * 0.60 * scale
	return start


## The neutral end when the asset has none: a fixed point over the mattress, behind her rump.
func _fallback_start(_asset: Variant, frame: Variant, scale: float) -> Vector3:
	if frame is Transform3D:
		return (frame as Transform3D) * Vector3(0.0, 0.62 * scale, -0.85 * scale)
	return Vector3.INF


func _bed_frame() -> Variant:
	if is_instance_valid(runtime):
		var frame: Variant = runtime.get("_bed_pose_frame")
		if frame is Transform3D:
			return frame
	return null


## Horizontal directions of the pose frame: her head, her rump, her side.
func _bed_head_direction() -> Vector3:
	var frame: Variant = _bed_frame()
	if frame is Transform3D:
		var dir: Vector3 = (frame as Transform3D).basis.z
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			return dir.normalized()
	return -_bed_back_direction()


func _bed_back_direction() -> Vector3:
	var frame: Variant = _bed_frame()
	if frame is Transform3D:
		var dir: Vector3 = -((frame as Transform3D).basis.z)
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			return dir.normalized()
	var back: Vector3 = pony.global_basis.z if is_instance_valid(pony) else Vector3.BACK
	back.y = 0.0
	return back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK


func _bed_side_direction() -> Vector3:
	var frame: Variant = _bed_frame()
	if frame is Transform3D:
		var dir: Vector3 = (frame as Transform3D).basis.x
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			return dir.normalized()
	var side: Vector3 = pony.global_basis.x if is_instance_valid(pony) else Vector3.RIGHT
	side.y = 0.0
	return side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT


func _missionary_side_lean_forward() -> float:
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	var amount := float((cfg as Dictionary).get("side_lean", 0.0)) if cfg is Dictionary else 0.0
	return amount * absf(float(runtime.get("_lean_view_side"))) \
		* float(runtime.call("_lean_size_scale"))


func _missionary_body_scale() -> float:
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return clampf(float(pony.get("body_scale")), 0.8, 1.6)
	return 1.0


func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return INF
	var fallback: float = float(bed.get_meta("mattress_top", 0.6)) + float(bed.global_position.y)
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


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


## The missionary head aim uses the camera as Anon's face. Keep a minimum distance so the camera
## cannot sit inside her head and produce near-zero direction flips.
func _missionary_head_look_point(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	var kiss: Variant = runtime.call("_kiss_controller")
	var point := view.global_position
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


func _make_missionary_view() -> void:
	if bool(runtime.get("_player_pony")) or not is_instance_valid(pony):
		return
	if is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view")):
		return
	_missionary_prev_camera = runtime.get_viewport().get_camera_3d() \
		if runtime.get_viewport() != null else null
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
		_log("missionary view restore fov=%.1f near=%.3f far=%.0f" % [
			_missionary_prev_camera.fov, _missionary_prev_camera.near,
			_missionary_prev_camera.far])
	_missionary_prev_camera = null
	if is_instance_valid(main) and is_instance_valid(main.player):
		var source: Camera3D = main.camera() if is_instance_valid(main) else null
		if _missionary_player_rot_saved and is_instance_valid(source):
			source.rotation = _missionary_player_rotation
	_missionary_player_rot_saved = false


## Remember the exact scene at missionary start so ending early can revert to it.
func _snapshot_missionary_start() -> void:
	_missionary_start_camera = runtime.get_viewport().get_camera_3d() \
		if runtime.get_viewport() != null else null
	if is_instance_valid(_missionary_start_camera):
		_missionary_start_camera_transform = _missionary_start_camera.global_transform
	if is_instance_valid(main) and is_instance_valid(main.player):
		_missionary_start_player_transform = main.player.global_transform
	if is_instance_valid(pony):
		_missionary_start_pony_transform = pony.global_transform
		_missionary_start_pony_posture = str(pony.call("posture_status").get("requested", ""))
		_missionary_start_saved = true


## Change the player's own eye height for the act instead of writing camera.position.y.
## Park the game's desktop presentation, which would otherwise show and drive his body from the
## player rig. The act's own body (`missionary_anon.gd`) is placed and posed over it after this.
func _hide_anon_avatar_for_missionary() -> void:
	if str(runtime.get("pose_id")) != "missionary" or not is_instance_valid(main) \
			or not is_instance_valid(main.player):
		return
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


func _restore_anon_avatar() -> void:
	if is_instance_valid(_desktop_presentation) and _desktop_presentation_enabled:
		_desktop_presentation.call("set_enabled", true)
	_desktop_presentation = null
	_desktop_presentation_enabled = true


## Put the player, the pony and the camera back exactly as the act found them. The act never rejoins
## a bed or a cuddle: both stand, and the caller stands her.
func _restore_scene() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	if not _missionary_start_saved:
		return
	# Player/pony first, camera last: setting the player yaw rotates a child camera, so the snapshot
	# camera transform must be applied after the rig is back in place.
	main.player.global_transform = _missionary_start_player_transform
	pony.global_transform = _missionary_start_pony_transform
	pony.reset_physics_interpolation()
	if is_instance_valid(_missionary_start_camera):
		_missionary_start_camera.global_transform = _missionary_start_camera_transform
		_missionary_start_camera.make_current()
	_log("missionary restore: scene restored camera=%s player=%s pony=%s" % [
		str(_missionary_start_camera_transform.origin), str(_missionary_start_player_transform.origin),
		str(_missionary_start_pony_transform.origin)])


## One line at act start: the authored shot ends and the live offsets.
func _log_shot_setup() -> void:
	if not is_instance_valid(main) or not bool(main.get("debug_logs")):
		return
	var scale := _missionary_body_scale()
	var asset: Variant = runtime.call("authored_pose_asset") if is_instance_valid(runtime) else null
	var source := "derived"
	if asset != null and bool(asset.get("has_shots")):
		source = "asset"
	var parts: Array[String] = []
	for id: String in SHOT_IDS:
		parts.append("%s=%s" % [id, str(_shot_position(id, scale))])
	_log("missionary camera shots=%s %s offsets=%s" % [
		source, " ".join(parts), str(_shot_offsets())])


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
