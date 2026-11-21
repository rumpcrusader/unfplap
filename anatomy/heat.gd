extends RefCounted
## Idle heat animation only: the resting open shape and one wink burst. The estrus service owns
## the phase and the schedule; the shape module owns the tween.
## See `docs/anatomy.md` (`## Idle heat`).

var shapes: RefCounted
## The idle rest, pushed by estrus and never read from Settings here.
var _rest_open := 0.0
## The idle display is suppressed while the act owns the mesh.
var _suppressed := false


func setup(shapes_node: RefCounted) -> void:
	shapes = shapes_node


func reset() -> void:
	_rest_open = 0.0
	_suppressed = false


func suppressed() -> bool:
	return _suppressed


func rest_open() -> float:
	return _rest_open


func set_suppressed(value: bool) -> void:
	_suppressed = value


## The estrus service's resting openness. It applies on the next idle beat, not mid-tween.
func set_rest(open: float) -> void:
	_rest_open = clampf(open, 0.0, 1.0)
	if _suppressed or shapes == null or shapes.tween_running():
		return
	if not is_equal_approx(shapes.wink_amount(), _rest_open):
		shapes.set_idle_wink(_rest_open)


## One idle burst. `on_peak` releases the droplets at the first beat's peak.
func wink_burst(count: int, on_peak: Callable) -> void:
	if _suppressed or shapes == null:
		return
	shapes.wink_burst(maxi(count, 1), maxi(count, 1), _rest_open, on_peak)
