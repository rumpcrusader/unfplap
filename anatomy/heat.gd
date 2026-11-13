extends RefCounted
## Idle heat display: the phase poll, the resting open shape and the wink/discharge schedule.
## The controller passes the act state, whether the mesh is visible and a phase getter; the
## shape module owns the tween.
##
## See `docs/anatomy.md` (`## Idle heat`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")

const PHASE_POLL_S := 2.0

var shapes: RefCounted

var _phase := ""
var _phase_clock := 0.0
var _wink_clock := 0.0
var _suppressed := false


func setup(shapes_node: RefCounted) -> void:
	shapes = shapes_node


func reset() -> void:
	_phase = ""
	_phase_clock = 0.0
	_wink_clock = 0.0
	_suppressed = false


func suppressed() -> bool:
	return _suppressed


func phase() -> String:
	return _phase


func wink_clock() -> float:
	return _wink_clock


func rest_open() -> float:
	return clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)


## `phase_getter` is called only when the two-second poll expires. `on_peak` releases the heat
## droplets at the first beat's peak.
func tick(delta: float, state: int, visible: bool, phase_getter: Callable,
		on_peak: Callable) -> void:
	if state in [1, 2, 3]:
		if not _suppressed:
			_suppressed = true
			_phase = ""
			_phase_clock = 0.0
			_wink_clock = _interval()
		return
	_suppressed = false
	if not visible or shapes == null:
		return

	_phase_clock -= delta
	if _phase_clock <= 0.0:
		_phase_clock = PHASE_POLL_S
		var current := str(phase_getter.call()) if phase_getter.is_valid() else CYCLE.NORMAL
		if current != _phase:
			_phase = current
			_wink_clock = _interval() if current == CYCLE.HEAT else 0.0

	# Heat rests slightly open; normal and diestrus rest closed. Do not fight a wink tween.
	if not shapes.tween_running():
		var idle_rest := rest_open() if _phase == CYCLE.HEAT else 0.0
		if not is_equal_approx(shapes.wink_amount(), idle_rest):
			shapes.set_idle_wink(idle_rest)

	if _phase != CYCLE.HEAT:
		return

	_wink_clock -= delta
	if _wink_clock > 0.0:
		return
	_wink_clock = _interval()
	var count := CYCLE.wink_burst_count(randf())
	shapes.wink_burst(count, count, rest_open(), on_peak)


func _interval() -> float:
	return CYCLE.wink_interval(
		maxf(SETTINGS.wink_min_s.get_num(), 0.05),
		maxf(SETTINGS.wink_max_s.get_num(), 0.05))
