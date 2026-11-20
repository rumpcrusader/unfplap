extends RefCounted
## The typed host boundary for one act's anatomy bridge. The runtime fills the named callbacks
## once; the bridge reads them through named methods and never sees a service locator.

var pony_cb: Callable = Callable()
var runtime_cb: Callable = Callable()
var reactions_cb: Callable = Callable()
var anatomy_service_cb: Callable = Callable()
var eligibility_service_cb: Callable = Callable()
var state_cb: Callable = Callable()
var pose_view_cb: Callable = Callable()
var depth_cb: Callable = Callable()
var penetration_m_cb: Callable = Callable()
var penetration_reach_cb: Callable = Callable()
var climaxes_cb: Callable = Callable()
var size_scale_cb: Callable = Callable()
var auto_pace_cb: Callable = Callable()
var fluid_ground_y_cb: Callable = Callable()
var cycle_phase_cb: Callable = Callable()
var bed_frame_cb: Callable = Callable()
var body_coat_smack_cb: Callable = Callable()
var status_cb: Callable = Callable()
var command_cb: Callable = Callable()
var missionary_camera_cb: Callable = Callable()
var kiss_controller_cb: Callable = Callable()
var pose_cb: Callable = Callable()
var thrust_move_cb: Callable = Callable()
var now_s_cb: Callable = Callable()
var set_penetration_m_cb: Callable = Callable()
var align_cb: Callable = Callable()
var touch_cb: Callable = Callable()
var vr_scene_cb: Callable = Callable()


static func _value(callback: Callable, fallback: Variant = null) -> Variant:
	return callback.call() if callback.is_valid() else fallback


func pony() -> Node:
	var value: Variant = _value(pony_cb)
	return value as Node if is_instance_valid(value) else null


func runtime() -> Node:
	var value: Variant = _value(runtime_cb)
	return value as Node if is_instance_valid(value) else null


func reactions() -> Variant:
	return _value(reactions_cb)


func anatomy_service() -> Variant:
	return _value(anatomy_service_cb)


func eligibility_service() -> Variant:
	return _value(eligibility_service_cb)


func state() -> int:
	return int(_value(state_cb, 0))


func pose_view() -> Variant:
	return _value(pose_view_cb)


func depth() -> float:
	return float(_value(depth_cb, 0.0))


func penetration_m() -> float:
	return float(_value(penetration_m_cb, 0.0))


func penetration_reach() -> float:
	return float(_value(penetration_reach_cb, 0.2))


func climaxes() -> int:
	return int(_value(climaxes_cb, 0))


func size_scale() -> float:
	return float(_value(size_scale_cb, 1.0))


func auto_pace() -> float:
	return float(_value(auto_pace_cb, 1.0))


func fluid_ground_y() -> float:
	return float(_value(fluid_ground_y_cb, 0.0))


func cycle_phase() -> String:
	return str(_value(cycle_phase_cb, "normal"))


func bed_frame() -> Variant:
	return _value(bed_frame_cb)


func body_coat_smack() -> Callable:
	return body_coat_smack_cb


func status() -> Callable:
	return status_cb


func command() -> Callable:
	return command_cb


func missionary_camera() -> Variant:
	return _value(missionary_camera_cb)


func kiss_controller() -> Variant:
	return _value(kiss_controller_cb)


func pose() -> Variant:
	return _value(pose_cb)


func thrust_move() -> Callable:
	return thrust_move_cb


func now_s() -> float:
	return float(_value(now_s_cb, 0.0))


func set_penetration_m() -> Callable:
	return set_penetration_m_cb


func align() -> Callable:
	return align_cb


func touch() -> Callable:
	return touch_cb


func vr_scene() -> Variant:
	return _value(vr_scene_cb)


## The pony read as a callable for the VR controller, which stores a source callback.
func pony_callable() -> Callable:
	return pony_cb
