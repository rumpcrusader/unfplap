extends Control
## Small readiness bar with an assist cap tick and a close tick. Pure drawing, no scene access.

const HEIGHT := 9.0
const BACKGROUND := Color(0.05, 0.05, 0.07, 0.78)
const FILL := Color(0.94, 0.52, 0.68, 0.92)
const FILL_CLOSE := Color(1.0, 0.66, 0.78, 0.96)
const TICK := Color(1.0, 1.0, 1.0, 0.55)

var value := 0.0
var assist_cap := 60.0
var close_at := 65.0


func _ready() -> void:
	custom_minimum_size = Vector2(260.0, HEIGHT)
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
	var color := FILL_CLOSE if value >= close_at else FILL
	draw_rect(Rect2(0.0, 0.0, fill_width, height), color)
	for marker: float in [assist_cap, close_at]:
		var x := width * clampf(marker, 0.0, 100.0) / 100.0
		draw_line(Vector2(x, 0.0), Vector2(x, height), TICK, 1.0)
