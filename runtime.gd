extends Node
## One per pony. The per-pony host and act orchestrator: lifetime, the act's own `act/` modules
## (state and clock, host, context, view, idle), the one composition and bind pass, the ordered
## idle/physics/render schedules, the start/teardown ledgers and the one act view call. It owns no
## system's rules or mutable state and never edits game files.

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
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
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
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_CONSENT := preload("res://mods/unfplap/act/consent.gd")
const AUDIO_ACT := preload("res://mods/unfplap/audio/act.gd")
const ACT_IMPACT := preload("res://mods/unfplap/act/impact.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const ACT_IDLE := preload("res://mods/unfplap/act/idle.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_START := preload("res://mods/unfplap/act/start.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
## Loaded lazily so both audio flags off never load the pack streams or the catalogue.
const ACT_AUDIO_PATH := "res://mods/unfplap/audio/service.gd"

const State := ACT_STATE.State

const READINESS_MAX := 100.0
const CLIMAX_SECONDS := ACT_SESSION.CLIMAX_SECONDS
const POSE_IN_SECONDS := ACT_SESSION.POSE_IN_SECONDS
const RESTORE_SECONDS := ACT_SESSION.RESTORE_SECONDS
## A player-requested reveal is the act's one exceptional beat; its heat, peak, cue and memory
## mark are the provider policy's, not the base runtime's. The handover owns the form flags.
const AGREEMENT_WAIT := ACT_START.AGREEMENT_WAIT
const AGREEMENT_STARTED := ACT_START.AGREEMENT_STARTED
const AGREEMENT_FAILED := ACT_START.AGREEMENT_FAILED

## The pony this runtime presents. Assigning a body rebinds the pose session's pony once.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_pose_session.bind(self, value if is_instance_valid(value) else null)
		if _act_host != null:
			_act_host.pony = value

var _pony_node: Node = null

## The act's one state, timer, clock and value owner; created once per pony and reset per act.
var _act: ACT_SESSION = null
## The act modules' node operations and typed collaborator set, bound once in `_build_systems()`.
var _act_host: ACT_NODE = null
var _act_context: ACT_CONTEXT = null
var _view: ACT_VIEW = null
var _consent: RefCounted = null
var _impact: ACT_IMPACT = null
var _idle: ACT_IDLE = null
var _exit: ACT_EXIT = null
var _start: ACT_START = null

## Temporary read-only forward: the act session owns the live state; remove in R4.
var state: int:
	get:
		return _act.state if _act != null else State.IDLE
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
## Debug perf probe: timed chunks report here and one summary prints per window. Built in `_init()`
## once the systems exist, because the host binds their live reads. See `shared/perf.gd`.
var _perf_probe: PERF = null
## Cached gate for the idle probe. Set once in `_ready()` and again on every live settings edit, so
## no tick reads the entry node's flags.
var idle_perf := false
## Estrus is derived from the world day and her relationship, so it is resolved once per tick and
## the HUD card reads the cached flag.
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
## `reparent()` runs `_exit_tree()`. The handover moves the live runtime between bodies, so that
## signal must not run the world-close teardown it exists for.
var _swapping_parent := false
## The act's afterglow phase: the standing close window and the presentation it asks for.
## See `afterglow/service.gd` and `docs/afterglow.md`.
var _afterglow: RefCounted = AFTERGLOW.new()
## The act's scene ownership. The runtime keeps the act state and the teardown order; the service
## owns the flags. See `scene_hold/service.gd`.
var _hold: RefCounted = SCENE_HOLD.new()
## The stable act identity, owned by the session; this is the runtime's read-through handle.
var _id: String:
	get:
		return _act.pony_id if _act != null else ""
	set(value):
		if _act != null:
			_act.pony_id = value
## The act's settings snapshot. `_snapshot_settings()` is its only writer; the act tunables are read
## through `_snapshot.<name>`, never copied into a second field. A zeroed snapshot stands in until
## the first act, so an idle runtime reads the same zero values the fields used to default to.
var _snapshot: SETTINGS.ActSnapshot:
	get:
		return _act.snapshot
## The act's summary, grade and peak record; see `summary/service.gd`. The runtime reads it as
## `_summary_service.summary`.
var _summary_service: RefCounted = SUMMARY.new()
var _end_early_key := ""
var _wings: WING = null
## The act's face owner: beats, line-face ownership, the stare release and the post-act mood
## face. See `face/service.gd` and `docs/face.md`.
var _face: RefCounted = FACE.new()
## Thrust and climax presentation: jiggle, smack reaction, rump blush and hearts. See
## `reactions/service.gd` and `docs/reactions.md`.
var _reactions: RefCounted = REACTIONS.new()
var _hands: HANDS = null
var _kiss: KISS = null
var _integrations: INTEGRATIONS = null
var _missionary_camera_ctl: MISSIONARY_CAMERA = null
var _standing_camera_ctl: STANDING_CAMERA = null
var _standing_anon_ctl: STANDING_ANON = null
var _standing_presentation_ctl: STANDING_PRESENTATION = null
## One runtime's act audio: the lazy node, the voice policy and the excitement Beat holds.
var _audio: AUDIO_ACT = null

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
	_act_camera.standing_anon = _standing_anon_ctl
	_audio = AUDIO_ACT.new()
	_audio.bind(self)
	_audio.log = Callable(self, "_log")
	_bind_act_frame()


## The typed collaborator set the view and idle modules read. Built once, after the systems.
func _build_act_context() -> ACT_CONTEXT:
	var context := ACT_CONTEXT.new()
	context.pose = _pose_session
	context.camera = _act_camera
	context.readiness = _readiness
	context.afterglow = _afterglow
	context.face = _face
	context.reactions = _reactions
	context.dialogue = _act_dialogue
	context.anatomy = _anatomy_bridge
	context.handover = _handover
	context.gate = _scene
	context.facts = _act_facts
	context.kiss = _kiss
	context.summary = _summary_service
	context.presentation = _standing_presentation_ctl
	context.standing_anon = _standing_anon_ctl
	context.standing_camera = _standing_camera_ctl
	context.wings = _wings
	context.hands = _hands
	context.integrations = _integrations
	context.hold = _hold
	context.rest = _rest
	context.placement = _placement
	context.anatomy_host = _anatomy_host()
	context.missionary_camera = _missionary_camera_ctl
	return context


## Build the act's own host, context and modules once. The runtime node keeps the ordered ticks;
## these objects own the state, the view and the idle schedule.
func _bind_act_frame() -> void:
	_act_host = ACT_NODE.new()
	_act_host.bind(self)
	_act_host.log_sink = Callable(self, "_log")
	_act_host.perf_sink = Callable(self, "perf_note")
	_act_context = _build_act_context()
	_act = ACT_SESSION.new()
	_act.bind(_act_host, _act_context)
	_consent = ACT_CONSENT.new()
	_consent.bind(_act_host, _act_context, _act)
	_act_context.consent = _consent
	_impact = ACT_IMPACT.new()
	_impact.bind(_act_host, _act_context, _act)
	_act_context.impact = _impact
	_act_context.audio = _audio
	_view = ACT_VIEW.new()
	_view.bind(_act_host, _act_context)
	_idle = ACT_IDLE.new()
	_idle.bind(_act_host, _act_context, _act)
	_exit = ACT_EXIT.new()
	_exit.bind(_act_host, _act_context, _act)
	_start = ACT_START.new()
	_start.bind(_act_host, _act_context, _act, _exit, _view)
	_act.start = _start
	_act.view = _view
	_exit.start = _start



## Bind the pose session's host callbacks once. The body paths rebind the pony itself.
func _bind_pose_hosts() -> void:
	_pose_session.bind(self, pony if is_instance_valid(pony) else null)
	_pose_session.id = _act.pony_id
	_pose_session.hide_avatar = Callable(_missionary_camera_ctl, "hide_avatar")
	_pose_session.set_act_body = Callable(self, "_set_missionary_anon_handle")
	_pose_session.eye_camera = Callable(_missionary_camera_ctl, "tick")
	_pose_session.perf = Callable(self, "perf_note")
	_pose_session.facts = _act_facts
	_pose_session.mouth_point = Callable(self, "_oral_mouth_point")
	_pose_session.opening_point = Callable(self, "_oral_opening_point")
	_pose_session.face_point = Callable(self, "_anatomy_face_point")
	_pose_session.oral_kiss = Callable(_audio, "oral_kiss")
	_pose_session.oral_speech_stop = Callable(_act, "oral_speech_stop")
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
	_act_facts.neck_point = Callable(_act_camera, "neck_midpoint")
	_act_facts.set_look = Callable(self, "_act_set_look")
	_act_facts.set_forced_glance = Callable(self, "_act_set_forced_glance")
	_act_facts.set_camera_basis_ready = Callable(self, "_act_set_camera_basis_ready")
	_act_facts.director = Callable(self, "_director")
	_act_facts.now = Callable(self, "_now_s")
	_readiness.log = Callable(self, "_log")
	_readiness.clock = Callable(self, "_now_s")
	_readiness.state = Callable(self, "_readiness_state")
	_readiness.on_climax = Callable(_act, "climax")
	_readiness.on_close = Callable(self, "_readiness_close")
	_readiness.on_face = Callable(_act, "face_beat")
	_readiness.on_anatomy_react = Callable(self, "_readiness_anatomy_react")
	_readiness.heat_cycle = Callable(self, "_readiness_heat")
	_readiness.on_cue = Callable(self, "_readiness_cue")
	_readiness.shaft_length = Callable(self, "_player_shaft_length_m")
	_readiness.pose_family = Callable(self, "_pose_family")
	_summary_service.log = Callable(self, "_log")
	_afterglow.log = Callable(self, "_log")
	_afterglow.caress_active = Callable(self, "_afterglow_caressing")
	_afterglow.on_stay_close = Callable(_act, "on_stay_close")
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
	_act_facts.play_mouth_kiss = Callable(_audio, "play_mouth_kiss")
	_act_facts.act_actions_allowed = Callable(_act_camera, "at_actions_allowed")
	_act_facts.auto_panel_open = Callable(self, "auto_panel_open")
	_act_facts.standing_camera = Callable(self, "_standing_camera_controller")
	_act_facts.missionary_anon = Callable(self, "missionary_anon_body")
	_act_facts.anatomy_normal = Callable(self, "anatomy_normal")
	_act_facts.anatomy_opening = Callable(self, "anatomy_opening")
	_act_facts.authored_pose_asset = Callable(_pose_session, "authored_asset")
	_act_facts.missionary_face_point = Callable(_act_camera, "missionary_face_point")
	_act_facts.gaze_point = Callable(self, "_missionary_gaze_point")
	_act_facts.free_look_rotation = Callable(_act_camera, "free_look_rotation")
	_act_facts.desktop_pose_driver = Callable(self, "_desktop_pose_driver")
	_act_facts.cuddle_active = Callable(self, "_cuddle_active")
	_act_facts.free_of_affection = Callable(self, "_free_of_affection")
	_act_facts.pause_face_turn = Callable(self, "_pause_face_turn")
	_act_facts.restore_face_turn = Callable(self, "_restore_face_turn")
	_act_facts.hold_excitement = Callable(_audio, "hold_excitement")
	_act_facts.release_excitement = Callable(_audio, "release_excitement")
	_act_facts.mod_enabled = Callable(self, "_mod_enabled")
	_act_facts.on_touch = Callable(_readiness, "touch")
	_act_facts.on_smack = Callable(self, "_on_smack_impact")
	_act_facts.pose_host = Callable(self, "_runtime")
	_perf_probe = PERF.build(_perf_host())
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
	host.size_scale_cb = Callable(_act_camera, "size_scale")
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
	host.thrust_move_cb = Callable(_impact, "move")
	host.now_s_cb = Callable(self, "_now_s")
	host.set_penetration_m_cb = Callable(_impact, "set_depth")
	host.align_cb = Callable(self, "apply_anon_align")
	host.touch_cb = Callable(_readiness, "touch")
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
	host.attach_to_world_cb = Callable(self, "_handover_attach_to_world")
	host.release_carry_cb = Callable(self, "_handover_release_carry")
	host.release_contacts_cb = Callable(self, "_handover_release_contacts")
	host.remember_auto_cb = Callable(self, "_handover_remember_auto")
	host.release_act_body_cb = Callable(self, "_handover_release_act_body")
	host.release_scene_cb = Callable(self, "_handover_release_scene")
	host.free_pose_cb = Callable(self, "_handover_release_pose")
	host.restore_camera_cb = Callable(self, "_handover_restore_camera")
	host.stop_breath_cb = Callable(self, "_handover_stop_breath")
	host.resume_body_cb = Callable(self, "_handover_resume_body")
	host.prepare_anatomy_act_cb = Callable(self, "_handover_prepare_anatomy_act")
	host.apply_resume_settings_cb = Callable(self, "_handover_apply_resume_settings")
	host.rebind_reactions_cb = Callable(self, "_handover_rebind_reactions")
	host.set_act_pose_config_cb = Callable(self, "_handover_set_act_pose_config")
	host.rebuild_act_pose_cb = Callable(self, "_handover_rebuild_act_pose")
	host.sync_start_config_cb = Callable(self, "_handover_sync_start_config")
	host.reset_visual_for_form_cb = Callable(self, "_handover_reset_visual")
	host.reset_player_pelvis_cb = Callable(self, "_handover_reset_pelvis")
	host.reset_lean_cb = Callable(self, "_handover_reset_lean")
	host.prepare_start_camera_cb = Callable(self, "_handover_prepare_start_camera")
	host.open_camera_cb = Callable(self, "_handover_open_camera")
	host.hide_avatar_cb = Callable(self, "_handover_hide_avatar")
	host.reset_wings_cb = Callable(self, "_handover_reset_wings")
	host.claim_nav_cb = Callable(self, "_handover_claim_nav")
	host.pause_face_turn_cb = Callable(self, "_handover_pause_face_turn")
	host.reset_face_cb = Callable(self, "_handover_reset_face")
	host.apply_voice_policy_cb = Callable(self, "_handover_apply_voice_policy")
	host.apply_pose_change_cb = Callable(self, "_handover_apply_pose_change")
	host.apply_anatomy_live_cb = Callable(self, "_handover_apply_anatomy_live")
	host.begin_integrations_cb = Callable(self, "_handover_begin_integrations")
	host.sync_hud_cb = Callable(self, "_handover_sync_hud")
	host.resume_auto_cb = Callable(self, "_handover_resume_auto")
	host.rebind_body_cb = Callable(self, "_handover_rebind_body")
	host.prepare_standing_camera_cb = Callable(self, "_handover_prepare_standing_camera")
	host.new_body_adult_cb = Callable(self, "_new_body_is_adult")
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
	return str(_act.start_row().get("id", ""))


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


## Temporary read-only forward: the session owns the state; remove in R4.
func _state() -> int:
	return _act.state


## Temporary migration delegate: the act session owns the one state writer. The suites use it;
## R4 removes it with the rest of the facade.
func _set_state(next: int) -> void:
	_act._set_state(next)


## The live pose family, or the start spec's family before the first view fill.
func _pose_family() -> String:
	var view: Variant = _pose_session.view()
	var family := str(view.family) if view != null else ""
	return family if not family.is_empty() else _act.start_family()


## The live pose frame, or the start spec's frame before the first view fill.
func _start_frame() -> String:
	var view: Variant = _pose_session.view()
	var frame := str(view.frame) if view != null else ""
	return frame if not frame.is_empty() else str(_act.start_row().get("frame", ""))


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
	return _act.max_pony_climaxes


func _satisfaction_value() -> float:
	return satisfaction


func _cue_value() -> String:
	return cue


func _event_id_value() -> String:
	return _act.event_id


func _cue_reaction_max_age_value() -> float:
	return _snapshot.cue_reaction_max_age_s


func _auto_pace() -> float:
	return _readiness.auto_pace()


func _bed_frame() -> Variant:
	return _pose_session.bed_frame


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
	_act.refresh_identity()
	_bind_pose_hosts()
	call_deferred("refresh_identity")
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


## Write the state the persistent controller polls outside the act. The bridge owns the facts.
func _sync_anatomy_facts() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.sync_facts()


## Refresh the typed act view. `act/view.gd` composes it; the runtime keeps this one call so the
## phase ordering and the existing callers stay unchanged.
func refresh_view() -> void:
	_view.refresh(_act_facts, _act)


## Typed write-backs for the presentation controllers. The runtime keeps ownership of the forced
## glance; the captured look snapshot is the camera facade's.
func _act_set_look(yaw: float, pitch: float) -> void:
	_act_camera.look_yaw = yaw
	_act_camera.look_pitch = pitch
	_act_facts.look_yaw = yaw
	_act_facts.look_pitch = pitch


func _act_set_forced_glance(side: String) -> void:
	_act.forced_glance = side
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


## Debug perf probe. Timed chunks report microseconds here; `perf_note()` forwards to `shared/perf.gd`,
## which prints one summary a second so a pony-specific stall can be attributed to a modifier
## without a live profiler.
func _perf_enabled() -> bool:
	return LOG.debug_logs and LOG.debug_perf


## Called by every timed chunk (runtime, skeleton modifiers, HUD). Cheap no-op with both windows off.
func perf_note(key: String, usec: int) -> void:
	_perf_probe.note(key, usec)


## Time one call site for the probes (callers take the start stamp themselves).
func _timed(key: String, started: int) -> void:
	_perf_probe.time(key, started)


func _perf_tick(delta: float) -> void:
	_perf_probe.tick(delta)


## The act probe's typed host. Built once: the callables are bound methods, so a per-frame rebind
## must not allocate. See `shared/perf.gd`.
var _perf_host_cache: PERF.Host = null

func _perf_host() -> PERF.Host:
	if _perf_host_cache != null:
		return _perf_host_cache
	var host := PERF.Host.new()
	host.enabled_cb = Callable(self, "_perf_enabled")
	host.log_cb = Callable(self, "_log")
	host.show_cb = Callable(LOG, "perf_block")
	host.id_cb = Callable(self, "_act_id")
	host.pose_cb = Callable(self, "_perf_pose_id")
	host.state_cb = Callable(self, "_state")
	host.lean_forward_cb = Callable(_act_camera, "shot_lean_forward")
	host.lean_side_cb = Callable(self, "_perf_lean_side")
	host.hand_left_cb = Callable(_hands, "active").bind("L")
	host.hand_right_cb = Callable(_hands, "active").bind("R")
	host.near_mesh_cb = Callable(self, "_perf_near_mesh")
	host.tier_cb = Callable(self, "_perf_tier")
	host.wing_hold_cb = Callable(self, "_perf_wing_hold")
	host.winged_cb = Callable(self, "_perf_winged")
	host.idle_note_cb = Callable(LOG, "note")
	_perf_host_cache = host
	return _perf_host_cache


func _perf_pose_id() -> String:
	return _act.pose_id


func _perf_lean_side() -> float:
	return _act_camera.lean_view_side


## The pony build's near-mesh flag and simulation tier, or null when the game has neither.
func _perf_near_mesh() -> Variant:
	return pony.get("near_mesh_enabled") if is_instance_valid(pony) else null


func _perf_tier() -> Variant:
	return pony.get("sim_tier") if is_instance_valid(pony) else null


func _perf_wing_hold() -> bool:
	return _wings != null and bool(_wings.get("_wing_hold"))


func _perf_winged() -> bool:
	return _wings != null and bool(_wings.get("_winged"))


func _wings_controller() -> WING:
	return _wings

func _hand_controller() -> HANDS:
	return _hands

func _kiss_controller() -> KISS:
	return _kiss

func _integrations_controller() -> INTEGRATIONS:
	return _integrations

func _missionary_camera_controller() -> MISSIONARY_CAMERA:
	return _missionary_camera_ctl

func _standing_camera_controller() -> STANDING_CAMERA:
	return _standing_camera_ctl

func _standing_anon_controller() -> STANDING_ANON:
	return _standing_anon_ctl

func _standing_presentation_controller() -> STANDING_PRESENTATION:
	return _standing_presentation_ctl

## Feature flag from the act snapshot. Unknown flags read as off.
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
		request["features"] = _act.features
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
	_call_pose_changed(_audio, view)


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
	_scene.configure(state, _id, _act.features)


## Optional HUD cue and readiness readouts. The act continues without them.
func hud_readouts() -> bool:
	return bool(_act.feature("hud_readouts"))


## Optional act control card, separate from the pony state readouts.
func hud_controls() -> bool:
	return bool(_act.feature("act_controls"))


## The typed act view `main.gd` and `hud/service.gd` read. The runtime owns it; the HUD never
## probes this node for a method.
func act_view() -> RefCounted:
	return _act_facts


## The entry's live settings fan-out; the session owns the snapshot, the view and the voice policy.
func apply_live_settings() -> void:
	idle_perf = _act.apply_live_settings()


## True while the automatic stroke owns the depth. X only switches it in ACTIVE/CLIMAX.
func auto_active() -> bool:
	return _readiness.auto_active()

func _act_presentation(delta: float) -> void:
	if not is_instance_valid(pony):
		return
	_act.advance_act_seconds(delta)
	if _pose_family() == "bed":
		_missionary_camera_controller().hide_avatar()
		_aim_missionary_eyes()
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", ACT_FACE.blush_for(_act.act_phase(), satisfaction,
			_act.feature("blush_arc")))
	var wings_started := Time.get_ticks_usec()
	_wings_controller().tick(delta, str(_pose_service().view().family), satisfaction, _act._act_seconds)
	_timed("wings_tick", wings_started)
	_integrations_controller().tick(delta)

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
	_act.sync_pose_frame()
	_act.pose_render_write()
	_idle_pose_sample()
	_standing_camera_controller().clamp_look()
	_camera_service().call("write_look_target", _pose_session.pose())
	if state == State.CLIMAX:
		_act.refresh_climax_progress()
	_camera_service().call("tick_shot", delta, state,
		_standing_camera_controller().speed(), _act._climax_progress)
	_audio.tick(delta, state, _readiness.thrusts_per_second())

## Debug free look: the input service hands over the relative motion instead of a thrust.
func look_motion(relative: Vector2) -> void:
	_camera_service().call("look_input", relative)


func _headset_view() -> bool:
	return is_instance_valid(WORLD.game) and bool(WORLD.game.get("headset_view"))

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	var idle := idle_perf and state == State.IDLE
	_physics_tick(delta)
	var sync_started := Time.get_ticks_usec() if idle else 0
	_sync_anatomy_facts()
	if idle:
		perf_note("runtime_anatomy_sync", Time.get_ticks_usec() - sync_started)
	if _perf_probe.on():
		perf_note("runtime_physics", Time.get_ticks_usec() - started)


func _physics_tick(delta: float) -> void:
	# The handover owns the pause overlay: a suspended act runs no act work until the one resume.
	_body_swap_tick(delta)
	if _suspended:
		return
	_act.tick_clock(delta)
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
		_idle.tick(delta, idle_perf)
		return
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		force_stop()
		return
	_act.cycle_heat = cycle_phase() == CYCLE.HEAT
	_act.sync_pose_frame()
	if pony.sleeping:
		pony.sleeping = false
	_audio.tick_vocal(delta)
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
		if _consent.tick(delta) == ACT_CONSENT.STOP:
			_stop_with_her(_consent.stop_kind)
	_log_pose_settled()
	var kiss_started := Time.get_ticks_usec()
	_kiss_controller().tick(delta)
	_timed("kiss_tick", kiss_started)
	if state in [State.ACTIVE, State.CLIMAX]:
		var ai_started := Time.get_ticks_usec()
		_impact.auto_advance(delta)
		_impact.tick()
		_timed("runtime_ai", ai_started)
		if _anatomy_bridge.act_available():
			_anatomy_bridge.bind(_anatomy_host())
			_anatomy_bridge.tick(delta)
		if state == State.ACTIVE:
			var talk_started := Time.get_ticks_usec()
			_readiness.tick(delta)
			_talk_tick(delta)
			_handover.offer_tick()
			_bystander_tick(delta)
			_timed("runtime_talk", talk_started)
	if state in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.RESTORE]:
		_utterance_tick()
	var phase: int = _act.tick_timers(delta)
	if state == State.CLIMAX:
		_reactions.hearts_tick(delta)
	match phase:
		ACT_SESSION.ENTER_ACTIVE:
			_act.enter_active_act()
			# The start snapshot caught Anon mid stand-up, so his eye height was the reclined one; the
			# scene is settled now, and restoring to this is what puts the camera back correctly.
			if _pose_family() == "bed":
				_missionary_camera_controller().resnapshot()
			_handover.hint_tick()
		ACT_SESSION.FINISH_CLIMAX:
			_act.finish_climax()
		ACT_SESSION.FINISH_RESTORE:
			_finish_restore()
	if state == State.AFTERGLOW:
		_afterglow_tick(delta)
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
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW] \
			and _act.consume_check_clock(delta):
		var verdict: SCENE_GATE.RunningVerdict = _scene_gate().running_verdict(
			_hold.nav, _act.bed, _act.player_pony, _kiss_controller().base_active())
		if not verdict.ok:
			_stop(verdict.reason)
	var face_started := Time.get_ticks_usec()
	_act.eyes_tick()
	_timed("runtime_face", face_started)

# --------------------------------------------------------------------------- gates

## The live vertical gap; NAN when the rule or the anatomy is unavailable.
func stool_gap_m() -> float:
	return float(_start.stool().call("gap_m")) if _start.stool() != null else NAN

func stool_needed_count() -> int:
	return int(_start.stool().call("needed_count")) if _start.stool() != null else 0

func stool_case_count() -> int:
	return int(_start.stool().call("case_count")) if _start.stool() != null else 0


func stool_state_text() -> String:
	return str(_start.stool().call("state_text")) if _start.stool() != null else "stool unavailable"

func start_verdict(pose: String, act_source: String, bed_in: Variant = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	_act.refresh_identity()
	return _scene_gate().start_verdict(pose, act_source, bed_in, verdict_in)


## The scene-only start of an accepted Agreement: no policy verdict, no formation row, no
## aftercare. `frozen` carries the pose capability recorded at formation.
func scene_only_verdict(pose: String, act_source: String, bed_in: Variant = null,
		frozen: Variant = null, stool_need: int = -1, stool_have: int = -1) -> Variant:
	_act.refresh_identity()
	var capability: Variant = frozen if frozen != null else SCENE_GATE.FrozenPose.new(true, true)
	return _scene_gate().scene_only_verdict(pose, act_source, bed_in, capability,
		stool_need, stool_have)


## The live act values the debug status line reads. The debug pony helper owns the scene gather;
## the act's session values are the runtime's own.
func _debug_context() -> Dictionary:
	return _act.debug_context()


## The debug status line. The scene gate owns the row and verdict assembly.
func debug_line(pose: String, act_source: String, bed_in: Variant = null, distance := -1.0, dot := -1.0) -> String:
	_act.refresh_identity()
	return _scene_gate().debug_line(pose, act_source, bed_in, distance, dot)

## The stable pony id the act is on, read from the live body. `ponies` matches a prompt note
## to its one runtime through this; the id itself stays private to the act.
func live_id() -> String:
	_act.refresh_identity()
	return _act.pony_id


## The deferred identity retry after the first frame, for a mod that assigns it late.
func refresh_identity() -> void:
	_act.refresh_identity()


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

func find_bed_under() -> Node3D:
	return _scene_gate().find_bed_under()

## The Agreement start's answer. The start ledger owns the rows and the start body.
func start_agreement(handle: Variant, skip_presentation := false) -> int:
	return _start.start_agreement(handle, skip_presentation)


## True when the scene-only rows pass and, for a standing option, the presentation is settled.
func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	return _start.agreement_offer_ready(handle, skip_presentation)


## The hotkey's readiness: the scene-only rows plus Base clearance.
func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return _start.hotkey_ready(pose, act_source, bed_in)


## The footstool pair this call's gate used.
func hint_stool() -> Dictionary:
	return _start.hint_stool()


## The act key's immediate attempt, with no Agreement and no presentation wait.
func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	return _start.start_hotkey(pose, bed_in, act_source, skip_presentation)


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


## True while a shape change has the act suspended. `ponies` keeps the act's pending record and
## the debug actions see one change at a time.
func body_swap_pending() -> bool:
	return _suspended


## The act-side form request. The handover decides whether a source can take the form; a later
## handover tick suspends the act, so the act's state, depth and climaxes are never handed to a
## second runtime.
func request_form_change(true_form: bool, shape_id := "", by_player := false) -> Dictionary:
	return _handover.request(true_form, shape_id, by_player)


## Apply one handover action. The handover decides when and executes the ordered release, the
## adoption and the one resume; the runtime applies each verdict and ends a failed swap through
## the one exit.
func _body_swap_tick(delta: float) -> void:
	var action := _handover.tick(delta)
	if action == BODY_CHANGE_ACT.Action.SUSPEND:
		_handover.release(_handover.candidate)
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


## Suite seam for the watcher's suspend action; the handover owns the release order.
func _suspend_for_body_swap(change: BODY_CHANGE) -> void:
	_handover.release(change)


## Move the live runtime under another node without running its world-close `_exit_tree()`. The
## handover moves it off the old body and then onto the new one.
func attach_to_body(parent: Node) -> void:
	if not is_instance_valid(parent) or get_parent() == parent:
		return
	_swapping_parent = true
	reparent(parent)
	_swapping_parent = false


## `ponies` calls this when the source's new body spawns. The runtime is already under the entry;
## it moves under the new body, binds its pose, face and anatomy, and waits for the handover's
## resume. A body that is not an adult mare ends the act through the one exit.
func adopt_body(new_pony: Node) -> void:
	if not _suspended or not is_instance_valid(new_pony):
		return
	_handover.adopt(new_pony)
	pony = new_pony
	_bind_adopted_body()
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
	_handover.rebind(form)


## The same presented body carries a revised form: refresh the eye/pose/camera and the other
## body-bound systems without a resume, a second runtime or an act exit.
func refresh_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if _suspended or not _is_presented_body(body):
		return
	_handover.rebind(form)


func _is_presented_body(body: Node3D) -> bool:
	return is_instance_valid(body) and is_instance_valid(pony) and body == pony


## The one resume. The handover owns the rebuild; the runtime applies a no-body failure through the
## one exit. `_suspended` is read before the handover clears it.
func _resume_after_body_swap() -> void:
	var was_suspended := _suspended
	if _handover.resume():
		return
	if was_suspended:
		force_stop()


## The adopted body's bind before the resume: the pose, face, identity name, view, anatomy and
## scene gate. The handover resumes into it; this never resumes by itself.
func _bind_adopted_body() -> void:
	_pose_session.bind(self, pony)
	_face.bind(pony, self)
	_audio.bind_identity(pony, _id, _act.bed)
	_act.adopt_display_name(_handover.form(), pony)
	refresh_view()
	_anatomy_refresh()
	_refresh_scene_gate()


## One revised form's rebind for a presented body: every body-bound system in its order.
func _handover_rebind_body() -> void:
	var form := _body_form()
	_act.adopt_display_name(form, pony)
	_refresh_scene_gate()
	_pose_session.bind(self, pony)
	_face.bind(pony, self)
	_audio.bind_identity(pony, _id, _act.bed)
	refresh_view()
	_anatomy_refresh()
	_reactions.bind_scene(pony, _anatomy_bridge.controller)
	var view: Variant = _pose_session.view()
	_call_pose_changed(_hand_controller(), view)
	_call_pose_changed(_kiss_controller(), view)
	_call_pose_changed(_audio, view)


## Recompute the act's visual frame after a presented-form revision. The camera's old offset is
## undone before the new form is measured, then the standing placement is re-fitted. The act state,
## depth and climaxes are untouched; the pose session owns its own rebuild on a new body.
func _reset_visual_for_form(form: BODY_FORM.BodyForm) -> void:
	_act_camera.reset_for_form(_act.start_family(), _act.player_pony, form)
	_reanchor_player_for_form(form)
	refresh_view()


## Bind the placement handle's act values, then place, re-anchor or measure from them. The
## placement handle owns the math; the act session owns the values.
func _bind_placement(form: BODY_FORM.BodyForm = null) -> void:
	_act_context.placement.bind_act(_act.placement_values(form))


## A standing act places Anon at the body's gap. A different body form needs that pass again;
## the bed act keeps him where he is and its authored shot re-reads the live body scale.
func _reanchor_player_for_form(form: BODY_FORM.BodyForm = null) -> void:
	_bind_placement(form)
	var standing: Variant = _act_context.placement.reanchor_act(_pose_family())
	if standing is Transform3D:
		_standing_camera_controller().begin_facing(standing)


func _reset_player_pelvis() -> void:
	_bind_placement()
	_act_context.placement.reset_pelvis_act()


## The new body must still pass the act's adult-mare gate. A missing service reads as allowed, so
## a suite can drive the handover without the world's eligibility graph.
func _new_body_is_adult() -> bool:
	_bind_placement()
	return _act_context.placement.new_body_is_adult_act()


func _standing_gap(form: BODY_FORM.BodyForm = null) -> float:
	_bind_placement(form)
	return _act_context.placement.gap_act()


## The swap's ordered release steps the handover calls. Each is one act operation; the runtime
## keeps the node and the services, the handover keeps the order.
func _handover_attach_to_world() -> void:
	attach_to_body(WORLD.game)


func _handover_release_carry() -> bool:
	return _hold.release_carry()


func _handover_release_contacts() -> void:
	_kiss_controller().reset()
	_hand_controller().reset()


func _handover_remember_auto() -> void:
	_handover.remember_auto(_readiness.auto_active())
	_readiness.stop_auto()


func _handover_release_act_body() -> void:
	_wings_controller().release()
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()


func _handover_release_scene() -> void:
	_hold.release_nav()
	_hold.restore_face_turn()


## The one pose ledger plus the bone restore. This is the body-swap suspension, the third ledger
## caller; the act exit and the new-act prep are the other two.
func _handover_release_pose() -> void:
	_exit.free_pose()
	_act_context.pose.restore_bones()


func _handover_restore_camera() -> void:
	if _act_camera.camera_owned:
		_act_camera.release_act_shot()
		refresh_view()
		_act_camera.finish_act_shot()


func _handover_stop_breath() -> void:
	_audio.stop_breath()


## The swap's ordered resume steps the handover calls.
func _handover_resume_body() -> void:
	_pose_session.bind(self, pony)
	_face.bind(pony, self)
	_act.adopt_display_name(_handover.form(), pony)
	refresh_view()
	pony.sleeping = false
	if pony.has_method("set_sim_tier"):
		pony.set_sim_tier(pony.SimTier.HERO)
	pony.set_meta("sex_active", true)


func _handover_prepare_anatomy_act() -> void:
	_anatomy_refresh()
	_anatomy_act_refresh()


func _handover_apply_resume_settings() -> void:
	_act.preserve_auto_shape = true
	_act.snapshot_settings()
	_act.preserve_auto_shape = false


func _handover_rebind_reactions() -> void:
	_reactions.bind_scene(pony, _anatomy_bridge.controller)
	_reactions.apply_radius()


func _handover_set_act_pose_config() -> void:
	_pose_session.set_pose_config(SETTINGS.pose(_id, _act.start_group()))


## Rebuild the live pose on the new skeleton at the pose the act was in. The start ramp is
## skipped because the act is continuing, not entering.
func _handover_rebuild_act_pose() -> void:
	_act_context.pose.snapshot_bones()
	var camera: Camera3D = WORLD.camera()
	var look: Vector3 = pony.global_position
	var camera_at := Vector3.INF
	if camera is Camera3D:
		look = (camera as Camera3D).global_position
		camera_at = look
	var values := _act.pose_values(_handover.pose, look, camera_at, _act_camera.size_name())
	if not _pose_session.rebuild_act(values):
		_log("body swap: the new body has no pose skeleton")
		return
	_reactions.bind_tail(_pose_session.tail)


func _handover_sync_start_config() -> void:
	_act_context.pose.sync_start_config(_act.start_group())


func _handover_reset_lean() -> void:
	_act_camera.reset_lean_state()


func _handover_prepare_start_camera() -> void:
	var camera_row: Variant = _act.start_row().get("camera", {})
	var profile := str((camera_row as Dictionary).get("profile", "")) if camera_row is Dictionary else ""
	_act_context.camera.prepare_start(profile)


func _handover_open_camera() -> void:
	if _act_camera.begin_act_shot(_pose_family(), _act.player_pony, _headset_view()):
		_start_vr_act()


func _handover_hide_avatar() -> void:
	_missionary_camera_controller().hide_avatar()


func _handover_reset_wings() -> void:
	_wings_controller().reset()


func _handover_claim_nav() -> void:
	_claim_nav()


func _handover_pause_face_turn() -> void:
	_pause_face_turn(true)


func _handover_reset_face() -> void:
	_act.clear_face()
	_act.set_face(0.45, FACE.ACT_LIDS)


func _handover_apply_voice_policy() -> void:
	_audio.apply_voice_policy(_act.feature("mute_ponese_audio"), pony, _id)


func _handover_apply_pose_change() -> void:
	_pose_session.pose_changed(_pose_session.view())


func _handover_apply_anatomy_live() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.apply_live()


func _handover_begin_integrations() -> void:
	_integrations_controller().begin()


func _handover_sync_hud() -> void:
	if is_instance_valid(HUD.instance):
		_act.sync_hud()
		HUD.instance.update_from(_act_facts)


func _handover_resume_auto() -> void:
	if _handover.auto_on and state in [State.ACTIVE, State.CLIMAX]:
		_readiness.toggle_auto(depth)
	_handover.clear_auto()


func _handover_reset_visual() -> void:
	_reset_visual_for_form(_body_form())


func _handover_reset_pelvis() -> void:
	_reset_player_pelvis()


func _handover_prepare_standing_camera() -> void:
	if _pose_family() == "standing":
		_standing_camera_controller().prepare()


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
	_act.toggle_anatomy_hole()


## The `oral` command: request the standing oral pose, or the return edge when it is already
## active. The per-mare consent string is passed only when the anatomy service says yes; the
## feature is checked by the edge requirements, not here.
func toggle_anatomy_oral() -> void:
	_act.toggle_anatomy_oral()

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


## integration: precise action gates. With no act controller (feature off or no controller) the
## keys pass through and the HUD rows stay hidden.
func anatomy_hole_ready() -> bool:
	return _anatomy_bridge.hole_ready()


func anatomy_oral_ready() -> bool:
	return _anatomy_bridge.oral_ready()


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
	_act.anatomy_status(text, seconds)


## Idempotent stop for every state exit. It never moves the depth.
func _stop_auto() -> void:
	_readiness.stop_auto()


## The mouse's vertical travel as hip travel; the input service hands over the relative motion.
func thrust_motion(relative_y: float) -> void:
	_impact.motion(relative_y)


## The deepest the tip can reach, in metres. The readiness stroke state owns the placement math.
func penetration_reach() -> float:
	return _readiness.reach()


func _director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


## The debug read of the voice routing she has; the audio owner reports nothing before an act.
func voice_status_line() -> String:
	return _audio.voice_status_line(_id)


## The anatomy service's visible shaft length, or zero when the part is not showing. The readiness
## stroke state turns zero into the nominal length, so the mouse feel is the same with it off.
func _player_shaft_length_m() -> float:
	var service: Variant = _anatomy_service()
	if service != null and service.has_method("player_shaft_length_m"):
		var length: Variant = service.call("player_shaft_length_m")
		if length is float and (length as float) > 0.001:
			return length as float
	return 0.0


## One real touch event. The readiness system applies the cooldown, heat and tolerance meter.
func _set_cue_override(text: String, seconds := -1.0) -> void:
	_readiness.set_cue_override(text, seconds)


func _talk_tick(_delta: float) -> void:
	var director := _director()
	_handover.player_line_tick(director)
	_readiness.talk_tick(director)


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
	_set_cue_override(text, _snapshot.cue_override_seconds)


func _form_set_face(smile: float) -> void:
	_act.set_face(smile, FACE.ACT_LIDS)


func _form_status(text: String) -> void:
	HUD.toast(text, 2.5)


## The readiness host boundary: scene values the pure scoring needs, and the presentation it
## triggers. The runtime keeps the state, the face beats, the tolerance meter and the cue line.
func _readiness_state() -> int:
	return state


func _readiness_close() -> void:
	_act.face_beat("close")


func _readiness_anatomy_react() -> void:
	_anatomy_bridge.react()


func _readiness_heat() -> bool:
	return cycle_phase() == CYCLE.HEAT


func _readiness_cue(mood_value: String, cue_value: String, is_override: bool) -> void:
	_act_facts.mood = mood_value
	_act_facts.cue = cue_value
	_act_facts.cue_override = is_override
	_dialogue_service().admit_cue(_act.clock_s())


## Free a delivered line and expire a queued one at its max age. See `dialogue/service.gd`.
func _utterance_tick() -> void:
	_dialogue_service().tick()


## integration: one adult observer may say a short line, using the modern witness perception.
func _bystander_tick(delta: float) -> void:
	_dialogue_service().bystander_tick(delta)


## A real consent stop. It ends the act without the normal afterglow/cuddle restore, commits a
## severe bad summary, and only Strict additionally bucks and requests space. The consent owner
## presents the warning, the space request and the stop line; the one exit stays here.
func _stop_with_her(reason: String) -> void:
	var stop: Dictionary = _consent.begin_stop(reason)
	if stop.is_empty():
		return
	var strict := bool(stop.get("strict", false))
	_act.commit_summary(false)
	# The stopped summary already says why. The basic event is the fallback when the summary was
	# skipped, so one partner stop is never two memories.
	if _summary_service.summary.is_empty() and is_instance_valid(WORLD.game):
		MEMORY.instance.note(MEMORY.NoteKind.STOPPED, _id, _act.event_id,
			MEMORY.StopReason.WITHDREW)
	if _pose_family() == "bed":
		REST.release_managed(pony)
	_dialogue_service().end_act(_act.event_id, true)
	_end_session(false)
	_exit.finalize(true)
	_consent.finish_stop(strict, not _summary_service.summary.is_empty())
	_log("stop withdrew tier=%s distress=%.1f reason=%s strict=%s" % [
		str(stop.get("tolerance", "normal")), float(stop.get("distress", 0.0)),
		reason, str(strict)])


## Idle-only history scan. `dialogue/service.gd` reads the scene and owns the decisions and the
## line queueing.
func _history_tick(delta: float) -> void:
	_idle.history_tick(delta)


## Debug actions run from the paused settings page; the request is consumed on the next frame.
func debug_force_tolerance(kind: String) -> bool:
	return _consent.force(kind)


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
		_act.ended_early = true
		_act.commit_summary(false)
		# The early summary already records this end. Keep the basic event only when the summary
		# was skipped, so the story never holds the same end twice.
		if _summary_service.summary.is_empty():
			MEMORY.instance.note(MEMORY.NoteKind.CANCELLED, _id, _act.event_id)
		# Cancel act lines before restoring, then queue the intentional early-stop reaction.
		_dialogue_service().end_act(_act.event_id, true)
		_restore_begin()
		# Half the time she says nothing at all. When she does speak, it is a moment, not a
		# review or a next-time list.
		if randf() >= 0.5:
			var act_id := _act.event_id
			var expires := _act.clock_s() + _cue_reaction_max_age_value()
			var valid := func() -> bool:
				if not is_instance_valid(pony) or _act.event_id != act_id:
					return false
				if _act.clock_s() <= expires:
					return true
				return MEMORY.instance.line_state(_end_early_key) == MEMORY.LineState.SPEAKING
			var key: String = _dialogue_service().reaction_line(MEMORY.Reaction.END_EARLY, act_id, ACT_SUMMARY.early_end_prompt(_summary_service.summary), valid)
			_end_early_key = key
			if not key.is_empty():
				var now := _act.clock_s()
				_dialogue_service().note_reaction(key, "", now + _cue_reaction_max_age_value())
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

## Estrus phase. The eligibility owner resolves the debug override, the feature flag and the
## world day; the validity guard keeps a body freed during teardown from reaching it.
func cycle_phase() -> String:
	_act.refresh_identity()
	if not is_instance_valid(pony):
		return CYCLE.NORMAL
	return ELIGIBILITY.cycle_phase_for(pony, _id)


## The session override currently in force, or "" when the automatic cycle owns the phase.
func cycle_override() -> String:
	_act.refresh_identity()
	return CYCLE.override_for(_id)


## Private heat/diestrus note for the normal dialogue prompt, outside and during acts. The
## eligibility owner keeps the gate check and the note.
func cycle_note() -> String:
	if not is_instance_valid(pony):
		return ""
	var service: Variant = _eligibility_service()
	return service.cycle_note(pony) if service != null else ""


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	return _act.prompt_note()


func _afterglow_caressing() -> bool:
	return _hand_controller().any_active()

func _enter_afterglow() -> void:
	_act.begin_afterglow()

func _afterglow_tick(delta: float) -> void:
	if state != State.AFTERGLOW:
		return
	# integration: keep the optional bed-body part tracking through afterglow.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.afterglow_tick(delta)
	if state != State.AFTERGLOW or _pose_family() != "standing":
		return
	_afterglow.close_tick(delta)

func close_hint() -> String:
	return _view.close_hint(_act, _pose_family())

func _restore_begin() -> void:
	if state == State.IDLE or state == State.RESTORE:
		return
	_act.record_peak_memory()
	_afterglow.cancel_close()
	_stop_auto()
	_dialogue_service().end_act(_act.event_id, true)
	_log("restore begin from state=%d pony=%s" % [state, str(pony.name) if is_instance_valid(pony) else "?"])
	_act.begin_restore()
	_handover.hint_tick()
	# integration: act-only anatomy hides as soon as the act starts restoring.
	_anatomy_bridge.apply_live()
	_act.clear_face()
	_act.end_act_face()
	_wings_controller().release()
	if is_instance_valid(_pose_session.pose()):
		_pose_session.pose().target_amount = 0.0
	_pose_service().set_tail_target(0.0)
	_audio.stop_breath()
	_camera_service().call("release_back")
	_standing_camera_controller().reset_facing()
	if is_instance_valid(HUD.instance):
		HUD.instance.hide_act()

## The one act exit. The order and every ownership check live in `act/exit.gd`; this node keeps
## the one entry the exit routes call.
func _end_session(rejoin_cuddle: bool) -> void:
	_exit.run(rejoin_cuddle)

## The bed/couch rest and cuddle rejoin. See `rest/service.gd` and `docs/rest.md`.
func _rest_service() -> RefCounted:
	_rest.bind(pony, _act.bed)
	return _rest


func _rest_restore_scene() -> void:
	_missionary_camera_controller().restore_scene()


func _finish_restore() -> void:
	if is_instance_valid(pony):
		_log("restore finished pony=%s" % str(pony.name))
	else:
		_log("restore finished with invalid pony")
	_end_session(true)
	_exit.finalize(true)

func force_stop() -> void:
	# Defensive: every stop path must leave the quick slots in their pre-act state.
	if state == State.IDLE:
		_end_session(false)
		return
	_restore_now()

func _restore_now() -> void:
	_dialogue_service().end_act(_act.event_id, true)
	_end_session(false)
	_exit.finalize(true)

## The afterglow's satisfaction decay writes here; the meter's range is readiness's.
func _write_satisfaction(value: float) -> void:
	satisfaction = clampf(value, 0.0, READINESS_MAX)


# --------------------------------------------------------------------------- act face

## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_act_face(face: String) -> bool:
	return _act.force_act_face(face)


## Debug view for the "Show act face" action.
func act_face_rows() -> Array[String]:
	return _act.act_face_rows()


# --------------------------------------------------------------------------- checks

## A forced stop from a scene verdict. The gate returned the reason; this applies the one stop.
func _stop(reason: String) -> void:
	_log("stop reason=%s state=%d pony=%s" % [reason, state,
		str(pony.name) if is_instance_valid(pony) else "?"])
	if state in [State.POSING_IN, State.ACTIVE, State.CLIMAX]:
		MEMORY.instance.note(MEMORY.NoteKind.STOPPED, _id, _act.event_id,
			MEMORY.stop_reason(reason))
	_restore_begin()

# --------------------------------------------------------------------------- camera

## Open the act's shot. The camera owns the leaves and returns whether the standing VR act needs
## the anatomy bridge started.
func shot_lean_forward() -> float:
	return _act_camera.shot_lean_forward()


func smack() -> void:
	_hand_controller().smack()


## Publish or clear the pose session's opaque Anon body handle on the anatomy bridge. The session
## owns the body; the bridge only reads it.
func _set_missionary_anon_handle(body: Variant) -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.set_missionary_anon(body)


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
	return _anatomy_bridge.diag_row(_act_camera.missionary_face_point(),
		_act_camera.missionary_vulva_point())


func apply_camera_motion() -> void:
	_act.apply_camera_motion()


## Shared desktop hand driver for the caress and the standing body wrapper.
func _desktop_pose_driver() -> Node:
	return _standing_anon_controller().driver()


func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_thrust(hip, facing)


func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	_standing_anon_controller().apply_anon_lean(hip, facing)


## The kiss foreleg overrides are global AffectionPose settings. Restore them if the world
## closes or the mod is switched off mid-kiss.
func _exit_tree() -> void:
	if _swapping_parent:
		return
	PONIES.clear_body_swap(self)
	_kiss_controller().restore_forelegs()
	_start.release_stool()
	_act_host.end_tail_tuck()
	_afterglow.clear_post_act(pony if is_instance_valid(pony) else null)
	# integration: never leave the anatomy nodes or the per-act controller behind.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()
	_anatomy_bridge.detach()
	_face.shutdown()
