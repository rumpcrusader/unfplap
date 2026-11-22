extends Node
## Optional VR standing act; not built on desktop.
## The fork's auto-speed controls are deliberately not imported.

const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const TOUCH_BRIDGE := preload("res://mods/unfplap/shared/touch_bridge.gd")
const SELF := preload("res://mods/unfplap/vr/service.gd")

const HIP_RANGE_M := 0.16
const STICK_DEAD := 0.5
const STICK_REPEAT_S := 0.18

## Host boundary: the act owns the anatomy targets, the commands and the headset depth.
## Missing callbacks are no-ops.
var forward := Callable()
var depth := Callable()
var toggle_hole := Callable()
var oral_ready := Callable()
var touch := Callable()
var pony_source := Callable()
var command := Callable()
var player: Node3D
var hip_target: Node3D
var camera: XRCamera3D
var origin: Node3D

## The touch callable's typed wrapper, rebuilt only when the anatomy host changes it.
var _touch_bridge: TOUCH_BRIDGE = null
var _touch_source := Callable()

var _left: XRController3D
var _right: XRController3D
var _hip_base := Vector3.INF
var _stick_wait := 0.0
var _swap_held := false
var _oral_held := false
var y_held := false


## Build the optional VR controller for `player` and parent it under `runtime`; null on desktop.
static func attach(runtime: Node, player: Node) -> Node:
	if not is_instance_valid(runtime) or not is_instance_valid(player):
		return null
	var avatar := player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return null
	var cameras: Array = player.find_children("*", "XRCamera3D", true, false)
	var origins: Array = player.find_children("*", "XROrigin3D", true, false)
	if cameras.is_empty() or origins.is_empty():
		return null
	var act: Node = SELF.new()
	act.name = "UnfplapVrAct"
	act.player = player as Node3D
	act.hip_target = avatar.get("_hip_target") as Node3D
	act.camera = cameras[0] as XRCamera3D
	act.origin = origins[0] as XROrigin3D
	runtime.add_child(act)
	return act


func _ready() -> void:
	process_priority = 100
	if not is_instance_valid(player):
		return
	for node: Node in player.find_children("*", "XRController3D", true, false):
		var hand := node as XRController3D
		if hand.tracker == &"left_hand":
			_left = hand
		elif hand.tracker == &"right_hand":
			_right = hand


func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	y_held = is_instance_valid(_right) and _right.is_button_pressed("primary_click")
	_drive_depth()
	_read_hands()
	var swap := is_instance_valid(_right) and _right.is_button_pressed("ax_button")
	if swap and not _swap_held and toggle_hole.is_valid():
		toggle_hole.call()
	_swap_held = swap
	var oral := is_instance_valid(_left) and _left.is_button_pressed("by_button")
	if oral and not _oral_held and command.is_valid() and _oral_ready():
		command.call(ACT_COMMANDS.ORAL)
	_oral_held = oral


## The act side of the oral gate, the same one the desktop `N` key reads.
func _oral_ready() -> bool:
	return oral_ready.call() if oral_ready.is_valid() else false


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
	if not forward.is_valid() or not depth.is_valid():
		return
	var axis: Vector3 = forward.call()
	depth.call(clampf((hips - _hip_base).dot(axis) / HIP_RANGE_M, 0.0, 1.0))


## integration: real hands caress when the game's touch body reports petting.
func _read_hands() -> void:
	var pony: Variant = pony_source.call() if pony_source.is_valid() else null
	if not is_instance_valid(pony):
		return
	var body: Variant = pony.get("touch_body")
	if body != null and bool(body.get("petting")) and touch.is_valid():
		if touch != _touch_source:
			_touch_source = touch
			_touch_bridge = TOUCH_BRIDGE.new()
			_touch_bridge.run = touch
		WORLD.affection().caress(_touch_bridge)
