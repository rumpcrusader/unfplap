extends CanvasLayer
## The debug action wheel: holding the middle mouse button in captured desktop play opens a ring
## of the actions for the aimed mare, or for the live act. It does not pause the tree, claim a
## hotkey or write a setting; see docs/debug.md.

const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const SOUNDS := preload("res://world/audio/interaction_sounds.gd")

var main: Node

var _open := false
var _page := "mare"
var _slots: Array[String] = []
var _context: Dictionary = {}
var _target: Node
var _had_target := false
var _aim := Vector2.ZERO
var _hover := -1
var _root: Control
var _canvas: WheelCanvas


class WheelCanvas extends Control:
	var wheel: Variant

	func _draw() -> void:
		if wheel != null:
			wheel.call("_draw_wheel", self)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "WheelRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_canvas = WheelCanvas.new()
	_canvas.name = "WheelCanvas"
	_canvas.wheel = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_canvas.resized.connect(_canvas.queue_redraw)
	_root.add_child(_canvas)
	_root.visible = false
	set_process(false)


func is_open() -> bool:
	return _open


## Open at the context root: Act while an act runs, Mare otherwise. Reopening always starts here.
func open() -> bool:
	if not _can_open():
		return false
	var context: Variant = main.call("debug_wheel_context")
	_context = context if context is Dictionary else {}
	var pony: Variant = _context.get("pony")
	_target = pony as Node if is_instance_valid(pony) else null
	_had_target = is_instance_valid(_target)
	_page = DEBUG_ACTIONS.wheel_root(bool(_context.get("act", false)))
	_slots = DEBUG_ACTIONS.wheel_actions(_page)
	_aim = Vector2.ZERO
	_hover = -1
	_open = true
	_root.visible = true
	set_process(true)
	_canvas.queue_redraw()
	return true


func close() -> void:
	_open = false
	_hover = -1
	_aim = Vector2.ZERO
	if is_instance_valid(_root):
		_root.visible = false
	set_process(false)


## Every event while open is ours. Releasing the middle button closes without running a slot;
## Escape and right click close, left click runs the highlighted slot, and the game's dev F-keys
## close and pass through.
func handle_input(event: InputEvent) -> bool:
	if not _open:
		if event is InputEventMouseButton:
			var middle := event as InputEventMouseButton
			if middle.button_index == MOUSE_BUTTON_MIDDLE and middle.pressed:
				return open()
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_aim += motion.relative
		_clamp_aim()
		_update_hover()
		_canvas.queue_redraw()
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			if button.button_index == MOUSE_BUTTON_MIDDLE:
				close()
			return true
		match button.button_index:
			MOUSE_BUTTON_MIDDLE:
				close()
			MOUSE_BUTTON_LEFT:
				_activate()
			MOUSE_BUTTON_RIGHT:
				close()
			_:
				pass
		return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return true
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			close()
			return true
		if key.physical_keycode in [KEY_F4, KEY_F9, KEY_F10, KEY_F11]:
			close()
			return false
		return true
	return true


func _process(_delta: float) -> void:
	if not _open:
		return
	if not _can_stay():
		close()


func _can_open() -> bool:
	return is_instance_valid(main) and bool(main.call("debug_wheel_allowed"))


func _can_stay() -> bool:
	if not _can_open():
		return false
	if _had_target and not is_instance_valid(_target):
		return false
	return bool(main.call("debug_wheel_act_live")) == (_page == "act")


func _activate() -> void:
	var hovered := _hover
	close()
	if hovered < 0 or hovered >= _slots.size() or not is_instance_valid(main):
		return
	main.call("debug_wheel_action", _slots[hovered])


func _clamp_aim() -> void:
	var limit := _wheel_metrics().x - 8.0
	if _aim.length() > limit:
		_aim = _aim.normalized() * limit


func _set_hover(value: int) -> void:
	if value == _hover:
		return
	_hover = value
	if _hover >= 0:
		_play_hover()


func _update_hover() -> void:
	if _slots.is_empty():
		_set_hover(-1)
		return
	if _aim.length() < _wheel_metrics().y * 0.75:
		_set_hover(-1)
		return
	var count := _slots.size()
	var step := TAU / float(count)
	var angle := fposmod(atan2(_aim.y, _aim.x) + PI * 0.5, TAU)
	_set_hover(int(angle / step) % count)


## One stock UI click when the reticle moves onto a slot. The centre, open and close stay silent.
func _play_hover() -> void:
	if not is_instance_valid(main) or not main.has_method("camera"):
		return
	var view: Variant = main.call("camera")
	if view is Camera3D and is_instance_valid(view):
		SOUNDS.play_at(view, "prop_ui_confirm", (view as Camera3D).global_position)


## Outer and inner radius for the current viewport.
func _wheel_metrics() -> Vector2:
	var size := _canvas.size if is_instance_valid(_canvas) else Vector2(800.0, 600.0)
	var outer := clampf(minf(size.x, size.y) * 0.20, 70.0, 180.0)
	return Vector2(outer, outer * 0.42)


func _context_name() -> String:
	return str(_target.name) if is_instance_valid(_target) else "No mare"


func _context_source() -> String:
	match str(_context.get("source", "none")):
		"aimed":
			return "aimed mare"
		"act":
			return "live act"
	return "no target"


func _sector(center: Vector2, inner: float, outer: float, start: float, end: float) \
		-> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 12
	for i in range(segments + 1):
		var angle := start + (end - start) * float(i) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * outer)
	for i in range(segments, -1, -1):
		var angle := start + (end - start) * float(i) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * inner)
	return points


func _draw_wheel(canvas: Control) -> void:
	var size := canvas.size
	if size.x < 40.0 or size.y < 40.0:
		return
	var center := size * 0.5
	var metrics := _wheel_metrics()
	var outer := metrics.x
	var inner := metrics.y
	var font := canvas.get_theme_default_font()
	var font_size := clampi(roundi(outer * 0.052), 12, 18)
	var count := _slots.size()
	var step := TAU / float(maxi(1, count))
	canvas.draw_circle(center, outer + 18.0, Color(0.04, 0.015, 0.07, 0.86))
	canvas.draw_arc(center, outer + 18.0, 0.0, TAU, 96, Color(0.95, 0.5, 0.7, 0.25), 2.0, true)
	for i in count:
		var start := -PI * 0.5 + step * float(i)
		var end := start + step
		var hot := i == _hover
		var fill := Color(0.32, 0.10, 0.20, 0.9) if hot else Color(0.12, 0.06, 0.14, 0.88)
		var edge := Color(0.98, 0.62, 0.76, 0.9) if hot else Color(0.55, 0.32, 0.45, 0.55)
		canvas.draw_colored_polygon(_sector(center, inner, outer, start, end), fill)
		canvas.draw_arc(center, outer, start, end, 24, edge, 2.0, true)
		canvas.draw_arc(center, inner, start, end, 24, edge, 1.0, true)
		var mid := start + step * 0.5
		var at := center + Vector2(cos(mid), sin(mid)) * ((inner + outer) * 0.5)
		var label := DEBUG_ACTIONS.action_short(str(_slots[i]), main)
		canvas.draw_string(font, at + Vector2(-outer * 0.5, font_size * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, outer, font_size,
			Color.WHITE if hot else Color(0.95, 0.88, 0.92, 0.9))
	canvas.draw_circle(center, inner * 0.92, Color(0.045, 0.02, 0.07, 0.96))
	canvas.draw_arc(center, inner * 0.92, 0.0, TAU, 72, Color(0.95, 0.55, 0.72, 0.35), 1.5, true)
	var page_title := DEBUG_ACTIONS.wheel_title(_page).to_upper()
	canvas.draw_string(font, center + Vector2(-inner, -inner * 0.62), page_title,
		HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0, maxi(10, font_size - 3),
		Color(0.98, 0.55, 0.72, 0.9))
	canvas.draw_string(font, center + Vector2(-inner, -inner * 0.28), _context_name(),
		HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0, font_size + 2, Color.WHITE)
	canvas.draw_string(font, center + Vector2(-inner, -inner * 0.02), _context_source(),
		HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0, maxi(10, font_size - 4),
		Color(0.82, 0.72, 0.8, 0.9))
	var tip := center + _aim
	canvas.draw_circle(tip, 4.0, Color(0.98, 0.7, 0.82, 0.95))
	canvas.draw_arc(tip, 10.0, 0.0, TAU, 24, Color(0.98, 0.7, 0.82, 0.55), 1.5, true)
	canvas.draw_string(font, center + Vector2(-outer, outer + 34.0),
		"Hold middle · Left click select · Release closes · Right click / Esc close",
		HORIZONTAL_ALIGNMENT_CENTER, outer * 2.0, maxi(10, font_size - 4),
		Color(0.8, 0.72, 0.78, 0.8))
