extends "res://mods/unfplap/shared/presentation_port.gd"
## The act's one state, timer, clock and value owner: a transition guards and dispatches, and the
## owner services do the work. Its typed one-liners are the contract callers use, not wrappers to
## move onto the owners.
##
## See `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AFTERGLOW_SUMMARY := preload("res://mods/unfplap/afterglow/summary.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SETTINGS := preload("res://mods/unfplap/act/settings.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const PONY_IDENTITY := preload("res://mods/unfplap/shared/pony_identity.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const STOOL_ACT := preload("res://mods/unfplap/stool/act.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const VR_ACT := preload("res://mods/unfplap/vr/act.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State
const CLIMAX_SECONDS := ACT_SETTINGS.CLIMAX_SECONDS
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
const CHECK_SECONDS := 0.25
## The cycle phase refresh cadence: the bond day moves once per in-game day.
const CYCLE_REFRESH_S := 0.5
const STATE_NAMES: Array[String] = ["IDLE", "POSING_IN", "ACTIVE", "CLIMAX", "AFTERGLOW", "RESTORE"]
const PHASE_NONE := 0
const ENTER_ACTIVE := 1
const FINISH_CLIMAX := 2
const FINISH_RESTORE := 3

var host: ACT_NODE = null
var context: ACT_CONTEXT = null
var start: Variant = null
var view: Variant = null
## The act's input protocol; the input service reaches it through the session's handle.
var input: Variant = null
## The ordered frame schedule; the entry's two hooks forward here.
var ticker: Variant = null
## The one exit handle. The node's world-close and the suites stop through it.
var exit: Variant = null
## The body-swap seams handle. The node's body binding and the suites read it.
var swap: Variant = null
## The act's settings snapshot and live apply, owned by `act/settings.gd`.
var settings: ACT_SETTINGS = ACT_SETTINGS.new()
## The live act state, written only by the session itself.
var state: int = State.IDLE
var pose_id := ""
var source := ""
var bed: Node3D = null
var event_id := ""
var serial := 0
var pony_id := ""
## The relationship meta the last identity refresh read; a late assignment is caught without an
## allocation per physics frame.
var _identity_meta := ""
var display_name := "the pony"
var preferences: Dictionary = {}
var player_pony := false
var profile: Dictionary = {}
var forced_glance := ""
var posture_owned := false
var finalized := false
var stopped_by_her := false
var aftercare_min := 0
var cue_gap := 0.0
var first_time := false
var act_spoken_at := -1e9
var ended_early := false
var cycle_heat := false
var preserve_auto_shape := false
var snapshot: SETTINGS.ActSnapshot:
	get:
		return settings.snapshot
var features: Dictionary:
	get:
		return settings.features
	set(value):
		settings.features = value
var presentation_config: Dictionary:
	get:
		return settings.presentation_config
	set(value):
		settings.presentation_config = value
var max_pony_climaxes: int:
	get:
		return settings.max_pony_climaxes
	set(value):
		settings.max_pony_climaxes = value
var climax_mode: String:
	get:
		return settings.climax_mode
	set(value):
		settings.climax_mode = value
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
var _climax_progress := 0.0
var _clock_s := 0.0
var _cycle_left := 0.0
var _cycle_cached := "normal"
var _cycle_dirty := true
var _act_seconds := 0.0
## The optional VR standing controller this act built.
var vr: Node = null
func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in
	settings.bind(host_in, context_in)


## Drop the composition's module references at runtime exit; the runtime calls it once, last.
## It is not a teardown: it clears references only, never an act value or a node.
func _release() -> void:
	# The two ledgers point at each other, the one link the module set does not drop on its own.
	if exit != null:
		exit.start = null
	if start != null:
		start.exit = null
	host = null
	context = null
	start = null
	view = null
	input = null
	ticker = null
	exit = null
	swap = null


## Start one act. The ledger owns the recipe and the order; the session only enters it.
func begin(pose: String, bed_in: Variant, act_source: String, skip_presentation := false) -> bool:
	if start == null:
		return false
	return bool(start.run(pose, bed_in, act_source, skip_presentation))
func _set_state(next: int) -> void:
	state = next
	refresh_gate()

func refresh_gate() -> void:
	if context == null or context.gate == null:
		return
	var pony_node: Node3D = host.pony if host != null and is_instance_valid(host.pony) else null
	context.gate.bind_pony(pony_node)
	context.gate.configure(state, pony_id, SCENE_GATE.Features.from_dict(features))

func act_seconds() -> float:
	return _act_seconds

func climax_progress() -> float:
	return _climax_progress

## The one physics frame, owned by `act/tick.gd`.
func tick(delta: float) -> void:
	ticker.tick(delta)

## The one render frame, owned by `act/tick.gd`.
func render(delta: float) -> void:
	ticker.render(delta)

func clock_s() -> float:
	return _clock_s

func feature(name: String) -> bool:
	return bool(features.get(name, false))

func start_row() -> Dictionary:
	return POSE_SPECS.spec(pose_id)

func start_family() -> String:
	return str(start_row().get("family", ""))

func start_group() -> String:
	return str(start_row().get("settings_group", ""))

func pose_values(pose: String, look: Vector3, camera_at: Vector3, size_name: String) -> POSE_SESSION.ActPose:
	var values := POSE_SESSION.ActPose.new()
	var target := pose if not pose.is_empty() else pose_id
	values.fill(str(POSE_SPECS.spec(target).get("id", "")), pony_id, features, bed,
		presentation_config, context.pose.pose_config, look, camera_at, size_name)
	return values

func adopt_display_name(form: BODY_FORM.BodyForm, body: Variant) -> void:
	display_name = PONY_IDENTITY.display_name(form, body if is_instance_valid(body) else null, pony_id)

func refresh_identity() -> bool:
	_cycle_dirty = true
	var identity: PONY_IDENTITY.Identity = PONY_IDENTITY.Identity.new()
	if is_instance_valid(host.pony):
		identity = PONY_IDENTITY.identity_of(host.pony)
		_identity_meta = str(host.pony.get_meta("relationship_id", ""))
	if not identity.id.is_empty():
		pony_id = identity.id
	if pony_id.is_empty():
		refresh_gate()
		return false
	context.pose.set_id(pony_id)
	adopt_display_name(context.handover.form(), host.pony)
	refresh_gate()
	return true

func pose_family() -> String:
	var live: Variant = context.pose.view() if context.pose != null else null
	var family := str(live.family) if live != null else ""
	return family if not family.is_empty() else start_family()

func refresh_view() -> void:
	if view != null:
		view.refresh(context.facts, self)

func sync_hud() -> void:
	view.sync_hud(context.facts, self, max_pony_climaxes, cycle_heat, pose_family())

func stool() -> STOOL_ACT:
	if not WORLD.ready() or not is_instance_valid(host.pony):
		return null
	var service: STOOL = context.stool_service
	if service == null:
		return null
	if context.stool == null:
		context.stool = service.new_act()
	context.stool.bind(service, host.pony as Node3D, WORLD.player_rig(), context.world.anatomy)
	return context.stool

func release_stool() -> void:
	var handle := stool()
	if handle != null:
		handle.release()

func reset_stool_state() -> void:
	var handle := stool()
	if handle != null:
		handle.reset()

func clear_aftercare() -> void:
	context.afterglow.clear_post_act(host.pony if is_instance_valid(host.pony) else null)

func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else "IDLE"

func reset_act() -> void:
	_act_seconds = 0.0
	clear_phase()

func clear_phase() -> void:
	_pose_in_left = 0.0
	_climax_left = 0.0
	_restore_left = 0.0
	_check_clock = 0.0
	_climax_progress = 0.0

func tick_clock(delta: float) -> void:
	_clock_s += maxf(0.0, delta)
	_cycle_left -= delta
	if _cycle_left <= 0.0:
		_cycle_left = CYCLE_REFRESH_S
		_cycle_dirty = true

func advance_act_seconds(delta: float) -> void:
	_act_seconds += delta

func consume_check_clock(delta: float) -> bool:
	_check_clock += delta
	if _check_clock < CHECK_SECONDS:
		return false
	_check_clock = 0.0
	return true

func refresh_climax_progress() -> void:
	_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)

func tick_timers(delta: float) -> int:
	match state:
		State.POSING_IN:
			_pose_in_left -= delta
			if _pose_in_left <= 0.0:
				return ENTER_ACTIVE
		State.CLIMAX:
			_climax_left -= delta
			if _climax_left <= 0.0:
				return FINISH_CLIMAX
		State.RESTORE:
			_restore_left -= delta
			if _restore_left <= 0.0:
				return FINISH_RESTORE
	return PHASE_NONE

func enter_active() -> void:
	_set_state(State.ACTIVE)

func begin_pose_in() -> void:
	_set_state(State.POSING_IN)
	_pose_in_left = POSE_IN_SECONDS

func enter_climax() -> void:
	_set_state(State.CLIMAX)
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0

func enter_afterglow() -> void:
	_set_state(State.AFTERGLOW)

func begin_restore() -> void:
	_set_state(State.RESTORE)
	_restore_left = RESTORE_SECONDS

func finish_restore() -> void:
	enter_idle()

func enter_idle() -> void:
	_set_state(State.IDLE)
	clear_phase()

func enter_active_act() -> void:
	enter_active()
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.ACTIVE)

func snapshot_settings() -> void:
	settings.snapshot_values(start_group(), start_family(), preferences, preserve_auto_shape)
	refresh_gate()

func apply_live_settings() -> void:
	view.apply_live(self)


## The typed act view the HUD and the entry read: the facts object the view fills.
func facts() -> RefCounted:
	return context.facts


## The one exit's force stop. The node's world-close and the suites call it here.
func force_stop() -> void:
	exit.force_stop()


## A body binding's adopt callback: the presented body's revised services are rebound.
func bind_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if context.handover.suspended or not _is_presented_body(body):
		return
	context.handover.rebind(form)


## A revised form on the same presented body: the same rebind, never a resume.
func refresh_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if context.handover.suspended or not _is_presented_body(body):
		return
	context.handover.rebind(form)


func _is_presented_body(body: Node3D) -> bool:
	return host != null and is_instance_valid(host.pony) and body == host.pony


## The handover's request for a form change; the debug action and the suites call it here.
func request_form_change(true_form: bool, shape_id: String = "",
		by_player: bool = false) -> Dictionary:
	return context.handover.request(true_form, shape_id, by_player)


## The pose view the debug rows read.
func pose_view() -> Variant:
	return context.pose.view()


## The readiness reach the anatomy host and the thrust suite read.
func penetration_reach() -> float:
	return context.readiness.reach()


## The afterglow close cue the HUD and the suite read.
func close_hint() -> String:
	return view.close_hint(self, pose_family())


## The pose diagnostic rows for the debug panel.
func pose_state_rows() -> Array:
	return context.pose.state_rows(state)


## The debug face-fit refusal, or "" when the pose can be entered.
func face_sit_error() -> String:
	return context.pose.face_sit_error(state)


## Reload the current pose's source asset from disk.
func reload_pose_asset() -> String:
	var live: Variant = context.pose.view()
	var candidate := str(live.id) if live != null else ""
	return context.pose.reload_authored(candidate)


## The debug face preview. A speaking line still wins.
func force_act_face(face: String) -> bool:
	context.face.sync_settings(feature("face_debug"))
	return context.face.force_face(face)


## The debug tolerance trigger through the consent owner.
func force_tolerance(kind: String) -> bool:
	return context.consent.force(kind)


## The anatomy handle's mouth and frame points for the pose and camera callbacks.
func anatomy_mouth_point() -> Vector3:
	return context.anatomy.mouth_point() if context.anatomy != null else Vector3.ZERO


func anatomy_opening() -> Vector3:
	return context.anatomy.frame_point() if context.anatomy != null else Vector3.ZERO


## The missionary body handle the pose service owns.
func missionary_anon_body() -> Variant:
	return context.pose.act_body_handle()


func anatomy_react() -> void:
	if context.anatomy != null:
		context.anatomy.react()


func anatomy_set_mouth_viseme(letter: String) -> void:
	if context.anatomy != null:
		context.anatomy.set_mouth_viseme(letter)


## Begin the anatomy handle for this act. The pose view is the start row's view; the pose fan-out
## replaces it on every later change.
func begin_anatomy(view: ANATOMY.PoseView) -> void:
	context.pose_view = view
	context.stage = ANATOMY.ActStage.new()
	context.anon = context.world.anatomy.anon() if context.world.anatomy != null else null
	context.anatomy = context.world.anatomy.begin_act(host.pony as Node3D, view) \
		if context.world.anatomy != null else null
	context.facts.anon = context.anon
	if context.anon != null:
		context.anon.encounter(true)


## The one per-frame anatomy call, after the pose fan-out.
func stage_anatomy(delta: float) -> void:
	if context.anatomy == null or context.stage == null:
		return
	context.stage.phase = _anatomy_phase(state)
	context.stage.depth = context.readiness.depth_value()
	context.stage.penetration_m = context.readiness.penetration_m_value()
	context.stage.size_scale = context.camera.size_scale()
	if context.pose_view != null:
		context.pose_view.bed_frame = context.pose._bed_frame_value()
	context.anatomy.stage(delta, context.stage)
	var point: Vector3 = context.anatomy.frame_point()
	context.facts.anatomy_opening = point if point.is_finite() else Vector3.ZERO


## Release the act handle and hide the persistent part. The one exit calls this before the pose.
func release_anatomy() -> void:
	stop_vr()
	if context.anatomy != null:
		context.anatomy.end()
		context.anatomy = null
	if context.anon != null:
		context.anon.encounter(false)
		context.anon = null
	context.facts.anon = null
	context.pose_view = null
	context.stage = null


## Build the optional VR controller; the VR handle owns the scene lookup and the node.
func begin_vr() -> void:
	stop_vr()
	vr = VR_ACT.attach(host.node, WORLD.player_rig())
	if vr == null:
		return
	vr.forward = Callable(self, "vr_forward")
	vr.depth = Callable(self, "vr_depth")
	vr.toggle_hole = Callable(input, "command").bind(ACT_COMMANDS.HOLE)
	vr.oral_ready = Callable(input, "anatomy_oral_ready")
	vr.command = Callable(input, "command")
	vr.touch = Callable(context.readiness, "touch")
	vr.pony_source = Callable(host, "pony_value")


func stop_vr() -> void:
	if is_instance_valid(vr):
		vr.queue_free()
	vr = null


func vr_y_held() -> bool:
	return is_instance_valid(vr) and bool(vr.y_held)


## The forward axis the tracked hips travel along in the VR act.
func vr_forward() -> Vector3:
	if context.anatomy != null:
		var axis: Vector3 = context.anatomy.frame_axis()
		var forward := Vector3(-axis.x, 0.0, -axis.z).normalized()
		if forward.length_squared() > 0.001:
			return forward
	if is_instance_valid(host.pony):
		return -host.pony.global_basis.z.normalized()
	return Vector3.FORWARD


func vr_depth(value: float) -> void:
	if state not in [State.ACTIVE, State.CLIMAX]:
		return
	context.impact.move(value - context.readiness.depth_value(), clock_s())
	context.impact.set_depth(context.readiness.depth_value() * context.readiness.reach())


static func _anatomy_phase(value: int) -> int:
	match value:
		State.POSING_IN:
			return ANATOMY.Phase.POSING_IN
		State.ACTIVE:
			return ANATOMY.Phase.ACTIVE
		State.CLIMAX:
			return ANATOMY.Phase.CLIMAX
		State.AFTERGLOW:
			return ANATOMY.Phase.AFTERGLOW
		State.RESTORE:
			return ANATOMY.Phase.RESTORE
	return ANATOMY.Phase.POSING_IN


## The desktop Anon pose driver's act hooks.
func apply_anon_thrust(hip: Node3D, facing: Basis) -> void:
	context.standing_anon.apply_anon_thrust(hip, facing)


func apply_anon_lean(hip: Node3D, facing: Basis) -> void:
	context.standing_anon.apply_anon_lean(hip, facing)


func apply_anon_align(_hip: Node3D, _facing: Basis) -> void:
	pass


## The cycle reads the entry, prompt notes and debug use.
func cycle_phase() -> String:
	if not is_instance_valid(host.pony):
		return CYCLE.NORMAL
	var meta_id := str(host.pony.get_meta("relationship_id", ""))
	if pony_id.is_empty() or (not meta_id.is_empty() and meta_id != _identity_meta):
		refresh_identity()
	var override := CYCLE.override_for(pony_id)
	if not override.is_empty():
		return override
	if is_instance_valid(context.world.estrus):
		return str(context.world.estrus.phase(host.pony))
	return CYCLE.NORMAL


func cycle_override() -> String:
	refresh_identity()
	return CYCLE.override_for(pony_id)


func cycle_note() -> String:
	if not is_instance_valid(host.pony):
		return ""
	var service: Variant = context.world.act_gate
	return service.cycle_note(host.pony) if service != null else ""

func reset_thrust_state() -> void:
	view.reset_act_state(self)
	act_spoken_at = -1e9
	ended_early = false

func face_beat(moment: String) -> void:
	view.face_beat(moment, self)

func act_face_rows() -> Array[String]:
	return view.face_rows(self)

func pose_render_write() -> void:
	view.pose_render(self)

func apply_camera_motion() -> void:
	view.camera_motion(self)

func prompt_note() -> String:
	refresh_identity()
	return view.prompt_note(self)

func debug_context() -> Dictionary:
	return view.debug_context(self)

func act_input() -> SUMMARY.ActInput:
	return view.summary_input(self)

func commit_summary(real_act: bool) -> void:
	context.summary.commit_act(act_input(), context.readiness, real_act)

func record_peak_memory() -> void:
	context.summary.record_act_peak(act_input(), context.readiness, context.dialogue)

func commit_afterglow() -> void:
	context.summary.commit_after_act(act_input(), context.readiness, context.dialogue,
		display_name, serial, host.pony)

func begin_afterglow() -> void:
	LOG.debug("afterglow pose=%s pony=%s", [pose_id, host.pony_name()])
	context.readiness.stop_auto()
	context.dialogue.end_act(event_id, true)
	# Bed afterglow keeps only lean and caress; standing keeps its kiss.
	if pose_family() != "standing":
		context.kiss.end_lean_kiss()
	commit_afterglow()
	enter_afterglow()
	context.handover.hint_tick()
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.AFTERGLOW)
	refresh_view()
	# The oral afterglow releases the mouth contact and keeps the turned pose.
	context.pose.release_mouth_contact()
	context.integrations.afterglow()
	context.afterglow.set_act(pony_id, event_id)
	context.afterglow.bind_view(context.pose.view())
	var summary := AFTERGLOW_SUMMARY.new()
	summary.fill(context.summary.summary)
	context.afterglow.begin(summary)
	context.readiness.clear_cues()
	context.face.release_stare()
	context.face.set_face(0.85, context.face.AFTERGLOW_LIDS)
	face_beat("afterglow")
	if context.afterglow.apply_presentation():
		context.wings.begin_afterglow()

func climax() -> void:
	if state != State.ACTIVE:
		return
	context.readiness.begin_climax(start_row().get("id", ""), host.pony_name(), CLIMAX_SECONDS)
	enter_climax()
	context.handover.hint_tick()
	context.reactions.schedule_hearts()
	context.reactions.hearts_burst_at(context.reactions.dock_point())
	context.face.set_face(0.3, context.face.CLIMAX_LIDS)
	face_beat("climax")
	context.dialogue.end_act(event_id, true)
	if is_instance_valid(WORLD.world_root()) and context.memory != null \
			and context.readiness.pony_climaxes == 1:
		context.memory.note(MEMORY.NoteKind.CLIMAXED, pony_id, event_id)
	view.climax_line(self)
	context.audio.climax()
	# integration: her fluid and one-shot climax presentation.
	if context.anatomy != null:
		context.anatomy.climax()
	if is_instance_valid(context.hud):
		context.hud.set_state("CLIMAX")

func finish_climax() -> void:
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.CLIMAX_END)
	if max_pony_climaxes > 0 and context.readiness.pony_climaxes >= max_pony_climaxes:
		begin_afterglow()
		return
	enter_active()
	context.face.release_stare()
	context.face.set_face(0.45, context.face.ACT_LIDS)
	context.handover.hint_tick()
	context.readiness.end_climax(max_pony_climaxes)


## The act's scene ownership handle: the negotiation asks for it.
func hold_handle() -> Node:
	return context.hold


## The standing presentation the offer's standing path reads and clears.
func present_standing() -> bool:
	return context.presentation.present_standing()


func presentation_active() -> bool:
	return context.presentation.presentation_active()


func presentation_settled() -> bool:
	return context.presentation.presentation_settled()


func clear_presentation() -> void:
	context.presentation.clear_presentation()


## The per-act footstool reads the offer's hint uses; a missing handle reads as blocked nothing.
func stool_pair(pose: String) -> Vector2i:
	var handle := stool()
	return handle.hotkey_pair(pose) if handle != null else NO_STOOL_PAIR


func stool_gap_m() -> float:
	var handle := stool()
	return handle.gap_m() if handle != null else NAN


func stool_needed_count() -> int:
	var handle := stool()
	return handle.needed_count() if handle != null else 0


func stool_case_count() -> int:
	var handle := stool()
	return handle.case_count() if handle != null else 0


func stool_state_text() -> String:
	var handle := stool()
	return handle.state_text() if handle != null else "stool unavailable"


## The rump point the offer hint anchors to.
func rump_anchor() -> Vector3:
	return context.reactions.rump_point()


## The typed reads the host-callback bindings use. Each one names the value's owner: the state and
## the act values here, the meter on readiness, the handles on their service.
func state_value() -> int:
	return state


func act_live() -> bool:
	return state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]


func restoring() -> bool:
	return state == State.RESTORE


func suspended() -> bool:
	return context.handover != null and context.handover.suspended


func act_id() -> String:
	return pony_id


func start_id() -> String:
	return str(start_row().get("id", ""))


func event_id_value() -> String:
	return event_id


func climax_limit() -> int:
	return max_pony_climaxes


func cue_reaction_max_age() -> float:
	return snapshot.cue_reaction_max_age_s


func current_pose_id() -> String:
	return pose_id


func in_heat() -> bool:
	return cycle_phase() == CYCLE.HEAT


func kiss_service() -> Variant:
	return context.kiss


func reactions_service() -> Variant:
	return context.reactions


## The rest facade's live act values, built on demand for its one decision.
func rest_context() -> Dictionary:
	return {
		"state": state,
		"serial": serial,
		"player_pony": player_pony,
		"headset": WORLD.headset_view(),
		"summary": context.summary.summary,
		"satisfaction": context.readiness.satisfaction,
		"aftercare_min": aftercare_min,
	}


## The form handover's cue override uses the act's own duration, not a fresh settings read.
func form_cue_override(text: String) -> void:
	context.readiness.set_cue_override(text, snapshot.cue_override_seconds)


func form_set_face(smile: float) -> void:
	context.face.set_face(smile, context.face.ACT_LIDS)


func form_status(text: String) -> void:
	if is_instance_valid(context.hud):
		context.hud.toast(text, 2.5)


## The roster's anatomy re-check at act start; the handle itself is created by the start ledger.
## The stored form is re-presented, so a retry never resets a borrowed shape to the own form.
func refresh_anatomy() -> void:
	var pony: Node = host.pony if is_instance_valid(host.pony) else null
	if not is_instance_valid(pony) or not is_instance_valid(context.world.anatomy):
		return
	var body := pony as Node3D
	if not is_instance_valid(body):
		return
	var form: Variant = null
	if is_instance_valid(context.world.body_change):
		form = context.world.body_change.form_for(body)
	context.world.anatomy.present(body, form)


## The adopted body's bind before the handover's one resume: the pose, face, identity name, view,
## anatomy and scene gate. It never resumes by itself.
func bind_adopted_body(body: Node) -> void:
	context.pose.bind(host.node, body)
	context.face.bind(body as Node3D, host.node)
	context.audio.rebind_body(body, pony_id, bed)
	adopt_display_name(context.handover.form(), body)
	refresh_view()
	refresh_anatomy()
	refresh_gate()
