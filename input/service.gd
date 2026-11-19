extends Node
## Input and the seated-player Q guard. Runs in _input before desktop_player._unhandled_input.
## While an act is active it consumes the act keys and the interaction keys, and keeps the
## game's own stand_up poll from force-standing a seated player.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## Keys the act samples every frame: the lean (Q/E/W/S), the auto layer (Q A W S E D Z, X), the
## caress (A/D, Z/C), the kiss (F) and the act-key hold. They are consumed but their pressed
## state is kept, or the act's own controls would die.
const RAW_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_X, KEY_C, KEY_F]
## Same hold length the game uses for bridal-carry initiation (interactor KEY_HOLD_SECONDS).
const HOLD_ACT_SECONDS := 0.35
## Keys that stay live during an act: typing, the game's talk turn, the pause menu and the game's
## save/settings/weather/debug F-keys.
const PASS_KEYS := [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_T,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
	KEY_F11, KEY_F12]

## The idle offer's facade: the act key hands it the start.
var offer: OFFER = null

## The act input shield, cached from `features.act_input_shield` on every settings change.
var _shield: bool
var _suppress_q := false
var _old_q := false
## One recapture log per act. The cursor can take more than one physics tick to report captured.
var _mouse_recapture_logged := false
## The act-key hold. The latch belongs to one live act: a tap does nothing, and a held key cannot
## fire twice until it is released. A body swap and a fresh act drop it.
var _act_hold := 0.0
var _act_hold_ready := false
var _act_hold_fired := false
var _hold_runtime: Variant = null
## The act's input protocol for the active runtime, resolved once per runtime and not per frame.
var _act_input: Variant = null
var _input_runtime: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	apply_settings()
	CHANGE.on_changed(Callable(self, "apply_settings"))


func _exit_tree() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))
	if InputMap.has_action(ACT_KEYS.ACTION):
		InputMap.erase_action(ACT_KEYS.ACTION)


## Set by the entry: the idle offer the act key hands its press to.
func bind(offer_node: OFFER) -> void:
	offer = offer_node


## Rebuild the mod-owned act action from the captured `act_key` keycode and cache the input
## shield flag. The game's typing guard stashes every non-`ui_` InputMap action while a text
## field has focus, so a real action keeps the act key out of chat without a second focus check
## in the runtime.
func apply_settings() -> void:
	_shield = SETTINGS.act_input_shield.get_bool()
	if InputMap.has_action(ACT_KEYS.ACTION):
		InputMap.action_erase_events(ACT_KEYS.ACTION)
	else:
		InputMap.add_action(ACT_KEYS.ACTION)
	var event := InputEventKey.new()
	event.physical_keycode = ACT_KEYS.code(int(SETTINGS.act_key.get_num()))
	InputMap.action_add_event(ACT_KEYS.ACTION, event)


func _physics_process(delta: float) -> void:
	var runtime: Node = PONIES.active()
	if is_instance_valid(runtime):
		# Pause/settings must not end the act; the runtime simply stops processing while the
		# tree is paused and resumes when the menu closes.
		_suppress_seated_q()
		_hold_movement()
		# A menu, map, inventory or alt-tab that leaves the cursor visible must not keep the
		# act's mouse input dead. The base game's own click-to-recapture is skipped while
		# controls_locked owns the act, so the mod keeps the mouse captured itself.
		_keep_mouse_captured()
		# The runtime freezes its act tick while paused or suspended; the hold and the auto
		# layer keep that same window.
		if not get_tree().paused:
			_hold_act_tick(delta, runtime)
			if not bool(runtime.call("body_swap_pending")):
				_auto_layer_tick(delta, runtime)
	else:
		_mouse_recapture_logged = false
		_restore_seated_q()
		_forget_hold()


## The act key is a deliberate hold, matching the game's 0.35 s bridal-carry hold. The latch is
## dropped between acts and on a body swap, so a key still down from the last act cannot fire.
func _hold_act_tick(delta: float, runtime: Node) -> void:
	if runtime != _hold_runtime:
		_hold_runtime = runtime
		_reset_hold()
	if bool(runtime.call("body_swap_pending")):
		_reset_hold()
		return
	var state := int(runtime.get("state"))
	if state not in [ACT_STATE.State.POSING_IN, ACT_STATE.State.ACTIVE,
			ACT_STATE.State.CLIMAX, ACT_STATE.State.AFTERGLOW]:
		_reset_hold()
		return
	var held: bool = Input.is_action_pressed(ACT_KEYS.ACTION) or bool(_act_for(runtime).vr_y_held())
	if not held:
		_reset_hold()
		_act_hold_ready = true
		return
	if not _act_hold_ready:
		return
	_act_hold += delta
	if _act_hold < HOLD_ACT_SECONDS or _act_hold_fired:
		return
	_act_hold_fired = true
	LOG.debug("hold act key state=%d climaxes=%d" % [
		state, int(runtime.get("pony_climaxes"))])
	if state == ACT_STATE.State.AFTERGLOW:
		_act_for(runtime).end_afterglow()
	elif state == ACT_STATE.State.ACTIVE:
		if int(runtime.get("pony_climaxes")) > 0:
			_act_for(runtime).request_afterglow()
		else:
			_act_for(runtime).cancel()
	elif state == ACT_STATE.State.CLIMAX:
		_act_for(runtime).request_afterglow()
	else:
		_act_for(runtime).cancel()


## Hold X for the auto settings layer. The policy, the rows and the shape write live in
## `readiness/service.gd`; the input service samples the physical keys and the runtime applies
## them through its protocol.
func _auto_layer_tick(delta: float, runtime: Node) -> void:
	var keys: Array[bool] = [
		Input.is_physical_key_pressed(KEY_Q), Input.is_physical_key_pressed(KEY_A),
		Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S),
		Input.is_physical_key_pressed(KEY_E), Input.is_physical_key_pressed(KEY_D),
		Input.is_physical_key_pressed(KEY_Z),
	]
	_act_for(runtime).auto_panel_input(delta, Input.is_physical_key_pressed(KEY_X), keys)


## The act's input handle. The session owns the protocol object; the input service only decodes.
func _act_for(runtime: Node) -> Variant:
	if runtime != _input_runtime:
		_input_runtime = runtime
		var session: Variant = runtime.get("act")
		_act_input = session.input if session != null else null
	return _act_input


func _reset_hold() -> void:
	_act_hold = 0.0
	_act_hold_ready = false
	_act_hold_fired = false


func _forget_hold() -> void:
	_hold_runtime = null
	_input_runtime = null
	_act_input = null
	_reset_hold()


## Recapture the cursor during an act unless a menu panel still owns it. The base game's own
## click-to-recapture is skipped while controls_locked owns the act. menu_panel_open() leaves a
## paused tree or an open panel in charge, so this only fires when the cursor is loose.
func _keep_mouse_captured() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	# A headset session has no usable cursor; grabbing it would only fight the desktop window.
	if _headset():
		return false
	if not DisplayServer.window_is_focused():
		return false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return false
	if WORLD.menu_panel_open():
		return false
	# integration: the act chat owns the cursor while its field has focus.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _mouse_recapture_logged:
		_mouse_recapture_logged = true
		LOG.debug("recaptured mouse during act")
	return true


## The eye is in a headset: the stock game leaves the desktop cursor visible, so act input must not
## require it captured.
func _headset() -> bool:
	return WORLD.headset_view()


func _suppress_seated_q() -> void:
	var body: Variant = WORLD.player
	if not is_instance_valid(body):
		return
	if body.get("seat") != null:
		if not _suppress_q:
			_suppress_q = true
			_old_q = bool(body.get("_q_held"))
		body.set("_q_held", true)


func _restore_seated_q() -> void:
	if not _suppress_q:
		return
	var body: Variant = WORLD.player
	if is_instance_valid(body):
		body.set("_q_held", _old_q)
	_suppress_q = false


func _hold_movement() -> void:
	var body: Variant = WORLD.player
	if not is_instance_valid(body):
		return
	# Keep the camera free but stop walking, jumping, and couch-sleep toggles.
	if not body.has_meta("kiss_hold"):
		body.set_meta("kiss_hold", true)
	Input.action_release("move_jump")
	if "_space_hold" in body:
		body.set("_space_hold", 0.0)
	if "_rest_held" in body:
		body.set("_rest_held", true)


func _input(event: InputEvent) -> void:
	# The debug wheel owns every event while it is open, and a middle press opens it. With debug
	# off the wheel returns false, so the middle button is not consumed.
	var wheel_middle := event is InputEventMouseButton \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE
	if DEBUG_ACTIONS.wheel_open() or wheel_middle:
		if DEBUG_ACTIONS.wheel_input(event):
			get_viewport().set_input_as_handled()
			return
	# While the wheel is open it owns every event, even one it did not consume.
	if DEBUG_ACTIONS.wheel_open():
		return
	if event is InputEventKey:
		var debug_key := event as InputEventKey
		# A debug action may declare a hotkey in DEBUG_ACTIONS.ACTIONS (none do today). Do not claim
		# one in a text field; leave modified keys (Shift+\ is the game's dev noclip) to the game.
		if debug_key.pressed and not debug_key.echo and not debug_key.ctrl_pressed \
				and not debug_key.shift_pressed and not debug_key.alt_pressed:
			var focus := get_viewport().gui_get_focus_owner()
			var action := DEBUG_ACTIONS.hotkey_action(debug_key.physical_keycode)
			if not action.is_empty() and not (focus is LineEdit or focus is TextEdit):
				DEBUG_ACTIONS.run_action(action)
				get_viewport().set_input_as_handled()
				return
	if get_tree().paused:
		return
	# A panel that does not pause the tree (the map, the inventory) keeps its own keys.
	if WORLD.menu_panel_open():
		return
	var runtime: Node = PONIES.active()
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
				and DEBUG_ACTIONS.skeleton_click():
			get_viewport().set_input_as_handled()
			return
		# A click takes the mouse back when a menu left it visible during an act. The base game's
		# own click-to-recapture is skipped while controls_locked owns the act.
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
				and is_instance_valid(runtime) and _keep_mouse_captured():
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and is_instance_valid(runtime):
			# AFTERGLOW keeps only close actions.
			if int(runtime.get("state")) != ACT_STATE.State.AFTERGLOW:
				runtime.call("smack")
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
				and is_instance_valid(runtime):
			_act_for(runtime).auto_thrust_wheel(
				1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(runtime):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and is_instance_valid(runtime):
		_act_motion(runtime, event as InputEventMouseMotion)
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# integration: typed chat text is never an act key.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if is_instance_valid(runtime):
		_act_key(runtime, key, int(runtime.get("state")))
		return
	if key.is_action(ACT_KEYS.ACTION):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _headset():
			return
		if is_instance_valid(offer) and offer.try_start():
			get_viewport().set_input_as_handled()


## Mouse motion while an act is live. Debug free look drives the act camera; otherwise the
## vertical travel is thrust. Auto thrust owns the stroke, so the mouse does nothing while it
## runs. Pause and the menu are already gated above.
func _act_motion(runtime: Node, motion: InputEventMouseMotion) -> void:
	var state := int(runtime.get("state"))
	if state == ACT_STATE.State.IDLE:
		return
	if bool(runtime.call("body_swap_pending")):
		return
	var act_input: Variant = _act_for(runtime)
	if bool(act_input.free_look_active()):
		act_input.look_motion(motion.relative)
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if state in [ACT_STATE.State.ACTIVE, ACT_STATE.State.CLIMAX]:
		if not bool(runtime.call("auto_active")):
			act_input.thrust_motion(motion.relative.y)
		get_viewport().set_input_as_handled()


## Route one key press while an act is live. The act's own keys act here; with the shield on,
## every other key is taken from the game and from other mods (`docs/input.md`).
func _act_key(runtime: Node, key: InputEventKey, state: int) -> void:
	# integration: optional anatomy actions, only when their act is live. The runtime checks the
	# pose's control profile and the live edge lock; the key is consumed whether or not it allows.
	if key.physical_keycode == KEY_V and bool(runtime.call("anatomy_hole_ready")):
		_act_for(runtime).command(ACT_COMMANDS.HOLE)
		_consume(key)
		return
	if key.physical_keycode == KEY_N and bool(runtime.call("anatomy_oral_ready")):
		_act_for(runtime).command(ACT_COMMANDS.ORAL)
		_consume(key)
		return
	# Enter opens the act chat and then hands the keyboard to the text field.
	if key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and bool(WORLD.open_act_chat()):
		get_viewport().set_input_as_handled()
		return
	# X is consumed in every act state: AnonPony uses X to lie down, and the runtime polls it
	# for the tap toggle and the hold-X auto settings layer. Consume it here and do not act.
	if key.physical_keycode == KEY_X:
		_consume(key)
		return
	# G is the keyboard smack. RMB does the same; the act owns both.
	if key.physical_keycode == KEY_G:
		# AFTERGLOW keeps only close actions.
		if state != ACT_STATE.State.AFTERGLOW:
			runtime.call("smack")
		_consume(key)
		return
	# Space must not jump or start a couch sleep while the act holds the player.
	if key.is_action("move_jump") or key.physical_keycode == KEY_SPACE:
		_consume(key)
		return
	# H is the game's hug/deep-kiss key. Keep it consumed for the whole act even though the
	# mod no longer binds it, or a hug release can end the act's base kiss.
	if key.physical_keycode == KEY_H:
		_consume(key)
		return
	# AFTERGLOW: the act key, lean, caress and the standing kiss are live.
	if state == ACT_STATE.State.AFTERGLOW:
		if key.is_action(ACT_KEYS.ACTION) or key.is_action("stand_up") \
				or key.physical_keycode in [
					KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_T, KEY_Z, KEY_C]:
			_consume(key)
		elif _shield:
			_consume(key)
		return
	# CLIMAX / RESTORE: only the polled act actions.
	if state in [ACT_STATE.State.CLIMAX, ACT_STATE.State.RESTORE]:
		if key.is_action(ACT_KEYS.ACTION) or key.is_action("stand_up") \
				or key.physical_keycode in [
					KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_Z, KEY_C]:
			_consume(key)
		elif _shield:
			_consume(key)
		return
	if key.is_action("stand_up"):
		_consume(key)
		return
	if key.is_action(ACT_KEYS.ACTION):
		_consume(key)
		return
	# Keep native world interactions from firing during the act. With the shield on every other
	# key belongs to the act alone; Z/C are the per-side caress-motion toggles and would
	# otherwise sit/lie or interact.
	if _shield:
		_consume(key)
	elif key.physical_keycode in [KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_G, KEY_K, KEY_Z, KEY_C]:
		get_viewport().set_input_as_handled()


## Take one key from the game and from other mods. `PASS_KEYS` stay live while the shield is on;
## the act's own polled keys are consumed but keep their state (see `RAW_KEYS`).
func _consume(key: InputEventKey) -> void:
	if _shield and key.physical_keycode in PASS_KEYS:
		return
	get_viewport().set_input_as_handled()
	if not _shield:
		return
	if key.is_action(ACT_KEYS.ACTION) or key.physical_keycode in RAW_KEYS:
		return
	_suppress_raw(key)


## HACK: feed Input a matching release so a mod that samples the raw key state in
## `_physics_process` (Pegasus Ride, the bundled Dance Mod) reads the key as up. `set_input_as_handled`
## cannot reach those pollers. The flush drains this release before the next physics step, and the
## player's own release restores the real state.
func _suppress_raw(key: InputEventKey) -> void:
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	release.echo = false
	Input.parse_input_event(release)

