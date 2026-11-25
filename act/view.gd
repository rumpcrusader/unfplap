extends RefCounted
## The act view composition. It fills the typed read model (`shared/act_facts.gd`) from the
## session, the live systems and the plain act values, and gathers the HUD card's values. One per
## pony, bound once; the schedule and the act boundaries call it once per phase.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const FACE := preload("res://mods/unfplap/face/api.gd")
const BEAT := preload("res://mods/unfplap/shared/face_beat.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
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
	var readout := context.readiness.readout()
	facts.state = session.state
	facts.pose_view = pose_view
	facts.source = session.source
	facts.satisfaction = readout.satisfaction
	facts.mood = readout.mood
	facts.cue = readout.cue
	facts.form_hint = context.handover.form_hint()
	facts.pony_climaxes = readout.climaxes
	facts.depth = readout.depth
	facts.penetration_m = readout.penetration_m
	facts.pony = host.pony
	facts.camera = context.camera.camera
	facts.viewport = host.viewport()
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
	facts.seconds_since_stroke = readout.seconds_since_stroke
	facts.last_intensity = readout.last_intensity
	facts.last_pattern = readout.last_pattern
	facts.last_touch = readout.last_touch
	facts.last_talk = readout.last_talk
	facts.cue_override = readout.cue_override
	facts.thrust_pace = readout.rate
	# The pose view is the one contact source; the mouth/contact provider reads `contact_kind`.
	facts.penetration_reach = readout.reach_m
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
	facts.thrust_travel = readout.travel
	facts.same_height_scale = cam.same_height_scale()
	facts.anon_height_scale = cam.anon_height_scale()
	facts.palm_scale_factor = cam.palm_scale_factor()
	facts.bob = cam.bob
	facts.back = cam.back
	facts.back_target = cam.back_target
	facts.forced_glance = session.forced_glance


## Gather the HUD card's live values into the act view; `main.gd` calls it once per rendered frame
## just before the card updates, so the card reads fields instead of calling back.
func sync_hud(facts: ACT_FACTS, session: ACT_SESSION, max_climaxes: int,
		cycle_heat: bool, pose_family: String) -> void:
	var features: Dictionary = session.features if session.features is Dictionary else {}
	var summary: Dictionary = {}
	if session.act_score != null:
		summary = session.act_score.outcome
	var afterglow: Variant = context.afterglow
	var anatomy: Variant = context.anatomy
	facts.max_pony_climaxes = max_climaxes
	facts.close_hint = close_hint(session, pose_family)
	facts.summary_hud = str(summary.get("hud", ""))
	facts.cycle_heat = cycle_heat
	facts.close_earned = bool(afterglow.close_caress_earned) if afterglow != null else false
	facts.hud_readouts = bool(features.get("hud_readouts", false))
	facts.hud_controls = bool(features.get("act_controls", false))
	facts.hole_ready = bool(anatomy.can_target_vulva()) if anatomy != null else false
	facts.oral_ready = bool(anatomy.can_target_mouth()) if anatomy != null else false
	var auto: Variant = context.auto.readout() if context.auto != null else null
	facts.auto_on = auto != null and bool(auto.active)
	if facts.auto_on:
		facts.auto_min_depth = float(auto.min_depth)
		facts.auto_max_depth = float(auto.max_depth)
		facts.auto_pace = float(auto.pace)
		facts.auto_shape = str(auto.shape)
	facts.auto_layer_open = auto != null and bool(auto.panel_open)


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
	context.standing_anon.reset_phase()
	context.view.reset_depth()
	context.facts.standing_sway_offset = Vector3.ZERO
	context.afterglow.reset()
	context.dialogue.reset(session.clock_s(), session.cue_gap)
	session.settings.configure_dialogue()
	session.clear_phase()


func _face_values(session: ACT_SESSION) -> FACE.ActValues:
	var outcome: Dictionary = {}
	if session.act_score != null:
		outcome = session.act_score.outcome
	var values := FACE.ActValues.new()
	values.state = session.state
	values.pony_id = session.pony_id
	values.event_id = session.event_id
	values.first_time = session.first_time
	values.tolerance = str(session.preferences.get("tolerance", "normal"))
	values.climax_mode = session.climax_mode
	values.summary = BEAT.Summary.from_dict(outcome)
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
	context.view.write_eye()


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
		or context.camera.lean_action_active or bool(context.facts.kiss_active)
	values.missionary = session.pose_family() == "bed"
	values.form_source = context.handover.source() != null
	values.form_name = form.form_name.strip_edges() if form != null else ""
	values.form_borrowed = form != null and not form.is_own()
	return context.dialogue.act_prompt(values)


func debug_context(session: ACT_SESSION) -> Dictionary:
	var readout := context.readiness.readout()
	return DEBUG_PONY.context(host.pony, session.pony_id, {
		"state": session.state,
		"presenting": context.presentation.presentation_active(),
		"cuddle": context.gate.cuddle_active(),
		"max_pony_climaxes": session.max_pony_climaxes,
		"satisfaction": readout.satisfaction,
		"pony_climaxes": readout.climaxes,
		"last_intensity": readout.last_intensity,
		"last_pattern": readout.last_pattern,
		"cue": readout.cue,
		"thrust_up": readout.up_is_deep,
		"penetration_m": readout.penetration_m,
		"penetration_reach": readout.reach_m,
		"preferences": PREFERENCES.describe(session.preferences),
		"voice_status_line": VOICE.status_line(WORLD.director().voice_facts(session.pony_id,
			SETTINGS.tts_enabled())),
	}, context.world.act_gate)


func climax_line(session: ACT_SESSION) -> void:
	var live: Variant = context.pose.view()
	var mouth_busy := live != null and str(live.contact_kind) == "mouth"
	var readout := context.readiness.readout()
	context.dialogue.climax_line(mouth_busy, readout.cue, session.event_id, readout.climaxes,
		session.snapshot.cue_reaction_max_age_s)


## The one act snapshot the summary scores: her identity, the route that ended the act, the act's
## own values and one readiness read. It is built once, at the verdict, so nothing else names a
## counter.
func summary_snapshot(session: ACT_SESSION) -> SUMMARY.ActSnapshot:
	var ending := SUMMARY.ActSnapshot.Ending.COMPLETE
	if session.stopped_by_her:
		ending = SUMMARY.ActSnapshot.Ending.STOPPED
	elif session.ended_early:
		ending = SUMMARY.ActSnapshot.Ending.EARLY
	var out := SUMMARY.ActSnapshot.new(session.pony_id, session.event_id, ending)
	out.seconds = session.act_seconds()
	out.act_spoken_at = session.act_spoken_at
	out.preferences = session.preferences
	out.form_reveal = context.handover.reveal_done
	out.meter = context.readiness.take_meter()
	return out


## Her last spoken line and when, taken with the snapshot so the summary keeps the act's own timing.
func summary_exchange() -> SUMMARY.Exchange:
	return SUMMARY.Exchange.new(context.dialogue.last_spoken_at(),
		context.dialogue.last_spoken_line())
