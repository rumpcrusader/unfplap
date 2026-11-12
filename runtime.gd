extends Node
## One per pony. Holds the act state machine and all per-act state. It never edits game files.

const POSE_SESSION := preload("res://mods/unfplap/poses/session.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/act_summary.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const TAIL_TUCK := preload("res://mods/unfplap/tail_tuck.gd")
const REST := preload("res://mods/unfplap/rest_control.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const SEX_BOND := preload("res://mods/unfplap/sex_bond.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const AFTERCARE := preload("res://mods/unfplap/aftercare.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
const THRUST := preload("res://mods/unfplap/thrust.gd")
const AUTO_THRUST := preload("res://mods/unfplap/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/auto_panel.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/utterance_scheduler.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/relationship_cue.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const HANDS := preload("res://mods/unfplap/hand_control.gd")
const KISS := preload("res://mods/unfplap/kiss_control.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/standing_presentation.gd")
const SOUND := preload("res://mods/unfplap/act_sound.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const ANATOMY_FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const ACT_FACTS := preload("res://mods/unfplap/act_facts.gd")
const ACT_LINES := preload("res://mods/unfplap/act_lines.gd")
const READINESS := preload("res://mods/unfplap/readiness.gd")
const HISTORY := preload("res://mods/unfplap/history.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow.gd")
const FACE := preload("res://mods/unfplap/face_session.gd")
const REACTIONS := preload("res://mods/unfplap/act_reactions.gd")
const PERF := preload("res://mods/unfplap/perf.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/missionary_anon.gd")
const VR_ACT := preload("res://mods/unfplap/vr_act.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const COUCH_EXIT := preload("res://world/life/couch/exit_space.gd")
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
const CLIMAX_SECONDS := 5.0
const CLIMAX_BOBS := 2
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## A normal bed missionary end puts Anon back in the bed's rest and invites her into its guest
## seat. The stock snuggle support reads the reclined avatar's hip targets, so the invite waits
## for the recline to settle (the lab waits 1.2 s for the same reason). The window covers the
## 10 s aftercare navigator hold and the bed's own 20 s guest cooldown.
const CUDDLE_REJOIN_SETTLE_S := 1.5
const CUDDLE_REJOIN_RETRY_S := 0.5
const CUDDLE_REJOIN_WINDOW_S := 30.0
## The shaft length used for the depth scale when the anatomy part is not showing, so the mouse
## feel is the same with the anatomy off. Close to the default part's visible length.
const NOMINAL_SHAFT_M := 0.2
## Same hold length the game uses for bridal-carry initiation (interactor KEY_HOLD_SECONDS).
const HOLD_Y_SECONDS := 0.35
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
## The Y hint's `End` shade: one step per climax, capped below full so only the earned
## afterglow caress turns it fully pink.
const Y_END_TINT_MAX := 0.75

## Standing keeps her body facing away but lets her glance back over a shoulder now and then.
## Fade time for the extra head-back glance pose; prevents the head snapping back to low.
## Yaw limit for a look-back glance. Raised 20% from 1.35 so she turns farther over her shoulder.
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
## The act's readiness system; see `readiness.gd`. The public act values below forward to it.
var _readiness: RefCounted = READINESS.new()
## Her arousal/readiness, 0..100. At 100 she climaxes; the player chooses afterglow.
var satisfaction: float:
	get:
		return _readiness.satisfaction
	set(value):
		_readiness.satisfaction = value
## Public for the HUD: mood and a short third-person cue.
var mood: String:
	get:
		return _readiness.mood
	set(value):
		_readiness.mood = value
var cue: String:
	get:
		return _readiness.cue
	set(value):
		_readiness.cue = value

## Public for the HUD/debug: how many pony climaxes this act has had.
var pony_climaxes: int:
	get:
		return _readiness.pony_climaxes
	set(value):
		_readiness.pony_climaxes = value
## Public: penetration 0..1 and the same orientation flag used by mouse input.
var depth := 0.0
## Public: how far the tip has passed her lips, in metres. Negative is the `back_out` standoff
## behind them, and the depth stays at zero for all of it.
var penetration_m := 0.0
var thrust_up := true

## The act's pose session: the pose modifier, the authored missionary base, the bed frame, the
## extra modifiers, the bone snapshots and the pose diagnostics. See `poses/session.gd`.
var _pose_session: RefCounted = POSE_SESSION.new()
## The live pose modifier. The session owns it; presentation modules still write its look and
## afterglow fields through this read view.
var _pose: Variant:
	get:
		return _pose_session.pose()
## Bed space of the hand-authored missionary base pose for this act (`null` for other poses).
## The pose session owns it; this is the read view presentation modules still poll.
var _bed_pose_frame: Variant:
	get:
		return _pose_session.bed_frame
## Free look's own view rotation (the act holds controls_locked, so the stock look is off).
var _free_look_yaw := 0.0
var _free_look_pitch := 0.0
var _free_look_was := false
## integration: persistent anatomy and the current act's anatomy controller.
var _anatomy: Node
var _anatomy_act: Node
## Reused typed context for the per-act and persistent anatomy controllers. The runtime writes
## it; anatomy reads it. No anatomy file reads this runtime node.
var _anatomy_facts: RefCounted = ANATOMY_FACTS.new()
## Reused typed act context. The runtime writes it; the presentation controllers read it instead of
## reaching into this node. See `act_facts.gd`.
var _act_facts: RefCounted = ACT_FACTS.new()
## The act's line system: scheduler, prompt assembly, reactions and the bystander line.
var _act_lines: RefCounted = ACT_LINES.new(_act_facts)
var _act_lines_main: Node
## Debug perf probe: timed chunks report here and one summary prints per window. See `perf.gd`.
var _perf_probe := PERF.new()
var _missionary_anon: Node
var _vr_act: Node
## Idle standing invitation. Kept separate from the act's pose/tail so Y can take over cleanly.
## Idle request face: blush and lids while a private offer is being asked or presented.
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
## The act's afterglow phase: self-end roll, `[stay]` hold and the standing close window.
## See `afterglow.gd` and `docs/afterglow.md`.
var _afterglow: RefCounted = AFTERGLOW.new()
var _afterglow_elapsed: float:
	get:
		return _afterglow.elapsed
	set(value):
		_afterglow.elapsed = value
## One short private afterglow beat, rolled once when afterglow begins. Empty means silence.
var _afterglow_beat: String:
	get:
		return _afterglow.beat
	set(value):
		_afterglow.beat = value
var _afterglow_hold_until: float:
	get:
		return _afterglow.hold_until
	set(value):
		_afterglow.hold_until = value
var _self_end_clock: float:
	get:
		return _afterglow.self_end_clock
	set(value):
		_afterglow.self_end_clock = value
var _close_left: float:
	get:
		return _afterglow.close_left
	set(value):
		_afterglow.close_left = value
var _close_caress_seconds: float:
	get:
		return _afterglow.close_caress_seconds
	set(value):
		_afterglow.close_caress_seconds = value
var _close_rewarded: bool:
	get:
		return _afterglow.close_rewarded
	set(value):
		_afterglow.close_rewarded = value
## True only when the standing close window earned its caress reward.
var _close_caress_earned: bool:
	get:
		return _afterglow.close_caress_earned
	set(value):
		_afterglow.close_caress_earned = value

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
## The live pose config. The pose session owns it; the standing gap, the act view and the tests
## read it here.
var _pose_cfg: Dictionary:
	get:
		return _pose_session.pose_config
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
var _camera_surge := 0.0
var _camera_bob := 0.0
var _last_intensity: String:
	get:
		return _readiness.last_intensity
	set(value):
		_readiness.last_intensity = value
var _last_pattern: String:
	get:
		return _readiness.last_pattern
	set(value):
		_readiness.last_pattern = value
var _stroke_window: Array[Dictionary]:
	get:
		return _readiness.stroke_window
	set(value):
		_readiness.stroke_window = value
var _last_stroke_at: float:
	get:
		return _readiness.last_stroke_at
	set(value):
		_readiness.last_stroke_at = value
var _overwhelmed: float:
	get:
		return _readiness.overwhelmed
	set(value):
		_readiness.overwhelmed = value
var _cue_override: String:
	get:
		return _readiness.cue_override
	set(value):
		_readiness.cue_override = value
var _cue_until: float:
	get:
		return _readiness.cue_until
	set(value):
		_readiness.cue_until = value
var _last_touch: String:
	get:
		return _readiness.last_touch
	set(value):
		_readiness.last_touch = value
var _last_talk: String:
	get:
		return _readiness.last_talk
	set(value):
		_readiness.last_talk = value
var _last_touch_at: float:
	get:
		return _readiness.last_touch_at
	set(value):
		_readiness.last_touch_at = value
var _last_thrust_score_at: float:
	get:
		return _readiness.last_thrust_score_at
	set(value):
		_readiness.last_thrust_score_at = value
var _receptive_until: float:
	get:
		return _readiness.receptive_until
	set(value):
		_readiness.receptive_until = value
var _last_talk_at: float:
	get:
		return _readiness.last_talk_at
	set(value):
		_readiness.last_talk_at = value
var _last_talk_turn: int:
	get:
		return _readiness.last_talk_turn
	set(value):
		_readiness.last_talk_turn = value
var _peak_satisfaction: float:
	get:
		return _readiness.peak_satisfaction
	set(value):
		_readiness.peak_satisfaction = value
var _act_both_matches: int:
	get:
		return _readiness.act_both_matches
	set(value):
		_readiness.act_both_matches = value
var _act_dislikes: int:
	get:
		return _readiness.act_dislikes
	set(value):
		_readiness.act_dislikes = value
var _act_liked_touch: int:
	get:
		return _readiness.act_liked_touch
	set(value):
		_readiness.act_liked_touch = value
var _act_liked_talk: int:
	get:
		return _readiness.act_liked_talk
	set(value):
		_readiness.act_liked_talk = value
var _last_player_talk: String:
	get:
		return _readiness.last_player_talk
	set(value):
		_readiness.last_player_talk = value
var _act_touch_counts: Dictionary:
	get:
		return _readiness.act_touch_counts
	set(value):
		_readiness.act_touch_counts = value
var _act_touch_dislikes: Dictionary:
	get:
		return _readiness.act_touch_dislikes
	set(value):
		_readiness.act_touch_dislikes = value
var _act_talk_dislikes: int:
	get:
		return _readiness.act_talk_dislikes
	set(value):
		_readiness.act_talk_dislikes = value
var _act_player_lines: int:
	get:
		return _readiness.act_player_lines
	set(value):
		_readiness.act_player_lines = value
var _act_thrusts: int:
	get:
		return _readiness.act_thrusts
	set(value):
		_readiness.act_thrusts = value
var _act_intensity_total: int:
	get:
		return _readiness.act_intensity_total
	set(value):
		_readiness.act_intensity_total = value
var _act_intensity_right: int:
	get:
		return _readiness.act_intensity_right
	set(value):
		_readiness.act_intensity_right = value
var _act_pattern_total: int:
	get:
		return _readiness.act_pattern_total
	set(value):
		_readiness.act_pattern_total = value
var _act_pattern_right: int:
	get:
		return _readiness.act_pattern_right
	set(value):
		_readiness.act_pattern_right = value
var _cue_gap := 12.0
var _vocal_cooldown := 0.0
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
var _act_spoken_at := -1e9
var _act_ended_early := false
## The act's summary, history and tolerance system; see `history.gd`. The act values below forward.
var _history: RefCounted = HISTORY.new()
var _summary: Dictionary:
	get:
		return _history.summary
	set(value):
		_history.summary = value
var _summary_done: bool:
	get:
		return _history.summary_done
	set(value):
		_history.summary_done = value
## Compatibility read for the face suite: the live pure tolerance meter.
var _tolerance:
	get:
		return _history.tolerance
	set(value):
		_history.tolerance = value
var _stopped_by_her := false
var _tolerance_warning_key := ""
var _end_early_key := ""
var _climax_reaction_key := ""
var _tail_tuck: Node
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
## Footstool state for the standing act. See docs/stool.md.
var _stool_active := false
var _stool_lifted := false
var _stool_failed := false
var _stool_tokens: Array[String] = []
var _stool_slots: Array[int] = []
var _stool_count := 0
var _stool_node: Node3D
var _stool_height_m := 0.0
var _stool_floor_y := 0.0
var _wings
var _act_seconds := 0.0
## Processed-time clock. It only advances while the runtime ticks, so a paused tree freezes
## act timing and stroke memory instead of aging them by the pause length.
var _clock_s := 0.0
var _aftercare: Node
## The act's face owner: beats, line-face ownership, the stare release and the post-act mood
## face. See `face_session.gd` and `docs/face.md`.
var _face: RefCounted = FACE.new()
var _mood_face: Node:
	get:
		return _face.mood_face
	set(value):
		_face.mood_face = value
var _warm_note: bool:
	get:
		return _face.warm_note
	set(value):
		_face.warm_note = value
var _act_face: String:
	get:
		return _face.act_face
	set(value):
		_face.act_face = value
var _stare_release_until: float:
	get:
		return _face.stare_release_until
	set(value):
		_face.stare_release_until = value
## Thrust and climax presentation: jiggle, smack reaction, rump blush and hearts. See
## `act_reactions.gd` and `docs/reactions.md`.
var _reactions: RefCounted = REACTIONS.new()
var _first_time := false
var _act_climax_mode := "auto"
var _satisfaction_tween: Tween
## The act's base kiss normally rears and lifts both forelegs; zeroing those two shared
## settings keeps her forehooves planted for the kiss and restores them when it ends.
## The act's stare is released once when a kiss starts so the regular kiss can drive the eyes.
var _act_eyes_released := false
var _face_timer: Timer
var _kisser: Node
var _kisser_processing := false
var _climax_progress := 0.0
## Debug-only head pitch in degrees. Alt+7 raises, Alt+8 lowers; zero outside experimentation.
var _debug_chin_deg := 0.0
var _sounds
var _hands
var _kiss
var _missionary_camera_ctl
var _standing_camera_ctl
var _standing_anon_ctl
var _standing_presentation_ctl
var _act_audio: Node
var _bed_soft := false

func _init() -> void:
	_anatomy_facts.perf_note = Callable(self, "perf_note")
	_anatomy_facts.log = Callable(self, "_log")
	_anatomy_facts.body_coat_smack = Callable(self, "body_coat_jiggle_target")
	_act_facts.perf_note = Callable(self, "perf_note")
	_act_facts.log = Callable(self, "_log")
	_act_facts.body_coat_smack = Callable(self, "body_coat_jiggle_target")
	_act_facts.kiss = Callable(self, "_kiss_controller")
	_act_facts.neck_point = Callable(self, "_neck_midpoint")
	_act_facts.set_look = Callable(self, "_act_set_look")
	_act_facts.set_forced_glance = Callable(self, "_act_set_forced_glance")
	_act_facts.set_camera_basis_ready = Callable(self, "_act_set_camera_basis_ready")
	_act_facts.director = Callable(self, "_director")
	_act_facts.now = Callable(self, "_now_s")
	_readiness.log = Callable(self, "_log")
	_readiness.clock = Callable(self, "_now_s")
	_readiness.state = Callable(self, "_readiness_state")
	_readiness.on_climax = Callable(self, "_climax")
	_readiness.on_close = Callable(self, "_readiness_close")
	_readiness.on_face = Callable(self, "_act_face_beat")
	_readiness.on_anatomy_react = Callable(self, "_readiness_anatomy_react")
	_readiness.tolerance_dislike = Callable(self, "_tolerance_dislike")
	_readiness.tolerance_like = Callable(self, "_tolerance_like")
	_readiness.tolerance_event = Callable(self, "_tolerance_event")
	_readiness.heat_cycle = Callable(self, "_readiness_heat")
	_readiness.on_cue = Callable(self, "_readiness_cue")
	_history.log = Callable(self, "_log")
	_history.reaction_line = Callable(self, "_reaction_line")
	_history.idle = Callable(self, "_history_is_idle")
	_afterglow.log = Callable(self, "_log")
	_afterglow.clock = Callable(self, "_now_s")
	_afterglow.in_phase = Callable(self, "_afterglow_active")
	_afterglow.speech_busy = Callable(self, "_speech_busy")
	_afterglow.player_close = Callable(self, "_player_is_close")
	_afterglow.caress_active = Callable(self, "_afterglow_caressing")
	_afterglow.on_end = Callable(self, "end_afterglow")
	_afterglow.on_stay_close = Callable(self, "_on_stay_close")
	_face.log = Callable(self, "_log")
	_face.clock = Callable(self, "_now_s")
	_reactions.log = Callable(self, "_log")
	_pose_session.log = Callable(self, "_log")
	_perf_probe.enabled = Callable(self, "_perf_enabled")
	_perf_probe.active = Callable(self, "_perf_active")
	_perf_probe.header = Callable(self, "_perf_header")
	_perf_probe.log = Callable(self, "_log")


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
	# Identity is the key for per-mare preferences, poses, prompts and memory. It can arrive after
	# the pony enters the tree, so read it now and once more after the first frame.
	_read_id()
	call_deferred("_read_id")
	_face.bind(pony, self)
	# integration: anatomy is persistent outside acts. Retry once after the first frame for a mod
	# that assigns the pony's identity after she enters the tree.
	_anatomy_refresh()
	call_deferred("_anatomy_refresh")


## integration: resolve the persistent anatomy controller through the world service. The service
## owns it; the runtime only keeps the handle for the act.
func _anatomy_refresh() -> void:
	if not is_instance_valid(pony):
		_reactions.bind_scene(pony, null)
		return
	var service: Variant = main.get("anatomy") if is_instance_valid(main) else null
	var eligibility_service: ELIGIBILITY = main.get("eligibility") \
		if is_instance_valid(main) else null
	var target_ok := eligibility_service != null \
		and eligibility_service.eligible(pony, ELIGIBILITY.Target.ANATOMY)
	if not SETTINGS.anatomy_on() or not target_ok or not ANATOMY.assets_exist():
		if service != null and service.has_method("detach_controller"):
			service.call("detach_controller", pony)
		elif is_instance_valid(_anatomy):
			_anatomy.call("detach")
			_anatomy.queue_free()
		_anatomy = null
		_reactions.bind_scene(pony, _anatomy)
		return
	if service == null or not service.has_method("controller_for"):
		_anatomy = null
		_reactions.bind_scene(pony, _anatomy)
		return
	_anatomy = service.call("controller_for", pony, self)
	_reactions.bind_scene(pony, _anatomy)
	if is_instance_valid(_anatomy):
		_anatomy.call("refresh")


func anatomy_available() -> bool:
	return is_instance_valid(_anatomy)


## The typed anatomy context. The anatomy facade takes it when it creates the controller.
func anatomy_facts() -> RefCounted:
	return _anatomy_facts


## Public hook for the anatomy's stock flank smack. The controller calls it through the context
## callback instead of reaching into the reaction facade.
func body_coat_jiggle_target() -> void:
	_reactions.body_coat_target()


func _anatomy_act_refresh(pose_id: String) -> void:
	_anatomy_facts.penetration_m = 0.0
	_anatomy_facts.climaxes = 0
	_anatomy_facts.auto_pace = 1.0
	_anatomy_facts.fluid_ground_y = 0.0
	_anatomy_facts.penetration_reach = 0.2
	_sync_anatomy_facts()
	_anatomy_act = null
	if not is_instance_valid(_anatomy):
		return
	_anatomy_act = _anatomy.call("begin_act", pose_id)


func _anatomy_service() -> Variant:
	return main.get("anatomy") if is_instance_valid(main) else null


## The typed act/context the anatomy reads. Reused, never saved. The persistent controller sees
## the same object every frame; the act gets the extra depth/finish fields here.
func _anatomy_context() -> RefCounted:
	_sync_anatomy_facts()
	_anatomy_facts.penetration_m = penetration_m
	_anatomy_facts.climaxes = pony_climaxes
	_anatomy_facts.size_scale = _size_scale()
	var auto: Variant = _auto_controller()
	_anatomy_facts.auto_pace = float(auto.get("pace")) if auto != null else 1.0
	_anatomy_facts.fluid_ground_y = _anatomy_fluid_ground_y()
	_anatomy_facts.penetration_reach = penetration_reach()
	return _anatomy_facts


## Write the state the persistent controller polls outside the act. `bed_frame` is the live
## missionary bed frame, so the anatomy never reads the runtime field directly.
func _sync_anatomy_facts() -> void:
	_anatomy_facts.state = state
	_anatomy_facts.pose_id = pose_id
	_anatomy_facts.depth = depth
	_anatomy_facts.bed_frame = _bed_pose_frame
	_anatomy_facts.cycle_phase = cycle_phase()


## Write the typed act context the presentation controllers read. Called at the head of each tick
## and again by `apply_camera_motion()`, because `main.gd` drives the camera after the act tick.
func _sync_act_facts() -> void:
	var facts := _act_facts
	facts.state = state
	facts.pose_id = pose_id
	facts.source = source
	facts.satisfaction = satisfaction
	facts.mood = mood
	facts.cue = cue
	facts.pony_climaxes = pony_climaxes
	facts.depth = depth
	facts.penetration_m = penetration_m
	facts.main = main
	facts.pony = pony
	facts.camera = _camera
	facts.pose = _pose_session.pose()
	facts.event_id = _event_id
	facts.pony_id = _id
	facts.display_name = _display_name
	facts.preferences = _preferences
	facts.act_prompts = _act_prompts
	facts.features = _features
	if state == State.IDLE:
		# No presentation module reads the derived values outside an act; skipping the settings and
		# geometry lookups keeps an idle town from paying for every runtime every frame.
		return
	facts.act_seconds = _act_seconds
	facts.last_intensity = _last_intensity
	facts.last_pattern = _last_pattern
	facts.last_touch = _last_touch
	facts.last_talk = _last_talk
	facts.cue_override = not _cue_override.is_empty()
	facts.thrust_pace = _thrusts_per_second()
	facts.oral_active = anatomy_oral_active()
	facts.anal_active = is_instance_valid(_anatomy_act) and bool(_anatomy_act.get("_anal"))
	facts.penetration_reach = penetration_reach()
	facts.size_name = _size_name()
	facts.size_scale = _size_scale()
	facts.lean_size_scale = _lean_size_scale()
	facts.standing_lean_scale = _standing_lean_scale()
	facts.player_eye_height = _player_eye_height()
	facts.anon_torso_forward = _anon_torso_forward()
	facts.anon_torso_drop = _anon_torso_drop()
	facts.player_pony = _player_pony
	facts.headset_view = _headset_view()
	facts.free_camera_active = _free_camera_active
	facts.free_look_active = free_look_active()
	facts.camera_owned = _camera_owned
	facts.look_captured = _look_captured
	facts.look_yaw = _look_yaw
	facts.look_pitch = _look_pitch
	facts.lean_forward = _lean_forward
	facts.lean_side = _lean_side
	facts.lean_view_forward = _lean_view_forward
	facts.lean_view_side = _lean_view_side
	facts.lean_sway = _lean_sway
	facts.bob = _bob
	facts.back = _back
	facts.back_target = _back_target
	facts.forced_glance = _forced_glance
	facts.pose_config = _pose_cfg
	facts.presentation_config = _presentation_cfg
	facts.bed_frame = _bed_pose_frame
	var kiss: Variant = _kiss
	if kiss != null:
		facts.kiss_amount = float(kiss.amount())
		facts.kiss_active = bool(kiss.leaning_close())
		facts.kiss_side = float(kiss.side())
	else:
		facts.kiss_amount = 0.0
		facts.kiss_active = false
		facts.kiss_side = 0.0


## Typed write-backs for the presentation controllers. The runtime keeps ownership of the captured
## look snapshot and the forced glance, so the controller never writes those fields directly.
func _act_set_look(yaw: float, pitch: float) -> void:
	_look_yaw = yaw
	_look_pitch = pitch
	_act_facts.look_yaw = yaw
	_act_facts.look_pitch = pitch


func _act_set_forced_glance(side: String) -> void:
	_forced_glance = side
	_act_facts.forced_glance = side


func _act_set_camera_basis_ready() -> void:
	_camera_basis_ready = true


func _anatomy_fluid_ground_y() -> float:
	var ground: float = pony.global_position.y if is_instance_valid(pony) else 0.0
	if pose_id != CATALOG.MISSIONARY:
		return ground
	var camera: Variant = _missionary_camera_controller()
	if camera != null and camera.has_method("bed_surface_top"):
		var top: Variant = camera.call("bed_surface_top")
		if top is float and is_finite(top):
			return top
	return ground


## Apply the oral turn's facing after the anatomy tick, inside the same physics frame.
func _apply_anatomy_facing() -> void:
	if not is_instance_valid(_anatomy_act) or pose_id != CATALOG.STANDING:
		return
	var facing: Variant = _anatomy_act.call("facing")
	if not facing is Dictionary or (facing as Dictionary).is_empty():
		return
	var value: Dictionary = facing
	var basis: Basis = value.get("basis", Basis.IDENTITY)
	anatomy_facing(basis, float(value.get("amount", 0.0)))


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


## Debug perf probe. Timed chunks report microseconds here; `perf_note()` forwards to `perf.gd`,
## which prints one summary a second so a pony-specific stall can be attributed to a modifier
## without a live profiler.
func _perf_enabled() -> bool:
	return is_instance_valid(main) and bool(main.get("debug_logs")) \
		and bool(main.get("debug_perf"))


func _perf_active() -> bool:
	return state != State.IDLE


## Called by every timed chunk (runtime, skeleton modifiers, HUD). Cheap no-op with logs off.
func perf_note(key: String, usec: int) -> void:
	_perf_probe.note(key, usec)


## Time one call site for the perf probe (callers take the start stamp themselves).
func _timed(key: String, started: int) -> void:
	_perf_probe.time(key, started)


func _perf_tick(delta: float) -> void:
	_perf_probe.tick(delta)


## Header facts for one perf summary line.
func _perf_header() -> Dictionary:
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
	return {
		"pony": _id,
		"pose": pose_id,
		"state": state,
		"near_mesh": near_mesh,
		"tier": tier,
		"wings": wing_state,
	}


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

## Lazily create the act hand controller, including outside the tree in tests.
func _hand_controller():
	if _hands == null:
		_hands = HANDS.new(self)
	return _hands

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
		_standing_camera_ctl = STANDING_CAMERA.new(_act_facts)
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


func _lines_service() -> RefCounted:
	if _act_lines_main != main:
		_act_lines_main = main
		_act_lines.setup(main)
	_act_facts.pony_id = _id
	return _act_lines


## The pose session, bound to this runtime and its pony. Suites build a runtime without entering
## the tree, so the binding is refreshed on every access instead of only in `_ready()`.
func _pose_service() -> RefCounted:
	_pose_session.bind(self, pony)
	_pose_session.pose_id = pose_id
	_pose_session.id = _id
	return _pose_session


## Push the debug talk/cue pacing settings into the pure scheduler. `reset()` keeps these
## fields, so `_reset_thrust_state()` only has to reset the act's timing state.
func _configure_utterance_scheduler() -> void:
	_lines_service().configure({
		"base_stable": _cue_base_stable_s,
		"override_stable": _cue_override_stable_s,
		"utterance_gap": _cue_utterance_gap_s,
		"demand_gap": _cue_demand_gap_s,
		"demand_repeat": _cue_demand_repeat_s,
		"max_age": _cue_max_age_s,
		"release_hold": _cue_release_hold_s,
	})


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
	_reactions.configure({
		"jiggle": jiggle_block,
		"pose_id": pose_id,
		"size_scale": _jiggle_size_scale(),
		"climax_seconds": CLIMAX_SECONDS,
	})
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
	_readiness.configure(_preferences, _cue_override_seconds, _cue_overwhelmed_s,
		_touch_cooldown_s, _talk_cooldown_s, _receptive_seconds)
	_presentation_cfg = SETTINGS.block("presentation." + pose_id + ".")
	_act_climax_mode = str(SETTINGS.climax_mode.get_choice())
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
	_reactions.apply_radius()
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
	_sync_act_face_settings()
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
	_pose_service().refresh_modifiers(pose_id, _features)
	if pose_id == CATALOG.STANDING:
		_standing_anon_controller().refresh_palm()
	elif pose_id == CATALOG.MISSIONARY:
		if is_instance_valid(_missionary_anon):
			_missionary_anon.call("refresh_palm")

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

## Act blush and wing presentation. The blush ramps with readiness unless the debug arc is off.
func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act_seconds += delta
	if pose_id == CATALOG.MISSIONARY:
		_missionary_camera_controller().hide_avatar()
		_aim_missionary_eyes()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", ACT_FACE.blush_for(_act_phase(), satisfaction,
			_feature("blush_arc")))
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
	if _perf_probe.on():
		perf_note("runtime_process", Time.get_ticks_usec() - started)
		_perf_tick(delta)


func _process_tick(delta: float) -> void:
	if state == State.IDLE:
		_standing_presentation_controller().process()
		return
	_sync_act_facts()
	_sync_bed_pose_frame()
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
	_sync_anatomy_facts()
	_physics_tick(delta)
	_sync_anatomy_facts()
	if _perf_probe.on():
		perf_note("runtime_physics", Time.get_ticks_usec() - started)


func _physics_tick(delta: float) -> void:
	_clock_s += maxf(0.0, delta)
	_sync_act_facts()
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
	_sync_bed_pose_frame()
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
	_sync_act_facts()
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
			_anatomy_act.call("tick", delta, _anatomy_context())
			_apply_anatomy_facing()
		if state == State.ACTIVE:
			_readiness_tick(delta)
			_talk_tick(delta)
			_bystander_tick(delta)
	if state in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.RESTORE]:
		_sync_act_facts()
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
		_reactions.hearts_tick(delta)
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
	_reactions.blush_tick(delta)
	apply_camera_motion()
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
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
	if _now_s() < _stare_release_until:
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

func can_show_start(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return bool(start_verdict(pose, act_source, bed_in).get("show", false))


## Offer eligibility before she is in position. Unlike the Y start gate, this does not require
## the pony to be lying or the player to be ready; those stay in the final gate. `forced` is the
## Debug -> Actions bypass: the settings page pauses the tree, and the episode advances after it
## closes, so the paused row must not reject a forced offer.
func can_offer(pose: String, act_source: String, bed_in: Variant = null, forced := false) -> bool:
	return bool(offer_verdict(pose, act_source, bed_in, forced).get("ok", false))


## The failed offer gates, for the debug request buttons and their logs.
func offer_reasons(pose: String, act_source: String, bed_in: Variant = null,
		forced := false) -> PackedStringArray:
	return _report_reasons(offer_verdict(pose, act_source, bed_in, forced).get("rows", []))


func _start_reasons(pose: String, act_source: String, bed_in: Variant = null) -> PackedStringArray:
	return _report_reasons(start_verdict(pose, act_source, bed_in).get("rows", []))


## Whether the footstool rule can apply at all. Anatomy internals stay behind its facade.
func stool_applies() -> bool:
	if not SETTINGS.standing_stool.get_bool():
		return false
	if not SETTINGS.anatomy_on():
		return false
	if not is_instance_valid(main) or not is_instance_valid(pony) or not pony is Node3D:
		return false
	if not is_instance_valid(main.player) or not main.player is Node3D:
		return false
	var tree := get_tree() if is_inside_tree() else null
	if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		return false
	if _headset_view():
		return false
	if not is_instance_valid(_anatomy) or not _anatomy.has_method("hole_point"):
		return false
	return true


## The live vertical gap: her opening above her hooves against his part above his feet.
## Returns NAN when either body or the anatomy is unavailable.
func stool_gap_m() -> float:
	if not stool_applies():
		return NAN
	var service: Variant = _anatomy_service()
	if service == null or not service.has_method("player_prepare") \
			or not service.has_method("player_root_now"):
		return NAN
	if not bool(service.call("player_prepare")):
		return NAN
	var opening: Variant = _anatomy.call("hole_point", 0.0)
	var part: Variant = service.call("player_root_now")
	if not opening is Vector3 or not (opening as Vector3).is_finite():
		return NAN
	if not part is Vector3 or not (part as Vector3).is_finite():
		return NAN
	var system: Variant = main.get("stool")
	if system == null or not system.has_method("gap"):
		return NAN
	return float(system.call("gap", (opening as Vector3).y, pony.global_position.y,
		(part as Vector3).y, main.player.global_position.y))


func stool_needed_count() -> int:
	var gap := stool_gap_m()
	if not is_finite(gap):
		return 0
	var system: Variant = main.get("stool") if is_instance_valid(main) else null
	if system == null or not system.has_method("needed_count"):
		return 0
	return maxi(0, int(system.call("needed_count", gap)))


func stool_required() -> bool:
	return stool_needed_count() > 0


func stool_case_slot() -> int:
	var system: Variant = main.get("stool") if is_instance_valid(main) else null
	var store: Variant = _inventory_store()
	if system == null or store == null:
		return -1
	if not bool(system.call("writable", store)):
		return -1
	return int(system.call("case_slot", store))


func stool_case_count() -> int:
	var system: Variant = main.get("stool") if is_instance_valid(main) else null
	var store: Variant = _inventory_store()
	if system == null or store == null:
		return 0
	if not bool(system.call("writable", store)):
		return 0
	return maxi(0, int(system.call("case_count", store)))


## True only when the footstool stack is the one thing keeping the Make love hint away.
func stool_blocks_start(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	var need := stool_needed_count()
	if need <= 0 or stool_case_count() >= need:
		return false
	var reasons: PackedStringArray = _start_reasons(pose, act_source, bed_in)
	if reasons.is_empty():
		return false
	for reason: String in reasons:
		if reason != "needs_stool":
			return false
	return true


func stool_state_text() -> String:
	var system: Variant = main.get("stool") if is_instance_valid(main) else null
	var store: Variant = _inventory_store()
	var anatomy_ok := is_instance_valid(_anatomy) and _anatomy.has_method("hole_point")
	var opening := Vector3.ZERO
	if anatomy_ok:
		var value: Variant = _anatomy.call("hole_point", 0.0)
		if value is Vector3:
			opening = value
	var service: Variant = _anatomy_service()
	var part := Vector3.ZERO
	var part_ok := false
	if service != null and service.has_method("player_prepare") \
			and service.has_method("player_root_now"):
		if bool(service.call("player_prepare")):
			var value: Variant = service.call("player_root_now")
			if value is Vector3 and (value as Vector3).is_finite():
				part = value
				part_ok = true
	var hoof_y: float = pony.global_position.y if is_instance_valid(pony) and pony is Node3D else 0.0
	var foot_y: float = main.player.global_position.y \
		if is_instance_valid(main) and is_instance_valid(main.player) and main.player is Node3D else 0.0
	var gap := NAN
	if anatomy_ok and part_ok and system != null and system.has_method("gap") \
			and is_instance_valid(pony) and is_instance_valid(main.player) and main.player is Node3D:
		gap = float(system.call("gap", opening.y, hoof_y, part.y, foot_y))
	var threshold := SETTINGS.stool_gap_m.get_num() if system == null \
		else float(system.call("threshold_m"))
	var height := SETTINGS.stool_height_m.get_num() if system == null \
		else float(system.call("height_m"))
	var need := stool_needed_count()
	var gap_text := "n/a" if not is_finite(gap) else "%.3f" % gap
	var owned := 0
	var free := 0
	if system != null and store != null:
		owned = int(system.call("owned_count", store))
		free = int(system.call("free_slots", store))
	return "pony=%s applies=%s anatomy=%s part=%s her_opening=%.3f her_hoof=%.3f her_bits=%.3f his_root=%.3f his_feet=%.3f his_bits=%.3f floor_delta=%.3f gap=%s threshold=%.3f height=%.3f required=%s need=%d active=%s count=%d case=%d owned=%d free=%d" % [
		str(pony.name) if is_instance_valid(pony) else "?",
		str(stool_applies()), str(anatomy_ok), str(part_ok),
		opening.y, hoof_y, opening.y - hoof_y, part.y, foot_y, part.y - foot_y,
		hoof_y - foot_y, gap_text, threshold, height, str(stool_required()),
		need, str(_stool_active), _stool_count, stool_case_count(), owned, free]


func _inventory_store() -> Variant:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return null
	var inventory: Variant = main.game.get("inventory")
	if not is_instance_valid(inventory):
		return null
	return inventory.get("inventory")


## The full Y-start gate: eligibility policy rows plus the start scene rows. `show` is the hint,
## `attempt` is a start, and the two refusals are separate. See docs/eligibility.md.
func start_verdict(pose: String, act_source: String, bed_in: Variant = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var data := _gate_data(pose, act_source, bed_in, "start", false, verdict_in)
	var policy: ELIGIBILITY.Verdict = data.get("policy")
	var scene_ok := bool(data.get("scene_ok", false))
	return {
		"show": policy != null and policy.show and scene_ok,
		"attempt": policy != null and policy.attempt and scene_ok,
		"buck_refuse": policy != null and policy.buck_refuse,
		"history_refuse": policy != null and policy.history_refuse and scene_ok,
		"rows": data.get("rows", []),
		"policy": policy,
	}


## The full proactive-offer gate. It uses the offer-safe scene subset.
func offer_verdict(pose: String, act_source: String, bed_in: Variant = null,
		forced := false, verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var data := _gate_data(pose, act_source, bed_in, "offer", forced, verdict_in)
	var policy: ELIGIBILITY.Verdict = data.get("policy")
	var scene_ok := bool(data.get("scene_ok", false))
	return {
		"ok": policy != null and policy.offer and scene_ok,
		"rows": data.get("rows", []),
		"policy": policy,
	}


func _gate_data(pose: String, act_source: String, bed_in: Variant, mode: String,
		forced := false, verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var structural: Array = []
	_gate_row(structural, "invalid_pony", is_instance_valid(pony), "invalid_pony")
	if not is_instance_valid(pony):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_read_id()
	_gate_row(structural, "no_main", is_instance_valid(main), "no_main")
	if not is_instance_valid(main):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_gate_row(structural, "no_player", is_instance_valid(main.player), "no_player")
	if not is_instance_valid(main.player):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_gate_row(structural, "no_game", is_instance_valid(main.game), "no_game")
	if not is_instance_valid(main.game):
		return {"rows": structural, "policy": null, "scene_ok": false}
	var policy_mode: ELIGIBILITY.Mode = ELIGIBILITY.Mode.OFFER if mode == "offer" \
		else ELIGIBILITY.Mode.START
	var policy: ELIGIBILITY.Verdict = _policy_verdict(policy_mode, verdict_in)
	var scene_rows: Array = _scene_rows(pose, act_source, bed_in, mode, forced)
	var rows: Array = structural.duplicate()
	if policy != null:
		for row: ELIGIBILITY.Row in policy.rows:
			rows.append(row)
	for row: Variant in scene_rows:
		rows.append(row)
	return {
		"rows": rows,
		"policy": policy,
		"scene_ok": _report_ok(scene_rows),
	}


## The scene-only rows. They never enter the pure policy.
func _scene_rows(pose: String, act_source: String, bed_in: Variant, mode: String,
		forced: bool) -> Array:
	var rows: Array = []
	_gate_row(rows, "state", state == State.IDLE, "state=%d" % state)
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
	if pose == CATALOG.STANDING:
		var stool_need := stool_needed_count()
		_gate_row(rows, "stool", stool_need <= 0 or stool_case_count() >= stool_need,
			"needs_stool")
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


func _policy_verdict(mode: ELIGIBILITY.Mode,
		verdict_in: ELIGIBILITY.Verdict = null) -> ELIGIBILITY.Verdict:
	if verdict_in != null:
		return verdict_in
	if not is_instance_valid(main):
		return null
	var service: ELIGIBILITY = main.get("eligibility")
	if service == null:
		return null
	return service.get_verdict(pony, mode)


func _gate_row(rows: Array, key: String, ok: bool, reason := "") -> void:
	var row := ELIGIBILITY.Row.new()
	row.key = key
	row.ok = ok
	row.reason = reason if not reason.is_empty() else key
	rows.append(row)


func _report_ok(rows: Array) -> bool:
	for row: ELIGIBILITY.Row in rows:
		if not row.ok:
			return false
	return true


func _report_reasons(rows: Array) -> PackedStringArray:
	var reasons: PackedStringArray = []
	for row: ELIGIBILITY.Row in rows:
		if not row.ok:
			reasons.append(row.reason)
	return reasons


func debug_line(pose: String, act_source: String, bed_in: Variant = null, distance := -1.0, dot := -1.0) -> String:
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	var id := ""
	var display := "?"
	if identity != null:
		id = str(identity.get("id"))
		display = str(identity.get("display_name")) if identity.get("display_name") != null else id
	var gate := start_verdict(pose, act_source, bed_in)
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	var relations: ELIGIBILITY.Relations = policy.relations if policy != null \
		else ELIGIBILITY.Relations.new()
	var stage := relations.stage
	var love_level := relations.love_level
	var love_name := "?"
	var rel: Variant = null
	if is_instance_valid(pony) and pony.has_meta("relationship_runtime"):
		rel = pony.get_meta("relationship_runtime")
	if rel != null and is_instance_valid(rel) and rel.has_method("ladder"):
		var ladder: Variant = rel.call("ladder", id)
		if ladder is Dictionary:
			var love: Variant = (ladder as Dictionary).get("love", {})
			if love is Dictionary:
				love_name = str((love as Dictionary).get("name", "?"))
	var welcomes := relations.willing
	var sex_bond := policy != null and (relations.stored_bond \
		or relations.sex_start == "try_luck")
	var sex_start := relations.sex_start
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
	var reasons: PackedStringArray = _report_reasons(gate.get("rows", []))
	var reason_text := "none" if reasons.is_empty() else ",".join(reasons)
	var found_bed: Node3D = _resolve_bed(pose, act_source, bed_in) if pose == CATALOG.MISSIONARY else null
	var bed_gate := "n/a"
	if pose == CATALOG.MISSIONARY:
		bed_gate = str(found_bed != null and _bed_gate(pose, act_source, found_bed))
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level%d) welcomes=%s bond=%s start=%s mood=%s | show=%s attempt=%s offer=%s buck=%s history=%s | state=%d presenting=%s sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s romance=%s promiscuity=%s bondrow=%s cycle=%s historyrow=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		display, id, float(distance), float(dot), stage, love_name, love_level, str(welcomes), str(sex_bond), sex_start, mood,
		str(bool(gate.get("show", false))), str(bool(gate.get("attempt", false))),
		str(policy != null and policy.offer), str(policy != null and policy.buck_refuse),
		str(policy != null and policy.history_refuse),
		state, str(_standing_presentation_controller().presentation_active()), str(pony.get("sleeping")), str(pony.is_held()), str(pony.grounded()), str(pony.has_meta("seated")),
		str(_cuddle_active()), str(pony.get("motion_paused")), float(pony.get("actual_speed")), str(status.get("requested")),
		str(pony.action_interruption_reason()), owner, str(target), reserved,
		str(body.get("controls_locked")) if body != null else "?",
		str(body.get("flying")) if body != null else "?",
		str(body.get("seat")) if body != null else "?",
		str(Input.mouse_mode), str(get_tree().paused),
		str(_policy_row_ok(policy, "relation")), str(_policy_row_ok(policy, "form")),
		str(_policy_row_ok(policy, "romance")), str(_policy_row_ok(policy, "promiscuity")),
		str(_policy_row_ok(policy, "sex_bond")), str(_policy_row_ok(policy, "cycle")),
		str(_policy_row_ok(policy, "history")), str(_conversation_ok()), str(_free_of_affection()),
		str(_player_ready_for(pose, act_source, bed_in)), str(_nav_owner_allows(pose, act_source)),
		str(_nav_pose_gate(pose, act_source)), bed_gate, str(bool(gate.get("show", false))), reason_text]
	if state != State.IDLE:
		var limit_text := "∞" if _max_pony_climaxes <= 0 else str(_max_pony_climaxes)
		text += " | readiness=%.0f mood=%s climaxes=%d/%s intensity=%s pattern=%s cue=%s up=%s penetration=%.1f/%.1fcm | %s" % [
			satisfaction, mood, pony_climaxes, limit_text,
			_last_intensity, _last_pattern, cue, str(thrust_up),
			penetration_m * 100.0, penetration_reach() * 100.0,
			PREFERENCES.describe(_preferences).replace("\n", "; ")]
	text += " | " + voice_status_line()
	return text


func _policy_row_ok(policy: ELIGIBILITY.Verdict, key: String) -> bool:
	if policy == null:
		return true
	for row in policy.rows:
		if row.key == key:
			return row.ok
	return true

func refuse_available(pose: String, act_source: String, bed_in: Variant = null,
		gate_in: Dictionary = {}) -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	_read_id()
	var gate: Dictionary = gate_in if not gate_in.is_empty() \
		else start_verdict(pose, act_source, bed_in)
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	if policy == null or not policy.buck_refuse:
		return false # Willing, or not an eligible adult mare: the normal offer/start path owns it.
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

func refuse(pose: String, act_source: String, bed_in: Variant = null,
		gate_in: Dictionary = {}) -> void:
	if not refuse_available(pose, act_source, bed_in, gate_in):
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
## impression note, which drives eligibility, anger, offers, approaches and her dialogue; the held
## face displays it (mood_face.gd). A buck is the stronger moment, so it is the stronger mood.
func _note_refusal(bucked: bool) -> void:
	if is_instance_valid(main) and is_instance_valid(main.game):
		var impression := MEMORY.Impression.new()
		impression.id = _id
		impression.event_id = "unfplap_refusal_%s_%d" % [_id, Time.get_ticks_usec()]
		impression.slot = MEMORY.ImpressionSlot.REFUSAL
		impression.mood = "angry" if bucked else "annoyed"
		main.memory.commit(impression)
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
	# The relationship id is the stable key used by eligibility, preferences and memory. Prefer
	# the meta value whenever it appears; a mod may assign it after the pony enters the tree.
	var meta_id := str(pony.get_meta("relationship_id", "")) if pony.has_meta("relationship_id") else ""
	if not meta_id.is_empty():
		_id = meta_id
	elif _id.is_empty():
		var identity_id: Variant = pony.get("identity")
		if identity_id != null:
			_id = str(identity_id.get("id"))
	if _id.is_empty():
		return false
	var identity: Variant = pony.get("identity")
	if identity != null:
		_display_name = str(identity.get("display_name")) if identity.get("display_name") != null else _id
	return true

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


## Public cuddle state for the proactive-request service. The internal helper stays for the act
## gates, so no other system reaches a private function.
func cuddle_active() -> bool:
	return _cuddle_active()


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

## Public affection state for the standing presentation. The internal helper stays for the
## act gates, so no other system reaches a private function.
func free_of_affection() -> bool:
	return _free_of_affection()


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

func start(pose: String, bed_in: Variant, act_source: String,
		gate_in: Dictionary = {}) -> bool:
	_read_id()
	var gate: Dictionary = gate_in if not gate_in.is_empty() \
		else start_verdict(pose, act_source, bed_in)
	if bool(gate.get("history_refuse", false)):
		_log("start refused by history pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		refuse_from_history(pose, act_source, bed_in)
		return false
	if not bool(gate.get("attempt", false)):
		_log("start blocked pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		# Try Your Luck can reach this point before she welcomes the kiss. The refusal is a real
		# buck/push, not a silent no-op.
		if bool(gate.get("buck_refuse", false)) and refuse_available(pose, act_source, bed_in, gate):
			_log("start refused pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
			refuse(pose, act_source, bed_in, gate)
		return false
	_reset_stool_state()
	_anatomy_refresh()
	if pose == CATALOG.STANDING:
		var stool_need := stool_needed_count()
		if stool_need > 0:
			if stool_case_count() < stool_need or not _take_stool_items(stool_need):
				_log("start blocked stool pose=%s pony=%s need=%d" % [
					pose, str(pony.name) if is_instance_valid(pony) else "?", stool_need])
				return false
	_camera_owned = false
	_look_captured = false
	_look_restore_yaw = pose != CATALOG.STANDING
	_posture_owned = false
	_session_finalized = false
	# Remove the idle standing invitation and its request face before the act builds its own pose.
	set_request_face(false)
	clear_presentation()
	_end_mood_face()
	_end_act_face()
	pose_id = pose
	source = act_source
	_profile = SETTINGS.template_for(_id)
	_pose_service().set_pose_config(SETTINGS.pose(_id, pose_id))
	_preferences = SETTINGS.preferences(_id)
	_act_prompts = _profile.get("act_prompts", {})
	_snapshot_settings()
	_reactions.apply_radius()
	_thrust_tracker = THRUST.new()
	_aftercare_min = int(_profile.get("aftercare_min", 10))
	_cue_gap = SETTINGS.cue_gap_value(float(_profile.get("cue_gap", 12.0)))
	_standing_camera_controller().reset()
	bed = _resolve_bed(pose, act_source, bed_in)
	if pose == CATALOG.MISSIONARY and bed == null:
		# Nothing else is borrowed yet, but the jiggle radius was just applied.
		_reactions.restore_radius()
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
	_act_seconds = 0.0
	_reactions.begin_act()
	_reset_lean_state()
	_clear_face()
	_set_face(0.45, ACT_LIDS)
	_serial = _next_serial()
	_event_id = "intimacy_%s_%d" % [_id, _serial]
	_first_time = _read_first_time()
	_started_at = Time.get_unix_time_from_system()
	satisfaction = 0.0
	mood = "warming"
	cue = ""
	_y_hold = 0.0
	_y_hold_ready = false
	_y_hold_fired = false
	_reset_thrust_state()
	_stopped_by_her = false
	_tolerance_warning_key = ""
	_end_tail_tuck()
	_history.reset_act(_preferences)
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
		if _stool_failed:
			_abort_start()
			return false
		pony.request_posture("stand")
		_sync_act_facts()
		_standing_camera_controller().begin_facing(standing)

	_build_pose()
	_reactions.clear_stock_marks()
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
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_encounter"):
		service.call("player_encounter", true)
	state = State.POSING_IN
	_act_face_beat("start")
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
			or not is_instance_valid(main.player) or not main.player is Node3D:
		if _stool_active:
			_stool_failed = true
		pony.reset_motion(standing)
		pony.reset_physics_interpolation()
		return standing
	# The offer cone already requires him within 0.8 m of her rump, so the correction is small.
	# The act end leaves him there instead of snapping him back.
	var body: Variant = main.player
	var target: Vector3 = pony.global_position - forward * _standing_gap()
	var floor_y := _floor_y_at(Vector3(target.x, body.global_position.y + 0.4, target.z), body)
	if not is_finite(floor_y) or absf(floor_y - body.global_position.y) > 1.0:
		floor_y = body.global_position.y
	target.y = body.global_position.y
	if _stool_active:
		var system: Variant = main.get("stool")
		var built: Dictionary = {}
		if system != null and system.has_method("build_prop"):
			var step := float(system.call("height_m"))
			var ignore: PhysicsBody3D = null
			if pony is PhysicsBody3D:
				ignore = pony as PhysicsBody3D
			built = system.call("build_prop", system,
				Vector3(target.x, floor_y, target.z), body.rotation.y,
				_stool_count, step, ignore)
		var node: Variant = built.get("node")
		if node is Node3D and is_instance_valid(node):
			_stool_node = node
			_stool_height_m = float(built.get("height", 0.0))
			_stool_floor_y = floor_y
			_stool_lifted = true
			target.y = floor_y + _stool_height_m + 0.005
			_log("stool placed count=%d height=%.3f floor=%.3f at=%s" % [
				_stool_count, _stool_height_m, floor_y,
				str(Vector3(target.x, floor_y, target.z))])
		else:
			_stool_failed = true
			_log("stool placement failed at=%s" % str(Vector3(target.x, floor_y, target.z)))
	body.global_position = target
	if _stool_lifted and body.get("velocity") != null:
		body.set("velocity", Vector3.ZERO)
	# Do not inherit the previous act's view: face him along her forward, so his body is in front
	# of the camera instead of off to one side after a missionary restore.
	body.rotation.y = atan2(-forward.x, -forward.z)
	body.reset_physics_interpolation()
	_log("standing keeps pony at=%s and places Anon at=%s yaw=%.3f stool=%s" % [
		str(pony.global_position), str(target), body.rotation.y, str(_stool_active)])
	return standing


## Remove the act prop and put every case item back. Every exit path calls this.
func _release_stool() -> void:
	var was_active := _stool_active or not _stool_tokens.is_empty()
	if is_instance_valid(_stool_node):
		var system: Variant = main.get("stool") if is_instance_valid(main) else null
		if system != null and system.has_method("free_prop"):
			system.call("free_prop", _stool_node)
		else:
			_stool_node.queue_free()
	_stool_node = null
	if _stool_lifted and is_instance_valid(main) and is_instance_valid(main.player) \
			and main.player is Node3D:
		var body: Variant = main.player
		var at: Vector3 = body.global_position
		var floor_y := _stool_floor_y
		var candidate := _floor_y_at(Vector3(at.x, at.y + 0.2, at.z), body)
		if is_finite(candidate) and absf(candidate - _stool_floor_y) < 0.5:
			floor_y = candidate
		body.global_position = Vector3(at.x, floor_y + 0.002, at.z)
		if body.get("velocity") != null:
			body.set("velocity", Vector3.ZERO)
		body.reset_physics_interpolation()
		_log("stool lowered player floor=%.3f" % floor_y)
	if not _stool_tokens.is_empty():
		var store: Variant = _inventory_store()
		for i: int in _stool_tokens.size():
			var token := _stool_tokens[i]
			var slot := _stool_slots[i] if i < _stool_slots.size() else -1
			var returned := false
			if store != null:
				returned = bool(store.call("put", token, slot))
				if not returned:
					returned = bool(store.call("put", token, -1))
			if returned:
				_log("stool returned count=%d/%d slot=%d" % [
					i + 1, _stool_tokens.size(), slot])
			else:
				_log("stool item restore pending token=%s" % token)
		_stool_tokens.clear()
		_stool_slots.clear()
	if was_active:
		_log("stool released")
	_stool_active = false
	_stool_lifted = false
	_stool_failed = false
	_stool_count = 0
	_stool_height_m = 0.0
	_stool_floor_y = 0.0


func _reset_stool_state() -> void:
	if _stool_active or not _stool_tokens.is_empty() or is_instance_valid(_stool_node):
		_release_stool()
	_stool_active = false
	_stool_lifted = false
	_stool_failed = false
	_stool_tokens.clear()
	_stool_slots.clear()
	_stool_count = 0
	_stool_node = null
	_stool_height_m = 0.0
	_stool_floor_y = 0.0


func _take_stool_items(need: int) -> bool:
	var count := maxi(1, need)
	_stool_tokens.clear()
	_stool_slots.clear()
	var system: Variant = main.get("stool") if is_instance_valid(main) else null
	var store: Variant = _inventory_store()
	if system == null or store == null or not bool(system.call("writable", store)):
		return false
	for _i: int in count:
		var slot := int(system.call("case_slot", store))
		if slot < 0:
			_release_stool()
			return false
		var token := str(store.call("take", slot))
		if token.is_empty():
			_release_stool()
			return false
		_stool_tokens.append(token)
		_stool_slots.append(slot)
	_stool_count = count
	_stool_active = true
	_stool_failed = false
	_log("stool items taken count=%d" % count)
	return true


## The floor under a standing spot. The player is excluded so his own capsule cannot answer.
func _floor_y_at(at: Vector3, body: Node3D) -> float:
	if not is_instance_valid(body) or not at.is_finite():
		return NAN
	var world := body.get_world_3d()
	if world == null:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 1.4, 1)
	if body is CollisionObject3D:
		query.exclude = [body.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	var y := float(point.y)
	return y if is_finite(y) else NAN


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
	_pose_service().set_chin(_debug_chin_deg)
	# Let the skeleton modifier apply this frame before sampling the head/chin positions.
	call_deferred("_log_chin")

## Keep the debug chin modifier after every pose modifier, so an act cannot overwrite the debug
## head pitch.
func _keep_chin_last() -> void:
	_pose_service().keep_chin_last()

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
	if not _pose_service().sync_standing_config(_presentation_cfg):
		return
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("pose_config", _pose_cfg)


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose keeps its nuzzle overrides live.
func _sync_missionary_pose_config() -> void:
	if not _pose_service().sync_missionary_config():
		return
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("pose_config", _pose_cfg)


## The parsed authored missionary pose, for the shot camera and the debug action.
func authored_pose_asset() -> Variant:
	return _pose_service().authored_asset()


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
	return _pose_service().missionary_origin()


## A bed can move under the act. The pose session carries the authored pose, the act body, the
## camera shot and the anatomy placement with it. See ROTATION.md.
func _sync_bed_pose_frame() -> void:
	_pose_service().sync_bed_frame()


func _build_pose() -> void:
	_free_pose()
	var session := _pose_service()
	var view: Variant = main.call("camera") if is_instance_valid(main) and main.has_method("camera") else null
	var look: Vector3 = pony.global_position
	var camera_at := Vector3.INF
	if view is Camera3D:
		look = (view as Camera3D).global_position
		camera_at = look
	session.begin({
		"pose_id": pose_id,
		"id": _id,
		"features": _features,
		"bed": bed,
		"presentation": _presentation_cfg,
		"pose_config": _pose_cfg,
		"look_point": look,
		"camera_position": camera_at,
	})
	_reactions.bind_tail(session.tail)


## Snapshot before the act changes her posture or the pose writes bones.
func _snapshot_pony_bones() -> void:
	_pose_service().snapshot_bones()


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func _restore_pony_bones() -> void:
	_pose_service().restore_bones()


## The one pose teardown: the pose-owned start state, the cross-system releases in their order,
## the live modifiers, then the pose and the standing tail.
func _free_pose() -> void:
	_pose_service().release_start()
	clear_presentation()
	_end_lean_action()
	_hand_controller().reset()
	_kiss_controller().reset()
	_release_free_camera_lock()
	_standing_anon_controller().remove()
	_pose_service().remove_modifiers()
	_restore_voice_volume()
	_reactions.end_act()
	_pose_service().release_pose()


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
	_readiness.reset(_preferences)
	_climax_left = 0.0
	_afterglow.reset()
	_lines_service().reset(_now_s(), _cue_gap)
	_configure_utterance_scheduler()
	_vocal_cooldown = 0.0
	_act_spoken_at = -1e9
	_act_ended_early = false
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
		_anatomy_act.call("toggle_hole", state)


func toggle_anatomy_oral() -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("toggle_oral", state)


func toggle_anatomy_finish() -> void:
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("toggle_finish", state)


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


## integration: the standing part aims itself in `player.gd`'s track; only the optional bed body
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
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_shaft_length_m"):
		var length: Variant = service.call("player_shaft_length_m")
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
			pose_id, _reactions.rump_point(), _bed_audio_point(), _bed_soft)
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

## Score one closed inward thrust through the readiness system. Presentation stays in
## `_on_impact`; this only updates the two preference axes and the act counters.
func _on_stroke(event: Dictionary) -> void:
	_readiness.stroke(event)


## Score the current axes. The readiness tick calls it after a stroke; the suite calls it directly.
func _score_thrust() -> void:
	_readiness.score_thrust()


## Add one readiness chunk. The readiness system clamps and tracks the peak.
func _add_heat(amount: float) -> void:
	_readiness.add_heat(amount)


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
	_reactions.thrust(jiggle)
	_reactions.tail_thrust(jiggle)
	if pose_id == CATALOG.STANDING:
		_reactions.add_blush(impact)
		_pose_service().trigger_ear_twitch(impact)
	_readiness.thrust_times.append(now)
	while not _readiness.thrust_times.is_empty() \
			and now - float(_readiness.thrust_times[0]) > 1.0:
		_readiness.thrust_times.pop_front()
	_play_vocal()
	if is_instance_valid(_act_audio):
		_act_audio.play_impact(pose_id, strength, _reactions.rump_point(),
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

## Readiness never decays on its own; the readiness system owns the values and counters.
func _readiness_tick(delta: float) -> void:
	_readiness.tick(delta)


## One real touch event. The readiness system applies the cooldown, heat and tolerance meter.
func _set_cue_override(text: String, seconds := -1.0) -> void:
	_readiness.set_cue_override(text, seconds)


func _on_touch(kind: String) -> void:
	_readiness.touch(kind)


func _on_talk(text: String) -> void:
	_readiness.talk(text)


func _talk_tick(_delta: float) -> void:
	_readiness.talk_tick(_director())


func _remember_talk_turn() -> void:
	_readiness.remember_talk_turn(_director())


## The readiness host boundary: scene values the pure scoring needs, and the presentation it
## triggers. The runtime keeps the state, the face beats, the tolerance meter and the cue line.
func _readiness_state() -> int:
	return state


func _readiness_close() -> void:
	_act_face_beat("close")


func _readiness_anatomy_react() -> void:
	if is_instance_valid(_anatomy):
		_anatomy.call("react")


func _readiness_heat() -> bool:
	return cycle_phase() == CYCLE.HEAT


func _readiness_cue(mood_value: String, cue_value: String, is_override: bool) -> void:
	_act_facts.mood = mood_value
	_act_facts.cue = cue_value
	_act_facts.cue_override = is_override
	_lines_service().admit_cue(_now_s())


func _tolerance_dislike(kind: String) -> Dictionary:
	return _history.observe_dislike(kind)


func _tolerance_like(kind: String) -> void:
	_history.observe_like(kind)


## True while the director or the pony is actually speaking.
func _speech_busy() -> bool:
	return _lines_service().busy()


## Free a delivered line and expire a queued one at its max age. See `act_lines.gd`.
func _utterance_tick() -> void:
	_lines_service().tick()


## integration: one adult observer may say a short line, using the modern witness perception.
func _bystander_tick(delta: float) -> void:
	_lines_service().bystander_tick(delta)


## The typed stop reason for one `_stop()` reason string.
func _stop_reason(reason: String) -> int:
	match reason:
		"unwilling":
			return MEMORY.StopReason.UNWILLING
		"picked up":
			return MEMORY.StopReason.PICKED_UP
		"interrupted":
			return MEMORY.StopReason.INTERRUPTED
		"form change":
			return MEMORY.StopReason.FORM_CHANGE
		"withdrew":
			return MEMORY.StopReason.WITHDREW
		_:
			return MEMORY.StopReason.NONE


## Queue one settings-driven reaction line. Returns the director key, or "" when it was not queued.
func _reaction_line(reaction: int, event_id: String, fallback: String, valid: Callable) -> String:
	return _lines_service().reaction_line(reaction, event_id, fallback, valid)


## Drop all act lines that have not started speaking.
func _end_act_lines(keep_speaking := true) -> void:
	_lines_service().end_act(_event_id, keep_speaking)


func _last_spoken_line() -> String:
	return _lines_service().last_spoken_line()


## When she last actually spoke, so a peak memory does not quote a pre-act line as an answer.
func _last_spoken_at() -> float:
	return _lines_service().last_spoken_at()


## One summary per act. The history system scores it and owns the stored row.
func _commit_summary(real_act: bool) -> void:
	_history.commit_summary(real_act, _summary_context())


func _summary_context() -> Dictionary:
	return {
		"main": main,
		"pony_id": _id,
		"event_id": _event_id,
		"inputs": _summary_inputs(),
	}


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


func _history_note() -> String:
	return _history.prompt_note(_id)


## Called by main before a normal Y start. A withdrawn mare still shows the offer; pressing Y
## gives one gentle refusal instead of a silent no.
func history_blocks_start() -> bool:
	if state != State.IDLE:
		return false
	var verdict := _policy_verdict(ELIGIBILITY.Mode.START)
	return _history.blocks_start(verdict)


func refuse_from_history(_pose: String, source: String, _bed: Variant = null) -> bool:
	_read_id()
	if not history_blocks_start():
		return false
	var now := _now_s()
	if not _history.refusal_ready(now):
		return true
	_history.mark_refusal(now)
	if is_instance_valid(main) and is_instance_valid(main.game):
		var row: Dictionary = _history.row(_id)
		var event_id := "history_refusal_%s_%d" % [_id, Time.get_ticks_usec()]
		var valid := func() -> bool:
			return is_instance_valid(pony) and state == State.IDLE
		_reaction_line(MEMORY.Reaction.HISTORY_REFUSAL, event_id,
			ACT_HISTORY.refusal_purpose(row), valid)
		_log("history refusal id=%s tier=%s hurt=%d" % [
			_id, ACT_HISTORY.tier_name(row), int(row.get("hurt", 0))])
	if source == "cradle":
		_release_carry()
		if is_instance_valid(pony) and pony.get("posture") != null:
			pony.request_posture("stand")
	return true


## Idle-only history scan. The scene values are gathered here; `history.gd` owns the decisions.
func _history_tick(delta: float) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(main) \
			or not is_instance_valid(main.player):
		return
	var director := _director()
	if director == null:
		return
	var target: Variant = pony.get("conversation_target")
	var body: Variant = main.player_body()
	_history.tick_idle(delta, {
		"main": main,
		"pony": pony,
		"director": director,
		"pony_id": _id,
		"event_id": _event_id,
		"now": _now_s(),
		"turn": int(director.get("_turn_id")),
		"text": str(director.get("_player_text")).strip_edges(),
		"paused": get_tree().paused,
		"speech_busy": _speech_busy(),
		"director_state": str(director.get("state")),
		"distance": main.player.global_position.distance_to(pony.global_position),
		"target_is_player": target == main.player or target == body,
	})


func _history_is_idle() -> bool:
	return state == State.IDLE


## The meter only advances during an act. A forced debug warning or stop runs here so it lands
## on the next frame after the Debug panel is closed.
func _tolerance_tick(delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE]:
		return
	var action: String = _history.take_debug()
	if not action.is_empty():
		if action == "warning":
			_tolerance_warn(1)
		elif action == "stop":
			_stop_with_her("debug")
		return
	_history.tolerance_tick(delta)


func _tolerance_event(event: Dictionary) -> void:
	if event.is_empty() or _stopped_by_her:
		return
	var decision: Dictionary = _history.tolerance_decision(event)
	if decision.is_empty():
		return
	var warning := int(decision.get("warning", 0))
	if warning > 0:
		_tolerance_warn(warning)
		return
	if bool(decision.get("stopped", false)) or bool(decision.get("stop", false)):
		_stop_with_her(str(decision.get("kind", "")))


func _tolerance_warn(level: int) -> void:
	var cue := "She doesn't like that." if level <= 1 else "She is warning you."
	_set_cue_override(cue, 4.0)
	_act_face_beat("warning")
	_queue_tolerance_warning(level)
	_log("neglect warning=%d tier=%s distress=%.1f kind=%s" % [
		level, str(_preferences.get("tolerance", "normal")),
		_history.distress(), _history.last_dislike()])


func _queue_tolerance_warning(level: int) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return
	if not _tolerance_warning_key.is_empty():
		main.memory.cancel_line(_tolerance_warning_key)
	var act_id := _event_id
	var event_id := "%s:tolerance_warning:%d" % [_event_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state in [State.POSING_IN, State.ACTIVE] \
			and _event_id == act_id
	var fallback := ("Don't do that." if level <= 1 else "I said stop that.") \
		+ " Begin with [annoyed] or [calm]."
	_tolerance_warning_key = _reaction_line(MEMORY.Reaction.TOLERANCE_WARNING,
		event_id, fallback, valid)


func _cancel_tolerance_warning() -> void:
	if not _tolerance_warning_key.is_empty() and is_instance_valid(main) and is_instance_valid(main.game):
		main.memory.cancel_line(_tolerance_warning_key)
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
		main.memory.note(MEMORY.NoteKind.STOPPED, _id, _event_id, MEMORY.StopReason.WITHDREW)
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
		str(_preferences.get("tolerance", "normal")), _history.distress(),
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
	var fallback := "Stop. I don't want to continue. Not now. Begin with [angry] or [sad]."
	if strict:
		fallback = "I told you to stop. Get off me and give me space. Begin with [angry] or [sad]."
	var event_id := "tolerance_stop_%s_%d" % [_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state == State.IDLE
	_reaction_line(MEMORY.Reaction.TOLERANCE_STOP, event_id, fallback, valid)


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
	_history.request_debug(kind)
	return true


## Store the strongest clean act per mare. The history system owns the eligibility and the text.
func _record_peak_memory() -> void:
	_history.record_peak_memory({
		"main": main,
		"pony_id": _id,
		"event_id": _event_id,
		"satisfaction": _peak_satisfaction,
		"both_matches": _act_both_matches,
		"dislikes": _act_dislikes,
		"liked_touch": _act_liked_touch,
		"liked_talk": _act_liked_talk,
		"player_talk": _last_player_talk,
		"her_at": _last_spoken_at(),
		"her_line": _last_spoken_line(),
	}, _act_spoken_at)


## A smack has already started the native cheek jiggle. The reaction facade carries it into the
## same tail-base propagation as a thrust.
func _on_smack_impact(strength: float) -> void:
	_reactions.smack(strength)


## Public rump anchor for the standing offer's rear cone.
func rump_anchor() -> Vector3:
	return _reactions.rump_point()


func cancel() -> void:
	_log("cancel state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE]:
		_act_ended_early = true
		_commit_summary(false)
		# The early summary already records this end. Keep the basic event only when history is
		# off or the summary was skipped, so the story never holds the same end twice.
		if _summary.is_empty():
			main.memory.note(MEMORY.NoteKind.CANCELLED, _id, _event_id)
		# Cancel act lines before restoring, then queue the intentional early-stop reaction.
		_end_act_lines(true)
		_restore_begin()
		if _act_lines_enabled():
			# Half the time she says nothing at all. When she does speak, it is a moment, not a
			# review or a next-time list.
			if randf() >= 0.5:
				var act_id := _event_id
				var expires := _now_s() + _cue_reaction_max_age_s
				var valid := func() -> bool:
					if not is_instance_valid(pony) or _event_id != act_id:
						return false
					if _now_s() <= expires:
						return true
					return main.memory.line_state(_end_early_key) == MEMORY.LineState.SPEAKING
				var key: String = _reaction_line(MEMORY.Reaction.END_EARLY, act_id,
					ACT_SUMMARY.early_end_prompt(_summary), valid)
				_end_early_key = key
				if not key.is_empty():
					var now := _now_s()
					_lines_service().note_reaction(key, "", now + _cue_reaction_max_age_s)
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
		_afterglow.cancel_close()
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
	_reactions.schedule_hearts()
	_reactions.hearts_burst_at(_reactions.dock_point())
	_set_face(0.3, CLIMAX_LIDS)
	_act_face_beat("climax")
	_end_act_lines(true)
	if is_instance_valid(main) and pony_climaxes == 1:
		main.memory.note(MEMORY.NoteKind.CLIMAXED, _id, _event_id)
	_queue_climax_reaction()
	_play_climax()
	# integration: her fluid hook.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("on_climax")
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("CLIMAX")


func _queue_climax_reaction() -> void:
	if not is_instance_valid(main) or not _act_lines_enabled():
		return
	var act_id := _event_id
	var count := pony_climaxes
	var climax_id := "%s:pony_climax:%d" % [act_id, count]
	var expires := _now_s() + _cue_reaction_max_age_s
	var valid := func() -> bool:
		if not is_instance_valid(pony) or _event_id != act_id or pony_climaxes != count:
			return false
		if _now_s() <= expires:
			return true
		return main.memory.line_state(_climax_reaction_key) == MEMORY.LineState.SPEAKING
	var key: String = _reaction_line(MEMORY.Reaction.CLIMAX, climax_id,
		"You have just climaxed during intimacy with Anon. Say one short sentence, at most 12 words, in your own voice. Begin with [surprised], [happy] or [calm]. Staying quiet is fine. Do not describe anatomy.",
		valid)
	_climax_reaction_key = key
	if key.is_empty():
		return
	var now := _now_s()
	_lines_service().note_reaction(key, cue, now + _cue_reaction_max_age_s)
	_log("utterance kind=reaction key=%s" % key)

## The pony climax ends on its own. It returns to ACTIVE unless the configured limit was
## reached; afterglow is the player's choice, not the climax state's automatic exit.
func _finish_climax() -> void:
	if _max_pony_climaxes > 0 and pony_climaxes >= _max_pony_climaxes:
		_enter_afterglow()
		return
	state = State.ACTIVE
	_stare_release_until = 0.0
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
	if not is_instance_valid(pony):
		return ""
	var verdict := _policy_verdict(ELIGIBILITY.Mode.START)
	if verdict == null or not verdict.base:
		return ""
	return CYCLE.prompt_note(cycle_phase())


## Short private relationship facts for normal dialogue. Empty outside a relationship runtime.
func _relationship_note() -> String:
	if not is_instance_valid(main) or not is_instance_valid(main.game):
		return ""
	_read_id()
	return RELATIONSHIP_CUE.note(main.memory.cue_facts(_id, _event_id).to_dict())


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	_read_id()
	var history := _history_note()
	if state not in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		if _warm_note:
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
	var policy := _policy_verdict(ELIGIBILITY.Mode.BOND)
	if policy == null or not policy.bond:
		return ""
	return RELATIONSHIP_CUE.lover_note(policy.relations.stored_bond)

## Grant the mod lover bond. Dialogue_consent calls this after a clear spoken agreement; the
## Debug action calls it for the aimed mare. Every gate is re-checked here because the classifier
## can answer while the world has moved on.
func grant_sex_bond(source := "dialogue", line := "") -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or pony.sleeping:
		return false
	if not _read_id():
		return false
	var policy := _policy_verdict(ELIGIBILITY.Mode.BOND)
	if policy == null or not policy.bond:
		return false
	var stage := policy.relations.stage
	var section: Dictionary = SEX_BOND.section()
	if SEX_BOND.bonded(section, _id):
		return true
	if not SEX_BOND.grant(section, _id, stage, policy.relations.love_level, source, line):
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
	return _hand_controller().any_active()

func _player_is_leaning_close() -> bool:
	return _lean_forward >= 0.35 or _lean_action_active or _kiss_controller().leaning_close()

func _player_is_close() -> bool:
	return _player_is_caressing() or _player_is_leaning_close()

func _afterglow_active() -> bool:
	return state == State.AFTERGLOW

func _afterglow_caressing() -> bool:
	return _hand_controller().any_active()

## The game's action executor owns `[stay: SECONDS]`. A permitted stay during the afterglow is
## her agreement to keep the moment going, so pause the self-end roll for that long. The
## afterglow facade owns the hold; the runtime only finds the game's executor.
func _bind_action_executor() -> void:
	_afterglow.bind_action_executor(_director(), _id)

func _enter_afterglow() -> void:
	_afterglow_begin()
	_wings_controller().begin_afterglow()

func _commit_afterglow() -> void:
	if not is_instance_valid(main):
		return
	_commit_summary(true)
	_record_peak_memory()
	for row: MEMORY.Witness in main.memory.witnesses(_id, _display_name, _serial, pony):
		_log("witness " + str(row.to_dict()))

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
	state = State.AFTERGLOW
	_afterglow.begin(pose_id, _summary)
	_bind_action_executor()
	cue = ""
	_cue_override = ""
	_cue_until = 0.0
	_stare_release_until = 0.0
	_set_face(0.85, AFTERGLOW_LIDS)
	_act_face_beat("afterglow")
	if is_instance_valid(_pose):
		if pose_id == CATALOG.STANDING:
			_pose.mode = "standing"
		else:
			_pose.mode = "afterglow"
			_pose.afterglow_pose = pose_id
		_pose.target_amount = 1.0
		_pose.amount = 1.0
	if pose_id == CATALOG.STANDING:
		_pose_service().set_tail_target(0.55)
		_pose_service().flick_tail(2)
	else:
		_pose_service().set_tail_target(0.35)
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")

func _afterglow_tick(delta: float) -> void:
	if state != State.AFTERGLOW:
		return
	_afterglow.advance(delta)
	# integration: keep the optional bed-body part tracking through afterglow.
	if is_instance_valid(_anatomy_act):
		_anatomy_act.call("afterglow_tick", delta, _anatomy_context())
	_afterglow.self_end_tick(delta)
	if state != State.AFTERGLOW or pose_id != CATALOG.STANDING:
		return
	_afterglow.close_tick(delta)

## The standing close window elapsed. The facade decided the reward; the runtime presents it.
func _on_stay_close(caressed: bool, reward: bool) -> void:
	if is_instance_valid(main):
		var impression := MEMORY.Impression.new()
		impression.id = _id
		impression.event_id = _event_id
		impression.slot = MEMORY.ImpressionSlot.STAY_CLOSE
		impression.mood = "happy" if reward else ""
		impression.romance = 1 if reward and caressed else 0
		main.memory.commit(impression)
	if not reward and caressed:
		if ACT_HISTORY.repair(ACT_HISTORY.section(), _id, 1, ACT_HISTORY.day_now()):
			ACT_HISTORY.save()
	_set_face(0.9, AFTERGLOW_CLOSE_LIDS)
	_reactions.hearts_burst()
	cue = ""

func close_hint() -> String:
	if state != State.AFTERGLOW or pose_id != CATALOG.STANDING:
		return ""
	return _afterglow.hint()

func _restore_begin() -> void:
	if state == State.IDLE or state == State.RESTORE:
		return
	_record_peak_memory()
	_afterglow.cancel_close()
	_stop_auto_thrust()
	_end_act_lines(true)
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	state = State.RESTORE
	# integration: act-only anatomy hides as soon as the act starts restoring.
	if is_instance_valid(_anatomy):
		_anatomy.call("apply_live")
	_restore_left = RESTORE_SECONDS
	_clear_face()
	_end_act_face()
	_wings_controller().release()
	if is_instance_valid(_pose):
		_pose.target_amount = 0.0
	_pose_service().set_tail_target(0.0)
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
	# Capture the bed before the session state is cleared: a normal end of a bed missionary act
	# returns Anon and her to it, but only when it did not go badly.
	var rejoin_bed: Node3D = null
	var rejoin_serial := _serial
	if rejoin_cuddle and pose_id == CATALOG.MISSIONARY \
			and source in ["bed_side", "already_lying"] and not _stopped_by_her \
			and _rejoin_wanted():
		rejoin_bed = bed
	# integration: close the anatomy act once, before the pose is freed.
	var was_standing := pose_id == CATALOG.STANDING
	if is_instance_valid(_anatomy) and _anatomy.has_method("end_act"):
		_anatomy.call("end_act")
	elif is_instance_valid(_anatomy_act):
		_anatomy_act.call("end")
		_anatomy_act.call("teardown")
		_anatomy_act.queue_free()
	_anatomy_act = null
	if was_standing:
		anatomy_facing(Basis.IDENTITY, 0.0)
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
		_end_act_face()
		_wings_controller().release()
	_unlock_player()
	if _camera_owned:
		_restore_camera()
	_release_stool()
	if is_instance_valid(pony):
		pony.remove_meta("sex_active")
	# integration: hide the player part when the act ends.
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_encounter"):
		service.call("player_encounter", false)
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
	# Deferred so `_finalize_session()` has started aftercare (and its navigator hold) first; the
	# rejoin retries until that hold and the bed's guest cooldown are gone.
	if rejoin_bed != null:
		_rejoin_bed_cuddle.call_deferred(rejoin_bed, rejoin_serial)

## One-time bookkeeping after the borrowed state is back. Idempotent: a failed start has no act
## to reset and must not start aftercare.
func _finalize_session(real_act: bool) -> void:
	if _session_finalized:
		return
	_session_finalized = true
	if real_act:
		_reset_after_act()

## Give the bed back: restore the pre-act scene and stand her. A bed missionary act that ended well
## is re-seated and re-invited by `_rejoin_bed_cuddle()` after the session is fully back to IDLE.
## A forced stop never reaches it; the world is going away or the pony is already invalid.
func _restore_posture(restore_pose: String, rejoin_cuddle: bool) -> void:
	_posture_owned = false
	if not is_instance_valid(pony):
		return
	# The act's own snapshot puts the player, the pony and the camera back, so the rejoin starts
	# from the same standing spot the act began at.
	if restore_pose == CATALOG.MISSIONARY:
		_missionary_camera_controller().restore_scene()
	if pony.get("posture") != null:
		pony.request_posture("stand")

## A normal bed missionary end returns to the cuddle: Anon lies back on the same bed and she is
## invited into its guest seat, where the stock `CuddleSession` picks her up. The act released the
## bed rest and stood both of them, so this is a fresh stock recline and a fresh guest invite. The
## stock closeness rule still decides (she must welcome hugs and be at least a friend), and a bad
## act or an upset mare stays standing. Every failure is logged and leaves her standing.
func _rejoin_bed_cuddle(bed_node: Node3D, act_serial: int) -> void:
	if not is_inside_tree() or not is_instance_valid(pony) or not is_instance_valid(bed_node):
		return
	if _serial != act_serial:
		return
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var body: Variant = main.player
	if not body.has_method("sit_on") or not body.has_method("toggle_couch_sleep"):
		_log("cuddle rejoin skipped reason=no_player_rest")
		return
	var rest: Variant = _bed_rest_for(bed_node)
	if rest == null:
		_log("cuddle rejoin skipped reason=no_bed_rest")
		return
	var seats: Variant = rest.get("seats")
	if not seats is Array or (seats as Array).size() < 2:
		_log("cuddle rejoin skipped reason=no_seats")
		return
	var player_seat: Variant = (seats as Array)[0]
	var guest_seat: Variant = (seats as Array)[1]
	if not player_seat is Node3D or not guest_seat is Node3D:
		_log("cuddle rejoin skipped reason=no_seats")
		return
	if body.get("seat") != player_seat:
		if not bool(body.call("sit_on", player_seat)):
			_log("cuddle rejoin failed reason=sit")
			return
	if not bool(body.get_meta("couch_sleeping", false)):
		if not bool(body.call("toggle_couch_sleep")):
			_log("cuddle rejoin failed reason=recline")
			return
	# The act restores her still standing on the mattress, and the bed's own front probe rejects a
	# floor half a metre below her feet. Put her on the clear floor beside the bed first.
	_stand_beside_bed(rest, guest_seat)
	await get_tree().create_timer(CUDDLE_REJOIN_SETTLE_S).timeout
	var deadline := Time.get_ticks_msec() + int(CUDDLE_REJOIN_WINDOW_S * 1000.0)
	var note := ""
	while Time.get_ticks_msec() < deadline:
		if not is_inside_tree() or not is_instance_valid(pony) or not is_instance_valid(bed_node):
			return
		if _serial != act_serial or state != State.IDLE:
			_log("cuddle rejoin cancelled reason=act")
			return
		if not bool(body.get_meta("couch_sleeping", false)):
			_log("cuddle rejoin cancelled reason=stood_up")
			return
		if bool(rest.call("open")) and bool(rest.call("invite", pony, guest_seat)):
			_log("cuddle rejoin invited bed=%s" % str(bed_node.name))
			return
		note = _rejoin_note(rest)
		await get_tree().create_timer(CUDDLE_REJOIN_RETRY_S).timeout
	_log("cuddle rejoin failed reason=timeout %s" % note)

## The game's live rest that owns this bed (`world/relationships/shared_bed.gd`). `_shared_bed_rest`
## only returns her transform; the rejoin needs the seats and the invite entry.
func _bed_rest_for(bed_node: Node3D) -> Variant:
	if not is_instance_valid(bed_node) or not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group("couches"):
		if not node is Node3D or not node.has_method("invite"):
			continue
		if node.get("_bed") != bed_node and node.get("bed_node") != bed_node:
			continue
		var seats: Variant = node.get("seats")
		if seats is Array and (seats as Array).size() >= 2:
			return node
	return null

## Stand her on the nearest clear floor beside the bed. The act's restore leaves her on the
## mattress, and `shared_bed._front_for()` drops a floor more than half a metre below her feet.
func _stand_beside_bed(rest: Node, seat: Node3D) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(seat):
		return
	var profile: Variant = pony.get("profile")
	var clearance := float(profile.get("clearance")) if profile != null else 1.2
	var radius := float(profile.get("radius")) if profile != null else 0.25
	var front: Variant = rest.call("approach", seat)
	var fallback: Vector3 = seat.global_position
	if front is Vector3 and (front as Vector3).is_finite():
		fallback = front
	var at: Vector3 = COUCH_EXIT.find_exit(pony, seat, fallback, clearance, radius)
	if not at.is_finite():
		_log("cuddle rejoin floor=no_space")
		return
	var pose: Transform3D = pony.global_transform
	pose.origin = at
	var euler: Vector3 = pose.basis.get_euler()
	if absf(euler.x) > 0.01 or absf(euler.z) > 0.01:
		# A support-recovery tilt would fight the collider every tick; keep the facing yaw.
		pose.basis = Basis(Vector3.UP, euler.y) * Basis.from_scale(pose.basis.get_scale())
	pony.reset_motion(pose)
	if pony.get("velocity") != null:
		pony.set("velocity", Vector3.ZERO)
	pony.reset_physics_interpolation()
	_log("cuddle rejoin floor=%s" % str(at))

## A compact state dump for the timeout line. Read-only: the stock invite stays the authority.
func _rejoin_note(rest: Node) -> String:
	var parts := PackedStringArray()
	if is_instance_valid(pony):
		var status: Dictionary = pony.posture_status() if pony.has_method("posture_status") else {}
		parts.append("posture=" + str(status.get("requested", "")))
		parts.append("grounded=" + str(pony.grounded()))
		var nav: Node = pony.get_node_or_null("Navigator")
		if nav != null:
			parts.append("nav=" + str(nav.get("command_owner")))
		var cooldowns: Variant = rest.get("_cooldowns")
		if cooldowns is Dictionary:
			var until := int((cooldowns as Dictionary).get(pony.get_instance_id(), 0))
			var left := until - Time.get_ticks_msec()
			if left > 0:
				parts.append("cooldown=%dms" % left)
	parts.append("fits=" + str(rest.get("_mare_fits")))
	return " ".join(parts)

## A bed missionary end that can return to the cuddle: desktop human Anon at the unforced end of an
## act that did not go badly. With act history off there is no summary, so the aftercare readiness
## rule is the fallback.
func _rejoin_wanted() -> bool:
	if _player_pony or _headset_view():
		return false
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return false
	if not _summary.is_empty():
		return str(_summary.get("grade", "neutral")) != "bad"
	return satisfaction >= float(_aftercare_min)

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
	_aftercare = AFTERCARE.new()
	_aftercare.set("pony", pony)
	_aftercare.set("runtime", self)
	_aftercare.set("body_language", healthy and satisfaction >= _aftercare_min)
	add_child(_aftercare)
	_start_post_act_face()

## The post-act face. The facade owns the lifetime and the warm note; the runtime gathers the
## scene values.
func _start_post_act_face() -> void:
	_bind_face()
	_face.start_post_act({
		"stopped": _stopped_by_her,
		"summary": _summary,
		"satisfied": satisfaction,
		"aftercare_min": _aftercare_min,
	})

func _start_mood_face(mood: String, face: String, blush: float, warm_note: bool) -> void:
	_bind_face()
	_face.start_mood_face(mood, face, blush, warm_note)

func _end_mood_face() -> void:
	_bind_face()
	_face.end_mood_face()

## Compatibility aliases: the lab's anger keys and the old call sites still use these names.
func _start_upset(mood: String) -> void:
	_bind_face()
	_face.start_upset(mood)

func _end_upset() -> void:
	_bind_face()
	_face.end_mood_face()

func _end_satisfied() -> void:
	_bind_face()
	_face.end_mood_face()

# --------------------------------------------------------------------------- act face

## The act's phase name for the face table. The state machine stays here.
func _act_phase() -> String:
	match state:
		State.POSING_IN:
			return "posing_in"
		State.ACTIVE:
			return "active"
		State.CLIMAX:
			return "climax"
		State.AFTERGLOW:
			return "afterglow"
	return ""


## First time uses the durable act history plus the world context, the same fact the cue prompt
## already gets.
func _read_first_time() -> bool:
	if not is_instance_valid(main) or not is_instance_valid(main.game) or _id.is_empty():
		return false
	var facts: MEMORY.CueFacts = main.memory.cue_facts(_id, _event_id)
	return facts.first_time


## Live presentation score for the auto climax face. This never writes the summary or history.
func _climax_quality_inputs() -> Dictionary:
	var touch_dislikes := 0
	for count: Variant in _act_touch_dislikes.values():
		touch_dislikes += int(count)
	return {
		"intensity_total": _act_intensity_total,
		"intensity_right": _act_intensity_right,
		"pattern_total": _act_pattern_total,
		"pattern_right": _act_pattern_right,
		"both_matches": _act_both_matches,
		"liked_touch": _act_liked_touch,
		"liked_talk": _act_liked_talk,
		"dislikes_total": touch_dislikes + _act_talk_dislikes,
		"distress": _history.distress(),
		"seeks_touch": PREFERENCES.seeks_touch(_preferences),
		"seeks_talk": PREFERENCES.seeks_talk(_preferences),
		"overwhelmed": _overwhelmed > 0.0,
	}


## The facade is bound in `_ready`; a suite that builds a runtime without entering the tree
## binds it on the first call.
func _bind_face() -> void:
	if _face.pony != pony or _face.host != self:
		_face.bind(pony, self)


func _act_face_beat(moment: String) -> void:
	_bind_face()
	if not _feature("act_faces") or not is_instance_valid(pony):
		return
	_face.debug_enabled = _feature("face_debug")
	var ctx := {
		"enabled": true,
		"debug": _face.debug_enabled,
		"first_time": _first_time,
		"tolerance": str(_preferences.get("tolerance", "normal")),
	}
	if moment == "climax":
		ctx["climax_mode"] = _act_climax_mode
		ctx["quality"] = _climax_quality_inputs()
	elif moment == "afterglow":
		ctx["summary"] = _summary
	_face.beat(moment, ctx)


func _current_dialogue_face() -> String:
	_bind_face()
	return _face.dialogue_face()


func _set_act_face(face: String, hold_s: float) -> bool:
	_bind_face()
	_face.debug_enabled = _feature("face_debug")
	return _face.set_act_face(face, hold_s)


func _end_act_face() -> void:
	_bind_face()
	_face.debug_enabled = _feature("face_debug")
	_face.end_face()


func _sync_act_face_settings() -> void:
	_bind_face()
	_face.sync_settings(_feature("act_faces"), _feature("face_debug"))


## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_act_face(face: String) -> bool:
	_bind_face()
	_face.debug_enabled = _feature("face_debug")
	return _face.force_face(face)


## Debug view for the "Show act face" action.
func act_face_rows() -> Array[String]:
	_bind_face()
	var base_mood := ""
	if is_instance_valid(main) and is_instance_valid(main.game) and not _id.is_empty():
		var facts: MEMORY.CueFacts = main.memory.cue_facts(_id, _event_id)
		base_mood = facts.mood
	return _face.rows({
		"state": state,
		"hud_mood": mood,
		"base_mood": base_mood,
		"act_faces": _feature("act_faces"),
		"climax_mode": _act_climax_mode,
		"blush_arc": _feature("blush_arc"),
	})

# --------------------------------------------------------------------------- checks

func _check_running() -> void:
	if not is_instance_valid(pony):
		force_stop()
		return
	if state == State.ACTIVE or state == State.POSING_IN or state == State.CLIMAX:
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
	var policy := _policy_verdict(ELIGIBILITY.Mode.MID_ACT)
	return policy != null and not policy.stop

func _stop(reason: String) -> void:
	_log("stop reason=%s state=%d pony=%s" % [reason, state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX]:
		main.memory.note(MEMORY.NoteKind.STOPPED, _id, _event_id, _stop_reason(reason))
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
	var scales := SETTINGS.block("caress.palm_scale.")
	return float(scales.get(_size_name(), 1.0))


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
	_sync_act_facts()
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
	_hand_controller().return_tick()
	if not _act_actions_allowed():
		_hand_controller().stop_inputs()
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
		_hand_controller().stop_inputs()
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
		_hand_controller().tick(delta)
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
	_hand_controller().tick(delta)
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
	_hand_controller().smack()

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
		_hand_controller().start_reach(shoulder)
	_log("action fire pose=%s side=%.2f kind=%s shoulder=%s" % [
		pose_id, side, _lean_action_kind, shoulder])

func _end_lean_action() -> void:
	if _lean_action_kind == "reach":
		_hand_controller().end_reach()
		_forced_glance = ""
		_standing_camera_controller().clear_glance()
	_lean_action_active = false
	_lean_action_side = 0.0
	_lean_action_kind = ""

func _reset_lean_state() -> void:
	_end_lean_action()
	_hand_controller().reset()
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

## Which missionary base is in charge and why, from the pose session.
func pose_base_info() -> Dictionary:
	return _pose_service().base_info()


## True when the missionary asset loaded. The act refuses to start otherwise: there is no fallback
## missionary pose any more.
func _authored_pose_ready() -> bool:
	return _pose_service().authored_ready()


## Why the missionary pose asset is unusable, for the gate row and the start log.
func _authored_pose_reason() -> String:
	return _pose_service().authored_reason()


## The authored body bones the live rig lacks, cached per skeleton by the pose session.
func _pose_rig_missing() -> Array:
	return _pose_service().rig_missing()


## The gate row's reason, naming the first few bones and counting the rest.
func _pose_rig_reason(missing: Array) -> String:
	return _pose_service().rig_reason(missing)


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
		_pose_service().apply_render(sk)
	# The eye camera reads his posed head, so it has to run after this write, not from the physics
	# tick where the pose is one frame older.
	if _free_camera_active and str(SETTINGS.camera_mode.get_value()) == "eye":
		_missionary_camera_controller().tick()


## The render-time placement trace, driven by the pose session.
func _pose_idle_sample() -> void:
	_pose_service().idle_sample(state)


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
func pose_state_rows() -> Array:
	return _pose_service().state_rows(state)


## One line with where the pose actually put her, once the weight settles.
func _log_pose_settled() -> void:
	_pose_service().log_settled(state, Callable(self, "_anon_pose_diag_row"))


## The posed Anon body's diagnostic row, or silence when the act has no Anon body.
func _anon_pose_diag_row() -> String:
	if not is_instance_valid(_missionary_anon):
		return ""
	return str(_missionary_anon.call("diag_row", missionary_face_point(), missionary_vulva_point()))


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
	_sync_act_facts()
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
	_hand_controller().reset()
	_release_free_camera_lock()
	_standing_anon_controller().remove()
	_restore_eye_override()
	_missionary_camera_controller().release()
	_sync_act_facts()
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
		_act_audio.play_climax_wet(_reactions.dock_point())
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
	return _readiness.thrusts_per_second()

func _bed_audio_point() -> Vector3:
	if is_instance_valid(bed):
		return bed.global_position + Vector3.UP * 0.35
	return _reactions.rump_point()

func _snout() -> Vector3:
	var boop: Variant = pony.get("boop_node")
	if is_instance_valid(boop) and boop.has_method("nose_world"):
		return boop.call("nose_world")
	return pony.global_position + Vector3.UP * 1.0

## The kiss foreleg overrides are global AffectionPose settings. Restore them if the world
## closes or the mod is switched off mid-kiss.
func _exit_tree() -> void:
	_kiss_controller().restore_forelegs()
	_release_stool()
	_end_tail_tuck()
	# integration: never leave the anatomy nodes or the per-act controller behind.
	var was_standing := pose_id == CATALOG.STANDING
	if is_instance_valid(_anatomy) and _anatomy.has_method("end_act"):
		_anatomy.call("end_act")
	elif is_instance_valid(_anatomy_act):
		_anatomy_act.call("end")
		_anatomy_act.call("teardown")
		_anatomy_act.queue_free()
	_anatomy_act = null
	if was_standing:
		anatomy_facing(Basis.IDENTITY, 0.0)
	if is_instance_valid(_missionary_anon):
		_missionary_anon.call("remove")
		_missionary_anon.queue_free()
		_missionary_anon = null
	_stop_vr_act()
	if is_instance_valid(_anatomy):
		var service: Variant = main.get("anatomy") if is_instance_valid(main) else null
		if service != null and service.has_method("detach_controller"):
			service.call("detach_controller", pony)
		else:
			_anatomy.call("detach")
			_anatomy.queue_free()
		_anatomy = null
	_face.shutdown()
