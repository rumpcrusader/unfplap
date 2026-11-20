extends RefCounted
## The act's debug perf probe. Timed chunks land here and a per-window summary names the worst, so a
## stall can be pinned on a modifier without a live profiler.
##
## The typed `Host` carries the gates, sinks, header values and idle forward; no scene access.

const TREE := preload("res://mods/unfplap/shared/perf_tree.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
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

## One runtime's side of the act probe. Callbacks are filled once by the runtime; this module owns
## the header's shape and never reads a scene.
class Host extends RefCounted:
	## Both debug switches are on.
	var enabled_cb := Callable()
	var log_cb := Callable()
	## The panel sink for one window.
	var show_cb := Callable()
	## The pony, the act's start pose and its state, as the header line names them. The act's
	## running gate and the idle window's gate both come from that state.
	var id_cb := Callable()
	var pose_cb := Callable()
	var state_cb := Callable()
	## The live header values, read only when a window closes: the shot's forward and smoothed
	## side lean, the latched caress hands, and the pony's near-mesh flag and simulation tier.
	var lean_forward_cb := Callable()
	var lean_side_cb := Callable()
	var hand_left_cb := Callable()
	var hand_right_cb := Callable()
	var near_mesh_cb := Callable()
	var tier_cb := Callable()
	var wing_hold_cb := Callable()
	var winged_cb := Callable()
	## The idle window this pony's chunks also feed while no act runs: the log module's sink. The
	## aggregator itself is `shared/perf_idle.gd`'s.
	var idle_note_cb := Callable()

	static func _value(callback: Callable, fallback: Variant = null) -> Variant:
		return callback.call() if callback.is_valid() else fallback

	func id() -> String:
		return str(_value(id_cb, ""))

	func enabled() -> bool:
		return bool(_value(enabled_cb, false))

	func state() -> int:
		return int(_value(state_cb, ACT_STATE.STATE_IDLE))

	## Whether an act owns this pony's frame.
	func active() -> bool:
		return state() != ACT_STATE.STATE_IDLE

	## True while the idle window owns this pony's chunks: the switches are on and no act runs.
	func idle() -> bool:
		return enabled() and state() == ACT_STATE.STATE_IDLE

	## Header facts for one summary line. The runtime supplies the live values; the keys and the
	## display strings are this module's.
	func header() -> Dictionary:
		return {
			"pony": id(),
			"pose": str(_value(pose_cb, "")),
			"state": state(),
			"lean": "%.2f/%.2f" % [float(_value(lean_forward_cb, 0.0)),
				float(_value(lean_side_cb, 0.0))],
			"hands": hands(),
			"near_mesh": label(near_mesh_cb),
			"tier": label(tier_cb),
			"wings": wings(),
		}

	## Which caress hands are latched, as a compact flag.
	func hands() -> String:
		var left := bool(_value(hand_left_cb, false))
		var right := bool(_value(hand_right_cb, false))
		return "LR" if left and right else ("L" if left else ("R" if right else "-"))

	## The wing state: a hold wins over a winged body, a body without wings reads `no`.
	func wings() -> String:
		if bool(_value(wing_hold_cb, false)):
			return "held"
		if bool(_value(winged_cb, false)):
			return "winged"
		return "no"

	## One nullable engine value as the header prints it; `?` when the game build has none.
	static func label(callback: Callable) -> String:
		var value: Variant = _value(callback)
		return str(value) if value != null else "?"

	## One idle chunk for this pony, keyed by its id like the row's owner. The log module owns the
	## one shared window; a missing sink keeps the chunk out.
	func note_idle(key: String, usec: int) -> void:
		if idle_note_cb.is_valid():
			idle_note_cb.call(key, usec, id())


var _rows: Dictionary = {}
var _clock := 0.0
var _frames := 0
## Physics frames at the start of the window; `-1` until the first tick after a reset.
var _physics_mark := -1

## Host boundary. A missing callable keeps the probe off, so tests can build one without a runtime.
var enabled := Callable()
## The act gate: false clears the window.
var active := Callable()
## Header facts for the summary line: pony, pose, state, lean, hands, near_mesh, tier, wings.
var header := Callable()
var log := Callable()
## The panel sink for one window: the laid-out rows plus the header and engine facts as data.
var show := Callable()
## The idle window this pony's chunks also feed while no act runs: its gate and the host's
## forwarding sink.
var idle := Callable()
var idle_note := Callable()
## The typed host owns the callbacks this probe binds; keeping it here keeps those Callables
## valid, because a Callable does not hold its RefCounted receiver alive.
var host: Host = null


## Build one runtime's probe with its host boundary bound once. Missing callables keep it off.
static func build(host_in: Host) -> RefCounted:
	var probe := new()
	probe.host = host_in
	var host := host_in
	probe.enabled = Callable(host, "enabled")
	probe.active = Callable(host, "active")
	probe.header = Callable(host, "header")
	probe.log = host.log_cb
	probe.show = host.show_cb
	probe.idle = Callable(host, "idle")
	probe.idle_note = Callable(host, "note_idle")
	return probe


func on() -> bool:
	return enabled.is_valid() and bool(enabled.call())


## True while the idle window owns this pony's chunks.
func idle_on() -> bool:
	return idle.is_valid() and bool(idle.call())


## Record one timed chunk; with the idle window owning the frame it is forwarded there.
func note(key: String, usec: int) -> void:
	if on():
		var row: Array = _rows.get(key, [0, 0, 0])
		row[0] = int(row[0]) + 1
		row[1] = int(row[1]) + usec
		row[2] = maxi(int(row[2]), usec)
		_rows[key] = row
	if idle_on():
		idle_note.call(key, usec)


## Close one call site: callers take the start stamp themselves.
func time(key: String, started_usec: int) -> void:
	if on() or idle_on():
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
