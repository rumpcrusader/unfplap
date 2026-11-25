extends RefCounted
## The act's stroke presentation: the one post-move path, the stroke/impact fan-out and the
## physical penetration write. The meter owns the math and the events; this owner turns one event
## batch into presentation in the order the act depends on.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const State := ACT_STATE.State

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## The mouse's vertical travel as hip travel. The sensitivity and the orientation are read at use;
## the hand's new physical depth is the one input the meter clamps.
func motion(relative_y: float) -> void:
	var readout := context.readiness.readout()
	var metres := THRUST.pixels_to_metres(relative_y, SETTINGS.pixels_per_cm.get_num(),
		readout.up_is_deep)
	set_penetration(readout.penetration_m + metres)


## Put him at this physical penetration; the meter mirrors it into the public 0..1 depth.
func set_penetration(target_m: float) -> void:
	var before := context.readiness.readout().depth
	var events: Array[THRUST_STATE.StrokeEvent] = context.readiness.set_penetration(target_m)
	finish_stroke(before, events)


## Move the measured depth by a share of his reach.
func move(amount: float) -> void:
	var before := context.readiness.readout().depth
	var events: Array[THRUST_STATE.StrokeEvent] = context.readiness.stroke(amount)
	finish_stroke(before, events)


## One auto frame: the generated movement through the same tracker.
func auto_advance(delta: float) -> void:
	var movement := context.auto.step(delta, context.readiness.readout().depth)
	if is_zero_approx(movement):
		return
	move(movement)


## The one post-move path: the withdrawal slide when the tip crosses her lips outward, then the
## ordered stroke/impact fan-out.
func finish_stroke(before: float, events: Array[THRUST_STATE.StrokeEvent]) -> void:
	var readout := context.readiness.readout()
	if session.state in [State.ACTIVE, State.CLIMAX] and not _face_contact() \
			and context.audio.crossing_out(before, readout.depth):
		context.audio.slide_out(before, readout.depth, readout.strength,
			context.reactions.rump_point())
	dispatch(events)


func dispatch(events: Array[THRUST_STATE.StrokeEvent]) -> void:
	for event: THRUST_STATE.StrokeEvent in events:
		_dispatch_stroke_event(event)


## The tracker reports the bottom of a stroke and its close. Presentation belongs to the bottom
## so the plap and the body land with the motion; the close was already scored by the meter.
func _dispatch_stroke_event(event: THRUST_STATE.StrokeEvent) -> void:
	if event.kind == "impact":
		impact(event)


## The stroke's bottom, with the motion: the plap, the wobble, the wings, blush and ear twitch land
## here; the oral segment drops the plap and the rump/tail jiggle and keeps the rest.
func impact(event: THRUST_STATE.StrokeEvent) -> void:
	if session.state not in [State.ACTIVE, State.CLIMAX] or _suspended():
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
	context.audio.vocal()
	context.audio.impact(event.tier, event.strength, context.reactions.rump_point(),
		event.gap, not quiet)
	var readout := context.readiness.readout()
	LOG.debug("thrust impact gap=%.3f speed=%.2f tier=%s plap=%d oral=%d face=%d readiness=%.0f rate=%.1f/s strength=%.2f impact=%.2f jiggle=%.2f intensity=%s pattern=%s", [
		event.gap, event.impact_speed, event.tier if not event.tier.is_empty() else "-",
		1 if event.plap else 0, 1 if oral else 0, 1 if face else 0,
		readout.satisfaction, readout.rate, event.strength,
		event.visual, event.jiggle, readout.last_intensity, readout.last_pattern])


## A body swap holds the act's scene while the meter's own tick may still close a stroke, so the
## presentation waits for the resume.
func _suspended() -> bool:
	return context.handover != null and context.handover.suspended


## Live mouth contact from the pose view: the plap/vocal guard and the climax-line skip.
func _mouth_contact() -> bool:
	var view: Variant = context.pose.view()
	return view != null and str(view.contact_kind) == "mouth"


## The bed face-sit contact: his mouth, not her opening.
func _face_contact() -> bool:
	var view: Variant = context.pose.view()
	return view != null and str(view.contact_kind) == "face"
