extends "res://mods/unfplap/tests/support/suite.gd"
## The one profiler: the gate, the open-frame stack, one window a second, the rows and the panel
## helpers.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/perf/test_perf.gd

const PERF := preload("res://mods/unfplap/shared/perf.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

var perf_read := true


func _switch() -> bool:
	return perf_read


func _frame() -> void:
	PERF.start_frame()
	PERF.end_frame()


## One frame carrying `chunk`, so a window has a row of its own to look for.
func _frame_with(chunk: String) -> void:
	PERF.start_frame()
	PERF.begin(chunk)
	PERF.end(chunk)
	PERF.end_frame()


func _has(rows: Array, key: String) -> bool:
	for row: Dictionary in rows:
		if str(row.get("key", "")) == key:
			return true
	return false


func _row(rows: Array, key: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("key", "")) == key:
			return row
	return {}


func run() -> void:
	LOG.enabled = true
	PERF.bind(Callable(self, "_switch"), null)
	await _check_gate()
	await _check_window()
	await _check_tree()
	await _check_discard()
	_check_panel()
	if failures == 0:
		print("PERF_PASS")
	finish()


## Both switches on is the gate; off, a chunk costs nothing and the window stays shut.
func _check_gate() -> void:
	perf_read = false
	PERF.start_frame()
	check(not PERF.enabled, "the gate needs the perf switch")
	PERF.begin("off_chunk")
	check(PERF._open == 0, "an off frame opens no chunk")
	PERF.end("off_chunk")
	PERF.end_frame()
	perf_read = true
	LOG.enabled = false
	PERF.start_frame()
	check(not PERF.enabled, "the gate needs the debug switch")
	PERF.end_frame()
	LOG.enabled = true
	PERF.start_frame()
	check(PERF.enabled, "both switches open the gate")
	check(PERF._open == 1, "the entry frame is the first open chunk")
	PERF.end_frame()
	check(PERF._open == 0, "the entry frame closes with the frame")


## One window a second: the rows of a closed window are readable, and a short window is not.
func _check_window() -> void:
	# The window that the gate check left open closes here, so the next one starts fresh.
	await create_timer(1.1).timeout
	_frame()
	_frame_with("window_marker")
	check(not _has(PERF.last_frame(), "window_marker"),
		"a window under a second has not closed")
	await create_timer(1.1).timeout
	_frame_with("window_marker")
	var rows := PERF.last_frame()
	check(_has(rows, "window_marker"), "the window closes a second after it opened")
	check(_has(rows, "entry_process"), "the entry frame is a row of the window")
	var marker := _row(rows, "window_marker")
	check(int(marker.get("depth", -1)) == 1, "a chunk of the entry frame sits one level down")
	check(int(marker.get("calls", 0)) >= 1, "the row carries its call count")
	check(float(marker.get("max", 0.0)) >= 0.0, "the row carries its peak")


## Nesting comes from the open stack: an inner chunk is a child, and the parent keeps a residual.
func _check_tree() -> void:
	await create_timer(1.1).timeout
	PERF.start_frame()
	PERF.begin("outer")
	_sleep(0.002)
	PERF.begin("inner")
	_sleep(0.002)
	PERF.end("inner")
	PERF.end("outer")
	PERF.end_frame()
	var rows: Array = []
	for attempt in 3:
		await create_timer(0.5).timeout
		PERF.start_frame()
		PERF.begin("outer")
		PERF.end("outer")
		PERF.end_frame()
		rows = PERF.last_frame()
		if _has(rows, "outer"):
			break
	var outer := _row(rows, "outer")
	var inner := _row(rows, "inner")
	check(not outer.is_empty() and not inner.is_empty(), "both nested chunks reach the window")
	check(int(outer.get("depth", -1)) == 1, "the outer chunk is one level down")
	check(int(inner.get("depth", -1)) == 2, "the inner chunk nests under the outer one")
	check(str(inner.get("prefix", "")).length() > str(outer.get("prefix", "")).length(),
		"the child row is indented past its parent")
	check(_has(rows, "self"), "an outer chunk with children reports its own residual")
	check(not bool(inner.get("self", true)), "a measured chunk is not a residual")
	var ordered := true
	for index in range(1, rows.size()):
		if int(rows[index - 1]["depth"]) == int(rows[index]["depth"]) \
				and float(rows[index - 1]["total"]) < float(rows[index]["total"]):
			ordered = false
	check(ordered, "siblings print largest first")


## A chunk that never closed, or closed out of order, drops the window it belonged to.
func _check_discard() -> void:
	await create_timer(1.1).timeout
	PERF.start_frame()
	PERF.begin("sentinel")
	PERF.end("sentinel")
	PERF.begin("ghost")
	PERF.end_frame()
	check(not _has(PERF.last_frame(), "sentinel"), "an open chunk drops its whole window")
	check(PERF._open == 0, "a dropped window leaves the stack empty")
	await create_timer(1.1).timeout
	PERF.start_frame()
	PERF.begin("first")
	PERF.begin("second")
	PERF.end("first")
	check(PERF._open == 0, "an out-of-order close drops the window")
	PERF.end_frame()


## The panel's helpers: the caption, the row height and the window totals.
func _check_panel() -> void:
	var info := {"fps": 60, "frame_ms": 12.5, "phys_ms": 1.5, "tick": 1.0, "draws": 40}
	var caption := PERF.View.caption(info)
	check(caption.begins_with("perf"), "the caption names the panel")
	check(caption.contains("60 fps") and caption.contains("12.5ms"), "the caption carries the frame")
	check(is_equal_approx(PERF.View.height([]), PERF.ROW_H),
		"an empty window is one total row tall")
	check(is_equal_approx(PERF.View.height([{}, {}]), PERF.ROW_H * 3.0),
		"two rows and the total row set the list height")
	var rows := [
		{"key": "a", "depth": 0, "prefix": "", "self": false, "total": 2.0, "calls": 1, "max": 1.5},
		{"key": "b", "depth": 1, "prefix": "├─ ", "self": false, "total": 1.0, "calls": 4, "max": 0.5},
	]
	var totals := PERF.View.totals(rows)
	check(is_equal_approx(float(totals["avg"]), 2.0), "the total row sums the roots")
	check(is_equal_approx(float(totals["max"]), 1.5), "the total row keeps the worst call")
	check(is_equal_approx(PERF.View.per_frame(4, 2), 2.0), "calls divide by the frame count")
	check(is_equal_approx(PERF.View.per_frame(4, 0), 0.0), "a window with no frames reports none")


## Burn a little time so a chunk measures above zero; the profiler's own clock is the only one.
func _sleep(seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < until:
		pass
