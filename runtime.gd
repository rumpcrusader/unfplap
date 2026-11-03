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
const THRUST := preload("res://mods/unfplap/thrust.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const UTTERANCE := preload("res://mods/unfplap/utterance.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/relationship_cue.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const ANON_THRUST := preload("res://mods/unfplap/anon_thrust.gd")
const CHIN_DEBUG := preload("res://mods/unfplap/chin_debug.gd")
const BODY_SWAY := preload("res://mods/unfplap/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/prone_sway.gd")
const PALM_SCALE := preload("res://mods/unfplap/palm_scale.gd")
const EAR_TWITCH := preload("res://mods/unfplap/ear_twitch.gd")
const WING_SWEEP := preload("res://mods/unfplap/wing_sweep.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")
const VOICE := preload("res://mods/unfplap/voice_status.gd")
## Loaded lazily so both audio flags off never load the pack streams or the catalogue.
const ACT_AUDIO_PATH := "res://mods/unfplap/act_audio.gd"

enum State { IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE }

const READINESS_MAX := 100.0
## Her "close" cue. The player's afterglow is chosen separately.
const CLOSE_AT := 65.0
## Act eyelid values: half-lidded through ACTIVE, wide only at climax, sleepier afterglow.
const ACT_LIDS := 0.45
const CLIMAX_LIDS := 0.0
const AFTERGLOW_LIDS := 0.9
const AFTERGLOW_CLOSE_LIDS := 0.95
## Readiness that triggers one pony climax. The player's afterglow is separate.
const PONY_CLIMAX_AT := READINESS_MAX
const MAX_PONY_CLIMAXES := 3
## Readiness per real thrust. Both taste axes match, one axis matches, or neither matches.
const THRUST_HEAT_BOTH := 1.4
const THRUST_HEAT_ONE := 0.7
## Perceived intensity is scored from average stroke speed. Visual impact uses a separate
## scale so normal and fast thrusts move the rump and camera; slow and shallow strokes stay
## lighter.
const THRUST_IMPACT_GAIN := 2.0
const THRUST_HEAT_NONE := 0.0
## Never let a macro score faster than this.
const THRUST_SCORE_MIN_INTERVAL := 0.2
## Touch and talk can warm her to this point; only real thrusts can finish her.
const ASSIST_CAP := 60.0
const TOUCH_HEAT := 6.0
const TALK_HEAT := 6.0
const TOUCH_COOLDOWN_S := 4.0
const TALK_COOLDOWN_S := 8.0
## A liked touch/talk briefly makes real thrusts land harder.
const RECEPTIVE_S := 8.0
const RECEPTIVE_BOOST := 1.25
const CUE_OVERRIDE_S := 2.5
const OVERWHELM_S := 1.2
## Readiness text clears after this long without an inward thrust.
const STROKE_MEMORY_S := 1.2
## Mod-owned generated lines wait this long after the previous line starts, even when the
## director is free. Other systems keep their own scheduling.
const UTTERANCE_MIN_GAP_S := 18.0
## A changed cue must stay stable before it can become a line, so thrust variation does not
## fire a new request every stroke.
const CUE_STABLE_S := 2.0
## Demand lines ("She wants it…"/"She needs…") get their own budget and repeat lock.
const DEMAND_LINE_GAP_S := 28.0
const DEMAND_REPEAT_S := 45.0
## Appended to cue prompts to stop the model turning every cue into a command.
const CUE_REACTION_NOTE := "\nDo not turn the cue into a repeated command; say it as your own reaction or preference."
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
## After this long the mare may choose to end the afterglow herself. Being held or caressed
## lowers the chance; an accepted [stay] pauses the roll entirely.
const AFTERGLOW_SELF_END_SECONDS := 16.0
const AFTERGLOW_SELF_END_CHECK_S := 1.0
const AFTERGLOW_SELF_END_CHANCE_CLOSE := 0.12
const AFTERGLOW_SELF_END_CHANCE_ALONE := 0.30
## Pose 1 camera: above and behind her neck so the shot looks forward along her body at her
## face. `pony.global_basis.z` is her backward direction.
const POSE1_CAMERA_HEIGHT_M := 0.45
const POSE1_CAMERA_BACK_M := 0.22
## Default room between the pose-1 shot and the pony; the presentation setting overrides it.
const POSE1_CAMERA_PULLBACK_M := 0.22
## Extra height requested after the first visual pass.
const POSE1_CAMERA_LIFT_M := 0.10
## The pose-1 shot starts at the old maximum forward lean, so W pushes further up her torso
## instead of starting from the wide position. 1.0 is one full `LEAN_FORWARD_M` lean.
const POSE1_START_LEAN := 1.0
## Presentation: how close the pony stands in front of the player for pose 2.
const POSE2_GAP_M := 0.55
## Idle horse invitation: turn away from Anon at this rate before she settles into the stance.
const PRESENT_TURN_RATE := 2.4
## The game's supported standing turn steps the hooves. Its default 0.45 rad/s half-turn would
## take about 7 s, so the request speeds it up while it owns the turn.
const PRESENT_FACE_TURN_RATE := 1.5
## The locomotion's stepping turn stops at 3°, so settle just beyond that.
const PRESENT_TURN_SETTLE_RAD := 0.06
const PRESENT_TURN_TIMEOUT_S := 4.0
## A blocked ground probe can leave the stepping turn standing still; snap instead of waiting.
const PRESENT_TURN_STALL_S := 0.75
## The request's face: the act's half-lidded gaze and a full blush while she asks and presents.
const REQUEST_LIDS := 0.45
const REQUEST_BLUSH := 1.0
## Per-size pose-2 standing gap. Same Height is the tuned baseline; Hoers stays unchanged.
const POSE2_GAPS := {
	"same height": 0.55,
	"mounting": 0.45,
	"canon": 0.25,
	"hoers": 0.55,
}
## Camera thrust amplitudes at full slider and full speed. The camera follows the filtered
## thrust speed, never an impulse: surge moves forward, bob dips toward the bed.
const CAM_SURGE_M := 0.06
const CAM_BOB_M := 0.02
## Depth speed (depth/second) that reaches full camera travel.
const CAM_SPEED_REF := 4.0
## Low-pass on the raw depth speed, seconds.
const CAM_SPEED_SMOOTH_S := 0.06
## One critically damped camera response for surge and bob, seconds.
const CAM_RESPONSE_S := 0.12
## Outward strokes move the camera this fraction of the inward travel.
const CAM_BACK_RATIO := 0.5
## Climax camera amplitudes at full sliders. The sine keeps the same smooth envelope.
const CAM_CLIMAX_BOB_M := 0.008
const CAM_CLIMAX_SURGE_M := 0.02
## Hip phase low-pass on mouse depth. Depth is the input; this only removes single-frame
## mouse steps, it is not a speed attack.
const HIP_SMOOTH_S := 0.04
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
## Experiment: Anon's chest/head follow the thrust; the pelvis counter-moves so his upper body
## travels forward on the inward stroke and back on the outward stroke.
const ANON_THRUST_SWAY_M := 0.02
const LEAN_PITCH_DEG := 6.0
const LEAN_ROLL_DEG := 1.5
const LEAN_SIDE_ROLL_DEG := 8.0
const LEAN_SIDE_YAW_DEG := 3.0
## Hold-mode breathing amplitude in lean units, reduced 33% from the first pass
## (forward 0.015, side 0.0125).
const HOLD_SWAY_FORWARD := 0.010
const HOLD_SWAY_SIDE := 0.0084
## Q/E fire their pose reaction when the smoothed side lean crosses these values.
const LEAN_FIRE := 0.75
const LEAN_RELEASE := 0.60
## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35
## Pose-2 A/D caress: an oval rub on the flank surface. The oval is wider along the body
## than up/down, so the hand reads as stroking instead of drawing a perfect circle.
const CARESS_RADIUS_M := 0.04125
const CARESS_SPEED_RAD_S := 3.6
const CARESS_OVAL_ACROSS := 1.30
const CARESS_OVAL_UP := 0.70
## The rub centre is lifted this far above each size profile's `up` point. The cutie-mark
## anchor sits low on the flank; this keeps the stroke on the barrel instead of the belly.
const CARESS_UP_BIAS_M := 0.05
## A smack swings the caress hand to the cheek and back; ease the return so the contact reset
## does not read as a teleport.
const CARESS_RETURN_SECONDS := 0.12
## The palm ball's own collision radius (anon_body.gd hand sweep). The palm marker is its
## centre, so this is how far the centre sits above the coat when the visible palm touches.
const PALM_ON_COAT_CLEARANCE_M := 0.04
const PALM_CONTACT_SMOOTH := 18.0
const PALM_CONTACT_MAX_STEP_M := 0.06
const PALM_CONTACT_SOURCE_HITS := 2
## A palm normal may turn this fast when the coat normal moves or the contact source changes.
## Fast enough to track the coat, slow enough to avoid snapping.
const PALM_NORMAL_MAX_DEG_S := 120.0
## The clearance scales with the pony's actual body scale so Canon, JRHNBR and Hoers keep the
## same relative palm stand-off. Clamped so a malformed scale cannot push the hand far away.
static func palm_clearance_for(body_scale: float,
		distance := PALM_ON_COAT_CLEARANCE_M) -> float:
	return distance * clampf(body_scale, 0.5, 2.0)
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
## Displayed-lean smoothing. Always on.
const CAMERA_INERTIA_SMOOTH := 5.0
## Rump blush from strong thrusts: a fraction of the 0.8 smack decal strength. Always on.
const RUMP_BLUSH_MIN_STRENGTH := 0.55
const RUMP_BLUSH_STEP := 0.0525
const RUMP_BLUSH_MAX := 0.375
const RUMP_BLUSH_DECAY := 0.006
const POSE2_HEAD_NECK_HEIGHT_M := 1.0
## Canon is small enough that the standing shot needs a lower eye line.
const CANON_POSE2_CAMERA_DROP_M := 0.10
## JRHNBR is tall enough that the standing shot needs a higher eye line.
const MOUNTING_POSE2_CAMERA_LIFT_M := 0.10
## Anon's spine length, used to turn the pose-2 torso angle into head/camera travel.
const ANON_TORSO_LEN_M := 0.65
## Pose-2 Anon thrust: mouse depth (only lightly smoothed) moves the hip. This is position, not
## speed; the camera's speed-driven thrust is separate.
const THRUST_MAX_M := 0.045
## Safety cone for AnonPony's own body-yaw limit; the desktop act camera does not free-look.
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
## Pose 2 after the climax: Anon eases back before the act restores.
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Pose 2 after the climax: held afterglow; Anon stays put.
## The close window only exists in the horse afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5

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
## blend further toward fully open; readiness gradually opens them from here.
const WING_POSE2_HOLD := 0.65
const WING_POSE2_SPREAD := 0.25
## Afterglow eases the open wings all the way down to the folded resting pose. The game's
## release_hold() folds in about 0.3 s; this drives the same WingTuck blend slowly instead.
const WING_AFTERGLOW_RETURN_SECONDS := 6.0
## The game's flutter cycle is 3 × (0.16 + 0.13) = 0.87 s. A thrust may not restart it before
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
## Jiggle placement on the flank. The thrust scale is reduced 20% from the review pass; the
## native smack keeps its own strength.
const JIGGLE_HEIGHT := 0.78
const JIGGLE_BACK := 0.12
## `_start_jiggle` clamps strength to 0.3..1, so weak thrusts still move a little.
const JIGGLE_MIN_STRENGTH := 0.30
const JIGGLE_RUMP_SCALE := 2.8
## Smack decals target slightly higher and farther back along the flank than the mark centres.
const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08
const SMACK_ZONE_RADIUS_M := 0.035
const SMACK_COOLDOWN_MS := 200
const SMACK_SWING_SECONDS := 0.20
const SMACK_CONTACT_PHASE := 0.45
## Act kiss timing. The sound repeats softly while her mouth is held to Anon's.
const KISS_FADE_IN := 0.35
const KISS_FADE_OUT := 0.45
const KISS_SOUND_MIN := 2.0
const KISS_SOUND_MAX := 3.4
## Anon leans in while kissing. Pose 2 moves the act camera (and the hip counter keeps his
## pelvis planted); pose 1 moves the framing view and offsets the virtual mouth by the same
## amount, because its player camera is not the rendered shot.
const KISS_LEAN_M := 0.27
const KISS_LEAN_SIDE_M := 0.18
const KISS_LEAN_DROP_M := 0.035
const KISS_CAMERA_YAW_DEG := 10.0
const KISS_LEAN_SECONDS := 0.35
## `AffectionPose`'s lean/tilt sign is opposite the camera lean sign: `+1` rolls her head toward
## Anon's left, while a negative lean moves the camera to his left. Keep the mapping in one place.
## Kissing heads need complementary tilts, so she rolls away from his lean.
const KISS_PONY_SIDE_SIGN := 1.0

var pony
var main

var state: int = State.IDLE
var pose_id := ""
var source := ""
var bed: Node3D
## Her arousal/readiness, 0..100. At 100 she climaxes; the player chooses afterglow.
var satisfaction := 0.0
## Public for the HUD: mood and a short third-person cue.
var mood := "warming"
var cue := ""

## Public for the HUD/debug: how many pony climaxes this act has had.
var pony_climaxes := 0
## Public: penetration 0..1 and the same orientation flag used by mouse input.
var depth := 0.0
var thrust_up := true

var _pose
var _tail
## Idle horse invitation. Kept separate from the act's pose/tail so Y can take over cleanly.
var _presenting := false
var _present_turning := false
var _present_turn_started := 0.0
var _present_turn_last_yaw := 0.0
var _present_turn_still := 0.0
var _present_turn_rate_saved := -1.0
var _present_turn_rate_owned := false
var _present_pose
var _present_tail
var _present_yaw := 0.0
var _present_target_yaw := 0.0
var _present_look_point := Vector3.ZERO
var _present_face_direction := Vector3.ZERO
## Idle request face: blush and lids while a private offer is being asked or presented.
var _request_face := false
var _request_claimed_affection := false
var _debug_pose: Node
var _debug_pose_saved := Transform3D.IDENTITY
var _debug_pose_active := false
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
var _afterglow_pose := ""
var _afterglow_elapsed := 0.0
var _afterglow_hold_until := 0.0
var _self_end_clock := 0.0
var _action_executor: Node
var _close_left := 0.0
var _close_caress_seconds := 0.0
var _close_rewarded := false

var _player_pony := false
var _had_kiss_hold := false
var _locked_player := false
var _face_turn_rate_saved := -1.0
var _face_turn_rate_owned := false
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
var _taste: Dictionary = {}
var _act_prompts: Dictionary = {}
var _thrust_tracker
var _thrust_pixels_per_full := 480.0
var _camera_surge := 0.0
var _camera_bob := 0.0
## Last closed inward thrust; the pattern window is the last three to four thrusts.
var _last_stroke: Dictionary = {}
var _last_intensity := ""
var _last_pattern := ""
var _stroke_window: Array[Dictionary] = []
var _last_stroke_at := -1000.0
var _utterance_pending_key := ""
var _utterance_pending_until := 0.0
var _utterance_done_key := ""
var _utterance_done_at := 0.0
var _utterance_serial := 0
var _last_utterance_at := -1000.0
var _vocal_cooldown := 0.0
var _overwhelmed := 0.0
var _cue_override := ""
var _cue_until := 0.0
var _last_touch := ""
var _last_talk := ""
var _last_touch_at := -1000.0
var _last_thrust_score_at := -1000.0
var _receptive_until := 0.0
var _last_talk_at := -1000.0
var _last_talk_turn := -1
var _last_cue_text := ""
var _last_cue_seen := ""
var _cue_changed_at := 0.0
var _last_cue_line_at := -1000.0
var _last_demand_text := ""
var _last_demand_at := -1000.0
var _last_blocked_cue := ""
var _cue_gap := 12.0
var _used_memory_ids: Array[String] = []
var _peak_satisfaction := 0.0
var _act_both_matches := 0
var _act_dislikes := 0
var _act_liked_touch := 0
var _act_liked_talk := 0
var _last_player_talk := ""
var _peak_recorded := false
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
var _pose2_base_local := Vector3.ZERO
var _pose2_base_saved := false
var _restore_yaw := 0.0
var _restore_pitch := 0.0
var _controls_locked_saved := false
var _controls_locked_by_camera := false
var _anon_thrust_driver: Node3D
var _anon_thrust_original: Node
var _anon_thrust_avatar: Node3D
var _palm_scale: SkeletonModifier3D
var _chin_modifier: SkeletonModifier3D
var _body_sway: SkeletonModifier3D
var _prone_sway: SkeletonModifier3D
var _ear_twitch: SkeletonModifier3D
var _lean_forward := 0.0
var _lean_side := 0.0
var _lean_view_forward := 0.0
var _lean_view_side := 0.0
var _side_return_armed := false
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
var _caress_latched := {"L": false, "R": false}
var _caress_key_down := {"L": false, "R": false}
var _caress_moving := {"L": true, "R": true}
var _caress_move_key_down := {"L": false, "R": false}
var _caress_phase := {"L": 0.0, "R": 0.0}
var _caress_logged := {"L": false, "R": false}
var _caress_return_from := {"L": Transform3D.IDENTITY, "R": Transform3D.IDENTITY}
var _caress_return_started := {"L": 0, "R": 0}
var _caress_diag_at := 0
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
var _kiss_lean := 0.0
var _kiss_sound_clock := 0.0
var _custom_kiss_active := false
var _base_kiss_active := false
var _base_kiss_releasing := false
var _pose2_kiss_active := false
var _pose2_kiss_used := false
var _pose2_kiss_ready_at := 0
const KISS_RESTART_COOLDOWN_MS := 500
## Latched for the whole kiss (including the Affection release) so rock noise cannot flip sides.
var _kiss_camera_side := 0.0
var _kiss_pony_side := 0.0
var _kiss_diag_clock := 0.0
var _base_kiss_affection: Node
var _base_kiss_pose: SkeletonModifier3D
var _base_kiss_pose_index := -1
var _base_kiss_excitement: Node
var _base_kiss_beat: Timer
var _base_kiss_beat_paused := false
var _forced_glance := ""
var _depth_prev := 0.0
var _depth_speed := 0.0
var _presentation_cfg: Dictionary = {}
var _hip_phase := 0.0
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
var _pose1_camera_applied := Vector3.INF
var _pose1_head_roll := 0.0
var _pose1_start_camera: Camera3D
var _pose1_start_camera_transform := Transform3D.IDENTITY
var _pose1_start_player_transform := Transform3D.IDENTITY
var _pose1_start_pony_transform := Transform3D.IDENTITY
var _pose1_start_pony_posture := ""
var _pose1_start_saved := false
var _pose1_basis_logged := false
var _pose1_camera_log_until := 0
var _pose1_camera_log_next := 0
var _pose1_view: Camera3D
var _pose1_source_fov := 75.0
var _pose1_source_near := 0.05
var _pose1_source_far := 4000.0
var _pose1_source_cull := 0xFFFFFFFF
var _pose1_view_basis := Basis.IDENTITY
var _pose1_last_view_basis := Basis.IDENTITY
var _pose1_last_view_pos := Vector3.INF
var _pose1_last_head := Transform3D.IDENTITY
var _pose1_camera_rebuilds := 0
var _pose1_snap_ready := false
var _pose1_aim_until := 0
var _pose1_prev_camera: Camera3D
var _pose1_player_rotation := Vector3.ZERO
var _pose1_player_rot_saved := false
var _anon_avatars: Array[Node3D] = []
var _anon_avatar_states: Array[bool] = []
var _desktop_presentation: Node
var _desktop_presentation_enabled := true
var _lower_left := Transform3D.IDENTITY
var _lower_right := Transform3D.IDENTITY
var _lower_captured := false
var _bob := 0.0
var _bob_velocity := 0.0
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
var _wing_sweep: SkeletonModifier3D
var _wing_returning := false
var _wing_return_done := false
var _wing_return_node: Node
var _wing_return_progress := 0.0
var _wing_return_from_tuck := 0.0
var _wing_return_from_half := 0.0
const WING_SWEEP_DEG := 10.0
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
var _palm_contacts: Dictionary = {}
var _jiggle_logged := false
var _dock_jiggle_mesh: MeshInstance3D
var _dock_jiggle_material: ShaderMaterial
var _dock_jiggle_original: Material
var _climax_sound: AudioStreamPlayer3D
var _kiss_stream: AudioStream
var _climax_streams: Array[AudioStream] = []
var _thrust_times: Array[float] = []
var _act_audio: Node
var _bed_soft := false


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
	if _wing_returning:
		if is_instance_valid(_wing_return_node):
			_wing_return_node.set_process(true)
		_wing_returning = false
		_wing_return_done = false
		_wing_return_node = null
		_wing_return_progress = 0.0
		_clear_wing_sweep()
		_wing_hold = false
		_wing_hold_started = false
		_wings_node = null
		return
	if _wing_hold and is_instance_valid(_wings_node) and _wings_node.has_method("release_hold"):
		_wings_node.call("release_hold", "unfplap")
	_clear_wing_sweep()
	_wing_hold = false
	_wing_hold_started = false
	_wings_node = null


## Afterglow: clear the act's wing hold, then drive the same WingTuck blend to a full fold
## over WING_AFTERGLOW_RETURN_SECONDS. The game's own release path only takes 0.3 s.
func _begin_wing_afterglow() -> void:
	if not _winged or not is_instance_valid(_wings_node) \
			or not _wings_node.has_method("release_hold"):
		return
	var wings: Node = _wings_node
	_clear_wing_sweep()
	wings.call("release_hold", "unfplap")
	wings.call("set_open", false)
	var tuck_value: Variant = wings.get("tuck")
	var half_value: Variant = wings.get("half")
	_wing_return_from_tuck = float(tuck_value) if tuck_value != null else 0.0
	_wing_return_from_half = float(half_value) if half_value != null else 0.0
	_wing_return_node = wings
	_wing_return_progress = 0.0
	_wing_return_done = false
	_wing_returning = true
	wings.set("opened", false)
	wings.set_process(false)
	_wing_hold = false
	_wing_hold_started = false
	_log("wing afterglow return %.1fs from tuck=%.2f half=%.2f" % [
		WING_AFTERGLOW_RETURN_SECONDS, _wing_return_from_tuck, _wing_return_from_half])


func _wing_return_tick(delta: float) -> void:
	if not is_instance_valid(_wing_return_node):
		_wing_returning = false
		_wing_return_done = false
		_wing_return_node = null
		return
	if _wing_return_done:
		return
	_wing_return_progress = minf(1.0,
		_wing_return_progress + delta / maxf(WING_AFTERGLOW_RETURN_SECONDS, 0.001))
	var eased := smoothstep(0.0, 1.0, _wing_return_progress)
	_wing_return_node.set("tuck", lerpf(_wing_return_from_tuck, 1.0, eased))
	_wing_return_node.set("half", lerpf(_wing_return_from_half, 0.0, eased))
	_wing_return_node.set("opened", false)
	_wing_return_node.set_process(false)
	if _wing_return_progress >= 1.0:
		_wing_return_done = true
		# The wing node's own process finalizes the fold: hides the open meshes, shows folded.
		_wing_return_node.set_process(true)
		_log("wing afterglow return complete")


func _ensure_wing_sweep() -> void:
	if pose_id != CATALOG.HORSE or not _wing_hold or not is_instance_valid(pony):
		_clear_wing_sweep()
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	if not is_instance_valid(_wing_sweep):
		var sweep: Node3D = WING_SWEEP.new()
		sweep.name = "UnfplapWingSweep"
		skeleton.add_child(sweep)
		sweep.call("setup", skeleton, WING_SWEEP_DEG)
		_wing_sweep = sweep as SkeletonModifier3D
		_log("wing sweep %.0f deg" % WING_SWEEP_DEG)
	var last := skeleton.get_child_count() - 1
	if _wing_sweep.get_index() != last:
		skeleton.move_child(_wing_sweep, last)
	_wing_sweep.set("amount", 1.0)


func _clear_wing_sweep() -> void:
	if is_instance_valid(_wing_sweep):
		_wing_sweep.queue_free()
	_wing_sweep = null


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


func _feature(name: String) -> bool:
	return bool(_features.get(name, true))


## Re-read the settings tab's live-editable values during an act. Feature installs/removals are
## idempotent so repeated edits do not stack modifiers.
func apply_live_settings() -> void:
	if state == State.IDLE:
		return
	var previous_mute := bool(_features.get("mute_ponese_audio", false))
	_features = SETTINGS.features()
	var foley := _feature("act_foley")
	var vocals := _feature("act_vocals")
	var climax := _feature("act_climax")
	if foley or vocals or climax:
		_ensure_act_audio(foley, vocals, climax)
	elif is_instance_valid(_act_audio):
		_act_audio.set_enabled(false, false, false)
	var thrust_controls := SETTINGS.thrust_controls()
	thrust_up = bool(thrust_controls.get("up", true))
	_thrust_pixels_per_full = float(thrust_controls.get("pixels_per_full", 480.0))
	var camera_thrust := SETTINGS.camera_thrust_controls()
	_camera_surge = float(camera_thrust.get("surge", 0.0))
	_camera_bob = float(camera_thrust.get("bob", 0.0))
	_presentation_cfg = SETTINGS.presentation_controls(pose_id)
	# Nudge the frozen pose-1 anchor only when the framing control actually changed, so a taste
	# edit does not snap the shot. Move by the delta instead of recomputing from the pony: she
	# has settled since the start anchor was taken and the bed reference may be gone.
	var pose1_offsets := _pose1_camera_offsets()
	if pose_id == CATALOG.MISSIONARY and state != State.IDLE and is_instance_valid(pony) \
			and _pose1_camera.is_finite() \
			and not pose1_offsets.is_equal_approx(_pose1_camera_applied):
		var delta := pose1_offsets - _pose1_camera_applied
		_pose1_camera += -pony.global_basis.z.normalized() * delta.x
		_pose1_camera.y += delta.y
		_pose1_camera += pony.global_basis.x.normalized() * delta.z
		_pose1_camera_applied = pose1_offsets
		if _pose1_look_point.is_finite():
			_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
	if not _id.is_empty():
		_taste = SETTINGS.taste(_id)
	_refresh_live_modifiers()
	if previous_mute != _feature("mute_ponese_audio"):
		_refresh_live_voice()
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.update_from(self, hud_readouts())


func _refresh_live_modifiers() -> void:
	if not is_instance_valid(pony):
		return
	var skeleton_value: Variant = pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		return
	var skeleton := skeleton_value as Skeleton3D
	if not _feature("thrust_tail_dock_jiggle"):
		_restore_dock_jiggle_material()
	if pose_id == CATALOG.HORSE:
		if _feature("pose2_body_sway") and not is_instance_valid(_body_sway):
			_install_body_sway(skeleton)
		elif not _feature("pose2_body_sway") and is_instance_valid(_body_sway):
			_body_sway.queue_free()
			_body_sway = null
		if _feature("thrust_ear_twitch") and not is_instance_valid(_ear_twitch):
			_install_ear_twitch()
		elif not _feature("thrust_ear_twitch") and is_instance_valid(_ear_twitch):
			_ear_twitch.queue_free()
			_ear_twitch = null
		_refresh_palm_scale()
	elif pose_id == CATALOG.MISSIONARY:
		if _feature("pose1_body_motion") and not is_instance_valid(_prone_sway):
			_install_prone_sway(skeleton)
		elif not _feature("pose1_body_motion") and is_instance_valid(_prone_sway):
			_prone_sway.queue_free()
			_prone_sway = null


func _refresh_live_voice() -> void:
	if not is_inside_tree():
		return
	_restore_voice_volume()
	_apply_voice_policy()


## Optional HUD cue and readiness readouts. The act continues without them.
func hud_readouts() -> bool:
	return bool(_features.get("hud_readouts", true))


## One compact HUD line: hearts, cue, then her preference versus yours. The close prompt is
## always kept in afterglow even when the optional readouts are off.
func hud_cue_line(show_readouts := true) -> String:
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return ""
	var parts: PackedStringArray = ["❤ %d/%d" % [pony_climaxes, MAX_PONY_CLIMAXES]]
	var cue_text := cue.strip_edges()
	var closing := state == State.AFTERGLOW
	if closing:
		var close_text := close_hint()
		if not close_text.is_empty():
			cue_text = close_text
	if show_readouts or closing:
		parts.append(cue_text if not cue_text.is_empty() else "—")
	return " | ".join(parts)


## Separate readiness/taste line under the cue. Empty outside ACTIVE/CLIMAX or when readouts off.
func hud_readiness_line(show_readouts := true) -> String:
	if not show_readouts or state not in [State.ACTIVE, State.CLIMAX]:
		return ""
	var have_intensity := _last_intensity if not _last_intensity.is_empty() else "—"
	var have_pattern := _last_pattern if not _last_pattern.is_empty() else "—"
	var want_intensity := str(_taste.get("intensity", "firm"))
	var want_pattern := str(_taste.get("pattern", "steady"))
	return "Wants: %s & %s | You: %s & %s" % [
		want_intensity, want_pattern, have_intensity, have_pattern]


## Strong blush for the whole act; pegasi/alicorns spread their wings and occasionally flutter.
func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act_seconds += delta
	if pose_id == CATALOG.MISSIONARY:
		_hide_anon_avatar_for_pose1()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", 1.0)
	# The optional debug pin reuses the boop-fluster response: it pins the ears back along the
	# skull. Off keeps normal ears; the blush and stare() eyelids are independent.
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster") and _feature("act_ear_pin"):
		expressions.call("fluster", 1.2)
	if not _winged:
		return
	if _wing_returning:
		_wing_return_tick(delta)
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
		var level := sqrt(clampf(float(satisfaction) / READINESS_MAX, 0.0, 1.0))
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
		_ensure_wing_sweep()
		return
	# Fallback when the half-open wing pose is unavailable.
	if satisfaction >= READINESS_MAX * 0.75:
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
		if _present_turning:
			_present_turn_process()
		elif _presenting:
			_presentation_process()
		if _request_face:
			_request_face_process()
		return
	_clamp_look()
	if is_instance_valid(_pose) and is_instance_valid(main):
		var view: Camera3D = main.camera()
		if pose_id == CATALOG.MISSIONARY and is_instance_valid(_pose1_view):
			view = _pose1_view
		var custom_kiss := _kiss_amount > 0.001 and not _base_kiss_active
		var kiss_view := _kiss_mouth_view()
		if is_instance_valid(view):
			if custom_kiss and is_instance_valid(kiss_view):
				_pose.look_point = _kiss_target(kiss_view)
			elif pose_id == CATALOG.MISSIONARY:
				# Look at Anon, not at the framing view: the shot now sits behind her neck and a
				# camera there would demand a half-turn and flip her head side to side.
				var head_view: Camera3D = kiss_view if is_instance_valid(kiss_view) else view
				_pose.look_point = _pose1_head_look_point(head_view)
			else:
				_pose.look_point = view.global_position
		_pose.kiss = _kiss_amount if custom_kiss else 0.0
		_pose.climaxing = state == State.CLIMAX
	var surge_target := 0.0
	var bob_target := 0.0
	if state == State.ACTIVE:
		var norm := clampf(_depth_speed / CAM_SPEED_REF, -1.0, 1.0)
		surge_target = norm * CAM_SURGE_M * _camera_surge \
			* (CAM_BACK_RATIO if norm < 0.0 else 1.0)
		bob_target = -norm * CAM_BOB_M * _camera_bob
	elif state == State.CLIMAX:
		_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)
		var wave := sin(_climax_progress * PI * 2.0 * float(CLIMAX_BOBS))
		surge_target = wave * CAM_CLIMAX_SURGE_M * _camera_surge
		bob_target = -wave * CAM_CLIMAX_BOB_M * _camera_bob
	_camera_thrust_tick(delta, surge_target, bob_target)
	var back_speed := AFTERGLOW_BACK_SPEED if state == State.AFTERGLOW else RESTORE_BACK_SPEED
	_back = move_toward(_back, _back_target, back_speed * delta)
	_breath_tick(delta)


## One critically damped response for both camera channels. The targets are velocity-driven
## metres, so the camera eases through the stroke instead of being kicked at its close.
func _camera_thrust_tick(delta: float, surge_target: float, bob_target: float) -> void:
	var omega := 1.0 / maxf(CAM_RESPONSE_S, 0.001)
	var surge_accel := omega * omega * (surge_target - _lean) - 2.0 * omega * _lean_velocity
	_lean_velocity += surge_accel * delta
	_lean += _lean_velocity * delta
	var bob_accel := omega * omega * (bob_target - _bob) - 2.0 * omega * _bob_velocity
	_bob_velocity += bob_accel * delta
	_bob += _bob_velocity * delta


## Mouse input. Vertical motion thrusts; the act camera intentionally ignores it for look.
func _input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if state in [State.ACTIVE, State.CLIMAX]:
		if _thrust_tracker != null:
			var amount: float = THRUST.mouse_to_depth(motion.relative.y, _thrust_pixels_per_full, thrust_up)
			_thrust_move(amount, _now_s())
		get_viewport().set_input_as_handled()


func _headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view"))


## Y is a deliberate hold, matching the game's 0.35 s bridal-carry hold. A tap does nothing,
## and the trigger latches until release so a held key cannot fire twice.
func _hold_y_tick(delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
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
	_log("hold Y state=%d climaxes=%d" % [state, pony_climaxes])
	if state == State.AFTERGLOW:
		end_afterglow()
	elif state == State.ACTIVE:
		if pony_climaxes > 0:
			_enter_afterglow()
		else:
			cancel()
	elif state == State.CLIMAX:
		_enter_afterglow()
	else:
		cancel()


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		# Last-resort safety: a missed exit path must not leave the quick slots hidden.
		if _inventory_hud_hidden:
			_set_inventory_hud_hidden(false)
		if _present_turning or _presenting:
			_presentation_physics(delta)
		return
	if not is_instance_valid(pony) or not is_instance_valid(main):
		force_stop()
		return
	if pony.sleeping:
		pony.sleeping = false
	_vocal_cooldown = maxf(0.0, _vocal_cooldown - delta)
	_keep_nav()
	_keep_act_attention()
	_pause_face_turn()
	_hold_y_tick(delta)
	_lean_tick(delta)
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_act_presentation(delta)
	_kiss_tick(delta)
	if state in [State.ACTIVE, State.CLIMAX]:
		_thrust_tick()
		if state == State.ACTIVE:
			_readiness_tick(delta)
			_talk_tick(delta)
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
	elif state == State.AFTERGLOW:
		_afterglow_tick(delta)
	elif state == State.RESTORE:
		_restore_left -= delta
		if _restore_left <= 0.0:
			_finish_restore()
	_lock_body_facing()
	_drive_glance(delta)
	_suppress_auto_cuddle()
	_clamp_look()
	_depth_speed_tick(delta)
	_hip_phase_tick(delta)
	_rump_blush_tick(delta)
	apply_camera_motion()
	if state in [State.POSING_IN, State.ACTIVE, State.AFTERGLOW]:
		_check_clock += delta
		if _check_clock >= 0.25:
			_check_clock = 0.0
			_check_running()
	_eyes_tick()


## The act owns the lids. Set at every transition, then reasserted late so a kiss release,
## climax return, or fluster peek cannot leave her wide-eyed while leaning.
func _eyes_tick() -> void:
	if not is_instance_valid(pony):
		return
	var lids := -1.0
	match state:
		State.POSING_IN, State.ACTIVE:
			lids = ACT_LIDS
		State.CLIMAX:
			lids = CLIMAX_LIDS
		State.AFTERGLOW:
			lids = AFTERGLOW_CLOSE_LIDS if _close_rewarded else AFTERGLOW_LIDS
	if lids < 0.0:
		return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("stare"):
		expressions.call("stare", true, lids)


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
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level=%d) welcomes=%s mood=%s | state=%d presenting=%s sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		display, id, float(distance), float(dot), stage, love_name, love_level, str(welcomes), mood,
		state, str(_presenting), str(pony.get("sleeping")), str(pony.is_held()), str(pony.grounded()), str(pony.has_meta("seated")),
		str(_cuddle_active()), str(pony.get("motion_paused")), float(pony.get("actual_speed")), str(status.get("requested")),
		str(pony.action_interruption_reason()), owner, str(target), reserved,
		str(body.get("controls_locked")) if body != null else "?",
		str(body.get("flying")) if body != null else "?",
		str(body.get("seat")) if body != null else "?",
		str(Input.mouse_mode), str(get_tree().paused),
		str(_relationship_ok()), str(_player_form_ok()), str(_conversation_ok()), str(_free_of_affection()),
		str(_player_ready_for(pose, act_source, bed_in)), str(_nav_owner_allows(pose, act_source)),
		str(_nav_pose_gate(pose, act_source)), bed_gate, str(can), reason_text]
	if state != State.IDLE:
		text += " | readiness=%.0f mood=%s climaxes=%d/%d intensity=%s pattern=%s cue=%s up=%s | %s" % [
			satisfaction, mood, pony_climaxes, MAX_PONY_CLIMAXES,
			_last_intensity, _last_pattern, cue, str(thrust_up),
			PREFERENCES.describe(_taste).replace("\n", "; ")]
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
	if _features.has("allow_act_during_cuddle"):
		return bool(_features.get("allow_act_during_cuddle", false))
	return SETTINGS.feature("allow_act_during_cuddle")


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
	# The request controller holds her while she walks over, presents and waits for Y.
	if owner.begins_with("unfplap:request:"):
		return state == State.IDLE
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
		var interruption := str(pony.action_interruption_reason())
		if not interruption.is_empty():
			# The request's own affection_active hold is not a gate against its invite.
			if not (_request_face and state == State.IDLE and interruption.contains("Affection")):
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
		_log("start blocked pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		return false
	# Remove the idle horse invitation and its request face before the act builds its own pose.
	set_request_face(false)
	clear_presentation()
	pose_id = pose
	source = act_source
	_profile = SETTINGS.template_for(_id)
	_features = SETTINGS.features()
	_pose_cfg = SETTINGS.pose(_id, pose_id)
	_taste = SETTINGS.taste(_id)
	_presentation_cfg = SETTINGS.presentation_controls(pose_id)
	_act_prompts = _profile.get("act_prompts", {})
	var thrust_controls := SETTINGS.thrust_controls()
	thrust_up = bool(thrust_controls.get("up", true))
	_thrust_pixels_per_full = float(thrust_controls.get("pixels_per_full", 480.0))
	var camera_thrust := SETTINGS.camera_thrust_controls()
	_camera_surge = float(camera_thrust.get("surge", 0.0))
	_camera_bob = float(camera_thrust.get("bob", 0.0))
	_thrust_tracker = THRUST.new()
	_aftercare_min = int(_profile.get("aftercare_min", 10))
	_cue_gap = SETTINGS.cue_gap_value(float(_profile.get("cue_gap", 12.0)))
	_has_facing = false
	bed = _resolve_bed(pose, act_source, bed_in)
	if pose == CATALOG.MISSIONARY and bed == null:
		return false
	_player_pony = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	_applied_bob = 0.0
	_applied_lean = 0.0
	_bob = 0.0
	_bob_velocity = 0.0
	_lean = 0.0
	_lean_velocity = 0.0
	_depth_prev = 0.0
	_depth_speed = 0.0
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
	_wing_returning = false
	_wing_return_done = false
	_wing_return_node = null
	_wing_return_progress = 0.0
	_jiggle_logged = false
	_act_seconds = 0.0
	_flutter_clock = randf_range(1.0, 3.0)
	_heart_elapsed = 0.0
	_heart_index = 0
	_heart_times.clear()
	_heart_counts.clear()
	_reset_lean_state()
	_rump_blush = 0.0
	_clear_face()
	_set_face(0.45, ACT_LIDS)
	_serial = _next_serial()
	_event_id = "intimacy_%s_%d" % [_id, _serial]
	_started_at = Time.get_unix_time_from_system()
	satisfaction = 0.0
	mood = "warming"
	cue = ""
	_y_hold = 0.0
	_y_hold_ready = false
	_y_hold_fired = false
	_reset_thrust_state()
	_prepare_vocal()
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()
	_remember_talk_turn()
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
	if _cuddle_active() and _feature("allow_act_during_cuddle") \
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
	_pose1_camera = _pose1_camera_target() if pose == CATALOG.MISSIONARY else Vector3.INF
	_pose1_camera_applied = _pose1_camera_offsets() if pose == CATALOG.MISSIONARY else Vector3.INF
	if pose == CATALOG.MISSIONARY:
		_snapshot_pose1_start()
		_make_pose1_view()
	_capture_look()
	_lock_player()
	_pause_face_turn()
	_begin_camera_mode()
	_hide_anon_avatar_for_pose1()
	_bind_action_executor()
	_start_audio()
	_apply_voice_policy()
	_set_inventory_hud_hidden(true)
	MEMORY.start_event(main.game, _id, _display_name, _event_id)
	state = State.POSING_IN
	_pose_in_left = POSE_IN_SECONDS
	main.set_active(self)
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.show_act(self, hud_readouts())
		main.hud.hide_prompt()
	_log("started pose=%s source=%s pony=%s eye=%.2f" % [pose, act_source, str(pony.name), _camera_target_eye])
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


## Pose 2 keeps her body turned away and planted. Stop the standing face-turn response so a
## player conversation cannot make her take turn steps, without pausing locomotion or emotions.
func _pause_face_turn(force := false) -> void:
	if (not force and pose_id != CATALOG.HORSE) or not is_instance_valid(pony):
		return
	if _face_turn_rate_owned:
		if absf(float(pony.get("face_turn_rate"))) > 0.0001:
			pony.set("face_turn_rate", 0.0)
		return
	var rate: Variant = pony.get("face_turn_rate")
	if rate == null:
		return
	_face_turn_rate_saved = float(rate)
	if absf(_face_turn_rate_saved) > 0.0001:
		pony.set("face_turn_rate", 0.0)
		_face_turn_rate_owned = true


func _restore_face_turn() -> void:
	if _face_turn_rate_owned and is_instance_valid(pony):
		pony.set("face_turn_rate", _face_turn_rate_saved)
	_face_turn_rate_owned = false
	_face_turn_rate_saved = -1.0


## Idle horse invitation: turn her back to Anon, look over the shoulder, bow and lift the tail.
## This is not the act: no player lock, camera, HUD, sex_active or state change. Y remains the
## only way to begin the real act.
func present_horse() -> bool:
	if _presenting or _present_turning:
		return true
	if state != State.IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or _cuddle_active():
		return false
	if not _free_of_affection():
		return false
	if _id.is_empty() and not _stage_ok():
		return false
	if not _request_face:
		set_request_face(true)
	var player: Variant = main.player
	var view: Camera3D = main.camera()
	var target: Vector3 = pony.global_position - Vector3.FORWARD
	if is_instance_valid(view):
		target = view.global_position
	elif is_instance_valid(player):
		target = player.global_position
	var away: Vector3 = pony.global_position - target
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = pony.global_basis.z
	away = away.normalized()
	_present_target_yaw = atan2(-away.x, -away.z)
	_present_yaw = pony.rotation.y
	_present_look_point = target
	_present_face_direction = away
	if pony.has_method("request_posture") and str(pony.posture_status().get("requested", "")) != "stand":
		pony.request_posture("stand")
	_present_turn_started = _now_s()
	_present_turn_last_yaw = pony.rotation.y
	_present_turn_still = 0.0
	if pony.has_method("face_direction") and pony.get("face_turn_rate") != null:
		_present_turning = true
		_begin_present_turn()
	else:
		# Unusual actor without the locomotion turn: keep the old direct-rotation fallback.
		_present_turning = false
		_attach_present_pose()
		_pause_face_turn(true)
	_log("present horse target_yaw=%.2f turn=%s" % [
		_present_target_yaw, "stepping" if _present_turning else "direct"])
	return true


## Create the idle pose and tail once she has finished turning. Doing this before the turn
## let the spread/bow pose fight the planted hooves and twisted the legs.
func _attach_present_pose() -> void:
	if not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(_id, CATALOG.HORSE)
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_present_pose = POSE.new()
		_present_pose.name = "UnfplapPresentPose"
		_present_pose.mare = pony
		_present_pose.mode = "pose2"
		_present_pose.pose_config = SETTINGS.pose(_id, CATALOG.HORSE)
		_present_pose.look_point = _present_look_point
		_present_pose.amount = 0.0
		_present_pose.target_amount = 1.0
		(skeleton as Skeleton3D).add_child(_present_pose)
		_keep_chin_last()
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_present_tail = TAIL.new()
		_present_tail.name = "UnfplapPresentTail"
		_present_tail.mare = pony
		_present_tail.runtime = self
		_present_tail.aside_angle = float(_pose_cfg.get("tail_aside", 0.55))
		_present_tail.lift_angle = float(_pose_cfg.get("tail_lift", 0.42))
		_present_tail.amount = 0.0
		_present_tail.target_amount = 1.0
		_present_tail.call("choose_side")
		(hair as Skeleton3D).add_child(_present_tail)
	_presenting = true
	_glance_back = true
	_glance_sign_set = false


func _begin_present_turn() -> void:
	if not is_instance_valid(pony) or not pony.has_method("face_direction"):
		return
	var rate: Variant = pony.get("face_turn_rate")
	if rate != null:
		_present_turn_rate_saved = float(rate)
		_present_turn_rate_owned = true
		pony.set("face_turn_rate", maxf(_present_turn_rate_saved, PRESENT_FACE_TURN_RATE))
	pony.call("face_direction", _present_face_direction)


func _restore_present_turn_rate() -> void:
	if _present_turn_rate_owned and is_instance_valid(pony):
		pony.set("face_turn_rate", _present_turn_rate_saved)
	_present_turn_rate_owned = false
	_present_turn_rate_saved = -1.0


func _finish_present_turn() -> void:
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", Vector3.ZERO)
	_restore_present_turn_rate()
	_present_turning = false
	if is_instance_valid(pony):
		var error := absf(wrapf(pony.rotation.y - _present_target_yaw, -PI, PI))
		if error > PRESENT_TURN_SETTLE_RAD:
			# The stepping turn could not finish (blocked feet, touch, wall). Snap once here
			# rather than letting the old static-lock path rotate the body under planted feet.
			var t: Transform3D = pony.global_transform
			var scale := t.basis.get_scale()
			t.basis = Basis(Vector3.UP, _present_target_yaw).scaled(scale)
			pony.global_transform = t
			_present_yaw = _present_target_yaw
			_log("present horse turn snap error=%.2f target=%.2f" % [error, _present_target_yaw])
		else:
			_present_yaw = pony.rotation.y
			_present_target_yaw = _present_yaw
			_log("present horse turn settled yaw=%.2f" % _present_yaw)
	if not _presenting:
		_attach_present_pose()
	_pause_face_turn(true)


func presentation_active() -> bool:
	return _presenting or _present_turning


## True once the stepping turn is done and the idle pose is attached. The post-accept line
## waits for this so she comments after taking the position, not while still turning into it.
func presentation_settled() -> bool:
	if not _presenting or _present_turning:
		return false
	return absf(wrapf(_present_yaw - _present_target_yaw, -PI, PI)) <= 0.05


func clear_presentation() -> void:
	if _present_turning:
		if is_instance_valid(pony) and pony.has_method("face_direction"):
			pony.call("face_direction", Vector3.ZERO)
		_restore_present_turn_rate()
		_present_turning = false
	if is_instance_valid(_present_pose):
		_present_pose.queue_free()
	_present_pose = null
	if is_instance_valid(_present_tail):
		_present_tail.queue_free()
	_present_tail = null
	_presenting = false
	_glance_back = false
	_glance_sign_set = false
	_restore_face_turn()


func _presentation_valid() -> bool:
	if not _presenting or state != State.IDLE:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or pony.has_meta("seated"):
		return false
	if _cuddle_active() or not _free_of_affection():
		return false
	if not pony.grounded():
		return false
	var status: Dictionary = pony.posture_status()
	if str(status.get("requested", "")) != "stand":
		return false
	if float(pony.actual_speed) > 0.10:
		return false
	var player: Variant = main.player
	if is_instance_valid(player) and player.global_position.distance_to(pony.global_position) > 8.0:
		return false
	return true


## Turn her away in place and stop conversation facing from taking the body back. Runs late in
## physics, after the navigator and locomotion, like the act's horse facing lock.
func _presentation_physics(delta: float) -> void:
	if _present_turning:
		_presentation_turn_physics(delta)
		return
	if not _presentation_valid():
		clear_presentation()
		return
	_present_yaw = rotate_toward(_present_yaw, _present_target_yaw, PRESENT_TURN_RATE * delta)
	var t: Transform3D = pony.global_transform
	var scale := t.basis.get_scale()
	t.basis = Basis(Vector3.UP, _present_yaw).scaled(scale)
	pony.global_transform = t
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)
	_pause_face_turn(true)


## Turn her with the game's supported standing turn, which steps the hooves. The direct
## transform write used to rotate the body under planted feet and twisted her legs.
func _presentation_turn_physics(delta: float) -> void:
	if not _presentation_turn_valid():
		clear_presentation()
		return
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", _present_face_direction)
	var yaw: float = pony.rotation.y
	if absf(wrapf(yaw - _present_turn_last_yaw, -PI, PI)) < 0.0005:
		_present_turn_still += delta
	else:
		_present_turn_still = 0.0
		_present_turn_last_yaw = yaw
	var error := absf(wrapf(yaw - _present_target_yaw, -PI, PI))
	if error <= PRESENT_TURN_SETTLE_RAD \
			or _present_turn_still >= PRESENT_TURN_STALL_S \
			or _now_s() - _present_turn_started >= PRESENT_TURN_TIMEOUT_S:
		_finish_present_turn()


func _presentation_turn_valid() -> bool:
	if not _present_turning or state != State.IDLE:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or pony.has_meta("seated"):
		return false
	if _cuddle_active() or not _free_of_affection():
		return false
	if not pony.grounded():
		return false
	var status: Dictionary = pony.posture_status()
	if str(status.get("requested", "")) != "stand":
		return false
	var player: Variant = main.player
	if is_instance_valid(player) and player.global_position.distance_to(pony.global_position) > 8.0:
		return false
	return true


## Idle request face and action hold. `affection_active` is the game's existing "physical
## affection owns her" flag; it blocks AI approach/follow actions while she asks and presents.
func set_request_face(on: bool) -> void:
	if not is_instance_valid(pony):
		return
	if on:
		_request_face = true
		if not pony.has_meta("affection_active"):
			pony.set_meta("affection_active", true)
			_request_claimed_affection = true
		return
	_request_face = false
	if _request_claimed_affection:
		pony.remove_meta("affection_active")
		_request_claimed_affection = false
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("stare"):
		expressions.call("stare", false)


func request_face_active() -> bool:
	return _request_face


func _request_face_process() -> void:
	if not _request_face or not is_instance_valid(pony):
		return
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", REQUEST_BLUSH)
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("stare"):
		expressions.call("stare", true, REQUEST_LIDS)


func _present_turn_process() -> void:
	if not _present_turning or not is_instance_valid(pony):
		return
	# Conversation facing can write a target in process after our late physics tick. Reassert
	# the away direction in process so the next locomotion step keeps turning her back.
	if pony.has_method("face_direction"):
		pony.call("face_direction", _present_face_direction)


func _presentation_process() -> void:
	if not _presentation_valid():
		clear_presentation()
		return
	var view: Camera3D = main.camera() if is_instance_valid(main) else null
	if is_instance_valid(_present_pose) and is_instance_valid(view):
		_present_pose.look_point = view.global_position
		_present_pose.head_back = 0.0
	_glance_back = true
	var secondary: Variant = pony.get("secondary")
	if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
		secondary.call("look_toward", _glance_angles(), 0.45)
	_aim_eyes_at_player()


func _keep_nav() -> void:
	if _nav == null or not is_instance_valid(_nav):
		return
	if str(_nav.get("command_owner")) != _token:
		_nav.call("stay")
		_nav.set("command_owner", _token)
		_nav.set("wander_enabled", false)


## Keep the act's attention while another character talks to Anon. Clearing the listener every
## tick stops the director from turning her away or pinning her gaze; speech, emotions and
## locomotion keep running, and `_check_running` does not treat conversation as a stop.
func _keep_act_attention() -> void:
	if state in [State.IDLE, State.RESTORE, State.AFTERGLOW] or not is_instance_valid(pony):
		return
	if pony.has_method("set_conversation_target"):
		pony.call("set_conversation_target", null, false)


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
	_end_act_lines(true)
	_set_inventory_hud_hidden(false)
	set_request_face(false)
	_restore_face_turn()
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
## so she settles onto the mattress instead of hovering.
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
## mattress (not across it) and on the drawn bedding.
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
## overwrite the debug head pitch.
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
			if _feature("pose2_body_sway"):
				_install_body_sway(skeleton)
			if _feature("thrust_ear_twitch"):
				_install_ear_twitch()
		elif _feature("pose1_body_motion"):
			_install_prone_sway(skeleton)
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
	clear_presentation()
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
	if not _feature("pose2_body_sway"):
		return
	_body_sway = BODY_SWAY.new()
	_body_sway.name = "UnfplapBodySway"
	_body_sway.set("mare", pony)
	_body_sway.set("runtime", self)
	skeleton.add_child(_body_sway)


func _install_prone_sway(skeleton: Skeleton3D) -> void:
	_prone_sway = PRONE_SWAY.new()
	_prone_sway.name = "UnfplapProneSway"
	_prone_sway.set("mare", pony)
	_prone_sway.set("runtime", self)
	skeleton.add_child(_prone_sway)


func _install_ear_twitch() -> void:
	if not _feature("thrust_ear_twitch"):
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
	_restore_dock_jiggle_material()
	if is_instance_valid(_body_sway):
		_body_sway.queue_free()
	_body_sway = null
	if is_instance_valid(_prone_sway):
		_prone_sway.queue_free()
	_prone_sway = null
	if is_instance_valid(_ear_twitch):
		_ear_twitch.queue_free()
	_ear_twitch = null


# --------------------------------------------------------------------------- thrust

func _now_s() -> float:
	return Time.get_ticks_msec() * 0.001


func _reset_thrust_state() -> void:
	depth = 0.0
	_hip_phase = 0.0
	_depth_prev = 0.0
	_depth_speed = 0.0
	_last_stroke.clear()
	_last_intensity = ""
	_last_pattern = ""
	_stroke_window.clear()
	_last_stroke_at = -1000.0
	pony_climaxes = 0
	_climax_left = 0.0
	_close_left = 0.0
	_close_caress_seconds = 0.0
	_close_rewarded = false
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	_utterance_done_key = ""
	_utterance_done_at = 0.0
	_utterance_serial = 0
	_last_utterance_at = -1000.0
	_vocal_cooldown = 0.0
	_overwhelmed = 0.0
	_cue_override = ""
	_cue_until = 0.0
	_last_touch = ""
	_last_talk = ""
	_last_touch_at = -1000.0
	_last_thrust_score_at = -1000.0
	_receptive_until = 0.0
	_last_talk_at = -1000.0
	_last_cue_text = ""
	_last_cue_seen = ""
	_cue_changed_at = 0.0
	_last_cue_line_at = -1000.0
	_last_demand_text = ""
	_last_demand_at = -1000.0
	_last_blocked_cue = ""
	_used_memory_ids.clear()
	_peak_satisfaction = 0.0
	_act_both_matches = 0
	_act_dislikes = 0
	_act_liked_touch = 0
	_act_liked_talk = 0
	_last_player_talk = ""
	_peak_recorded = false
	if _thrust_tracker == null:
		_thrust_tracker = THRUST.new()
	_thrust_tracker.reset()


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


## `mute_ponese_audio`: keep the generated line and text HUD, but silence the Ponese audio
## for this act. A generated-voice pony is left alone.
func _apply_voice_policy() -> void:
	_voice_info = _classify_voice()
	_text_only_voice = _feature("mute_ponese_audio") \
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
	# Let the inventory re-evaluate its own HUD state after restoring `hud_hidden`: a stale
	# saved layer flag from a bed/menu start must not keep the quick slots hidden.
	if inventory.has_method("_place_hotbar"):
		inventory.call("_place_hotbar")
	_inventory_hud_hidden = false
	_log("inventory HUD restored hud_hidden=%s hotbar=%s layer=%s" % [
		str(_inventory_hud_saved), str(_inventory_hotbar_visible), str(_inventory_hud_layer_visible)])


func _thrust_move(amount: float, now: float) -> void:
	if _thrust_tracker == null:
		return
	var before := depth
	var events: Array = _thrust_tracker.move(amount, now)
	depth = _thrust_tracker.depth
	if is_instance_valid(_act_audio) and state in [State.ACTIVE, State.CLIMAX] \
			and _act_audio.crossed(before, depth):
		_act_audio.withdraw_crossed(before, depth, _thrust_tracker.live_strength(now),
			pose_id, _rump_point(), _bed_audio_point(), _bed_soft)
	for event: Dictionary in events:
		_on_stroke(event)


func _thrust_tick() -> void:
	if _thrust_tracker == null:
		return
	var events: Array = _thrust_tracker.tick(_now_s())
	depth = _thrust_tracker.depth
	for event: Dictionary in events:
		_on_stroke(event)


## Only real thrusts update the pattern window and score. Upward strokes, tiny jitter and
## pullbacks are presentation only.
func _on_stroke(event: Dictionary) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	if int(event.get("direction", 0)) <= 0:
		return
	if not bool(event.get("thrust", false)):
		return
	if state == State.CLIMAX:
		# The player can keep thrusting through her climax; it is presentation only.
		_on_thrust(event)
		return
	_last_stroke = event.duplicate(true)
	_last_stroke_at = _now_s()
	_stroke_window.append(_last_stroke)
	while _stroke_window.size() > 4:
		_stroke_window.pop_front()
	_last_intensity = PREFERENCES.intensity_for(float(event.get("strength", 0.0)))
	_last_pattern = PREFERENCES.pattern_for(_stroke_window)
	_log("thrust stroke travel=%.2f speed=%.2f peak=%.2f strength=%.2f intensity=%s pattern=%s readiness=%.0f" % [
		float(event.get("travel", 0.0)), float(event.get("speed", 0.0)),
		float(event.get("peak_speed", 0.0)), float(event.get("strength", 0.0)),
		_last_intensity, _last_pattern, satisfaction])
	_on_thrust(_last_stroke)
	_score_thrust()


## Each real thrust lands as a discrete chunk. Matching both axes is best, one axis still
## helps, and a mismatch makes no progress. This is what makes thrusting essential.
func _score_thrust() -> void:
	if state != State.ACTIVE:
		return
	var now := _now_s()
	if now - _last_thrust_score_at < THRUST_SCORE_MIN_INTERVAL:
		return
	_last_thrust_score_at = now
	var wanted_intensity := str(_taste.get("intensity", "firm"))
	var wanted_pattern := str(_taste.get("pattern", "steady"))
	var intensity_match := not _last_intensity.is_empty() and _last_intensity == wanted_intensity
	var pattern_match := not _last_pattern.is_empty() and _last_pattern == wanted_pattern
	if intensity_match and pattern_match:
		_act_both_matches += 1
	var heat := THRUST_HEAT_NONE
	if intensity_match and pattern_match:
		heat = THRUST_HEAT_BOTH
	elif intensity_match or pattern_match:
		heat = THRUST_HEAT_ONE
	if heat > 0.0:
		heat *= PREFERENCES.warmth_scale(_taste)
		if now < _receptive_until:
			heat *= RECEPTIVE_BOOST
		_add_heat(heat)
	_log("thrust score intensity=%s pattern=%s both=%s heat=%.2f readiness=%.0f" % [
		_last_intensity, _last_pattern, str(intensity_match and pattern_match),
		heat, satisfaction])


func _on_thrust(result: Dictionary) -> void:
	var strength := clampf(float(result.get("strength", 0.0)), 0.0, 1.0)
	var impact := clampf(strength * THRUST_IMPACT_GAIN, 0.0, 1.0)
	var now := _now_s()
	_wing_flick = lerpf(WING_FLICK_MIN, WING_FLICK_MAX, impact)
	if _winged and not _wing_hold and now - _last_wing_flutter >= WING_FLUTTER_COOLDOWN_S:
		var excitement: Variant = pony.get("excitement")
		if excitement != null and excitement.has_method("flutter"):
			excitement.call("flutter")
			_last_wing_flutter = now
	_thrust_jiggle(impact)
	if pose_id == CATALOG.HORSE and is_instance_valid(_tail):
		_tail.call("thrust", impact * _jiggle_size_scale())
	if pose_id == CATALOG.HORSE:
		if impact >= RUMP_BLUSH_MIN_STRENGTH:
			_rump_blush = minf(RUMP_BLUSH_MAX, _rump_blush + RUMP_BLUSH_STEP)
			_ensure_rump_decal()
		if _feature("thrust_ear_twitch") and is_instance_valid(_ear_twitch):
			_ear_twitch.call("try_trigger", impact)
	_thrust_times.append(now)
	while not _thrust_times.is_empty() and now - float(_thrust_times[0]) > 1.0:
		_thrust_times.pop_front()
	_play_kiss()
	_play_vocal()
	if is_instance_valid(_act_audio):
		if _act_audio.foley_enabled():
			_act_audio.play_impact(pose_id, strength, _rump_point(),
				_bed_audio_point(), _bed_soft)
	_log("thrust readiness=%.0f rate=%.1f/s strength=%.2f impact=%.2f intensity=%s pattern=%s" % [
		satisfaction, _thrusts_per_second(), strength, impact, _last_intensity, _last_pattern])


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


func _add_heat(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var before := int(satisfaction)
	satisfaction = clampf(satisfaction + amount, 0.0, READINESS_MAX)
	if satisfaction > _peak_satisfaction:
		_peak_satisfaction = satisfaction
	if int(satisfaction) != before and (int(satisfaction) == 0 or int(satisfaction) % 10 == 0):
		_log("readiness=%.0f mood=%s" % [satisfaction, mood])


## Readiness never decays on its own. Real thrusts add the chunks in `_score_thrust`; only a
## disliked touch/talk subtracts. This tick clears stale thrust memory and updates cues.
func _readiness_tick(delta: float) -> void:
	if state != State.ACTIVE:
		return
	if satisfaction >= PONY_CLIMAX_AT:
		_climax()
		return
	var now := _now_s()
	if now - _last_stroke_at > STROKE_MEMORY_S:
		_last_intensity = ""
		_last_pattern = ""
		_stroke_window.clear()
	if _overwhelmed > 0.0:
		_overwhelmed = maxf(0.0, _overwhelmed - delta)
	if satisfaction >= PONY_CLIMAX_AT:
		_climax()
		return
	var wanted_intensity := str(_taste.get("intensity", "firm"))
	var wanted_pattern := str(_taste.get("pattern", "steady"))
	var intensity_match := not _last_intensity.is_empty() and _last_intensity == wanted_intensity
	var pattern_match := not _last_pattern.is_empty() and _last_pattern == wanted_pattern
	mood = _mood_for()
	if not _cue_override.is_empty() and now < _cue_until:
		cue = _cue_override
	else:
		_cue_override = ""
		cue = _base_cue(intensity_match, pattern_match)
	if cue != _last_cue_seen:
		_last_cue_seen = cue
		_cue_changed_at = now
	var demand := UTTERANCE.is_demand(cue)
	var blocked := demand and _demand_line_blocked(cue, now)
	if blocked and _last_blocked_cue != cue:
		_last_blocked_cue = cue
		_log("cue blocked demand=%s gap=%.1f repeat=%.1f" % [
			cue, DEMAND_LINE_GAP_S, DEMAND_REPEAT_S])
	if not blocked and cue != _last_cue_text \
			and now - _cue_changed_at >= CUE_STABLE_S \
			and UTTERANCE.ready(now, _last_cue_line_at, _cue_gap) \
			and _queue_utterance("cue", "cue", "cue"):
		_last_cue_text = cue
		_last_cue_line_at = now
		if demand:
			_last_demand_text = cue
			_last_demand_at = now


func _mood_for() -> String:
	if _overwhelmed > 0.0:
		return "overwhelmed"
	if satisfaction >= CLOSE_AT:
		return "close"
	if satisfaction >= 40.0:
		return "wanting"
	return "warming"


func _base_cue(intensity_match: bool, pattern_match: bool) -> String:
	if _overwhelmed > 0.0:
		return "She's overwhelmed."
	if satisfaction >= CLOSE_AT:
		return "She's close."
	if not _last_intensity.is_empty() and not intensity_match:
		var wanted := str(_taste.get("intensity", "firm"))
		if wanted == "soft":
			return "She wants it softer."
		if wanted == "rough":
			return "She wants it harder."
		return "She wants it firmer." if _last_intensity == "soft" else "She wants it softer."
	if not _last_pattern.is_empty() and not pattern_match:
		match str(_taste.get("pattern", "steady")):
			"teasing":
				return "She wants to be teased."
			"quick":
				return "She wants it quicker."
		return "She wants a steadier rhythm."
	if intensity_match and pattern_match:
		return "She likes that."
	return "She's warming up."


## Demand lines get their own budget so a flapping preference cue cannot turn into a stream of
## commands. Non-demand lines only obey the shared utterance gap.
func _demand_line_blocked(text: String, now: float) -> bool:
	if not UTTERANCE.is_demand(text):
		return false
	if now - _last_demand_at < DEMAND_LINE_GAP_S:
		return true
	return text == _last_demand_text and now - _last_demand_at < DEMAND_REPEAT_S


func _set_cue_override(text: String, seconds := CUE_OVERRIDE_S) -> void:
	cue = text
	_cue_override = text
	_cue_until = _now_s() + maxf(0.0, seconds)


func _on_touch(kind: String) -> void:
	if state != State.ACTIVE:
		return
	var now := _now_s()
	# One shared scoring cooldown: alternating caress/kiss/smack must not bypass the cap.
	if now - _last_touch_at < TOUCH_COOLDOWN_S:
		return
	_last_touch_at = now
	_last_touch = kind
	if kind in _taste.get("touch", []):
		_act_liked_touch += 1
		if satisfaction < ASSIST_CAP:
			_add_heat(minf(TOUCH_HEAT, ASSIST_CAP - satisfaction))
			_set_cue_override("She likes that.")
		else:
			_set_cue_override("She needs more than your hands.")
		_receptive_until = now + RECEPTIVE_S
		_log("touch like kind=%s readiness=%.0f" % [kind, satisfaction])
	elif kind in _taste.get("dislikes", []):
		_act_dislikes += 1
		_add_heat(-TOUCH_HEAT)
		_overwhelmed = OVERWHELM_S
		_set_cue_override("She doesn't like that.")
		_log("touch dislike kind=%s readiness=%.0f" % [kind, satisfaction])
	else:
		_set_cue_override("She notices your touch.")


## The player's own words are a concrete input. The AI still writes her reply; this only
## decides whether the line landed with her taste.
func _on_talk(text: String) -> void:
	if state != State.ACTIVE:
		return
	var category := PREFERENCES.classify_talk(text)
	if category.is_empty():
		return
	var now := _now_s()
	if now - _last_talk_at < TALK_COOLDOWN_S:
		return
	_last_talk_at = now
	_last_talk = category
	if category in _taste.get("talk", []):
		_act_liked_talk += 1
		if satisfaction < ASSIST_CAP:
			_add_heat(minf(TALK_HEAT, ASSIST_CAP - satisfaction))
			_set_cue_override("She likes that.")
		else:
			_set_cue_override("She needs you to move.")
		_receptive_until = now + RECEPTIVE_S
		_log("talk like category=%s readiness=%.0f" % [category, satisfaction])
	elif category in _taste.get("dislikes", []):
		_act_dislikes += 1
		_add_heat(-TALK_HEAT)
		_overwhelmed = OVERWHELM_S
		_set_cue_override("She didn't like that.")
		_log("talk dislike category=%s readiness=%.0f" % [category, satisfaction])
	else:
		_set_cue_override("She listens.")


## Watch the director for a new player turn. No new control: the game's T key already
## produces the text/mic turn. Talk is scored when it actually happens.
func _talk_tick(_delta: float) -> void:
	if state != State.ACTIVE:
		return
	var director := _director()
	if director != null:
		var turn := int(director.get("_turn_id"))
		var text := str(director.get("_player_text"))
		if turn != _last_talk_turn:
			_last_talk_turn = turn
			if not text.strip_edges().is_empty():
				_last_player_talk = text.strip_edges()
				_on_talk(text)


func _remember_talk_turn() -> void:
	var director := _director()
	if director == null:
		_last_talk_turn = -1
		return
	_last_talk_turn = int(director.get("_turn_id"))


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


func _utterance_tick() -> void:
	if state != State.ACTIVE:
		return
	_release_finished_utterance()
	if _utterance_pending_key.is_empty():
		return
	if _now_s() > _utterance_pending_until and not _speech_busy():
		_log("utterance timeout key=%s" % _utterance_pending_key)
		_cancel_pending_utterance()


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
			pose_id, mood, _last_intensity, _last_pattern,
			_last_touch, _last_talk, _act_seconds, pony_climaxes),
		"taste": PREFERENCES.describe(_taste),
		"cue": cue,
		"recent": _recent_lines(),
	}
	var memory_id := ""
	if kind == "cue":
		var facts := MEMORY.cue_facts(main.game, _id, _event_id)
		var tone_name := RELATIONSHIP_CUE.tone(facts)
		values["relationship"] = RELATIONSHIP_CUE.note(facts)
		values["tone"] = RELATIONSHIP_CUE.tone_line(tone_name)
		var memory := MEMORY.shared_memory(main.game, _id, cue, _event_id, _used_memory_ids)
		values["memory"] = RELATIONSHIP_CUE.memory_line(str(memory.get("text", "")))
		memory_id = str(memory.get("id", ""))
	var purpose := UTTERANCE.format(template, values)
	if kind == "cue":
		purpose += CUE_REACTION_NOTE
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
	if not memory_id.is_empty():
		_used_memory_ids.append(memory_id)
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


## Drop all act lines that have not started speaking. A line that is already speaking may
## finish; one that is only queued or still being generated is cancelled. This runs at every
## climax/afterglow boundary and every act end, so a delayed line cannot start afterward.
func _end_act_lines(keep_speaking := true) -> void:
	if is_instance_valid(main) and is_instance_valid(main.game):
		var cancelled := MEMORY.cancel_act_lines(main.game, _event_id, keep_speaking)
		if cancelled > 0:
			_log("act lines cancelled=%d" % cancelled)
	_utterance_pending_key = ""
	_utterance_pending_until = 0.0
	_utterance_done_key = ""
	_utterance_done_at = 0.0


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
	var start := maxi(0, (spoken as Array).size() - 4)
	for index in range(start, (spoken as Array).size()):
		recent.append(str((spoken as Array)[index]))
	return " | ".join(recent)


func _last_spoken_line() -> String:
	var recent := _recent_lines()
	if recent.is_empty():
		return ""
	var parts := recent.split(" | ")
	return parts[parts.size() - 1].strip_edges() if not parts.is_empty() else ""


## Store the strongest clean act per mare. The exchange is the useful part: a later cue can
## infer that she liked it without any name-specific instruction.
func _record_peak_memory() -> void:
	if _peak_recorded:
		return
	_peak_recorded = true
	if not RELATIONSHIP_CUE.peak_eligible(_peak_satisfaction, _act_both_matches, _act_dislikes):
		return
	var player := _last_player_talk.strip_edges()
	var her := _last_spoken_line()
	if player.length() > 160:
		player = player.left(160).strip_edges()
	if her.length() > 160:
		her = her.left(160).strip_edges()
	var text := ""
	if not player.is_empty():
		text = "Anon said: \"%s\"." % player
		if not her.is_empty():
			text += " You answered: \"%s\"." % her
	else:
		text = "Anon made you feel completely wanted."
	var score := RELATIONSHIP_CUE.peak_score(_peak_satisfaction, _act_both_matches,
		_act_liked_touch, _act_liked_talk, _act_dislikes)
	MEMORY.record_peak_memory(_id, _event_id, text, score)


func _thrust_jiggle(strength: float) -> void:
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
	# supports only one jiggle at a time; the shader center covers both flanks.
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
	# get less shader travel from the same thrust impulse.
	var amount: Variant = _flank.get("_jiggle_amount")
	if amount != null:
		_flank.set("_jiggle_amount", float(amount) * JIGGLE_RUMP_SCALE * _jiggle_size_scale())
	if _feature("thrust_tail_dock_jiggle"):
		_include_dock_jiggle()
	else:
		_restore_dock_jiggle_material()
	if not _jiggle_logged:
		_jiggle_logged = true
		var targets: Variant = _flank.get("_jiggle_targets")
		_log("jiggle rump at=%s root=%s normal=%s targets=%d" % [
			str(at), str(pony.global_position), str(normal),
			(targets as Array).size() if targets is Array else -1])


## Add the rigid dock and merged near-dock surface to the rump's shader wobble. The hair tail
## bones are already driven by tail_pose; this is the missing dock piece.
func _include_dock_jiggle() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(_flank):
		return
	var dock := pony.find_child("OpenPonyDock", true, false) as MeshInstance3D
	if not is_instance_valid(dock):
		return
	var body: Variant = _flank.get("_body")
	var source: Material = null
	if body is MeshInstance3D:
		source = (body as MeshInstance3D).get_active_material(0)
	if not source is ShaderMaterial:
		return
	if not is_instance_valid(_dock_jiggle_mesh) or _dock_jiggle_mesh != dock:
		_restore_dock_jiggle_material()
		_dock_jiggle_mesh = dock
		_dock_jiggle_original = dock.get_surface_override_material(0)
		_dock_jiggle_material = (source as ShaderMaterial).duplicate() as ShaderMaterial
		if not is_instance_valid(_dock_jiggle_material):
			_dock_jiggle_mesh = null
			_dock_jiggle_original = null
			return
		dock.set_surface_override_material(0, _dock_jiggle_material)
	var targets: Variant = _flank.get("_jiggle_targets")
	if targets is Array:
		(targets as Array).append([_dock_jiggle_material, dock])
	_include_dock_near_masks()


## The near mesh merges the dock into the body palette with a zero jiggle_entry mask. Raise
## the dock's palette entries so the merged surface follows the same wobble.
func _include_dock_near_masks() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(_flank):
		return
	var near: Variant = pony.get("_near")
	if not near is Dictionary:
		return
	var groups: Variant = (near as Dictionary).get("groups", [])
	if not groups is Array:
		return
	var targets: Variant = _flank.get("_jiggle_targets")
	if not targets is Array:
		return
	for entry_v: Variant in groups:
		if not entry_v is Dictionary:
			continue
		var entry: Dictionary = entry_v
		var mi_v: Variant = entry.get("mi")
		if not mi_v is MeshInstance3D:
			continue
		var group_v: Variant = entry.get("group")
		if not group_v is Dictionary:
			continue
		var variants_v: Variant = (group_v as Dictionary).get("variants", {})
		if not variants_v is Dictionary:
			continue
		var variant_v: Variant = (variants_v as Dictionary).get(entry.get("variant"))
		if not variant_v is Dictionary:
			continue
		var outputs_v: Variant = (variant_v as Dictionary).get("outputs", [])
		if not outputs_v is Array:
			continue
		for target_v: Variant in targets:
			if not target_v is Array or (target_v as Array).size() < 2:
				continue
			var mat_v: Variant = (target_v as Array)[0]
			var target_mi_v: Variant = (target_v as Array)[1]
			if target_mi_v != mi_v or not mat_v is ShaderMaterial:
				continue
			var mat := mat_v as ShaderMaterial
			var mask_v: Variant = mat.get_shader_parameter("jiggle_entry")
			if not mask_v is PackedFloat32Array:
				continue
			var mask: PackedFloat32Array = mask_v
			var changed := false
			for si: int in (outputs_v as Array).size():
				var output_v: Variant = (outputs_v as Array)[si]
				if not output_v is Dictionary:
					continue
				var sources_v: Variant = (output_v as Dictionary).get("entries", [])
				if not sources_v is Array:
					continue
				for i: int in mini((sources_v as Array).size(), mask.size()):
					var source_v: Variant = (sources_v as Array)[i]
					if not source_v is Array:
						continue
					var path_v: Variant = (source_v as Array)[0]
					var src_node: Node = pony.get_node_or_null(NodePath(str(path_v)))
					if src_node is Node and String(src_node.name).begins_with("OpenPonyDock"):
						mask[i] = 1.0
						changed = true
			if changed:
				mat.set_shader_parameter("jiggle_entry", mask)


func _restore_dock_jiggle_material() -> void:
	if is_instance_valid(_dock_jiggle_mesh):
		_dock_jiggle_mesh.set_surface_override_material(0, _dock_jiggle_original)
	_dock_jiggle_mesh = null
	_dock_jiggle_material = null
	_dock_jiggle_original = null


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
	if pose_id != CATALOG.HORSE:
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
		# Cancel act lines before restoring, then queue the intentional early-stop reaction.
		_end_act_lines(true)
		_restore_begin()
		var expiry := Time.get_ticks_msec() + 60000
		var valid := func() -> bool:
			return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
		MEMORY.reaction_for(main.game, _id, "end_early", _event_id,
			"Anon stopped before you reached climax. Say one short sentence, at most 12 words, in your own voice. Saying nothing is fine.",
			valid)
	elif state == State.AFTERGLOW:
		end_afterglow()


func end_afterglow() -> void:
	if state == State.AFTERGLOW:
		_log("afterglow end pony=%s" % str(pony.name))
		_close_cancel()
		_restore_begin()


func _climax() -> void:
	if state != State.ACTIVE:
		return
	pony_climaxes += 1
	_log("pony climax=%d pose=%s pony=%s readiness=%.0f" % [
		pony_climaxes, pose_id, str(pony.name), satisfaction])
	state = State.CLIMAX
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0
	mood = "climax"
	cue = "She's coming."
	_set_cue_override("She's coming.", CLIMAX_SECONDS)
	_schedule_climax_hearts()
	_climax_hearts_burst_at(_dock_point())
	_set_face(0.3, CLIMAX_LIDS)
	_end_act_lines(true)
	if is_instance_valid(main):
		MEMORY.climax_event(main.game, _id, _display_name, _event_id, pony_climaxes)
	_queue_climax_reaction()
	_play_climax()
	if is_instance_valid(main) and is_instance_valid(main.hud):
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
	if not pony.is_inside_tree():
		return pony.position
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
	if not is_instance_valid(main):
		return
	var expiry := Time.get_ticks_msec() + 60000
	var valid := func() -> bool:
		return is_instance_valid(pony) and Time.get_ticks_msec() < expiry
	var climax_id := "%s:pony_climax:%d" % [_event_id, pony_climaxes]
	MEMORY.reaction_for(main.game, _id, "climax", climax_id,
		"You have just climaxed during intimacy with Anon. Say one short sentence, at most 12 words, in your own voice. Staying quiet is fine. Do not describe anatomy.",
		valid)


## The pony climax ends on its own. It returns to ACTIVE unless this was the third;
## afterglow is the player's choice, not the climax state's automatic exit.
func _finish_climax() -> void:
	if pony_climaxes >= MAX_PONY_CLIMAXES:
		_enter_afterglow()
		return
	state = State.ACTIVE
	_set_face(0.45, ACT_LIDS)
	satisfaction = float(_taste.get("recovery", PREFERENCES.RECOVERY_DEFAULT))
	mood = "warming"
	cue = ""
	_cue_override = ""
	_cue_until = 0.0
	_overwhelmed = 0.0
	_last_intensity = ""
	_last_pattern = ""
	_stroke_window.clear()
	_last_stroke_at = -1000.0
	_last_thrust_score_at = -1000.0
	_receptive_until = 0.0
	_log("pony climax end=%d/%d recovery=%.0f" % [
		pony_climaxes, MAX_PONY_CLIMAXES, satisfaction])


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return ""
	var parts: PackedStringArray = []
	if state == State.AFTERGLOW:
		parts.append("- You are still in the afterglow with Anon; the act has ended, but the moment is not finished yet.")
	else:
		parts.append("- You are in the middle of sex with Anon.")
	var caressing := _player_is_caressing()
	var leaning := _player_is_leaning_close()
	if caressing and leaning:
		parts.append("He is leaning in close against you and caressing your flank.")
	elif caressing:
		parts.append("He is caressing your flank.")
	elif leaning:
		parts.append("He is leaning in close, holding you.")
	else:
		parts.append("He is close but not caressing or leaning in right now.")
	if state == State.AFTERGLOW:
		parts.append("If Anon asks to stay longer, use [stay: 120] to hold the afterglow.")
	return " ".join(parts)


func _player_is_caressing() -> bool:
	return bool(_caress_active.get("L", false)) or bool(_caress_active.get("R", false))


func _player_is_leaning_close() -> bool:
	return _lean_forward >= 0.35 or _lean_action_active or _kiss_amount > 0.05 \
		or _base_kiss_active or _base_kiss_releasing or _pose2_kiss_active


func _player_is_close() -> bool:
	return _player_is_caressing() or _player_is_leaning_close()


## The game's action executor owns [stay: SECONDS]. A permitted stay during the afterglow is
## her agreement to keep the moment going, so pause the self-end roll for that long.
func _bind_action_executor() -> void:
	if is_instance_valid(_action_executor) and _action_executor.is_inside_tree():
		return
	_action_executor = null
	var director := _director()
	if director == null:
		return
	var actions: Variant = director.get("actions")
	if actions == null:
		return
	var executors: Variant = actions.get("executors")
	if not executors is Dictionary:
		return
	var executor: Variant = (executors as Dictionary).get(_id)
	if not executor is Node:
		return
	_action_executor = executor as Node
	var callback := Callable(self, "_on_action_outcome")
	if _action_executor.has_signal("outcome") and not _action_executor.is_connected("outcome", callback):
		_action_executor.connect("outcome", callback)


func _on_action_outcome(event: Dictionary) -> void:
	if state != State.AFTERGLOW:
		return
	if str(event.get("type", "")) != "stay":
		return
	if str(event.get("status", "")) != "accepted":
		return
	var duration := 30.0
	if is_instance_valid(_action_executor):
		var movement: Variant = _action_executor.get("movement")
		if movement is Dictionary:
			duration = float((movement as Dictionary).get("duration_s", 30.0))
	duration = clampf(duration, 0.5, 600.0)
	_afterglow_hold_until = maxf(_afterglow_hold_until, _now_s() + duration)
	_log("afterglow hold extended %.0fs by [stay]" % duration)


static func self_end_chance(close: bool) -> float:
	return AFTERGLOW_SELF_END_CHANCE_CLOSE if close else AFTERGLOW_SELF_END_CHANCE_ALONE


func _self_end_tick(delta: float) -> void:
	if _afterglow_elapsed < AFTERGLOW_SELF_END_SECONDS:
		return
	if _now_s() < _afterglow_hold_until:
		return
	_self_end_clock -= delta
	if _self_end_clock > 0.0:
		return
	_self_end_clock = AFTERGLOW_SELF_END_CHECK_S
	if _speech_busy():
		return
	var close := _player_is_close()
	var chance := self_end_chance(close)
	if randf() >= chance:
		return
	_log("afterglow self end after %.1fs close=%s" % [_afterglow_elapsed, str(close)])
	end_afterglow()


func _enter_afterglow() -> void:
	if pose_id == CATALOG.HORSE:
		_pose2_afterglow_begin()
	else:
		_afterglow_begin()
	_begin_wing_afterglow()


func _commit_afterglow() -> void:
	if not is_instance_valid(main):
		return
	_record_peak_memory()
	MEMORY.commit_climax(main.game, _id, _display_name, _event_id)
	MEMORY.afterglow_event(main.game, _id, _display_name, _event_id, pose_id)
	WITNESS.commit(main.game, _id, _display_name, _serial, pony)


## Pose 2 also gets a held afterglow now that there are things to do in it.
func _pose2_afterglow_begin() -> void:
	_log("afterglow pose=%s pony=%s" % [pose_id, str(pony.name)])
	_end_act_lines(true)
	_commit_afterglow()
	state = State.AFTERGLOW
	_afterglow_pose = pose_id
	_afterglow_elapsed = 0.0
	_afterglow_hold_until = 0.0
	_self_end_clock = 0.0
	_bind_action_executor()
	cue = ""
	_cue_override = ""
	_cue_until = 0.0
	_set_face(0.85, AFTERGLOW_LIDS)
	if is_instance_valid(_pose):
		_pose.mode = "pose2"
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.55
		_tail.call("flick", 2)
	_inside_aftermath()
	_begin_close_window()
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")


func _afterglow_begin() -> void:
	_log("afterglow pose=%s pony=%s" % [pose_id, str(pony.name)])
	_end_act_lines(true)
	_commit_afterglow()
	state = State.AFTERGLOW
	_afterglow_pose = pose_id
	_afterglow_elapsed = 0.0
	_afterglow_hold_until = 0.0
	_self_end_clock = 0.0
	_bind_action_executor()
	cue = ""
	_cue_override = ""
	_cue_until = 0.0
	_set_face(0.85, AFTERGLOW_LIDS)
	if is_instance_valid(_pose):
		_pose.mode = "afterglow"
		_pose.afterglow_pose = pose_id
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.35
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")


## Pose 2 only: tell her Anon came inside her. Normal dialogue resumes from here.
func _inside_aftermath() -> void:
	if not is_instance_valid(main):
		return
	MEMORY.inside_event(main.game, _id, _display_name, _event_id)


## Horse afterglow only. The HUD and this timer own the stay-close invitation; normal dialogue
## resumes instead of a scripted stay-close line.
func _begin_close_window() -> void:
	if pose_id != CATALOG.HORSE:
		return
	_close_left = STAY_CLOSE_SECONDS
	_close_caress_seconds = 0.0
	_close_rewarded = false
	cue = ""
	_cue_override = ""
	_cue_until = 0.0


func _afterglow_tick(delta: float) -> void:
	if state != State.AFTERGLOW:
		return
	_afterglow_elapsed += delta
	_self_end_tick(delta)
	if state != State.AFTERGLOW or pose_id != CATALOG.HORSE:
		return
	if _close_left <= 0.0:
		return
	if bool(_caress_active["L"]) or bool(_caress_active["R"]):
		_close_caress_seconds += delta
	_close_left = maxf(0.0, _close_left - delta)
	if _close_left <= 0.0:
		_close_afterglow()


func _close_afterglow() -> void:
	if _close_rewarded:
		return
	_close_rewarded = true
	_close_left = 0.0
	var caressed := _close_caress_seconds >= STAY_CLOSE_CARESS_SECONDS
	if is_instance_valid(main):
		MEMORY.stay_close_reward(main.game, _id, _event_id, caressed)
	_set_face(0.9, AFTERGLOW_CLOSE_LIDS)
	_climax_hearts_burst()
	cue = ""
	_log("stay close reward caressed=%s caress_seconds=%.1f" % [
		str(caressed), _close_caress_seconds])


func _close_cancel() -> void:
	if _close_rewarded:
		return
	_close_left = 0.0
	_close_caress_seconds = 0.0


func close_hint() -> String:
	if state != State.AFTERGLOW or pose_id != CATALOG.HORSE:
		return ""
	if _close_left > 0.0:
		return "Stay close · %ds · caress" % int(ceil(_close_left))
	if _close_rewarded:
		return "She seems content."
	return ""


func _restore_begin() -> void:
	if state == State.IDLE or state == State.RESTORE:
		return
	_record_peak_memory()
	_close_cancel()
	_end_act_lines(true)
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
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.hide_act()


func _finish_restore() -> void:
	if not is_instance_valid(pony):
		_log("restore finished with invalid pony")
		_set_inventory_hud_hidden(false)
		state = State.IDLE
		return
	var was_pose := pose_id
	_log("restore finished pony=%s" % str(pony.name))
	_set_inventory_hud_hidden(false)
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
	if is_instance_valid(main) and is_instance_valid(main.hud):
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
	# Defensive: every stop path must leave the quick slots in their pre-act state.
	_set_inventory_hud_hidden(false)
	if state == State.IDLE:
		set_request_face(false)
		clear_presentation()
		return
	_restore_now()


func _restore_now() -> void:
	_end_act_lines(true)
	_set_inventory_hud_hidden(false)
	set_request_face(false)
	_restore_face_turn()
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
		if is_instance_valid(main) and is_instance_valid(main.hud):
			main.hud.hide_all()
	state = State.IDLE
	pose_id = ""
	source = ""
	bed = null
	_reset_after_act()


func _reset_after_act() -> void:
	if not is_inside_tree():
		return
	_reset_thrust_state()
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()
	var from := float(satisfaction)
	_satisfaction_tween = create_tween()
	_satisfaction_tween.tween_method(func(value: float) -> void: satisfaction = clampf(value, 0.0, READINESS_MAX), from, 0.0, 30.0)
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
	# Conversation attention does not end an act. The runtime owns her body and clears the
	# listener each tick, so a character addressing Anon can keep talking without cancelling it.
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
	return bool(runtime.bonds.welcomes(_id, "kiss"))


func _stop(reason: String) -> void:
	_log("stop reason=%s state=%d pony=%s" % [reason, state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE]:
		MEMORY.stop_event(main.game, _id, _display_name, _event_id, reason)
	_restore_begin()


# --------------------------------------------------------------------------- camera

func _size_name() -> String:
	if not is_inside_tree():
		return ""
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


## Pose-2 presentation only. The accepted Anon rig's hands read a little large beside a Canon
## pony; JRHNBR needs a smaller correction. Other presets keep the authored size.
static func pose2_palm_scale_for(size_name: String) -> float:
	match size_name:
		"canon":
			return 0.85
		"mounting":
			return 0.95
	return 1.0


## Absolute hand scale for the current body preset, from the per-size caress setting.
func _palm_scale_factor() -> float:
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		var scales: Variant = (caress as Dictionary).get("palm_scale", {})
		if scales is Dictionary:
			return float((scales as Dictionary).get(_size_name(), 1.0))
	return 1.0


func _bed_surface_top() -> float:
	if not is_instance_valid(bed):
		return INF
	var fallback := float(bed.get_meta("mattress_top", 0.6)) + bed.global_position.y
	var points: Array[Vector3] = [bed.global_position]
	return MATTRESS.visible_top(bed, points, fallback)


## Change the player's own eye height for the act instead of writing camera.position.y. That keeps
## `desktop_player._set_eye_y` as the single owner of the camera height and avoids drift/teleports.
func _hide_anon_avatar_for_pose1() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(main) or not is_instance_valid(main.player):
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
	# The pose-1 view settles its aim on her neck (`apply_camera_motion`); the player look controls
	# are left alone so the bed/seated camera is not disturbed.
	_pose1_look_point = _neck_midpoint()
	var forward: Vector3 = -pony.global_basis.z.normalized() if is_instance_valid(pony) else Vector3.FORWARD
	if not _pose1_look_point.is_finite() or not is_instance_valid(pony) \
			or (_pose1_look_point - _pose1_camera).dot(forward) < -0.05:
		_pose1_look_point = (pony.global_position if is_instance_valid(pony) else _pose1_camera) \
			+ forward * 0.20 + Vector3.UP * 0.10
	_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
	_pose1_aim_until = Time.get_ticks_msec() + 1000
	_pose1_camera_log_until = Time.get_ticks_msec() + 10000
	_pose1_camera_log_next = 0
	_pose1_snap_ready = false
	_pose1_camera_rebuilds = 0
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
	if not is_instance_valid(pony):
		return Vector3.INF
	var forward: Vector3 = -pony.global_basis.z.normalized()
	return pony.global_position + forward * 0.20 + Vector3.UP * 0.10


## The fixed pose-1 view orientation: from the camera anchor toward her neck. Computed once so the
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


func _pose1_body_scale() -> float:
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return clampf(float(pony.get("body_scale")), 0.8, 1.6)
	return 1.0


func _pose1_pullback() -> float:
	var value := float(_presentation_cfg.get("pullback", POSE1_CAMERA_PULLBACK_M))
	return value * _pose1_body_scale()


## Framing pitch after the frozen neck aim. Positive looks up; the anchor and settle target do
## not move, so this only tilts the shot and applies live.
func _pose1_pitch_basis() -> Basis:
	var degrees := float(_presentation_cfg.get("pitch_deg", 0.0))
	return Basis(Vector3.RIGHT, deg_to_rad(degrees))


func _pose1_camera_offsets() -> Vector3:
	return Vector3(
		float(_presentation_cfg.get("forward",
			SETTINGS.PRESENTATION_DEFAULTS["missionary"]["forward"])),
		float(_presentation_cfg.get("height",
			SETTINGS.PRESENTATION_DEFAULTS["missionary"]["height"])),
		float(_presentation_cfg.get("side",
			SETTINGS.PRESENTATION_DEFAULTS["missionary"]["side"])))


## Side lean also travels along the mattress toward her head, outside the view-axis clamp. The
## amount is metres at full Q/E and is live.
func _pose1_side_lean_forward() -> float:
	var amount := float(_presentation_cfg.get("side_lean",
		SETTINGS.PRESENTATION_DEFAULTS["missionary"]["side_lean"]))
	return amount * absf(_lean_view_side) * _lean_size_scale()


func _pose1_camera_target() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var root: Vector3 = pony.global_position
	var back: Vector3 = pony.global_basis.z.normalized()
	var body_scale := _pose1_body_scale()
	# Stay behind her neck, toward her rump. Anchoring ahead of the neck put the camera over her
	# head and aimed the shot back down her torso, away from her face. Larger ponies need a
	# proportionally higher and farther-back anchor so the shot does not sit inside her neck.
	var height := (float(_pose_cfg.get("camera_height", POSE1_CAMERA_HEIGHT_M)) + POSE1_CAMERA_LIFT_M) \
		* body_scale
	if _size_name() == "canon":
		height *= 0.9
	var target := root + Vector3.UP * height \
		+ back * float(_pose_cfg.get("camera_back", POSE1_CAMERA_BACK_M)) * body_scale
	var bed_top := _bed_surface_top()
	if is_finite(bed_top) and bed_top <= root.y + 2.0:
		target.y = maxf(target.y, bed_top + 0.30 * body_scale)
	target.y = clampf(target.y, root.y + 0.30 * body_scale, root.y + 1.50 * body_scale)
	# Fine missionary framing: forward along her body, vertical, and her lateral axis. The
	# base anchor would otherwise sit behind her neck and too high for the close shot.
	var offsets := _pose1_camera_offsets()
	target += -back * offsets.x
	target.y += offsets.y
	target += pony.global_basis.x.normalized() * offsets.z
	if is_finite(bed_top) and bed_top <= root.y + 2.0:
		target.y = maxf(target.y, bed_top + 0.10 * body_scale)
	return target


func _pose1_head_transform() -> Transform3D:
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


## The pose-1 head aim uses the camera as Anon's face. Keep a minimum distance so a large pony's
## camera anchor can be near her head without producing near-zero direction flips.
func _pose1_head_look_point(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	var point := view.global_position
	# Move the virtual partner with the displayed lean. Otherwise the framing camera slides
	# sideways while her head stays on the fixed player camera and appears to turn the other way.
	if is_instance_valid(_pose1_view) and view != _pose1_view:
		point += _pose1_view_basis.x * _lateral_lean_shift(_lean_size_scale())
		if is_instance_valid(pony):
			var bed_forward: Vector3 = -pony.global_basis.z
			bed_forward.y = 0.0
			if bed_forward.length_squared() > 0.0001:
				point += bed_forward.normalized() * _pose1_side_lean_forward()
	var head := _pose1_head_transform()
	if not head.origin.is_finite():
		return point
	var offset := point - head.origin
	var minimum := 0.45 * _pose1_body_scale()
	if offset.length() >= minimum:
		return point
	var direction: Vector3 = offset.normalized() if offset.length_squared() > 0.000001 \
		else -pony.global_basis.z.normalized()
	return head.origin + direction * minimum


## Debug readout of how far her actual face points from the act look target. The link updates
## the OpenPony head after the pose modifier, so this is the previous frame's settled frame.
func _pose1_gaze_error() -> float:
	if not is_instance_valid(pony) or not is_instance_valid(_pose) or not _pose.look_point.is_finite():
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
	var to: Vector3 = _pose.look_point - (origin as Vector3)
	if to.length_squared() < 0.000001:
		return -1.0
	return rad_to_deg((forward as Vector3).angle_to(to))


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
	_hip_phase = 0.0
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
		_pose2_base_look = _pose2_neck_point()
		_apply_pose2_base_look()
		_install_anon_thrust()
	_apply_free_camera_lock()


## Lean/caress remain live through the pose-2 afterglow; pose 1 afterglow stays passive.
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
	if targets.y != 0.0:
		_side_return_armed = false
	elif targets.x < 0.0:
		# Pulling back also recentres the shoulder roll instead of leaving it locked until a
		# lean to the other side.
		_side_return_armed = true
	_lean_forward = _lean_step(_lean_forward, targets.x, delta)
	_lean_side = _lean_step(_lean_side, targets.y, delta, _side_return_armed)
	if _side_return_armed and is_zero_approx(targets.y) and absf(_lean_side) <= 0.001:
		_side_return_armed = false
	var alpha := 1.0 - exp(-CAMERA_INERTIA_SMOOTH * delta)
	_lean_view_forward = lerpf(_lean_view_forward, _lean_forward, alpha)
	_lean_view_side = lerpf(_lean_view_side, _lean_side, alpha)
	if _feature("idle_camera_sway"):
		# Idle breathing. The feature toggle is the only way to stop the drift when the
		# player is not leaning.
		_hold_rock_clock += delta
		_lean_view_forward = clampf(_lean_view_forward
			+ sin(_hold_rock_clock * 0.80) * HOLD_SWAY_FORWARD, -1.0, 1.0)
		_lean_view_side = clampf(_lean_view_side
			+ sin(_hold_rock_clock * 0.57 + 1.1) * HOLD_SWAY_SIDE, -1.0, 1.0)
	_lean_action_tick()
	_pose2_kiss_tick()
	_caress_tick(delta)
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


## Advance the oval phase only while that hand is moving. Stopping keeps the palm at the
## current point instead of resetting the stroke.
static func caress_phase_step(phase: float, moving: bool, delta: float) -> float:
	if not moving:
		return phase
	return fmod(phase + CARESS_SPEED_RAD_S * delta, TAU)


## Canon needs a little less travel in the standing pose than the other presets.
func _pose2_lean_scale() -> float:
	var scale := _lean_size_scale()
	if _size_name() == "canon":
		scale *= 0.8
	return scale


## Pose-2 torso angle: hinge Anon's upper body forward over her by moving the head/camera
## forward and down by the spine arc, then countering the hip in `apply_anon_lean`.
func _anon_torso_angle() -> float:
	return deg_to_rad(float(_presentation_cfg.get("torso_angle_deg", 0.0)))


func _anon_torso_forward() -> float:
	return ANON_TORSO_LEN_M * sin(_anon_torso_angle())


func _anon_torso_drop() -> float:
	return ANON_TORSO_LEN_M * (1.0 - cos(_anon_torso_angle()))


func _jiggle_size_scale() -> float:
	return clampf(_size_scale(), 0.5, 1.2)


## Forward and backward leans use different distances. JRHNBR (`1.0`) is the reference size.
static func lean_distance(forward: float, size_scale := 1.0) -> float:
	var metres := LEAN_FORWARD_M if forward >= 0.0 else LEAN_BACK_M
	return metres * forward * size_scale


## The lean always holds a released position. `return_to_zero` is only used by the explicit
## S shoulder recentre; forced end-of-act returns bypass this helper.
static func _lean_step(current: float, target: float, delta: float,
		return_to_zero := false) -> float:
	if is_zero_approx(target):
		if not return_to_zero:
			return current
		return move_toward(current, 0.0, delta / maxf(LEAN_RETURN_SECONDS, 0.001))
	return move_toward(current, target, delta / maxf(LEAN_RAMP_SECONDS, 0.001))


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
		_latch_kiss_side()
		_custom_kiss_active = not _start_base_kiss()
		if _custom_kiss_active:
			_play_mouth_kiss()
			_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
		_on_touch("kiss")
		_log("kiss side anon=%.2f pony=%.2f base=%s" % [
			_kiss_camera_side, _kiss_pony_side, str(_base_kiss_active)])
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
		_pose2_kiss_used = false
		_end_pose2_kiss()
		return
	var want := pose2_kiss_wanted(Input.is_physical_key_pressed(KEY_F), _lean_side)
	if not want:
		_pose2_kiss_used = false
		_end_pose2_kiss()
		return
	if _pose2_kiss_active:
		# The base kiss can finish on its own (deep-kiss timeout); stop holding the pose with it.
		if _base_kiss_active:
			var affection: Variant = _base_kiss_affection
			if not is_instance_valid(affection) or str(affection.get("kind")) != "kiss":
				_end_pose2_kiss()
		elif not _custom_kiss_active:
			_end_pose2_kiss()
		return
	if _pose2_kiss_used or Time.get_ticks_msec() < _pose2_kiss_ready_at:
		return
	_pose2_kiss_used = true
	_pose2_kiss_active = true
	_forced_glance = ""
	_latch_kiss_side()
	_custom_kiss_active = not _start_base_kiss()
	if _custom_kiss_active:
		_play_mouth_kiss()
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
	_on_touch("kiss")
	_log("pose2 kiss start lean=%.2f side=%.2f pony_side=%.2f lateral=%.3f base=%s" % [
		_lean_side, _kiss_camera_side, _kiss_pony_side,
		_lateral_lean_shift(_pose2_lean_scale()), str(_base_kiss_active)])


func _end_pose2_kiss() -> void:
	if not _pose2_kiss_active:
		return
	_pose2_kiss_active = false
	_pose2_kiss_used = false
	_pose2_kiss_ready_at = Time.get_ticks_msec() + KISS_RESTART_COOLDOWN_MS
	_end_base_kiss()
	_custom_kiss_active = false
	_release_kiss_face()
	# Releasing the kiss must not leave the shoulder reach's forced over-the-shoulder glance
	# latched while F is still held.
	_forced_glance = ""
	_glance_left = 0.0
	_glance_back = false
	_glance_wait = randf_range(
		float(_pose_cfg.get("glance_min", GLANCE_MIN_INTERVAL)),
		float(_pose_cfg.get("glance_max", GLANCE_MAX_INTERVAL)))
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
	_palm_contacts.clear()
	_lower_captured = false
	_end_base_kiss()
	_clear_kiss_side()
	_custom_kiss_active = false
	_lean_forward = 0.0
	_lean_side = 0.0
	_lean_view_forward = 0.0
	_lean_view_side = 0.0
	_side_return_armed = false
	_caress_latched = {"L": false, "R": false}
	_caress_key_down = {"L": false, "R": false}
	_pose2_kiss_used = false
	_pose2_kiss_ready_at = 0
	_hold_rock_clock = 0.0
	_kiss_amount = 0.0
	_kiss_lean = 0.0
	_kiss_sound_clock = 0.0
	_release_kiss_face()
	_restore_base_kiss_pose()


## Reuse the game's own kiss in pose 2. `pony_kisser.begin_from_pony()` runs the same eligibility
## checks as a normal Ponese kiss, including `controls_locked`, so unlock for that one call only.
## The AffectionPose modifier is moved to the end of the skeleton chain so its kiss IK layers on
## top of the act pose instead of being overwritten by it. Pose 1 always returns false here.
func _start_base_kiss() -> bool:
	# The stock kiss pose is authored for a standing pony. On the bed its chest/neck give lifts
	# the lying body off the mattress and turns her head across it, so pose 1 uses the act's own
	# head aim instead.
	if pose_id == CATALOG.MISSIONARY:
		return false
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
	_suppress_base_kiss_excitement()
	var pose_node: Variant = affection.get("pose")
	var sk: Variant = pony.get("skeleton")
	if pose_node != null and pose_node.has_method("set_kiss_side"):
		pose_node.call("set_kiss_side", _kiss_pony_side)
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
	_restore_base_kiss_excitement()
	var affection: Variant = _base_kiss_affection
	if is_instance_valid(affection):
		if str(affection.get("kind")) == "kiss":
			affection.call("end")
		# Even if the affection already ended itself, clear its 60 s stare afterglow.
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
	if is_instance_valid(_base_kiss_pose) and _base_kiss_pose.has_method("set_kiss_side"):
		_base_kiss_pose.call("set_kiss_side", 0.0)
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
	_restore_base_kiss_excitement()
	_keep_chin_last()


## A base kiss otherwise triggers the stock unicorn horn sparkle and flutter beat. Keep the beat
## paused for the kiss so a kiss does not read as spellcasting.
func _suppress_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_excitement) or not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	_base_kiss_excitement = excitement as Node
	var beat: Variant = _base_kiss_excitement.get_node_or_null("Beat")
	if beat is Timer:
		_base_kiss_beat = beat as Timer
		_base_kiss_beat_paused = _base_kiss_beat.paused
		_base_kiss_beat.paused = true
	_base_kiss_excitement.set("_until", 0.0)


func _restore_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_beat):
		_base_kiss_beat.paused = _base_kiss_beat_paused
	_base_kiss_beat = null
	_base_kiss_excitement = null
	_base_kiss_beat_paused = false


func _kiss_visible() -> bool:
	if _base_kiss_active:
		return true
	if _pose2_kiss_active and _custom_kiss_active:
		return true
	return _lean_action_active and _lean_action_kind == "kiss" and _custom_kiss_active


func _kiss_lean_distance() -> float:
	return KISS_LEAN_M * _kiss_lean


## The act kiss follows the side Anon leaned to; outside a latched kiss fall back to live input.
func _kiss_side() -> float:
	if absf(_kiss_camera_side) > 0.5:
		return _kiss_camera_side
	if absf(_lean_view_side) > 0.01:
		return signf(_lean_view_side)
	if absf(_lean_action_side) > 0.01:
		return signf(_lean_action_side)
	return 0.0


## `AffectionPose` wants the opposite sign: she must lean toward the same world side Anon moved to.
static func kiss_pony_side(lean_side: float) -> float:
	if absf(lean_side) <= 0.001:
		return 0.0
	return KISS_PONY_SIDE_SIGN * signf(lean_side)


## Lateral shot/hip travel. The lean offset hands over to the single kiss offset as the kiss
## blends in, instead of adding both (0.18 m + 0.18 m is further sideways than her neck reaches,
## and the clearance pass then pushed her muzzle back into him).
static func kiss_lateral_offset(lean_side: float, kiss_side: float, kiss_lean: float,
		size_scale := 1.0) -> float:
	var blend := clampf(kiss_lean, 0.0, 1.0)
	var lean := LEAN_SIDE_M * lean_side * size_scale
	var kiss := KISS_LEAN_SIDE_M * kiss_side
	return lerpf(lean, kiss, blend)


func _lateral_lean_shift(lean_scale: float) -> float:
	return kiss_lateral_offset(_lean_view_side, _kiss_side(), _kiss_lean, lean_scale)


func _latch_kiss_side() -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0
	# Latch the requested lean, not the inertia-smoothed view: switching sides and pressing F
	# immediately must not keep the previous side for the whole kiss.
	var lean := _lean_side
	if absf(lean) <= 0.01:
		lean = _lean_action_side
	if absf(lean) <= 0.01:
		lean = _lean_view_side
	if absf(lean) <= 0.01:
		return
	_kiss_camera_side = signf(lean)
	_kiss_pony_side = kiss_pony_side(_kiss_camera_side)


func _clear_kiss_side() -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0


func _kiss_side_distance() -> float:
	return KISS_LEAN_SIDE_M * _kiss_side() * _kiss_lean


## Her mouth stays at Anon's lips while the kiss channel is held, with a soft repeat sound.
func _kiss_tick(delta: float) -> void:
	var holding := _kiss_visible()
	if _base_kiss_releasing:
		var releasing_affection: Variant = _base_kiss_affection
		if is_instance_valid(releasing_affection) and float(releasing_affection.get("amount")) > 0.2:
			holding = true
	_kiss_lean = move_toward(_kiss_lean, 1.0 if holding else 0.0, delta / KISS_LEAN_SECONDS)
	if _kiss_lean <= 0.0001 and not holding:
		_clear_kiss_side()
	if _base_kiss_releasing:
		var affection: Variant = _base_kiss_affection
		if not is_instance_valid(affection) or float(affection.get("amount")) <= 0.001:
			_restore_base_kiss_pose()
	if _base_kiss_active:
		_kiss_diag_clock -= delta
		if _kiss_diag_clock <= 0.0:
			_kiss_diag_clock = 1.0
			_kiss_diag()
		_update_base_kiss(delta)
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


## The player kisser is paused for the whole act, so it cannot write these itself. Feed the base
## kiss the live mouth/eye/face and its repeat sound, exactly as pony_kisser would.
func _update_base_kiss(delta: float) -> void:
	var affection: Variant = _base_kiss_affection
	if is_instance_valid(affection):
		var view := _kiss_mouth_view()
		if is_instance_valid(view):
			affection.set("target", _kiss_target(view))
			affection.set("eye", view.global_position)
			affection.set("face", view.global_basis.orthonormalized())
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		_play_mouth_kiss()
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


## Once a second while a base kiss runs: confirms she is on the latched side and whether any
## remaining clip is a joint limit, a reach miss, or Anon's eye clearance pushing her back.
func _kiss_diag() -> void:
	var affection: Variant = _base_kiss_affection
	if not is_instance_valid(affection):
		return
	var pose: Variant = affection.get("pose")
	var pose_side := 0.0
	var limited := 0.0
	var miss := 0.0
	var cleared := ""
	if pose != null:
		pose_side = float(pose.get("_side_now"))
		limited = rad_to_deg(float(pose.get("limited")))
		miss = float(pose.get("miss"))
		cleared = str(pose.get("cleared_by"))
	var cam_roll := 0.0
	var head_roll := 0.0
	var skull_lateral := 0.0
	var mouth_gap := -1.0
	var view := _kiss_mouth_view()
	if is_instance_valid(view):
		var target := _kiss_target(view)
		var right := view.global_basis.x.normalized()
		if affection.has_method("mouth_point"):
			var mouth: Variant = affection.call("mouth_point")
			if mouth is Vector3 and (mouth as Vector3).is_finite():
				mouth_gap = (mouth as Vector3).distance_to(target)
		var boop: Variant = pony.get("boop_node") if is_instance_valid(pony) else null
		if boop != null and boop.has_method("skull_world"):
			var skull: Variant = boop.call("skull_world")
			if skull is Vector3:
				skull_lateral = ((skull as Vector3) - target).dot(right)
		cam_roll = rad_to_deg(_camera.rotation.z) if is_instance_valid(_camera) else 0.0
		var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
		if sk is Skeleton3D:
			var skeleton := sk as Skeleton3D
			var head_bone := skeleton.find_bone("pony_head")
			if head_bone >= 0:
				var head_t := skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
				var up := head_t.basis.y.normalized()
				var view_up := view.global_basis.y.normalized()
				head_roll = rad_to_deg(up.signed_angle_to(view_up, -view.global_basis.z.normalized()))
	_log("kiss diag base=%s custom=%s amount=%.2f lean=%.2f cam_side=%.2f pony_side=%.2f pose_side=%.2f cam_roll=%.1f head_roll=%.1f skull_lat=%.3f gap=%.3f limited=%.1fdeg miss=%.3fm clear=%s lateral=%.3f" % [
		str(_base_kiss_active), str(_custom_kiss_active),
		float(affection.get("amount")), _kiss_lean, _kiss_camera_side, _kiss_pony_side,
		pose_side, cam_roll, head_roll, skull_lateral, mouth_gap,
		limited, miss, cleared,
		_lateral_lean_shift(_pose2_lean_scale()) if pose_id == CATALOG.HORSE else 0.0])


func _kiss_target(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	var point := view.global_position + view.global_basis * Vector3(0.0, -0.07, -0.02)
	# Pose 1's player camera is not the rendered shot; move the virtual mouth with the view.
	if pose_id == CATALOG.MISSIONARY:
		point += -view.global_basis.z.normalized() * _kiss_lean_distance()
		point += view.global_basis.x.normalized() * _kiss_side_distance()
		point.y -= KISS_LEAN_DROP_M * _kiss_lean
	return point


## Anon's actual mouth camera. Pose 1 frames the shot through a separate view, so using that as
## the kiss target aimed her at the camera instead of at him.
func _kiss_mouth_view() -> Camera3D:
	if is_instance_valid(main):
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			return view
	return _camera


func _play_mouth_kiss() -> void:
	if is_instance_valid(_act_audio) and _act_audio.foley_enabled():
		_act_audio.play_mouth_kiss(_snout())
		return
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
	return {"palm": shoulder.origin, "outward": outward}


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
	var point: Vector3 = info["palm"]
	var side := "left" if _lean_action_shoulder == "L" else "right"
	if _reach_hand_started <= 0:
		_reset_palm_contact(side)
	# Palm flat on the shoulder coat: the surface contact supplies the position/normal and the
	# shared frame helper keeps the fingers forward with the palm inward.
	var target := _palm_on_coat_frame(side, point, outward, -pony.global_basis.z)
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
		var palm_normal: Vector3 = target.basis.x * (1.0 if side == "left" else -1.0)
		_log("reach hand side=%s target=%s x=%s y=%s z=%s fingers=%s palm=%s" % [
			side, str(target.origin), str(target.basis.x), str(target.basis.y),
			str(target.basis.z), str(-target.basis.z), str(palm_normal)])
	driver.call("set_hold_target", side, frame, "rub")


func _caress_tick(delta: float) -> void:
	if pose_id != CATALOG.HORSE:
		_end_caress()
		return
	var keys := {
		"L": Input.is_physical_key_pressed(KEY_A),
		"R": Input.is_physical_key_pressed(KEY_D),
	}
	var motion_keys := {
		"L": KEY_Z,
		"R": KEY_C,
	}
	for side: String in ["L", "R"]:
		var held := bool(keys[side])
		var pressed := held and not bool(_caress_key_down[side])
		_caress_key_down[side] = held
		if pressed:
			_caress_latched[side] = not bool(_caress_latched[side])
		var move_held := Input.is_physical_key_pressed(motion_keys[side])
		var move_pressed := move_held and not bool(_caress_move_key_down[side])
		_caress_move_key_down[side] = move_held
		if move_pressed:
			_caress_moving[side] = not bool(_caress_moving[side])
			_log("caress movement side=%s %s" % [
				side, "on" if bool(_caress_moving[side]) else "off"])
		var hand_side := "left" if side == "L" else "right"
		# The slapping hand owns the hold target during its swing. Freeze the oval phase so
		# the hand can return to the same caress point without a jump.
		if _smack_active and _smack_side == hand_side:
			continue
		var want := bool(_caress_latched[side])
		if want:
			if not bool(_caress_active[side]):
				_caress_active[side] = true
				_caress_phase[side] = 0.0
				_caress_logged[side] = false
				_caress_return_started[side] = 0
				_reset_palm_contact("left" if side == "L" else "right")
				_log("caress start side=%s" % side)
			_caress_phase[side] = caress_phase_step(
				float(_caress_phase[side]), bool(_caress_moving[side]), delta)
			_set_caress_hand(side)
			_on_touch("caress")
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
	_caress_latched[side] = false
	_caress_phase[side] = 0.0
	_caress_logged[side] = false
	_caress_return_started[side] = 0


func _end_caress() -> void:
	_end_caress_side("L")
	_end_caress_side("R")
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_diag_at = 0


## Hand-marker basis with the palm flat on the coat: local -Z is the fingers, and the palm
## normal (local -X right / +X left) points inward along -outward. No custom roll.
static func palm_surface_basis(side: String, outward: Vector3, finger_hint: Vector3) -> Basis:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector3.RIGHT
	var x_axis := normal * (1.0 if side == "right" else -1.0)
	var fingers := finger_hint.normalized()
	fingers -= x_axis * fingers.dot(x_axis)
	if fingers.length_squared() < 0.0001:
		fingers = Vector3.FORWARD - x_axis * Vector3.FORWARD.dot(x_axis)
	if fingers.length_squared() < 0.0001:
		fingers = Vector3.UP - x_axis * Vector3.UP.dot(x_axis)
	fingers = fingers.normalized()
	var z_axis := -fingers
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


## Caress contact exclusions. The tail flick after a smack can put a tail hull beside the rub
## point; without this the fallback nearest() would snap the palm onto the tail.
func _caress_ignore() -> Array:
	var caress: Variant = _presentation_cfg.get("caress", {})
	if not caress is Dictionary:
		return []
	var raw: Variant = (caress as Dictionary).get("ignore", [])
	if not raw is Array:
		return []
	var out: Array = []
	for region: Variant in raw:
		var name := str(region).to_lower()
		if name in SETTINGS.CARESS_IGNORE_REGIONS and not out.has(name):
			out.append(name)
	return out


static func _region_ignored(region: String, ignore: Array) -> bool:
	if ignore.is_empty():
		return false
	var name := region.to_lower()
	for value: Variant in ignore:
		var prefix := str(value).to_lower()
		if name == prefix or name.begins_with(prefix + "_"):
			return true
	return false


## PonyTouchBody.nearest() without the caress-ignored regions. Only used when the ignore list
## is non-empty; otherwise the game's own query is used unchanged.
func _nearest_touch(point: Vector3, ignore: Array) -> Dictionary:
	var touch: Variant = pony.get("touch_body") if is_instance_valid(pony) else null
	if touch == null or not touch.has_method("nearest"):
		return {}
	var near: Dictionary = touch.call("nearest", point)
	if ignore.is_empty():
		return near
	var entry: Variant = near.get("entry")
	if entry is Dictionary and not _region_ignored(
			str((entry as Dictionary).get("region", "")), ignore):
		return near
	var entries: Variant = touch.get("_entries")
	if not entries is Array:
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for e: Variant in entries:
		if not e is Dictionary:
			continue
		var ed: Dictionary = e
		if _region_ignored(str(ed.get("region", "")), ignore):
			continue
		var world: Variant = ed.get("world")
		if not world is Transform3D:
			continue
		var local: Vector3 = (world as Transform3D).affine_inverse() * point
		var a: Vector3 = ed.get("a", Vector3.ZERO)
		var b: Vector3 = ed.get("b", Vector3.ZERO)
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var away := local - (a + ab * t)
		var distance := away.length() - float(ed.get("r", 0.0))
		if distance < best_distance:
			best_distance = distance
			var normal := Vector3.UP
			if away.length() > 0.000001:
				normal = away.normalized()
			best = {"entry": ed, "distance": distance, "local": local, "normal": normal}
	return best


## Nearest coat point/normal for a palm. FlankSurface owns the flank/rump patch; the body
## hull query covers the shoulder and any point outside that patch.
func _coat_contact(point: Vector3, outward_hint: Vector3,
		ignore: Array = []) -> Dictionary:
	if not is_instance_valid(pony):
		return {"point": point, "normal": outward_hint, "source": "fallback"}
	var outward := outward_hint.normalized()
	if outward.length_squared() < 0.5:
		outward = pony.global_basis.x.normalized()
	if is_instance_valid(_flank):
		var surface: Variant = _flank.get("surface")
		var frame: Variant = _flank.get("frame")
		var sk: Variant = pony.get("skeleton")
		if surface != null and surface.has_method("contact") and frame is Transform3D:
			if surface.has_method("update_pose") and sk is Skeleton3D:
				surface.call("update_pose", sk, frame)
			var local_point: Vector3 = (frame as Transform3D).affine_inverse() * point
			var local_palm: Vector3 = ((frame as Transform3D).basis.inverse() * -outward).normalized()
			var radii: Variant = _flank.get("radii")
			var reach := float((radii as Vector3).z) if radii is Vector3 else 0.10
			var hit: Dictionary = surface.call("contact", local_point, local_point, local_palm, reach)
			var hit_local: Variant = hit.get("position")
			var normal_local: Variant = hit.get("normal")
			if hit_local is Vector3 and normal_local is Vector3:
				var hit_world: Vector3 = (frame as Transform3D) * (hit_local as Vector3)
				var hit_normal: Vector3 = ((frame as Transform3D).basis.inverse().transposed() \
					* (normal_local as Vector3)).normalized()
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
				return {"point": hit_world, "normal": hit_normal, "source": "flank"}
	var touch: Variant = pony.get("touch_body")
	if touch != null and touch.has_method("nearest"):
		var near: Dictionary = _nearest_touch(point, ignore)
		var entry: Variant = near.get("entry")
		var normal_local: Variant = near.get("normal")
		if entry is Dictionary and normal_local is Vector3:
			var world: Variant = (entry as Dictionary).get("world")
			if world is Transform3D:
				var hit_normal: Vector3 = ((world as Transform3D).basis \
					* (normal_local as Vector3)).normalized()
				var distance := float(near.get("distance", 0.0))
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
					distance = -distance
				return {"point": point - hit_normal * distance, "normal": hit_normal,
					"source": "hull"}
	return {"point": point, "normal": outward, "source": "fallback"}


func _palm_contact_state(side: String) -> Dictionary:
	if not _palm_contacts.has(side):
		_palm_contacts[side] = {
			"point": Vector3.INF, "normal": Vector3.UP, "basis": Basis.IDENTITY,
			"source": "", "switches": 0, "miss": 0, "logged": "",
			"normal_step": 0.0, "normal_out": 0.0,
		}
	return _palm_contacts[side]


func _reset_palm_contact(side: String) -> void:
	_palm_contacts.erase(side)


## Keep a genuine coat normal: blending toward a torso radial tilts the palm off the surface
## and presses its heel into the coat. The radial is only a fallback for a degenerate normal or
## one that points into the body.
func _palm_stable_outward(point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var wanted := hint.normalized()
	if wanted.length_squared() < 0.5:
		return _palm_radial_outward(point, hint)
	var radial := _palm_radial_outward(point, hint)
	if radial.length_squared() < 0.5:
		return wanted
	return radial if wanted.dot(radial) < 0.1 else wanted


func _palm_radial_outward(point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var scale := clampf(float(pony.get("body_scale")), 0.8, 1.6)
	var centre: Vector3 = pony.global_position + Vector3.UP * (0.55 * scale)
	var radial: Vector3 = point - centre
	if radial.length_squared() < 0.001:
		return Vector3.ZERO
	return radial.normalized()


## Rotate `from` toward `to` by at most `max_step` radians. Keeps a palm normal from snapping
## when the contact source changes or the coat curvature jumps.
static func rotate_normal_toward(from: Vector3, to: Vector3, max_step: float) -> Vector3:
	var a := from.normalized()
	var b := to.normalized()
	if a.length_squared() < 0.5:
		return b
	if b.length_squared() < 0.5:
		return a
	var angle := a.angle_to(b)
	if angle <= 0.0001 or angle <= max_step:
		return b
	return a.slerp(b, clampf(max_step / angle, 0.0, 1.0)).normalized()


func _palm_on_coat_frame(side: String, point: Vector3, outward_hint: Vector3,
		finger_hint: Vector3, smooth := true, ignore: Array = []) -> Transform3D:
	var hit := _coat_contact(point, outward_hint, ignore)
	var source := str(hit.get("source", "fallback"))
	var hit_point: Vector3 = hit.get("point", point)
	var hit_normal: Vector3 = hit.get("normal", outward_hint)
	if hit_normal.length_squared() < 0.5:
		hit_normal = outward_hint.normalized()
	hit_normal = _palm_stable_outward(hit_point, hit_normal)
	var clearance := _palm_clearance()
	if not smooth:
		return Transform3D(palm_surface_basis(side, hit_normal, finger_hint),
			hit_point + hit_normal * clearance)
	var state := _palm_contact_state(side)
	var last_point: Vector3 = state.point
	var last_normal: Vector3 = state.normal
	var have := last_point.is_finite()
	var changed := source != str(state.source)
	if changed:
		state.switches = int(state.switches) + 1
	else:
		state.switches = 0
	var accept := not changed or int(state.switches) >= PALM_CONTACT_SOURCE_HITS or not have
	if not changed and have and last_normal.dot(hit_normal) < -0.5:
		# A near-opposite normal under the same source is a bad triangle/hull frame; do not
		# let the palm rotate through the body. Smaller changes update the point and blend.
		hit_normal = last_normal
		accept = false
	if source == "fallback":
		state.miss = int(state.miss) + 1
		if have:
			accept = false
	else:
		state.miss = 0
	if not accept and have:
		hit_point = last_point
		hit_normal = last_normal
	if accept:
		state.source = source
	var smooth_point := hit_point
	var smooth_normal := hit_normal
	var normal_step := 0.0
	var normal_out := 0.0
	if have:
		var step := smooth_point - last_point
		if step.length() > PALM_CONTACT_MAX_STEP_M:
			smooth_point = last_point + step.normalized() * PALM_CONTACT_MAX_STEP_M
		var frame_delta := maxf(get_physics_process_delta_time(), 0.001)
		var alpha := 1.0 - exp(-PALM_CONTACT_SMOOTH * frame_delta)
		smooth_point = last_point.lerp(smooth_point, alpha)
		var blended := last_normal.lerp(hit_normal, alpha)
		if blended.length_squared() < 0.5:
			blended = hit_normal
		else:
			blended = blended.normalized()
		var max_step := deg_to_rad(PALM_NORMAL_MAX_DEG_S) * frame_delta
		smooth_normal = rotate_normal_toward(last_normal, blended, max_step)
		# A stale normal must never tuck the palm into the coat. Rotate back toward the
		# outward hint at the bounded rate; only a frame that is already bad snaps out.
		var outward := outward_hint.normalized()
		if outward.length_squared() < 0.5:
			outward = last_normal
		if outward.length_squared() > 0.5:
			normal_out = rad_to_deg(smooth_normal.angle_to(outward))
			if smooth_normal.dot(outward) < 0.1:
				smooth_normal = rotate_normal_toward(last_normal, outward, max_step)
				if smooth_normal.dot(outward) < 0.1:
					smooth_normal = outward
		normal_step = rad_to_deg(last_normal.angle_to(smooth_normal))
	# The palm plane is rebuilt from the final normal every frame, not slerped on its own,
	# so it cannot lag around and rotate into her between contact updates.
	var smooth_basis := palm_surface_basis(side, smooth_normal, finger_hint)
	state.point = smooth_point
	state.normal = smooth_normal
	state.basis = smooth_basis
	state.normal_step = normal_step
	state.normal_out = normal_out
	if str(state.logged) != source:
		state.logged = source
		_log("palm contact side=%s source=%s point=%s normal=%s" % [
			side, source, str(smooth_point), str(smooth_normal)])
	var palm := smooth_point + smooth_normal * clearance
	return Transform3D(smooth_basis, palm)


func _palm_clearance() -> float:
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = float(pony.get("body_scale"))
	var distance := PALM_ON_COAT_CLEARANCE_M
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		distance = float((caress as Dictionary).get("palm_distance", distance))
	return palm_clearance_for(scale, distance)


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
	var flank_world: Vector3 = centre_world \
		+ Vector3.UP * (float(profile.get("up", 0.16)) + CARESS_UP_BIAS_M) \
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
	var up := Vector3.UP.slide(normal)
	if up.length_squared() < 0.001:
		# On the rump top the world-up tangent collapses; use the body axis instead.
		up = -pony.global_basis.z.slide(normal)
	up = up.normalized()
	var across := up.cross(normal).normalized()
	var angle := float(_caress_phase[side])
	var offset := (across * (cos(angle) * CARESS_OVAL_ACROSS)
		+ up * (sin(angle) * CARESS_OVAL_UP)) * (CARESS_RADIUS_M * size)
	var hand_side := "left" if side == "L" else "right"
	var target := _palm_on_coat_frame(hand_side, centre_world + offset, normal,
		-pony.global_basis.z, true, _caress_ignore())
	var return_started := int(_caress_return_started.get(side, 0))
	if return_started > 0:
		var elapsed := float(Time.get_ticks_msec() - return_started) / 1000.0
		if elapsed >= CARESS_RETURN_SECONDS:
			_caress_return_started[side] = 0
		else:
			var t := smoothstep(0.0, 1.0, elapsed / CARESS_RETURN_SECONDS)
			var from: Transform3D = _caress_return_from[side]
			target = from.interpolate_with(target, t)
	if not bool(_caress_logged[side]):
		_caress_logged[side] = true
		_log("caress hand side=%s target=%s normal=%s x=%s y=%s z=%s lift=%.3f" % [
			hand_side, str(target.origin), str(normal), str(target.basis.x),
			str(target.basis.y), str(target.basis.z),
			(centre_world + offset).y - pony.global_position.y])
	if Time.get_ticks_msec() >= _caress_diag_at:
		_caress_diag_at = Time.get_ticks_msec() + 1000
		_caress_diag(hand_side, target, centre_world + offset, shoulder_world, side)
	var driver := _desktop_pose_driver()
	if is_instance_valid(driver) and driver.has_method("set_hold_target"):
		driver.call("set_hold_target", hand_side, target, "rub")


## Once a second while a hand caresses: where the rub sits relative to her root/shoulder, how
## far the driven hand is from its target, and whether the contact is missing or switching.
func _caress_diag(hand_side: String, target: Transform3D, rub_point: Vector3,
		shoulder_point: Vector3, side: String) -> void:
	if not is_instance_valid(pony):
		return
	var root_y: float = pony.global_position.y
	var state := _palm_contact_state(hand_side)
	var hand_dist := -1.0
	var driver := _desktop_pose_driver()
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var frame_v: Variant = driver.call("hand_frame", hand_side)
		if frame_v is Transform3D and (frame_v as Transform3D).is_finite():
			hand_dist = (frame_v as Transform3D).origin.distance_to(target.origin)
	_log("caress diag side=%s rub_h=%.3f shoulder_h=%.3f hand_dist=%.3f source=%s miss=%d switches=%d normal_step=%.1f normal_out=%.1f" % [
		side, rub_point.y - root_y, shoulder_point.y - root_y, hand_dist,
		str(state.source), int(state.miss), int(state.switches),
		float(state.get("normal_step", 0.0)), float(state.get("normal_out", 0.0))])


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
	# If a hand is already resting on the flank, slap with that hand. Both on the flank: pick
	# one at random. Otherwise keep the lean-based cheek/hand mapping.
	var hand_side := ""
	if _caress_active["L"] and _caress_active["R"]:
		hand_side = "left" if randf() < 0.5 else "right"
	elif _caress_active["L"]:
		hand_side = "left"
	elif _caress_active["R"]:
		hand_side = "right"
	var index := 0 if hand_side == "left" else (1 if hand_side == "right" else smack_side_index(_lean_side))
	if index < 0:
		index = 0 if randf() < 0.5 else 1
		hand_side = "left" if index == 0 else "right"
	elif hand_side.is_empty():
		hand_side = "left" if index == 0 else "right"
	var source := "caress" if _caress_active["L"] or _caress_active["R"] else "lean"
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
		var driver := _desktop_pose_driver()
		var from_frame := Transform3D.IDENTITY
		if is_instance_valid(driver) and driver.has_method("hand_frame"):
			var current: Variant = driver.call("hand_frame", hand_side)
			if current is Transform3D and (current as Transform3D).is_finite():
				from_frame = current
		if is_instance_valid(driver) and from_frame.is_finite():
			var world_centre: Vector3 = _flank.global_transform * at
			var target := _palm_on_coat_frame(hand_side, world_centre, normal, Vector3.UP, false)
			_smack_from = from_frame
			_smack_to = target
			_smack_index = index
			_smack_at = at
			_smack_side = hand_side
			_smack_started = now
			_smack_impact_done = false
			_smack_active = true
			_log("smack swing side=%.2f cheek=%s at=%s hand=%s source=%s" % [
				_lean_side, "L" if index == 0 else "R", str(at), hand_side, source])
			return
	_flank_impact_without_reaction(index, at)
	_on_touch("smack")
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
		_on_touch("smack")
	if phase >= 1.0:
		_end_smack_swing()


func _end_smack_swing() -> void:
	if not _smack_active:
		return
	if not _smack_side.is_empty():
		var driver := _desktop_pose_driver()
		var caress_side := "L" if _smack_side == "left" else "R"
		if bool(_caress_active[caress_side]):
			# The smack may have moved the tail or another soft hull next to the rub point.
			# Drop the cached source/normal and reacquire the caress contact before returning.
			var from := _smack_to
			if is_instance_valid(driver) and driver.has_method("hand_frame"):
				var current: Variant = driver.call("hand_frame", _smack_side)
				if current is Transform3D and (current as Transform3D).is_finite():
					from = current
			_reset_palm_contact(_smack_side)
			_caress_return_from[caress_side] = from
			_caress_return_started[caress_side] = Time.get_ticks_msec()
			_set_caress_hand(caress_side)
			_log("smack return side=%s caress=%s target=%s" % [
				_smack_side, caress_side,
				str(_palm_contact_state(_smack_side).get("point", Vector3.INF))])
		elif is_instance_valid(driver) and driver.has_method("clear_hold_target"):
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


## Pose-2 hip phase follows the mouse depth directly, with a short low-pass so a single-frame
## mouse step does not snap the body. Depth is the input; this is not a speed attack.
func _hip_phase_tick(delta: float) -> void:
	if pose_id != CATALOG.HORSE or state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_hip_phase = 0.0
		return
	_hip_phase = hip_phase_step(_hip_phase, depth, delta)


## Pure hip smoothing for tests: depth is the input, this only removes single-frame steps.
static func hip_phase_step(current: float, depth_value: float, delta: float) -> float:
	var alpha := 1.0 - exp(-delta / maxf(HIP_SMOOTH_S, 0.001))
	return lerpf(current, clampf(depth_value, 0.0, 1.0), alpha)


## Signed mouse-depth speed for the camera. Update it on the physics tick where `depth`
## changes; render frames only consume the filtered value, so physics/render rate mismatch
## cannot inject a ripple.
func _depth_speed_tick(delta: float) -> void:
	var raw_speed := (depth - _depth_prev) / maxf(delta, 0.0001)
	_depth_prev = depth
	var alpha := 1.0 - exp(-delta / maxf(CAM_SPEED_SMOOTH_S, 0.001))
	_depth_speed = lerpf(_depth_speed, raw_speed, alpha)


## Pose-2 yaw/pitch from the lean vector, applied to the player camera on top of the base aim.
func _apply_pose2_lean_look() -> void:
	if not _free_camera_active or pose_id != CATALOG.HORSE or _player_pony or _headset_view():
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Node = main.player
	var lean_scale := _pose2_lean_scale()
	var yaw := _look_yaw + deg_to_rad(LEAN_SIDE_YAW_DEG) * _lean_view_side * lean_scale
	# Turn a little further toward her while kissing, over the shoulder.
	yaw += deg_to_rad(KISS_CAMERA_YAW_DEG) * _kiss_lean * _kiss_side()
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
	_install_palm_scale(avatar)


func _install_palm_scale(avatar: Node3D) -> void:
	_remove_palm_scale()
	if not is_instance_valid(avatar):
		return
	var factor := _palm_scale_factor()
	if is_equal_approx(factor, 1.0):
		return
	var skeleton := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(skeleton):
		_log("pose2 palm scale skipped: no skeleton")
		return
	_palm_scale = PALM_SCALE.new()
	_palm_scale.name = "UnfplapPalmScale"
	_palm_scale.set("skeleton", skeleton)
	_palm_scale.set("factor", factor)
	_palm_scale.process_priority = 10
	skeleton.add_child(_palm_scale)
	_log("pose2 palm scale=%.2f size=%s" % [factor, _size_name()])


func _refresh_palm_scale() -> void:
	if pose_id != CATALOG.HORSE or not is_instance_valid(_anon_thrust_avatar):
		return
	var factor := _palm_scale_factor()
	if is_equal_approx(factor, 1.0):
		_remove_palm_scale()
		return
	if is_instance_valid(_palm_scale):
		if not is_equal_approx(float(_palm_scale.get("factor")), factor):
			_palm_scale.set("factor", factor)
		return
	_install_palm_scale(_anon_thrust_avatar)


func _remove_palm_scale() -> void:
	if is_instance_valid(_palm_scale):
		_palm_scale.set("active", false)
		_palm_scale.call("restore")
		_palm_scale.queue_free()
	_palm_scale = null


func _remove_anon_thrust() -> void:
	_remove_palm_scale()
	if is_instance_valid(_anon_thrust_avatar) and is_instance_valid(_anon_thrust_original) \
			and _anon_thrust_avatar.get("desktop_pose_driver") == _anon_thrust_driver:
		_anon_thrust_avatar.set("desktop_pose_driver", _anon_thrust_original)
	if is_instance_valid(_anon_thrust_driver):
		_anon_thrust_driver.queue_free()
	_anon_thrust_driver = null
	_anon_thrust_original = null
	_anon_thrust_avatar = null


## Called after anon_body has set the hip target, through the desktop pose-driver wrapper.
## The hip follows the lightly smoothed mouse depth, so its position is the mouse travel.
func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	if pose_id != CATALOG.HORSE or _hip_phase <= 0.0001 or not is_instance_valid(hip):
		return
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	hip.global_position += -facing.z.normalized() * (THRUST_MAX_M * scale * _hip_phase)


## Phase-2 Anon body lean: keep the pelvis planted behind her rump. The camera/head moves
## forward or sideways, so the torso hinges at the hips instead of the whole body sliding into
## her. Pulling back still moves the whole body away.
func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	if pose_id != CATALOG.HORSE or not _free_camera_active or not is_instance_valid(hip):
		return
	var forward := -facing.z.normalized()
	var side := facing.x.normalized()
	var lean_scale := _pose2_lean_scale()
	var forward_shift := lean_distance(maxf(_lean_view_forward, 0.0), lean_scale) \
		+ _kiss_lean_distance() + _anon_torso_forward()
	hip.global_position -= forward * forward_shift
	var side_shift := _lateral_lean_shift(lean_scale)
	hip.global_position -= side * side_shift
	# The kiss and torso angle drop the camera/head; keep the pelvis planted through the hinge.
	hip.global_position.y += KISS_LEAN_DROP_M * _kiss_lean + _anon_torso_drop()
	# Depth moves the pelvis back; the chest/head stay forward, so the upper body thrusts.
	hip.global_position -= forward * (_hip_phase * ANON_THRUST_SWAY_M * lean_scale)
	# The feet are placed from the camera/head before this call. Pin the lower body so a forward
	# or kiss lean hinges the torso instead of walking his legs into the shot.
	var body := hip.get_parent()
	if body != null:
		var left: Variant = body.get("_left_foot")
		var right: Variant = body.get("_right_foot")
		if forward_shift > 0.001 or absf(side_shift) > 0.001 or _kiss_lean > 0.001:
			if not _lower_captured and left is Node3D and right is Node3D:
				_lower_left = (left as Node3D).global_transform
				_lower_right = (right as Node3D).global_transform
				_lower_captured = true
				_log("pose2 lower body pinned")
			if _lower_captured:
				if left is Node3D:
					(left as Node3D).global_transform = _lower_left
				if right is Node3D:
					(right as Node3D).global_transform = _lower_right
		elif _lower_captured:
			_lower_captured = false
			_log("pose2 lower body released")


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
		var body_scale := _pose1_body_scale()
		var bed_top := _bed_surface_top()
		var rebuild := ""
		if not _pose1_camera.is_finite():
			rebuild = "invalid"
		elif _pose1_camera.distance_to(pony.global_position) > 3.0:
			rebuild = "distance"
		elif is_finite(bed_top) and _pose1_camera.y < bed_top - 0.05:
			rebuild = "below-bed"
		if not rebuild.is_empty():
			_pose1_camera = _pose1_camera_target()
			_pose1_camera_rebuilds += 1
			_log("pose1 CAMERA REBUILD #%d reason=%s size=%s scale=%.2f pony=%s anchor=%s bed_top=%.2f" % [
				_pose1_camera_rebuilds, rebuild, _size_name(), body_scale,
				str(pony.global_position), str(_pose1_camera), bed_top])
		if not _pose1_camera.is_finite():
			return
		if is_finite(bed_top) and bed_top <= pony.global_position.y + 2.0 \
				and _pose1_camera.y < bed_top + 0.15 * body_scale:
			_pose1_camera.y = bed_top + 0.30 * body_scale
		_pose1_camera.y = clampf(_pose1_camera.y, pony.global_position.y + 0.30 * body_scale,
			pony.global_position.y + 1.50 * body_scale)
		if not is_instance_valid(_pose1_view):
			_make_pose1_view()
		if not is_instance_valid(_pose1_view):
			return
		_pose1_view.global_position = _pose1_camera + Vector3.UP * _bob
		# Pull the whole shot back along its own view axis; the frozen aim still points at her neck.
		_pose1_view.global_position += _pose1_view_basis.z * _pose1_pullback()
		var lean_scale := _lean_size_scale()
		var lean_forward := lean_distance(_lean_view_forward, lean_scale) \
			+ lean_distance(POSE1_START_LEAN, lean_scale)
		var to_target := _pose1_look_target() - _pose1_camera
		if lean_forward < 0.0:
			# Never let the shot cross its own neck target and flip the view backwards.
			var room := maxf(0.0, to_target.dot(-_pose1_view_basis.z) - 0.12)
			lean_forward = -minf(-lean_forward, room)
		# Stop 0.12 m before the neck instead of crossing it when the start offset is added.
		var forward_room := maxf(0.0, to_target.dot(-_pose1_view_basis.z)
			+ _pose1_pullback() - 0.12)
		lean_forward = minf(lean_forward, forward_room)
		var kiss_lean := _kiss_lean_distance()
		if kiss_lean > 0.0:
			var view_room := maxf(0.0, to_target.dot(-_pose1_view_basis.z)
				+ _pose1_pullback() - 0.12 - maxf(lean_forward, 0.0))
			kiss_lean = minf(kiss_lean, view_room)
		_pose1_view.global_position -= _pose1_view_basis.z \
			* (-_back + lean_forward + kiss_lean)
		# The speed-driven surge runs along the mattress toward her head, not down the view axis.
		var bed_forward: Vector3 = -pony.global_basis.z
		bed_forward.y = 0.0
		if bed_forward.length_squared() > 0.0001:
			_pose1_view.global_position += bed_forward.normalized() \
				* (_lean + _pose1_side_lean_forward())
		_pose1_view.global_position.y -= KISS_LEAN_DROP_M * _kiss_lean
		_pose1_view.global_position += _pose1_view_basis.x \
			* _lateral_lean_shift(lean_scale)
		_camera_basis_ready = true
		# Settle the aim on her neck while the act pose blends in. The target is her neck, not
		# the moving view, and the basis comes from the fixed anchor; no feedback loop.
		if Time.get_ticks_msec() < _pose1_aim_until:
			var neck := _neck_midpoint()
			var forward: Vector3 = -pony.global_basis.z.normalized()
			# Never re-aim at a neck point behind the anchor; that flips the shot back down her
			# torso. Keep the previous target when the pose puts the neck behind the camera.
			if neck.is_finite() and (neck - _pose1_camera).dot(forward) > 0.02:
				_pose1_look_point = neck
			_pose1_view_basis = _pose1_aim_basis(_pose1_camera)
		var lean := Basis.from_euler(Vector3(
			-deg_to_rad(LEAN_PITCH_DEG) * absf(_lean_view_forward) * lean_scale,
			-deg_to_rad(LEAN_SIDE_YAW_DEG) * _lean_view_side * lean_scale,
			(-deg_to_rad(LEAN_SIDE_ROLL_DEG) * _lean_view_side
				+ deg_to_rad(LEAN_ROLL_DEG) * _lean_view_forward) * lean_scale))
		_pose1_view.global_basis = _pose1_view_basis * _pose1_pitch_basis() * lean
		var look_dir := _pose1_look_target() - _pose1_view.global_position
		var look_dot := (-_pose1_view.global_basis.z).dot(look_dir.normalized()) \
			if look_dir.length_squared() > 0.000001 else 1.0
		if not _pose1_basis_logged:
			_pose1_basis_logged = true
			_log("pose1 camera base_euler=%s applied_basis=%s" % [
				str(_pose1_view_basis.get_euler()), str(_pose1_view.global_basis)])
		var now := Time.get_ticks_msec()
		if now < _pose1_camera_log_until and now >= _pose1_camera_log_next:
			_pose1_camera_log_next = now + 100
			var dot := (-_pose1_view.global_basis.z).dot(look_dir.normalized()) \
				if look_dir.length_squared() > 0.000001 else 0.0
			_log("pose1 cam anchor=%s view=%s base_euler=%s target=%s dot=%.3f gaze=%.1f bed=%.2f pose=%.2f lean=%.2f/%.2f size=%s%.2f" % [
				str(_pose1_camera), str(_pose1_view.global_position),
				str(_pose1_view_basis.get_euler()), str(_pose1_look_target()), dot,
				_pose1_gaze_error(), bed_top, _pose_basis_amount(),
				_lean_view_forward, _lean_view_side, _size_name(), _size_scale()])
		if is_instance_valid(main) and bool(main.get("debug_logs")):
			var view_basis := _pose1_view.global_basis
			if _pose1_snap_ready:
				var basis_delta := rad_to_deg(_pose1_last_view_basis.get_rotation_quaternion() \
					.angle_to(view_basis.get_rotation_quaternion()))
				var pos_delta := _pose1_last_view_pos.distance_to(_pose1_view.global_position)
				if basis_delta > 15.0 or pos_delta > 0.12:
					_log("pose1 CAMERA SNAP basis=%.1fdeg pos=%.3fm view=%s anchor=%s target=%s dot=%.3f lean=%.2f/%.2f kiss=%.2f size=%s scale=%.2f" % [
						basis_delta, pos_delta, str(_pose1_view.global_position), str(_pose1_camera),
						str(_pose1_look_target()), look_dot, _lean_view_forward, _lean_view_side,
						_kiss_lean, _size_name(), body_scale])
				var head := _pose1_head_transform()
				if head.origin.is_finite():
					var head_angle := rad_to_deg(_pose1_last_head.basis.get_rotation_quaternion() \
						.angle_to(head.basis.get_rotation_quaternion()))
					var head_move := _pose1_last_head.origin.distance_to(head.origin)
					if head_angle > 18.0 or head_move > 0.05:
						_log("pose1 HEAD SNAP angle=%.1fdeg move=%.3fm head=%s look=%s view=%s dot=%.3f size=%s scale=%.2f" % [
							head_angle, head_move, str(head.origin), str(_pose.look_point if is_instance_valid(_pose) else Vector3.INF),
							str(_pose1_view.global_position), look_dot, _size_name(), body_scale])
					_pose1_last_head = head
			_pose1_last_view_basis = view_basis
			_pose1_last_view_pos = _pose1_view.global_position
			_pose1_snap_ready = true
		return
	var lean_scale := _pose2_lean_scale()
	_set_camera_offsets(_bob - KISS_LEAN_DROP_M * _kiss_lean - _anon_torso_drop(),
		_lean - _back + lean_distance(_lean_view_forward, lean_scale)
		+ _kiss_lean_distance() + _anon_torso_forward(), _lateral_lean_shift(lean_scale))
	if pose_id == CATALOG.HORSE and _free_camera_active and is_instance_valid(_camera):
		_camera.rotation.z = (-deg_to_rad(LEAN_SIDE_ROLL_DEG) * _lean_view_side \
			+ deg_to_rad(LEAN_ROLL_DEG) * _lean_view_forward) * lean_scale
		_camera.rotation.x = clampf(
			_look_pitch - deg_to_rad(LEAN_PITCH_DEG) * absf(_lean_view_forward) * lean_scale,
			-1.5, 1.5)


func _pose_basis_amount() -> float:
	return float(_pose.get("amount")) if is_instance_valid(_pose) else 0.0


func _pose2_eye_height() -> float:
	var height := _player_eye_height()
	if _size_name() == "canon":
		height -= CANON_POSE2_CAMERA_DROP_M
	elif _size_name() == "mounting":
		height += MOUNTING_POSE2_CAMERA_LIFT_M
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
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		# stay() clears the route, but conversation facing still writes face_point and can make
		# her take a turn step. Clear both late in the tick so the act owns the body facing.
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)


## Multiplier-based glance-back speed. Higher speed means a shorter fade.
static func glance_back_fade_for(speed: float) -> float:
	return GLANCE_BACK_FADE / clampf(speed, 0.25, 3.0)


func _glance_back_fade() -> float:
	return glance_back_fade_for(float(_presentation_cfg.get("glance_back_speed", 1.0)))


## Every few seconds she turns her head back toward Anon, then forward again. The game's
## secondary gaze owns the turn; pose 2 only adds the optional throw-back rotation (`head_back`),
## eased so it does not snap.
func _drive_glance(delta: float) -> void:
	if not _has_facing or pose_id != CATALOG.HORSE or not is_instance_valid(pony):
		return
	# The base kiss owns the head and gaze while it runs or releases. Clear the shoulder reach's
	# forced over-the-shoulder look so the two head poses do not fight and clip.
	if _pose2_kiss_active or _base_kiss_releasing:
		if is_instance_valid(_pose):
			_glance_head_back = move_toward(_glance_head_back, 0.0, delta / _glance_back_fade())
			_pose.set("head_back", _glance_head_back)
		_forced_glance = ""
		_glance_left = 0.0
		_glance_back = false
		return
	# A full forward W lean (no side lean, no kiss) makes her throw her head fully back and
	# look up at Anon instead of waiting for a random glance.
	var lean_up := _lean_forward >= 0.95 and absf(_lean_side) <= 0.2 and not _pose2_kiss_active
	if is_instance_valid(_pose):
		var back_target := 1.0 if (not _forced_glance.is_empty() or lean_up \
			or (_glance_left > 0.0 and _glance_back)) else 0.0
		_glance_head_back = move_toward(_glance_head_back, back_target, delta / _glance_back_fade())
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
	_lean = 0.0
	_lean_velocity = 0.0
	_depth_prev = 0.0
	_depth_speed = 0.0
	_hip_phase = 0.0
	_back = 0.0
	_back_target = 0.0
	_pose1_camera = Vector3.INF
	_camera_basis_ready = false
	_pose2_base_saved = false
	_camera = null


# --------------------------------------------------------------------------- audio

## Create the optional audio node on first use, or update its flags if it already exists.
## This keeps act_audio.gd and its pack streams out of a both-flags-off act.
func _ensure_act_audio(foley: bool, vocals: bool, climax: bool) -> void:
	if is_instance_valid(_act_audio):
		_act_audio.set_enabled(foley, vocals, climax)
		return
	var audio_script: Script = load(ACT_AUDIO_PATH)
	if audio_script == null:
		return
	_act_audio = audio_script.new()
	_act_audio.name = "UnfplapActAudio"
	add_child(_act_audio)
	_act_audio.setup(foley, vocals, climax)


func _start_audio() -> void:
	_stop_audio()
	_bed_soft = is_instance_valid(bed) \
		and ("couch" in bed.name.to_lower() or "sofa" in bed.name.to_lower()
			or "cloth" in bed.name.to_lower())
	var foley := _feature("act_foley")
	var vocals := _feature("act_vocals")
	var climax := _feature("act_climax")
	if foley or vocals or climax:
		_ensure_act_audio(foley, vocals, climax)
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
	if is_instance_valid(_act_audio):
		_act_audio.stop()
		_act_audio.queue_free()
		_act_audio = null
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
	# With act foley on, the depth-crossing trigger owns the impact. Keeping this silent avoids a
	# second plap when the stroke closes on the mouse reversal.
	if is_instance_valid(_act_audio) and _act_audio.foley_enabled():
		return
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
	if not _climax_streams.is_empty() and is_instance_valid(_climax_sound):
		_climax_sound.stream = _climax_streams[randi() % _climax_streams.size()]
		_climax_sound.global_position = _snout()
		_climax_sound.pitch_scale = randf_range(0.95, 1.05)
		_climax_sound.play()
	if is_instance_valid(_act_audio):
		_act_audio.play_climax_wet(_dock_point())
		_act_audio.play_climax_voice(_snout())


func _breath_tick(delta: float) -> void:
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return
	if _breath_streams.is_empty() or not is_instance_valid(_breath):
		return
	var rate := clampf(_thrusts_per_second() / BREATH_RATE_CAP, 0.0, 1.0)
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


func _thrusts_per_second() -> float:
	var now := Time.get_ticks_msec() * 0.001
	while not _thrust_times.is_empty() and now - float(_thrust_times[0]) > 1.0:
		_thrust_times.pop_front()
	return float(_thrust_times.size())


func _camera_position() -> Vector3:
	if is_instance_valid(_camera):
		return _camera.global_position
	return _snout()


func _bed_audio_point() -> Vector3:
	if is_instance_valid(bed):
		return bed.global_position + Vector3.UP * 0.35
	return _rump_point()


func _snout() -> Vector3:
	var boop: Variant = pony.get("boop_node")
	if is_instance_valid(boop) and boop.has_method("nose_world"):
		return boop.call("nose_world")
	return pony.global_position + Vector3.UP * 1.0
