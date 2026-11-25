extends "res://mods/unfplap/shared/presentation_port.gd"
## The act's one state, timer, clock and value owner: a transition guards and dispatches, and the
## owner services do the work. Its typed one-liners are the contract callers use, not wrappers to
## move onto the owners.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AFTERGLOW_SUMMARY := preload("res://mods/unfplap/afterglow/summary.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_REPORT := preload("res://mods/unfplap/shared/act_report.gd")
const ACT_SETTINGS := preload("res://mods/unfplap/act/settings.gd")
const SUMMARY := preload("res://mods/unfplap/summary/api.gd")
const ACT_METER := preload("res://mods/unfplap/shared/act_meter.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const PONY_IDENTITY := preload("res://mods/unfplap/shared/pony_identity.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const STOOL := preload("res://mods/unfplap/stool/api.gd")
const STOOL_ACT := preload("res://mods/unfplap/stool/act.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/api.gd")
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

## One live act snapshot at a change; the cross-mod facade relays it.
signal progress(data: Dictionary)

## One committed act result; the cross-mod facade relays it.
signal result(data: Dictionary)

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
## The live form id; her own body reports the stable pony id.
var _form_id := ""
## Every form she wore during the act, in order; a repeated form stays in the list.
var _forms_taken: Array[String] = []
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
## The one verdict this act produced; the presentation reads it across the afterglow.
var act_score: SUMMARY.ActScore = null
var cycle_heat := false
## The director turn the act has already read for the player's own words.
var talk_turn := -1
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
var _progress_due := false
var _result_emitted := false
var _last_state: int = State.IDLE
var _last_mood := ""
var _last_climaxes := -1
var _last_heat := false
var _last_pose := ""
var _last_form := ""
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
	_progress_due = true
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
	_emit_progress_if_changed()

## The one render frame, owned by `act/tick.gd`.
func render(delta: float) -> void:
	ticker.render(delta)

func clock_s() -> float:
	return _clock_s

func start_row() -> Dictionary:
	return POSE_SPECS.spec(pose_id)

func start_family() -> String:
	return str(start_row().get("family", ""))

func start_group() -> String:
	return str(start_row().get("settings_group", ""))

## The pose's start values: its id and the two camera points. The id, bed and features come from
## the facts; the size name and the block from settings.
func pose_start(pose: String, look: Vector3, camera_at: Vector3) -> POSE_SESSION.PoseStart:
	var start := POSE_SESSION.PoseStart.new()
	var target := pose if not pose.is_empty() else pose_id
	start.pose_id = str(POSE_SPECS.spec(target).get("id", ""))
	start.look = look
	start.camera_at = camera_at
	return start

func adopt_display_name(form: BODY_FORM.BodyForm, body: Variant) -> void:
	display_name = PONY_IDENTITY.display_name(form, body if is_instance_valid(body) else null, pony_id)
	var form_id := form.form_id.strip_edges() if form != null else ""
	var next_id := form_id if not form_id.is_empty() else pony_id
	if not next_id.is_empty() and (_forms_taken.is_empty() or next_id != _forms_taken.back()):
		_forms_taken.append(next_id)
	_form_id = next_id

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
	_forms_taken.clear()
	_form_id = ""
	act_score = null
	talk_turn = -1
	_progress_due = false
	_result_emitted = false
	_last_state = State.IDLE
	_last_mood = ""
	_last_climaxes = -1
	_last_heat = false
	_last_pose = ""
	_last_form = ""
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
	settings.snapshot_values(start_group(), start_family())
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
	return context.readiness.readout().reach_m


## The director turn this act has already read: the opening turn is remembered at the start so it
## is never scored as fresh input, and a new turn hands its words back once.
func take_player_line(director: Node) -> String:
	var turn := director_turn(director)
	if turn == talk_turn:
		return ""
	talk_turn = turn
	return str(director.get("_player_text")).strip_edges()


func remember_talk_turn(director: Node) -> void:
	talk_turn = director_turn(director)


static func director_turn(director: Node) -> int:
	if director == null:
		return -1
	var value: Variant = director.get("_turn_id")
	return int(value) if value != null else -1


## The afterglow close cue the HUD and the suite read.
func close_hint() -> String:
	return view.close_hint(self, pose_family())


## The pose diagnostic rows for the debug panel.
func pose_state_rows() -> Array:
	return context.pose.diagnostics().state_rows(state)



## Reload the current pose's source asset from disk.
func reload_pose_asset() -> String:
	var live: Variant = context.pose.view()
	var candidate := str(live.id) if live != null else ""
	return context.pose.reload_authored(candidate)


## The debug face preview. A speaking line still wins.
func force_act_face(face: String) -> bool:
	context.face.sync_settings(SETTINGS.face_debug.get_bool())
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
	return context.pose.act_body()


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
	context.stage.depth = context.readiness.readout().depth
	context.stage.penetration_m = context.readiness.readout().penetration_m
	context.stage.size_scale = context.camera.size_scale()
	if context.pose_view != null:
		context.pose_view.bed_frame = context.pose.view().bed_frame
	context.anatomy.stage(delta, context.stage)
	var point: Vector3 = context.anatomy.frame_point()
	context.facts.anatomy_opening = point if point.is_finite() else Vector3.ZERO
	var mouth: Vector3 = context.anatomy.mouth_point()
	context.facts.anatomy_mouth = mouth if mouth.is_finite() else Vector3.ZERO


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
	vr.touch = Callable(context.facts, "touch")
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
	context.impact.set_penetration(value * context.readiness.readout().reach_m)


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

## The one verdict funnel: the act's snapshot is scored once, its consequences are committed, and
## the verdict is kept here for the presentation. The afterglow entry, a cancel and a partner stop
## are its only callers, so an act commits exactly once and never after its afterglow has ended.
func finish() -> void:
	if act_score != null or not is_instance_valid(context.summary):
		return
	var score := context.summary.score(view.summary_snapshot(self))
	context.summary.commit(score, view.summary_exchange())
	act_score = score
	_emit_result_once()


## The verdict's record as the presentation reads it; empty before the verdict and on a skip.
func _outcome() -> Dictionary:
	return act_score.outcome if act_score != null else {}


## One progress emission per frame at most: a scalar comparison, then a payload only on a change.
func _emit_progress_if_changed() -> void:
	if context.handover != null and context.handover.suspended:
		return
	if state == State.IDLE and not _progress_due:
		return
	var readiness := context.readiness
	if readiness == null or not is_instance_valid(readiness):
		return
	var readout := readiness.readout()
	if not _progress_due and state == _last_state and readout.mood == _last_mood \
			and readout.climaxes == _last_climaxes and cycle_heat == _last_heat \
			and pose_id == _last_pose and _form_id == _last_form:
		return
	_last_state = state
	_last_mood = readout.mood
	_last_climaxes = readout.climaxes
	_last_heat = cycle_heat
	_last_pose = pose_id
	_last_form = _form_id
	_progress_due = false
	var report := ACT_REPORT.Progress.new()
	report.act_id = serial
	report.state = state_name()
	report.pony_id = pony_id
	report.form_id = _form_id if not _form_id.is_empty() else pony_id
	report.pose = pose_id
	report.duration_s = act_seconds()
	report.mood = readout.mood
	report.climaxes = {"current": readout.climaxes, "limit": climax_limit()}
	report.heat = cycle_heat
	progress.emit(report.to_dict())


## One result per act, only once the act has a verdict; a skipped or never-scored act sends none.
func _emit_result_once() -> void:
	if _result_emitted or act_score == null:
		return
	var summary: Dictionary = act_score.outcome
	if summary.is_empty():
		return
	var readiness := context.readiness
	if readiness == null or not is_instance_valid(readiness):
		return
	_result_emitted = true
	var meter: ACT_METER = act_score.meter
	var report := ACT_REPORT.Result.new()
	report.act_id = serial
	report.pony_id = pony_id
	report.form_id = _form_id if not _form_id.is_empty() else pony_id
	report.forms = _report_forms()
	report.pose = pose_id
	report.duration_s = act_seconds()
	report.thrusts = meter.thrusts if meter != null else 0
	report.climaxes = {"current": readiness.readout().climaxes, "limit": climax_limit()}
	report.grade = str(summary.get("grade", "neutral"))
	report.stop_reasons = _summary_reasons(summary)
	report.outcome = {
		"romance": int(summary.get("romance", 0)),
		"mood": str(summary.get("mood", "")),
	}
	result.emit(report.to_dict())


func _report_forms() -> Array[String]:
	var out: Array[String] = _forms_taken.duplicate()
	if not out.is_empty():
		return out
	if not _form_id.is_empty():
		return [_form_id]
	return [pony_id]


static func _summary_reasons(summary: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = summary.get("reasons", [])
	if raw is Array:
		for item: Variant in raw:
			out.append(str(item))
	return out

func begin_afterglow() -> void:
	LOG.debug("afterglow pose=%s pony=%s", [pose_id, host.pony_name()])
	context.auto.stop()
	context.readiness.end_act()
	context.dialogue.end_act(event_id, true)
	# Bed afterglow keeps only lean and caress; standing keeps its kiss.
	if pose_family() != "standing":
		context.kiss.stop()
	finish()
	# The adults who can perceive the pair remember it here: the afterglow entry is the one moment
	# this route reaches, and it still holds the scene the witness pass reads.
	if is_instance_valid(WORLD.world_root()) and context.memory != null:
		for row: MEMORY.Witness in context.memory.witnesses(pony_id, display_name, serial,
				host.pony):
			LOG.debug("witness %s", [row.to_dict()])
	enter_afterglow()
	context.handover.hint_tick()
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.AFTERGLOW)
	refresh_view()
	# The oral afterglow releases the mouth contact and keeps the turned pose until the one exit
	# restores the frame.
	context.pose.release_mouth_contact()
	context.integrations.afterglow()
	context.afterglow.set_act(pony_id, event_id)
	context.afterglow.bind_view(context.pose.view())
	var summary := AFTERGLOW_SUMMARY.new()
	summary.fill(_outcome())
	context.afterglow.begin(summary)
	context.face.release_stare()
	context.face.set_face(0.85, context.face.AFTERGLOW_LIDS)
	face_beat("afterglow")
	if context.afterglow.apply_presentation():
		context.wings.begin_afterglow()

func climax() -> void:
	if state != State.ACTIVE:
		return
	context.readiness.begin_climax(CLIMAX_SECONDS)
	enter_climax()
	context.handover.hint_tick()
	context.reactions.schedule_hearts()
	context.reactions.hearts_burst_at(context.reactions.dock_point())
	context.face.set_face(0.3, context.face.CLIMAX_LIDS)
	face_beat("climax")
	context.dialogue.end_act(event_id, true)
	if is_instance_valid(WORLD.world_root()) and context.memory != null \
			and context.readiness.readout().climaxes == 1:
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
	if max_pony_climaxes > 0 and context.readiness.readout().climaxes >= max_pony_climaxes:
		begin_afterglow()
		return
	enter_active()
	context.face.release_stare()
	context.face.set_face(0.45, context.face.ACT_LIDS)
	context.handover.hint_tick()
	context.readiness.end_climax()


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


func reactions_service() -> Variant:
	return context.reactions


## The rest facade's live act values, built on demand for its one decision.
func rest_context() -> Dictionary:
	return {
		"state": state,
		"serial": serial,
		"player_pony": player_pony,
		"headset": WORLD.headset_view(),
		"summary": _outcome(),
		"satisfaction": context.readiness.readout().satisfaction,
		"aftercare_min": aftercare_min,
	}


## The form handover's cue override uses the act's own duration, not a fresh settings read.
func form_cue_override(text: String) -> void:
	context.readiness.cue(text, snapshot.cue_override_seconds)


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
	context.face.bind(body as Node3D, host.node)
	context.audio.rebind_body(body, pony_id, bed)
	adopt_display_name(context.handover.form(), body)
	refresh_view()
	refresh_anatomy()
	refresh_gate()
