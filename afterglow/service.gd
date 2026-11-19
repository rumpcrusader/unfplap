extends RefCounted
## The post-act afterglow phase and the aftercare that follows it: the private afterglow beat,
## the standing close window with its caress reward, the presentation the phase asks for, the
## satisfaction decay and the post-act aftercare node. The runtime owns the act state, its exit
## and the frame hooks; this facade owns what the after-act looks like and how long it lives.
## Contract: `docs/afterglow.md`.

const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const AFTERCARE := preload("res://mods/unfplap/afterglow/aftercare.gd")

## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5
## The satisfaction meter runs down to zero over this window after every act.
const SATISFACTION_DECAY_SECONDS := 30.0

## The post-act decision the runtime hosts. One act ends in either the tail tuck after a partner
## stop or the aftercare beat the summary and the meter earn; the post-act face reads the same
## values.
class PostAct extends RefCounted:
	## After a partner stop she keeps her tail tucked and gets no aftercare beat.
	var tail_tuck := false
	## The aftercare body language: a healthy summary, or a satisfied meter over her threshold.
	var body_language := false
	var stopped := false
	var satisfied := 0.0
	var aftercare_min := 0.0
	var has_summary := false

	## The face facade's context for the post-act face. The summary is carried only when the act
	## had one.
	func face_context(summary: Dictionary) -> Dictionary:
		return {
			"stopped": stopped,
			"summary": summary if has_summary else {},
			"satisfied": satisfied,
			"aftercare_min": aftercare_min,
		}

## The pose view the runtime carries into the next `begin()`; its `afterglow` profile owns the
## close-window decision and its family the presentation row.
var view: RefCounted = null
## Whether this pose's afterglow profile opens a close window.
var close_window := false
## One short private afterglow beat, rolled once when the afterglow begins. Empty means silence.
var beat := ""
var close_left := 0.0
var close_caress_seconds := 0.0
var close_rewarded := false
## True only when the standing close window earned its caress reward.
var close_caress_earned := false
## True when the summary of the act being held is a positive one.
var positive := false

## Host boundary. Missing callbacks are no-ops.
var log := Callable()
var caress_active := Callable()
## The close window elapsed: `(caressed, positive)`.
var on_stay_close := Callable()
## The host node the post-act children join. The runtime binds itself (D24: it owns the tree).
var host: Node = null
## The satisfaction decay's write: `(value: float)`. The runtime clamps into the meter's range.
var write_satisfaction := Callable()

## The live aftercare node the host parented, or null. It frees itself after its beat.
var aftercare: Node = null
## The satisfaction decay tween the runtime's node created for the facade.
var _decay: Tween = null


## Bind the host node whose tree the post-act children join. The runtime binds once.
func bind_host(node: Node) -> void:
	host = node


## Carry the pose view into the next afterglow. The runtime binds it once per act.
func bind_view(view_in: RefCounted) -> void:
	view = view_in


## Start a fresh afterglow for the live view. The row's `afterglow.close_window` opens the close
## window immediately.
func begin(summary: Dictionary) -> void:
	var afterglow: Variant = view.afterglow if view != null else null
	close_window = bool((afterglow as Dictionary).get("close_window", false)) \
		if afterglow is Dictionary else false
	beat = ACT_SUMMARY.afterglow_beat(summary, randf())
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = bool(summary.get("reward", false))
	close_left = STAY_CLOSE_SECONDS if close_window else 0.0


## The presentation the runtime applies when the act enters the held afterglow. The facade owns
## the phase decisions; the runtime applies the row in this order and owns the scene calls the
## row cannot make (the wings, the face beat, the summary commit). The tail targets follow the
## active view family, not the act's start pose. The held pose is the act's current pose: the row
## names no pose mode and no afterglow pose.
func presentation() -> Dictionary:
	var standing := view != null and str(view.family) == "standing"
	return {
		"tail_target": 0.55 if standing else 0.35,
		"tail_flicks": 2 if standing else 0,
		"hud_state": "AFTERGLOW",
		"wings": true,
	}


## Clear every value for the next act. The callbacks stay.
func reset() -> void:
	close_window = false
	beat = ""
	close_left = 0.0
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = false


## Start the satisfaction meter's decay. The runtime's node creates the tween (D24); the facade
## owns it, so a new act kills the one still running.
func decay_satisfaction(from: float) -> void:
	stop_decay()
	if not is_instance_valid(host) or not host.is_inside_tree() or not write_satisfaction.is_valid():
		return
	_decay = host.create_tween()
	if _decay == null:
		return
	_decay.tween_method(write_satisfaction, from, 0.0, SATISFACTION_DECAY_SECONDS)


func stop_decay() -> void:
	if _decay != null and _decay.is_valid():
		_decay.kill()
	_decay = null


## The after-act decision. A partner stop keeps the tail tucked; otherwise the healthy summary,
## or a satisfied meter over her aftercare threshold, gives the aftercare beat its body language.
func post_act(stopped: bool, satisfied: float, aftercare_min: int,
		summary_present: bool, summary_positive: bool) -> PostAct:
	var plan := PostAct.new()
	plan.stopped = stopped
	plan.satisfied = satisfied
	plan.aftercare_min = float(aftercare_min)
	plan.tail_tuck = stopped
	plan.has_summary = summary_present
	var healthy := summary_positive if summary_present else satisfied >= plan.aftercare_min
	plan.body_language = not stopped and healthy and satisfied >= plan.aftercare_min
	return plan


## Parent the aftercare node for the plan. Returns false when there is nothing to host: the act
## ended outside the tree, the body is gone, or a node is already running.
func start_aftercare(pony: Node3D, plan: PostAct) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or not is_instance_valid(pony):
		return false
	if is_instance_valid(aftercare):
		return false
	aftercare = AFTERCARE.new()
	aftercare.set("pony", pony)
	aftercare.set("body_language", plan.body_language)
	host.add_child(aftercare)
	return true


## Drop the running aftercare node and the pony's aftercare mark. The node restores its own
## navigator lease; the mark is cleared here because a start may replace the node before it runs.
func clear_post_act(pony: Node3D = null) -> void:
	if is_instance_valid(aftercare):
		aftercare.queue_free()
	aftercare = null
	if is_instance_valid(pony) and pony.has_meta("sex_aftercare"):
		pony.remove_meta("sex_aftercare")


## Count caress time and run the close window down. The window opens in `begin()`.
func close_tick(delta: float) -> void:
	if not close_window or close_left <= 0.0:
		return
	if _truthy(caress_active):
		close_caress_seconds += delta
	close_left = maxf(0.0, close_left - delta)
	if close_left <= 0.0:
		_finish_close()


func _finish_close() -> void:
	if close_rewarded:
		return
	close_rewarded = true
	close_left = 0.0
	var caressed := close_caress_seconds >= STAY_CLOSE_CARESS_SECONDS
	close_caress_earned = caressed
	_write_log("stay close reward caressed=%s caress_seconds=%.1f" % [
		str(caressed), close_caress_seconds])
	if on_stay_close.is_valid():
		on_stay_close.call(caressed, positive)


## Leaving afterglow early closes the window without a reward.
func cancel_close() -> void:
	if close_rewarded:
		return
	close_left = 0.0
	close_caress_seconds = 0.0


func hint() -> String:
	if close_left > 0.0:
		return "Stay close · %ds · caress" % int(ceil(close_left))
	if close_rewarded:
		return "She seems content."
	return ""


func _truthy(callback: Callable) -> bool:
	return bool(callback.call()) if callback.is_valid() else false


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
