extends RefCounted
## The act's one exit ledger. It gives back everything the act borrowed in the order the pose and
## camera were built; every step checks the ownership flag it restores, so a failed start runs the
## same body and restores only what it took. `run()` is the only scene-restoring teardown in the
## mod; this ledger's own routes and the consent stop are its only callers.
##
## See `docs/runtime.md` and `docs/poses.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")

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


## Give back everything the act borrowed, in the order the pose and camera were built. Every step
## checks its own ownership flag, so a start that failed early runs the same function and restores
## only what it took. Keep this the only teardown. The act's end lines are deliberately outside:
## `act/input.gd:cancel()` queues the early-stop reaction after the restore begins, and
## `finish_restore()` must
## not cut it. The utterance scheduler is start/finalize state, not a session borrow.
func run(rejoin_cuddle: bool) -> void:
	context.readiness.stop_auto()
	# A suspended act may end here (world close, a failed swap or an invalid body). Drop the
	# handover before the normal teardown; it is not a second exit path.
	context.handover.abort()
	context.handover.end_act()
	PONIES.clear_body_swap(host.node)
	# Capture the bed before the session state is cleared: a normal end of a bed missionary act
	# returns Anon and her to it, but only when it did not go badly.
	var rejoin_bed: Node3D = null
	var rejoin_serial := session.serial
	if rejoin_cuddle and _start_frame() == "bed" \
			and session.source in ["bed_side", "already_lying"] and not session.stopped_by_her \
			and _rejoin_wanted():
		rejoin_bed = session.bed
	# integration: close the anatomy act once, before the pose is freed.
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.end()
	# The oral turn's facing override must not outlive the act, even on a direct forced stop.
	context.standing_camera.reset_facing()
	if is_instance_valid(HUD.instance):
		HUD.instance.set_inventory_hidden(false)
	context.kiss.restore_forelegs()
	context.hold.restore_face_turn()
	context.camera.restore_eye_override()
	if is_instance_valid(host.pony):
		context.face.clear_face()
		context.face.end_face()
		context.wings.release()
	context.hold.unlock_player()
	if context.camera.camera_owned:
		context.camera.release_act_shot()
		session.refresh_view()
		context.camera.finish_act_shot()
	if context.stool != null:
		context.stool.call("release")
	if is_instance_valid(host.pony):
		host.pony.remove_meta("sex_active")
	# integration: hide the player part when the act ends.
	var anatomy_service: Variant = PONIES.anatomy
	if anatomy_service != null and anatomy_service.has_method("player_encounter"):
		anatomy_service.call("player_encounter", false)
	context.hold.release_nav()
	if context.camera.look_captured:
		context.camera.restore_look(session.start_family())
	if session.posture_owned:
		restore_posture(_start_frame(), rejoin_cuddle)
	free_pose()
	context.pose.restore_bones()
	context.audio.stop()
	if is_instance_valid(WORLD.game):
		if is_instance_valid(HUD.instance):
			HUD.instance.hide_all()
		PONIES.clear_active(host.node)
	session.finish_restore()
	session.pose_id = ""
	session.source = ""
	session.bed = null
	# integration: act-only anatomy hides immediately when the act ends.
	context.anatomy.apply_live()
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
## the act-scope releases between them, then the session's final pose clear. A later pose
## transition calls only the pose-scope steps; it never calls this function.
func free_pose() -> void:
	# A lost body must not reach the pose session's oral/face bindings.
	context.pose.bind(host.node, host.pony if is_instance_valid(host.pony) else null)
	context.pose.leave_pose_start()
	context.presentation.clear_presentation()
	context.camera.end_lean_action()
	context.hands.reset()
	context.kiss.reset()
	context.integrations.reset()
	context.audio.reset_excitement_hold()
	context.camera.release_free_camera_lock()
	context.standing_anon.remove()
	context.pose.leave_pose_body()
	context.audio.restore_voice_policy()
	context.reactions.end_act()
	context.pose.release_pose()


## The after-act. The order is the act exit's: the stroke state resets, the meter runs down, and
## the act ends in either the tail tuck after a partner stop or the aftercare beat. The afterglow
## facade owns the decisions and the values; this hosts the nodes.
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


## Give the bed back: restore the pre-act scene and stand her. A bed missionary act that ended well
## is re-seated and re-invited by `rejoin_bed_cuddle()` after the session is fully back to IDLE.
## A forced stop never reaches it; the world is going away or the pony is already invalid.
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
	return context.rest.rejoin_wanted({
		"serial": session.serial,
		"state": session.state,
		"player_pony": session.player_pony,
		"headset": WORLD.headset_view(),
		"summary": context.summary.summary,
		"satisfaction": context.readiness.satisfaction,
		"aftercare_min": session.aftercare_min,
	})


## Close the standing afterglow window and begin the one restore.
func end_afterglow() -> void:
	if session.state != State.AFTERGLOW:
		return
	host.log("afterglow end pony=%s" % host.pony_name())
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
	host.log("restore begin from state=%d pony=%s" % [session.state, host.pony_name()])
	session.begin_restore()
	context.handover.hint_tick()
	# integration: act-only anatomy hides as soon as the act starts restoring.
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.apply_live()
	context.face.clear_face()
	context.face.end_face()
	context.wings.release()
	var pose: Variant = context.pose.pose()
	if is_instance_valid(pose):
		pose.target_amount = 0.0
	context.pose.set_tail_target(0.0)
	context.audio.stop_breath()
	context.camera.release_back()
	context.standing_camera.reset_facing()
	if is_instance_valid(HUD.instance):
		HUD.instance.hide_act()


## The RESTORE timer's end: the normal act end, then the one finalize.
func finish_restore() -> void:
	if is_instance_valid(host.pony):
		host.log("restore finished pony=%s" % host.pony_name())
	else:
		host.log("restore finished with invalid pony")
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
	host.log("stop reason=%s state=%d pony=%s" % [reason, session.state, host.pony_name()])
	if session.state in [State.POSING_IN, State.ACTIVE, State.CLIMAX]:
		MEMORY.instance.note(MEMORY.NoteKind.STOPPED, session.pony_id, session.event_id,
			MEMORY.stop_reason(reason))
	restore_begin()
