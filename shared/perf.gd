extends RefCounted
## Service: perf
## Contract: this header, frozen; edit only with the user's approval
## Scope: process
## Import: shared/perf.gd
## The mod's only profiler: one window a second, one open-frame stack and one corner panel.

const LOG := preload("res://mods/unfplap/shared/log.gd")
## One window's length, in seconds of wall clock.
const WINDOW_S := 1.0
## The frame the entry opens and closes around its own process.
const ENTRY := "entry_process"
## The smallest parent residual worth a row, in milliseconds inside one window.
const MIN_SELF_MS := 0.01
## The open stack's first capacity; it grows when an act nests deeper.
const STACK := 64
const BAR := "│  "
const GAP := "   "
const BRANCH := "├─ "
const LAST := "└─ "
const PANEL_W := 620.0
const PANEL_PAD := 10.0
const PANEL_AT := Vector2(28.0, 26.0)
const INNER_W := PANEL_W - PANEL_PAD * 2.0
const ROW_H := 16.0
const FONT_SIZE := 11
const CAPTION_FONT := 13
## A fixed cell for one tree glyph, so the indentation lines up without a monospace font.
const CELL_W := 7.0
const NAME_GAP := 6.0
const AVG_W := 78.0
const MAX_W := 60.0
const CALLS_W := 46.0
const COL_GAP := 8.0
const VALUE_W := AVG_W + MAX_W + CALLS_W + COL_GAP * 2.0
const TOTAL_LABEL := "unfplap total"
## The debug targets: a column reads red at its target and green at zero.
const AVG_LIMIT := 100.0
const MAX_LIMIT := 0.5
const CALLS_BASE := 1.0
const CALLS_LIMIT := 2.0
const GREEN := Color("7ee08a")
const AMBER := Color("ffd166")
const RED := Color("ff6b81")
const ACCENT := Color("ffa8c7")
const INK := Color("f4f1ff")
const SHADE := Color("1a1624")
const MUTED := Color(0.957, 0.945, 1.0, 0.6)

## Both switches on. Recomposed once per frame, so a switch edit lands at the next boundary.
static var enabled := false

## The perf switch read and the node that parents the panel: the entry binds them once.
static var _read := Callable()
static var _entry: Node = null
## The panel, created on the first printed window.
static var _view: View = null

# The open frames: one key and one start stamp per level, preallocated and reused.
static var _keys := PackedStringArray()
static var _stamps := PackedInt64Array()
static var _open := 0

# The window: per key its total, calls, peak and the frame it was opened under.
static var _total: Dictionary = {}
static var _calls: Dictionary = {}
static var _peak: Dictionary = {}
static var _parent: Dictionary = {}
## The rows of the last closed window, as the panel and a suite read them.
static var _rows: Array = []
static var _frames := 0
static var _physics := -1
static var _started := 0


## Store the perf switch read and the entry node the panel hangs under. Idempotent.
static func bind(perf_read: Callable, entry: Node) -> void:
	_read = perf_read
	_entry = entry


## Recompose the gate and open the entry's frame; a closed gate drops the window.
static func start_frame() -> void:
	enabled = _read.is_valid() and bool(_read.call()) and LOG.enabled
	if not enabled:
		_hide()
		_reset()
		return
	if _keys.size() == 0:
		_keys.resize(STACK)
		_stamps.resize(STACK)
	begin(ENTRY)


## Close the entry's frame, then print and hand over the window at the boundary.
static func end_frame() -> void:
	if not enabled:
		return
	if _open != 1 or _keys[0] != ENTRY:
		_fail("perf: the entry frame closed at depth %d with %s open" % [
			_open, _keys[0] if _open > 0 else "nothing"])
		return
	var now := Time.get_ticks_usec()
	var usec := now - _stamps[0]
	_open = 0
	_record(ENTRY, usec, "")
	if _started == 0:
		_started = now
	var physics := Engine.get_physics_frames()
	if _physics < 0:
		_physics = physics
	_frames += 1
	if float(now - _started) < WINDOW_S * 1000000.0:
		return
	_print_window(now, physics)


## Open one chunk. Off, it costs a branch; a nested chunk is a child of the frame below it.
static func begin(id: String) -> void:
	if not enabled:
		return
	if _open >= _keys.size():
		_keys.resize(_open + STACK)
		_stamps.resize(_open + STACK)
	_keys[_open] = id
	_stamps[_open] = Time.get_ticks_usec()
	_open += 1


## Close the chunk `id`, which must be the one on top; anything else discards the window.
static func end(id: String) -> void:
	if _open == 0:
		return
	var at := _open - 1
	if _keys[at] != id:
		_fail("perf: %s closed while %s was open" % [id, _keys[at]])
		return
	var usec := Time.get_ticks_usec() - _stamps[at]
	_open = at
	_record(id, usec, _keys[at - 1] if at > 0 else "")


## The rows of the last closed window: key, depth, prefix, self, total ms, calls and peak ms.
static func last_frame() -> Array:
	return _rows


static func _record(id: String, usec: int, parent: String) -> void:
	_total[id] = int(_total.get(id, 0)) + usec
	_calls[id] = int(_calls.get(id, 0)) + 1
	_peak[id] = maxi(int(_peak.get(id, 0)), usec)
	if not _parent.has(id):
		_parent[id] = parent


## A frame out of order is a caller bug: one error, and the window it belonged to is dropped.
static func _fail(message: String) -> void:
	LOG.error(message)
	_hide()
	_reset()


static func _reset() -> void:
	_total.clear()
	_calls.clear()
	_peak.clear()
	_parent.clear()
	_frames = 0
	_physics = -1
	_started = 0
	_open = 0


## Print the window, hand its rows to the panel and start the next one.
static func _print_window(now: int, physics: int) -> void:
	var frames := maxi(1, _frames)
	var ticks := float(maxi(0, physics - _physics)) / float(frames)
	var info := {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"tick": ticks,
		"draws": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"frames": frames,
	}
	var rows := _layout()
	var text := "perf fps=%d frame=%.1fms phys=%.1fms tick=%.2f draws=%d prims=%d" % [
		int(info["fps"]), float(info["frame_ms"]), float(info["phys_ms"]), ticks,
		int(info["draws"]), int(info["prims"])]
	for row: Dictionary in rows:
		var total := float(row["total"])
		# A residual row has no call of its own: only the unmeasured time is real.
		var peak := "-"
		var calls := "-"
		if not bool(row["self"]):
			peak = "%.2fms" % float(row["max"])
			calls = str(int(row["calls"]))
		text += "\n%-28s %8.2fms/s per-frame %8s max %7s calls %s" % [
			str(row["prefix"]) + str(row["key"]), total, "%.3fms" % (total / float(frames)),
			peak, calls]
	_rows = rows
	LOG.debug(text)
	_show(rows, info)
	_reset()
	_started = now
	_physics = physics


## Hand one window to the panel, which the entry parents the first time it prints.
static func _show(rows: Array, info: Dictionary) -> void:
	if not is_instance_valid(_entry):
		return
	if not is_instance_valid(_view):
		_view = View.new()
		_view.name = "UnfplapPerfView"
		_entry.add_child(_view)
	_view.show_window(rows, info)


## Hide the panel; a window already hidden costs one check.
static func _hide() -> void:
	if is_instance_valid(_view) and _view.visible:
		_view.clear()


## The window as a tree: a chunk's parent is the frame it was opened under.
static func _layout() -> Array:
	var children: Dictionary = {}
	var roots := PackedStringArray()
	for key: String in _total:
		var parent := str(_parent.get(key, ""))
		if parent.is_empty() or not _total.has(parent) or parent == key:
			roots.append(key)
			continue
		var siblings: Array = children.get(parent, [])
		siblings.append(key)
		children[parent] = siblings
	var rows: Array = []
	for key: String in _largest(roots):
		_emit(key, "", "", 0, false, children, rows)
	return rows


## One measured chunk, then its children and the parent's own residual, largest first.
static func _emit(key: String, lead: String, marker: String, depth: int, more: bool,
		children: Dictionary, rows: Array) -> void:
	rows.append({
		"key": key,
		"depth": depth,
		"prefix": lead + marker,
		"self": false,
		"total": float(_total[key]) / 1000.0,
		"calls": int(_calls.get(key, 0)),
		"max": float(_peak.get(key, 0)) / 1000.0,
	})
	var kids: Array = children.get(key, [])
	if kids.is_empty():
		return
	var child_total := 0
	var entries: Array = []
	for kid: String in kids:
		child_total += int(_total[kid])
		entries.append([int(_total[kid]), kid])
	var residual := int(_total[key]) - child_total
	if float(residual) / 1000.0 >= MIN_SELF_MS:
		entries.append([residual, ""])
	var order := PackedInt32Array()
	for index in entries.size():
		order.append(index)
	for index in range(1, order.size()):
		var at := index
		while at > 0 and int(entries[order[at - 1]][0]) < int(entries[order[at]][0]):
			var held := order[at]
			order[at] = order[at - 1]
			order[at - 1] = held
			at -= 1
	var child_lead := lead
	if not marker.is_empty():
		child_lead += BAR if more else GAP
	for position in order.size():
		var entry: Array = entries[order[position]]
		var last := position == order.size() - 1
		var branch := LAST if last else BRANCH
		if str(entry[1]).is_empty():
			rows.append({
				"key": "self",
				"depth": depth + 1,
				"prefix": child_lead + branch,
				"self": true,
				"total": float(entry[0]) / 1000.0,
				"calls": 0,
				"max": 0.0,
			})
			continue
		_emit(str(entry[1]), child_lead, branch, depth + 1, not last, children, rows)


## `keys` largest first; the insertion sort keeps equal totals in the order they opened.
static func _largest(keys: PackedStringArray) -> PackedStringArray:
	var out := keys.duplicate()
	for index in range(1, out.size()):
		var key: String = out[index]
		var at := index - 1
		while at >= 0 and int(_total[out[at]]) < int(_total[key]):
			out[at + 1] = out[at]
			at -= 1
		out[at + 1] = key
	return out


## The in-game panel: one window as the tree the log printed, coloured against the targets.
class View extends CanvasLayer:
	var _panel: PanelContainer = null
	var _caption: Label = null
	var _canvas: TreeCanvas = null
	var _entries: Array = []
	var _info: Dictionary = {}
	## When the previous window arrived and the measured rate; `-1` until a second window.
	var _last_shown_ms := -1
	var _refresh_hz := 0.0

	func _ready() -> void:
		layer = 20
		process_mode = Node.PROCESS_MODE_ALWAYS
		var root := Control.new()
		root.name = "PerfViewRoot"
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(root)
		_panel = PanelContainer.new()
		_panel.name = "PerfPanel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_panel.position = PANEL_AT
		_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
		_panel.add_theme_stylebox_override("panel", _panel_style())
		root.add_child(_panel)
		var box := VBoxContainer.new()
		box.name = "PerfBox"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 6)
		_panel.add_child(box)
		_caption = Label.new()
		_caption.name = "PerfCaption"
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_caption.add_theme_font_size_override("font_size", CAPTION_FONT)
		_caption.add_theme_color_override("font_color", INK)
		box.add_child(_caption)
		_canvas = TreeCanvas.new()
		_canvas.name = "PerfCanvas"
		_canvas.view = self
		_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.custom_minimum_size = Vector2(INNER_W, 0.0)
		_canvas.resized.connect(_canvas.queue_redraw)
		box.add_child(_canvas)
		_panel.visible = false

	func _panel_style() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(SHADE, 0.78)
		style.border_color = Color(ACCENT, 0.28)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(PANEL_PAD)
		return style

	## Draw one window: the printed rows and the engine facts behind them.
	func show_window(entries: Array, info: Dictionary) -> void:
		if _panel == null:
			return
		var now := Time.get_ticks_msec()
		if _last_shown_ms >= 0:
			var seconds := float(now - _last_shown_ms) / 1000.0
			if seconds > 0.05:
				_refresh_hz = 1.0 / seconds
		_last_shown_ms = now
		_entries = entries
		_info = info
		var line := caption(info)
		if _refresh_hz > 0.0:
			line += " · refresh %.1f Hz" % _refresh_hz
		_caption.text = line
		_canvas.custom_minimum_size = Vector2(INNER_W, height(entries))
		_canvas.queue_redraw()
		_panel.visible = true

	## Hide the panel and drop the last window.
	func clear() -> void:
		_entries = []
		_info = {}
		_last_shown_ms = -1
		_refresh_hz = 0.0
		if is_instance_valid(_caption):
			_caption.text = ""
		if is_instance_valid(_canvas):
			_canvas.custom_minimum_size = Vector2(INNER_W, 0.0)
			_canvas.queue_redraw()
		if is_instance_valid(_panel):
			_panel.visible = false

	## The caption line: the engine facts this window was printed with.
	static func caption(info: Dictionary) -> String:
		return "perf · %d fps · frame %.1fms · phys %.1fms · tick %.2f · draws %d" % [
			int(info.get("fps", 0)), float(info.get("frame_ms", 0.0)),
			float(info.get("phys_ms", 0.0)), float(info.get("tick", 0.0)),
			int(info.get("draws", 0))]

	## The list height for one window: the permanent total row, then one row per tree line.
	static func height(entries: Array) -> float:
		return float(entries.size() + 1) * ROW_H

	## The permanent top row: the roots' summed total and the window's worst call.
	static func totals(entries: Array) -> Dictionary:
		var average := 0.0
		var peak := 0.0
		for entry: Dictionary in entries:
			if int(entry["depth"]) == 0:
				average += float(entry["total"])
			if not bool(entry["self"]):
				peak = maxf(peak, float(entry.get("max", 0.0)))
		return {"avg": average, "max": peak}

	## Green at zero, amber at half the target, red at the target and beyond.
	static func heat(value: float, limit: float) -> Color:
		if limit <= 0.0:
			return GREEN
		var ratio := clampf(value / limit, 0.0, 1.0)
		if ratio <= 0.5:
			return GREEN.lerp(AMBER, ratio * 2.0)
		return AMBER.lerp(RED, (ratio - 0.5) * 2.0)

	## Calls per rendered frame; a window with no frames reports none.
	static func per_frame(calls: int, frames: int) -> float:
		if frames <= 0:
			return 0.0
		return float(calls) / float(frames)

	## One call per frame is the baseline; the call count reaches red at the limit.
	static func calls_heat(calls: int, frames: int) -> Color:
		var over := maxf(0.0, per_frame(calls, frames) - CALLS_BASE)
		return heat(over, CALLS_LIMIT - CALLS_BASE)

	func _draw_rows(canvas: Control) -> void:
		var font := canvas.get_theme_default_font()
		if font == null:
			return
		var width := canvas.size.x
		if width <= 0.0:
			return
		var frames := int(_info.get("frames", 0))
		var value_left := width - VALUE_W
		var name_limit := value_left - COL_GAP
		var avg_x := value_left
		var max_x := avg_x + AVG_W + COL_GAP
		var calls_x := max_x + MAX_W + COL_GAP
		var pad_top := (ROW_H - font.get_height(FONT_SIZE)) * 0.5
		var ascent := font.get_ascent(FONT_SIZE)
		var first_baseline := pad_top + ascent
		var summary := totals(_entries)
		canvas.draw_string(font, Vector2(NAME_GAP, first_baseline), TOTAL_LABEL,
			HORIZONTAL_ALIGNMENT_LEFT, name_limit - NAME_GAP, FONT_SIZE, ACCENT)
		canvas.draw_string(font, Vector2(avg_x, first_baseline), "%.2fms/s" % float(summary["avg"]),
			HORIZONTAL_ALIGNMENT_RIGHT, AVG_W, FONT_SIZE, heat(float(summary["avg"]), AVG_LIMIT))
		canvas.draw_string(font, Vector2(max_x, first_baseline), "%.2fms" % float(summary["max"]),
			HORIZONTAL_ALIGNMENT_RIGHT, MAX_W, FONT_SIZE, heat(float(summary["max"]), MAX_LIMIT))
		canvas.draw_string(font, Vector2(calls_x, first_baseline), "-",
			HORIZONTAL_ALIGNMENT_RIGHT, CALLS_W, FONT_SIZE, MUTED)
		canvas.draw_rect(Rect2(0.0, ROW_H - 1.0, width, 1.0), Color(ACCENT, 0.22))
		var cell_widths: Dictionary = {}
		for index in _entries.size():
			var entry: Dictionary = _entries[index]
			var baseline := float(index + 1) * ROW_H + first_baseline
			var is_self := bool(entry["self"])
			var prefix := str(entry.get("prefix", ""))
			for cell in prefix.length():
				var glyph := prefix[cell]
				var glyph_w := float(cell_widths.get(glyph, -1.0))
				if glyph_w < 0.0:
					glyph_w = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
					cell_widths[glyph] = glyph_w
				canvas.draw_string(font,
					Vector2(float(cell) * CELL_W + (CELL_W - glyph_w) * 0.5, baseline), glyph,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MUTED)
			var name_x := float(prefix.length()) * CELL_W + NAME_GAP
			var name_w := name_limit - name_x
			if name_w > 8.0:
				canvas.draw_string(font, Vector2(name_x, baseline),
					_fit(font, str(entry["key"]), name_w), HORIZONTAL_ALIGNMENT_LEFT, name_w,
					FONT_SIZE, MUTED if is_self else INK)
			var total := float(entry["total"])
			canvas.draw_string(font, Vector2(avg_x, baseline), "%.2fms/s" % total,
				HORIZONTAL_ALIGNMENT_RIGHT, AVG_W, FONT_SIZE, heat(total, AVG_LIMIT))
			if is_self:
				canvas.draw_string(font, Vector2(max_x, baseline), "-",
					HORIZONTAL_ALIGNMENT_RIGHT, MAX_W, FONT_SIZE, MUTED)
				canvas.draw_string(font, Vector2(calls_x, baseline), "-",
					HORIZONTAL_ALIGNMENT_RIGHT, CALLS_W, FONT_SIZE, MUTED)
				continue
			var peak := float(entry.get("max", 0.0))
			canvas.draw_string(font, Vector2(max_x, baseline), "%.2fms" % peak,
				HORIZONTAL_ALIGNMENT_RIGHT, MAX_W, FONT_SIZE, heat(peak, MAX_LIMIT))
			var calls := int(entry["calls"])
			canvas.draw_string(font, Vector2(calls_x, baseline), str(calls),
				HORIZONTAL_ALIGNMENT_RIGHT, CALLS_W, FONT_SIZE, calls_heat(calls, frames))

	## `text` trimmed with an ellipsis when it does not fit `width`.
	static func _fit(font: Font, text: String, width: float) -> String:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= width:
			return text
		var cut := text
		while cut.length() > 1 \
				and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > width:
			cut = cut.left(cut.length() - 1)
		return cut + "…"


## One tree row's glyph cells, drawn by the panel's canvas.
class TreeCanvas extends Control:
	var view: View = null

	func _draw() -> void:
		if view != null:
			view._draw_rows(self)
