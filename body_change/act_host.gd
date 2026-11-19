extends RefCounted
## The typed host boundary for one act's body-change handover. The runtime fills the named
## callbacks once; the handover reads live values through named methods and never sees a service
## locator.

var runtime_cb: Callable = Callable()
var pony_cb: Callable = Callable()
var id_cb: Callable = Callable()
var act_live_cb: Callable = Callable()
var restoring_cb: Callable = Callable()
var depth_cb: Callable = Callable()
var climaxes_cb: Callable = Callable()
var pose_view_cb: Callable = Callable()
var start_pose_cb: Callable = Callable()
var shape_name_cb: Callable = Callable()
var log_cb: Callable = Callable()


static func _value(callback: Callable, fallback: Variant = null) -> Variant:
	return callback.call() if callback.is_valid() else fallback


func runtime() -> Node:
	var value: Variant = _value(runtime_cb)
	return value as Node if is_instance_valid(value) else null


func pony() -> Node3D:
	var value: Variant = _value(pony_cb)
	if not is_instance_valid(value) or not value is Node3D:
		return null
	return value


func id() -> String:
	return str(_value(id_cb, ""))


## True while the act can be suspended or asked for a form: posing in, active, climax or afterglow.
func act_live() -> bool:
	return bool(_value(act_live_cb, false))


func restoring() -> bool:
	return bool(_value(restoring_cb, false))


func depth() -> float:
	return float(_value(depth_cb, 0.0))


func climaxes() -> int:
	return int(_value(climaxes_cb, 0))


func pose_view() -> Variant:
	return _value(pose_view_cb)


func start_pose_id() -> String:
	return str(_value(start_pose_cb, ""))


func shape_name(shape_id: String) -> String:
	if not shape_name_cb.is_valid():
		return shape_id
	return str(shape_name_cb.call(shape_id))


func log(text: String) -> void:
	if log_cb.is_valid():
		log_cb.call(text)
