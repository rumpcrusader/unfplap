extends "res://mods/unfplap/tests/support/suite.gd"
## The debug action wheel's pages and the action registry split.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_debug_wheel.gd
##
## Pure: the wheel layout, the settings-only split, the dynamic cycle labels, the open gate and the
## registry dispatch to the actions node.

const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const DEBUG_WHEEL := preload("res://mods/unfplap/debug/wheel.gd")
const DEBUG_ACTION_NODE := preload("res://mods/unfplap/debug/actions.gd")



## The cycle-phase read the labels ask the actions node.
class PhaseNode extends Node:
	var phase := "heat"

	func debug_cycle_phase() -> String:
		return phase


## A stand-in for the actions node: the gate, the context and the slot dispatch.
class WheelActions extends "res://mods/unfplap/debug/actions.gd":
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


func run() -> void:
	_check_roots()
	_check_pages()
	_check_registry()
	_check_labels()
	_check_gate()
	await _check_node()
	await _check_dispatch()
	if failures == 0:
		print("DEBUG_WHEEL_PASS")
	finish()


func _check_roots() -> void:
	check(DEBUG_ACTIONS.wheel_root(false) == "mare", "no act opens the Mare page")
	check(DEBUG_ACTIONS.wheel_root(true) == "act", "a live act opens the Act page")
	check(DEBUG_ACTIONS.wheel_title("mare") == "Mare", "the Mare page is titled")
	check(DEBUG_ACTIONS.wheel_title("act") == "Act", "the Act page is titled")
	check(DEBUG_ACTIONS.WHEEL_MAX_SLOTS == 9, "the wheel is capped at nine slots")


func _check_pages() -> void:
	check(DEBUG_ACTIONS.wheel_actions("mare") == [
		"show_data", "bed_offer", "bed_cuddle", "standing_offer", "anon_offer",
		"cycle_heat", "cycle_diestrus", "sex_ready", "deep_stretch"],
		"the Mare page order is stable")
	check(DEBUG_ACTIONS.wheel_actions("act") == [
		"show_data", "force_tolerance_warning", "force_tolerance_stop", "force_act_face",
		"deep_stretch"], "the Act page order is stable")
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
	for settings_only: String in ["reset_act_history", "reload_pose", "give_stool",
			"cycle_auto", "facesit_variant", "clear_cooldown"]:
		check(DEBUG_ACTIONS.ACTIONS.has(settings_only),
			"the settings-only action %s stays registered" % settings_only)
		check(not _wheel_has(settings_only), "the wheel leaves %s to settings" % settings_only)
		check(bool(DEBUG_ACTIONS.ACTIONS[settings_only].get("panel", true)),
			"the settings-only action %s stays on the panel" % settings_only)
	check(str(DEBUG_ACTIONS.ACTIONS["facesit_variant"].get("label", "")) == "Pose: face-sit",
		"the face-sit action label")
	check(str(DEBUG_ACTIONS.ACTIONS["facesit_variant"].get("method", "")) == "action_facesit_variant",
		"the face-sit action method")
	check(str(DEBUG_ACTIONS.ACTIONS["facesit_variant"].get("help", "")).contains("face-sit"),
		"the face-sit action help names the pose")
	check(not (DEBUG_ACTIONS.ACTIONS["facesit_variant"] as Dictionary).has("hotkey"),
		"the face-sit action has no hotkey")
	for page: String in DEBUG_ACTIONS.WHEEL_PAGES:
		for name: String in DEBUG_ACTIONS.wheel_actions(page):
			check(not bool(DEBUG_ACTIONS.ACTIONS[name].get("panel", true)),
				"the wheel action %s stays off the settings blocks" % name)
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
	check(not bool(DEBUG_ACTIONS.ACTIONS["sex_ready"].get("panel", true)),
		"the sex-ready action is wheel-only")
	check(str(DEBUG_ACTIONS.ACTIONS["sex_ready"].get("short", "")) == "Sex ready",
		"the sex-ready action has its wheel label")
	check(not bool(DEBUG_ACTIONS.ACTIONS["force_act_face"].get("panel", true)),
		"the face action is wheel-only")
	check(DEBUG_ACTIONS.ACTIONS.has("deep_stretch"), "the deep-stretch action is registered")
	check(str(DEBUG_ACTIONS.ACTIONS["deep_stretch"].get("label", "")) == "Force deep stretch",
		"the deep-stretch action label")
	check(str(DEBUG_ACTIONS.ACTIONS["deep_stretch"].get("method", "")) == "action_deep_stretch",
		"the deep-stretch action method")
	check(str(DEBUG_ACTIONS.ACTIONS["deep_stretch"].get("short", "")) == "Deep stretch",
		"the deep-stretch wheel label")
	check(not bool(DEBUG_ACTIONS.ACTIONS["deep_stretch"].get("panel", true)),
		"the deep-stretch action is wheel-only")
	check(not (DEBUG_ACTIONS.ACTIONS["deep_stretch"] as Dictionary).has("hotkey"),
		"the deep-stretch action has no hotkey")


## One clear desktop frame, then one closed gate at a time.
func _check_gate() -> void:
	check(DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, true, true, false, false,
		false), "a captured, focused desktop frame opens the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, true, false, false,
		false, false), "a free mouse refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, true, false, true, true, false,
		false, false), "a paused tree refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, true, true, false,
		true, false), "a focused text field refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(false, false, true, false, false, true, true, false,
		false, false), "debug off refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, true, true, false, false, true, true, false,
		false, false), "a headless display refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, false, false, false, true, true, false,
		false, false), "no world refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, true, true, true, false,
		false, false), "a headset eye refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, false, true, false,
		false, false), "an unfocused window refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, true, true, true,
		false, false), "an open menu refuses the wheel")
	check(not DEBUG_ACTIONS.wheel_gate(true, false, true, false, false, true, true, false,
		false, true), "a held left button refuses the wheel")


## The registry resolves the actions node by itself: run, label, gate and clears it on exit.
func _check_dispatch() -> void:
	check(not DEBUG_ACTIONS.run_action("show_data").begins_with("Data written"),
		"no actions node runs no action")
	check(DEBUG_ACTIONS.run_action("no_such_action").is_empty(),
		"an unknown action runs nothing")
	check(not DEBUG_ACTIONS.wheel_open(), "no actions node has no open wheel")
	check(not DEBUG_ACTIONS.skeleton_click(), "no actions node clicks no joint")
	var node: Node = DEBUG_ACTION_NODE.new()
	root.add_child(node)
	await process_frame
	check(DEBUG_ACTIONS.target == node, "the actions node registers itself")
	check(DEBUG_ACTIONS.run_action("show_data") == "Player not ready.",
		"the registry dispatch reaches the actions node")
	check(DEBUG_ACTIONS.action_short("show_data") == "Show data",
		"the registry label reads the actions node")
	check(DEBUG_ACTIONS.action_label("show_data") == "Show data",
		"the registry full label reads the actions node")
	check(not DEBUG_ACTIONS.wheel_open(), "the actions node has no wheel yet")
	var press := _button(MOUSE_BUTTON_MIDDLE, true)
	check(not DEBUG_ACTIONS.wheel_input(press),
		"the live wheel input refuses while the headless gate is closed")
	root.remove_child(node)
	node.free()
	check(DEBUG_ACTIONS.target == null, "the actions node clears the registry on exit")
	check(DEBUG_ACTIONS.run_action("show_data").is_empty(), "a freed node is no target")


func _check_labels() -> void:
	var node := PhaseNode.new()
	check(DEBUG_ACTIONS.action_label("cycle_heat", null) == "Force heat",
		"cycle heat defaults to Force without a target")
	check(DEBUG_ACTIONS.action_short("cycle_heat", null) == "Force heat",
		"the short cycle heat defaults to Force without a target")
	node.phase = "heat"
	check(DEBUG_ACTIONS.action_label("cycle_heat", node) == "Clear heat",
		"cycle heat shows Clear in heat")
	check(DEBUG_ACTIONS.action_short("cycle_heat", node) == "Clear heat",
		"the short cycle heat shows Clear in heat")
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", node) == "Force diestrus",
		"cycle diestrus stays Force in heat")
	node.phase = "diestrus"
	check(DEBUG_ACTIONS.action_label("cycle_diestrus", node) == "Clear diestrus",
		"cycle diestrus shows Clear in diestrus")
	check(DEBUG_ACTIONS.action_label("cycle_heat", node) == "Force heat",
		"cycle heat returns to Force in diestrus")
	node.free()


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
	var fake := WheelActions.new()
	root.add_child(fake)
	wheel.set("actions", fake)
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
