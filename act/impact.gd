extends RefCounted
## The act's stroke presentation: the one post-move path, the stroke/impact fan-out and the
## physical penetration write. The readiness stroke state owns the math and the events; this owner
## turns one event batch into presentation in the order the act depends on.
##
## See `docs/runtime.md` and `docs/readiness.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")

const State := ACT_STATE.State
const CONTACT_GAP_M := 0.0

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## One idle tracker frame: a held bottom or a timed-out stroke produces its event here.
func tick() -> void:
	dispatch(context.readiness.stroke_tick(session.clock_s()))


## The process-time clock of the stroke; the session owns it.
func now() -> float:
	return session.clock_s()


## The mouse's vertical travel as hip travel. Readiness converts the pixels and owns the clamp;
## the one post-move path carries the events to the ordered fan-out.
func motion(relative_y: float) -> void:
	set_penetration(context.readiness.penetration_m + context.readiness.mouse_travel(relative_y),
		now())


## Move the physical penetration and mirror it into the public 0..1 depth.
func set_penetration(target_m: float, at: float) -> void:
	var before := context.readiness.depth
	var events: Array[THRUST_STATE.StrokeEvent] = context.readiness.set_penetration(target_m, at)
	finish_stroke(before, at, events)


func move(amount: float, at: float) -> void:
	var before := context.readiness.depth
	var events: Array[THRUST_STATE.StrokeEvent] = context.readiness.move(amount, at)
	finish_stroke(before, at, events)


## The public 0..1 depth write the anatomy host uses.
func set_depth(value: float) -> void:
	context.readiness.penetration_m = value


## One auto frame: the generated depth through the same tracker.
func auto_advance(delta: float) -> void:
	var before := context.readiness.depth
	var at := now()
	var events: Array[THRUST_STATE.StrokeEvent] = context.readiness.auto_advance(delta, at)
	finish_stroke(before, at, events)


## The one post-move path: the withdrawal slide when the tip crosses her lips outward, then the
## ordered stroke/impact fan-out.
func finish_stroke(before: float, at: float, events: Array[THRUST_STATE.StrokeEvent]) -> void:
	if session.state in [State.ACTIVE, State.CLIMAX] and not _face_contact() \
			and context.audio.crossed(before, context.readiness.depth):
		context.audio.withdraw(before, context.readiness.depth,
			context.readiness.live_strength(at), context.reactions.rump_point())
	dispatch(events)


func dispatch(events: Array[THRUST_STATE.StrokeEvent]) -> void:
	for event: THRUST_STATE.StrokeEvent in events:
		_dispatch_stroke_event(event)


## The tracker reports the bottom of a stroke and its close. Presentation belongs to the bottom
## so the plap and the body land with the motion; the score belongs to the close.
func _dispatch_stroke_event(event: THRUST_STATE.StrokeEvent) -> void:
	if event.kind == "impact":
		impact(event)
	else:
		context.readiness.stroke(event)


## The stroke's bottom: the plap, the wobble, the wings, her blush and the ear twitch all land
## here, with the motion. The oral segment keeps the slide, vocal, wings, blush and ear twitch but
## drops the plap and the rump/tail jiggle.
func impact(event: THRUST_STATE.StrokeEvent) -> void:
	if session.state not in [State.ACTIVE, State.CLIMAX]:
		return
	var oral := _mouth_contact()
	var face := _face_contact()
	var quiet := oral or face
	context.wings.on_thrust(event.visual)
	if not quiet:
		context.reactions.thrust(event.jiggle)
		context.reactions.tail_thrust(event.jiggle)
	if session.pose_family() == "standing":
		context.reactions.add_blush(event.visual)
		context.pose.trigger_ear_twitch(event.visual)
	context.readiness.note_impact()
	context.audio.play_vocal()
	context.audio.impact(event.tier, event.strength, context.reactions.rump_point(),
		event.gap, CONTACT_GAP_M, not quiet)
	host.log("thrust impact gap=%.3f speed=%.2f tier=%s plap=%d oral=%d face=%d readiness=%.0f rate=%.1f/s strength=%.2f impact=%.2f jiggle=%.2f intensity=%s pattern=%s" % [
		event.gap, event.impact_speed, event.tier if not event.tier.is_empty() else "-",
		1 if event.plap else 0, 1 if oral else 0, 1 if face else 0,
		context.readiness.satisfaction, context.readiness.thrusts_per_second(), event.strength,
		event.visual, event.jiggle, context.readiness.last_intensity,
		context.readiness.last_pattern])


## Live mouth contact from the pose view: the plap/vocal guard and the climax-line skip.
func _mouth_contact() -> bool:
	var view: Variant = context.pose.view()
	return view != null and str(view.contact_kind) == "mouth"


## The bed face-sit contact: his mouth, not her opening.
func _face_contact() -> bool:
	var view: Variant = context.pose.view()
	return view != null and str(view.contact_kind) == "face"
