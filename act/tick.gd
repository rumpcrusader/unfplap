extends RefCounted
## The act's ordered frame schedule. The runtime node's `_physics_process` and `_process` forward
## here; this module owns the order, the chunk names and the one pose fan-out, and calls each
## step's owner. It implements no owner's rules.
##
## See `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_IDLE := preload("res://mods/unfplap/act/idle.gd")
const ACT_CONSENT := preload("res://mods/unfplap/act/consent.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
var idle: ACT_IDLE = null
## The swap module's one action tick; a suspended act runs no act work until its one resume.
var swap: Variant = null
## The one exit: a lost body, a failed swap and the restore timer end through its routes.
var exit: Variant = null
## The frame-level presentation and its write-backs.
var phases: Variant = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		idle_in: ACT_IDLE) -> void:
	host = host_in
	context = context_in
	session = session_in
	idle = idle_in


## One physics frame: the ordered act work, then the anatomy facts the persistent controller
## polls outside the act.
func tick(delta: float) -> void:
	PERF.begin("runtime_physics")
	_tick(delta)
	PERF.begin("runtime_anatomy_sync")
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.sync_facts()
	PERF.end("runtime_anatomy_sync")
	PERF.end("runtime_physics")


## The ordered act work. The handover owns the pause overlay: a suspended act runs nothing until
## the one resume. The pose edge advances before the view read, then the fan-out, then presentation.
func _tick(delta: float) -> void:
	swap.tick(delta)
	if context.handover.suspended:
		return
	session.tick_clock(delta)
	if session.state != State.IDLE:
		PERF.begin("pose_tick")
		context.pose.tick(delta)
		PERF.end("pose_tick")
	PERF.begin("runtime_facts")
	session.refresh_view()
	PERF.end("runtime_facts")
	if session.state != State.IDLE:
		PERF.begin("pose_fanout")
		_fanout()
		PERF.end("pose_fanout")
	if session.state == State.IDLE:
		idle.tick(delta)
		return
	if not is_instance_valid(host.pony) or not is_instance_valid(WORLD.game):
		exit.force_stop()
		return
	session.cycle_heat = false
	session.refresh_identity()
	if is_instance_valid(host.pony):
		session.cycle_heat = ELIGIBILITY.cycle_phase_for(host.pony, session.pony_id) == CYCLE.HEAT
	context.pose.sync_frame(session.pose_family())
	if host.pony.sleeping:
		host.pony.sleeping = false
	context.audio.tick_vocal(delta)
	context.hold.keep_nav()
	context.camera.tick_free_look()
	context.hold.keep_attention()
	context.hold.pause_face_turn(false)
	var tree: SceneTree = host.tree()
	context.camera.tick_lean(delta, tree != null and tree.paused,
		session.input.auto_panel_open())
	if session.state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW]:
		PERF.begin("runtime_presentation")
		phases.presentation(delta)
		PERF.end("runtime_presentation")
	if session.state in [State.POSING_IN, State.ACTIVE]:
		if context.consent.tick(delta) == ACT_CONSENT.STOP:
			context.consent.stop_with_her(context.consent.stop_kind)
	phases.log_settled()
	PERF.begin("kiss_tick")
	context.kiss.tick(delta)
	PERF.end("kiss_tick")
	if session.state in [State.ACTIVE, State.CLIMAX]:
		PERF.begin("runtime_ai")
		context.impact.auto_advance(delta)
		context.impact.tick()
		PERF.end("runtime_ai")
		if context.anatomy.act_available():
			context.anatomy.bind(context.anatomy_host)
			context.anatomy.tick(delta)
		if session.state == State.ACTIVE:
			PERF.begin("runtime_talk")
			context.readiness.tick(delta)
			talk(delta)
			context.handover.offer_tick()
			context.dialogue.bystander_tick(delta)
			PERF.end("runtime_talk")
	if session.state in [State.ACTIVE, State.CLIMAX, State.AFTERGLOW, State.RESTORE]:
		context.dialogue.tick()
	var phase: int = session.tick_timers(delta)
	if session.state == State.CLIMAX:
		context.reactions.hearts_tick(delta)
	match phase:
		ACT_SESSION.ENTER_ACTIVE:
			session.enter_active_act()
			# The start snapshot caught Anon mid stand-up, so his eye height was the reclined one;
			# the scene is settled now, and restoring to this is what puts the camera back right.
			if session.pose_family() == "bed":
				context.frame.resnapshot()
			context.handover.hint_tick()
		ACT_SESSION.FINISH_CLIMAX:
			session.finish_climax()
		ACT_SESSION.FINISH_RESTORE:
			exit.finish_restore()
	if session.state == State.AFTERGLOW:
		context.afterglow.phase_tick(delta, context.anatomy, context.anatomy_host,
			session.pose_family() == "standing")
	PERF.begin("runtime_camera")
	context.standing_camera.lock_facing()
	context.standing_camera.drive_glance(delta)
	context.gate.suppress_auto_cuddle()
	context.standing_camera.clamp_look()
	context.standing_camera.tick_depth(delta)
	context.standing_anon.tick_phase(delta)
	context.reactions.blush_tick(delta)
	session.apply_camera_motion()
	PERF.end("runtime_camera")
	if session.state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW] \
			and session.consume_check_clock(delta):
		var verdict: Variant = context.gate.running_verdict(context.hold.nav, session.bed,
			session.player_pony, context.kiss.base_active())
		if not verdict.ok:
			exit.stop(verdict.reason)
	PERF.begin("runtime_face")
	context.face.eyes_for(session.state, context.afterglow.close_rewarded,
		context.kiss.eyes_active())
	PERF.end("runtime_face")


## One talk turn: the handover's form reading and the readiness score read the same director turn.
func talk(_delta: float) -> void:
	var director := _director()
	context.handover.player_line_tick(director)
	context.readiness.talk_tick(director)


## The game's conversation director, or null outside the tree.
func _director() -> Node:
	if not is_instance_valid(host.node) or not host.node.is_inside_tree():
		return null
	return host.node.get_tree().get_first_node_in_group("conversation_director")


## The pose-change fan-out has a fixed order: the pose service reconciles its modifiers and the
## act body, then the camera, hands, kiss, anatomy and audio retarget. Every hook is idempotent.
func _fanout() -> void:
	var view: Variant = context.pose.view()
	context.pose.pose_changed(view)
	_changed(context.camera, view)
	_changed(context.hands, view)
	_changed(context.kiss, view)
	context.anatomy.bind(context.anatomy_host)
	_changed(context.anatomy, view)
	_changed(context.audio, view)


static func _changed(owner: Variant, view: Variant) -> void:
	if owner != null and owner.has_method("pose_changed"):
		owner.call("pose_changed", view)


## One render frame: the pose write, the look target, the shot and the breath. Idle keeps only the
## standing presentation's own render pass; a suspended act returns first.
func render(delta: float) -> void:
	PERF.begin("runtime_process")
	if session.state == State.IDLE:
		context.presentation.process()
	elif not context.handover.suspended:
		session.refresh_view()
		context.pose.sync_frame(session.pose_family())
		session.pose_render_write()
		context.pose.idle_sample(session.state)
		context.standing_camera.clamp_look()
		context.camera.write_look_target(context.pose.pose())
		if session.state == State.CLIMAX:
			session.refresh_climax_progress()
		context.camera.tick_shot(delta, session.state, context.standing_camera.speed(),
			session.climax_progress())
		context.audio.tick(delta, session.state, context.readiness.thrusts_per_second())
	PERF.end("runtime_process")
