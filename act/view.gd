extends RefCounted
## The act view composition. It fills the typed read model (`shared/act_facts.gd`) from the
## session, the live systems and the plain act values, and gathers the HUD card's values. One per
## pony, bound once; the schedule and the act boundaries call it once per phase.
##
## See `docs/act_facts.md` and `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const FACE := preload("res://mods/unfplap/face/api.gd")
const BEAT := preload("res://mods/unfplap/shared/face_beat.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const SUMMARY := preload("res://mods/unfplap/summary/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug_actions/pony.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_NODE = null
var context: ACT_CONTEXT = null


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Compose the view from the session and the live systems. Each phase refreshes it in its own slot:
## idle first, physics between pose tick and fan-out, render before the camera.
func refresh(facts: ACT_FACTS, session: ACT_SESSION) -> void:
	var pose_session: Variant = context.pose
	var pose_view: Variant = pose_session.view()
	facts.state = session.state
	facts.pose_view = pose_view
	facts.source = session.source
	facts.satisfaction = context.readiness.satisfaction
	facts.mood = context.readiness.mood
	facts.cue = context.readiness.cue
	facts.form_hint = context.handover.form_hint()
	facts.pony_climaxes = context.readiness.pony_climaxes
	facts.depth = context.readiness.depth
	facts.penetration_m = context.readiness.penetration_m
	facts.pony = host.pony
	facts.camera = context.camera.camera
	facts.viewport = host.viewport()
	facts.pose = pose_session.pose()
	facts.event_id = session.event_id
	facts.pony_id = session.pony_id
	facts.display_name = session.display_name
	facts.preferences = session.preferences
	facts.features = session.features
	facts.player_pony = session.player_pony
	facts.bed = session.bed
	facts.presentation_config = session.presentation_config
	facts.profile = session.profile
	facts.physics_delta = host.physics_delta()
	if session.state == State.IDLE:
		# No presentation module reads the derived values outside an act; skipping the settings and
		# geometry lookups keeps an idle town from paying for every runtime every frame.
		return
	facts.act_seconds = session.act_seconds()
	facts.seconds_since_stroke = maxf(0.0, session.clock_s() - context.readiness.last_stroke_at)
	facts.last_intensity = context.readiness.last_intensity
	facts.last_pattern = context.readiness.last_pattern
	facts.last_touch = context.readiness.last_touch
	facts.last_talk = context.readiness.last_talk
	facts.cue_override = not context.readiness.cue_override.is_empty()
	facts.thrust_pace = context.readiness.thrusts_per_second()
	# The pose view is the one contact source; the mouth/contact provider reads `contact_kind`.
	facts.penetration_reach = context.readiness.reach()
	var cam: Variant = context.camera
	facts.size_name = cam.size_name()
	facts.size_scale = cam.size_scale()
	facts.lean_size_scale = cam.lean_size_scale()
	facts.standing_lean_scale = cam.standing_lean_scale()
	facts.player_eye_height = cam.player_eye_height()
	facts.anon_torso_forward = cam.anon_torso_forward()
	facts.anon_torso_drop = cam.anon_torso_drop()
	facts.headset_view = WORLD.headset_view()
	facts.free_camera_active = cam.free_camera_active
	facts.free_look_active = cam.free_look_active()
	facts.camera_owned = cam.camera_owned
	# The act frame owns the captured look; the camera only runs its live offsets on top.
	var frame: Variant = context.frame
	var frame_plan: Variant = frame.plan() if frame != null else null
	if frame_plan != null:
		facts.look_captured = bool(frame.active())
		facts.look_yaw = float(frame_plan.look_yaw)
		facts.look_pitch = float(frame_plan.look_pitch)
	else:
		facts.look_captured = false
		facts.look_yaw = 0.0
		facts.look_pitch = 0.0
	facts.lean_forward = cam.lean_forward
	facts.lean_side = cam.lean_side
	facts.lean_action_side = cam.lean_action_side
	facts.lean_view_forward = cam.lean_view_forward
	facts.lean_view_side = cam.lean_view_side
	facts.lean_sway = cam.lean_sway
	facts.lean = cam.lean
	facts.shot_lean_forward = cam.shot_lean_forward()
	facts.thrust_travel = context.readiness.thrust_travel
	facts.same_height_scale = cam.same_height_scale()
	facts.anon_height_scale = cam.anon_height_scale()
	facts.palm_scale_factor = cam.palm_scale_factor()
	facts.bob = cam.bob
	facts.back = cam.back
	facts.back_target = cam.back_target
	facts.forced_glance = session.forced_glance
	facts.bed_frame = pose_session.bed_frame
	var kiss: Variant = context.kiss
	if kiss != null:
		facts.kiss_amount = float(kiss.amount())
		facts.kiss_active = bool(kiss.leaning_close())
		facts.kiss_side = float(kiss.side())
	else:
		facts.kiss_amount = 0.0
		facts.kiss_active = false
		facts.kiss_side = 0.0


## Gather the HUD card's live values into the act view; `main.gd` calls it once per rendered frame
## just before the card updates, so the card reads fields instead of calling back.
func sync_hud(facts: ACT_FACTS, session: ACT_SESSION, max_climaxes: int,
		cycle_heat: bool, pose_family: String) -> void:
	var features: Dictionary = session.features if session.features is Dictionary else {}
	var summary: Dictionary = {}
	if context.summary != null and context.summary.summary is Dictionary:
		summary = context.summary.summary
	var afterglow: Variant = context.afterglow
	var anatomy: Variant = context.anatomy
	var readiness: Variant = context.readiness
	facts.max_pony_climaxes = max_climaxes
	facts.close_hint = close_hint(session, pose_family)
	facts.summary_hud = str(summary.get("hud", ""))
	facts.cycle_heat = cycle_heat
	facts.close_earned = bool(afterglow.close_caress_earned) if afterglow != null else false
	facts.hud_readouts = bool(features.get("hud_readouts", false))
	facts.hud_controls = bool(features.get("act_controls", false))
	facts.hole_ready = bool(anatomy.can_target_vulva()) if anatomy != null else false
	facts.oral_ready = bool(anatomy.can_target_mouth()) if anatomy != null else false
	facts.auto_on = bool(readiness.auto_active()) if readiness != null else false
	if facts.auto_on:
		facts.auto_min_depth = readiness.auto_min_depth()
		facts.auto_max_depth = readiness.auto_max_depth()
		facts.auto_pace = readiness.auto_pace()
		facts.auto_shape = readiness.auto_shape()
	facts.auto_layer_open = bool(readiness.auto_panel_open()) if readiness != null else false


## The standing close prompt, or "" outside the standing afterglow. The runtime passes its live pose
## family so the start-spec fallback stays the one source.
func close_hint(session: ACT_SESSION, pose_family: String) -> String:
	if session.state != State.AFTERGLOW or pose_family != "standing":
		return ""
	if context.afterglow == null:
		return ""
	return context.afterglow.hint()


func apply_live(session: ACT_SESSION) -> void:
	var settings: Variant = session.settings
	session.snapshot_settings()
	if settings.suspended():
		return
	if session.state == State.IDLE:
		refresh(context.facts, session)
		settings.apply_idle_live()
		return
	settings.apply_act_live_pre()
	refresh(context.facts, session)
	var live_preferences: Dictionary = settings.live_preferences(session.pony_id)
	if not live_preferences.is_empty():
		session.preferences = live_preferences
	settings.apply_act_live(session.pose_family())
	if is_instance_valid(context.hud):
		sync_hud(context.facts, session, settings.max_pony_climaxes, session.cycle_heat,
			session.pose_family())
		context.hud.update_from(context.facts)


func reset_act_state(session: ACT_SESSION) -> void:
	context.readiness.reset_thrust()
	context.readiness.reset_auto()
	context.readiness.reset(READINESS.Profile.from_dict(session.preferences))
	context.standing_anon.reset_phase()
	context.view.reset_depth()
	context.facts.standing_sway_offset = Vector3.ZERO
	context.afterglow.reset()
	context.dialogue.reset(session.clock_s(), session.cue_gap)
	session.settings.configure_dialogue()
	session.clear_phase()


func _face_values(session: ACT_SESSION) -> FACE.ActValues:
	var values := FACE.ActValues.new()
	values.state = session.state
	values.pony_id = session.pony_id
	values.event_id = session.event_id
	values.first_time = session.first_time
	values.tolerance = str(session.preferences.get("tolerance", "normal"))
	values.climax_mode = session.climax_mode
	values.summary = BEAT.Summary.from_dict(context.summary.summary)
	values.blush_arc = session.feature("blush_arc")
	return values


func face_beat(moment: String, session: ACT_SESSION) -> void:
	context.face.ensure_bound(host.pony, host.node)
	context.face.act_beat_for(moment, _face_values(session),
		session.settings.debug_face())


func face_rows(session: ACT_SESSION) -> Array[String]:
	context.face.ensure_bound(host.pony, host.node)
	return context.face.act_rows(_face_values(session))


func pose_render(_session: ACT_SESSION) -> void:
	var body_scale: Variant = host.pony.get("body_scale") if is_instance_valid(host.pony) else null
	context.pose.write_render_frame(float(body_scale) if body_scale != null else 1.0)


func camera_motion(session: ACT_SESSION) -> void:
	if context.handover != null and context.handover.suspended:
		return
	refresh(context.facts, session)
	sync_hud(context.facts, session, session.max_pony_climaxes, session.cycle_heat,
		session.pose_family())
	if context.camera.motion_ready():
		context.camera.apply_motion()


func prompt_note(session: ACT_SESSION) -> String:
	var form: Variant = context.handover.form()
	var values := DIALOGUE.ActValues.new()
	values.state = session.state
	values.pony_id = session.pony_id
	values.event_id = session.event_id
	values.warm = context.face.warm_note
	values.beat = context.afterglow.beat
	values.caressing = context.hands.any_active()
	values.leaning = context.camera.lean_forward >= 0.35 \
		or context.camera.lean_action_active or context.kiss.leaning_close()
	values.missionary = session.pose_family() == "bed"
	values.form_source = context.handover.source() != null
	values.form_name = form.form_name.strip_edges() if form != null else ""
	values.form_borrowed = form != null and not form.is_own()
	return context.dialogue.act_prompt(values)


func debug_context(session: ACT_SESSION) -> Dictionary:
	return DEBUG_PONY.context(host.pony, session.pony_id, {
		"state": session.state,
		"presenting": context.presentation.presentation_active(),
		"cuddle": context.gate.cuddle_active(),
		"max_pony_climaxes": session.max_pony_climaxes,
		"satisfaction": context.readiness.satisfaction,
		"pony_climaxes": context.readiness.pony_climaxes,
		"last_intensity": context.readiness.last_intensity,
		"last_pattern": context.readiness.last_pattern,
		"cue": context.readiness.cue,
		"thrust_up": context.readiness.up_is_deep,
		"penetration_m": context.readiness.penetration_m,
		"penetration_reach": context.readiness.reach(),
		"preferences": PREFERENCES.describe(session.preferences),
		"voice_status_line": VOICE.status_line(WORLD.director().voice_facts(session.pony_id,
			SETTINGS.tts_enabled())),
	}, context.world.act_gate)


func climax_line(session: ACT_SESSION) -> void:
	var live: Variant = context.pose.view()
	var mouth_busy := live != null and str(live.contact_kind) == "mouth"
	context.dialogue.climax_line(mouth_busy, context.readiness.cue, session.event_id,
		context.readiness.pony_climaxes, session.snapshot.cue_reaction_max_age_s)


func summary_input(session: ACT_SESSION) -> SUMMARY.ActInput:
	var values := SUMMARY.ActInput.new()
	values.pony_id = session.pony_id
	values.event_id = session.event_id
	values.preferences = session.preferences
	values.seconds = session.act_seconds()
	values.ended_early = session.ended_early
	values.stopped_by_her = session.stopped_by_her
	values.form_reveal = context.handover.reveal_done
	values.act_spoken_at = session.act_spoken_at
	return values
