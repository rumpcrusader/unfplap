extends RefCounted
## The per-pony composition root. One `Bundle` per runtime node: it constructs every system, host
## and act module and binds every callable to its owner. It contains no behaviour.
##
## See `docs/runtime.md`.

const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const REST_REJOIN := preload("res://mods/unfplap/rest/service.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/service.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_CHANGE_ACT_HOST := preload("res://mods/unfplap/body_change/act_host.gd")
const SWAP_PORT := preload("res://mods/unfplap/body_change/swap_port.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const AUDIO := preload("res://mods/unfplap/audio/api.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
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

## The scope assertion every Pony service carries; the runtime's children are the set.
const PONY_GROUP := "unfplap_pony_service"


## The constructed per-pony objects. Fields only, plus the one pony rebind the runtime's setter and
## `_ready()` call: the components are bound by construction, not by a second pass.
class Bundle extends RefCounted:
	## The runtime node the callable bindings and the node operations point at.
	var node: Node = null
	## The presented body, kept in step by `bind_pony()`.
	var pony: Node = null
	## The World services the per-pony modules receive; null outside the entry's factory.
	var world: HANDLES = null
	var hud: Node = null
	var memory: Node = null
	var stool: STOOL = null
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
	## The act audio handle, typed by convention: the API's inner class, so a suite may replace it.
	var audio: RefCounted = null
	var afterglow: AFTERGLOW = null
	var face: FACE = null
	var reactions: REACTIONS = null
	var dialogue: ACT_DIALOGUE = null
	var handover: BODY_CHANGE_ACT = null
	var handover_host: BODY_CHANGE_ACT_HOST = null
	var summary: SUMMARY = null
	var wings: WING = null
	var hands: HANDS = null
	var kiss: KISS = null
	var integrations: INTEGRATIONS = null
	var view: CAMERA_VIEW = null
	var standing_anon: STANDING_ANON = null
	var presentation: STANDING_PRESENTATION = null
	var hold: SCENE_HOLD = null
	var rest: REST_REJOIN = null
	var facts: ACT_FACTS = null
	var act_view: ACT_VIEW = null
	var idle: ACT_IDLE = null
	var consent: ACT_CONSENT = null
	var impact: ACT_IMPACT = null
	var exit: ACT_EXIT = null
	var start: ACT_START = null
	var agreement: ACT_AGREEMENT = null
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
		if is_instance_valid(reactions) and value is Node3D:
			reactions.bind_scene(value as Node3D, world.anatomy if world != null else null,
				(value as Node3D).get_node_or_null("FlankTouch"))


## The runtime's implementation of the handover's value contract; the swap seam is `b.swap`.
class BodyChangeHost extends "res://mods/unfplap/body_change/act_host.gd":
	var b: Bundle = null

	func _init(bundle: Bundle) -> void:
		b = bundle

	func swap() -> SWAP_PORT:
		return b.swap

	func runtime() -> Node:
		return b.host.runtime()

	func pony() -> Node3D:
		return b.host.pony_value() as Node3D

	func id() -> String:
		return b.act.act_id()

	func act_live() -> bool:
		return b.act.act_live()

	func restoring() -> bool:
		return b.act.restoring()

	func state() -> int:
		return b.act.state_value()

	func event_id() -> String:
		return b.act.event_id_value()

	func depth() -> float:
		return b.readiness.depth_value()

	func climaxes() -> int:
		return b.readiness.climax_count()

	func max_climaxes() -> int:
		return b.act.climax_limit()

	func satisfaction() -> float:
		return b.readiness.satisfaction_value()

	func cue() -> String:
		return b.readiness.cue_value()

	func pose_view() -> Variant:
		return b.act.pose_view()

	func start_pose_id() -> String:
		return b.act.start_id()

	func shape_name(shape_id: String) -> String:
		return SETTINGS.character_name(shape_id)

	func reaction_line(reaction: int, event_id: String, fallback: String,
			valid: ACT_DIALOGUE.Validity) -> String:
		return b.dialogue.reaction_line(reaction, event_id, fallback, valid)

	func validity(rule: Callable) -> ACT_DIALOGUE.Validity:
		return ACT_DIALOGUE.Validity.of(rule)

	func note_reaction(key: String, cue_text: String, until: float) -> void:
		b.dialogue.note_reaction(key, cue_text, until)

	func add_heat(amount: float) -> void:
		b.readiness.add_heat(amount)

	func set_cue_override(text: String) -> void:
		b.act.form_cue_override(text)

	func set_face(smile: float) -> void:
		b.act.form_set_face(smile)

	func status(text: String) -> void:
		b.act.form_status(text)

	func now() -> float:
		return b.act.clock_s()

	func reaction_max_age() -> float:
		return b.act.cue_reaction_max_age()


## Build the bundle once. `pony` is null at `_init()` because the registry assigns the body after
## the node is built; `bind_pony()` carries it then.
static func build(pony: Node, node: Node, world: HANDLES) -> Bundle:
	var b := Bundle.new()
	b.node = node
	b.pony = pony if is_instance_valid(pony) else null
	b.world = world
	b.hud = world.hud if world != null else null
	b.memory = world.memory if world != null else null
	b.stool = world.stool if world != null else null
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
	b.summary = SUMMARY.new(b.memory)
	b.face = FACE.new(b.memory)
	b.reactions = REACTIONS.new()
	b.facts = ACT_FACTS.new()
	b.dialogue = ACT_DIALOGUE.new(b.facts, b.memory)
	b.afterglow = AFTERGLOW.new(b.hud, b.memory)
	b.hold = SCENE_HOLD.new()
	b.audio = AUDIO.ActAudio.new(world.audio if world != null else null)
	_build_systems(b)
	_bind_act_frame(node, b)
	_bind_pose_hosts(node, b)
	_bind_facts(node, b)
	b.gate.bind(b.pony, b.pose, world.act_gate if world != null else null)
	b.gate.configure(b.act.state, b.act.pony_id,
		SCENE_GATE.Features.from_dict(b.act.features))
	_attach_services(node, b)
	return b


## The per-act systems, in construction order.
static func _build_systems(b: Bundle) -> void:
	b.handover_host = BodyChangeHost.new(b)
	b.handover = BODY_CHANGE_ACT.new(b.handover_host, b.memory)
	b.wings = WING.new(b.facts)
	b.hands = HANDS.new(b.facts)
	b.kiss = KISS.new(b.facts)
	b.integrations = INTEGRATIONS.new(b.facts)
	b.view = CAMERA_VIEW.new(b.facts)
	b.standing_anon = STANDING_ANON.new(b.facts)
	b.presentation = STANDING_PRESENTATION.new(b.facts)
	b.camera.bind(b.facts, b.hands, b.kiss, b.view)
	b.camera.standing_anon = b.standing_anon


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
	b.act_view = ACT_VIEW.new()
	b.act_view.bind(b.host, b.context)
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
	b.start.bind(b.host, b.context, b.act, b.exit, b.act_view)
	b.agreement = ACT_AGREEMENT.new()
	b.agreement.bind(b.host, b.context, b.act, b.start)
	b.act.start = b.start
	b.act.view = b.act_view
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
	context.handover = b.handover
	context.gate = b.gate
	context.facts = b.facts
	context.kiss = b.kiss
	context.summary = b.summary
	context.presentation = b.presentation
	context.standing_anon = b.standing_anon
	context.view = b.view
	context.wings = b.wings
	context.hands = b.hands
	context.integrations = b.integrations
	context.hold = b.hold
	context.rest = b.rest
	context.hud = b.hud
	context.memory = b.memory
	context.stool_service = b.stool
	context.world = b.world
	return context


## The pose session's host callbacks. Built once here; the body itself is rebound by `bind_pony()`.
static func _bind_pose_hosts(node: Node, b: Bundle) -> void:
	b.pose.bind(node, b.pony)
	b.pose.id = b.act.pony_id
	b.pose.eye_camera = Callable(b.view, "write_eye")
	b.pose.facts = b.facts
	b.pose.mouth_point = Callable(b.act, "anatomy_mouth_point")
	b.pose.opening_point = Callable(b.act, "anatomy_opening")
	b.pose.face_point = Callable(b.pose, "act_body_face_point")
	b.pose.oral_kiss = Callable(b.audio, "oral_kiss")
	b.pose.oral_speech_stop = Callable(b.phases, "oral_speech_stop")
	b.pose.oral_viseme = Callable(b.act, "anatomy_set_mouth_viseme")
	if is_instance_valid(b.hud):
		b.pose.oral_status = Callable(b.hud, "anatomy_status")


## The act view, readiness, afterglow, face, scene gate, rest, scene hold and controller bindings.
static func _bind_facts(node: Node, b: Bundle) -> void:
	b.facts.kiss = Callable(b.act, "kiss_service")
	b.facts.neck_point = Callable(b.camera, "neck_midpoint")
	b.facts.set_look = Callable(b.phases, "set_look")
	b.facts.set_forced_glance = Callable(b.phases, "set_forced_glance")
	b.facts.set_head_back = Callable(b.pose, "set_head_back")
	b.facts.set_camera_basis_ready = Callable(b.phases, "set_camera_basis_ready")
	b.facts.director = Callable(b.host, "director")
	b.facts.now = Callable(b.act, "clock_s")
	b.readiness.clock = Callable(b.act, "clock_s")
	b.readiness.state = Callable(b.act, "state_value")
	b.readiness.on_climax = Callable(b.act, "climax")
	b.readiness.on_close = Callable(b.act, "face_beat").bind("close")
	b.readiness.on_face = Callable(b.act, "face_beat")
	b.readiness.on_anatomy_react = Callable(b.act, "anatomy_react")
	b.readiness.heat_cycle = Callable(b.act, "in_heat")
	b.readiness.on_cue = Callable(b.phases, "cue")
	b.readiness.shaft_length = Callable(b.phases, "shaft_length_m")
	b.readiness.pose_family = Callable(b.act, "pose_family")
	b.afterglow.caress_active = Callable(b.hands, "any_active")
	b.afterglow.bind_act(b.face, b.reactions, b.readiness)
	b.afterglow.bind_host(node)
	b.afterglow.write_satisfaction = Callable(b.readiness, "write_satisfaction")
	b.face.clock = Callable(b.act, "clock_s")
	b.gate.stool_need = Callable(b.act, "stool_needed_count")
	b.gate.stool_count = Callable(b.act, "stool_case_count")
	b.gate.presentation_active = Callable(b.act, "presentation_active")
	b.gate.hold_compatible = Callable(b.hold, "accepts_hold")
	b.gate.debug_context = Callable(b.act, "debug_context")
	b.rest.context = Callable(b.act, "rest_context")
	b.rest.restore_scene = Callable(b.frame, "restore_scene")
	var hold_host := SCENE_HOLD.Host.new()
	hold_host.pony = Callable(b.host, "pony_value")
	hold_host.state = Callable(b.act, "state_value")
	hold_host.pose_family = Callable(b.act, "pose_family")
	b.hold.bind(hold_host)
	b.facts.play_mouth_kiss = Callable(b.audio, "mouth_kiss")
	b.facts.act_actions_allowed = Callable(b.camera, "at_actions_allowed")
	b.facts.auto_panel_open = Callable(b.input, "auto_panel_open")
	b.facts.view = Callable(b.camera, "view_controller")
	b.facts.missionary_anon = Callable(b.pose, "act_body_handle")
	b.facts.missionary_face_point = Callable(b.camera, "missionary_face_point")
	b.facts.authored_pose_asset = Callable(b.pose, "authored_asset")
	b.facts.gaze_point = Callable(b.camera, "gaze_point")
	b.facts.free_look_rotation = Callable(b.camera, "free_look_rotation")
	b.facts.desktop_pose_driver = Callable(b.standing_anon, "driver")
	b.facts.cuddle_active = Callable(b.gate, "cuddle_active")
	b.facts.free_of_affection = Callable(b.gate, "free_of_affection")
	b.facts.pause_face_turn = Callable(b.hold, "pause_face_turn")
	b.facts.restore_face_turn = Callable(b.hold, "restore_face_turn")
	b.facts.hold_excitement = Callable(b.hold, "hold_beat")
	b.facts.release_excitement = Callable(b.hold, "release_beat")
	b.facts.mod_enabled = Callable(b.host, "mod_enabled")
	b.facts.on_touch = Callable(b.readiness, "touch")
	b.facts.on_smack = Callable(b.reactions, "smack")
	b.facts.pose_host = Callable(b.host, "runtime")


## Name, parent and group one Pony service under the runtime. The builder is the only attach site.
static func _attach(node: Node, service: Node, service_name: String) -> void:
	service.name = service_name
	node.add_child(service)
	service.add_to_group(PONY_GROUP)


## Attach the 13 Pony services to the runtime in their fixed order, after every binding exists.
static func _attach_services(node: Node, b: Bundle) -> void:
	_attach(node, b.pose, "UnfplapPoses")
	_attach(node, b.camera, "UnfplapCamera")
	_attach(node, b.hands, "UnfplapHands")
	_attach(node, b.kiss, "UnfplapKiss")
	_attach(node, b.face, "UnfplapFace")
	_attach(node, b.afterglow, "UnfplapAfterglow")
	_attach(node, b.rest, "UnfplapRest")
	_attach(node, b.gate, "UnfplapSceneGate")
	_attach(node, b.hold, "UnfplapSceneHold")
	_attach(node, b.readiness, "UnfplapReadiness")
	_attach(node, b.reactions, "UnfplapReactions")
	_attach(node, b.summary, "UnfplapSummary")
	_attach(node, b.dialogue, "UnfplapDialogue")
