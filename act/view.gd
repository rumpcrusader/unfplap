extends RefCounted
## The act view composition. It fills the typed read model (`shared/act_facts.gd`) from the
## session, the live systems and the plain act values, and gathers the HUD card's values. One per
## pony, bound once; the runtime calls it once per phase.
##
## See `docs/act_facts.md` and `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")

const State := ACT_STATE.State

var host: ACT_NODE = null
var context: ACT_CONTEXT = null


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Compose the view from the session and the live systems. The tick refreshes it once per phase:
## idle before the idle systems, physics after the pose tick and before the fan-out, render before
## the camera work, and the entry's `apply_camera_motion()` hand-off.
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
	facts.act_prompts = session.act_prompts
	facts.features = session.features
	facts.caress_quality = session.caress_quality
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
	facts.look_captured = cam.look_captured
	facts.look_yaw = cam.look_yaw
	facts.look_pitch = cam.look_pitch
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


## Gather the HUD card's live values into the act view. `main.gd` calls `apply_camera_motion()`
## once per rendered frame just before `hud.update_from()`, so the card reads fields instead of
## calling back into the runtime.
func sync_hud(facts: ACT_FACTS, session: ACT_SESSION, max_climaxes: int,
		cycle_heat: bool, pose_family: String) -> void:
	facts.max_pony_climaxes = max_climaxes
	facts.close_hint = close_hint(session, pose_family)
	facts.summary_hud = str(context.summary.summary.get("hud", ""))
	facts.cycle_heat = cycle_heat
	facts.close_earned = context.afterglow.close_caress_earned
	facts.hud_readouts = bool(session.features["hud_readouts"])
	facts.hud_controls = bool(session.features["act_controls"])
	facts.hole_ready = context.anatomy.hole_ready()
	facts.oral_ready = context.anatomy.oral_ready()
	facts.auto_on = context.readiness.auto_active()
	if facts.auto_on:
		facts.auto_min_depth = context.readiness.auto_min_depth()
		facts.auto_max_depth = context.readiness.auto_max_depth()
		facts.auto_pace = context.readiness.auto_pace()
		facts.auto_shape = context.readiness.auto_shape()
	facts.auto_layer_open = context.readiness.auto_panel_open()


## The standing close prompt, or "" outside the standing afterglow. The runtime passes its live pose
## family so the start-spec fallback stays the one source.
func close_hint(session: ACT_SESSION, pose_family: String) -> String:
	if session.state != State.AFTERGLOW or pose_family != "standing":
		return ""
	return context.afterglow.hint()
