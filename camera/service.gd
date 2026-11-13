extends RefCounted
## The act camera session: the lean input and its smoothing, the speed-driven thrust camera, the
## debug free look, the free-camera lock, the standing eye override, the captured player look and
## the shot geometry helpers. The two pose cameras (`camera/missionary_camera.gd`, `camera/standing_camera.gd`)
## stay the shot implementations; this facade owns the session around them.
## Contract: docs/camera.md.

const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

## The thrust camera: both channels are velocity-driven metres with one critically damped
## response, so the shot eases through the stroke instead of being kicked at its close.
const CAM_SURGE_M := 0.06
const CAM_BOB_M := 0.02
const CAM_SPEED_REF := 4.0
const CAM_RESPONSE_S := 0.12
const CAM_BACK_RATIO := 0.5
const CAM_CLIMAX_SURGE_M := 0.02
const CAM_CLIMAX_BOB_M := 0.008
const CAM_CLIMAX_BOBS := 2.0
const CAMERA_INERTIA_SMOOTH := 5.0
## The shot keeps a released position; the lean only rides the current target.
const AFTERGLOW_BACK_SPEED := 0.16
const RESTORE_BACK_SPEED := 0.6
## Idle breathing: one slow forward rock added on top of the displayed lean.
const HOLD_SWAY_HZ := 0.80
## Anon's spine length used by the standing torso hinge.
const ANON_TORSO_LEN_M := 0.65

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

## The typed act view. Presentation modules read it; the camera writes its live values here only
## through `runtime._sync_act_facts()`.
var facts: Variant = null
## The controllers the camera drives and asks. The runtime binds them on every service call.
var hands: Variant = null
var kiss: Variant = null
var standing_camera: Variant = null
var missionary_camera: Variant = null

## Act-session ownership. Each flag marks external state this act took and must give back.
var camera_owned := false
var look_captured := false
## Standing leaves Anon facing where the act left him; only missionary snaps the pre-act
## yaw/pitch back.
var look_restore_yaw := true
var camera: Camera3D = null
var free_camera_active := false
var camera_basis_ready := false
var restore_yaw := 0.0
var restore_pitch := 0.0
var controls_locked_saved := false
var controls_locked_by_camera := false

## The lean. `lean_forward`/`lean_side` are the input target; `lean_view_*` the smoothed view and
## `lean_sway` the idle-breathing offset the shot adds on top (never folded into the view).
var lean_forward := 0.0
var lean_side := 0.0
var lean_view_forward := 0.0
var lean_view_side := 0.0
var lean_sway := 0.0
## One-shot per act: the lean input was blocked, and why.
var lean_block_logged := false
var side_return_armed := false
var hold_rock_clock := 0.0
var lean_action_active := false
var lean_action_side := 0.0
var lean_action_kind := ""

## The shot's smoothing state and the afterglow back-off.
var bob := 0.0
var bob_velocity := 0.0
var lean := 0.0
var lean_velocity := 0.0
var back := 0.0
var back_target := 0.0
var camera_surge := 0.0
var camera_bob := 0.0

## The player look the act captured and the live view it applies.
var look_yaw := 0.0
var look_pitch := 0.0

## The standing eye override: the act raises or lowers the player's own eye height while it runs.
var eye_override := false
var saved_stand_eye := 0.0
var saved_eye_height := 0.0
var camera_target_eye := 0.0

## Debug free look: the player camera replaces the act shot and the mouse looks instead of
## thrusting. The rotation is held from the act's starting view.
var free_look_yaw := 0.0
var free_look_pitch := 0.0
var free_look_was := false


## Bind the typed act view and the controllers the camera drives. The runtime refreshes these on
## every service call, so a suite can build a runtime without entering the tree.
func bind(facts_context: Variant, hands_ctl: Variant, kiss_ctl: Variant,
		standing_ctl: Variant, missionary_ctl: Variant) -> void:
	facts = facts_context
	hands = hands_ctl
	kiss = kiss_ctl
	standing_camera = standing_ctl
	missionary_camera = missionary_ctl


## Take the act's camera tuning from the runtime's settings snapshot.
func configure(camera_block: Dictionary) -> void:
	camera_surge = float(camera_block.get("surge", 1.0))
	camera_bob = float(camera_block.get("bob", 0.35))


## A fresh act: the previous session is dropped and the shot starts from rest. The runtime captures
## the player look and creates the act's Anon body around this call.
func begin_session(pose: String) -> void:
	camera_owned = false
	look_captured = false
	look_restore_yaw = pose != CATALOG.STANDING
	camera = null
	free_camera_active = false
	camera_basis_ready = false
	reset_shot()


## Open the shot before the first camera frame. AnonPony and headset/VR keep the stock camera and
## return before `begin_free()`.
func open_shot() -> void:
	camera_owned = true
	camera_basis_ready = false
	free_camera_active = false
	reset_lean_state()


## Take the desktop free shot: the player camera owns the view from here.
func begin_free() -> void:
	free_camera_active = true
	camera = main_camera()


## Release the shot's own state at act end. The runtime runs the cross-system releases around it
## in the same order they were built.
func close_shot() -> void:
	camera_basis_ready = false
	camera = null
	reset_shot()


## Reset the smoothed shot and the afterglow back-off.
func reset_shot() -> void:
	bob = 0.0
	bob_velocity = 0.0
	lean = 0.0
	lean_velocity = 0.0
	back = 0.0
	back_target = 0.0


## The restore released the back-off; the shot eases the last offset out instead of snapping.
func release_back() -> void:
	back_target = 0.0


## Lean/caress remain live through the afterglow in both poses. Missionary keeps its passive
## afterglow otherwise: no kiss, reach or close window.
func at_actions_allowed() -> bool:
	return int(facts.state) in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]


## Q/E drive the side lean; W/S lean forward/back. Q/E add a forward-plus-side diagonal and also
## fire a pose reaction once the smoothed side lean crosses MOTION.LEAN_FIRE. `auto_open` is the
## hold-X auto settings layer, which freezes the shot exactly where it is.
func tick_lean(delta: float, paused: bool, auto_open: bool) -> void:
	if hands != null:
		hands.call("return_tick")
	if not at_actions_allowed():
		lean_idle(delta)
		return
	if not free_camera_active or bool(facts.player_pony) or bool(facts.headset_view) \
			or paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not lean_block_logged and int(facts.state) in [STATE_ACTIVE, STATE_CLIMAX]:
			lean_block_logged = true
			write_log("lean blocked: free=%s pony=%s headset=%s paused=%s mouse=%d" % [
				str(free_camera_active), str(facts.player_pony), str(facts.headset_view),
				str(paused), Input.mouse_mode])
		lean_idle(delta)
		return
	if auto_open:
		# Hold-X auto settings: hold the shot exactly where it is. Do not write `lean_view_*`
		# here: the idle sway leaves it ahead of `lean_forward`, so copying the base value in
		# snapped the camera by about a sway step. Freezing both values leaves nothing to jump.
		side_return_armed = false
		end_lean_action()
		if kiss != null:
			kiss.call("lean_kiss_tick")
		var frozen_caress := Time.get_ticks_usec()
		if hands != null:
			hands.call("tick", delta)
		if facts != null:
			facts.perf("caress_tick", Time.get_ticks_usec() - frozen_caress)
		apply_standing_lean_look()
		return
	var side := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		side -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		side += 1.0
	var forward := 0.0
	if Input.is_action_pressed("move_forward"):
		forward -= 1.0
	if Input.is_action_pressed("move_back"):
		forward += 1.0
	var targets := MOTION.lean_targets(side, forward)
	if targets.y != 0.0:
		side_return_armed = false
	elif targets.x < 0.0:
		# Pulling back also recentres the shoulder roll instead of leaving it locked until a
		# lean to the other side.
		side_return_armed = true
	lean_forward = MOTION.lean_step(lean_forward, targets.x, delta)
	lean_side = MOTION.lean_step(lean_side, targets.y, delta, side_return_armed)
	if side_return_armed and is_zero_approx(targets.y) and absf(lean_side) <= 0.001:
		side_return_armed = false
	var alpha := 1.0 - exp(-CAMERA_INERTIA_SMOOTH * delta)
	lean_view_forward = lerpf(lean_view_forward, lean_forward, alpha)
	lean_view_side = lerpf(lean_view_side, lean_side, alpha)
	# Idle breathing is a true offset on top of the displayed lean. Adding it into
	# `lean_view_forward` itself let the smoother amplify it (a forced offset of
	# HOLD_SWAY_FORWARD / (1 - exp(-CAMERA_INERTIA_SMOOTH * delta)), about twelve times the
	# intended amount) so the shot crept when nobody was leaning.
	lean_sway = 0.0
	lean_block_logged = false
	if feature("idle_camera_sway"):
		hold_rock_clock += delta
		lean_sway = sin(hold_rock_clock * HOLD_SWAY_HZ) * MOTION.HOLD_SWAY_FORWARD
	tick_lean_action()
	# Missionary afterglow keeps lean and caress live but not the kiss; standing afterglow keeps
	# its kiss. `_afterglow_begin()` releases a missionary kiss when the state changes.
	if str(facts.pose_id) == CATALOG.STANDING or int(facts.state) != STATE_AFTERGLOW:
		if kiss != null:
			kiss.call("lean_kiss_tick")
	var caress_started := Time.get_ticks_usec()
	if hands != null:
		hands.call("tick", delta)
	if facts != null:
		facts.perf("caress_tick", Time.get_ticks_usec() - caress_started)
	apply_standing_lean_look()


## No input this frame: drop the hands, release the pose action and return the lean to rest.
func lean_idle(delta: float) -> void:
	if hands != null:
		hands.call("stop_inputs")
	end_lean_action()
	lean_forward = move_toward(lean_forward, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
	lean_side = move_toward(lean_side, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
	lean_view_forward = lean_forward
	lean_view_side = lean_side


## One step of the thrust camera. The targets come from the runtime's state (stroke speed or the
## climax wave); this smooths them and the afterglow back-off.
func tick_shot(delta: float, state: int, speed: float, climax_progress: float) -> void:
	var surge_target := 0.0
	var bob_target := 0.0
	if state == STATE_ACTIVE:
		var norm := clampf(speed / CAM_SPEED_REF, -1.0, 1.0)
		surge_target = norm * CAM_SURGE_M * camera_surge \
			* (CAM_BACK_RATIO if norm < 0.0 else 1.0)
		bob_target = -norm * CAM_BOB_M * camera_bob
	elif state == STATE_CLIMAX:
		var wave := sin(climax_progress * PI * 2.0 * CAM_CLIMAX_BOBS)
		surge_target = wave * CAM_CLIMAX_SURGE_M * camera_surge
		bob_target = -wave * CAM_CLIMAX_BOB_M * camera_bob
	var omega := 1.0 / maxf(CAM_RESPONSE_S, 0.001)
	var surge_accel := omega * omega * (surge_target - lean) - 2.0 * omega * lean_velocity
	lean_velocity += surge_accel * delta
	lean += lean_velocity * delta
	var bob_accel := omega * omega * (bob_target - bob) - 2.0 * omega * bob_velocity
	bob_velocity += bob_accel * delta
	bob += bob_velocity * delta
	var back_speed := AFTERGLOW_BACK_SPEED if state == STATE_AFTERGLOW else RESTORE_BACK_SPEED
	back = move_toward(back, back_target, back_speed * delta)


## The shot's forward lean: the displayed lean plus the idle-breathing offset, applied once.
func shot_lean_forward() -> float:
	return clampf(lean_view_forward + lean_sway, -1.0, 1.0)


func lean_size_scale() -> float:
	return MOTION.lean_size_scale_for(size_scale())


## Canon needs a little less travel in the standing pose than the other presets.
func standing_lean_scale() -> float:
	var scale := lean_size_scale()
	if size_name() == "canon":
		scale *= 0.8
	return scale


## Standing torso angle: hinge Anon's upper body forward over her by moving the head/camera
## forward and down by the spine arc, then countering the hip in `poses/standing_anon.gd`.
func anon_torso_angle() -> float:
	var presentation: Variant = facts.presentation_config if facts != null else null
	if not presentation is Dictionary:
		return 0.0
	return deg_to_rad(float((presentation as Dictionary).get("torso_angle_deg", 0.0)))


func anon_torso_forward() -> float:
	return ANON_TORSO_LEN_M * sin(anon_torso_angle())


func anon_torso_drop() -> float:
	return ANON_TORSO_LEN_M * (1.0 - cos(anon_torso_angle()))


func jiggle_size_scale() -> float:
	return clampf(size_scale(), 0.5, 1.2)


## The pose reaction a full side lean fires. The hand reach and the over-the-shoulder glance are
## the presentation; this owns the latch.
func tick_lean_action() -> void:
	if not at_actions_allowed():
		end_lean_action()
		return
	var side := lean_side
	if not lean_action_active:
		if absf(side) >= MOTION.LEAN_FIRE:
			start_lean_action(side)
		return
	if absf(side) <= MOTION.LEAN_RELEASE or signf(side) != signf(lean_action_side):
		end_lean_action()
		if absf(side) >= MOTION.LEAN_FIRE:
			start_lean_action(side)
		return


func start_lean_action(side: float) -> void:
	lean_action_active = true
	lean_action_side = side
	lean_action_kind = MOTION.lean_action_kind(str(facts.pose_id), side)
	var shoulder := ""
	if lean_action_kind == "reach":
		shoulder = "L" if side < 0.0 else "R"
		if facts != null:
			facts.write_forced_glance(shoulder)
		if standing_camera != null:
			standing_camera.call("hold_glance")
		if hands != null:
			hands.call("start_reach", shoulder)
	write_log("action fire pose=%s side=%.2f kind=%s shoulder=%s" % [
		str(facts.pose_id), side, lean_action_kind, shoulder])


func end_lean_action() -> void:
	if lean_action_kind == "reach":
		if hands != null:
			hands.call("end_reach")
		if facts != null:
			facts.write_forced_glance("")
		if standing_camera != null:
			standing_camera.call("clear_glance")
	lean_action_active = false
	lean_action_side = 0.0
	lean_action_kind = ""


## Drop the lean, the hands and the kiss for a fresh act or a restored look.
func reset_lean_state() -> void:
	end_lean_action()
	if hands != null:
		hands.call("reset")
	if kiss != null:
		kiss.call("reset")
	lean_forward = 0.0
	lean_side = 0.0
	lean_view_forward = 0.0
	lean_view_side = 0.0
	lean_sway = 0.0
	side_return_armed = false
	hold_rock_clock = 0.0


## Free camera owns the movement keys completely: Anon cannot walk, shift on the bed, jump or
## start couch actions while the shot is active. The previous value is restored at act end.
func apply_free_camera_lock() -> void:
	var body: Variant = player_body()
	if not is_instance_valid(body):
		return
	if not controls_locked_by_camera:
		controls_locked_saved = bool(body.get("controls_locked"))
		controls_locked_by_camera = true
	body.set("controls_locked", true)


func release_free_camera_lock() -> void:
	if not controls_locked_by_camera:
		return
	var body: Variant = player_body()
	if is_instance_valid(body):
		body.set("controls_locked", controls_locked_saved)
	controls_locked_by_camera = false
	controls_locked_saved = false


## Middle of the neck chain: midpoint of pony_neck1 and pony_neck2 world origins.
func neck_midpoint() -> Vector3:
	var pony: Variant = facts.pony if facts != null else null
	if not is_instance_valid(pony):
		return Vector3.INF
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return Vector3.INF
	var skeleton := sk as Skeleton3D
	var first := skeleton.find_bone("pony_neck1")
	var second := skeleton.find_bone("pony_neck2")
	if first >= 0 and second >= 0:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(first).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
		return (a + b) * 0.5
	if second >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
	return Vector3.INF


## Dispatch the act shot. Missionary owns its own view; standing applies the player-camera
## offsets. Debug free look leaves the stock player camera alone.
func apply_motion() -> void:
	if str(facts.pose_id) == CATALOG.MISSIONARY:
		if missionary_camera != null:
			missionary_camera.call("tick")
		return
	if free_look_active():
		return
	if standing_camera != null:
		standing_camera.call("tick")


## True when the shot owns the view this frame: not idle, not AnonPony/VR, and the camera exists.
func motion_ready() -> bool:
	if int(facts.state) == STATE_IDLE or not free_camera_active:
		return false
	if bool(facts.headset_view):
		return false
	if not is_instance_valid(camera):
		camera = main_camera()
	return is_instance_valid(camera)


## Debug: the player camera replaces the act shot so the pose can be inspected. The mouse stops
## feeding thrust while it is on and drives this look instead, because the act holds
## `controls_locked` (the stock mouse look is dead during an act).
func free_look_active() -> bool:
	return int(facts.state) != STATE_IDLE and SETTINGS.free_look.get_bool()


## Accumulated free-look rotation as (pitch, yaw), radians, from the act's starting view.
func free_look_rotation() -> Vector3:
	return Vector3(free_look_pitch, free_look_yaw, 0.0)


## Apply the debug free-look mouse motion. The runtime marks the event handled.
func look_input(relative: Vector2) -> void:
	var sensitivity := mouse_sensitivity()
	free_look_yaw = wrapf(free_look_yaw - relative.x * sensitivity, -PI, PI)
	var invert := -1.0 if invert_y() else 1.0
	free_look_pitch = clampf(free_look_pitch - relative.y * sensitivity * invert, -1.5, 1.5)


## Reset the free-look rotation whenever the debug view is switched on or off, and log the edges.
func tick_free_look() -> void:
	var active := free_look_active()
	if active == free_look_was:
		return
	free_look_was = active
	free_look_yaw = 0.0
	free_look_pitch = 0.0
	write_log("free look %s" % ("on" if active else "off"))


## Standing eye height follows the body preset; missionary is owned by the game's bed rest/seat
## camera and AnonPony has its own eye height. The previous values are restored at act end.
func apply_eye_override(pose: String, player_pony: bool) -> void:
	camera_target_eye = 0.0
	if pose == CATALOG.MISSIONARY or player_pony:
		return
	var body: Variant = player_body()
	if not is_instance_valid(body):
		return
	if body.get("_stand_eye") == null or body.get("seat") != null:
		return
	var base := player_eye_height()
	var target := base * size_scale()
	camera_target_eye = target
	if absf(target - base) < 0.001:
		return
	if not eye_override:
		saved_stand_eye = float(body.get("_stand_eye"))
		saved_eye_height = float(body.get("_eye_height"))
		eye_override = true
	body.set("_stand_eye", target)
	body.set("_eye_height", target)
	if body.has_method("_set_eye_y"):
		body.call("_set_eye_y", target)
	write_log("eye override standing base=%.2f target=%.2f" % [base, target])


func restore_eye_override() -> void:
	if not eye_override:
		return
	eye_override = false
	var body: Variant = player_body()
	if not is_instance_valid(body):
		return
	if body.get("_stand_eye") != null:
		body.set("_stand_eye", saved_stand_eye)
	if body.get("_eye_height") != null:
		body.set("_eye_height", saved_eye_height)
	if body.has_method("_set_eye_y"):
		body.call("_set_eye_y", saved_stand_eye)


## Snapshot the player look before the act turns the camera.
func capture_look() -> void:
	var body: Variant = player_body()
	if not is_instance_valid(body):
		return
	restore_yaw = float(body.rotation.y)
	var pitch: Variant = body.get("_pitch")
	restore_pitch = float(pitch) if pitch != null else 0.0
	look_yaw = restore_yaw
	look_pitch = restore_pitch
	look_captured = true


## Restore the player's yaw/pitch captured at act start. Missionary restores exactly; standing
## leaves Anon facing where the act left him, because snapping the pre-act view back looks worse.
## The lean/caress/kiss state is reset either way.
func restore_look(pose: String) -> void:
	if not look_captured:
		return
	look_captured = false
	var body: Variant = player_body()
	if not is_instance_valid(body):
		return
	var yaw := restore_yaw
	if look_restore_yaw:
		# Missionary restores the exact start snapshot; use its rig yaw rather than the later
		# capture.
		if pose == CATALOG.MISSIONARY and missionary_camera != null:
			var saved_yaw: float = missionary_camera.call("snapshot_yaw")
			if not is_nan(saved_yaw):
				yaw = saved_yaw
		body.rotation.y = yaw
		if body.get("_pitch") != null:
			body.set("_pitch", restore_pitch)
		if body.get("form_driver") == null:
			var view := main_camera()
			if is_instance_valid(view):
				view.rotation.x = restore_pitch
				view.rotation.z = 0.0
	reset_lean_state()
	write_log("look restored yaw=%.3f (captured %.3f) pitch=%.3f restore=%s" % [
		yaw, restore_yaw, restore_pitch, str(look_restore_yaw)])


## The current body preset name, or "" when no Settings node is reachable (a suite runtime).
func size_name() -> String:
	var settings := settings_node()
	if settings == null:
		return ""
	return str(settings.call("get_value", "ponies/size"))


func size_scale() -> float:
	match size_name():
		"mounting":
			return 0.80
		"hoers":
			return 1.10
		"canon":
			return 0.66
	return same_height_scale()


## Anon's chosen height over the 6 ft rig every offset was tuned on (1.0 at default).
func anon_height_scale() -> float:
	var settings := settings_node()
	if settings != null and settings.has_method("anon_height_scale"):
		return clampf(float(settings.call("anon_height_scale")), 0.6, 1.4)
	return 1.0


## "Same height as Anon" now sizes the pony from Anon's chosen height too. Other presets keep
## their authored sizes, so only this preset's camera/gap offsets follow the setting.
func same_height_scale() -> float:
	return anon_height_scale() if size_name() == "same height" else 1.0


## Absolute hand scale for the current body preset, from the per-size caress setting.
func palm_scale_factor() -> float:
	return SETTINGS.palm_scale_for(size_name())


func player_eye_height() -> float:
	var body: Variant = player_body()
	if is_instance_valid(body) and body.has_method("eye_height"):
		return float(body.call("eye_height"))
	if is_instance_valid(body) and body.get("_stand_eye") != null:
		return float(body.get("_stand_eye"))
	return 1.6


func mouse_sensitivity() -> float:
	var body: Variant = player_body()
	var value: Variant = body.get("mouse_sensitivity") if body != null else null
	return float(value) if value != null else 0.0022


func invert_y() -> bool:
	var body: Variant = player_body()
	var value: Variant = body.get("invert_y") if body != null else null
	return bool(value) if value != null else false


## The live player rig, or null outside a scene.
func player_body() -> Variant:
	if facts == null or not is_instance_valid(facts.main):
		return null
	return (facts.main as Node).get("player")


## The player's eye camera, or null.
func main_camera() -> Camera3D:
	if facts == null or not is_instance_valid(facts.main):
		return null
	var main_node: Node = facts.main
	if not main_node.has_method("camera"):
		return null
	var view: Variant = main_node.call("camera")
	return view as Camera3D


func apply_standing_lean_look() -> void:
	if str(facts.pose_id) == CATALOG.STANDING and standing_camera != null:
		standing_camera.call("apply_lean_look")


func settings_node() -> Node:
	var node: Node = null
	if facts != null and is_instance_valid(facts.main):
		node = facts.main
	elif facts != null and is_instance_valid(facts.pony):
		node = facts.pony
	return node.get_node_or_null("/root/Settings") if node != null else null


func feature(name: String) -> bool:
	var block: Variant = facts.features if facts != null else null
	return bool((block as Dictionary).get(name, false)) if block is Dictionary else false


func write_log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
