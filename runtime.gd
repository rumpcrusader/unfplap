extends Node
## One per pony. Holds the act state machine and all per-act state. It never edits game files.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const REST_REJOIN := preload("res://mods/unfplap/rest/service.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/service.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const TAIL_TUCK := preload("res://mods/unfplap/poses/tail_tuck.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/camera/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_CHANGE_ACT_HOST := preload("res://mods/unfplap/body_change/act_host.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const ACT_HOST := preload("res://mods/unfplap/anatomy/act_host.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
## Loaded lazily so both audio flags off never load the pack streams or the catalogue.
const ACT_AUDIO_PATH := "res://mods/unfplap/audio/service.gd"

const State := ACT_STATE.State

const READINESS_MAX := 100.0
const CLIMAX_SECONDS := 5.0
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## A player-requested reveal is the act's one exceptional beat; its heat, peak, cue and memory
## mark are the provider policy's, not the base runtime's. The handover owns the form flags.
## The Agreement start's answer: a transient row or an unsettled presentation keeps waiting; a
## technical rollback is a start failure.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1
const AGREEMENT_FAILED := 2

## The pony this runtime presents. Assigning a body rebinds the pose session's pony once.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_pose_session.bind(self, value if is_instance_valid(value) else null)

var _pony_node: Node = null

var state: int = State.IDLE
var pose_id := ""
var source := ""
var bed: Node3D
## The act's readiness system; see `readiness/service.gd`. The public act values below forward to it.
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
## Public: penetration 0..1, forwarded to the readiness stroke state.
var depth: float:
	get:
		return _readiness.depth
	set(value):
		_readiness.depth = value
## Public: how far the tip has passed her lips, in metres. It never goes behind them: the tip rests
## at her entrance and the depth stays at zero there.
var penetration_m: float:
	get:
		return _readiness.penetration_m
	set(value):
		_readiness.penetration_m = value

## The act's pose session: the pose modifier, the authored missionary base, the bed frame, the
## extra modifiers, the bone snapshots and the pose diagnostics. See `poses/service.gd`.
var _pose_session: RefCounted = POSE_SESSION.new()
## The scene gate: the live state, navigator, bed, cuddle, player and pose rows. See
## `scene_gate/service.gd` and `docs/scene_gate.md`.
var _scene: RefCounted = SCENE_GATE.new()
## The bed/couch rest and cuddle rejoin. See `rest/service.gd` and `docs/rest.md`.
var _rest: RefCounted = REST_REJOIN.new()
## The act camera session: the lean, the shot smoothing, the free look, the free-camera lock, the
## standing eye override and the captured player look. See `camera/service.gd` and `docs/camera.md`.
var _act_camera: RefCounted = ACT_CAMERA.new()
## The per-act anatomy bridge: the persistent controller, the per-act handle, the typed context,
## the missionary body and the VR controller. See `docs/anatomy.md`.
var _anatomy_bridge: RefCounted = ANATOMY.new_act(_anatomy_host())
## Reused typed act context. The runtime writes it; the presentation controllers read it instead of
## reaching into this node. See `shared/act_facts.gd`.
var _act_facts: RefCounted = ACT_FACTS.new()
## The standing placement math. The runtime fills its facts and keeps the ordered start adapters.
var _placement: PLACEMENT = null
## Reused placement facts. One object per runtime; the runtime writes it before each call.
var _placement_facts: PLACEMENT.Facts = null

## The act's dialogue service: scheduler, prompt assembly, reactions and the bystander line.
var _act_dialogue: RefCounted = ACT_DIALOGUE.new(_act_facts)
## Debug perf probe: timed chunks report here and one summary prints per window. See `shared/perf.gd`.
var _perf_probe := PERF.new()
## Cached gate for the idle probe. Set once in `_ready()` and again on every live settings edit, so
## no tick reads the entry node's flags.
var idle_perf := false
## Idle standing invitation. Kept separate from the act's pose/tail so the act key can take over
## cleanly.
## The `POSING_IN` timer: the pose settles into the act after this many seconds.
var _pose_in_left := 0.0
## Estrus is derived from the world day and her relationship, so it is resolved once per tick and
## the HUD card reads the cached flag.
var _cycle_heat := false
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
## A body swap keeps the act alive but stops its ticks. The handover owns the typed change, the
## adopted body and the current pose id until the one resume; `_end_session()` is still the only
## exit.
var _handover: BODY_CHANGE_ACT = null
## The handover's pause overlay, read-only here: the handover is its one writer.
var _suspended: bool:
	get:
		return _handover != null and _handover.suspended
## Keep the live `Z` shape when the resume re-reads settings instead of treating it as a settings
## edit. The next act's snapshot still follows the saved setting.
var _preserve_auto_shape_on_snapshot := false
## `reparent()` runs `_exit_tree()`. The handover moves the live runtime between bodies, so that
## signal must not run the world-close teardown it exists for.
var _swapping_parent := false
## The act's afterglow phase: the standing close window and the presentation it asks for.
## See `afterglow/service.gd` and `docs/afterglow.md`.
var _afterglow: RefCounted = AFTERGLOW.new()
var _player_pony := false
## The act's scene ownership. The runtime keeps the act state and the teardown order; the service
## owns the flags. See `scene_hold/service.gd`.
var _hold: RefCounted = SCENE_HOLD.new()
## Act-session ownership: each flag marks external state this act took and must give back.
## `_end_session()` checks them, so a start that failed early restores only what it took. The
## camera flags live on `_act_camera`; the navigator and player flags on `_hold`.
var _posture_owned := false
var _session_finalized := false
var _id := ""
var _profile: Dictionary = {}
var _features: Dictionary = {}
## The act's caress surface level, snapshotted from the settings so the engine never reads them.
var _caress_quality: String
var _preferences: Dictionary = {}
var _act_prompts: Dictionary = {}
var _max_pony_climaxes: int
var _cue_gap: float
## The cue/utterance pacing and the oral soft-kiss cue. The oral turn owns its idle timer.
var _cue_override_seconds: float
var _cue_base_stable_s: float
var _cue_override_stable_s: float
var _cue_utterance_gap_s: float
var _cue_demand_gap_s: float
var _cue_demand_repeat_s: float
var _cue_max_age_s: float
var _cue_reaction_max_age_s: float
var _cue_release_hold_s: float
var _cue_overwhelmed_s: float
var _touch_cooldown_s: float
var _talk_cooldown_s: float
var _receptive_seconds: float
var _act_spoken_at := -1e9
var _act_ended_early := false
## The act's summary, grade and peak record; see `summary/service.gd`. The runtime reads it as
## `_summary_service.summary`.
var _summary_service: RefCounted = SUMMARY.new()
var _stopped_by_her := false
var _tolerance_warning_key := ""
var _end_early_key := ""
var _climax_reaction_key := ""
var _tail_tuck: Node
var _aftercare_min: int
var _display_name := "the pony"
var _serial := 0
var _event_id := ""
var _started_at := 0.0

## The forced over-the-shoulder glance of a standing reach; the camera facade writes it back
## through the typed act view.
var _forced_glance := ""
var _presentation_cfg: Dictionary = {}
## This act's footstool handle: the case loans, the placed stack and the player lift. See
## `stool/act.gd` and docs/stool.md.
var _stool: RefCounted = null
var _wings: WING = null
var _act_seconds := 0.0
## Processed-time clock. It only advances while the runtime ticks, so a paused tree freezes
## act timing and stroke memory instead of aging them by the pause length.
var _clock_s := 0.0
## The act's face owner: beats, line-face ownership, the stare release and the post-act mood
## face. See `face/service.gd` and `docs/face.md`.
var _face: RefCounted = FACE.new()
## Thrust and climax presentation: jiggle, smack reaction, rump blush and hearts. See
## `reactions/service.gd` and `docs/reactions.md`.
var _reactions: RefCounted = REACTIONS.new()
var _first_time := false
var _act_climax_mode: String
## The act's base kiss normally rears and lifts both forelegs; zeroing those two shared
## settings keeps her forehooves planted for the kiss and restores them when it ends.
## The act's stare is released once when a kiss starts so the regular kiss can drive the eyes.
var _climax_progress := 0.0
var _hands: HANDS = null
var _kiss: KISS = null
var _integrations: INTEGRATIONS = null
var _missionary_camera_ctl: MISSIONARY_CAMERA = null
var _standing_camera_ctl: STANDING_CAMERA = null
var _standing_anon_ctl: STANDING_ANON = null
var _standing_presentation_ctl: STANDING_PRESENTATION = null
var _act_audio: Variant = null
## Shared act-level excitement Beat holds. The kiss controller holds "kiss" for a base kiss; an
## integration holds its provider id while it runs. The last release restores the saved pause state.
var _excitement_holders: Array[String] = []
var _excitement_beat: Timer
var _excitement_beat_saved := false
var _excitement_beat_paused := false

## Construct the per-pony controllers once. Only the audio node waits for the tree.
func _build_systems() -> void:
	_handover = BODY_CHANGE_ACT.new(_handover_host())
	_placement = PLACEMENT.new()
	_placement_facts = PLACEMENT.Facts.new()
	_wings = WING.new(_act_facts)
	_wings.log = Callable(self, "_log")
	_hands = HANDS.new(_act_facts)
	_kiss = KISS.new(_act_facts)
	_integrations = INTEGRATIONS.new(_act_facts)
	_missionary_camera_ctl = MISSIONARY_CAMERA.new(_act_facts)
	_standing_camera_ctl = STANDING_CAMERA.new(_act_facts)
	_standing_anon_ctl = STANDING_ANON.new(_act_facts)
	_standing_presentation_ctl = STANDING_PRESENTATION.new(_act_facts)
	_act_camera.bind(_act_facts, _hands, _kiss, _standing_camera_ctl, _missionary_camera_ctl)


## Bind the pose session's host callbacks once. The body paths rebind the pony itself.
func _bind_pose_hosts() -> void:
	_pose_session.bind(self, pony if is_instance_valid(pony) else null)
	_pose_session.id = _id
	_pose_session.hide_avatar = Callable(self, "_hide_act_avatar")
	_pose_session.set_act_body = Callable(self, "_set_missionary_anon_handle")
	_pose_session.eye_camera = Callable(self, "_missionary_eye_tick")
	_pose_session.perf = Callable(self, "perf_note")
	_pose_session.facts = _act_facts
	_pose_session.mouth_point = Callable(self, "_oral_mouth_point")
	_pose_session.opening_point = Callable(self, "_oral_opening_point")
	_pose_session.face_point = Callable(self, "_anatomy_face_point")
	_pose_session.oral_kiss = Callable(self, "_oral_kiss")
	_pose_session.oral_speech_stop = Callable(self, "_oral_speech_stop")
	_pose_session.oral_viseme = Callable(self, "_oral_viseme")
	_pose_session.oral_status = Callable(self, "_anatomy_status")


func _init() -> void:
	_build_systems()
	_bind_pose_hosts()
	_anatomy_bridge.bind(_anatomy_host())
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
	_readiness.heat_cycle = Callable(self, "_readiness_heat")
	_readiness.on_cue = Callable(self, "_readiness_cue")
	_readiness.shaft_length = Callable(self, "_player_shaft_length_m")
	_readiness.pose_family = Callable(self, "_pose_family")
	_summary_service.log = Callable(self, "_log")
	_afterglow.log = Callable(self, "_log")
	_afterglow.caress_active = Callable(self, "_afterglow_caressing")
	_afterglow.on_stay_close = Callable(self, "_on_stay_close")
	_afterglow.bind_host(self)
	_afterglow.write_satisfaction = Callable(self, "_write_satisfaction")
	_face.log = Callable(self, "_log")
	_face.clock = Callable(self, "_now_s")
	_reactions.log = Callable(self, "_log")
	_pose_session.log = Callable(self, "_log")
	_scene.stool_need = Callable(self, "stool_needed_count")
	_scene.stool_count = Callable(self, "stool_case_count")
	_scene.presentation_active = Callable(self, "presentation_active")
	_scene.hold_compatible = Callable(self, "_scene_hold_compatible")
	_scene.debug_context = Callable(self, "_debug_context")
	_rest.context = Callable(self, "_rest_context")
	_rest.restore_scene = Callable(self, "_rest_restore_scene")
	_rest.log = Callable(self, "_log")
	_hold.bind({
		"pony": Callable(self, "_pony"),
		"state": Callable(self, "_state"),
		"pose_family": Callable(self, "_pose_family"),
	})
	_act_facts.play_mouth_kiss = Callable(self, "_play_mouth_kiss")
	_act_facts.act_actions_allowed = Callable(self, "_act_actions_allowed")
	_act_facts.auto_panel_open = Callable(self, "auto_panel_open")
	_act_facts.standing_camera = Callable(self, "_standing_camera_controller")
	_act_facts.missionary_anon = Callable(self, "missionary_anon_body")
	_act_facts.anatomy_normal = Callable(self, "anatomy_normal")
	_act_facts.anatomy_opening = Callable(self, "anatomy_opening")
	_act_facts.authored_pose_asset = Callable(self, "authored_pose_asset")
	_act_facts.missionary_face_point = Callable(self, "missionary_face_point")
	_act_facts.gaze_point = Callable(self, "_missionary_gaze_point")
	_act_facts.free_look_rotation = Callable(self, "free_look_rotation")
	_act_facts.desktop_pose_driver = Callable(self, "_desktop_pose_driver")
	_act_facts.cuddle_active = Callable(self, "_cuddle_active")
	_act_facts.free_of_affection = Callable(self, "_free_of_affection")
	_act_facts.pause_face_turn = Callable(self, "_pause_face_turn")
	_act_facts.restore_face_turn = Callable(self, "_restore_face_turn")
	_act_facts.hold_excitement = Callable(self, "_hold_excitement")
	_act_facts.release_excitement = Callable(self, "_release_excitement")
	_act_facts.mod_enabled = Callable(self, "_mod_enabled")
	_act_facts.on_touch = Callable(self, "_on_touch")
	_act_facts.on_smack = Callable(self, "_on_smack_impact")
	_act_facts.pose_host = Callable(self, "_runtime")
	_perf_probe.enabled = Callable(self, "_perf_enabled")
	_perf_probe.active = Callable(self, "_perf_active")
	_perf_probe.header = Callable(self, "_perf_header")
	_perf_probe.log = Callable(self, "_log")
	_perf_probe.show = Callable(self, "_perf_show")
	_refresh_scene_gate()


## The typed host for the per-act anatomy bridge. The bridge reads the scene, the live state and
## the callbacks through named methods; it never reads the runtime's private fields. Built once:
## the callables are bound methods, so a per-frame rebind must not allocate.
var _anatomy_host_cache: ACT_HOST = null

func _anatomy_host() -> ACT_HOST:
	if _anatomy_host_cache != null:
		return _anatomy_host_cache
	var host := ACT_HOST.new()
	host.pony_cb = Callable(self, "_pony")
	host.runtime_cb = Callable(self, "_runtime")
	host.reactions_cb = Callable(self, "_reactions_service")
	host.anatomy_service_cb = Callable(self, "_anatomy_service")
	host.eligibility_service_cb = Callable(self, "_eligibility_service")
	host.state_cb = Callable(self, "_state")
	host.pose_view_cb = Callable(self, "_pose_view_value")
	host.depth_cb = Callable(self, "_depth")
	host.penetration_m_cb = Callable(self, "_penetration_m")
	host.penetration_reach_cb = Callable(self, "penetration_reach")
	host.climaxes_cb = Callable(self, "_climaxes")
	host.size_scale_cb = Callable(self, "_size_scale")
	host.auto_pace_cb = Callable(self, "_auto_pace")
	host.fluid_ground_y_cb = Callable(self, "_anatomy_fluid_ground_y")
	host.cycle_phase_cb = Callable(self, "cycle_phase")
	host.bed_frame_cb = Callable(self, "_bed_frame")
	host.log_cb = Callable(self, "_log")
	host.perf_note_cb = Callable(self, "perf_note")
	host.perf_enabled_cb = Callable(self, "_perf_enabled")
	host.body_coat_smack_cb = Callable(self, "body_coat_jiggle_target")
	host.status_cb = Callable(self, "_anatomy_status")
	host.command_cb = Callable(self, "command")
	host.missionary_camera_cb = Callable(self, "_missionary_camera_controller")
	host.kiss_controller_cb = Callable(self, "_kiss_controller")
	host.pose_cb = Callable(self, "_pose_service")
	host.thrust_move_cb = Callable(self, "_thrust_move")
	host.now_s_cb = Callable(self, "_now_s")
	host.set_penetration_m_cb = Callable(self, "_set_penetration_m")
	host.align_cb = Callable(self, "apply_anon_align")
	host.touch_cb = Callable(self, "_on_touch")
	host.vr_scene_cb = Callable(self, "_vr_scene")
	_anatomy_host_cache = host
	return _anatomy_host_cache


## The typed host for the act's body-change handover. Built once: the callables are bound methods,
## so a per-frame rebind must not allocate.
var _handover_host_cache: BODY_CHANGE_ACT_HOST = null

func _handover_host() -> BODY_CHANGE_ACT_HOST:
	if _handover_host_cache != null:
		return _handover_host_cache
	var host := BODY_CHANGE_ACT_HOST.new()
	host.runtime_cb = Callable(self, "_runtime")
	host.pony_cb = Callable(self, "_pony")
	host.id_cb = Callable(self, "_act_id")
	host.act_live_cb = Callable(self, "_act_live")
	host.restoring_cb = Callable(self, "_act_restoring")
	host.state_cb = Callable(self, "_state")
	host.event_id_cb = Callable(self, "_event_id_value")
	host.depth_cb = Callable(self, "_depth")
	host.climaxes_cb = Callable(self, "_climaxes")
	host.max_climaxes_cb = Callable(self, "_max_climaxes_value")
	host.satisfaction_cb = Callable(self, "_satisfaction_value")
	host.cue_cb = Callable(self, "_cue_value")
	host.pose_view_cb = Callable(self, "_pose_view_value")
	host.start_pose_cb = Callable(self, "_start_pose_id")
	host.shape_name_cb = Callable(self, "_shape_name")
	host.reaction_line_cb = Callable(self, "_form_reaction_line")
	host.note_reaction_cb = Callable(self, "_form_note_reaction")
	host.add_heat_cb = Callable(self, "_form_add_heat")
	host.cue_override_cb = Callable(self, "_form_cue_override")
	host.set_face_cb = Callable(self, "_form_set_face")
	host.status_cb = Callable(self, "_form_status")
	host.now_cb = Callable(self, "_now_s")
	host.reaction_max_age_cb = Callable(self, "_cue_reaction_max_age_value")
	host.log_cb = Callable(self, "_log")
	_handover_host_cache = host
	return _handover_host_cache


func _pony() -> Variant:
	return pony


func _act_id() -> String:
	return _id


## True while the act can be suspended or asked for a form.
func _act_live() -> bool:
	return state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]


func _act_restoring() -> bool:
	return state == State.RESTORE


func _start_pose_id() -> String:
	return str(_start_row().get("id", ""))


func _shape_name(shape_id: String) -> String:
	return SETTINGS.character_name(shape_id)


func _runtime() -> Variant:
	return self


func _reactions_service() -> Variant:
	return _reactions


## The VR scene handles the anatomy bridge wires into the VR act. The runtime owns the player
## scene; the bridge receives the nodes and never searches for them.
func _vr_scene() -> Variant:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return null
	var player: Node = WORLD.player
	var avatar := player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return null
	var cameras: Array = player.find_children("*", "XRCamera3D", true, false)
	var origins: Array = player.find_children("*", "XROrigin3D", true, false)
	if cameras.is_empty() or origins.is_empty():
		return null
	return {
		"player": player,
		"avatar": avatar,
		"camera": cameras[0],
		"origin": origins[0],
		"hip_target": avatar.get("_hip_target"),
	}


## Whether another mod's entry is active in this launch, for the integrations context.
func _mod_enabled(id: String) -> bool:
	if id.is_empty() or not is_inside_tree():
		return false
	var mods: Node = get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", id))


func _state() -> int:
	return state


## The one act-state writer. Consumers read `state`; transitions call this.
func _set_state(next: int) -> void:
	state = next
	_refresh_scene_gate()


## The live pose family, or the start spec's family before the first view fill.
func _pose_family() -> String:
	var view: Variant = _pose_session.view()
	var family := str(view.family) if view != null else ""
	return family if not family.is_empty() else _start_family()


## The start spec row. Start-time decisions read this before the view exists; the raw read is kept
## in this one helper so the start identity stays the only pose-id input.
func _start_row() -> Dictionary:
	return POSE_SPECS.spec(pose_id)


## The start spec's family. Start-time decisions read this before the view exists.
func _start_family() -> String:
	return str(_start_row().get("family", ""))


## The start spec's settings group. The internal poses share the standing group.
func _start_group() -> String:
	return str(_start_row().get("settings_group", ""))



## The live pose frame, or the start spec's frame before the first view fill.
func _start_frame() -> String:
	var view: Variant = _pose_session.view()
	var frame := str(view.frame) if view != null else ""
	return frame if not frame.is_empty() else str(_start_row().get("frame", ""))


## The pose read model the anatomy context mirrors; the session owns the one object.
func _pose_view_value() -> Variant:
	return _pose_session.view()


func _depth() -> float:
	return depth


func _penetration_m() -> float:
	return penetration_m


func _climaxes() -> int:
	return pony_climaxes


func _max_climaxes_value() -> int:
	return _max_pony_climaxes


func _satisfaction_value() -> float:
	return satisfaction


func _cue_value() -> String:
	return cue


func _event_id_value() -> String:
	return _event_id


func _cue_reaction_max_age_value() -> float:
	return _cue_reaction_max_age_s


func _auto_pace() -> float:
	return _readiness.auto_pace()


func _bed_frame() -> Variant:
	return _pose_session.bed_frame


func _set_penetration_m(value: float) -> void:
	penetration_m = value


func _anatomy_status(text: String, seconds := 2.0) -> void:
	HUD.anatomy_status(text, seconds)


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	idle_perf = _perf_enabled()
	# Run after locomotion/navigator/attention so the body facing lock and head glance win.
	process_physics_priority = 100
	# Identity is the key for per-mare preferences, poses, prompts and memory. It can arrive after
	# the pony enters the tree, so read it now and once more after the first frame.
	_read_id()
	_bind_pose_hosts()
	call_deferred("_read_id")
	_face.bind(pony, self)
	# integration: anatomy is persistent outside acts. Retry once after the first frame for a mod
	# that assigns the pony's identity after she enters the tree.
	_anatomy_refresh()
	call_deferred("_anatomy_refresh")


## integration: resolve the persistent anatomy controller through the world service. The bridge
## owns the controller handle; the service owns the controller.
func _anatomy_refresh() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.refresh()


func anatomy_facts() -> RefCounted:
	return _anatomy_bridge.context()


## Public hook for the anatomy's stock flank smack. The controller calls it through the context
## callback instead of reaching into the reaction facade.
func body_coat_jiggle_target() -> void:
	_reactions.body_coat_target()


func _anatomy_act_refresh() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.begin_act()


func _anatomy_service() -> Variant:
	return PONIES.anatomy


func _eligibility_service() -> Variant:
	return PONIES.eligibility


## The typed act/context the anatomy reads. The bridge owns the per-act facts.
func _anatomy_context() -> RefCounted:
	_anatomy_bridge.bind(_anatomy_host())
	return _anatomy_bridge.context()


## Write the state the persistent controller polls outside the act. The bridge owns the facts.
func _sync_anatomy_facts() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.sync_facts()


## Refresh the typed act context the presentation controllers read. The tick refreshes it once per
## phase: idle before the idle systems, physics after the pose tick and before the fan-out, render
## before the camera work, and the entry's `apply_camera_motion()` hand-off.
func refresh_view() -> void:
	var facts := _act_facts
	var view: Variant = _pose_service().view()
	facts.state = state
	facts.pose_view = view
	facts.source = source
	facts.satisfaction = satisfaction
	facts.mood = mood
	facts.cue = cue
	facts.form_hint = _handover.form_hint()
	facts.pony_climaxes = pony_climaxes
	facts.depth = depth
	facts.penetration_m = penetration_m
	facts.pony = pony
	facts.camera = _act_camera.camera
	facts.viewport = get_viewport()
	facts.pose = _pose_session.pose()
	facts.event_id = _event_id
	facts.pony_id = _id
	facts.display_name = _display_name
	facts.preferences = _preferences
	facts.act_prompts = _act_prompts
	facts.features = _features
	facts.caress_quality = _caress_quality
	facts.player_pony = _player_pony
	facts.bed = bed
	facts.presentation_config = _presentation_cfg
	facts.profile = _profile
	facts.physics_delta = get_physics_process_delta_time()
	if state == State.IDLE:
		# No presentation module reads the derived values outside an act; skipping the settings and
		# geometry lookups keeps an idle town from paying for every runtime every frame.
		return
	facts.act_seconds = _act_seconds
	facts.seconds_since_stroke = maxf(0.0, _clock_s - _readiness.last_stroke_at)
	facts.last_intensity = _readiness.last_intensity
	facts.last_pattern = _readiness.last_pattern
	facts.last_touch = _readiness.last_touch
	facts.last_talk = _readiness.last_talk
	facts.cue_override = not _readiness.cue_override.is_empty()
	facts.thrust_pace = _readiness.thrusts_per_second()
	# The pose view is the one contact source; the mouth/contact provider reads `contact_kind`.
	facts.penetration_reach = penetration_reach()
	var cam: RefCounted = _camera_service()
	facts.size_name = cam.call("size_name")
	facts.size_scale = cam.call("size_scale")
	facts.lean_size_scale = cam.call("lean_size_scale")
	facts.standing_lean_scale = cam.call("standing_lean_scale")
	facts.player_eye_height = cam.call("player_eye_height")
	facts.anon_torso_forward = cam.call("anon_torso_forward")
	facts.anon_torso_drop = cam.call("anon_torso_drop")
	facts.headset_view = _headset_view()
	facts.free_camera_active = cam.free_camera_active
	facts.free_look_active = cam.call("free_look_active")
	facts.camera_owned = cam.camera_owned
	facts.look_captured = cam.look_captured
	facts.look_yaw = cam.look_yaw
	facts.look_pitch = cam.look_pitch
	facts.lean_forward = cam.lean_forward
	facts.lean_side = cam.lean_side
	facts.lean_action_side = cam.lean_action_side
	facts.lean_view_forward = cam.lean_view_forward
	facts.lean_view_side = cam.lean_view_side
	facts.lean_sway = cam.lean_sway
	facts.lean = cam.lean
	facts.shot_lean_forward = shot_lean_forward()
	facts.thrust_travel = _readiness.thrust_travel
	facts.same_height_scale = float(_camera_service().call("same_height_scale"))
	facts.anon_height_scale = float(_camera_service().call("anon_height_scale"))
	facts.palm_scale_factor = float(_camera_service().call("palm_scale_factor"))
	facts.bob = cam.bob
	facts.back = cam.back
	facts.back_target = cam.back_target
	facts.forced_glance = _forced_glance
	facts.bed_frame = _pose_session.bed_frame
	var kiss: Variant = _kiss
	if kiss != null:
		facts.kiss_amount = float(kiss.amount())
		facts.kiss_active = bool(kiss.leaning_close())
		facts.kiss_side = float(kiss.side())
	else:
		facts.kiss_amount = 0.0
		facts.kiss_active = false
		facts.kiss_side = 0.0


## One-shot alias for the start, resume and teardown paths.
func _sync_act_facts() -> void:
	refresh_view()


## Typed write-backs for the presentation controllers. The runtime keeps ownership of the forced
## glance; the captured look snapshot is the camera facade's.
func _act_set_look(yaw: float, pitch: float) -> void:
	_act_camera.look_yaw = yaw
	_act_camera.look_pitch = pitch
	_act_facts.look_yaw = yaw
	_act_facts.look_pitch = pitch


func _act_set_forced_glance(side: String) -> void:
	_forced_glance = side
	_act_facts.forced_glance = side


func _act_set_camera_basis_ready() -> void:
	_act_camera.camera_basis_ready = true


func _anatomy_fluid_ground_y() -> float:
	var ground: float = pony.global_position.y if is_instance_valid(pony) else 0.0
	if _pose_family() != "bed":
		return ground
	var camera: Variant = _missionary_camera_controller()
	if camera != null and camera.has_method("bed_surface_top"):
		var top: Variant = camera.call("bed_surface_top")
		if top is float and is_finite(top):
			return top
	return ground


func _log(text: String) -> void:
	LOG.debug(text)


## Forward one act window to the corner panel, which owns the drawing.
func _perf_show(entries: Array, info: Dictionary) -> void:
	LOG.perf_block(entries, info)


## Debug perf probe. Timed chunks report microseconds here; `perf_note()` forwards to `shared/perf.gd`,
## which prints one summary a second so a pony-specific stall can be attributed to a modifier
## without a live profiler.
func _perf_enabled() -> bool:
	return LOG.debug_logs and LOG.debug_perf


func _perf_active() -> bool:
	return state != State.IDLE


## Called by every timed chunk (runtime, skeleton modifiers, HUD). Cheap no-op with logs off.
func perf_note(key: String, usec: int) -> void:
	_perf_probe.note(key, usec)
	if idle_perf and state == State.IDLE:
		_idle_perf_note(key, usec)


## Forward one idle chunk to the log module's aggregator. Only reachable while the idle probe is on.
func _idle_perf_note(key: String, usec: int) -> void:
	LOG.note(key, usec, _id)


## Time one call site for the perf probe (callers take the start stamp themselves).
func _timed(key: String, started: int) -> void:
	if not _perf_probe.on() and not idle_perf:
		return
	var usec := Time.get_ticks_usec() - started
	_perf_probe.note(key, usec)
	if idle_perf and state == State.IDLE:
		_idle_perf_note(key, usec)


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
	# The lean is what the drop was reported against, and the latched hands are what the caress
	# costs, so both belong in the line the reader compares across windows.
	var lean := "%.2f/%.2f" % [shot_lean_forward(), _act_camera.lean_view_side]
	var hands := "-"
	var controller: Variant = _hand_controller()
	if controller != null:
		var left := bool(controller.call("active", "L"))
		var right := bool(controller.call("active", "R"))
		hands = "LR" if left and right else ("L" if left else ("R" if right else "-"))
	return {
		"pony": _id,
		"pose": pose_id,
		"state": state,
		"lean": lean,
		"hands": hands,
		"near_mesh": near_mesh,
		"tier": tier,
		"wings": wing_state,
	}


func _wings_controller() -> WING:
	return _wings

func _hand_controller() -> HANDS:
	return _hands

func _kiss_controller() -> KISS:
	return _kiss

func _integrations_controller() -> INTEGRATIONS:
	return _integrations

## Acquire a named hold on the game's excitement Beat. The first successful holder saves the
## current pause state; every holder keeps the Beat paused. Repeating an owner is idempotent.
func _hold_excitement(owner: String) -> void:
	if owner.is_empty() or _excitement_holders.has(owner):
		return
	if not is_instance_valid(_excitement_beat):
		_excitement_beat = null
		_excitement_beat_saved = false
	if not _excitement_beat_saved:
		_resolve_excitement_beat()
	_excitement_holders.append(owner)
	if is_instance_valid(_excitement_beat):
		_excitement_beat.paused = true

## Release a named hold. The saved state comes back only when the last holder has released.
func _release_excitement(owner: String) -> void:
	var index := _excitement_holders.find(owner)
	if index >= 0:
		_excitement_holders.remove_at(index)
	if not _excitement_holders.is_empty():
		return
	_restore_excitement_beat()

func _resolve_excitement_beat() -> void:
	if not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	var beat: Variant = (excitement as Node).get_node_or_null("Beat")
	if not beat is Timer:
		return
	_excitement_beat = beat as Timer
	_excitement_beat_paused = _excitement_beat.paused
	_excitement_beat_saved = true

func _restore_excitement_beat() -> void:
	if _excitement_beat_saved and is_instance_valid(_excitement_beat):
		_excitement_beat.paused = _excitement_beat_paused
	_excitement_beat = null
	_excitement_beat_saved = false
	_excitement_beat_paused = false

## Act teardown fallback: drop every hold and restore the Beat once.
func _reset_excitement_hold() -> void:
	_excitement_holders.clear()
	_restore_excitement_beat()

func _missionary_camera_controller() -> MISSIONARY_CAMERA:
	return _missionary_camera_ctl

func _standing_camera_controller() -> STANDING_CAMERA:
	return _standing_camera_ctl

func _standing_anon_controller() -> STANDING_ANON:
	return _standing_anon_ctl

func _standing_presentation_controller() -> STANDING_PRESENTATION:
	return _standing_presentation_ctl

## Feature flag from the act snapshot. Unknown flags read as off.
func _feature(name: String) -> bool:
	return bool(_features.get(name, false))


func _dialogue_service() -> RefCounted:
	return _act_dialogue


## The pose session. Its host binding is one pass in `_init`; a body swap rebinds the pony itself.
func _pose_service() -> RefCounted:
	return _pose_session


## The pose read model, for the debug action and the suites.
func pose_view() -> RefCounted:
	return _pose_service().view()


## Why the face-sit debug action cannot toggle right now, or "" when it is ready: an active act, a
## live missionary or face-sit view, a steady pose, no running kiss and the anatomy's act body.
## The pose owner keeps the rule; the act state is the runtime's.
func face_sit_error() -> String:
	return _pose_service().face_sit_error(state)


## Re-read the active pose's authored asset in place. The debug action uses this; a running act
## sees the new file on its next frame.
func reload_pose_asset() -> String:
	var view := pose_view()
	var candidate := str(view.id) if view != null else ""
	return _pose_service().reload_authored(candidate)


## One pose request. The runtime supplies the act values; the session refuses or starts the edge.
func request_pose(target_id: String, trigger := "", context: Dictionary = {}) -> Dictionary:
	var request := context.duplicate()
	if not request.has("act_state"):
		request["act_state"] = state
	if not request.has("features"):
		request["features"] = _features
	return _pose_service().request_pose(target_id, trigger, request)


## One command check: the pose's control profile and the live edge lock. `end` is reserved.
func request_command(command_id: String) -> bool:
	return _pose_service().request_command(command_id)


## Run one discrete command after the pose's control set and the live edge lock allow it.
## Returns true only when a command was dispatched. `end` is reserved; the act-key hold owns it.
func command(command_id: String) -> bool:
	if not request_command(command_id):
		return false
	match command_id:
		ACT_COMMANDS.HOLE:
			toggle_anatomy_hole()
			return true
		ACT_COMMANDS.ORAL:
			toggle_anatomy_oral()
			return true
		ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD:
			return false
		ACT_COMMANDS.END:
			return true
	return false


## The fixed-order pose-change fan-out. The pose service reconciles its modifier profile and the
## act body first, then the camera, hands, kiss, anatomy and audio retarget in that order. Each
## owner's `pose_changed(view)` is cheap and idempotent. The face, dialogue and HUD read the view
## through the act facts and have no hook.
func _pose_fanout() -> void:
	var view: Variant = _pose_service().view()
	_pose_service().pose_changed(view)
	_call_pose_changed(_camera_service(), view)
	_call_pose_changed(_hand_controller(), view)
	_call_pose_changed(_kiss_controller(), view)
	_anatomy_bridge.bind(_anatomy_host())
	_call_pose_changed(_anatomy_bridge, view)
	if is_instance_valid(_act_audio):
		_call_pose_changed(_act_audio, view)


static func _call_pose_changed(owner: Variant, view: Variant) -> void:
	if owner != null and owner.has_method("pose_changed"):
		owner.call("pose_changed", view)


## The act camera session, bound once with the other per-pony controllers.
func _camera_service() -> RefCounted:
	return _act_camera


## The scene gate. Its callables are bound once in `_init`; only its live scene handles and act
## values refresh.
func _scene_gate() -> RefCounted:
	return _scene


## Rebind the scene gate's pony and pose session and refresh its act values. The host calls this
## wherever the bound body or the act state changes, never per gate access.
func _refresh_scene_gate() -> void:
	_scene.bind(pony, _pose_service())
	_scene.configure(state, _id, _features)


## Push the debug talk/cue pacing settings into the pure scheduler. `reset()` keeps these
## fields, so `_reset_thrust_state()` only has to reset the act's timing state.
func _configure_utterance_scheduler() -> void:
	_dialogue_service().configure({
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
	# The start spec's settings group selects the pose presentation block; an internal pose
	# (`standing_test`, `standing_oral`) has no block of its own and must never be passed here.
	var snap := SETTINGS.act_snapshot(_start_group())
	_features = snap.features
	_caress_quality = snap.caress_quality
	_readiness.configure_thrust(snap.thrust_pixels_per_cm, snap.thrust_up,
		snap.thrust_travel, snap.pelvis_gap_m)
	_max_pony_climaxes = snap.max_pony_climaxes
	_handover.set_form_hint_debug(SETTINGS.debug_mode.get_bool())
	_readiness.configure_auto(snap.auto_pace, snap.auto_max_depth, snap.auto_curve,
		snap.auto_min_depth, _preserve_auto_shape_on_snapshot)
	_reactions.configure({
		"jiggle": snap.jiggle,
		"pose_family": _start_family(),
		"size_scale": _camera_service().call("jiggle_size_scale"),
		"climax_seconds": CLIMAX_SECONDS,
	})
	_camera_service().call("configure", snap.camera_thrust)
	_cue_override_seconds = snap.cue_override_seconds
	_cue_base_stable_s = snap.cue_base_stable_s
	_cue_override_stable_s = snap.cue_override_stable_s
	_cue_utterance_gap_s = snap.cue_utterance_gap_s
	_cue_demand_gap_s = snap.cue_demand_gap_s
	_cue_demand_repeat_s = snap.cue_demand_repeat_s
	_cue_max_age_s = snap.cue_max_age_s
	_cue_reaction_max_age_s = snap.cue_reaction_max_age_s
	_cue_release_hold_s = snap.cue_release_hold_s
	_cue_overwhelmed_s = snap.cue_overwhelmed_s
	_touch_cooldown_s = snap.touch_cooldown_s
	_talk_cooldown_s = snap.talk_cooldown_s
	_receptive_seconds = snap.receptive_seconds
	_readiness.configure(_preferences, _cue_override_seconds, _cue_overwhelmed_s,
		_touch_cooldown_s, _talk_cooldown_s, _receptive_seconds)
	_presentation_cfg = snap.presentation
	_act_climax_mode = snap.climax_mode
	_configure_utterance_scheduler()
	_refresh_scene_gate()

## Re-read the settings tab's live-editable values during an act. Feature installs/removals are
## idempotent so repeated edits do not stack modifiers.
func apply_live_settings() -> void:
	# Snapshot before the IDLE early return too, so mouse sensitivity and the other act tunables
	# apply as soon as they are edited rather than only at the next act start.
	idle_perf = _perf_enabled()
	# Read the pre-edit mute before the snapshot replaces `_features`: a live Ponese mute edit is
	# only visible as a change against the value the act started with, and that change is what
	# pushes the new policy into the voice player below.
	var previous_mute := _feature("mute_ponese_audio")
	_snapshot_settings()
	if _suspended:
		# The resume re-reads the snapshot and rebuilds the body-bound services; an edit during
		# the flame must not touch a released pose or the old body.
		return
	if state == State.IDLE:
		# The idle standing presentation has its own live values, so a settings edit reaches it
		# before the act-only work is skipped.
		refresh_view()
		_standing_presentation_controller().apply_live_settings()
		# integration: the anatomy feature is live outside acts too.
		_anatomy_refresh()
		return
	_anatomy_refresh()
	_sync_act_facts()
	_integrations_controller().apply_live_settings()
	_reactions.apply_radius()
	if _pose_family() == "standing":
		_kiss_controller().apply_live_settings()
		_sync_standing_pose_config()
		_standing_presentation_controller().apply_live_settings()
	elif _pose_family() == "bed":
		_sync_missionary_pose_config()
	# A running edge's target snapshot follows the same edit; the start pose's config sync above
	# stays for the compatibility readers.
	_pose_service().apply_live_settings()
	# Nudge the frozen missionary anchor only when the framing control actually changed, so a preference
	# edit does not snap the shot. Move by the delta instead of recomputing from the pony: she
	# has settled since the start anchor was taken and the bed reference may be gone.
	if not _id.is_empty():
		_preferences = SETTINGS.preferences(_id)
	_refresh_live_modifiers()
	_sync_act_face_settings()
	if previous_mute != _feature("mute_ponese_audio"):
		_refresh_live_voice()
	if is_instance_valid(HUD.instance):
		_sync_hud_facts()
		HUD.instance.update_from(_act_facts)

func _refresh_live_modifiers() -> void:
	if not is_instance_valid(pony):
		return
	var skeleton_value: Variant = pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		return
	_pose_service().refresh_modifiers(_features)
	if _pose_family() == "standing":
		_standing_anon_controller().refresh_palm()
	elif _pose_family() == "bed":
		_anatomy_bridge.bind(_anatomy_host())
		_anatomy_bridge.refresh_palm()

func _refresh_live_voice() -> void:
	if not is_inside_tree():
		return
	_restore_voice_volume()
	_apply_voice_policy()

## Optional HUD cue and readiness readouts. The act continues without them.
func hud_readouts() -> bool:
	return bool(_features["hud_readouts"])


## Optional act control card, separate from the pony state readouts.
func hud_controls() -> bool:
	return bool(_features["act_controls"])


## The typed act view `main.gd` and `hud/service.gd` read. The runtime owns it; the HUD never
## probes this node for a method.
func act_view() -> RefCounted:
	return _act_facts


## Gather the HUD card's live values into the act view. `main.gd` calls `apply_camera_motion()`
## once per rendered frame just before `hud.update_from()`, so this runs once a frame and the card
## reads fields instead of calling back into the runtime.
func _sync_hud_facts() -> void:
	var facts := _act_facts
	facts.max_pony_climaxes = _max_pony_climaxes
	facts.close_hint = close_hint()
	facts.summary_hud = str(_summary_service.summary.get("hud", ""))
	facts.cycle_heat = _cycle_heat
	facts.close_earned = _afterglow.close_caress_earned
	facts.hud_readouts = hud_readouts()
	facts.hud_controls = hud_controls()
	facts.hole_ready = _anatomy_bridge.hole_ready()
	facts.oral_ready = _anatomy_bridge.oral_ready()
	facts.auto_on = _readiness.auto_active()
	if facts.auto_on:
		facts.auto_min_depth = _readiness.auto_min_depth()
		facts.auto_max_depth = _readiness.auto_max_depth()
		facts.auto_pace = _readiness.auto_pace()
		facts.auto_shape = _readiness.auto_shape()
	facts.auto_layer_open = _readiness.auto_panel_open()


## True while the automatic stroke owns the depth. X only switches it in ACTIVE/CLIMAX.
func auto_active() -> bool:
	return _readiness.auto_active()

func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act_seconds += delta
	if _pose_family() == "bed":
		_missionary_camera_controller().hide_avatar()
		_aim_missionary_eyes()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", ACT_FACE.blush_for(_act_phase(), satisfaction,
			_feature("blush_arc")))
	var wings_started := Time.get_ticks_usec()
	_wings_controller().tick(delta, str(_pose_service().view().family), satisfaction, _act_seconds)
	_timed("wings_tick", wings_started)
	_integrations_controller().tick(delta)

## The act's smile and lids; the facade owns the write and the hold timer.
func _set_face(smile: float, lids: float, hold_seconds := 0.0) -> void:
	_bind_face()
	_face.set_face(smile, lids, hold_seconds)


## Clear the act's smile and lids.
func _clear_face() -> void:
	_bind_face()
	_face.clear_face()

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
	if _suspended:
		return
	refresh_view()
	_sync_pose_frame()
	_pose_render_write()
	_idle_pose_sample()
	_standing_camera_controller().clamp_look()
	_camera_service().call("write_look_target", _pose_session.pose())
	if state == State.CLIMAX:
		_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)
	_camera_service().call("tick_shot", delta, state,
		_standing_camera_controller().speed(), _climax_progress)
	_breath_tick(delta)

## Debug free look: the input service hands over the relative motion instead of a thrust.
func look_motion(relative: Vector2) -> void:
	_camera_service().call("look_input", relative)


func _headset_view() -> bool:
	return is_instance_valid(WORLD.game) and bool(WORLD.game.get("headset_view"))

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	var idle := idle_perf and state == State.IDLE
	var sync_started := started if idle else 0
	_sync_anatomy_facts()
	var sync_split := Time.get_ticks_usec() if idle else 0
	_physics_tick(delta)
	var tick_done := Time.get_ticks_usec() if idle else 0
	_sync_anatomy_facts()
	if idle:
		_idle_perf_note("runtime_anatomy_sync",
			(sync_split - sync_started) + (Time.get_ticks_usec() - tick_done))
	if _perf_probe.on():
		perf_note("runtime_physics", Time.get_ticks_usec() - started)


func _physics_tick(delta: float) -> void:
	# The handover owns the pause overlay: a suspended act runs no act work until the one resume.
	_body_swap_tick(delta)
	if _suspended:
		return
	_clock_s += maxf(0.0, delta)
	# The pose edge advances before the view refresh reads it; the fan-out runs after that read and
	# before any presentation tick. An edge keeps ticking through CLIMAX and AFTERGLOW.
	if state != State.IDLE:
		var pose_started := Time.get_ticks_usec()
		_pose_service().tick(delta)
		_timed("pose_tick", pose_started)
	var facts_started := Time.get_ticks_usec()
	refresh_view()
	_timed("runtime_facts", facts_started)
	if state != State.IDLE:
		var fanout_started := Time.get_ticks_usec()
		_pose_fanout()
		_timed("pose_fanout", fanout_started)
	if state == State.IDLE:
		# Last-resort safety: a missed exit path must not leave the quick slots hidden.
		_restore_stray_inventory_hud()
		var presentation_started := Time.get_ticks_usec() if idle_perf else 0
		_standing_presentation_controller().physics(delta)
		if idle_perf:
			_idle_perf_note("runtime_presentation",
				Time.get_ticks_usec() - presentation_started)
		var history_started := Time.get_ticks_usec() if idle_perf else 0
		_history_tick(delta)
		if idle_perf:
			_idle_perf_note("runtime_history", Time.get_ticks_usec() - history_started)
		return
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		force_stop()
		return
	_cycle_heat = cycle_phase() == CYCLE.HEAT
	_sync_pose_frame()
	if pony.sleeping:
		pony.sleeping = false
	_vocal_tick(delta)
	_keep_nav()
	_camera_service().call("tick_free_look")
	_keep_act_attention()
	_pause_face_turn()
	_camera_service().call("tick_lean", delta, get_tree().paused, auto_panel_open())
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		var presentation_started := Time.get_ticks_usec()
		_act_presentation(delta)
		_timed("runtime_presentation", presentation_started)
	if state in [State.POSING_IN, State.ACTIVE]:
		_tolerance_tick(delta)
	_log_pose_settled()
	var kiss_started := Time.get_ticks_usec()
	_kiss_controller().tick(delta)
	_timed("kiss_tick", kiss_started)
	if state in [State.ACTIVE, State.CLIMAX]:
		var ai_started := Time.get_ticks_usec()
		_auto_tick(delta)
		_thrust_tick()
		_timed("runtime_ai", ai_started)
		if _anatomy_bridge.act_available():
			_anatomy_bridge.bind(_anatomy_host())
			_anatomy_bridge.tick(delta)
		if state == State.ACTIVE:
			var talk_started := Time.get_ticks_usec()
			_readiness_tick(delta)
			_talk_tick(delta)
			_handover.offer_tick()
			_bystander_tick(delta)
			_timed("runtime_talk", talk_started)
	if state in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.RESTORE]:
		_utterance_tick()
	if state == State.POSING_IN:
		_pose_in_left -= delta
		if _pose_in_left <= 0.0:
			_enter_active()
			# The start snapshot caught Anon mid stand-up, so his eye height was the reclined one; the
			# scene is settled now, and restoring to this is what puts the camera back correctly.
			if _pose_family() == "bed":
				_missionary_camera_controller().resnapshot()
			_handover.hint_tick()
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
	var camera_started := Time.get_ticks_usec()
	_standing_camera_controller().lock_facing()
	_standing_camera_controller().drive_glance(delta)
	_suppress_auto_cuddle()
	_standing_camera_controller().clamp_look()
	_standing_camera_controller().tick_depth(delta)
	_standing_anon_controller().tick_phase(delta)
	_reactions.blush_tick(delta)
	apply_camera_motion()
	_timed("runtime_camera", camera_started)
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_check_clock += delta
		if _check_clock >= 0.25:
			_check_clock = 0.0
			_check_running()
	var face_started := Time.get_ticks_usec()
	_eyes_tick()
	_timed("runtime_face", face_started)

## The act owns the lids outside a kiss. Set at every transition, then reasserted late so a
## climax return or fluster peek cannot leave her wide-eyed while leaning.
func _eyes_tick() -> void:
	_bind_face()
	_face.eyes_tick({
		"state": state,
		"close_rewarded": _afterglow.close_rewarded,
		"eyes_active": _kiss_controller().eyes_active(),
	})

# --------------------------------------------------------------------------- gates

func _start_reasons(pose: String, act_source: String, bed_in: Variant = null) -> PackedStringArray:
	return _scene_gate().report_reasons(start_verdict(pose, act_source, bed_in).get("rows", []))


func _stool_act() -> Variant:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(pony):
		return null
	var service: Variant = STOOL.instance
	if service == null or not service.has_method("new_act"):
		return null
	if _stool == null:
		_stool = service.call("new_act")
		_stool.log = Callable(self, "_log")
	_stool.call("bind", service, pony, WORLD.player, _anatomy_bridge.controller)
	return _stool


func _stool_failed() -> bool:
	return _stool_act() != null and bool(_stool_act().call("has_failed"))


## Whether the footstool rule can apply at all. See docs/stool.md.
func stool_applies() -> bool:
	return _stool_act() != null and bool(_stool_act().call("applies"))

## The live vertical gap; NAN when the rule or the anatomy is unavailable.
func stool_gap_m() -> float:
	return float(_stool_act().call("gap_m")) if _stool_act() != null else NAN

func stool_needed_count() -> int:
	return int(_stool_act().call("needed_count")) if _stool_act() != null else 0

func stool_required() -> bool:
	return _stool_act() != null and bool(_stool_act().call("required"))

func stool_case_slot() -> int:
	return int(_stool_act().call("case_slot")) if _stool_act() != null else -1

func stool_case_count() -> int:
	return int(_stool_act().call("case_count")) if _stool_act() != null else 0

## True only when the footstool stack is the one thing keeping the Make love hint away.
func stool_blocks_start(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return _stool_act() != null \
		and bool(_stool_act().call("blocks_start", _start_reasons(pose, act_source, bed_in)))


func stool_state_text() -> String:
	return str(_stool_act().call("state_text")) if _stool_act() != null else "stool unavailable"

func start_verdict(pose: String, act_source: String, bed_in: Variant = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	_read_id()
	return _scene_gate().start_verdict(pose, act_source, bed_in, verdict_in)


## The scene-only start of an accepted Agreement: no policy verdict, no formation row, no
## aftercare. `frozen` carries the pose capability recorded at formation.
func scene_only_verdict(pose: String, act_source: String, bed_in: Variant = null,
		frozen: Variant = null, stool_need: int = -1, stool_have: int = -1) -> Variant:
	_read_id()
	var capability: Variant = frozen if frozen != null else SCENE_GATE.FrozenPose.new(true, true)
	return _scene_gate().scene_only_verdict(pose, act_source, bed_in, capability,
		stool_need, stool_have)


## The live act values the debug status line reads. The debug pony helper owns the scene gather;
## the act's session values are the runtime's own.
func _debug_context() -> Dictionary:
	return DEBUG_PONY.context(pony, _id, {
		"state": state,
		"presenting": _standing_presentation_controller().presentation_active(),
		"cuddle": _cuddle_active(),
		"max_pony_climaxes": _max_pony_climaxes,
		"satisfaction": satisfaction,
		"pony_climaxes": pony_climaxes,
		"last_intensity": _readiness.last_intensity,
		"last_pattern": _readiness.last_pattern,
		"cue": cue,
		"thrust_up": _readiness.up_is_deep,
		"penetration_m": penetration_m,
		"penetration_reach": penetration_reach(),
		"preferences": PREFERENCES.describe(_preferences),
		"voice_status_line": voice_status_line(),
	})


## The debug status line. The scene gate owns the row and verdict assembly.
func debug_line(pose: String, act_source: String, bed_in: Variant = null, distance := -1.0, dot := -1.0) -> String:
	_read_id()
	return _scene_gate().debug_line(pose, act_source, bed_in, distance, dot)

## The stable pony id the act is on, read from the live body. `ponies` matches a prompt note
## to its one runtime through this; the id itself stays private to the act.
func live_id() -> String:
	_read_id()
	return _id


func _read_id() -> bool:
	if not is_instance_valid(pony):
		_refresh_scene_gate()
		return false
	# The relationship id is the stable key used by eligibility, preferences and memory. Prefer
	# the meta value whenever it appears; a mod may assign it after the pony enters the tree.
	var meta_id := str(pony.get_meta("relationship_id", "")) if pony.has_meta("relationship_id") else ""
	if not meta_id.is_empty():
		_id = meta_id
	elif _id.is_empty():
		_id = PONY_ID.from("", pony.get("identity"))
	if _id.is_empty():
		_refresh_scene_gate()
		return false
	_pose_session.id = _id
	_adopt_display_name(pony)
	_refresh_scene_gate()
	return true

func _suppress_auto_cuddle() -> void:
	_scene_gate().suppress_auto_cuddle()

func cuddle_active() -> bool:
	return _cuddle_active()


func _cuddle_active() -> bool:
	return _scene_gate().cuddle_active()

func free_of_affection() -> bool:
	return _free_of_affection()


func _free_of_affection() -> bool:
	return _scene_gate().free_of_affection()

func _nav_pose_gate(pose: String, act_source: String) -> bool:
	return _scene_gate().nav_pose_gate(pose, act_source)

func find_bed_under() -> Node3D:
	return _scene_gate().find_bed_under()

## The scene-only Agreement start. The Negotiation package froze the policy and the pose
## capability; only the world rows run. `WAIT` keeps the Agreement live (a transient row or the
## presentation is not ready); `STARTED` and `FAILED` are reported to the Negotiation service by
## the offer service, its only caller. The hotkey's exact match passes `skip_presentation`, so a
## settled turn is not waited on.
func start_agreement(handle: Variant, skip_presentation := false) -> int:
	if handle == null or not bool(handle.call("valid")):
		return AGREEMENT_FAILED
	var option: Variant = handle.option
	if option == null:
		return AGREEMENT_FAILED
	_read_id()
	var pose := str(option.pose)
	var act_source := str(option.source)
	var verdict: Variant = scene_only_verdict(pose, act_source, option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.hard_ok):
		_log("agreement start blocked pose=%s source=%s pony=%s reasons=%s" % [
			pose, act_source, str(pony.name) if is_instance_valid(pony) else "?",
			"none" if verdict == null else ",".join(verdict.reasons)])
		return AGREEMENT_FAILED
	if not bool(verdict.ok):
		_log("agreement start waiting pose=%s source=%s transient=%s" % [
			pose, act_source, ",".join(verdict.transient)])
		return AGREEMENT_WAIT
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and presentation_active() and not presentation_settled():
		_log("agreement start waiting pose=%s source=%s presentation" % [pose, act_source])
		return AGREEMENT_WAIT
	_clear_aftercare()
	var started := _begin_act(pose, option.bed, act_source, skip_presentation)
	_log("agreement start %s pose=%s source=%s" % [
		"started" if started else "failed", pose, act_source])
	return AGREEMENT_STARTED if started else AGREEMENT_FAILED


## True when the scene-only rows pass and, for a standing option, the presentation is settled.
func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	if handle == null or not bool(handle.call("valid")):
		return false
	var option: Variant = handle.option
	if option == null:
		return false
	_read_id()
	var pose := str(option.pose)
	var verdict: Variant = scene_only_verdict(pose, str(option.source), option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.ok):
		return false
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and presentation_active() and not presentation_settled():
		return false
	return true


## The hotkey's readiness: the scene-only rows plus Base clearance. The scene gate owns the
## predicate; the act key never bucks and the tolerance stop owns refusal.
func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	_read_id()
	var stool: Variant = _stool_act()
	var pair := Vector2i(-1, -1)
	if stool != null:
		pair = stool.call("hotkey_pair", pose)
	var started := Time.get_ticks_usec() if idle_perf else 0
	var allowed: bool = _scene_gate().hotkey_ready(pose, act_source, bed_in, pair)
	if idle_perf:
		_idle_perf_note("offer_rows", Time.get_ticks_usec() - started)
	return allowed


## The footstool pair this call's gate used, so the blocked standing note does not repeat the
## reach and case reads.
func hint_stool() -> Dictionary:
	var stool: Variant = _stool_act()
	if stool == null:
		return {"need": 0, "have": 0}
	return stool.call("hint_pair")


## The act key's immediate attempt, with no Agreement and no presentation wait.
func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	if not hotkey_ready(pose, act_source, bed_in):
		_log("hotkey blocked pose=%s source=%s pony=%s" % [
			pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		return false
	_clear_aftercare()
	var started := _begin_act(pose, bed_in, act_source, skip_presentation)
	_log("hotkey start %s pose=%s source=%s" % [
		"started" if started else "failed", pose, act_source])
	return started


## Clear the visual aftercare before a new start: the face and tail state, the meta and the
## aftercare navigator lease. The node restores its own nav only while it still owns it.
func _clear_aftercare() -> void:
	_afterglow.clear_post_act(pony if is_instance_valid(pony) else null)


## The shared start body after every gate. The act key's policy path and the scene-only
## Agreement path both land here; the one teardown still owns every failure.
func _begin_act(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and presentation_active() and not presentation_settled():
		_log("start blocked presentation turn pose=%s source=%s pony=%s" % [
			pose, act_source, str(pony.name) if is_instance_valid(pony) else "?"])
		return false
	_reset_stool_state()
	_anatomy_refresh()
	if bool(POSE_SPECS.scene(pose).get("stool", false)):
		var stool_need := stool_needed_count()
		if stool_need > 0:
			if stool_case_count() < stool_need or not _take_stool_items(stool_need):
				_log("start blocked stool pose=%s pony=%s need=%d" % [
					pose, str(pony.name) if is_instance_valid(pony) else "?", stool_need])
				return false
	_camera_service().call("begin_session", _start_family())
	_posture_owned = false
	_session_finalized = false
	# Remove the idle standing presentation and its face before the act builds its own pose.
	clear_presentation()
	_bind_face()
	_face.end_mood_face()
	_end_act_face()
	pose_id = pose
	source = act_source
	_profile = SETTINGS.template_for(_id)
	_pose_service().set_pose_config(SETTINGS.pose(_id, _start_group()))
	_preferences = SETTINGS.preferences(_id)
	_act_prompts = _profile.get("act_prompts", {})
	_snapshot_settings()
	_reactions.apply_radius()
	_aftercare_min = int(_profile["aftercare_min"])
	_cue_gap = SETTINGS.cue_gap_value(float(_profile["cue_gap"]))
	_standing_camera_controller().reset()
	bed = _scene_gate().resolve_bed(pose, act_source, bed_in)
	if bool(POSE_SPECS.scene(pose).get("requires_bed", false)) and bed == null:
		# Nothing else is borrowed yet, but the jiggle radius was just applied.
		_reactions.restore_radius()
		pose_id = ""
		source = ""
		bed = null
		return false
	_player_pony = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	_camera_service().call("apply_eye_override", _start_family(), _player_pony, _body_form())
	_wings_controller().reset()
	_act_seconds = 0.0
	_reactions.begin_act()
	_camera_service().call("reset_lean_state")
	_clear_face()
	_set_face(0.45, FACE.ACT_LIDS)
	_serial = _next_serial()
	_event_id = "intimacy_%s_%d" % [_id, _serial]
	_first_time = _read_first_time()
	_started_at = Time.get_unix_time_from_system()
	satisfaction = 0.0
	mood = "warming"
	cue = ""
	_reset_thrust_state()
	_stopped_by_her = false
	_tolerance_warning_key = ""
	_handover.reset_act()
	_end_tail_tuck()
	_summary_service.reset_act()
	_prepare_vocal()
	_afterglow.stop_decay()
	_remember_talk_turn()
	_act_spoken_at = _dialogue_service().last_spoken_at()
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
	if _cuddle_active() and source not in ["bed_side", "already_lying"]:
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
	_anatomy_act_refresh()

	# The act is its own state for both of them: the setup adapter places the bodies before the
	# snapshot and the lock. The bed only supplies the frame their bodies are placed in.
	var setup := POSE_SPECS.start_setup(pose)
	if not _run_start_setup(setup):
		_abort_start()
		return false

	_build_pose()
	_reactions.clear_stock_marks()
	_sync_start_pose_config()
	_camera_service().call("reset_lean_state")
	_prepare_start_camera()
	_camera_service().call("capture_look")
	_lock_player()
	_pause_face_turn()
	_begin_camera_mode()
	_missionary_camera_controller().hide_avatar()
	_start_audio()
	_apply_voice_policy()
	_set_inventory_hud_hidden(true)
	# integration: show the player part for the encounter.
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_encounter"):
		service.call("player_encounter", true)
	_set_state(State.POSING_IN)
	_integrations_controller()
	_sync_act_facts()
	# The pose session installs the act body and reconciles the modifiers for the start view, before
	# the first rendered frame; every later change arrives through `_pose_fanout()`.
	_pose_service().pose_changed(_pose_service().view())
	_integrations_controller().begin()
	_act_face_beat("start")
	# integration: act-only visibility updates at the state change, not on the next poll.
	_anatomy_bridge.apply_live()
	_pose_in_left = POSE_IN_SECONDS
	PONIES.set_active(self)
	if is_instance_valid(HUD.instance):
		_sync_hud_facts()
		HUD.instance.show_act(_act_facts)
		HUD.instance.hide_prompt()
	_log("started pose=%s setup=%s source=%s pony=%s eye=%.2f" % [
		pose, setup, act_source, str(pony.name), _act_camera.camera_target_eye])
	return true

func _next_serial() -> int:
	return PONIES.allocate_serial()

func _end_cuddle_session() -> void:
	_hold.end_cuddle()


func _release_carry() -> bool:
	return _hold.release_carry()


func _claim_nav() -> bool:
	if _hold.holds_negotiation():
		return _hold.adopt_hold()
	return _hold.claim_nav(_id)


## The per-pony negotiation hold handle. The Negotiation's bridge calls this through the runtime;
## it does not read `_hold`.
func hold_handle() -> RefCounted:
	return _hold


func _scene_hold_compatible(pose: String, source: String) -> bool:
	return _hold.accepts_hold(pose, source)


## Standing keeps her body turned away and planted. Stop the standing face-turn response so a
## player conversation cannot make her take turn steps, without pausing locomotion or emotions.
func _pause_face_turn(force := false) -> void:
	_hold.pause_face_turn(force)


func _restore_face_turn() -> void:
	_hold.restore_face_turn()

func present_standing() -> bool:
	return bool(_standing_presentation_controller().present_standing())

func presentation_active() -> bool:
	return bool(_standing_presentation_controller().presentation_active())

func presentation_settled() -> bool:
	return bool(_standing_presentation_controller().presentation_settled())

func clear_presentation() -> void:
	_standing_presentation_controller().clear_presentation()

func _keep_nav() -> void:
	_hold.keep_nav()


## Keep the act's attention while another character talks to Anon. Clearing the listener every
## tick stops the director from turning her away or pinning her gaze; speech, emotions and
## locomotion keep running, and `_check_running` does not treat conversation as a stop.
func _keep_act_attention() -> void:
	_hold.keep_attention()


func _release_nav() -> void:
	_hold.release_nav()


func _lock_player() -> void:
	_hold.lock_player()


func _unlock_player() -> void:
	_hold.unlock_player()

func _abort_start() -> void:
	_end_act_lines(true)
	_end_session(false)
	_finalize_session(false)

# --------------------------------------------------------------------------- body swap

## True while a shape change has the act suspended. `ponies` keeps the act's pending record and
## the debug actions see one change at a time.
func body_swap_pending() -> bool:
	return _suspended


## The act-side form request. The handover decides whether a source can take the form; the watcher
## suspends the act on a later tick, so the act's state, depth and climaxes are never handed to a
## second runtime.
func request_form_change(true_form: bool, shape_id := "", by_player := false) -> Dictionary:
	return _handover.request(true_form, shape_id, by_player)


## Apply one handover action. The handover decides when; the ordered release, the adoption and the
## one resume stay here, and a swap the act cannot resume from ends through the one exit.
func _body_swap_tick(delta: float) -> void:
	var action := _handover.tick(delta)
	if action == BODY_CHANGE_ACT.Action.SUSPEND:
		_suspend_for_body_swap(_handover.candidate)
	elif action == BODY_CHANGE_ACT.Action.RESUME:
		_resume_after_body_swap()
	elif action == BODY_CHANGE_ACT.Action.FAIL:
		_log("body swap failed: %s" % _handover.fail_reason)
		force_stop()
	elif action == BODY_CHANGE_ACT.Action.END_RESTORE:
		force_stop()


## The presented body's form, through the handover's service read.
func _body_form() -> BODY_FORM.BodyForm:
	return _handover.form()


## Stop the act's ticks without ending it. The runtime leaves the old body here; the old body may
## still be alive inside the flame. The outer act state, depth, climaxes, summary and event stay.
func _suspend_for_body_swap(change: BODY_CHANGE) -> void:
	if _suspended or not is_instance_valid(pony) or change == null:
		return
	if not pony is Node3D or change.previous_body != pony:
		return
	if state not in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		return
	if not _handover.change_changing(change):
		return
	# Another system holding her would keep the old body as the act's owner. Release it before
	# the flame takes the body; a failed release is logged and the watchdog still decides.
	if pony.has_method("is_held") and bool(pony.call("is_held")) and not _release_carry():
		_log("body swap: could not release the held body")
	_handover.begin(change)
	# Leave the old body before it is freed. The world keeps the act; the new body adopts the node.
	attach_to_body(WORLD.game)
	var source := _handover.change_source(change)
	_log("body swap suspend source=%s target=%s origin=%d form=%s state=%d pose=%s depth=%.3f climaxes=%d" % [
		source.source_id() if source != null else "?", change.target_form_id,
		int(change.origin), _handover.change_form_id(change), state, _handover.pose, depth,
		pony_climaxes])
	# The old body's contact and input state must not survive the flame. The new pose owns the
	# contact after resume; a held key or a running auto stroke would otherwise fire on it.
	_kiss_controller().reset()
	_hand_controller().reset()
	_handover.remember_auto(_readiness.auto_active())
	_reset_swap_input_state()
	_handover.hint_tick()
	_wings_controller().release()
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()
	_release_nav()
	_restore_face_turn()
	_free_pose()
	_restore_pony_bones()
	if _act_camera.camera_owned:
		_restore_camera()
	_stop_breath()


## Move the live runtime under another node without running its world-close `_exit_tree()`. The
## handover moves it off the old body and then onto the new one.
func attach_to_body(parent: Node) -> void:
	if not is_instance_valid(parent) or get_parent() == parent:
		return
	_swapping_parent = true
	reparent(parent)
	_swapping_parent = false


## `ponies` calls this when the source's new body spawns. The runtime is already under the entry;
## it moves under the new body, binds its pose, face and anatomy, and waits for the watcher's resume.
## A body that is not an adult mare ends the act through the one exit.
func adopt_body(new_pony: Node) -> void:
	if not _suspended or not is_instance_valid(new_pony):
		return
	_handover.adopt(new_pony)
	pony = new_pony
	_pose_service().bind(self, pony)
	_face.bind(pony, self)
	_bind_audio_identity()
	_adopt_display_name(pony)
	_anatomy_refresh()
	_refresh_scene_gate()
	if not _new_body_is_adult():
		_log("body swap ended: the new body is not an adult mare pony=%s" % str(new_pony.name))
		force_stop()
		return
	WORLD.refresh_body_lod(new_pony)


## The body-change binding's adopt hook. It runs only for a body this runtime already presents;
## a suspended act is left to the one resume, and an idle runtime simply rebinds its sub-services.
func bind_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if _suspended or not _is_presented_body(body):
		return
	_rebind_body_services(form)


## The same presented body carries a revised form: refresh the eye/pose/camera and the other
## body-bound systems without a resume, a second runtime or an act exit.
func refresh_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if _suspended or not _is_presented_body(body):
		return
	_rebind_body_services(form)


func _is_presented_body(body: Node3D) -> bool:
	return is_instance_valid(body) and is_instance_valid(pony) and body == pony


## One idempotent rebind for the body-change path. The act resume owns its own ordered rebuild;
## this is the idle and in-place revision refresh and never touches the act state.
func _rebind_body_services(form: BODY_FORM.BodyForm) -> void:
	_apply_form_display_name(form)
	_refresh_scene_gate()
	_pose_service().bind(self, pony)
	_face.bind(pony, self)
	_bind_audio_identity()
	refresh_view()
	_anatomy_refresh()
	_camera_service()
	_reactions.bind_scene(pony, _anatomy_bridge.controller)
	var view: Variant = _pose_service().view()
	_call_pose_changed(_hand_controller(), view)
	_call_pose_changed(_kiss_controller(), view)
	if is_instance_valid(_act_audio):
		_call_pose_changed(_act_audio, view)
	_wings_controller()
	_integrations_controller()
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		_reset_visual_for_form(form)
		if _pose_family() == "standing":
			_standing_camera_controller().prepare()
		_sync_act_facts()
		if not _features.is_empty() and is_instance_valid(HUD.instance):
			_sync_hud_facts()
			HUD.instance.update_from(_act_facts)


## Recompute the act's visual frame after a presented-form revision. The camera's old offset is
## undone before the new form is measured, then the standing placement is re-fitted. The act state,
## depth and climaxes are untouched; the pose session owns its own rebuild on a new body.
func _reset_visual_for_form(form: BODY_FORM.BodyForm) -> void:
	_camera_service().call("reset_for_form", _start_family(), _player_pony, form)
	_reanchor_player_for_form(form)
	_sync_act_facts()


## Resume the same act on the adopted body: anatomy, pose, camera, ownership and the body-bound
## controllers are rebuilt; the act's state and history are not.
func _resume_after_body_swap() -> void:
	if not _suspended:
		return
	if not is_instance_valid(pony):
		_log("body swap failed: no body to resume on")
		_handover.abort()
		force_stop()
		return
	var change := _handover.change
	var changed := is_instance_valid(_handover.new_pony)
	var confirmed := _handover.shape_confirmed
	_handover.finish()
	_pose_service().bind(self, pony)
	_face.bind(pony, self)
	_adopt_display_name(pony)
	_sync_act_facts()
	pony.sleeping = false
	if pony.has_method("set_sim_tier"):
		pony.set_sim_tier(pony.SimTier.HERO)
	pony.set_meta("sex_active", true)
	# integration: the old act handle is gone; fetch the new body's controller and start its act.
	_anatomy_refresh()
	_anatomy_act_refresh()
	_preserve_auto_shape_on_snapshot = true
	_snapshot_settings()
	_preserve_auto_shape_on_snapshot = false
	_reactions.bind_scene(pony, _anatomy_bridge.controller)
	_reactions.apply_radius()
	_pose_service().set_pose_config(SETTINGS.pose(_id, _start_group()))
	_rebuild_pose_for_swap(_handover.pose)
	_sync_start_pose_config()
	_reset_visual_for_form(_body_form())
	# The bed path has no placement fit; clear the old body's Hips handshake for every resume.
	_reset_player_pelvis()
	_reset_swap_input_state()
	_camera_service().call("reset_lean_state")
	_prepare_start_camera()
	_begin_camera_mode()
	_missionary_camera_controller().hide_avatar()
	_wings_controller().reset()
	_claim_nav()
	_pause_face_turn(true)
	_clear_face()
	_set_face(0.45, FACE.ACT_LIDS)
	_apply_voice_policy()
	_sync_act_facts()
	_pose_service().pose_changed(_pose_service().view())
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.apply_live()
	_integrations_controller().begin()
	if is_instance_valid(HUD.instance):
		_sync_hud_facts()
		HUD.instance.update_from(_act_facts)
	if _handover.auto_on and state in [State.ACTIVE, State.CLIMAX]:
		_readiness.toggle_auto(depth)
	_handover.clear_auto()
	_log("body swap resumed pony=%s id=%s form=%s state=%d pose=%s depth=%.3f climaxes=%d" % [
		str(pony.name), _id, _handover.change_form_id(change), state, _handover.pose, depth,
		pony_climaxes])
	_handover.complete_resume(change, changed, confirmed)
	if changed:
		_handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.FORM_SETTLED, change)


## Rebuild the live pose on the new skeleton at the pose the act was in. The start ramp is
## skipped because the act is continuing, not entering.
func _rebuild_pose_for_swap(pose: String) -> void:
	_snapshot_pony_bones()
	var camera: Camera3D = WORLD.camera()
	var look: Vector3 = pony.global_position
	var camera_at := Vector3.INF
	if camera is Camera3D:
		look = (camera as Camera3D).global_position
		camera_at = look
	var size_name := str(_camera_service().call("size_name"))
	var started: bool = _pose_service().begin({
		"pose_id": pose if not pose.is_empty() else str(_start_row().get("id", "")),
		"id": _id,
		"features": _features,
		"bed": bed,
		"presentation": _presentation_cfg,
		"pose_config": _pose_session.pose_config,
		"look_point": look,
		"camera_position": camera_at,
		"size_name": size_name,
	})
	if not started:
		_log("body swap: the new body has no pose skeleton")
		return
	_pose_service().settle()
	_reactions.bind_tail(_pose_service().tail)


## The front lean and the auto stroke belong to the hand and the old body. The auto generator
## keeps its pace, band and shape; only its running state is interrupted.
func _reset_swap_input_state() -> void:
	_readiness.stop_auto()


## Fill the reused placement facts for one pass. The handle reads the same object; the runtime
## writes the live scene values before each call.
func _placement_facts_for(form: BODY_FORM.BodyForm = null) -> PLACEMENT.Facts:
	var facts := _placement_facts
	var body_form: Variant = _body_form()
	facts.pony = pony if is_instance_valid(pony) else null
	facts.player = WORLD.player if is_instance_valid(WORLD.player) else null
	facts.bed = bed
	facts.stool = _stool_act()
	facts.form = form if form != null else body_form
	facts.body_form = body_form
	facts.id = _id
	var configured: Variant = _pose_session.pose_config.get("gaps", {})
	facts.gaps = configured if configured is Dictionary else {}
	facts.camera = _camera_service()
	facts.anatomy = _anatomy_service()
	facts.player_pony = _player_pony
	facts.headset_view = _headset_view()
	facts.log = Callable(self, "_log")
	return facts


## A standing act places Anon at the body's gap. A different body form needs that pass again;
## the bed act keeps him where he is and its authored shot re-reads the live body scale.
func _reanchor_player_for_form(form: BODY_FORM.BodyForm = null) -> void:
	var standing: Variant = _placement.reanchor(_placement_facts_for(form), _pose_family())
	if standing is Transform3D:
		_standing_camera_controller().begin_facing(standing)


## Drop the part's pelvis handshake after the placement fit or a new body. The service owns the
## part; a missing service (a suite or the anatomy off) is a no-op.
func _reset_player_pelvis() -> void:
	_placement.reset_pelvis(_placement_facts_for())


## The new body must still pass the act's adult-mare gate. A missing service reads as allowed,
## so a suite can drive the handover without the world's eligibility graph.
func _new_body_is_adult() -> bool:
	return _placement.new_body_is_adult(_placement_facts_for())


## The presented body's name for the act caption and dialogue. The form's presentation name wins;
## the identity's display name is the fallback. The stable id stays the act's id: a borrowed shape
## still belongs to the same relationship, preferences and history.
func _adopt_display_name(new_pony: Node) -> void:
	if not is_instance_valid(new_pony):
		return
	_apply_form_display_name(_body_form(), new_pony)


## Apply one presented form's name. An empty form name falls back to the identity's display name,
## then to the stable act id.
func _apply_form_display_name(form: BODY_FORM.BodyForm, new_pony: Node = null) -> void:
	var name := form.form_name.strip_edges() if form != null else ""
	if name.is_empty():
		var body: Node = new_pony if is_instance_valid(new_pony) else pony
		var identity: Variant = body.get("identity") if is_instance_valid(body) else null
		var display: Variant = identity.get("display_name") if identity != null else null
		name = str(display).strip_edges() if display != null else ""
	_display_name = name if not name.is_empty() else _id


func _begin_standing_placement(form: BODY_FORM.BodyForm = null) -> Transform3D:
	return _placement.begin(_placement_facts_for(form))


## The horizontal shift that puts the part's natural pivot one shaft behind her entrance, so a
## standing start touches her instead of asking the Hips bone to carry the pre-act gap. The fit
## moves Anon's whole body before the act; the per-frame aim still owns the stroke correction.
func _standing_part_shift() -> Vector3:
	return _placement.part_shift(_placement_facts_for())


## Dispatch the spec's closed `start.setup` vocabulary to its placement adapter. It never selects
## on a pose id: a new pose row adds its setup name and data, not a branch here. A missing or
## unknown name is a data error after the gate passed; `start()` aborts the partial act.
func _run_start_setup(setup: String) -> bool:
	match setup:
		"bed_stand_up":
			return _start_bed_stand_up()
		"bed_keep_lying":
			return _start_bed_keep_lying()
		"standing_place":
			return _start_standing_place()
		_:
			_log("start blocked setup=%s source=%s pony=%s" % [
				setup if not setup.is_empty() else "missing", source,
				str(pony.name) if is_instance_valid(pony) else "?"])
			return false


## The bed stand-up start: Anon leaves the mattress before the player snapshot and the lock, and
## she leaves the game's lying state. The bed rest/cradle release already ran in the common
## prelude; the authored body owns her pose from here.
func _start_bed_stand_up() -> bool:
	if bed == null:
		return false
	if not _player_pony:
		var body: Variant = WORLD.player
		if body != null and body.has_method("force_stand_up"):
			body.call("force_stand_up")
	if source == "cradle":
		_rest_service().call("place_on_start")
	else:
		pony.reset_physics_interpolation()
	if pony.get("posture") != null:
		pony.request_posture("stand")
	return true


## The bed lying start: Anon does not stand up, and the authored act body takes over her pose. The
## riding pose is the first intended consumer; no shipped row uses this setup yet.
func _start_bed_keep_lying() -> bool:
	if bed == null:
		return false
	if source == "dialogue" and not REST.release_managed(pony):
		return false
	pony.reset_physics_interpolation()
	if pony.get("posture") != null:
		pony.request_posture("stand")
	return true


## The standing start: keep her where she stands, place Anon behind her at the act gap, take the
## stool items and start the facing lock.
func _start_standing_place() -> bool:
	var standing := _begin_standing_placement()
	if _stool_failed():
		return false
	pony.request_posture("stand")
	_sync_act_facts()
	_standing_camera_controller().begin_facing(standing)
	return true


## Remove the act prop and put every case item back. Every exit path calls this.
func _release_stool() -> void:
	var act: Variant = _stool_act()
	if act != null:
		act.call("release")

func _reset_stool_state() -> void:
	var act: Variant = _stool_act()
	if act != null:
		act.call("reset")

func _take_stool_items(need: int) -> bool:
	var act: Variant = _stool_act()
	return act != null and bool(act.call("take_items", need))

## The floor under a standing spot; the stool handle owns the probe.
func _floor_y_at(at: Vector3, body: Node3D) -> float:
	return _placement.floor_y_at(_placement_facts_for(), at, body)

func _standing_transform() -> Transform3D:
	return _placement.transform(_placement_facts_for())

func _standing_gap(form: BODY_FORM.BodyForm = null) -> float:
	return _placement.gap(_placement_facts_for(form))


## The standing recipe reads these from pose_config every frame. Re-reading the character's pose
## first keeps the other pose overrides, then the presentation neck/head controls win.
func _sync_standing_pose_config() -> void:
	_pose_service().sync_standing_config(_presentation_cfg)


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose keeps its nuzzle overrides live.
func _sync_missionary_pose_config() -> void:
	_pose_service().sync_missionary_config()


## The start pose's settings-group sync after `_build_pose()`. This is a group dispatch, not a pose
## branch: the riding group adds its own sync with its pose row, and foundation 3 generalizes the
## per-group sync. An unknown group keeps the config `start()` already set from its settings block.
func _sync_start_pose_config() -> void:
	match _start_group():
		"missionary":
			_sync_missionary_pose_config()
		_:
			pass


## Prepare the start pose's camera profile before the look is captured. The bed shot camera reads
## the authored asset; the standing camera starts in its placement adapter instead.
func _prepare_start_camera() -> void:
	var camera: Variant = _start_row().get("camera", {})
	var profile := str((camera as Dictionary).get("profile", "")) if camera is Dictionary else ""
	if profile == "missionary_shots":
		_missionary_camera_controller().prepare()


## The parsed authored missionary pose, for the shot camera and the debug action.
func authored_pose_asset() -> Variant:
	return _pose_service().authored_asset()


## Debug: the player camera replaces the act shot so the pose can be inspected. The mouse stops
## feeding thrust while it is on and drives this look instead, because the act holds
## `controls_locked` (the stock mouse look is dead during an act).
func free_look_active() -> bool:
	return bool(_camera_service().call("free_look_active"))


## Accumulated free-look rotation as (pitch, yaw), radians, from the act's starting view.
func free_look_rotation() -> Vector3:
	var rotation: Variant = _camera_service().call("free_look_rotation")
	return rotation if rotation is Vector3 else Vector3.ZERO


func _sync_pose_frame() -> void:
	if _pose_family() == "bed":
		_pose_service().sync_bed_frame()
	else:
		_pose_service().sync_ground_frame()


## The new-act prep: run the one pose teardown first so a pose left from the offer cannot stack,
## then build the act's pose.
func _build_pose() -> void:
	_free_pose()
	var session := _pose_service()
	var view: Camera3D = WORLD.camera()
	var look: Vector3 = pony.global_position
	var camera_at := Vector3.INF
	if view is Camera3D:
		look = (view as Camera3D).global_position
		camera_at = look
	# The act facts only carry the derived size inside an act, and the session starts before the
	# state leaves IDLE; supply the live size so the variant selection does not capture an empty
	# name.
	var size_name := str(_camera_service().call("size_name"))
	session.begin({
		"pose_id": pose_id,
		"id": _id,
		"features": _features,
		"bed": bed,
		"presentation": _presentation_cfg,
		"pose_config": _pose_session.pose_config,
		"look_point": look,
		"camera_position": camera_at,
		"size_name": size_name,
	})
	_reactions.bind_tail(session.tail)


## Snapshot before the act changes her posture or the pose writes bones.
func _snapshot_pony_bones() -> void:
	_pose_service().snapshot_bones()


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func _restore_pony_bones() -> void:
	_pose_service().restore_bones()


## The one pose teardown ledger: the pose-scope start and body steps at their current positions,
## the act-scope releases between them, then the session's final pose clear. A later pose
## transition calls only the pose-scope steps; it never calls this function.
func _free_pose() -> void:
	# A lost body must not reach the pose session's oral/face bindings.
	_pose_session.bind(self, pony if is_instance_valid(pony) else null)
	_pose_service().leave_pose_start()
	clear_presentation()
	_camera_service().call("end_lean_action")
	_hand_controller().reset()
	_kiss_controller().reset()
	_integrations_controller().reset()
	_reset_excitement_hold()
	_camera_service().call("release_free_camera_lock")
	_standing_anon_controller().remove()
	_pose_service().leave_pose_body()
	_restore_voice_volume()
	_reactions.end_act()
	_pose_service().release_pose()


# --------------------------------------------------------------------------- thrust

func _now_s() -> float:
	return _clock_s

func _reset_thrust_state() -> void:
	_readiness.reset_thrust()
	_readiness.reset_auto()
	_standing_anon_controller().reset_phase()
	_standing_camera_controller().reset_depth()
	_act_facts.standing_sway_offset = Vector3.ZERO
	_readiness.reset(_preferences)
	_climax_left = 0.0
	_afterglow.reset()
	_dialogue_service().reset(_now_s(), _cue_gap)
	_configure_utterance_scheduler()
	_act_spoken_at = -1e9
	_act_ended_early = false

## Switch the automatic stroke on or off. X is the only caller. Turning it on starts from the
## hand's current depth, so the shot does not snap; turning it off leaves the depth where it is.
func toggle_auto_thrust() -> void:
	_readiness.toggle_auto(depth)


## One wheel notch while auto owns the stroke.
func auto_thrust_wheel(direction: int) -> void:
	_readiness.auto_wheel(direction)


## True while the hold-X auto settings layer is open. The lean, the caress input and the kiss
## read this so W/S/Q/E/A/D/Z/F belong to the layer instead of the act.
func auto_panel_open() -> bool:
	return _readiness.auto_panel_open()


## One hold-X policy frame. The input service samples the keys; readiness owns the tap, the
## rows and the shape write.
func auto_panel_input(delta: float, x_down: bool, keys: Array) -> void:
	_readiness.auto_panel_tick(delta, x_down, keys, depth)


## The VR act's right primary click is the act key's hold. The bridge owns the controller.
func vr_y_held() -> bool:
	return _anatomy_bridge.vr_y_held()


## The act-key hold with a climax behind it enters the afterglow instead of cancelling.
func request_afterglow() -> void:
	_enter_afterglow()


## integration: anatomy action entry points for input.gd. They are no-ops when the per-act
## controller is absent, so the keys behave exactly like master with the feature off.
func toggle_anatomy_hole() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.toggle_hole()


## The `oral` command: request the standing oral pose, or the return edge when it is already
## active. The per-mare consent string is passed only when the anatomy service says yes; the
## feature is checked by the edge requirements, not here.
func toggle_anatomy_oral() -> void:
	var view: RefCounted = _pose_service().view()
	var from_id := str(view.id)
	var target := CATALOG.STANDING_ORAL if from_id == CATALOG.STANDING else CATALOG.STANDING
	var request := {}
	var consent := false
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("consent") and target == CATALOG.STANDING_ORAL:
		consent = bool(service.call("consent", pony, "oral"))
		if consent:
			request["consent"] = "oral"
	var result: Dictionary = request_pose(target, "oral", request)
	if bool(result.get("ok", false)):
		_log("oral pose %s -> %s: ok" % [from_id, target])
		return
	_log("oral pose %s -> %s refused: %s (%s)" % [
		from_id, target, str(result.get("code", "")), str(result.get("reason", ""))])
	if target == CATALOG.STANDING_ORAL and not consent:
		_oral_status("%s is not into that" % _display_name)
	elif service != null:
		_oral_status(str(result.get("reason", "")))


## The oral refusal line through the pose service's host callback, or the anatomy status when the
## callback is absent.
func _oral_status(text: String) -> void:
	var session: RefCounted = _pose_service()
	if session.oral_status.is_valid():
		session.oral_status.call(text)
	else:
		_anatomy_status(text)


## The mouth point the pose turn aims at once it has settled.
func _oral_mouth_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host())
	return _anatomy_bridge.mouth_point()


## The opening the pose turn captures before the turn.
func _oral_opening_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host())
	return _anatomy_bridge.opening()


## The face contact's real anchor on the act body. The pose service's face driver uses it; a
## missing or inactive body is Vector3.INF.
func _anatomy_face_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host())
	var point: Variant = _anatomy_bridge.face_point()
	return point if point is Vector3 else Vector3.INF


## The edge viseme event: the D shape, or the clear on contact release.
func _oral_viseme(value: String) -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.set_oral_viseme(value)


## The edge's speech stop: her authored line, the shared director turn and her own voice end once
## when the oral edge starts. The mouth shape follows through the separate `viseme` event.
func _oral_speech_stop() -> void:
	_end_act_lines(false)
	_stop_oral_director()
	_stop_pony_speech()


## integration: precise action gates. With no act controller (feature off or no controller) the
## keys pass through and the HUD rows stay hidden.
func anatomy_hole_ready() -> bool:
	return _anatomy_bridge.hole_ready()


func anatomy_oral_ready() -> bool:
	return _anatomy_bridge.oral_ready()


func anatomy_actions_ready() -> bool:
	return _anatomy_bridge.actions_ready()


func missionary_anon_body() -> Variant:
	return _anatomy_bridge.missionary_anon_body()


## Her gaze target in missionary: the authored Anon's face. The game camera is on his standing
## player rig, metres off the bed, and aiming there had her looking at empty air.
func _missionary_gaze_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host())
	return _anatomy_bridge.gaze_point()


## The game's eye modifier still points wherever the standing player rig left it; in missionary the
## pupils follow the same gaze target the head solve uses, so the eyes do not sit above his face.
func _aim_missionary_eyes() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.aim_eyes()


func _start_vr_act() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.vr_start()


func _stop_vr_act() -> void:
	_anatomy_bridge.vr_stop()


func vr_forward() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host())
	return _anatomy_bridge.vr_forward()


func vr_depth(value: float) -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.vr_depth(value)


func anatomy_normal() -> Vector3:
	return _anatomy_bridge.normal()


## integration: her entrance point during an anatomy act, in world space.
func anatomy_opening() -> Vector3:
	return _anatomy_bridge.opening()


## integration: the standing part aims itself in `player.gd`'s track; only the optional bed body
## still needs the wrapper hook.
## The bed pose writes his hip itself, so the marker alignment is only for other rigs (VR).
func apply_anon_align(_hip: Node3D, _facing: Basis) -> void:
	pass


func anatomy_status(text: String, seconds := 2.0) -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.status(text, seconds)


## Idempotent stop for every state exit. It never moves the depth.
func _stop_auto() -> void:
	_readiness.stop_auto()


## Feed the generated depth through the same tracker as the mouse. Strength, readiness,
## intensity, pattern, audio, camera and presentation therefore need no auto-specific path.
func _auto_tick(delta: float) -> void:
	var before := depth
	var now := _now_s()
	var events: Array[THRUST_STATE.StrokeEvent] = _readiness.auto_advance(delta, now)
	_finish_stroke(before, now, events)

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


## The debug read of the voice routing she has. `audio/service.gd` owns the classification; the
## facade is created for an act, so an idle runtime reports nothing instead of loading the pack.
func voice_status_line() -> String:
	if not is_instance_valid(_act_audio):
		return ""
	return str(_act_audio.voice_status_line(_id))


## Keep the generated line and the text HUD, but silence her Ponese audio for this act. The
## setting is live, so `apply_live_settings()` re-applies it when it changes mid-act.
func _apply_voice_policy() -> void:
	var audio: Variant = _audio_service()
	if audio != null:
		audio.apply_voice_policy(_feature("mute_ponese_audio"), pony, _id)


## The pose ledger's step: give the voice player its saved volume back. The policy state itself
## lives on the audio facade.
func _restore_voice_volume() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.restore_voice_policy()


## The idle safety check. `hud/service.gd` owns the borrowed quick-slot state, so every idle
## sibling runtime sees the same hidden flag; only restore it when no other runtime is mid-act.
func _restore_stray_inventory_hud() -> void:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(HUD.instance):
		return
	if not HUD.instance.inventory_hidden():
		return
	var owner: Node = PONIES.active()
	if is_instance_valid(owner) and owner != self:
		var owner_state: Variant = owner.get("state")
		if owner_state != null and int(owner_state) != State.IDLE:
			return
	_set_inventory_hud_hidden(false)

## The act hides the game's quick-slot card for its whole run. `hud/service.gd` owns the borrowed
## state and restores exactly what it found, so every exit path can call this unconditionally.
func _set_inventory_hud_hidden(hidden: bool) -> void:
	if is_instance_valid(HUD.instance) \
			and HUD.instance.has_method("set_inventory_hidden"):
		HUD.instance.set_inventory_hidden(hidden)

## Anon's visible shaft length in metres. The readiness stroke state owns the nominal fallback.
func _shaft_length_m() -> float:
	return _readiness.shaft_length_m()


## The anatomy service's visible shaft length, or zero when the part is not showing. The readiness
## stroke state turns zero into the nominal length, so the mouse feel is the same with it off.
func _player_shaft_length_m() -> float:
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_shaft_length_m"):
		var length: Variant = service.call("player_shaft_length_m")
		if length is float and (length as float) > 0.001:
			return length as float
	return 0.0


## The deepest the tip can reach, in metres. The readiness stroke state owns the placement math.
func penetration_reach() -> float:
	return _readiness.reach()


## The mouse's vertical travel as hip travel. Readiness converts the pixels and owns the clamp;
## the one post-move path carries the events to the ordered fan-out.
func thrust_motion(relative_y: float) -> void:
	_set_penetration(penetration_m + _readiness.mouse_travel(relative_y), _now_s())


## Move the physical penetration and mirror it into the public 0..1 depth. The readiness stroke
## state owns the clamp, the depth mapping and the events.
func _set_penetration(target_m: float, now: float) -> void:
	var before := depth
	var events: Array[THRUST_STATE.StrokeEvent] = _readiness.set_penetration(target_m, now)
	_finish_stroke(before, now, events)


func _thrust_move(amount: float, now: float) -> void:
	var before := depth
	var events: Array[THRUST_STATE.StrokeEvent] = _readiness.move(amount, now)
	_finish_stroke(before, now, events)


func _thrust_tick() -> void:
	_dispatch_events(_readiness.stroke_tick(_now_s()))


## The one post-move path: the withdrawal slide when the tip crosses her lips outward, then the
## ordered stroke/impact fan-out.
func _finish_stroke(before: float, now: float, events: Array[THRUST_STATE.StrokeEvent]) -> void:
	if is_instance_valid(_act_audio) and state in [State.ACTIVE, State.CLIMAX] \
			and not _face_contact() and _act_audio.crossed(before, depth):
		_act_audio.withdraw(before, depth, _readiness.live_strength(now),
			_reactions.rump_point())
	_dispatch_events(events)


func _dispatch_events(events: Array[THRUST_STATE.StrokeEvent]) -> void:
	for event: THRUST_STATE.StrokeEvent in events:
		_dispatch_stroke_event(event)


## The tracker reports the bottom of a stroke and its close. Presentation belongs to the bottom
## so the plap and the body land with the motion; the score belongs to the close.
func _dispatch_stroke_event(event: THRUST_STATE.StrokeEvent) -> void:
	if event.kind == "impact":
		_on_impact(event)
	else:
		_on_stroke(event)


## Score one closed inward thrust through the readiness system. Presentation stays in
## `_on_impact`; this only updates the two preference axes and the act counters.
func _on_stroke(event: THRUST_STATE.StrokeEvent) -> void:
	_readiness.stroke(event)


## Score the current axes. The readiness tick calls it after a stroke; the suite calls it directly.
func _score_thrust() -> void:
	_readiness.score_thrust()


## Add one readiness chunk. The readiness system clamps and tracks the peak.
func _add_heat(amount: float) -> void:
	_readiness.add_heat(amount)


## The stroke's bottom: the plap, the wobble, the wings, her blush and the ear twitch all land
## here, with the motion. The readiness stroke state supplies the physical facts: the gap to her
## coat, the impact tier and speed, the wobble and the visual impact. The oral segment keeps the
## slide, vocal, wings, blush and ear twitch but drops the plap and the rump/tail jiggle.
func _on_impact(event: THRUST_STATE.StrokeEvent) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	var oral := _mouth_contact()
	var face := _face_contact()
	var quiet := oral or face
	_wings_controller().on_thrust(event.visual)
	if not quiet:
		_reactions.thrust(event.jiggle)
		_reactions.tail_thrust(event.jiggle)
	if _pose_family() == "standing":
		_reactions.add_blush(event.visual)
		_pose_service().trigger_ear_twitch(event.visual)
	_readiness.note_impact()
	_play_vocal()
	if is_instance_valid(_act_audio):
		_act_audio.impact(event.tier, event.strength, _reactions.rump_point(),
			event.gap, THRUST_STATE.CONTACT_GAP_M, not quiet)
	_log("thrust impact gap=%.3f speed=%.2f tier=%s plap=%d oral=%d face=%d readiness=%.0f rate=%.1f/s strength=%.2f impact=%.2f jiggle=%.2f intensity=%s pattern=%s" % [
		event.gap, event.impact_speed, event.tier if not event.tier.is_empty() else "-",
		1 if event.plap else 0, 1 if oral else 0, 1 if face else 0, satisfaction,
		_readiness.thrusts_per_second(), event.strength, event.visual, event.jiggle,
		_readiness.last_intensity, _readiness.last_pattern])

## Her own generated vocal on a stroke. `audio/service.gd` owns the cooldown and the cache repair.
func _play_vocal() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.play_vocal()


## The generated-vocal cooldown runs on processed time. `audio/service.gd` owns it.
func _vocal_tick(delta: float) -> void:
	if is_instance_valid(_act_audio):
		_act_audio.tick_vocal(delta)


## Live mouth contact from the pose view. The pose service owns the contact switch; the runtime
## reads it for the plap/vocal guards and the climax line.
func _mouth_contact() -> bool:
	var view: Variant = _pose_service().view()
	return view != null and str(view.contact_kind) == "mouth"


## The bed face-sit contact: his mouth, not her opening. The impact fan-out and the withdraw cue
## use it like the oral branch; the anatomy act parks the part.
func _face_contact() -> bool:
	var view: Variant = _pose_service().view()
	return view != null and str(view.contact_kind) == "face"


## Interrupt the shared director only when it is driving this mare, so a bystander's turn is not
## cut by her mouth being busy.
func _stop_oral_director() -> void:
	var director := _director()
	if director == null or not director.has_method("interrupt"):
		return
	if str(director.get("state")) == "idle":
		return
	if str(director.get("_current")) != _id:
		return
	director.call("interrupt")


## Stop her own voice. `stop_speaking()` restores the rest viseme, so the oral turn re-asserts its
## mouth shape; the turn is the only owner of the open mouth.
func _stop_pony_speech() -> void:
	if not is_instance_valid(pony):
		return
	if pony.has_method("is_speaking") and bool(pony.call("is_speaking")):
		if pony.has_method("stop_speaking"):
			pony.call("stop_speaking")
		_anatomy_bridge.hold_oral_mouth()


## The base game's soft kiss at her snout. The audio facade owns the cue and its level.
func _oral_kiss() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.oral_kiss()


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
	var director := _director()
	_handover.player_line_tick(director)
	_readiness.talk_tick(director)


func _remember_talk_turn() -> void:
	var director := _director()
	_readiness.remember_talk_turn(director)
	_handover.remember_talk_turn(director)


## The body-change handover's host callbacks: the form interaction lives there and the runtime
## supplies the dialogue reaction, the readiness spike and the act's expression beat.
func _form_reaction_line(reaction: int, event_id: String, fallback: String,
		valid: Callable) -> String:
	return _dialogue_service().reaction_line(reaction, event_id, fallback, valid)


func _form_note_reaction(key: String, cue_text: String, until: float) -> void:
	_dialogue_service().note_reaction(key, cue_text, until)


func _form_add_heat(amount: float) -> void:
	_readiness.add_heat(minf(amount, READINESS_MAX - satisfaction))


func _form_cue_override(text: String) -> void:
	_set_cue_override(text, _cue_override_seconds)


func _form_set_face(smile: float) -> void:
	_set_face(smile, FACE.ACT_LIDS)


func _form_status(text: String) -> void:
	HUD.toast(text, 2.5)


## The readiness host boundary: scene values the pure scoring needs, and the presentation it
## triggers. The runtime keeps the state, the face beats, the tolerance meter and the cue line.
func _readiness_state() -> int:
	return state


func _readiness_close() -> void:
	_act_face_beat("close")


func _readiness_anatomy_react() -> void:
	_anatomy_bridge.react()


func _readiness_heat() -> bool:
	return cycle_phase() == CYCLE.HEAT


func _readiness_cue(mood_value: String, cue_value: String, is_override: bool) -> void:
	_act_facts.mood = mood_value
	_act_facts.cue = cue_value
	_act_facts.cue_override = is_override
	_dialogue_service().admit_cue(_now_s())


## True while the director or the pony is actually speaking.
func _speech_busy() -> bool:
	return _dialogue_service().busy()


## Free a delivered line and expire a queued one at its max age. See `dialogue/service.gd`.
func _utterance_tick() -> void:
	_dialogue_service().tick()


## integration: one adult observer may say a short line, using the modern witness perception.
func _bystander_tick(delta: float) -> void:
	_dialogue_service().bystander_tick(delta)


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


func _end_act_lines(keep_speaking := true) -> void:
	_dialogue_service().end_act(_event_id, keep_speaking)


func _commit_summary(real_act: bool) -> void:
	_summary_service.commit_summary(real_act, _summary_service.summary_context(_summary_values()))


## The scene values the summary scores. The history facade owns the shape; this only gathers.
func _summary_values() -> Dictionary:
	return {
		"pony_id": _id,
		"event_id": _event_id,
		"preferences": _preferences,
		"seconds": _act_seconds,
		"thrusts": _readiness.act_thrusts,
		"pony_climaxes": pony_climaxes,
		"talk_liked": _readiness.act_liked_talk,
		"talk_dislikes": _readiness.act_talk_dislikes,
		"touches_liked": _readiness.act_liked_touch,
		"touch_dislikes": _readiness.act_touch_dislikes,
		"player_lines": _readiness.act_player_lines,
		"intensity_total": _readiness.act_intensity_total,
		"intensity_right": _readiness.act_intensity_right,
		"pattern_total": _readiness.act_pattern_total,
		"pattern_right": _readiness.act_pattern_right,
		"ended_early": _act_ended_early,
		"stopped_by_her": _stopped_by_her,
		"form_reveal": _handover.reveal_done,
	}


func _summary_inputs() -> Dictionary:
	return _summary_service.summary_inputs(_summary_values())


func _history_note() -> String:
	var row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), _id, ACT_HISTORY.day_now())
	return ACT_HISTORY.prompt_note(row)


## Idle-only history scan. The scene values are gathered here; `dialogue/service.gd` owns the
## decisions and the line queueing.
func _history_tick(delta: float) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game) \
			or not is_instance_valid(WORLD.player):
		return
	var director := _director()
	if director == null:
		return
	var target: Variant = pony.get("conversation_target")
	var body: Variant = WORLD.player_body()
	_dialogue_service().history_tick(delta, {
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
		"distance": WORLD.player.global_position.distance_to(pony.global_position),
		"target_is_player": target == WORLD.player or target == body,
	})


## The meter only advances during an act. A forced debug warning or stop runs here so it lands
## on the next frame after the Debug panel is closed. The readiness system owns the meter and the
## policy; this only carries out the cue, the face beat and the stop.
func _tolerance_tick(delta: float) -> void:
	if state not in [State.POSING_IN, State.ACTIVE]:
		return
	var action: String = _readiness.take_debug()
	if not action.is_empty():
		if action == "warning":
			_tolerance_warn(1)
		elif action == "stop":
			_stop_with_her("debug")
		return
	_readiness.tolerance_tick(delta)
	_present_tolerance(_readiness.take_tolerance_decision())


## Present one collected tolerance decision.
func _present_tolerance(decision: Dictionary) -> void:
	if decision.is_empty() or _stopped_by_her:
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
		_readiness.distress(), _readiness.last_dislike()])


func _queue_tolerance_warning(level: int) -> void:
	if not is_instance_valid(WORLD.game):
		return
	if not _tolerance_warning_key.is_empty():
		MEMORY.instance.cancel_line(_tolerance_warning_key)
	var act_id := _event_id
	var event_id := "%s:tolerance_warning:%d" % [_event_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state in [State.POSING_IN, State.ACTIVE] \
			and _event_id == act_id
	var fallback := ("Don't do that." if level <= 1 else "I said stop that.") \
		+ " Begin with [annoyed] or [calm]."
	_tolerance_warning_key = _dialogue_service().reaction_line(MEMORY.Reaction.TOLERANCE_WARNING, event_id, fallback, valid)


func _cancel_tolerance_warning() -> void:
	if not _tolerance_warning_key.is_empty() and is_instance_valid(WORLD.game):
		MEMORY.instance.cancel_line(_tolerance_warning_key)
	_tolerance_warning_key = ""


## A real consent stop. It ends the act without the normal afterglow/cuddle restore, commits a
## severe bad summary, and only Strict additionally bucks and requests space.
func _stop_with_her(reason: String) -> void:
	if _stopped_by_her or state not in [State.POSING_IN, State.ACTIVE]:
		return
	_stopped_by_her = true
	var strict := str(_preferences.get("tolerance", "normal")) == "strict"
	# The teardown resets readiness; keep the value that caused the stop for the log below.
	var distress: float = _readiness.distress()
	_cancel_tolerance_warning()
	_commit_summary(false)
	# The stopped summary already says why. The basic event is the fallback when the summary was
	# skipped, so one partner stop is never two memories.
	if _summary_service.summary.is_empty() and is_instance_valid(WORLD.game):
		MEMORY.instance.note(MEMORY.NoteKind.STOPPED, _id, _event_id, MEMORY.StopReason.WITHDREW)
	if _pose_family() == "bed":
		REST.release_managed(pony)
	_end_act_lines(true)
	_end_session(false)
	_finalize_session(true)
	if strict:
		_request_space()
		bool(_scene_gate().buck_or_push())
	# The summary owns the impression, including a skipped summary.
	if not _summary_service.summary.is_empty():
		_start_upset("angry" if strict else "annoyed")
	_queue_stop_line(strict)
	_log("stop withdrew tier=%s distress=%.1f reason=%s strict=%s" % [
		str(_preferences.get("tolerance", "normal")), distress,
		reason, str(strict)])


func _request_space() -> void:
	if not is_instance_valid(pony):
		return
	var rel: Variant = pony.get_meta("relationship_runtime") \
		if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("request_space"):
		bonds.call("request_space", _id)


func _queue_stop_line(strict: bool) -> void:
	if not is_instance_valid(WORLD.game):
		return
	var fallback := "Stop. I don't want to continue. Not now. Begin with [angry] or [sad]."
	if strict:
		fallback = "I told you to stop. Get off me and give me space. Begin with [angry] or [sad]."
	var event_id := "tolerance_stop_%s_%d" % [_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(pony) and state == State.IDLE
	_dialogue_service().reaction_line(MEMORY.Reaction.TOLERANCE_STOP, event_id, fallback, valid)


## The tail tuck after a partner stop: `poses/tail_tuck.gd` is a pose-scope node, so the runtime
## hosts it. The afterglow facade owns the decision that asks for it.
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
	_readiness.request_debug(kind)
	return true


## Store the strongest clean act per mare. The history system owns the eligibility and the text.
func _record_peak_memory() -> void:
	_summary_service.record_peak_memory({
		"pony_id": _id,
		"event_id": _event_id,
		"satisfaction": _readiness.peak_satisfaction,
		"both_matches": _readiness.act_both_matches,
		"dislikes": _readiness.act_dislikes,
		"liked_touch": _readiness.act_liked_touch,
		"liked_talk": _readiness.act_liked_talk,
		"player_talk": _readiness.last_player_talk,
		"her_at": _dialogue_service().last_spoken_at(),
		"her_line": _dialogue_service().last_spoken_line(),
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
		# The early summary already records this end. Keep the basic event only when the summary
		# was skipped, so the story never holds the same end twice.
		if _summary_service.summary.is_empty():
			MEMORY.instance.note(MEMORY.NoteKind.CANCELLED, _id, _event_id)
		# Cancel act lines before restoring, then queue the intentional early-stop reaction.
		_end_act_lines(true)
		_restore_begin()
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
				return MEMORY.instance.line_state(_end_early_key) == MEMORY.LineState.SPEAKING
			var key: String = _dialogue_service().reaction_line(MEMORY.Reaction.END_EARLY, act_id, ACT_SUMMARY.early_end_prompt(_summary_service.summary), valid)
			_end_early_key = key
			if not key.is_empty():
				var now := _now_s()
				_dialogue_service().note_reaction(key, "", now + _cue_reaction_max_age_s)
				_log("utterance kind=reaction key=%s" % key)
			# The stopped act gets one post-act beat at most: suppress the later history line
			# for the same act, even when the roll chose silence. A skipped summary must not
			# clear an older act's pending reminder.
			if not _summary_service.summary.is_empty() \
					and ACT_HISTORY.mark_announced(ACT_HISTORY.section(), _id, "complaint"):
				ACT_HISTORY.save()
	elif state == State.AFTERGLOW:
		end_afterglow()

func end_afterglow() -> void:
	if state == State.AFTERGLOW:
		_log("afterglow end pony=%s" % str(pony.name))
		_afterglow.cancel_close()
		_restore_begin()

func _climax() -> void:
	if state != State.ACTIVE:
		return
	pony_climaxes += 1
	_log("pony climax=%d pose=%s pony=%s readiness=%.0f" % [
		pony_climaxes, str(_start_row().get("id", "")), str(pony.name), satisfaction])
	_set_state(State.CLIMAX)
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0
	mood = "climax"
	cue = "She is climaxing."
	_set_cue_override("She is climaxing.", CLIMAX_SECONDS)
	_handover.hint_tick()
	_reactions.schedule_hearts()
	_reactions.hearts_burst_at(_reactions.dock_point())
	_set_face(0.3, FACE.CLIMAX_LIDS)
	_act_face_beat("climax")
	_end_act_lines(true)
	if is_instance_valid(WORLD.game) and pony_climaxes == 1:
		MEMORY.instance.note(MEMORY.NoteKind.CLIMAXED, _id, _event_id)
	_queue_climax_reaction()
	_play_climax()
	# integration: her fluid hook.
	_anatomy_bridge.on_climax()
	if is_instance_valid(HUD.instance):
		HUD.instance.set_state("CLIMAX")


func _queue_climax_reaction() -> void:
	# Her mouth is busy during oral; the climax line waits for a later act.
	if _mouth_contact():
		return
	if not is_instance_valid(WORLD.game):
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
		return MEMORY.instance.line_state(_climax_reaction_key) == MEMORY.LineState.SPEAKING
	var key: String = _dialogue_service().reaction_line(MEMORY.Reaction.CLIMAX, climax_id, "You have just climaxed. Say one short sentence, at most 12 words, in your own voice. Begin with [surprised], [happy] or [calm]. Staying quiet is fine.", valid)
	_climax_reaction_key = key
	if key.is_empty():
		return
	var now := _now_s()
	_dialogue_service().note_reaction(key, cue, now + _cue_reaction_max_age_s)
	_log("utterance kind=reaction key=%s" % key)

## The first ACTIVE entry after the pose settles. Later returns from a climax are CLIMAX_END.
func _enter_active() -> void:
	_set_state(State.ACTIVE)
	_handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.ACTIVE)


## The pony climax ends on its own. It returns to ACTIVE unless the configured limit was
## reached; afterglow is the player's choice, not the climax state's automatic exit.
func _finish_climax() -> void:
	_handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.CLIMAX_END)
	if _max_pony_climaxes > 0 and pony_climaxes >= _max_pony_climaxes:
		_enter_afterglow()
		return
	_set_state(State.ACTIVE)
	_face.stare_release_until = 0.0
	_set_face(0.45, FACE.ACT_LIDS)
	satisfaction = 0.0
	mood = "warming"
	cue = ""
	_handover.hint_tick()
	_readiness.cue_override = ""
	_readiness.cue_until = 0.0
	_readiness.overwhelmed = 0.0
	_readiness.last_intensity = ""
	_readiness.last_pattern = ""
	_readiness.stroke_window.clear()
	_readiness.last_stroke_at = -1000.0
	_readiness.last_thrust_score_at = -1000.0
	_readiness.receptive_until = 0.0
	var limit_text := "∞" if _max_pony_climaxes <= 0 else str(_max_pony_climaxes)
	_log("pony climax end=%d/%s readiness=0" % [pony_climaxes, limit_text])

## Estrus phase. The eligibility owner resolves the debug override, the feature flag and the
## world day; the validity guard keeps a body freed during teardown from reaching it.
func cycle_phase() -> String:
	_read_id()
	if not is_instance_valid(pony):
		return CYCLE.NORMAL
	return ELIGIBILITY.cycle_phase_for(pony, _id)


## The session override currently in force, or "" when the automatic cycle owns the phase.
func cycle_override() -> String:
	_read_id()
	return CYCLE.override_for(_id)


## Session-only estrus override: heat, diestrus, normal, or "" to resume the automatic cycle. The
## debug action is the shipped writer; the runtime keeps the protocol for its suites.
func set_cycle_override(phase_name: String) -> void:
	_read_id()
	CYCLE.set_override(_id, phase_name)


## Private heat/diestrus note for the normal dialogue prompt, outside and during acts. The
## eligibility owner keeps the gate check and the note.
func cycle_note() -> String:
	if not is_instance_valid(pony):
		return ""
	var service: Variant = _eligibility_service()
	return service.cycle_note(pony) if service != null else ""


## Short private relationship facts for normal dialogue. Empty outside a relationship runtime.
func _relationship_note() -> String:
	if not is_instance_valid(WORLD.game):
		return ""
	_read_id()
	return RELATIONSHIP_CUE.note(MEMORY.instance.cue_facts(_id, _event_id).to_dict())


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	_read_id()
	var form := _body_form()
	return _dialogue_service().prompt_note({
		"state": state,
		"warm": _face.warm_note,
		"history": _history_note(),
		"beat": _afterglow.beat,
		"relation": _relationship_note(),
		"caressing": _hand_controller().any_active(),
		"leaning": _act_camera.lean_forward >= 0.35 or _act_camera.lean_action_active or _kiss_controller().leaning_close(),
		"missionary": _pose_family() == "bed",
		"form_source": _handover.source() != null,
		"form_name": form.form_name.strip_edges() if form != null else "",
		"form_borrowed": form != null and not form.is_own(),
	})


func _afterglow_caressing() -> bool:
	return _hand_controller().any_active()

func _enter_afterglow() -> void:
	_afterglow_begin()

func _commit_afterglow() -> void:
	if not is_instance_valid(WORLD.game):
		return
	_commit_summary(true)
	_record_peak_memory()
	for row: MEMORY.Witness in MEMORY.instance.witnesses(_id, _display_name, _serial, pony):
		_log("witness " + str(row.to_dict()))

## Both poses share the held afterglow; standing adds the close window and a slightly lifted
## tail.
func _afterglow_begin() -> void:
	_log("afterglow pose=%s pony=%s" % [pose_id, str(pony.name)])
	_stop_auto()
	_end_act_lines(true)
	# Bed afterglow keeps only lean and caress; standing keeps its kiss.
	if _pose_family() != "standing":
		_kiss_controller().end_lean_kiss()
	_commit_afterglow()
	_set_state(State.AFTERGLOW)
	_handover.hint_tick()
	_handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.AFTERGLOW)
	_sync_act_facts()
	# The oral afterglow releases the mouth contact and keeps the turned pose. The pose row's
	# afterglow profile is passive, so no standing close window opens.
	_pose_service().release_mouth_contact()
	_integrations_controller().afterglow()
	_afterglow.bind_view(_pose_session.view())
	_afterglow.begin(_summary_service.summary)
	cue = ""
	_readiness.cue_override = ""
	_readiness.cue_until = 0.0
	_face.stare_release_until = 0.0
	_set_face(0.85, FACE.AFTERGLOW_LIDS)
	_act_face_beat("afterglow")
	_apply_afterglow_presentation(_afterglow.presentation())


## Apply the afterglow facade's presentation row in the built order: the pose weight, the tail,
## the HUD state, then the wings. The evaluator keeps its current pair, so the pose holds.
func _apply_afterglow_presentation(row: Dictionary) -> void:
	if is_instance_valid(_pose_session.pose()):
		_pose_session.pose().target_amount = 1.0
		_pose_session.pose().amount = 1.0
	_pose_service().set_tail_target(float(row.get("tail_target", 0.35)))
	var flicks := int(row.get("tail_flicks", 0))
	if flicks > 0:
		_pose_service().flick_tail(flicks)
	if is_instance_valid(HUD.instance):
		HUD.instance.set_state(str(row.get("hud_state", "AFTERGLOW")))
	if bool(row.get("wings", false)):
		_wings_controller().begin_afterglow()

func _afterglow_tick(delta: float) -> void:
	if state != State.AFTERGLOW:
		return
	# integration: keep the optional bed-body part tracking through afterglow.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.afterglow_tick(delta)
	if state != State.AFTERGLOW or _pose_family() != "standing":
		return
	_afterglow.close_tick(delta)

## The standing close window elapsed. The facade decided the reward; the runtime presents it.
func _on_stay_close(caressed: bool, reward: bool) -> void:
	if is_instance_valid(WORLD.game):
		var impression := MEMORY.Impression.new()
		impression.id = _id
		impression.event_id = _event_id
		impression.slot = MEMORY.ImpressionSlot.STAY_CLOSE
		impression.mood = "happy" if reward else ""
		impression.romance = 1 if reward and caressed else 0
		MEMORY.instance.commit(impression)
	if not reward and caressed:
		if ACT_HISTORY.repair(ACT_HISTORY.section(), _id, 1, ACT_HISTORY.day_now()):
			ACT_HISTORY.save()
	_set_face(0.9, FACE.AFTERGLOW_CLOSE_LIDS)
	_reactions.hearts_burst()
	cue = ""

func close_hint() -> String:
	if state != State.AFTERGLOW or _pose_family() != "standing":
		return ""
	return _afterglow.hint()

func _restore_begin() -> void:
	if state == State.IDLE or state == State.RESTORE:
		return
	_record_peak_memory()
	_afterglow.cancel_close()
	_stop_auto()
	_end_act_lines(true)
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	_set_state(State.RESTORE)
	_handover.hint_tick()
	# integration: act-only anatomy hides as soon as the act starts restoring.
	_anatomy_bridge.apply_live()
	_restore_left = RESTORE_SECONDS
	_clear_face()
	_end_act_face()
	_wings_controller().release()
	if is_instance_valid(_pose_session.pose()):
		_pose_session.pose().target_amount = 0.0
	_pose_service().set_tail_target(0.0)
	_stop_breath()
	_camera_service().call("release_back")
	_standing_camera_controller().reset_facing()
	if is_instance_valid(HUD.instance):
		HUD.instance.hide_act()

## Give back everything the act borrowed, in the order the pose and camera were built. Every step
## checks its own ownership flag, so a start that failed early runs the same function and restores
## only what it took. Keep this the only exit path. `_end_act_lines()` is deliberately outside:
## `cancel()` queues the early-stop reaction after `_restore_begin()`, and `_finish_restore()` must
## not cut it. The utterance scheduler is start/finalize state, not a session borrow.
func _end_session(rejoin_cuddle: bool) -> void:
	_stop_auto()
	# A suspended act may end here (world close, a failed swap or an invalid body). Drop the
	# handover before the normal teardown; it is not a second exit path.
	_handover.abort()
	_handover.end_act()
	PONIES.clear_body_swap(self)
	# Capture the bed before the session state is cleared: a normal end of a bed missionary act
	# returns Anon and her to it, but only when it did not go badly.
	var rejoin_bed: Node3D = null
	var rejoin_serial := _serial
	if rejoin_cuddle and _start_frame() == "bed" \
			and source in ["bed_side", "already_lying"] and not _stopped_by_her \
			and bool(_rest_service().call("rejoin_wanted", _rest_context())):
		rejoin_bed = bed
	# integration: close the anatomy act once, before the pose is freed.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()
	# The oral turn's facing override must not outlive the act, even on a direct forced stop.
	_standing_camera_controller().reset_facing()
	_set_inventory_hud_hidden(false)
	_kiss_controller().restore_forelegs()
	_restore_face_turn()
	_camera_service().call("restore_eye_override")
	if is_instance_valid(pony):
		_clear_face()
		_end_act_face()
		_wings_controller().release()
	_unlock_player()
	if _act_camera.camera_owned:
		_restore_camera()
	_release_stool()
	if is_instance_valid(pony):
		pony.remove_meta("sex_active")
	# integration: hide the player part when the act ends.
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_encounter"):
		service.call("player_encounter", false)
	_release_nav()
	if _act_camera.look_captured:
		_restore_look()
	if _posture_owned:
		_restore_posture(_start_frame(), rejoin_cuddle)
	_free_pose()
	_restore_pony_bones()
	_stop_audio()
	if is_instance_valid(WORLD.game):
		if is_instance_valid(HUD.instance):
			HUD.instance.hide_all()
		PONIES.clear_active(self)
	_set_state(State.IDLE)
	pose_id = ""
	source = ""
	bed = null
	# integration: act-only anatomy hides immediately when the act ends.
	_anatomy_bridge.apply_live()
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

## The bed/couch rest and cuddle rejoin. See `rest/service.gd` and `docs/rest.md`.
func _rest_service() -> RefCounted:
	_rest.bind(pony, bed)
	return _rest


## The live act values the rejoin decisions need. Read fresh on every check, so the async paths
## see a new act or an ended session instead of the values from the call that started them.
func _rest_context() -> Dictionary:
	return {
		"serial": _serial,
		"state": state,
		"player_pony": _player_pony,
		"headset": _headset_view(),
		"summary": _summary_service.summary,
		"satisfaction": satisfaction,
		"aftercare_min": _aftercare_min,
	}


func _rest_restore_scene() -> void:
	_missionary_camera_controller().restore_scene()


## Give the bed back: restore the pre-act scene and stand her. A bed missionary act that ended well
## is re-seated and re-invited by `_rejoin_bed_cuddle()` after the session is fully back to IDLE.
## A forced stop never reaches it; the world is going away or the pony is already invalid.
func _restore_posture(frame: String, rejoin_cuddle: bool) -> void:
	_posture_owned = false
	_rest_service().call("restore_posture", frame, rejoin_cuddle)


func _rejoin_bed_cuddle(bed_node: Node3D, act_serial: int) -> void:
	await _rest_service().call("rejoin_bed_cuddle", bed_node, act_serial)


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

## The after-act. The order is the act exit's: the stroke state resets, the meter runs down, and
## the act ends in either the tail tuck after a partner stop or the aftercare beat. The afterglow
## facade owns the decisions and the values; this hosts the nodes.
func _reset_after_act() -> void:
	if not is_inside_tree():
		return
	_reset_thrust_state()
	_afterglow.decay_satisfaction(satisfaction)
	var plan: AFTERGLOW.PostAct = _afterglow.post_act(_stopped_by_her, satisfaction,
		_aftercare_min, not _summary_service.summary.is_empty(),
		bool(_summary_service.summary.get("positive", false)))
	if plan.tail_tuck:
		_start_tail_tuck()
	elif is_instance_valid(pony) and _afterglow.start_aftercare(pony, plan):
		_bind_face()
		_face.start_post_act(plan.face_context(_summary_service.summary))


## The afterglow's satisfaction decay writes here; the meter's range is readiness's.
func _write_satisfaction(value: float) -> void:
	satisfaction = clampf(value, 0.0, READINESS_MAX)


## Compatibility aliases: the lab's anger keys still use these names.
func _start_upset(mood: String) -> void:
	_bind_face()
	_face.start_upset(mood)

func _end_upset() -> void:
	_bind_face()
	_face.end_upset()

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
	if not is_instance_valid(WORLD.game) or _id.is_empty():
		return false
	var facts: MEMORY.CueFacts = MEMORY.instance.cue_facts(_id, _event_id)
	return facts.first_time


## Live presentation score for the auto climax face. This never writes the summary or history:
## the runtime gathers its counters and the facade owns the shape `shared/act_face.gd` reads.
func _climax_quality_inputs() -> Dictionary:
	_bind_face()
	return _face.climax_quality({
		"intensity_total": _readiness.act_intensity_total,
		"intensity_right": _readiness.act_intensity_right,
		"pattern_total": _readiness.act_pattern_total,
		"pattern_right": _readiness.act_pattern_right,
		"both_matches": _readiness.act_both_matches,
		"liked_touch": _readiness.act_liked_touch,
		"liked_talk": _readiness.act_liked_talk,
		"touch_dislikes": _readiness.act_touch_dislikes,
		"talk_dislikes": _readiness.act_talk_dislikes,
		"distress": _readiness.distress(),
		"preferences": _preferences,
		"overwhelmed": _readiness.overwhelmed > 0.0,
	})


## The facade is bound in `_ready`; a suite that builds a runtime without entering the tree
## binds it on the first call.
func _bind_face() -> void:
	if _face.pony != pony or _face.host != self:
		_face.bind(pony, self)


## One act face moment. The runtime gathers the act values; the facade applies the debug flag and
## the beat table.
func _act_face_beat(moment: String) -> void:
	_bind_face()
	var ctx := {
		"first_time": _first_time,
		"tolerance": str(_preferences.get("tolerance", "normal")),
	}
	if moment == "climax":
		ctx["climax_mode"] = _act_climax_mode
		ctx["quality"] = _climax_quality_inputs()
	elif moment == "afterglow":
		ctx["summary"] = _summary_service.summary
	_face.act_beat(moment, ctx, _feature("face_debug"))


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
	_face.sync_settings(_feature("face_debug"))


## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_act_face(face: String) -> bool:
	_bind_face()
	_face.debug_enabled = _feature("face_debug")
	return _face.force_face(face)


## Debug view for the "Show act face" action.
func act_face_rows() -> Array[String]:
	_bind_face()
	var base_mood := ""
	if is_instance_valid(WORLD.game) and not _id.is_empty():
		var facts: MEMORY.CueFacts = MEMORY.instance.cue_facts(_id, _event_id)
		base_mood = facts.mood
	return _face.rows({
		"state": state,
		"hud_mood": mood,
		"base_mood": base_mood,
		"climax_mode": _act_climax_mode,
		"blush_arc": _feature("blush_arc"),
	})

# --------------------------------------------------------------------------- checks

func _check_running() -> void:
	if not is_instance_valid(pony):
		force_stop()
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
	if _hold.nav != null and is_instance_valid(_hold.nav) and str(_hold.nav.get("reserved_by")) != "":
		_stop("interrupted")
		return
	if _pose_family() == "bed" and bed != null and WORLD.bed_occupied(bed, pony):
		_stop("interrupted")
		return
	if _player_pony != PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree())):
		_stop("form change")
		return

func _stop(reason: String) -> void:
	_log("stop reason=%s state=%d pony=%s" % [reason, state, str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX]:
		MEMORY.instance.note(MEMORY.NoteKind.STOPPED, _id, _event_id, _stop_reason(reason))
	_restore_begin()

# --------------------------------------------------------------------------- camera

func _size_scale() -> float:
	return float(_camera_service().call("size_scale"))


func _begin_camera_mode() -> void:
	_camera_service().call("open_shot")
	_standing_anon_controller().reset_phase()
	_missionary_camera_controller().reset_look()
	# The act's own Anon body is created by the pose session on its first pose change (desktop human
	# only; AnonPony and VR have their own bodies).
	# integration: the VR standing act; it uses the headset rig and no desktop camera.
	if _headset_view() and not _player_pony and _pose_family() == "standing":
		_start_vr_act()
	if _player_pony or _headset_view():
		return
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return
	_camera_service().call("begin_free")
	_sync_act_facts()
	if _pose_family() == "standing" and is_instance_valid(_act_camera.camera):
		_standing_camera_controller().prepare()
		_standing_anon_controller().install()
	_camera_service().call("apply_free_camera_lock")


## Lean/caress remain live through the afterglow in both poses. Missionary keeps its passive
## afterglow otherwise: no kiss, reach or close window.
func _act_actions_allowed() -> bool:
	return bool(_camera_service().call("at_actions_allowed"))


func shot_lean_forward() -> float:
	return float(_camera_service().call("shot_lean_forward"))


func _jiggle_size_scale() -> float:
	return float(_camera_service().call("jiggle_size_scale"))


func smack() -> void:
	_hand_controller().smack()


func _lean_action_tick() -> void:
	_camera_service().call("tick_lean_action")


func _play_mouth_kiss() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.play_mouth_kiss()


func _neck_midpoint() -> Vector3:
	var point: Variant = _camera_service().call("neck_midpoint")
	return point if point is Vector3 else Vector3.INF


func _pose_render_write() -> void:
	_pose_service().render_write({
		"bed_frame": _pose_session.bed_frame,
		"body_scale": _body_scale_value(),
		"size_name": _act_facts.size_name,
		"eye_camera_active": _act_camera.free_camera_active \
			and str(SETTINGS.camera_mode.get_value()) == "eye",
	})


## Park the game's desktop presentation (it re-enables itself) for the bed family. The pose
## session owns the render-time sequence and calls this before it writes the pose.
func _hide_act_avatar() -> void:
	_missionary_camera_controller().hide_avatar()


## Publish or clear the pose session's opaque Anon body handle on the anatomy bridge. The session
## owns the body; the bridge only reads it.
func _set_missionary_anon_handle(body: Variant) -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.set_missionary_anon(body)


## The eye camera reads his posed head, so it has to run after the render write, not from the
## physics tick where the pose is one frame older.
func _missionary_eye_tick() -> void:
	_missionary_camera_controller().tick()


## The render-time placement trace, driven by the pose session.
func _idle_pose_sample() -> void:
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
	return _anatomy_bridge.diag_row(missionary_face_point(), missionary_vulva_point())


## The camera owner resolves the missionary face point and the vulva target; they are shot
## geometry. The anatomy diagnostic row and the shot camera read the runtime's forwards.
func missionary_face_point() -> Vector3:
	return _camera_service().missionary_face_point()


## The pulled-back shot's target: the vulva when the anatomy is showing, otherwise a point between
## her hind femurs lifted toward her belly.
func missionary_vulva_point() -> Vector3:
	return _camera_service().missionary_vulva_point()


func _body_scale_value() -> float:
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


## Dispatch the act shot through the camera facade. The facts are refreshed first so the shot
## reads this frame's lean and look.
func apply_camera_motion() -> void:
	if _suspended:
		return
	refresh_view()
	_sync_hud_facts()
	if not bool(_camera_service().call("motion_ready")):
		return
	_camera_service().call("apply_motion")


## Shared desktop hand driver for the caress and the standing body wrapper.
func _desktop_pose_driver() -> Node:
	return _standing_anon_controller().driver()


func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_thrust(hip, facing)


func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_lean(hip, facing)


func _restore_look() -> void:
	_camera_service().call("restore_look", _start_family())


## Give the camera back in the order the shot was built. The facade owns the leaves; the runtime
## keeps the ordered ledger and the cross-system releases.
func _restore_camera() -> void:
	if not _act_camera.camera_owned:
		return
	_act_camera.camera_owned = false
	_camera_service().call("end_lean_action")
	_hand_controller().reset()
	_camera_service().call("release_free_camera_lock")
	_standing_anon_controller().remove()
	_camera_service().call("restore_eye_override")
	_missionary_camera_controller().release()
	_sync_act_facts()
	_standing_camera_controller().restore()
	_camera_service().call("close_shot")
	_standing_anon_controller().reset_phase()


# --------------------------------------------------------------------------- audio

## The act audio node. One per runtime for the process; `bind()` names the act's pony, id and bed,
## `begin()` opens it and `end()` closes it, so the Ponese mute policy keeps its saved volume
## across the act boundary.
func _audio_service() -> Node:
	if is_instance_valid(_act_audio):
		return _act_audio
	var audio_script: Script = load(ACT_AUDIO_PATH)
	if audio_script == null:
		return null
	_act_audio = audio_script.new()
	_act_audio.name = "UnfplapActAudio"
	_act_audio.log = Callable(self, "_log")
	add_child(_act_audio)
	return _act_audio


func _start_audio() -> void:
	_stop_audio()
	var audio: Variant = _audio_service()
	if audio != null:
		audio.bind(pony, _id, bed)
		audio.begin()


## The audio facade reads her snout, the bed point and the director's vocal cache key from its
## bind, so a new presented body rebinds it without restarting the act's layer.
func _bind_audio_identity() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.bind(pony, _id, bed)


func _stop_audio() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.end()


func _stop_breath() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.stop_breath()


func _play_climax() -> void:
	if is_instance_valid(_act_audio):
		_act_audio.climax()


func _breath_tick(delta: float) -> void:
	if is_instance_valid(_act_audio):
		_act_audio.tick(delta, _act_audio.phase_for_state(state),
			_readiness.thrusts_per_second())

## The kiss foreleg overrides are global AffectionPose settings. Restore them if the world
## closes or the mod is switched off mid-kiss.
func _exit_tree() -> void:
	if _swapping_parent:
		return
	PONIES.clear_body_swap(self)
	_kiss_controller().restore_forelegs()
	_release_stool()
	_end_tail_tuck()
	_clear_aftercare()
	# integration: never leave the anatomy nodes or the per-act controller behind.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()
	_anatomy_bridge.detach()
	_face.shutdown()
