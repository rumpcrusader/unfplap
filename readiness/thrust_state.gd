extends RefCounted
## Per-act stroke and penetration state: the one depth tracker, the public 0..1 depth, the physical
## penetration in metres and the depth scale they share. It turns the tracker's raw readings into
## the typed stroke/impact events the act presentation consumes. Readiness owns it; see
## docs/readiness.md.

const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")

## The shaft length used for the depth scale when the anatomy part is not showing, so the mouse
## feel is the same with the anatomy off. Close to the default part's visible length.
const NOMINAL_SHAFT_M := 0.2
## The body slap fires only when his skin has actually reached her coat.
const CONTACT_GAP_M := 0.0
## Visual impact = physical strength × this, so normal and fast thrusts keep their tuned
## reaction while slow or shallow strokes stay lighter.
const THRUST_IMPACT_GAIN := 2.0


## One closed stroke or one stroke bottom. The raw tracker fields keep their scale; the derived
## ones are the physical facts presentation reads.
class StrokeEvent extends RefCounted:
	var kind := "stroke"
	var direction := 0
	var start_depth := 0.0
	var end_depth := 0.0
	var travel := 0.0
	var duration := 0.0
	var speed := 0.0
	var peak_speed := 0.0
	var strength := 0.0
	var thrust := false
	var impact_speed := 0.0
	var tier := ""
	var plap := false
	var gap := 0.0
	var jiggle := 0.0
	var visual := 0.0


var depth := 0.0
var penetration_m := 0.0
var pixels_per_cm := 0.0
var up_is_deep := false
var travel := 0.0
var pelvis_gap_m := 0.0

## Host reads for the depth scale: his visible shaft length in metres and the live pose family.
## A missing callback falls back to the nominal length and a detached reach.
var shaft_length := Callable()
var pose_family := Callable()

var _tracker: RefCounted = THRUST.new()


func reset() -> void:
	depth = 0.0
	penetration_m = 0.0
	_tracker.reset()


## The act's depth scale, pushed once per act and again on every live settings apply.
func configure(pixels_per_cm_in: float, up_is_deep_in: bool, travel_in: float,
		pelvis_gap_in: float) -> void:
	pixels_per_cm = pixels_per_cm_in
	up_is_deep = up_is_deep_in
	travel = travel_in
	pelvis_gap_m = pelvis_gap_in


## His visible shaft length in metres.
func shaft_length_m() -> float:
	if shaft_length.is_valid():
		var length := float(shaft_length.call())
		if length > 0.001:
			return length
	return NOMINAL_SHAFT_M


## The deepest the tip can reach, in metres. Both poses carry his body on the stroke, so the
## pelvis gap keeps his pelvis that far behind her rear surface; a detached placement is limited
## by the shaft alone.
func reach() -> float:
	var length := shaft_length_m()
	if _pose_family() in ["standing", "bed"]:
		return maxf(length - pelvis_gap_m, 0.02)
	return maxf(length, 0.02)


func live_strength(now: float) -> float:
	return _tracker.live_strength(now)


## Vertical mouse motion as hip travel in metres, through the act's sensitivity and orientation.
func mouse_travel(dy_pixels: float) -> float:
	return THRUST.pixels_to_metres(dy_pixels, pixels_per_cm, up_is_deep)


## Move the physical penetration and mirror it into the public 0..1 depth. The tip rests at her
## entrance when it is out, and the depth stays at zero there, so no standoff eats a stroke.
func set_penetration(target_m: float, now: float) -> Array[StrokeEvent]:
	var reach_m := reach()
	penetration_m = clampf(target_m, 0.0, reach_m)
	return move(THRUST.penetration_to_depth(penetration_m, reach_m) - depth, now)


func move(amount: float, now: float) -> Array[StrokeEvent]:
	if _tracker == null:
		return []
	var events: Array[StrokeEvent] = []
	for raw: Dictionary in _tracker.move(amount, now):
		events.append(_event(raw))
	depth = _tracker.depth
	return events


func tick(now: float) -> Array[StrokeEvent]:
	if _tracker == null:
		return []
	var events: Array[StrokeEvent] = []
	for raw: Dictionary in _tracker.tick(now):
		events.append(_event(raw))
	depth = _tracker.depth
	return events


func _pose_family() -> String:
	return str(pose_family.call()) if pose_family.is_valid() else ""


## Fill the derived physical facts at the tracker's edge, so presentation receives values instead
## of recomputing them from the depth scale.
func _event(raw: Dictionary) -> StrokeEvent:
	var event := StrokeEvent.new()
	event.kind = str(raw.get("kind", "stroke"))
	event.direction = int(raw.get("direction", 0))
	event.start_depth = float(raw.get("start_depth", 0.0))
	event.end_depth = float(raw.get("end_depth", depth))
	event.travel = float(raw.get("travel", 0.0))
	event.duration = float(raw.get("duration", 0.0))
	event.speed = float(raw.get("speed", 0.0))
	event.peak_speed = float(raw.get("peak_speed", 0.0))
	event.strength = clampf(float(raw.get("strength", 0.0)), 0.0, 1.0)
	event.thrust = bool(raw.get("thrust", false))
	event.visual = clampf(event.strength * THRUST_IMPACT_GAIN, 0.0, 1.0)
	if event.kind != "impact":
		return event
	var reach_m := reach()
	event.impact_speed = float(raw.get("impact_speed", 0.0))
	event.gap = THRUST.skin_gap_m(event.end_depth * reach_m, reach_m)
	event.tier = THRUST.plap_tier(event.impact_speed)
	event.plap = THRUST.plap_touching(event.gap, CONTACT_GAP_M) and not event.tier.is_empty()
	event.jiggle = THRUST.jiggle_amount(event.travel, event.strength)
	return event
