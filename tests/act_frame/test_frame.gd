extends SceneTree
## The act frame's player contract: the pure solve for one standing and one missionary start, and
## the plan's player-only shape. The live placement stays pinned by the teardown suite.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_frame/test_frame.gd

const FRAME := preload("res://mods/unfplap/act/frame.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, epsilon := 0.0001) -> bool:
	return absf(a - b) <= epsilon


func run() -> void:
	_check_standing()
	_check_missionary()
	_check_plan_shape()
	print("ACT_FRAME_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FRAME_PASS")
	quit(0 if failures == 0 else 1)


## Her forward is -Z, the gap is 0.42 m, and the part's pivot sits 0.32 m behind her root while one
## shaft puts it 0.14 m past her opening: the fit is a 0.18 m step back, so Anon lands 0.24 m
## behind her. This pins the start placement the frame is extracting.
func _check_standing() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("standing")
	check(pose.family == "standing", "the standing row names its family")
	var rig := FRAME.Rig.new()
	rig.forward = Vector3(0.0, 0.0, -1.0)
	rig.pony_position = Vector3(0.0, 0.0, 0.0)
	rig.player_position = Vector3(0.0, 0.0, 0.42)
	rig.gap = 0.42
	rig.eye = 1.6
	rig.neck_height = 1.4
	rig.opening = Vector3(0.0, 0.9, 0.0)
	rig.rear = Vector3(0.0, 0.0, 1.0)
	rig.part_root = Vector3(0.0, 0.9, 0.32)
	rig.shaft_length = 0.14
	var plan := frame.solve(pose, rig)
	check(plan.family == "standing", "the standing solve keeps its family")
	check(near(plan.gap, 0.42), "the solve carries the act gap")
	check(plan.fit.is_equal_approx(Vector3(0.0, 0.0, -0.18)),
		"the whole-body fit moves him one shaft behind her entrance")
	check(plan.root_transform.origin.is_equal_approx(Vector3(0.0, 0.0, 0.24)),
		"the standing plan places Anon at the gap plus the fit")
	check(near(plan.yaw, 0.0), "the standing plan faces Anon along her forward")
	check(near(plan.aim_pitch, atan2(1.4 - 1.6, 0.24)),
		"the standing plan aims at her neck line from the placed eye")
	check(near(plan.look_yaw, plan.yaw) and near(plan.look_pitch, plan.aim_pitch),
		"the plan owns the captured look")
	check(near(plan.eye, 1.6), "the plan carries the stance eye")

	# A stale or unreadable pivot fits nothing instead of pulling him across the gap.
	var broken := FRAME.Rig.new()
	broken.forward = Vector3(0.0, 0.0, -1.0)
	broken.pony_position = Vector3(0.0, 0.0, 0.0)
	broken.gap = 0.42
	broken.shaft_length = 0.14
	broken.opening = Vector3.INF
	broken.rear = Vector3.BACK
	broken.part_root = Vector3.ZERO
	check(FRAME.fit_offset(broken).is_zero_approx(), "an unreadable opening fits nothing")


## The missionary plan carries the act body's placement only: the player rig stays parked.
func _check_missionary() -> void:
	var frame := FRAME.new()
	var pose := FRAME.pose("missionary")
	check(pose.family == "bed", "the missionary row names its family")
	var rig := FRAME.Rig.new()
	rig.act_body_transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.5, 2.0))
	var plan := frame.solve(pose, rig)
	check(plan.family == "bed", "the missionary solve keeps its family")
	check(plan.act_body_transform.is_equal_approx(rig.act_body_transform),
		"the missionary plan places the act body from the asset")
	check(plan.root_transform.is_equal_approx(Transform3D.IDENTITY),
		"the missionary plan never moves the player rig")


## The plan is player-only: it carries no camera transform, shot or eye-override step.
func _check_plan_shape() -> void:
	var names: Array[String] = []
	for field: Dictionary in FRAME.PlayerPlan.new().get_property_list():
		names.append(str(field["name"]))
	check(names.has("root_transform") and names.has("yaw") and names.has("aim_pitch"),
		"the plan carries the player placement and look")
	check(names.has("stand_eye") and names.has("eye_height"),
		"the plan carries the standing stance")
	check(not names.has("camera_transform") and not names.has("shot"),
		"the plan carries no camera transform or shot")
