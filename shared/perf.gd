extends RefCounted
## The act's debug perf probe: timed chunks report microseconds here and one summary prints per
## window so a pony-specific stall can be attributed to a modifier without a live profiler.
##
## The host supplies the two gates and the header facts, so this module has no scene access. See
## `docs/perf.md` and `docs/settings.md`.

const TREE := preload("res://mods/unfplap/shared/perf_tree.gd")
const WINDOW_S := 1.0

## Chunk containment inside one act tick. A chunk without an entry, or whose parent did not print
## in this window, is a root; the modifier pass reports under the render-time `runtime_process`.
const PARENTS := {
	"pose_tick": "runtime_physics",
	"runtime_facts": "runtime_physics",
	"pose_fanout": "runtime_physics",
	"runtime_presentation": "runtime_physics",
	"wings_tick": "runtime_presentation",
	"caress_tick": "runtime_physics",
	"caress_precise": "caress_tick",
	"caress_path": "caress_precise",
	"caress_surface": "caress_precise",
	"caress_select": "caress_surface",
	"caress_ensure": "caress_surface",
	"caress_skin": "caress_surface",
	"caress_closest": "caress_surface",
	"caress_ray": "caress_surface",
	"caress_blur": "caress_surface",
	"caress_tri": "caress_surface",
	"caress_arm": "pose_fanout",
	"kiss_tick": "runtime_physics",
	"runtime_ai": "runtime_physics",
	"anatomy_tick": "runtime_physics",
	"anatomy_afterglow": "runtime_physics",
	"runtime_talk": "runtime_physics",
	"runtime_camera": "runtime_physics",
	"runtime_face": "runtime_physics",
	"pose_recipe": "runtime_process",
	"pose_prone": "runtime_process",
	"body_sway": "runtime_process",
	"ear_twitch": "runtime_process",
	"tail_pose": "runtime_process",
}

var _rows: Dictionary = {}
var _clock := 0.0
var _frames := 0
## Physics frames at the start of the window; `-1` until the first tick after a reset.
var _physics_mark := -1

## Host boundary. A missing callable keeps the probe off, so tests can build one without a runtime.
var enabled := Callable()
## True while an act is running; the window clears outside it.
var active := Callable()
## Header facts for the summary line: pony, pose, state, lean, hands, near_mesh, tier, wings.
var header := Callable()
var log := Callable()
## The panel sink for one window: the laid-out rows plus the header and engine facts as data.
var show := Callable()


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
	_physics_mark = -1
	_rows.clear()


## Accumulate a frame and print the summary at the window boundary.
func tick(delta: float) -> void:
	if not on() or (active.is_valid() and not bool(active.call())):
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
		peaks[key] = int(row[2])
	_rows.clear()
	var entries: Array = TREE.layout(totals, PARENTS)
	var facts: Dictionary = header.call() if header.is_valid() else {}
	var fps := Engine.get_frames_per_second()
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var text := "perf pony=%s pose=%s state=%d fps=%d frame=%.1fms phys=%.1fms lean=%s hands=%s tick=%.2f draws=%d prims=%d near_mesh=%s tier=%s wings=%s" % [
		str(facts.get("pony", "?")), str(facts.get("pose", "")), int(facts.get("state", 0)),
		fps, frame_ms, phys_ms,
		str(facts.get("lean", "?")), str(facts.get("hands", "?")), ticks,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		str(facts.get("near_mesh", "?")), str(facts.get("tier", "?")),
		str(facts.get("wings", "no"))]
	for entry: Dictionary in entries:
		var key := str(entry["key"])
		var total := float(entry["total"])
		# A residual row has no call of its own: only the unmeasured time is real.
		var peak := "-"
		var calls := "-"
		if not bool(entry["self"]):
			peak = "%.2fms" % (float(peaks.get(key, 0)) / 1000.0)
			calls = str(int(entry["calls"]))
		text += "\n%-28s %8.2fms/s per-frame %8s max %7s calls %s" % [
			str(entry["prefix"]) + key, total, "%.3fms" % (total / float(frames)), peak, calls]
	if log.is_valid():
		log.call(text)
	if show.is_valid():
		for entry: Dictionary in entries:
			entry["max"] = float(peaks.get(str(entry["key"]), 0)) / 1000.0
		var info := facts.duplicate()
		info["fps"] = fps
		info["frame_ms"] = frame_ms
		info["phys_ms"] = phys_ms
		info["tick"] = ticks
		info["frames"] = frames
		show.call(entries, info)
