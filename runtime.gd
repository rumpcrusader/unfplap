extends Node
## One per pony. The per-pony host and composition root: lifetime, the one bind pass, the two frame
## forwards and the act's session, start, exit and view handles. The `act/` modules own the state,
## the schedule, the presentation, the input protocol, the swap seams, the ledgers and the view; the
## node owns no system's rules or mutable state and never edits game files.

const ACT_BUILD := preload("res://mods/unfplap/act/build.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
const ACT_GATE := preload("res://mods/unfplap/act/gate.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const MISSIONARY_CAMERA := preload("res://mods/unfplap/camera/missionary_camera.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

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

## The pony this runtime presents. Assigning a body rebinds the pose session and the act host
## through the bundle; nothing else is rebound per frame.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_bundle.bind_pony(value)

var _pony_node: Node = null
## The per-pony composition root's product. `_init()` builds it once and the field aliases below
## point at its objects; the builder owns construction, the node owns the aliases for the step.
var _bundle: ACT_BUILD.Bundle = null

## The act's one state, timer, clock and value owner; created once per pony and reset per act.
var _act: ACT_SESSION = null
## The act modules' node operations and typed collaborator set, built by `act/build.gd`.
var _act_host = null
var _act_context = null
var _view = null
var _consent: RefCounted = null
var _input = null
var _swap = null
var _tick = null
var _phases = null
var _impact = null
var _idle = null
var _exit = null
var _start = null
var _agreement = null

## Temporary read-only forward: the act session owns the live state; remove in R4.
var state: int:
	get:
		return _act.state if _act != null else State.IDLE
## The act's one session handle: the state, the timers and the input protocol. The entry and the
## input service read it; the Node keeps lifetime and node operations.
var act: ACT_SESSION:
	get:
		return _act


## The offer-facing gate handle: scene verdicts, the Agreement start, the hotkey readiness and the
## stool/rump/presentation reads. `offer`, `negotiation` and `initiation` use this handle.
var gate: ACT_GATE:
	get:
		return _bundle.act_gate if _bundle != null else null


## The act's readiness system; see `readiness/service.gd`. The public act values below forward to it.
var _readiness: RefCounted = null
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
var _pose_session: RefCounted = null
## The scene gate: the live state, navigator, bed, cuddle, player and pose rows. See
## `scene_gate/service.gd` and `docs/scene_gate.md`.
var _scene: RefCounted = null
## The bed/couch rest and cuddle rejoin. See `rest/service.gd` and `docs/rest.md`.
var _rest: RefCounted = null
## The act camera session: the lean, the shot smoothing, the free look, the free-camera lock, the
## standing eye override and the captured player look. See `camera/service.gd` and `docs/camera.md`.
var _act_camera: RefCounted = null
## The per-act anatomy bridge: the persistent controller, the per-act handle, the typed context,
## the missionary body and the VR controller. See `docs/anatomy.md`.
var _anatomy_bridge: RefCounted = null
## Reused typed act context. The runtime writes it; the presentation controllers read it instead of
## reaching into this node. See `shared/act_facts.gd`.
var _act_facts: RefCounted = null
## The standing placement math. The runtime fills its facts and keeps the ordered start adapters.
var _placement: PLACEMENT = null
## Reused placement facts. One object per runtime; the runtime writes it before each call.
var _placement_facts: PLACEMENT.Facts = null

## The act's dialogue service: scheduler, prompt assembly, reactions and the bystander line.
var _act_dialogue: RefCounted = null
## Debug perf probe: timed chunks report here and one summary prints per window. Built by the
## composition root once the systems exist, because the host binds their live reads. See
## `shared/perf.gd`.
var _perf_probe = null
## Cached gate for the idle probe. Set once in `_ready()` and again on every live settings edit, so
## no tick reads the entry node's flags.
## Estrus is derived from the world day and her relationship, so it is resolved once per tick and
## the HUD card reads the cached flag.
## A body swap keeps the act alive but stops its ticks. The handover owns the typed change, the
## adopted body and the current pose id until the one resume; `act/exit.gd:run()` is still the only
## exit.
var _handover = null
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
var _afterglow: RefCounted = null
## The act's scene ownership. The runtime keeps the act state and the teardown order; the service
## owns the flags. See `scene_hold/service.gd`.
var _hold: RefCounted = null
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
var _summary_service: RefCounted = null
var _wings: WING = null
## The act's face owner: beats, line-face ownership, the stare release and the post-act mood
## face. See `face/service.gd` and `docs/face.md`.
var _face: RefCounted = null
## Thrust and climax presentation: jiggle, smack reaction, rump blush and hearts. See
## `reactions/service.gd` and `docs/reactions.md`.
var _reactions: RefCounted = null
var _hands: HANDS = null
var _kiss: KISS = null
var _integrations: INTEGRATIONS = null
var _missionary_camera_ctl: MISSIONARY_CAMERA = null
var _standing_camera_ctl: STANDING_CAMERA = null
var _standing_anon_ctl: STANDING_ANON = null
var _standing_presentation_ctl: STANDING_PRESENTATION = null
## One runtime's act audio: the lazy node, the voice policy and the excitement Beat holds.
var _audio = null

## Build the per-pony composition root once and point the runtime's field aliases at its objects.
## The builder owns construction and the one bind pass; every method below still reads its alias.
func _init() -> void:
	_bundle = ACT_BUILD.build(null, self)
	_act = _bundle.act
	_act_host = _bundle.host
	_act_context = _bundle.context
	_act_facts = _bundle.facts
	_act_camera = _bundle.camera
	_act_dialogue = _bundle.dialogue
	_afterglow = _bundle.afterglow
	_agreement = _bundle.agreement
	_anatomy_bridge = _bundle.anatomy_bridge
	_anatomy_host_cache = _bundle.anatomy_host
	_audio = _bundle.audio
	_consent = _bundle.consent
	_exit = _bundle.exit
	_face = _bundle.face
	_hands = _bundle.hands
	_handover = _bundle.handover
	_hold = _bundle.hold
	_idle = _bundle.idle
	_impact = _bundle.impact
	_input = _bundle.input
	_integrations = _bundle.integrations
	_kiss = _bundle.kiss
	_missionary_camera_ctl = _bundle.missionary_camera
	_perf_probe = _bundle.perf_probe
	_phases = _bundle.phases
	_placement = _bundle.placement
	_placement_facts = _bundle.placement_facts
	_pose_session = _bundle.pose
	_readiness = _bundle.readiness
	_reactions = _bundle.reactions
	_rest = _bundle.rest
	_scene = _bundle.gate
	_start = _bundle.start
	_standing_anon_ctl = _bundle.standing_anon
	_standing_camera_ctl = _bundle.standing_camera
	_standing_presentation_ctl = _bundle.presentation
	_summary_service = _bundle.summary
	_swap = _bundle.swap
	_tick = _bundle.tick
	_view = _bundle.view
	_wings = _bundle.wings



## The typed host the anatomy bridge reads, built once by `act/build.gd`.
var _anatomy_host_cache = null



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
	_bundle.bind_pony(pony)
	call_deferred("refresh_identity")
	_face.bind(pony, self)
	# integration: anatomy is persistent outside acts. Retry once after the first frame for a mod
	# that assigns the pony's identity after she enters the tree.
	_anatomy_refresh()
	call_deferred("_anatomy_refresh")


## integration: resolve the persistent anatomy controller through the world service. The bridge
## owns the controller handle; the service owns the controller.
func _anatomy_refresh() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.refresh()


func anatomy_facts() -> RefCounted:
	return _anatomy_bridge.context()


## Public hook for the anatomy's stock flank smack. The controller calls it through the context
## callback instead of reaching into the reaction facade.
func body_coat_jiggle_target() -> void:
	_reactions.body_coat_target()


func _anatomy_act_refresh() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
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











func _claim_nav() -> bool:
	if _hold.holds_negotiation():
		return _hold.adopt_hold()
	return _hold.claim_nav(_id)



func _scene_hold_compatible(pose: String, source: String) -> bool:
	return _hold.accepts_hold(pose, source)


## Standing keeps her body turned away and planted. Stop the standing face-turn response so a
## player conversation cannot make her take turn steps, without pausing locomotion or emotions.







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
	_anatomy_bridge.bind(_anatomy_host_cache)
	return _anatomy_bridge.mouth_point()


## The opening the pose turn captures before the turn.
func _oral_opening_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host_cache)
	return _anatomy_bridge.opening()


## The face contact's real anchor on the act body. The pose service's face driver uses it; a
## missing or inactive body is Vector3.INF.
func _anatomy_face_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host_cache)
	var point: Variant = _anatomy_bridge.face_point()
	return point if point is Vector3 else Vector3.INF


## The edge viseme event: the D shape, or the clear on contact release.
func _oral_viseme(value: String) -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.set_oral_viseme(value)




## integration: anatomy action entry points for the input service. They are no-ops when the
## per-act controller is absent, so the keys behave exactly like master with the feature off.
func toggle_anatomy_hole() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.toggle_hole()


## The `oral` command: request the standing oral pose, or the return edge when it is already
## active. The per-mare consent string is passed only when the anatomy service says yes.
func toggle_anatomy_oral() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.toggle_oral(_pose_service(), _act.display_name, _act.features)


func missionary_anon_body() -> Variant:
	return _anatomy_bridge.missionary_anon_body()


## Her gaze target in missionary: the authored Anon's face. The game camera is on his standing
## player rig, metres off the bed, and aiming there had her looking at empty air.
func _missionary_gaze_point() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host_cache)
	return _anatomy_bridge.gaze_point()


## The game's eye modifier still points wherever the standing player rig left it; in missionary the
## pupils follow the same gaze target the head solve uses, so the eyes do not sit above his face.
func _aim_missionary_eyes() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.aim_eyes()


func _start_vr_act() -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.vr_start()


func vr_forward() -> Vector3:
	_anatomy_bridge.bind(_anatomy_host_cache)
	return _anatomy_bridge.vr_forward()


func vr_depth(value: float) -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
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
	_anatomy_bridge.bind(_anatomy_host_cache)
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


func _rest_context() -> Dictionary:
	return {
		"state": state,
		"serial": _act.serial,
		"player_pony": _act.player_pony,
		"headset": WORLD.headset_view(),
		"summary": _summary_service.summary,
		"satisfaction": _readiness.satisfaction,
		"aftercare_min": _act.aftercare_min,
	}


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



## Publish or clear the pose session's opaque Anon body handle on the anatomy bridge. The session
## owns the body; the bridge only reads it.
func _set_missionary_anon_handle(body: Variant) -> void:
	_anatomy_bridge.bind(_anatomy_host_cache)
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
	_anatomy_bridge.bind(_anatomy_host_cache)
	_anatomy_bridge.end()
	_anatomy_bridge.detach()
	_face.shutdown()
