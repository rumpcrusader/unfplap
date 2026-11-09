extends RefCounted
## Missionary framing and the act avatar hiding. There is one shot: the **authored** one. The eye
## blends between the five camera transforms (position and direction) authored in the pose lab,
## selected by the lean; a pure axis lean meets the saved transform exactly. See ROTATION.md.
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
## In Anon eyes a kiss leans the eye in toward her face, but never closer than this to the face
## point: her muzzle extends past it, and the old 0.30 m floor put the eye inside the muzzle. The
## authored shot does not move for a kiss; its front transform is the kiss framing.
const KISS_CLEARANCE_M := 0.45

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
var _desktop_presentation_processing := true
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


## Re-read the scene once the act is fully posed. `prepare()` snapshots while Anon is still standing
## up from the bed, so the eye height it catches is the old reclined one; the pose settle is when his
## eye height and the camera have finished moving, and nothing else changes after it.
func resnapshot() -> void:
	_sync()
	if not is_instance_valid(main) or not is_instance_valid(main.player) \
			or not is_instance_valid(pony):
		return
	# Only the *game* camera's transform is refreshed. `_missionary_start_camera` stays the game camera
	# captured by `prepare()`; asking the viewport now would return the act's own view, which is freed
	# at the end.
	_missionary_start_player_transform = main.player.global_transform
	if is_instance_valid(main.camera()):
		_missionary_start_camera = main.camera()
		_missionary_start_camera_transform = main.camera().global_transform
	_missionary_start_pony_transform = pony.global_transform
	_missionary_start_pony_posture = str(pony.call("posture_status").get("requested", ""))
	_missionary_start_saved = true


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
	if str(SETTINGS.camera_mode.get_value()) == "eye":
		_tick_eye(runtime.call("_kiss_controller"), look)
		return
	_tick_authored(runtime.call("_kiss_controller"), look)


## His own view: the camera is his posed head, so the lean (which bends his chest and neck) and the
## authored body are what move it. The kiss still leans the eye in towards the aim.
func _tick_eye(kiss: Variant, look: Vector3) -> void:
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	var body: Variant = runtime.call("missionary_anon_body") if is_instance_valid(runtime) else null
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
	at += Vector3.UP * float(runtime.get("_bob"))
	at -= basis.z * float(runtime.get("_lean"))
	var aim: Vector3 = runtime.call("missionary_face_point")
	if aim.is_finite():
		at += basis.x * kiss.lateral_offset(float(runtime.call("_lean_size_scale")))
		at.y -= kiss.lean_drop() * kiss.lean()
		if kiss.lean() > 0.0:
			var reach := (aim - at).length()
			at -= basis.z * minf(kiss.lean_distance(),
				maxf(0.0, reach - KISS_CLEARANCE_M * _missionary_body_scale()))
	at = _clear_live_head(at)
	_missionary_view.global_position = at
	_missionary_view.global_basis = basis
	runtime.set("_camera_basis_ready", true)
	if (absf(look.x) > 0.00001 or absf(look.y) > 0.00001) \
			and Time.get_ticks_msec() >= _free_look_log_at:
		_free_look_log_at = Time.get_ticks_msec() + 2000
		_log("free look eye=%s rotation=%s" % [str(at), str(look)])


## The authored shot. The eye is a weighted blend of the five authored camera transforms: the
## neutral start plus the forward/back shot and the side shot selected by the lean. At a pure axis
## extreme (S, W, Q or E) the weight is exactly one, so the eye meets the pose lab's camera position
## **and direction**; everything between is interpolated. See ROTATION.md.
func _tick_authored(kiss: Variant, look: Vector3) -> void:
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	var scale := _missionary_body_scale()
	var forward := clampf(float(runtime.call("shot_lean_forward")), -1.0, 1.0)
	var side := clampf(float(runtime.get("_lean_view_side")), -1.0, 1.0)
	var tf := absf(forward)
	var ts := absf(side)
	var total := maxf(1.0, tf + ts)
	var entries: Array = []
	var start_weight := maxf(0.0, 1.0 - tf - ts) / total
	if start_weight > 0.0001:
		entries.append([_shot_transform("start", scale), start_weight])
	if tf > 0.0001:
		entries.append([_shot_transform("front" if forward > 0.0 else "back", scale), tf / total])
	if ts > 0.0001:
		# The asset's `left` shot is on Anon's screen right and vice versa (the lab names them from
		# her side), so Q reads `right` and E reads `left` to make the keys match the screen.
		entries.append([_shot_transform("right" if side < 0.0 else "left", scale), ts / total])
	var shot := _blend_shots(entries)
	if not shot.is_finite():
		return
	var at := shot.origin
	var view_basis := shot.basis.orthonormalized()
	# The speed-driven surge/bob from standing: zero at rest, so the eye is exactly the authored
	# transform; during a stroke the view rocks with it.
	at += Vector3.UP * float(runtime.get("_bob"))
	at -= view_basis.z * float(runtime.get("_lean"))
	if SETTINGS.third_person.get_bool():
		# Third-person views (debug) is the only deviation from the authored transform: the lean
		# tilts the eye, the speed-driven surge travels along the mattress and a side lean travels
		# with it. Off, the eye is exactly the authored shot at every extreme.
		var lean_scale: float = float(runtime.call("_lean_size_scale"))
		var lean := Basis.from_euler(Vector3(
			-deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(forward) * lean_scale,
			-deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG) * side * lean_scale,
			(-deg_to_rad(MOTION.LEAN_SIDE_ROLL_DEG) * side
				+ deg_to_rad(MOTION.LEAN_ROLL_DEG) * forward) * lean_scale))
		view_basis = view_basis * lean
		at += view_basis.x * kiss.lateral_offset(lean_scale)
		at.y -= kiss.lean_drop() * kiss.lean()
	if absf(look.x) > 0.00001 or absf(look.y) > 0.00001:
		# Debug free look: turn this shot where it stands.
		view_basis = Basis(Vector3.UP, look.y) * view_basis * Basis(Vector3.RIGHT, look.x)
	at = _clear_live_head(at)
	_missionary_view.global_position = at
	_missionary_view.global_basis = view_basis
	runtime.set("_camera_basis_ready", true)
	if (absf(look.x) > 0.00001 or absf(look.y) > 0.00001) \
			and Time.get_ticks_msec() >= _free_look_log_at:
		_free_look_log_at = Time.get_ticks_msec() + 2000
		_log("free look shot=%s rotation=%s" % [str(at), str(look)])


## The authored camera transform at one lean extreme: position and direction exactly as the pose
## lab saved them. A missing shot keeps the fixed bed-relative fallback, aimed at her face.
func _shot_transform(id: String, scale: float) -> Transform3D:
	var asset: Variant = runtime.call("authored_pose_asset") if is_instance_valid(runtime) else null
	var frame: Variant = _bed_frame()
	if asset != null and frame is Transform3D and bool(asset.call("has_shot", id)):
		var shot: Transform3D = (asset.get("shots") as Dictionary)[id]
		shot.origin *= scale
		return (frame as Transform3D) * shot
	var pos := _shot_position(id, scale)
	var face: Vector3 = runtime.call("missionary_face_point")
	if not face.is_finite():
		face = _missionary_head_transform().origin
	return Transform3D(_aimed_basis(pos, face), pos)


## A camera basis that looks from `at` at `aim`, with the mattress line as the roll reference when
## the view steepens: a straight-down view has no stable world-up roll.
func _aimed_basis(at: Vector3, aim: Vector3) -> Basis:
	var direction := aim - at
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return Basis.IDENTITY
	var dir := direction.normalized()
	var steep := smoothstep(0.55, 0.95, absf(dir.dot(Vector3.UP)))
	var pole := Vector3.UP.lerp(_bed_head_direction(), steep)
	if pole.length_squared() < 0.0001:
		pole = Vector3.UP
	return Basis.looking_at(dir, pole.normalized())


## Weighted position and quaternion average. A pure axis lean has a single weight of one, so the
## result is the authored transform itself, not an approximation.
func _blend_shots(entries: Array) -> Transform3D:
	if entries.is_empty():
		return Transform3D.IDENTITY
	var total := 0.0
	var origin := Vector3.ZERO
	var reference := Quaternion.IDENTITY
	var have_reference := false
	var qsum := Quaternion(0.0, 0.0, 0.0, 0.0)
	for entry: Array in entries:
		var shot: Transform3D = entry[0]
		var weight := float(entry[1])
		if weight <= 0.0 or not shot.is_finite():
			continue
		total += weight
		origin += shot.origin * weight
		var q := shot.basis.orthonormalized().get_rotation_quaternion()
		if not have_reference:
			reference = q
			have_reference = true
		if q.dot(reference) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		qsum = Quaternion(qsum.x + q.x * weight, qsum.y + q.y * weight,
			qsum.z + q.z * weight, qsum.w + q.w * weight)
	if total <= 0.0001 or qsum.length_squared() < 0.000001:
		return Transform3D.IDENTITY
	return Transform3D(Basis(qsum.normalized()), origin / total)


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


func _missionary_body_scale() -> float:
	# The real body size, the same number the pose placement and the anatomy use. The body scales
	# with the rig, so the camera, the head clearance and the kiss distance must too; a floor keeps
	# a degenerate rig from dividing by zero.
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return maxf(float(pony.get("body_scale")), 0.1)
	return 1.0


func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return INF
	var fallback: float = float(bed.get_meta("mattress_top", 0.6)) + float(bed.global_position.y)
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


## Her live head as a skull sphere plus a muzzle capsule. The camera is Anon's eye, so pushing it
## out of those volumes is what keeps a close lean from entering her head no matter which way she
## turns or pulls her head; a point target cannot do that because the surface moves under it.
func _clear_live_head(at: Vector3) -> Vector3:
	var clearance := SETTINGS.head_clearance_mm.get_num() / 1000.0
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
			# `set_enabled(false)` only hides his body; `advance()` keeps running and re-hides it
			# every frame. Park the presentation's process too, so the act owns the avatar wholly.
			_desktop_presentation_processing = presentation.is_processing()
			presentation.set_process(false)
	if is_instance_valid(_desktop_presentation) and _desktop_presentation_enabled \
			and bool(_desktop_presentation.get("_enabled")) == true:
		_desktop_presentation.call("set_enabled", false)


func _restore_anon_avatar() -> void:
	if is_instance_valid(_desktop_presentation):
		_desktop_presentation.set_process(_desktop_presentation_processing)
		if _desktop_presentation_enabled:
			_desktop_presentation.call("set_enabled", true)
	_desktop_presentation = null
	_desktop_presentation_enabled = true
	_desktop_presentation_processing = true


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


## One line at act start: the authored shot ends.
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
	_log("missionary camera shots=%s %s" % [source, " ".join(parts)])


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
