extends RefCounted
## The act's input protocol: the one place the input service's decoded intent becomes an act verb.
## It calls the owners (readiness, camera, anatomy, the session and the one exit) and never reads a
## raw key, an input event or a keycode.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
## The session, held weakly: it owns this protocol, so a strong link back would be a cycle.
var _session_ref: WeakRef = null
## The one exit: cancel and the afterglow end are its routes, never a second teardown.
var exit: Variant = null
## The queued early-end line, so one cancel owns one post-act reaction.
var end_early_key := ""


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	_session_ref = weakref(session_in)


## The session, or null once it has released this protocol.
func _session() -> ACT_SESSION:
	return _session_ref.get_ref() as ACT_SESSION


## The mouse's vertical travel as hip travel. Readiness owns the conversion and the clamp.
func thrust_motion(relative_y: float) -> void:
	context.impact.motion(relative_y)


## Debug free look: the input service hands over the relative motion instead of a thrust.
func look_motion(relative: Vector2) -> void:
	context.camera.look_input(relative)


## One hold-X policy frame. The input service samples the keys; the auto service owns the tap,
## the layer's actions and the shape write.
func auto_panel_input(delta: float, x_down: bool, keys: Array[bool]) -> void:
	if _session().state not in [State.ACTIVE, State.CLIMAX]:
		return
	context.auto.panel(delta, x_down, keys, context.readiness.readout().depth)


## True while the hold-X auto settings layer is open.
func auto_panel_open() -> bool:
	return context.auto.readout().panel_open


## True while the auto stroke owns the act; the input service's mouse thrust is off.
func auto_active() -> bool:
	return context.auto.readout().active


## The act's pause overlay. The input service's hold and auto layer stop in the same window.
func body_swap_pending() -> bool:
	return context.handover.suspended


## The keyboard and right-mouse smack both land here; the hands owner swings the caress hand.
func smack() -> void:
	context.hands.smack()


## The anatomy action gates the input service's V/N keys read.
func anatomy_hole_ready() -> bool:
	return context.anatomy != null and context.anatomy.can_target_vulva()


func anatomy_oral_ready() -> bool:
	return context.anatomy != null and context.anatomy.can_target_mouth()


## How many pony climaxes this act has had; the act-key hold picks afterglow or cancel.
func climaxes() -> int:
	return context.readiness.pony_climaxes


## The VR act's right primary click is the act key's hold.
func vr_y_held() -> bool:
	return _session().vr_y_held()


## The act-key hold takes her to afterglow once she has climaxed, and cancels at zero.
func request_afterglow() -> void:
	_session().begin_afterglow()


## The act-key hold inside the afterglow closes it and begins the one restore.
func end_afterglow() -> void:
	exit.end_afterglow()


## Cancel/end early. The early summary and its one memory mark, then the one restore and the one
## rolled post-act line.
func cancel() -> void:
	LOG.debug("cancel state=%d pony=%s", [_session().state, host.pony_name()])
	if _session().state in [State.POSING_IN, State.ACTIVE]:
		_session().ended_early = true
		_session().finish()
		var score := _session().act_score
		var outcome: Dictionary = score.outcome if score != null else {}
		# The early summary already records this end. Keep the basic event only when the summary
		# was skipped, so the story never holds the same end twice.
		if (score == null or score.skipped) and context.memory != null:
			context.memory.note(MEMORY.NoteKind.CANCELLED, _session().pony_id, _session().event_id)
		context.dialogue.end_act(_session().event_id, true)
		exit.restore_begin()
		# Half the time she says nothing at all. When she does speak, it is a moment, not a
		# review or a next-time list.
		if randf() >= 0.5:
			var act_id := _session().event_id
			var max_age := _session().snapshot.cue_reaction_max_age_s
			var expires := _session().clock_s() + max_age
			var valid := DIALOGUE.Validity.of(func() -> bool:
				if not is_instance_valid(host.pony) or _session().event_id != act_id:
					return false
				if _session().clock_s() <= expires:
					return true
				return context.memory != null \
					and context.memory.line_state(end_early_key) == MEMORY.LineState.SPEAKING)
			var key: String = context.dialogue.reaction_line(MEMORY.Reaction.END_EARLY, act_id,
				ACT_SUMMARY.early_end_prompt(outcome), valid)
			end_early_key = key
			if not key.is_empty():
				var now := _session().clock_s()
				context.dialogue.note_reaction(key, "", now + max_age)
				LOG.debug("utterance kind=reaction key=%s", [key])
			# The stopped act gets one post-act beat at most: suppress the later history line
			# for the same act, even when the roll chose silence. A skipped summary must not
			# clear an older act's pending reminder.
			var history: Dictionary = WORLD.mods().state(ACT_HISTORY.MOD_ID).rows
			if not outcome.is_empty() \
					and ACT_HISTORY.mark_announced(history, _session().pony_id, "complaint"):
				WORLD.mods().save()
	elif _session().state == State.AFTERGLOW:
		end_afterglow()


## One wheel notch while auto owns the stroke.
func auto_thrust_wheel(direction: int) -> void:
	context.auto.wheel(direction)


## Switch the automatic stroke on or off. Turning it on starts from the hand's current depth, so
## the shot does not snap; turning it off leaves the depth where it is.
func toggle_auto_thrust() -> void:
	if _session().state not in [State.ACTIVE, State.CLIMAX]:
		return
	context.auto.toggle(context.readiness.readout().depth)


## True while the debug free look owns the player camera instead of the act shot.
func free_look_active() -> bool:
	return context.camera.free_look_active()


## One pose request. The facts supply the act values; the pose service refuses or starts the edge.
func request_pose(target_id: String, trigger := "",
		consent := "") -> POSE_SESSION.PoseResult:
	return context.pose.request_pose(target_id, trigger, consent)


## One command check against the pose's control set and the live edge lock; `end` is reserved.
func request_command(command_id: String) -> bool:
	return context.pose.request_command(command_id)


## Run one discrete command after the pose's control set and the live edge lock allow it.
## Returns true only when a command was dispatched. `end` is reserved; the act-key hold owns it.
func command(command_id: String) -> bool:
	if not request_command(command_id):
		return false
	match command_id:
		ACT_COMMANDS.HOLE:
			return _toggle_hole()
		ACT_COMMANDS.ORAL:
			return _toggle_oral()
		ACT_COMMANDS.END:
			return true
	return false


## V: turn the vulva or the anus. Consent stays with the input; anatomy never checks it.
func _toggle_hole() -> bool:
	var anatomy = context.anatomy
	if anatomy == null:
		return false
	if anatomy.target() == ANATOMY.Target.VULVA and anatomy.can_target_vulva():
		if not _consent("anal"):
			_show_status("%s is not into that" % _session().display_name)
			return false
		anatomy.target_anus()
		return true
	anatomy.target_vulva()
	return true


## N: request the standing oral edge, or its return; the pose service owns the edge.
func _toggle_oral() -> bool:
	var anatomy = context.anatomy
	if anatomy == null or not anatomy.can_target_mouth():
		return false
	var live: Variant = context.pose.view()
	var from_id := str(live.id) if live != null else ""
	var target := CATALOG.STANDING_ORAL if from_id == CATALOG.STANDING else CATALOG.STANDING
	var consent := false
	if target == CATALOG.STANDING_ORAL:
		consent = _consent("oral")
	var result: POSE_SESSION.PoseResult = context.pose.request_pose(target, "oral",
		"oral" if consent else "")
	if result != null and result.ok:
		LOG.debug("oral pose %s -> %s: ok", [from_id, target])
		return true
	LOG.debug("oral pose %s -> %s refused: %s (%s)", [
		from_id, target, str(result.code if result != null else ""),
		str(result.reason if result != null else "")])
	if target == CATALOG.STANDING_ORAL and not consent:
		_show_status("%s is not into that" % _session().display_name)
	elif result != null:
		_show_status(str(result.reason))
	return false


func _consent(key: String) -> bool:
	if not is_instance_valid(host.pony) or not is_instance_valid(context.world.act_gate):
		return false
	return context.world.act_gate.consent(host.pony, key)


func _show_status(text: String) -> void:
	if text.is_empty() or not is_instance_valid(context.hud):
		return
	context.hud.anatomy_status(text, 2.0)
