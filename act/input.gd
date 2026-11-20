extends RefCounted
## The act's input protocol: the one place the input service's decoded intent becomes an act verb.
## It calls the owners (readiness, camera, anatomy, the session and the one exit) and never reads a
## raw key, an input event or a keycode.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
## The one exit: cancel and the afterglow end are its routes, never a second teardown.
var exit: Variant = null
## The queued early-end line, so one cancel owns one post-act reaction.
var end_early_key := ""


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## The mouse's vertical travel as hip travel. Readiness owns the conversion and the clamp.
func thrust_motion(relative_y: float) -> void:
	context.impact.motion(relative_y)


## Debug free look: the input service hands over the relative motion instead of a thrust.
func look_motion(relative: Vector2) -> void:
	context.camera.look_input(relative)


## One hold-X policy frame. The input service samples the keys; readiness owns the tap, the rows
## and the shape write.
func auto_panel_input(delta: float, x_down: bool, keys: Array[bool]) -> void:
	context.readiness.auto_panel_tick(delta, x_down, keys, context.readiness.depth)


## True while the hold-X auto settings layer is open.
func auto_panel_open() -> bool:
	return context.readiness.auto_panel_open()


## True while the auto stroke owns the act; the input service's mouse thrust is off.
func auto_active() -> bool:
	return context.readiness.auto_active()


## The act's pause overlay. The input service's hold and auto layer stop in the same window.
func body_swap_pending() -> bool:
	return context.handover.suspended


## The keyboard and right-mouse smack both land here; the hands owner swings the caress hand.
func smack() -> void:
	context.hands.smack()


## The anatomy action gates the input service's V/N keys read.
func anatomy_hole_ready() -> bool:
	return context.anatomy.hole_ready()


func anatomy_oral_ready() -> bool:
	return context.anatomy.oral_ready()


## How many pony climaxes this act has had; the act-key hold picks afterglow or cancel.
func climaxes() -> int:
	return context.readiness.pony_climaxes


## The VR act's right primary click is the act key's hold. The anatomy bridge owns the controller.
func vr_y_held() -> bool:
	return context.anatomy.vr_y_held()


## The act-key hold takes her to afterglow once she has climaxed, and cancels at zero.
func request_afterglow() -> void:
	session.begin_afterglow()


## The act-key hold inside the afterglow closes it and begins the one restore.
func end_afterglow() -> void:
	exit.end_afterglow()


## Cancel/end early. The early summary and its one memory mark, then the one restore and the one
## rolled post-act line.
func cancel() -> void:
	LOG.debug("cancel state=%d pony=%s", [session.state, host.pony_name()])
	if session.state in [State.POSING_IN, State.ACTIVE]:
		session.ended_early = true
		session.commit_summary(false)
		# The early summary already records this end. Keep the basic event only when the summary
		# was skipped, so the story never holds the same end twice.
		if context.summary.summary.is_empty():
			MEMORY.instance.note(MEMORY.NoteKind.CANCELLED, session.pony_id, session.event_id)
		context.dialogue.end_act(session.event_id, true)
		exit.restore_begin()
		# Half the time she says nothing at all. When she does speak, it is a moment, not a
		# review or a next-time list.
		if randf() >= 0.5:
			var act_id := session.event_id
			var max_age := session.snapshot.cue_reaction_max_age_s
			var expires := session.clock_s() + max_age
			var valid := DIALOGUE.Validity.of(func() -> bool:
				if not is_instance_valid(host.pony) or session.event_id != act_id:
					return false
				if session.clock_s() <= expires:
					return true
				return MEMORY.instance.line_state(end_early_key) == MEMORY.LineState.SPEAKING)
			var key: String = context.dialogue.reaction_line(MEMORY.Reaction.END_EARLY, act_id,
				ACT_SUMMARY.early_end_prompt(context.summary.summary), valid)
			end_early_key = key
			if not key.is_empty():
				var now := session.clock_s()
				context.dialogue.note_reaction(key, "", now + max_age)
				LOG.debug("utterance kind=reaction key=%s", [key])
			# The stopped act gets one post-act beat at most: suppress the later history line
			# for the same act, even when the roll chose silence. A skipped summary must not
			# clear an older act's pending reminder.
			if not context.summary.summary.is_empty() \
					and ACT_HISTORY.mark_announced(ACT_HISTORY.section(), session.pony_id,
						"complaint"):
				ACT_HISTORY.save()
	elif session.state == State.AFTERGLOW:
		end_afterglow()


## One wheel notch while auto owns the stroke.
func auto_thrust_wheel(direction: int) -> void:
	context.readiness.auto_wheel(direction)


## Switch the automatic stroke on or off. Turning it on starts from the hand's current depth, so
## the shot does not snap; turning it off leaves the depth where it is.
func toggle_auto_thrust() -> void:
	context.readiness.toggle_auto(context.readiness.depth)


## True while the debug free look owns the player camera instead of the act shot.
func free_look_active() -> bool:
	return context.camera.free_look_active()


## One pose request. The session supplies the act values; the pose service refuses or starts the
## edge.
func request_pose(target_id: String, trigger := "",
		request: POSE_SESSION.PoseRequest = null) -> POSE_SESSION.PoseResult:
	var values := request.copy() if request != null else POSE_SESSION.PoseRequest.new()
	if values.act_state < 0:
		values.act_state = session.state
	if not values.features_set:
		values.features = session.features
		values.features_set = true
	return context.pose.request_pose(target_id, trigger, values)


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
			context.anatomy.bind(context.anatomy_host)
			context.anatomy.toggle_hole()
			return true
		ACT_COMMANDS.ORAL:
			context.anatomy.bind(context.anatomy_host)
			context.anatomy.toggle_oral(context.pose, session.display_name, session.features)
			return true
		ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD:
			return false
		ACT_COMMANDS.END:
			return true
	return false
