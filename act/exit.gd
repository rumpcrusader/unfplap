extends RefCounted
## The act's one exit ledger: the returns run in the order the pose and camera were built, and an
## ownership flag decides what to restore, so a failed start restores only what it took.
##
## See `docs/runtime.md` and `docs/poses.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/service.gd")
const REST := preload("res://mods/unfplap/rest/service.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
## The start ledger owns the pose build's bone snapshot and its restore.
var start: RefCounted = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## The one teardown, in the order the pose and camera were built; each step restores only what its
## ownership flag says it took. End lines stay outside: `finish_restore()` must not cut them.
func run(rejoin_cuddle: bool) -> void:
	context.readiness.stop_auto()
	# A suspended act may end here (world close, a failed swap or an invalid body). Drop the
	# handover before the normal teardown; it is not a second exit path.
	context.handover.abort()
	context.handover.end_act()
	var owner: ACT_OWNER = context.world.act_owner if context.world != null else null
	if is_instance_valid(owner):
		owner.clear_body_swap(host.node)
	# Capture the bed before the session state is cleared: a normal end of a bed missionary act
	# returns Anon and her to it, but only when it did not go badly.
	var rejoin_bed: Node3D = null
	var rejoin_serial := session.serial
	if rejoin_cuddle and _start_frame() == "bed" \
			and session.source in ["bed_side", "already_lying"] and not session.stopped_by_her \
			and _rejoin_wanted():
		rejoin_bed = session.bed
	# integration: close the anatomy act once, before the pose is freed.
	session.release_anatomy()
	# The oral turn's facing override must not outlive the act, even on a direct forced stop.
	context.view.reset_facing()
	if is_instance_valid(context.hud):
		context.hud.set_inventory_hidden(false)
	context.kiss.restore_forelegs()
	context.hold.restore_face_turn()
	context.frame.end()
	context.view.unmount()
	if is_instance_valid(host.pony):
		context.face.clear_face()
		context.face.end_face()
		context.wings.release()
	context.hold.unlock_player()
	session.refresh_view()
	context.camera.finish_act()
	if context.stool != null:
		context.stool.release()
	if is_instance_valid(host.pony):
		host.pony.remove_meta("sex_active")
	context.hold.release_nav()
	if session.posture_owned:
		restore_posture(_start_frame(), rejoin_cuddle)
	free_pose()
	context.pose.restore_bones()
	context.audio.end_act()
	if is_instance_valid(WORLD.world_root()):
		if is_instance_valid(context.hud):
			context.hud.hide_all()
		if is_instance_valid(owner):
			owner.clear_active(host.node)
	session.finish_restore()
	session.pose_id = ""
	session.source = ""
	session.bed = null
	# Deferred so `finalize()` has started aftercare (and its navigator hold) first; the rejoin
	# retries until that hold and the bed's guest cooldown are gone.
	if rejoin_bed != null:
		rejoin_bed_cuddle.call_deferred(rejoin_bed, rejoin_serial)


## One-time bookkeeping after the borrowed state is back. Idempotent: a failed start has no act to
## reset and must not start aftercare.
func finalize(real_act: bool) -> void:
	if session.finalized:
		return
	session.finalized = true
	if real_act:
		reset_after_act()


## The one partial-start funnel: end the act's lines, run the one exit and finalize it as a
## failed start. A caller that returns false must come through here.
func abort() -> void:
	context.dialogue.end_act(session.event_id, true)
	run(false)
	finalize(false)


## The one pose teardown ledger: the pose-scope start and body steps at their current positions,
## the act-scope releases between them, then the session's final pose clear; never a transition.
func free_pose() -> void:
	# A lost body must not reach the pose session's oral/face bindings.
	context.pose.bind(host.node, host.pony if is_instance_valid(host.pony) else null)
	context.pose.leave_pose_start()
	context.presentation.clear_presentation()
	context.camera.end_lean_action()
	context.hands.reset()
	context.kiss.reset()
	context.integrations.reset()
	context.hold.release_all_beats()
	context.standing_anon.remove()
	context.pose.leave_pose_body()
	context.reactions.end_act()
	context.pose.release_pose()


## The after-act, in the act exit's order: the stroke state resets, the meter runs down, then the
## tail tuck after a partner stop or the aftercare beat. The afterglow facade owns the decisions.
func reset_after_act() -> void:
	if not is_instance_valid(host.node) or not host.node.is_inside_tree():
		return
	session.reset_thrust_state()
	context.afterglow.decay_satisfaction(context.readiness.satisfaction)
	var plan: AFTERGLOW.PostAct = context.afterglow.post_act(session.stopped_by_her,
		context.readiness.satisfaction, session.aftercare_min,
		not context.summary.summary.is_empty(),
		bool(context.summary.summary.get("positive", false)))
	if plan.tail_tuck:
		host.start_tail_tuck()
	elif is_instance_valid(host.pony) and context.afterglow.start_aftercare(host.pony, plan):
		context.face.ensure_bound(host.pony, host.node)
		context.face.start_post_act(plan.face_context(context.summary.summary))


## Give the bed back: restore the pre-act scene and stand her; a bed act that ended well is
## re-seated and re-invited by `rejoin_bed_cuddle()` once the session is back to IDLE.
func restore_posture(frame: String, rejoin_cuddle: bool) -> void:
	session.posture_owned = false
	context.rest.bind(host.pony, session.bed)
	context.rest.restore_posture(frame, rejoin_cuddle)


func rejoin_bed_cuddle(bed_node: Node3D, act_serial: int) -> void:
	context.rest.bind(host.pony, session.bed)
	await context.rest.rejoin_bed_cuddle(bed_node, act_serial)


## The start row's frame, read from the act's pose id. The pose row owns the frame name.
func _start_frame() -> String:
	return str(POSE_SPECS.spec(session.pose_id).get("frame", ""))


## The live act values the rejoin decides on, read fresh so an async path sees a new act or an
## ended session instead of the values from the call that started it.
func _rejoin_wanted() -> bool:
	context.rest.bind(host.pony, session.bed)
	return context.rest.rejoin_wanted(REST.Context.from_dict({
		"serial": session.serial,
		"state": session.state,
		"player_pony": session.player_pony,
		"headset": WORLD.headset_view(),
		"summary": context.summary.summary,
		"satisfaction": context.readiness.satisfaction,
		"aftercare_min": session.aftercare_min,
	}))


## Close the standing afterglow window and begin the one restore.
func end_afterglow() -> void:
	if session.state != State.AFTERGLOW:
		return
	LOG.debug("afterglow end pony=%s", [host.pony_name()])
	context.afterglow.cancel_close()
	restore_begin()


## Begin RESTORE: keep the peak memory, stop the act's work and hand the scene back to the pose's
## release. The state change is the session's; this is its side-effect ledger.
func restore_begin() -> void:
	if session.state == State.IDLE or session.state == State.RESTORE:
		return
	session.record_peak_memory()
	context.afterglow.cancel_close()
	context.readiness.stop_auto()
	context.dialogue.end_act(session.event_id, true)
	LOG.debug("restore begin from state=%d pony=%s", [session.state, host.pony_name()])
	session.begin_restore()
	context.handover.hint_tick()
	context.face.clear_face()
	context.face.end_face()
	context.wings.release()
	var pose: Variant = context.pose.pose()
	if is_instance_valid(pose):
		pose.target_amount = 0.0
	context.pose.set_tail_target(0.0)
	context.camera.release_back()
	context.view.reset_facing()
	if is_instance_valid(context.hud):
		context.hud.hide_act()


## The RESTORE timer's end: the normal act end, then the one finalize.
func finish_restore() -> void:
	if is_instance_valid(host.pony):
		LOG.debug("restore finished pony=%s", [host.pony_name()])
	else:
		LOG.debug("restore finished with invalid pony")
	run(true)
	finalize(true)


## End the act now without the normal afterglow or cuddle rejoin. Failure paths keep this route.
func restore_now() -> void:
	context.dialogue.end_act(session.event_id, true)
	run(false)
	finalize(true)


## The defensive stop every route must leave the quick slots in their pre-act state through.
func force_stop() -> void:
	if session.state == State.IDLE:
		run(false)
		return
	restore_now()


## A forced stop from a scene verdict. The gate returned the reason; this applies the one stop.
func stop(reason: String) -> void:
	LOG.debug("stop reason=%s state=%d pony=%s", [reason, session.state, host.pony_name()])
	if session.state in [State.POSING_IN, State.ACTIVE, State.CLIMAX] and context.memory != null:
		context.memory.note(MEMORY.NoteKind.STOPPED, session.pony_id, session.event_id,
			MEMORY.stop_reason(reason))
	restore_begin()
