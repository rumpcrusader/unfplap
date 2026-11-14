extends SceneTree
## The act key: the 6 default, any-key capture, the mod-owned InputMap action, typing protection,
## the start route through the input service and the act input shield.
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
	var chats := 0
	var panels := false

	func try_start() -> bool:
		starts += 1
		return true

	func open_act_chat() -> bool:
		chats += 1
		return true

	func menu_panel_open() -> bool:
		return panels

	func skeleton_click() -> bool:
		return false

	func headset_view() -> bool:
		return true


class FakeRuntime extends Node:
	var state := 4
	var holes := 0
	var orals := 0
	var finishes := 0
	var smacks := 0

	func anatomy_hole_ready() -> bool:
		return true

	func anatomy_oral_ready() -> bool:
		return true

	func anatomy_finish_ready() -> bool:
		return true

	func toggle_anatomy_hole() -> void:
		holes += 1

	func toggle_anatomy_oral() -> void:
		orals += 1

	func toggle_anatomy_finish() -> void:
		finishes += 1

	func smack() -> void:
		smacks += 1

	func auto_thrust_wheel(_direction: int) -> void:
		pass


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_choices()
	await _check_injection()
	await _check_action()
	await _check_shield()
	print("INPUT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INPUT_PASS")
	quit(0 if failures == 0 else 1)


## The pure module labels and validates captured keys.
func _check_choices() -> void:
	check(ACT_KEYS.DEFAULT_CODE == KEY_6, "the legacy act-key fallback stays 6")
	check(ACT_KEYS.label(KEY_6) == "6", "the cap reads its number")
	check(ACT_KEYS.label(KEY_O) == "O" and ACT_KEYS.label(KEY_Y) == "Y",
		"any captured key gets its label")
	check(ACT_KEYS.code(KEY_F) == KEY_F, "a captured key is kept")
	check(ACT_KEYS.code(0) == KEY_6, "an invalid code falls back to 6")
	check(bool(SETTINGS.act_key.hidden), "the setting is drawn by the hand-built capture row")


func _key(code: int, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


## The shield's HACK: a parsed release clears the state a raw-key poller reads. Headless may not
## dispatch parsed events to the viewport, but it always updates Input's key state.
func _check_injection() -> void:
	Input.parse_input_event(_key(KEY_N))
	await physics_frame
	await physics_frame
	check(Input.is_physical_key_pressed(KEY_N) and Input.is_key_pressed(KEY_N),
		"a parsed press sets the key state")
	Input.parse_input_event(_key(KEY_N, false))
	await physics_frame
	await physics_frame
	check(not Input.is_physical_key_pressed(KEY_N) and not Input.is_key_pressed(KEY_N),
		"a parsed release clears the key state")


## The action lives in the InputMap, follows the setting and starts the act once.
func _check_action() -> void:
	var before := int(SETTINGS.act_key.get_num())
	SETTINGS.act_key.set_num(float(KEY_6))
	var main := FakeMain.new()
	root.add_child(main)
	var service := INPUT.new()
	service.main = main
	main.add_child(service)
	await process_frame

	check(InputMap.has_action(ACT_KEYS.ACTION), "the act action is installed")
	check(not String(ACT_KEYS.ACTION).begins_with("ui_"),
		"the act action is stashed by the game's typing guard")
	check(_action_key() == KEY_6, "the default action is 6")

	SETTINGS.act_key.set_num(float(KEY_Y))
	service.call("apply_settings")
	check(_action_key() == KEY_Y, "a captured Y rebinds the action")
	SETTINGS.act_key.set_num(float(KEY_O))
	service.call("apply_settings")
	check(_action_key() == KEY_O, "a captured O rebinds the action")
	SETTINGS.act_key.set_num(float(KEY_6))
	service.call("apply_settings")
	check(_action_key() == KEY_6, "a captured 6 restores the default")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_6
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
	SETTINGS.act_key.set_num(float(before))
	await process_frame


## The act input shield: foreign keys are consumed and their polled state cleared, the act's own
## polled keys keep theirs, and typing, T, Esc, F1-F12 and a paused/menu tree stay live.
func _check_shield() -> void:
	var before := SETTINGS.act_input_shield.get_bool()
	SETTINGS.act_input_shield.set_bool(true)
	var main := FakeMain.new()
	root.add_child(main)
	var service := INPUT.new()
	service.main = main
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 2
	main.active_runtime = runtime
	await process_frame
	check(bool(service.get("_shield")), "the shield follows its setting")

	# Typing owns the keyboard: nothing is consumed and the raw state survives.
	var field := LineEdit.new()
	root.add_child(field)
	field.grab_focus()
	await process_frame
	await _hold(service, KEY_P)
	_reset_handled()
	service.call("_input", _key(KEY_P))
	check(not root.is_input_handled(), "typing is never consumed")
	check(Input.is_physical_key_pressed(KEY_P), "typing keeps the raw key state")
	field.release_focus()
	field.queue_free()
	await process_frame
	await _release(KEY_P)

	# With the shield off, a key outside the act's old interaction list still passes.
	SETTINGS.act_input_shield.set_bool(false)
	service.call("apply_settings")
	await _hold(service, KEY_P)
	_reset_handled()
	service.call("_input", _key(KEY_P))
	check(not root.is_input_handled(), "with the shield off a foreign key passes")
	SETTINGS.act_input_shield.set_bool(true)
	service.call("apply_settings")
	await _release(KEY_P)

	# A paused tree and an open panel belong to the menu.
	paused = true
	await _hold(service, KEY_P)
	_reset_handled()
	service.call("_input", _key(KEY_P))
	check(not root.is_input_handled(), "a paused tree keeps its keys")
	paused = false
	await _release(KEY_P)
	main.panels = true
	await _hold(service, KEY_P)
	_reset_handled()
	service.call("_input", _key(KEY_P))
	check(not root.is_input_handled(), "an open panel keeps its keys")
	main.panels = false
	await _release(KEY_P)

	# The pass list stays live.
	for code: int in [KEY_T, KEY_ESCAPE, KEY_F5]:
		await _hold(service, code)
		_reset_handled()
		service.call("_input", _key(code))
		check(not root.is_input_handled(), "key %d stays live during an act" % code)
		check(Input.is_physical_key_pressed(code), "key %d keeps its state" % code)
		await _release(code)

	# Enter opens the act chat and is consumed there, without clearing its state.
	await _hold(service, KEY_ENTER)
	_reset_handled()
	service.call("_input", _key(KEY_ENTER))
	check(main.chats == 1, "Enter opens the act chat")
	check(root.is_input_handled(), "Enter is consumed by the chat")
	await physics_frame
	check(Input.is_physical_key_pressed(KEY_ENTER), "Enter keeps its state")
	await _release(KEY_ENTER)

	# A foreign key is consumed and its polled state cleared: this is the Pegasus Ride bug.
	await _hold(service, KEY_P)
	service.call("_input", _key(KEY_P))
	check(root.is_input_handled(), "a foreign key is consumed")
	await physics_frame
	check(not Input.is_physical_key_pressed(KEY_P) and not Input.is_key_pressed(KEY_P),
		"a foreign key's raw state is cleared")

	# The act's own raw-polled keys are consumed but keep their state.
	await _hold(service, KEY_X)
	service.call("_input", _key(KEY_X))
	check(root.is_input_handled(), "an act-polled key is consumed")
	await physics_frame
	check(Input.is_physical_key_pressed(KEY_X), "an act-polled key keeps its state")
	await _release(KEY_X)

	# The anatomy action keeps firing and its raw state is cleared too.
	await _hold(service, KEY_N)
	service.call("_input", _key(KEY_N))
	check(runtime.orals == 1, "N still toggles oral")
	check(root.is_input_handled(), "N is consumed")
	await physics_frame
	check(not Input.is_physical_key_pressed(KEY_N), "N's raw state is cleared")

	service.queue_free()
	main.queue_free()
	runtime.queue_free()
	SETTINGS.act_input_shield.set_bool(before)
	await process_frame


## Hold a key's raw state without letting a parsed event reach the service's own `_input`.
func _hold(service: Node, code: int) -> void:
	var saved: Variant = service.main
	service.main = null
	Input.parse_input_event(_key(code))
	await physics_frame
	service.main = saved


func _release(code: int) -> void:
	Input.parse_input_event(_key(code, false))
	await physics_frame


## Clear the viewport's handled flag the way a new dispatch does, without consuming a key.
func _reset_handled() -> void:
	root.push_input(_key(KEY_F24, false))


func _action_key() -> int:
	var events := InputMap.action_get_events(ACT_KEYS.ACTION)
	for event: InputEvent in events:
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE
