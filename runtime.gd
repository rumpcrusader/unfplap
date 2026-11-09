extends Node
## One per pony. Holds the act state machine and all per-act state. It never edits game files.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/tail_lay.gd")
const DOCK_TAIL_COAT := preload("res://mods/unfplap/dock_tail_coat_follow.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/act_summary.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const ACT_TOLERANCE := preload("res://mods/unfplap/act_tolerance.gd")
const TAIL_TUCK := preload("res://mods/unfplap/tail_tuck.gd")
const REST := preload("res://mods/unfplap/rest_control.gd")
const WITNESS := preload("res://mods/unfplap/witness.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SEX_BOND := preload("res://mods/unfplap/sex_bond.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const AFTERCARE := preload("res://mods/unfplap/aftercare.gd")
const SATISFIED := preload("res://mods/unfplap/satisfied.gd")
const UPSET := preload("res://mods/unfplap/upset.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
const AUTO_THRUST := preload("res://mods/unfplap/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/auto_panel.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const UTTERANCE := preload("res://mods/unfplap/utterance.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/utterance_scheduler.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/relationship_cue.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const CHIN_DEBUG := preload("res://mods/unfplap/chin_debug.gd")
const BODY_SWAY := preload("res://mods/unfplap/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/prone_sway.gd")
const EAR_TWITCH := preload("res://mods/unfplap/ear_twitch.gd")
const CAESS := preload("res://mods/unfplap/standing_caress.gd")
const KISS := preload("res://mods/unfplap/kiss_control.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/standing_presentation.gd")
const SOUND := preload("res://mods/unfplap/act_sound.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy_act.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/missionary_anon.gd")
const VR_ACT := preload("res://mods/unfplap/vr_act.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const FLANK_TOUCH := preload("res://world/characters/hybrid_mare/pony_flank_touch.gd")
const VOICE := preload("res://mods/unfplap/voice_status.gd")
## Loaded lazily so both audio flags off never load the pack streams or the catalogue.
const ACT_AUDIO_PATH := "res://mods/unfplap/act_audio.gd"

enum State { IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE }

const READINESS_MAX := 100.0
## Act eyelid values: half-lidded through ACTIVE, wide only at climax, sleepier afterglow.
const ACT_LIDS := 0.45
const CLIMAX_LIDS := 0.0
const AFTERGLOW_LIDS := 0.9
const AFTERGLOW_CLOSE_LIDS := 0.95
## Readiness that triggers one pony climax. The player's afterglow is separate.
const PONY_CLIMAX_AT := READINESS_MAX
## Readiness per real thrust. Both preference axes match, one axis matches, or neither matches.
const THRUST_HEAT_BOTH := 1.4
const THRUST_HEAT_ONE := 0.7
## Perceived intensity is scored from average stroke speed. Visual impact uses a separate
## scale so normal and fast thrusts move the rump and camera; slow and shallow strokes stay
## lighter.
const THRUST_IMPACT_GAIN := 2.0
const THRUST_HEAT_NONE := 0.0
## Heat multiplies every real thrust chunk while the estrus cycle is enabled and she is in heat.
const HEAT_READINESS := 1.6
## Never let a macro score faster than this.
const THRUST_SCORE_MIN_INTERVAL := 0.2
## Touch and talk can warm her to this point; only real thrusts can finish her.
const ASSIST_CAP := 60.0
const TOUCH_HEAT := 6.0
const TALK_HEAT := 6.0
## A liked touch/talk briefly makes real thrusts land harder.
const RECEPTIVE_BOOST := 1.25
## Readiness text clears after this long without an inward thrust.
const STROKE_MEMORY_S := 1.2
## Appended to cue prompts to stop the model turning every cue into a command.
const CUE_REACTION_NOTE := "\nDo not turn the private moment into a repeated command; say it as your own reaction or preference."
## integration: line-variety history and angles, ported from the fork.
const RECENT_LINES := 8
const ANGLES_REMEMBERED := 7
const LINE_ANGLES := [
	"say something about a thing you two talked about earlier.",
	"tease him.",
	"tell him exactly what you want next.",
	"say his name, and little else.",
	"mention where you are right now.",
	"tell him something you have never said out loud.",
	"sound surprised at yourself.",
	"say something tender, in the middle of all this.",
	"let him see how much you trust him.",
	"make a joke, in your usual voice.",
	"complain playfully about something he is doing.",
	"bring up how you feel about him lately.",
	"say something only you would say, true to your personality.",
]
const SPEECH_ROUGHNESS := {"soft": 0.1, "firm": 0.5, "rough": 1.0}
const SPEECH_FULL_PACE := 3.0
## integration: optional bystander lines.
const BYSTANDER_FIRST_S := 12.0
const BYSTANDER_GAP_S := 20.0
const BYSTANDER_CHANCE := 0.7
const BYSTANDER_MAX := 3
const BYSTANDER_PROMPT := "You can see Anon and %s having sex right in front of you, %s Say ONE short line in your own voice, at most 14 words, aloud to them or to yourself. Ponies have much less shame about this than humans do, so react the way a pony would: amused, teasing, curious, nosy, a little flustered, or mildly put out, but never horrified, panicked or disgusted. Mention where they are doing it if that is what stands out. Do not join in, do not describe anatomy, and do not ask a question that needs an answer."
const BYSTANDER_OUTDOORS := "out in the open where anypony could walk past."
const BYSTANDER_INDOORS := "indoors, in a house you are also in."
var _bystander_event := ""
var _bystander_spoken: Array[String] = []
var _bystander_wait := 0.0
const CLIMAX_SECONDS := 5.0
const CLIMAX_BOBS := 2
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## The shaft length used for the depth scale when the anatomy part is not showing, so the mouse
## feel is the same with the anatomy off. Close to the default part's visible length.
const NOMINAL_SHAFT_M := 0.2
## Same hold length the game uses for bridal-carry initiation (interactor KEY_HOLD_SECONDS).
const HOLD_Y_SECONDS := 0.35
## Debug perf probe window (one `[unfplap] perf` block per second, DEBUG LOGS only).
const PERF_WINDOW_S := 1.0
## After this long the mare may choose to end the afterglow herself. Being held or caressed
## lowers the chance; an accepted [stay] pauses the roll entirely.
const AFTERGLOW_SELF_END_SECONDS := 16.0
const AFTERGLOW_SELF_END_CHECK_S := 1.0
const AFTERGLOW_SELF_END_CHANCE_CLOSE := 0.12
const AFTERGLOW_SELF_END_CHANCE_ALONE := 0.30
## Missionary camera: above and behind her neck so the shot looks forward along her body at her
## face. `pony.global_basis.z` is her backward direction.
## Default room between the missionary shot and the pony; the presentation setting overrides it.
## Extra height requested after the first visual pass.
## The missionary shot starts at the old maximum forward lean, so W pushes further up her torso
## instead of starting from the wide position. 1.0 is one full `MOTION.LEAN_FORWARD_M` lean.
## Presentation: how close the pony stands in front of the player for standing.
const STANDING_GAP_M := 0.55
## Idle standing invitation: turn away from Anon at this rate before she settles into the stance.
## The game's supported standing turn steps the hooves. Its default 0.45 rad/s half-turn would
## take about 7 s, so the request speeds it up while it owns the turn.
## The locomotion's stepping turn stops at 3°, so settle just beyond that.
## A blocked ground probe can leave the stepping turn standing still; snap instead of waiting.
## The request's face: the act's half-lidded gaze and a full blush while she asks and presents.
## Per-size standing gap. Same Height is the tuned baseline; Hoers stays unchanged.
const STANDING_GAPS := {
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
## One critically damped camera response for surge and bob, seconds.
const CAM_RESPONSE_S := 0.12
## Outward strokes move the camera this fraction of the inward travel.
const CAM_BACK_RATIO := 0.5
## Climax camera amplitudes at full sliders. The sine keeps the same smooth envelope.
const CAM_CLIMAX_BOB_M := 0.008
const CAM_CLIMAX_SURGE_M := 0.02
## Hip phase low-pass on mouse depth. Depth is the input; this only removes single-frame
## mouse steps, it is not a speed attack.
## Standing F kiss: hold F at a full side lean (the shoulder reach) to use the same base kiss.
## Act camera lean. Q/E drive one controlled lean vector: W/S forward/back, Q/E a
## forward-plus-side diagonal. The channel ramps in, then returns slowly when released.
## Backward travel is halved so pulling away cannot open an extreme gap.
## Backing off is half the forward travel so Anon cannot pull too far from her.
## Phase-2 Anon body lean: the pelvis stays planted while the camera/head leans.
## Experiment: Anon's chest/head follow the thrust; the pelvis counter-moves so his upper body
## travels forward on the inward stroke and back on the outward stroke.
## Hold-mode breathing amplitude in lean units, reduced 33% from the first pass
## (forward 0.015, side 0.0125).
## Q/E fire their pose reaction when the smoothed side lean crosses these values.
## Displayed-lean smoothing. Always on.
const CAMERA_INERTIA_SMOOTH := 5.0
## Rump blush from strong thrusts: a fraction of the 0.8 smack decal strength. Always on.
const RUMP_BLUSH_MIN_STRENGTH := 0.55
const RUMP_BLUSH_STEP := 0.0525
const RUMP_BLUSH_MAX := 0.375
const RUMP_BLUSH_DECAY := 0.006
## Canon is small enough that the standing shot needs a lower eye line.
## JRHNBR is tall enough that the standing shot needs a higher eye line.
## Anon's spine length, used to turn the standing torso angle into head/camera travel.
const ANON_TORSO_LEN_M := 0.65
## Standing Anon thrust: mouse depth (only lightly smoothed) moves the hip. This is position, not
## speed; the camera's speed-driven thrust is separate.
## Safety cone for AnonPony's own body-yaw limit; the desktop act camera does not free-look.
## Standing after the climax: Anon eases back before the act restores.
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Standing after the climax: held afterglow; Anon stays put.
## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5
## The Y hint's `End` shade: one step per climax, capped below full so only the earned
## afterglow caress turns it fully pink.
const Y_END_TINT_MAX := 0.75

## Standing keeps her body facing away but lets her glance back over a shoulder now and then.
## Fade time for the extra head-back glance pose; prevents the head snapping back to low.
## Yaw limit for a look-back glance. Raised 20% from 1.35 so she turns farther over her shoulder.
## Jiggle placement on the flank. The thrust scale is reduced 20% from the review pass; the
## native smack keeps its own strength.
const JIGGLE_HEIGHT := 0.78
const JIGGLE_BACK := 0.12
const JIGGLE_RUMP_SCALE := 2.8
## Act kiss timing. The sound repeats softly while her mouth is held to Anon's.
## Anon leans in while kissing. Standing moves the act camera (and the hip counter keeps his
## pelvis planted); missionary moves the framing view and offsets the virtual mouth by the same
## amount, because its player camera is not the rendered shot.
## `AffectionPose`'s lean/tilt sign is opposite the camera lean sign: `+1` rolls her head toward
## Anon's left, while a negative lean moves the camera to his left. Keep the mapping in one place.
## Kissing heads need complementary tilts, so she rolls away from his lean.

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
## Public: how far the tip has passed her lips, in metres. Negative is the `back_out` standoff
## behind them, and the depth stays at zero for all of it.
var penetration_m := 0.0
var thrust_up := true

var _pose
## Bed space of the hand-authored missionary base pose for this act (`null` for other poses).
var _bed_pose_frame: Variant = null
## One settled-pose log line per act.
var _pose_logged := false
## Frames the render-time placement trace has printed this act (two, then it stops).
var _pose_trace_frames := 0
## The authored body bones the live rig lacks, cached per skeleton. The gate polls every frame, so
## the name lookup runs once per rig, not once per poll.
var _pose_rig_checked := false
var _pose_rig_skeleton := 0
var _pose_rig_missing_bones: Array = []
## Free look's own view rotation (the act holds controls_locked, so the stock look is off).
var _free_look_yaw := 0.0
var _free_look_pitch := 0.0
var _free_look_was := false
var _tail
var _tail_lay: Node
## The pony's whole skeleton (body and hair) before the act. The act writes rotations, positions
## and scales; restoring every local pose is what keeps a zeroed/stretched bone from surviving the
## teardown, the same reason Anon gets a bone snapshot.
var _pony_saved_bones: Array[Transform3D] = []
var _pony_saved_hair: Array[Transform3D] = []
var _pony_saved_skeleton: Skeleton3D
var _pony_saved_hair_skeleton: Skeleton3D
var _dock_tail
## integration: persistent anatomy and the current act's anatomy controller.
var _anatomy: Node
var _anatomy_act: Node
var _missionary_anon: Node
var _vr_act: Node
var _used_angles: Array[String] = []
## Idle standing invitation. Kept separate from the act's pose/tail so Y can take over cleanly.
## Idle request face: blush and lids while a private offer is being asked or presented.
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
var _afterglow_pose := ""
var _afterglow_elapsed := 0.0
## One short private afterglow beat, rolled once when afterglow begins. Empty means silence.
var _afterglow_beat := ""
var _afterglow_hold_until := 0.0
var _self_end_clock := 0.0
var _action_executor: Node
var _close_left := 0.0
var _close_caress_seconds := 0.0
var _close_rewarded := false
## True only when the standing close window earned its caress reward.
var _close_caress_earned := false

var _player_pony := false
var _had_kiss_hold := false
var _locked_player := false
var _face_turn_rate_saved := -1.0
var _face_turn_rate_owned := false
## Act-session ownership: each flag marks external state this act took and must give back.
## `_end_session()` checks them, so a start that failed early restores only what it took.
var _camera_owned := false
var _look_captured := false
## Standing leaves Anon facing where the act left him; only missionary snaps the pre-act
## yaw/pitch back.
var _look_restore_yaw := true
var _posture_owned := false
var _session_finalized := false
var _y_hold := 0.0
var _y_hold_ready := false
var _y_hold_fired := false
var _nav: Node
## Wander flag found when the act claimed the navigator. Other systems can hold it off, so the
## act gives back what it found instead of forcing it on.
var _nav_old_wander := true
var _token := ""
var _id := ""
## Debug-only estrus phase override. Empty means derive the phase from the world day and her id.
var _cycle_override := ""
var _profile: Dictionary = {}
var _features: Dictionary = {}
var _pose_cfg: Dictionary = {}
var _preferences: Dictionary = {}
var _act_prompts: Dictionary = {}
var _thrust_tracker
## Auto thrust uses the one tracker: the generated depth only replaces the mouse movement.
var _auto_thrust
var _auto_panel
var _auto_on := false
var _auto_default_pace := 1.0
var _auto_default_depth := 0.5
var _auto_default_min := 0.0
var _auto_default_shape := "cosine"
var _thrust_pixels_per_cm := 100.0
var _thrust_travel := 1.0
var _max_pony_climaxes := 3
var _jiggle_radius_m := 0.26
var _jiggle_center_height_m := 0.1
var _jiggle_center_back_m := 0.15
var _jiggle_intensity_scale := 0.2
var _jiggle_smack_intensity := 0.55
var _jiggle_radius_materials: Array = []
var _camera_surge := 0.0
var _camera_bob := 0.0
## Last closed inward thrust; the pattern window is the last three to four thrusts.
var _last_stroke: Dictionary = {}
var _last_intensity := ""
var _last_pattern := ""
var _stroke_window: Array[Dictionary] = []
var _last_stroke_at := -1000.0
var _utterance_serial := 0
## One `utterance delivered` log per line: the pending key stays until speech stops and the release
## hold passes, so the delivered state is seen every frame.
var _utterance_delivered_key := ""
var _lines
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
var _last_cue_log_text := ""
var _last_cue_log_reason := ""
var _cue_gap := 12.0
var _cue_override_seconds := 10.0
var _cue_base_stable_s := 2.0
var _cue_override_stable_s := 0.5
var _cue_utterance_gap_s := 18.0
var _cue_demand_gap_s := 28.0
var _cue_demand_repeat_s := 45.0
var _cue_max_age_s := 20.0
var _cue_reaction_max_age_s := 30.0
var _cue_release_hold_s := 1.0
var _cue_overwhelmed_s := 1.2
var _touch_cooldown_s := 4.0
var _talk_cooldown_s := 8.0
var _receptive_seconds := 8.0
var _used_memory_ids: Array[String] = []
var _act_spoken_at := -1e9
var _peak_satisfaction := 0.0
var _act_both_matches := 0
var _act_dislikes := 0
var _act_liked_touch := 0
var _act_liked_talk := 0
var _last_player_talk := ""
var _act_touch_counts := {}
var _act_touch_dislikes := {}
var _act_talk_dislikes := 0
var _act_player_lines := 0
var _act_thrusts := 0
var _act_intensity_total := 0
var _act_intensity_right := 0
var _act_pattern_total := 0
var _act_pattern_right := 0
var _act_ended_early := false
var _summary: Dictionary = {}
var _summary_done := false
var _stopped_by_her := false
var _tolerance
var _tolerance_warning_key := ""
var _debug_forced_tolerance := ""
var _tail_tuck: Node
var _history_refusal_at := -1000.0
var _history_reminder_at := -1000.0
var _history_scan_clock := 0.0
var _history_turn := -1
var _peak_recorded := false
var _aftercare_min := 10
var _display_name := "the pony"
var _serial := 0
var _event_id := ""
var _started_at := 0.0

var _camera: Camera3D
var _free_camera_active := false
var _camera_basis_ready := false
var _restore_yaw := 0.0
var _restore_pitch := 0.0
var _controls_locked_saved := false
var _controls_locked_by_camera := false
var _chin_modifier: SkeletonModifier3D
var _body_sway: SkeletonModifier3D
var _prone_sway: SkeletonModifier3D
var _ear_twitch: SkeletonModifier3D
## World-space hip sway published by `body_sway.gd`; the standing Anon controller adds it to its
## pinned hip so the two bodies rock together.
var _standing_sway_offset := Vector3.ZERO
var _lean_forward := 0.0
var _lean_side := 0.0
var _lean_view_forward := 0.0
var _lean_view_side := 0.0
## Idle breathing, added on top of the displayed lean by the shot (never folded into it).
var _lean_sway := 0.0
## One-shot per act: the lean input was blocked, and why.
var _lean_block_logged := false
var _side_return_armed := false
var _hold_rock_clock := 0.0
var _lean_action_active := false
var _lean_action_side := 0.0
var _lean_action_kind := ""
var _forced_glance := ""
var _presentation_cfg: Dictionary = {}
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
var _bob := 0.0
var _bob_velocity := 0.0
var _lean := 0.0
var _lean_velocity := 0.0
var _back := 0.0
var _back_target := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _eye_override := false
var _saved_stand_eye := 0.0
var _saved_eye_height := 0.0
var _camera_target_eye := 0.0
var _wings
var _act_seconds := 0.0
## Processed-time clock. It only advances while the runtime ticks, so a paused tree freezes
## act timing and stroke memory instead of aging them by the pause length.
var _clock_s := 0.0
var _aftercare: Node
var _satisfied: Node
var _upset: Node
var _satisfaction_tween: Tween
## The act's base kiss normally rears and lifts both forelegs; zeroing those two shared
## settings keeps her forehooves planted for the kiss and restores them when it ends.
## The act's stare is released once when a kiss starts so the regular kiss can drive the eyes.
var _act_eyes_released := false
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
var _sounds
var _caress
var _kiss
var _missionary_camera_ctl
var _standing_camera_ctl
var _standing_anon_ctl
var _standing_presentation_ctl
var _flank: Node
var _jiggle_logged := false
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
	# integration: anatomy is persistent outside acts and attaches only to the modern preference roster.
	_anatomy_refresh()


## integration: create or drop the persistent anatomy controller. Called at ready and on every
## settings edit, including while idle.
func _anatomy_refresh() -> void:
	if not is_instance_valid(pony):
		return
	if not SETTINGS.anatomy_on():
		if is_instance_valid(_anatomy):
			_anatomy.call("detach")
			_anatomy.queue_free()
		_anatomy = null
		return
	if not ANATOMY.eligible(pony) or not ANATOMY.assets_exist():
		if is_instance_valid(_anatomy):
			_anatomy.call("detach")
			_anatomy.queue_free()
		_anatomy = null
		return
	if not is_instance_valid(_anatomy):
		_anatomy = ANATOMY.new()
		_anatomy.name = "UnfplapAnatomyController"
		add_child(_anatomy)
		_anatomy.call("setup", pony, self)
	_anatomy.call("refresh")


func anatomy_available() -> bool:
	return is_instance_valid(_anatomy)


func _anatomy_act_refresh(pose_id: String) -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("teardown")
		_anatomy_act.queue_free()
		_anatomy_act = null
	if not is_instance_valid(_anatomy):
		return
	_anatomy_act = ANATOMY_ACT.new()
	_anatomy_act.name = "UnfplapAnatomyAct"
	add_child(_anatomy_act)
	_anatomy_act.call("setup", self, _anatomy, pose_id)

func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


## Debug perf probe. Timed chunks report microseconds here; `_perf_tick()` prints one summary a
## second so a pony-specific stall can be attributed to a modifier without a live profiler.
var _perf: Dictionary = {}
var _perf_clock := 0.0
var _perf_frames := 0


func _perf_on() -> bool:
	return is_instance_valid(main) and bool(main.get("debug_logs")) \
		and bool(main.get("debug_perf"))


## Called by every timed chunk (runtime, skeleton modifiers, HUD). Cheap no-op with logs off.
func perf_note(key: String, usec: int) -> void:
	if not _perf_on():
		return
	var row: Array = _perf.get(key, [0, 0, 0])
	row[0] = int(row[0]) + 1
	row[1] = int(row[1]) + usec
	row[2] = maxi(int(row[2]), usec)
	_perf[key] = row


## Time one call site for the perf probe (callers take the start stamp themselves).
func _timed(key: String, started: int) -> void:
	if _perf_on():
		perf_note(key, Time.get_ticks_usec() - started)


func _perf_tick(delta: float) -> void:
	if not _perf_on() or state == State.IDLE:
		_perf_clock = 0.0
		_perf_frames = 0
		_perf.clear()
		return
	_perf_frames += 1
	_perf_clock += delta
	if _perf_clock < PERF_WINDOW_S:
		return
	var frames := maxi(1, _perf_frames)
	_perf_clock = 0.0
	_perf_frames = 0
	var rows: Array = []
	for key: String in _perf:
		var row: Array = _perf[key]
		rows.append([key, int(row[0]), float(row[1]) / 1000.0, int(row[2])])
	_perf.clear()
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	var near_mesh := "?"
	var tier := "?"
	if is_instance_valid(pony):
		var value: Variant = pony.get("near_mesh_enabled")
		near_mesh = str(value) if value != null else "?"
		value = pony.get("sim_tier")
		tier = str(value) if value != null else "?"
	var wings: Variant = _wings_controller()
	var wing_state := "no"
	if wings != null:
		if bool(wings.get("_wing_hold")):
			wing_state = "held"
		elif bool(wings.get("_winged")):
			wing_state = "winged"
	var dock := "no"
	if is_instance_valid(_dock_tail):
		dock = "on" if bool(_dock_tail.get("_active")) else "off"
	var text := "perf pony=%s pose=%s state=%d fps=%d frame=%.1fms near_mesh=%s tier=%s wings=%s dock=%s" % [
		_id, pose_id, state, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		near_mesh, tier, wing_state, dock]
	for row: Array in rows:
		text += "\n\t%-16s %7.2fms/s per-frame %6.3fms max %6.2fms calls %d" % [
			str(row[0]), float(row[2]), float(row[2]) / frames, float(row[3]) / 1000.0, int(row[1])]
	_log(text)


## Lazily create the wing controller. Tests instantiate the runtime without entering the tree.
func _wings_controller():
	if _wings == null:
		_wings = WING.new(self)
	return _wings

## Lazily create the base-game act sound controller, including outside the tree in tests.
func _sounds_controller():
	if _sounds == null:
		_sounds = SOUND.new(self)
		_sounds.name = "UnfplapActSound"
		add_child(_sounds)
	return _sounds

## Lazily create the standing caress controller, including outside the tree in tests.
func _caress_controller():
	if _caress == null:
		_caress = CAESS.new(self)
	return _caress

## Lazily create the kiss controller, including outside the tree in tests.
func _kiss_controller():
	if _kiss == null:
		_kiss = KISS.new(self)
	return _kiss

## Lazily create the missionary camera controller, including outside the tree in tests.
func _missionary_camera_controller():
	if _missionary_camera_ctl == null:
		_missionary_camera_ctl = MISSIONARY_CAMERA.new(self)
	return _missionary_camera_ctl

## Lazily create the standing camera controller, including outside the tree in tests.
func _standing_camera_controller():
	if _standing_camera_ctl == null:
		_standing_camera_ctl = STANDING_CAMERA.new(self)
	return _standing_camera_ctl

## Lazily create the standing Anon body controller, including outside the tree in tests.
func _standing_anon_controller():
	if _standing_anon_ctl == null:
		_standing_anon_ctl = STANDING_ANON.new(self)
	return _standing_anon_ctl

## Lazily create the idle standing presentation controller.
func _standing_presentation_controller():
	if _standing_presentation_ctl == null:
		_standing_presentation_ctl = STANDING_PRESENTATION.new(self)
	return _standing_presentation_ctl

## Feature flag from the act snapshot. Unknown flags read as off.
func _feature(name: String) -> bool:
	return bool(_features.get(name, false))


## Unprompted act lines (cues and reactions). Missing from an empty test snapshot means on.
func _act_lines_enabled() -> bool:
	return bool(_features.get("act_lines", true))


func _utterance_scheduler():
	if _lines == null:
		_lines = UTTERANCE_SCHEDULER.new()
	return _lines


## Push the debug talk/cue pacing settings into the pure scheduler. `reset()` keeps these
## fields, so `_reset_thrust_state()` only has to reset the act's timing state.
func _configure_utterance_scheduler() -> void:
	var lines = _utterance_scheduler()
	lines.base_stable_s = _cue_base_stable_s
	lines.override_stable_s = _cue_override_stable_s
	lines.utterance_gap_s = _cue_utterance_gap_s
	lines.demand_gap_s = _cue_demand_gap_s
	lines.demand_repeat_s = _cue_demand_repeat_s
	lines.max_age_s = _cue_max_age_s
	lines.release_hold_s = _cue_release_hold_s


## Snapshot every tunable the act reads per stroke or per frame. `apply_live_settings()` re-runs
## it so a settings edit applies without a new act.
func _snapshot_settings() -> void:
	_features = SETTINGS.block("features.")
	var thrust_block := SETTINGS.block("thrust.")
	thrust_up = str(thrust_block.get("orientation", "up")).to_lower() == "up"
	_thrust_pixels_per_cm = float(thrust_block.get("pixels_per_cm", 100.0))
	_thrust_travel = float(thrust_block.get("travel", 0.5))
	_max_pony_climaxes = int(thrust_block.get("max_pony_climaxes", 3))
	var auto_block := SETTINGS.block("auto_thrust.")
	_auto_default_pace = float(auto_block.get("pace", 1.0))
	_auto_default_depth = float(auto_block.get("max_depth", 0.5))
	_auto_default_min = float(auto_block.get("min_depth", 0.0))
	var shape_setting := str(auto_block.get("curve", "cosine"))
	_auto_default_shape = shape_setting if AUTO_THRUST.SHAPES.has(shape_setting) else "cosine"
	var jiggle_block := SETTINGS.block("jiggle.")
	_jiggle_radius_m = float(jiggle_block.get("radius", 0.26))
	_jiggle_center_height_m = float(jiggle_block.get("center_height_m", 0.1))
	_jiggle_center_back_m = float(jiggle_block.get("center_back_m", 0.15))
	_jiggle_intensity_scale = float(jiggle_block.get("intensity", 0.2))
	_jiggle_smack_intensity = float(jiggle_block.get("smack_intensity", 0.55))
	var camera_block := SETTINGS.block("camera_thrust.")
	_camera_surge = float(camera_block.get("surge", 1.0))
	_camera_bob = float(camera_block.get("bob", 0.35))
	var cue_block := SETTINGS.block("cues.")
	_cue_override_seconds = float(cue_block.get("override_seconds", 10.0))
	_cue_base_stable_s = float(cue_block.get("base_stable_seconds", 2.0))
	_cue_override_stable_s = float(cue_block.get("override_stable_seconds", 0.5))
	_cue_utterance_gap_s = float(cue_block.get("utterance_gap_seconds", 18.0))
	_cue_demand_gap_s = float(cue_block.get("demand_gap_seconds", 28.0))
	_cue_demand_repeat_s = float(cue_block.get("demand_repeat_seconds", 45.0))
	_cue_max_age_s = float(cue_block.get("max_age_seconds", 20.0))
	_cue_reaction_max_age_s = float(cue_block.get("reaction_max_age_seconds", 30.0))
	_cue_release_hold_s = float(cue_block.get("release_hold_seconds", 1.0))
	_cue_overwhelmed_s = float(cue_block.get("overwhelmed_seconds", 1.2))
	var talk_block := SETTINGS.block("talk.")
	_touch_cooldown_s = float(talk_block.get("touch_cooldown_seconds", 4.0))
	_talk_cooldown_s = float(talk_block.get("talk_cooldown_seconds", 8.0))
	_receptive_seconds = float(talk_block.get("receptive_seconds", 8.0))
	_presentation_cfg = SETTINGS.block("presentation." + pose_id + ".")
	_configure_utterance_scheduler()

## Re-read the settings tab's live-editable values during an act. Feature installs/removals are
## idempotent so repeated edits do not stack modifiers.
func apply_live_settings() -> void:
	# Snapshot before the IDLE early return too, so mouse sensitivity and the other act tunables
	# apply as soon as they are edited rather than only at the next act start.
	_snapshot_settings()
	if state == State.IDLE:
		# integration: the anatomy feature is live outside acts too.
		_anatomy_refresh()
		return
	var previous_mute := bool(_features.get("mute_ponese_audio", false))
	var previous_lines := _act_lines_enabled()
	_anatomy_refresh()
	if previous_lines and not _act_lines_enabled() and is_instance_valid(main) and is_instance_valid(main.game):
		_end_act_lines(true)
	var vocals := _feature("act_vocals")
	var climax := _feature("act_climax")
	_ensure_act_audio(vocals, climax)
	if is_instance_valid(_flank):
		_apply_jiggle_radius()
	if _auto_thrust != null:
		_auto_thrust.call("set_shape", _auto_default_shape)
	if pose_id == CATALOG.STANDING:
		_kiss_controller().apply_live_settings()
		_sync_standing_pose_config()
	elif pose_id == CATALOG.MISSIONARY:
		_sync_missionary_pose_config()
	# Nudge the frozen missionary anchor only when the framing control actually changed, so a preference
	# edit does not snap the shot. Move by the delta instead of recomputing from the pony: she
	# has settled since the start anchor was taken and the bed reference may be gone.
	if not _id.is_empty():
		_preferences = SETTINGS.preferences(_id)
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
	if pose_id == CATALOG.STANDING:
		if _feature("standing_body_sway") and not is_instance_valid(_body_sway):
			_install_body_sway(skeleton)
		elif not _feature("standing_body_sway") and is_instance_valid(_body_sway):
			_body_sway.queue_free()
			_body_sway = null
		if _feature("thrust_ear_twitch") and not is_instance_valid(_ear_twitch):
			_install_ear_twitch()
		elif not _feature("thrust_ear_twitch") and is_instance_valid(_ear_twitch):
			_ear_twitch.queue_free()
			_ear_twitch = null
		_standing_anon_controller().refresh_palm()
	elif pose_id == CATALOG.MISSIONARY:
		if _feature("missionary_body_motion") and not is_instance_valid(_prone_sway):
			_install_prone_sway(skeleton)
		elif not _feature("missionary_body_motion") and is_instance_valid(_prone_sway):
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

## Optional act control card, separate from the pony state readouts.
func hud_controls() -> bool:
	return bool(_features.get("act_controls", true))

## One compact HUD line: hearts, cue, then her preference versus yours. The close prompt is
## always kept in afterglow even when the optional readouts are off.
func hud_cue_line(show_readouts := true) -> String:
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return ""
	var hearts := "❤ %d/∞" % pony_climaxes if _max_pony_climaxes <= 0 \
		else "❤ %d/%d" % [pony_climaxes, _max_pony_climaxes]
	var parts: PackedStringArray = [hearts]
	var cue_text := cue.strip_edges()
	var closing := state == State.AFTERGLOW
	if closing:
		var close_text := close_hint()
		if not close_text.is_empty():
			cue_text = close_text
		elif not _summary.is_empty():
			cue_text = str(_summary.get("hud", ""))
	if show_readouts or closing:
		parts.append(cue_text if not cue_text.is_empty() else "—")
	return " | ".join(parts)

## Separate readiness/preference line under the cue. In the afterglow it carries the act summary when
## the cue already shows the standing close prompt. Empty elsewhere when readouts are off.
func hud_readiness_line(show_readouts := true) -> String:
	if state == State.AFTERGLOW:
		if _summary.is_empty() or close_hint().is_empty():
			return ""
		return str(_summary.get("hud", ""))
	if not show_readouts or state not in [State.ACTIVE, State.CLIMAX]:
		return ""
	var have_intensity := _last_intensity if not _last_intensity.is_empty() else "—"
	var have_pattern := _last_pattern if not _last_pattern.is_empty() else "—"
	var want_intensity := str(_preferences.get("intensity", "firm"))
	var want_pattern := str(_preferences.get("pattern", "steady"))
	var line := "Wants: %s & %s | You: %s & %s" % [
		want_intensity, want_pattern, have_intensity, have_pattern]
	return line + " | In heat" if cycle_phase() == CYCLE.HEAT else line

## True while the automatic stroke owns the depth. X only switches it in ACTIVE/CLIMAX.
func auto_active() -> bool:
	return _auto_on and state in [State.ACTIVE, State.CLIMAX]

## Pink shade for the control card's `End`: one step per climax, capped below full so only the
## earned standing afterglow caress turns it fully pink.
func hud_y_pink() -> float:
	if pose_id == CATALOG.STANDING and state == State.AFTERGLOW and _close_caress_earned:
		return 1.0
	var reference := float(_max_pony_climaxes) if _max_pony_climaxes > 0 else 3.0
	return clampf(float(pony_climaxes) / reference, 0.0, 1.0) * Y_END_TINT_MAX

## HUD control readout under the Wants/You line. Empty while manual.
func auto_hud_text() -> String:
	if not auto_active():
		return ""
	var auto = _auto_controller()
	return "Auto · %d–%d%% · %.2f/s · %s" % [
		roundi(float(auto.get("min_depth")) * 100.0),
		roundi(float(auto.get("max_depth")) * 100.0),
		float(auto.get("pace")), auto_shape_name()]

## Strong blush for the whole act; pegasi/alicorns spread their wings and occasionally flutter.
func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act_seconds += delta
	if pose_id == CATALOG.MISSIONARY:
		_missionary_camera_controller().hide_avatar()
		_aim_missionary_eyes()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", 1.0)
	# The optional debug pin reuses the boop-fluster response: it pins the ears back along the
	# skull. Off keeps normal ears; the blush and stare() eyelids are independent.
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster") and _feature("act_ear_pin"):
		expressions.call("fluster", 1.2)
	var wings_started := Time.get_ticks_usec()
	_wings_controller().tick(delta, pose_id, satisfaction, _act_seconds)
	_timed("wings_tick", wings_started)

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
	var started := Time.get_ticks_usec()
	_process_tick(delta)
	if _perf_on():
		perf_note("runtime_process", Time.get_ticks_usec() - started)
		_perf_tick(delta)


func _process_tick(delta: float) -> void:
	if state == State.IDLE:
		_standing_presentation_controller().process()
		return
	_pose_render_write()
	_pose_idle_sample()
	_standing_camera_controller().clamp_look()
	if is_instance_valid(_pose) and is_instance_valid(main):
		var view: Camera3D = main.camera()
		if pose_id == CATALOG.MISSIONARY and is_instance_valid(_missionary_camera_controller().view()):
			view = _missionary_camera_controller().view()
		var kiss: Variant = _kiss_controller()
		var custom_kiss: bool = kiss.custom_visible()
		var kiss_view: Camera3D = kiss.mouth_view()
		if is_instance_valid(view):
			if custom_kiss and is_instance_valid(kiss_view):
				if pose_id == CATALOG.MISSIONARY:
					# Best-effort lean: blend from his eyes to his mouth with the kiss's own 0.35 s
					# fade, so the head leans in with the kiss instead of snapping to the mouth on
					# the first frame. The pose solve still aims at the moving point every frame.
					var mouth: Variant = kiss.target(kiss_view)
					var gaze := _missionary_gaze_point()
					if mouth is Vector3 and (mouth as Vector3).is_finite() and gaze.is_finite():
						_pose.look_point = gaze.lerp(mouth, clampf(float(kiss.amount()), 0.0, 1.0))
					else:
						_pose.look_point = gaze
				else:
					_pose.look_point = kiss.target(kiss_view)
			elif pose_id == CATALOG.MISSIONARY:
				# Look at the authored Anon, not at the game camera: his body is placed by the act,
				# and the player rig the camera belongs to is standing off the bed.
				_pose.look_point = _missionary_gaze_point()
			else:
				_pose.look_point = view.global_position
		_pose.kiss = kiss.amount() if custom_kiss else 0.0
		_pose.climaxing = state == State.CLIMAX
	var surge_target := 0.0
	var bob_target := 0.0
	if state == State.ACTIVE:
		var norm := clampf(_standing_camera_controller().speed() / CAM_SPEED_REF, -1.0, 1.0)
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
## Auto thrust owns the stroke, so the mouse does nothing there: depth is set from the hold-X layer.
func _input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	# Debug free look: the mouse looks around instead of driving depth. The act owns
	# `controls_locked`, so the stock player look is dead and this has to drive it.
	if free_look_active():
		var sensitivity := _mouse_sensitivity()
		_free_look_yaw = wrapf(_free_look_yaw - motion.relative.x * sensitivity, -PI, PI)
		var sign := -1.0 if _invert_y() else 1.0
		_free_look_pitch = clampf(_free_look_pitch - motion.relative.y * sensitivity * sign,
			-1.5, 1.5)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if state in [State.ACTIVE, State.CLIMAX]:
		if not _auto_on and _thrust_tracker != null:
			var travel: float = THRUST.pixels_to_metres(motion.relative.y, _thrust_pixels_per_cm,
				thrust_up)
			_set_penetration(penetration_m + travel, _now_s())
		get_viewport().set_input_as_handled()

func _mouse_sensitivity() -> float:
	var body: Variant = main.player if is_instance_valid(main) else null
	var value: Variant = body.get("mouse_sensitivity") if body != null else null
	return float(value) if value != null else 0.0022


func _invert_y() -> bool:
	var body: Variant = main.player if is_instance_valid(main) else null
	var value: Variant = body.get("invert_y") if body != null else null
	return bool(value) if value != null else false


func _headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) and bool(main.game.get("headset_view"))

## Y is a deliberate hold, matching the game's 0.35 s bridal-carry hold. A tap does nothing,
## and the trigger latches until release so a held key cannot fire twice.
func _hold_y_tick(delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_y_hold = 0.0
		_y_hold_fired = false
		return
	var held := Input.is_physical_key_pressed(KEY_Y) \
		or (is_instance_valid(_vr_act) and bool(_vr_act.get("y_held")))
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
	var started := Time.get_ticks_usec()
	_physics_tick(delta)
	if _perf_on():
		perf_note("runtime_physics", Time.get_ticks_usec() - started)


func _physics_tick(delta: float) -> void:
	_clock_s += maxf(0.0, delta)
	if state == State.IDLE:
		# Last-resort safety: a missed exit path must not leave the quick slots hidden.
		if _inventory_hud_hidden:
			_set_inventory_hud_hidden(false)
		_standing_presentation_controller().physics(delta)
		_history_tick(delta)
		return
	if not is_instance_valid(pony) or not is_instance_valid(main):
		force_stop()
		return
	if pony.sleeping:
		pony.sleeping = false
	_vocal_cooldown = maxf(0.0, _vocal_cooldown - delta)
	_keep_nav()
	if free_look_active() != _free_look_was:
		_free_look_was = free_look_active()
		_free_look_yaw = 0.0
		_free_look_pitch = 0.0
		_log("free look %s" % ("on" if _free_look_was else "off"))
	_keep_act_attention()
	_pause_face_turn()
	_hold_y_tick(delta)
	_auto_panel_tick(delta)
	_lean_tick(delta)
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_act_presentation(delta)
	if state in [State.POSING_IN, State.ACTIVE]:
		_tolerance_tick(delta)
	_log_pose_settled()
	var kiss_started := Time.get_ticks_usec()
	_kiss_controller().tick(delta)
	_timed("kiss_tick", kiss_started)
	if state in [State.ACTIVE, State.CLIMAX]:
		_auto_thrust_tick(delta)
		_thrust_tick()
		if is_instance_valid(_anatomy_act):
			_anatomy_act.call("tick", delta)
		if state == State.ACTIVE:
			_readiness_tick(delta)
			_talk_tick(delta)
			_bystander_tick(delta)
	if state in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.RESTORE]:
		_utterance_tick()
	if state == State.POSING_IN:
		_pose_in_left -= delta
		if _pose_in_left <= 0.0:
			state = State.ACTIVE
			# The start snapshot caught Anon mid stand-up, so his eye height was the reclined one; the
			# scene is settled now, and restoring to this is what puts the camera back correctly.
			if pose_id == CATALOG.MISSIONARY:
				_missionary_camera_controller().resnapshot()
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
	_standing_camera_controller().lock_facing()
	_standing_camera_controller().drive_glance(delta)
	_suppress_auto_cuddle()
	_standing_camera_controller().clamp_look()
	_standing_camera_controller().tick_depth(delta)
	_standing_anon_controller().tick_phase(delta)
	_rump_blush_tick(delta)
	apply_camera_motion()
	if state in [State.POSING_IN, State.ACTIVE, State.AFTERGLOW]:
		_check_clock += delta
		if _check_clock >= 0.25:
			_check_clock = 0.0
			_check_running()
	_eyes_tick()

## The act owns the lids outside a kiss. Set at every transition, then reasserted late so a
## climax return or fluster peek cannot leave her wide-eyed while leaning.
func _eyes_tick() -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if _kiss_controller().eyes_active():
		if not _act_eyes_released:
			if expressions.has_method("stare"):
				expressions.call("stare", false)
			_act_eyes_released = true
		return
	_act_eyes_released = false
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
	if expressions.has_method("stare"):
		expressions.call("stare", true, lids)

# --------------------------------------------------------------------------- gates

func can_start(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return _report_ok(_gate_report(pose, act_source, bed_in, "start"))


## Offer eligibility before she is in position. Unlike can_start(), this does not require the
## pony to be lying or the player to be ready; those stay in the final Y gate. `forced` is the
## Debug -> Actions bypass: the settings page pauses the tree, and the episode advances after it
## closes, so the paused row must not reject a forced offer.
func can_offer(pose: String, act_source: String, bed_in: Variant = null, forced := false) -> bool:
	return _report_ok(_gate_report(pose, act_source, bed_in, "offer", forced))


## The failed offer gates, for the debug request buttons and their logs.
func offer_reasons(pose: String, act_source: String, bed_in: Variant = null,
		forced := false) -> PackedStringArray:
	return _report_reasons(_gate_report(pose, act_source, bed_in, "offer", forced))


func _start_reasons(pose: String, act_source: String, bed_in: Variant = null) -> PackedStringArray:
	return _report_reasons(_gate_report(pose, act_source, bed_in, "start"))


## Ordered gate report shared by the start and offer paths. Start adds player readiness,
## navigator reservation and the full bed gate; offer keeps only the offer-safe subset.
func _gate_report(pose: String, act_source: String, bed_in: Variant, mode: String,
		forced := false) -> Array:
	var rows: Array = []
	_gate_row(rows, "invalid_pony", is_instance_valid(pony), "invalid_pony")
	if not is_instance_valid(pony):
		return rows
	_gate_row(rows, "no_main", is_instance_valid(main), "no_main")
	if not is_instance_valid(main):
		return rows
	_gate_row(rows, "no_player", is_instance_valid(main.player), "no_player")
	if not is_instance_valid(main.player):
		return rows
	_gate_row(rows, "no_game", is_instance_valid(main.game), "no_game")
	if not is_instance_valid(main.game):
		return rows
	_gate_row(rows, "state", state == State.IDLE, "state=%d" % state)
	_gate_row(rows, "cycle", CYCLE.allows_sex(cycle_phase()), "diestrus")
	# Try Your Luck lets the attempt reach the refusal path before she welcomes the kiss.
	# Her proactive offers still require willingness (mode == "offer").
	if mode == "offer" or not _try_luck():
		_gate_row(rows, "relation", _relationship_ok(), "relation")
	_gate_row(rows, "sex_bond", _sex_bond_ok(), "sex_bond")
	_gate_row(rows, "form", _player_form_ok(), "form")
	var tree := get_tree()
	_gate_row(rows, "paused", forced or tree == null or not tree.paused, "paused")
	_gate_row(rows, "conversation", _conversation_ok(), "conversation")
	_gate_row(rows, "sleeping", not pony.sleeping, "sleeping")
	_gate_row(rows, "sex_active", not bool(pony.get_meta("sex_active", false)), "sex_active")
	_gate_row(rows, "aftercare", not pony.has_meta("sex_aftercare"), "aftercare")
	_gate_row(rows, "cuddle",
		not _cuddle_active() or _cuddle_start_override(pose, act_source), "cuddle")
	_gate_row(rows, "affection", _free_of_affection(), "affection")
	if mode == "start":
		_gate_row(rows, "player", _player_ready_for(pose, act_source, bed_in), "player")
	var nav: Node = pony.get_node_or_null("Navigator")
	if mode == "start":
		_gate_row(rows, "navigator", nav != null, "no_navigator")
		if nav != null:
			_gate_row(rows, "navigator_reserved",
				str(nav.get("reserved_by")) == "", "navigator_reserved")
			_gate_row(rows, "nav_owner", _nav_owner_allows(pose, act_source), "nav_owner")
		_gate_row(rows, "nav_pose", _nav_pose_gate(pose, act_source), "nav_pose")
	else:
		_gate_row(rows, "nav_owner",
			nav != null and _nav_owner_allows(pose, act_source), "nav_owner")
	if pose == CATALOG.MISSIONARY:
		var pose_ready := _authored_pose_ready()
		_gate_row(rows, "pose_asset", pose_ready, _authored_pose_reason())
		if pose_ready:
			var missing := _pose_rig_missing()
			_gate_row(rows, "pose_rig", missing.is_empty(), _pose_rig_reason(missing))
		var found: Node3D = _resolve_bed(pose, act_source, bed_in)
		_gate_row(rows, "bed", found != null, "no_bed")
		if found != null:
			_gate_row(rows, "bed_occupied", not main.bed_occupied(found, pony), "bed_occupied")
			if mode == "start":
				_gate_row(rows, "bed_gate", _bed_gate(pose, act_source, found), "bed_gate")
	elif mode == "offer":
		if pose == CATALOG.STANDING:
			_gate_row(rows, "standing_free",
				not pony.is_held() and not pony.has_meta("seated"), "standing_free")
		else:
			_gate_row(rows, "pose", false, "pose")
	return rows


func _gate_row(rows: Array, key: String, ok: bool, reason := "") -> void:
	rows.append({"key": key, "ok": ok, "reason": reason if not reason.is_empty() else key})


func _report_ok(rows: Array) -> bool:
	for row: Dictionary in rows:
		if not bool(row.get("ok", false)):
			return false
	return true


func _report_reasons(rows: Array) -> PackedStringArray:
	var reasons: PackedStringArray = []
	for row: Dictionary in rows:
		if not bool(row.get("ok", false)):
			reasons.append(str(row.get("reason", "")))
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
	var sex_bond := _sex_bond_ok()
	var sex_start := SETTINGS.sex_start.get_choice()
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
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level=%d) welcomes=%s bond=%s start=%s mood=%s | state=%d presenting=%s sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		display, id, float(distance), float(dot), stage, love_name, love_level, str(welcomes), str(sex_bond), sex_start, mood,
		state, str(_standing_presentation_controller().presentation_active()), str(pony.get("sleeping")), str(pony.is_held()), str(pony.grounded()), str(pony.has_meta("seated")),
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
		var limit_text := "∞" if _max_pony_climaxes <= 0 else str(_max_pony_climaxes)
		text += " | readiness=%.0f mood=%s climaxes=%d/%s intensity=%s pattern=%s cue=%s up=%s penetration=%.1f/%.1fcm | %s" % [
			satisfaction, mood, pony_climaxes, limit_text,
			_last_intensity, _last_pattern, cue, str(thrust_up),
			penetration_m * 100.0, penetration_reach() * 100.0,
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
	if body.get("controls_locked") == true or body.get("flying") == true:
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	if DisplayServer.get_name() != "headless" and not _headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection == null or not affection.has_method("buck"):
		return false
	if pose == CATALOG.STANDING:
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
	if pose == CATALOG.STANDING:
		_note_refusal(_buck_or_push())
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
		_note_refusal(_buck_or_push())
		return
	if act_source == "already_lying":
		if not REST.release_managed(pony):
			return
		pony.request_posture("stand")
		await get_tree().physics_frame
		_note_refusal(_buck_or_push())

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

func _buck_or_push() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and affection.has_method("buck"):
		if bool(affection.call("buck", main.player_body())):
			return true
	var body = main.player
	if not is_instance_valid(body):
		return false
	var knockdown: Variant = body.get("knockdown")
	if knockdown == null or not knockdown.has_method("start"):
		return false
	var direction: Vector3 = pony.global_position - body.global_position
	direction.y = 0.25
	if direction.length_squared() < 0.0001:
		direction = -body.global_basis.z
	knockdown.call("start", body, direction.normalized() * 3.0)
	return true


## A refusal is a real mood beat, not just a buck animation. The game's lasting feeling is the
## impression note, which drives `bonds.welcomes()`, anger, offers, approaches and her dialogue;
## the held face displays it (upset.gd). A buck is the stronger moment, so it is the stronger mood.
func _note_refusal(bucked: bool) -> void:
	if is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.refusal_event(main.game, _id, _display_name,
			"unfplap_refusal_%s_%d" % [_id, Time.get_ticks_usec()], bucked)
	_refuse_trust()
	_start_upset("angry" if bucked else "annoyed")


## The game's own unwelcome-contact hook: a little trust lost and the boundary signal. It never
## sets a mood itself, so `refusal_event` owns the impression.
func _refuse_trust() -> void:
	if not is_instance_valid(pony):
		return
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel):
		return
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("unwanted_contact"):
		bonds.call("unwanted_contact", _id, "kiss")


func _read_id() -> bool:
	if not is_instance_valid(pony):
		return false
	if not _id.is_empty():
		return true
	_id = str(pony.get_meta("relationship_id", ""))
	if _id.is_empty():
		var identity_id: Variant = pony.get("identity")
		if identity_id != null:
			_id = str(identity_id.get("id"))
	return not _id.is_empty()

func _stage_ok() -> bool:
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return false
	if not _read_id():
		return false
	var identity: Variant = pony.get("identity")
	if identity == null or bool(identity.get("filly")):
		return false
	if not bool(runtime.bonds.adults.get(_id, false)):
		return false
	var ladder: Dictionary = runtime.ladder(_id)
	var love: Dictionary = ladder.get("love", {})
	if not SEX_BOND.level_ok(SETTINGS.promiscuity.get_choice(),
			int(love.get("level", -1))):
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

## Starting Sex: Try Your Luck lets Anon attempt before she welcomes the kiss. The actual start
## still checks _relationship_ok() and refuses when it is false.
func _try_luck() -> bool:
	return SETTINGS.sex_start.get_choice() == "try_luck"

## The stored bond, without the Starting Sex bypass. Promiscuity and the base kiss willingness
## are separate gates, so a bond made at Crush or Any Adult is valid outside a dating stage.
func _stored_sex_bond() -> bool:
	return SEX_BOND.bonded(SEX_BOND.section(), _id)

## Gate row: the mod lover bond, or true when Starting Sex is Try Your Luck. The base kiss
## willingness remains the separate relation row.
func _sex_bond_ok() -> bool:
	if not _stage_ok():
		return false
	if _try_luck():
		return true
	return _stored_sex_bond()

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
	# automatically begins a CuddleSession. That interrupts missionary, so keep it off while active.
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
	if _features.is_empty():
		return SETTINGS.allow_act_during_cuddle.get_bool()
	return _feature("allow_act_during_cuddle")


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
	# NightRest's new [go_to_bed] owns her with a sleep: lease. While she is lying awake in a
	# bed, a bed-side act is still valid; walking to bed or sleeping is not.
	if owner.begins_with("sleep:"):
		return _sleep_owner_allows_bed(pose, act_source)
	if owner.begins_with("unfplap:"):
		return false
	if owner.begins_with("weather:") or owner.begins_with("show:"):
		return false
	if owner.begins_with("cuddle:"):
		return pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]
	# A managed bed/couch rest is valid for missionary; every other leisure seat is not.
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

## NightRest's sleep: lease is also used for an awake [go_to_bed] rest. Only a pony already
## lying in a bed, with Anon there too, may accept a bed-side act through it.
func _sleep_owner_allows_bed(pose: String, act_source: String) -> bool:
	if pose != CATALOG.MISSIONARY or act_source not in ["bed_side", "already_lying"]:
		return false
	if not is_instance_valid(pony) or bool(pony.get("sleeping")):
		return false
	if not pony.has_method("posture_status"):
		return false
	var status: Dictionary = pony.posture_status()
	return str(status.get("requested", "")) == "lie_down"

func _nav_pose_gate(pose: String, act_source: String) -> bool:
	if pose == CATALOG.STANDING:
		if pony.is_held() or not pony.grounded():
			return false
		if bool(pony.motion_paused):
			return false
		if pony.has_meta("seated"):
			return false
		var interruption := str(pony.action_interruption_reason())
		if not interruption.is_empty():
			# The request's own affection_active hold is not a gate against its invite.
			if not (_standing_presentation_controller().request_face_active() and state == State.IDLE and interruption.contains("Affection")):
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
		var real: Variant = main.call("real_bed", bed_in) if main.has_method("real_bed") else bed_in
		if real is Node3D and is_instance_valid(real):
			return real
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
	# A headset rig is a plain Node3D: it has neither desktop `controls_locked` nor `flying`, and
	# `bool(null)` is an error in GDScript, so compare against true instead.
	if body.get("controls_locked") == true:
		return false
	if body.get("flying") == true:
		return false
	var wing: Variant = body.get("wing_flight")
	if wing != null and bool(wing.get("active")):
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	var swimming: Variant = body.get("swimming")
	if swimming != null and bool(swimming.get("active")):
		return false
	if DisplayServer.get_name() != "headless" and not _headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var inventory: Variant = main.game.get("inventory") if is_instance_valid(main.game) else null
	if inventory != null:
		var held: Variant = inventory.get("held")
		if held is Dictionary and not (held as Dictionary).is_empty():
			return false
		if str(inventory.get("holding_case")) != "":
			return false
	var seat: Variant = body.get("seat")
	if pose == CATALOG.STANDING:
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
	# Try Your Luck can reach this point before she welcomes the kiss. Starting still needs her
	# current willingness; refusal is a real buck/push, not a silent no-op.
	if not _relationship_ok():
		_log("start refused pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		refuse(pose, act_source, bed_in)
		return false
	_camera_owned = false
	_look_captured = false
	_look_restore_yaw = pose != CATALOG.STANDING
	_posture_owned = false
	_session_finalized = false
	# Remove the idle standing invitation and its request face before the act builds its own pose.
	set_request_face(false)
	clear_presentation()
	_end_satisfied()
	_end_upset()
	pose_id = pose
	source = act_source
	_profile = SETTINGS.template_for(_id)
	_pose_cfg = SETTINGS.pose(_id, pose_id)
	_preferences = SETTINGS.preferences(_id)
	_act_prompts = _profile.get("act_prompts", {})
	_snapshot_settings()
	if is_instance_valid(_flank):
		_apply_jiggle_radius()
	_thrust_tracker = THRUST.new()
	_aftercare_min = int(_profile.get("aftercare_min", 10))
	_cue_gap = SETTINGS.cue_gap_value(float(_profile.get("cue_gap", 12.0)))
	_standing_camera_controller().reset()
	bed = _resolve_bed(pose, act_source, bed_in)
	if pose == CATALOG.MISSIONARY and bed == null:
		# Nothing else is borrowed yet, but the jiggle radius was just applied.
		_restore_jiggle_radius()
		pose_id = ""
		source = ""
		bed = null
		return false
	_player_pony = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	_bob = 0.0
	_bob_velocity = 0.0
	_lean = 0.0
	_lean_velocity = 0.0
	_back = 0.0
	_back_target = 0.0
	_apply_eye_override()
	_wings_controller().reset()
	_jiggle_logged = false
	_act_seconds = 0.0
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
	_pose_logged = false
	_pose_trace_frames = 0
	_summary = {}
	_summary_done = false
	_afterglow_beat = ""
	_stopped_by_her = false
	_debug_forced_tolerance = ""
	_tolerance_warning_key = ""
	_end_tail_tuck()
	_tolerance_controller().reset(_preferences)
	_prepare_vocal()
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()
	_remember_talk_turn()
	_act_spoken_at = _last_spoken_at()
	if source == "cradle":
		if not _release_carry():
			_abort_start()
			return false
	elif source == "already_lying":
		if not REST.release_managed(pony):
			_abort_start()
			return false
	elif source == "bed_side":
		_end_cuddle_session()
		if not REST.release_managed(pony):
			_abort_start()
			return false
	if _cuddle_active() and _feature("allow_act_during_cuddle") \
			and source not in ["bed_side", "already_lying"]:
		_end_cuddle_session()
		REST.release_managed(pony)
	if not _claim_nav():
		_abort_start()
		return false

	_snapshot_pony_bones()
	_posture_owned = true
	pony.sleeping = false
	pony.set_sim_tier(pony.SimTier.HERO)
	pony.set_meta("sex_active", true)
	# integration: build the per-act anatomy controller before the pose reads its config.
	_anatomy_refresh()
	_anatomy_act_refresh(pose)

	# The act is its own state for both of them: Anon stands up before the snapshot and the lock, and
	# she leaves the game's lying state. The bed only supplies the frame their bodies are placed in.
	if pose == CATALOG.MISSIONARY and not _player_pony:
		var body: Variant = main.player
		if body != null and body.has_method("force_stand_up"):
			body.call("force_stand_up")
	if pose == CATALOG.MISSIONARY:
		if source == "cradle":
			_place_on_bed(_bed_anchor())
		else:
			pony.reset_physics_interpolation()
		if pony.get("posture") != null:
			pony.request_posture("stand")
	else:
		var standing := _begin_standing_placement()
		pony.request_posture("stand")
		_standing_camera_controller().begin_facing(standing)

	_build_pose()
	_clear_stock_flank_marks()
	if pose == CATALOG.MISSIONARY:
		_sync_missionary_pose_config()
	_reset_lean_state()
	if pose == CATALOG.MISSIONARY:
		_missionary_camera_controller().prepare()
	_capture_look()
	_lock_player()
	_pause_face_turn()
	_begin_camera_mode()
	_missionary_camera_controller().hide_avatar()
	_bind_action_executor()
	_start_audio()
	_apply_voice_policy()
	_set_inventory_hud_hidden(true)
	# integration: show the player part for the encounter.
	if is_instance_valid(main) and main.has_method("anon_encounter"):
		main.call("anon_encounter", true)
	state = State.POSING_IN
	# integration: act-only visibility updates at the state change, not on the next poll.
	if is_instance_valid(_anatomy):
		_anatomy.call("apply_live")
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

## Standing keeps her body turned away and planted. Stop the standing face-turn response so a
## player conversation cannot make her take turn steps, without pausing locomotion or emotions.
func _pause_face_turn(force := false) -> void:
	if (not force and pose_id != CATALOG.STANDING) or not is_instance_valid(pony):
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

func present_standing() -> bool:
	return bool(_standing_presentation_controller().present_standing())

func presentation_active() -> bool:
	return bool(_standing_presentation_controller().presentation_active())

func presentation_settled() -> bool:
	return bool(_standing_presentation_controller().presentation_settled())

func clear_presentation() -> void:
	_standing_presentation_controller().clear_presentation()

func set_request_face(on: bool) -> void:
	_standing_presentation_controller().set_request_face(on)

func request_face_active() -> bool:
	return bool(_standing_presentation_controller().request_face_active())

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
	_nav.set("wander_enabled", _nav_old_wander)
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
	_end_session(false)
	_finalize_session(false)

## Put her on the bed's anchor. The act poses her body itself, so she only needs to be there; she
## keeps the neutral standing state the solver maintains without fighting the authored pose.
func _place_on_bed(anchor: Transform3D) -> void:
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
	if pony.get("posture") != null:
		pony.request_posture("stand")

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

## Standing start keeps her where she is and puts Anon behind her. The offer cone already
## requires him within 0.8 m of her rump, so the correction is small; the old path moved her in
## front of him instead. AnonPony and headset/VR keep the old placement because their rig is
## the camera or another body.
func _begin_standing_placement() -> Transform3D:
	var forward: Vector3 = -pony.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -main.player.global_basis.z
	forward = forward.normalized()
	var standing := Transform3D(Basis.looking_at(forward, Vector3.UP), pony.global_position)
	if _player_pony or _headset_view() or not is_instance_valid(main) \
			or not is_instance_valid(main.player):
		pony.reset_motion(standing)
		pony.reset_physics_interpolation()
		return standing
	# The offer cone already requires him within 0.8 m of her rump, so the correction is small.
	# The act end leaves him there instead of snapping him back.
	var body: Variant = main.player
	var target: Vector3 = pony.global_position - forward * _standing_gap()
	target.y = body.global_position.y
	body.global_position = target
	# Do not inherit the previous act's view: face him along her forward, so his body is in front
	# of the camera instead of off to one side after a missionary restore.
	body.rotation.y = atan2(-forward.x, -forward.z)
	body.reset_physics_interpolation()
	_log("standing keeps pony at=%s and places Anon at=%s yaw=%.3f" % [
		str(pony.global_position), str(target), body.rotation.y])
	return standing

func _standing_transform() -> Transform3D:
	var view: Camera3D = main.camera()
	var forward := Vector3.FORWARD
	if view != null:
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -main.player.global_basis.z
	forward = forward.normalized()
	var at: Vector3 = main.player.global_position + forward * _standing_gap()
	at.y = main.player.global_position.y
	return Transform3D(Basis.looking_at(forward, Vector3.UP), at)

func _standing_gap() -> float:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return STANDING_GAP_M
	var size := str(settings.call("get_value", "ponies/size"))
	var gaps: Variant = _pose_cfg.get("gaps", STANDING_GAPS)
	var gap := float((gaps as Dictionary).get(size, STANDING_GAP_M)) if gaps is Dictionary else STANDING_GAP_M
	gap *= _same_height_scale()
	gap += SETTINGS.gap_offset_m.get_num()
	_log("standing size=%s gap=%.2f" % [size, gap])
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

## The standing recipe reads these from pose_config every frame. Re-reading the character's pose
## first keeps the other pose overrides, then the presentation neck/head controls win.
func _sync_standing_pose_config() -> void:
	if pose_id != CATALOG.STANDING or not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(_id, CATALOG.STANDING)
	_pose_cfg["play_bow"] = _feature("standing_play_bow")
	_pose_cfg["chin_up_deg"] = float(_presentation_cfg.get("chin_up_deg",
		SETTINGS.chin_up_deg.default))
	_pose_cfg["neck_down_deg"] = float(_presentation_cfg.get("neck_down_deg",
		SETTINGS.neck_down_deg.default))
	var tail_cfg: Variant = _presentation_cfg.get("tail", {})
	if tail_cfg is Dictionary:
		_pose_cfg["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary).get("yaw_deg",
			SETTINGS.yaw_deg.default)))
		_pose_cfg["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary).get("pitch_deg",
			SETTINGS.tail_pitch_deg.default)))
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("pose_config", _pose_cfg)
	if is_instance_valid(_pose):
		_pose.pose_config = _pose_cfg
	if is_instance_valid(_tail):
		_tail.aside_angle = float(_pose_cfg.get("tail_aside", 0.55))
		_tail.lift_angle = float(_pose_cfg.get("tail_lift", 0.42))


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose keeps its nuzzle overrides live.
func _sync_missionary_pose_config() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(_id, CATALOG.MISSIONARY)
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("pose_config", _pose_cfg)
	if is_instance_valid(_pose):
		_pose.pose_config = _pose_cfg
		# The asset instance is shared, so the reload action reaches the live act.
		_pose.authored = _authored_pose()


## The hand-authored missionary base pose. Parsed once for the process; the debug action rewrites
## the same instance in place, so a live act picks the new pose up on its next frame.
func _authored_pose() -> Variant:
	return AUTHORED.shared()


## The parsed authored pose, for the shot camera and the debug action.
func authored_pose_asset() -> Variant:
	return _authored_pose()


## Debug: the player camera replaces the act shot so the pose can be inspected. The mouse stops
## feeding thrust while it is on and drives this look instead, because the act holds
## `controls_locked` (the stock mouse look is dead during an act).
func free_look_active() -> bool:
	return state != State.IDLE and SETTINGS.free_look.get_bool()


## Accumulated free-look rotation as (pitch, yaw), radians, from the act's starting view.
func free_look_rotation() -> Vector3:
	return Vector3(_free_look_pitch, _free_look_yaw, 0.0)


## The middle of the missionary bed's mattress top: the authored pose's origin in world space.
func missionary_pose_origin() -> Vector3:
	if _bed_pose_frame is Transform3D:
		return (_bed_pose_frame as Transform3D).origin
	return pony.global_position if is_instance_valid(pony) else Vector3.ZERO


## Bed space for the authored pose: the middle of the real bed's mattress top, in the bed's axes,
## with the pillow end at -Z so the authored `+Z` (her head) points at the head of the bed. The
## pose is stored relative to this frame, so any bed size or yaw works; `null` leaves the
## correction stack in charge.
func _missionary_pose_frame() -> Variant:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(bed):
		return null
	var fallback: float = float(bed.get_meta("mattress_top", 0.6)) + float(bed.global_position.y)
	var points: Array[Vector3] = [bed.global_position]
	var top: float = MATTRESS.visible_top(bed, points, fallback)
	if not is_finite(top):
		return null
	var at: Vector3 = bed.global_position
	var basis := bed.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


func _build_pose() -> void:
	_free_pose()
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_pose = POSE.new()
		_pose.name = "UnfplapPose"
		_pose.mare = pony
		_pose.set("runtime", self)
		_pose.mode = "standing" if pose_id == CATALOG.STANDING else "missionary"
		_pose.pose_config = SETTINGS.pose(_id, pose_id)
		_pose.look_point = main.camera().global_position if main.camera() != null else pony.global_position
		_pose.amount = 0.0
		_pose.target_amount = 1.0
		if pose_id == CATALOG.MISSIONARY:
			_bed_pose_frame = _missionary_pose_frame()
			_pose.authored = _authored_pose()
			_pose.bed_frame = _bed_pose_frame
			_log_pose_base()
		(skeleton as Skeleton3D).add_child(_pose)
		if pose_id == CATALOG.STANDING:
			if _feature("standing_body_sway"):
				_install_body_sway(skeleton)
			if _feature("thrust_ear_twitch"):
				_install_ear_twitch()
		elif _feature("missionary_body_motion"):
			_install_prone_sway(skeleton)
		_keep_chin_last()
	if pose_id == CATALOG.MISSIONARY:
		_install_tail_lay()
	if pose_id != CATALOG.STANDING:
		return
	_sync_standing_pose_config()
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
		var side_anchor := Vector3.INF
		if is_instance_valid(main) and main.has_method("camera"):
			var view: Variant = main.call("camera")
			if view is Camera3D:
				side_anchor = (view as Camera3D).global_position
		_tail.call("choose_side", side_anchor)
		(hair as Skeleton3D).add_child(_tail)
		_dock_tail = DOCK_TAIL_COAT.new()
		_dock_tail.name = "UnfplapDockTailCoat"
		_dock_tail.mare = pony
		_dock_tail.runtime = self
		_dock_tail.process_priority = 40
		(hair as Skeleton3D).add_child(_dock_tail)

## Snapshot before the act changes her posture or the pose writes bones.
func _snapshot_pony_bones() -> void:
	_pony_saved_bones.clear()
	_pony_saved_hair.clear()
	_pony_saved_skeleton = null
	_pony_saved_hair_skeleton = null
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		_pony_saved_skeleton = sk as Skeleton3D
		for i in (_pony_saved_skeleton as Skeleton3D).get_bone_count():
			_pony_saved_bones.append((_pony_saved_skeleton as Skeleton3D).get_bone_pose(i))
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_pony_saved_hair_skeleton = hair as Skeleton3D
		for i in (_pony_saved_hair_skeleton as Skeleton3D).get_bone_count():
			_pony_saved_hair.append((_pony_saved_hair_skeleton as Skeleton3D).get_bone_pose(i))


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func _restore_pony_bones() -> void:
	if is_instance_valid(_pony_saved_skeleton) \
			and _pony_saved_bones.size() == _pony_saved_skeleton.get_bone_count():
		for i in _pony_saved_bones.size():
			_pony_saved_skeleton.set_bone_pose(i, _pony_saved_bones[i])
	if is_instance_valid(_pony_saved_hair_skeleton) \
			and _pony_saved_hair.size() == _pony_saved_hair_skeleton.get_bone_count():
		for i in _pony_saved_hair.size():
			_pony_saved_hair_skeleton.set_bone_pose(i, _pony_saved_hair[i])
	_pony_saved_bones.clear()
	_pony_saved_hair.clear()
	_pony_saved_skeleton = null
	_pony_saved_hair_skeleton = null


func _free_pose() -> void:
	_pose_rig_checked = false
	_pose_rig_skeleton = 0
	_pose_rig_missing_bones = []
	if is_instance_valid(_tail_lay):
		_tail_lay.call("restore_tail")
		_tail_lay.queue_free()
	_tail_lay = null
	_bed_pose_frame = null
	clear_presentation()
	_end_lean_action()
	_caress_controller().reset()
	_kiss_controller().reset()
	_release_free_camera_lock()
	_standing_anon_controller().remove()
	_remove_extra_modifiers()
	_restore_voice_volume()
	if is_instance_valid(_rump_decal):
		_rump_decal.queue_free()
	_rump_decal = null
	_rump_blush = 0.0
	if is_instance_valid(_pose):
		_pose.queue_free()
	_pose = null
	if is_instance_valid(_dock_tail):
		_dock_tail.call("restore")
		_dock_tail.queue_free()
	_dock_tail = null
	if is_instance_valid(_tail):
		_tail.call("restore_tail")
		_tail.queue_free()
	_tail = null

## The hair tail is not in the authored body pose: each pony has its own tail rig. This lays
## whichever `mTail1..6` bones exist on the hair skeleton flat on the bed.
func _install_tail_lay() -> void:
	if not is_instance_valid(pony):
		return
	var hair: Variant = pony.get("hair_skeleton")
	if not hair is Skeleton3D:
		return
	_tail_lay = TAIL_LAY.new()
	_tail_lay.name = "UnfplapTailLay"
	_tail_lay.mare = pony
	_tail_lay.runtime = self
	(hair as Skeleton3D).add_child(_tail_lay)


func _install_body_sway(skeleton: Skeleton3D) -> void:
	if not _feature("standing_body_sway"):
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
	_ear_twitch.set("runtime", self)
	(head as Skeleton3D).add_child(_ear_twitch)

func _remove_extra_modifiers() -> void:
	_restore_jiggle_radius()
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
	return _clock_s

func _reset_thrust_state() -> void:
	depth = 0.0
	penetration_m = -_back_out_m()
	_auto_on = false
	_auto_controller().reset(_auto_default_pace, _auto_default_depth, _auto_default_shape,
		_auto_default_min)
	_auto_panel_controller().reset()
	_standing_anon_controller().reset_phase()
	_standing_camera_controller().reset_depth()
	_standing_sway_offset = Vector3.ZERO
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
	_close_caress_earned = false
	_utterance_serial = 0
	_utterance_delivered_key = ""
	_utterance_scheduler().reset(_now_s(), _cue_gap)
	_configure_utterance_scheduler()
	_vocal_cooldown = 0.0
	_overwhelmed = 0.0
	_cue_override = ""
	_cue_until = 0.0
	_last_cue_log_text = ""
	_last_cue_log_reason = ""
	_last_touch = ""
	_last_talk = ""
	_last_touch_at = -1000.0
	_last_thrust_score_at = -1000.0
	_receptive_until = 0.0
	_last_talk_at = -1000.0
	_used_memory_ids.clear()
	_used_angles.clear()
	_act_spoken_at = -1e9
	_peak_satisfaction = 0.0
	_act_both_matches = 0
	_act_dislikes = 0
	_act_liked_touch = 0
	_act_liked_talk = 0
	_last_player_talk = ""
	_act_touch_counts.clear()
	_act_touch_dislikes.clear()
	_act_talk_dislikes = 0
	_act_player_lines = 0
	_act_thrusts = 0
	_act_intensity_total = 0
	_act_intensity_right = 0
	_act_pattern_total = 0
	_act_pattern_right = 0
	_act_ended_early = false
	_peak_recorded = false
	if _thrust_tracker == null:
		_thrust_tracker = THRUST.new()
	_thrust_tracker.reset()

func _auto_controller():
	if _auto_thrust == null:
		_auto_thrust = AUTO_THRUST.new()
	return _auto_thrust

## Switch the automatic stroke on or off. X is the only caller. Turning it on starts from the
## hand's current depth, so the shot does not snap; turning it off leaves the depth where it is.
func toggle_auto_thrust() -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	_auto_on = not _auto_on
	var auto = _auto_controller()
	if _auto_on:
		auto.call("begin", depth)
	else:
		auto.call("stop")
	_log("auto thrust %s pace=%.2f/s depth=%.0f%%" % [
		"on" if _auto_on else "off", float(auto.get("pace")),
		float(auto.get("max_depth")) * 100.0])

## One wheel notch while auto owns the stroke. A static controller makes this a no-op.
func auto_thrust_wheel(direction: int) -> void:
	if not _auto_on or state not in [State.ACTIVE, State.CLIMAX]:
		return
	_auto_controller().call("nudge_pace", float(direction) * AUTO_THRUST.PACE_STEP)


func _auto_panel_controller():
	if _auto_panel == null:
		_auto_panel = AUTO_PANEL.new()
	return _auto_panel


## True while the hold-X auto settings layer is open. The lean, the caress input and the kiss
## read this so W/S/Q/E/A/D/Z/F belong to the layer instead of the act.
func auto_panel_open() -> bool:
	return _auto_panel != null and bool(_auto_panel.get("open"))


## Hold X for the auto settings layer: a tap still toggles auto, a hold opens the four rows while
## auto runs. Every action comes from the pure `auto_panel.gd`.
func _auto_panel_tick(delta: float) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		_auto_panel_controller().reset()
		return
	var keys := [
		Input.is_physical_key_pressed(KEY_Q), Input.is_physical_key_pressed(KEY_A),
		Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S),
		Input.is_physical_key_pressed(KEY_E), Input.is_physical_key_pressed(KEY_D),
		Input.is_physical_key_pressed(KEY_Z),
	]
	var actions: Array = _auto_panel_controller().tick(delta,
		Input.is_physical_key_pressed(KEY_X), keys, _auto_on)
	for action: String in actions:
		_auto_panel_action(action)


func _auto_panel_action(action: String) -> void:
	var auto = _auto_controller()
	match action:
		"toggle":
			toggle_auto_thrust()
		"min_up", "min_down":
			auto.call("nudge_min", AUTO_PANEL.DEPTH_STEP if action == "min_up"
				else -AUTO_PANEL.DEPTH_STEP)
		"max_up", "max_down":
			auto.call("nudge_depth", AUTO_PANEL.DEPTH_STEP if action == "max_up"
				else -AUTO_PANEL.DEPTH_STEP)
		"pace_up", "pace_down":
			auto.call("nudge_pace", AUTO_PANEL.PACE_STEP if action == "pace_up"
				else -AUTO_PANEL.PACE_STEP)
		"shape_next":
			auto_cycle_shape()
		_:
			return
	_log("auto layer %s min=%.0f%% max=%.0f%% pace=%.2f/s shape=%s" % [
		action, float(auto.get("min_depth")) * 100.0, float(auto.get("max_depth")) * 100.0,
		float(auto.get("pace")), str(auto.get("shape"))])


## `Z` in the layer: next stroke shape, written to settings so an experiment survives the act.
func auto_cycle_shape() -> void:
	var next: String = AUTO_THRUST.next_shape(str(_auto_controller().get("shape")))
	SETTINGS.curve.set_choice(next)
	_auto_default_shape = next
	_auto_controller().call("set_shape", next)


## The `Auto shape` label for the current generator value, matching the settings row.
func auto_shape_name() -> String:
	var value := str(_auto_controller().get("shape"))
	var index := SETTINGS.curve.options.find(value)
	if index >= 0 and index < SETTINGS.curve.labels.size():
		return str(SETTINGS.curve.labels[index])
	return value


## Live text for one hold-X control row.
func auto_panel_label(kind: String) -> String:
	var auto = _auto_controller()
	match kind:
		"min":
			return "Min depth %d%%" % roundi(float(auto.get("min_depth")) * 100.0)
		"max":
			return "Max depth %d%%" % roundi(float(auto.get("max_depth")) * 100.0)
		"pace":
			return "Pace %.2f/s" % float(auto.get("pace"))
		"shape":
			return "Shape: %s" % auto_shape_name()
	return ""


## integration: anatomy action entry points for input.gd. They are no-ops when the per-act
## controller is absent, so the keys behave exactly like master with the feature off.
func toggle_anatomy_hole() -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("toggle_hole")


func toggle_anatomy_oral() -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("toggle_oral")


func toggle_anatomy_finish() -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("toggle_finish")


func anatomy_oral_active() -> bool:
	return is_instance_valid(_anatomy_act) and bool(_anatomy_act.call("oral_active"))


func anatomy_finish_pull_out() -> bool:
	return is_instance_valid(_anatomy_act) and bool(_anatomy_act.call("pull_out_selected"))


## integration: precise action gates. With no act controller (assets missing, feature off) the
## keys pass through and the HUD rows stay hidden.
func anatomy_hole_ready() -> bool:
	return is_instance_valid(_anatomy_act) and state in [State.ACTIVE, State.CLIMAX] \
		and SETTINGS.anatomy_holes.get_bool() \
		and not bool(_anatomy_act.call("oral_active"))


func anatomy_oral_ready() -> bool:
	return is_instance_valid(_anatomy_act) and state == State.ACTIVE \
		and pose_id == CATALOG.STANDING and SETTINGS.anatomy_oral.get_bool()


func anatomy_finish_ready() -> bool:
	return is_instance_valid(_anatomy_act) and state in [State.ACTIVE, State.CLIMAX] \
		and SETTINGS.anatomy_finish.get_bool()


func anatomy_actions_ready() -> bool:
	return anatomy_hole_ready() or anatomy_oral_ready() or anatomy_finish_ready()


func missionary_anon_body() -> Variant:
	return _missionary_anon


## Her gaze target in missionary: the authored Anon's face. The game camera is on his standing
## player rig, metres off the bed, and aiming there had her looking at empty air.
func _missionary_gaze_point() -> Vector3:
	if is_instance_valid(_missionary_anon) and bool(_missionary_anon.get("active")):
		var point: Variant = _missionary_anon.call("eye_point")
		if point is Vector3 and (point as Vector3).is_finite():
			var aim: Vector3 = point
			aim.y += SETTINGS.gaze_offset_mm_for(SETTINGS.pony_size_name()) / 1000.0
			return _missionary_camera_controller().head_look_point_at(aim)
	return _missionary_camera_controller().head_look_point(_kiss_controller().mouth_view())


## The game's eye modifier still points wherever the standing player rig left it; in missionary the
## pupils follow the same gaze target the head solve uses, so the eyes do not sit above his face.
func _aim_missionary_eyes() -> void:
	if not is_instance_valid(pony):
		return
	var target := _missionary_gaze_point()
	if is_instance_valid(_pose):
		var value: Variant = _pose.get("look_point")
		if value is Vector3 and (value as Vector3).is_finite() \
				and (value as Vector3).length_squared() > 0.0001:
			target = value
	if not target.is_finite():
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)


func anatomy_bed_active() -> bool:
	return is_instance_valid(_missionary_anon) and bool(_missionary_anon.get("active"))


## integration: VR standing hooks. No-op unless the VR flag created the controller.
func _start_vr_act() -> void:
	_stop_vr_act()
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var avatar := main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return
	var cameras: Array = main.player.find_children("*", "XRCamera3D", true, false)
	var origins: Array = main.player.find_children("*", "XROrigin3D", true, false)
	if cameras.is_empty() or origins.is_empty():
		return
	_vr_act = VR_ACT.new()
	_vr_act.name = "UnfplapVrAct"
	_vr_act.set("runtime", self)
	_vr_act.set("player", main.player)
	_vr_act.set("hip_target", avatar.get("_hip_target"))
	_vr_act.set("camera", cameras[0])
	_vr_act.set("origin", origins[0])
	add_child(_vr_act)


func _stop_vr_act() -> void:
	if is_instance_valid(_vr_act):
		_vr_act.queue_free()
	_vr_act = null


func vr_forward() -> Vector3:
	if is_instance_valid(_anatomy_act):
		var rear: Vector3 = _anatomy_act.call("hole_rear")
		var forward := Vector3(-rear.x, 0.0, -rear.z).normalized()
		if forward.length_squared() > 0.001:
			return forward
	if is_instance_valid(pony):
		return -pony.global_basis.z.normalized()
	return Vector3.FORWARD


func vr_depth(value: float) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	_thrust_move(value - depth, _now_s())
	penetration_m = depth * penetration_reach()


## The Anon body the act poses, so the avatar hiding leaves it visible.
func anatomy_bed_avatar() -> Variant:
	if is_instance_valid(_missionary_anon):
		return _missionary_anon.get("avatar")
	return null


## integration: drives the standing camera's facing override for the oral turn.
## integration: her opening's outward normal, in world space.
func anatomy_normal() -> Vector3:
	if not is_instance_valid(_anatomy_act):
		return Vector3.ZERO
	var normal: Variant = _anatomy_act.call("opening_normal")
	if normal is Vector3 and (normal as Vector3).is_finite():
		return normal
	return Vector3.ZERO


## integration: her entrance point during an anatomy act, in world space.
func anatomy_opening() -> Vector3:
	if not is_instance_valid(_anatomy_act):
		return Vector3.ZERO
	var point: Variant = _anatomy_act.call("hole_point")
	if point is Vector3 and (point as Vector3).is_finite():
		return point
	return Vector3.ZERO


## integration: her exit axis during an anatomy act, in world space; `Vector3.ZERO` otherwise.
func anatomy_rear() -> Vector3:
	if not is_instance_valid(_anatomy_act):
		return Vector3.ZERO
	var rear: Variant = _anatomy_act.call("hole_rear")
	if rear is Vector3 and (rear as Vector3).is_finite():
		return rear
	return Vector3.ZERO


func anatomy_facing(basis: Basis, amount: float) -> void:
	var camera: Variant = _standing_camera_controller()
	if camera != null and camera.has_method("set_facing_override"):
		camera.call("set_facing_override", basis, amount)


## integration: the standing part aims itself in `anon_part.track`; only the optional bed body
## still needs the wrapper hook.
## The bed pose writes his hip itself, so the marker alignment is only for other rigs (VR).
func apply_anon_align(_hip: Node3D, _facing: Basis) -> void:
	pass


func anatomy_status(text: String, seconds := 2.0) -> void:
	if is_instance_valid(main) and main.has_method("anatomy_status"):
		main.call("anatomy_status", text, seconds)


## integration: debug placement controls for the local anatomy asset.
func anatomy_place(op: String, value := 0.0) -> String:
	if not is_instance_valid(_anatomy):
		return "Anatomy is not attached."
	match op:
		"save":
			_anatomy.call("save_place")
		"reset":
			_anatomy.call("reset_place")
		"text":
			return str(_anatomy.call("place_text"))
		_:
			_anatomy.call("nudge", op, value)
	return str(_anatomy.call("place_text"))

## Idempotent stop for every state exit. It never moves the depth.
func _stop_auto_thrust() -> void:
	_auto_on = false
	if _auto_thrust != null:
		_auto_thrust.call("stop")
	if _auto_panel != null:
		_auto_panel.call("close")

## Feed the generated depth through the same tracker as the mouse. Strength, readiness,
## intensity, pattern, audio, camera and presentation therefore need no auto-specific path.
func _auto_thrust_tick(delta: float) -> void:
	if not _auto_on or _thrust_tracker == null:
		return
	var next_depth: float = _auto_controller().call("step", delta)
	_thrust_move(next_depth - depth, _now_s())
	penetration_m = depth * penetration_reach()

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

## Anon's visible shaft length in metres, measured from the placed part. With the anatomy off the
## nominal length keeps the mouse feel identical.
func _shaft_length_m() -> float:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if is_instance_valid(part) and bool(part.call("showing")):
		var length: Variant = part.call("shaft_length_m")
		if length is float and (length as float) > 0.001:
			return length as float
	return NOMINAL_SHAFT_M


## The deepest the tip can reach, in metres. Both poses carry his body on the stroke, so
## `Pelvis gap` keeps his pelvis that far behind her rear surface; a detached placement is limited
## by the shaft alone.
func penetration_reach() -> float:
	var length := _shaft_length_m()
	if pose_id in [CATALOG.STANDING, CATALOG.MISSIONARY]:
		return maxf(length - SETTINGS.pelvis_gap_m.get_num(), 0.02)
	return maxf(length, 0.02)


## How far the tip rests behind her lips when pulled all the way out.
func _back_out_m() -> float:
	return maxf(SETTINGS.back_out_m.get_num(), 0.0)


## Move the physical penetration and mirror it into the public 0..1 depth. Travel behind the lips
## moves the cock but leaves the depth at zero, so the standoff never eats a stroke.
func _set_penetration(target_m: float, now: float) -> void:
	var reach := penetration_reach()
	penetration_m = clampf(target_m, -_back_out_m(), reach)
	_thrust_move(THRUST.penetration_to_depth(penetration_m, reach) - depth, now)


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
		_dispatch_stroke_event(event)

func _thrust_tick() -> void:
	if _thrust_tracker == null:
		return
	var events: Array = _thrust_tracker.tick(_now_s())
	depth = _thrust_tracker.depth
	for event: Dictionary in events:
		_dispatch_stroke_event(event)

## The tracker reports the bottom of a stroke and its close. Presentation belongs to the bottom
## so the plap and the body land with the motion; the score belongs to the close.
func _dispatch_stroke_event(event: Dictionary) -> void:
	if str(event.get("kind", "stroke")) == "impact":
		_on_impact(event)
	else:
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
	_act_thrusts += 1
	if state == State.CLIMAX:
		# The player can keep thrusting through her climax; presentation already happened at the
		# bottom and only the score stays off.
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
	var wanted_intensity := str(_preferences.get("intensity", "firm"))
	var wanted_pattern := str(_preferences.get("pattern", "steady"))
	var intensity_match := not _last_intensity.is_empty() and _last_intensity == wanted_intensity
	var pattern_match := not _last_pattern.is_empty() and _last_pattern == wanted_pattern
	_act_intensity_total += 1
	if intensity_match:
		_act_intensity_right += 1
	if not _last_pattern.is_empty():
		_act_pattern_total += 1
		if pattern_match:
			_act_pattern_right += 1
	if intensity_match and pattern_match:
		_act_both_matches += 1
	var heat := THRUST_HEAT_NONE
	if intensity_match and pattern_match:
		heat = THRUST_HEAT_BOTH
	elif intensity_match or pattern_match:
		heat = THRUST_HEAT_ONE
	if heat > 0.0:
		heat *= PREFERENCES.warmth_scale(_preferences)
		if now < _receptive_until:
			heat *= RECEPTIVE_BOOST
		if cycle_phase() == CYCLE.HEAT:
			heat *= HEAT_READINESS
		_add_heat(heat)
	_log("thrust score intensity=%s pattern=%s both=%s heat=%.2f readiness=%.0f" % [
		_last_intensity, _last_pattern, str(intensity_match and pattern_match),
		heat, satisfaction])

## The stroke's bottom: the plap, the wobble, the wings, her blush and the ear twitch all land
## here, with the motion. Fired once per real thrust from the tracker's `impact` event. Only the
## body slap checks contact: his skin has to reach her coat, so a shallow thrust stays silent
## while the slide and the bed still play.
func _on_impact(result: Dictionary) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	var strength := clampf(float(result.get("strength", 0.0)), 0.0, 1.0)
	var impact := clampf(strength * THRUST_IMPACT_GAIN, 0.0, 1.0)
	var jiggle := THRUST.jiggle_amount(float(result.get("travel", 0.0)), strength)
	var reach := penetration_reach()
	var contact := THRUST.contact_amount(float(result.get("end_depth", 0.0)) * reach, reach,
		maxf(SETTINGS.contact_gap_m.get_num(), 0.0))
	var plap := PREFERENCES.intensity_for(strength) != "soft" and contact > 0.001
	var now := _now_s()
	_wings_controller().on_thrust(impact)
	_thrust_jiggle(jiggle)
	if pose_id == CATALOG.STANDING and is_instance_valid(_tail):
		_tail.call("thrust", jiggle * _jiggle_size_scale() * _jiggle_intensity_scale)
	if pose_id == CATALOG.STANDING:
		if impact >= RUMP_BLUSH_MIN_STRENGTH:
			_rump_blush = minf(RUMP_BLUSH_MAX, _rump_blush + RUMP_BLUSH_STEP)
			_ensure_rump_decal()
		if _feature("thrust_ear_twitch") and is_instance_valid(_ear_twitch):
			_ear_twitch.call("try_trigger", impact)
	_thrust_times.append(now)
	while not _thrust_times.is_empty() and now - float(_thrust_times[0]) > 1.0:
		_thrust_times.pop_front()
	_play_vocal()
	if is_instance_valid(_act_audio):
		_act_audio.play_impact(pose_id, strength, _rump_point(),
			_bed_audio_point(), _bed_soft, contact)
	_log("thrust impact contact=%.2f plap=%d readiness=%.0f rate=%.1f/s strength=%.2f impact=%.2f jiggle=%.2f intensity=%s pattern=%s" % [
		contact, 1 if plap else 0, satisfaction, _thrusts_per_second(), strength, impact, jiggle,
		_last_intensity, _last_pattern])

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
	var lines = _utterance_scheduler()
	mood = UTTERANCE_SCHEDULER.mood_for(satisfaction, _overwhelmed)
	if not _cue_override.is_empty() and now < _cue_until:
		cue = _cue_override
	else:
		_cue_override = ""
		cue = UTTERANCE_SCHEDULER.base_cue(_preferences, _overwhelmed, satisfaction,
			_last_intensity, _last_pattern)
	lines.observe_cue(now, cue)
	var demand := UTTERANCE.is_demand(cue)
	var is_override := not _cue_override.is_empty()
	var admit := false
	var reason := ""
	if not _act_lines_enabled():
		reason = "act_lines_off"
	elif demand and lines.demand_blocked(cue, now):
		reason = "demand"
	elif not _utterance_channel_free():
		reason = "channel" if not lines.channel_free() else "speech"
	else:
		admit = lines.admit_cue(now, cue, is_override)
		if not admit:
			reason = lines.last_reason
	var decision := reason if not admit else "admit"
	if cue != _last_cue_log_text or decision != _last_cue_log_reason:
		_last_cue_log_text = cue
		_last_cue_log_reason = decision
		_log("cue text=\"%s\" admit=%s reason=%s override=%s" % [
			cue, "yes" if admit else "no", decision, str(is_override)])
	if admit:
		var key := _queue_utterance("cue", "cue", "cue")
		if not key.is_empty():
			lines.note_cue_queued(now, key, cue, demand, is_override)

func _set_cue_override(text: String, seconds := -1.0) -> void:
	if seconds < 0.0:
		seconds = _cue_override_seconds
	cue = text
	_cue_override = text
	_cue_until = _now_s() + maxf(0.0, seconds)

## One real action per call, including the tolerance meter. Continuous inputs must emit discrete
## events: a held caress calls this once per CAESS_TOUCH_SECONDS (standing_caress.gd), never once
## per physics tick, or a liked caress would erase all distress every frame.
func _on_touch(kind: String) -> void:
	if state != State.ACTIVE:
		return
	# integration: a kiss or an act smack makes the anatomy mesh react.
	if is_instance_valid(_anatomy) and kind in ["kiss", "smack"]:
		_anatomy.call("react")
	_act_touch_counts[kind] = int(_act_touch_counts.get(kind, 0)) + 1
	var tolerance_event: Dictionary = {}
	if kind in _preferences.get("dislikes", []):
		_act_touch_dislikes[kind] = int(_act_touch_dislikes.get(kind, 0)) + 1
		tolerance_event = _tolerance_controller().observe_dislike(kind)
	elif kind in _preferences.get("touch", []):
		_tolerance_controller().observe_like(kind)
	var now := _now_s()
	# One shared scoring cooldown: alternating caress/kiss/smack must not bypass the cap.
	if now - _last_touch_at < _touch_cooldown_s:
		_tolerance_event(tolerance_event)
		return
	_last_touch_at = now
	_last_touch = kind
	if kind in _preferences.get("touch", []):
		_act_liked_touch += 1
		if satisfaction < ASSIST_CAP:
			_add_heat(minf(TOUCH_HEAT, ASSIST_CAP - satisfaction))
			_set_cue_override("She likes that.")
		else:
			_set_cue_override("She needs more than your hands.")
		_receptive_until = now + _receptive_seconds
		_log("touch like kind=%s readiness=%.0f" % [kind, satisfaction])
	elif kind in _preferences.get("dislikes", []):
		_act_dislikes += 1
		_add_heat(-TOUCH_HEAT)
		_overwhelmed = _cue_overwhelmed_s
		_set_cue_override("She doesn't like that.")
		_log("touch dislike kind=%s readiness=%.0f" % [kind, satisfaction])
	# A neutral touch sets no override; the live base cue stays on screen.
	_tolerance_event(tolerance_event)

## The player's own words are a concrete input. The AI still writes her reply; this only
## decides whether the line landed with her preference.
func _on_talk(text: String) -> void:
	if state != State.ACTIVE:
		return
	var category := PREFERENCES.classify_talk(text)
	if category.is_empty():
		return
	var tolerance_event: Dictionary = {}
	if category in _preferences.get("dislikes", []):
		_act_talk_dislikes += 1
		tolerance_event = _tolerance_controller().observe_dislike(category)
	elif category in _preferences.get("talk", []):
		_tolerance_controller().observe_like(category)
	var now := _now_s()
	if now - _last_talk_at < _talk_cooldown_s:
		_tolerance_event(tolerance_event)
		return
	_last_talk_at = now
	_last_talk = category
	if category in _preferences.get("talk", []):
		_act_liked_talk += 1
		if satisfaction < ASSIST_CAP:
			_add_heat(minf(TALK_HEAT, ASSIST_CAP - satisfaction))
			_set_cue_override("She likes that.")
		else:
			_set_cue_override("She needs you to move.")
		_receptive_until = now + _receptive_seconds
		_log("talk like category=%s readiness=%.0f" % [category, satisfaction])
	elif category in _preferences.get("dislikes", []):
		_act_dislikes += 1
		_add_heat(-TALK_HEAT)
		_overwhelmed = _cue_overwhelmed_s
		_set_cue_override("She didn't like that.")
		_log("talk dislike category=%s readiness=%.0f" % [category, satisfaction])
	else:
		_set_cue_override("She listens.")
	_tolerance_event(tolerance_event)

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
				_act_player_lines += 1
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

## True when no mod line owns the slot and the director/pony are not already speaking.
func _utterance_channel_free() -> bool:
	return _utterance_scheduler().channel_free() and not _speech_busy()


## Free a delivered line after its release hold, drop a row the director erased, and expire a
## queued or generating line at its max age. A line that already reached audio is never cut here.
func _utterance_tick() -> void:
	if state in [State.IDLE, State.POSING_IN]:
		return
	_release_finished_utterance()
	var lines = _utterance_scheduler()
	var key = lines.pending_key()
	if key.is_empty():
		_utterance_delivered_key = ""
		return
	var now := _now_s()
	var line := "unknown"
	if is_instance_valid(main) and is_instance_valid(main.game):
		line = MEMORY.line_state(main.game, key)
	if line == "absent":
		_log("utterance absent key=%s" % key)
		lines.drop_pending()
		return
	if line == "delivered":
		# A released line keeps this state until speech stops and the hold passes. Log it once.
		if key != _utterance_delivered_key:
			_utterance_delivered_key = key
			_log("utterance delivered key=%s age=%.1f" % [
				key, maxf(0.0, now - lines.pending_since())])
		lines.note_finished(now, key)
		_release_finished_utterance()
		return
	if line == "speaking":
		return
	if lines.pending_override() and (_cue_override.is_empty() or cue != lines.pending_cue()) \
			and not (line == "unknown" and _speech_busy()):
		_cancel_pending_utterance("override")
		return
	if line == "unknown" and _speech_busy():
		return
	if now > lines.pending_until():
		_cancel_pending_utterance("age")


## integration: one adult observer may say a short line, using the modern witness perception.
func _bystander_tick(delta: float) -> void:
	if not SETTINGS.act_bystanders.get_bool() or state != State.ACTIVE \
			or not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	if _bystander_event != _event_id:
		_bystander_event = _event_id
		_bystander_spoken.clear()
		_bystander_wait = BYSTANDER_FIRST_S
	_bystander_wait -= delta
	if _bystander_wait > 0.0 or _bystander_spoken.size() >= BYSTANDER_MAX:
		return
	_bystander_wait = BYSTANDER_GAP_S
	if randf() > BYSTANDER_CHANCE:
		return
	var seen: Array = MEMORY.perceived_adults(main.game, pony).filter(func(row: Dictionary) -> bool:
		return not str(row.id) in _bystander_spoken and str(row.id) != _id)
	if seen.is_empty():
		return
	var row: Dictionary = seen.pick_random()
	var observer: Node3D = row.node
	var event_id := _event_id
	var valid := func() -> bool:
		return is_instance_valid(observer) and is_instance_valid(pony) and _event_id == event_id \
			and state in [State.ACTIVE, State.CLIMAX]
	var indoors: bool = HOUSE.at(get_tree(), pony.global_position) != null
	var purpose := BYSTANDER_PROMPT % [_display_name,
		BYSTANDER_INDOORS if indoors else BYSTANDER_OUTDOORS]
	if MEMORY.bystander_line(main.game, str(row.id), event_id, purpose, valid):
		_bystander_spoken.append(str(row.id))
		_log("bystander line from %s" % row.id)


func _queue_utterance(kind: String, prompt_key: String, key_suffix: String) -> String:
	if state != State.ACTIVE or not is_instance_valid(main) or not is_instance_valid(main.game):
		return ""
	# integration: her mouth is busy during oral.
	if anatomy_oral_active():
		return ""
	if _director() == null:
		return ""
	var template := str(_act_prompts.get(prompt_key, ""))
	if template.strip_edges().is_empty():
		template = str(_act_prompts.get("utterance", ""))
	if template.strip_edges().is_empty():
		_log("utterance missing prompt kind=%s" % kind)
		return ""
	var values := {
		"state": UTTERANCE.state_line(
			pose_id, mood, _last_intensity, _last_pattern,
			_last_touch, _last_talk, _act_seconds, pony_climaxes),
		"preferences": PREFERENCES.describe(_preferences),
		"taste": PREFERENCES.describe(_preferences),
		"cue": cue,
		"recent": _recent_lines(),
	}
	var memory_id := ""
	if kind == "cue":
		var facts := MEMORY.cue_facts(main.game, _id, _event_id)
		var tone_name := RELATIONSHIP_CUE.tone(facts)
		var relationship_note := RELATIONSHIP_CUE.note(facts)
		values["relationship"] = relationship_note
		values["tone"] = RELATIONSHIP_CUE.tone_line(tone_name) \
			if not relationship_note.is_empty() else ""
		values["seed"] = UTTERANCE.line_seed({
			"mood": mood,
			"intensity": _last_intensity,
			"pattern": _last_pattern,
			"wanted_intensity": str(_preferences.get("intensity", "firm")),
			"wanted_pattern": str(_preferences.get("pattern", "steady")),
			"last_touch": _last_touch,
			"last_talk": _last_talk,
			"touch_likes": _preferences.get("touch", []),
			"touch_dislikes": _preferences.get("dislikes", []),
			"talk_likes": _preferences.get("talk", []),
		})
		var memory := MEMORY.shared_memory(main.game, _id, cue, _event_id, _used_memory_ids)
		values["memory"] = RELATIONSHIP_CUE.memory_line(str(memory.get("text", "")))
		memory_id = str(memory.get("id", ""))
	var purpose := UTTERANCE.format(template, values)
	if kind == "cue":
		purpose += UTTERANCE.context_note(template, values)
		purpose += CUE_REACTION_NOTE
		# integration: optional line angles and speech feel, independent of each other.
		if SETTINGS.act_speech_feel.get_bool():
			purpose += _speech_feel_note()
		if SETTINGS.act_line_angles.get_bool():
			purpose += _line_variety(values.recent)
	_utterance_serial += 1
	var suffix := "%s:%d" % [key_suffix, _utterance_serial]
	var act_id := _event_id
	var line_key := MEMORY.mod_key(act_id, "line", suffix)
	var valid := func() -> bool:
		# Deliberately independent of the act state: cancelling the act must not invalidate
		# a line that is already being generated or spoken. Explicit `_end_act_lines` calls
		# still cancel it at climax/afterglow boundaries.
		return is_instance_valid(pony) and _event_id == act_id
	var finished := func() -> void:
		_utterance_done(line_key)
	var queued := MEMORY.utterance_for(main.game, _id, act_id, suffix, purpose, valid, finished)
	if queued.is_empty():
		_log("utterance queue failed kind=%s text=\"%s\"" % [kind, cue])
		return ""
	if not memory_id.is_empty():
		_used_memory_ids.append(memory_id)
	_log("utterance kind=%s text=\"%s\" key=%s" % [kind, cue, queued])
	return queued


func _utterance_done(key: String) -> void:
	_utterance_scheduler().note_finished(_now_s(), key)
	_release_finished_utterance()


## The director can report a line finished before its final voice chunk has stopped. Keep the
## slot reserved until `_speech_busy()` is false, otherwise the next line can cut it off.
func _release_finished_utterance() -> void:
	if _speech_busy():
		return
	var lines = _utterance_scheduler()
	if not lines.release_ready(_now_s()):
		return
	lines.release()


func _cancel_pending_utterance(reason := "") -> void:
	var lines = _utterance_scheduler()
	var key = lines.pending_key()
	var pending_cue: String = str(lines.pending_cue())
	var age: float = maxf(0.0, _now_s() - float(lines.pending_since()))
	var line := "unknown"
	if not key.is_empty() and is_instance_valid(main) and is_instance_valid(main.game):
		line = MEMORY.line_state(main.game, key)
	var director := _director()
	var director_state := str(director.get("state")) if director != null else "?"
	lines.drop_pending()
	if key.is_empty():
		return
	_log("utterance cancel reason=%s key=%s text=\"%s\" age=%.1f line=%s director=%s speech=%s" % [
		reason if not reason.is_empty() else "manual", key, pending_cue, age, line,
		director_state, str(_speech_busy())])
	if is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.cancel_line(main.game, key)


## Drop all act lines that have not started speaking. A line that is already speaking may
## finish; one that is only queued or still being generated is cancelled. This runs at every
## climax/afterglow boundary and every act end, so a delayed line cannot start afterward.
func _end_act_lines(keep_speaking := true) -> void:
	if is_instance_valid(main) and is_instance_valid(main.game):
		var cancelled := MEMORY.cancel_act_lines(main.game, _event_id, keep_speaking)
		if cancelled > 0:
			_log("act lines cancelled=%d" % cancelled)
	_utterance_scheduler().drop_pending()

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
	var limit := RECENT_LINES if SETTINGS.act_line_angles.get_bool() else 4
	var start := maxi(0, (spoken as Array).size() - limit)
	for index in range(start, (spoken as Array).size()):
		recent.append(str((spoken as Array)[index]))
	return " | ".join(recent)


## integration: without a fresh angle she answers the same prompt the same way.
func _line_variety(recent: Variant) -> String:
	var open: Array = LINE_ANGLES.filter(func(angle: String) -> bool:
		return not angle in _used_angles)
	if open.is_empty():
		_used_angles.clear()
		open = LINE_ANGLES.duplicate()
	var angle: String = open.pick_random()
	_used_angles.append(angle)
	if _used_angles.size() > ANGLES_REMEMBERED:
		_used_angles.remove_at(0)
	var note := " This time, %s Bring in something you two actually said, did or know from today if it fits." % angle
	if not str(recent).is_empty():
		note += " Your recent lines were: %s. Do not reuse their wording, their opening word or their idea." % recent
	return note


## integration: tells the line how the current strokes break up her speech.
func _speech_feel_note() -> String:
	if _last_intensity.is_empty():
		return ""
	var pace := maxf(_thrusts_per_second(), 0.0)
	var hole := ""
	if is_instance_valid(_anatomy_act) and bool(_anatomy_act.get("_anal")):
		hole = " Anon is in your ass right now, not your pussy."
	var level := 0.5 * float(SPEECH_ROUGHNESS.get(_last_intensity, 0.5)) \
		+ 0.5 * clampf(pace / SPEECH_FULL_PACE, 0.0, 1.0)
	var frequency := "Put one after almost every word or two, so your speech keeps breaking apart."
	if level < 0.25:
		frequency = "Use only one, quiet and breathy."
	elif level < 0.5:
		frequency = "Use one or two."
	elif level < 0.75:
		frequency = "Put one after every few words."
	return hole + " Right now Anon's strokes are %s and %s, about %.1f a second. Break up your speech with exclamations between words, such as \"Ah!\", \"Hah!\", \"FUCK!\", \"Ah...\", \"Buck...\", \"Nngh...\" and similar ones in your own voice. %s They do not count toward your word limit." % [
		_last_intensity, _last_pattern if not _last_pattern.is_empty() else "steady", pace, frequency]

func _last_spoken_line() -> String:
	var recent := _recent_lines()
	if recent.is_empty():
		return ""
	var parts := recent.split(" | ")
	return parts[parts.size() - 1].strip_edges() if not parts.is_empty() else ""


## When she last actually spoke, so a peak memory does not quote a pre-act line as an answer.
func _last_spoken_at() -> float:
	var director := _director()
	if director == null:
		return -1e9
	var characters: Variant = director.get("characters")
	if not characters is Dictionary or not (characters as Dictionary).has(_id):
		return -1e9
	var entry: Variant = (characters as Dictionary)[_id]
	if not entry is Dictionary:
		return -1e9
	return float((entry as Dictionary).get("last_spoken_at", -1e9))

## One summary per act. It is scored from the action counters, stored in the world's module
## state, and written to the game's impression once. Forced stops never call it.
func _commit_summary(real_act: bool) -> void:
	if _summary_done:
		return
	_summary_done = true
	if not _history_enabled() or not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	var outcome: Dictionary = ACT_SUMMARY.evaluate(_summary_inputs(), ACT_SUMMARY.rules())
	if bool(outcome.get("skip", false)):
		_log("summary skip reasons=%s seconds=%.1f thrusts=%d" % [
			_summary_reasons(outcome), _act_seconds, _act_thrusts])
		return
	_summary = outcome
	var result: Dictionary = ACT_HISTORY.commit(ACT_HISTORY.section(), _id, outcome,
		ACT_HISTORY.day_now())
	ACT_HISTORY.save()
	MEMORY.commit_act(main.game, _id, _display_name, _event_id, outcome, not real_act)
	var row: Dictionary = result.get("row", {})
	var events: PackedStringArray = []
	var raw_events: Variant = result.get("events", [])
	if raw_events is Array:
		for item: Variant in raw_events:
			events.append(str(item))
	_log("summary grade=%s quality=%.2f checks=%d/%d reasons=%s tier=%s hurt=%d comfort=%d events=%s" % [
		str(outcome.get("grade", "neutral")), float(outcome.get("quality", 0.0)),
		int(outcome.get("right", 0)), int(outcome.get("total", 0)),
		_summary_reasons(outcome), ACT_HISTORY.tier_name(row),
		int(row.get("hurt", 0)), int(row.get("comfort", 0)), ",".join(events)])


func _summary_inputs() -> Dictionary:
	return {
		"preferences": _preferences,
		"seconds": _act_seconds,
		"thrusts": _act_thrusts,
		"pony_climaxes": pony_climaxes,
		"talk_liked": _act_liked_talk,
		"talk_dislikes": _act_talk_dislikes,
		"touches_liked": _act_liked_touch,
		"touch_dislikes": _act_touch_dislikes.duplicate(true),
		"player_lines": _act_player_lines,
		"intensity_total": _act_intensity_total,
		"intensity_right": _act_intensity_right,
		"pattern_total": _act_pattern_total,
		"pattern_right": _act_pattern_right,
		"ended_early": _act_ended_early,
		"stopped_by_her": _stopped_by_her,
		"tolerance": str(_preferences.get("tolerance", "normal")),
		"forced": false,
	}


func _summary_reasons(outcome: Dictionary) -> String:
	var parts: PackedStringArray = []
	var raw: Variant = outcome.get("reasons", [])
	if raw is Array:
		for item: Variant in raw:
			parts.append(str(item))
	return ",".join(parts)


func _history_enabled() -> bool:
	return ACT_HISTORY.enabled()


func _history_row() -> Dictionary:
	return ACT_HISTORY.effective_row(ACT_HISTORY.section(), _id, ACT_HISTORY.day_now())


func _history_note() -> String:
	if not _history_enabled():
		return ""
	return ACT_HISTORY.prompt_note(_history_row())


## Called by main before a normal Y start. A withdrawn mare still shows the offer; pressing Y
## gives one gentle refusal instead of a silent no.
func history_blocks_start() -> bool:
	if state != State.IDLE or not _history_enabled():
		return false
	return ACT_HISTORY.blocks_start(_history_row())


func refuse_from_history(_pose: String, source: String, _bed: Variant = null) -> bool:
	if not history_blocks_start():
		return false
	if _now_s() - _history_refusal_at < 4.0:
		return true
	_history_refusal_at = _now_s()
	if is_instance_valid(main) and is_instance_valid(main.game):
		var row := _history_row()
		var event_id := "history_refusal_%s_%d" % [_id, Time.get_ticks_usec()]
		var valid := func() -> bool:
			return is_instance_valid(pony) and state == State.IDLE
		MEMORY.reaction_for(main.game, _id, "history_refusal", event_id,
			ACT_HISTORY.refusal_purpose(row), valid)
		_log("history refusal id=%s tier=%s hurt=%d" % [
			_id, ACT_HISTORY.tier_name(row), int(row.get("hurt", 0))])
	if source == "cradle":
		_release_carry()
		if is_instance_valid(pony) and pony.get("posture") != null:
			pony.request_posture("stand")
	return true


## Idle-only: a sincere apology repairs once per in-game day, and a pending reminder or
## complaint becomes one short line in a quiet moment.
func _history_tick(_delta: float) -> void:
	if not _history_enabled() or not is_instance_valid(pony) or not is_instance_valid(main):
		return
	if not is_instance_valid(main.player) or get_tree().paused:
		return
	var director := _director()
	if director == null:
		return
	var now := _now_s()
	var turn := int(director.get("_turn_id"))
	var text := str(director.get("_player_text")).strip_edges()
	if _history_turn < 0:
		_history_turn = turn
	elif turn != _history_turn:
		_history_turn = turn
		if not text.is_empty() and PREFERENCES.apology_intent(text):
			var target: Variant = pony.get("conversation_target")
			var body: Variant = main.player_body()
			if target == main.player or target == body:
				if ACT_HISTORY.apology_repair(ACT_HISTORY.section(), _id,
						ACT_HISTORY.day_now()):
					ACT_HISTORY.save()
					if is_instance_valid(main.game):
						MEMORY.history_apology(main.game, _id, text)
					_log("history apology id=%s" % _id)
	_history_scan_clock += _delta
	if _history_scan_clock < 1.0:
		return
	_history_scan_clock = 0.0
	if now - _history_reminder_at < 15.0 or _speech_busy():
		return
	if str(director.get("state")) != "idle":
		return
	if main.player.global_position.distance_to(pony.global_position) > 5.0:
		return
	var row := _history_row()
	var kind := ACT_HISTORY.pending_line(row)
	if kind.is_empty():
		return
	if Time.get_unix_time_from_system() - float(row.get("last_at", 0.0)) < 45.0:
		return
	var event_id := "history_%s_%d" % [_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state == State.IDLE
	var key := MEMORY.reaction_for(main.game, _id, "history_" + kind, event_id,
		ACT_HISTORY.line_purpose(row, kind), valid)
	if key.is_empty():
		return
	ACT_HISTORY.mark_announced(ACT_HISTORY.section(), _id, kind)
	ACT_HISTORY.save()
	_history_reminder_at = now
	_log("history line kind=%s key=%s" % [kind, key])


func _tolerance_controller():
	if _tolerance == null:
		_tolerance = ACT_TOLERANCE.new()
	return _tolerance


## The meter only advances during an act. A forced debug warning or stop runs here so it lands
## on the next frame after the Debug panel is closed.
func _tolerance_tick(_delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE]:
		return
	if not _debug_forced_tolerance.is_empty():
		var action := _debug_forced_tolerance
		_debug_forced_tolerance = ""
		if action == "warning":
			_tolerance_warn(1)
		elif action == "stop":
			_stop_with_her("debug")
		return
	_tolerance_controller().tick(_delta)


func _tolerance_event(event: Dictionary) -> void:
	if event.is_empty() or _stopped_by_her:
		return
	var warning := int(event.get("warning", 0))
	if warning > 0:
		_tolerance_warn(warning)
		return
	if bool(event.get("stopped", false)) or bool(event.get("stop", false)):
		_stop_with_her(str(event.get("kind", "")))


func _tolerance_warn(level: int) -> void:
	var cue := "She doesn't like that." if level <= 1 else "She is warning you."
	_set_cue_override(cue, 4.0)
	_queue_tolerance_warning(level)
	_log("neglect warning=%d tier=%s distress=%.1f kind=%s" % [
		level, str(_preferences.get("tolerance", "normal")),
		float(_tolerance_controller().distress), _tolerance_controller().last_dislike])


func _queue_tolerance_warning(level: int) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	if not _tolerance_warning_key.is_empty():
		MEMORY.cancel_line(main.game, _tolerance_warning_key)
	var act_id := _event_id
	var event_id := "%s:tolerance_warning:%d" % [_event_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state in [State.POSING_IN, State.ACTIVE] \
			and _event_id == act_id
	var fallback := "Don't do that." if level <= 1 else "I said stop that."
	_tolerance_warning_key = MEMORY.reaction_for(main.game, _id, "tolerance_warning",
		event_id, fallback, valid)


func _cancel_tolerance_warning() -> void:
	if not _tolerance_warning_key.is_empty() and is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.cancel_line(main.game, _tolerance_warning_key)
	_tolerance_warning_key = ""


## A real consent stop. It ends the act without the normal afterglow/cuddle restore, commits a
## severe bad summary, and only Strict additionally bucks and requests space.
func _stop_with_her(reason: String) -> void:
	if _stopped_by_her or state not in [State.POSING_IN, State.ACTIVE]:
		return
	_stopped_by_her = true
	var strict := str(_preferences.get("tolerance", "normal")) == "strict"
	_cancel_tolerance_warning()
	_commit_summary(false)
	# The stopped summary already says why. The basic event is the fallback when no summary was
	# written (features.act_history off), so one partner stop is never two memories.
	if _summary.is_empty() and is_instance_valid(main) and is_instance_valid(main.game):
		MEMORY.stop_event(main.game, _id, _display_name, _event_id, "withdrew")
	if pose_id == CATALOG.MISSIONARY:
		REST.release_managed(pony)
	_end_act_lines(true)
	_end_session(false)
	_finalize_session(true)
	if strict:
		_request_space()
		_buck_or_push()
	# The summary owns the impression, including features.act_history off and a skipped summary.
	if not _summary.is_empty():
		_start_upset("angry" if strict else "annoyed")
	_queue_stop_line(strict)
	_log("stop withdrew tier=%s distress=%.1f reason=%s strict=%s" % [
		str(_preferences.get("tolerance", "normal")), float(_tolerance_controller().distress),
		reason, str(strict)])


func _request_space() -> void:
	if not is_instance_valid(pony):
		return
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel):
		return
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("request_space"):
		bonds.call("request_space", _id)


func _queue_stop_line(strict: bool) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	var fallback := "Stop. I don't want to continue. Not now."
	if strict:
		fallback = "I told you to stop. Get off me and give me space."
	var event_id := "tolerance_stop_%s_%d" % [_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state == State.IDLE
	MEMORY.reaction_for(main.game, _id, "tolerance_stop", event_id, fallback, valid)


func _start_tail_tuck() -> void:
	_end_tail_tuck()
	if not is_inside_tree() or not is_instance_valid(pony):
		return
	var tuck: Node = TAIL_TUCK.new()
	tuck.name = "UnfplapTailTuck"
	tuck.set("pony", pony)
	tuck.set("runtime", self)
	add_child(tuck)
	_tail_tuck = tuck


func _end_tail_tuck() -> void:
	if is_instance_valid(_tail_tuck):
		_tail_tuck.queue_free()
	_tail_tuck = null


## Debug actions run from the paused settings page; the request is consumed on the next frame.
func debug_force_tolerance(kind: String) -> bool:
	if state not in [State.POSING_IN, State.ACTIVE]:
		return false
	_debug_forced_tolerance = kind
	return true


## Store the strongest clean act per mare. The exchange is the useful part: a later cue can
## infer that she liked it without any name-specific instruction.
func _record_peak_memory() -> void:
	if _peak_recorded:
		return
	_peak_recorded = true
	if not _summary.is_empty() and not bool(_summary.get("positive", false)):
		return
	if not RELATIONSHIP_CUE.peak_eligible(_peak_satisfaction, _act_both_matches, _act_dislikes):
		return
	var player := _last_player_talk.strip_edges()
	var her := ""
	if _last_spoken_at() > _act_spoken_at:
		her = _last_spoken_line()
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

## The runtime-patched rig coat is no longer the exact game Shader, so FlankTouch's
## JIGGLE_SHADERS check skips it. Put the coat and its outline back into the active target list.
## `_start_jiggle()` rebuilds the list on every slap, so this runs for each thrust and act smack.
func _attach_body_coat_jiggle_target() -> void:
	if not SETTINGS.body_coat_deform.get_bool():
		return
	if not is_instance_valid(_flank) and is_instance_valid(pony):
		_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank) or not is_instance_valid(_anatomy):
		return
	if _anatomy.has_method("is_attached") and not bool(_anatomy.call("is_attached")):
		return
	var body: Variant = _anatomy.call("body_coat_mesh")
	var mat: Variant = _anatomy.call("body_coat_material")
	if not is_instance_valid(body) or not body is MeshInstance3D \
			or not is_instance_valid(mat) or not mat is ShaderMaterial:
		# The near mesh can be rebuilt between the anatomy's visibility polls. Catch up now
		# instead of waiting for the next poll and losing a few thrusts of body wobble.
		if _anatomy.has_method("_apply_body_coat"):
			_anatomy.call("_apply_body_coat")
		body = _anatomy.call("body_coat_mesh")
		mat = _anatomy.call("body_coat_material")
	if not is_instance_valid(body) or not body is MeshInstance3D \
			or not is_instance_valid(mat) or not mat is ShaderMaterial:
		return
	var targets: Variant = _flank.get("_jiggle_targets")
	if not targets is Array:
		return
	var materials: Array = [mat]
	var outline: Variant = _anatomy.call("body_outline_material")
	if is_instance_valid(outline) and outline is ShaderMaterial:
		materials.append(outline)
	for material: Variant in materials:
		var target_mat := material as ShaderMaterial
		if target_mat == null:
			continue
		var present := false
		for target: Variant in targets:
			if target is Array and not (target as Array).is_empty() \
					and (target as Array)[0] == target_mat:
				present = true
				break
		if present:
			continue
		(targets as Array).append([target_mat, body])


func _thrust_jiggle(weight: float) -> void:
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
			at = (a + b) * 0.5 + Vector3.UP * _jiggle_center_height_m \
				+ back * _jiggle_center_back_m
	var across := Vector3.UP.cross(normal).normalized()
	if across.length_squared() < 0.5:
		across = Vector3.RIGHT
	var decal := mark as Decal
	decal.global_transform = Transform3D(Basis(across, normal, across.cross(normal)).orthonormalized(), at + normal * 0.015)
	decal.visible = false
	# The stock jiggle clamps its own impulse to 0.3..1. Pass a full stroke and scale the
	# resolved amount here, so a soft stroke can wobble almost not at all.
	var wobble := clampf(weight, 0.0, 1.0)
	_flank.call("_start_jiggle", 0, 1.0)
	_attach_body_coat_jiggle_target()
	# One shader center now covers both flanks, so scale the resolved amount up. Smaller ponies
	# get less shader travel from the same thrust impulse.
	var amount: Variant = _flank.get("_jiggle_amount")
	if amount != null:
		_flank.set("_jiggle_amount", float(amount) * wobble * JIGGLE_RUMP_SCALE
			* _jiggle_size_scale() * _jiggle_intensity_scale)
		# `_start_jiggle()` already ran one frame at the stock full amount; refresh it now so
		# the first frame of a soft thrust does not pop.
		if _flank.has_method("_process"):
			_flank.call("_process", 0.0)
	_apply_jiggle_radius()
	if not _jiggle_logged:
		_jiggle_logged = true
		var targets: Variant = _flank.get("_jiggle_targets")
		_log("jiggle rump at=%s root=%s normal=%s targets=%d index=%d mark=%s" % [
			str(at), str(pony.global_position), str(normal),
			(targets as Array).size() if targets is Array else -1,
			int(_flank.get("_jiggle_index")), str(decal.global_position)])

## A smack has already started the native cheek jiggle. Carry it into the same tail-base
## propagation as a thrust.
func _on_smack_impact(strength: float) -> void:
	if not is_instance_valid(pony):
		return
	if is_instance_valid(_flank):
		_attach_body_coat_jiggle_target()
		var amount: Variant = _flank.get("_jiggle_amount")
		if amount != null:
			_flank.set("_jiggle_amount", float(amount) * _jiggle_smack_intensity)
	_apply_jiggle_radius()
	if pose_id == CATALOG.STANDING and is_instance_valid(_tail):
		var tail_strength := _jiggle_size_scale() * _jiggle_smack_intensity
		_tail.call("thrust", tail_strength)


## Set the shared rump wobble radius on every active jiggle target material.
func _apply_jiggle_radius() -> void:
	if not is_instance_valid(_flank):
		return
	var targets: Variant = _flank.get("_jiggle_targets")
	if not targets is Array:
		return
	var radius := _jiggle_radius_m
	for target_v: Variant in targets:
		if not target_v is Array or (target_v as Array).is_empty():
			continue
		var mat_v: Variant = (target_v as Array)[0]
		if not mat_v is ShaderMaterial:
			continue
		var mat := mat_v as ShaderMaterial
		mat.set_shader_parameter("jiggle_radius", radius)
		if not _jiggle_radius_materials.has(mat):
			_jiggle_radius_materials.append(mat)


## Remove the radius override so stock/base-game jiggles use the shader default again.
func _restore_jiggle_radius() -> void:
	for mat_v: Variant in _jiggle_radius_materials:
		if mat_v is ShaderMaterial and is_instance_valid(mat_v):
			(mat_v as ShaderMaterial).set_shader_parameter("jiggle_radius", null)
	_jiggle_radius_materials.clear()



## The base game leaves a redness mark for 18 s after a regular smack. The act has its own
## rump blush and act-smack mark, so clear the stock marks when the act starts. Regular smacks
## outside the act keep their native marks.
func _clear_stock_flank_marks() -> void:
	if not is_instance_valid(pony):
		return
	_flank = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(_flank):
		return
	var marks: Variant = _flank.get("marks")
	if not marks is Array:
		return
	var ages: Variant = _flank.get("ages")
	for i: int in (marks as Array).size():
		var mark: Variant = (marks as Array)[i]
		if mark is Decal:
			(mark as Decal).visible = false
		if ages is Array and i < (ages as Array).size():
			ages[i] = 1000.0
	_log("stock flank marks cleared count=%d" % (marks as Array).size())


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


## Public rump anchor for the standing offer's rear cone.
func rump_anchor() -> Vector3:
	return _rump_point()

func _rump_blush_tick(delta: float) -> void:
	if pose_id != CATALOG.STANDING:
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
		_act_ended_early = true
		_commit_summary(false)
		# The early summary already records this end. Keep the basic event only when history is
		# off or the summary was skipped, so the story never holds the same end twice.
		if _summary.is_empty():
			MEMORY.cancel_event(main.game, _id, _display_name, _event_id)
		# Cancel act lines before restoring, then queue the intentional early-stop reaction.
		_end_act_lines(true)
		_restore_begin()
		if _act_lines_enabled():
			# Half the time she says nothing at all. When she does speak, it is a moment, not a
			# review or a next-time list.
			if randf() >= 0.5:
				var act_id := _event_id
				var expires := _now_s() + _cue_reaction_max_age_s
				var reaction_key := MEMORY.mod_key(act_id, "reply", "end_early")
				var valid := func() -> bool:
					if not is_instance_valid(pony) or _event_id != act_id:
						return false
					if _now_s() <= expires:
						return true
					return MEMORY.line_state(main.game, reaction_key) == "speaking"
				var key := MEMORY.reaction_for(main.game, _id, "end_early", act_id,
					ACT_SUMMARY.early_end_prompt(_summary), valid)
				if not key.is_empty():
					var now := _now_s()
					_utterance_scheduler().note_reaction_queued(now, key, "",
						now + _cue_reaction_max_age_s)
					_log("utterance kind=reaction key=%s" % key)
			# The stopped act gets one post-act beat at most: suppress the later history line
			# for the same act, even when the roll chose silence. A skipped summary must not
			# clear an older act's pending reminder.
			if not _summary.is_empty() \
					and ACT_HISTORY.mark_announced(ACT_HISTORY.section(), _id, "complaint"):
				ACT_HISTORY.save()
	elif state == State.AFTERGLOW:
		end_afterglow()

func end_afterglow() -> void:
	if state == State.AFTERGLOW:
		_log("afterglow end pony=%s" % str(pony.name))
		# integration: if he stayed in, the withdrawal gush is part of the finish.
		if is_instance_valid(_anatomy_act):
			_anatomy_act.call("withdraw")
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
	cue = "She is climaxing."
	_set_cue_override("She is climaxing.", CLIMAX_SECONDS)
	_schedule_climax_hearts()
	_climax_hearts_burst_at(_dock_point())
	_set_face(0.3, CLIMAX_LIDS)
	_end_act_lines(true)
	if is_instance_valid(main) and pony_climaxes == 1:
		MEMORY.climax_event(main.game, _id, _display_name, _event_id)
	_queue_climax_reaction()
	_play_climax()
	# integration: her fluid hook.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("on_climax")
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
	if not is_instance_valid(main) or not _act_lines_enabled():
		return
	var act_id := _event_id
	var count := pony_climaxes
	var climax_id := "%s:pony_climax:%d" % [act_id, count]
	var expires := _now_s() + _cue_reaction_max_age_s
	var reaction_key := MEMORY.mod_key(climax_id, "reply", "climax")
	var valid := func() -> bool:
		if not is_instance_valid(pony) or _event_id != act_id or pony_climaxes != count:
			return false
		if _now_s() <= expires:
			return true
		return MEMORY.line_state(main.game, reaction_key) == "speaking"
	var key := MEMORY.reaction_for(main.game, _id, "climax", climax_id,
		"You have just climaxed during intimacy with Anon. Say one short sentence, at most 12 words, in your own voice. Staying quiet is fine. Do not describe anatomy.",
		valid)
	if key.is_empty():
		return
	var now := _now_s()
	_utterance_scheduler().note_reaction_queued(now, key, cue,
		now + _cue_reaction_max_age_s)
	_log("utterance kind=reaction key=%s" % key)

## The pony climax ends on its own. It returns to ACTIVE unless the configured limit was
## reached; afterglow is the player's choice, not the climax state's automatic exit.
func _finish_climax() -> void:
	if _max_pony_climaxes > 0 and pony_climaxes >= _max_pony_climaxes:
		_enter_afterglow()
		return
	state = State.ACTIVE
	_set_face(0.45, ACT_LIDS)
	satisfaction = 0.0
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
	var limit_text := "∞" if _max_pony_climaxes <= 0 else str(_max_pony_climaxes)
	_log("pony climax end=%d/%s readiness=0" % [pony_climaxes, limit_text])

## Estrus phase. Derived from the world day and her id; the debug override wins even when the
## feature is off so the lab can test heat and diestrus without waiting in-game days.
func cycle_phase() -> String:
	if not _cycle_override.is_empty():
		return _cycle_override
	if not SETTINGS.estrus_cycle.get_bool():
		return CYCLE.NORMAL
	if not is_instance_valid(pony) or not _read_id():
		return CYCLE.NORMAL
	var relationship: Variant = pony.get_meta("relationship_runtime")
	if relationship == null or not is_instance_valid(relationship):
		return CYCLE.NORMAL
	var bonds: Variant = relationship.get("bonds")
	if bonds == null or not is_instance_valid(bonds) or not bonds.has_method("day"):
		return CYCLE.NORMAL
	return CYCLE.phase(float(bonds.call("day")), _id)


## Debug-only session override: heat, diestrus, normal, or "" to resume the automatic cycle.
func set_cycle_override(phase_name: String) -> void:
	if phase_name in [CYCLE.HEAT, CYCLE.DIESTRUS, CYCLE.NORMAL]:
		_cycle_override = phase_name
	elif phase_name.is_empty():
		_cycle_override = ""


## Private heat/diestrus note for the normal dialogue prompt, outside and during acts.
func cycle_note() -> String:
	if not is_instance_valid(pony) or not _stage_ok():
		return ""
	return CYCLE.prompt_note(cycle_phase())


## Short private relationship facts for normal dialogue. Empty outside a relationship runtime.
func _relationship_note() -> String:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return ""
	return RELATIONSHIP_CUE.note(MEMORY.cue_facts(main.game, _id, _event_id))


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	var history := _history_note()
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		if is_instance_valid(_satisfied):
			var warm := "- You are still warm and relaxed after making love with Anon. Keep an affectionate tone; do not act stiff or businesslike."
			var relation := _relationship_note()
			if not relation.is_empty():
				warm += " " + relation
			return warm
		return history
	var parts: PackedStringArray = []
	if state == State.AFTERGLOW:
		parts.append("- You are still in the afterglow with Anon; the act has ended, but the moment is not finished yet.")
		if not _afterglow_beat.is_empty():
			parts.append("- " + _afterglow_beat)
	else:
		parts.append("- You are in the middle of sex with Anon.")
		if not history.is_empty():
			parts.append(history)
	var relation := _relationship_note()
	if not relation.is_empty():
		parts.append("- " + relation)
	var caressing := _player_is_caressing()
	var leaning := _player_is_leaning_close()
	var where := "your chest and belly" if pose_id == CATALOG.MISSIONARY else "your flank"
	if caressing and leaning:
		parts.append("He is leaning in close against you and caressing " + where + ".")
	elif caressing:
		parts.append("He is caressing " + where + ".")
	elif leaning:
		parts.append("He is leaning in close, holding you.")
	else:
		parts.append("He is close but not caressing or leaning in right now.")
	if state == State.AFTERGLOW:
		parts.append("If Anon asks to stay longer, use [stay: 120] to hold the afterglow.")
	return " ".join(parts)


## Lover-bond context for the normal dialogue prompt. Empty during an act, where prompt_note
## owns the line.
func lover_prompt_note() -> String:
	if not is_instance_valid(pony) or pony.sleeping:
		return ""
	if not _stage_ok():
		return ""
	var bonded := _stored_sex_bond()
	if not bonded and not _try_luck() and not _relationship_ok():
		return ""
	return RELATIONSHIP_CUE.lover_note(bonded)

## Grant the mod lover bond. Dialogue_consent calls this after a clear spoken agreement; the
## Debug action calls it for the aimed mare. Every gate is re-checked here because the classifier
## can answer while the world has moved on.
func grant_sex_bond(source := "dialogue", line := "") -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or pony.sleeping:
		return false
	if not _stage_ok() or not _player_form_ok() or not _relationship_ok():
		return false
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return false
	var record: Dictionary = runtime.bonds.record_for(_id)
	var stage := str(record.get("stage", ""))
	if _stored_sex_bond():
		return true
	var ladder: Dictionary = runtime.ladder(_id)
	var love: Dictionary = ladder.get("love", {})
	var section: Dictionary = SEX_BOND.section()
	if not SEX_BOND.grant(section, _id, stage, int(love.get("level", -1)), source, line):
		return false
	SEX_BOND.save()
	_record_sex_bond_event("You and Anon became lovers.")
	_log("lover bond granted id=%s stage=%s source=%s" % [_id, stage, source])
	return true

## Clear the mod lover bond after a spoken withdrawal or from the Debug action. A break-up is
## handled by refresh_sex_bond().
func end_sex_bond(source := "dialogue", _line := "") -> bool:
	if not _read_id():
		return false
	var section: Dictionary = SEX_BOND.section()
	if not SEX_BOND.bonded(section, _id):
		return false
	if not SEX_BOND.clear(section, _id, source):
		return false
	SEX_BOND.save()
	_record_sex_bond_event("You and Anon are no longer lovers.")
	_log("lover bond ended id=%s source=%s" % [_id, source])
	return true

## Clear a stored bond once the base relationship has left the romantic stages. The gate already
## rejects it; this prevents it from reviving if they date again later.
func refresh_sex_bond() -> void:
	if not _read_id():
		return
	var section: Dictionary = SEX_BOND.section()
	if not SEX_BOND.bonded(section, _id):
		return
	var runtime: Variant = pony.get_meta("relationship_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return
	var row: Dictionary = SEX_BOND.row(section, _id)
	var stored_stage := str(row.get("stage", ""))
	var record: Dictionary = runtime.bonds.record_for(_id)
	var live_stage := str(record.get("stage", ""))
	if SEX_BOND.romantic_stage(live_stage):
		# A Crush bond can become a dating bond later; keep the stored stage current so a
		# break-up still clears it.
		if stored_stage != live_stage and SEX_BOND.set_stage(section, _id, live_stage):
			SEX_BOND.save()
		return
	# A bond made at Crush or Any Adult has no romantic stage to leave. A bond made while
	# dating/engaged/married is cleared by a break-up.
	if not SEX_BOND.romantic_stage(stored_stage):
		return
	if SEX_BOND.clear(section, _id, "stage=" + live_stage):
		SEX_BOND.save()
		_log("lover bond cleared id=%s stage=%s" % [_id, live_stage])

func _record_sex_bond_event(text: String) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	var ctx: Variant = main.game.get("world_context")
	if ctx == null or not is_instance_valid(ctx) or not ctx.has_method("record"):
		return
	ctx.call("record", "relationship", text, [_id, "player"], [_id, "player"],
		"unfplap:sex_bond:%s:%d" % [_id, Time.get_ticks_usec()])

func _player_is_caressing() -> bool:
	return _caress_controller().any_active()

func _player_is_leaning_close() -> bool:
	return _lean_forward >= 0.35 or _lean_action_active or _kiss_controller().leaning_close()

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
	_afterglow_begin()
	_wings_controller().begin_afterglow()

func _commit_afterglow() -> void:
	if not is_instance_valid(main):
		return
	_commit_summary(true)
	_record_peak_memory()
	for row: Variant in WITNESS.commit(main.game, _id, _display_name, _serial, pony):
		_log("witness " + str(row))

## Both poses share the held afterglow; standing adds the close window and a slightly lifted
## tail.
func _afterglow_begin() -> void:
	_log("afterglow pose=%s pony=%s" % [pose_id, str(pony.name)])
	_stop_auto_thrust()
	_end_act_lines(true)
	# Missionary afterglow keeps only lean and caress; standing keeps its kiss.
	if pose_id != CATALOG.STANDING:
		_kiss_controller().end_lean_kiss()
	# integration: decide and show the finish before the summary is written.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("on_finish")
	_commit_afterglow()
	_afterglow_beat = ACT_SUMMARY.afterglow_beat(_summary, randf())
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
		if pose_id == CATALOG.STANDING:
			_pose.mode = "standing"
		else:
			_pose.mode = "afterglow"
			_pose.afterglow_pose = pose_id
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if is_instance_valid(_tail):
		if pose_id == CATALOG.STANDING:
			_tail.target_amount = 0.55
			_tail.call("flick", 2)
		else:
			_tail.target_amount = 0.35
	if pose_id == CATALOG.STANDING:
		_begin_close_window()
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")

## Standing afterglow only. The HUD and this timer own the stay-close invitation; normal dialogue
## resumes instead of a scripted stay-close line.
func _begin_close_window() -> void:
	if pose_id != CATALOG.STANDING:
		return
	_close_left = STAY_CLOSE_SECONDS
	_close_caress_seconds = 0.0
	_close_rewarded = false
	_close_caress_earned = false
	cue = ""
	_cue_override = ""
	_cue_until = 0.0

func _afterglow_tick(delta: float) -> void:
	if state != State.AFTERGLOW:
		return
	_afterglow_elapsed += delta
	# integration: keep the optional bed-body part tracking through afterglow.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("afterglow_tick", delta)
	_self_end_tick(delta)
	if state != State.AFTERGLOW or pose_id != CATALOG.STANDING:
		return
	if _close_left <= 0.0:
		return
	if _caress_controller().any_active():
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
	_close_caress_earned = caressed
	var reward := bool(_summary.get("reward", false))
	if is_instance_valid(main):
		MEMORY.stay_close_reward(main.game, _id, _event_id, caressed, reward)
	if not reward and caressed:
		if ACT_HISTORY.repair(ACT_HISTORY.section(), _id, 1, ACT_HISTORY.day_now()):
			ACT_HISTORY.save()
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
	if state != State.AFTERGLOW or pose_id != CATALOG.STANDING:
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
	_stop_auto_thrust()
	_end_act_lines(true)
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	state = State.RESTORE
	# integration: act-only anatomy hides as soon as the act starts restoring.
	if is_instance_valid(_anatomy):
		_anatomy.call("apply_live")
	_restore_left = RESTORE_SECONDS
	_clear_face()
	_wings_controller().release()
	if is_instance_valid(_pose):
		_pose.target_amount = 0.0
	if is_instance_valid(_tail):
		_tail.target_amount = 0.0
	_stop_breath()
	_back_target = 0.0
	_standing_camera_controller().reset_facing()
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.hide_act()

## Give back everything the act borrowed, in the order the pose and camera were built. Every step
## checks its own ownership flag, so a start that failed early runs the same function and restores
## only what it took. Keep this the only exit path. `_end_act_lines()` is deliberately outside:
## `cancel()` queues the early-stop reaction after `_restore_begin()`, and `_finish_restore()` must
## not cut it. The utterance scheduler is start/finalize state, not a session borrow.
func _end_session(rejoin_cuddle: bool) -> void:
	_stop_auto_thrust()
	# integration: close the anatomy act once, before the pose is freed.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("end")
		_anatomy_act.call("teardown")
		_anatomy_act.queue_free()
		_anatomy_act = null
	if is_instance_valid(_missionary_anon):
		_missionary_anon.call("remove")
		_missionary_anon.queue_free()
		_missionary_anon = null
	_stop_vr_act()
	_set_inventory_hud_hidden(false)
	set_request_face(false)
	_kiss_controller().restore_forelegs()
	_restore_face_turn()
	_restore_eye_override()
	if is_instance_valid(pony):
		_clear_face()
		_wings_controller().release()
	_unlock_player()
	if _camera_owned:
		_restore_camera()
	if is_instance_valid(pony):
		pony.remove_meta("sex_active")
	# integration: hide the player part when the act ends.
	if is_instance_valid(main) and main.has_method("anon_encounter"):
		main.call("anon_encounter", false)
	_release_nav()
	if _look_captured:
		_restore_look()
	if _posture_owned:
		_restore_posture(pose_id, rejoin_cuddle)
	_free_pose()
	_restore_pony_bones()
	_stop_audio()
	if is_instance_valid(main):
		if is_instance_valid(main.hud):
			main.hud.hide_all()
		main.clear_active(self)
	state = State.IDLE
	pose_id = ""
	source = ""
	bed = null
	# integration: act-only anatomy hides immediately when the act ends.
	if is_instance_valid(_anatomy):
		_anatomy.call("apply_live")

## One-time bookkeeping after the borrowed state is back. Idempotent: a failed start has no act
## to reset and must not start aftercare.
func _finalize_session(real_act: bool) -> void:
	if _session_finalized:
		return
	_session_finalized = true
	if real_act:
		_reset_after_act()

## Give her back to the game: the missionary bed cuddle on a normal end, or a standing posture.
## A forced stop never rejoins the cuddle; the world is going away or the pony is already invalid.
func _restore_posture(restore_pose: String, rejoin_cuddle: bool) -> void:
	_posture_owned = false
	if not is_instance_valid(pony):
		return
	# The missionary act is its own state with its own scene snapshot. It never rejoins a bed: the
	# snapshot puts the player, the pony and the camera back, and she stands.
	if restore_pose == CATALOG.MISSIONARY:
		_missionary_camera_controller().restore_scene()
	if pony.get("posture") != null:
		pony.request_posture("stand")

func _finish_restore() -> void:
	if is_instance_valid(pony):
		_log("restore finished pony=%s" % str(pony.name))
	else:
		_log("restore finished with invalid pony")
	_end_session(true)
	_finalize_session(true)

func _stand_after_pose() -> void:
	if is_instance_valid(pony) and pony.get("posture") != null:
		pony.request_posture("stand")

func force_stop() -> void:
	# Defensive: every stop path must leave the quick slots in their pre-act state.
	if state == State.IDLE:
		_end_session(false)
		return
	_restore_now()

func _restore_now() -> void:
	_end_act_lines(true)
	_end_session(false)
	_finalize_session(true)

func _reset_after_act() -> void:
	if not is_inside_tree():
		return
	_reset_thrust_state()
	if _satisfaction_tween != null and _satisfaction_tween.is_valid():
		_satisfaction_tween.kill()
	var from := float(satisfaction)
	_satisfaction_tween = create_tween()
	_satisfaction_tween.tween_method(func(value: float) -> void: satisfaction = clampf(value, 0.0, READINESS_MAX), from, 0.0, 30.0)
	if _stopped_by_her:
		_start_tail_tuck()
	else:
		_begin_aftercare()

func _begin_aftercare() -> void:
	if not is_inside_tree() or not is_instance_valid(pony):
		return
	if is_instance_valid(_aftercare):
		return
	var has_summary := not _summary.is_empty()
	var healthy := bool(_summary.get("positive", false)) if has_summary \
		else satisfaction >= _aftercare_min
	var reward := bool(_summary.get("reward", false)) if has_summary \
		else satisfaction >= _aftercare_min
	_aftercare = AFTERCARE.new()
	_aftercare.set("pony", pony)
	_aftercare.set("runtime", self)
	_aftercare.set("body_language", healthy and satisfaction >= _aftercare_min)
	add_child(_aftercare)
	if reward and satisfaction >= _aftercare_min:
		_start_satisfied()

## The emotional grace after a positive act: relaxed face, light blush and a warm prompt note.
## It lasts as long as the game's impression mood stays fresh (satisfied.gd) and never holds
## her navigator or blocks another act.
func _start_satisfied() -> void:
	if not is_inside_tree() or not is_instance_valid(pony):
		return
	if is_instance_valid(_satisfied):
		return
	_satisfied = SATISFIED.new()
	_satisfied.name = "UnfplapSatisfied"
	_satisfied.set("pony", pony)
	_satisfied.set("runtime", self)
	add_child(_satisfied)

func _end_satisfied() -> void:
	if is_instance_valid(_satisfied):
		_satisfied.queue_free()
	_satisfied = null


## A refused advance or a consent stop: hold the hostile face that matches the impression mood.
## It yields to the director's line faces and ends when a newer mood replaces ours (upset.gd).
func _start_upset(mood: String) -> void:
	if not is_inside_tree() or not is_instance_valid(pony):
		return
	_end_satisfied()
	if is_instance_valid(_upset):
		_upset.queue_free()
	_upset = UPSET.new()
	_upset.name = "UnfplapUpset"
	_upset.set("pony", pony)
	_upset.set("runtime", self)
	_upset.set("mood", mood)
	add_child(_upset)


func _end_upset() -> void:
	if is_instance_valid(_upset):
		_upset.queue_free()
	_upset = null

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
		var our_kiss: bool = _kiss_controller().base_active()
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
	return _same_height_scale()

## Anon's chosen height over the 6 ft rig every offset was tuned on (1.0 at default).
func _anon_height_scale() -> float:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("anon_height_scale"):
		return clampf(float(settings.call("anon_height_scale")), 0.6, 1.4)
	return 1.0

## "Same height as Anon" now sizes the pony from Anon's chosen height too. Other presets keep
## their authored sizes, so only this preset's camera/gap offsets follow the setting.
func _same_height_scale() -> float:
	return _anon_height_scale() if _size_name() == "same height" else 1.0

## Absolute hand scale for the current body preset, from the per-size caress setting.
func _palm_scale_factor() -> float:
	var caress: Variant = _presentation_cfg.get("caress", {})
	if caress is Dictionary:
		var scales: Variant = (caress as Dictionary).get("palm_scale", {})
		if scales is Dictionary:
			return float((scales as Dictionary).get(_size_name(), 1.0))
	return 1.0


func _apply_eye_override() -> void:
	_camera_target_eye = 0.0
	# Missionary is owned by the game's bed rest/seat camera. Do not fight it with eye-height edits.
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
	_camera_owned = true
	_camera_basis_ready = false
	_reset_lean_state()
	_standing_anon_controller().reset_phase()
	_missionary_camera_controller().reset_look()
	# The act shows and poses Anon's body itself (desktop human only; AnonPony and VR have their own).
	if pose_id == CATALOG.MISSIONARY and not _player_pony and not _headset_view():
		_missionary_anon = MISSIONARY_ANON.new()
		_missionary_anon.name = "UnfplapMissionaryAnon"
		add_child(_missionary_anon)
		if not bool(_missionary_anon.call("install", self)):
			_missionary_anon.queue_free()
			_missionary_anon = null
	# integration: optional VR standing act; it uses the headset rig and no desktop camera.
	if _headset_view() and not _player_pony and pose_id == CATALOG.STANDING \
			and SETTINGS.anatomy_vr.get_bool():
		_start_vr_act()
	if _player_pony or _headset_view():
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_free_camera_active = true
	_camera = main.camera()
	if pose_id == CATALOG.STANDING and is_instance_valid(_camera):
		_standing_camera_controller().prepare()
		_standing_anon_controller().install()
	_apply_free_camera_lock()

## Lean/caress remain live through the afterglow in both poses. Missionary keeps its passive
## afterglow otherwise: no kiss, reach or close window.
func _act_actions_allowed() -> bool:
	return state in [State.ACTIVE, State.CLIMAX] or state == State.AFTERGLOW

## Q/E drive the side lean; W/S lean forward/back. Q/E add a forward-plus-side diagonal and
## also fire a pose reaction once the smoothed side lean crosses MOTION.LEAN_FIRE.
func _lean_tick(delta: float) -> void:
	_caress_controller().return_tick()
	if not _act_actions_allowed():
		_caress_controller().stop_inputs()
		_end_lean_action()
		_lean_forward = move_toward(_lean_forward, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
		_lean_side = move_toward(_lean_side, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
		_lean_view_forward = _lean_forward
		_lean_view_side = _lean_side
		return
	if not _free_camera_active or _player_pony or _headset_view() or get_tree().paused \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not _lean_block_logged and state in [State.ACTIVE, State.CLIMAX]:
			_lean_block_logged = true
			_log("lean blocked: free=%s pony=%s headset=%s paused=%s mouse=%d" % [
				str(_free_camera_active), str(_player_pony), str(_headset_view()),
				str(get_tree().paused), Input.mouse_mode])
		_caress_controller().stop_inputs()
		_end_lean_action()
		_lean_forward = move_toward(_lean_forward, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
		_lean_side = move_toward(_lean_side, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
		_lean_view_forward = _lean_forward
		_lean_view_side = _lean_side
		return
	if auto_panel_open():
		# Hold-X auto settings: hold the shot exactly where it is. Do not write `_lean_view_*`
		# here: the idle sway leaves it ahead of `_lean_forward`, so copying the base value in
		# snapped the camera by about a sway step. Freezing both values leaves nothing to jump.
		_side_return_armed = false
		_end_lean_action()
		_kiss_controller().lean_kiss_tick()
		var frozen_caress := Time.get_ticks_usec()
		_caress_controller().tick(delta)
		_timed("caress_tick", frozen_caress)
		if pose_id == CATALOG.STANDING:
			_standing_camera_controller().apply_lean_look()
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
	var targets := MOTION.lean_targets(side, forward)
	if targets.y != 0.0:
		_side_return_armed = false
	elif targets.x < 0.0:
		# Pulling back also recentres the shoulder roll instead of leaving it locked until a
		# lean to the other side.
		_side_return_armed = true
	_lean_forward = MOTION.lean_step(_lean_forward, targets.x, delta)
	_lean_side = MOTION.lean_step(_lean_side, targets.y, delta, _side_return_armed)
	if _side_return_armed and is_zero_approx(targets.y) and absf(_lean_side) <= 0.001:
		_side_return_armed = false
	var alpha := 1.0 - exp(-CAMERA_INERTIA_SMOOTH * delta)
	_lean_view_forward = lerpf(_lean_view_forward, _lean_forward, alpha)
	_lean_view_side = lerpf(_lean_view_side, _lean_side, alpha)
	# Idle breathing is a true offset on top of the displayed lean. Adding it into
	# `_lean_view_forward` itself let the smoother amplify it (a forced offset of
	# HOLD_SWAY_FORWARD / (1 - exp(-CAMERA_INERTIA_SMOOTH * delta)), about twelve times the
	# intended amount) so the shot crept when nobody was leaning.
	_lean_sway = 0.0
	_lean_block_logged = false
	if _feature("idle_camera_sway"):
		_hold_rock_clock += delta
		_lean_sway = sin(_hold_rock_clock * 0.80) * MOTION.HOLD_SWAY_FORWARD
	_lean_action_tick()
	# Missionary afterglow keeps lean and caress live but not the kiss; standing afterglow keeps
	# its kiss. `_afterglow_begin()` releases a missionary kiss when the state changes.
	if pose_id == CATALOG.STANDING or state != State.AFTERGLOW:
		_kiss_controller().lean_kiss_tick()
	var caress_started := Time.get_ticks_usec()
	_caress_controller().tick(delta)
	_timed("caress_tick", caress_started)
	if pose_id == CATALOG.STANDING:
		_standing_camera_controller().apply_lean_look()

## The shot's forward lean: the displayed lean plus the idle-breathing offset, applied once.
func shot_lean_forward() -> float:
	return clampf(_lean_view_forward + _lean_sway, -1.0, 1.0)


func _lean_size_scale() -> float:
	return MOTION.lean_size_scale_for(_size_scale())

## Canon needs a little less travel in the standing pose than the other presets.
func _standing_lean_scale() -> float:
	var scale := _lean_size_scale()
	if _size_name() == "canon":
		scale *= 0.8
	return scale

## Standing torso angle: hinge Anon's upper body forward over her by moving the head/camera
## forward and down by the spine arc, then countering the hip in `apply_anon_lean`.
func _anon_torso_angle() -> float:
	return deg_to_rad(float(_presentation_cfg.get("torso_angle_deg", 0.0)))

func _anon_torso_forward() -> float:
	return ANON_TORSO_LEN_M * sin(_anon_torso_angle())

func _anon_torso_drop() -> float:
	return ANON_TORSO_LEN_M * (1.0 - cos(_anon_torso_angle()))

func _jiggle_size_scale() -> float:
	return clampf(_size_scale(), 0.5, 1.2)

func smack() -> void:
	_caress_controller().smack()


func caress_pick_ready() -> bool:
	return _feature("caress_pick") and pose_id == CATALOG.MISSIONARY \
		and _caress_controller().any_active()


func pick_caress_point() -> bool:
	if not caress_pick_ready():
		return false
	return bool(_caress_controller().pick_missionary_anchor())


func clear_caress_picks() -> void:
	_caress_controller().clear_picked_anchors()

func _lean_action_tick() -> void:
	if not _act_actions_allowed():
		_end_lean_action()
		return
	var side := _lean_side
	if not _lean_action_active:
		if absf(side) >= MOTION.LEAN_FIRE:
			_start_lean_action(side)
		return
	if absf(side) <= MOTION.LEAN_RELEASE or signf(side) != signf(_lean_action_side):
		_end_lean_action()
		if absf(side) >= MOTION.LEAN_FIRE:
			_start_lean_action(side)
		return

func _start_lean_action(side: float) -> void:
	_lean_action_active = true
	_lean_action_side = side
	_lean_action_kind = MOTION.lean_action_kind(pose_id, side)
	var shoulder := ""
	if _lean_action_kind == "reach":
		shoulder = "L" if side < 0.0 else "R"
		_forced_glance = shoulder
		_standing_camera_controller().hold_glance()
		_caress_controller().start_reach(shoulder)
	_log("action fire pose=%s side=%.2f kind=%s shoulder=%s" % [
		pose_id, side, _lean_action_kind, shoulder])

func _end_lean_action() -> void:
	if _lean_action_kind == "reach":
		_caress_controller().end_reach()
		_forced_glance = ""
		_standing_camera_controller().clear_glance()
	_lean_action_active = false
	_lean_action_side = 0.0
	_lean_action_kind = ""

func _reset_lean_state() -> void:
	_end_lean_action()
	_caress_controller().reset()
	_kiss_controller().reset()
	_lean_forward = 0.0
	_lean_side = 0.0
	_lean_view_forward = 0.0
	_lean_view_side = 0.0
	_lean_sway = 0.0
	_side_return_armed = false
	_hold_rock_clock = 0.0

func _play_mouth_kiss() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.play_mouth_kiss(_snout())

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

## Which missionary base is in charge and why. One dictionary so the log, the settled line and the
## debug action cannot drift apart.
func pose_base_info() -> Dictionary:
	var authored: Variant = _authored_pose()
	var bones: Variant = authored.get("pony_bones")
	var info := {
		"base": "none",
		"reason": "",
		"version": int(authored.get("version")),
		"bones": (bones as Dictionary).size() if bones is Dictionary else 0,
		"available": bool(authored.get("available")),
		"error": str(authored.get("error")),
		"frame": _bed_pose_frame,
		"shots": bool(authored.get("has_shots")),
		"asset": authored,
	}
	if pose_id != CATALOG.MISSIONARY:
		info["reason"] = "pose=%s" % pose_id
	elif not bool(info["available"]):
		info["reason"] = _authored_pose_reason()
	elif not _bed_pose_frame is Transform3D:
		info["reason"] = "no bed frame"
	else:
		info["base"] = "authored"
	return info


## True when the missionary asset loaded. The act refuses to start otherwise: there is no fallback
## missionary pose any more.
func _authored_pose_ready() -> bool:
	return bool(_authored_pose().get("available"))


## Why the missionary pose asset is unusable, for the gate row and the start log.
func _authored_pose_reason() -> String:
	var authored: Variant = _authored_pose()
	if bool(authored.get("available")):
		return ""
	var why := str(authored.get("error"))
	return "pose_asset: %s" % (why if not why.is_empty() else "not loaded")


## The authored body bones the live rig lacks. The pose writes only the bones it holds, so a missing
## one leaves the game's pose on that link and the chain above it reads broken; the act refuses to
## start. Cached per skeleton instance, because the gate polls every frame.
func _pose_rig_missing() -> Array:
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return []
	var skeleton := sk as Skeleton3D
	var id := skeleton.get_instance_id()
	if _pose_rig_checked and id == _pose_rig_skeleton:
		return _pose_rig_missing_bones
	_pose_rig_checked = true
	_pose_rig_skeleton = id
	var missing: Variant = _authored_pose().call("missing_bones", skeleton)
	_pose_rig_missing_bones = missing if missing is Array else []
	return _pose_rig_missing_bones


## The gate row's reason, naming the first few bones and counting the rest.
func _pose_rig_reason(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var names: PackedStringArray = []
	for i in mini(3, missing.size()):
		names.append(str(missing[i]))
	var text := "pose_rig: missing %s" % ", ".join(names)
	if missing.size() > 3:
		text += " (+%d more)" % (missing.size() - 3)
	return text


## Rig, modifier and posture diagnostics: which skeleton the modifier drives, which skeleton every
## mesh is actually bound to, whether the pose survives between frames, and who else is near the bed.
## One idle-frame sample of what the renderer actually sees, once per act.
## The missionary act owns what is rendered: the game re-poses the rig after our modifier pass, so
## the authored pose is written once more here, after every physics and process writer of the frame.
## See ROTATION.md.
func _pose_render_write() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return
	# Park the game's desktop presentation (it re-enables itself) and then place and pose the act's
	# own Anon body over it, before her pose writes last.
	_missionary_camera_controller().hide_avatar()
	var frame: Variant = _bed_pose_frame
	if is_instance_valid(_missionary_anon) and frame is Transform3D:
		_missionary_anon.call("apply", frame, _body_scale_value())
	var sk: Variant = pony.get("skeleton")
	if is_instance_valid(_pose) and sk is Skeleton3D:
		_pose.call("apply_render", sk)
	# The eye camera reads his posed head, so it has to run after this write, not from the physics
	# tick where the pose is one frame older.
	if _free_camera_active and str(SETTINGS.camera_mode.get_value()) == "eye":
		_missionary_camera_controller().tick()


## Render-time placement trace, two lines per act: printed from idle, after every physics and process
## writer, so it reads the pose the renderer is about to use. `root` is the armature bone the authored
## placement is written to; `wanted` is that pose carried into the live bed frame.
func _pose_idle_sample() -> void:
	if _pose_trace_frames >= 2 or pose_id != CATALOG.MISSIONARY or state == State.IDLE:
		return
	if not is_instance_valid(_pose) or _pose_basis_amount() < 0.9:
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var root := int(_pose.get("diag_root"))
	var hips := skeleton.find_bone("pony_hips")
	var g := skeleton.global_transform
	var render_root := g * skeleton.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var render_hips := g * skeleton.get_bone_global_pose(hips) if hips >= 0 else Transform3D.IDENTITY
	var wanted_root: Transform3D = _pose.get("diag_root_wanted")
	var wanted_hips: Transform3D = _pose.get("diag_hips_wanted")
	var animation: Variant = pony.get("animation")
	var clip := ""
	var playing := false
	if animation is AnimationPlayer:
		clip = (animation as AnimationPlayer).current_animation
		playing = (animation as AnimationPlayer).is_playing()
	_log("pose trace f=%d root=%d:%s asset_root=%d trace=%d mode=%d clip=%s playing=%s G=%s" % [
		_pose_trace_frames, root, str(_pose.get("diag_root_name")), int(_pose.get("diag_asset_root")),
		int(_pose.get("diag_trace")), skeleton.modifier_callback_mode_process, clip, str(playing),
		str(g)])
	_log("pose trace f=%d root start=%s after=%s render=%s wanted=%s d=%.3f/%.3f | hips start=%s render=%s wanted=%s d=%.3f" % [
		_pose_trace_frames, str(_pose.get("diag_root_start")), str(_pose.get("diag_root_after")),
		str(render_root), str(wanted_root),
		render_root.origin.distance_to(wanted_root.origin),
		_transform_angle(render_root, wanted_root),
		str(_pose.get("diag_hips_start")), str(render_hips), str(wanted_hips),
		render_hips.origin.distance_to(wanted_hips.origin)])
	_pose_trace_frames += 1


## Degrees between two transforms' bases, for the trace.
func _transform_angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion()))


func _pose_diagnostics(skeleton: Skeleton3D, info: Dictionary) -> Array:
	var rows: Array = []
	var pose: Variant = _pose
	var parent: Node = pose.get_parent() if is_instance_valid(pose) else null
	rows.append("modifier=%s parent=%s match=%s frames=%d weight=%.2f base=%s readback=%.2f°" % [
		"yes" if is_instance_valid(pose) else "no",
		"%s@%s" % [str(parent.name), str(parent.get_instance_id())] if parent != null else "none",
		"yes" if parent == skeleton else "NO", int(_num(pose.get("diag_frames"))) if is_instance_valid(pose) else 0,
		_num(pose.get("diag_last_weight")) if is_instance_valid(pose) else 0.0,
		str(pose.get("diag_last_base")) if is_instance_valid(pose) else "",
		_num(pose.get("diag_readback_deg")) if is_instance_valid(pose) else 0.0])
	var modifiers: Array[String] = []
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D:
			var active: Variant = child.get("active")
			var influence: Variant = child.get("influence")
			modifiers.append("%s%s%s" % [
				str(child.name),
				(" active=%s" % str(active)) if active != null else "",
				(" inf=%.2f" % float(influence)) if influence is float else ""])
	rows.append("skeleton modifiers=%d [%s]" % [modifiers.size(), ", ".join(modifiers)])
	rows.append("hips write check: after_write=%.2f° readback=%.2f° (%s)" % [
		_num(pose.get("diag_after_write_deg")) if is_instance_valid(pose) else 0.0,
		_num(pose.get("diag_readback_deg")) if is_instance_valid(pose) else 0.0,
		"write lands, survives" if is_instance_valid(pose)
			and _num(pose.get("diag_after_write_deg")) < 1.0
			and _num(pose.get("diag_readback_deg")) < 1.0
		else "write lands, lost by next frame" if is_instance_valid(pose)
			and _num(pose.get("diag_after_write_deg")) < 1.0
		else "write does not land"])
	rows.append("pony_skeleton=%s@%s actor=%s paused=%s visible=%s" % [
		str(skeleton.name), str(skeleton.get_instance_id()), str(pony.global_position),
		str(pony.get("motion_paused")), str(pony.visible)])
	var posture: Variant = pony.get("posture")
	if posture != null:
		rows.append("posture kind=%s requested=%s phase=%s progress=%.2f ready=%s clip=%s refusal=%s" % [
			str(posture.get("kind")), str(posture.get("requested")), str(posture.get("phase")),
			_num(posture.get("progress")), str(posture.get("ready")), str(posture.get("clip")),
			str(posture.get("refusal"))])
	# Every mesh's own skeleton: a mesh bound elsewhere would follow the game's animation instead of
	# the pose modifier.
	var groups: Dictionary = {}
	for node: Node in pony.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var target: Node = mesh.get_node_or_null(mesh.skeleton) if not mesh.skeleton.is_empty() else null
		var id := target.get_instance_id() if target != null else 0
		if not groups.has(id):
			groups[id] = {"count": 0, "sample": str(mesh.name), "visible": false, "target": target}
		var entry: Dictionary = groups[id]
		entry["count"] = int(entry["count"]) + 1
		entry["visible"] = bool(entry["visible"]) or mesh.is_visible_in_tree()
	for id: Variant in groups:
		var entry: Dictionary = groups[id]
		var target: Variant = entry["target"]
		var hips := Vector3.INF
		if target is Skeleton3D:
			var bone := (target as Skeleton3D).find_bone("pony_hips")
			if bone >= 0:
				hips = (target as Skeleton3D).global_transform * (target as Skeleton3D).get_bone_global_pose(bone).origin
		rows.append("mesh_skeleton=%s meshes=%d sample=%s visible=%s hips=%s" % [
			("%s@%s" % [str((target as Node).name), str(id)]) if target is Node else "none",
			int(entry["count"]), str(entry["sample"]), str(entry["visible"]), str(hips)])
	# Live hips pose vs the authored quaternion: proves whether the modifier's write is what lives.
	var authored: Variant = info.get("asset")
	var hips_bone := skeleton.find_bone("pony_hips")
	if hips_bone >= 0 and authored != null:
		var entry: Variant = (authored.get("pony_bones") as Dictionary).get("pony_hips")
		if entry is Dictionary:
			var wanted: Quaternion = (entry as Dictionary)["rotation"]
			var live := skeleton.get_bone_pose_rotation(hips_bone)
			rows.append("hips_pose live=%s authored=%s delta=%.1f°" % [
				str(live), str(wanted), rad_to_deg(live.angle_to(wanted))])
	# Nearby ponies, so a body on the bed can be identified as someone else.
	var nearest: Array = []
	for node: Node in get_tree().get_nodes_in_group("ai_characters"):
		var other := node as Node3D
		if other == null or other == pony:
			continue
		var distance := other.global_position.distance_to(pony.global_position)
		if distance > 4.0:
			continue
		var other_sk: Variant = other.get("skeleton")
		var hips_at := Vector3.INF
		if other_sk is Skeleton3D:
			var b := (other_sk as Skeleton3D).find_bone("pony_hips")
			if b >= 0:
				hips_at = (other_sk as Skeleton3D).global_transform * (other_sk as Skeleton3D).get_bone_global_pose(b).origin
		nearest.append("%s d=%.1f posture=%s hips=%s" % [
			str(other.name), distance,
			str(other.call("posture_status").get("requested", "?")), str(hips_at)])
	rows.append("nearby=%d %s" % [nearest.size(), "; ".join(nearest)])
	return rows


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
func pose_state_rows() -> Array:
	var info := pose_base_info()
	var frame: Variant = info["frame"]
	var rows: Array = []
	rows.append("pony=%s pose=%s state=%d weight=%.2f" % [
		str(pony.name) if is_instance_valid(pony) else "?", pose_id, state, _pose_basis_amount()])
	rows.append("base=%s reason=%s asset=v%d %s bones=%d missing=%s shots=%s error=%s" % [
		str(info["base"]), str(info["reason"]),
		int(info["version"]), "ok" if bool(info["available"]) else "error", int(info["bones"]),
		str(_pose_rig_missing()), "yes" if bool(info["shots"]) else "no", str(info["error"])])
	rows.append("bed_frame=%s scale=%.2f" % [
		str(frame) if frame is Transform3D else "null", _body_scale_value()])
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return rows
	var skeleton := sk as Skeleton3D
	rows.append_array(_pose_diagnostics(skeleton, info))
	var space := Transform3D.IDENTITY
	if frame is Transform3D:
		space = (frame as Transform3D).affine_inverse()
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["neck_mid", "pony_neck2"],
			["head", "pony_head"], ["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		rows.append("%s world=(%.3f,%.3f,%.3f) bed=(%.3f,%.3f,%.3f)" % [
			str(pair[0]), world.x, world.y, world.z, bed.x, bed.y, bed.z])
	return rows


## The base line written once when the act builds its pose.
func _log_pose_base() -> void:
	if pose_id != CATALOG.MISSIONARY:
		return
	var info := pose_base_info()
	var frame: Variant = info["frame"]
	var missing := _pose_rig_missing()
	_log("missionary base=%s reason=%s asset=v%d %s bones=%d missing=%d shots=%s frame=%s scale=%.2f" % [
		str(info["base"]), str(info["reason"]), int(info["version"]),
		"ok" if bool(info["available"]) else "error", int(info["bones"]),
		missing.size(), "yes" if bool(info["shots"]) else "no",
		str(frame) if frame is Transform3D else "null", _body_scale_value()])
	if not missing.is_empty():
		_log("missionary rig %s" % _pose_rig_reason(missing))


## One line with where the pose actually put her, in world and bed space, once the weight settles.
func _log_pose_settled() -> void:
	if _pose_logged or pose_id != CATALOG.MISSIONARY or state == State.IDLE:
		return
	if _pose_basis_amount() < 0.9:
		return
	_pose_logged = true
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var frame: Variant = _bed_pose_frame
	var space := Transform3D.IDENTITY
	if frame is Transform3D:
		space = (frame as Transform3D).affine_inverse()
	var parts: Array[String] = []
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["head", "pony_head"],
			["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		parts.append("%s=w%s/b(%.3f,%.3f,%.3f)" % [
			str(pair[0]), str(world), bed.x, bed.y, bed.z])
	_log("missionary settled base=%s weight=%.2f %s" % [
		str(pose_base_info()["base"]), _pose_basis_amount(), " ".join(parts)])
	for row: Variant in _pose_diagnostics(skeleton, pose_base_info()):
		_log("missionary diag %s" % str(row))
	if is_instance_valid(_missionary_anon):
		_log("anon diag %s" % str(_missionary_anon.call("diag_row",
			missionary_face_point(), missionary_vulva_point())))


## Numeric read of a Variant property without tripping over a missing one.
func _num(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback


## Her face, for the start shot: the head bone pushed a little along the neck → head direction, so
## the aim lands where the OpenPony face hangs.
func missionary_face_point() -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return Vector3.INF
	var skeleton := sk as Skeleton3D
	var head := skeleton.find_bone("pony_head")
	if head < 0:
		return _neck_midpoint()
	var at := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	var neck := skeleton.find_bone("pony_neck2")
	if neck < 0:
		return at
	var base := skeleton.global_transform * skeleton.get_bone_global_pose(neck).origin
	var direction := at - base
	if direction.length_squared() < 0.000001:
		return at
	return at + direction.normalized() * 0.12 * _body_scale_value()


## The pulled-back shot's target: the vulva when the anatomy is showing, otherwise a point between
## her hind femurs lifted toward her belly.
func missionary_vulva_point() -> Vector3:
	if is_instance_valid(_anatomy_act):
		var point: Variant = _anatomy_act.call("hole_point")
		if point is Vector3 and (point as Vector3).is_finite():
			return point
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return Vector3.INF
	var skeleton := sk as Skeleton3D
	var left := skeleton.find_bone("pony_femur_L")
	var right := skeleton.find_bone("pony_femur_R")
	if left < 0 or right < 0:
		return _neck_midpoint()
	var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
	return (a + b) * 0.5 + Vector3.UP * 0.10 * _body_scale_value()


func _body_scale_value() -> float:
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


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
		_missionary_camera_controller().tick()
		return
	# Debug free look: the stock player camera is the view, so the act camera leaves it alone.
	if free_look_active():
		return
	_standing_camera_controller().tick()

## Shared desktop hand driver for the caress and the standing body wrapper.
func _desktop_pose_driver() -> Node:
	return _standing_anon_controller().driver()

func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_thrust(hip, facing)

func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_lean(hip, facing)

func _pose_basis_amount() -> float:
	return float(_pose.get("amount")) if is_instance_valid(_pose) else 0.0

func _player_eye_height() -> float:
	var body: Variant = main.player if is_instance_valid(main) else null
	if is_instance_valid(body) and body.has_method("eye_height"):
		return float(body.call("eye_height"))
	if is_instance_valid(body) and body.get("_stand_eye") != null:
		return float(body.get("_stand_eye"))
	return 1.6

func _capture_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	_restore_yaw = float(main.player.rotation.y)
	var pitch: Variant = main.player.get("_pitch")
	_restore_pitch = float(pitch) if pitch != null else 0.0
	_look_yaw = _restore_yaw
	_look_pitch = _restore_pitch
	_look_captured = true

## Restore the player's yaw/pitch captured at act start. Missionary restores exactly; standing
## leaves Anon facing where the act left him, because snapping the pre-act view back looks worse.
## The lean/caress/kiss state is reset either way.
func _restore_look() -> void:
	if not _look_captured:
		return
	_look_captured = false
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var yaw := _restore_yaw
	if _look_restore_yaw:
		# Missionary restores the exact start snapshot; use its rig yaw rather than the later
		# capture.
		if pose_id == CATALOG.MISSIONARY:
			var saved_yaw: float = _missionary_camera_controller().snapshot_yaw()
			if not is_nan(saved_yaw):
				yaw = saved_yaw
		main.player.rotation.y = yaw
		if main.player.get("_pitch") != null:
			main.player.set("_pitch", _restore_pitch)
		if main.player.get("form_driver") == null:
			var view: Camera3D = main.camera()
			if is_instance_valid(view):
				view.rotation.x = _restore_pitch
				view.rotation.z = 0.0
	_reset_lean_state()
	_log("look restored yaw=%.3f (captured %.3f) pitch=%.3f restore=%s" % [
		yaw, _restore_yaw, _restore_pitch, str(_look_restore_yaw)])

func _restore_camera() -> void:
	if not _camera_owned:
		return
	_camera_owned = false
	_end_lean_action()
	_caress_controller().reset()
	_release_free_camera_lock()
	_standing_anon_controller().remove()
	_restore_eye_override()
	_missionary_camera_controller().release()
	_standing_camera_controller().restore()
	_bob = 0.0
	_bob_velocity = 0.0
	_lean = 0.0
	_lean_velocity = 0.0
	_standing_anon_controller().reset_phase()
	_back = 0.0
	_back_target = 0.0
	_camera_basis_ready = false
	_camera = null

# --------------------------------------------------------------------------- audio

## Create the audio node on first use, or update its optional layers if it already exists.
func _ensure_act_audio(vocals: bool, climax: bool) -> void:
	if is_instance_valid(_act_audio):
		_act_audio.set_enabled(vocals, climax)
		return
	var audio_script: Script = load(ACT_AUDIO_PATH)
	if audio_script == null:
		return
	_act_audio = audio_script.new()
	_act_audio.name = "UnfplapActAudio"
	add_child(_act_audio)
	_act_audio.setup(vocals, climax)

func _start_audio() -> void:
	_stop_audio()
	_bed_soft = is_instance_valid(bed) \
		and ("couch" in bed.name.to_lower() or "sofa" in bed.name.to_lower()
			or "cloth" in bed.name.to_lower())
	var vocals := _feature("act_vocals")
	var climax := _feature("act_climax")
	_ensure_act_audio(vocals, climax)
	_sounds_controller().start()

func _stop_audio() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.stop()
		_act_audio.queue_free()
		_act_audio = null
	if _sounds != null:
		_sounds.stop()

func _stop_breath() -> void:
	if _sounds != null:
		_sounds.stop_breath()

func _play_climax() -> void:
	_sounds_controller().play_climax(_snout())
	if is_instance_valid(_act_audio):
		_act_audio.play_climax_wet(_dock_point())
		_act_audio.play_climax_voice(_snout())

func _breath_tick(delta: float) -> void:
	var phase := ""
	if state == State.ACTIVE:
		phase = "active"
	elif state == State.CLIMAX:
		phase = "climax"
	elif state == State.AFTERGLOW:
		phase = "afterglow"
	_sounds_controller().breath_tick(delta, phase, _thrusts_per_second(), _snout())

func _thrusts_per_second() -> float:
	var now := _now_s()
	while not _thrust_times.is_empty() and now - float(_thrust_times[0]) > 1.0:
		_thrust_times.pop_front()
	return float(_thrust_times.size())

func _bed_audio_point() -> Vector3:
	if is_instance_valid(bed):
		return bed.global_position + Vector3.UP * 0.35
	return _rump_point()

func _snout() -> Vector3:
	var boop: Variant = pony.get("boop_node")
	if is_instance_valid(boop) and boop.has_method("nose_world"):
		return boop.call("nose_world")
	return pony.global_position + Vector3.UP * 1.0

## The kiss foreleg overrides are global AffectionPose settings. Restore them if the world
## closes or the mod is switched off mid-kiss.
func _exit_tree() -> void:
	_kiss_controller().restore_forelegs()
	_end_tail_tuck()
	# integration: never leave the anatomy nodes or the per-act controller behind.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("end")
		_anatomy_act.call("teardown")
		_anatomy_act.queue_free()
		_anatomy_act = null
	if is_instance_valid(_missionary_anon):
		_missionary_anon.call("remove")
		_missionary_anon.queue_free()
		_missionary_anon = null
	_stop_vr_act()
	if is_instance_valid(_anatomy):
		_anatomy.call("detach")
		_anatomy.queue_free()
		_anatomy = null
	if is_instance_valid(_satisfied):
		_satisfied.queue_free()
		_satisfied = null
	if is_instance_valid(_upset):
		_upset.queue_free()
		_upset = null
