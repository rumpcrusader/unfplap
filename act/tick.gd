extends RefCounted
## The act's ordered frame schedule. The runtime node's `_physics_process` and `_process` forward
## here; this module owns the order, the perf labels and the one pose fan-out, and calls each
## step's owner. It implements no owner's rules.
##
## See `docs/runtime.md` and `docs/perf.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_IDLE := preload("res://mods/unfplap/act/idle.gd")
const ACT_CONSENT := preload("res://mods/unfplap/act/consent.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")

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
## The perf probe, bound once after `PERF.build()`; a null probe is a no-op.
var probe: Variant = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		idle_in: ACT_IDLE) -> void:
	host = host_in
	context = context_in
	session = session_in
	idle = idle_in


## One physics frame: the ordered act work, then the anatomy facts the persistent controller
## polls outside the act. `idle_perf` only times the idle window.
func tick(delta: float) -> void:
	var started := Time.get_ticks_usec()
	var idle_gate := session.idle_perf and session.state == State.IDLE
	_tick(delta)
	var sync_started := Time.get_ticks_usec() if idle_gate else 0
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.sync_facts()
	if idle_gate:
		host.perf_note("runtime_anatomy_sync", Time.get_ticks_usec() - sync_started)
	if probe != null and probe.on():
		host.perf_note("runtime_physics", Time.get_ticks_usec() - started)


## The ordered act work. The handover owns the pause overlay: a suspended act runs nothing until
## the one resume. The pose edge advances before the view read, then the fan-out, then presentation.
func _tick(delta: float) -> void:
	swap.tick(delta)
	if context.handover.suspended:
		return
	session.tick_clock(delta)
	if session.state != State.IDLE:
		var pose_started := Time.get_ticks_usec()
		context.pose.tick(delta)
		_timed("pose_tick", pose_started)
	var facts_started := Time.get_ticks_usec()
	session.refresh_view()
	_timed("runtime_facts", facts_started)
	if session.state != State.IDLE:
		var fanout_started := Time.get_ticks_usec()
		_fanout()
		_timed("pose_fanout", fanout_started)
	if session.state == State.IDLE:
		idle.tick(delta, session.idle_perf)
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
		var presentation_started := Time.get_ticks_usec()
		phases.presentation(delta)
		_timed("runtime_presentation", presentation_started)
	if session.state in [State.POSING_IN, State.ACTIVE]:
		if context.consent.tick(delta) == ACT_CONSENT.STOP:
			context.consent.stop_with_her(context.consent.stop_kind)
	phases.log_settled()
	var kiss_started := Time.get_ticks_usec()
	context.kiss.tick(delta)
	_timed("kiss_tick", kiss_started)
	if session.state in [State.ACTIVE, State.CLIMAX]:
		var ai_started := Time.get_ticks_usec()
		context.impact.auto_advance(delta)
		context.impact.tick()
		_timed("runtime_ai", ai_started)
		if context.anatomy.act_available():
			context.anatomy.bind(context.anatomy_host)
			context.anatomy.tick(delta)
		if session.state == State.ACTIVE:
			var talk_started := Time.get_ticks_usec()
			context.readiness.tick(delta)
			talk(delta)
			context.handover.offer_tick()
			context.dialogue.bystander_tick(delta)
			_timed("runtime_talk", talk_started)
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
				context.missionary_camera.resnapshot()
			context.handover.hint_tick()
		ACT_SESSION.FINISH_CLIMAX:
			session.finish_climax()
		ACT_SESSION.FINISH_RESTORE:
			exit.finish_restore()
	if session.state == State.AFTERGLOW:
		context.afterglow.phase_tick(delta, context.anatomy, context.anatomy_host,
			session.pose_family() == "standing")
	var camera_started := Time.get_ticks_usec()
	context.standing_camera.lock_facing()
	context.standing_camera.drive_glance(delta)
	context.gate.suppress_auto_cuddle()
	context.standing_camera.clamp_look()
	context.standing_camera.tick_depth(delta)
	context.standing_anon.tick_phase(delta)
	context.reactions.blush_tick(delta)
	session.apply_camera_motion()
	_timed("runtime_camera", camera_started)
	if session.state in [State.POSING_IN, State.ACTIVE, State.CLIMAX, State.AFTERGLOW] \
			and session.consume_check_clock(delta):
		var verdict: Variant = context.gate.running_verdict(context.hold.nav, session.bed,
			session.player_pony, context.kiss.base_active())
		if not verdict.ok:
			exit.stop(verdict.reason)
	var face_started := Time.get_ticks_usec()
	context.face.eyes_for(session.state, context.afterglow.close_rewarded,
		context.kiss.eyes_active())
	_timed("runtime_face", face_started)


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
	var started := Time.get_ticks_usec()
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
	if probe != null and probe.on():
		host.perf_note("runtime_process", Time.get_ticks_usec() - started)
		probe.tick(delta)


## Time one call site for the probes; the probe owns the reporting window.
func _timed(key: String, started: int) -> void:
	if probe != null:
		probe.time(key, started)
