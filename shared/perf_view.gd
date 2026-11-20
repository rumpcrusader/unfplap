extends CanvasLayer
## The in-game perf panel: the probe's window as the same tree the log block prints, with each
## row's average, max and call count coloured against the debug targets. The text block stays the
## record; this only adds the table. See `docs/perf.md` and `docs/debug.md`.

const PANEL_W := 620.0
const PANEL_PAD := 10.0
const PANEL_AT := Vector2(28.0, 26.0)
const INNER_W := PANEL_W - PANEL_PAD * 2.0
const ROW_H := 16.0
const FONT_SIZE := 11
const CAPTION_FONT := 13
## Fixed cell for one tree glyph, so the indentation lines up without a monospace font.
const CELL_W := 7.0
const NAME_GAP := 6.0
const AVG_W := 78.0
const MAX_W := 60.0
const CALLS_W := 46.0
const COL_GAP := 8.0
const VALUE_W := AVG_W + MAX_W + CALLS_W + COL_GAP * 2.0
## The permanent first row's label: the whole window's measured total.
const TOTAL_LABEL := "unfplap total"
## Debug targets: a column reads red at its target and green at zero. An idle chunk's average and
## max are the whole window's; calls are coloured per rendered frame against one call.
const AVG_LIMIT := 100.0
const MAX_LIMIT := 0.5
const CALLS_BASE := 1.0
const CALLS_LIMIT := 2.0
const GREEN := Color("7ee08a")
const AMBER := Color("ffd166")
const RED := Color("ff6b81")
## The act card's palette, so the debug panel reads as the mod's and not as a second look.
const ACCENT := Color("ffa8c7")
const INK := Color("f4f1ff")
const SHADE := Color("1a1624")
const MUTED := Color(0.957, 0.945, 1.0, 0.6)

var _panel: PanelContainer
var _caption: Label
var _canvas: TreeCanvas
var _entries: Array = []
var _info: Dictionary = {}
## When the previous window arrived and the measured refresh rate; `-1` until a second window.
var _last_shown_ms := -1
var _refresh_hz := 0.0


class TreeCanvas extends Control:
	var view: Variant

	func _draw() -> void:
		if view != null:
			view.call("_draw_rows", self)


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


## Draw one window. Both probes hand over the rows they printed and the facts behind them.
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


## The caption line: the probe's own header facts, then the engine numbers both probes carry.
static func caption(info: Dictionary) -> String:
	var lead := "perf"
	if info.has("pony"):
		lead = "perf pony=%s pose=%s state=%d" % [
			str(info.get("pony", "?")), str(info.get("pose", "")), int(info.get("state", 0))]
	elif info.has("runtimes"):
		lead = "perf idle runtimes=%d mares=%d" % [
			int(info.get("runtimes", 0)), int(info.get("mares", 0))]
	return "%s · %d fps · frame %.1fms · phys %.1fms · tick %.2f" % [
		lead, int(info.get("fps", 0)), float(info.get("frame_ms", 0.0)),
		float(info.get("phys_ms", 0.0)), float(info.get("tick", 0.0))]


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


## One call per frame is the baseline; the call count reaches red at `CALLS_LIMIT`.
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
