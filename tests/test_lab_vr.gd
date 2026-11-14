extends "res://mods/unfplap/tests/test_lab.gd"
## Unfplap VR lab: the normal manual lab plus a fake waist tracker, so the standing VR act can be
## driven without body-tracking hardware. Run with ./lab-vr.sh; Monado's qwerty driver supplies the
## HMD and both hand controllers.
##
## Extra hotkeys (the mouse must be captured, like the desktop lab):
##   [ / ]   move the fake waist 5 mm toward the mare / back toward Anon
##   ;       toggle the fake waist auto stroke (1.1 Hz between 0 and the vr_act hip range)
##   F9      put Anon just behind the aimed (or nearest) adult test mare and face her
##
## The tracker is an XRPositionalTracker named `waist`. vr_act._tracked_hips() accepts a positional
## tracker named for the waist, so vr_depth() runs the same path a body-tracked waist would. On a
## desktop run the tracker is inert and nothing else changes: the rig is only XR under Monado.

const VR_ACT := preload("res://mods/unfplap/vr/service.gd")

## One full stroke of the fake waist, the same range vr_act maps to depth 1.
const HIP_RANGE_M := VR_ACT.HIP_RANGE_M
const NUDGE_M := 0.005
const AUTO_HZ := 1.1
const LOG_SECONDS := 1.0

var _waist: XRPositionalTracker
## Tracker pose in play-space (XROrigin3D) coordinates. Only the origin moves.
var _pose := Transform3D.IDENTITY
## Play-space point the fake waist starts a stroke from; latched at each act start.
var _base := Vector3.ZERO
var _depth_m := 0.0
var _auto := false
var _auto_time := 0.0
var _seen_runtime: Node = null
var _log_clock := 0.0
var _seen_state := -1
## The runtime's state names, in enum order: IDLE, POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE.
const STATE_NAMES := ["IDLE", "POSING_IN", "ACTIVE", "CLIMAX", "AFTERGLOW", "RESTORE"]
var _origin_cache: XROrigin3D
## Automated smoke run: `--vr-lab-autostart` qualifies the nearest mare, starts the standing act
## and turns the fake waist stroke on, so a scripted session can prove the whole path end to end.
var _autostart := false
var _autostart_clock := 0.0
var _autostart_done := false
## Set when the smoke run starts the act; the new-runtime branch turns the stroke on after it
## latches the base, because latching resets the stroke.
var _autostart_stroke := false


func _ready() -> void:
	super()
	_autostart = "--vr-lab-autostart" in OS.get_cmdline_user_args()
	_waist = XRPositionalTracker.new()
	_waist.name = "waist"
	_waist.type = XRServer.TRACKER_ANY
	XRServer.add_tracker(_waist)
	print("[unfplap vr] fake waist tracker installed: [ / ] waist, ; auto stroke, F9 stand behind the mare")
	print("[unfplap vr] the Monado window owns the keyboard: pose the headset there, then keep the game focused for these keys")


## The lab's own input runs first for its keys; ours are unclaimed by the game or the lab.
func _input(event: InputEvent) -> void:
	if _vr_key(event):
		get_viewport().set_input_as_handled()
		return
	super(event)


func _vr_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.alt_pressed or key.ctrl_pressed:
		return false
	match key.physical_keycode:
		KEY_BRACKETLEFT:
			_nudge(-NUDGE_M)
		KEY_BRACKETRIGHT:
			_nudge(NUDGE_M)
		KEY_SEMICOLON:
			_toggle_auto()
		KEY_F9:
			_stand_behind_target()
		_:
			return false
	return true


## A body tracker's hips move with the play space, so the fake waist is a play-space offset too.
## The tracker is only driven while an act runs; the base is re-latched on every act so the first
## vr_act tick always sees the hips at their start point.
func _physics_process(delta: float) -> void:
	var runtime := _runtime()
	if runtime != _seen_runtime:
		_seen_runtime = runtime
		_base = _pose.origin
		_depth_m = 0.0
		_auto = _autostart_stroke
		_autostart_stroke = false
		_auto_time = 0.0
		_seen_state = -1
		if is_instance_valid(runtime):
			print("[unfplap vr] waist base latched for the new act at %s; trackers: %s" % [
				str(_base), _tracker_names()])
	if not is_instance_valid(runtime):
		_depth_m = 0.0
	elif _auto:
		_auto_time += delta
		_depth_m = HIP_RANGE_M * (0.5 - 0.5 * cos(TAU * AUTO_HZ * _auto_time))
	_push_pose()
	_log_tick(delta)
	_autostart_tick(delta)


## After the lab has placed the ponies, walk the smoke run through qualify → start → stroke.
func _autostart_tick(delta: float) -> void:
	if not _autostart or _autostart_done:
		return
	if not _done or not is_inside_tree():
		return
	_autostart_clock += delta
	if _autostart_clock < 4.0:
		return
	_autostart_done = true
	_autostart_run.call_deferred()


func _autostart_run() -> void:
	var main := _main()
	if main == null:
		print("[unfplap vr] autostart: no unfplap entry node")
		return
	var pony: Node3D = _stand_behind_target()
	DisplayServer.window_move_to_foreground()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	if is_instance_valid(pony):
		_qualify(pony)
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var started: bool = main.call("try_start")
	print("[unfplap vr] autostart: standing act started=%s" % str(started))
	if started:
		# The runtime appears on the next tick, which latches the base and resets the stroke.
		_autostart_stroke = true


func _nudge(metres: float) -> void:
	if not is_instance_valid(_runtime()):
		print("[unfplap vr] waist nudge ignored: no act is running")
		return
	_auto = false
	_depth_m = clampf(_depth_m + metres, 0.0, HIP_RANGE_M)
	print("[unfplap vr] waist %.0f mm (depth %.0f%%)" % [_depth_m * 1000.0, _depth_m / HIP_RANGE_M * 100.0])


func _toggle_auto() -> void:
	_auto = not _auto
	_auto_time = 0.0
	if not _auto:
		_depth_m = 0.0
	print("[unfplap vr] waist auto stroke %s" % ("on" if _auto else "off"))


## Push the fake waist pose into the tracking space every tick, along her forward axis.
func _push_pose() -> void:
	if _waist == null:
		return
	var origin := _origin()
	if origin == null:
		return
	var forward: Vector3 = _forward()
	var local_forward: Vector3 = origin.global_basis.inverse() * forward
	_pose.origin = _base + local_forward * _depth_m
	_waist.set_pose(&"default", _pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


## vr_forward() knows about the anatomy hole and her facing; the fallback matches it.
func _forward() -> Vector3:
	var runtime := _runtime()
	if is_instance_valid(runtime) and runtime.has_method("vr_forward"):
		var forward: Variant = runtime.call("vr_forward")
		if forward is Vector3 and (forward as Vector3).length_squared() > 0.0001:
			return forward
	var pony := _pony()
	if is_instance_valid(pony):
		return -(pony as Node3D).global_basis.z.normalized()
	return Vector3.FORWARD


func _log_tick(delta: float) -> void:
	_log_clock += delta
	if _log_clock < LOG_SECONDS:
		return
	_log_clock = 0.0
	var runtime := _runtime()
	if not is_instance_valid(runtime):
		_seen_state = -1
		return
	var state := int(runtime.get("state"))
	var state_name: String = STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else str(state)
	if state != _seen_state:
		_seen_state = state
		print("[unfplap vr] state=%s thrusts=%d readiness=%d" % [
			state_name, int(runtime._readiness.act_thrusts), int(runtime.get("satisfaction"))])
	var wants: Variant = runtime.get("_preferences")
	var wanted_intensity := str((wants as Dictionary).get("intensity", "")) if wants is Dictionary else ""
	var wanted_pattern := str((wants as Dictionary).get("pattern", "")) if wants is Dictionary else ""
	print("[unfplap vr] waist depth=%.0f%% auto=%s state=%s thrusts=%d readiness=%d wants=%s/%s you=%s/%s" % [
		_depth_m / HIP_RANGE_M * 100.0, str(_auto), state_name,
		int(runtime._readiness.act_thrusts), int(runtime.get("satisfaction")),
		wanted_intensity, wanted_pattern,
		str(runtime._readiness.last_intensity), str(runtime._readiness.last_pattern)])


## F9: the offer cone needs Anon on the ground behind her rump, and XR locomotion is stick-only
## (qwerty's simple controller has no stick), so place him instead of walking.
func _stand_behind_target() -> Node3D:
	var pony := _target_under_aim()
	if not is_instance_valid(pony):
		var nearest := _nearest_adult_to_player()
		if is_instance_valid(nearest):
			pony = nearest
	if not is_instance_valid(pony):
		print("[unfplap vr] F9: no adult test mare to stand behind")
		return null
	var back := (pony as Node3D).global_basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		print("[unfplap vr] F9: %s has no usable facing" % _pony_id(pony))
		return null
	# The offer cone measures from her rump anchor to the eye and is 1.2 m wide, so sit inside it
	# with room to spare instead of the 0.9 m that a body origin would need.
	var anchor: Vector3 = (pony as Node3D).global_position
	var runtime: Node = (pony as Node).get_node_or_null("UnfplapRuntime")
	if runtime != null and runtime.has_method("rump_anchor"):
		var reported: Variant = runtime.call("rump_anchor")
		if reported is Vector3 and (reported as Vector3).is_finite():
			anchor = reported
	var spot: Vector3 = anchor + back.normalized() * 0.8
	# The rump anchor sits above her hooves; Anon's feet stay on her floor.
	spot.y = (pony as Node3D).global_position.y
	var body: Variant = game.get("player")
	if not is_instance_valid(body):
		print("[unfplap vr] F9: no player rig")
		return null
	# The cone measures from her rump to the eye, and the headset sits wherever the HMD pose is
	# relative to the XR origin, so move the whole rig by the eye's error, not the rig origin's.
	var camera := _camera()
	var shift := Vector3.ZERO
	if camera != null:
		shift = spot - camera.global_position
		shift.y = 0.0
	# The XR rig's root stays at the spawn anchor; its Body child is the part that moves.
	var rig: Node3D = (body as Node3D)
	var body_node: Node = (body as Node).get_node_or_null("Body")
	if body_node is Node3D:
		rig = body_node
	var target := rig.global_position + shift
	if rig.has_method("teleport"):
		rig.call("teleport", target)
	else:
		rig.global_position = target
		rig.reset_physics_interpolation()
	_face_point((pony as Node3D).global_position)
	print("[unfplap vr] F9: Anon behind %s at %s; press the act key (O) for the standing act" % [
		_pony_id(pony), str(target)])
	return pony as Node3D


## Turn the play space about the eye, exactly like the XR body's snap turn, so the shot faces her
## without moving the body or the headset.
func _face_point(point: Vector3) -> void:
	var camera := _camera()
	var origin := _origin()
	if camera == null or origin == null:
		return
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	var to: Vector3 = point - camera.global_position
	to.y = 0.0
	if forward.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return
	var turn: Basis = Basis(Vector3.UP, forward.normalized().signed_angle_to(to.normalized(), Vector3.UP))
	var pivot: Vector3 = origin.to_local(camera.global_position)
	var around := Transform3D(Basis(), pivot) * Transform3D(turn, Vector3.ZERO) * Transform3D(Basis(), -pivot)
	origin.transform = origin.transform * around


## Make a chosen test mare sex-ready the same way the lab's Mouse5 does. F9/autostart cannot rely
## on the crosshair (a headset session has no captured cursor), so the target is passed in.
func _qualify(pony: Node3D) -> void:
	var rows := PackedStringArray()
	rows.append("idle=" + _make_idle(pony, true))
	rows.append("cleared=" + _clear_busy(pony))
	rows.append("record=" + _set_dating_record(pony))
	rows.append("mood=" + _set_mood(pony, "neutral"))
	_log_action("VR qualify " + _pony_id(pony), rows)


func _nearest_adult_to_player() -> Node3D:
	var body: Variant = game.get("player")
	if not is_instance_valid(body):
		return null
	var best: Node3D = null
	var best_distance := INF
	for node: Variant in _adult_test_ponies():
		var pony: Node3D = node as Node3D
		if not is_instance_valid(pony):
			continue
		var distance := pony.global_position.distance_to((body as Node3D).global_position)
		if distance < best_distance:
			best = pony
			best_distance = distance
	return best


func _main() -> Node:
	var mods := get_node_or_null("/root/Mods")
	return mods.get_node_or_null("unfplap") if mods != null else null


func _runtime() -> Node:
	var main := _main()
	var runtime: Variant = main.get("active_runtime") if main != null else null
	return runtime if is_instance_valid(runtime) else null


func _pony() -> Node3D:
	var runtime := _runtime()
	var pony: Variant = runtime.get("pony") if is_instance_valid(runtime) else null
	return pony if is_instance_valid(pony) else null


## Every tracker the runtime can see, so the log proves the fake waist reached XRServer.
func _tracker_names() -> String:
	var names := PackedStringArray()
	for key: Variant in XRServer.get_trackers(XRServer.TRACKER_ANY):
		names.append(str(key))
	return ", ".join(names)


func _origin() -> XROrigin3D:
	if is_instance_valid(_origin_cache):
		return _origin_cache
	var body: Variant = game.get("player") if is_instance_valid(game) else null
	if not is_instance_valid(body):
		return null
	var found: Array = (body as Node).find_children("*", "XROrigin3D", true, false)
	if found.is_empty():
		return null
	_origin_cache = found[0] as XROrigin3D
	return _origin_cache


func _camera() -> Camera3D:
	# The game's own eye camera: the XR rig also carries a disabled cinematic-view camera, so a
	# plain find can return the wrong one and the eye offset then throws the teleport anywhere.
	var main := _main()
	if main != null and main.has_method("camera"):
		var view: Variant = main.call("camera")
		if is_instance_valid(view) and view is Camera3D:
			return view
	var body: Variant = game.get("player") if is_instance_valid(game) else null
	if not is_instance_valid(body):
		return null
	for node: Variant in (body as Node).find_children("*", "XRCamera3D", true, false):
		if node is Camera3D and (node as Camera3D).current:
			return node
	return null
