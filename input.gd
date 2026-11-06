extends Node
## Input and the seated-player Q guard. Runs in _input before desktop_player._unhandled_input.
## While an act is active it consumes the act keys and the interaction keys, and keeps the
## game's own stand_up poll from force-standing a seated player.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")

var main: Node

var _suppress_q := false
var _old_q := false
## One recapture log per act. The cursor can take more than one physics tick to report captured.
var _mouse_recapture_logged := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(main):
		return
	var runtime: Variant = main.get("active_runtime")
	if is_instance_valid(runtime):
		# Pause/settings must not end the act; the runtime simply stops processing while the
		# tree is paused and resumes when the menu closes.
		_suppress_seated_q()
		_hold_movement()
		# A menu, map, inventory or alt-tab that leaves the cursor visible must not keep the
		# act's mouse input dead. The base game's own click-to-recapture is skipped while
		# controls_locked owns the act, so the mod keeps the mouse captured itself.
		_keep_mouse_captured()
	else:
		_mouse_recapture_logged = false
		_restore_seated_q()


## Recapture the cursor during an act unless a menu panel still owns it. The base game's own
## click-to-recapture is skipped while controls_locked owns the act. menu_panel_open() leaves a
## paused tree or an open panel in charge, so this only fires when the cursor is loose.
func _keep_mouse_captured() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not DisplayServer.window_is_focused():
		return false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return false
	if main.has_method("menu_panel_open") and bool(main.call("menu_panel_open")):
		return false
	# integration: the act chat owns the cursor while its field has focus.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _mouse_recapture_logged and main.has_method("debug"):
		_mouse_recapture_logged = true
		main.call("debug", "recaptured mouse during act")
	return true


func _suppress_seated_q() -> void:
	var body: Variant = main.get("player")
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
	var body: Variant = main.get("player")
	if is_instance_valid(body):
		body.set("_q_held", _old_q)
	_suppress_q = false


func _hold_movement() -> void:
	var body: Variant = main.get("player")
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
	if not is_instance_valid(main):
		return
	if event is InputEventKey:
		var debug_key := event as InputEventKey
		# Debug actions declare their own hotkey in TUNABLES.ACTIONS. Do not claim one in a text
		# field; leave modified keys (Shift+\ is the game's dev noclip) to the game.
		if debug_key.pressed and not debug_key.echo and not debug_key.ctrl_pressed \
				and not debug_key.shift_pressed and not debug_key.alt_pressed:
			var focus := get_viewport().gui_get_focus_owner()
			var action := TUNABLES.hotkey_action(debug_key.physical_keycode)
			if not action.is_empty() and not (focus is LineEdit or focus is TextEdit):
				TUNABLES.run_action(action, main)
				get_viewport().set_input_as_handled()
				return
	if get_tree().paused:
		return
	var runtime: Variant = main.get("active_runtime")
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
				and bool(main.call("skeleton_click")):
			get_viewport().set_input_as_handled()
			return
		# A click takes the mouse back when a menu left it visible during an act. The base game's
		# own click-to-recapture is skipped while controls_locked owns the act.
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
				and is_instance_valid(runtime) and _keep_mouse_captured():
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and is_instance_valid(runtime):
			if int(runtime.get("state")) != 4: # AFTERGLOW keeps only close actions
				runtime.call("smack")
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
				and is_instance_valid(runtime):
			runtime.call("auto_thrust_wheel",
				1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(runtime):
			get_viewport().set_input_as_handled()
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
		# integration: optional anatomy actions, only when their act is live.
		if key.physical_keycode == KEY_V and bool(runtime.call("anatomy_hole_ready")):
			runtime.call("toggle_anatomy_hole")
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_N and bool(runtime.call("anatomy_oral_ready")):
			runtime.call("toggle_anatomy_oral")
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_B and bool(runtime.call("anatomy_finish_ready")):
			runtime.call("toggle_anatomy_finish")
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] \
				and TUNABLES.get_bool("features.act_chat") and bool(main.call("open_act_chat")):
			get_viewport().set_input_as_handled()
			return
		var state := int(runtime.get("state"))
		# X toggles auto thrust. Consume it in every act state: AnonPony uses X to lie down,
		# and that must not fire while the act owns the body.
		if key.physical_keycode == KEY_X:
			if state in [2, 3]: # ACTIVE / CLIMAX
				runtime.call("toggle_auto_thrust")
			get_viewport().set_input_as_handled()
			return
		# Space must not jump or start a couch sleep while the act holds the player.
		if key.is_action("move_jump") or key.physical_keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			return
		# H is the game's hug/deep-kiss key. Keep it consumed for the whole act even though the
		# mod no longer binds it, or a hug release can end the act's base kiss.
		if key.physical_keycode == KEY_H:
			get_viewport().set_input_as_handled()
			return
		if state == 4: # AFTERGLOW: only Y / lean / caress / kiss are live
			if key.is_action("stand_up") or key.physical_keycode in [
					KEY_Y, KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_T, KEY_Z, KEY_C]:
				get_viewport().set_input_as_handled()
			return
		if state in [3, 5]: # CLIMAX / RESTORE: only polled act actions
			if key.is_action("stand_up") or key.physical_keycode in [
					KEY_Y, KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_Z, KEY_C]:
				get_viewport().set_input_as_handled()
			return
		if key.is_action("stand_up"):
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_Y:
			get_viewport().set_input_as_handled()
			return
		# Keep native world interactions from firing during the act. Z/C are the per-side
		# caress-motion toggles and would otherwise sit/lie or interact.
		if key.physical_keycode in [KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_G, KEY_K, KEY_Z, KEY_C]:
			get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_Y:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if bool(main.call("try_start")):
			get_viewport().set_input_as_handled()
