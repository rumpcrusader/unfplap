extends CanvasLayer
## The in-game perf panel: one probe window drawn as an icicle flame graph in the top-left corner.
## Roots share the top row, each level below sits inside its parent's span and a parent's
## unmeasured cost is its `self` bar. The text block stays the record; this only adds the picture.
## See `docs/perf.md` and `docs/debug.md`.

const PANEL_W := 620.0
const PANEL_PAD := 10.0
const PANEL_AT := Vector2(28.0, 26.0)
const GRAPH_W := PANEL_W - PANEL_PAD * 2.0
const ROW_H := 16.0
const ROW_GAP := 2.0
const LEGEND_ROWS := 6
const BAR_FONT := 11
const CAPTION_FONT := 13
const LEGEND_FONT := 12
const NAME_PAD := 6.0
## The act card's palette, so the debug panel reads as the mod's and not as a second look.
const ACCENT := Color("ffa8c7")
const INK := Color("f4f1ff")
const SHADE := Color("1a1624")
const MUTED := Color(0.957, 0.945, 1.0, 0.6)
const BAR_ALPHA := 0.92
## How far a nested level fades from the accent toward the panel shade.
const DEPTH_FADE := 0.62

var _panel: PanelContainer
var _caption: Label
var _canvas: FlameCanvas
var _legend: GridContainer
var _legend_names: Array[Label] = []
var _legend_values: Array[Label] = []
var _entries: Array = []


class FlameCanvas extends Control:
	var view: Variant

	func _draw() -> void:
		if view != null:
			view.call("_draw_bars", self)


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
	_canvas = FlameCanvas.new()
	_canvas.name = "PerfCanvas"
	_canvas.view = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.custom_minimum_size = Vector2(GRAPH_W, 0.0)
	_canvas.resized.connect(_canvas.queue_redraw)
	box.add_child(_canvas)
	_legend = GridContainer.new()
	_legend.name = "PerfLegend"
	_legend.columns = 2
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_constant_override("h_separation", 12)
	_legend.add_theme_constant_override("v_separation", 1)
	box.add_child(_legend)
	for _index in LEGEND_ROWS:
		var name_label := Label.new()
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", LEGEND_FONT)
		name_label.add_theme_color_override("font_color", MUTED)
		_legend.add_child(name_label)
		_legend_names.append(name_label)
		var value_label := Label.new()
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size = Vector2(76.0, 0.0)
		value_label.add_theme_font_size_override("font_size", LEGEND_FONT)
		value_label.add_theme_color_override("font_color", INK)
		_legend.add_child(value_label)
		_legend_values.append(value_label)
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
	_entries = entries
	_caption.text = caption(info)
	_fill_legend(entries)
	_canvas.custom_minimum_size = Vector2(GRAPH_W, height(entries))
	_canvas.queue_redraw()
	_panel.visible = true


## Hide the panel and drop the last window.
func clear() -> void:
	_entries = []
	if is_instance_valid(_caption):
		_caption.text = ""
	for index in _legend_names.size():
		_legend_names[index].text = ""
		_legend_values[index].text = ""
	if is_instance_valid(_canvas):
		_canvas.custom_minimum_size = Vector2(GRAPH_W, 0.0)
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


## One bar per display row: roots pack across `width` in entry order, children pack inside their
## parent's span and a `self` row keeps the residual. Empty entries and a zero width draw nothing.
static func rects(entries: Array, width: float) -> Array:
	var out: Array = []
	if entries.is_empty() or width <= 0.0:
		return out
	var root_total := 0.0
	for entry: Dictionary in entries:
		if int(entry["depth"]) == 0:
			root_total += maxf(0.0, float(entry["total"]))
	# Per depth: [origin_x, span_w, cursor_x, total]. A depth-first entry list fills the parent
	# before its own children arrive, so the cursor is all the packing needs.
	var levels: Array = []
	var root_left := 0.0
	for entry: Dictionary in entries:
		var depth := int(entry["depth"])
		var total := maxf(0.0, float(entry["total"]))
		var x := 0.0
		var bar := 0.0
		if depth == 0:
			bar = width if root_total <= 0.0 else width * total / root_total
			x = root_left
			root_left += bar
			levels.clear()
		elif depth <= levels.size():
			var parent: Array = levels[depth - 1]
			var span := float(parent[1])
			var parent_total := float(parent[3])
			var room := maxf(0.0, float(parent[0]) + span - float(parent[2]))
			bar = 0.0 if parent_total <= 0.0 else minf(total / parent_total * span, room)
			x = float(parent[2])
			parent[2] = x + bar
			levels.resize(depth)
		out.append(_bar(entry, x, bar))
		levels.append([x, bar, x, total])
	return out


## The graph height for one window: one row per level.
static func height(entries: Array) -> float:
	var deepest := -1
	for entry: Dictionary in entries:
		deepest = maxi(deepest, int(entry["depth"]))
	if deepest < 0:
		return 0.0
	return float(deepest + 1) * (ROW_H + ROW_GAP)


static func _bar(entry: Dictionary, x: float, w: float) -> Dictionary:
	return {
		"key": str(entry["key"]),
		"depth": int(entry["depth"]),
		"x": x,
		"w": w,
		"self": bool(entry["self"]),
	}


func _fill_legend(entries: Array) -> void:
	var rows: Array = []
	for entry: Dictionary in entries:
		if not bool(entry["self"]):
			rows.append([float(entry["total"]), str(entry["key"])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for index in _legend_names.size():
		if index < rows.size():
			_legend_names[index].text = str(rows[index][1])
			_legend_values[index].text = "%.2fms/s" % float(rows[index][0])
		else:
			_legend_names[index].text = ""
			_legend_values[index].text = ""


func _depth_color(depth: int) -> Color:
	var fade := clampf(float(depth) / 4.0, 0.0, 1.0) * DEPTH_FADE
	return Color(ACCENT.lerp(SHADE, fade), BAR_ALPHA)


func _draw_bars(canvas: Control) -> void:
	if _entries.is_empty():
		return
	var bars: Array = rects(_entries, canvas.size.x)
	var font := canvas.get_theme_default_font()
	for row: Dictionary in bars:
		var w := float(row["w"])
		if w < 1.0:
			continue
		var depth := int(row["depth"])
		var at := Vector2(float(row["x"]), float(depth) * (ROW_H + ROW_GAP))
		var fill := MUTED if bool(row["self"]) else _depth_color(depth)
		canvas.draw_rect(Rect2(at, Vector2(w, ROW_H)), fill)
		if font == null:
			continue
		var key := str(row["key"])
		if font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, BAR_FONT).x + NAME_PAD > w:
			continue
		canvas.draw_string(font, at + Vector2(NAME_PAD * 0.5, ROW_H - 4.0), key,
			HORIZONTAL_ALIGNMENT_LEFT, w, BAR_FONT, Color.WHITE)
