extends "res://mods/unfplap/tests/support/suite.gd"
## The bed face-sit debug action and its runtime refusal helper: the pair toggle, every refusal
## reason in order and the ready case. Pure fakes; no game scene.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_face_sit_action.gd

const MAIN := preload("res://mods/unfplap/main.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const POSES := preload("res://mods/unfplap/poses/service.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")



## The act input protocol the debug action reaches through the runtime's session handle.
class FakeInput extends RefCounted:
	var rt: Variant = null

	func request_pose(target_id: String, trigger := "",
			request: POSES.PoseRequest = null) -> POSES.PoseResult:
		return rt.request_pose(target_id, trigger, request)


class FakeAct extends RefCounted:
	var input: FakeInput = FakeInput.new()
	var rt: Variant = null

	func face_sit_error() -> String:
		return rt.face_sit_error()

	func pose_view() -> Variant:
		return rt.pose_view()


class FakeRuntime extends Node:
	var error := ""
	var target := ""
	var view_id := CATALOG.MISSIONARY
	var requests := 0
	var act := FakeAct.new()

	func _init() -> void:
		act.input.rt = self
		act.rt = self

	func face_sit_error() -> String:
		return error

	func pose_view() -> Variant:
		var view: Variant = VIEW.new()
		view.id = view_id
		return view

	func request_pose(target_id: String, _trigger := "",
			_request: POSES.PoseRequest = null) -> POSES.PoseResult:
		requests += 1
		target = target_id
		return POSES.PoseResult.make("ok")


func run() -> void:
	_check_helper()
	_check_action()
	if failures == 0:
		print("FACE_SIT_ACTION_PASS")
	finish()


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var view: Variant = VIEW.new()
	view.id = CATALOG.MISSIONARY
	view.pose_state = VIEW.STEADY
	var pose: RefCounted = POSES.new()
	pose.bind(runtime, null)
	pose.facts = runtime._bundle.facts
	pose._view = view
	pose.act_body = MISSIONARY_ANON.new()
	runtime.act._set_state(2)
	runtime._bundle.pose = pose
	runtime.act.context.pose = pose
	runtime._bundle.facts.missionary_anon = Callable(pose, "act_body_handle")
	runtime._bundle.facts.kiss_active = false
	root.add_child(runtime)
	return {"runtime": runtime, "pose": pose, "view": view}


func _free_fixture(made: Dictionary) -> void:
	var runtime: Node = made["runtime"]
	var pose: RefCounted = made["pose"]
	root.remove_child(runtime)
	runtime.free()
	if is_instance_valid(pose.act_body):
		pose.act_body.free()


func _check_helper() -> void:
	var previous := SETTINGS.anatomy_mode.get_choice()
	SETTINGS.anatomy_mode.set_choice("act")
	var made := _fixture()
	var runtime: Node = made["runtime"]
	var pose: RefCounted = made["pose"]
	var view: Variant = made["view"]
	runtime.act._set_state(0)
	check(runtime.act.face_sit_error() == "no active act", "no idle act is refused")
	runtime.act._set_state(5)
	check(runtime.act.face_sit_error() == "no active act", "a restoring act is refused")
	runtime.act._set_state(2)
	view.id = CATALOG.STANDING
	check(runtime.act.face_sit_error() == "only in a missionary act",
		"a standing view is refused")
	view.id = CATALOG.MISSIONARY
	runtime.act._set_state(1)
	check(runtime.act.face_sit_error() == "the act is not active",
		"a posing act is refused")
	runtime.act._set_state(2)
	check(runtime.act.face_sit_error() == "", "a steady missionary act is ready")
	view.pose_state = VIEW.TRANSITIONING
	check(runtime.act.face_sit_error() == "the pose is changing",
		"a changing pose is refused")
	view.pose_state = VIEW.STEADY
	runtime._bundle.facts.kiss_active = true
	check(runtime.act.face_sit_error() == "a kiss is running", "a running kiss is refused")
	runtime._bundle.facts.kiss_active = false
	SETTINGS.anatomy_mode.set_choice("never")
	check(runtime.act.face_sit_error() == "the anatomy is not available",
		"the anatomy master off is refused")
	SETTINGS.anatomy_mode.set_choice("act")
	pose.act_body = null
	check(runtime.act.face_sit_error() == "the anatomy is not available",
		"a missing act body is refused")
	pose.act_body = MISSIONARY_ANON.new()
	view.id = CATALOG.BED_FACESIT
	check(runtime.act.face_sit_error() == "", "a steady face-sit act is ready")
	view.id = CATALOG.MISSIONARY
	_free_fixture(made)
	SETTINGS.anatomy_mode.set_choice(previous)


func _check_action() -> void:
	var main: Node = MAIN.new()
	root.add_child(main)
	var runtime := FakeRuntime.new()
	root.add_child(runtime)
	runtime.view_id = CATALOG.MISSIONARY
	var actions: Node = main.get("debug_actions")
	check(is_instance_valid(actions), "the entry builds the debug actions node")
	if not is_instance_valid(actions):
		return
	check(DEBUG_ACTIONS.target == actions, "the registry dispatches to the actions node")
	actions.get("host").act = func() -> Node: return runtime
	var result := DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 1 and runtime.target == CATALOG.BED_FACESIT,
		"the action requests bed_facesit from missionary")
	check(result == "Pose bed_facesit: ok.", "the action returns the human result")
	runtime.view_id = CATALOG.BED_FACESIT
	DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 2 and runtime.target == CATALOG.MISSIONARY,
		"the action requests missionary from bed_facesit")
	runtime.error = "a kiss is running"
	var refused := DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 2, "a refused action requests no pose")
	check(refused == "Face-sit refused: a kiss is running.",
		"the action returns the refusal reason")
	runtime.error = ""
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(main)
	main.free()
