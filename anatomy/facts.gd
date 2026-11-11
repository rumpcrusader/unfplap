extends RefCounted
## The typed anatomy context. The runtime owns one per pony and rewrites it as the state
## changes; the persistent controller and the per-act handle read only this object, never the
## runtime node. Callbacks are the host boundary for logging, the perf probe and the body-coat
## smack hook.
##
## See `docs/anatomy.md` (`## Architecture`).

var state := 0
var pose_id := ""
var depth := 0.0
var penetration_m := 0.0
var climaxes := 0
var size_scale := 1.0
var auto_pace := 1.0
var fluid_ground_y := 0.0
var penetration_reach := 0.2
## The act's bed frame, or null outside a missionary act.
var bed_frame: Variant = null
var cycle_phase := "normal"
## Host callbacks. A missing callback is a no-op, so tests can build a context without a runtime.
var perf_note := Callable()
var log := Callable()
var body_coat_smack := Callable()


func perf(chunk: String, usec: int) -> void:
	if perf_note.is_valid():
		perf_note.call(chunk, usec)


func write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)


func smack_body_coat() -> void:
	if body_coat_smack.is_valid():
		body_coat_smack.call()
