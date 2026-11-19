extends SceneTree
## The bed face-sit debug action and its runtime refusal helper: the pair toggle, every refusal
## reason in order and the ready case. Pure fakes; no game scene.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_face_sit_action.gd

## Loaded at run time: `main.gd` names the game's `Mods` autoload, which the `--script`
## compiler cannot see at preload time. The autoload node exists before the suite runs.
var MAIN: Variant = null
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const POSES := preload("res://mods/unfplap/poses/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

var failures := 0
var checks := 0


class FakeBridge extends RefCounted:
	var missionary_anon: Variant = null

	func bind(_host: Variant) -> void:
		pass

	func refresh() -> void:
		pass

	func end() -> void:
		pass

	func detach() -> void:
		pass

	func missionary_anon_body() -> Variant:
		return missionary_anon


## The act input protocol the debug action reaches through the runtime's session handle.
class FakeInput extends RefCounted:
	var rt: Variant = null

	func request_pose(target_id: String, trigger := "", request: Dictionary = {}) -> Dictionary:
		return rt.request_pose(target_id, trigger, request)


class FakeAct extends RefCounted:
	var input: FakeInput = FakeInput.new()


class FakeRuntime extends Node:
	var error := ""
	var target := ""
	var view_id := CATALOG.MISSIONARY
	var requests := 0
	var act := FakeAct.new()

	func _init() -> void:
		act.input.rt = self

	func face_sit_error() -> String:
		return error

	func pose_view() -> Variant:
		var view: Variant = VIEW.new()
		view.id = view_id
		return view

	func request_pose(target_id: String, _trigger := "", _context: Dictionary = {}) -> Dictionary:
		requests += 1
		target = target_id
		return {"ok": true, "code": "ok", "edge": "", "reason": ""}


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_helper()
	_check_action()
	print("FACE_SIT_ACTION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("FACE_SIT_ACTION_PASS")
	quit(0 if failures == 0 else 1)


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var view: Variant = VIEW.new()
	view.id = CATALOG.MISSIONARY
	view.pose_state = VIEW.STEADY
	var pose: RefCounted = POSES.new()
	pose.bind(runtime, null)
	pose.facts = runtime._act_facts
	pose._view = view
	pose.act_body = Node.new()
	var bridge := FakeBridge.new()
	bridge.missionary_anon = Node.new()
	runtime._set_state(2)
	runtime._pose_session = pose
	runtime._anatomy_bridge = bridge
	runtime._act_facts.kiss_active = false
	root.add_child(runtime)
	return {"runtime": runtime, "pose": pose, "bridge": bridge, "view": view}


func _free_fixture(made: Dictionary) -> void:
	var runtime: Node = made["runtime"]
	var pose: RefCounted = made["pose"]
	var bridge: FakeBridge = made["bridge"]
	root.remove_child(runtime)
	runtime.free()
	if is_instance_valid(pose.act_body):
		pose.act_body.free()
	if is_instance_valid(bridge.missionary_anon):
		bridge.missionary_anon.free()


func _check_helper() -> void:
	var previous := SETTINGS.anatomy_mode.get_choice()
	SETTINGS.anatomy_mode.set_choice("act")
	var made := _fixture()
	var runtime: Node = made["runtime"]
	var pose: RefCounted = made["pose"]
	var bridge: FakeBridge = made["bridge"]
	var view: Variant = made["view"]
	runtime._set_state(0)
	check(runtime.face_sit_error() == "no active act", "no idle act is refused")
	runtime._set_state(5)
	check(runtime.face_sit_error() == "no active act", "a restoring act is refused")
	runtime._set_state(2)
	view.id = CATALOG.STANDING
	check(runtime.face_sit_error() == "only in a missionary act",
		"a standing view is refused")
	view.id = CATALOG.MISSIONARY
	runtime._set_state(1)
	check(runtime.face_sit_error() == "the act is not active",
		"a posing act is refused")
	runtime._set_state(2)
	check(runtime.face_sit_error() == "", "a steady missionary act is ready")
	view.pose_state = VIEW.TRANSITIONING
	check(runtime.face_sit_error() == "the pose is changing",
		"a changing pose is refused")
	view.pose_state = VIEW.STEADY
	runtime._act_facts.kiss_active = true
	check(runtime.face_sit_error() == "a kiss is running", "a running kiss is refused")
	runtime._act_facts.kiss_active = false
	SETTINGS.anatomy_mode.set_choice("never")
	check(runtime.face_sit_error() == "the anatomy is not available",
		"the anatomy master off is refused")
	SETTINGS.anatomy_mode.set_choice("act")
	pose.act_body = null
	check(runtime.face_sit_error() == "the anatomy is not available",
		"a missing act body is refused")
	pose.act_body = Node.new()
	bridge.missionary_anon = null
	check(runtime.face_sit_error() == "the anatomy is not available",
		"a missing bridge handle is refused")
	bridge.missionary_anon = Node.new()
	view.id = CATALOG.BED_FACESIT
	check(runtime.face_sit_error() == "", "a steady face-sit act is ready")
	view.id = CATALOG.MISSIONARY
	_free_fixture(made)
	SETTINGS.anatomy_mode.set_choice(previous)


func _check_action() -> void:
	MAIN = load("res://mods/unfplap/main.gd")
	check(MAIN != null, "main.gd loads with the game autoloads")
	if MAIN == null:
		return
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
