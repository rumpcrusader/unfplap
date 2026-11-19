extends Node
## One per pony. The per-pony host and composition root: lifetime, the one bind pass, the two frame
## forwards and the act's session, start, exit and view handles. The `act/` modules own the state,
## the schedule, the presentation, the input protocol, the swap seams, the ledgers and the view; the
## node owns no system's rules or mutable state and never edits game files.

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
const ACT_INPUT := preload("res://mods/unfplap/act/input.gd")
const ACT_SWAP := preload("res://mods/unfplap/act/swap.gd")
const ACT_TICK := preload("res://mods/unfplap/act/tick.gd")
const ACT_PHASES := preload("res://mods/unfplap/act/phases.gd")
const AUDIO_ACT := preload("res://mods/unfplap/audio/act.gd")
const ACT_IMPACT := preload("res://mods/unfplap/act/impact.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const ACT_IDLE := preload("res://mods/unfplap/act/idle.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_START := preload("res://mods/unfplap/act/start.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
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
const AGREEMENT_WAIT := ACT_AGREEMENT.AGREEMENT_WAIT
const AGREEMENT_STARTED := ACT_AGREEMENT.AGREEMENT_STARTED
const AGREEMENT_FAILED := ACT_AGREEMENT.AGREEMENT_FAILED

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
var _input: ACT_INPUT = ACT_INPUT.new()
var _swap: ACT_SWAP = ACT_SWAP.new()
var _tick: ACT_TICK = ACT_TICK.new()
var _phases: ACT_PHASES = ACT_PHASES.new()
var _impact: ACT_IMPACT = null
var _idle: ACT_IDLE = null
var _exit: ACT_EXIT = null
var _start: ACT_START = null
var _agreement: ACT_AGREEMENT = null

## Temporary read-only forward: the act session owns the live state; remove in R4.
var state: int:
	get:
		return _act.state if _act != null else State.IDLE
## The act's one session handle: the state, the timers and the input protocol. The entry and the
## input service read it; the Node keeps lifetime and node operations.
var act: ACT_SESSION:
	get:
		return _act


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
## Estrus is derived from the world day and her relationship, so it is resolved once per tick and
## the HUD card reads the cached flag.
## A body swap keeps the act alive but stops its ticks. The handover owns the typed change, the
## adopted body and the current pose id until the one resume; `act/exit.gd:run()` is still the only
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
	_input = ACT_INPUT.new()
	_input.bind(_act_host, _act_context, _act)
	_input.exit = _exit
	_consent.exit = _exit
	_act.input = _input
	_swap.bind(_act_host, _act_context, _act)
	_swap.exit = _exit
	_phases.bind(_act_host, _act_context, _act)
	_tick.bind(_act_host, _act_context, _act, _idle)
	_tick.swap = _swap
	_tick.exit = _exit
	_tick.phases = _phases
	_act.ticker = _tick
	_start = ACT_START.new()
	_start.bind(_act_host, _act_context, _act, _exit, _view)
	_agreement = ACT_AGREEMENT.new()
	_agreement.bind(_act_host, _act_context, _act, _start)
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
	_pose_session.oral_speech_stop = Callable(_phases, "oral_speech_stop")
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
	_act_facts.set_look = Callable(_phases, "set_look")
	_act_facts.set_forced_glance = Callable(_phases, "set_forced_glance")
	_act_facts.set_camera_basis_ready = Callable(_phases, "set_camera_basis_ready")
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
	_readiness.on_cue = Callable(_phases, "cue")
	_readiness.shaft_length = Callable(_phases, "shaft_length_m")
	_readiness.pose_family = Callable(self, "_pose_family")
	_summary_service.log = Callable(self, "_log")
	_afterglow.log = Callable(self, "_log")
	_afterglow.caress_active = Callable(self, "_afterglow_caressing")
	_afterglow.bind_act(_face, _reactions, _readiness)
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
	_act_facts.auto_panel_open = Callable(_input, "auto_panel_open")
	_act_facts.standing_camera = Callable(self, "_standing_camera_controller")
	_act_facts.missionary_anon = Callable(self, "missionary_anon_body")
	_act_facts.anatomy_normal = Callable(self, "anatomy_normal")
	_act_facts.anatomy_opening = Callable(self, "anatomy_opening")
	_act_facts.authored_pose_asset = Callable(_pose_session, "authored_asset")
	_act_facts.missionary_face_point = Callable(_act_camera, "missionary_face_point")
	_act_facts.gaze_point = Callable(self, "_missionary_gaze_point")
	_act_facts.free_look_rotation = Callable(_act_camera, "free_look_rotation")
	_act_facts.desktop_pose_driver = Callable(self, "_desktop_pose_driver")
	_act_facts.cuddle_active = Callable(self, "cuddle_active")
	_act_facts.free_of_affection = Callable(self, "free_of_affection")
	_act_facts.pause_face_turn = Callable(_hold, "pause_face_turn")
	_act_facts.restore_face_turn = Callable(_hold, "restore_face_turn")
	_act_facts.hold_excitement = Callable(_audio, "hold_excitement")
	_act_facts.release_excitement = Callable(_audio, "release_excitement")
	_act_facts.mod_enabled = Callable(self, "_mod_enabled")
	_act_facts.on_touch = Callable(_readiness, "touch")
	_act_facts.on_smack = Callable(self, "_on_smack_impact")
	_act_facts.pose_host = Callable(self, "_runtime")
	_perf_probe = PERF.build(_perf_host())
	_tick.probe = _perf_probe
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
	host.fluid_ground_y_cb = Callable(_phases, "fluid_ground_y")
	host.cycle_phase_cb = Callable(self, "cycle_phase")
	host.bed_frame_cb = Callable(self, "_bed_frame")
	host.log_cb = Callable(self, "_log")
	host.perf_note_cb = Callable(self, "perf_note")
	host.perf_enabled_cb = Callable(self, "_perf_enabled")
	host.body_coat_smack_cb = Callable(self, "body_coat_jiggle_target")
	host.status_cb = Callable(self, "_anatomy_status")
	host.command_cb = Callable(_input, "command")
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
	host.attach_to_world_cb = Callable(_swap, "attach_to_world")
	host.release_carry_cb = Callable(_swap, "release_carry")
	host.release_contacts_cb = Callable(_swap, "release_contacts")
	host.remember_auto_cb = Callable(_swap, "remember_auto")
	host.release_act_body_cb = Callable(_swap, "release_act_body")
	host.release_scene_cb = Callable(_swap, "release_scene")
	host.free_pose_cb = Callable(_swap, "release_pose")
	host.restore_camera_cb = Callable(_swap, "restore_camera")
	host.stop_breath_cb = Callable(_swap, "stop_breath")
	host.resume_body_cb = Callable(_swap, "resume_body")
	host.prepare_anatomy_act_cb = Callable(_swap, "prepare_anatomy_act")
	host.apply_resume_settings_cb = Callable(_swap, "apply_resume_settings")
	host.rebind_reactions_cb = Callable(_swap, "rebind_reactions")
	host.set_act_pose_config_cb = Callable(_swap, "set_act_pose_config")
	host.rebuild_act_pose_cb = Callable(_swap, "rebuild_act_pose")
	host.sync_start_config_cb = Callable(_swap, "sync_start_config")
	host.reset_visual_for_form_cb = Callable(_swap, "reset_visual_for_form")
	host.reset_player_pelvis_cb = Callable(_swap, "reset_pelvis")
	host.reset_lean_cb = Callable(_swap, "reset_lean")
	host.prepare_start_camera_cb = Callable(_swap, "prepare_start_camera")
	host.open_camera_cb = Callable(_swap, "open_camera")
	host.hide_avatar_cb = Callable(_swap, "hide_avatar")
	host.reset_wings_cb = Callable(_swap, "reset_wings")
	host.claim_nav_cb = Callable(_swap, "claim_nav")
	host.pause_face_turn_cb = Callable(_swap, "pause_face_turn")
	host.reset_face_cb = Callable(_swap, "reset_face")
	host.apply_voice_policy_cb = Callable(_swap, "apply_voice_policy")
	host.apply_pose_change_cb = Callable(_swap, "apply_pose_change")
	host.apply_anatomy_live_cb = Callable(_swap, "apply_anatomy_live")
	host.begin_integrations_cb = Callable(_swap, "begin_integrations")
	host.sync_hud_cb = Callable(_swap, "sync_hud")
	host.resume_auto_cb = Callable(_swap, "resume_auto")
	host.rebind_body_cb = Callable(_swap, "rebind_body")
	host.prepare_standing_camera_cb = Callable(_swap, "prepare_standing_camera")
	host.new_body_adult_cb = Callable(_swap, "new_body_is_adult")
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
	_act.idle_perf = _perf_enabled()
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
func refresh_view() -> void:
	_view.refresh(_act_facts, _act)


## Typed write-backs for the presentation controllers. The runtime keeps ownership of the forced
## glance; the captured look snapshot is the camera facade's.








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
	_act.idle_perf = _act.apply_live_settings()


## True while the automatic stroke owns the depth. X only switches it in ACTIVE/CLIMAX.
func auto_active() -> bool:
	return _readiness.auto_active()

func _process(delta: float) -> void:
	_act.render(delta)


## Suite seam: the one render frame.
func _process_tick(delta: float) -> void:
	_act.render(delta)


func _physics_process(delta: float) -> void:
	_act.tick(delta)


## Suite seam: the one physics frame.
func _physics_tick(delta: float) -> void:
	_act.tick(delta)



# --------------------------------------------------------------------------- gates

## The live vertical gap; NAN when the rule or the anatomy is unavailable.
func stool_gap_m() -> float:
	return float(_act.stool().call("gap_m")) if _act.stool() != null else NAN

func stool_needed_count() -> int:
	return int(_act.stool().call("needed_count")) if _act.stool() != null else 0

func stool_case_count() -> int:
	return int(_act.stool().call("case_count")) if _act.stool() != null else 0


func stool_state_text() -> String:
	return str(_act.stool().call("state_text")) if _act.stool() != null else "stool unavailable"

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
	return _scene_gate().cuddle_active()

func free_of_affection() -> bool:
	return _scene_gate().free_of_affection()

func find_bed_under() -> Node3D:
	return _scene_gate().find_bed_under()

## The Agreement start's answer. The start protocol owns the rows; the start ledger owns the body.
func start_agreement(handle: Variant, skip_presentation := false) -> int:
	return _agreement.start_agreement(handle, skip_presentation)


## True when the scene-only rows pass and, for a standing option, the presentation is settled.
func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	return _agreement.agreement_offer_ready(handle, skip_presentation)


## The hotkey's readiness: the scene-only rows plus Base clearance.
func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return _agreement.hotkey_ready(pose, act_source, bed_in)


## The footstool pair this call's gate used.
func hint_stool() -> Dictionary:
	return _agreement.hint_stool()


## The act key's immediate attempt, with no Agreement and no presentation wait.
func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	return _agreement.start_hotkey(pose, bed_in, act_source, skip_presentation)


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



func present_standing() -> bool:
	return bool(_standing_presentation_controller().present_standing())

func presentation_active() -> bool:
	return bool(_standing_presentation_controller().presentation_active())

func presentation_settled() -> bool:
	return bool(_standing_presentation_controller().presentation_settled())

func clear_presentation() -> void:
	_standing_presentation_controller().clear_presentation()

func body_swap_pending() -> bool:
	return _suspended


## The act-side form request. The handover decides whether a source can take the form; a later
## handover tick suspends the act, so the act's state, depth and climaxes are never handed to a
## second runtime.
func request_form_change(true_form: bool, shape_id := "", by_player := false) -> Dictionary:
	return _handover.request(true_form, shape_id, by_player)


## Suite seam: the handover's one action tick. The swap module owns the dispatch.
func _body_swap_tick(delta: float) -> void:
	_swap.tick(delta)


## Suite seam: the watcher's suspend action. The handover owns the release order.
func _suspend_for_body_swap(change: BODY_CHANGE) -> void:
	_swap.suspend(change)


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
	if not _swap.new_body_is_adult():
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


## The live standing gap, for the offer and the suites. The placement handle owns the value.
func _standing_gap(form: BODY_FORM.BodyForm = null) -> float:
	_swap.bind_placement(form)
	return _act_context.placement.gap_act()


## The parsed authored missionary pose, for the shot camera and the debug action.
func authored_pose_asset() -> Variant:
	return _pose_service().authored_asset()


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


## integration: anatomy action entry points for the input service. They are no-ops when the
## per-act controller is absent, so the keys behave exactly like master with the feature off.
func toggle_anatomy_hole() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.toggle_hole()


## The `oral` command: request the standing oral pose, or the return edge when it is already
## active. The per-mare consent string is passed only when the anatomy service says yes.
func toggle_anatomy_oral() -> void:
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.toggle_oral(_pose_service(), _act.display_name, _act.features)


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
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.status(text, seconds)


## Idempotent stop for every state exit. It never moves the depth.
func _stop_auto() -> void:
	_readiness.stop_auto()


## The mouse's vertical travel as hip travel; the input service hands over the relative motion.
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
func _set_cue_override(text: String, seconds := -1.0) -> void:
	_readiness.set_cue_override(text, seconds)


## Suite seam: one talk turn. The schedule owns the ordered call.
func _talk_tick(delta: float) -> void:
	_tick.talk(delta)


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
	_face.set_face(smile, FACE.ACT_LIDS)


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


func debug_force_tolerance(kind: String) -> bool:
	return _consent.force(kind)


## A smack has already started the native cheek jiggle. The reaction facade carries it into the
## same tail-base propagation as a thrust.
func _on_smack_impact(strength: float) -> void:
	_reactions.smack(strength)


## Public rump anchor for the standing offer's rear cone.
func rump_anchor() -> Vector3:
	return _reactions.rump_point()


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


func close_hint() -> String:
	return _view.close_hint(_act, _pose_family())

func _rest_service() -> RefCounted:
	_rest.bind(pony, _act.bed)
	return _rest


func _rest_restore_scene() -> void:
	_missionary_camera_controller().restore_scene()


## Every stop path must leave the quick slots in their pre-act state; the exit owns the route.
func force_stop() -> void:
	_exit.force_stop()

func _write_satisfaction(value: float) -> void:
	satisfaction = clampf(value, 0.0, READINESS_MAX)


# --------------------------------------------------------------------------- act face

## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_act_face(face: String) -> bool:
	_face.sync_settings(_act.feature("face_debug"))
	return _face.force_face(face)


## Debug view for the "Show act face" action.
func act_face_rows() -> Array[String]:
	return _act.act_face_rows()


# --------------------------------------------------------------------------- checks

## A forced stop from a scene verdict. The gate returned the reason; this applies the one stop.

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
	_act.release_stool()
	_act_host.end_tail_tuck()
	_afterglow.clear_post_act(pony if is_instance_valid(pony) else null)
	# integration: never leave the anatomy nodes or the per-act controller behind.
	_anatomy_bridge.bind(_anatomy_host())
	_anatomy_bridge.end()
	_anatomy_bridge.detach()
	_face.shutdown()
