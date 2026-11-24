extends "res://mods/unfplap/tests/support/suite.gd"
## The bed face-sit debug action: the pair toggle, its view guard and the pose service's refusal
## message. Pure fakes; no game scene. The refusal order itself is the pose suite's.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_face_sit_action.gd

const MAIN := preload("res://mods/unfplap/main.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/api.gd")
const POSES := preload("res://mods/unfplap/poses/api.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")



## The act input protocol the debug action reaches through the runtime's session handle.
class FakeInput extends RefCounted:
	var rt: Variant = null

	func request_pose(target_id: String, trigger := "",
			consent := "") -> POSES.PoseResult:
		return rt.request_pose(target_id, trigger, consent)


class FakeAct extends RefCounted:
	var input: FakeInput = FakeInput.new()
	var rt: Variant = null

	func pose_view() -> Variant:
		return rt.pose_view()


class FakeRuntime extends Node:
	var result_code := "ok"
	var result_reason := ""
	var target := ""
	var view_id := CATALOG.MISSIONARY
	var requests := 0
	var act := FakeAct.new()

	func _init() -> void:
		act.input.rt = self
		act.rt = self

	func pose_view() -> Variant:
		var view: Variant = VIEW.new()
		view.id = view_id
		return view

	func request_pose(target_id: String, _trigger := "",
			_consent := "") -> POSES.PoseResult:
		requests += 1
		target = target_id
		return POSES.PoseResult.make(result_code, result_reason)


func run() -> void:
	_check_action()
	if failures == 0:
		print("FACE_SIT_ACTION_PASS")
	finish()


func _check_action() -> void:
	var main: Node = MAIN.new()
	root.add_child(main)
	var runtime := FakeRuntime.new()
	root.add_child(runtime)
	var actions: Node = main.get("debug_actions")
	check(is_instance_valid(actions), "the entry builds the debug actions node")
	if not is_instance_valid(actions):
		return
	check(DEBUG_ACTIONS.target == actions, "the registry dispatches to the actions node")
	actions.get("host").act = func() -> Node: return runtime

	runtime.view_id = CATALOG.STANDING
	var guard := DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 0, "a standing view asks the pose service nothing")
	check(guard == "Only in a missionary act.", "a standing view is refused")

	runtime.view_id = CATALOG.MISSIONARY
	var result := DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 1 and runtime.target == CATALOG.BED_FACESIT,
		"the action requests bed_facesit from missionary")
	check(result == "Pose bed_facesit: ok.", "the action returns the human result")

	runtime.view_id = CATALOG.BED_FACESIT
	DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 2 and runtime.target == CATALOG.MISSIONARY,
		"the action requests missionary from bed_facesit")

	runtime.result_code = "refused"
	runtime.result_reason = "a kiss is running"
	var refused := DEBUG_ACTIONS.run_action("facesit_variant")
	check(runtime.requests == 3, "a refused action still asks the pose service")
	check(refused == "Face-sit refused: a kiss is running.",
		"the action returns the refusal reason")
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(main)
	main.free()
