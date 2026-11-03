extends Node
## Input and the seated-player Q guard. Runs in _input before desktop_player._unhandled_input.
## While an act is active it consumes the act keys and the interaction keys, and keeps the
## game's own stand_up poll from force-standing a seated player.

var main: Node

var _suppress_q := false
var _old_q := false


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
	else:
		_restore_seated_q()
	if int(main.get("pending_unlock")) >= 0 and not bool(main.call("menu_open")):
		if is_instance_valid(main.get("player")):
			var body: Node = main.get("player")
			body.set("controls_locked", int(main.get("pending_unlock")) == 1)
		main.set("pending_unlock", -1)


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
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_D \
				and debug_key.ctrl_pressed and debug_key.shift_pressed:
			main.call("toggle_debug_logs")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_V \
				and debug_key.ctrl_pressed and debug_key.shift_pressed \
				and bool(main.get("debug_logs")):
			main.call("debug_voices")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_F7 \
				and bool(main.get("debug_logs")):
			main.call("debug_request")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_F8 \
				and bool(main.get("debug_logs")):
			main.call("_debug_offer")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_F9 \
				and bool(main.get("debug_logs")):
			main.call("debug_pose1_float")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.physical_keycode == KEY_F10 \
				and bool(main.get("debug_logs")):
			main.call("toggle_skeleton_debug")
			get_viewport().set_input_as_handled()
			return
		if debug_key.pressed and not debug_key.echo and debug_key.alt_pressed \
				and debug_key.physical_keycode in [KEY_7, KEY_8] \
				and bool(main.get("debug_logs")):
			main.call("debug_chin", 5.0 if debug_key.physical_keycode == KEY_7 else -5.0)
			get_viewport().set_input_as_handled()
			return
	if get_tree().paused:
		return
	var runtime: Variant = main.get("active_runtime")
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
				and bool(main.get("debug_logs")) and bool(main.call("skeleton_click")):
			get_viewport().set_input_as_handled()
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and is_instance_valid(runtime):
			runtime.call("smack")
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
	if is_instance_valid(runtime):
		var state := int(runtime.get("state"))
		# Space must not jump or start a couch sleep while the act holds the player.
		if key.is_action("move_jump") or key.physical_keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_H:
			runtime.call("toggle_lean_return")
			get_viewport().set_input_as_handled()
			return
		if state == 4: # AFTERGLOW
			if key.is_action("stand_up") or key.physical_keycode in [KEY_Y, KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F]:
				get_viewport().set_input_as_handled()
			return
		if state in [3, 5]: # CLIMAX / RESTORE: only polled act actions
			if key.is_action("stand_up") or key.physical_keycode in [KEY_Y, KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F]:
				get_viewport().set_input_as_handled()
			return
		if key.is_action("stand_up"):
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_Y:
			get_viewport().set_input_as_handled()
			return
		# Keep native world interactions from firing during the act.
		if key.physical_keycode in [KEY_Q, KEY_E, KEY_A, KEY_D, KEY_F, KEY_G, KEY_K]:
			get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_Y:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if bool(main.call("try_start")):
			get_viewport().set_input_as_handled()
