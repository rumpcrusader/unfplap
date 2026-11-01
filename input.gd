extends Node
## Input and the seated-player Q guard. Runs in _input before desktop_player._unhandled_input.
## While an act is active it consumes F/Q/L and the interaction keys, and keeps the game's own
## stand_up poll from force-standing a seated player.

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
		# Pose-1 debug head roll (Alt+1/2) and camera rotation (Alt+7/8/9/0/-/+).
		if debug_key.pressed and not debug_key.echo and debug_key.alt_pressed:
			var active: Variant = main.get("active_runtime")
			if is_instance_valid(active):
				if debug_key.physical_keycode == KEY_1:
					active.call("debug_roll_pose1_head", 1.0)
					get_viewport().set_input_as_handled()
					return
				if debug_key.physical_keycode == KEY_2:
					active.call("debug_roll_pose1_head", -1.0)
					get_viewport().set_input_as_handled()
					return
			var axis := -1
			match debug_key.physical_keycode:
				KEY_7: axis = 0
				KEY_8: axis = 1
				KEY_9: axis = 2
				KEY_0: axis = 3
				KEY_MINUS: axis = 4
				KEY_EQUAL, KEY_PLUS: axis = 5
			if axis >= 0:
				if is_instance_valid(active):
					active.call("debug_rotate_pose1", axis)
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
	if get_tree().paused:
		return
	var runtime: Variant = main.get("active_runtime")
	if event is InputEventMouseButton:
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
		if state == 4: # AFTERGLOW
			if key.is_action("stand_up"):
				runtime.call("end_afterglow")
			if key.is_action("stand_up") or key.physical_keycode in [KEY_F, KEY_L]:
				get_viewport().set_input_as_handled()
			return
		if state in [3, 5, 6]: # CLIMAX / WITHDRAW / RESTORE: no controls
			if key.is_action("stand_up") or key.physical_keycode in [KEY_F, KEY_L]:
				get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_F:
			runtime.call("pump")
			get_viewport().set_input_as_handled()
			return
		if key.is_action("stand_up"):
			runtime.call("cancel")
			get_viewport().set_input_as_handled()
			return
		# Keep native world interactions from firing during the act.
		if key.physical_keycode in [KEY_E, KEY_G, KEY_K, KEY_H]:
			get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_L:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if bool(main.call("try_start")):
			get_viewport().set_input_as_handled()
