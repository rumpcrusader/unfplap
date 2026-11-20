extends RefCounted
## The act's ordered start ledger: the presentation guard, the stool, the camera session, the
## borrows, the id/profile snapshot, the placement, the pose build and the act open, in that order.
## A failed step runs the one partial-start abort.
##
## See `docs/runtime.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_FRAME := preload("res://mods/unfplap/act/frame.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const ACT_SETUP := preload("res://mods/unfplap/act/setup.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
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
	_anatomy_refresh()
	if bool(POSE_SPECS.scene(pose).get("stool", false)):
		var stool_need := int(session.stool().call("needed_count")) \
			if session.stool() != null else 0
		if stool_need > 0:
			var stool_act: Variant = session.stool()
			if stool_act == null or int(stool_act.call("case_count")) < stool_need \
					or not bool(stool_act.call("take_items", stool_need)):
				LOG.debug("start blocked stool pose=%s pony=%s need=%d", [
					pose, host.pony_name(), stool_need])
				return false
	context.camera.begin_session(session.start_family())
	session.posture_owned = false
	session.finalized = false
	# Remove the idle standing presentation and its face before the act builds its own pose.
	context.presentation.clear_presentation()
	context.face.ensure_bound(host.pony, host.node)
	context.face.end_mood_face()
	context.face.end_face()
	session.pose_id = pose
	session.source = act_source
	session.profile = SETTINGS.template_for(session.pony_id)
	context.pose.set_pose_config(SETTINGS.pose(session.pony_id, session.start_group()))
	session.preferences = SETTINGS.preferences(session.pony_id)
	session.act_prompts = session.profile.get("act_prompts", {})
	session.snapshot_settings()
	context.reactions.apply_radius()
	session.aftercare_min = int(session.profile["aftercare_min"])
	session.cue_gap = SETTINGS.cue_gap_value(float(session.profile["cue_gap"]))
	context.standing_camera.reset()
	session.bed = context.gate.resolve_bed(pose, act_source, bed_in)
	if bool(POSE_SPECS.scene(pose).get("requires_bed", false)) and session.bed == null:
		# Nothing else is borrowed yet, but the jiggle radius was just applied.
		context.reactions.restore_radius()
		session.pose_id = ""
		session.source = ""
		session.bed = null
		return false
	session.player_pony = PLAYER_FORM.is_pony(PLAYER_FORM.active(host.tree()))
	context.wings.reset()
	session.reset_act()
	context.reactions.begin_act()
	context.camera.reset_lean_state()
	context.face.clear_face()
	context.face.set_face(0.45, context.face.ACT_LIDS)
	session.serial = PONIES.allocate_serial()
	session.event_id = "intimacy_%s_%d" % [session.pony_id, session.serial]
	session.first_time = MEMORY.instance.first_time(session.pony_id, session.event_id)
	context.readiness.satisfaction = 0.0
	context.readiness.mood = "warming"
	context.readiness.cue = ""
	session.reset_thrust_state()
	session.stopped_by_her = false
	context.consent.reset()
	context.handover.reset_act()
	host.end_tail_tuck()
	context.summary.reset_act()
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
	# integration: build the per-act anatomy controller before the pose reads its config.
	_anatomy_refresh()
	_anatomy_act_refresh()

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
	if session.start_group() == "missionary":
		context.pose.sync_missionary_config()
	context.camera.reset_lean_state()
	if session.start_family() == "bed":
		context.missionary_camera.prepare()
	context.hold.lock_player()
	context.hold.pause_face_turn(false)
	if context.camera.begin_act_shot(session.start_family(), session.player_pony, WORLD.headset_view()):
		context.anatomy.bind(context.anatomy_host)
		context.anatomy.vr_start()
	context.audio.start(host.pony, session.pony_id, session.bed)
	context.audio.apply_voice_policy(session.feature("mute_ponese_audio"), host.pony, session.pony_id)
	if is_instance_valid(HUD.instance):
		HUD.instance.set_inventory_hidden(true)
	# integration: show the player part for the encounter.
	var service: Variant = PONIES.anatomy
	if service != null and service.has_method("player_encounter"):
		service.call("player_encounter", true)
	session.begin_pose_in()
	view.refresh(context.facts, session)
	# The pose session installs the act body and reconciles the modifiers for the start view,
	# before the first rendered frame; every later change arrives through the pose fan-out.
	context.pose.pose_changed(context.pose.view())
	context.integrations.begin()
	session.face_beat("start")
	# integration: act-only visibility updates at the state change, not on the next poll.
	context.anatomy.apply_live()
	PONIES.set_active(host.node)
	if is_instance_valid(HUD.instance):
		session.sync_hud()
		HUD.instance.show_act(context.facts)
		HUD.instance.hide_prompt()
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
	exit.free_pose()
	var camera: Camera3D = WORLD.camera()
	var look: Vector3 = host.pony.global_position
	var camera_at := Vector3.INF
	if camera is Camera3D:
		look = camera.global_position
		camera_at = look
	context.pose.begin_act(session.pose_values(session.pose_id, look, camera_at,
		context.camera.size_name()))
	context.reactions.bind_tail(context.pose.tail)


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


func _anatomy_refresh() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.refresh()


func _anatomy_act_refresh() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.begin_act()
