extends Node
## One per pony: **the host** and the Pony composition root. It exists, is parented under the body
## and reparented across a body swap, forwards both engine frames and releases what outlives an act.
## It constructs the systems and the typed record once, holding no act rule and no act value.

const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const REST_REJOIN := preload("res://mods/unfplap/rest/api.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/api.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/api.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/api.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const KISS := preload("res://mods/unfplap/act/kiss.gd")
const INTEGRATIONS_ACT := preload("res://mods/unfplap/integrations/act.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/act/standing_presentation.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const HOST_LIVE := preload("res://mods/unfplap/act/host_live.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const AUTO_THRUST := preload("res://mods/unfplap/auto_thrust/api.gd")
const SUMMARY := preload("res://mods/unfplap/summary/api.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/api.gd")
const FACE := preload("res://mods/unfplap/face/api.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/api.gd")
const AUDIO := preload("res://mods/unfplap/audio/api.gd")
const STOOL := preload("res://mods/unfplap/stool/api.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const HUD := preload("res://mods/unfplap/hud/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
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
const START_PORT := preload("res://mods/unfplap/shared/start_port.gd")
const PRESENTATION_PORT := preload("res://mods/unfplap/shared/presentation_port.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The scope assertion every Pony service carries; the runtime's children are the set.
const PONY_GROUP := "unfplap_pony_service"
## The roster's set of live runtimes; the one place a runtime is discovered rather than held.
const RUNTIME_GROUP := "unfplap_pony"

## One act's presentation began. The entry connects this to the world integrations, so the
## undress and the anatomy act handle fire from the runtime instead of the anatomy service.
signal act_started(pony: Node3D)

## The presented body. A new assignment rebinds the pose session and host; nothing rebinds per
## frame.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_bind_pony(value)
		_sync_frames()

var _pony_node: Node = null
## The World services this pony's act reads; a bare `new()` gets an empty record.
var _world: HANDLES = null
## The session behind the `act` property below.
var _act: ACT_SESSION = null
## The gate behind the `scene` property below.
var _gate: SCENE_GATE = null
## The agreement behind the `start` property below.
var _agreement: ACT_AGREEMENT = null
var _face: FACE = null
## The act's body-change handover: the swap record and the form offer.
var _handover: BODY_CHANGE_ACT = null
var _kiss: KISS = null
## The act modules' node operations.
var _host: ACT_NODE = null
var _afterglow: AFTERGLOW = null
var _pose: POSE_SESSION = null
## The typed collaborators the act modules read; filled once by the composition function.
var _context: ACT_CONTEXT = null
## The handover's value contract, answering from this node's fields.
var _handover_host: HOST_LIVE = null

## The act's one session handle. The entry, the input service and the debug actions read it.
var act: ACT_SESSION:
	get:
		return _act

## The per-pony scene gate: the offer-facing verdicts and readiness reads.
var scene: SCENE_GATE:
	get:
		return _gate

## The per-pony start handle: the hotkey and Agreement starts and the footstool hint.
var start: START_PORT:
	get:
		return _agreement

## The per-pony presentation handle: the stool reads, the scene hold and the standing invitation.
var presentation: PRESENTATION_PORT:
	get:
		return _act

## `reparent()` runs `_exit_tree()`. The handover moves the live runtime between bodies, so that
## signal must not run the world-close release it exists for.
var _swapping_parent := false


## The World record is built here so the act modules read it unguarded; the parameter body stays
## unbound until the setter hands it to the composition.
func _init(pony: Node = null, world: HANDLES = null) -> void:
	_world = world if world != null else HANDLES.new()
	_compose()
	_assert_children()
	_pony_node = pony if is_instance_valid(pony) else null


## Construct every system, host and module, fill the act record, wire the typed hosts and attach
## the services in their fixed order.
func _compose() -> void:
	var hud: HUD = _world.hud
	var memory: MEMORY = _world.memory
	var stool: STOOL = _world.stool
	var swap: ACT_SWAP = ACT_SWAP.new()
	var tick: ACT_TICK = ACT_TICK.new()
	var phases: ACT_PHASES = ACT_PHASES.new()
	var facts: ACT_FACTS = ACT_FACTS.new()
	_pose = POSE_SESSION.new(facts)
	_gate = SCENE_GATE.new()
	var rest: REST_REJOIN = REST_REJOIN.new()
	var camera: ACT_CAMERA = ACT_CAMERA.new()
	var readiness: READINESS = READINESS.new()
	var auto: AUTO_THRUST = AUTO_THRUST.new()
	var summary: SUMMARY = SUMMARY.new()
	_face = FACE.new()
	var reactions: REACTIONS = REACTIONS.new()
	var dialogue: ACT_DIALOGUE = ACT_DIALOGUE.new(facts)
	_afterglow = AFTERGLOW.new()
	var hold: SCENE_HOLD = SCENE_HOLD.new()
	var audio: RefCounted = AUDIO.ActAudio.new(_world.audio)
	# The per-act systems, in construction order; the handover and the anatomy bridge are built
	# against these instances.
	_handover_host = HOST_LIVE.new()
	_handover = BODY_CHANGE_ACT.new(_handover_host, memory, _world.act_owner,
		_world.body_change, _world.ponies)
	var wings: WING = WING.new(facts)
	var hands: HANDS = HANDS.new(facts)
	var integrations: INTEGRATIONS_ACT = INTEGRATIONS_ACT.new(facts)
	var view: CAMERA_VIEW = CAMERA_VIEW.new(facts)
	var standing_anon: STANDING_ANON = STANDING_ANON.new(facts)
	var standing_presentation: STANDING_PRESENTATION = \
		STANDING_PRESENTATION.new(facts, _world.eligibility)
	camera.wire(facts, hands, view)
	camera.standing_anon = standing_anon
	reactions.wire(_world.anatomy)
	_face.wire(memory, readiness)
	summary.wire(memory)
	dialogue.wire(memory)
	# The act's own host, record, session and modules, in binding order.
	_host = ACT_NODE.new()
	_host.bind(self)
	_context = ACT_CONTEXT.new()
	_context.pose = _pose
	_context.camera = camera
	_context.readiness = readiness
	_context.auto = auto
	_context.afterglow = _afterglow
	_context.face = _face
	_context.reactions = reactions
	_context.dialogue = dialogue
	_context.handover = _handover
	_context.gate = _gate
	_context.facts = facts
	_kiss = KISS.new()
	_kiss.bind(_host, _context)
	_context.kiss = _kiss
	_context.summary = summary
	_context.presentation = standing_presentation
	_context.standing_anon = standing_anon
	_context.view = view
	_context.wings = wings
	_context.hands = hands
	_context.integrations = integrations
	_context.hold = hold
	_context.rest = rest
	_context.hud = hud
	_context.memory = memory
	_context.stool_service = stool
	_context.world = _world
	_act = ACT_SESSION.new()
	_act.bind(_host, _context)
	# The handover's reads point at the live act frame, which exists only after the session binds.
	_handover_host.host = _host
	_handover_host.act = _act
	_handover_host.act_swap = swap
	_handover_host.readiness = readiness
	_handover_host.dialogue = dialogue
	var frame: ACT_FRAME = ACT_FRAME.new()
	frame.bind(_host, _context, _act)
	_context.frame = frame
	var consent: ACT_CONSENT = ACT_CONSENT.new()
	consent.bind(_host, _context, _act)
	_context.consent = consent
	var impact: ACT_IMPACT = ACT_IMPACT.new()
	impact.bind(_host, _context, _act)
	_context.impact = impact
	_context.audio = audio
	var act_view: ACT_VIEW = ACT_VIEW.new()
	act_view.bind(_host, _context)
	var idle: ACT_IDLE = ACT_IDLE.new()
	idle.bind(_host, _context, _act)
	var exit: ACT_EXIT = ACT_EXIT.new()
	exit.bind(_host, _context, _act)
	var input: ACT_INPUT = ACT_INPUT.new()
	input.bind(_host, _context, _act)
	input.exit = exit
	consent.exit = exit
	_act.input = input
	_act.exit = exit
	swap.bind(_host, _context, _act)
	_act.swap = swap
	swap.exit = exit
	phases.bind(_host, _context, _act)
	tick.bind(_host, _context, _act, idle)
	tick.swap = swap
	tick.exit = exit
	tick.phases = phases
	_act.ticker = tick
	var start_ledger: ACT_START = ACT_START.new()
	start_ledger.bind(_host, _context, _act, exit, act_view)
	_agreement = ACT_AGREEMENT.new()
	_agreement.bind(_host, _context, _act, start_ledger)
	_act.start = start_ledger
	_act.view = act_view
	exit.start = start_ledger
	# The act view, readiness, afterglow, face, scene gate, rest, scene hold and controller bindings.
	facts.neck_point = Callable(camera, "neck_midpoint")
	facts.set_look = Callable(phases, "set_look")
	facts.set_forced_glance = Callable(phases, "set_forced_glance")
	facts.set_head_back = Callable(_pose, "set_head_back")
	facts.aim_look = Callable(_pose, "aim_look")
	facts.set_camera_basis_ready = Callable(phases, "set_camera_basis_ready")
	facts.director = Callable(_host, "director")
	facts.now = Callable(_act, "clock_s")
	readiness.wire(READINESS.Deps.new(Callable(phases, "shaft_length_m"),
		Callable(_act, "pose_family"), Callable(_act, "in_heat")))
	readiness.climaxed.connect(Callable(_act, "climax"))
	readiness.close_reached.connect(Callable(_act, "face_beat").bind("close"))
	readiness.overwhelmed.connect(Callable(_act, "face_beat").bind("overwhelmed"))
	readiness.cue_changed.connect(Callable(phases, "cue"))
	readiness.tolerance.connect(Callable(consent, "on_tolerance"))
	readiness.strokes.connect(Callable(impact, "dispatch"))
	_afterglow.caress_active = Callable(hands, "any_active")
	_afterglow.wire(_face, reactions, readiness, _pose, hud, memory)
	_afterglow.bind_host(self)
	_face.clock = Callable(_act, "clock_s")
	_gate.stool_need = Callable(_act, "stool_needed_count")
	_gate.stool_count = Callable(_act, "stool_case_count")
	_gate.presentation_active = Callable(_act, "presentation_active")
	_gate.hold_compatible = Callable(hold, "accepts_hold")
	_gate.debug_context = Callable(_act, "debug_context")
	rest.context = Callable(_act, "rest_context")
	rest.restore_scene = Callable(frame, "restore_scene")
	var hold_host := SCENE_HOLD.Host.new()
	hold_host.pony = Callable(_host, "pony_value")
	hold_host.state = Callable(_act, "state_value")
	hold_host.pose_family = Callable(_act, "pose_family")
	hold.bind(hold_host)
	facts.play_mouth_kiss = Callable(audio, "mouth_kiss")
	facts.speech_stop = Callable(phases, "oral_speech_stop")
	facts.set_mouth_viseme = Callable(_act, "anatomy_set_mouth_viseme")
	facts.act_actions_allowed = Callable(camera, "at_actions_allowed")
	facts.auto_panel_open = Callable(input, "auto_panel_open")
	facts.view = Callable(camera, "view_controller")
	facts.missionary_anon = Callable(_pose, "act_body")
	facts.missionary_face_point = Callable(camera, "missionary_face_point")
	facts.gaze_point = Callable(camera, "gaze_point")
	facts.free_look_rotation = Callable(camera, "free_look_rotation")
	facts.desktop_pose_driver = Callable(standing_anon, "driver")
	facts.cuddle_active = Callable(_gate, "cuddle_active")
	facts.free_of_affection = Callable(_gate, "free_of_affection")
	facts.pause_face_turn = Callable(hold, "pause_face_turn")
	facts.restore_face_turn = Callable(hold, "restore_face_turn")
	facts.hold_excitement = Callable(hold, "hold_beat")
	facts.release_excitement = Callable(hold, "release_beat")
	facts.mod_enabled = Callable(_host, "mod_enabled")
	facts.on_caress = Callable(readiness, "caress")
	facts.on_kiss = Callable(readiness, "kiss")
	facts.on_smack = Callable(readiness, "smack")
	facts.on_anatomy_react = Callable(_act, "anatomy_react")
	facts.on_smack_hit = Callable(reactions, "smack")
	facts.pose_host = Callable(_host, "runtime")
	_gate.wire(_pose, _world.act_gate)
	_gate.configure(_act.state, _act.pony_id)
	_attach(_pose, "UnfplapPoses")
	_attach(camera, "UnfplapCamera")
	_attach(hands, "UnfplapHands")
	_attach(_face, "UnfplapFace")
	_attach(_afterglow, "UnfplapAfterglow")
	_attach(rest, "UnfplapRest")
	_attach(_gate, "UnfplapSceneGate")
	_attach(hold, "UnfplapSceneHold")
	_attach(readiness, "UnfplapReadiness")
	_attach(auto, "UnfplapAutoThrust")
	_attach(reactions, "UnfplapReactions")
	_attach(summary, "UnfplapSummary")
	_attach(dialogue, "UnfplapDialogue")


## Log one error per direct child that is not a Pony service; returns the offender count.
func _assert_children() -> int:
	if not LOG.enabled:
		return 0
	var offenders := 0
	for child: Node in get_children():
		if child.is_in_group(PONY_GROUP):
			continue
		LOG.error("child %s is not a %s service", [str(child.name), PONY_GROUP])
		offenders += 1
	return offenders


## Name, parent and group one Pony service under the runtime; the composition is the only caller.
func _attach(service: Node, service_name: String) -> void:
	service.name = service_name
	add_child(service)
	service.add_to_group(PONY_GROUP)


## Assign the presented body: the pose session's host and the act host's pony follow it. The
## runtime's setter and `_ready()` are the only callers.
func _bind_pony(value: Node) -> void:
	if _host != null:
		_host.pony = value
	if is_instance_valid(_context.reactions) and value is Node3D:
		_context.reactions.bind_scene(value as Node3D,
			(value as Node3D).get_node_or_null("FlankTouch"))


## The frames track the body: with none bound the runtime still composes and releases but ticks
## nothing, which is the suite fixture state, and the game binds before the runtime enters.
func _sync_frames() -> void:
	var body_live := is_instance_valid(_pony_node)
	set_process(body_live)
	set_physics_process(body_live)


func _ready() -> void:
	add_to_group(RUNTIME_GROUP)
	# Run after locomotion/navigator/attention so the body facing lock and head glance win.
	process_physics_priority = 100
	# Identity is the key for per-mare preferences, poses, prompts and memory. It can arrive after
	# the pony enters the tree, so read it now and once more after the first frame.
	_act.refresh_identity()
	_bind_pony(pony)
	_deferred_refresh.call_deferred()
	_face.bind(pony, self)
	# integration: anatomy is persistent outside acts.
	_act.refresh_anatomy()
	_sync_frames()


## The first-frame retry, owned by the node so the engine drops it when the runtime is freed;
## a callable held by the session would outlive the services it reads.
func _deferred_refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(_act):
		return
	_act.refresh_identity()
	if is_instance_valid(_world.anatomy):
		_act.refresh_anatomy()


func _process(delta: float) -> void:
	_act.render(delta)


func _physics_process(delta: float) -> void:
	_act.tick(delta)


## The stable pony id the act is on, read from the live body. `ponies` matches a prompt note to its
## one runtime through this; the id itself stays the act's.
func live_id() -> String:
	_act.refresh_identity()
	return _act.pony_id


## Move the live runtime under another node without running its world-close `_exit_tree()`. The
## handover moves it off the old body and then onto the new one.
func attach_to_body(parent: Node) -> void:
	if not is_instance_valid(parent) or get_parent() == parent:
		return
	_swapping_parent = true
	reparent(parent)
	_swapping_parent = false


## Called when the source's new body spawns, while the runtime is already under the entry: it moves
## under the new body, binds pose, face and anatomy and waits for the resume; a non-adult ends it.
func adopt_body(new_pony: Node) -> void:
	if not _act.suspended() or not is_instance_valid(new_pony):
		return
	_handover.adopt(new_pony)
	pony = new_pony
	_act.bind_adopted_body(new_pony)
	if not _act.swap.new_body_is_adult():
		_act.swap.end_non_adult(new_pony)
		return
	WORLD.refresh_body_lod(new_pony)


## World close or mod switch-off: release what outlives an act. The stock kiss rows are global
## AffectionPose settings, the anatomy nodes are persistent and none may be left behind.
func _exit_tree() -> void:
	if _swapping_parent:
		return
	if _world != null and is_instance_valid(_world.act_owner):
		_world.act_owner.clear_body_swap(self)
	KISS.restore_rows()
	_act.release_stool()
	_host.end_tail_tuck()
	_afterglow.clear_post_act(pony if is_instance_valid(pony) else null)
	# integration: never leave the anatomy act handle or the per-pony controller behind.
	_act.release_anatomy()
	_face.shutdown()
	_release_composition()


## The world-close release runs last: the hands controller and the act record drop their peers, so
## the composition's RefCounted graph collects. It is not a teardown; nothing reads either after.
func _release_composition() -> void:
	_context.hands._release()
	_context.release()
	_act._release()
	_act.context = null
