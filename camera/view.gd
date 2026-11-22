extends RefCounted
## Live camera: standing side, bed-act sightline.
## The frame owns the player; this module owns the view and its live offsets.
## Contract: `docs/camera.md`, `docs/act_facts.md`.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const CANON_STANDING_CAMERA_DROP_M := 0.10
const MOUNTING_STANDING_CAMERA_LIFT_M := 0.10
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
const CAM_SPEED_SMOOTH_S := 0.06
## The closest an Anon-eyes kiss lean-in may put the eye to her face point: her muzzle extends past
## it, and the view does not move for a kiss.
const KISS_CLEARANCE_M := 0.45
## The authored look path's five ends, in the order the blend weights index them.
const SHOT_IDS := ["start", "back", "front", "left", "right"]

const STATE_IDLE := ACT_STATE.State.IDLE
const STATE_RESTORE := ACT_STATE.State.RESTORE

var facts: ACT_FACTS = null
var pony: Node3D = null
var bed: Node3D = null
var camera: Camera3D
var _presentation_cfg: Dictionary = {}
var _pose_cfg: Dictionary = {}
## Re-read the pose config only on a settings-group or pose-id change, so the standing debug pair
## keeps the live values instead of snapping to the target every tick.
var _pose_cfg_group := ""
var _pose_cfg_key := ""

var _applied_bob := 0.0
var _applied_lean := 0.0
var _applied_side := 0.0
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

var _missionary_view: Camera3D
var _missionary_prev_camera: Camera3D
var _missionary_player_rotation := Vector3.ZERO
var _missionary_player_rot_saved := false
var _missionary_source_fov := 75.0
var _missionary_source_near := 0.05
var _missionary_source_far := 4000.0
var _missionary_source_cull := 0xFFFFFFFF
var _free_look_log_at := 0
## The authored shot bases are bed-local; cache them per asset and multiply by the live bed basis.
var _shot_asset_id := 0
var _shot_local: Array[Basis] = []
var _shot_present := PackedByteArray()
var _shot_weights := PackedFloat32Array()


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


## One physics frame of the live view. A bed act's view is written by the render pass instead, so
## it reads the pose of the frame it is drawn in.
func tick() -> void:
	_sync()
	if _pose_family() == "bed":
		return
	var kiss: Variant = facts.kiss_controller()
	if kiss == null:
		return
	var lean_scale := float(facts.standing_lean_scale)
	_set_camera_offsets(float(facts.bob) - kiss.lean_drop() * kiss.lean() - float(facts.anon_torso_drop),
		float(facts.lean) - float(facts.back) + MOTION.lean_distance(
			float(facts.lean_view_forward), lean_scale)
		+ kiss.lean_distance() + float(facts.anon_torso_forward)
		+ float(_presentation_cfg["camera_forward_m"]), kiss.lateral_offset(lean_scale))
	if bool(facts.free_camera_active) and is_instance_valid(camera):
		camera.rotation.z = (-deg_to_rad(MOTION.LEAN_SIDE_ROLL_DEG) * float(facts.lean_view_side) \
			+ deg_to_rad(MOTION.LEAN_ROLL_DEG) * float(facts.lean_view_forward)) * lean_scale
		camera.rotation.x = clampf(
			float(facts.look_pitch) - deg_to_rad(MOTION.LEAN_PITCH_DEG) * absf(float(facts.lean_view_forward)) * lean_scale
			+ deg_to_rad(float(_presentation_cfg["camera_pitch_deg"])),
			-1.5, 1.5)


## The render-time eye write: the act body's posed head for the position, the authored look path
## for the basis, after the pose write and before the draw.
func write_eye() -> void:
	_sync()
	if _pose_family() != "bed" or not is_instance_valid(pony):
		return
	var look := Vector3.ZERO
	if facts != null and bool(facts.free_look_active):
		var rotation: Variant = facts.call_value(facts.free_look_rotation, Vector3.ZERO)
		if rotation is Vector3:
			look = rotation
	_tick_eye(facts.kiss_controller(), look)


## Mount the act's own view once the scene is settled.
func mount() -> void:
	_sync()
	_make_missionary_view()


## Unmount the act's view and hand the game camera back.
func unmount() -> void:
	_free_missionary_view()


func view() -> Camera3D:
	return _missionary_view


## Put the player camera back where it stood; the act's live offsets are gone.
func restore() -> void:
	_sync()
	if is_instance_valid(camera):
		if _standing_base_saved:
			camera.position = Vector3(_standing_base_local.x, float(facts.player_eye_height),
				_standing_base_local.z)
		elif camera.top_level:
			if absf(_applied_bob) > 0.00001:
				camera.global_position -= Vector3.UP * _applied_bob
			if absf(_applied_lean) > 0.00001:
				camera.global_position += camera.global_basis.z * _applied_lean
			if absf(_applied_side) > 0.00001:
				camera.global_position -= camera.global_basis.x * _applied_side
		else:
			camera.position.y = float(facts.player_eye_height)
			camera.position.z += _applied_lean
			camera.position.x -= _applied_side
	_applied_bob = 0.0
	_applied_lean = 0.0
	_applied_side = 0.0
	_standing_base_saved = false
	_depth_prev = 0.0
	_depth_speed = 0.0


## The standing camera's own base state for a fresh act. The frame writes the base aim.
func prepare() -> void:
	_sync()
	if not is_instance_valid(camera):
		return
	_standing_base_local = camera.position
	_standing_base_saved = true
	if facts != null:
		facts.mark_camera_basis_ready()
		if _pose_family() == "standing" and _has_facing and not _facing_override_on:
			_facing_basis = Basis(Vector3.UP, float(facts.look_yaw))
		apply_lean_look()


## The act's base facing, from the frame's placement.
func begin_facing(transform: Transform3D) -> void:
	_sync()
	_facing_basis = transform.basis
	_has_facing = true
	_facing_override_on = false
	_glance_left = 0.0
	_glance_back = false
	_glance_sign_set = false
	_glance_head_back = 0.0
	# The standing placement starts before the pose session builds; arm the first wait when the
	# config is available on the first drive tick instead of reading an empty config here.
	_glance_wait = -1.0


## integration: the pose view owns the oral facing while its turn runs. Amount 0 clears it.
func set_facing_override(basis: Basis, amount: float) -> void:
	if amount <= 0.001:
		_facing_override_on = false
		_facing_override = Basis.IDENTITY
		return
	_facing_override_on = true
	_facing_override = basis.orthonormalized()


## Read the pose view's live facing each physics tick. The oral turn writes it every tick; a
## cleared view or amount 0 returns the normal facing lock.
func sync_view_facing() -> void:
	if facts == null:
		return
	var view: Variant = facts.pose_view
	if view == null:
		set_facing_override(Basis.IDENTITY, 0.0)
		return
	set_facing_override(view.facing, view.facing_amount)


func reset() -> void:
	_applied_bob = 0.0
	_applied_lean = 0.0
	_applied_side = 0.0
	_standing_base_saved = false
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
	sync_view_facing()
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
	_glance_wait = -1.0 if _pose_cfg.is_empty() else randf_range(
		float(_pose_cfg["glance_min"]),
		float(_pose_cfg["glance_max"]))


func _depth_speed_tick(delta: float) -> void:
	var raw_speed := (float(facts.depth) - _depth_prev) / maxf(delta, 0.0001)
	_depth_prev = float(facts.depth)
	var alpha := 1.0 - exp(-delta / maxf(CAM_SPEED_SMOOTH_S, 0.001))
	_depth_speed = lerpf(_depth_speed, raw_speed, alpha)


## Standing yaw/pitch from the lean vector, applied to the player camera on top of the base aim.
func _apply_standing_lean_look() -> void:
	var kiss: Variant = facts.kiss_controller()
	if not bool(facts.free_camera_active) or _pose_family() != "standing" \
			or bool(facts.player_pony) or bool(facts.headset_view):
		return
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player) or kiss == null:
		return
	var body: Node3D = WORLD.player
	var lean_scale := float(facts.standing_lean_scale)
	var yaw := float(facts.look_yaw) + deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG) \
		* float(facts.lean_view_side) * lean_scale
	# Turn a little further toward her while kissing, over the shoulder.
	yaw += deg_to_rad(kiss.camera_yaw_deg()) * kiss.lean() * kiss.side()
	var pitch := clampf(
		float(facts.look_pitch) - deg_to_rad(MOTION.LEAN_PITCH_DEG) \
			* absf(float(facts.lean_view_forward)) * lean_scale
		+ deg_to_rad(float(_presentation_cfg["camera_pitch_deg"])),
		-1.5, 1.5)
	body.rotation.y = yaw
	GAME.set_pitch(body, pitch)
	if GAME.form_of(body) == null:
		var view: Camera3D = WORLD.camera()
		if is_instance_valid(view):
			view.rotation.x = pitch


func _set_camera_offsets(vertical: float, forward: float, side: float = 0.0) -> void:
	if not is_instance_valid(camera):
		return
	var seated := GAME.seat_of(WORLD.player) != null
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
	var height := float(facts.player_eye_height)
	if str(facts.size_name) == "canon":
		height -= CANON_STANDING_CAMERA_DROP_M
	elif str(facts.size_name) == "mounting":
		height += MOUNTING_STANDING_CAMERA_LIFT_M
	return height


func _lock_body_facing() -> void:
	if not _has_facing or _pose_family() != "standing" or not is_instance_valid(pony):
		return
	if int(facts.state) in [STATE_IDLE, STATE_RESTORE]:
		return
	var t: Transform3D = pony.global_transform
	var scale := t.basis.get_scale()
	t.basis = (_facing_override if _facing_override_on else _facing_basis).scaled(scale)
	pony.global_transform = t
	# stay() clears the route, but conversation facing still writes face_point and can make
	# her take a turn step. Clear both late in the tick so the act owns the body facing.
	GAME.clear_facing(pony)


func _glance_back_fade() -> float:
	return MOTION.glance_back_fade_for(float(_presentation_cfg["glance_back_speed"]))


## Every few seconds she turns her head back toward Anon. The game's secondary gaze owns the turn;
## standing only adds the optional `head_back` throw-back, eased so it does not snap.
func _drive_glance(delta: float) -> void:
	var kiss: Variant = facts.kiss_controller()
	if not _has_facing or _pose_family() != "standing" or not is_instance_valid(pony):
		return
	if kiss == null:
		return
	# The base kiss owns the head and gaze while it runs or releases. Clear the shoulder reach's
	# forced over-the-shoulder look so the two head poses do not fight and clip.
	if kiss.standing_active() or kiss.base_active():
		if is_instance_valid(facts.pose) and facts.set_head_back.is_valid():
			_glance_head_back = move_toward(_glance_head_back, 0.0, delta / _glance_back_fade())
			facts.set_head_back.call(_glance_head_back)
		facts.write_forced_glance("")
		_glance_left = 0.0
		_glance_back = false
		return
	# A full forward W lean (no side lean, no kiss) makes her throw her head fully back and
	# look up at Anon instead of waiting for a random glance.
	var lean_up: bool = float(facts.lean_forward) >= 0.95 \
		and absf(float(facts.lean_side)) <= 0.2 and not kiss.standing_active()
	if is_instance_valid(facts.pose) and facts.set_head_back.is_valid():
		var back_target := 1.0 if (not str(facts.forced_glance).is_empty() or lean_up \
			or (_glance_left > 0.0 and _glance_back)) else 0.0
		_glance_head_back = move_toward(_glance_head_back, back_target, delta / _glance_back_fade())
		facts.set_head_back.call(_glance_head_back)
	# The forced, lean-up and random glances all read the pose config. The standing placement can
	# begin before the pose session builds, so wait for the config instead of indexing an empty one.
	if _pose_cfg.is_empty():
		return
	var secondary: Object = pony.get("secondary")
	if not str(facts.forced_glance).is_empty():
		_glance_sign_set = true
		_glance_sign = 1.0 if str(facts.forced_glance) == "L" else -1.0
		_glance_back = true
		if WORLD.pony(pony).look_toward(secondary, _glance_angles(), 0.4):
			_aim_eyes_at_player()
		return
	if lean_up:
		if not _glance_sign_set:
			_glance_sign = 1.0
			_glance_sign_set = true
		_glance_back = true
		if WORLD.pony(pony).look_toward(secondary, _glance_angles(), 0.3):
			_aim_eyes_at_player()
		return
	if not is_instance_valid(secondary) or not secondary.has_method("look_toward"):
		return
	if _glance_wait < 0.0:
		_glance_wait = randf_range(float(_pose_cfg["glance_min"]), float(_pose_cfg["glance_max"]))
	if _glance_left > 0.0:
		_glance_left -= delta
		WORLD.pony(pony).look_toward(secondary, _glance_angles(), 0.4)
		_aim_eyes_at_player()
		if _glance_left <= 0.0:
			_glance_wait = randf_range(float(_pose_cfg["glance_min"]), float(_pose_cfg["glance_max"]))
		return
	_glance_wait -= delta
	if _glance_wait <= 0.0:
		_glance_left = float(_pose_cfg["glance_hold"])
		_glance_back = randf() < float(_pose_cfg["glance_back_chance"])
		_glance_sign_set = false
	WORLD.pony(pony).look_toward(secondary, Vector3.ZERO, 0.4)


## Pupils/eyes follow Anon during a glance. The native eye modifier exposes `target_world` and
## `target_weight`; runtime physics priority runs after the pony, so this wins for the frame.
func _aim_eyes_at_player() -> void:
	if not is_instance_valid(pony):
		return
	var view: Camera3D = WORLD.camera()
	var target: Vector3 = view.global_position if is_instance_valid(view) else pony.global_position
	WORLD.pony(pony).aim_eyes(target)


func _glance_angles() -> Vector3:
	var head := WORLD.pony(pony).listen_point()
	var target: Vector3 = head
	if is_instance_valid(WORLD.player):
		var view: Camera3D = WORLD.camera()
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
		var back_pitch := float(_pose_cfg["glance_back_pitch"]) * 1.2
		return Vector3(clampf(pitch + back_pitch, -0.25, 1.44),
			clampf(yaw, -MOTION.GLANCE_BACK_YAW, MOTION.GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg["glance_yaw"])
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)


## Free look, but inside a 45-degree cone around the direction the act began in. Movement stays
## held by kiss_hold; this only limits where the camera can turn.
func _clamp_look() -> void:
	if _pose_family() == "bed":
		# Missionary uses the mod-owned view; the player's body look is left alone.
		return
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return
	var body: Node3D = WORLD.player
	var form := GAME.form_of(body)
	# AnonPony lying/sitting has her own body-yaw limit; never widen it.
	GAME.clamp_view(form)
	var yaw_delta := angle_difference(float(facts.look_yaw), float(body.rotation.y))
	if absf(yaw_delta) > LOOK_YAW_LIMIT:
		body.rotation.y = float(facts.look_yaw) + clampf(yaw_delta, -LOOK_YAW_LIMIT, LOOK_YAW_LIMIT)
	if GAME.headset_view(body):
		return
	var pitch_now := GAME.pitch(body)
	if not is_finite(pitch_now):
		return
	var want := float(facts.look_pitch) + clampf(pitch_now - float(facts.look_pitch), -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	if absf(pitch_now - want) > 0.00001:
		GAME.set_pitch(body, want)
	var view: Camera3D = WORLD.camera()
	if form == null and is_instance_valid(view):
		view.rotation.x = want


func _sync() -> void:
	pony = facts.pony if facts != null else null
	bed = facts.bed if facts != null else null
	camera = facts.camera if facts != null else null
	var cfg: Variant = facts.presentation_config if facts != null else null
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var view: Variant = facts.pose_view if facts != null else null
	var group := str(view.settings_group) if view != null else ""
	var key := str(view.id) if view != null else ""
	if group != _pose_cfg_group or key != _pose_cfg_key:
		var pose_cfg: Variant = view.from_config if view != null else null
		if not pose_cfg is Dictionary or (pose_cfg as Dictionary).is_empty():
			pose_cfg = view.pose_config if view != null else null
		_pose_cfg = pose_cfg if pose_cfg is Dictionary else {}
		_pose_cfg_group = group
		_pose_cfg_key = key


## The pose family from the pose view: `bed` and `standing` are the two views.
func _pose_family() -> String:
	var view: Variant = facts.pose_view if facts != null else null
	return str(view.family) if view != null else ""


## The missionary view: the position is his posed eye; the basis is the authored look path so the
## action is framed and the lean follows it. The kiss still leans the eye in towards the aim.
func _tick_eye(kiss: Variant, look: Vector3) -> void:
	if not is_instance_valid(_missionary_view):
		_make_missionary_view()
	if not is_instance_valid(_missionary_view):
		return
	var body: Node = facts.missionary_body() if facts != null else null
	if body == null:
		return
	var eye := WORLD.pony(body).eye_transform()
	if not eye.origin.is_finite():
		return
	var eye_basis := eye.basis.orthonormalized()
	var at: Vector3 = eye.origin
	# The position follows his eye; the orientation is the authored look path, not his head.
	var basis := _shot_basis(at, eye_basis)
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


## Blend the authored look path for this lean; the eye supplies only the position and the
## fallback when no shot can be read.
func _shot_basis(at: Vector3, fallback: Basis) -> Basis:
	if facts == null:
		return fallback
	var asset: Variant = facts.call_value(facts.authored_pose_asset)
	var frame: Variant = facts.bed_frame
	if asset == null or not frame is Transform3D:
		return fallback
	_refresh_shots(asset)
	var forward := clampf(float(facts.shot_lean_forward), -1.0, 1.0)
	var side := clampf(float(facts.lean_view_side), -1.0, 1.0)
	var tf := absf(forward)
	var ts := absf(side)
	var total := maxf(1.0, tf + ts)
	for i in _shot_weights.size():
		_shot_weights[i] = 0.0
	_shot_weights[0] = maxf(0.0, 1.0 - tf - ts) / total
	if tf > 0.0001:
		_shot_weights[2 if forward > 0.0 else 1] = tf / total
	if ts > 0.0001:
		_shot_weights[4 if side < 0.0 else 3] = ts / total
	var frame_basis: Basis = (frame as Transform3D).basis
	var aim: Vector3 = facts.call_value(facts.missionary_face_point, Vector3.INF)
	var reference := Quaternion.IDENTITY
	var have_reference := false
	var qsum := Quaternion(0.0, 0.0, 0.0, 0.0)
	var weight_sum := 0.0
	for i in SHOT_IDS.size():
		var weight := _shot_weights[i]
		if weight <= 0.0001:
			continue
		var basis: Basis
		if _shot_present[i] > 0:
			basis = (frame_basis * _shot_local[i]).orthonormalized()
		else:
			basis = _aimed_basis(at, aim, frame_basis, fallback)
		var q := basis.get_rotation_quaternion()
		if not have_reference:
			reference = q
			have_reference = true
		if q.dot(reference) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		qsum = Quaternion(qsum.x + q.x * weight, qsum.y + q.y * weight,
			qsum.z + q.z * weight, qsum.w + q.w * weight)
		weight_sum += weight
	if weight_sum <= 0.0001 or qsum.length_squared() < 0.000001:
		return fallback
	return Basis(qsum.normalized())


## The authored shot bases are bed-local; cache them per asset and scale only the live frame.
func _refresh_shots(asset: Variant) -> void:
	var id: int = asset.get_instance_id() if asset != null else 0
	if id == _shot_asset_id and _shot_local.size() == SHOT_IDS.size():
		return
	_shot_asset_id = id
	_shot_local.resize(SHOT_IDS.size())
	_shot_present.resize(SHOT_IDS.size())
	_shot_present.fill(0)
	_shot_weights.resize(SHOT_IDS.size())
	var shots: Variant = asset.get("shots") if asset != null else null
	if not shots is Dictionary:
		return
	for i in SHOT_IDS.size():
		var shot: Variant = (shots as Dictionary).get(SHOT_IDS[i])
		if shot is Transform3D:
			_shot_local[i] = ((shot as Transform3D).basis).orthonormalized()
			_shot_present[i] = 1


## A missing shot's basis: look at her face from the eye, with the bed's head line as the pole when
## the view steepens. A non-finite aim keeps the eye's own basis.
static func _aimed_basis(at: Vector3, aim: Vector3, frame_basis: Basis, fallback: Basis) -> Basis:
	if not aim.is_finite():
		return fallback
	var direction := aim - at
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return fallback
	var dir := direction.normalized()
	var steep := smoothstep(0.55, 0.95, absf(dir.dot(Vector3.UP)))
	var head := frame_basis.z
	head.y = 0.0
	var pole := Vector3.UP
	if head.length_squared() > 0.0001:
		pole = Vector3.UP.lerp(head.normalized(), steep)
	if pole.length_squared() < 0.0001:
		pole = Vector3.UP
	return Basis.looking_at(dir, pole.normalized())


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
	var body_view := WORLD.pony(pony)
	var skull := body_view.skull_world()
	var nose := body_view.nose_world()
	if not skull.is_finite() or not nose.is_finite():
		return at
	var scale := _missionary_body_scale()
	var point := _push_sphere(at, skull, 0.09 * scale + clearance)
	var muzzle := body_view.muzzle_world()
	if muzzle.is_finite():
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
func head_look_point(viewer: Camera3D) -> Vector3:
	if not is_instance_valid(viewer):
		return Vector3.INF
	return head_look_point_at(viewer.global_position)


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
		LOG.debug("act view setup source_fov=%.1f near=%.3f far=%.0f", [
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
		LOG.debug("act view restore fov=%.1f near=%.3f far=%.0f", [
			_missionary_prev_camera.fov, _missionary_prev_camera.near,
			_missionary_prev_camera.far])
	_missionary_prev_camera = null
	if is_instance_valid(WORLD.player):
		var source: Camera3D = WORLD.camera()
		if _missionary_player_rot_saved and is_instance_valid(source):
			source.rotation = _missionary_player_rotation
	_missionary_player_rot_saved = false
