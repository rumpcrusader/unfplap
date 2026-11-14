extends SceneTree
## The act key: the O default, the Y compatibility choice, the mod-owned InputMap action, typing
## protection and the start route through the input service.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_input.gd

const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const INPUT := preload("res://mods/unfplap/input/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

var failures := 0
var checks := 0


class FakeMain extends Node:
	var active_runtime: Node = null
	var starts := 0

	func try_start() -> bool:
		starts += 1
		return true

	func headset_view() -> bool:
		return true


class FakeRuntime extends Node:
	var state := 4


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_choices()
	await _check_action()
	print("INPUT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INPUT_PASS")
	quit(0 if failures == 0 else 1)


## The pure module and the declaration agree on the two choices.
func _check_choices() -> void:
	check(ACT_KEYS.DEFAULT == "o", "the act key defaults to O")
	check(ACT_KEYS.CHOICES == ["o", "y"], "the act key offers O and Y")
	check(ACT_KEYS.label("o") == "O" and ACT_KEYS.label("y") == "Y", "the caps read their key")
	check(ACT_KEYS.key("y") == KEY_Y, "Y maps to KEY_Y")
	check(ACT_KEYS.key("sideways") == KEY_O, "an unknown choice falls back to O")
	check(str(SETTINGS.act_key.default) == ACT_KEYS.DEFAULT, "the setting default is the module default")
	check(SETTINGS.act_key.options == ACT_KEYS.CHOICES, "the setting options are the module choices")
	check(SETTINGS.act_key.labels == ACT_KEYS.LABELS, "the setting labels are the module labels")


## The action lives in the InputMap, follows the setting and starts the act once.
func _check_action() -> void:
	var before := SETTINGS.act_key.get_choice()
	SETTINGS.act_key.set_choice("o")
	var main := FakeMain.new()
	root.add_child(main)
	var service := INPUT.new()
	service.main = main
	main.add_child(service)
	await process_frame

	check(InputMap.has_action(ACT_KEYS.ACTION), "the act action is installed")
	check(not String(ACT_KEYS.ACTION).begins_with("ui_"),
		"the act action is stashed by the game's typing guard")
	check(_action_key() == KEY_O, "the default action is O")

	SETTINGS.act_key.set_choice("y")
	service.call("apply_act_key")
	check(_action_key() == KEY_Y, "the Y choice rebinds the action")
	SETTINGS.act_key.set_choice("o")
	service.call("apply_act_key")
	check(_action_key() == KEY_O, "the O choice rebinds the action back")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_O
	key.pressed = true
	service.call("_input", key)
	check(main.starts == 1, "an idle act-key press starts the hinted act")

	var runtime := FakeRuntime.new()
	main.active_runtime = runtime
	service.call("_input", key)
	check(main.starts == 1, "the act key does not start a second act while one is live")

	# A focused text field takes the action out of the InputMap and restores it afterwards.
	var field := LineEdit.new()
	root.add_child(field)
	field.grab_focus()
	await process_frame
	check(InputMap.action_get_events(ACT_KEYS.ACTION).is_empty(),
		"a text field stashes the act action")
	field.release_focus()
	field.queue_free()
	await process_frame
	check(not InputMap.action_get_events(ACT_KEYS.ACTION).is_empty(),
		"the act action returns after typing")

	service.queue_free()
	main.queue_free()
	runtime.queue_free()
	SETTINGS.act_key.set_choice(before)
	await process_frame


func _action_key() -> int:
	var events := InputMap.action_get_events(ACT_KEYS.ACTION)
	for event: InputEvent in events:
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE
