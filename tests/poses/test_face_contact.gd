extends "res://mods/unfplap/tests/support/suite.gd"
## The bed face-sit contact driver: the begin capture, the mouth follow, the depth press, the
## moving-bed carry, the missing-provider hold and the one restore. A node-less facade and fakes only.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_face_contact.gd

const FACE := preload("res://mods/unfplap/poses/face_contact.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")



class FakePoints:
	var mouth := Vector3.ZERO
	var opening := Vector3.ZERO
	var active := true
	var mouth_calls := 0
	var opening_calls := 0

	func live() -> bool:
		return active

	func mouth_point() -> Vector3:
		mouth_calls += 1
		return mouth

	func opening_point() -> Vector3:
		opening_calls += 1
		return opening


## The facts the driver reads: his mouth is the fake body, her opening is read live.
class FakeFacts extends RefCounted:
	var points: FakePoints = null

	var anatomy_opening: Vector3:
		get:
			return points.opening_point() if points != null else Vector3.ZERO

	func missionary_body() -> Variant:
		return points


class FakePoseNode extends "res://mods/unfplap/poses/skeleton_pose.gd":
	pass

func near_v(a: Vector3, b: Vector3, eps := 0.0001) -> bool:
	return a.distance_to(b) <= eps


func offset_of(driver: Variant) -> Vector3:
	var value: Variant = driver.call("offset")
	return value as Vector3


func target_of(driver: Variant) -> Vector3:
	var value: Variant = driver.call("target")
	return value as Vector3


func run() -> void:
	_check_capture()
	_check_follow()
	_check_press()
	_check_moving_bed()
	_check_missing_provider()
	_check_restore()
	if failures == 0:
		print("FACE_CONTACT_PASS")
	finish()


func _make(points: FakePoints) -> Variant:
	var facts := FakeFacts.new()
	facts.points = points
	var driver: Variant = FACE.new()
	driver.call("bind", facts)
	return driver


func _view(contact := "face") -> Variant:
	var view: Variant = VIEW.new()
	view.set("contact_kind", contact)
	return view


func _check_capture() -> void:
	var points := FakePoints.new()
	points.mouth = Vector3(0.34, 0.72, -1.2)
	points.opening = Vector3(0.30, 0.66, -1.1)
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame := Transform3D(Basis(Vector3.UP, 0.6), Vector3(1.0, 0.62, -2.0))
	check(bool(driver.call("begin", view, frame)), "a face begin captures a finite pair")
	check(bool(driver.get("active")), "the driver is active after begin")
	check(bool(driver.get("captured")), "the driver captured the pair")
	var inverse := frame.affine_inverse()
	var expected := (inverse * points.mouth) - (inverse * points.opening)
	check(near_v(offset_of(driver), expected), "begin stores mouth - opening in frame space")
	check(near_v(target_of(driver), points.mouth), "begin points the view at the mouth")
	check(near_v(view.get("contact_target") as Vector3, points.mouth),
		"the view receives the mouth target")
	check(points.mouth_calls == 1 and points.opening_calls == 1,
		"begin reads the mouth and the opening once")

	var no_frame: Variant = _make(points)
	check(not bool(no_frame.call("begin", _view(), null)), "begin without a frame refuses")
	check(bool(no_frame.get("active")), "a refused begin still activates for a later frame")
	check(not bool(no_frame.get("captured")), "a refused begin captures nothing")


func _check_follow() -> void:
	var points := FakePoints.new()
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame := Transform3D.IDENTITY
	var node := FakePoseNode.new()
	driver.call("begin", view, frame)
	check(near_v(offset_of(driver), Vector3.ZERO), "a zero residual starts at zero")
	points.mouth = Vector3(0.01, 0.0, 0.0)
	driver.call("tick", 1.0, view, 0.0, frame, node)
	check(offset_of(driver).x > 0.009, "the offset follows the moved mouth")
	check(near_v(node.contact_offset, offset_of(driver)), "the node gets the world offset")
	check(near_v(view.get("contact_target") as Vector3, points.mouth),
		"the view target tracks the mouth")
	var held := offset_of(driver)
	driver.call("tick", 1.0, view, 0.0, frame, node)
	check(near_v(offset_of(driver), held), "a settled follow does not overshoot")
	node.free()


func _check_press() -> void:
	var points := FakePoints.new()
	points.mouth = Vector3(0.05, 0.0, 0.0)
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame := Transform3D.IDENTITY
	var node := FakePoseNode.new()
	driver.call("begin", view, frame)
	var base := offset_of(driver)
	check(near_v(base, Vector3(0.05, 0.0, 0.0)), "the press starts from the captured residual")
	driver.call("tick", 0.5, view, 1.0, frame, node)
	var pressed := offset_of(driver)
	check(pressed.x > base.x + FACE.PRESS_M * 0.9,
		"full depth presses her toward his mouth")
	check(pressed.length() > base.length(), "the press adds a live correction")
	var idle: Variant = _make(points)
	idle.call("begin", _view(), frame)
	var idle_node := FakePoseNode.new()
	idle.call("tick", 0.5, _view(), 0.0, frame, idle_node)
	check(offset_of(idle).x < pressed.x, "zero depth does not press")
	node.free()
	idle_node.free()


func _check_moving_bed() -> void:
	var points := FakePoints.new()
	points.mouth = Vector3(0.2, 0.3, -0.4)
	points.opening = Vector3(0.1, 0.2, -0.3)
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame_a := Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.0, 0.6, 0.0))
	var local_mouth := frame_a.affine_inverse() * points.mouth
	var local_opening := frame_a.affine_inverse() * points.opening
	driver.call("begin", view, frame_a)
	var held := offset_of(driver)
	var frame_b := Transform3D(Basis(Vector3.UP, 0.8), Vector3(1.2, 0.9, -0.7)) * frame_a
	points.mouth = frame_b * local_mouth
	points.opening = frame_b * local_opening
	var node := FakePoseNode.new()
	driver.call("tick", 0.5, view, 0.0, frame_b, node)
	check(near_v(offset_of(driver), held, 0.00001),
		"a moving bed changes the frame but not the frame-space residual")
	check(near_v(node.contact_offset, frame_b.basis * held),
		"the written offset carries with the bed's basis")
	check(near_v(view.get("contact_target") as Vector3, points.mouth),
		"the target follows the moved mouth")
	node.free()


func _check_missing_provider() -> void:
	var points := FakePoints.new()
	points.mouth = Vector3(0.2, 0.3, -0.4)
	points.opening = Vector3(0.1, 0.2, -0.3)
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame := Transform3D.IDENTITY
	var node := FakePoseNode.new()
	driver.call("begin", view, frame)
	driver.call("tick", 0.2, view, 0.5, frame, node)
	var held := offset_of(driver)
	var last_mouth := points.mouth
	points.mouth = Vector3.INF
	driver.call("tick", 0.2, view, 0.5, frame, node)
	check(near_v(offset_of(driver), held), "a missing provider holds the last offset")
	check(near_v(node.contact_offset, frame.basis * held),
		"a missing provider writes the last valid offset")
	check(near_v(view.get("contact_target") as Vector3, last_mouth),
		"a missing provider keeps the last target")
	driver.call("tick", 0.2, view, 0.5, frame, node)
	points.mouth = Vector3(0.25, 0.3, -0.4)
	driver.call("tick", 0.2, view, 0.5, frame, node)
	check(not near_v(offset_of(driver), held), "a valid provider resumes the follow")
	points.mouth = Vector3.INF
	driver.call("tick", 0.2, view, 0.5, frame, node)
	node.free()


func _check_restore() -> void:
	var points := FakePoints.new()
	points.mouth = Vector3(0.2, 0.3, -0.4)
	points.opening = Vector3(0.1, 0.2, -0.3)
	var driver: Variant = _make(points)
	var view: Variant = _view()
	var frame := Transform3D.IDENTITY
	var node := FakePoseNode.new()
	driver.call("begin", view, frame)
	driver.call("tick", 0.5, view, 0.5, frame, node)
	check(node.contact_offset.length() > 0.0, "the node carries a live offset before restore")
	driver.call("restore", view, node)
	check(not bool(driver.get("active")), "restore deactivates the driver")
	check(not bool(driver.get("captured")), "restore drops the capture")
	check(node.contact_offset.is_zero_approx(), "restore zeroes the pose node's offset")
	check(not (view.get("contact_target") as Vector3).is_finite(),
		"restore clears the view's contact target")
	check(near_v(offset_of(driver), Vector3.ZERO), "restore clears the offset")
	driver.call("restore", view, node)
	check(node.contact_offset.is_zero_approx(), "a second restore is a no-op")
	node.free()
