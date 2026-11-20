extends RefCounted
## The act's player frame: the one owner of Anon's placement, stance and restore. `begin()` places
## the act start, `refit()` re-solves the player for a new rig and `end()` gives him back once.
##
## See `docs/poses.md` (`## Player frame`) and `docs/runtime.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")


## The pose's part of the frame contract: which asset family the start installs and the closed
## `start.setup` name. The rig below supplies everything the scene owns.
class PoseInput:
	var id := ""
	var family := ""
	var frame := ""
	var setup := ""


## The player-only result of one solve. It carries no camera transform and no shot: the game camera
## follows the player rig, and the view owns only its live offsets.
class PlayerPlan:
	var family := ""
	var gap := 0.0
	var fit := Vector3.ZERO
	var root_transform := Transform3D.IDENTITY
	var act_body_transform := Transform3D.IDENTITY
	var yaw := 0.0
	var aim_pitch := 0.0
	var look_yaw := 0.0
	var look_pitch := 0.0
	var stand_eye := 0.0
	var eye_height := 0.0
	var eye := 0.0
	var visible := true
	var controls_locked := true
	var body_visible := true
	var avatar_visible := true
	var valid := true


## The scene values one solve reads. The frame assembles it once per call; `solve()` never touches
## the scene, so a test can build the same record by hand.
class Rig:
	var pony: Node3D = null
	var player: Node3D = null
	var bed: Node3D = null
	var stool: Variant = null
	var form: Variant = null
	var player_pony := false
	var headset_view := false
	var forward := Vector3.FORWARD
	var pony_position := Vector3.ZERO
	var player_position := Vector3.ZERO
	var gap := 0.0
	var size_name := ""
	var size_scale := 1.0
	var base_eye := 1.6
	var her_eye := NAN
	var entrance := Vector2.ZERO
	var eye := 0.0
	var neck_height := 0.0
	var opening := Vector3.INF
	var rear := Vector3.INF
	var part_root := Vector3.INF
	var shaft_length := 0.0
	var act_body_transform := Transform3D.IDENTITY


var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null

var _active := false
var _pose: PoseInput = null
var _plan: PlayerPlan = null
var _player: Node3D = null
var _captured := false
var _owns_eye := false
var _saved_stand_eye := 0.0
var _saved_eye_height := 0.0
var _saved_yaw := 0.0
var _saved_pitch := 0.0


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## The start row as the frame's pose input. A missing row keeps the frame a no-op.
static func pose(name: String) -> PoseInput:
	var row: Dictionary = POSE_SPECS.spec(name)
	var input := PoseInput.new()
	input.id = str(row.get("id", name))
	input.family = str(row.get("family", ""))
	input.frame = str(row.get("frame", ""))
	var start: Variant = row.get("start", {})
	input.setup = str((start as Dictionary).get("setup", "")) if start is Dictionary else ""
	return input


func pose_input() -> PoseInput:
	return pose(session.pose_id)


func active() -> bool:
	return _active


func plan() -> PlayerPlan:
	return _plan


## Place the act start once. A second call while the frame is live returns the running plan.
func begin(pose_input: PoseInput = null, rig: Rig = null) -> PlayerPlan:
	if _active:
		return _plan
	var input := pose_input if pose_input != null else pose_input()
	if input == null or input.family.is_empty():
		return null
	var values := rig if rig != null else live_rig(input)
	var solved := solve(input, values)
	if rig == null:
		_apply_start(solved, input, values)
	else:
		_apply_plan(solved, values)
	_active = true
	_pose = input
	_plan = solved
	return solved


## Re-solve the player for a changed rig: a body swap or resume, a form revision, a size or
## anatomy setting, or a moving bed. No entrance repeats.
func refit(pose_input: PoseInput = null, form: Variant = null) -> PlayerPlan:
	var input := pose_input if pose_input != null else pose_input()
	if input == null or input.family.is_empty():
		return null
	if not _active:
		return begin(input)
	var values := live_rig(input, form)
	var solved := solve(input, values)
	_apply_start(solved, input, values)
	_plan = solved
	return solved


## Give the player back once, in the state the act found him in. A failed start runs the same end.
func end() -> void:
	if not _active:
		return
	_active = false
	_restore_player()
	_plan = null
	_pose = null
	_player = null
	_captured = false


## The pure solve: one pose and one rig record in, one player-only plan out.
func solve(pose_input: PoseInput, rig: Rig) -> PlayerPlan:
	var plan := PlayerPlan.new()
	plan.family = pose_input.family
	plan.gap = rig.gap
	plan.eye = rig.eye
	plan.stand_eye = rig.eye
	plan.eye_height = rig.eye
	plan.yaw = yaw_for(rig.forward)
	if pose_input.family != "standing":
		plan.act_body_transform = rig.act_body_transform
		return plan
	if rig.player_pony or rig.headset_view:
		return plan
	var target := base_target(rig)
	plan.fit = fit_offset(rig)
	target += plan.fit
	plan.root_transform = Transform3D(Basis.looking_at(rig.forward, Vector3.UP), target)
	plan.aim_pitch = aim_pitch_for(rig, target)
	plan.look_yaw = plan.yaw
	plan.look_pitch = plan.aim_pitch
	return plan


## The act stance's player root before the fit: her gap behind her, on his current floor height.
static func base_target(rig: Rig) -> Vector3:
	var target: Vector3 = rig.pony_position - rig.forward * rig.gap
	target.y = rig.player_position.y
	return target


## Move Anon so the part's resting pivot meets her opening: one horizontal shaft, clamped, and
## zero when the readings are unusable.
static func fit_offset(rig: Rig) -> Vector3:
	if rig.shaft_length <= 0.001:
		return Vector3.ZERO
	if not rig.opening.is_finite() or not rig.rear.is_finite():
		return Vector3.ZERO
	if not rig.part_root.is_finite():
		return Vector3.ZERO
	var flat := Vector3(rig.rear.x, 0.0, rig.rear.z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	var pivot_target: Vector3 = rig.opening + flat.normalized() * rig.shaft_length
	var shift: Vector3 = pivot_target - rig.part_root
	shift.y = 0.0
	if not shift.is_finite() or shift.length() > PLACEMENT.FIT_MAX_M:
		return Vector3.ZERO
	return shift


static func yaw_for(forward: Vector3) -> float:
	return atan2(-forward.x, -forward.z)


## The act base aim: her neck line in the authored stance, never her live neck or the pre-act look.
static func aim_pitch_for(rig: Rig, target: Vector3, eye: float = NAN) -> float:
	var at_eye := eye if not is_nan(eye) else (rig.eye if rig.eye > 0.0 else rig.base_eye)
	var eye_y := target.y + at_eye
	var flat := Vector2(rig.pony_position.x - target.x, rig.pony_position.z - target.z).length()
	if flat < 0.001:
		return 0.0
	return clampf(atan2(rig.neck_height - eye_y, flat), -1.0, 1.0)


## The scene values one live frame reads. The pose and the rig supply the rest.
func live_rig(pose_input: PoseInput, form: Variant = null) -> Rig:
	var rig := Rig.new()
	rig.pony = host.pony if is_instance_valid(host.pony) else null
	rig.player = WORLD.player if is_instance_valid(WORLD.player) else null
	rig.bed = session.bed
	rig.stool = context.stool
	rig.form = form if form != null else context.handover.form()
	rig.player_pony = session.player_pony
	rig.headset_view = WORLD.headset_view()
	rig.forward = forward_for(rig.pony, rig.player)
	rig.pony_position = rig.pony.global_position if is_instance_valid(rig.pony) else Vector3.ZERO
	rig.player_position = rig.player.global_position if is_instance_valid(rig.player) else Vector3.ZERO
	context.placement.bind_act(session.placement_values(rig.form))
	rig.gap = context.placement.gap_act()
	rig.size_name = context.camera.size_name()
	rig.size_scale = context.camera.size_scale()
	rig.entrance = context.camera.entrance_offset_for(rig.form)
	rig.her_eye = context.camera.pony_eye_height()
	rig.neck_height = neck_height_for(rig.pony)
	_capture(rig, pose_input.family == "standing")
	rig.eye = stance_eye(rig)
	if pose_input.family == "standing" and not rig.player_pony and not rig.headset_view:
		_measure_standing(rig)
	return rig


## Her flat forward, with Anon's own facing as the fallback, exactly as the placement handle reads
## it.
static func forward_for(pony: Node3D, player: Node3D) -> Vector3:
	var forward: Vector3 = -pony.global_basis.z if is_instance_valid(pony) else Vector3.FORWARD
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and is_instance_valid(player):
		forward = -player.global_basis.z
		forward.y = 0.0
	return forward.normalized()


## Her neck line in the authored stance: the closed rule the standing camera uses when no live
## bone is available, so a start never reads her idle neck.
static func neck_height_for(pony: Variant) -> float:
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = clampf(float(pony.get("body_scale")), 0.5, 2.5)
	return STANDING_CAMERA.STANDING_HEAD_NECK_HEIGHT_M * scale


## The standing eye line from the player's true base and the presented form, never from a previous
## override.
func stance_eye(rig: Rig) -> float:
	if not is_instance_valid(rig.player) or rig.player_pony or rig.headset_view:
		return 0.0
	if rig.player.get("_stand_eye") == null or rig.player.get("seat") != null:
		return 0.0
	var base := _saved_stand_eye if _owns_eye else player_base_eye(rig.player)
	return BODY_PROFILE.standing_eye(base, rig.size_scale, rig.her_eye, rig.entrance)


static func player_base_eye(player: Variant) -> float:
	if is_instance_valid(player) and player.has_method("eye_height"):
		return float(player.call("eye_height"))
	if is_instance_valid(player) and player.get("_stand_eye") != null:
		return float(player.get("_stand_eye"))
	return 1.6


## The start's one measurement: place him on the act stance's base root, put her in the authored
## target pose, sync his body once and read the fit from the undeformed opening.
func _measure_standing(rig: Rig) -> void:
	if not is_instance_valid(rig.player) or _stool_active(rig):
		# A stool start never fits: the lifted stance is the scene's, not the shaft's.
		return
	rig.eye = stance_eye(rig)
	var yaw := yaw_for(rig.forward)
	var target := base_target(rig)
	rig.player.global_position = target
	_write_stance(rig, rig.eye, yaw, aim_pitch_for(rig, target, rig.eye))
	if context.pose != null:
		context.pose.apply_target_once()
	var synced := _sync_player_body(rig.player, yaw)
	var anatomy: Variant = PONIES.anatomy
	if not _anatomy_ready(anatomy):
		return
	rig.shaft_length = float(anatomy.call("player_shaft_length_m"))
	var controller: Variant = anatomy.call("controller", rig.pony)
	if not _controller_ready(controller):
		return
	rig.opening = _base_hole_point(controller)
	rig.rear = _base_hole_rear(controller)
	rig.part_root = anatomy.call("player_root_natural")
	if not synced:
		rig.part_root = project_pivot(rig.part_root, rig.player, yaw)


func _anatomy_ready(service: Variant) -> bool:
	if service == null or not service.has_method("player_prepare") \
			or not service.has_method("player_root_natural") \
			or not service.has_method("player_shaft_length_m") \
			or not service.has_method("controller"):
		return false
	return bool(service.call("player_prepare"))


static func _controller_ready(controller: Variant) -> bool:
	if not is_instance_valid(controller) or not controller.has_method("hole_point"):
		return false
	if controller.has_method("is_attached") and not bool(controller.call("is_attached")):
		return false
	return true


static func _base_hole_point(controller: Variant) -> Vector3:
	if controller.has_method("hole_base_point"):
		return controller.call("hole_base_point", 0.0)
	return controller.call("hole_point", 0.0)


static func _base_hole_rear(controller: Variant) -> Vector3:
	if controller.has_method("hole_base_rear"):
		return controller.call("hole_base_rear", 0.0)
	return controller.call("hole_rear", 0.0)


## Sync the desktop body once for the canonical stance, so the fit reads that stance; a failed
## guarded sync falls back to projecting the measured pivot onto the canonical yaw.
func _sync_player_body(player: Node3D, yaw: float) -> bool:
	if not is_instance_valid(player):
		return false
	var body: Variant = player.find_child("AnonBody", true, false)
	if not is_instance_valid(body) or not body.has_method("_process_step"):
		return false
	var frame_value: Variant = body.get("_body_physics_frame")
	if frame_value != null:
		body.set("_body_physics_frame", -1)
	if body.get("_body_yaw") != null:
		body.set("_body_yaw", yaw)
	if body.get("_yaw_initialized") != null:
		body.set("_yaw_initialized", true)
	body.call("_process_step", 0.0)
	if frame_value != null:
		body.set("_body_physics_frame", frame_value)
	var ik: Variant = body.find_child("BodyIK", true, false)
	if is_instance_valid(ik) and ik.has_method("_modification_step"):
		ik.call("_modification_step")
	var skeleton: Variant = body.find_child("Skeleton3D", true, false)
	if not skeleton is Skeleton3D:
		return false
	var sk := skeleton as Skeleton3D
	sk.force_update_all_bone_transforms()
	var hips := sk.find_bone("Hips")
	if hips >= 0:
		sk.force_update_bone_child_transform(hips)
	return true


## Fallback when the body could not be synced: keep the pivot's distance and height, but put it
## on the canonical forward so a stale body yaw cannot move him sideways.
static func project_pivot(root: Vector3, player: Node3D, yaw: float) -> Vector3:
	if not root.is_finite() or not is_instance_valid(player):
		return root
	var offset := root - player.global_position
	var flat := Vector2(offset.x, offset.z).length()
	if flat < 0.0001:
		return root
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return player.global_position + forward * flat + Vector3.UP * offset.y


## The start placement.
func _apply_start(plan: PlayerPlan, pose_input: PoseInput, rig: Rig) -> void:
	if pose_input.family == "standing":
		_apply_standing(plan, rig)
		return
	_place_act_body(plan)


## The standing start: Anon at her gap and forward, the whole-body fit included, then his stance.
func _apply_standing(plan: PlayerPlan, rig: Rig) -> void:
	var body: Node3D = rig.player
	if rig.player_pony or rig.headset_view or not is_instance_valid(body):
		context.placement.bind_act(session.placement_values(rig.form))
		var placed: Transform3D = context.placement.begin_act()
		plan.root_transform = placed
		_check_stool(plan, rig)
		return
	_write_stance(rig, plan.eye, plan.yaw, plan.aim_pitch)
	var target := plan.root_transform.origin
	var floor_y := _floor_y_at(rig, Vector3(target.x, body.global_position.y + 0.4, target.z), body)
	if not is_finite(floor_y) or absf(floor_y - body.global_position.y) > 1.0:
		floor_y = body.global_position.y
	target.y = body.global_position.y
	if _stool_active(rig):
		var raised: Variant = rig.stool.call("place", target, plan.yaw, floor_y)
		if raised is Vector3:
			target = raised
	body.global_position = target
	if rig.stool != null and bool(rig.stool.get("lifted")) and body.get("velocity") != null:
		body.set("velocity", Vector3.ZERO)
	plan.root_transform.origin = target
	# The fit moved him after the measurement: one more sync keeps the first frame's body on the
	# stance the plan placed, instead of the previous stance for a frame.
	_sync_player_body(body, plan.yaw)
	_reset_pelvis()
	body.reset_physics_interpolation()
	_write_look(plan)
	context.standing_camera.begin_facing(plan.root_transform)
	_check_stool(plan, rig)
	LOG.debug("frame places Anon at=(%.4f, %.4f, %.4f) yaw=%.4f pitch=%.4f fit=%+.4f gap=%.3f eye=%.3f pony=(%.4f, %.4f, %.4f) fwd=(%.4f, %.4f, %.4f)", [
		target.x, target.y, target.z, plan.yaw, plan.aim_pitch, plan.fit.dot(rig.forward),
		plan.gap, plan.eye, rig.pony_position.x, rig.pony_position.y, rig.pony_position.z,
		rig.forward.x, rig.forward.y, rig.forward.z])


## The missionary act body's placement for this frame: the pose service owns the body and applies
## it at render time; the frame triggers the first placement before the act opens.
func _place_act_body(plan: PlayerPlan) -> void:
	var frame: Variant = context.pose.bed_frame
	if not frame is Transform3D:
		return
	var body_scale: Variant = host.pony.get("body_scale") if is_instance_valid(host.pony) else null
	context.pose.render_write({
		"bed_frame": frame,
		"body_scale": float(body_scale) if body_scale != null else 1.0,
		"size_name": context.facts.size_name,
		"eye_camera_active": false,
	})
	var body: Variant = context.pose.act_body
	var avatar: Variant = body.get("avatar") if is_instance_valid(body) else null
	if is_instance_valid(avatar) and avatar is Node3D:
		plan.act_body_transform = (avatar as Node3D).global_transform


## Apply a hand-made rig's plan (the pure solve path and the suites).
func _apply_plan(plan: PlayerPlan, rig: Rig) -> void:
	var player: Node3D = rig.player
	_player = player
	if not is_instance_valid(player):
		return
	_capture(rig, plan.family == "standing")
	if plan.family != "standing":
		return
	if rig.player_pony or rig.headset_view:
		return
	_write_stance(rig, plan.eye, plan.yaw, plan.aim_pitch)
	player.global_position = plan.root_transform.origin
	_write_look(plan)


## The canonical stance for that body: eye line, yaw and pitch on the player's own state. The game
## camera is his child and follows.
func _write_stance(rig: Rig, eye: float, yaw: float, pitch: float) -> void:
	var body: Node3D = rig.player
	if not is_instance_valid(body):
		return
	_capture(rig)
	body.rotation.y = yaw
	if body.get("_pitch") != null:
		body.set("_pitch", pitch)
	if eye > 0.0:
		body.set("_stand_eye", eye)
		body.set("_eye_height", eye)
		if body.has_method("_set_eye_y"):
			body.call("_set_eye_y", eye)
	var view := WORLD.camera()
	if body.get("form_driver") == null and is_instance_valid(view):
		view.rotation.x = pitch
	if context != null and context.camera != null:
		context.camera.camera_target_eye = eye


func _write_look(plan: PlayerPlan) -> void:
	if context == null or context.facts == null:
		return
	context.facts.write_look(plan.look_yaw, plan.look_pitch)
	context.facts.mark_camera_basis_ready()
	if plan.eye > 0.0:
		context.facts.player_eye_height = plan.eye


## Capture the player state the act found, once per start. A refit keeps the first token.
func _capture(rig: Rig, owns_eye := true) -> void:
	if _captured or not is_instance_valid(rig.player):
		return
	_captured = true
	_player = rig.player
	_saved_yaw = _player.rotation.y
	var pitch: Variant = _player.get("_pitch")
	_saved_pitch = float(pitch) if pitch != null else 0.0
	var stand: Variant = _player.get("_stand_eye")
	var height: Variant = _player.get("_eye_height")
	if owns_eye and stand != null and height != null:
		_saved_stand_eye = float(stand)
		_saved_eye_height = float(height)
		_owns_eye = true


## Give the player back: the eye line always, the act's captured look for a bed act. A standing act
## leaves Anon facing where it ended.
func _restore_player() -> void:
	if _owns_eye and is_instance_valid(_player):
		_owns_eye = false
		if _player.get("_stand_eye") != null:
			_player.set("_stand_eye", _saved_stand_eye)
		if _player.get("_eye_height") != null:
			_player.set("_eye_height", _saved_eye_height)
		if _player.has_method("_set_eye_y"):
			_player.call("_set_eye_y", _saved_stand_eye)
	if context != null and context.camera != null:
		context.camera.camera_target_eye = 0.0
		context.camera.reset_lean_state()
	if _pose != null and _pose.family != "standing" and is_instance_valid(_player):
		_player.rotation.y = _saved_yaw
		if _player.get("_pitch") != null:
			_player.set("_pitch", _saved_pitch)
		var view := WORLD.camera()
		if _player.get("form_driver") == null and is_instance_valid(view):
			view.rotation.x = _saved_pitch


func _check_stool(plan: PlayerPlan, rig: Rig) -> void:
	if rig.stool != null and bool(rig.stool.get("failed")):
		plan.valid = false


static func _stool_active(rig: Rig) -> bool:
	return rig.stool != null and bool(rig.stool.get("active"))


static func _floor_y_at(rig: Rig, at: Vector3, body: Node3D) -> float:
	if rig.stool != null and rig.stool.has_method("floor_y_at"):
		return float(rig.stool.call("floor_y_at", at, body))
	return NAN


func _reset_pelvis() -> void:
	var service: Variant = PONIES.anatomy
	if service != null and service.has_method("player_reset_pelvis"):
		service.call("player_reset_pelvis")
