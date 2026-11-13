extends Node
## integration: optional VR standing act. Desktop paths
## do not create it. It drives the same depth and anatomy actions as the desktop keys; the
## auto-speed/stroke-depth controls from the fork are deliberately not imported.

const HIP_RANGE_M := 0.16
const STICK_DEAD := 0.5
const STICK_REPEAT_S := 0.18

## Host boundary. The bridge owns the anatomy actions and the headset depth; the typed act view
## supplies her node and the readiness touch. Missing callbacks are no-ops.
var bridge: Variant = null
var align := Callable()
var touch := Callable()
var pony_source := Callable()
var player: Node3D
var hip_target: Node3D
var camera: XRCamera3D
var origin: Node3D

var _left: XRController3D
var _right: XRController3D
var _hip_base := Vector3.INF
var _stick_wait := 0.0
var _swap_held := false
var _finish_held := false
var _oral_held := false
var y_held := false


func _ready() -> void:
	process_priority = 100
	for node: Node in player.find_children("*", "XRController3D", true, false):
		var hand := node as XRController3D
		if hand.tracker == &"left_hand":
			_left = hand
		elif hand.tracker == &"right_hand":
			_right = hand


func _process(_delta: float) -> void:
	if is_instance_valid(hip_target) and align.is_valid():
		align.call(hip_target, Basis.IDENTITY)


func _physics_process(delta: float) -> void:
	y_held = is_instance_valid(_right) and _right.is_button_pressed("primary_click")
	_drive_depth()
	_read_hands()
	var swap := is_instance_valid(_right) and _right.is_button_pressed("ax_button")
	if swap and not _swap_held and bridge != null:
		bridge.toggle_hole()
	_swap_held = swap
	var finish := is_instance_valid(_left) and _left.is_button_pressed("primary_click")
	if finish and not _finish_held and bridge != null:
		bridge.toggle_finish()
	_finish_held = finish
	var oral := is_instance_valid(_left) and _left.is_button_pressed("by_button")
	if oral and not _oral_held and bridge != null:
		bridge.toggle_oral()
	_oral_held = oral


## integration: her body tracker's hips, or a positional tracker named for the waist.
func _tracked_hips() -> Vector3:
	if not is_instance_valid(origin):
		return Vector3.INF
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANY)
	for key: Variant in trackers:
		var tracker: Variant = trackers[key]
		if tracker is XRBodyTracker:
			var body := tracker as XRBodyTracker
			if body.has_method("get_has_tracking_data") and body.get_has_tracking_data():
				return origin.global_transform * body.get_joint_transform(
					XRBodyTracker.JOINT_HIPS).origin
		if tracker is XRPositionalTracker:
			var label := str(key).to_lower()
			if label.contains("waist") or label.contains("hip"):
				var pose: XRPose = (tracker as XRPositionalTracker).get_pose(&"default")
				if pose != null and pose.has_tracking_data:
					return origin.global_transform * pose.get_adjusted_transform().origin
	return Vector3.INF


func _drive_depth() -> void:
	var hips := _tracked_hips()
	if hips == Vector3.INF:
		_hip_base = Vector3.INF
		return
	if _hip_base == Vector3.INF:
		_hip_base = hips
	if bridge == null:
		return
	var forward: Vector3 = bridge.vr_forward()
	bridge.vr_depth(clampf((hips - _hip_base).dot(forward) / HIP_RANGE_M, 0.0, 1.0))


## integration: real hands caress when the game's touch body reports petting.
func _read_hands() -> void:
	var pony: Variant = pony_source.call() if pony_source.is_valid() else null
	if not is_instance_valid(pony):
		return
	var body: Variant = pony.get("touch_body")
	if body != null and bool(body.get("petting")) and touch.is_valid():
		touch.call("caress")
