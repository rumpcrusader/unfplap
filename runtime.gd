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
const ANON_THRUST := preload("res://mods/unfplap/anon_thrust.gd")
const CHIN_DEBUG := preload("res://mods/unfplap/chin_debug.gd")
const BODY_SWAY := preload("res://mods/unfplap/body_sway.gd")
const EAR_TWITCH := preload("res://mods/unfplap/ear_twitch.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")
const VOICE := preload("res://mods/unfplap/voice_status.gd")

enum State { IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE }

const SATISFACTION_MAX := 100
const STAMINA_MAX := 400
## Mod-owned generated lines wait this long after the previous line starts, even when the
## director is free. Other systems keep their own scheduling.
const UTTERANCE_MIN_GAP_S := 6.0
## Safety timeout for a queued line that never starts. In-progress speech is never timed out.
const UTTERANCE_QUEUE_TIMEOUT_S := 60.0
## Keep the line slot reserved briefly after speech stops, so a split TTS reply cannot be
## interrupted by the next queued line.
const UTTERANCE_RELEASE_HOLD_S := 1.0
const CLIMAX_SECONDS := 5.0
const CLIMAX_BOBS := 2
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## Same hold length the game uses for bridal-carry initiation (interactor KEY_HOLD_SECONDS).
const HOLD_Y_SECONDS := 0.35
const BREATH_BASE_INTERVAL_S := 0.9
const BREATH_MIN_INTERVAL_S := 0.2
const BREATH_CLIMAX_INTERVAL_S := 0.85
const BREATH_RATE_CAP := 10.0
## Breath gain easing. Active: follows the plap rate; afterglow: fades over this many seconds.
const BREATH_FADE_S := 2.5
const AFTERGLOW_BREATH_FADE_S := 5.0
const WITNESS_RADIUS_M := 8.0
## Pose 1 camera: closer to her neck/face so the free shot does not feel distant.
## `pony.global_basis.z` is her backward direction.
const POSE1_CAMERA_HEIGHT_M := 0.45
const POSE1_CAMERA_FORWARD_M := 0.22
## Additional room between the pose-1 shot and the pony.
const POSE1_CAMERA_PULLBACK_M := 0.20
## Extra height requested after the first visual pass.
const POSE1_CAMERA_LIFT_M := 0.10
## Presentation: how close the pony stands in front of the player for pose 2.
const POSE2_GAP_M := 0.55
## Per-size pose-2 standing gap. Same Height is the tuned baseline; Hoers stays unchanged.
const POSE2_GAPS := {
	"same height": 0.55,
	"mounting": 0.45,
	"canon": 0.25,
	"hoers": 0.55,
}
## Pose 1 camera vertical bob uses the same spring as pose 2.
## Camera bob: damped spring, vertical and forward. Amplitudes are one sixth of the
## pre-mouse-pump values (2.30/1.80 impulses, 0.025/0.12 climax).
const BOB_PUMP_IMPULSE := 2.30 / 3.0
const BOB_STIFFNESS := 105.0
const BOB_DAMPING := 13.0
const BOB_CLIMAX_AMPLITUDE := 0.025 / 3.0
const BOB_LIMIT := 0.40
const BOB_FORWARD_IMPULSE := 1.80 / 6.0
const BOB_FORWARD_STIFFNESS := 100.0
const BOB_FORWARD_DAMPING := 12.0
const BOB_FORWARD_LIMIT := 0.32
const BOB_CLIMAX_FORWARD := 0.12 / 6.0
## Pump speed at which the bob uses its full-speed spring. Slower strokes scale the whole
## bob timebase down (spring, damping and impulse together), so the peak stays the same but
## the motion takes longer. Very slow strokes stop at this scale.
const BOB_SPEED_REFERENCE := 0.80
const BOB_SPEED_SCALE_MIN := 0.35
## Pose-2 F kiss: hold F at a full side lean (the shoulder reach) to use the same base kiss.
const POSE2_KISS_LEAN := 0.90
## Act camera lean. Q/E drive one controlled lean vector: W/S forward/back, Q/E a
## forward-plus-side diagonal. The channel ramps in, then returns slowly when released.
## Backward travel is halved so pulling away cannot open an extreme gap.
const LEAN_RAMP_SECONDS := 0.5
const LEAN_RETURN_SECONDS := 1.6
const LEAN_FORWARD_M := 0.24
## Backing off is half the forward travel so Anon cannot pull too far from her.
const LEAN_BACK_M := 0.08
const LEAN_SIDE_M := 0.18
## Phase-2 Anon body lean: the pelvis stays planted while the camera/head leans.
## Experiment: Anon's chest/head follow the pump; the pelvis counter-moves so his upper body
## travels forward on the inward stroke and back on the outward stroke.
const ANON_PUMP_SWAY_M := 0.02
const LEAN_PITCH_DEG := 6.0
const LEAN_ROLL_DEG := 1.5
const LEAN_SIDE_ROLL_DEG := 8.0
const LEAN_SIDE_YAW_DEG := 3.0
## Q/E fire their pose reaction when the smoothed side lean crosses these values.
const LEAN_FIRE := 0.75
const LEAN_RELEASE := 0.60
## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35
## Pose-2 A/D caress: an oval rub on the flank surface. The oval is wider along the body
## than up/down, so the hand reads as stroking instead of drawing a perfect circle.
const CARESS_RADIUS_M := 0.055
const CARESS_SPEED_RAD_S := 4.5
const CARESS_OVAL_ACROSS := 1.30
const CARESS_OVAL_UP := 0.70
const CARESS_SURFACE_LIFT_M := 0.085
## Caress-point offsets are per size preset, in metres before the body scale is applied to
## only the circle radius. `out` moves each hand out from the flank; both hands together gain
## twice that amount. JRHNBR (`mounting`) is 4 cm wider; Canon sits lower.
const CARESS_PROFILES := {
	"canon": {"up": 0.08, "back": 0.06, "out": 0.0},
	"mounting": {"up": 0.16, "back": 0.08, "out": 0.02},
	"same height": {"up": 0.18, "back": 0.09, "out": 0.03},
	"hoers": {"up": 0.20, "back": 0.10, "out": 0.04},
}
## Backward lean reaches the rump top at this magnitude, not at a full -1 lean.
const CARESS_RUMP_LEAN := 0.5
## EXPERIMENTAL (feature: camera_inertia).
const CAMERA_INERTIA_SMOOTH := 5.0
## EXPERIMENTAL (feature: camera_rock).
const CAMERA_ROCK_IMPULSE := 0.20
const CAMERA_ROCK_STIFFNESS := 45.0
const CAMERA_ROCK_DAMPING := 8.0
const CAMERA_ROCK_LIMIT := 0.026
const CAMERA_ROCK_PITCH_RATIO := 0.45
## EXPERIMENTAL (feature: rump_blush). Rump blush from strong pumps: a fraction of the 0.8
## smack decal strength.
const RUMP_BLUSH_MIN_STRENGTH := 0.55
const RUMP_BLUSH_STEP := 0.035
const RUMP_BLUSH_MAX := 0.25
const RUMP_BLUSH_DECAY := 0.012
const POSE2_HEAD_NECK_HEIGHT_M := 1.0
## Canon is small enough that the standing shot needs a lower eye line.
const CANON_POSE2_CAMERA_DROP_M := 0.10
## Pose-2 Anon thrust: the hip follows raw depth directly, so it stays on the mouse.
const THRUST_MAX_M := 0.045
## Safety cone for AnonPony's own body-yaw limit; the desktop act camera no longer free-looks.
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
## Pose 2 after the climax: Anon eases back before the act restores.
const AFTERGLOW_BACK_M := 0.18
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Pose 2 after the climax: held afterglow; Anon no longer auto-withdraws.

## Wing spread/droop and jitter. All mod-owned wing timing is deliberately slow: the wings
## spread over four seconds, lower over twenty, and the flutter cannot restart mid-cycle.
const WING_FADE_SECONDS := 2.20
const WING_FLICK_DECAY := 1.80
const WING_FLICK_MIN := 0.10
const WING_FLICK_MAX := 0.24
const WING_SPREAD_SECONDS := 8.0
const WING_DROOP_SECONDS := 40.0
const WING_DROOP_AMOUNT := 0.35
const WING_JITTER_AMOUNT := 0.04
const WING_JITTER_MIN := 1.6
const WING_JITTER_MAX := 4.0
const WING_JITTER_FADE := 0.8
## Pose 2 starts at a relaxed ~60° spread instead of the half-open pose's ~75°. Lower values
## blend further toward fully open; satisfaction gradually opens them from here.
const WING_POSE2_HOLD := 0.65
const WING_POSE2_SPREAD := 0.25
## The game's flutter cycle is 3 × (0.16 + 0.13) = 0.87 s. A pump may not restart it before
## it finishes or the wings snap back open mid-motion.
const WING_FLUTTER_COOLDOWN_S := 1.80
## Pose 2 keeps her body facing away but lets her glance back over a shoulder now and then.
const GLANCE_MIN_INTERVAL := 5.0
const GLANCE_MAX_INTERVAL := 9.0
const GLANCE_HOLD := 1.8
const GLANCE_YAW := 3.0
const GLANCE_BACK_PITCH := 1.2
const GLANCE_BACK_CHANCE := 0.5
## Fade time for the extra head-back glance pose; prevents the head snapping back to low.
const GLANCE_BACK_FADE := 0.45
## Yaw limit for a look-back glance. Raised 20% from 1.35 so she turns farther over her shoulder.
const GLANCE_BACK_YAW := 1.62
## Jiggle placement on the flank. The pump scale is reduced 20% from the review pass; the
## native smack keeps its own strength.
const JIGGLE_HEIGHT := 0.78
const JIGGLE_SIDE := 0.24
const JIGGLE_BACK := 0.12
## `_start_jiggle` clamps strength to 0.3..1, so weak pumps still move a little.
const JIGGLE_MIN_STRENGTH := 0.30
const JIGGLE_RUMP_SCALE := 2.8
## Smack decals target slightly higher and farther back along the flank than the mark centres.
const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08
const SMACK_ZONE_RADIUS_M := 0.035
const SMACK_COOLDOWN_MS := 200
const SMACK_SWING_SECONDS := 0.20
const SMACK_CONTACT_PHASE := 0.45
const SMACK_CONTACT_LIFT_M := 0.035
## Act kiss timing. The sound repeats softly while her mouth is held to Anon's.
const KISS_FADE_IN := 0.35
const KISS_FADE_OUT := 0.45
const KISS_SOUND_MIN := 2.0
const KISS_SOUND_MAX := 3.4

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
var _y_hold := 0.0
var _y_hold_ready := false
var _y_hold_fired := false
var _nav: Node
var _nav_old_wander := true
var _token := ""
var _id := ""
var _profile: Dictionary = {}
var _features: Dictionary = {}
var _pose_cfg: Dictionary = {}
var _base_preferences: Dictionary = {}
var _preferences: Dictionary = {}
var _phase_index := -1
var _act_prompts: Dictionary = {}
var _pump_tracker
var _pump_pixels_per_full := 600.0
var _pump_bobs := false
var _satisfaction_frac := 0.0
var _speed_zone_previous := "ok"
var _speed_zone_strokes := 0
## Last closed stroke: direction/travel/speed/peak_speed/strength, shape/zone/multiplier,
## base/scaled gain. One result feeds scoring, HUD debug, utterances and the visual effects.
var _last_stroke: Dictionary = {}
var _last_reaction: Dictionary = {}
var _depth_out_seconds := 0.0
var _utterance_points: Array[float] = []
var _utterance_index := 0
var _utterance_pending_key := ""
var _utterance_pending_until := 0.0
var _utterance_done_key := ""
var _utterance_done_at := 0.0
var _utterance_rng := RandomNumberGenerator.new()
var _utterance_serial := 0
var _last_utterance_at := -1000.0
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
var _applied_bob := 0.0
var _applied_lean := 0.0
var _applied_side := 0.0
var _free_camera_active := false
var _camera_basis_ready := false
var _pose1_look_point := Vector3.INF
var _pose2_base_look := Vector3.INF
var _pose2_aim_until := 0
var _pose2_base_local := Vector3.ZERO
var _pose2_base_saved := false
var _restore_yaw := 0.0
var _restore_pitch := 0.0
var _controls_locked_saved := false
var _controls_locked_by_camera := false
var _anon_thrust_driver: Node3D
var _anon_thrust_original: Node
var _anon_thrust_avatar: Node3D
var _chin_modifier: SkeletonModifier3D
var _body_sway: SkeletonModifier3D
var _ear_twitch: SkeletonModifier3D
var _lean_forward := 0.0
var _lean_side := 0.0
var _lean_view_forward := 0.0
var _lean_view_side := 0.0
var _lean_return_enabled := true
var _hold_rock_clock := 0.0
var _lean_action_active := false
var _lean_action_side := 0.0
var _lean_action_kind := ""
var _lean_action_shoulder := ""
var _reach_hand_from := Transform3D.IDENTITY
var _reach_hand_rest := Transform3D.IDENTITY
var _reach_hand_rest_valid := false
var _reach_hand_started := 0
var _reach_hand_logged := false
var _reach_hand_returning := false
var _reach_hand_return_from := Transform3D.IDENTITY
var _reach_hand_return_started := 0
var _reach_hand_return_side := ""
var _caress_active := {"L": false, "R": false}
var _caress_started := {"L": 0, "R": 0}
var _caress_logged := {"L": false, "R": false}
var _last_smack_ms := -10000
var _smack_active := false
var _smack_index := 0
var _smack_at := Vector3.INF
var _smack_side := ""
var _smack_from := Transform3D.IDENTITY
var _smack_to := Transform3D.IDENTITY
var _smack_started := 0
var _smack_impact_done := false
var _kiss_amount := 0.0
var _kiss_sound_clock := 0.0
var _custom_kiss_active := false
var _base_kiss_active := false
var _base_kiss_releasing := false
var _pose2_kiss_active := false
var _base_kiss_affection: Node
var _base_kiss_pose: SkeletonModifier3D
var _base_kiss_pose_index := -1
var _forced_glance := ""
var _camera_rock := 0.0
var _camera_rock_velocity := 0.0
var _camera_rock_sign := 1.0
var _rump_blush := 0.0
var _rump_decal: Decal
var _voice_info: Dictionary = {}
var _voice_player: AudioStreamPlayer3D
var _voice_volume_saved := 0.0
var _text_only_voice := false
var _inventory_hud_hidden := false
var _inventory_hud_saved := false
var _inventory_hotbar_visible := true
var _inventory_hud_layer_visible := true
var _pose1_camera := Vector3.INF
var _pose1_head_roll := 0.0
var _pose1_start_camera: Camera3D
var _pose1_start_camera_transform := Transform3D.IDENTITY
var _pose1_start_player_transform := Transform3D.IDENTITY
var _pose1_start_pony_transform := Transform3D.IDENTITY
var _pose1_start_pony_posture := ""
var _pose1_start_saved := false
var _pose1_basis_logged := false
var _pose1_aim_fix_logged := false
var _pose1_camera_log_until := 0
var _pose1_camera_log_next := 0
var _pose1_view: Camera3D
var _pose1_source_fov := 75.0
var _pose1_source_near := 0.05
var _pose1_source_far := 4000.0
var _pose1_source_cull := 0xFFFFFFFF
var _pose1_view_basis := Basis.IDENTITY
var _pose1_aim_until := 0
var _pose1_prev_camera: Camera3D
var _pose1_player_rotation := Vector3.ZERO
var _pose1_player_rot_saved := false
var _anon_avatar: Node3D
var _anon_avatar_visible := true
var _bob := 0.0
var _bob_velocity := 0.0
var _bob_speed_scale := 1.0
var _lean := 0.0
var _lean_velocity := 0.0
var _back := 0.0
var _back_target := 0.0
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
var _last_wing_flutter := -1000.0
var _act_seconds := 0.0
var _wings_node: Node
var _aftercare: Node
var _satisfaction_tween: Tween
var _face_timer: Timer
var _kisser: Node
var _kisser_processing := false
var _climax_progress := 0.0
## Climax hearts: three pulses with at least one second between them. The first pulse emits
## four boop bursts, the second two, and the last one. A separate burst starts from her dock at
## the exact climax start. Each burst uses celebrate() (five hearts, no boop count).
var _heart_elapsed := 0.0
var _heart_index := 0
var _heart_times: Array[float] = []
var _heart_counts: Array[int] = []
## Debug-only head pitch in degrees. Alt+7 raises, Alt+8 lowers; zero outside experimentation.
var _debug_chin_deg := 0.0
var _breath: AudioStreamPlayer3D
var _breath_streams: Array[AudioStream] = []
var _breath_clock := 0.0
var _breath_gain := 0.0
var _kiss_sound: AudioStreamPlayer3D
var _mouth_kiss_sound: AudioStreamPlayer3D
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


func _feature(name: String) -> bool:
	return bool(_features.get(name, true))


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
			base_target = clampf(WING_POSE2_HOLD - level * spread_t * WING_POSE2_SPREAD, 0.0, 1.0)
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
			_wing_clock = 2.0
			excitement.call("spread", 4.0)
		return
	_flutter_clock -= delta
	if _flutter_clock <= 0.0 and excitement.has_method("flutter"):
		var now := _now_s()
		if now - _last_wing_flutter >= WING_FLUTTER_COOLDOWN_S:
			excitement.call("flutter")
			_last_wing_flutter = now
		_flutter_clock = randf_range(4.8, 9.2)


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
	_clamp_look()
	if is_instance_valid(_pose) and is_instance_valid(main):
		var view: Camera3D = main.camera()
		if pose_id == CATALOG.MISSIONARY and is_instance_valid(_pose1_view):
			view = _pose1_view
		var custom_kiss := _kiss_amount > 0.001 and not _base_kiss_active
		if is_instance_valid(view):
			_pose.look_point = _kiss_target(view) if custom_kiss else view.global_position
		_pose.kiss = _kiss_amount if custom_kiss else 0.0
		_pose.climaxing = state == State.CLIMAX
	if not _pump_bobs:
		_bob = 0.0
		_bob_velocity = 0.0
		_lean = 0.0
		_lean_velocity = 0.0
	elif state == State.CLIMAX:
		_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)
		var wave := sin(_climax_progress * PI * 2.0 * float(CLIMAX_BOBS))
		_bob = wave * BOB_CLIMAX_AMPLITUDE
		_lean = wave * BOB_CLIMAX_FORWARD
		_bob_velocity = 0.0
		_lean_velocity = 0.0
	else:
		var speed_scale := _bob_speed_scale
		var bob_stiffness := BOB_STIFFNESS * speed_scale * speed_scale
		var bob_damping := BOB_DAMPING * speed_scale
		var accel := -bob_stiffness * _bob - bob_damping * _bob_velocity
		_bob_velocity += accel * delta
		_bob = clampf(_bob + _bob_velocity * delta, -BOB_LIMIT, BOB_LIMIT)
		var lean_stiffness := BOB_FORWARD_STIFFNESS * speed_scale * speed_scale
		var lean_damping := BOB_FORWARD_DAMPING * speed_scale
		var forward_accel := -lean_stiffness * _lean - lean_damping * _lean_velocity
		_lean_velocity += forward_accel * delta
		_lean = clampf(_lean + _lean_velocity * delta, -BOB_FORWARD_LIMIT, BOB_FORWARD_LIMIT)
	var back_speed := AFTERGLOW_BACK_SPEED if state == State.AFTERGLOW else RESTORE_BACK_SPEED
	_back = move_toward(_back, _back_target, back_speed * delta)
	_breath_tick(delta)


## Mouse input. Vertical motion pumps; the act camera intentionally ignores it for look.
func _input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if state in [State.ACTIVE, State.CLIMAX]:
		if state == State.ACTIVE and _pump_tracker != null:
			var amount: float = PUMP.mouse_to_depth(motion.relative.y, _pump_pixels_per_full, pump_up)
			_pump_move(amount, _now_s())
		get_viewport().set_input_as_handled()


func _headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view"))


## Y is a deliberate hold, matching the game's 0.35 s bridal-carry hold. A tap does nothing,
## and the trigger latches until release so a held key cannot fire twice.
func _hold_y_tick(delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE, State.AFTERGLOW]:
		_y_hold = 0.0
		_y_hold_fired = false
		return
	var held := Input.is_physical_key_pressed(KEY_Y)
	if not held:
		_y_hold = 0.0
		_y_hold_fired = false
		_y_hold_ready = true
		return
	if not _y_hold_ready:
		return
	_y_hold += delta
	if _y_hold < HOLD_Y_SECONDS or _y_hold_fired:
		return
	_y_hold_fired = true
	_log("hold Y state=%d" % state)
	if state == State.AFTERGLOW:
		end_afterglow()
	else:
		cancel()


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
	_hold_y_tick(delta)
	_lean_tick(delta)
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_act_presentation(delta)
	_kiss_tick(delta)
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
		_climax_hearts_tick(delta)
		if _climax_left <= 0.0:
			_finish_climax()
	elif state == State.RESTORE:
		_restore_left -= delta
		if _restore_left <= 0.0:
			_finish_restore()
	_lock_body_facing()
	_drive_glance(delta)
	_suppress_auto_cuddle()
	_clamp_look()
	_camera_rock_tick(delta)
	_rump_blush_tick(delta)
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
	if _cuddle_active() and not _cuddle_start_override(pose, act_source):
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
	if _cuddle_active() and not _cuddle_start_override(pose, act_source):
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
		text += " | pump depth=%.2f speed=%.2f peak=%.2f strength=%.2f zone=%s shape=%s up=%s | %s" % [
			depth, float(_last_stroke.get("speed", 0.0)), float(_last_stroke.get("peak_speed", 0.0)),
			float(_last_stroke.get("strength", 0.0)), str(_last_stroke.get("speed_zone", "ok")),
			str(_last_stroke.get("shape", "mixed")), str(pump_up),
			PREFERENCES.describe(_preferences).replace("\n", "; ")]
	text += " | " + voice_status_line()
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
	if state == State.IDLE:
		return
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


## The stock cuddle gate is bypassable by feature flag. The normal bed-side paths remain.
func _cuddle_start_override(pose: String, act_source: String) -> bool:
	if pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]:
		return true
	if _features.has("cuddle_override"):
		return bool(_features.get("cuddle_override", false))
	return SETTINGS.feature("cuddle_override")


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
	_features = SETTINGS.features()
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
	_pump_pixels_per_full = float(pump_controls.get("pixels_per_full", 600.0))
	_pump_bobs = bool(pump_controls.get("bobs", false))
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
	_applied_bob = 0.0
	_applied_lean = 0.0
	_bob = 0.0
	_bob_velocity = 0.0
	_bob_speed_scale = 1.0
	_lean = 0.0
	_lean_velocity = 0.0
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
	_last_wing_flutter = -1000.0
	_jiggle_logged = false
	_act_seconds = 0.0
	_flutter_clock = randf_range(1.0, 3.0)
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()
	_reset_lean_state()
	_camera_rock = 0.0
	_camera_rock_velocity = 0.0
	_camera_rock_sign = 1.0
	_rump_blush = 0.0
	_clear_face()
	_set_face(0.45, 0.45)
	_serial = _next_serial()
	_event_id = "intimacy_%s_%d" % [_id, _serial]
	_started_at = Time.get_unix_time_from_system()
	satisfaction = 0
	stamina = STAMINA_MAX
	_y_hold = 0.0
	_y_hold_ready = false
	_y_hold_fired = false
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
	if _cuddle_active() and _feature("cuddle_override") \
			and source not in ["bed_side", "already_lying"]:
		_end_cuddle_session()
		REST.release_managed(pony)
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
	_reset_lean_state()
	_pose1_basis_logged = false
	_pose1_aim_fix_logged = false
	_pose1_camera = _pose1_camera_target() if pose == CATALOG.MISSIONARY else Vector3.INF
	if pose == CATALOG.MISSIONARY:
		_snapshot_pose1_start()
		_make_pose1_view()
	_capture_look()
	_lock_player()
	_begin_camera_mode()
	_hide_anon_avatar_for_pose1()
	_start_audio()
	_apply_voice_policy()
	_set_inventory_hud_hidden(true)
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
	_set_inventory_hud_hidden(false)
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


func debug_chin(step_deg: float) -> void:
	if not is_instance_valid(pony):
		return
	_debug_chin_deg = clampf(_debug_chin_deg + step_deg, -30.0, 30.0)
	_apply_debug_chin()
	# Let the skeleton modifier apply this frame before sampling the head/chin positions.
	call_deferred("_log_chin")


## Attach the debug chin modifier and keep it after every pose modifier, so an act cannot
## overwrite the experimental head pitch.
func _apply_debug_chin() -> void:
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not skeleton is Skeleton3D:
		return
	if not is_instance_valid(_chin_modifier) or _chin_modifier.get_parent() != skeleton:
		if is_instance_valid(_chin_modifier):
			_chin_modifier.queue_free()
		_chin_modifier = CHIN_DEBUG.new()
		_chin_modifier.name = "UnfplapChinDebug"
		_chin_modifier.set("mare", pony)
		(skeleton as Skeleton3D).add_child(_chin_modifier)
	_chin_modifier.set("chin_deg", _debug_chin_deg)
	_keep_chin_last()


func _keep_chin_last() -> void:
	if not is_instance_valid(_chin_modifier):
		return
	var parent := _chin_modifier.get_parent()
	if parent is Skeleton3D:
		(parent as Skeleton3D).move_child(_chin_modifier, parent.get_child_count() - 1)


func _log_chin() -> void:
	if not is_instance_valid(pony):
		return
	var rows: Array[String] = []
	rows.append("pony=%s angle=%+.1f°" % [str(pony.name), _debug_chin_deg])
	var body: Variant = pony.get("skeleton")
	if body is Skeleton3D:
		var head_bone := (body as Skeleton3D).find_bone("pony_head")
		if head_bone >= 0:
			var head_pose := (body as Skeleton3D).get_bone_global_pose(head_bone)
			rows.append("head origin=%s dir=%s" % [
				str((body as Skeleton3D).global_transform * head_pose.origin),
				str(head_pose.basis.z)])
	var boop: Variant = pony.get("boop_node")
	var head_sk: Variant = boop.get("head_skeleton") if boop != null else null
	if head_sk is Skeleton3D:
		var chin_bone := (head_sk as Skeleton3D).find_bone("mFaceChin")
		if chin_bone >= 0:
			var chin_pose := (head_sk as Skeleton3D).get_bone_global_pose(chin_bone)
			rows.append("chin world=%s" % str((head_sk as Skeleton3D).global_transform * chin_pose.origin))
		if boop.has_method("nose_world"):
			rows.append("snout world=%s" % str(boop.call("nose_world")))
	if is_instance_valid(main) and main.has_method("_debug_block"):
		main.call("_debug_block", "CHIN", rows)


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
	_keep_chin_last()
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
		if pose_id == CATALOG.HORSE:
			if _feature("body_sway"):
				_install_body_sway(skeleton)
			if _feature("ear_twitch"):
				_install_ear_twitch()
		_keep_chin_last()
	if pose_id != CATALOG.HORSE:
		return
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_tail = TAIL.new()
		_tail.name = "UnfplapTail"
		_tail.mare = pony
		_tail.runtime = self
		_tail.aside_angle = float(_pose_cfg.get("tail_aside", 0.55))
		_tail.lift_angle = float(_pose_cfg.get("tail_lift", 0.42))
		_tail.amount = 0.0
		_tail.target_amount = 1.0
		_tail.call("choose_side")
		(hair as Skeleton3D).add_child(_tail)


func _free_pose() -> void:
	_end_caress()
	_end_smack_swing()
	_end_lean_action()
	_clear_reach_hand()
	_restore_base_kiss_pose()
	_release_free_camera_lock()
	_remove_anon_thrust()
	_remove_extra_modifiers()
	_restore_voice_volume()
	if is_instance_valid(_rump_decal):
		_rump_decal.queue_free()
	_rump_decal = null
	_rump_blush = 0.0
	if is_instance_valid(_pose):
		_pose.queue_free()
	_pose = null
	if is_instance_valid(_tail):
		_tail.queue_free()
	_tail = null


func _install_body_sway(skeleton: Skeleton3D) -> void:
	if not _feature("body_sway"):
		return
	_body_sway = BODY_SWAY.new()
	_body_sway.name = "UnfplapBodySway"
	_body_sway.set("mare", pony)
	_body_sway.set("runtime", self)
	skeleton.add_child(_body_sway)


func _install_ear_twitch() -> void:
	if not _feature("ear_twitch"):
		return
	var boop: Variant = pony.get("boop_node")
	var head: Variant = boop.get("head_skeleton") if boop != null else null
	if not head is Skeleton3D:
		return
	_ear_twitch = EAR_TWITCH.new()
	_ear_twitch.name = "UnfplapEarTwitch"
	_ear_twitch.set("mare", pony)
	(head as Skeleton3D).add_child(_ear_twitch)


func _remove_extra_modifiers() -> void:
	if is_instance_valid(_body_sway):
		_body_sway.queue_free()
	_body_sway = null
	if is_instance_valid(_ear_twitch):
		_ear_twitch.queue_free()
	_ear_twitch = null


# --------------------------------------------------------------------------- pump

func _now_s() -> float:
	return Time.get_ticks_msec() * 0.001


func _reset_pump_state() -> void:
	depth = 0.0
	_satisfaction_frac = 0.0
	_speed_zone_previous = "ok"
	_speed_zone_strokes = 0
	_last_stroke.clear()
	_last_reaction.clear()
	_depth_out_seconds = 0.0
	_utterance_points.clear()
	_utterance_index = 0
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	_utterance_done_key = ""
	_utterance_done_at = 0.0
	_utterance_serial = 0
	_last_utterance_at = -1000.0
	_vocal_cooldown = 0.0
	_bored_seconds = 0.0
	_speed_travel = 0.0
	if _pump_tracker == null:
		_pump_tracker = PUMP.new()
	_pump_tracker.reset()


func _schedule_utterances() -> void:
	_utterance_rng.randomize()
	# Keep sex dialogue sparse for every mare: at most three scheduled act lines.
	var low := clampi(int(_profile.get("min_utterances", 2)), 0, 3)
	var high := clampi(int(_profile.get("max_utterances", 3)), 0, 3)
	if low > high:
		low = high
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


func _voice_profile() -> Dictionary:
	var director := _director()
	if director == null:
		return {}
	var characters: Variant = director.get("characters")
	if characters is Dictionary and (characters as Dictionary).has(_id):
		var entry: Variant = (characters as Dictionary)[_id]
		if entry is Dictionary:
			var profile: Variant = (entry as Dictionary).get("profile", {})
			if profile is Dictionary:
				return profile
	return {}


func _tts_node() -> Node:
	var director := _director()
	if director == null:
		return null
	var tts: Variant = director.get("tts")
	return tts as Node if is_instance_valid(tts) else null


func _tts_enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("tts_enabled"):
		return bool(settings.call("tts_enabled"))
	return true


func _classify_voice() -> Dictionary:
	return VOICE.classify(_voice_profile(), _tts_node(), _tts_enabled())


func voice_status_line() -> String:
	return "voice " + VOICE.describe(_classify_voice())


func _find_voice_player() -> AudioStreamPlayer3D:
	if not is_instance_valid(pony):
		return null
	var head: Variant = pony.get("head")
	var voice: Variant = head.get("voice") if head != null else null
	if voice is AudioStreamPlayer3D:
		return voice
	var found: Variant = pony.find_child("Voice", true, false)
	return found as AudioStreamPlayer3D if found is AudioStreamPlayer3D else null


## `act_text_only_ponese`: keep the generated line and text HUD, but silence the Ponese audio
## for this act. A generated-voice pony is left alone.
func _apply_voice_policy() -> void:
	_voice_info = _classify_voice()
	_text_only_voice = _feature("act_text_only_ponese") \
		and bool(_voice_info.get("effective_ponese", false))
	if not _text_only_voice:
		return
	_voice_player = _find_voice_player()
	if not is_instance_valid(_voice_player):
		_log("voice text-only: no voice player pony=%s" % _id)
		return
	_voice_volume_saved = _voice_player.volume_db
	_voice_player.volume_db = -80.0
	_log("voice text-only pony=%s %s" % [_id, VOICE.describe(_voice_info)])


func _restore_voice_volume() -> void:
	if is_instance_valid(_voice_player):
		_voice_player.volume_db = _voice_volume_saved
	_voice_player = null
	_voice_volume_saved = 0.0
	_text_only_voice = false


## Hide the quick-slot hotbar for the whole act. `hud_hidden` keeps the inventory's own
## `_place_hotbar()` from showing it again.
func _set_inventory_hud_hidden(hidden: bool) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	var inventory: Variant = main.game.get("inventory")
	if not is_instance_valid(inventory):
		return
	var bar: Variant = inventory.get("hotbar")
	if hidden:
		if _inventory_hud_hidden:
			return
		_inventory_hud_hidden = true
		_inventory_hud_saved = bool(inventory.get("hud_hidden"))
		inventory.set("hud_hidden", true)
		if is_instance_valid(bar):
			_inventory_hotbar_visible = bool(bar.get("visible"))
			var layer: Variant = bar.get("_hud")
			if layer is CanvasLayer:
				_inventory_hud_layer_visible = bool((layer as CanvasLayer).visible)
			bar.call("set_hud_visible", false)
			bar.set("visible", false)
		return
	if not _inventory_hud_hidden:
		return
	inventory.set("hud_hidden", _inventory_hud_saved)
	if is_instance_valid(bar):
		bar.set("visible", _inventory_hotbar_visible)
		var layer: Variant = bar.get("_hud")
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = _inventory_hud_layer_visible
	_inventory_hud_hidden = false


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
	var speed := float(event.get("speed", 0.0))
	var shape := PREFERENCES.MIXED
	var zone := "ok"
	var multiplier := 1.0
	if direction > 0:
		var shape_cfg: Dictionary = _preferences.get("shape", {})
		if bool(shape_cfg.get("enabled", false)):
			var samples: PackedVector2Array = event.get("samples", PackedVector2Array())
			var classified := PREFERENCES.classify_shape(
				samples,
				float(shape_cfg.get("min_travel", 0.30)),
				float(shape_cfg.get("max_rmse", 0.18)))
			shape = str(classified.get("shape", PREFERENCES.MIXED))
		zone = PREFERENCES.speed_zone(_preferences, speed)
		multiplier = PREFERENCES.multiplier(_preferences, zone, shape)
	var base_gain := float(event.get("base_gain", 0.0))
	var result := {
		"direction": direction,
		"start_depth": float(event.get("start_depth", 0.0)),
		"end_depth": float(event.get("end_depth", 0.0)),
		"travel": float(event.get("travel", 0.0)),
		"duration": float(event.get("duration", 0.0)),
		"speed": speed,
		"peak_speed": float(event.get("peak_speed", speed)),
		"base_gain": base_gain,
		"scaled_gain": base_gain * multiplier,
		"pump": bool(event.get("pump", false)),
		"shape": shape,
		"speed_zone": zone,
		"multiplier": multiplier,
		"strength": float(event.get("strength", 0.0)),
	}
	if direction > 0:
		_last_stroke = result
		_note_speed(zone)
		_note_shape(shape)
	if result.pump:
		_on_pump(result)
	_add_satisfaction(float(result.scaled_gain))
	_log("stroke dir=%d travel=%.2f speed=%.2f peak=%.2f shape=%s zone=%s strength=%.2f gain=%.2f satisfaction=%d" % [
		direction, float(result.travel), speed, float(result.peak_speed), shape, zone,
		float(result.strength), float(result.scaled_gain), satisfaction])
	if state == State.ACTIVE and satisfaction >= _climax_at:
		_climax()


func _on_pump(result: Dictionary) -> void:
	var strength := clampf(float(result.get("strength", 0.0)), 0.0, 1.0)
	var now := _now_s()
	stamina = maxi(0, stamina - 1)
	if _pump_bobs:
		_bob_speed_scale = _bob_response_scale(float(result.get("speed", 0.0)))
		_bob_velocity += BOB_PUMP_IMPULSE * _bob_speed_scale
		_lean_velocity += BOB_FORWARD_IMPULSE * _bob_speed_scale
	_wing_flick = lerpf(WING_FLICK_MIN, WING_FLICK_MAX, strength)
	if _winged and not _wing_hold and now - _last_wing_flutter >= WING_FLUTTER_COOLDOWN_S:
		var excitement: Variant = pony.get("excitement")
		if excitement != null and excitement.has_method("flutter"):
			excitement.call("flutter")
			_last_wing_flutter = now
	_pump_jiggle(strength)
	if pose_id == CATALOG.HORSE and is_instance_valid(_tail):
		_tail.call("pump", strength * _jiggle_size_scale())
	if _feature("camera_rock"):
		_camera_rock_velocity += CAMERA_ROCK_IMPULSE * strength * _camera_rock_sign
		_camera_rock_sign = -_camera_rock_sign
	if pose_id == CATALOG.HORSE:
		if _feature("rump_blush") and strength >= RUMP_BLUSH_MIN_STRENGTH:
			_rump_blush = minf(RUMP_BLUSH_MAX, _rump_blush + RUMP_BLUSH_STEP)
			_ensure_rump_decal()
		if _feature("ear_twitch") and is_instance_valid(_ear_twitch):
			_ear_twitch.call("try_trigger", strength)
	_pump_times.append(now)
	while not _pump_times.is_empty() and now - float(_pump_times[0]) > 1.0:
		_pump_times.pop_front()
	_play_kiss()
	_play_vocal()
	if satisfaction == 0 or satisfaction % 10 == 0:
		_log("pump satisfaction=%d stamina=%d rate=%.1f/s strength=%.2f" % [
			satisfaction, stamina, _pumps_per_second(), strength])


## Slow strokes get a slower spring. Scaling stiffness by s², damping by s and the
## impulse by s keeps the peak displacement while stretching the response in time.
func _bob_response_scale(speed: float) -> float:
	return clampf(speed / BOB_SPEED_REFERENCE, BOB_SPEED_SCALE_MIN, 1.0)


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
	# Only too-deep reactions remain; shallow reactions were removed for chattiness.
	if depth > band.y:
		_depth_out_seconds += delta
	else:
		_depth_out_seconds = 0.0
	if _depth_out_seconds < 1.2:
		return
	if _reaction_ready("depth_deep", 12.0):
		_queue_utterance("depth_deep", "depth_deep", "depth_deep")


func _reaction_ready(kind: String, cooldown: float) -> bool:
	if not _utterance_channel_free():
		return false
	var now := _now_s()
	if now - _last_utterance_at < UTTERANCE_MIN_GAP_S:
		return false
	if now - float(_last_reaction.get(kind, -1000.0)) < cooldown:
		return false
	_last_reaction[kind] = now
	return true


## True while the director or the pony is actually speaking. Unlike
## `_utterance_channel_free`, this ignores our own pending key, so a queued line can tell the
## difference between "still talking" and "stuck".
func _speech_busy() -> bool:
	var director := _director()
	if director != null and str(director.get("state")) != "idle":
		return true
	if is_instance_valid(pony) and pony.has_method("is_speaking") and bool(pony.call("is_speaking")):
		return true
	return false


## True when no mod line is pending and the director/pony are not already speaking. This
## keeps a new intent from being queued while the previous reply is still finishing its voice.
func _utterance_channel_free() -> bool:
	if not _utterance_pending_key.is_empty() or not _utterance_done_key.is_empty():
		return false
	return not _speech_busy()


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
	_release_finished_utterance()
	if not _utterance_pending_key.is_empty():
		if _now_s() > _utterance_pending_until and not _speech_busy():
			_log("utterance timeout key=%s" % _utterance_pending_key)
			_cancel_pending_utterance()
		else:
			# A line is already in flight (or still speaking). Do not build a backlog: accept
			# that these points are skipped and advance past them.
			while _utterance_index < _utterance_points.size() \
					and float(satisfaction) + _satisfaction_frac >= _utterance_points[_utterance_index]:
				_log("utterance skipped point=%d pending" % _utterance_index)
				_utterance_index += 1
			return
	if not _utterance_channel_free():
		return
	if _now_s() - _last_utterance_at < UTTERANCE_MIN_GAP_S:
		return
	while _utterance_index < _utterance_points.size() \
			and float(satisfaction) + _satisfaction_frac >= _utterance_points[_utterance_index]:
		var point := _utterance_index
		_utterance_index += 1
		_queue_utterance("scheduled", "utterance", "point_%d" % point)
		if not _utterance_pending_key.is_empty():
			return


func _queue_utterance(kind: String, prompt_key: String, key_suffix: String) -> bool:
	if state != State.ACTIVE or not is_instance_valid(main) or not is_instance_valid(main.game):
		return false
	if not _utterance_channel_free():
		return false
	var now := _now_s()
	if now - _last_utterance_at < UTTERANCE_MIN_GAP_S:
		return false
	var template := str(_act_prompts.get(prompt_key, ""))
	if template.strip_edges().is_empty():
		template = str(_act_prompts.get("utterance", ""))
	if template.strip_edges().is_empty():
		_log("utterance missing prompt kind=%s" % kind)
		return false
	var values := {
		"state": UTTERANCE.state_line(
			pose_id, satisfaction, _climax_at, depth,
			float(_last_stroke.get("speed", 0.0)), str(_last_stroke.get("speed_zone", "ok")),
			str(_last_stroke.get("shape", "mixed")), _act_seconds),
		"preferences": PREFERENCES.describe(_preferences),
		"recent": _recent_lines(),
	}
	var purpose := UTTERANCE.format(template, values)
	_utterance_serial += 1
	var key := "%s:%d" % [key_suffix, _utterance_serial]
	var event_id := _event_id
	var valid := func() -> bool:
		# Deliberately independent of the act state: cancelling the act must not invalidate
		# a line that is already being generated or spoken. Explicit `_cancel_pending_utterance`
		# calls still cancel it at climax/afterglow boundaries.
		return is_instance_valid(pony) and _event_id == event_id
	var finished := func() -> void:
		_utterance_done(key)
	var queued := MEMORY.utterance_for(main.game, _id, event_id, key, purpose, valid, finished)
	if not queued:
		_log("utterance queue failed kind=%s" % kind)
		return false
	_utterance_pending_key = key
	_utterance_done_key = ""
	_utterance_done_at = 0.0
	_utterance_pending_until = now + UTTERANCE_QUEUE_TIMEOUT_S
	_last_utterance_at = now
	_log("utterance kind=%s key=%s" % [kind, key])
	return true


func _utterance_done(key: String) -> void:
	if _utterance_pending_key == key:
		_utterance_done_key = key
		_utterance_done_at = _now_s()
		_release_finished_utterance()


## The director can report a line finished before its final voice chunk has stopped. Keep the
## slot reserved until `_speech_busy()` is false, otherwise the next line can cut it off.
func _release_finished_utterance() -> void:
	if _utterance_done_key.is_empty() or _speech_busy():
		return
	if _now_s() - _utterance_done_at < UTTERANCE_RELEASE_HOLD_S:
		return
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	_utterance_done_key = ""
	_utterance_done_at = 0.0


func _cancel_pending_utterance() -> void:
	_utterance_done_key = ""
	_utterance_done_at = 0.0
	if _utterance_pending_key.is_empty():
		return
	var key := _utterance_pending_key
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	if is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.cancel_generated(main.game, _event_id, key)


## Drop act lines that are still queued, but let a line already being thought or spoken
## finish. Called at climax and at act restore.
func _drop_queued_utterance() -> void:
	if _utterance_pending_key.is_empty():
		return
	var key := _utterance_pending_key
	if _utterance_is_active(key):
		_log("utterance active, keep key=%s" % key)
		_utterance_pending_key = ""
		_utterance_pending_until = 0.0
		return
	_log("utterance queued, drop key=%s" % key)
	_cancel_pending_utterance()


func _utterance_is_active(key: String) -> bool:
	var director := _director()
	if director == null:
		return false
	var active := str(director.get("_authored_active"))
	return active == MEMORY.mod_key(_event_id, "line", key)


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


func _pump_jiggle(strength: float) -> void:
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
	var jiggle := clampf(strength, JIGGLE_MIN_STRENGTH, 1.0)
	_flank.call("_start_jiggle", 0, jiggle)
	# One shader center now covers both flanks, so scale the resolved amount up. Smaller ponies
	# get less shader travel from the same pump impulse.
	var amount: Variant = _flank.get("_jiggle_amount")
	if amount != null:
		_flank.set("_jiggle_amount", float(amount) * JIGGLE_RUMP_SCALE * _jiggle_size_scale())
	if not _jiggle_logged:
		_jiggle_logged = true
		var targets: Variant = _flank.get("_jiggle_targets")
		_log("jiggle rump at=%s root=%s normal=%s targets=%d" % [
			str(at), str(pony.global_position), str(normal),
			(targets as Array).size() if targets is Array else -1])


func _ensure_rump_decal() -> void:
	if is_instance_valid(_rump_decal):
		return
	if not is_instance_valid(pony):
		return
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch")
	var texture: Variant = FLANK_TOUCH.texture
	if not texture is Texture2D:
		return
	var decal := Decal.new()
	decal.name = "UnfplapRumpBlush"
	decal.texture_albedo = texture
	decal.modulate = Color("de5263")
	decal.size = Vector3(0.16, 0.10, 0.18)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.25
	decal.normal_fade = 0.6
	decal.cull_mask = 1 << 19
	decal.albedo_mix = 0.0
	decal.visible = false
	pony.add_child(decal)
	_rump_decal = decal


func _rump_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var back: Vector3 = pony.global_basis.z.normalized()
	var point: Vector3 = pony.global_position + Vector3.UP * JIGGLE_HEIGHT + back * JIGGLE_BACK
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		var skeleton := sk as Skeleton3D
		var left := skeleton.find_bone("pony_femur_L")
		var right := skeleton.find_bone("pony_femur_R")
		if left >= 0 and right >= 0:
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
			point = (a + b) * 0.5 + Vector3.UP * 0.08 + back * 0.10
	return point


func _rump_blush_tick(delta: float) -> void:
	if not _feature("rump_blush") or pose_id != CATALOG.HORSE:
		return
	if _rump_blush > 0.0:
		_rump_blush = maxf(0.0, _rump_blush - RUMP_BLUSH_DECAY * delta)
	if not is_instance_valid(_rump_decal):
		return
	if _rump_blush <= 0.001:
		_rump_decal.visible = false
		return
	var point := _rump_point()
	var back: Vector3 = pony.global_basis.z.normalized()
	var across := Vector3.UP.cross(back).normalized()
	if not point.is_finite() or across.length_squared() < 0.5:
		return
	var basis := Basis(across, back, across.cross(back)).orthonormalized()
	_rump_decal.global_transform = Transform3D(basis, point + back * 0.015)
	_rump_decal.albedo_mix = _rump_blush
	_rump_decal.visible = true


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
	state = State.CLIMAX
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0
	_schedule_climax_hearts()
	_climax_hearts_burst_at(_dock_point())
	_set_face(0.3, 0.0)
	if not _utterance_pending_key.is_empty():
		_log("climax utterance pending key=%s" % _utterance_pending_key)
		_drop_queued_utterance()
	_queue_climax_reaction()
	_play_climax()
	if is_instance_valid(main.hud):
		main.hud.set_state("CLIMAX")


## Three pulses: four bursts at the start, two after at least one second, one after at least
## another second. The dock burst is separate and fires from `_climax()`.
func _schedule_climax_hearts() -> void:
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()
	_heart_times.append(0.0)
	_heart_counts.append(4)
	var latest := maxf(1.0, CLIMAX_SECONDS - 0.4)
	var second := randf_range(1.0, minf(2.4, latest))
	var third := randf_range(second + 1.0, maxf(second + 1.0, latest))
	_heart_times.append(second)
	_heart_counts.append(2)
	_heart_times.append(third)
	_heart_counts.append(1)


func _climax_hearts_tick(delta: float) -> void:
	if _heart_times.is_empty():
		return
	_heart_elapsed += delta
	while _heart_index < _heart_times.size() and _heart_elapsed >= _heart_times[_heart_index]:
		var count := _heart_counts[_heart_index] if _heart_index < _heart_counts.size() else 1
		var at := _heart_times[_heart_index]
		_heart_index += 1
		for i: int in count:
			_climax_hearts_burst()
		_log("climax hearts pulse t=%.2f count=%d" % [at, count])


## Same effect as a boop (five drifting hearts, her heart colours) without counting a boop or
## restarting the blush/squeak reaction.
func _climax_hearts_burst() -> void:
	var boop: Variant = pony.get("boop_node") if is_instance_valid(pony) else null
	if boop != null and boop.has_method("celebrate"):
		boop.call("celebrate")


## A boop-heart burst moved to `origin` while keeping its random spread and drift.
func _climax_hearts_burst_at(origin: Vector3) -> void:
	if not is_instance_valid(pony) or not origin.is_finite():
		return
	var boop: Variant = pony.get("boop_node")
	if boop == null or not boop.has_method("celebrate"):
		return
	var stored: Variant = boop.get("_hearts")
	if not stored is Array:
		return
	var hearts: Array = stored
	var before := hearts.size()
	boop.call("celebrate")
	if hearts.size() <= before:
		return
	var first: Dictionary = hearts[before]
	var first_origin: Vector3 = first.get("origin", origin)
	var shift: Vector3 = origin - first_origin
	for i: int in range(before, hearts.size()):
		var heart: Dictionary = hearts[i]
		var old: Vector3 = heart.get("origin", origin)
		var moved := old + shift
		heart["origin"] = moved
		var sprite: Variant = heart.get("sprite")
		if sprite is Node3D:
			(sprite as Node3D).global_position = moved
	_log("climax dock hearts=%d" % (hearts.size() - before))


## Her dock is the tail base on the hair skeleton; fall back to the hips if it is unavailable.
func _dock_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		var tail := (hair as Skeleton3D).find_bone("mTail1")
		if tail >= 0:
			return (hair as Skeleton3D).global_transform * (hair as Skeleton3D).get_bone_global_pose(tail).origin
	var body: Variant = pony.get("skeleton")
	if body is Skeleton3D:
		var hips := (body as Skeleton3D).find_bone("pony_hips")
		if hips >= 0:
			return (body as Skeleton3D).global_transform * (body as Skeleton3D).get_bone_global_pose(hips).origin \
				+ pony.global_basis.z.normalized() * 0.18 + Vector3.UP * 0.05
	return pony.global_position + Vector3.UP * 0.7


func _queue_climax_reaction() -> void:
	var expiry := Time.get_ticks_msec() + 60000
	var valid := func() -> bool:
		return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
	MEMORY.reaction_for(main.game, _id, "climax", _event_id,
		"You have just climaxed during intimacy with Anon. Say one short sentence, at most 12 words, in your own voice. Staying quiet is fine. Do not describe anatomy.",
		valid)


func _finish_climax() -> void:
	MEMORY.climax_event(main.game, _id, _display_name, _event_id)
	MEMORY.commit_climax(main.game, _id, _display_name, _event_id)
	WITNESS.commit(main.game, _id, _display_name, _serial, pony)
	if pose_id == CATALOG.HORSE:
		_pose2_afterglow_begin()
	else:
		_afterglow_begin()


## Pose 2 also gets a held afterglow now that there are things to do in it.
func _pose2_afterglow_begin() -> void:
	_log("afterglow pose=%s legacy=%d pony=%s" % [pose_id, CATALOG.legacy_index(pose_id), str(pony.name)])
	_drop_queued_utterance()
	state = State.AFTERGLOW
	_afterglow_pose = pose_id
	_set_face(0.85, 0.9)
	if is_instance_valid(_pose):
		_pose.mode = "pose2"
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.55
		_tail.call("flick", 2)
	_inside_aftermath()
	if is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")


func _afterglow_begin() -> void:
	_log("afterglow pose=%s legacy=%d pony=%s" % [pose_id, CATALOG.legacy_index(pose_id), str(pony.name)])
	_drop_queued_utterance()
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
	state = State.RESTORE
	_restore_left = RESTORE_SECONDS
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
	_drop_queued_utterance()
	_set_inventory_hud_hidden(false)
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
	if affection != null:
		var kind := str(affection.get("kind"))
		# The base-game kiss runs through Affection; it is part of the act, not an interruption.
		var our_kiss := _base_kiss_active or _base_kiss_releasing
		if not kind.is_empty() and not (our_kiss and kind == "kiss"):
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

func _size_name() -> String:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return ""
	return str(settings.call("get_value", "ponies/size"))


func _size_scale() -> float:
	var size := _size_name()
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
		_pose1_source_fov = source.fov
		_pose1_source_near = source.near
		_pose1_source_far = source.far
		_pose1_source_cull = source.cull_mask
		_pose1_view.fov = _pose1_source_fov
		_pose1_view.near = _pose1_source_near
		_pose1_view.far = _pose1_source_far
		_pose1_view.cull_mask = _pose1_source_cull
		_log("pose1 view setup source_fov=%.1f near=%.3f far=%.0f" % [
			source.fov, source.near, source.far])
	# The pose-1 view aims itself at her face every frame (`apply_camera_motion`); the player look
	# controls are left alone so the bed/seated camera is not disturbed.
	_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
	_pose1_aim_until = Time.get_ticks_msec() + 1000
	_pose1_camera_log_until = Time.get_ticks_msec() + 2500
	_pose1_camera_log_next = 0
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
		_pose1_view.current = false
		_pose1_view.queue_free()
	_pose1_view = null
	if is_instance_valid(_pose1_prev_camera):
		# The game may have changed the player camera's projection during the act; restore the
		# exact projection captured before the mod-owned view took over.
		_pose1_prev_camera.fov = _pose1_source_fov
		_pose1_prev_camera.near = _pose1_source_near
		_pose1_prev_camera.far = _pose1_source_far
		_pose1_prev_camera.cull_mask = _pose1_source_cull
		_pose1_prev_camera.make_current()
		_log("pose1 view restore fov=%.1f near=%.3f far=%.0f" % [
			_pose1_prev_camera.fov, _pose1_prev_camera.near, _pose1_prev_camera.far])
	_pose1_prev_camera = null
	if is_instance_valid(main) and is_instance_valid(main.player):
		var source: Camera3D = main.camera() if is_instance_valid(main) else null
		if _pose1_player_rot_saved and is_instance_valid(source):
			source.rotation = _pose1_player_rotation
	_pose1_player_rot_saved = false


## Stable pose-1 camera target: the middle of her neck. The live nose (`listen_point`) moves as
## she aims/nuzzles and could end up behind the camera, which made the camera look backwards.
func _pose1_look_target() -> Vector3:
	if _pose1_look_point.is_finite():
		return _pose1_look_point
	var neck := _neck_midpoint()
	if neck.is_finite() and is_instance_valid(pony):
		var from: Vector3 = _pose1_view.global_position if is_instance_valid(_pose1_view) else _pose1_camera
		if from.is_finite() and (neck - from).dot(-pony.global_basis.z) >= -0.05:
			return neck
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
	var height := float(_pose_cfg.get("camera_height", POSE1_CAMERA_HEIGHT_M)) + POSE1_CAMERA_LIFT_M
	if _size_name() == "canon":
		height *= 0.9
	var target := root + Vector3.UP * height \
		- back * float(_pose_cfg.get("camera_forward", POSE1_CAMERA_FORWARD_M))
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


## Set up the free shot before the first camera frame. AnonPony and headset/VR keep the stock
## camera and do not enter this path.
func _begin_camera_mode() -> void:
	_free_camera_active = false
	_camera_basis_ready = false
	_reset_lean_state()
	_camera_rock = 0.0
	_camera_rock_velocity = 0.0
	_pose1_look_point = Vector3.INF
	_pose2_base_look = Vector3.INF
	_pose2_base_saved = false
	if _player_pony or _headset_view():
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_free_camera_active = true
	_camera = main.camera()
	if pose_id == CATALOG.HORSE and is_instance_valid(_camera):
		_pose2_base_local = _camera.position
		_pose2_base_saved = true
		_pose2_aim_until = Time.get_ticks_msec() + 1000
		_pose2_base_look = _pose2_neck_point()
		_apply_pose2_base_look()
		_install_anon_thrust()
	_apply_free_camera_lock()


## Lean/caress remain live through the pose-2 afterglow; pose 1 afterglow stays passive.
func toggle_lean_return() -> void:
	if not _act_actions_allowed():
		return
	_lean_return_enabled = not _lean_return_enabled
	_log("lean return %s" % ("on" if _lean_return_enabled else "hold"))


func _act_actions_allowed() -> bool:
	return state in [State.ACTIVE, State.CLIMAX] \
		or (state == State.AFTERGLOW and pose_id == CATALOG.HORSE)


## Q/E drive the side lean; W/S lean forward/back. Q/E add a forward-plus-side diagonal and
## also fire a pose reaction once the smoothed side lean crosses LEAN_FIRE.
func _lean_tick(delta: float) -> void:
	_reach_hand_return_tick()
	if not _act_actions_allowed():
		_end_caress()
		_end_smack_swing()
		_end_lean_action()
		_lean_forward = move_toward(_lean_forward, 0.0, delta / LEAN_RETURN_SECONDS)
		_lean_side = move_toward(_lean_side, 0.0, delta / LEAN_RETURN_SECONDS)
		_lean_view_forward = _lean_forward
		_lean_view_side = _lean_side
		return
	if not _free_camera_active or _player_pony or _headset_view() or get_tree().paused \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_end_caress()
		_end_lean_action()
		_lean_forward = move_toward(_lean_forward, 0.0, delta / LEAN_RETURN_SECONDS)
		_lean_side = move_toward(_lean_side, 0.0, delta / LEAN_RETURN_SECONDS)
		_lean_view_forward = _lean_forward
		_lean_view_side = _lean_side
		return
	var side := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		side -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		side += 1.0
	var forward := 0.0
	if Input.is_action_pressed("move_forward"):
		forward -= 1.0
	if Input.is_action_pressed("move_back"):
		forward += 1.0
	var targets := lean_targets(side, forward)
	_lean_forward = _lean_step(_lean_forward, targets.x, delta, _lean_return_enabled)
	_lean_side = _lean_step(_lean_side, targets.y, delta, _lean_return_enabled)
	var alpha := 1.0 - exp(-CAMERA_INERTIA_SMOOTH * delta)
	if _feature("camera_inertia"):
		_lean_view_forward = lerpf(_lean_view_forward, _lean_forward, alpha)
		_lean_view_side = lerpf(_lean_view_side, _lean_side, alpha)
	else:
		_lean_view_forward = _lean_forward
		_lean_view_side = _lean_side
	if not _lean_return_enabled:
		# Hold mode still breathes: a slow rock around the held lean, using the same camera
		# mapping, so Anon never freezes completely in place.
		_hold_rock_clock += delta
		_lean_view_forward = clampf(_lean_view_forward
			+ sin(_hold_rock_clock * 0.80) * 0.015, -1.0, 1.0)
		_lean_view_side = clampf(_lean_view_side
			+ sin(_hold_rock_clock * 0.57 + 1.1) * 0.0125, -1.0, 1.0)
	_lean_action_tick()
	_pose2_kiss_tick()
	_caress_tick()
	_smack_swing_tick()
	if pose_id == CATALOG.HORSE:
		_apply_pose2_lean_look()


## Pure mapping for tests: vector x is side, y is forward. Q/E contribute both.
static func lean_targets(move_x: float, move_y: float) -> Vector2:
	var side := clampf(move_x, -1.0, 1.0)
	var forward := clampf(-move_y + absf(side), -1.0, 1.0)
	return Vector2(forward, side)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size;
## smaller ponies need a longer lean to reach the same place. Canon (`0.66`) is +34%.
static func lean_size_scale_for(size_scale: float) -> float:
	return clampf(2.0 - size_scale, 0.75, 1.5)


func _lean_size_scale() -> float:
	return lean_size_scale_for(_size_scale())


## Per-size caress-point offsets. Unknown presets use the JRHNBR reference.
static func caress_profile_for(size_name: String) -> Dictionary:
	var profile: Dictionary = CARESS_PROFILES.get(size_name, CARESS_PROFILES["mounting"])
	return profile


func _caress_profile() -> Dictionary:
	return caress_profile_for(_size_name())


## Canon needs a little less travel in the standing pose than the other presets.
func _pose2_lean_scale() -> float:
	var scale := _lean_size_scale()
	if _size_name() == "canon":
		scale *= 0.8
	return scale


func _jiggle_size_scale() -> float:
	return clampf(_size_scale(), 0.5, 1.2)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size.
static func lean_distance(forward: float, size_scale := 1.0) -> float:
	var metres := LEAN_FORWARD_M if forward >= 0.0 else LEAN_BACK_M
	return metres * forward * size_scale


static func _lean_step(current: float, target: float, delta: float, auto_return := true) -> float:
	if not auto_return and is_zero_approx(target):
		return current
	var returning := absf(target) < absf(current) \
		and (is_zero_approx(target) or signf(target) == signf(current))
	var seconds := LEAN_RETURN_SECONDS if returning else LEAN_RAMP_SECONDS
	return move_toward(current, target, delta / maxf(seconds, 0.001))


## Pose support for the threshold-triggered side action.
static func lean_action_kind(pose: String, side: float) -> String:
	if pose == CATALOG.MISSIONARY and side < 0.0:
		return "kiss"
	if pose == CATALOG.HORSE:
		return "reach"
	return ""


## 0 = left cheek, 1 = right cheek, -1 = centered (caller picks at random).
static func smack_side_index(side: float) -> int:
	if side > 0.0:
		return 0
	if side < 0.0:
		return 1
	return -1


func _lean_action_tick() -> void:
	if not _act_actions_allowed():
		_end_lean_action()
		return
	var side := _lean_side
	if not _lean_action_active:
		if absf(side) >= LEAN_FIRE:
			_start_lean_action(side)
		return
	if absf(side) <= LEAN_RELEASE or signf(side) != signf(_lean_action_side):
		_end_lean_action()
		if absf(side) >= LEAN_FIRE:
			_start_lean_action(side)
		return
	if _lean_action_kind == "reach":
		_set_reach_hand()


func _start_lean_action(side: float) -> void:
	_lean_action_active = true
	_lean_action_side = side
	_lean_action_kind = lean_action_kind(pose_id, side)
	_lean_action_shoulder = ""
	if _lean_action_kind == "kiss":
		_custom_kiss_active = not _start_base_kiss()
		if _custom_kiss_active:
			_play_mouth_kiss()
			_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
	elif _lean_action_kind == "reach":
		_lean_action_shoulder = "L" if side < 0.0 else "R"
		_forced_glance = _lean_action_shoulder
		_glance_wait = 0.0
		_reach_hand_returning = false
		_reach_hand_started = 0
		_reach_hand_logged = false
		_set_reach_hand()
	_log("action fire pose=%s side=%.2f kind=%s shoulder=%s" % [
		pose_id, side, _lean_action_kind, _lean_action_shoulder])


static func pose2_kiss_wanted(key_down: bool, lean: float) -> bool:
	return key_down and absf(lean) >= POSE2_KISS_LEAN


func _pose2_kiss_tick() -> void:
	if pose_id != CATALOG.HORSE or not _act_actions_allowed():
		_end_pose2_kiss()
		return
	var want := pose2_kiss_wanted(Input.is_physical_key_pressed(KEY_F), _lean_side)
	if want and not _pose2_kiss_active:
		_pose2_kiss_active = true
		_custom_kiss_active = not _start_base_kiss()
		if _custom_kiss_active:
			_play_mouth_kiss()
			_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
		_log("pose2 kiss start lean=%.2f base=%s" % [
			_lean_side, str(_base_kiss_active)])
	elif not want and _pose2_kiss_active:
		_end_pose2_kiss()


func _end_pose2_kiss() -> void:
	if not _pose2_kiss_active:
		return
	_pose2_kiss_active = false
	_end_base_kiss()
	_custom_kiss_active = false
	_release_kiss_face()
	_log("pose2 kiss stop")


func _end_lean_action() -> void:
	_end_pose2_kiss()
	if _lean_action_kind == "kiss":
		var was_base := _base_kiss_active
		_end_base_kiss()
		_custom_kiss_active = false
		if not was_base:
			_release_kiss_face()
	elif _lean_action_kind == "reach":
		_begin_reach_release()
		_forced_glance = ""
		_glance_left = 0.0
		_glance_back = false
		_glance_wait = randf_range(
			float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)),
			float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))
	_lean_action_active = false
	_lean_action_side = 0.0
	_lean_action_kind = ""
	_lean_action_shoulder = ""


func _reset_lean_state() -> void:
	_end_caress()
	_end_smack_swing()
	_end_lean_action()
	_clear_reach_hand()
	_end_base_kiss()
	_custom_kiss_active = false
	_lean_forward = 0.0
	_lean_side = 0.0
	_lean_view_forward = 0.0
	_lean_view_side = 0.0
	_lean_return_enabled = _feature("lean_return")
	_hold_rock_clock = 0.0
	_kiss_amount = 0.0
	_kiss_sound_clock = 0.0
	_release_kiss_face()
	_restore_base_kiss_pose()


## Reuse the game's own kiss. `pony_kisser.begin_from_pony()` runs the same eligibility checks as
## a normal Ponese kiss, including `controls_locked`, so unlock for that one call only. The
## AffectionPose modifier is moved to the end of the skeleton chain so its kiss IK layers on top
## of the act pose instead of being overwritten by it.
func _start_base_kiss() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(main) \
			or not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	var affection: Variant = pony.get_node_or_null("Affection")
	var kisser: Variant = main.game.get("kisser")
	if not is_instance_valid(affection) or not is_instance_valid(kisser):
		return false
	if not str(affection.get("kind")).is_empty():
		return false
	var body: Node = main.player
	var was_locked := bool(body.get("controls_locked"))
	body.set("controls_locked", false)
	var begun := bool(kisser.call("begin_from_pony", pony))
	body.set("controls_locked", was_locked)
	if not begun:
		return false
	_base_kiss_active = true
	_base_kiss_releasing = false
	_base_kiss_affection = affection
	var pose_node: Variant = affection.get("pose")
	var sk: Variant = pony.get("skeleton")
	if pose_node is SkeletonModifier3D and sk is Skeleton3D:
		var index := (sk as Skeleton3D).get_children().find(pose_node)
		if index >= 0:
			_base_kiss_pose = pose_node as SkeletonModifier3D
			_base_kiss_pose_index = index
			(sk as Skeleton3D).move_child(_base_kiss_pose, (sk as Skeleton3D).get_child_count() - 1)
	_log("base kiss start pony=%s" % _id)
	return true


func _end_base_kiss() -> void:
	if not _base_kiss_active:
		return
	_base_kiss_active = false
	var affection: Variant = _base_kiss_affection
	if is_instance_valid(affection) and str(affection.get("kind")) == "kiss":
		affection.call("end")
		affection.call("cancel_afterglow")
	if is_instance_valid(main) and is_instance_valid(main.game):
		var kisser: Variant = main.game.get("kisser")
		if is_instance_valid(kisser):
			kisser.set("_active", null)
			kisser.set("_her_kiss", false)
			kisser.set("_used_hold", false)
	if is_instance_valid(main) and is_instance_valid(main.player) \
			and state in [State.ACTIVE, State.CLIMAX]:
		main.player.set_meta("kiss_hold", true)
	_base_kiss_releasing = is_instance_valid(_base_kiss_pose)
	if not _base_kiss_releasing:
		_base_kiss_affection = null


## Keep the AffectionPose last while its own 0.6 s release eases out, then restore the child order.
func _restore_base_kiss_pose() -> void:
	_base_kiss_releasing = false
	if is_instance_valid(_base_kiss_pose) and is_instance_valid(pony):
		var sk: Variant = pony.get("skeleton")
		if sk is Skeleton3D:
			var skeleton := sk as Skeleton3D
			var index := clampi(_base_kiss_pose_index, 0, skeleton.get_child_count() - 1)
			skeleton.move_child(_base_kiss_pose, index)
	_base_kiss_pose = null
	_base_kiss_pose_index = -1
	_base_kiss_affection = null
	_keep_chin_last()


## Her mouth stays at Anon's lips while the kiss channel is held, with a soft repeat sound.
func _kiss_tick(delta: float) -> void:
	if _base_kiss_releasing:
		var affection: Variant = _base_kiss_affection
		if not is_instance_valid(affection) or float(affection.get("amount")) <= 0.001:
			_restore_base_kiss_pose()
	if _base_kiss_active:
		_kiss_amount = move_toward(_kiss_amount, 0.0, delta / KISS_FADE_OUT)
		return
	var active := (_lean_action_active and _lean_action_kind == "kiss" and _custom_kiss_active) \
		or (_pose2_kiss_active and _custom_kiss_active)
	var target := 1.0 if active else 0.0
	var seconds := KISS_FADE_IN if target > _kiss_amount else KISS_FADE_OUT
	_kiss_amount = move_toward(_kiss_amount, target, delta / maxf(seconds, 0.001))
	if _kiss_amount <= 0.0001:
		_kiss_amount = 0.0
		return
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("touch"):
		expressions.call("touch", "affection", 0.25 * _kiss_amount,
			(1.0 - 0.05) * _kiss_amount)
	var head: Variant = pony.get("head")
	var mouth: Variant = head.get("mouth") if head != null else null
	if mouth != null:
		mouth.call("set_expression", "pout", 0.18 * _kiss_amount)
		mouth.call("set_expression", "open_soft", 0.025 * _kiss_amount)
	if not active:
		return
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		_play_mouth_kiss()
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


func _kiss_target(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	return view.global_position + view.global_basis * Vector3(0.0, -0.07, -0.02)


func _play_mouth_kiss() -> void:
	if not is_instance_valid(_mouth_kiss_sound):
		return
	var stream: AudioStream = _plap_streams.pick_random() if not _plap_streams.is_empty() else _kiss_stream
	if stream == null:
		return
	_mouth_kiss_sound.stream = stream
	_mouth_kiss_sound.global_position = _snout()
	_mouth_kiss_sound.volume_db = -22.0
	_mouth_kiss_sound.pitch_scale = randf_range(0.97, 1.03)
	_mouth_kiss_sound.play()


func _release_kiss_face() -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("release_touch"):
		expressions.call("release_touch", "affection")
	var head: Variant = pony.get("head")
	var mouth: Variant = head.get("mouth") if head != null else null
	if mouth != null:
		mouth.call("set_expression", "pout", 0.0)
		mouth.call("set_expression", "open_soft", 0.0)


## Shared shoulder touch point. The lean reach and the full-lean caress must use exactly the
## same point so their hands coincide.
func _shoulder_hand_point(side: String) -> Dictionary:
	if side.is_empty() or not is_instance_valid(pony):
		return {}
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return {}
	var skeleton := sk as Skeleton3D
	var bone := skeleton.find_bone("pony_shoulder_" + side)
	if bone < 0:
		return {}
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == "L":
		outward = -outward
	return {"palm": shoulder.origin + outward * 0.10 + Vector3.UP * 0.02,
		"outward": outward}


## Approximate phase-1 hand placement: the palm rests on the named shoulder. This uses the
## desktop hold-target path, so it does not need `request_action` or release `controls_locked`.
func _set_reach_hand() -> void:
	if _lean_action_shoulder.is_empty() or not is_instance_valid(pony):
		return
	var driver := _desktop_pose_driver()
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		return
	var info := _shoulder_hand_point(_lean_action_shoulder)
	if info.is_empty():
		return
	var outward: Vector3 = info["outward"]
	var palm: Vector3 = info["palm"]
	var side := "left" if _lean_action_shoulder == "L" else "right"
	# Hand-marker convention: local -Z is the fingers, +Y is the thumb/up, and the palm normal
	# is local -X for the right hand / +X for the left. A basis equal to the pony's body basis
	# therefore points the fingers forward, thumbs up and palms inward: the hand continues
	# straight from the wrist instead of rolling onto its edge.
	var basis: Basis = pony.global_basis.orthonormalized()
	var target := Transform3D(basis, palm)
	if _reach_hand_started <= 0:
		_reach_hand_started = Time.get_ticks_msec()
		_reach_hand_from = Transform3D.IDENTITY
		if driver.has_method("hand_frame"):
			var from_frame: Variant = driver.call("hand_frame", side)
			if from_frame is Transform3D:
				_reach_hand_from = from_frame
		_reach_hand_rest = _reach_hand_from
		_reach_hand_rest_valid = _reach_hand_from.is_finite()
	var frame := target
	if _reach_hand_started > 0 and _reach_hand_from.is_finite():
		var t := clampf(float(Time.get_ticks_msec() - _reach_hand_started)
			/ (REACH_HAND_BLEND_S * 1000.0), 0.0, 1.0)
		frame = _reach_hand_from.interpolate_with(target, smoothstep(0.0, 1.0, t))
	if not _reach_hand_logged:
		_reach_hand_logged = true
		var palm_normal: Vector3 = basis.x * (1.0 if side == "left" else -1.0)
		_log("reach hand side=%s x=%s y=%s z=%s fingers=%s palm=%s" % [
			side, str(basis.x), str(basis.y), str(basis.z), str(-basis.z), str(palm_normal)])
	driver.call("set_hold_target", side, frame, "rub")


func _caress_tick() -> void:
	if pose_id != CATALOG.HORSE:
		_end_caress()
		return
	var want := {
		"L": Input.is_physical_key_pressed(KEY_A),
		"R": Input.is_physical_key_pressed(KEY_D),
	}
	for side: String in ["L", "R"]:
		if bool(want[side]):
			if not bool(_caress_active[side]):
				_caress_active[side] = true
				_caress_started[side] = Time.get_ticks_msec()
				_caress_logged[side] = false
				_log("caress start side=%s" % side)
			_set_caress_hand(side)
		elif bool(_caress_active[side]):
			_end_caress_side(side)


func _end_caress_side(side: String) -> void:
	if not bool(_caress_active[side]):
		return
	var hand_side := "left" if side == "L" else "right"
	var driver := _desktop_pose_driver()
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", hand_side)
	_log("caress stop side=%s" % side)
	_caress_active[side] = false
	_caress_started[side] = 0
	_caress_logged[side] = false


func _end_caress() -> void:
	_end_caress_side("L")
	_end_caress_side("R")


## Slow oval palm movement on the chosen flank/side.
func _set_caress_hand(side: String) -> void:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank):
		return
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	var index := 0 if side == "L" else 1
	if not centers is Array or index >= (centers as Array).size() \
			or not normals is Array or index >= (normals as Array).size():
		return
	var centre: Variant = (centers as Array)[index]
	var normal_local: Variant = (normals as Array)[index]
	if not centre is Vector3 or not normal_local is Vector3:
		return
	var frame: Transform3D = _flank.global_transform
	var centre_world: Vector3 = frame * (centre as Vector3)
	var normal: Vector3 = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
	if normal.length_squared() < 0.001:
		return
	# Keep the offset on the outside of the body even if the stored normal is inverted.
	var outward: Vector3 = pony.global_basis.x.normalized()
	if side == "L":
		outward = -outward
	if normal.dot(outward) < 0.0:
		normal = -normal
	var size := _size_scale()
	var profile := _caress_profile()
	var flank_world: Vector3 = centre_world + Vector3.UP * float(profile.get("up", 0.16)) \
		+ pony.global_basis.z.normalized() * float(profile.get("back", 0.08)) \
		+ outward * float(profile.get("out", 0.0))
	var shoulder_world: Vector3 = flank_world
	var shoulder_info := _shoulder_hand_point(side)
	if not shoulder_info.is_empty():
		shoulder_world = shoulder_info["palm"]
	var side_world: Vector3 = flank_world.lerp(shoulder_world, 0.5) + Vector3.DOWN * (0.06 * size)
	var rump_top: Vector3 = flank_world + Vector3.UP * (0.12 * size) + outward * (0.02 * size)
	var lean := clampf(_lean_forward, -1.0, 1.0)
	var target_normal := outward
	if lean < 0.0:
		var t := clampf(-lean / CARESS_RUMP_LEAN, 0.0, 1.0)
		centre_world = flank_world.lerp(rump_top, t)
		target_normal = normal.lerp(Vector3.UP, t).normalized()
	elif lean <= 0.5:
		var t := lean * 2.0
		centre_world = flank_world.lerp(side_world, t)
		target_normal = normal.lerp(outward, t).normalized()
	else:
		var t := (lean - 0.5) * 2.0
		centre_world = side_world.lerp(shoulder_world, t)
	normal = target_normal
	var up := Vector3.UP.slide(normal).normalized()
	var across := up.cross(normal).normalized()
	var angle := float(Time.get_ticks_msec() - int(_caress_started[side])) * 0.001 * CARESS_SPEED_RAD_S
	var offset := (across * (cos(angle) * CARESS_OVAL_ACROSS)
		+ up * (sin(angle) * CARESS_OVAL_UP)) * (CARESS_RADIUS_M * size)
	var palm := centre_world + offset + normal * CARESS_SURFACE_LIFT_M
	var hand_side := "left" if side == "L" else "right"
	# Same hand-marker basis as the lean shoulder reach: fingers forward, thumb up, palm inward.
	var basis: Basis = pony.global_basis.orthonormalized()
	if not bool(_caress_logged[side]):
		_caress_logged[side] = true
		_log("caress hand side=%s normal=%s x=%s y=%s z=%s" % [
			hand_side, str(normal), str(basis.x), str(basis.y), str(basis.z)])
	var driver := _desktop_pose_driver()
	if is_instance_valid(driver) and driver.has_method("set_hold_target"):
		driver.call("set_hold_target", hand_side, Transform3D(basis, palm), "rub")


## Release from the shoulder smoothly rather than teleporting back.
func _begin_reach_release() -> void:
	if _lean_action_shoulder.is_empty():
		return
	var side := "left" if _lean_action_shoulder == "L" else "right"
	var driver := _desktop_pose_driver()
	_reach_hand_return_from = _reach_hand_from
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var current: Variant = driver.call("hand_frame", side)
		if current is Transform3D and (current as Transform3D).is_finite():
			_reach_hand_return_from = current
	if not _reach_hand_rest_valid or not _reach_hand_return_from.is_finite():
		_clear_reach_hand()
		return
	_reach_hand_return_side = side
	_reach_hand_return_started = Time.get_ticks_msec()
	_reach_hand_returning = true


func _reach_hand_return_tick() -> void:
	if not _reach_hand_returning:
		return
	if _reach_hand_return_side.is_empty():
		_reach_hand_returning = false
		return
	var driver := _desktop_pose_driver()
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_reach_hand_returning = false
		return
	var t := clampf(float(Time.get_ticks_msec() - _reach_hand_return_started)
		/ (REACH_HAND_RELEASE_S * 1000.0), 0.0, 1.0)
	if t >= 1.0:
		_reach_hand_returning = false
		if driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _reach_hand_return_side)
		_reach_hand_return_side = ""
		_reach_hand_started = 0
		_reach_hand_from = Transform3D.IDENTITY
		return
	var frame: Transform3D = _reach_hand_return_from.interpolate_with(
		_reach_hand_rest, smoothstep(0.0, 1.0, t))
	driver.call("set_hold_target", _reach_hand_return_side, frame, "rub")


func _clear_reach_hand() -> void:
	var side := ""
	if not _lean_action_shoulder.is_empty():
		side = "left" if _lean_action_shoulder == "L" else "right"
	elif not _reach_hand_return_side.is_empty():
		side = _reach_hand_return_side
	_reach_hand_returning = false
	_reach_hand_return_side = ""
	_reach_hand_started = 0
	_reach_hand_logged = false
	_reach_hand_from = Transform3D.IDENTITY
	_reach_hand_rest_valid = false
	if side.is_empty():
		return
	var driver := _desktop_pose_driver()
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", side)


func _desktop_pose_driver() -> Node:
	if is_instance_valid(_anon_thrust_driver):
		return _anon_thrust_driver
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return null
	var avatar: Node = main.player.find_child("AnonBody", true, false)
	if not is_instance_valid(avatar):
		return null
	var driver: Variant = avatar.get("desktop_pose_driver")
	return driver as Node if is_instance_valid(driver) else null


## Mouse-right smack. Leaning right selects her left cheek because that is the cheek he can
## reach; centered input picks one of the two real cheek points at random.
func smack() -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	var now := Time.get_ticks_msec()
	if _smack_active or now - _last_smack_ms < SMACK_COOLDOWN_MS:
		return
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank) or not _flank.has_method("impact"):
		return
	var index := smack_side_index(_lean_side)
	if index < 0:
		index = 0 if randf() < 0.5 else 1
	var at := Vector3.INF
	var normal := Vector3.UP
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	if centers is Array and index < (centers as Array).size() \
			and normals is Array and index < (normals as Array).size():
		var centre: Variant = (centers as Array)[index]
		var normal_local: Variant = (normals as Array)[index]
		if centre is Vector3 and normal_local is Vector3 and is_instance_valid(pony):
			# The mark centres are local to FlankTouch. Map the pony's backward and world-up
			# directions into that frame so the offset is right regardless of model axes.
			var back_local: Vector3 = (_flank.global_basis.inverse() * pony.global_basis.z).normalized()
			var up_local: Vector3 = (_flank.global_basis.inverse() * Vector3.UP).normalized()
			var angle := randf() * TAU
			var zone_radius := float(_profile.get("smack_zone_radius", SMACK_ZONE_RADIUS_M))
			var radius := sqrt(randf()) * maxf(0.0, zone_radius)
			at = (centre as Vector3) + back_local * (SMACK_BACK_M + cos(angle) * radius) \
				+ up_local * (SMACK_UP_M + sin(angle) * radius)
			var frame: Transform3D = _flank.global_transform
			normal = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
			var outward: Vector3 = (frame * (centre as Vector3)) - pony.global_position
			outward.y = 0.0
			if outward.length_squared() > 0.001 and normal.dot(outward.normalized()) < 0.0:
				normal = -normal
	_last_smack_ms = now
	if at.is_finite() and is_instance_valid(main) and is_instance_valid(main.player):
		var hand_side := "left" if index == 0 else "right"
		var driver := _desktop_pose_driver()
		var from_frame := Transform3D.IDENTITY
		if is_instance_valid(driver) and driver.has_method("hand_frame"):
			var current: Variant = driver.call("hand_frame", hand_side)
			if current is Transform3D and (current as Transform3D).is_finite():
				from_frame = current
		if is_instance_valid(driver) and from_frame.is_finite():
			var world_centre: Vector3 = _flank.global_transform * at
			var palm := world_centre + normal * SMACK_CONTACT_LIFT_M
			var fingers := (Vector3.UP - normal * normal.dot(Vector3.UP)).normalized()
			var across := normal * (1.0 if hand_side == "right" else -1.0)
			var hand_basis := Basis(across, -fingers.cross(across), -fingers)
			_smack_from = from_frame
			_smack_to = Transform3D(hand_basis, palm)
			_smack_index = index
			_smack_at = at
			_smack_side = hand_side
			_smack_started = now
			_smack_impact_done = false
			_smack_active = true
			_log("smack swing side=%.2f cheek=%s at=%s" % [
				_lean_side, "L" if index == 0 else "R", str(at)])
			return
	_flank_impact_without_reaction(index, at)
	_log("smack side=%.2f cheek=%s at=%s (instant)" % [
		_lean_side, "L" if index == 0 else "R", str(at)])


func _smack_swing_tick() -> void:
	if not _smack_active:
		return
	if _smack_side.is_empty():
		_smack_active = false
		return
	var driver := _desktop_pose_driver()
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_end_smack_swing()
		return
	var phase := clampf(float(Time.get_ticks_msec() - _smack_started)
		/ (SMACK_SWING_SECONDS * 1000.0), 0.0, 1.0)
	var arc := sin(phase * PI)
	var frame := _smack_from.interpolate_with(_smack_to, arc)
	driver.call("set_hold_target", _smack_side, frame, "rub")
	if not _smack_impact_done and phase >= SMACK_CONTACT_PHASE:
		_smack_impact_done = true
		_flank_impact_without_reaction(_smack_index, _smack_at)
	if phase >= 1.0:
		_end_smack_swing()


func _end_smack_swing() -> void:
	if not _smack_active:
		return
	if not _smack_side.is_empty():
		var driver := _desktop_pose_driver()
		if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _smack_side)
	_smack_active = false
	_smack_side = ""
	_smack_at = Vector3.INF
	_smack_impact_done = false


## Native impact, but with the pony's game reaction signals silenced. During an act those
## reactions can trigger a buck/fidget or hoof shuffle, which is not wanted for a sex smack.
func _flank_impact_without_reaction(index: int, at: Vector3) -> void:
	if not is_instance_valid(pony) or not pony.has_signal("physical_reaction"):
		_flank.call("impact", index, at)
		return
	var sig: Signal = pony.physical_reaction
	var links: Array = sig.get_connections()
	_log("smack reaction suppressed links=%d" % links.size())
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and sig.is_connected(callable):
			sig.disconnect(callable)
	_flank.call("impact", index, at)
	for link: Variant in links:
		var entry: Dictionary = link
		var callable: Variant = entry.get("callable")
		if callable is Callable and not sig.is_connected(callable):
			sig.connect(callable)


## Slight camera roll on each thrust; roll only, driven by a damped spring. Both poses.
func _camera_rock_tick(delta: float) -> void:
	if not _feature("camera_rock") or pose_id not in [CATALOG.HORSE, CATALOG.MISSIONARY] \
			or not _free_camera_active or state not in [State.ACTIVE, State.CLIMAX]:
		_camera_rock = 0.0
		_camera_rock_velocity = 0.0
		return
	var accel := -CAMERA_ROCK_STIFFNESS * _camera_rock - CAMERA_ROCK_DAMPING * _camera_rock_velocity
	_camera_rock_velocity += accel * delta
	_camera_rock = clampf(_camera_rock + _camera_rock_velocity * delta,
		-CAMERA_ROCK_LIMIT, CAMERA_ROCK_LIMIT)


## Pose-2 yaw/pitch from the lean vector, applied to the player camera on top of the base aim.
func _apply_pose2_lean_look() -> void:
	if not _free_camera_active or pose_id != CATALOG.HORSE or _player_pony or _headset_view():
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var lean_scale := _pose2_lean_scale()
	var yaw := _look_yaw + deg_to_rad(LEAN_SIDE_YAW_DEG) * _lean_view_side * lean_scale
	var pitch := clampf(
		_look_pitch - deg_to_rad(LEAN_PITCH_DEG) * absf(_lean_view_forward) * lean_scale,
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
func _apply_free_camera_lock() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Variant = main.player
	if not _controls_locked_by_camera:
		_controls_locked_saved = bool(body.get("controls_locked"))
		_controls_locked_by_camera = true
	body.set("controls_locked", true)


func _release_free_camera_lock() -> void:
	if not _controls_locked_by_camera:
		return
	if is_instance_valid(main) and is_instance_valid(main.player):
		main.player.set("controls_locked", _controls_locked_saved)
	_controls_locked_by_camera = false
	_controls_locked_saved = false


func _pose2_neck_point() -> Vector3:
	var neck := _neck_midpoint()
	if neck.is_finite():
		return neck
	if not is_instance_valid(pony):
		return Vector3.INF
	var scale := 1.0
	if pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	return pony.global_position + Vector3.UP * (POSE2_HEAD_NECK_HEIGHT_M * scale)


## Middle of the neck chain: midpoint of pony_neck1 and pony_neck2 world origins.
func _neck_midpoint() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return Vector3.INF
	var skeleton := sk as Skeleton3D
	var first := skeleton.find_bone("pony_neck1")
	var second := skeleton.find_bone("pony_neck2")
	if first >= 0 and second >= 0:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(first).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
		return (a + b) * 0.5
	if second >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
	return Vector3.INF


## Point the player's own camera at the middle of her neck. This is the fixed free shot.
func _apply_pose2_base_look() -> void:
	if _player_pony or _headset_view():
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var view: Camera3D = main.camera()
	if not is_instance_valid(view):
		return
	var target := _pose2_base_look
	if not target.is_finite():
		target = _pose2_neck_point()
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
	_look_yaw = yaw
	_look_pitch = pitch
	_camera_basis_ready = true
	_pose2_base_look = target
	if pose_id == CATALOG.HORSE and _has_facing:
		_facing_basis = Basis(Vector3.UP, yaw)
	_apply_pose2_lean_look()


func _install_anon_thrust() -> void:
	_remove_anon_thrust()
	if pose_id != CATALOG.HORSE or _player_pony or not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var avatar := main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return
	var original: Variant = avatar.get("desktop_pose_driver")
	if not is_instance_valid(original):
		return
	var driver: Node3D = ANON_THRUST.new()
	driver.name = "UnfplapAnonThrust"
	driver.set("original", original)
	driver.set("runtime", self)
	main.player.add_child(driver)
	avatar.set("desktop_pose_driver", driver)
	_anon_thrust_driver = driver
	_anon_thrust_original = original
	_anon_thrust_avatar = avatar


func _remove_anon_thrust() -> void:
	if is_instance_valid(_anon_thrust_avatar) and is_instance_valid(_anon_thrust_original) \
			and _anon_thrust_avatar.get("desktop_pose_driver") == _anon_thrust_driver:
		_anon_thrust_avatar.set("desktop_pose_driver", _anon_thrust_original)
	if is_instance_valid(_anon_thrust_driver):
		_anon_thrust_driver.queue_free()
	_anon_thrust_driver = null
	_anon_thrust_original = null
	_anon_thrust_avatar = null


## Called after anon_body has set the hip target, through the desktop pose-driver wrapper.
## The hip tracks raw mouse depth with no spring or return animation.
func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	if pose_id != CATALOG.HORSE or depth <= 0.0001 or not is_instance_valid(hip):
		return
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	hip.global_position += -facing.z.normalized() * (THRUST_MAX_M * scale * clampf(depth, 0.0, 1.0))


## Phase-2 Anon body lean: keep the pelvis planted behind her rump. The camera/head moves
## forward or sideways, so the torso hinges at the hips instead of the whole body sliding into
## her. Pulling back still moves the whole body away.
func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	if pose_id != CATALOG.HORSE or not _free_camera_active or not is_instance_valid(hip):
		return
	var forward := -facing.z.normalized()
	var side := facing.x.normalized()
	var lean_scale := _pose2_lean_scale()
	var forward_shift := lean_distance(maxf(_lean_view_forward, 0.0), lean_scale)
	hip.global_position -= forward * forward_shift
	hip.global_position -= side * (LEAN_SIDE_M * _lean_view_side * lean_scale)
	# Depth 1 moves the pelvis back; the chest/head stay forward, so the upper body pumps.
	hip.global_position -= forward * (clampf(depth, 0.0, 1.0) * ANON_PUMP_SWAY_M * lean_scale)


func apply_camera_motion() -> void:
	if state == State.IDLE or not _free_camera_active:
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
		_pose1_view.global_position = _pose1_camera + Vector3.UP * _bob
		# Pull the whole shot back along its own view axis; the frozen aim still points at her neck.
		_pose1_view.global_position += _pose1_view_basis.z * POSE1_CAMERA_PULLBACK_M
		var lean_scale := _lean_size_scale()
		var lean_forward := lean_distance(_lean_view_forward, lean_scale)
		if lean_forward < 0.0:
			# Never let the shot cross its own neck target; that used to flip the view backwards.
			var to_target := _pose1_look_target() - _pose1_camera
			var room := maxf(0.0, to_target.dot(-_pose1_view_basis.z) - 0.12)
			lean_forward = -minf(-lean_forward, room)
		_pose1_view.global_position -= _pose1_view_basis.z \
			* (_lean - _back + lean_forward)
		_pose1_view.global_position += _pose1_view_basis.x \
			* (LEAN_SIDE_M * _lean_view_side * lean_scale)
		# Freeze the neck target once the pose has blended in. The live snout moves with her
		# nuzzles and can end up behind the camera in the bed pose.
		if Time.get_ticks_msec() < _pose1_aim_until:
			var neck := _neck_midpoint()
			if neck.is_finite() \
					and (neck - _pose1_view.global_position).dot(-pony.global_basis.z) >= -0.05:
				_pose1_look_point = neck
			else:
				_pose1_look_point = Vector3.INF
			# Always aim from the stable anchor. Re-aiming from the already moved view created a
			# position/basis feedback loop that flickered at act start.
			_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
		_camera_basis_ready = true
		var rock := _camera_rock if _feature("camera_rock") else 0.0
		var lean := Basis.from_euler(Vector3(
			-deg_to_rad(LEAN_PITCH_DEG) * absf(_lean_view_forward) * lean_scale
				+ rock * CAMERA_ROCK_PITCH_RATIO,
			-deg_to_rad(LEAN_SIDE_YAW_DEG) * _lean_view_side * lean_scale,
			(-deg_to_rad(LEAN_SIDE_ROLL_DEG) * _lean_view_side
				+ deg_to_rad(LEAN_ROLL_DEG) * _lean_view_forward) * lean_scale + rock))
		_pose1_view.global_basis = _pose1_camera_tweak() * (_pose1_view_basis * lean)
		var look_dir := _pose1_look_target() - _pose1_view.global_position
		if look_dir.length_squared() > 0.000001 \
				and (-_pose1_view.global_basis.z).dot(look_dir.normalized()) < 0.9:
			_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
			_pose1_view.global_basis = _pose1_camera_tweak() * (_pose1_view_basis * lean)
			if not _pose1_aim_fix_logged:
				_pose1_aim_fix_logged = true
				_log("pose1 camera aim corrected target=%s dot=%.3f" % [
					str(_pose1_look_target()),
					(-_pose1_view.global_basis.z).dot(
						(_pose1_look_target() - _pose1_view.global_position).normalized())])
		if not _pose1_basis_logged:
			_pose1_basis_logged = true
			_log("pose1 camera base_euler=%s tweak_euler=%s applied_basis=%s" % [
				str(_pose1_view_basis.get_euler()), str(_pose1_camera_tweak().get_euler()),
				str(_pose1_view.global_basis)])
		var now := Time.get_ticks_msec()
		if now < _pose1_camera_log_until and now >= _pose1_camera_log_next:
			_pose1_camera_log_next = now + 100
			var dot := (-_pose1_view.global_basis.z).dot(look_dir.normalized()) \
				if look_dir.length_squared() > 0.000001 else 0.0
			_log("pose1 cam anchor=%s view=%s base_euler=%s target=%s dot=%.3f bed=%.2f pose=%.2f lean=%.2f/%.2f size=%s%.2f" % [
				str(_pose1_camera), str(_pose1_view.global_position),
				str(_pose1_view_basis.get_euler()), str(_pose1_look_target()), dot,
				bed_top, _pose_basis_amount(), _lean_view_forward, _lean_view_side,
				_size_name(), _size_scale()])
		return
	if _pose2_base_saved and Time.get_ticks_msec() < _pose2_aim_until:
		_pose2_base_look = _pose2_neck_point()
		_apply_pose2_base_look()
	var lean_scale := _pose2_lean_scale()
	_set_camera_offsets(_bob, _lean - _back + lean_distance(_lean_view_forward, lean_scale),
		LEAN_SIDE_M * _lean_view_side * lean_scale)
	if pose_id == CATALOG.HORSE and _free_camera_active and is_instance_valid(_camera):
		var rock := _camera_rock if _feature("camera_rock") else 0.0
		_camera.rotation.z = rock \
			+ (-deg_to_rad(LEAN_SIDE_ROLL_DEG) * _lean_view_side \
			+ deg_to_rad(LEAN_ROLL_DEG) * _lean_view_forward) * lean_scale
		_camera.rotation.x = clampf(
			_look_pitch - deg_to_rad(LEAN_PITCH_DEG) * absf(_lean_view_forward) * lean_scale,
			-1.5, 1.5) + (rock * CAMERA_ROCK_PITCH_RATIO)


## Optional manual pose-1 camera correction. Identity unless a future tuning pass needs a fixed
## basis offset.
func _pose1_camera_tweak() -> Basis:
	return Basis.IDENTITY


func _pose_basis_amount() -> float:
	return float(_pose.get("amount")) if is_instance_valid(_pose) else 0.0


func _pose2_eye_height() -> float:
	var height := _player_eye_height()
	if _size_name() == "canon":
		height -= CANON_POSE2_CAMERA_DROP_M
	return height


func _player_eye_height() -> float:
	var body: Variant = main.player if is_instance_valid(main) else null
	if is_instance_valid(body) and body.has_method("eye_height"):
		return float(body.call("eye_height"))
	if is_instance_valid(body) and body.get("_stand_eye") != null:
		return float(body.get("_stand_eye"))
	return 1.6


## Desktop human camera: vertical is absolute from the player's eye height, so `_set_eye_y`
## cannot stomp it. AnonPony's top-level camera keeps the delta form.
func _set_camera_offsets(vertical: float, forward: float, side: float = 0.0) -> void:
	if not is_instance_valid(_camera):
		return
	var seated := is_instance_valid(main) and is_instance_valid(main.player) and main.player.get("seat") != null
	var eye_height := _pose2_eye_height()
	if _pose2_base_saved and not _camera.top_level and not seated:
		_camera.position = Vector3(
			_pose2_base_local.x + side,
			eye_height + vertical,
			_pose2_base_local.z - forward)
		_applied_bob = vertical
		_applied_lean = forward
		_applied_side = side
		return
	var df := forward - _applied_lean
	var ds := side - _applied_side
	if _camera.top_level or seated:
		var dy := vertical - _applied_bob
		if absf(dy) > 0.00001:
			_camera.global_position += Vector3.UP * dy
		if absf(df) > 0.00001:
			_camera.global_position -= _camera.global_basis.z * df
		if absf(ds) > 0.00001:
			_camera.global_position += _camera.global_basis.x * ds
	else:
		_camera.position.y = eye_height + vertical
		if absf(df) > 0.00001:
			_camera.position.z -= df
		if absf(ds) > 0.00001:
			_camera.position.x += ds
	_applied_bob = vertical
	_applied_lean = forward
	_applied_side = side


func _capture_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_restore_yaw = float(main.player.rotation.y)
	var pitch: Variant = main.player.get("_pitch")
	_restore_pitch = float(pitch) if pitch != null else 0.0
	_look_yaw = _restore_yaw
	_look_pitch = _restore_pitch


## Restore the player's yaw/pitch captured at act start. Free look and the pose-2 look cone can
## leave the rig yawed after the act, which makes W/D move relative to a different facing than the
## camera. Restoring the captured look keeps movement and view aligned.
func _restore_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var yaw := _restore_yaw
	# Pose 1 restores the exact start snapshot; use its rig yaw rather than the later capture.
	if pose_id == CATALOG.MISSIONARY and _pose1_start_saved:
		yaw = _pose1_start_player_transform.basis.get_euler().y
	main.player.rotation.y = yaw
	if main.player.get("_pitch") != null:
		main.player.set("_pitch", _restore_pitch)
	if main.player.get("form_driver") == null:
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			view.rotation.x = _restore_pitch
			view.rotation.z = 0.0
	_reset_lean_state()
	_camera_rock = 0.0
	_camera_rock_velocity = 0.0
	_log("look restored yaw=%.3f (captured %.3f) pitch=%.3f" % [yaw, _restore_yaw, _restore_pitch])


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
		var back_target := 1.0 if (not _forced_glance.is_empty() \
			or (_glance_left > 0.0 and _glance_back)) else 0.0
		_glance_head_back = move_toward(_glance_head_back, back_target, delta / GLANCE_BACK_FADE)
		_pose.set("head_back", _glance_head_back)
	var secondary: Variant = pony.get("secondary")
	if not _forced_glance.is_empty():
		_glance_sign_set = true
		_glance_sign = 1.0 if _forced_glance == "L" else -1.0
		_glance_back = true
		if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
			secondary.call("look_toward", _glance_angles(), 0.4)
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
			clampf(yaw, -GLANCE_BACK_YAW, GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg.get("glance_yaw", GLANCE_YAW))
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)


## Free look, but inside a 45-degree cone around the direction the act began in. Movement stays
## held by kiss_hold; this only limits where the camera can turn.
func _clamp_look() -> void:
	if pose_id == CATALOG.MISSIONARY:
		# Pose 1 uses the mod-owned view; the player's body look is left alone.
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
	_end_caress()
	_end_smack_swing()
	_end_lean_action()
	_clear_reach_hand()
	_release_free_camera_lock()
	_remove_anon_thrust()
	_restore_eye_override()
	_restore_anon_avatar()
	_free_pose1_view()
	if is_instance_valid(_camera):
		if _pose2_base_saved:
			_camera.position = Vector3(_pose2_base_local.x, _player_eye_height(), _pose2_base_local.z)
		elif _camera.top_level:
			if absf(_applied_bob) > 0.00001:
				_camera.global_position -= Vector3.UP * _applied_bob
			if absf(_applied_lean) > 0.00001:
				_camera.global_position += _camera.global_basis.z * _applied_lean
			if absf(_applied_side) > 0.00001:
				_camera.global_position -= _camera.global_basis.x * _applied_side
		else:
			_camera.position.y = _player_eye_height()
			_camera.position.z += _applied_lean
			_camera.position.x -= _applied_side
	_applied_bob = 0.0
	_applied_lean = 0.0
	_applied_side = 0.0
	_bob = 0.0
	_bob_velocity = 0.0
	_bob_speed_scale = 1.0
	_lean = 0.0
	_lean_velocity = 0.0
	_back = 0.0
	_back_target = 0.0
	_pose1_camera = Vector3.INF
	_camera_basis_ready = false
	_pose2_base_saved = false
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

	_mouth_kiss_sound = AudioStreamPlayer3D.new()
	_mouth_kiss_sound.name = "UnfplapMouthKiss"
	_mouth_kiss_sound.bus = _breath.bus
	_mouth_kiss_sound.unit_size = 1.0
	_mouth_kiss_sound.max_distance = 4.0
	add_child(_mouth_kiss_sound)

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
	if is_instance_valid(_mouth_kiss_sound):
		_mouth_kiss_sound.stop()
		_mouth_kiss_sound.queue_free()
		_mouth_kiss_sound = null
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
	_kiss_sound.global_position = _rump_point()
	_kiss_sound.unit_size = 1.0
	_kiss_sound.max_distance = 6.0
	_kiss_sound.volume_db = -22.0
	_kiss_sound.pitch_scale = randf_range(0.95, 1.05)
	_kiss_sound.play()


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
		interval = BREATH_CLIMAX_INTERVAL_S
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
