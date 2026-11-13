extends RefCounted
## The post-act afterglow phase: the self-end roll, the `[stay]` hold and the standing close
## window with its caress reward. The runtime owns the AFTERGLOW state transition and every scene
## result (wings, pose, tail, HUD, face, memory commit); this facade owns the timers and the
## decisions. Contract: `docs/afterglow.md`.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/history/summary.gd")

## After this long the mare may choose to end the afterglow herself. Being held or caressed
## lowers the chance; an accepted `[stay]` pauses the roll entirely.
const SELF_END_SECONDS := 16.0
const SELF_END_CHECK_S := 1.0
const SELF_END_CHANCE_CLOSE := 0.12
const SELF_END_CHANCE_ALONE := 0.30
## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5
const STAY_HOLD_MIN_S := 0.5
const STAY_HOLD_MAX_S := 600.0

## Pose of the afterglow that owns these timers.
var pose := ""
var elapsed := 0.0
## One short private afterglow beat, rolled once when the afterglow begins. Empty means silence.
var beat := ""
var hold_until := 0.0
var self_end_clock := 0.0
var close_left := 0.0
var close_caress_seconds := 0.0
var close_rewarded := false
## True only when the standing close window earned its caress reward.
var close_caress_earned := false
## True when the summary of the act being held is a positive one.
var positive := false
## The game's `[stay: SECONDS]` executor, kept across acts once found.
var executor: Node

## Host boundary. Missing callbacks are no-ops.
var log := Callable()
var clock := Callable()
## True while the runtime is still in its AFTERGLOW state.
var in_phase := Callable()
var speech_busy := Callable()
var player_close := Callable()
var caress_active := Callable()
## The self-end roll chose to end; the runtime leaves afterglow.
var on_end := Callable()
## The close window elapsed: `(caressed, positive)`.
var on_stay_close := Callable()


## Start a fresh afterglow for this pose. Standing opens its close window immediately.
func begin(pose_id: String, summary: Dictionary) -> void:
	pose = pose_id
	elapsed = 0.0
	beat = ACT_SUMMARY.afterglow_beat(summary, randf())
	hold_until = 0.0
	self_end_clock = 0.0
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = bool(summary.get("reward", false))
	close_left = STAY_CLOSE_SECONDS if pose_id == CATALOG.STANDING else 0.0


## The presentation the runtime applies when the act enters the held afterglow. The facade owns
## the phase decisions; the runtime applies the row in this order and owns the scene calls the
## row cannot make (the wings, the face beat, the summary commit).
func presentation() -> Dictionary:
	var standing := pose == CATALOG.STANDING
	return {
		"pose_mode": "standing" if standing else "afterglow",
		"afterglow_pose": "" if standing else pose,
		"tail_target": 0.55 if standing else 0.35,
		"tail_flicks": 2 if standing else 0,
		"hud_state": "AFTERGLOW",
		"wings": true,
	}


## Clear every value for the next act. The executor and the callbacks stay.
func reset() -> void:
	pose = ""
	elapsed = 0.0
	beat = ""
	hold_until = 0.0
	self_end_clock = 0.0
	close_left = 0.0
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = false


func advance(delta: float) -> void:
	elapsed += delta


static func self_end_chance(close: bool) -> float:
	return SELF_END_CHANCE_CLOSE if close else SELF_END_CHANCE_ALONE


## One roll after the minimum time and after any accepted `[stay]` expires. Talking or a busy
## director defers the roll instead of cancelling it.
func self_end_tick(delta: float) -> void:
	if elapsed < SELF_END_SECONDS:
		return
	if _now() < hold_until:
		return
	self_end_clock -= delta
	if self_end_clock > 0.0:
		return
	self_end_clock = SELF_END_CHECK_S
	if _truthy(speech_busy):
		return
	var close := _truthy(player_close)
	if randf() >= self_end_chance(close):
		return
	_write_log("afterglow self end after %.1fs close=%s" % [elapsed, str(close)])
	if on_end.is_valid():
		on_end.call()


## The game's action executor owns `[stay: SECONDS]`. A permitted stay during the afterglow is
## her agreement to keep the moment going, so pause the self-end roll for that long.
func bind_action_executor(director: Variant, pony_id: String) -> void:
	if is_instance_valid(executor) and executor.is_inside_tree():
		return
	executor = null
	if director == null or not is_instance_valid(director):
		return
	var actions: Variant = director.get("actions")
	if actions == null:
		return
	var executors: Variant = actions.get("executors")
	if not executors is Dictionary:
		return
	var found: Variant = (executors as Dictionary).get(pony_id)
	if not found is Node:
		return
	executor = found as Node
	var callback := Callable(self, "receive_action")
	if executor.has_signal("outcome") and not executor.is_connected("outcome", callback):
		executor.connect("outcome", callback)


## The game's action executor reports a finished action here. Only an accepted `[stay]` during the
## afterglow matters.
func receive_action(event: Dictionary) -> void:
	if not _truthy(in_phase):
		return
	if str(event.get("type", "")) != "stay":
		return
	if str(event.get("status", "")) != "accepted":
		return
	var duration := 30.0
	if is_instance_valid(executor):
		var movement: Variant = executor.get("movement")
		if movement is Dictionary:
			duration = float((movement as Dictionary).get("duration_s", 30.0))
	duration = clampf(duration, STAY_HOLD_MIN_S, STAY_HOLD_MAX_S)
	hold_until = maxf(hold_until, _now() + duration)
	_write_log("afterglow hold extended %.0fs by [stay]" % duration)


## Count caress time and run the standing close window down. The window opens in `begin()`.
func close_tick(delta: float) -> void:
	if pose != CATALOG.STANDING or close_left <= 0.0:
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


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


func _truthy(callback: Callable) -> bool:
	return bool(callback.call()) if callback.is_valid() else false


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
