extends Control
## Short readiness fill. No ticks or labels; the HUD line carries those words.

const HEIGHT := 6.0
const WIDTH := 220.0
const BACKGROUND := Color(0.05, 0.05, 0.07, 0.78)
const FILL := Color(0.94, 0.52, 0.68, 0.92)
const FILL_CLOSE := Color(1.0, 0.66, 0.78, 0.96)
const CLOSE_AT := 65.0

var value := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(next_value: float) -> void:
	var clamped := clampf(next_value, 0.0, 100.0)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var height := maxf(size.y, HEIGHT)
	draw_rect(Rect2(0.0, 0.0, width, height), BACKGROUND)
	var fill_width := width * value / 100.0
	var color := FILL_CLOSE if value >= CLOSE_AT else FILL
	draw_rect(Rect2(0.0, 0.0, fill_width, height), color)
