extends RefCounted
## The act's one state, timer, clock and value owner. One per pony, created once and reset per
## act. It writes `state` through `_set_state()`; a transition guards and dispatches, and the
## owner services do the work. The settings snapshot lives in `act/settings.gd`, the read
## composition in `act/view.gd` and the ordered frame in `act/tick.gd`.
##

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SETTINGS := preload("res://mods/unfplap/act/settings.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")

const State := ACT_STATE.State
const CLIMAX_SECONDS := ACT_SETTINGS.CLIMAX_SECONDS
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
const CHECK_SECONDS := 0.25
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
## The act's settings snapshot and live apply, owned by `act/settings.gd`.
var settings: ACT_SETTINGS = ACT_SETTINGS.new()
## The live act state. `_set_state()` is the only writer.
var state: int = State.IDLE
var pose_id := ""
var source := ""
var bed: Node3D = null
var event_id := ""
var serial := 0
var pony_id := ""
var display_name := "the pony"
var preferences: Dictionary = {}
var act_prompts: Dictionary = {}
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
var caress_quality: String:
	get:
		return settings.caress_quality
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
var eye_camera_mode: bool:
	get:
		return settings.eye_camera_mode
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
var _check_clock := 0.0
var _climax_progress := 0.0
var _clock_s := 0.0
var _act_seconds := 0.0
## True while the idle window's perf probe is enabled; set by the settings apply and `_ready`.
var idle_perf := false
func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in
	settings.bind(host_in, context_in)
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
	context.gate.bind(host.pony if host != null else null, context.pose)
	context.gate.configure(state, pony_id, features)

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

func placement_values(form: BODY_FORM.BodyForm = null) -> PLACEMENT.ActBind:
	var values := PLACEMENT.ActBind.new()
	var gaps: Variant = context.pose.pose_config.get("gaps", {})
	values.fill(host.pony, WORLD.player if is_instance_valid(WORLD.player) else null, bed,
		context.stool, form, context.handover.form(), pony_id,
		gaps if gaps is Dictionary else {}, context.camera, PONIES.anatomy, player_pony,
		WORLD.headset_view(), host.log_sink)
	return values

func adopt_display_name(form: BODY_FORM.BodyForm, body: Variant) -> void:
	display_name = PONIES.display_name_for(form, body if is_instance_valid(body) else null, pony_id)

func refresh_identity() -> bool:
	var identity: PONIES.Identity = PONIES.Identity.new()
	if is_instance_valid(host.pony):
		identity = PONIES.identity_of(host.pony)
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

func stool() -> Variant:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(host.pony):
		return null
	var service: Variant = STOOL.instance
	if service == null or not service.has_method("new_act"):
		return null
	if context.stool == null:
		context.stool = service.call("new_act")
		context.stool.call("set_log", host.log_sink)
	context.stool.call("bind", service, host.pony, WORLD.player, context.anatomy.controller)
	return context.stool

func release_stool() -> void:
	if stool() != null:
		context.stool.call("release")

func reset_stool_state() -> void:
	if stool() != null:
		context.stool.call("reset")

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

func apply_live_settings() -> bool:
	return view.apply_live(self)

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
	host.log("afterglow pose=%s pony=%s" % [pose_id, host.pony_name()])
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
	context.afterglow.begin(context.summary.summary)
	context.readiness.clear_cues()
	context.face.release_stare()
	context.face.set_face(0.85, context.face.AFTERGLOW_LIDS)
	face_beat("afterglow")
	if context.afterglow.apply_presentation(context.pose):
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
	if is_instance_valid(WORLD.game) and context.readiness.pony_climaxes == 1:
		MEMORY.instance.note(MEMORY.NoteKind.CLIMAXED, pony_id, event_id)
	view.climax_line(self)
	context.audio.play_climax()
	# integration: her fluid hook.
	context.anatomy.on_climax()
	if is_instance_valid(HUD.instance):
		HUD.instance.set_state("CLIMAX")

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
func hold_handle() -> RefCounted:
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
