extends RefCounted
## Standing look, glance, facing lock and camera offsets. The runtime owns the act state and
## the camera reference; this controller owns the look cone and framing state.

const MOTION := preload("res://mods/unfplap/act_motion.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const STANDING_HEAD_NECK_HEIGHT_M := 1.0
const CANON_STANDING_CAMERA_DROP_M := 0.10
const MOUNTING_STANDING_CAMERA_LIFT_M := 0.10
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
const GLANCE_MIN_INTERVAL := 5.0
const GLANCE_MAX_INTERVAL := 9.0
const GLANCE_HOLD := 1.8
const GLANCE_YAW := 3.0
const GLANCE_BACK_PITCH := 1.2
const GLANCE_BACK_CHANCE := 0.5
const CAM_SPEED_SMOOTH_S := 0.06
const STATE_IDLE := 0
const STATE_RESTORE := 5

var runtime: Node
var main: Variant
var pony: Variant
var camera: Camera3D
var _presentation_cfg: Dictionary = {}
var _pose_cfg: Dictionary = {}

var _applied_bob := 0.0
var _applied_lean := 0.0
var _applied_side := 0.0
var _standing_base_look := Vector3.INF
var _standing_base_local := Vector3.ZERO
var _standing_base_saved := false
var _depth_prev := 0.0
var _depth_speed := 0.0
var _facing_basis := Basis.IDENTITY
var _has_facing := false
## integration: the anatomy oral turn owns the facing while it is active.
var _facing_override := Basis.IDENTITY
var _facing_override_on := false
var _glance_wait := 0.0
var _glance_left := 0.0
var _glance_back := false
var _glance_sign := 1.0
var _glance_sign_set := false
var _glance_head_back := 0.0

func _depth_speed_tick(delta: float) -> void:
	var raw_speed := (float(runtime.get("depth")) - _depth_prev) / maxf(delta, 0.0001)
	_depth_prev = float(runtime.get("depth"))
	var alpha := 1.0 - exp(-delta / maxf(CAM_SPEED_SMOOTH_S, 0.001))
	_depth_speed = lerpf(_depth_speed, raw_speed, alpha)

## Standing yaw/pitch from the lean vector, applied to the player camera on top of the base aim.

func _apply_standing_lean_look() -> void:
	var kiss: Variant = runtime.call("_kiss_controller")
	if not bool(runtime.get("_free_camera_active")) or str(runtime.get("pose_id")) != CATALOG.STANDING or bool(runtime.get("_player_pony")) or bool(runtime.call("_headset_view")):
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var lean_scale := float(runtime.call("_standing_lean_scale"))
	var yaw := float(runtime.get("_look_yaw")) + deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG) * float(runtime.get("_lean_view_side")) * lean_scale
	# Turn a little further toward her while kissing, over the shoulder.
	yaw += deg_to_rad(kiss.camera_yaw_deg()) * kiss.lean() * kiss.side()
	var pitch := clampf(
		float(runtime.get("_look_pitch")) - deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(float(runtime.get("_lean_view_forward"))) * lean_scale,
		-1.5, 1.5)
	body.rotation.y = yaw
	if body.get("_pitch") != null:
		body.set("_pitch", pitch)
	if body.get("form_driver") == null:
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			view.rotation.x = pitch

## Free camera owns the movement keys completely: Anon cannot walk, shift on the bed, jump or
## start couch actions while the shot is active. The previous value is restored at act end.

func _standing_neck_point() -> Vector3:
	var neck: Vector3 = runtime.call("_neck_midpoint")
	if neck.is_finite():
		return neck
	if not is_instance_valid(pony):
		return Vector3.INF
	var scale := 1.0
	if pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	return pony.global_position + Vector3.UP * (STANDING_HEAD_NECK_HEIGHT_M * scale)

## Middle of the neck chain: midpoint of pony_neck1 and pony_neck2 world origins.

func _apply_standing_base_look() -> void:
	if bool(runtime.get("_player_pony")) or bool(runtime.call("_headset_view")):
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var view: Camera3D = main.camera()
	if not is_instance_valid(view):
		return
	var target := _standing_base_look
	if not target.is_finite():
		target = _standing_neck_point()
	if not target.is_finite():
		return
	var direction := target - view.global_position
	var flat := Vector2(direction.x, direction.z).length()
	if flat < 0.001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := clampf(atan2(direction.y, flat), -1.0, 1.0)
	body.rotation.y = yaw
	if body.get("_pitch") != null:
		body.set("_pitch", pitch)
	if body.get("form_driver") == null:
		view.rotation.x = pitch
	runtime.set("_look_yaw", yaw)
	runtime.set("_look_pitch", pitch)
	runtime.set("_camera_basis_ready", true)
	_standing_base_look = target
	if str(runtime.get("pose_id")) == CATALOG.STANDING and _has_facing \
			and not _facing_override_on:
		_facing_basis = Basis(Vector3.UP, yaw)
	_apply_standing_lean_look()

func _set_camera_offsets(vertical: float, forward: float, side: float = 0.0) -> void:
	if not is_instance_valid(camera):
		return
	var seated := is_instance_valid(main) and is_instance_valid(main.player) and main.player.get("seat") != null
	var eye_height := _standing_eye_height()
	if _standing_base_saved and not camera.top_level and not seated:
		camera.position = Vector3(
			_standing_base_local.x + side,
			eye_height + vertical,
			_standing_base_local.z - forward)
		_applied_bob = vertical
		_applied_lean = forward
		_applied_side = side
		return
	var df := forward - _applied_lean
	var ds := side - _applied_side
	if camera.top_level or seated:
		var dy := vertical - _applied_bob
		if absf(dy) > 0.00001:
			camera.global_position += Vector3.UP * dy
		if absf(df) > 0.00001:
			camera.global_position -= camera.global_basis.z * df
		if absf(ds) > 0.00001:
			camera.global_position += camera.global_basis.x * ds
	else:
		camera.position.y = eye_height + vertical
		if absf(df) > 0.00001:
			camera.position.z -= df
		if absf(ds) > 0.00001:
			camera.position.x += ds
	_applied_bob = vertical
	_applied_lean = forward
	_applied_side = side

func _standing_eye_height() -> float:
	var height: float = float(runtime.call("_player_eye_height"))
	if runtime.call("_size_name") == "canon":
		height -= CANON_STANDING_CAMERA_DROP_M
	elif runtime.call("_size_name") == "mounting":
		height += MOUNTING_STANDING_CAMERA_LIFT_M
	return height

func _lock_body_facing() -> void:
	if not _has_facing or str(runtime.get("pose_id")) != CATALOG.STANDING or not is_instance_valid(pony):
		return
	if int(runtime.get("state")) in [STATE_IDLE, STATE_RESTORE]:
		return
	var t: Transform3D = pony.global_transform
	var scale := t.basis.get_scale()
	t.basis = (_facing_override if _facing_override_on else _facing_basis).scaled(scale)
	pony.global_transform = t
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		# stay() clears the route, but conversation facing still writes face_point and can make
		# her take a turn step. Clear both late in the tick so the act owns the body facing.
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)

func _glance_back_fade() -> float:
	return MOTION.glance_back_fade_for(float(_presentation_cfg.get("glance_back_speed", 1.0)))

## Every few seconds she turns her head back toward Anon, then forward again. The game's
## secondary gaze owns the turn; standing only adds the optional throw-back rotation (`head_back`),
## eased so it does not snap.

func _drive_glance(delta: float) -> void:
	var kiss: Variant = runtime.call("_kiss_controller")
	if not _has_facing or str(runtime.get("pose_id")) != CATALOG.STANDING or not is_instance_valid(pony):
		return
	# The base kiss owns the head and gaze while it runs or releases. Clear the shoulder reach's
	# forced over-the-shoulder look so the two head poses do not fight and clip.
	if kiss.standing_active() or kiss.base_active():
		if is_instance_valid(runtime.get("_pose")):
			_glance_head_back = move_toward(_glance_head_back, 0.0, delta / _glance_back_fade())
			runtime.get("_pose").set("head_back", _glance_head_back)
		runtime.set("_forced_glance", "")
		_glance_left = 0.0
		_glance_back = false
		return
	# A full forward W lean (no side lean, no kiss) makes her throw her head fully back and
	# look up at Anon instead of waiting for a random glance.
	var lean_up: bool = float(runtime.get("_lean_forward")) >= 0.95 and absf(float(runtime.get("_lean_side"))) <= 0.2 and not kiss.standing_active()
	if is_instance_valid(runtime.get("_pose")):
		var back_target := 1.0 if (not str(runtime.get("_forced_glance")).is_empty() or lean_up \
			or (_glance_left > 0.0 and _glance_back)) else 0.0
		_glance_head_back = move_toward(_glance_head_back, back_target, delta / _glance_back_fade())
		runtime.get("_pose").set("head_back", _glance_head_back)
	var secondary: Variant = pony.get("secondary")
	if not str(runtime.get("_forced_glance")).is_empty():
		_glance_sign_set = true
		_glance_sign = 1.0 if str(runtime.get("_forced_glance")) == "L" else -1.0
		_glance_back = true
		if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
			secondary.call("look_toward", _glance_angles(), 0.4)
		_aim_eyes_at_player()
		return
	if lean_up:
		if not _glance_sign_set:
			_glance_sign = 1.0
			_glance_sign_set = true
		_glance_back = true
		if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
			secondary.call("look_toward", _glance_angles(), 0.3)
			_aim_eyes_at_player()
		return
	if secondary == null or not is_instance_valid(secondary) or not secondary.has_method("look_toward"):
		return
	if _glance_left > 0.0:
		_glance_left -= delta
		secondary.call("look_toward", _glance_angles(), 0.4)
		_aim_eyes_at_player()
		if _glance_left <= 0.0:
			_glance_wait = randf_range(float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)), float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))
		return
	_glance_wait -= delta
	if _glance_wait <= 0.0:
		_glance_left = float(_pose_cfg.get("glance_hold", GLANCE_HOLD))
		_glance_back = randf() < float(_pose_cfg.get("glance_back_chance", GLANCE_BACK_CHANCE))
		_glance_sign_set = false
	secondary.call("look_toward", Vector3.ZERO, 0.4)

## Pupils/eyes follow Anon during a glance. The native eye modifier exposes `target_world` and
## `target_weight`; runtime physics priority runs after the pony, so this wins for the frame.

func _aim_eyes_at_player() -> void:
	if not is_instance_valid(pony):
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	var view: Camera3D = main.camera() if is_instance_valid(main) else null
	var target: Vector3 = view.global_position if is_instance_valid(view) else pony.global_position
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)

func _glance_angles() -> Vector3:
	var head: Vector3 = pony.global_position + Vector3.UP
	if pony.has_method("listen_point"):
		head = pony.call("listen_point")
	var target: Vector3 = head
	if is_instance_valid(main) and is_instance_valid(main.player):
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			target = view.global_position
	var local: Vector3 = pony.global_basis.inverse() * (target - head)
	var raw := atan2(-local.x, -local.z)
	if not _glance_sign_set:
		# Pick one shoulder for this glance so a small movement behind her cannot flip it.
		_glance_sign = signf(raw) if absf(raw) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
		_glance_sign_set = true
	var yaw: float = _glance_sign * absf(raw)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	if _glance_back:
		var back_pitch := float(_pose_cfg.get("glance_back_pitch", GLANCE_BACK_PITCH)) * 1.2
		return Vector3(clampf(pitch + back_pitch, -0.25, 1.44),
			clampf(yaw, -MOTION.GLANCE_BACK_YAW, MOTION.GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg.get("glance_yaw", GLANCE_YAW))
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)

## Free look, but inside a 45-degree cone around the direction the act began in. Movement stays
## held by kiss_hold; this only limits where the camera can turn.

func _clamp_look() -> void:
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		# Missionary uses the mod-owned view; the player's body look is left alone.
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var form: Variant = body.get("form_driver")
	# AnonPony lying/sitting has her own body-yaw limit; never widen it.
	if form != null and form is Node and (form as Node).has_method("clamp_view"):
		form.call("clamp_view")
	var yaw_delta := angle_difference(float(runtime.get("_look_yaw")), float(body.rotation.y))
	if absf(yaw_delta) > LOOK_YAW_LIMIT:
		body.rotation.y = float(runtime.get("_look_yaw")) + clampf(yaw_delta, -LOOK_YAW_LIMIT, LOOK_YAW_LIMIT)
	var headset: Variant = body.get("headset_view")
	if headset is bool and headset:
		return
	var pitch_value: Variant = body.get("_pitch")
	if pitch_value == null:
		return
	var want := float(runtime.get("_look_pitch")) + clampf(float(pitch_value) - float(runtime.get("_look_pitch")), -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	if absf(float(pitch_value) - want) > 0.00001:
		body.set("_pitch", want)
	var view: Camera3D = main.camera()
	if form == null and is_instance_valid(view):
		view.rotation.x = want

func _sync() -> void:
	main = runtime.get("main") if is_instance_valid(runtime) else null
	pony = runtime.get("pony") if is_instance_valid(runtime) else null
	camera = runtime.get("_camera") if is_instance_valid(runtime) else null
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var pose_cfg: Variant = runtime.get("_pose_cfg") if is_instance_valid(runtime) else null
	_pose_cfg = pose_cfg if pose_cfg is Dictionary else {}

func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node

func prepare() -> void:
	_sync()
	if is_instance_valid(camera):
		_standing_base_local = camera.position
		_standing_base_saved = true
		_standing_base_look = _standing_neck_point()
		_apply_standing_base_look()

func begin_facing(transform: Transform3D) -> void:
	_sync()
	_facing_basis = transform.basis
	_has_facing = true
	_facing_override_on = false
	_glance_left = 0.0
	_glance_back = false
	_glance_sign_set = false
	_glance_head_back = 0.0
	_glance_wait = randf_range(
		float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)),
		float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))


## integration: the oral turn owns the facing while it is active. Amount 0 clears it.
func set_facing_override(basis: Basis, amount: float) -> void:
	if amount <= 0.001:
		_facing_override_on = false
		_facing_override = Basis.IDENTITY
		return
	_facing_override_on = true
	_facing_override = basis.orthonormalized()

func reset() -> void:
	_applied_bob = 0.0
	_applied_lean = 0.0
	_applied_side = 0.0
	_standing_base_saved = false
	_standing_base_look = Vector3.INF
	_standing_base_local = Vector3.ZERO
	_depth_prev = 0.0
	_depth_speed = 0.0
	_has_facing = false
	_facing_override_on = false
	_facing_override = Basis.IDENTITY
	_glance_wait = 0.0
	_glance_left = 0.0
	_glance_back = false
	_glance_sign_set = false
	_glance_head_back = 0.0

func speed() -> float:
	return _depth_speed

func reset_depth() -> void:
	_depth_prev = 0.0
	_depth_speed = 0.0

func reset_facing() -> void:
	_has_facing = false
	_facing_override_on = false
	_facing_override = Basis.IDENTITY
	_glance_left = 0.0
	_glance_back = false

func tick_depth(delta: float) -> void:
	_depth_speed_tick(delta)

func apply_lean_look() -> void:
	_apply_standing_lean_look()

func lock_facing() -> void:
	_lock_body_facing()

func drive_glance(delta: float) -> void:
	_drive_glance(delta)

func clamp_look() -> void:
	_clamp_look()

func hold_glance() -> void:
	_glance_wait = 0.0

func clear_glance() -> void:
	_glance_left = 0.0
	_glance_back = false
	_glance_wait = randf_range(
		float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)),
		float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))

func tick() -> void:
	_sync()
	var kiss: Variant = runtime.call("_kiss_controller")

	var lean_scale := float(runtime.call("_standing_lean_scale"))
	_set_camera_offsets(float(runtime.get("_bob")) - kiss.lean_drop() * kiss.lean() - float(runtime.call("_anon_torso_drop")),
		float(runtime.get("_lean")) - float(runtime.get("_back")) + MOTION.lean_distance(
			float(runtime.get("_lean_view_forward")), lean_scale,
			float(runtime.call("lean_back_distance")))
		+ kiss.lean_distance() + float(runtime.call("_anon_torso_forward")), kiss.lateral_offset(lean_scale))
	if str(runtime.get("pose_id")) == CATALOG.STANDING and bool(runtime.get("_free_camera_active")) and is_instance_valid(camera):
		camera.rotation.z = (-deg_to_rad(MOTION.LEAN_SIDE_ROLL_DEG) * float(runtime.get("_lean_view_side")) \
			+ deg_to_rad(MOTION.LEAN_ROLL_DEG) * float(runtime.get("_lean_view_forward"))) * lean_scale
		camera.rotation.x = clampf(
			float(runtime.get("_look_pitch")) - deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(float(runtime.get("_lean_view_forward"))) * lean_scale,
			-1.5, 1.5)

func restore() -> void:
	_sync()
	if is_instance_valid(camera):
		if _standing_base_saved:
			camera.position = Vector3(_standing_base_local.x, float(runtime.call("_player_eye_height")), _standing_base_local.z)
		elif camera.top_level:
			if absf(_applied_bob) > 0.00001:
				camera.global_position -= Vector3.UP * _applied_bob
			if absf(_applied_lean) > 0.00001:
				camera.global_position += camera.global_basis.z * _applied_lean
			if absf(_applied_side) > 0.00001:
				camera.global_position -= camera.global_basis.x * _applied_side
		else:
			camera.position.y = float(runtime.call("_player_eye_height"))
			camera.position.z += _applied_lean
			camera.position.x -= _applied_side
	_applied_bob = 0.0
	_applied_lean = 0.0
	_applied_side = 0.0
	_standing_base_saved = false
	_depth_prev = 0.0
	_depth_speed = 0.0

func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
