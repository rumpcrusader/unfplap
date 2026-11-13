extends RefCounted
## The idle debug perf aggregator: timed chunks from every idle runtime report microseconds here
## and one block prints per window, so the mod's out-of-act cost can be attributed to a chunk and
## its worst pony.
##
## The host supplies the gate, the counts and the log, so this module has no scene access. The act
## probe is the separate `shared/perf.gd`. See `docs/perf.md` and `docs/settings.md`.

const WINDOW_S := 1.0

var _rows: Dictionary = {}
var _clock := 0.0
var _frames := 0
## Physics frames at the start of the window; `-1` until the first tick after a reset.
var _physics_mark := -1

## Host boundary. A missing callable keeps the probe off, so tests can build one without an entry
## node. Enabled only while both debug switches are on and no act is running.
var enabled := Callable()
## Header counts for the block: `{runtimes, mares}`.
var counts := Callable()
var log := Callable()


func on() -> bool:
	return enabled.is_valid() and bool(enabled.call())


## Record one timed chunk. Cheap no-op with the probe off.
func note(key: String, usec: int, owner := "") -> void:
	if not on():
		return
	var row: Array = _rows.get(key, [0, 0, 0, ""])
	row[0] = int(row[0]) + 1
	row[1] = int(row[1]) + usec
	if usec > int(row[2]):
		row[2] = usec
		row[3] = owner
	_rows[key] = row


func reset() -> void:
	_clock = 0.0
	_frames = 0
	_physics_mark = -1
	_rows.clear()


## Accumulate a frame and print the block at the window boundary.
func tick(delta: float) -> void:
	if not on():
		reset()
		return
	var physics := Engine.get_physics_frames()
	if _physics_mark < 0:
		_physics_mark = physics
	_frames += 1
	_clock += delta
	if _clock < WINDOW_S:
		return
	var frames := maxi(1, _frames)
	var ticks := float(maxi(0, physics - _physics_mark)) / float(frames)
	_physics_mark = physics
	_clock = 0.0
	_frames = 0
	var rows: Array = []
	for key: String in _rows:
		var row: Array = _rows[key]
		rows.append([key, int(row[0]), float(row[1]) / 1000.0, int(row[2]), str(row[3])])
	_rows.clear()
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	var facts: Dictionary = counts.call() if counts.is_valid() else {}
	var text := "perf idle runtimes=%d mares=%d fps=%d frame=%.1fms phys=%.1fms tick=%.2f" % [
		int(facts.get("runtimes", 0)), int(facts.get("mares", 0)),
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		ticks]
	for row: Array in rows:
		var owner := str(row[4])
		text += "\n\t%-20s %8.2fms/s %7.1fus/call calls %d max %.2fms %s" % [
			str(row[0]), float(row[2]), float(row[2]) * 1000.0 / float(maxi(1, int(row[1]))),
			int(row[1]), float(row[3]) / 1000.0, owner if not owner.is_empty() else "-"]
	if log.is_valid():
		log.call(text)
