extends RefCounted
## The per-pony composition root. One `Bundle` per runtime node: it constructs every system, host
## and act module and binds every callable to its owner. It contains no behaviour.
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
const AUDIO_ACT := preload("res://mods/unfplap/audio/act.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FRAME := preload("res://mods/unfplap/act/frame.gd")
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
	## The act's player frame: placement, stance and restore.
	var frame: ACT_FRAME = null
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
	# The early modules, in construction order. They exist before the act frame binds them because
	# the anatomy bridge and the handover are built against these instances.
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
	# The anatomy bridge and its host exist before the act context can hold them; both hosts are
	# filled after the act frame exists, because their callbacks read the session and the modules.
	b.anatomy_host = ACT_HOST.new()
	b.anatomy_bridge = ANATOMY.new_act(b.anatomy_host)
	_build_systems(node, b)
	_bind_act_frame(node, b)
	_bind_anatomy_host(b)
	_bind_handover_host(b)
	_bind_pose_hosts(node, b)
	b.anatomy_bridge.bind(b.anatomy_host)
	_bind_facts(node, b)
	b.gate.bind(b.pony, b.pose)
	b.gate.configure(b.act.state, b.act.pony_id, b.act.features)
	return b


## The per-act systems, in construction order.
static func _build_systems(node: Node, b: Bundle) -> void:
	b.handover_host = BODY_CHANGE_ACT_HOST.new()
	b.handover = BODY_CHANGE_ACT.new(b.handover_host)
	b.placement = PLACEMENT.new()
	b.placement_facts = PLACEMENT.Facts.new()
	b.wings = WING.new(b.facts)
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


## The act's own host, context, session and modules, in binding order.
static func _bind_act_frame(node: Node, b: Bundle) -> void:
	b.host = ACT_NODE.new()
	b.host.bind(node)
	b.context = _build_act_context(b)
	b.act = ACT_SESSION.new()
	b.act.bind(b.host, b.context)
	b.frame = ACT_FRAME.new()
	b.frame.bind(b.host, b.context, b.act)
	b.context.frame = b.frame
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
	b.pose.set_act_body = Callable(b.anatomy_bridge, "set_missionary_anon")
	b.pose.eye_camera = Callable(b.missionary_camera, "tick")
	b.pose.facts = b.facts
	b.pose.mouth_point = Callable(b.anatomy_bridge, "mouth_point")
	b.pose.opening_point = Callable(b.anatomy_bridge, "opening")
	b.pose.face_point = Callable(b.anatomy_bridge, "face_point")
	b.pose.oral_kiss = Callable(b.audio, "oral_kiss")
	b.pose.oral_speech_stop = Callable(b.phases, "oral_speech_stop")
	b.pose.oral_viseme = Callable(b.anatomy_bridge, "set_oral_viseme")
	b.pose.oral_status = Callable(HUD, "anatomy_status")


## The act view, readiness, afterglow, face, scene gate, rest, scene hold and controller bindings.
static func _bind_facts(node: Node, b: Bundle) -> void:
	b.facts.body_coat_smack = Callable(b.reactions, "body_coat_target")
	b.facts.kiss = Callable(b.act, "kiss_service")
	b.facts.neck_point = Callable(b.camera, "neck_midpoint")
	b.facts.set_look = Callable(b.phases, "set_look")
	b.facts.set_forced_glance = Callable(b.phases, "set_forced_glance")
	b.facts.set_camera_basis_ready = Callable(b.phases, "set_camera_basis_ready")
	b.facts.director = Callable(b.host, "director")
	b.facts.now = Callable(b.act, "clock_s")
	b.readiness.clock = Callable(b.act, "clock_s")
	b.readiness.state = Callable(b.act, "state_value")
	b.readiness.on_climax = Callable(b.act, "climax")
	b.readiness.on_close = Callable(b.act, "face_beat").bind("close")
	b.readiness.on_face = Callable(b.act, "face_beat")
	b.readiness.on_anatomy_react = Callable(b.anatomy_bridge, "react")
	b.readiness.heat_cycle = Callable(b.act, "in_heat")
	b.readiness.on_cue = Callable(b.phases, "cue")
	b.readiness.shaft_length = Callable(b.phases, "shaft_length_m")
	b.readiness.pose_family = Callable(b.act, "pose_family")
	b.afterglow.caress_active = Callable(b.hands, "any_active")
	b.afterglow.bind_act(b.face, b.reactions, b.readiness)
	b.afterglow.bind_host(node)
	b.afterglow.write_satisfaction = Callable(b.readiness, "write_satisfaction")
	b.face.clock = Callable(b.act, "clock_s")
	b.gate.stool_need = Callable(b.act_gate, "stool_needed_count")
	b.gate.stool_count = Callable(b.act_gate, "stool_case_count")
	b.gate.presentation_active = Callable(b.act, "presentation_active")
	b.gate.hold_compatible = Callable(b.hold, "accepts_hold")
	b.gate.debug_context = Callable(b.act, "debug_context")
	b.rest.context = Callable(b.act, "rest_context")
	b.rest.restore_scene = Callable(b.missionary_camera, "restore_scene")
	b.hold.bind({
		"pony": Callable(b.host, "pony_value"),
		"state": Callable(b.act, "state_value"),
		"pose_family": Callable(b.act, "pose_family"),
	})
	b.facts.play_mouth_kiss = Callable(b.audio, "play_mouth_kiss")
	b.facts.act_actions_allowed = Callable(b.camera, "at_actions_allowed")
	b.facts.auto_panel_open = Callable(b.input, "auto_panel_open")
	b.facts.standing_camera = Callable(b.camera, "standing_controller")
	b.facts.missionary_anon = Callable(b.act, "missionary_anon_body")
	b.facts.anatomy_normal = Callable(b.act, "anatomy_normal")
	b.facts.anatomy_opening = Callable(b.act, "anatomy_opening")
	b.facts.authored_pose_asset = Callable(b.pose, "authored_asset")
	b.facts.missionary_face_point = Callable(b.camera, "missionary_face_point")
	b.facts.gaze_point = Callable(b.anatomy_bridge, "gaze_point")
	b.facts.free_look_rotation = Callable(b.camera, "free_look_rotation")
	b.facts.desktop_pose_driver = Callable(b.standing_anon, "driver")
	b.facts.cuddle_active = Callable(b.act_gate, "cuddle_active")
	b.facts.free_of_affection = Callable(b.act_gate, "free_of_affection")
	b.facts.pause_face_turn = Callable(b.hold, "pause_face_turn")
	b.facts.restore_face_turn = Callable(b.hold, "restore_face_turn")
	b.facts.hold_excitement = Callable(b.audio, "hold_excitement")
	b.facts.release_excitement = Callable(b.audio, "release_excitement")
	b.facts.mod_enabled = Callable(b.host, "mod_enabled")
	b.facts.on_touch = Callable(b.readiness, "touch")
	b.facts.on_smack = Callable(b.reactions, "smack")
	b.facts.pose_host = Callable(b.host, "runtime")


## The typed host for the per-act anatomy bridge; its callbacks name their owners, never the
## runtime node.
static func _bind_anatomy_host(b: Bundle) -> void:
	var host: ACT_HOST = b.anatomy_host
	host.pony_cb = Callable(b.host, "pony_value")
	host.runtime_cb = Callable(b.host, "runtime")
	host.reactions_cb = Callable(b.act, "reactions_service")
	host.anatomy_service_cb = Callable(PONIES, "anatomy_service")
	host.eligibility_service_cb = Callable(PONIES, "eligibility_service")
	host.state_cb = Callable(b.act, "state_value")
	host.pose_view_cb = Callable(b.act, "pose_view")
	host.depth_cb = Callable(b.readiness, "depth_value")
	host.penetration_m_cb = Callable(b.readiness, "penetration_m_value")
	host.penetration_reach_cb = Callable(b.readiness, "reach")
	host.climaxes_cb = Callable(b.readiness, "climax_count")
	host.size_scale_cb = Callable(b.camera, "size_scale")
	host.auto_pace_cb = Callable(b.readiness, "auto_pace")
	host.fluid_ground_y_cb = Callable(b.phases, "fluid_ground_y")
	host.cycle_phase_cb = Callable(b.act, "cycle_phase")
	host.bed_frame_cb = Callable(b.pose, "_bed_frame_value")
	host.body_coat_smack_cb = Callable(b.reactions, "body_coat_target")
	host.status_cb = Callable(HUD, "anatomy_status")
	host.command_cb = Callable(b.input, "command")
	host.missionary_camera_cb = Callable(b.camera, "missionary_controller")
	host.kiss_controller_cb = Callable(b.act, "kiss_service")
	host.pose_cb = Callable(b.pose, "self_handle")
	host.thrust_move_cb = Callable(b.impact, "move")
	host.now_s_cb = Callable(b.act, "clock_s")
	host.set_penetration_m_cb = Callable(b.impact, "set_depth")
	host.align_cb = Callable(b.act, "apply_anon_align")
	host.touch_cb = Callable(b.readiness, "touch")
	host.vr_scene_cb = Callable(b.host, "vr_scene")


## The typed host for the act's body-change handover, filled once the act frame exists.
static func _bind_handover_host(b: Bundle) -> void:
	var host: BODY_CHANGE_ACT_HOST = b.handover_host
	host.runtime_cb = Callable(b.host, "runtime")
	host.pony_cb = Callable(b.host, "pony_value")
	host.id_cb = Callable(b.act, "act_id")
	host.act_live_cb = Callable(b.act, "act_live")
	host.restoring_cb = Callable(b.act, "restoring")
	host.state_cb = Callable(b.act, "state_value")
	host.event_id_cb = Callable(b.act, "event_id_value")
	host.depth_cb = Callable(b.readiness, "depth_value")
	host.climaxes_cb = Callable(b.readiness, "climax_count")
	host.max_climaxes_cb = Callable(b.act, "climax_limit")
	host.satisfaction_cb = Callable(b.readiness, "satisfaction_value")
	host.cue_cb = Callable(b.readiness, "cue_value")
	host.pose_view_cb = Callable(b.act, "pose_view")
	host.start_pose_cb = Callable(b.act, "start_id")
	host.shape_name_cb = Callable(SETTINGS, "character_name")
	host.reaction_line_cb = Callable(b.dialogue, "reaction_line")
	host.note_reaction_cb = Callable(b.dialogue, "note_reaction")
	host.add_heat_cb = Callable(b.readiness, "add_heat")
	host.cue_override_cb = Callable(b.act, "form_cue_override")
	host.set_face_cb = Callable(b.act, "form_set_face")
	host.status_cb = Callable(b.act, "form_status")
	host.now_cb = Callable(b.act, "clock_s")
	host.reaction_max_age_cb = Callable(b.act, "cue_reaction_max_age")
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
