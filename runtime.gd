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
const SATISFIED := preload("res://mods/unfplap/satisfied.gd")
const AFFECTION_POSE := preload("res://world/relationships/affection_pose.gd")
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
const CAESS := preload("res://mods/unfplap/standing_caress.gd")
const KISS := preload("res://mods/unfplap/kiss_control.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/standing_anon.gd")
const SOUND := preload("res://mods/unfplap/act_sound.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
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
const STANDING_HEAD_NECK_HEIGHT_M := 1.0
## Canon is small enough that the standing shot needs a lower eye line.
const CANON_STANDING_CAMERA_DROP_M := 0.10
## JRHNBR is tall enough that the standing shot needs a higher eye line.
const MOUNTING_STANDING_CAMERA_LIFT_M := 0.10
## Anon's spine length, used to turn the standing torso angle into head/camera travel.
const ANON_TORSO_LEN_M := 0.65
## Standing Anon thrust: mouse depth (only lightly smoothed) moves the hip. This is position, not
## speed; the camera's speed-driven thrust is separate.
## Safety cone for AnonPony's own body-yaw limit; the desktop act camera does not free-look.
const LOOK_YAW_LIMIT := 0.785398
const LOOK_PITCH_LIMIT := 0.785398
## Standing after the climax: Anon eases back before the act restores.
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Standing after the climax: held afterglow; Anon stays put.
## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5

## Standing keeps her body facing away but lets her glance back over a shoulder now and then.
const GLANCE_MIN_INTERVAL := 5.0
const GLANCE_MAX_INTERVAL := 9.0
const GLANCE_HOLD := 1.8
const GLANCE_YAW := 3.0
const GLANCE_BACK_PITCH := 1.2
const GLANCE_BACK_CHANCE := 0.5
## Fade time for the extra head-back glance pose; prevents the head snapping back to low.
## Yaw limit for a look-back glance. Raised 20% from 1.35 so she turns farther over her shoulder.
## Jiggle placement on the flank. The thrust scale is reduced 20% from the review pass; the
## native smack keeps its own strength.
const JIGGLE_HEIGHT := 0.78
const JIGGLE_BACK := 0.12
## `_start_jiggle` clamps strength to 0.3..1, so weak thrusts still move a little.
const JIGGLE_MIN_STRENGTH := 0.30
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
var thrust_up := true

var _pose
var _tail
## Idle standing invitation. Kept separate from the act's pose/tail so Y can take over cleanly.
var _presenting := false
var _present_turning := false
var _present_turn_started := 0.0
var _present_turn_last_yaw := 0.0
var _present_turn_still := 0.0
var _present_turn_rate_saved := -1.0
var _present_turn_rate_owned := false
var _present_pose
var _present_glance_back := false
var _present_glance_sign := 1.0
var _present_glance_sign_set := false
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
var _lean_forward := 0.0
var _lean_side := 0.0
var _lean_view_forward := 0.0
var _lean_view_side := 0.0
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
var _missionary_head_roll := 0.0
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
var _aftercare: Node
var _satisfied: Node
var _satisfaction_tween: Tween
## The act's base kiss normally rears and lifts both forelegs; "planted" zeroes those two
## shared settings for the kiss and restores them when it ends.
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
var _flank: Node
var _jiggle_logged := false
var _dock_jiggle_mesh: MeshInstance3D
var _dock_jiggle_material: ShaderMaterial
var _dock_jiggle_original: Material
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


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


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
	var bed_creaks := bool(_features.get("bed_creaks", false))
	if foley or vocals or climax:
		_ensure_act_audio(foley, vocals, climax, bed_creaks)
	elif is_instance_valid(_act_audio):
		_act_audio.set_enabled(false, false, false)
	var thrust_controls := SETTINGS.thrust_controls()
	thrust_up = bool(thrust_controls.get("up", true))
	_thrust_pixels_per_full = float(thrust_controls.get("pixels_per_full", 480.0))
	var camera_thrust := SETTINGS.camera_thrust_controls()
	_camera_surge = float(camera_thrust.get("surge", 0.0))
	_camera_bob = float(camera_thrust.get("bob", 0.0))
	_presentation_cfg = SETTINGS.presentation_controls(pose_id)
	if pose_id == CATALOG.STANDING:
		_kiss_controller().apply_live_settings()
	elif pose_id == CATALOG.MISSIONARY:
		_sync_missionary_pose_config()
	# Nudge the frozen missionary anchor only when the framing control actually changed, so a taste
	# edit does not snap the shot. Move by the delta instead of recomputing from the pony: she
	# has settled since the start anchor was taken and the bed reference may be gone.
	if pose_id == CATALOG.MISSIONARY and state != State.IDLE:
		_missionary_camera_controller().apply_framing()
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
		_missionary_camera_controller().hide_avatar()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", 1.0)
	# The optional debug pin reuses the boop-fluster response: it pins the ears back along the
	# skull. Off keeps normal ears; the blush and stare() eyelids are independent.
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster") and _feature("act_ear_pin"):
		expressions.call("fluster", 1.2)
	_wings_controller().tick(delta, pose_id, satisfaction, _act_seconds)


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
				_pose.look_point = kiss.target(kiss_view)
			elif pose_id == CATALOG.MISSIONARY:
				# Look at Anon, not at the framing view: the shot now sits behind her neck and a
				# camera there would demand a half-turn and flip her head side to side.
				var head_view: Camera3D = kiss_view if is_instance_valid(kiss_view) else view
				_pose.look_point = _missionary_camera_controller().head_look_point(head_view)
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
	_kiss_controller().tick(delta)
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


## Offer eligibility before she is in position. Unlike can_start(), this does not require the
## pony to be lying or the player to be ready; those stay in the final Y gate.
func can_offer(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	if state != State.IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	if not _relationship_ok() or not _player_form_ok():
		return false
	if get_tree().paused or not _conversation_ok():
		return false
	if pony.sleeping:
		return false
	if bool(pony.get_meta("sex_active", false)) or pony.has_meta("sex_aftercare"):
		return false
	if _cuddle_active() and not _cuddle_start_override(pose, act_source):
		return false
	if not _free_of_affection():
		return false
	if not _nav_owner_allows(pose, act_source):
		return false
	if pose == CATALOG.MISSIONARY:
		var found: Node3D = _resolve_bed(pose, act_source, bed_in)
		if found == null or main.bed_occupied(found, pony):
			return false
		return true
	if pose == CATALOG.STANDING:
		return not pony.is_held() and not pony.has_meta("seated")
	return false


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

func start(pose: String, bed_in: Variant, act_source: String, y_allowed := false) -> bool:
	if not y_allowed:
		_log("start blocked by Y scenario gate pose=%s source=%s" % [pose, act_source])
		return false
	if not can_start(pose, act_source, bed_in):
		_log("start blocked pose=%s source=%s pony=%s" % [pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		return false
	# Remove the idle standing invitation and its request face before the act builds its own pose.
	set_request_face(false)
	clear_presentation()
	_end_satisfied()
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
	_standing_camera_controller().reset()
	bed = _resolve_bed(pose, act_source, bed_in)
	if pose == CATALOG.MISSIONARY and bed == null:
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
		_standing_camera_controller().begin_facing(standing)

	_build_pose()
	_missionary_head_roll = float(_pose_cfg.get("head_roll", 0.0))
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


## Idle standing invitation: turn her back to Anon, look over the shoulder, bow and lift the tail.
## This is not the act: no player lock, camera, HUD, sex_active or state change. Y remains the
## only way to begin the real act.
func present_standing() -> bool:
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
	_log("present standing target_yaw=%.2f turn=%s" % [
		_present_target_yaw, "stepping" if _present_turning else "direct"])
	return true


## Create the idle pose and tail once she has finished turning. Doing this before the turn
## let the spread/bow pose fight the planted hooves and twisted the legs.
func _attach_present_pose() -> void:
	if not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(_id, CATALOG.STANDING)
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_present_pose = POSE.new()
		_present_pose.name = "UnfplapPresentPose"
		_present_pose.mare = pony
		_present_pose.mode = "standing"
		_present_pose.pose_config = SETTINGS.pose(_id, CATALOG.STANDING)
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
	_present_glance_back = true
	_present_glance_sign_set = false


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
			_log("present standing turn snap error=%.2f target=%.2f" % [error, _present_target_yaw])
		else:
			_present_yaw = pony.rotation.y
			_present_target_yaw = _present_yaw
			_log("present standing turn settled yaw=%.2f" % _present_yaw)
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
	_present_glance_back = false
	_present_glance_sign_set = false
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
## physics, after the navigator and locomotion, like the act's standing facing lock.
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
	_present_glance_back = true
	var secondary: Variant = pony.get("secondary")
	if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
		secondary.call("look_toward", _present_glance_angles(), 0.45)
	_present_aim_eyes()


func _present_glance_angles() -> Vector3:
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
	if not _present_glance_sign_set:
		_present_glance_sign = signf(raw) if absf(raw) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
		_present_glance_sign_set = true
	var yaw: float = _present_glance_sign * absf(raw)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	if _present_glance_back:
		var back_pitch := float(_pose_cfg.get("glance_back_pitch", 1.2)) * 1.2
		return Vector3(clampf(pitch + back_pitch, -0.25, 1.44),
			clampf(yaw, -MOTION.GLANCE_BACK_YAW, MOTION.GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg.get("glance_yaw", 3.0))
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)


func _present_aim_eyes() -> void:
	if not is_instance_valid(pony):
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	var view: Camera3D = main.camera() if is_instance_valid(main) else null
	var target: Vector3 = view.global_position if is_instance_valid(view) else pony.global_position
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)


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
	_kiss_controller().restore_forelegs()
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


func debug_float_missionary(seconds: float) -> void:
	if state != State.IDLE or not is_instance_valid(pony) or _debug_pose_active:
		_log("float missionary: busy")
		return
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		return
	_debug_pose_active = true
	_debug_pose_saved = pony.global_transform
	pony.global_position.y += 0.45
	pony.reset_physics_interpolation()
	_debug_pose = POSE.new()
	_debug_pose.name = "UnfplapMissionaryDebugPose"
	_debug_pose.set("mare", pony)
	_debug_pose.set("mode", "missionary")
	_debug_pose.set("amount", 0.0)
	_debug_pose.set("target_amount", 1.0)
	_debug_pose.set("look_point", main.camera().global_position if main.camera() != null else pony.global_position)
	(skeleton as Skeleton3D).add_child(_debug_pose)
	_keep_chin_last()
	_log("float missionary pony=%s seconds=%.1f" % [str(pony.name), seconds])
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(pony) and _debug_pose_active:
		pony.global_transform = _debug_pose_saved
		pony.reset_physics_interpolation()
	if is_instance_valid(_debug_pose):
		_debug_pose.queue_free()
	_debug_pose = null
	_debug_pose_active = false


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose first keeps hind spread/rump drop overrides, then the presentation neck controls win.
func _sync_missionary_pose_config() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(_id, CATALOG.MISSIONARY)
	_pose_cfg["neck1_deg"] = float(_presentation_cfg.get("neck1_deg", 7.5))
	_pose_cfg["neck2_deg"] = float(_presentation_cfg.get("neck2_deg", 7.5))
	_pose_cfg["neck_roll_deg"] = float(_presentation_cfg.get("neck_roll_deg", 0.0))
	_pose_cfg["head_pitch_deg"] = float(_presentation_cfg.get("head_pitch_deg", 0.0))
	_pose_cfg["head_roll"] = float(_presentation_cfg.get("head_roll_deg", 0.0))
	if is_instance_valid(_pose):
		_pose.pose_config = _pose_cfg
	_missionary_head_roll = float(_pose_cfg.get("head_roll", 0.0))
	if is_instance_valid(_pose):
		_pose.head_roll = _missionary_head_roll


func _build_pose() -> void:
	_free_pose()
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_pose = POSE.new()
		_pose.name = "UnfplapPose"
		_pose.mare = pony
		_pose.mode = "standing" if pose_id == CATALOG.STANDING else "missionary"
		_pose.pose_config = SETTINGS.pose(_id, pose_id)
		_pose.head_roll = _missionary_head_roll
		_pose.look_point = main.camera().global_position if main.camera() != null else pony.global_position
		_pose.amount = 0.0
		_pose.target_amount = 1.0
		(skeleton as Skeleton3D).add_child(_pose)
		if pose_id == CATALOG.STANDING:
			if _feature("standing_body_sway"):
				_install_body_sway(skeleton)
			if _feature("thrust_ear_twitch"):
				_install_ear_twitch()
		elif _feature("missionary_body_motion"):
			_install_prone_sway(skeleton)
		_keep_chin_last()
	if pose_id != CATALOG.STANDING:
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
	if is_instance_valid(_tail):
		_tail.queue_free()
	_tail = null


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
	_standing_anon_controller().reset_phase()
	_standing_camera_controller().reset_depth()
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
	_wings_controller().on_thrust(impact)
	_thrust_jiggle(impact)
	if pose_id == CATALOG.STANDING and is_instance_valid(_tail):
		_tail.call("thrust", impact * _jiggle_size_scale())
	if pose_id == CATALOG.STANDING:
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
		if is_instance_valid(_satisfied):
			return "- You are still warm and satisfied after sex with Anon. Keep a relaxed, affectionate tone; do not act stiff or businesslike."
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
	_record_peak_memory()
	MEMORY.commit_climax(main.game, _id, _display_name, _event_id)
	MEMORY.afterglow_event(main.game, _id, _display_name, _event_id, pose_id)
	WITNESS.commit(main.game, _id, _display_name, _serial, pony)


## Both poses share the held afterglow; standing adds the inside event, the close window and
## a slightly lifted tail.
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
		_inside_aftermath()
		_begin_close_window()
	if is_instance_valid(main) and is_instance_valid(main.hud):
		main.hud.set_state("AFTERGLOW")


## Standing only: tell her Anon came inside her. Normal dialogue resumes from here.
func _inside_aftermath() -> void:
	if not is_instance_valid(main):
		return
	MEMORY.inside_event(main.game, _id, _display_name, _event_id)


## Standing afterglow only. The HUD and this timer own the stay-close invitation; normal dialogue
## resumes instead of a scripted stay-close line.
func _begin_close_window() -> void:
	if pose_id != CATALOG.STANDING:
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
	_end_act_lines(true)
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	state = State.RESTORE
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
		_missionary_camera_controller().resume_cuddle()
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



func _stand_after_pose() -> void:
	if is_instance_valid(pony) and pony.get("posture") != null:
		pony.request_posture("stand")


func force_stop() -> void:
	# Defensive: every stop path must leave the quick slots in their pre-act state.
	_set_inventory_hud_hidden(false)
	if state == State.IDLE:
		set_request_face(false)
		_kiss_controller().restore_forelegs()
		clear_presentation()
		return
	_restore_now()


func _restore_now() -> void:
	_end_act_lines(true)
	_set_inventory_hud_hidden(false)
	set_request_face(false)
	_kiss_controller().restore_forelegs()
	_restore_face_turn()
	if is_instance_valid(pony):
		_clear_face()
		_wings_controller().release()
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
	if satisfaction >= _aftercare_min:
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


## Standing presentation only. The accepted Anon rig's hands read a little large beside a Canon
## pony; JRHNBR needs a smaller correction. Other presets keep the authored size.
static func standing_palm_scale_for(size_name: String) -> float:
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
	_camera_basis_ready = false
	_reset_lean_state()
	_standing_anon_controller().reset_phase()
	_missionary_camera_controller().reset_look()
	_standing_camera_controller().reset()
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


## Lean/caress remain live through the standing afterglow; missionary afterglow stays passive.
func _act_actions_allowed() -> bool:
	return state in [State.ACTIVE, State.CLIMAX] \
		or (state == State.AFTERGLOW and pose_id == CATALOG.STANDING)


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
		_caress_controller().stop_inputs()
		_end_lean_action()
		_lean_forward = move_toward(_lean_forward, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
		_lean_side = move_toward(_lean_side, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
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
	if _feature("idle_camera_sway"):
		# Idle breathing. The feature toggle is the only way to stop the drift when the
		# player is not leaning.
		_hold_rock_clock += delta
		_lean_view_forward = clampf(_lean_view_forward
			+ sin(_hold_rock_clock * 0.80) * MOTION.HOLD_SWAY_FORWARD, -1.0, 1.0)
		_lean_view_side = clampf(_lean_view_side
			+ sin(_hold_rock_clock * 0.57 + 1.1) * MOTION.HOLD_SWAY_SIDE, -1.0, 1.0)
	_lean_action_tick()
	_kiss_controller().standing_tick()
	_caress_controller().tick(delta)
	if pose_id == CATALOG.STANDING:
		_standing_camera_controller().apply_lean_look()




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
	if _lean_action_kind == "kiss":
		_kiss_controller().start_lean_kiss(side)
		_log("kiss side=%.2f base=%s" % [side, str(_kiss_controller().base_active())])
	elif _lean_action_kind == "reach":
		shoulder = "L" if side < 0.0 else "R"
		_forced_glance = shoulder
		_standing_camera_controller().hold_glance()
		_caress_controller().start_reach(shoulder)
	_log("action fire pose=%s side=%.2f kind=%s shoulder=%s" % [
		pose_id, side, _lean_action_kind, shoulder])





func _end_lean_action() -> void:
	_kiss_controller().end_standing()
	if _lean_action_kind == "kiss":
		_kiss_controller().end_lean_kiss()
	elif _lean_action_kind == "reach":
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
	_side_return_armed = false
	_hold_rock_clock = 0.0


func _play_mouth_kiss() -> void:
	if is_instance_valid(_act_audio) and _act_audio.foley_enabled():
		_act_audio.play_mouth_kiss(_snout())
		return
	_sounds_controller().play_mouth_kiss(_snout())







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


## Restore the player's yaw/pitch captured at act start. Free look and the standing look cone can
## leave the rig yawed after the act, which makes W/D move relative to a different facing than the
## camera. Restoring the captured look keeps movement and view aligned.
func _restore_look() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var yaw := _restore_yaw
	# Missionary restores the exact start snapshot; use its rig yaw rather than the later capture.
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
	_log("look restored yaw=%.3f (captured %.3f) pitch=%.3f" % [yaw, _restore_yaw, _restore_pitch])









func _restore_camera() -> void:
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

## Create the optional audio node on first use, or update its flags if it already exists.
## This keeps act_audio.gd and its pack streams out of a both-flags-off act.
func _ensure_act_audio(foley: bool, vocals: bool, climax: bool, bed_creaks := false) -> void:
	if is_instance_valid(_act_audio):
		_act_audio.set_enabled(foley, vocals, climax, bed_creaks)
		return
	var audio_script: Script = load(ACT_AUDIO_PATH)
	if audio_script == null:
		return
	_act_audio = audio_script.new()
	_act_audio.name = "UnfplapActAudio"
	add_child(_act_audio)
	_act_audio.setup(foley, vocals, climax, bed_creaks)


func _start_audio() -> void:
	_stop_audio()
	_bed_soft = is_instance_valid(bed) \
		and ("couch" in bed.name.to_lower() or "sofa" in bed.name.to_lower()
			or "cloth" in bed.name.to_lower())
	var foley := _feature("act_foley")
	var vocals := _feature("act_vocals")
	var climax := _feature("act_climax")
	var bed_creaks := bool(_features.get("bed_creaks", false))
	if foley or vocals or climax:
		_ensure_act_audio(foley, vocals, climax, bed_creaks)
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


func _play_kiss() -> void:
	# With act foley on, the depth-crossing trigger owns the impact. Keeping this silent avoids a
	# second plap when the stroke closes on the mouse reversal.
	if is_instance_valid(_act_audio) and _act_audio.foley_enabled():
		return
	# Use the mod-owned player in both poses. Calling the game's boop `play_kiss()` increments her
	# kiss counter, and pony_awareness then tells the AI "The player kissed your face." during sex.
	_sounds_controller().play_kiss(_rump_point())


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
	if is_instance_valid(_satisfied):
		_satisfied.queue_free()
		_satisfied = null
