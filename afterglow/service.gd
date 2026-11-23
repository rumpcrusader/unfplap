extends RefCounted
## Service: afterglow
## Scope: pony
## Contract: docs/afterglow.md
## The held after-act phase and its aftercare; the runtime owns the act state.

const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const AFTERCARE := preload("res://mods/unfplap/afterglow/aftercare.gd")
const PRESENTATION := preload("res://mods/unfplap/afterglow/presentation.gd")
const SUMMARY := preload("res://mods/unfplap/afterglow/summary.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const BEAT := preload("res://mods/unfplap/shared/face_beat.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5
## The satisfaction meter runs down to zero over this window after every act.
const SATISFACTION_DECAY_SECONDS := 30.0

## The post-act decision: the tail tuck after a partner stop, or the earned aftercare beat.
## The post-act face reads the same values.
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
	func face_context(summary: Dictionary) -> BEAT:
		var context := BEAT.new()
		context.stopped = stopped
		context.satisfied = satisfied
		context.aftercare_min = aftercare_min
		if has_summary:
			context.summary = BEAT.Summary.from_dict(summary)
		return context

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

var caress_active := Callable()
## The host node the post-act children join. The runtime binds itself (D24: it owns the tree).
var host: Node = null
## The satisfaction decay's write: `(value: float)`. The runtime clamps into the meter's range.
var write_satisfaction := Callable()
## The phase's act collaborators, bound once by the runtime. The close reward writes through
## them; an unbound facade (a pure suite) skips the presentation.
var face: FACE = null
var reactions: REACTIONS = null
var readiness: READINESS = null
## The world HUD and memory the phase reports to; the runtime's builder passes them once.
var hud: Node = null
var memory: Node = null
## The act the reward records. The session sets both at the phase start.
var pony_id := ""
var event_id := ""

## The live aftercare node the host parented, or null. It frees itself after its beat.
var aftercare: AFTERCARE = null
## The satisfaction decay tween the runtime's node created for the facade.
var _decay: Tween = null


func _init(hud_in: Node = null, memory_in: Node = null) -> void:
	hud = hud_in
	memory = memory_in


## Bind the phase's act collaborators once. The runtime composes; the session sets the ids.
func bind_act(face_in: FACE, reactions_in: REACTIONS, readiness_in: READINESS) -> void:
	face = face_in
	reactions = reactions_in
	readiness = readiness_in


## The act the close reward records.
func set_act(pony_id_in: String, event_id_in: String) -> void:
	pony_id = pony_id_in
	event_id = event_id_in


## Bind the host node whose tree the post-act children join. The runtime binds once.
func bind_host(node: Node) -> void:
	host = node


## Carry the pose view into the next afterglow. The runtime binds it once per act.
func bind_view(view_in: RefCounted) -> void:
	view = view_in


## Start a fresh afterglow for the live view. The row's `afterglow.close_window` opens the close
## window immediately.
func begin(summary: SUMMARY) -> void:
	var afterglow: Variant = view.afterglow if view != null else null
	close_window = bool((afterglow as Dictionary).get("close_window", false)) \
		if afterglow is Dictionary else false
	beat = ACT_SUMMARY.afterglow_beat(summary.to_dict(), randf())
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = summary.reward
	close_left = STAY_CLOSE_SECONDS if close_window else 0.0


## The afterglow row the runtime applies: tail, flicks, HUD state, wings.
## Tail targets follow the active view family, not the act's start pose.
func presentation() -> PRESENTATION:
	var standing := view != null and str(view.family) == "standing"
	var row := PRESENTATION.new()
	row.tail_target = 0.55 if standing else 0.35
	row.tail_flicks = 2 if standing else 0
	row.wings = true
	return row


## Apply the row in its built order: pose weight, tail, HUD state.
## Returns whether the wing return is asked for; the session starts it through the wing owner.
func apply_presentation(pose: POSE_SESSION) -> bool:
	var row := presentation()
	if is_instance_valid(pose.pose()):
		pose.pose().target_amount = 1.0
		pose.pose().amount = 1.0
	pose.set_tail_target(row.tail_target)
	if row.tail_flicks > 0:
		pose.flick_tail(row.tail_flicks)
	if is_instance_valid(hud):
		hud.set_state(row.hud_state)
	return row.wings


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
	aftercare.pony = pony
	aftercare.body_language = plan.body_language
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


## One AFTERGLOW frame: the close window counts. The anatomy handle is staged by the act tick.
func phase_tick(delta: float, standing: bool) -> void:
	if standing:
		close_tick(delta)


func _finish_close() -> void:
	if close_rewarded:
		return
	close_rewarded = true
	close_left = 0.0
	var caressed := close_caress_seconds >= STAY_CLOSE_CARESS_SECONDS
	close_caress_earned = caressed
	LOG.debug("stay close reward caressed=%s positive=%s caress_seconds=%.1f", [
		str(caressed), str(positive), close_caress_seconds])
	_reward(caressed, positive)


## The close window's reward. The facade decided it; the bound face, reactions and meter present
## it, and the memory and history write one impression and one repair.
func _reward(caressed: bool, reward: bool) -> void:
	if is_instance_valid(WORLD.world_root()):
		var impression := MEMORY.Impression.new()
		impression.id = pony_id
		impression.event_id = event_id
		impression.slot = MEMORY.ImpressionSlot.STAY_CLOSE
		impression.mood = "happy" if reward else ""
		impression.romance = 1 if reward and caressed else 0
		if memory != null:
			memory.commit(impression)
	if not reward and caressed:
		var history: Dictionary = WORLD.mods().state(ACT_HISTORY.MOD_ID).rows
		if ACT_HISTORY.repair(history, pony_id, 1, ACT_HISTORY.day_now()):
			WORLD.mods().save()
	if face != null:
		face.set_face(0.9, FACE.AFTERGLOW_CLOSE_LIDS)
	if reactions != null:
		reactions.hearts_burst()
	if readiness != null:
		readiness.clear_cues()


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


