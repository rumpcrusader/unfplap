extends RefCounted
## The post-act afterglow phase: the private afterglow beat, the standing close window with its
## caress reward and the presentation the phase asks for. The runtime owns the AFTERGLOW state,
## its end and every scene result; this facade owns the close-window timer and its decision.
## Contract: `docs/afterglow.md`.

const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")

## The close window only exists in the standing afterglow.
const STAY_CLOSE_SECONDS := 8.0
const STAY_CLOSE_CARESS_SECONDS := 2.5

## The act pose this afterglow belongs to, for the presentation row.
var pose := ""
## The pose view the runtime carries into the next `begin()`; its `afterglow` profile owns the
## close-window decision.
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


## Carry the pose view into the next afterglow. The runtime binds it once per act.
func bind_view(view_in: RefCounted) -> void:
	view = view_in


## Start a fresh afterglow for this pose. The row's `afterglow.close_window` opens the close
## window immediately.
func begin(pose_id: String, summary: Dictionary) -> void:
	pose = pose_id
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
## row cannot make (the wings, the face beat, the summary commit). The held pose is the act's
## current pose: the row names no pose mode and no afterglow pose.
func presentation() -> Dictionary:
	var standing := pose == "standing"
	return {
		"tail_target": 0.55 if standing else 0.35,
		"tail_flicks": 2 if standing else 0,
		"hud_state": "AFTERGLOW",
		"wings": true,
	}


## Clear every value for the next act. The callbacks stay.
func reset() -> void:
	pose = ""
	close_window = false
	beat = ""
	close_left = 0.0
	close_caress_seconds = 0.0
	close_rewarded = false
	close_caress_earned = false
	positive = false


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
