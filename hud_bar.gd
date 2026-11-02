extends Control
## Simple vertical fill bar for Satisfaction. The depth bar has its own gradient/knob.

const BACKGROUND := Color(0.03, 0.03, 0.05, 0.58)
const OUTLINE := Color(1.0, 1.0, 1.0, 0.28)
const TICK := Color(1.0, 1.0, 1.0, 0.12)

var value := 0.0
var max_value := 100.0
var fill_color := Color(1.0, 0.45, 0.70)

var _last_value := -1.0
var _last_max := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40.0, 400.0)
	queue_redraw()


func set_value(new_value: float, new_max := 100.0) -> void:
	var top := maxf(0.001, new_max)
	var clamped := clampf(new_value, 0.0, top)
	if absf(clamped - _last_value) < 0.0005 and absf(top - _last_max) < 0.0005:
		return
	value = clamped
	max_value = top
	_last_value = clamped
	_last_max = top
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var height := size.y
	if width <= 1.0 or height <= 1.0:
		return
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, BACKGROUND, true)
	var inner := Rect2(Vector2(3.0, 3.0), Vector2(maxf(1.0, width - 6.0), maxf(1.0, height - 6.0)))
	var ratio := clampf(value / max_value, 0.0, 1.0)
	var fill_height := inner.size.y * ratio
	if fill_height > 0.0:
		draw_rect(Rect2(Vector2(inner.position.x, inner.position.y + inner.size.y - fill_height),
			Vector2(inner.size.x, fill_height)), fill_color, true)
	for index in [1, 2, 3]:
		var y := inner.position.y + inner.size.y * float(index) / 4.0
		draw_line(Vector2(inner.position.x, y), Vector2(inner.position.x + inner.size.x, y), TICK, 1.0)
	draw_rect(outer, OUTLINE, false, 1.0)
