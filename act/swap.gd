extends RefCounted
## The act's body-swap seams: the watcher dispatch, the handover's ordered release and resume, and
## the form rebinds. The handover decides when; this is the typed bridge to the live systems, and
## the node keeps only the reparent.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
## The one exit: a failed resume or a mid-restore change ends the act through its route.
var exit: Variant = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## One handover action. The handover decides when and executes the ordered release, the adoption
## and the one resume; this applies each verdict and ends a failed swap through the one exit.
func tick(delta: float) -> void:
	var action := context.handover.tick(delta)
	if action == BODY_CHANGE_ACT.Action.SUSPEND:
		context.handover.release(context.handover.candidate)
	elif action == BODY_CHANGE_ACT.Action.RESUME:
		resume()
	elif action == BODY_CHANGE_ACT.Action.FAIL:
		LOG.debug("body swap failed: %s", [context.handover.fail_reason])
		exit.force_stop()
	elif action == BODY_CHANGE_ACT.Action.END_RESTORE:
		exit.force_stop()


## The watcher's suspend action, for the suite seam and the handover's own candidate.
func suspend(change: BODY_CHANGE) -> void:
	context.handover.release(change)


## The one resume; the handover owns the rebuild and a no-body failure leaves by the exit route.
## The suspended flag is read before the handover clears it.
func resume() -> void:
	var was_suspended := context.handover.suspended
	if context.handover.resume():
		return
	if was_suspended:
		exit.force_stop()


## One revised form's rebind for a presented body: every body-bound system in its order.
func rebind_body() -> void:
	var form := context.handover.form()
	session.adopt_display_name(form, host.pony)
	session.refresh_gate()
	context.pose.bind(host.node, host.pony)
	context.face.bind(host.pony, host.node)
	context.audio.bind_identity(host.pony, session.pony_id, session.bed)
	session.refresh_view()
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.refresh()
	context.reactions.bind_scene(host.pony, context.anatomy.controller)
	var view: Variant = context.pose.view()
	for owner: Variant in [context.hands, context.kiss, context.audio]:
		if owner != null and owner.has_method("pose_changed"):
			owner.call("pose_changed", view)


## The host's revised-form visual pass: the camera frame and the standing placement.
func reset_visual_for_form() -> void:
	reset_visual(context.handover.form())


## Recompute the act's visual frame after a presented-form revision. The camera's old offset is
## undone before the new form is measured, then the player frame is re-fitted.
func reset_visual(form: BODY_FORM.BodyForm) -> void:
	context.camera.reset_for_form(session.start_family())
	context.frame.refit(context.frame.pose_input(), form)
	session.refresh_view()


## Bind the placement handle's act values, then place, re-anchor or measure from them. The
## placement handle owns the math; the act session owns the values.
func bind_placement(form: BODY_FORM.BodyForm = null) -> void:
	context.placement.bind_act(session.placement_values(form))


## The live standing gap for the offer and the suites. The placement handle owns the value.
func standing_gap(form: BODY_FORM.BodyForm = null) -> float:
	bind_placement(form)
	return context.placement.gap_act()


## A standing act places Anon at the body's gap. A different body form needs that pass again; the
## bed act keeps him where he is and its authored shot re-reads the live body scale.
func reanchor(form: BODY_FORM.BodyForm = null) -> void:
	bind_placement(form)
	var standing: Variant = context.placement.reanchor_act(session.pose_family())
	if standing is Transform3D:
		context.standing_camera.begin_facing(standing)


func reset_pelvis() -> void:
	bind_placement()
	context.placement.reset_pelvis_act()


## A new body must still be an adult mare for the act to go on. A missing service reads as allowed,
## so a suite can drive the handover without the world's eligibility graph.
func new_body_is_adult() -> bool:
	bind_placement()
	return context.placement.new_body_is_adult_act()


## The adopted body failed the act's adult-mare gate: log it and leave through the one exit.
func end_non_adult(body: Node) -> void:
	LOG.debug("body swap ended: the new body is not an adult mare pony=%s", [str(body.name)])
	session.force_stop()


## The swap's ordered release steps the handover calls.
func attach_to_world() -> void:
	host.attach_to_world()


func release_carry() -> bool:
	return context.hold.release_carry()


func release_contacts() -> void:
	context.kiss.reset()
	context.hands.reset()


func remember_auto() -> void:
	context.handover.remember_auto(context.readiness.auto_active())
	context.readiness.stop_auto()


func release_act_body() -> void:
	context.wings.release()
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.end()


func release_scene() -> void:
	context.hold.release_nav()
	context.hold.restore_face_turn()


## The one pose ledger call, then the bone restore. This is the body-swap caller of the ledger.
func release_pose() -> void:
	exit.free_pose()
	context.pose.restore_bones()


func restore_camera() -> void:
	if context.camera.camera_owned:
		context.camera.release_act_shot()
		session.refresh_view()
		context.camera.finish_act_shot()


func stop_breath() -> void:
	context.audio.stop_breath()


## The adopted body's binding before the resume moves the act onto it.
func resume_body() -> void:
	context.pose.bind(host.node, host.pony)
	context.face.bind(host.pony, host.node)
	session.adopt_display_name(context.handover.form(), host.pony)
	session.refresh_view()
	if not is_instance_valid(host.pony):
		return
	host.pony.sleeping = false
	if host.pony.has_method("set_sim_tier"):
		host.pony.set_sim_tier(host.pony.SimTier.HERO)
	host.pony.set_meta("sex_active", true)


func prepare_anatomy_act() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.refresh()
	context.anatomy.begin_act()


func apply_resume_settings() -> void:
	session.preserve_auto_shape = true
	session.snapshot_settings()
	session.preserve_auto_shape = false


func rebind_reactions() -> void:
	context.reactions.bind_scene(host.pony, context.anatomy.controller)
	context.reactions.apply_radius()


func set_act_pose_config() -> void:
	context.pose.set_pose_config(SETTINGS.pose(session.pony_id, session.start_group()))


## Rebuild the live pose against the new skeleton, keeping the pose the act was already in; the
## start ramp is skipped because the act is continuing, not entering.
func rebuild_act_pose() -> void:
	context.pose.snapshot_bones()
	var camera: Camera3D = WORLD.camera()
	var look: Vector3 = host.pony.global_position
	var camera_at := Vector3.INF
	if camera is Camera3D:
		look = (camera as Camera3D).global_position
		camera_at = look
	var values := session.pose_values(context.handover.pose, look, camera_at,
		context.camera.size_name())
	if not context.pose.rebuild_act(values):
		LOG.debug("body swap: the new body has no pose skeleton")
		return
	context.reactions.bind_tail(context.pose.tail)


func sync_start_config() -> void:
	context.pose.sync_start_config(session.start_group())


func reset_lean() -> void:
	context.camera.reset_lean_state()


func prepare_start_camera() -> void:
	var camera_row: Variant = session.start_row().get("camera", {})
	var profile := str((camera_row as Dictionary).get("profile", "")) \
		if camera_row is Dictionary else ""
	context.camera.prepare_start(profile)


func open_camera() -> void:
	if context.camera.begin_act_shot(session.pose_family(), session.player_pony,
			WORLD.headset_view()):
		context.anatomy.bind(context.anatomy_host)
		context.anatomy.vr_start()


func reset_wings() -> void:
	context.wings.reset()


func claim_nav() -> void:
	if context.hold.holds_negotiation():
		context.hold.adopt_hold()
	else:
		context.hold.claim_nav(session.pony_id)


func pause_face_turn() -> void:
	context.hold.pause_face_turn(true)


func reset_face() -> void:
	context.face.clear_face()
	context.face.set_face(0.45, context.face.ACT_LIDS)


func apply_voice_policy() -> void:
	context.audio.apply_voice_policy(session.feature("mute_ponese_audio"), host.pony,
		session.pony_id)


func apply_pose_change() -> void:
	context.pose.pose_changed(context.pose.view())


func apply_anatomy_live() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.apply_live()


func begin_integrations() -> void:
	context.integrations.begin()


func sync_hud() -> void:
	if is_instance_valid(HUD.instance):
		session.sync_hud()
		HUD.instance.update_from(context.facts)


func resume_auto() -> void:
	if context.handover.auto_on and session.state in [State.ACTIVE, State.CLIMAX]:
		context.readiness.toggle_auto(context.readiness.depth)
	context.handover.clear_auto()


func prepare_standing_camera() -> void:
	if session.pose_family() == "standing":
		context.standing_camera.prepare()
