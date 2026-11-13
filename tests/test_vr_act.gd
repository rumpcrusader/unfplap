extends SceneTree
## vr/service.gd: the VR standing act's controller bindings and fake-waist depth path.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_vr_act.gd
##
## No XR runtime is needed. XRPositionalTracker inputs and poses work without an interface, so the
## two hand trackers below stand in for a headset's controllers and the `waist` tracker for body
## tracking. The controller reads are the only vr_act path a Monado session cannot press: its
## KHR simple controller profile binds only select and menu.

const VR_ACT := preload("res://mods/unfplap/vr/service.gd")

var failures := 0
var checks := 0


class FakeTouch:
	var petting := false


class FakePony extends Node3D:
	var touch_body: Variant = null


## The anatomy bridge's side of the VR act: the action toggles, the headset forward and depth,
## her node and the hip alignment write-back.
class FakeBridge extends RefCounted:
	var calls: Array[String] = []
	var forward := Vector3(0.0, 0.0, -1.0)
	var depth := -1.0
	var pony: Variant = null

	func apply_anon_align(_hip: Node3D, _facing: Basis) -> void:
		calls.append("align")

	func toggle_hole() -> void:
		calls.append("hole")

	func toggle_finish() -> void:
		calls.append("finish")

	func toggle_oral() -> void:
		calls.append("oral")

	func on_touch(kind: String) -> void:
		calls.append("touch:" + kind)

	func vr_forward() -> Vector3:
		return forward

	func vr_depth(value: float) -> void:
		depth = value

	func pony_node() -> Variant:
		return pony


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _tracker(name: String, hand: int) -> XRPositionalTracker:
	var tracker := XRPositionalTracker.new()
	tracker.name = name
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.hand = hand
	XRServer.add_tracker(tracker)
	return tracker


func _pose(tracker: XRPositionalTracker, at: Vector3) -> void:
	tracker.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _tick(act: Node, times := 1) -> void:
	for _i in times:
		act.call("_physics_process", 0.02)


func _count(bridge: FakeBridge, call: String) -> int:
	var total := 0
	for entry: String in bridge.calls:
		if entry == call:
			total += 1
	return total


func run() -> void:
	var player := Node3D.new()
	player.name = "Player"
	root.add_child(player)
	var left := _tracker("left_hand", XRPositionalTracker.TRACKER_HAND_LEFT)
	var right := _tracker("right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT)
	var waist := XRPositionalTracker.new()
	waist.name = "waist"
	waist.type = XRServer.TRACKER_ANY
	XRServer.add_tracker(waist)
	_pose(waist, Vector3.ZERO)

	var controller_left := XRController3D.new()
	controller_left.tracker = &"left_hand"
	player.add_child(controller_left)
	var controller_right := XRController3D.new()
	controller_right.tracker = &"right_hand"
	player.add_child(controller_right)

	var origin := XROrigin3D.new()
	player.add_child(origin)
	var camera := XRCamera3D.new()
	origin.add_child(camera)

	var touch := FakeTouch.new()
	var pony := FakePony.new()
	pony.touch_body = touch
	root.add_child(pony)
	var bridge := FakeBridge.new()
	bridge.pony = pony

	var hip := Node3D.new()
	var act := VR_ACT.new()
	act.set("bridge", bridge)
	act.set("align", Callable(bridge, "apply_anon_align"))
	act.set("touch", Callable(bridge, "on_touch"))
	act.set("pony_source", Callable(bridge, "pony_node"))
	act.set("player", player)
	act.set("hip_target", hip)
	act.set("camera", camera)
	act.set("origin", origin)
	root.add_child(act)
	# The engine would run these every frame as well; the test calls them itself.
	act.set_process(false)
	act.set_physics_process(false)

	check(act.get("_left") == controller_left, "left controller found under the rig")
	check(act.get("_right") == controller_right, "right controller found under the rig")

	# Y is the right hand's primary click.
	right.set_input(&"primary_click", true)
	_tick(act)
	check(bool(act.get("y_held")), "right primary click holds Y")
	right.set_input(&"primary_click", false)
	_tick(act)
	check(not bool(act.get("y_held")), "releasing the right primary click drops Y")

	# The anatomy toggles fire on the press edge only.
	right.set_input(&"ax_button", true)
	_tick(act, 3)
	check(_count(bridge, "hole") == 1, "ax button switches the hole once per press")
	right.set_input(&"ax_button", false)
	_tick(act, 2)
	check(_count(bridge, "hole") == 1, "holding ax does not repeat the hole switch")
	right.set_input(&"ax_button", true)
	_tick(act)
	check(_count(bridge, "hole") == 2, "a second press switches the hole again")

	left.set_input(&"primary_click", true)
	_tick(act, 2)
	check(_count(bridge, "finish") == 1, "left primary click chooses the finish once")
	left.set_input(&"primary_click", false)
	_tick(act)

	left.set_input(&"by_button", true)
	_tick(act, 2)
	check(_count(bridge, "oral") == 1, "left by button turns her for oral once")
	left.set_input(&"by_button", false)
	_tick(act)

	# The waist tracker drives depth exactly like a body-tracked waist.
	_tick(act)
	_pose(waist, Vector3(0.0, 0.0, -0.08))
	_tick(act)
	check(is_equal_approx(bridge.depth, 0.5), "8 cm of waist travel is depth 0.5, got %f" % bridge.depth)
	_pose(waist, Vector3(0.0, 0.0, -0.32))
	_tick(act)
	check(is_equal_approx(bridge.depth, 1.0), "depth clamps at 1, got %f" % bridge.depth)
	_pose(waist, Vector3(0.0, 0.0, 0.5))
	_tick(act)
	check(is_equal_approx(bridge.depth, 0.0), "a waist behind the base is depth 0, got %f" % bridge.depth)

	# A tracked waist that never moves is depth 0: only a change counts.
	_pose(waist, Vector3(0.0, 0.0, 0.0))
	_tick(act, 2)
	var settled := bridge.depth
	_tick(act, 5)
	check(is_equal_approx(bridge.depth, settled), "a still waist keeps a constant depth")

	# The VR act also holds the anatomy part on the tracked hip and caresses from real petting.
	act.call("_process", 0.02)
	check(_count(bridge, "align") == 1, "process applies the hip alignment once")
	touch.petting = true
	_tick(act)
	check(_count(bridge, "touch:caress") == 1, "petting caresses through the act")

	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	XRServer.remove_tracker(waist)
	act.free()
	hip.free()
	pony.free()
	player.free()
	print("VR_ACT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("VR_ACT_PASS")
	quit(0 if failures == 0 else 1)
