extends RefCounted
## The act's debug perf probe: timed chunks report microseconds here and one summary prints per
## window so a pony-specific stall can be attributed to a modifier without a live profiler.
##
## The host supplies the two gates and the header facts, so this module has no scene access. See
## `docs/perf.md` and `docs/settings.md`.

const WINDOW_S := 1.0

var _rows: Dictionary = {}
var _clock := 0.0
var _frames := 0

## Host boundary. A missing callable keeps the probe off, so tests can build one without a runtime.
var enabled := Callable()
## True while an act is running; the window clears outside it.
var active := Callable()
## Header facts for the summary line: pony, pose, state, near_mesh, tier, wings.
var header := Callable()
var log := Callable()


func on() -> bool:
	return enabled.is_valid() and bool(enabled.call())


## Record one timed chunk. Cheap no-op with the probe off.
func note(key: String, usec: int) -> void:
	if not on():
		return
	var row: Array = _rows.get(key, [0, 0, 0])
	row[0] = int(row[0]) + 1
	row[1] = int(row[1]) + usec
	row[2] = maxi(int(row[2]), usec)
	_rows[key] = row


## Close one call site: callers take the start stamp themselves.
func time(key: String, started_usec: int) -> void:
	if on():
		note(key, Time.get_ticks_usec() - started_usec)


func reset() -> void:
	_clock = 0.0
	_frames = 0
	_rows.clear()


## Accumulate a frame and print the summary at the window boundary.
func tick(delta: float) -> void:
	if not on() or (active.is_valid() and not bool(active.call())):
		reset()
		return
	_frames += 1
	_clock += delta
	if _clock < WINDOW_S:
		return
	var frames := maxi(1, _frames)
	_clock = 0.0
	_frames = 0
	var rows: Array = []
	for key: String in _rows:
		var row: Array = _rows[key]
		rows.append([key, int(row[0]), float(row[1]) / 1000.0, int(row[2])])
	_rows.clear()
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	var facts: Dictionary = header.call() if header.is_valid() else {}
	var text := "perf pony=%s pose=%s state=%d fps=%d frame=%.1fms near_mesh=%s tier=%s wings=%s" % [
		str(facts.get("pony", "?")), str(facts.get("pose", "")), int(facts.get("state", 0)),
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		str(facts.get("near_mesh", "?")), str(facts.get("tier", "?")),
		str(facts.get("wings", "no"))]
	for row: Array in rows:
		text += "\n\t%-16s %7.2fms/s per-frame %6.3fms max %6.2fms calls %d" % [
			str(row[0]), float(row[2]), float(row[2]) / frames, float(row[3]) / 1000.0,
			int(row[1])]
	if log.is_valid():
		log.call(text)
