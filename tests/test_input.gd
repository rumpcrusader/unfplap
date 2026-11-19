extends SceneTree
## The act key: the 6 default, any-key capture, the mod-owned InputMap action, typing protection,
## the start route through the input service and the act input shield.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_input.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const INPUT := preload("res://mods/unfplap/input/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")

var failures := 0
var checks := 0


## The offer facade the act key hands its one press. Its own act-live rule is
## `tests/offer/test_start.gd`; this records that the input service reached it.
class FakeOffer extends OFFER:
	var starts := 0
	var live := false

	func try_start() -> bool:
		if live:
			return false
		starts += 1
		return true


class FakeWorld extends Node:
	var headset_view := true
	var save_menu: Variant = null

	func _init() -> void:
		var chat := FakeChat.new()
		chat.name = "ChatBox"
		add_child(chat)


class FakeChat extends Node:
	var opened := 0
	var _lock_owned := false

	func _open() -> bool:
		opened += 1
		return true


class FakePanel extends Node:
	var opened := false


class FakePlayer extends Node3D:
	var controls_locked := false


## The input service reads the scene through the world facade: a headset eye, a chat box and the
## menu panels.
func _world() -> Dictionary:
	var world := FakeWorld.new()
	root.add_child(world)
	var menu := FakePanel.new()
	world.add_child(menu)
	world.save_menu = menu
	WORLD.bind_world(world)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_player(player)
	return {"world": world, "chat": world.get_node("ChatBox"), "menu": menu}


## The act input protocol the fake runtime exposes through its session handle.
class FakeActInput extends RefCounted:
	var rt: Variant = null

	func vr_y_held() -> bool:
		return rt.vr_held

	func free_look_active() -> bool:
		return rt.free_look

	func cancel() -> void:
		rt.cancels += 1

	func request_afterglow() -> void:
		rt.afterglows += 1

	func end_afterglow() -> void:
		rt.afterglow_ends += 1

	func thrust_motion(relative_y: float) -> void:
		rt.thrusts.append(relative_y)

	func look_motion(relative: Vector2) -> void:
		rt.looks.append(relative)

	func auto_panel_input(_delta: float, x_down: bool, keys: Array) -> void:
		rt.panels.append([x_down, keys.duplicate()])

	func command(command_id: String) -> bool:
		rt.commands.append(command_id)
		return rt.command_ok

	func auto_thrust_wheel(direction: int) -> void:
		rt.wheels.append(direction)

	func body_swap_pending() -> bool:
		return rt.suspended

	func auto_active() -> bool:
		return rt.auto

	func anatomy_hole_ready() -> bool:
		return rt.action_ready

	func anatomy_oral_ready() -> bool:
		return rt.action_ready

	func smack() -> void:
		rt.smacks += 1

	func climaxes() -> int:
		return rt.pony_climaxes


class FakeAct extends RefCounted:
	var rt: Variant = null
	var state: int:
		get:
			return int(rt.state) if rt != null else 4
	var input: FakeActInput = FakeActInput.new()


class FakeRuntime extends Node:
	var state := 4
	var pony_climaxes := 0
	var suspended := false
	var auto := false
	var free_look := false
	var vr_held := false
	var holes := 0
	var orals := 0
	var smacks := 0
	var cancels := 0
	var afterglows := 0
	var afterglow_ends := 0
	var commands: Array[String] = []
	var wheels: Array[int] = []
	var action_ready := true
	var command_ok := true
	var thrusts: Array[float] = []
	var looks: Array[Vector2] = []
	var panels: Array = []
	var act := FakeAct.new()

	func _init() -> void:
		act.rt = self
		act.input.rt = self

	func anatomy_hole_ready() -> bool:
		return action_ready

	func anatomy_oral_ready() -> bool:
		return action_ready

	func body_swap_pending() -> bool:
		return suspended

	func auto_active() -> bool:
		return auto

	# The legacy anatomy path stays for the callers that still own it directly.
	func toggle_anatomy_hole() -> void:
		holes += 1

	func toggle_anatomy_oral() -> void:
		orals += 1

	func smack() -> void:
		smacks += 1



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
	await _check_act_hold()
	await _check_auto_layer()
	await _check_mouse()
	await _check_act_commands()
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
	var scene := _world()
	var main := Node.new()
	root.add_child(main)
	var offer := FakeOffer.new()
	root.add_child(offer)
	var service := INPUT.new()
	service.offer = offer
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
	check(offer.starts == 1, "an idle act-key press asks the offer to start")

	var runtime := FakeRuntime.new()
	offer.live = true
	PONIES.set_active(runtime)
	service.call("_input", key)
	check(offer.starts == 1, "the act key does not start a second act while one is live")
	offer.live = false

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
	PONIES.clear_active(runtime)
	main.queue_free()
	offer.queue_free()
	runtime.queue_free()
	SETTINGS.act_key.set_num(float(before))
	await process_frame


## The act input shield: foreign keys are consumed and their polled state cleared, the act's own
## polled keys keep theirs, and typing, T, Esc, F1-F12 and a paused/menu tree stay live.
func _check_shield() -> void:
	var before := SETTINGS.act_input_shield.get_bool()
	SETTINGS.act_input_shield.set_bool(true)
	var scene := _world()
	var main := Node.new()
	root.add_child(main)
	var service := INPUT.new()
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 2
	PONIES.set_active(runtime)
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
	(scene["menu"] as FakePanel).opened = true
	await _hold(service, KEY_P)
	_reset_handled()
	service.call("_input", _key(KEY_P))
	check(not root.is_input_handled(), "an open panel keeps its keys")
	(scene["menu"] as FakePanel).opened = false
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
	check(int((scene["chat"] as FakeChat).opened) == 1, "Enter opens the act chat")
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

	# The anatomy action dispatches its command and its raw state is cleared too.
	await _hold(service, KEY_N)
	service.call("_input", _key(KEY_N))
	check(runtime.commands == [ACT_COMMANDS.ORAL], "N dispatches the oral command")
	check(root.is_input_handled(), "N is consumed")
	await physics_frame
	check(not Input.is_physical_key_pressed(KEY_N), "N's raw state is cleared")

	service.queue_free()
	PONIES.clear_active(runtime)
	main.queue_free()
	runtime.queue_free()
	SETTINGS.act_input_shield.set_bool(before)
	await process_frame


## The act-key hold: the 0.35 s latch, one fire per press, the state outcomes, the VR hold and
## the act/suspension resets. The input service owns the timer; the runtime owns the transition.
func _check_act_hold() -> void:
	_world()
	var main := Node.new()
	root.add_child(main)
	var service := INPUT.new()
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 4
	PONIES.set_active(runtime)
	await process_frame

	_arm_hold(service, runtime)
	Input.action_press(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.2, runtime)
	check(runtime.afterglow_ends == 0, "a short hold does nothing")
	service.call("_hold_act_tick", 0.2, runtime)
	check(runtime.afterglow_ends == 1, "AFTERGLOW ends after the full hold")
	service.call("_hold_act_tick", 0.2, runtime)
	check(runtime.afterglow_ends == 1, "a still-held key fires once")
	Input.action_release(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.1, runtime)
	Input.action_press(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.4, runtime)
	check(runtime.afterglow_ends == 2, "a fresh press fires again after the release")
	Input.action_release(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.1, runtime)

	# ACTIVE: no climax cancels early; a climax behind the act requests the afterglow.
	runtime.state = 2
	runtime.pony_climaxes = 0
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.cancels == 1 and runtime.afterglows == 0,
		"ACTIVE with no climax cancels")
	runtime.pony_climaxes = 1
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.afterglows == 1 and runtime.cancels == 1,
		"ACTIVE with a climax requests the afterglow")
	runtime.state = 3
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.afterglows == 2, "CLIMAX requests the afterglow")
	runtime.state = 1
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.cancels == 2, "POSING_IN cancels")

	# A suspended act drops the latch and never fires.
	runtime.state = 2
	runtime.suspended = true
	_arm_hold(service, runtime)
	Input.action_press(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.5, runtime)
	check(runtime.cancels == 2, "a suspended act never fires the hold")
	Input.action_release(ACT_KEYS.ACTION)
	runtime.suspended = false
	service.call("_hold_act_tick", 0.1, runtime)

	# The VR primary click is the same hold without the action.
	runtime.pony_climaxes = 0
	runtime.vr_held = true
	service.call("_hold_act_tick", 0.4, runtime)
	check(runtime.cancels == 3, "the VR act key hold fires")
	runtime.vr_held = false
	service.call("_hold_act_tick", 0.1, runtime)
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.cancels == 4, "the VR release rearms the hold")

	# A new act drops a key still down from the last one.
	PONIES.clear_active(runtime)
	service.call("_physics_process", 0.1)
	PONIES.set_active(runtime)
	Input.action_press(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.5, runtime)
	check(runtime.cancels == 4, "a new act needs a release before the hold")
	Input.action_release(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.1, runtime)
	_arm_hold(service, runtime)
	_fire_hold(service, runtime)
	check(runtime.cancels == 5, "the new act fires after the release")

	service.queue_free()
	PONIES.clear_active(runtime)
	main.queue_free()
	runtime.queue_free()
	await process_frame


## The hold-X layer: the input service samples the physical keys and hands them to the runtime
## protocol; a suspended act samples nothing.
func _check_auto_layer() -> void:
	_world()
	var main := Node.new()
	root.add_child(main)
	var service := INPUT.new()
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 2
	PONIES.set_active(runtime)
	await process_frame

	await _hold(service, KEY_X)
	await _hold(service, KEY_Q)
	runtime.panels.clear()
	service.call("_auto_layer_tick", 0.1, runtime)
	check(runtime.panels.size() == 1, "the auto layer is one protocol call per tick")
	var row: Array = runtime.panels[0]
	check(bool(row[0]), "X reaches the layer as held")
	var keys: Array = row[1]
	check(keys.size() == 7 and bool(keys[0]), "Q is the first layer key")
	check(not bool(keys[1]), "an unpressed layer key reads false")

	runtime.suspended = true
	runtime.panels.clear()
	service.call("_physics_process", 0.1)
	check(runtime.panels.is_empty(), "a suspended act samples no auto keys")
	runtime.suspended = false

	await _release(KEY_X)
	await _release(KEY_Q)
	service.queue_free()
	PONIES.clear_active(runtime)
	main.queue_free()
	runtime.queue_free()
	await process_frame


## Mouse motion: free look drives the camera and is consumed; a free cursor (or an idle/suspended
## act) leaves the event and the stroke alone. Headless cannot capture the mouse, so the capture
## gate is the default state here.
func _check_mouse() -> void:
	_world()
	var main := Node.new()
	root.add_child(main)
	var service := INPUT.new()
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 2
	PONIES.set_active(runtime)
	await process_frame

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(6.0, -8.0)
	runtime.free_look = true
	_reset_handled()
	service.call("_input", motion)
	check(runtime.looks == [Vector2(6.0, -8.0)],
		"free look hands the motion to the camera")
	check(root.is_input_handled(), "free look consumes the motion")
	runtime.free_look = false
	runtime.looks.clear()
	_reset_handled()
	service.call("_input", motion)
	check(runtime.looks.is_empty() and runtime.thrusts.is_empty(),
		"a free cursor never thrusts or free-looks")
	check(not root.is_input_handled(), "a free cursor leaves the motion alone")
	runtime.state = 0
	_reset_handled()
	service.call("_input", motion)
	check(not root.is_input_handled(), "an idle runtime ignores the motion")

	service.queue_free()
	PONIES.clear_active(runtime)
	main.queue_free()
	runtime.queue_free()
	await process_frame


## Arm the hold latch the way a release does, then press and release once.
func _arm_hold(service: Node, runtime: Node) -> void:
	Input.action_release(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.1, runtime)


func _fire_hold(service: Node, runtime: Node) -> void:
	Input.action_press(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.4, runtime)
	Input.action_release(ACT_KEYS.ACTION)
	service.call("_hold_act_tick", 0.1, runtime)


## V/N emit their command ids through the runtime; a non-ready or refused command does not
## dispatch, and the key is consumed either way. B is retired: it is an ordinary blocked key.
func _check_act_commands() -> void:
	var before := SETTINGS.act_input_shield.get_bool()
	SETTINGS.act_input_shield.set_bool(true)
	var scene := _world()
	var main := Node.new()
	root.add_child(main)
	var service := INPUT.new()
	main.add_child(service)
	var runtime := FakeRuntime.new()
	runtime.state = 2
	PONIES.set_active(runtime)
	await process_frame

	for case: Array in [[KEY_V, ACT_COMMANDS.HOLE], [KEY_N, ACT_COMMANDS.ORAL]]:
		var code := int(case[0])
		var command_id := str(case[1])
		runtime.commands.clear()
		await _hold(service, code)
		_reset_handled()
		service.call("_input", _key(code))
		check(runtime.commands == [command_id], "%s dispatches once" % command_id)
		check(root.is_input_handled(), "the %s key is consumed" % command_id)
		await _release(code)

	# The finish key is gone: B dispatches nothing and is only shielded.
	runtime.commands.clear()
	await _hold(service, KEY_B)
	_reset_handled()
	service.call("_input", _key(KEY_B))
	check(runtime.commands.is_empty(), "B dispatches no command")
	check(root.is_input_handled(), "B stays a blocked act key")
	await _release(KEY_B)

	# A closed readiness gate leaves the command undispatched.
	runtime.action_ready = false
	runtime.commands.clear()
	await _hold(service, KEY_N)
	_reset_handled()
	service.call("_input", _key(KEY_N))
	check(runtime.commands.is_empty(), "a non-ready command does not dispatch")
	check(root.is_input_handled(), "a non-ready key is still consumed")
	await _release(KEY_N)
	runtime.action_ready = true

	# A refused command was attempted once and the key is still consumed.
	runtime.command_ok = false
	runtime.commands.clear()
	await _hold(service, KEY_V)
	_reset_handled()
	service.call("_input", _key(KEY_V))
	check(runtime.commands == [ACT_COMMANDS.HOLE], "a refused command is attempted once")
	check(root.is_input_handled(), "a refused key is still consumed")
	await _release(KEY_V)

	service.queue_free()
	PONIES.clear_active(runtime)
	main.queue_free()
	runtime.queue_free()
	SETTINGS.act_input_shield.set_bool(before)
	await process_frame


## Hold a key's raw state without letting a parsed event reach the service's own `_input`.
func _hold(service: Node, code: int) -> void:
	# Mute the service's own `_input` so only the raw key state reaches the tree.
	service.set_process_input(false)
	Input.parse_input_event(_key(code))
	await physics_frame
	service.set_process_input(true)


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
