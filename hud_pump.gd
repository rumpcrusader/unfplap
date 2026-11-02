extends Control
## Vertical depth bar: orange = deep, blue = shallow, with a circular knob.
## `up_is_deep` is the same pump.orientation flag used by input; flipping it flips the gradient
## and knob together so orange is always the deep end.

const ORANGE := Color(1.0, 0.48, 0.18)
const BLUE := Color(0.30, 0.62, 1.0)
const BACKGROUND := Color(0.03, 0.03, 0.05, 0.58)
const OUTLINE := Color(1.0, 1.0, 1.0, 0.28)
const KNOB_DARK := Color(0.02, 0.02, 0.04, 0.85)
const KNOB_LIGHT := Color(1.0, 0.96, 0.90, 0.96)

var depth := 0.0
var up_is_deep := true

var _last_depth := -1.0
var _last_up := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(40.0, 400.0)
	queue_redraw()


func set_depth(value: float, up: bool) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if absf(clamped - _last_depth) < 0.0005 and up == _last_up:
		return
	depth = clamped
	up_is_deep = up
	_last_depth = depth
	_last_up = up
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var height := size.y
	if width <= 1.0 or height <= 1.0:
		return
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, BACKGROUND, true)
	draw_rect(outer, OUTLINE, false, 1.0)
	var inner := Rect2(Vector2(2.0, 2.0), Vector2(maxf(1.0, width - 4.0), maxf(1.0, height - 4.0)))
	var top := ORANGE if up_is_deep else BLUE
	var bottom := BLUE if up_is_deep else ORANGE
	var strips := 40
	var strip_height := inner.size.y / float(strips)
	for index in strips:
		var t := float(index) / float(strips - 1)
		var color := top.lerp(bottom, t)
		draw_rect(Rect2(Vector2(inner.position.x, inner.position.y + strip_height * float(index)),
			Vector2(inner.size.x, strip_height + 1.0)), color, true)
	var knob_y := 0.0
	if up_is_deep:
		knob_y = inner.position.y + (1.0 - depth) * inner.size.y
	else:
		knob_y = inner.position.y + depth * inner.size.y
	var knob := Vector2(inner.position.x + inner.size.x * 0.5, knob_y)
	var radius := minf(8.0, inner.size.x * 0.32)
	draw_circle(knob, radius + 2.0, KNOB_DARK)
	draw_circle(knob, radius, KNOB_LIGHT)
