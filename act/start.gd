extends RefCounted
## The act's ordered start ledger: the presentation guard, the stool, the camera session, the
## borrows, the id/profile snapshot, the placement, the pose build and the act open, in that order.
## A failed step runs the one partial-start abort.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FRAME := preload("res://mods/unfplap/act/frame.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const ACT_SETUP := preload("res://mods/unfplap/act/setup.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/api.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
var exit: ACT_EXIT = null
var view: ACT_VIEW = null
## The closed start.setup adapters. A leaf: the ledger owns the order, this owns the scene moves.
var setup: ACT_SETUP = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		exit_in: ACT_EXIT, view_in: ACT_VIEW) -> void:
	host = host_in
	context = context_in
	session = session_in
	exit = exit_in
	view = view_in
	setup = ACT_SETUP.new()
	setup.bind(host, context, session, view)


## The shared start body after every gate. The act key's policy path and the scene-only
## Agreement path both land here; the one teardown still owns every failure.
func run(pose: String, bed_in: Variant, act_source: String, skip_presentation := false) -> bool:
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		LOG.debug("start blocked presentation turn pose=%s source=%s pony=%s", [
			pose, act_source, host.pony_name()])
		return false
	session.reset_stool_state()
	session.refresh_anatomy()
	if bool(POSE_SPECS.scene(pose).get("stool", false)):
		var stool_act := session.stool()
		var stool_need := stool_act.needed_count() if stool_act != null else 0
		if stool_need > 0:
			if stool_act == null or stool_act.case_count() < stool_need \
					or not stool_act.take_items(stool_need):
				LOG.debug("start blocked stool pose=%s pony=%s need=%d", [
					pose, host.pony_name(), stool_need])
				return false
	session.posture_owned = false
	session.finalized = false
	# Remove the idle standing presentation and its face before the act builds its own pose.
	context.presentation.clear_presentation()
	context.face.ensure_bound(host.pony, host.node)
	context.face.end_mood_face()
	context.face.end_face()
	session.pose_id = pose
	session.source = act_source
	session.profile = SETTINGS.template_for(session.pony_id).raw()
	session.preferences = SETTINGS.preferences(session.pony_id).raw()
	session.snapshot_settings()
	context.reactions.apply_radius()
	session.aftercare_min = int(session.profile["aftercare_min"])
	session.cue_gap = SETTINGS.cue_gap_value(float(session.profile["cue_gap"]))
	context.view.reset()
	session.bed = context.gate.resolve_bed(pose, act_source, bed_in)
	if bool(POSE_SPECS.scene(pose).get("requires_bed", false)) and session.bed == null:
		# Nothing else is borrowed yet, but the jiggle radius was just applied.
		context.reactions.restore_radius()
		session.pose_id = ""
		session.source = ""
		session.bed = null
		return false
	session.player_pony = WORLD.anon().form_is_pony()
	context.wings.reset()
	session.reset_act()
	context.reactions.begin_act()
	context.camera.reset_lean_state()
	context.face.clear_face()
	context.face.set_face(0.45, context.face.ACT_LIDS)
	var owner: ACT_OWNER = context.world.act_owner if context.world != null else null
	session.serial = owner.allocate_serial() if is_instance_valid(owner) else 0
	session.event_id = "intimacy_%s_%d" % [session.pony_id, session.serial]
	session.first_time = context.memory.first_time(session.pony_id, session.event_id) \
		if context.memory != null else false
	context.readiness.satisfaction = 0.0
	context.readiness.mood = "warming"
	context.readiness.cue = ""
	session.reset_thrust_state()
	session.stopped_by_her = false
	context.consent.reset()
	context.handover.reset_act()
	host.end_tail_tuck()
	context.dialogue.prepare_vocal(session.pony_id)
	context.afterglow.stop_decay()
	_remember_talk_turn()
	session.act_spoken_at = context.dialogue.last_spoken_at()
	if session.source == "cradle":
		if not context.hold.release_carry():
			abort()
			return false
	elif session.source == "already_lying":
		if not REST.release_managed(host.pony):
			abort()
			return false
	elif session.source == "bed_side":
		context.hold.end_cuddle()
		if not REST.release_managed(host.pony):
			abort()
			return false
	if context.gate.cuddle_active() and session.source not in ["bed_side", "already_lying"]:
		context.hold.end_cuddle()
		REST.release_managed(host.pony)
	if not _claim_nav():
		abort()
		return false

	context.pose.snapshot_bones()
	session.posture_owned = true
	var body: Variant = host.pony
	body.sleeping = false
	body.set_sim_tier(body.SimTier.HERO)
	body.set_meta("sex_active", true)
	# integration: build the per-act anatomy handle before the pose reads its config.
	session.refresh_anatomy()
	_begin_anatomy(pose)

	# The act is its own state for both of them: the setup adapter places the bodies before the
	# snapshot and the lock. The bed only supplies the frame their bodies are placed in.
	var setup_name := POSE_SPECS.start_setup(pose)
	if not setup.run(setup_name):
		abort()
		return false

	_build_pose()
	var frame_plan: Variant = context.frame.begin(context.frame.pose_input())
	if frame_plan == null or not bool(frame_plan.valid):
		abort()
		return false
	session.refresh_view()
	context.reactions.clear_stock_marks()
	context.camera.reset_lean_state()
	if session.start_family() == "bed":
		context.view.mount()
	context.hold.lock_player()
	context.hold.pause_face_turn(false)
	if context.camera.begin_act(session.start_family(), session.player_pony, WORLD.headset_view()):
		session.begin_vr()
	context.audio.begin_act(host.pony, session.pony_id, session.bed)
	if is_instance_valid(context.hud):
		context.hud.set_inventory_hidden(true)
	session.begin_pose_in()
	view.refresh(context.facts, session)
	# The pose session installs the act body and reconciles the modifiers for the start view,
	# before the first rendered frame; every later change arrives through the pose fan-out.
	context.pose.pose_changed()
	context.integrations.begin()
	session.face_beat("start")
	if is_instance_valid(owner):
		owner.set_active(host.node)
	host.runtime().emit_signal("act_started", host.pony)
	if is_instance_valid(context.hud):
		session.sync_hud()
		context.hud.show_act(context.facts)
		context.hud.hide_prompt()
	LOG.debug("started pose=%s setup=%s source=%s pony=%s eye=%.2f", [
		pose, setup_name, act_source, host.pony_name(),
		float(frame_plan.eye) if frame_plan != null else 0.0])
	return true


## The one partial-start funnel: end the act's lines, run the one exit and finalize it as a
## failed start.
func abort() -> void:
	exit.abort()


## The new-act prep: the pose teardown runs first, so an offer's leftover pose cannot stack, then
## the act's pose is built from the session's typed values.
func _build_pose() -> void:
	# The session reads the pony, id, bed and features from the facts; a start refreshes them first.
	session.refresh_view()
	exit.free_pose()
	var camera: Camera3D = WORLD.camera()
	var look: Vector3 = host.pony.global_position
	var camera_at := Vector3.INF
	if camera is Camera3D:
		look = camera.global_position
		camera_at = look
	context.pose.begin_act(session.pose_start(session.pose_id, look, camera_at))
	context.reactions.bind_tail(context.pose.tail())


func _claim_nav() -> bool:
	if context.hold.holds_negotiation():
		return context.hold.adopt_hold()
	return context.hold.claim_nav(session.pony_id)


## The start's one talk-turn reset: readiness and the handover keep their own last-turn state.
func _remember_talk_turn() -> void:
	var tree: SceneTree = host.tree()
	var director: Node = tree.get_first_node_in_group("conversation_director") \
		if tree != null else null
	context.readiness.remember_talk_turn(director)
	context.handover.remember_talk_turn(director)


func _begin_anatomy(pose: String) -> void:
	if context.world.anatomy == null:
		return
	var view := ANATOMY.PoseView.new()
	view.family = session.start_family()
	view.frame = str(POSE_SPECS.spec(pose).get("frame", ""))
	view.contact_kind = "opening"
	view.contact_target = Vector3.INF
	view.bed_frame = context.pose.view().bed_frame
	session.begin_anatomy(view)
