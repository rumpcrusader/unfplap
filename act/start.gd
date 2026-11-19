extends RefCounted
## The act's ordered start ledger. One recipe: the presentation guard, the stool, the camera
## session, the borrows, the id/profile snapshot, the placement, the pose build and the act open,
## in that order. A failed step runs the one partial-start abort and restores only what the act
## took.
##
## See `docs/runtime.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_EXIT := preload("res://mods/unfplap/act/exit.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
var exit: ACT_EXIT = null
var view: ACT_VIEW = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		exit_in: ACT_EXIT, view_in: ACT_VIEW) -> void:
	host = host_in
	context = context_in
	session = session_in
	exit = exit_in
	view = view_in


## The shared start body after every gate. The act key's policy path and the scene-only
## Agreement path both land here; the one teardown still owns every failure.
func run(pose: String, bed_in: Variant, act_source: String, skip_presentation := false) -> bool:
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		host.log("start blocked presentation turn pose=%s source=%s pony=%s" % [
			pose, act_source, _pony_name()])
		return false
	_reset_stool_state()
	_anatomy_refresh()
	if bool(POSE_SPECS.scene(pose).get("stool", false)):
		var stool_need := int(stool().call("needed_count")) if stool() != null else 0
		if stool_need > 0:
			var stool_act: Variant = stool()
			if stool_act == null or int(stool_act.call("case_count")) < stool_need \
					or not bool(stool_act.call("take_items", stool_need)):
				host.log("start blocked stool pose=%s pony=%s need=%d" % [
					pose, _pony_name(), stool_need])
				return false
	context.camera.begin_session(session.start_family())
	session.posture_owned = false
	session.finalized = false
	# Remove the idle standing presentation and its face before the act builds its own pose.
	context.presentation.clear_presentation()
	context.face.ensure_bound(host.pony, host.node)
	context.face.end_mood_face()
	session.end_act_face()
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
	context.camera.apply_eye_override(session.start_family(), session.player_pony, context.handover.form())
	context.wings.reset()
	session.reset_act()
	context.reactions.begin_act()
	context.camera.reset_lean_state()
	session.clear_face()
	session.set_face(0.45, context.face.ACT_LIDS)
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
	session.remember_talk_turn()
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
	var setup := POSE_SPECS.start_setup(pose)
	if not _run_start_setup(setup):
		abort()
		return false

	_build_pose()
	context.reactions.clear_stock_marks()
	if session.start_group() == "missionary":
		context.pose.sync_missionary_config()
	context.camera.reset_lean_state()
	var camera_row: Variant = session.start_row().get("camera", {})
	if camera_row is Dictionary and str((camera_row as Dictionary).get("profile", "")) == "missionary_shots":
		context.missionary_camera.prepare()
	context.camera.capture_look()
	context.hold.lock_player()
	context.hold.pause_face_turn(false)
	if context.camera.begin_act_shot(session.start_family(), session.player_pony, WORLD.headset_view()):
		context.anatomy.bind(context.anatomy_host)
		context.anatomy.vr_start()
	context.missionary_camera.hide_avatar()
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
	host.log("started pose=%s setup=%s source=%s pony=%s eye=%.2f" % [
		pose, setup, act_source, _pony_name(), context.camera.camera_target_eye])
	return true


## The one partial-start funnel: end the act's lines, run the one exit and finalize it as a
## failed start.
func abort() -> void:
	exit.abort()


## The new-act prep: run the one pose teardown first so a pose left from the offer cannot stack,
## then build the act's pose from the session's typed values.
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


## Dispatch the spec's closed `start.setup` vocabulary to its placement adapter. It never selects
## on a pose id: a new pose row adds its setup name and data, not a branch here. A missing or
## unknown name is a data error after the gate passed; `run()` aborts the partial act.
func _run_start_setup(setup: String) -> bool:
	match setup:
		"bed_stand_up":
			return _start_bed_stand_up()
		"bed_keep_lying":
			return _start_bed_keep_lying()
		"standing_place":
			return _start_standing_place()
		_:
			host.log("start blocked setup=%s source=%s pony=%s" % [
				setup if not setup.is_empty() else "missing", session.source, _pony_name()])
			return false


## The bed stand-up start: Anon leaves the mattress before the player snapshot and the lock, and
## she leaves the game's lying state. The bed rest/cradle release already ran in the common
## prelude; the authored body owns her pose from here.
func _start_bed_stand_up() -> bool:
	if session.bed == null:
		return false
	if not session.player_pony:
		var body: Variant = WORLD.player
		if body != null and body.has_method("force_stand_up"):
			body.call("force_stand_up")
	if session.source == "cradle":
		context.rest.bind(host.pony, session.bed)
		context.rest.place_on_start()
	else:
		host.pony.reset_physics_interpolation()
	if host.pony.get("posture") != null:
		host.pony.request_posture("stand")
	return true


## The bed lying start: Anon does not stand up, and the authored act body takes over her pose.
## The riding pose is the first intended consumer; no shipped row uses this setup yet.
func _start_bed_keep_lying() -> bool:
	if session.bed == null:
		return false
	if session.source == "dialogue" and not REST.release_managed(host.pony):
		return false
	host.pony.reset_physics_interpolation()
	if host.pony.get("posture") != null:
		host.pony.request_posture("stand")
	return true


## The standing start: keep her where she stands, place Anon behind her at the act gap, take the
## stool items and start the facing lock.
func _start_standing_place() -> bool:
	context.placement.bind_act(session.placement_values())
	var standing: Transform3D = context.placement.begin_act()
	var stool_act: Variant = stool()
	if stool_act != null and bool(stool_act.call("has_failed")):
		return false
	host.pony.request_posture("stand")
	view.refresh(context.facts, session)
	context.standing_camera.begin_facing(standing)
	return true


## This act's footstool handle: the case loans, the placed stack and the player lift. The start
## binds it before the first stool question; the exit releases the same handle.
func stool() -> Variant:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(host.pony):
		return null
	var service: Variant = STOOL.instance
	if service == null or not service.has_method("new_act"):
		return null
	if context.stool == null:
		context.stool = service.call("new_act")
		context.stool.log = Callable(host, "log")
	context.stool.call("bind", service, host.pony, WORLD.player, context.anatomy.controller)
	return context.stool


## Remove the act prop and put every case item back. Every exit path releases it.
func release_stool() -> void:
	var act: Variant = stool()
	if act != null:
		act.call("release")


func _reset_stool_state() -> void:
	var act: Variant = stool()
	if act != null:
		act.call("reset")


func _claim_nav() -> bool:
	if context.hold.holds_negotiation():
		return context.hold.adopt_hold()
	return context.hold.claim_nav(session.pony_id)


func _anatomy_refresh() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.refresh()


func _anatomy_act_refresh() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.begin_act()


func _pony_name() -> String:
	return str(host.pony.name) if is_instance_valid(host.pony) else "?"


## The Agreement start's answer: a transient row or an unsettled presentation keeps waiting; a
## technical rollback is a start failure.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1
const AGREEMENT_FAILED := 2


## The scene-only Agreement start. Negotiation froze the policy and the pose capability; only the
## world rows run. `WAIT` keeps the Agreement live; `STARTED` and `FAILED` are reported by the offer.
func start_agreement(handle: Variant, skip_presentation := false) -> int:
	if handle == null or not bool(handle.call("valid")):
		return AGREEMENT_FAILED
	var option: Variant = handle.get("option")
	if option == null:
		return AGREEMENT_FAILED
	session.refresh_identity()
	var pose := str(option.pose)
	var act_source := str(option.source)
	var verdict: Variant = context.gate.scene_only_verdict(pose, act_source, option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.hard_ok):
		host.log("agreement start blocked pose=%s source=%s pony=%s reasons=%s" % [
			pose, act_source, _pony_name(),
			"none" if verdict == null else ",".join(verdict.reasons)])
		return AGREEMENT_FAILED
	if not bool(verdict.ok):
		host.log("agreement start waiting pose=%s source=%s transient=%s" % [
			pose, act_source, ",".join(verdict.transient)])
		return AGREEMENT_WAIT
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		host.log("agreement start waiting pose=%s source=%s presentation" % [pose, act_source])
		return AGREEMENT_WAIT
	_clear_aftercare()
	var started := run(pose, option.bed, act_source, skip_presentation)
	host.log("agreement start %s pose=%s source=%s" % [
		"started" if started else "failed", pose, act_source])
	return AGREEMENT_STARTED if started else AGREEMENT_FAILED


## True when the scene-only rows pass and, for a standing option, the presentation is settled.
func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	if handle == null or not bool(handle.call("valid")):
		return false
	var option: Variant = handle.option
	if option == null:
		return false
	session.refresh_identity()
	var pose := str(option.pose)
	var verdict: Variant = context.gate.scene_only_verdict(pose, str(option.source), option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.ok):
		return false
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		return false
	return true


## The hotkey's readiness: the scene-only rows plus Base clearance. The act key never bucks.
func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	session.refresh_identity()
	var stool_act: Variant = stool()
	var pair := Vector2i(-1, -1)
	if stool_act != null:
		pair = stool_act.call("hotkey_pair", pose)
	var started := Time.get_ticks_usec()
	var allowed: bool = context.gate.hotkey_ready(pose, act_source, bed_in, pair)
	host.perf_note("offer_rows", Time.get_ticks_usec() - started)
	return allowed


## The footstool pair this call's gate used, so the blocked standing note does not repeat the
## reach and case reads.
func hint_stool() -> Dictionary:
	var stool_act: Variant = stool()
	if stool_act == null:
		return {"need": 0, "have": 0}
	return stool_act.call("hint_pair")


## The act key's immediate attempt, with no Agreement and no presentation wait.
func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	if not hotkey_ready(pose, act_source, bed_in):
		host.log("hotkey blocked pose=%s source=%s pony=%s" % [pose, act_source, _pony_name()])
		return false
	_clear_aftercare()
	var started := run(pose, bed_in, act_source, skip_presentation)
	host.log("hotkey start %s pose=%s source=%s" % [
		"started" if started else "failed", pose, act_source])
	return started


## Clear the visual aftercare before a new start: the face and tail state, the meta and the
## aftercare navigator lease.
func _clear_aftercare() -> void:
	context.afterglow.clear_post_act(host.pony if is_instance_valid(host.pony) else null)
