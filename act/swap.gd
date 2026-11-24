extends "res://mods/unfplap/body_change/swap_port.gd"
## The act's body-swap seams: the watcher dispatch, the handover's ordered release and resume, and
## the form rebinds. The handover decides when; this is the typed bridge to the live systems, and
## the node keeps only the reparent.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
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
	context.face.bind(host.pony as Node3D, host.node)
	context.audio.rebind_body(host.pony, session.pony_id, session.bed)
	session.refresh_view()
	session.refresh_anatomy()
	context.reactions.bind_scene(host.pony as Node3D, _flank())
	var view := context.pose.view()
	context.hands.pose_changed(view)
	context.kiss.pose_changed(view)
	if context.audio != null and context.audio.has_method("pose_changed"):
		context.audio.pose_changed(view)


## The host's revised-form visual pass: the live shot state and the player frame.
func reset_visual_for_form() -> void:
	reset_visual(context.handover.form())


## Recompute the act's visual frame after a presented-form revision: the shot starts from rest and
## the player frame re-fits the new form.
func reset_visual(form: BODY_FORM.BodyForm) -> void:
	context.camera.reset_shot()
	context.camera.camera_basis_ready = false
	context.frame.refit(context.frame.pose_input(), form)
	session.refresh_view()


## The live standing gap for the offer and the suites. The frame owns the value.
func standing_gap(form: BODY_FORM.BodyForm = null) -> float:
	return context.frame.standing_gap(form)


func reset_pelvis() -> void:
	context.frame.reset_pelvis()


## A new body must still be an adult mare for the act to go on. A missing service reads as allowed,
## so a suite can drive the handover without the world's eligibility graph.
func new_body_is_adult() -> bool:
	return context.frame.new_body_is_adult()


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
	session.release_anatomy()


func release_scene() -> void:
	context.hold.release_nav()
	context.hold.restore_face_turn()


## The one pose ledger call, then the bone restore. This is the body-swap caller of the ledger.
func release_swap_pose() -> void:
	exit.free_pose()
	context.pose.restore_bones()


func restore_camera() -> void:
	if context.camera.camera_owned:
		context.camera.finish_act()
		session.refresh_view()


func stop_breath() -> void:
	context.audio.silence_breath()


## The adopted body's binding before the resume moves the act onto it.
func resume_body() -> void:
	context.face.bind(host.pony as Node3D, host.node)
	session.adopt_display_name(context.handover.form(), host.pony)
	session.refresh_view()
	if not is_instance_valid(host.pony):
		return
	host.pony.sleeping = false
	if host.pony.has_method("set_sim_tier"):
		host.pony.set_sim_tier(host.pony.SimTier.HERO)
	host.pony.set_meta("sex_active", true)


func prepare_anatomy_act() -> void:
	session.refresh_anatomy()
	var view := context.pose.view()
	if view == null:
		return
	var wrap := ANATOMY.PoseView.new()
	wrap.family = str(view.family)
	wrap.frame = str(view.frame)
	wrap.contact_kind = str(view.contact_kind)
	wrap.contact_target = view.contact_target if view.contact_target is Vector3 else Vector3.INF
	wrap.bed_frame = context.pose.view().bed_frame
	session.begin_anatomy(wrap)


func apply_resume_settings() -> void:
	session.preserve_auto_shape = true
	session.snapshot_settings()
	session.preserve_auto_shape = false


func rebind_reactions() -> void:
	context.reactions.bind_scene(host.pony as Node3D, _flank())
	context.reactions.apply_radius()


func set_act_pose_config() -> void:
	context.pose.set_pose_config(POSE_SESSION.SettingsBlock.from_dict(
		SETTINGS.pose(session.pony_id, session.start_group()).raw()))


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


func open_camera() -> void:
	if context.camera.begin_act(session.pose_family(), session.player_pony,
			WORLD.headset_view()):
		session.begin_vr()


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


func apply_pose_change() -> void:
	context.pose.pose_changed(context.pose.view())


## The flank the reactions facade jiggles and patches; resolved by the scene adapter.
func _flank() -> Node3D:
	if not is_instance_valid(host.pony):
		return null
	return host.pony.get_node_or_null("FlankTouch") as Node3D


func begin_integrations() -> void:
	context.integrations.begin()


func sync_hud() -> void:
	if is_instance_valid(context.hud):
		session.sync_hud()
		context.hud.update_from(context.facts)


func resume_auto() -> void:
	if context.handover.auto_on and session.state in [State.ACTIVE, State.CLIMAX]:
		context.readiness.toggle_auto(context.readiness.depth)
	context.handover.clear_auto()

