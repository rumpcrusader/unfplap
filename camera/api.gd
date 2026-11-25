extends Node
## Scope: pony
## The act camera session: the lean and its smoothing, the thrust camera, the debug free look and
## the size/torso values the view and the hands read.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const CAMERA_CONFIG := preload("res://mods/unfplap/camera/config.gd")
const POSES := preload("res://mods/unfplap/poses/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

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
## The kiss amount's own ramp: the camera eases in with the kiss and out after it.
const KISS_FADE_IN := 0.35
const KISS_FADE_OUT := 0.45
## Anon's spine length used by the standing torso hinge.
const ANON_TORSO_LEN_M := 0.65

const STATE_IDLE := ACT_STATE.State.IDLE
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW

## The typed act view. Presentation modules read it; the runtime refreshes it once per phase
## through `refresh_view()`.
var facts: ACT_FACTS = null
## The controllers the camera drives and asks, wired once with the view.
var hands: HANDS = null
## The one act view. It owns the view node and every live offset; this facade owns the lean.
var view: CAMERA_VIEW = null
## The standing act's Anon body controller, which the view drives by phase.
var standing_anon: Variant = null

## Act-session ownership. Each flag marks external state this act took and must give back.
var camera_owned := false
var camera: Camera3D = null
var free_camera_active := false
var camera_basis_ready := false
## The look point the last render wrote, so `aim_eyes()` reads this frame's aim without the pose.
var _look_point := Vector3.ZERO

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
## An action retired ahead of its lean stays down until the input drops back to rest.
var lean_action_spent := false

## The shot's smoothing state and the afterglow back-off.
var bob := 0.0
var bob_velocity := 0.0
var lean := 0.0
var lean_velocity := 0.0
var back := 0.0
var back_target := 0.0
## The last pose-change family and lean profile the hook saw, so a steady tick does nothing.
var _hook_family := ""
var _hook_lean := ""
var _hook_seen := false
var camera_surge: float
var camera_bob: float

## The player look the act captured and the live view it applies.
var look_yaw := 0.0
var look_pitch := 0.0

## Debug free look: the player camera replaces the act shot and the mouse looks instead of
## thrusting. The rotation is held from the act's starting view.
var free_look_yaw := 0.0
var free_look_pitch := 0.0
var free_look_was := false


## The collaborators the camera asks and the one act view, handed over once per runtime; none is
## built here.
func wire(facts_context: ACT_FACTS, hands_ctl: HANDS, view_ctl: CAMERA_VIEW) -> void:
	facts = facts_context
	hands = hands_ctl
	view = view_ctl
	assert(facts != null and hands != null and view != null)


## The pose read model. A missing view reads as no family outside an act.
func _pose_view() -> POSE_VIEW:
	if facts == null:
		return null
	var handle: Variant = facts.pose_view
	return handle as POSE_VIEW


## The pose family: `bed` for missionary, `standing` for standing, empty outside an act.
func pose_family() -> String:
	var pose_view := _pose_view()
	return pose_view.family if pose_view != null else ""


## True while the pose's contact is the mouth. The producer stays in the anatomy until A5.
func mouth_contact() -> bool:
	var pose_view := _pose_view()
	return pose_view != null and pose_view.contact_kind == "mouth"


## The presentation lean profile, the value the pure action math maps.
func lean_profile() -> String:
	var pose_view := _pose_view()
	return str(pose_view.presentation.get("lean", "")) if pose_view != null else ""


## Retarget seam: a new family ends the pose-local lean action so the next view tick starts afresh.
func pose_changed(pose_view: POSE_VIEW) -> void:
	if pose_view == null:
		return
	var family := pose_view.family
	var lean := str(pose_view.presentation.get("lean", ""))
	if _hook_seen and family == _hook_family and lean == _hook_lean:
		return
	var family_changed := _hook_seen and family != _hook_family
	_hook_seen = true
	_hook_family = family
	_hook_lean = lean
	if family_changed:
		end_lean_action()
		camera_basis_ready = false


## Aim the pose's look point for this rendered frame, after the pose write but before the shot, so
## the head solve follows this frame's lean.
func write_look_target() -> void:
	if facts == null or not is_instance_valid(WORLD.player_rig()):
		return
	var eye: Camera3D = WORLD.camera()
	if pose_family() == "bed" and view != null and is_instance_valid(view.view()):
		eye = view.view()
	var amount := clampf(float(facts.kiss_amount), 0.0, 1.0)
	var point := _look_point
	if is_instance_valid(eye):
		if pose_family() == "bed":
			var gaze := gaze_point()
			# Fade the mouth in with the kiss; the raw point would snap on the first frame.
			var mouth := _missionary_mouth()
			if mouth.is_finite() and gaze.is_finite():
				point = gaze.lerp(mouth, amount)
			else:
				point = gaze
		else:
			point = eye.global_position
	_look_point = point
	if facts.aim_look.is_valid():
		facts.aim_look.call(point, int(facts.state) == STATE_CLIMAX)


## Her missionary gaze target: the act body's eye, or ZERO.
func gaze_point() -> Vector3:
	if facts == null:
		return Vector3.ZERO
	var body := facts.missionary_body() as POSES.PoseActBody
	if body != null and body.live():
		var point := body.eye_point()
		if point.is_finite():
			var aim := point
			aim.y += SETTINGS.gaze_offset_mm_for(SETTINGS.pony_size_name()) / 1000.0
			if view != null and view.has_method("head_look_point_at"):
				return view.head_look_point_at(aim)
	return Vector3.INF


## His authored mouth on the bed, the kiss's own aim once it blends in.
func _missionary_mouth() -> Vector3:
	var body := facts.missionary_body() as POSES.PoseActBody if facts != null else null
	if body != null and body.live():
		return body.mouth_point()
	return Vector3.INF


## Her pupils follow the same gaze target the head solve uses; the pose's look point wins.
func aim_eyes() -> void:
	var pony := _pony_node()
	if not is_instance_valid(pony) or facts == null:
		return
	var target := gaze_point()
	var value := _look_point
	if value.is_finite() and value.length_squared() > 0.0001:
		target = value
	if not target.is_finite():
		return
	WORLD.pony(pony).aim_eyes(target)


## Take the act's camera tuning from the runtime's settings snapshot.
func configure(camera_block: CAMERA_CONFIG.Config) -> void:
	camera_surge = camera_block.surge
	camera_bob = camera_block.bob


## Begin the act's view. Returns true when the standing VR act must start: the act starts it on the
## anatomy bridge, because the camera never reaches that system. The mod view belongs to the desktop
## human alone: AnonPony and a headset keep the stock camera and are never leaned.
func begin_act(family: String, player_pony: bool, headset: bool) -> bool:
	camera_owned = true
	camera_basis_ready = false
	free_camera_active = false
	camera = null
	_look_point = Vector3.ZERO
	reset_lean_state()
	reset_shot()
	if standing_anon != null:
		standing_anon.reset_phase()
	if headset and not player_pony and family == "standing":
		return true
	if player_pony or headset:
		return false
	if not WORLD.ready() or not is_instance_valid(WORLD.player_rig()):
		return false
	free_camera_active = true
	camera = main_camera()
	if family == "standing" and is_instance_valid(camera):
		view.prepare()
		if standing_anon != null:
			standing_anon.install()
	return false


## Give the act's view back: the live offsets and the act's own view node. The frame has already
## given the player back, and the pose service removes the act body.
func finish_act() -> void:
	if not camera_owned:
		return
	camera_owned = false
	end_lean_action()
	if hands != null:
		hands.reset()
	if standing_anon != null:
		standing_anon.remove()
	if view != null:
		view.unmount()
		view.restore()
	camera_basis_ready = false
	camera = null
	free_camera_active = false
	_look_point = Vector3.ZERO
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


## The lean input: Q/E side, W/S forward/back, with Q/E also firing the pose reaction once the
## smoothed side lean crosses MOTION.LEAN_FIRE. `auto_open` freezes the shot in place.
func tick_lean(delta: float, paused: bool, auto_open: bool) -> void:
	_kiss_ramp(delta)
	if not at_actions_allowed():
		lean_idle(delta)
		return
	if not free_camera_active or bool(facts.player_pony) or bool(facts.headset_view) \
			or paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not lean_block_logged and int(facts.state) in [STATE_ACTIVE, STATE_CLIMAX]:
			lean_block_logged = true
			LOG.debug("lean blocked: free=%s pony=%s headset=%s paused=%s mouse=%d", [
				str(free_camera_active), str(facts.player_pony), str(facts.headset_view),
				str(paused), Input.mouse_mode])
		lean_idle(delta)
		return
	if mouth_contact():
		oral_lean_tick(delta)
		return
	if auto_open:
		# Hold-X auto settings: hold the shot exactly where it is. Do not write `lean_view_*`
		# here: the idle sway leaves it ahead of `lean_forward`, so copying the base value in
		# snapped the camera by about a sway step. Freezing both values leaves nothing to jump.
		side_return_armed = false
		end_lean_action()
		PERF.begin("caress_tick")
		if hands != null:
			hands.tick(delta, true)
		PERF.end("caress_tick")
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
	# Keep idle breathing as an offset: folded into the displayed lean, the smoother multiplied it
	# roughly twelvefold and the shot crept with nobody leaning.
	lean_sway = 0.0
	lean_block_logged = false
	if SETTINGS.idle_camera_sway.get_bool():
		hold_rock_clock += delta
		lean_sway = sin(hold_rock_clock * HOLD_SWAY_HZ) * MOTION.HOLD_SWAY_FORWARD
	tick_lean_action()
	PERF.begin("caress_tick")
	if hands != null:
		hands.tick(delta, true)
	PERF.end("caress_tick")
	apply_standing_lean_look()


## Oral keeps the shot neutral: no reach and no lean, while the caress still ticks, the standing
## look response still runs, and A/D and Z/C keep their own input.
func oral_lean_tick(delta: float) -> void:
	end_lean_action()
	lean_forward = move_toward(lean_forward, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
	lean_side = move_toward(lean_side, 0.0, delta / MOTION.LEAN_RETURN_SECONDS)
	lean_view_forward = lean_forward
	lean_view_side = lean_side
	lean_sway = 0.0
	side_return_armed = false
	lean_block_logged = false
	PERF.begin("caress_tick")
	if hands != null:
		hands.tick(delta, true)
	PERF.end("caress_tick")
	apply_standing_lean_look()


## The kiss's own lean: the camera eases the amount in with the kiss and out after it, and every
## other system reads the three values it writes.
func _kiss_ramp(delta: float) -> void:
	var amount := move_toward(float(facts.kiss_amount), 1.0 if bool(facts.kiss_active) else 0.0,
		delta / maxf(KISS_FADE_IN if bool(facts.kiss_active) else KISS_FADE_OUT, 0.001))
	facts.kiss_amount = amount
	var drop := MOTION.KISS_LEAN_DROP_M
	var forward := MOTION.KISS_LEAN_M
	if pose_family() == "standing":
		drop = SETTINGS.lean_drop.get_num()
		forward = SETTINGS.lean_forward.get_num()
	var height := float(facts.anon_height_scale)
	facts.lean_drop_m = drop * height * amount
	facts.lean_distance_m = forward * height * amount


## No input this frame: drop the hands, release the pose action and return the lean to rest.
func lean_idle(delta: float) -> void:
	if hands != null:
		hands.tick(delta, false)
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


## The standing torso hinge angle. The head and camera follow the spine arc, and the hip counters it
## so the pelvis stays put.
func anon_torso_angle() -> float:
	if facts == null or pose_family() != "standing":
		return 0.0
	return deg_to_rad(SETTINGS.torso_angle_deg.get_num())


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
		if absf(side) <= MOTION.LEAN_RELEASE:
			lean_action_spent = false
		if absf(side) >= MOTION.LEAN_FIRE and not lean_action_spent:
			start_lean_action(side)
		return
	if lean_action_kind == "reach" and hands != null and not hands.reach_active():
		# The hands dropped the shoulder hold (a smack took that hand): the glance goes with it.
		lean_action_spent = true
		end_lean_action()
		return
	if absf(side) <= MOTION.LEAN_RELEASE or signf(side) != signf(lean_action_side):
		end_lean_action()
		if absf(side) >= MOTION.LEAN_FIRE:
			start_lean_action(side)
		return


func start_lean_action(side: float) -> void:
	lean_action_active = true
	lean_action_spent = false
	lean_action_side = side
	lean_action_kind = MOTION.lean_action_kind(lean_profile(), side)
	var shoulder := ""
	if lean_action_kind == "reach":
		shoulder = "L" if side < 0.0 else "R"
		if facts != null:
			facts.write_forced_glance(shoulder)
		if view != null:
			view.hold_glance()
		if hands != null:
			hands.set_reach(HANDS.Side.LEFT if shoulder == "L" else HANDS.Side.RIGHT)
	LOG.debug("action fire lean=%s side=%.2f kind=%s shoulder=%s", [
		lean_profile(), side, lean_action_kind, shoulder])


func end_lean_action() -> void:
	if lean_action_kind == "reach":
		if hands != null:
			hands.set_reach(HANDS.Side.NONE)
		if facts != null:
			facts.write_forced_glance("")
		if view != null:
			view.clear_glance()
	lean_action_active = false
	lean_action_side = 0.0
	lean_action_kind = ""


## Drop the lean and the hands for a fresh act or a restored look.
func reset_lean_state() -> void:
	end_lean_action()
	if hands != null:
		hands.reset()
	if facts != null:
		facts.kiss_amount = 0.0
		facts.lean_drop_m = 0.0
		facts.lean_distance_m = 0.0
	lean_action_spent = false
	lean_forward = 0.0
	lean_side = 0.0
	lean_view_forward = 0.0
	lean_view_side = 0.0
	lean_sway = 0.0
	side_return_armed = false
	hold_rock_clock = 0.0


## Middle of the neck chain: midpoint of pony_neck1 and pony_neck2 world origins.
func neck_midpoint() -> Vector3:
	var pony := _pony_node()
	if not is_instance_valid(pony):
		return Vector3.INF
	var skeleton := WORLD.pony(pony).skeleton()
	if skeleton == null:
		return Vector3.INF
	var first := skeleton.find_bone("pony_neck1")
	var second := skeleton.find_bone("pony_neck2")
	if first >= 0 and second >= 0:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(first).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
		return (a + b) * 0.5
	if second >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(second).origin
	return Vector3.INF


## Her missionary face point: the head carried forward from the neck, for the kiss lean.
func missionary_face_point() -> Vector3:
	var pony := _pony_node()
	if not is_instance_valid(pony):
		return Vector3.INF
	var skeleton := WORLD.pony(pony).skeleton()
	if skeleton == null:
		return Vector3.INF
	var head := skeleton.find_bone("pony_head")
	if head < 0:
		return neck_midpoint()
	var at := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	var neck := skeleton.find_bone("pony_neck2")
	if neck < 0:
		return at
	var base := skeleton.global_transform * skeleton.get_bone_global_pose(neck).origin
	var direction := at - base
	if direction.length_squared() < 0.000001:
		return at
	return at + direction.normalized() * 0.12 * WORLD.pony(pony).body_scale()


## The pulled-back shot's target: the vulva when the anatomy is showing, otherwise a point between
## her hind femurs lifted toward her belly.
func missionary_vulva_point() -> Vector3:
	var point := Vector3.ZERO
	if facts != null:
		point = facts.anatomy_opening
	if point != Vector3.ZERO:
		return point
	var pony := _pony_node()
	if not is_instance_valid(pony):
		return Vector3.INF
	var skeleton := WORLD.pony(pony).skeleton()
	if skeleton == null:
		return Vector3.INF
	var left := skeleton.find_bone("pony_femur_L")
	var right := skeleton.find_bone("pony_femur_R")
	if left < 0 or right < 0:
		return neck_midpoint()
	var a := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var b := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
	return (a + b) * 0.5 + Vector3.UP * 0.10 * WORLD.pony(pony).body_scale()


## The presented body, or null outside an act.
func _pony_node() -> Node3D:
	return facts.pony if facts != null else null


## Dispatch the live view. The bed view is written at render time from his posed head; standing
## applies the player-camera offsets. Debug free look leaves the stock player camera alone.
func apply_motion() -> void:
	if pose_family() == "bed":
		return
	if free_look_active():
		return
	if view != null:
		view.tick()


## True when the act view owns the player camera this frame: not idle, not AnonPony/VR, and it
## exists.
func motion_ready() -> bool:
	if int(facts.state) == STATE_IDLE or not free_camera_active:
		return false
	if bool(facts.headset_view):
		return false
	if not is_instance_valid(camera):
		camera = main_camera()
	return is_instance_valid(camera)


## Debug: the player camera replaces the act shot so the pose can be inspected. The mouse drives
## this look instead of thrust because the act holds `controls_locked`.
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
	LOG.debug("free look %s", [("on" if active else "off")])


## The current body preset; the settings facade owns the game read, and a missing node is `canon`.
func size_name() -> String:
	return SETTINGS.pony_size_name()


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
	return clampf(SETTINGS.anon_height_scale(), 0.6, 1.4)


## "Same height as Anon" now sizes the pony from Anon's chosen height too. Other presets keep
## their authored sizes, so only this preset's camera/gap offsets follow the setting.
func same_height_scale() -> float:
	return anon_height_scale() if size_name() == "same height" else 1.0


## Absolute hand scale for the current body preset, from the per-size caress setting.
func palm_scale_factor() -> float:
	return SETTINGS.palm_scale_for(size_name())


func player_eye_height() -> float:
	var body := player_body()
	if is_instance_valid(body):
		var eye := WORLD.anon().eye_height()
		if not is_nan(eye):
			return eye
		if body.get("_stand_eye") != null:
			return float(body.get("_stand_eye"))
	return 1.6


## Her live eye line in Anon's root frame, from the rest head bone: the OpenPony rest sits at eye
## height, a bow must not move the camera, and the root may stand on a raised floor.
func pony_eye_height() -> float:
	var pony := _pony_node()
	if not is_instance_valid(pony):
		return NAN
	var skeleton := WORLD.pony(pony).skeleton()
	if skeleton == null:
		return NAN
	var head := skeleton.find_bone("pony_head")
	if head < 0:
		return NAN
	var eye: Vector3 = skeleton.global_transform * skeleton.get_bone_global_rest(head).origin
	var body := player_body()
	var floor_y := body.global_position.y if is_instance_valid(body) else 0.0
	return eye.y - floor_y


## The player-head clearance for the bed view: the pad over her skull and muzzle radii at the
## current size preset.
func head_clearance_m() -> float:
	return SETTINGS.head_clearance_mm_for(SETTINGS.pony_size_name()) / 1000.0


## How far the presented form's entrance sits from the mare's every standing offset was tuned on,
## in world metres at that body's scale: `(higher +, further back +)`. Zero for an ordinary rig.
static func entrance_offset_for(form: BODY_FORM.BodyForm) -> Vector2:
	if form == null:
		return Vector2.ZERO
	return BODY_PROFILE.entrance_offset_for(form.rig, form.body_scale)


func mouse_sensitivity() -> float:
	var body := player_body()
	var value: Variant = body.get("mouse_sensitivity") if is_instance_valid(body) else null
	return float(value) if value != null else 0.0022


func invert_y() -> bool:
	var body := player_body()
	var value: Variant = body.get("invert_y") if is_instance_valid(body) else null
	return bool(value) if value != null else false


## The live player rig, or null outside a scene.
func player_body() -> Node3D:
	if facts == null:
		return null
	return WORLD.player_rig()


## The player's eye camera, or null.
func main_camera() -> Camera3D:
	if facts == null:
		return null
	return WORLD.camera()


func apply_standing_lean_look() -> void:
	if pose_family() == "standing" and view != null:
		view.apply_lean_look()


## The one act view, for the host callbacks and the anatomy gaze.
func view_controller() -> CAMERA_VIEW:
	return view
