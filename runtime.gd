extends Node
## One per pony. Holds the act state machine and all per-act state. It never edits game files.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const REST := preload("res://mods/unfplap/rest_control.gd")
const WITNESS := preload("res://mods/unfplap/witness.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const AFTERCARE := preload("res://mods/unfplap/aftercare.gd")
const PUMP := preload("res://mods/unfplap/pump.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const UTTERANCE := preload("res://mods/unfplap/utterance.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")

enum State { IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, WITHDRAW, RESTORE }

const SATISFACTION_MAX := 100
const STAMINA_MAX := 400
const CLIMAX_SECONDS := 5.0
const CLIMAX_BOBS := 2
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
const BREATH_BASE_INTERVAL_S := 0.9
const BREATH_MIN_INTERVAL_S := 0.2
const BREATH_RATE_CAP := 10.0
## Breath gain easing. Active: follows the plap rate; afterglow: fades over this many seconds.
const BREATH_FADE_S := 2.5
const AFTERGLOW_BREATH_FADE_S := 5.0
const WITNESS_RADIUS_M := 8.0
## Pose 1 camera: 0.75 m above the pony root and this far forward, so it sits above her neck/face
## instead of above the middle of her body. `pony.global_basis.z` is her backward direction.
const POSE1_CAMERA_HEIGHT_M := 0.55
const POSE1_CAMERA_FORWARD_M := 0.15
## Presentation: how close the pony stands in front of the player for pose 2.
const POSE2_GAP_M := 0.55
## Per-size pose-2 standing gap. Same Height is the tuned baseline; Hoers stays unchanged.
const POSE2_GAPS := {
	"same height": 0.55,
	"mounting": 0.45,
	"canon": 0.35,
	"hoers": 0.55,
}
## Camera motion is forward/back only, driven by the smoothed penetration value.
## `PUMP_LEAN_AMPLITUDE` is the old pump spring's peak (~0.09 m).
const PUMP_LEAN_AMPLITUDE := 0.09
const PUMP_LEAN_BASE_FRACTION := 0.10
const PUMP_TRAVEL_OMEGA := 30.0
const PUMP_TRAVEL_DAMPING := 60.0
const ACT_LOOK_YAW_SCALE := 0.10
const ACT_LOOK_PITCH_SCALE := 0.20
const LEAN_CLIMAX_FORWARD := 0.09
## Free look stays inside a 45-degree cone around the direction the act started in.
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
## Pose 2 after the climax: Anon eases back before the act restores.
const AFTERGLOW_BACK_M := 0.18
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Pose 2 after the climax: no cuddle afterglow; a short withdrawal shows the pull-back and flicks.
const POSE2_WITHDRAW_SECONDS := 1.6
## Wing spread/droop and jitter. Wings spread over two seconds, then lower over ten.
const WING_FADE_SECONDS := 0.55
const WING_FLICK_DECAY := 0.45
const WING_SPREAD_SECONDS := 2.0
const WING_DROOP_SECONDS := 10.0
const WING_DROOP_AMOUNT := 0.35
const WING_JITTER_AMOUNT := 0.04
const WING_JITTER_MIN := 0.4
const WING_JITTER_MAX := 1.0
const WING_JITTER_FADE := 0.2
## Pose 2 keeps her body facing away but lets her glance back over a shoulder now and then.
const GLANCE_MIN_INTERVAL := 5.0
const GLANCE_MAX_INTERVAL := 9.0
const GLANCE_HOLD := 1.8
const GLANCE_YAW := 3.0
const GLANCE_BACK_PITCH := 1.2
const GLANCE_BACK_CHANCE := 0.5
## Fade time for the extra head-back glance pose; prevents the head snapping back to low.
const GLANCE_BACK_FADE := 0.45
## Jiggle placement on the flank. DEBUG: strength is exaggerated to verify the hit points;
## lower JIGGLE_STRENGTH after the placement looks right.
const JIGGLE_HEIGHT := 0.78
const JIGGLE_SIDE := 0.24
const JIGGLE_BACK := 0.12
const JIGGLE_STRENGTH := 1.0

var pony
var main

var state: int = State.IDLE
var pose_id := ""
var source := ""
var bed: Node3D
var satisfaction := 0
var stamina := STAMINA_MAX
## Public for the HUD: penetration 0..1 and the same orientation flag used by mouse input.
var depth := 0.0
var pump_up := true

var _pose
var _tail
var _debug_pose: Node
var _debug_pose_saved := Transform3D.IDENTITY
var _debug_pose_active := false
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
var _afterglow_pose := ""

var _player_pony := false
var _had_kiss_hold := false
var _locked_player := false
var _nav: Node
var _nav_old_wander := true
var _token := ""
var _id := ""
var _profile: Dictionary = {}
var _pose_cfg: Dictionary = {}
var _base_preferences: Dictionary = {}
var _preferences: Dictionary = {}
var _phase_index := -1
var _act_prompts: Dictionary = {}
var _pump_tracker
var _pump_pixels_per_full := 800.0
var _satisfaction_frac := 0.0
var _speed_zone := "ok"
var _speed_zone_previous := "ok"
var _stroke_speed := 0.0
var _stroke_shape := ""
var _speed_zone_strokes := 0
var _last_reaction: Dictionary = {}
var _depth_out_seconds := 0.0
var _utterance_points: Array[float] = []
var _utterance_index := 0
var _utterance_pending_key := ""
var _utterance_pending_until := 0.0
var _utterance_rng := RandomNumberGenerator.new()
var _utterance_serial := 0
var _vocal_cooldown := 0.0
var _bored_seconds := 0.0
var _speed_travel := 0.0
var _climax_at := 100
var _aftercare_min := 10
var _display_name := "the pony"
var _serial := 0
var _event_id := ""
var _started_at := 0.0

var _camera: Camera3D
var _applied_lean := 0.0
## Smoothed depth for HUD/camera only. Raw `depth` still drives scoring/strokes.
var view_depth := 0.0
var _view_velocity := 0.0
var _pose1_camera := Vector3.INF
var _pose1_head_roll := 0.0
var _pose1_free_yaw := 0.0
var _pose1_free_pitch := 0.0
var _pose1_debug_rot := Basis.IDENTITY
var _pose1_start_camera: Camera3D
var _pose1_start_camera_transform := Transform3D.IDENTITY
var _pose1_start_player_transform := Transform3D.IDENTITY
var _pose1_start_pony_transform := Transform3D.IDENTITY
var _pose1_start_pony_posture := ""
var _pose1_start_saved := false
var _pose1_basis_logged := false
var _pose1_view: Camera3D
var _pose1_view_basis := Basis.IDENTITY
var _pose1_aim_until := 0
var _pose1_prev_camera: Camera3D
var _pose1_player_rotation := Vector3.ZERO
var _pose1_player_rot_saved := false
var _anon_avatar: Node3D
var _anon_avatar_visible := true
var _lean := 0.0
var _back := 0.0
var _back_target := 0.0
var _withdraw_left := 0.0
var _facing_basis := Basis.IDENTITY
var _has_facing := false
var _glance_wait := 0.0
var _glance_left := 0.0
var _glance_back := false
var _glance_sign := 1.0
var _glance_sign_set := false
var _glance_head_back := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _eye_override := false
var _saved_stand_eye := 0.0
var _saved_eye_height := 0.0
var _camera_target_eye := 0.0
var _winged := false
var _wing_clock := 0.0
var _flutter_clock := 0.0
var _wing_hold := false
var _wing_flick := 0.0
var _wing_hold_value := 1.0
var _wing_hold_started := false
var _wing_jitter := 0.0
var _wing_jitter_goal := 0.0
var _wing_jitter_clock := 0.0
var _act_seconds := 0.0
var _wings_node: Node
var _aftercare: Node
var _satisfaction_tween: Tween
var _face_timer: Timer
var _kisser: Node
var _kisser_processing := false
var _climax_progress := 0.0
var _breath: AudioStreamPlayer3D
var _breath_streams: Array[AudioStream] = []
var _breath_clock := 0.0
var _breath_gain := 0.0
var _kiss_sound: AudioStreamPlayer3D
var _plap_streams: Array[AudioStream] = []
var _flank: Node
var _jiggle_logged := false
var _climax_sound: AudioStreamPlayer3D
var _kiss_stream: AudioStream
var _climax_streams: Array[AudioStream] = []
var _pump_times: Array[float] = []


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	# Run after locomotion/navigator/attention so the body facing lock and head glance win.
	process_physics_priority = 100
	_face_timer = Timer.new()
	_face_timer.name = "UnfplapFaceTimer"
	_face_timer.one_shot = true
	_face_timer.timeout.connect(_clear_face)
	add_child(_face_timer)


func _release_wing_hold() -> void:
	if _wing_hold and is_instance_valid(_wings_node) and _wings_node.has_method("release_hold"):
		_wings_node.call("release_hold", "unfplap")
	_wing_hold = false
	_wing_hold_started = false
	_wings_node = null


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


## Strong blush for the whole act; pegasi/alicorns spread their wings and occasionally flutter.
func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act_seconds += delta
	if pose_id == CATALOG.MISSIONARY and not is_instance_valid(_anon_avatar):
		_hide_anon_avatar_for_pose1()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", 1.0)
	# Reuse the boop-fluster ear response: it pins the ears back along the skull and also keeps
	# the nose blush strong. Our stare() calls still own the eyelids.
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster"):
		expressions.call("fluster", 1.2)
	if not _winged:
		return
	var excitement: Variant = pony.get("excitement")
	if excitement == null:
		return
	_wing_flick = move_toward(_wing_flick, 0.0, delta / WING_FLICK_DECAY)
	if not _wing_hold:
		var wings: Variant = excitement.call("_wings") if excitement.has_method("_wings") else null
		if wings is Node and (wings as Node).has_method("hold_at"):
			_wings_node = wings as Node
			_wing_hold = bool(_wings_node.call("hold_at", "unfplap", 1.0))
	if _wing_hold and is_instance_valid(_wings_node):
		var level := sqrt(clampf(float(satisfaction) / (_climax_at * 0.75), 0.0, 1.0))
		var spread_t := smoothstep(0.0, 1.0, clampf(_act_seconds / WING_SPREAD_SECONDS, 0.0, 1.0))
		var base_target := 1.0 - spread_t
		if pose_id != CATALOG.MISSIONARY:
			base_target = lerpf(1.0, 1.0 - level, spread_t)
		var droop := clampf(_act_seconds / WING_DROOP_SECONDS, 0.0, 1.0) * WING_DROOP_AMOUNT
		_wing_jitter_clock -= delta
		if _wing_jitter_clock <= 0.0:
			_wing_jitter_goal = randf_range(-WING_JITTER_AMOUNT, WING_JITTER_AMOUNT)
			_wing_jitter_clock = randf_range(WING_JITTER_MIN, WING_JITTER_MAX)
		_wing_jitter = move_toward(_wing_jitter, _wing_jitter_goal, delta / WING_JITTER_FADE)
		var target_hold := clampf(base_target + droop + _wing_flick + _wing_jitter, 0.0, 1.0)
		if not _wing_hold_started:
			_wing_hold_value = 1.0
			_wing_hold_started = true
		_wing_hold_value = move_toward(_wing_hold_value, target_hold, delta / WING_FADE_SECONDS)
		_wings_node.call("hold_at", "unfplap", _wing_hold_value)
		return
	# Fallback when the half-open wing pose is unavailable.
	if satisfaction >= _climax_at * 0.75:
		_wing_clock -= delta
		if _wing_clock <= 0.0:
			_wing_clock = 1.0
			excitement.call("spread", 2.0)
		return
	_flutter_clock -= delta
	if _flutter_clock <= 0.0 and excitement.has_method("flutter"):
		excitement.call("flutter")
		_flutter_clock = randf_range(1.2, 2.3)


func _set_ears(kind: String, weight: float) -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	var eyes: Variant = expressions.get("eyes")
	if eyes == null:
		return
	var dict: Variant = eyes.get("expression_ears")
	if not dict is Dictionary:
		return
	var ears: Dictionary = dict
	for name: String in ["ears_alert", "ears_side", "ears_agitated", "ears_pinned"]:
		ears[name] = 0.0
	ears[kind] = clampf(weight, 0.0, 1.0)


func _set_face(smile: float, lids: float, hold_seconds := 0.0) -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if expressions.has_method("touch"):
		expressions.call("touch", "unfplap_state", smile, 0.0)
	if expressions.has_method("stare"):
		expressions.call("stare", true, lids)
	if hold_seconds > 0.0 and is_instance_valid(_face_timer):
		_face_timer.start(hold_seconds)


func _clear_face() -> void:
	if is_instance_valid(_face_timer):
		_face_timer.stop()
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if expressions.has_method("stare"):
		expressions.call("stare", false)
	if expressions.has_method("release_touch"):
		expressions.call("release_touch", "unfplap_state")


func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_travel_tick(delta)
	_clamp_look()
	if is_instance_valid(_pose) and is_instance_valid(main):
		var view: Camera3D = main.camera()
		if pose_id == CATALOG.MISSIONARY and is_instance_valid(_pose1_view):
			view = _pose1_view
		if is_instance_valid(view):
			_pose.look_point = view.global_position
		_pose.climaxing = state == State.CLIMAX
	if state == State.CLIMAX:
		_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)
		var wave := sin(_climax_progress * PI * 2.0 * float(CLIMAX_BOBS))
		_lean = wave * LEAN_CLIMAX_FORWARD
	elif state == State.ACTIVE:
		_lean = (view_depth - PUMP_LEAN_BASE_FRACTION) * PUMP_LEAN_AMPLITUDE
	else:
		_lean = move_toward(_lean, 0.0, delta / 0.18)
	var back_speed := AFTERGLOW_BACK_SPEED if state in [State.AFTERGLOW, State.WITHDRAW] else RESTORE_BACK_SPEED
	_back = move_toward(_back, _back_target, back_speed * delta)
	_breath_tick(delta)


## The bar/camera value brakes sharply before reversing. Raw `depth` keeps scoring exact.
func _travel_tick(delta: float) -> void:
	var dt := minf(maxf(delta, 0.0), 0.05)
	if dt <= 0.0:
		return
	var error := view_depth - depth
	_view_velocity += (-PUMP_TRAVEL_OMEGA * PUMP_TRAVEL_OMEGA * error
		- PUMP_TRAVEL_DAMPING * _view_velocity) * dt
	view_depth += _view_velocity * dt
	if view_depth <= 0.0:
		view_depth = 0.0
		_view_velocity = 0.0
	elif view_depth >= 1.0:
		view_depth = 1.0
		_view_velocity = 0.0


## Mouse input. Motion is consumed while the act owns the mouse so the two axes can use separate
## scales; scoring still uses the raw depth. Pose 1 also keeps its free-look offsets.
func _input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var headset := _headset_view()
	if state in [State.ACTIVE, State.CLIMAX]:
		if pose_id == CATALOG.MISSIONARY:
			if not headset:
				_pose1_free_yaw = clampf(_pose1_free_yaw - motion.relative.x * 0.0025 * ACT_LOOK_YAW_SCALE, -1.2, 1.2)
				_pose1_free_pitch = clampf(_pose1_free_pitch - motion.relative.y * 0.0025 * ACT_LOOK_PITCH_SCALE, -1.0, 1.0)
		elif not headset:
			_act_look(motion)
		if state == State.ACTIVE and _pump_tracker != null:
			var amount: float = PUMP.mouse_to_depth(motion.relative.y, _pump_pixels_per_full, pump_up)
			_pump_move(amount, _now_s())
		get_viewport().set_input_as_handled()
		return
	if pose_id != CATALOG.MISSIONARY or headset:
		return
	_pose1_free_yaw = clampf(_pose1_free_yaw - motion.relative.x * 0.0025, -1.2, 1.2)
	_pose1_free_pitch = clampf(_pose1_free_pitch - motion.relative.y * 0.0025, -1.0, 1.0)


func _headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view"))


## Pose-2 look during the act. Separate axis scales keep lateral movement nearly still while
## vertical still responds a little to the same mouse stroke that changes depth.
func _act_look(motion: InputEventMouseMotion) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var sensitivity: Variant = body.get("mouse_sensitivity")
	if sensitivity == null:
		return
	var value := float(sensitivity)
	body.rotation.y -= motion.relative.x * value * ACT_LOOK_YAW_SCALE
	var pitch: Variant = body.get("_pitch")
	if pitch != null:
		var invert: Variant = body.get("invert_y")
		var dy := motion.relative.y * value * (-1.0 if bool(invert) else 1.0) * ACT_LOOK_PITCH_SCALE
		body.set("_pitch", clampf(float(pitch) - dy, -1.5, 1.5))
		var form: Variant = body.get("form_driver")
		if form is Node and (form as Node).has_method("clamp_view"):
			form.call("clamp_view")
	_clamp_look()


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	if not is_instance_valid(pony) or not is_instance_valid(main):
		force_stop()
		return
	if pony.sleeping:
		pony.sleeping = false
	_vocal_cooldown = maxf(0.0, _vocal_cooldown - delta)
	_keep_nav()
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.WITHDRAW]:
		_act_presentation(delta)
	if state == State.ACTIVE:
		_update_phase()
		_pump_tick()
		_boredom_tick(delta)
		_utterance_tick()
	if state == State.POSING_IN:
		_pose_in_left -= delta
		if _pose_in_left <= 0.0:
			state = State.ACTIVE
	elif state == State.CLIMAX:
		_climax_left -= delta
		if _climax_left <= 0.0:
			_finish_climax()
	elif state == State.WITHDRAW:
		_withdraw_left -= delta
		if _withdraw_left <= 0.0:
			_restore_begin()
	elif state == State.RESTORE:
		_restore_left -= delta
		if _restore_left <= 0.0:
			_finish_restore()
	_lock_body_facing()
	_drive_glance(delta)
	_suppress_auto_cuddle()
	_clamp_look()
	apply_camera_motion()
	if state in [State.POSING_IN, State.ACTIVE, State.AFTERGLOW]:
		_check_clock += delta
		if _check_clock >= 0.25:
			_check_clock = 0.0
			_check_running()


# --------------------------------------------------------------------------- gates

func can_start(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	if not _relationship_ok():
		return false
	if not _player_form_ok():
		return false
	if get_tree().paused:
		return false
	if not _conversation_ok():
		return false
	if pony.sleeping:
		return false
	if bool(pony.get_meta("sex_active", false)):
		return false
	if pony.has_meta("sex_aftercare"):
		return false
	if _cuddle_active() and not (pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]):
		return false
	if not _free_of_affection():
		return false
	if not _player_ready_for(pose, act_source, bed_in):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or str(nav.get("reserved_by")) != "":
		return false
	if not _nav_owner_allows(pose, act_source):
		return false
	if not _nav_pose_gate(pose, act_source):
		return false
	if pose == CATALOG.MISSIONARY:
		var found: Node3D = _resolve_bed(pose, act_source, bed_in)
		if found == null:
			return false
		if main.bed_occupied(found, pony):
			return false
		if not _bed_gate(pose, act_source, found):
			return false
	return true


func _start_reasons(pose: String, act_source: String, bed_in: Variant = null) -> PackedStringArray:
	var reasons: PackedStringArray = []
	if not is_instance_valid(pony):
		reasons.append("invalid_pony")
		return reasons
	if not is_instance_valid(main):
		reasons.append("no_main")
		return reasons
	if not is_instance_valid(main.player):
		reasons.append("no_player")
		return reasons
	if not is_instance_valid(main.game):
		reasons.append("no_game")
		return reasons
	if state != State.IDLE:
		reasons.append("state=%d" % state)
	if not _relationship_ok():
		reasons.append("relation")
	if not _player_form_ok():
		reasons.append("form")
	if get_tree().paused:
		reasons.append("paused")
	if not _conversation_ok():
		reasons.append("conversation")
	if pony.sleeping:
		reasons.append("sleeping")
	if bool(pony.get_meta("sex_active", false)):
		reasons.append("sex_active")
	if pony.has_meta("sex_aftercare"):
		reasons.append("aftercare")
	if _cuddle_active() and not (pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]):
		reasons.append("cuddle")
	if not _free_of_affection():
		reasons.append("affection")
	if not _player_ready_for(pose, act_source, bed_in):
		reasons.append("player")
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		reasons.append("no_navigator")
	else:
		if str(nav.get("reserved_by")) != "":
			reasons.append("navigator_reserved")
		if not _nav_owner_allows(pose, act_source):
			reasons.append("nav_owner")
	if not _nav_pose_gate(pose, act_source):
		reasons.append("nav_pose")
	if pose == CATALOG.MISSIONARY:
		var found: Node3D = _resolve_bed(pose, act_source, bed_in)
		if found == null:
			reasons.append("no_bed")
		else:
			if main.bed_occupied(found, pony):
				reasons.append("bed_occupied")
			if not _bed_gate(pose, act_source, found):
				reasons.append("bed_gate")
	return reasons


func debug_line(pose: String, act_source: String, bed_in: Variant = null, distance := -1.0, dot := -1.0) -> String:
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	var id := ""
	var display := "?"
	if identity != null:
		id = str(identity.get("id"))
		display = str(identity.get("display_name")) if identity.get("display_name") != null else id
	var rel: Variant = pony.get_meta("relationship_runtime") if is_instance_valid(pony) else null
	var bonds: Variant = rel.get("bonds") if rel != null and is_instance_valid(rel) else null
	var stage := "?"
	var love_name := "?"
	var love_level := -1
	if rel != null and is_instance_valid(rel) and rel.has_method("ladder"):
		var ladder: Dictionary = rel.call("ladder", id)
		var love: Dictionary = ladder.get("love", {})
		love_name = str(love.get("name", "?"))
		love_level = int(love.get("level", -1))
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("record_for"):
		var rec: Dictionary = bonds.call("record_for", id)
		stage = str(rec.get("stage", "?"))
	var welcomes := false
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("welcomes"):
		welcomes = bool(bonds.call("welcomes", id, "kiss"))
	var mood := "?"
	if is_instance_valid(main) and is_instance_valid(main.game):
		var ctx: Variant = main.game.get("world_context")
		if ctx != null and is_instance_valid(ctx):
			var impressions: Variant = ctx.get("impressions")
			if impressions != null and is_instance_valid(impressions) and impressions.has_method("profile"):
				var prof: Dictionary = impressions.call("profile", id)
				mood = str(prof.get("mood", "?"))
	var status: Dictionary = pony.posture_status() if is_instance_valid(pony) and pony.has_method("posture_status") else {}
	var nav: Node = pony.get_node_or_null("Navigator") if is_instance_valid(pony) else null
	var owner := ""
	var target := false
	var reserved := ""
	if nav != null:
		owner = str(nav.get("command_owner"))
		target = bool(nav.get("_has_target"))
		reserved = str(nav.get("reserved_by"))
	var body: Variant = main.player if is_instance_valid(main) else null
	var reasons: PackedStringArray = _start_reasons(pose, act_source, bed_in)
	var can := can_start(pose, act_source, bed_in)
	var reason_text := "none" if reasons.is_empty() else ",".join(reasons)
	var found_bed: Node3D = _resolve_bed(pose, act_source, bed_in) if pose == CATALOG.MISSIONARY else null
	var bed_gate := "n/a"
	if pose == CATALOG.MISSIONARY:
		bed_gate = str(found_bed != null and _bed_gate(pose, act_source, found_bed))
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level=%d) welcomes=%s mood=%s | state=%d sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		display, id, float(distance), float(dot), stage, love_name, love_level, str(welcomes), mood,
		state, str(pony.get("sleeping")), str(pony.is_held()), str(pony.grounded()), str(pony.has_meta("seated")),
		str(_cuddle_active()), str(pony.get("motion_paused")), float(pony.get("actual_speed")), str(status.get("requested")),
		str(pony.action_interruption_reason()), owner, str(target), reserved,
		str(body.get("controls_locked")) if body != null else "?",
		str(body.get("flying")) if body != null else "?",
		str(body.get("seat")) if body != null else "?",
		str(Input.mouse_mode), str(get_tree().paused),
		str(_relationship_ok()), str(_player_form_ok()), str(_conversation_ok()), str(_free_of_affection()),
		str(_player_ready_for(pose, act_source, bed_in)), str(_nav_owner_allows(pose, act_source)),
		str(_nav_pose_gate(pose, act_source)), bed_gate, str(can), reason_text]
	if state != State.IDLE and not _preferences.is_empty():
		text += " | pump depth=%.2f speed=%.2f zone=%s shape=%s up=%s | %s" % [
			depth, _stroke_speed, _speed_zone, _stroke_shape, str(pump_up),
			PREFERENCES.describe(_preferences).replace("\n", "; ")]
	return text


func refuse_available(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	if not _stage_ok() or not _player_form_ok():
		return false
	if _relationship_ok():
		return false # Willing: the normal offer/start path owns it.
	if pony.sleeping or bool(pony.get_meta("sex_active", false)) or pony.has_meta("sex_aftercare"):
		return false
	if not _conversation_ok() or not _free_of_affection():
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or str(nav.get("reserved_by")) != "":
		return false
	if not _nav_owner_allows(pose, act_source):
		return false
	var body = main.player
	if bool(body.get("controls_locked")) or bool(body.get("flying")):
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection == null or not affection.has_method("buck"):
		return false
	if pose == CATALOG.HORSE:
		if pony.is_held() or not pony.grounded() or pony.has_meta("seated"):
			return false
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "stand" or not bool(status.get("settled", false)):
			return false
		if pony.global_position.distance_to(body.global_position) > 2.4:
			return false
		return true
	if act_source == "cradle":
		var reach: Node = main.interactor()
		if not is_instance_valid(reach):
			return false
		return reach.get("held") == pony and reach.get("cradled") == true
	if act_source == "already_lying":
		var bed: Node3D = _resolve_bed(pose, act_source, bed_in)
		if bed == null:
			return false
		var status2: Dictionary = pony.posture_status()
		if str(status2.get("requested", "")) != "lie_down":
			return false
		return main.player_beside_bed(bed)
	return false


func refuse(pose: String, act_source: String, bed_in: Variant = null) -> void:
	if not refuse_available(pose, act_source, bed_in):
		return
	if pose == CATALOG.HORSE:
		_buck_or_push()
		return
	if act_source == "cradle":
		if not _release_carry():
			return
		var at: Vector3 = _refusal_floor()
		var forward: Vector3 = main.player.global_position - at
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -main.player.global_basis.z
		forward = forward.normalized()
		pony.reset_motion(Transform3D(Basis.looking_at(forward, Vector3.UP), at))
		pony.reset_physics_interpolation()
		pony.request_posture("stand")
		await get_tree().physics_frame
		_buck_or_push()
		return
	if act_source == "already_lying":
		if not REST.release_managed(pony):
			return
		pony.request_posture("stand")
		await get_tree().physics_frame
		_buck_or_push()


func _refusal_floor() -> Vector3:
	var forward: Vector3 = -main.player.global_basis.z
	var view: Camera3D = main.camera()
	if view != null:
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var at: Vector3 = main.player.global_position + forward * 1.1
	var world: World3D = main.player.get_world_3d()
	if world != null:
		var space: PhysicsDirectSpaceState3D = world.direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1)
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty():
				at = hit.get("position", at)
	return at


func _buck_or_push() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and affection.has_method("buck"):
		if bool(affection.call("buck", main.player_body())):
			return
	var body = main.player
	if not is_instance_valid(body):
		return
	var knockdown: Variant = body.get("knockdown")
	if knockdown == null or not knockdown.has_method("start"):
		return
	var direction: Vector3 = pony.global_position - body.global_position
	direction.y = 0.25
	if direction.length_squared() < 0.0001:
		direction = -body.global_basis.z
	knockdown.call("start", body, direction.normalized() * 3.0)


func can_offer() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not _relationship_ok() or not _player_form_ok():
		return false
	if pony.sleeping or bool(pony.get_meta("sex_active", false)) or pony.has_meta("sex_aftercare"):
		return false
	if pony.is_held() or _cuddle_active():
		return false
	if not _conversation_ok() or not _free_of_affection():
		return false
	return true


func _stage_ok() -> bool:
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return false
	_id = str(pony.get_meta("relationship_id", ""))
	if _id.is_empty():
		var identity_id: Variant = pony.get("identity")
		if identity_id != null:
			_id = str(identity_id.get("id"))
	if _id.is_empty():
		return false
	var identity: Variant = pony.get("identity")
	if identity == null or bool(identity.get("filly")):
		return false
	if not bool(runtime.bonds.adults.get(_id, false)):
		return false
	var ladder: Dictionary = runtime.ladder(_id)
	var love: Dictionary = ladder.get("love", {})
	if int(love.get("level", -1)) < 2:
		return false
	if not bool(runtime.bonds.eligible_for_romance(_id)):
		return false
	_display_name = str(identity.get("display_name")) if identity.get("display_name") != null else _id
	return true


func _relationship_ok() -> bool:
	if not _stage_ok():
		return false
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return false
	return bool(runtime.bonds.welcomes(_id, "kiss"))


func _player_form_ok() -> bool:
	return not PLAYER_FORM.is_young(PLAYER_FORM.active(get_tree()))


func _conversation_ok() -> bool:
	var target: Variant = pony.get("conversation_target")
	if target == null or not is_instance_valid(target):
		return true
	var body: Node3D = main.player_body()
	if target == main.player or target == body:
		return true
	# The player's body/avatar is under the rig; another pony's is not.
	if is_instance_valid(main.player) and main.player is Node and (main.player as Node).is_ancestor_of(target as Node):
		return true
	return false


func _suppress_auto_cuddle() -> void:
	if not is_instance_valid(pony):
		return
	# The stock bed marks a lying companion with couch_cuddle; cuddle/player_input then
	# automatically begins a CuddleSession. That interrupts pose 1, so keep it off while active.
	if pony.has_meta("couch_cuddle"):
		pony.remove_meta("couch_cuddle")
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session != null and (bool(session.get("enabled")) or float(session.get("blend")) > 0.0):
		if session.has_method("end"):
			session.call("end", true)
	if pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")


func _cuddle_active() -> bool:
	if not is_instance_valid(pony):
		return false
	if pony.has_meta("cuddle_active"):
		return true
	# cuddle_session is a persistent reference to the cuddle input's session; the session
	# stays on the pony after end(). Only an enabled/blending session is an active cuddle.
	if not pony.has_meta("cuddle_session"):
		return false
	var session: Variant = pony.get_meta("cuddle_session")
	if session == null or not is_instance_valid(session):
		return false
	if bool(session.get("enabled")):
		return true
	var blend: Variant = session.get("blend")
	return blend != null and float(blend) > 0.01


func _free_of_affection() -> bool:
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null:
		var kind: Variant = affection.get("kind")
		if kind != null and not str(kind).is_empty():
			return false
	var hoof: Variant = pony.get("hoof_hold")
	if hoof != null and hoof.has_method("active") and bool(hoof.call("active")):
		return false
	return true


func _nav_owner_allows(pose: String, act_source: String) -> bool:
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	var owner := str(nav.get("command_owner"))
	if owner.is_empty():
		return true
	if owner.begins_with("unfplap:") or owner.begins_with("sleep:"):
		return false
	if owner.begins_with("weather:") or owner.begins_with("show:"):
		return false
	if owner.begins_with("cuddle:"):
		return pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]
	# A managed bed/couch rest is valid for pose 1; every other leisure seat is not.
	if owner.begins_with("leisure:"):
		return pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]
	# Player conversation is free; another pony's conversation is not.
	if owner.begins_with("social:"):
		return owner.begins_with("social:talk") and _conversation_ok()
	# Normal routine owners: idle routines are free, an active route is not.
	if owner.begins_with("life:") or owner.begins_with("day:"):
		return not bool(nav.get("_has_target"))
	# A player-owned date/outing, following the player, or an idle rest.
	if owner.begins_with("bond:") or owner.begins_with("player:") or owner == "rest_after_command":
		return true
	return false


func _nav_pose_gate(pose: String, act_source: String) -> bool:
	if pose == CATALOG.HORSE:
		if pony.is_held() or not pony.grounded():
			return false
		if bool(pony.motion_paused):
			return false
		if pony.has_meta("seated"):
			return false
		if not str(pony.action_interruption_reason()).is_empty():
			return false
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "stand" or not bool(status.get("settled", false)):
			return false
		if float(pony.actual_speed) > 0.06:
			return false
		return true
	if act_source == "cradle":
		return true
	# already_lying: seated is allowed; held/grounded/interruption are not used.
	return true


func _bed_gate(pose: String, act_source: String, found: Node3D) -> bool:
	if pose != CATALOG.MISSIONARY:
		return true
	var rest: Node = pony.get_node_or_null("CradleRest")
	if rest != null:
		if bool(rest.get("asleep")):
			return false
		if act_source == "cradle" and float(rest.get("drowse")) >= 0.5:
			return false
	if act_source == "cradle":
		var reach: Node = main.interactor()
		if not is_instance_valid(reach):
			return false
		if reach.get("held") != pony or reach.get("cradled") != true:
			return false
		# The cradle path exists only for human Anon.
		if PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())):
			return false
		return true
	if act_source == "bed_side":
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "lie_down" or not bool(status.get("settled", false)):
			return false
		return main.player_beside_bed(found)
	if not PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())):
		return false
	var status: Dictionary = pony.posture_status()
	if str(status.get("requested", "")) != "lie_down" or not bool(status.get("settled", false)):
		return false
	return main.player_beside_bed(found)


func _resolve_bed(pose: String, act_source: String, bed_in: Variant) -> Node3D:
	if pose != CATALOG.MISSIONARY:
		return null
	if bed_in is Node3D and is_instance_valid(bed_in):
		return bed_in
	if act_source == "cradle":
		return main.bed_for_cradle(pony)
	return find_bed_under()


func find_bed_under() -> Node3D:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return null
	var exclude: RID = pony.get_rid() if pony is CollisionObject3D else RID()
	return main.bed_under(pony.global_position, exclude)


func _player_ready_for(pose: String, act_source: String, bed_in: Variant) -> bool:
	var body = main.player
	if not is_instance_valid(body):
		return false
	if bool(body.get("controls_locked")):
		return false
	if bool(body.get("flying")):
		return false
	var wing: Variant = body.get("wing_flight")
	if wing != null and bool(wing.get("active")):
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	var swimming: Variant = body.get("swimming")
	if swimming != null and bool(swimming.get("active")):
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var inventory: Variant = main.game.get("inventory") if is_instance_valid(main.game) else null
	if inventory != null:
		var held: Variant = inventory.get("held")
		if held is Dictionary and not (held as Dictionary).is_empty():
			return false
		if str(inventory.get("holding_case")) != "":
			return false
	var seat: Variant = body.get("seat")
	if pose == CATALOG.HORSE:
		if seat != null:
			return false
	elif act_source == "cradle":
		if seat != null:
			return false
	elif act_source == "already_lying":
		var found: Node3D = _resolve_bed(pose, act_source, bed_in)
		if not main.player_beside_bed(found):
			return false
	elif act_source == "bed_side":
		if seat == null:
			return false
		var rest: Variant = body.get("_couch_rest")
		if rest != null and is_instance_valid(rest) and float(rest.get("amount")) < 0.99:
			return false
		var found_bed: Node3D = _resolve_bed(pose, act_source, bed_in)
		if not main.player_beside_bed(found_bed):
			return false
	return true


# --------------------------------------------------------------------------- start

func start(pose: String, bed_in: Variant, act_source: String) -> bool:
	if not can_start(pose, act_source, bed_in):
		_log("start blocked pose=%s legacy=%d source=%s pony=%s" % [pose, CATALOG.legacy_index(pose), act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		return false
	pose_id = pose
	source = act_source
	_profile = SETTINGS.template_for(_id)
	_pose_cfg = SETTINGS.pose(_id, pose_id)
	var preferences_block: Variant = _profile.get("preferences", {})
	_base_preferences = PREFERENCES.defaults()
	if preferences_block is Dictionary:
		var pump_block: Variant = (preferences_block as Dictionary).get("pump", {})
		if pump_block is Dictionary:
			_base_preferences = (pump_block as Dictionary).duplicate(true)
	_act_prompts = _profile.get("act_prompts", {})
	var pump_controls := SETTINGS.pump_controls()
	pump_up = bool(pump_controls.get("up", true))
	_pump_pixels_per_full = float(pump_controls.get("pixels_per_full", 800.0))
	_pump_tracker = PUMP.new()
	_climax_at = int(_profile.get("climax_at", 100))
	_phase_index = PREFERENCES.phase_index(_base_preferences, 0.0)
	_preferences = PREFERENCES.active(_base_preferences, 0.0)
	_aftercare_min = int(_profile.get("aftercare_min", 10))
	_has_facing = false
	bed = _resolve_bed(pose, act_source, bed_in)
	if pose == CATALOG.MISSIONARY and bed == null:
		return false
	_player_pony = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	_applied_lean = 0.0
	_lean = 0.0
	view_depth = 0.0
	_view_velocity = 0.0
	_back = 0.0
	_back_target = 0.0
	var identity: Variant = pony.get("identity")
	_winged = identity != null and identity.has_method("has_wings") and bool(identity.call("has_wings"))
	_apply_eye_override()
	_wing_clock = 0.0
	_wing_flick = 0.0
	_wing_hold_started = false
	_wing_jitter = 0.0
	_wing_jitter_goal = 0.0
	_wing_jitter_clock = 0.0
	_jiggle_logged = false
	_act_seconds = 0.0
	_flutter_clock = randf_range(0.5, 1.5)
	_clear_face()
	_set_face(0.45, 0.45)
	_serial = _next_serial()
	_event_id = "intimacy_%s_%d" % [_id, _serial]
	_started_at = Time.get_unix_time_from_system()
	satisfaction = 0
	stamina = STAMINA_MAX
	_reset_pump_state()
	_schedule_utterances()
	_prepare_vocal()
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()

	if source == "cradle":
		if not _release_carry():
			return false
	elif source == "already_lying":
		if not REST.release_managed(pony):
			return false
	elif source == "bed_side":
		_end_cuddle_session()
		if not REST.release_managed(pony):
			return false
	if not _claim_nav():
		_abort_start()
		return false

	pony.sleeping = false
	pony.set_sim_tier(pony.SimTier.HERO)
	pony.set_meta("sex_active", true)

	if pose == CATALOG.MISSIONARY:
		if source == "cradle":
			_place_cradle(_bed_anchor())
		else:
			if str(pony.posture_status().get("requested", "")) != "lie_down":
				if pony.get("posture") != null:
					pony.posture.impact_flop()
			pony.reset_physics_interpolation()
	else:
		var standing := _standing_transform()
		pony.reset_motion(standing)
		pony.reset_physics_interpolation()
		pony.request_posture("stand")
		_facing_basis = standing.basis
		_has_facing = true
		_glance_left = 0.0
		_glance_back = false
		_glance_sign_set = false
		_glance_head_back = 0.0
		_glance_wait = randf_range(float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)), float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))

	_build_pose()
	_pose1_head_roll = float(_pose_cfg.get("head_roll", 0.0))
	_pose1_free_yaw = 0.0
	_pose1_free_pitch = 0.0
	_pose1_debug_rot = Basis.IDENTITY
	_pose1_basis_logged = false
	_pose1_camera = _pose1_camera_target() if pose == CATALOG.MISSIONARY else Vector3.INF
	if pose == CATALOG.MISSIONARY:
		_snapshot_pose1_start()
		_make_pose1_view()
	_capture_look()
	_lock_player()
	_hide_anon_avatar_for_pose1()
	_start_audio()
	MEMORY.start_event(main.game, _id, _display_name, _event_id)
	state = State.POSING_IN
	_pose_in_left = POSE_IN_SECONDS
	main.set_active(self)
	if is_instance_valid(main.hud):
		main.hud.show_act(self, main.debug_logs)
		main.hud.hide_prompt()
	_log("started pose=%s legacy=%d source=%s pony=%s eye=%.2f" % [pose, CATALOG.legacy_index(pose), act_source, str(pony.name), _camera_target_eye])
	return true


func _next_serial() -> int:
	if is_instance_valid(main) and main.has_method("allocate_serial"):
		return int(main.call("allocate_serial"))
	return 1


func _end_cuddle_session() -> void:
	var session: Node = pony.get_node_or_null("CuddleSession") if is_instance_valid(pony) else null
	if session != null and session.has_method("end"):
		if bool(session.get("enabled")) or float(session.get("blend")) > 0.0:
			session.call("end", true)
	if is_instance_valid(pony) and pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")


func _release_carry() -> bool:
	var reach: Node = main.interactor()
	if not is_instance_valid(reach):
		return false
	if reach.get("held") != pony or reach.get("cradled") != true:
		return false
	pony.end_interaction()
	reach.set("held", null)
	reach.set("cradled", false)
	reach.set("_drop_upright", false)
	reach.set("_laying", -1.0)
	reach.set("_sleepy_kiss", false)
	reach.set("_lean", 0.0)
	reach.set("_lay", {})
	var actions: Variant = reach.get("desktop_actions")
	if is_instance_valid(actions) and actions.has_method("pony_released"):
		actions.call("pony_released")
	return true


func _claim_nav() -> bool:
	_nav = pony.get_node_or_null("Navigator")
	if _nav == null:
		return false
	if str(_nav.get("reserved_by")) != "":
		return false
	_nav_old_wander = bool(_nav.get("wander_enabled"))
	_token = "unfplap:" + _id
	_nav.call("stay")
	_nav.set("command_owner", _token)
	_nav.set("wander_enabled", false)
	return str(_nav.get("command_owner")) == _token


func _keep_nav() -> void:
	if _nav == null or not is_instance_valid(_nav):
		return
	if str(_nav.get("command_owner")) != _token:
		_nav.call("stay")
		_nav.set("command_owner", _token)
		_nav.set("wander_enabled", false)


func _release_nav() -> void:
	if _nav == null or not is_instance_valid(_nav):
		_nav = null
		return
	if str(_nav.get("command_owner")) == _token:
		_nav.set("command_owner", "")
	_nav.set("wander_enabled", true)
	_nav = null


func _lock_player() -> void:
	var body = main.player
	if not is_instance_valid(body):
		return
	# Hold movement with the game's kiss_hold meta, not controls_locked: the camera stays free.
	_had_kiss_hold = body.has_meta("kiss_hold")
	if not _had_kiss_hold:
		body.set_meta("kiss_hold", true)
	# pony_kisser.gd removes kiss_hold every physics tick when no deep kiss is active. Pause its
	# physics for the act so the hold survives while mouse look remains free.
	if is_instance_valid(main) and is_instance_valid(main.game):
		var kisser: Variant = main.game.get("kisser")
		if is_instance_valid(kisser) and kisser is Node:
			_kisser = kisser as Node
			_kisser_processing = _kisser.is_physics_processing()
			if _kisser_processing:
				_kisser.set_physics_process(false)
	_locked_player = true
	if body.get("seat") != null:
		body.set("_q_held", true)


func _unlock_player() -> void:
	if not _locked_player:
		return
	if is_instance_valid(_kisser):
		_kisser.set_physics_process(_kisser_processing)
	_kisser = null
	_kisser_processing = false
	if is_instance_valid(main) and is_instance_valid(main.player):
		if not _had_kiss_hold and main.player.has_meta("kiss_hold"):
			main.player.remove_meta("kiss_hold")
	_locked_player = false


func _abort_start() -> void:
	_cancel_pending_utterance()
	_release_nav()
	_unlock_player()
	_free_pose()
	if is_instance_valid(pony) and pony.has_meta("sex_active"):
		pony.remove_meta("sex_active")
	state = State.IDLE
	if is_instance_valid(main):
		main.clear_active(self)


## Put her in the game's own lie-down state after the teleport. Waiting one physics frame lets
## `grounded()` see the mattress; the native lie animation then settles her into the bedding
## instead of the old immediate impact-flop that left her hovering.
func _place_cradle(anchor: Transform3D) -> void:
	if not is_instance_valid(pony):
		return
	pony.reset_motion(anchor)
	pony.reset_physics_interpolation()
	for _i in 3:
		await get_tree().physics_frame
		if not is_instance_valid(pony) or state == State.IDLE:
			return
		if pony.grounded():
			break
	pony.reset_physics_interpolation()
	if not pony.request_posture("lie_down"):
		if pony.get("posture") != null:
			pony.posture.impact_flop()
	for _i in 240:
		await get_tree().physics_frame
		if not is_instance_valid(pony) or state in [State.IDLE, State.RESTORE]:
			return
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) == "lie_down" and bool(status.get("settled", false)):
			break


func _bed_anchor() -> Transform3D:
	if bed != null:
		var shared: Variant = _shared_bed_rest(bed)
		if shared != null:
			return shared
	var fallback := 0.6
	if bed != null and bed.has_meta("mattress_top"):
		fallback = float(bed.get_meta("mattress_top"))
	var center: Vector3 = bed.global_position if bed != null else pony.global_position
	var top: float = center.y
	if bed != null:
		var points: Array[Vector3] = [bed.to_global(Vector3(0.18, 0.0, 0.0)), bed.to_global(Vector3(-0.18, 0.0, 0.0))]
		top = MATTRESS.visible_top(bed, points, bed.to_global(Vector3(0.0, fallback, 0.0)).y)
		center = Vector3(bed.global_position.x, top, bed.global_position.z)
	var player_at: Vector3 = main.player.global_position
	var side := Vector3.FORWARD
	if bed != null:
		side = bed.global_basis.x
		side.y = 0.0
	if side.length_squared() < 0.0001:
		side = player_at - center
		side.y = 0.0
	side = side.normalized()
	var across := side * signf((player_at - center).dot(side)) * 0.25
	var along: Vector3 = -bed.global_basis.z if bed != null else -main.player.global_basis.z
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = player_at - center
		along.y = 0.0
	along = along.normalized()
	var at: Vector3 = center + across
	at.y = top + 0.02
	return Transform3D(Basis.looking_at(along, Vector3.UP), at)


## The game's own bed-rest place for a pony lying beside Anon. Using it keeps her along the
## mattress (not across it) and on the drawn bedding, instead of the old floating cross-bed pose.
func _shared_bed_rest(bed_node: Node3D) -> Variant:
	if not is_instance_valid(bed_node) or not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group("couches"):
		if not node is Node3D or node.get("bed_node") != bed_node:
			continue
		if not node.has_method("pony_transform"):
			continue
		var seats: Variant = node.get("seats")
		if not seats is Array or (seats as Array).size() < 2:
			continue
		var rest: Variant = node.call("pony_transform", (seats as Array)[1])
		if not rest is Transform3D:
			continue
		var t: Transform3D = rest
		if t.origin.length_squared() < 0.01 or t.origin.distance_to(bed_node.global_position) > 4.0:
			continue
		return t
	return null


func _standing_transform() -> Transform3D:
	var view: Camera3D = main.camera()
	var forward := Vector3.FORWARD
	if view != null:
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -main.player.global_basis.z
	forward = forward.normalized()
	var at: Vector3 = main.player.global_position + forward * _pose2_gap()
	at.y = main.player.global_position.y
	return Transform3D(Basis.looking_at(forward, Vector3.UP), at)


func _pose2_gap() -> float:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return POSE2_GAP_M
	var size := str(settings.call("get_value", "ponies/size"))
	var gaps: Variant = _pose_cfg.get("gaps", POSE2_GAPS)
	var gap := float((gaps as Dictionary).get(size, POSE2_GAP_M)) if gaps is Dictionary else POSE2_GAP_M
	_log("pose2 size=%s gap=%.2f" % [size, gap])
	return gap


func debug_float_pose1(seconds: float) -> void:
	if state != State.IDLE or not is_instance_valid(pony) or _debug_pose_active:
		_log("float pose1: busy")
		return
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		return
	_debug_pose_active = true
	_debug_pose_saved = pony.global_transform
	pony.global_position.y += 0.45
	pony.reset_physics_interpolation()
	_debug_pose = POSE.new()
	_debug_pose.name = "UnfplapDebugPose1"
	_debug_pose.set("mare", pony)
	_debug_pose.set("mode", "pose1")
	_debug_pose.set("amount", 0.0)
	_debug_pose.set("target_amount", 1.0)
	_debug_pose.set("look_point", main.camera().global_position if main.camera() != null else pony.global_position)
	(skeleton as Skeleton3D).add_child(_debug_pose)
	_log("float pose1 pony=%s seconds=%.1f" % [str(pony.name), seconds])
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(pony) and _debug_pose_active:
		pony.global_transform = _debug_pose_saved
		pony.reset_physics_interpolation()
	if is_instance_valid(_debug_pose):
		_debug_pose.queue_free()
	_debug_pose = null
	_debug_pose_active = false


func _build_pose() -> void:
	_free_pose()
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_pose = POSE.new()
		_pose.name = "UnfplapPose"
		_pose.mare = pony
		_pose.mode = "pose2" if pose_id == CATALOG.HORSE else "pose1"
		_pose.pose_config = SETTINGS.pose(_id, pose_id)
		_pose.head_roll = _pose1_head_roll
		_pose.look_point = main.camera().global_position if main.camera() != null else pony.global_position
		_pose.amount = 0.0
		_pose.target_amount = 1.0
		(skeleton as Skeleton3D).add_child(_pose)
	if pose_id != CATALOG.HORSE:
		return
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_tail = TAIL.new()
		_tail.name = "UnfplapTail"
		_tail.mare = pony
		_tail.aside_angle = float(_pose_cfg.get("tail_aside", 0.55))
		_tail.lift_angle = float(_pose_cfg.get("tail_lift", 0.34))
		_tail.amount = 0.0
		_tail.target_amount = 1.0
		_tail.call("choose_side")
		(hair as Skeleton3D).add_child(_tail)


func _free_pose() -> void:
	if is_instance_valid(_pose):
		_pose.queue_free()
	_pose = null
	if is_instance_valid(_tail):
		_tail.queue_free()
	_tail = null


# --------------------------------------------------------------------------- pump

func _now_s() -> float:
	return Time.get_ticks_msec() * 0.001


func _reset_pump_state() -> void:
	depth = 0.0
	_satisfaction_frac = 0.0
	_speed_zone = "ok"
	_speed_zone_previous = "ok"
	_stroke_speed = 0.0
	_stroke_shape = ""
	_speed_zone_strokes = 0
	_last_reaction.clear()
	_depth_out_seconds = 0.0
	_utterance_points.clear()
	_utterance_index = 0
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	_utterance_serial = 0
	_vocal_cooldown = 0.0
	_bored_seconds = 0.0
	_speed_travel = 0.0
	view_depth = 0.0
	_view_velocity = 0.0
	if _pump_tracker == null:
		_pump_tracker = PUMP.new()
	_pump_tracker.reset()


func _schedule_utterances() -> void:
	_utterance_rng.randomize()
	var low := clampi(int(_profile.get("min_utterances", 2)), 0, 8)
	var high := clampi(int(_profile.get("max_utterances", 5)), 0, 8)
	var count := UTTERANCE.line_count(low, high, _utterance_rng)
	_utterance_points = UTTERANCE.schedule(_climax_at, count, int(_utterance_rng.randi()))
	if count > 0:
		_log("utterances=%d points=%s" % [count, str(_utterance_points)])


func _prepare_vocal() -> void:
	var director := _director()
	if director == null:
		return
	var vocal: Variant = director.get("vocal")
	if vocal != null and vocal.has_method("prepare"):
		vocal.call("prepare", _id)


func _director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


func _depth_weight(value: float) -> float:
	return PREFERENCES.depth_weight(_preferences, value)


func _pump_move(amount: float, now: float) -> void:
	if _pump_tracker == null:
		return
	var before := depth
	var events: Array = _pump_tracker.move(amount, now, _depth_weight)
	depth = _pump_tracker.depth
	_speed_travel += absf(depth - before)
	for event: Dictionary in events:
		_on_stroke(event)


func _pump_tick() -> void:
	if _pump_tracker == null:
		return
	var events: Array = _pump_tracker.tick(_now_s())
	depth = _pump_tracker.depth
	for event: Dictionary in events:
		_on_stroke(event)
	_depth_tick(get_physics_process_delta_time())


func _on_stroke(event: Dictionary) -> void:
	if state != State.ACTIVE:
		return
	var direction := int(event.get("direction", 0))
	var travel := float(event.get("travel", 0.0))
	var speed := float(event.get("speed", 0.0))
	var shape := PREFERENCES.MIXED
	if direction > 0:
		var shape_cfg: Dictionary = _preferences.get("shape", {})
		if bool(shape_cfg.get("enabled", false)):
			var samples: PackedVector2Array = event.get("samples", PackedVector2Array())
			var classified := PREFERENCES.classify_shape(
				samples,
				float(shape_cfg.get("min_travel", 0.30)),
				float(shape_cfg.get("max_rmse", 0.18)))
			shape = str(classified.get("shape", PREFERENCES.MIXED))
		_stroke_shape = shape
		_stroke_speed = speed
		_speed_zone = PREFERENCES.speed_zone(_preferences, speed)
	var multiplier := 1.0
	if direction > 0:
		multiplier = PREFERENCES.multiplier(_preferences, _speed_zone, shape)
	if bool(event.get("pump", false)):
		_on_pump()
	_add_satisfaction(float(event.get("base_gain", 0.0)) * multiplier)
	if direction > 0:
		_note_speed(_speed_zone)
		_note_shape(shape)
	_log("stroke dir=%d travel=%.2f speed=%.2f shape=%s zone=%s gain=%.2f satisfaction=%d" % [
		direction, travel, speed, shape, _speed_zone,
		float(event.get("base_gain", 0.0)) * multiplier, satisfaction])
	if state == State.ACTIVE and satisfaction >= _climax_at:
		_climax()


func _on_pump() -> void:
	stamina = maxi(0, stamina - 1)
	_wing_flick = 0.18
	if _winged and not _wing_hold:
		var excitement: Variant = pony.get("excitement")
		if excitement != null and excitement.has_method("flutter"):
			excitement.call("flutter")
	_pump_jiggle()
	var now := _now_s()
	_pump_times.append(now)
	while not _pump_times.is_empty() and now - float(_pump_times[0]) > 1.0:
		_pump_times.pop_front()
	_play_kiss()
	_play_vocal()
	if satisfaction == 0 or satisfaction % 10 == 0:
		_log("pump satisfaction=%d stamina=%d rate=%.1f/s" % [satisfaction, stamina, _pumps_per_second()])


func _play_vocal() -> void:
	if _vocal_cooldown > 0.0:
		return
	var director := _director()
	if director == null or str(director.get("state")) != "idle" or not is_instance_valid(pony):
		return
	var vocal: Variant = director.get("vocal")
	if vocal != null and vocal.has_method("play"):
		if bool(vocal.call("play", _id, "m", pony, -34.0)):
			_vocal_cooldown = 3.0


func _add_satisfaction(amount: float) -> void:
	if amount <= 0.0:
		return
	_satisfaction_frac += amount
	if _satisfaction_frac < 1.0:
		return
	var whole := int(floor(_satisfaction_frac))
	var before := satisfaction
	satisfaction = mini(SATISFACTION_MAX, satisfaction + whole)
	_satisfaction_frac -= float(whole)
	if satisfaction != before and (satisfaction == 1 or satisfaction % 10 == 0):
		_log("satisfaction=%d stamina=%d rate=%.1f/s" % [satisfaction, stamina, _pumps_per_second()])


func _note_speed(zone: String) -> void:
	var cfg: Dictionary = _preferences.get("speed", {})
	if not bool(cfg.get("enabled", false)):
		return
	if zone != _speed_zone_previous:
		_speed_zone_previous = zone
		_speed_zone_strokes = 1
	else:
		_speed_zone_strokes += 1
	if zone == "perfect" and _speed_zone_strokes >= 2 and _reaction_ready("speed_perfect", 12.0):
		_queue_utterance("speed_perfect", "speed_perfect", "speed_perfect")
	elif zone == "slow" and _speed_zone_strokes >= 3 and _reaction_ready("speed_slow", 10.0):
		_queue_utterance("speed_slow", "speed_slow", "speed_slow")
	elif zone == "fast" and _speed_zone_strokes >= 3 and _reaction_ready("speed_fast", 8.0):
		_queue_utterance("speed_fast", "speed_fast", "speed_fast")


func _note_shape(shape: String) -> void:
	if shape == PREFERENCES.MIXED or shape.is_empty():
		return
	var cfg: Dictionary = _preferences.get("shape", {})
	if not bool(cfg.get("enabled", false)):
		return
	if shape == str(cfg.get("likes", "")) and _reaction_ready("shape_like", 12.0):
		_queue_utterance("shape_like", "shape_like", "shape_like")
	elif shape == str(cfg.get("dislikes", "")) and _reaction_ready("shape_dislike", 10.0):
		_queue_utterance("shape_dislike", "shape_dislike", "shape_dislike")


func _depth_tick(delta: float) -> void:
	if state != State.ACTIVE:
		return
	var band := PREFERENCES.comfort_band(_preferences)
	if band.x < 0.0:
		return
	if depth < band.x or depth > band.y:
		_depth_out_seconds += delta
	else:
		_depth_out_seconds = 0.0
	if _depth_out_seconds < 1.2:
		return
	var kind := "depth_shallow" if depth < band.x else "depth_deep"
	if _reaction_ready(kind, 12.0):
		_queue_utterance(kind, kind, kind)


func _reaction_ready(kind: String, cooldown: float) -> bool:
	if not _utterance_pending_key.is_empty():
		return false
	var now := _now_s()
	if now - float(_last_reaction.get(kind, -1000.0)) < cooldown:
		return false
	_last_reaction[kind] = now
	return true


func _update_phase() -> void:
	var progress := clampf(float(satisfaction) / maxf(1.0, float(_climax_at)), 0.0, 1.0)
	var index := PREFERENCES.phase_index(_base_preferences, progress)
	if index == _phase_index:
		return
	_phase_index = index
	_preferences = PREFERENCES.active(_base_preferences, progress)
	_log("preference phase=%d progress=%.2f %s" % [index, progress, PREFERENCES.describe(_preferences).replace("\n", "; ")])


func _boredom_tick(delta: float) -> void:
	_speed_travel *= maxf(0.0, 1.0 - delta / 1.5)
	var speed_cfg: Dictionary = _preferences.get("speed", {})
	var min_speed := float(speed_cfg.get("min", 0.001))
	if not bool(speed_cfg.get("enabled", true)) or min_speed <= 0.0:
		_bored_seconds = 0.0
		return
	var director := _director()
	if director != null and str(director.get("state")) != "idle":
		return
	var effective := _speed_travel / 1.5
	if effective < min_speed * 0.9:
		_bored_seconds += delta
	elif effective > min_speed * 1.2:
		_bored_seconds = 0.0
	if _bored_seconds < 10.0:
		return
	if not _reaction_ready("bored", 25.0):
		return
	_log("bored effective=%.3f min=%.3f" % [effective, min_speed])
	_bored_seconds = 0.0
	_queue_utterance("bored", "bored", "bored")


func _utterance_tick() -> void:
	if state != State.ACTIVE:
		return
	if not _utterance_pending_key.is_empty():
		if _now_s() > _utterance_pending_until:
			_cancel_pending_utterance()
		else:
			# A line is already in flight. Do not build a backlog: accept that these points are
			# skipped and advance past them.
			while _utterance_index < _utterance_points.size() \
					and float(satisfaction) + _satisfaction_frac >= _utterance_points[_utterance_index]:
				_log("utterance skipped point=%d pending" % _utterance_index)
				_utterance_index += 1
			return
	while _utterance_index < _utterance_points.size() \
			and float(satisfaction) + _satisfaction_frac >= _utterance_points[_utterance_index]:
		var point := _utterance_index
		_utterance_index += 1
		_queue_utterance("scheduled", "utterance", "point_%d" % point)
		if not _utterance_pending_key.is_empty():
			return


func _queue_utterance(kind: String, prompt_key: String, key_suffix: String) -> void:
	if state != State.ACTIVE or not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	if not _utterance_pending_key.is_empty():
		return
	var template := str(_act_prompts.get(prompt_key, ""))
	if template.strip_edges().is_empty():
		template = str(_act_prompts.get("utterance", ""))
	if template.strip_edges().is_empty():
		_log("utterance missing prompt kind=%s" % kind)
		return
	var values := {
		"state": UTTERANCE.state_line(pose_id, satisfaction, _climax_at, depth, _stroke_speed, _speed_zone, _stroke_shape, _act_seconds),
		"preferences": PREFERENCES.describe(_preferences),
		"recent": _recent_lines(),
	}
	var purpose := UTTERANCE.format(template, values)
	_utterance_serial += 1
	var key := "%s:%d" % [key_suffix, _utterance_serial]
	var event_id := _event_id
	var expiry := _now_s() + 10.0
	var valid := func() -> bool:
		return is_instance_valid(pony) and state == State.ACTIVE \
			and _event_id == event_id and _now_s() < expiry
	var finished := func() -> void:
		_utterance_done(key)
	var queued := MEMORY.utterance_for(main.game, _id, event_id, key, purpose, valid, finished)
	if not queued:
		_log("utterance queue failed kind=%s" % kind)
		return
	_utterance_pending_key = key
	_utterance_pending_until = _now_s() + 10.0
	_log("utterance kind=%s key=%s" % [kind, key])


func _utterance_done(key: String) -> void:
	if _utterance_pending_key == key:
		_utterance_pending_key = ""
		_utterance_pending_until = 0.0


func _cancel_pending_utterance() -> void:
	if _utterance_pending_key.is_empty():
		return
	var key := _utterance_pending_key
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	if is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.cancel_generated(main.game, _event_id, key)


func _recent_lines() -> String:
	var director := _director()
	if director == null or not is_instance_valid(pony):
		return ""
	var characters: Variant = director.get("characters")
	if not characters is Dictionary or not (characters as Dictionary).has(_id):
		return ""
	var entry: Variant = (characters as Dictionary)[_id]
	if not entry is Dictionary:
		return ""
	var spoken: Variant = (entry as Dictionary).get("spoken", [])
	if not spoken is Array or (spoken as Array).is_empty():
		return ""
	var recent: Array[String] = []
	var start := maxi(0, (spoken as Array).size() - 2)
	for index in range(start, (spoken as Array).size()):
		recent.append(str((spoken as Array)[index]))
	return " | ".join(recent)


func _pump_jiggle() -> void:
	if not is_instance_valid(pony):
		return
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank) or not _flank.has_method("_start_jiggle"):
		return
	if _flank.has_method("wake_tick"):
		_flank.call("wake_tick")
	var marks: Variant = _flank.get("marks")
	if not marks is Array or (marks as Array).size() < 2:
		return
	# One shader center on the rump midline so both flanks wobble together. The native FlankTouch
	# supports only one jiggle at a time, so this replaces the old left/right alternation.
	var mark: Variant = (marks as Array)[0]
	if not mark is Decal:
		return
	var back: Vector3 = pony.global_basis.z.normalized()
	var normal := back
	if normal.length_squared() < 0.001:
		return
	var at: Vector3 = pony.global_position + Vector3.UP * JIGGLE_HEIGHT + back * JIGGLE_BACK
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		var skeleton := sk as Skeleton3D
		var left := skeleton.find_bone("pony_femur_L")
		var right := skeleton.find_bone("pony_femur_R")
		if left >= 0 and right >= 0:
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
			at = (a + b) * 0.5 + Vector3.UP * 0.08 + back * 0.10
	var across := Vector3.UP.cross(normal).normalized()
	if across.length_squared() < 0.5:
		across = Vector3.RIGHT
	var decal := mark as Decal
	decal.global_transform = Transform3D(Basis(across, normal, across.cross(normal)).orthonormalized(), at + normal * 0.015)
	decal.visible = false
	_flank.call("_start_jiggle", 0, JIGGLE_STRENGTH)
	# Only one shader center now covers both flanks, so double the wobble amount. `_start_jiggle`
	# clamps strength to 1.0, so scale its resolved amount directly instead.
	var amount: Variant = _flank.get("_jiggle_amount")
	if amount != null:
		_flank.set("_jiggle_amount", float(amount) * 3.5)
	if not _jiggle_logged:
		_jiggle_logged = true
		var targets: Variant = _flank.get("_jiggle_targets")
		_log("jiggle rump at=%s root=%s normal=%s targets=%d" % [
			str(at), str(pony.global_position), str(normal),
			(targets as Array).size() if targets is Array else -1])


func cancel() -> void:
	_log("cancel state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE]:
		MEMORY.cancel_event(main.game, _id, _display_name, _event_id)
		var expiry := Time.get_ticks_msec() + 60000
		var valid := func() -> bool:
			return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
		MEMORY.reaction_for(main.game, _id, "end_early", _event_id,
			"Anon stopped before you reached climax. Say one short sentence, at most 12 words, in your own voice. Saying nothing is fine.",
			valid)
		_restore_begin()
	elif state == State.AFTERGLOW:
		end_afterglow()


func end_afterglow() -> void:
	if state == State.AFTERGLOW:
		_log("afterglow end pony=%s" % str(pony.name))
		_restore_begin()


func _climax() -> void:
	if state != State.ACTIVE:
		return
	_log("climax pose=%s legacy=%d pony=%s satisfaction=%d" % [pose_id, CATALOG.legacy_index(pose_id), str(pony.name), satisfaction])
	_cancel_pending_utterance()
	state = State.CLIMAX
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0
	_set_face(0.3, 0.0)
	var expiry := Time.get_ticks_msec() + 60000
	var valid := func() -> bool:
		return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
	MEMORY.reaction_for(main.game, _id, "climax", _event_id,
		"You have just climaxed during intimacy with Anon. Say one short sentence, at most 12 words, in your own voice. Staying quiet is fine. Do not describe anatomy.",
		valid)
	_play_climax()
	if is_instance_valid(main.hud):
		main.hud.set_state("CLIMAX")


func _finish_climax() -> void:
	MEMORY.climax_event(main.game, _id, _display_name, _event_id)
	MEMORY.commit_climax(main.game, _id, _display_name, _event_id)
	WITNESS.commit(main.game, _id, _display_name, _serial, pony)
	if pose_id == CATALOG.HORSE:
		_pose2_withdraw_begin()
	else:
		_afterglow_begin()


## Pose 2 has no cuddle afterglow: the climax pose holds for a short withdrawal while Anon eases
## back and her tail flicks, then the act restores on its own.
func _pose2_withdraw_begin() -> void:
	_log("withdraw pose=%s legacy=%d pony=%s" % [pose_id, CATALOG.legacy_index(pose_id), str(pony.name)])
	state = State.WITHDRAW
	_withdraw_left = float(_pose_cfg.get("withdraw_seconds", POSE2_WITHDRAW_SECONDS))
	_back_target = AFTERGLOW_BACK_M
	_set_face(0.7, 0.55, 12.0)
	if is_instance_valid(_tail):
		_tail.target_amount = 0.55
		_tail.call("flick", 2)
	_inside_aftermath()
	if is_instance_valid(main.hud):
		main.hud.hide_act()


func _afterglow_begin() -> void:
	_log("afterglow pose=%s legacy=%d pony=%s" % [pose_id, CATALOG.legacy_index(pose_id), str(pony.name)])
	_cancel_pending_utterance()
	state = State.AFTERGLOW
	_afterglow_pose = pose_id
	_set_face(0.85, 0.9)
	if is_instance_valid(_pose):
		_pose.mode = "afterglow"
		_pose.afterglow_pose = pose_id
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.35
	if is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")


## Pose 2 only: tell her Anon came inside her, then optionally invite a spoken reaction.
func _inside_aftermath() -> void:
	MEMORY.inside_event(main.game, _id, _display_name, _event_id)
	var expiry := Time.get_ticks_msec() + 60000
	var valid := func() -> bool:
		return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
	MEMORY.inside_response(main.game, _id, _event_id, valid)


func _restore_begin() -> void:
	if state == State.IDLE or state == State.RESTORE:
		return
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	_cancel_pending_utterance()
	var from_state := state
	state = State.RESTORE
	_restore_left = RESTORE_SECONDS
	if not (pose_id == CATALOG.HORSE and from_state == State.WITHDRAW):
		_clear_face()
	_release_wing_hold()
	if is_instance_valid(_pose):
		_pose.target_amount = 0.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.0
	_stop_breath()
	_back_target = 0.0
	_has_facing = false
	_glance_left = 0.0
	if is_instance_valid(main.hud):
		main.hud.hide_act()


func _finish_restore() -> void:
	if not is_instance_valid(pony):
		_log("restore finished with invalid pony")
		state = State.IDLE
		return
	var was_pose := pose_id
	_log("restore finished pony=%s" % str(pony.name))
	_unlock_player()
	_restore_camera()
	pony.remove_meta("sex_active")
	_release_nav()
	_restore_look()
	if was_pose == CATALOG.MISSIONARY:
		_resume_pose1_cuddle()
	elif pony.get("posture") != null:
		pony.request_posture("stand")
	_free_pose()
	_stop_audio()
	if is_instance_valid(main.hud):
		main.hud.hide_all()
	if is_instance_valid(main):
		main.clear_active(self)
	state = State.IDLE
	pose_id = ""
	source = ""
	bed = null
	_reset_after_act()


## Pose 1 ended early (Q): hand her back to the stock bed cuddle instead of leaving Anon posed
## over her. Re-invites her onto the couch/bed through the seat's couch so cuddle/player_input
## can start its session again.
func _resume_pose1_cuddle() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) or not is_instance_valid(main.player):
		_stand_after_pose()
		return
	# Revert the exact scene captured at start: camera, player and pony transforms.
	if _pose1_start_saved:
		# Player/pony first, camera last: setting the player yaw rotates a child camera, so the
		# snapshot camera transform must be applied after the rig is back in place.
		main.player.global_transform = _pose1_start_player_transform
		pony.global_transform = _pose1_start_pony_transform
		pony.reset_physics_interpolation()
		if is_instance_valid(_pose1_start_camera):
			_pose1_start_camera.global_transform = _pose1_start_camera_transform
			_pose1_start_camera.make_current()
		_log("pose1 restore: snapshot camera=%s player=%s pony=%s player_yaw=%.3f" % [
			str(_pose1_start_camera_transform.origin), str(_pose1_start_player_transform.origin),
			str(_pose1_start_pony_transform.origin),
			float(main.player.rotation.y)])
	var seat: Variant = main.player.get("seat")
	var couch: Variant = null
	if is_instance_valid(seat) and seat.has_meta("couch"):
		couch = seat.get_meta("couch")
	if is_instance_valid(couch) and couch.has_method("accept") and bool(couch.call("accept", pony)):
		_log("pose1 restore: cuddle resumed")
		return
	_log("pose1 restore: cuddle resume failed; restoring posture")
	if _pose1_start_saved and _pose1_start_pony_posture != "":
		pony.request_posture(_pose1_start_pony_posture)
	else:
		_stand_after_pose()


func _stand_after_pose() -> void:
	if is_instance_valid(pony) and pony.get("posture") != null:
		pony.request_posture("stand")


func force_stop() -> void:
	if state == State.IDLE:
		return
	_restore_now()


func _restore_now() -> void:
	_cancel_pending_utterance()
	if is_instance_valid(pony):
		_clear_face()
		_release_wing_hold()
		_unlock_player()
		_restore_camera()
		pony.remove_meta("sex_active")
		if pony.get("posture") != null:
			pony.request_posture("stand")
		_restore_look()
		_release_nav()
	_free_pose()
	_stop_audio()
	if is_instance_valid(main):
		main.clear_active(self)
		if is_instance_valid(main.hud):
			main.hud.hide_all()
	state = State.IDLE
	pose_id = ""
	source = ""
	bed = null
	_reset_after_act()


func _reset_after_act() -> void:
	if not is_inside_tree():
		return
	_reset_pump_state()
	stamina = STAMINA_MAX
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()
	var from := float(satisfaction)
	_satisfaction_tween = create_tween()
	_satisfaction_tween.tween_method(func(value: float) -> void: satisfaction = int(round(value)), from, 0.0, 30.0)
	_begin_aftercare()


func _begin_aftercare() -> void:
	if not is_inside_tree() or not is_instance_valid(pony):
		return
	if is_instance_valid(_aftercare):
		return
	_aftercare = AFTERCARE.new()
	_aftercare.set("pony", pony)
	_aftercare.set("runtime", self)
	_aftercare.set("body_language", satisfaction >= _aftercare_min)
	add_child(_aftercare)


# --------------------------------------------------------------------------- checks

func _check_running() -> void:
	if not is_instance_valid(pony):
		force_stop()
		return
	if state == State.ACTIVE or state == State.POSING_IN:
		if not _still_willing():
			_stop("unwilling")
			return
	if pony.is_held():
		_stop("picked up")
		return
	if not _conversation_ok():
		_stop("interrupted")
		return
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and not str(affection.get("kind")).is_empty():
		_stop("interrupted")
		return
	if _cuddle_active():
		_stop("interrupted")
		return
	if _nav != null and is_instance_valid(_nav) and str(_nav.get("reserved_by")) != "":
		_stop("interrupted")
		return
	if pose_id == CATALOG.MISSIONARY and bed != null and main.bed_occupied(bed, pony):
		_stop("interrupted")
		return
	if _player_pony != PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())):
		_stop("form change")
		return


func _still_willing() -> bool:
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return false
	if not _conversation_ok():
		return false
	return bool(runtime.bonds.welcomes(_id, "kiss"))


func _stop(reason: String) -> void:
	_log("stop reason=%s state=%d pony=%s" % [reason, state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE]:
		MEMORY.stop_event(main.game, _id, _display_name, _event_id, reason)
	_restore_begin()


# --------------------------------------------------------------------------- camera

func _size_scale() -> float:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return 1.0
	var size := str(settings.call("get_value", "ponies/size"))
	match size:
		"mounting":
			return 0.80
		"hoers":
			return 1.10
		"canon":
			return 0.66
	return 1.0


func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return 0.0
	var fallback := float(bed.get_meta("mattress_top", 0.6)) + bed.global_position.y
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


## Change the player's own eye height for the act instead of writing camera.position.y. That keeps
## `desktop_player._set_eye_y` as the single owner of the camera height and avoids drift/teleports.
func _hide_anon_avatar_for_pose1() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node3D = main.player.find_child("CouchAnonBody", true, false) as Node3D
	if body == null:
		body = main.player.find_child("AnonBody", true, false) as Node3D
	if body == null:
		for node: Node in main.player.find_children("*AnonBody*", "", true, false):
			if node is Node3D:
				body = node as Node3D
				break
	if body == null:
		return
	_anon_avatar = body
	_anon_avatar_visible = body.visible
	# The first-person camera is the all-fours presentation; hide the reclining body so it does
	# not appear standing over the pony.
	body.visible = false


func _restore_anon_avatar() -> void:
	if is_instance_valid(_anon_avatar):
		_anon_avatar.visible = _anon_avatar_visible
	_anon_avatar = null


## Remember the exact scene at pose-1 start so ending early can revert to it.
func _snapshot_pose1_start() -> void:
	_pose1_start_camera = get_viewport().get_camera_3d() if get_viewport() != null else null
	if is_instance_valid(_pose1_start_camera):
		_pose1_start_camera_transform = _pose1_start_camera.global_transform
	if is_instance_valid(main) and is_instance_valid(main.player):
		_pose1_start_player_transform = main.player.global_transform
	if is_instance_valid(pony):
		_pose1_start_pony_transform = pony.global_transform
		if pony.has_method("posture_status"):
			var status: Variant = pony.call("posture_status")
			if status is Dictionary:
				_pose1_start_pony_posture = str((status as Dictionary).get("requested", ""))
	_pose1_start_saved = true
	_log("pose1 snapshot camera=%s player=%s pony=%s posture=%s player_yaw=%.3f" % [
		str(_pose1_start_camera_transform.origin), str(_pose1_start_player_transform.origin),
		str(_pose1_start_pony_transform.origin), _pose1_start_pony_posture,
		_pose1_start_player_transform.basis.get_euler().y])


func _make_pose1_view() -> void:
	if _player_pony or not is_instance_valid(pony):
		return
	if is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view")):
		return
	_pose1_prev_camera = get_viewport().get_camera_3d() if get_viewport() != null else null
	_pose1_view = Camera3D.new()
	_pose1_view.name = "UnfplapPose1View"
	_pose1_view.top_level = true
	_pose1_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var source: Camera3D = main.camera() if is_instance_valid(main) else null
	if is_instance_valid(source):
		if not _pose1_player_rot_saved:
			_pose1_player_rotation = source.rotation
			_pose1_player_rot_saved = true
		_pose1_view.fov = source.fov
		_pose1_view.near = source.near
		_pose1_view.far = source.far
		_pose1_view.cull_mask = source.cull_mask
	# The pose-1 view aims itself at her face every frame (`apply_camera_motion`); the player look
	# controls are left alone so the bed/seated camera is not disturbed.
	_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
	_pose1_aim_until = Time.get_ticks_msec() + 1000
	pony.add_child(_pose1_view)
	_pose1_view.current = true
	_pose1_log_setup()


func _pose1_log_setup() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) or not bool(main.get("debug_logs")):
		return
	var seat: Variant = main.player.get("seat") if is_instance_valid(main.player) else null
	var rest: Variant = main.player.get("_couch_rest") if is_instance_valid(main.player) else null
	_log("pose1 setup pony=%s pos=%s anchor=%s camera=%s bed=%s bed_top=%.2f seat=%s rest=%.2f" % [
		str(pony.name), str(pony.global_position), str(_pose1_camera),
		source,
		str(bed.name) if is_instance_valid(bed) else "null", _bed_surface_top(),
		str(seat.name) if is_instance_valid(seat) else "null",
		float(rest.get("amount")) if is_instance_valid(rest) else -1.0])


func _free_pose1_view() -> void:
	if is_instance_valid(_pose1_view):
		_pose1_view.queue_free()
	_pose1_view = null
	if is_instance_valid(_pose1_prev_camera):
		_pose1_prev_camera.make_current()
	_pose1_prev_camera = null
	if is_instance_valid(main) and is_instance_valid(main.player):
		var source: Camera3D = main.camera() if is_instance_valid(main) else null
		if _pose1_player_rot_saved and is_instance_valid(source):
			source.rotation = _pose1_player_rotation
	_pose1_player_rot_saved = false


## Stable pose-1 camera target: a point ahead of the root at chest/neck height. The live nose
## (`listen_point`) moves as she aims/nuzzles and could end up behind the camera, which made the
## camera look backwards at her rump. This point only depends on her body transform.
func _pose1_look_target() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var forward: Vector3 = -pony.global_basis.z.normalized()
	return pony.global_position + forward * 0.20 + Vector3.UP * 0.10


## The fixed pose-1 view orientation: from the camera anchor toward her face. Computed once so the
## camera does not track the snout while she nuzzles; bob only moves its position.
func _pose1_aim_basis(from_position: Vector3) -> Basis:
	var look := _pose1_look_target()
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


func _pose1_camera_target() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var root: Vector3 = pony.global_position
	var back: Vector3 = pony.global_basis.z.normalized()
	# Move toward her head/neck (forward is -back) so the camera is not centred over her body.
	var target := root + Vector3.UP * float(_pose_cfg.get("camera_height", POSE1_CAMERA_HEIGHT_M)) - back * float(_pose_cfg.get("camera_forward", POSE1_CAMERA_FORWARD_M))
	var bed_top := _bed_surface_top()
	if is_finite(bed_top) and bed_top <= root.y + 2.0:
		target.y = maxf(target.y, bed_top + 0.30)
	target.y = clampf(target.y, root.y + 0.30, root.y + 1.50)
	return target


func _apply_eye_override() -> void:
	_camera_target_eye = 0.0
	# Pose 1 is owned by the game's bed rest/seat camera. Do not fight it with eye-height edits.
	if pose_id == CATALOG.MISSIONARY or _player_pony:
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Variant = main.player
	if body.get("_stand_eye") == null or body.get("seat") != null:
		return
	var base := _player_eye_height()
	var target := base * _size_scale()
	_camera_target_eye = target
	if absf(target - base) < 0.001:
		return
	if not _eye_override:
		_saved_stand_eye = float(body.get("_stand_eye"))
		_saved_eye_height = float(body.get("_eye_height"))
		_eye_override = true
	body.set("_stand_eye", target)
	body.set("_eye_height", target)
	if body.has_method("_set_eye_y"):
		body.call("_set_eye_y", target)
	_log("eye override standing base=%.2f target=%.2f" % [base, target])


func _restore_eye_override() -> void:
	if not _eye_override:
		return
	_eye_override = false
	var body: Variant = main.player if is_instance_valid(main) else null
	if not is_instance_valid(body):
		return
	if body.get("_stand_eye") != null:
		body.set("_stand_eye", _saved_stand_eye)
	if body.get("_eye_height") != null:
		body.set("_eye_height", _saved_eye_height)
	if body.has_method("_set_eye_y"):
		body.call("_set_eye_y", _saved_stand_eye)


func apply_camera_motion() -> void:
	if state == State.IDLE:
		return
	if is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view")):
		return
	if not is_instance_valid(_camera):
		_camera = main.camera() if is_instance_valid(main) else null
	if not is_instance_valid(_camera):
		return
	if pose_id == CATALOG.MISSIONARY:
		if not is_instance_valid(pony):
			return
		var bed_top := _bed_surface_top()
		if not _pose1_camera.is_finite() or _pose1_camera.distance_to(pony.global_position) > 3.0 \
				or (is_finite(bed_top) and _pose1_camera.y < bed_top - 0.05):
			_pose1_camera = _pose1_camera_target()
		if not _pose1_camera.is_finite():
			return
		if is_finite(bed_top) and bed_top <= pony.global_position.y + 2.0 and _pose1_camera.y < bed_top + 0.15:
			_pose1_camera.y = bed_top + 0.30
		_pose1_camera.y = clampf(_pose1_camera.y, pony.global_position.y + 0.30, pony.global_position.y + 1.50)
		if not is_instance_valid(_pose1_view):
			_make_pose1_view()
		if not is_instance_valid(_pose1_view):
			return
		_pose1_view.global_position = _pose1_camera
		_pose1_view.global_position -= _pose1_view_basis.z * (_lean - _back)
		# Track the face for the first second (while the pose blends in), then freeze the
		# orientation so the camera is not locked to her snout while she nuzzles.
		if Time.get_ticks_msec() < _pose1_aim_until:
			_pose1_view_basis = _pose1_aim_basis(_pose1_view.global_position)
		var free := Basis.from_euler(Vector3(_pose1_free_pitch, _pose1_free_yaw, 0.0))
		_pose1_view.global_basis = _pose1_debug_rot * _pose1_camera_tweak() * (_pose1_view_basis * free)
		if not _pose1_basis_logged:
			_pose1_basis_logged = true
			_log("pose1 camera base_euler=%s tweak_euler=%s applied_basis=%s" % [
				str(_pose1_view_basis.get_euler()), str(_pose1_camera_tweak().get_euler()),
				str(_pose1_view.global_basis)])
		return
	_set_camera_offsets(_lean - _back)


## Baseline correction copied EXACTLY from the last logged debug `total_basis` (the user's final
## pressed state), not reconstructed from Euler angles. Change or clear this if re-tuned.
func _pose1_camera_tweak() -> Basis:
	return Basis.IDENTITY


## DEBUG: adjust the pose-1 head roll around her forward axis (Alt+1/2) and log it.
func debug_roll_pose1_head(direction: float) -> void:
	if pose_id != CATALOG.MISSIONARY or state == State.IDLE:
		_log("pose1 head roll ignored pose=%s state=%d" % [pose_id, state])
		return
	_pose1_head_roll += direction * deg_to_rad(5.0)
	if is_instance_valid(_pose):
		_pose.set("head_roll", _pose1_head_roll)
	_log("pose1 head roll %.1f°" % rad_to_deg(_pose1_head_roll))


## DEBUG: rotate the pose-1 camera in world axes so the correct roll/orientation can be found
## interactively (Ctrl+1..6 in input.gd). Logs the axis, step and accumulated rotation.
func debug_rotate_pose1(axis_index: int) -> void:
	if pose_id != CATALOG.MISSIONARY or state == State.IDLE:
		_log("pose1 rotate ignored pose=%s state=%d" % [pose_id, state])
		return
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var names: Array[String] = ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	var index := clampi(axis_index, 0, axes.size() - 1)
	var step := deg_to_rad(5.0)
	_pose1_debug_rot = Basis(axes[index], step) * _pose1_debug_rot
	_log("pose1 camera rotate %s 5° total_euler=%s total_basis=%s base_basis=%s" % [
		names[index], str(_pose1_debug_rot.get_euler()), str(_pose1_debug_rot), str(_pose1_view_basis)])


func _player_eye_height() -> float:
	var body: Variant = main.player if is_instance_valid(main) else null
	if is_instance_valid(body) and body.has_method("eye_height"):
		return float(body.call("eye_height"))
	if is_instance_valid(body) and body.get("_stand_eye") != null:
		return float(body.get("_stand_eye"))
	return 1.6


## Desktop human camera: only the forward/back lean moves the camera. The artificial vertical
## bob is gone; the player's look owns the pitch.
func _set_camera_offsets(forward: float) -> void:
	if not is_instance_valid(_camera):
		return
	var df := forward - _applied_lean
	var seated := is_instance_valid(main) and is_instance_valid(main.player) and main.player.get("seat") != null
	if _camera.top_level or seated:
		if absf(df) > 0.00001:
			_camera.global_position -= _camera.global_basis.z * df
	else:
		_camera.position.y = _player_eye_height()
		if absf(df) > 0.00001:
			_camera.position.z -= df
	_applied_lean = forward


func _capture_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_look_yaw = float(main.player.rotation.y)
	var pitch: Variant = main.player.get("_pitch")
	_look_pitch = float(pitch) if pitch != null else 0.0


## Restore the player's yaw/pitch captured at act start. Free look and the pose-2 look cone can
## leave the rig yawed after the act, which makes W/D move relative to a different facing than the
## camera. Restoring the captured look keeps movement and view aligned.
func _restore_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var yaw := _look_yaw
	# Pose 1 restores the exact start snapshot; use its rig yaw rather than the later capture.
	if pose_id == CATALOG.MISSIONARY and _pose1_start_saved:
		yaw = _pose1_start_player_transform.basis.get_euler().y
	main.player.rotation.y = yaw
	if main.player.get("_pitch") != null:
		main.player.set("_pitch", _look_pitch)
	_log("look restored yaw=%.3f (captured %.3f) pitch=%.3f" % [yaw, _look_yaw, _look_pitch])


## Pose 2 must keep her rump toward Anon. The navigator tries to face a conversation partner
## and idle motion can add turns; this runs late and restores the start basis every tick.
func _lock_body_facing() -> void:
	if not _has_facing or pose_id != CATALOG.HORSE or not is_instance_valid(pony):
		return
	if state in [State.IDLE, State.RESTORE]:
		return
	var t: Transform3D = pony.global_transform
	var scale := t.basis.get_scale()
	t.basis = _facing_basis.scaled(scale)
	pony.global_transform = t


## Every few seconds she turns her head back toward Anon, then forward again. Reverted to the
## initial implementation: the game's secondary gaze owns the turn; pose 2 only adds the optional
## throw-back rotation (`head_back`), eased so it does not snap.
func _drive_glance(delta: float) -> void:
	if not _has_facing or pose_id != CATALOG.HORSE or not is_instance_valid(pony):
		return
	if is_instance_valid(_pose):
		var back_target := 1.0 if (_glance_left > 0.0 and _glance_back) else 0.0
		_glance_head_back = move_toward(_glance_head_back, back_target, delta / GLANCE_BACK_FADE)
		_pose.set("head_back", _glance_head_back)
	var secondary: Variant = pony.get("secondary")
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
		return Vector3(clampf(pitch + float(_pose_cfg.get("glance_back_pitch", GLANCE_BACK_PITCH)), -0.25, 1.0), clampf(yaw, -1.35, 1.35), 0.0)
	var yaw_limit := float(_pose_cfg.get("glance_yaw", GLANCE_YAW))
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)


## Free look, but inside a 45-degree cone around the direction the act began in. Movement stays
## held by kiss_hold; this only limits where the camera can turn.
func _clamp_look() -> void:
	if pose_id == CATALOG.MISSIONARY:
		# Pose 1: temporary free look while the pose is being tuned.
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var form: Variant = body.get("form_driver")
	# AnonPony lying/sitting has her own body-yaw limit; never widen it.
	if form != null and form is Node and (form as Node).has_method("clamp_view"):
		form.call("clamp_view")
	var yaw_delta := angle_difference(_look_yaw, float(body.rotation.y))
	if absf(yaw_delta) > LOOK_YAW_LIMIT:
		body.rotation.y = _look_yaw + clampf(yaw_delta, -LOOK_YAW_LIMIT, LOOK_YAW_LIMIT)
	var headset: Variant = body.get("headset_view")
	if headset is bool and headset:
		return
	var pitch_value: Variant = body.get("_pitch")
	if pitch_value == null:
		return
	var want := _look_pitch + clampf(float(pitch_value) - _look_pitch, -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	if absf(float(pitch_value) - want) > 0.00001:
		body.set("_pitch", want)
	var view: Camera3D = main.camera()
	if form == null and is_instance_valid(view):
		view.rotation.x = want


func _restore_camera() -> void:
	_restore_eye_override()
	_restore_anon_avatar()
	_free_pose1_view()
	if is_instance_valid(_camera):
		if _camera.top_level:
			if absf(_applied_lean) > 0.00001:
				_camera.global_position += _camera.global_basis.z * _applied_lean
		else:
			_camera.position.y = _player_eye_height()
			_camera.position.z += _applied_lean
	_applied_lean = 0.0
	_lean = 0.0
	_back = 0.0
	_back_target = 0.0
	_pose1_camera = Vector3.INF
	_camera = null


# --------------------------------------------------------------------------- audio

func _start_audio() -> void:
	_stop_audio()
	_breath_streams.clear()
	for i: int in range(1, 15):
		var path := "res://world/audio/pony/breath_%02d.wav" % i
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_breath_streams.append(stream)
	_breath = AudioStreamPlayer3D.new()
	_breath.name = "UnfplapBreath"
	_breath.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_breath.unit_size = 1.0
	_breath.max_distance = 8.0
	add_child(_breath)
	_breath_clock = 0.0
	_breath_gain = 0.0

	_kiss_stream = load("res://world/audio/pony/kiss.wav") if ResourceLoader.exists("res://world/audio/pony/kiss.wav") else null
	# The boop kiss uses the `kiss_soft_*` pool; use the same streams for the pose-1 rump plap.
	_plap_streams.clear()
	for i: int in range(1, 41):
		var path := "res://world/audio/pony/kiss_soft_%02d.wav" % i
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_plap_streams.append(stream)
	if _plap_streams.is_empty() and _kiss_stream != null:
		_plap_streams.append(_kiss_stream)
	_kiss_sound = AudioStreamPlayer3D.new()
	_kiss_sound.name = "UnfplapKiss"
	_kiss_sound.bus = _breath.bus
	_kiss_sound.unit_size = 1.0
	_kiss_sound.max_distance = 6.0
	add_child(_kiss_sound)

	_climax_streams.clear()
	for path: String in ["res://world/audio/pony/squee_1.ogg", "res://world/audio/pony/squee_2.ogg"]:
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_climax_streams.append(stream)
	_climax_sound = AudioStreamPlayer3D.new()
	_climax_sound.name = "UnfplapClimax"
	_climax_sound.bus = _breath.bus
	_climax_sound.unit_size = 1.0
	_climax_sound.max_distance = 10.0
	add_child(_climax_sound)


func _stop_audio() -> void:
	if is_instance_valid(_breath):
		_breath.stop()
		_breath.queue_free()
		_breath = null
	if is_instance_valid(_kiss_sound):
		_kiss_sound.stop()
		_kiss_sound.queue_free()
		_kiss_sound = null
	if is_instance_valid(_climax_sound):
		_climax_sound.stop()
		_climax_sound.queue_free()
		_climax_sound = null


func _stop_breath() -> void:
	if is_instance_valid(_breath):
		_breath.stop()


func _play_kiss() -> void:
	# Use the mod-owned player in both poses. Calling the game's boop `play_kiss()` increments her
	# kiss counter, and pony_awareness then tells the AI "The player kissed your face." during sex.
	var stream: AudioStream = _plap_streams.pick_random() if not _plap_streams.is_empty() else _kiss_stream
	if stream == null or not is_instance_valid(_kiss_sound):
		return
	_kiss_sound.stream = stream
	_kiss_sound.global_position = _dock_position() if pose_id == CATALOG.MISSIONARY else _snout()
	_kiss_sound.unit_size = 1.0
	_kiss_sound.max_distance = 6.0
	_kiss_sound.volume_db = -22.0
	_kiss_sound.pitch_scale = randf_range(0.95, 1.05)
	_kiss_sound.play()


## World position of the tail dock (hair `mTail1`, body `pony_tail_01` fallback).
func _dock_position() -> Vector3:
	if is_instance_valid(pony):
		var hair: Variant = pony.get("hair_skeleton")
		if hair is Skeleton3D:
			var bone := (hair as Skeleton3D).find_bone("mTail1")
			if bone >= 0:
				return (hair as Skeleton3D).global_transform * (hair as Skeleton3D).get_bone_global_pose(bone).origin
		var sk: Variant = pony.get("skeleton")
		if sk is Skeleton3D:
			var body_bone := (sk as Skeleton3D).find_bone("pony_tail_01")
			if body_bone >= 0:
				return (sk as Skeleton3D).global_transform * (sk as Skeleton3D).get_bone_global_pose(body_bone).origin
		return pony.global_position
	return Vector3.ZERO


func _play_climax() -> void:
	if _climax_streams.is_empty() or not is_instance_valid(_climax_sound):
		return
	_climax_sound.stream = _climax_streams[randi() % _climax_streams.size()]
	_climax_sound.global_position = _snout()
	_climax_sound.pitch_scale = randf_range(0.95, 1.05)
	_climax_sound.play()


func _breath_tick(delta: float) -> void:
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return
	if _breath_streams.is_empty() or not is_instance_valid(_breath):
		return
	var rate := clampf(_pumps_per_second() / BREATH_RATE_CAP, 0.0, 1.0)
	# Gain follows the plap rate, jumps loud at climax, and fades out over 5 s in afterglow.
	var target := 0.0
	var fade := BREATH_FADE_S
	if state == State.ACTIVE:
		target = rate
	elif state == State.CLIMAX:
		target = 1.0
		fade = 0.25
	else:
		target = 0.0
		fade = AFTERGLOW_BREATH_FADE_S
	_breath_gain = move_toward(_breath_gain, target, delta / fade)
	# Climax volume matches the kiss/plap level, not a shout.
	var max_db := -22.0 if state == State.CLIMAX else -18.0
	var db := lerpf(-42.0, max_db, _breath_gain)
	if _breath.playing:
		_breath.volume_db = db
	_breath_clock -= delta
	if _breath_clock > 0.0:
		return
	if _breath_gain < 0.02:
		_breath_clock = 0.4
		return
	var interval := lerpf(BREATH_BASE_INTERVAL_S, BREATH_MIN_INTERVAL_S, rate)
	if state == State.CLIMAX:
		interval = 0.7
	elif state == State.AFTERGLOW:
		interval = 1.4
	_breath_clock = interval
	_breath.stream = _breath_streams[randi() % _breath_streams.size()]
	_breath.global_position = _snout()
	_breath.volume_db = db
	_breath.pitch_scale = 1.0 + rate * 0.2
	_breath.play()


func _pumps_per_second() -> float:
	var now := Time.get_ticks_msec() * 0.001
	while not _pump_times.is_empty() and now - float(_pump_times[0]) > 1.0:
		_pump_times.pop_front()
	return float(_pump_times.size())


func _snout() -> Vector3:
	var boop: Variant = pony.get("boop_node")
	if is_instance_valid(boop) and boop.has_method("nose_world"):
		return boop.call("nose_world")
	return pony.global_position + Vector3.UP * 1.0
