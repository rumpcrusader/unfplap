extends RefCounted
## The act's one state, timer, clock and value owner. One per pony, created once and reset per act.
## It writes `state` through `_set_state()`; the runtime keeps the transition bodies and the side
## effects and asks this owner for the timer verdict, the clock values and the act's own values.
##
## See `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")

const State := ACT_STATE.State

const CLIMAX_SECONDS := 5.0
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## The scene gate's running-check cadence while the act is live.
const CHECK_SECONDS := 0.25

## The ordered tick's transition verbs. `tick_timers()` only counts down; the runtime applies the
## verb through its transition body.
const PHASE_NONE := 0
const ENTER_ACTIVE := 1
const FINISH_CLIMAX := 2
const FINISH_RESTORE := 3

## Bound once by the runtime. All are per-pony and outlive one act.
var host: ACT_NODE = null
var context: ACT_CONTEXT = null
## The ordered start ledger. Set once by the runtime; `begin()` is its one entry.
var start: Variant = null

## The live act state. `_set_state()` is the only writer.
var state: int = State.IDLE

## The act's own values, written at the start boundary and read by the view, the idle schedule,
## the scene gate and the ledgers. `pony_id` is the stable id; `display_name` is the presented
## form's name.
var pose_id := ""
var source := ""
var bed: Node3D = null
var event_id := ""
## The act's serial from `ponies`' allocator; `event_id` embeds it.
var serial := 0
var pony_id := ""
var display_name := "the pony"
var preferences: Dictionary = {}
var act_prompts: Dictionary = {}
var features: Dictionary = {}
var player_pony := false
var presentation_config: Dictionary = {}
var profile: Dictionary = {}
var caress_quality := ""
var forced_glance := ""
## Act-scope bookkeeping the ledgers read: what this act borrowed, what it finalized, and the
## values the aftercare plan is built from. `finalized` makes the post-act bookkeeping one-shot.
var posture_owned := false
var finalized := false
var stopped_by_her := false
var aftercare_min := 0
var cue_gap := 0.0
var first_time := false
var tolerance_warning_key := ""
var act_spoken_at := -1e9

## The `POSING_IN` timer: the pose settles into the act after this many seconds.
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
## The 0.25 s running-check accumulator.
var _check_clock := 0.0
## The `CLIMAX` state's 0..1 progress, read by the shot camera.
var _climax_progress := 0.0
## Processed-time clock. It only advances while the runtime ticks, so a paused tree freezes the
## act timing; it is never reset between acts.
var _clock_s := 0.0
var _act_seconds := 0.0


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Start one act. The ledger owns the recipe and the order; the session only enters it.
func begin(pose: String, bed_in: Variant, act_source: String, skip_presentation := false) -> bool:
	if start == null:
		return false
	return bool(start.run(pose, bed_in, act_source, skip_presentation))


## The one state writer. The scene gate's live values follow every transition.
func _set_state(next: int) -> void:
	state = next
	if context == null or context.gate == null:
		return
	var pony_node: Variant = host.pony if host != null else null
	context.gate.bind(pony_node, context.pose)
	context.gate.configure(state, pony_id, features)


## Elapsed act time, in seconds. The view reads it; `reset_act()` clears it.
func act_seconds() -> float:
	return _act_seconds


## The processed-time clock. It is monotonic across acts.
func clock_s() -> float:
	return _clock_s


func state_name() -> String:
	match state:
		State.POSING_IN:
			return "POSING_IN"
		State.ACTIVE:
			return "ACTIVE"
		State.CLIMAX:
			return "CLIMAX"
		State.AFTERGLOW:
			return "AFTERGLOW"
		State.RESTORE:
			return "RESTORE"
	return "IDLE"


## Start-of-act reset. The session itself is reused; only the act's own timers and elapsed time
## clear. The processed-time clock stays monotonic across acts.
func reset_act() -> void:
	_act_seconds = 0.0
	clear_phase()


## Clear the phase timers after a stop that did not run the restore timer.
func clear_phase() -> void:
	_pose_in_left = 0.0
	_climax_left = 0.0
	_restore_left = 0.0
	_check_clock = 0.0
	_climax_progress = 0.0


## Advance the act's processed-time clock. A negative frame delta is clamped to zero.
func tick_clock(delta: float) -> void:
	_clock_s += maxf(0.0, delta)


func advance_act_seconds(delta: float) -> void:
	_act_seconds += delta


## The 0.25 s running-check cadence. True only on the tick that crosses the interval.
func consume_check_clock(delta: float) -> bool:
	_check_clock += delta
	if _check_clock < CHECK_SECONDS:
		return false
	_check_clock = 0.0
	return true


func refresh_climax_progress() -> void:
	_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)


## Advance the one active transition timer. The caller owns what each verb does.
func tick_timers(delta: float) -> int:
	match state:
		State.POSING_IN:
			_pose_in_left -= delta
			if _pose_in_left <= 0.0:
				return ENTER_ACTIVE
		State.CLIMAX:
			_climax_left -= delta
			if _climax_left <= 0.0:
				return FINISH_CLIMAX
		State.RESTORE:
			_restore_left -= delta
			if _restore_left <= 0.0:
				return FINISH_RESTORE
	return PHASE_NONE


func enter_active() -> void:
	_set_state(State.ACTIVE)


func begin_pose_in() -> void:
	_set_state(State.POSING_IN)
	_pose_in_left = POSE_IN_SECONDS


func enter_climax() -> void:
	_set_state(State.CLIMAX)
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0


func enter_afterglow() -> void:
	_set_state(State.AFTERGLOW)


func begin_restore() -> void:
	_set_state(State.RESTORE)
	_restore_left = RESTORE_SECONDS


func finish_restore() -> void:
	enter_idle()


func enter_idle() -> void:
	_set_state(State.IDLE)
	_pose_in_left = 0.0
	_climax_left = 0.0
	_restore_left = 0.0
	_climax_progress = 0.0
