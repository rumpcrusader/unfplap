extends RefCounted
## The idle debug perf aggregator: timed chunks from every idle runtime report microseconds here
## and one block prints per window, so the mod's out-of-act cost can be attributed to a chunk and
## its worst pony.
##
## The host supplies the gate, the counts and the log, so this module has no scene access. The act
## probe is the separate `shared/perf.gd`. See `docs/perf.md` and `docs/settings.md`.

const TREE := preload("res://mods/unfplap/shared/perf_tree.gd")
const WINDOW_S := 1.0

## Chunk containment outside an act. A chunk without an entry, or whose parent did not print in
## this window, is a root; the anatomy controller's own chunks nest under its whole process.
const PARENTS := {
	"entry_caption": "entry_process",
	"entry_initiation": "entry_process",
	"entry_negotiation": "entry_process",
	"entry_watch": "entry_process",
	"entry_hint": "entry_process",
	"offer_scan": "entry_process",
	"offer_cone": "offer_scan",
	"offer_gate": "offer_scan",
	"offer_rows": "offer_gate",
	"offer_policy": "offer_gate",
	"runtime_anatomy_sync": "runtime_physics",
	"runtime_facts": "runtime_physics",
	"runtime_presentation": "runtime_physics",
	"runtime_history": "runtime_physics",
	"anatomy_coat_line": "anatomy_process",
	"anatomy_visibility": "anatomy_process",
}

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
## The panel sink for one window: the laid-out rows plus the counts and engine facts as data.
var show := Callable()


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
	var totals: Dictionary = {}
	var peaks: Dictionary = {}
	for key: String in _rows:
		var row: Array = _rows[key]
		totals[key] = [float(row[1]) / 1000.0, int(row[0])]
		peaks[key] = [int(row[2]), str(row[3])]
	_rows.clear()
	var entries: Array = TREE.layout(totals, PARENTS)
	var facts: Dictionary = counts.call() if counts.is_valid() else {}
	var fps := Engine.get_frames_per_second()
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var text := "perf idle runtimes=%d mares=%d fps=%d frame=%.1fms phys=%.1fms tick=%.2f" % [
		int(facts.get("runtimes", 0)), int(facts.get("mares", 0)),
		fps, frame_ms, phys_ms, ticks]
	for entry: Dictionary in entries:
		var key := str(entry["key"])
		var total := float(entry["total"])
		# A residual row has no call of its own: only the unmeasured time is real.
		var per_call := "-"
		var calls := "-"
		var peak := "-"
		var owner := "-"
		if not bool(entry["self"]):
			var row: Array = peaks.get(key, [0, ""])
			var count := maxi(1, int(entry["calls"]))
			per_call = "%.1fus" % (total * 1000.0 / float(count))
			calls = str(int(entry["calls"]))
			peak = "%.2fms" % (float(row[0]) / 1000.0)
			owner = str(row[1]) if not str(row[1]).is_empty() else "-"
		text += "\n%-28s %8.2fms/s %8s/call calls %4s max %7s %s" % [
			str(entry["prefix"]) + key, total, per_call, calls, peak, owner]
	if log.is_valid():
		log.call(text)
	if show.is_valid():
		var info := facts.duplicate()
		info["fps"] = fps
		info["frame_ms"] = frame_ms
		info["phys_ms"] = phys_ms
		info["tick"] = ticks
		show.call(entries, info)
