extends RefCounted
## The per-pony composition root. One `Bundle` per runtime node, built once by `runtime.gd:_init()`:
## it constructs every system, host, collaborator set and act module, and binds every callable, in
## the order the runtime used to. It contains no behaviour: no gate, input, start, exit, tick or view
## wrapper and no forwarder. Construction and the pony rebind are all it does.
##
## See `docs/runtime.md`.

const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const REST_REJOIN := preload("res://mods/unfplap/rest/service.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/service.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/camera/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_CHANGE_ACT_HOST := preload("res://mods/unfplap/body_change/act_host.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const ACT_HOST := preload("res://mods/unfplap/anatomy/act_host.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const AUDIO_ACT := preload("res://mods/unfplap/audio/act.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const ACT_IDLE := preload("res://mods/unfplap/act/idle.gd")
const ACT_CONSENT := preload("res://mods/unfplap/act/consent.gd")
const ACT_IMPACT := preload("res://mods/unfplap/act/impact.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_INPUT := preload("res://mods/unfplap/act/input.gd")
const ACT_SWAP := preload("res://mods/unfplap/act/swap.gd")
const ACT_PHASES := preload("res://mods/unfplap/act/phases.gd")
const ACT_TICK := preload("res://mods/unfplap/act/tick.gd")
const ACT_START := preload("res://mods/unfplap/act/start.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
const ACT_GATE := preload("res://mods/unfplap/act/gate.gd")


## The constructed per-pony objects. Fields only, plus the one pony rebind the runtime's setter and
## `_ready()` call: the components are bound by construction, not by a second pass.
class Bundle extends RefCounted:
	## The runtime node the callable bindings and the node operations point at.
	var node: Node = null
	## The presented body, kept in step by `bind_pony()`.
	var pony: Node = null
	## The act modules' node operations.
	var host: ACT_NODE = null
	## The typed collaborators the view, idle and act modules read.
	var context: ACT_CONTEXT = null
	## The act's state, timers, clock and value owner.
	var act: ACT_SESSION = null
	## The per-pony scene gate.
	var gate: SCENE_GATE = null
	var pose: POSE_SESSION = null
	var camera: ACT_CAMERA = null
	var readiness: READINESS = null
	var audio: AUDIO_ACT = null
	var afterglow: AFTERGLOW = null
	var face: FACE = null
	var reactions: REACTIONS = null
	var dialogue: ACT_DIALOGUE = null
	var anatomy_bridge: RefCounted = null
	var anatomy_host: ACT_HOST = null
	var handover: BODY_CHANGE_ACT = null
	var handover_host: BODY_CHANGE_ACT_HOST = null
	var summary: SUMMARY = null
	var wings: WING = null
	var hands: HANDS = null
	var kiss: KISS = null
	var integrations: INTEGRATIONS = null
	var missionary_camera: MISSIONARY_CAMERA = null
	var standing_camera: STANDING_CAMERA = null
	var standing_anon: STANDING_ANON = null
	var presentation: STANDING_PRESENTATION = null
	var hold: SCENE_HOLD = null
	var rest: REST_REJOIN = null
	var placement: PLACEMENT = null
	var placement_facts: PLACEMENT.Facts = null
	var facts: ACT_FACTS = null
	var perf_probe: PERF = null
	var view: ACT_VIEW = null
	var idle: ACT_IDLE = null
	var consent: ACT_CONSENT = null
	var impact: ACT_IMPACT = null
	var exit: ACT_EXIT = null
	var start: ACT_START = null
	var agreement: ACT_AGREEMENT = null
	var act_gate: ACT_GATE = null
	var input: ACT_INPUT = null
	var swap: ACT_SWAP = null
	var phases: ACT_PHASES = null
	var tick: ACT_TICK = null

	## Assign the presented body: the pose session's host and the act host's pony follow it. The
	## runtime's setter and `_ready()` are the only callers; nothing is rebound per frame.
	func bind_pony(value: Node) -> void:
		pony = value
		pose.bind(node, value if is_instance_valid(value) else null)
		if act != null:
			pose.id = act.pony_id
		if host != null:
			host.pony = value


## Build the bundle once. `pony` is null at `_init()` because the registry assigns the body after
## the node is built; `bind_pony()` carries it then.
static func build(pony: Node, node: Node) -> Bundle:
	var b := Bundle.new()
	b.node = node
	b.pony = pony if is_instance_valid(pony) else null
	# The runtime's former field initializers, in their order. The four act modules exist before
	# the frame binds them because the anatomy host is built against the early instances.
	b.input = ACT_INPUT.new()
	b.swap = ACT_SWAP.new()
	b.tick = ACT_TICK.new()
	b.phases = ACT_PHASES.new()
	b.pose = POSE_SESSION.new()
	b.gate = SCENE_GATE.new()
	b.rest = REST_REJOIN.new()
	b.camera = ACT_CAMERA.new()
	b.readiness = READINESS.new()
	b.summary = SUMMARY.new()
	b.face = FACE.new()
	b.reactions = REACTIONS.new()
	b.facts = ACT_FACTS.new()
	b.dialogue = ACT_DIALOGUE.new(b.facts)
	b.afterglow = AFTERGLOW.new()
	b.hold = SCENE_HOLD.new()
	# The runtime built this host while the act session was still null and kept it for the bridge's
	# lifetime, so the act-bound callbacks stay unbound; `bind_pony()` carries the body instead.
	b.anatomy_host = _anatomy_host(node, b)
	b.anatomy_bridge = ANATOMY.new_act(b.anatomy_host)
	_build_systems(node, b)
	_bind_act_frame(node, b)
	_bind_pose_hosts(node, b)
	b.anatomy_bridge.bind(b.anatomy_host)
	_bind_facts(node, b)
	b.perf_probe = PERF.build(_perf_host(node, b))
	b.tick.probe = b.perf_probe
	b.gate.bind(b.pony, b.pose)
	b.gate.configure(b.act.state, b.act.pony_id, b.act.features)
	return b


## The components `_build_systems()` used to construct, in its order.
static func _build_systems(node: Node, b: Bundle) -> void:
	b.handover_host = _handover_host(node, b)
	b.handover = BODY_CHANGE_ACT.new(b.handover_host)
	b.placement = PLACEMENT.new()
	b.placement_facts = PLACEMENT.Facts.new()
	b.wings = WING.new(b.facts)
	b.wings.log = Callable(node, "_log")
	b.hands = HANDS.new(b.facts)
	b.kiss = KISS.new(b.facts)
	b.integrations = INTEGRATIONS.new(b.facts)
	b.missionary_camera = MISSIONARY_CAMERA.new(b.facts)
	b.standing_camera = STANDING_CAMERA.new(b.facts)
	b.standing_anon = STANDING_ANON.new(b.facts)
	b.presentation = STANDING_PRESENTATION.new(b.facts)
	b.camera.bind(b.facts, b.hands, b.kiss, b.standing_camera, b.missionary_camera)
	b.camera.standing_anon = b.standing_anon
	b.audio = AUDIO_ACT.new()
	b.audio.bind(node)
	b.audio.log = Callable(node, "_log")


## The act's own host, context, session and modules, in `_bind_act_frame()`'s order.
static func _bind_act_frame(node: Node, b: Bundle) -> void:
	b.host = ACT_NODE.new()
	b.host.bind(node)
	b.host.log_sink = Callable(node, "_log")
	b.host.perf_sink = Callable(node, "perf_note")
	b.context = _build_act_context(b)
	b.act = ACT_SESSION.new()
	b.act.bind(b.host, b.context)
	b.consent = ACT_CONSENT.new()
	b.consent.bind(b.host, b.context, b.act)
	b.context.consent = b.consent
	b.impact = ACT_IMPACT.new()
	b.impact.bind(b.host, b.context, b.act)
	b.context.impact = b.impact
	b.context.audio = b.audio
	b.view = ACT_VIEW.new()
	b.view.bind(b.host, b.context)
	b.idle = ACT_IDLE.new()
	b.idle.bind(b.host, b.context, b.act)
	b.exit = ACT_EXIT.new()
	b.exit.bind(b.host, b.context, b.act)
	b.input = ACT_INPUT.new()
	b.input.bind(b.host, b.context, b.act)
	b.input.exit = b.exit
	b.consent.exit = b.exit
	b.act.input = b.input
	b.act.exit = b.exit
	b.swap.bind(b.host, b.context, b.act)
	b.act.swap = b.swap
	b.swap.exit = b.exit
	b.phases.bind(b.host, b.context, b.act)
	b.tick.bind(b.host, b.context, b.act, b.idle)
	b.tick.swap = b.swap
	b.tick.exit = b.exit
	b.tick.phases = b.phases
	b.act.ticker = b.tick
	b.start = ACT_START.new()
	b.start.bind(b.host, b.context, b.act, b.exit, b.view)
	b.agreement = ACT_AGREEMENT.new()
	b.agreement.bind(b.host, b.context, b.act, b.start)
	b.act_gate = ACT_GATE.new()
	b.act_gate.bind(b.gate, b.agreement, b.act, b.reactions)
	b.act.start = b.start
	b.act.view = b.view
	b.exit.start = b.start


## The typed collaborator set the view and idle modules read.
static func _build_act_context(b: Bundle) -> ACT_CONTEXT:
	var context := ACT_CONTEXT.new()
	context.pose = b.pose
	context.camera = b.camera
	context.readiness = b.readiness
	context.afterglow = b.afterglow
	context.face = b.face
	context.reactions = b.reactions
	context.dialogue = b.dialogue
	context.anatomy = b.anatomy_bridge
	context.handover = b.handover
	context.gate = b.gate
	context.facts = b.facts
	context.kiss = b.kiss
	context.summary = b.summary
	context.presentation = b.presentation
	context.standing_anon = b.standing_anon
	context.standing_camera = b.standing_camera
	context.wings = b.wings
	context.hands = b.hands
	context.integrations = b.integrations
	context.hold = b.hold
	context.rest = b.rest
	context.placement = b.placement
	context.anatomy_host = b.anatomy_host
	context.missionary_camera = b.missionary_camera
	return context


## The pose session's host callbacks. Built once here; the body itself is rebound by `bind_pony()`.
static func _bind_pose_hosts(node: Node, b: Bundle) -> void:
	b.pose.bind(node, b.pony)
	b.pose.id = b.act.pony_id
	b.pose.hide_avatar = Callable(b.missionary_camera, "hide_avatar")
	b.pose.set_act_body = Callable(node, "_set_missionary_anon_handle")
	b.pose.eye_camera = Callable(b.missionary_camera, "tick")
	b.pose.perf = Callable(node, "perf_note")
	b.pose.facts = b.facts
	b.pose.mouth_point = Callable(node, "_oral_mouth_point")
	b.pose.opening_point = Callable(node, "_oral_opening_point")
	b.pose.face_point = Callable(node, "_anatomy_face_point")
	b.pose.oral_kiss = Callable(b.audio, "oral_kiss")
	b.pose.oral_speech_stop = Callable(b.phases, "oral_speech_stop")
	b.pose.oral_viseme = Callable(node, "_oral_viseme")
	b.pose.oral_status = Callable(node, "_anatomy_status")
	b.pose.log = Callable(node, "_log")


## The act view, readiness, afterglow, face, scene gate, rest, scene hold and controller bindings.
static func _bind_facts(node: Node, b: Bundle) -> void:
	b.facts.perf_note = Callable(node, "perf_note")
	b.facts.log = Callable(node, "_log")
	b.facts.body_coat_smack = Callable(node, "body_coat_jiggle_target")
	b.facts.kiss = Callable(node, "_kiss_controller")
	b.facts.neck_point = Callable(b.camera, "neck_midpoint")
	b.facts.set_look = Callable(b.phases, "set_look")
	b.facts.set_forced_glance = Callable(b.phases, "set_forced_glance")
	b.facts.set_camera_basis_ready = Callable(b.phases, "set_camera_basis_ready")
	b.facts.director = Callable(node, "_director")
	b.facts.now = Callable(b.act, "clock_s")
	b.readiness.log = Callable(node, "_log")
	b.readiness.clock = Callable(b.act, "clock_s")
	b.readiness.state = Callable(node, "_readiness_state")
	b.readiness.on_climax = Callable(b.act, "climax")
	b.readiness.on_close = Callable(node, "_readiness_close")
	b.readiness.on_face = Callable(b.act, "face_beat")
	b.readiness.on_anatomy_react = Callable(node, "_readiness_anatomy_react")
	b.readiness.heat_cycle = Callable(node, "_readiness_heat")
	b.readiness.on_cue = Callable(b.phases, "cue")
	b.readiness.shaft_length = Callable(b.phases, "shaft_length_m")
	b.readiness.pose_family = Callable(node, "_pose_family")
	b.summary.log = Callable(node, "_log")
	b.afterglow.log = Callable(node, "_log")
	b.afterglow.caress_active = Callable(node, "_afterglow_caressing")
	b.afterglow.bind_act(b.face, b.reactions, b.readiness)
	b.afterglow.bind_host(node)
	b.afterglow.write_satisfaction = Callable(node, "_write_satisfaction")
	b.face.log = Callable(node, "_log")
	b.face.clock = Callable(b.act, "clock_s")
	b.reactions.log = Callable(node, "_log")
	b.gate.stool_need = Callable(b.act_gate, "stool_needed_count")
	b.gate.stool_count = Callable(b.act_gate, "stool_case_count")
	b.gate.presentation_active = Callable(b.act, "presentation_active")
	b.gate.hold_compatible = Callable(node, "_scene_hold_compatible")
	b.gate.debug_context = Callable(node, "_debug_context")
	b.rest.context = Callable(node, "_rest_context")
	b.rest.restore_scene = Callable(node, "_rest_restore_scene")
	b.rest.log = Callable(node, "_log")
	b.hold.bind({
		"pony": Callable(node, "_pony"),
		"state": Callable(node, "_state"),
		"pose_family": Callable(node, "_pose_family"),
	})
	b.facts.play_mouth_kiss = Callable(b.audio, "play_mouth_kiss")
	b.facts.act_actions_allowed = Callable(b.camera, "at_actions_allowed")
	b.facts.auto_panel_open = Callable(b.input, "auto_panel_open")
	b.facts.standing_camera = Callable(node, "_standing_camera_controller")
	b.facts.missionary_anon = Callable(node, "missionary_anon_body")
	b.facts.anatomy_normal = Callable(node, "anatomy_normal")
	b.facts.anatomy_opening = Callable(node, "anatomy_opening")
	b.facts.authored_pose_asset = Callable(b.pose, "authored_asset")
	b.facts.missionary_face_point = Callable(b.camera, "missionary_face_point")
	b.facts.gaze_point = Callable(node, "_missionary_gaze_point")
	b.facts.free_look_rotation = Callable(b.camera, "free_look_rotation")
	b.facts.desktop_pose_driver = Callable(node, "_desktop_pose_driver")
	b.facts.cuddle_active = Callable(b.act_gate, "cuddle_active")
	b.facts.free_of_affection = Callable(b.act_gate, "free_of_affection")
	b.facts.pause_face_turn = Callable(b.hold, "pause_face_turn")
	b.facts.restore_face_turn = Callable(b.hold, "restore_face_turn")
	b.facts.hold_excitement = Callable(b.audio, "hold_excitement")
	b.facts.release_excitement = Callable(b.audio, "release_excitement")
	b.facts.mod_enabled = Callable(node, "_mod_enabled")
	b.facts.on_touch = Callable(b.readiness, "touch")
	b.facts.on_smack = Callable(node, "_on_smack_impact")
	b.facts.pose_host = Callable(node, "_runtime")


## The typed host for the per-act anatomy bridge.
static func _anatomy_host(node: Node, b: Bundle) -> ACT_HOST:
	var host := ACT_HOST.new()
	host.pony_cb = Callable(node, "_pony")
	host.runtime_cb = Callable(node, "_runtime")
	host.reactions_cb = Callable(node, "_reactions_service")
	host.anatomy_service_cb = Callable(node, "_anatomy_service")
	host.eligibility_service_cb = Callable(node, "_eligibility_service")
	host.state_cb = Callable(node, "_state")
	host.pose_view_cb = Callable(node, "_pose_view_value")
	host.depth_cb = Callable(node, "_depth")
	host.penetration_m_cb = Callable(node, "_penetration_m")
	host.penetration_reach_cb = Callable(node, "penetration_reach")
	host.climaxes_cb = Callable(node, "_climaxes")
	host.size_scale_cb = Callable(b.camera, "size_scale")
	host.auto_pace_cb = Callable(node, "_auto_pace")
	host.fluid_ground_y_cb = _callback(b.phases, "fluid_ground_y")
	host.cycle_phase_cb = Callable(node, "cycle_phase")
	host.bed_frame_cb = Callable(node, "_bed_frame")
	host.log_cb = Callable(node, "_log")
	host.perf_note_cb = Callable(node, "perf_note")
	host.perf_enabled_cb = Callable(node, "_perf_enabled")
	host.body_coat_smack_cb = Callable(node, "body_coat_jiggle_target")
	host.status_cb = Callable(node, "_anatomy_status")
	host.command_cb = _callback(b.input, "command")
	host.missionary_camera_cb = Callable(node, "_missionary_camera_controller")
	host.kiss_controller_cb = Callable(node, "_kiss_controller")
	host.pose_cb = Callable(node, "_pose_service")
	host.thrust_move_cb = _callback(b.impact, "move")
	host.now_s_cb = _callback(b.act, "clock_s")
	host.set_penetration_m_cb = _callback(b.impact, "set_depth")
	host.align_cb = Callable(node, "apply_anon_align")
	host.touch_cb = Callable(b.readiness, "touch")
	host.vr_scene_cb = Callable(node, "_vr_scene")
	return host


## The typed host for the act's body-change handover. The runtime built it before the act session
## existed, so the clock callback stays unbound and `host.now()` keeps its 0.0 fallback.
static func _handover_host(node: Node, b: Bundle) -> BODY_CHANGE_ACT_HOST:
	var host := BODY_CHANGE_ACT_HOST.new()
	host.runtime_cb = Callable(node, "_runtime")
	host.pony_cb = Callable(node, "_pony")
	host.id_cb = Callable(node, "_act_id")
	host.act_live_cb = Callable(node, "_act_live")
	host.restoring_cb = Callable(node, "_act_restoring")
	host.state_cb = Callable(node, "_state")
	host.event_id_cb = Callable(node, "_event_id_value")
	host.depth_cb = Callable(node, "_depth")
	host.climaxes_cb = Callable(node, "_climaxes")
	host.max_climaxes_cb = Callable(node, "_max_climaxes_value")
	host.satisfaction_cb = Callable(node, "_satisfaction_value")
	host.cue_cb = Callable(node, "_cue_value")
	host.pose_view_cb = Callable(node, "_pose_view_value")
	host.start_pose_cb = Callable(node, "_start_pose_id")
	host.shape_name_cb = Callable(node, "_shape_name")
	host.reaction_line_cb = Callable(node, "_form_reaction_line")
	host.note_reaction_cb = Callable(node, "_form_note_reaction")
	host.add_heat_cb = Callable(node, "_form_add_heat")
	host.cue_override_cb = Callable(node, "_form_cue_override")
	host.set_face_cb = Callable(node, "_form_set_face")
	host.status_cb = Callable(node, "_form_status")
	host.now_cb = _callback(b.act, "clock_s")
	host.reaction_max_age_cb = Callable(node, "_cue_reaction_max_age_value")
	host.attach_to_world_cb = Callable(b.swap, "attach_to_world")
	host.release_carry_cb = Callable(b.swap, "release_carry")
	host.release_contacts_cb = Callable(b.swap, "release_contacts")
	host.remember_auto_cb = Callable(b.swap, "remember_auto")
	host.release_act_body_cb = Callable(b.swap, "release_act_body")
	host.release_scene_cb = Callable(b.swap, "release_scene")
	host.free_pose_cb = Callable(b.swap, "release_pose")
	host.restore_camera_cb = Callable(b.swap, "restore_camera")
	host.stop_breath_cb = Callable(b.swap, "stop_breath")
	host.resume_body_cb = Callable(b.swap, "resume_body")
	host.prepare_anatomy_act_cb = Callable(b.swap, "prepare_anatomy_act")
	host.apply_resume_settings_cb = Callable(b.swap, "apply_resume_settings")
	host.rebind_reactions_cb = Callable(b.swap, "rebind_reactions")
	host.set_act_pose_config_cb = Callable(b.swap, "set_act_pose_config")
	host.rebuild_act_pose_cb = Callable(b.swap, "rebuild_act_pose")
	host.sync_start_config_cb = Callable(b.swap, "sync_start_config")
	host.reset_visual_for_form_cb = Callable(b.swap, "reset_visual_for_form")
	host.reset_player_pelvis_cb = Callable(b.swap, "reset_pelvis")
	host.reset_lean_cb = Callable(b.swap, "reset_lean")
	host.prepare_start_camera_cb = Callable(b.swap, "prepare_start_camera")
	host.open_camera_cb = Callable(b.swap, "open_camera")
	host.hide_avatar_cb = Callable(b.swap, "hide_avatar")
	host.reset_wings_cb = Callable(b.swap, "reset_wings")
	host.claim_nav_cb = Callable(b.swap, "claim_nav")
	host.pause_face_turn_cb = Callable(b.swap, "pause_face_turn")
	host.reset_face_cb = Callable(b.swap, "reset_face")
	host.apply_voice_policy_cb = Callable(b.swap, "apply_voice_policy")
	host.apply_pose_change_cb = Callable(b.swap, "apply_pose_change")
	host.apply_anatomy_live_cb = Callable(b.swap, "apply_anatomy_live")
	host.begin_integrations_cb = Callable(b.swap, "begin_integrations")
	host.sync_hud_cb = Callable(b.swap, "sync_hud")
	host.resume_auto_cb = Callable(b.swap, "resume_auto")
	host.rebind_body_cb = Callable(b.swap, "rebind_body")
	host.prepare_standing_camera_cb = Callable(b.swap, "prepare_standing_camera")
	host.new_body_adult_cb = Callable(b.swap, "new_body_is_adult")
	host.log_cb = Callable(node, "_log")
	return host


## The debug perf probe's host: the live reads one summary window prints.
static func _perf_host(node: Node, b: Bundle) -> PERF.Host:
	var host := PERF.Host.new()
	host.enabled_cb = Callable(node, "_perf_enabled")
	host.log_cb = Callable(node, "_log")
	host.show_cb = Callable(LOG, "perf_block")
	host.id_cb = Callable(node, "_act_id")
	host.pose_cb = Callable(node, "_perf_pose_id")
	host.state_cb = Callable(node, "_state")
	host.lean_forward_cb = Callable(b.camera, "shot_lean_forward")
	host.lean_side_cb = Callable(node, "_perf_lean_side")
	host.hand_left_cb = Callable(b.hands, "active").bind("L")
	host.hand_right_cb = Callable(b.hands, "active").bind("R")
	host.near_mesh_cb = Callable(node, "_perf_near_mesh")
	host.tier_cb = Callable(node, "_perf_tier")
	host.wing_hold_cb = Callable(node, "_perf_wing_hold")
	host.winged_cb = Callable(node, "_perf_winged")
	host.idle_note_cb = Callable(LOG, "note")
	return host


## A construction-time callback, or an unbound one for an object the frame has not built yet.
static func _callback(target: Variant, method: String) -> Callable:
	return Callable(target, method) if target != null else Callable()
