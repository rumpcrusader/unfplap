extends SceneTree
## The debug action wheel's pages and the action registry split.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_debug_wheel.gd
##
## Pure: the wheel layout, the settings-only split and the dynamic cycle labels.

const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const DEBUG_WHEEL := preload("res://mods/unfplap/debug/wheel.gd")

var failures := 0
var checks := 0


class PhaseMain extends Node:
	var phase := "heat"

	func debug_cycle_phase() -> String:
		return phase


class WheelMain extends Node:
	var last_action := ""

	func debug_wheel_allowed() -> bool:
		return true

	func debug_wheel_context() -> Dictionary:
		return {"pony": null, "name": "No mare", "source": "none", "act": false}

	func debug_wheel_act_live() -> bool:
		return false

	func debug_wheel_action(name: String) -> String:
		last_action = name
		return ""


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_roots()
	_check_pages()
	_check_registry()
	_check_labels()
	await _check_node()
	print("DEBUG_WHEEL_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("DEBUG_WHEEL_PASS")
	quit(0 if failures == 0 else 1)


func _check_roots() -> void:
	check(DEBUG_ACTIONS.wheel_root(false) == "mare", "no act opens the Mare page")
	check(DEBUG_ACTIONS.wheel_root(true) == "act", "a live act opens the Act page")
	check(DEBUG_ACTIONS.wheel_title("mare") == "Mare", "the Mare page is titled")
	check(DEBUG_ACTIONS.wheel_title("act") == "Act", "the Act page is titled")
	check(DEBUG_ACTIONS.WHEEL_MAX_SLOTS == 6, "the wheel is capped at six slots")


func _check_pages() -> void:
	check(DEBUG_ACTIONS.wheel_actions("mare") == [
		"show_data", "bed_offer", "bed_cuddle", "standing_offer", "cycle_heat",
		"cycle_diestrus"], "the Mare page order is stable")
	check(DEBUG_ACTIONS.wheel_actions("act") == [
		"show_data", "force_tolerance_warning", "force_tolerance_stop", "force_act_face"],
		"the Act page order is stable")
	for page: String in ["mare", "act"]:
		var actions: Array[String] = DEBUG_ACTIONS.wheel_actions(page)
		var seen := {}
		check(not actions.is_empty(), "%s page has actions" % page)
		check(actions.size() <= DEBUG_ACTIONS.WHEEL_MAX_SLOTS,
			"%s page fits the slot cap" % page)
		for name: String in actions:
			check(not seen.has(name), "%s page has no duplicate %s" % [page, name])
			seen[name] = true
			check(DEBUG_ACTIONS.ACTIONS.has(name), "%s page action %s is registered" % [page, name])
	check(DEBUG_ACTIONS.wheel_actions("act").has("force_act_face"),
		"the Act page carries the face action")
	check(not DEBUG_ACTIONS.wheel_actions("act").has("cycle_heat"),
		"the Act page has no cycle toggle")
	check(not DEBUG_ACTIONS.wheel_actions("mare").has("force_tolerance_stop"),
		"the Mare page has no neglect action")
	check(DEBUG_ACTIONS.wheel_actions("mare").has("show_data")
		and DEBUG_ACTIONS.wheel_actions("act").has("show_data"),
		"Show data is on both pages")


func _check_registry() -> void:
	for removed: String in ["show_act_history", "show_stool", "show_act_face",
			"show_prompt_context", "pose_state", "force_heat", "force_diestrus",
			"clear_cycle_override", "skeleton_overlay"]:
		check(not DEBUG_ACTIONS.ACTIONS.has(removed), "the retired action %s is gone" % removed)
		check(not _wheel_has(removed), "the wheel does not carry %s" % removed)
	for settings_only: String in ["reset_act_history", "reload_pose", "give_stool",
			"reset_act_prompts", "cycle_auto"]:
		check(DEBUG_ACTIONS.ACTIONS.has(settings_only),
			"the settings-only action %s stays registered" % settings_only)
		check(not _wheel_has(settings_only), "the wheel leaves %s to settings" % settings_only)
	for name: String in DEBUG_ACTIONS.ACTIONS:
		if name.begins_with("anatomy_") or name.begins_with("tail_") \
				or name.begins_with("placement_"):
			check(not _wheel_has(name), "the wheel leaves the anatomy action %s out" % name)
	check(str(DEBUG_ACTIONS.ACTIONS["cycle_heat"].get("phase", "")) == "heat",
		"cycle heat carries its phase")
	check(str(DEBUG_ACTIONS.ACTIONS["cycle_diestrus"].get("phase", "")) == "diestrus",
		"cycle diestrus carries its phase")
	check(str(DEBUG_ACTIONS.ACTIONS["cycle_heat"].get("match_label", "")) == "Clear heat",
		"cycle heat carries its Clear label")
	check(str(DEBUG_ACTIONS.ACTIONS["cycle_diestrus"].get("match_label", "")) == "Clear diestrus",
		"cycle diestrus carries its Clear label")
	check(not bool(DEBUG_ACTIONS.ACTIONS["bed_cuddle"].get("panel", true)),
		"the bed cuddle is wheel-only")
	check(str(DEBUG_ACTIONS.ACTIONS["bed_cuddle"].get("short", "")) == "Bed cuddle",
		"the bed cuddle has its wheel label")
	check(DEBUG_ACTIONS.ACTIONS.has("force_act_face"),
		"the Act page face action is still a panel action")


func _check_labels() -> void:
	var main := PhaseMain.new()
	check(DEBUG_ACTIONS.action_label("cycle_heat", null) == "Force heat",
		"cycle heat defaults to Force without a target")
	check(DEBUG_ACTIONS.action_short("cycle_heat", null) == "Force heat",
		"the short cycle heat defaults to Force without a target")
	main.phase = "heat"
	check(DEBUG_ACTIONS.action_label("cycle_heat", main) == "Clear heat",
		"cycle heat shows Clear in heat")
	check(DEBUG_ACTIONS.action_short("cycle_heat", main) == "Clear heat",
		"the short cycle heat shows Clear in heat")
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", main) == "Force diestrus",
		"cycle diestrus stays Force in heat")
	main.phase = "diestrus"
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", main) == "Clear diestrus",
		"cycle diestrus shows Clear in diestrus")
	check(DEBUG_ACTIONS.action_label("cycle_heat", main) == "Force heat",
		"cycle heat returns to Force in diestrus")
	main.free()


func _button(index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _hover_top(wheel: CanvasLayer) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0.0, -200.0)
	wheel.call("handle_input", motion)


## The wheel scene builds without a game and follows the hold-middle contract; this catches a
## broken _ready or input path before a manual lab does.
func _check_node() -> void:
	var wheel: CanvasLayer = DEBUG_WHEEL.new()
	root.add_child(wheel)
	check(not bool(wheel.call("is_open")), "the wheel starts closed")
	check(not bool(wheel.call("handle_input", InputEventMouseButton.new())),
		"the wheel ignores an unhandled button while closed")
	var fake := WheelMain.new()
	root.add_child(fake)
	wheel.set("main", fake)
	await process_frame
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, true))),
		"the middle press is consumed")
	check(bool(wheel.call("is_open")), "the middle press opens the wheel")
	_hover_top(wheel)
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_LEFT, true))),
		"the left press is consumed")
	check(fake.last_action == "show_data", "the left click runs the top slot")
	check(not bool(wheel.call("is_open")), "the left click closes the wheel")
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, true))),
		"the wheel reopens on a middle press")
	fake.last_action = ""
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, false))),
		"the centre release is consumed")
	check(not bool(wheel.call("is_open")), "the centre release closes the wheel")
	check(fake.last_action.is_empty(), "the centre release does not run a slot")
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, true))),
		"the wheel reopens after a centre release")
	_hover_top(wheel)
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, false))),
		"the slot release is consumed")
	check(not bool(wheel.call("is_open")), "the slot release closes the wheel")
	check(fake.last_action == "show_data", "the middle release runs the hovered slot")
	check(bool(wheel.call("handle_input", _button(MOUSE_BUTTON_MIDDLE, true))),
		"the wheel reopens after a slot release")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	check(bool(wheel.call("handle_input", escape)), "Escape is consumed while open")
	check(not bool(wheel.call("is_open")), "Escape closes the wheel")
	wheel.free()
	fake.free()


func _wheel_has(name: String) -> bool:
	for page: String in DEBUG_ACTIONS.WHEEL_PAGES:
		if DEBUG_ACTIONS.wheel_actions(page).has(name):
			return true
	return false
