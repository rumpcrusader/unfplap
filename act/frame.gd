extends RefCounted
## The act's player frame: the one owner of Anon's placement, stance and restore. `begin()` places
## the act start, `refit()` re-solves the player for a new rig and `end()` gives him back once.
##
## See `docs/poses.md` (`## Player frame`) and `docs/runtime.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## Her neck line in the authored standing stance: the closed rule the aim uses when no live bone is
## available, so a start never reads her idle neck.
const STANDING_NECK_HEIGHT_M := 1.0


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
	var root_transform := Transform3D.IDENTITY
	var act_body_transform := Transform3D.IDENTITY
	var yaw := 0.0
	var aim_pitch := 0.0
	var look_yaw := 0.0
	var look_pitch := 0.0
	var stand_eye := 0.0
	var eye_height := 0.0
	var eye := 0.0
	## The pad his head keeps out of her skull and muzzle, in world metres. Zero for a standing act.
	var head_clearance := 0.0
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
	var stool: STOOL.ACT = null
	var form: Variant = null
	var player_pony := false
	var headset_view := false
	var forward := Vector3.FORWARD
	var pony_position := Vector3.ZERO
	var player_position := Vector3.ZERO
	var gaps: Dictionary = {}
	var gap := 0.0
	var size_name := ""
	var size_scale := 1.0
	## The "same height" preset's scale, the one the gap was tuned against.
	var anon_scale := 1.0
	var base_eye := 1.6
	var her_eye := NAN
	var entrance := Vector2.ZERO
	var eye := 0.0
	var neck_height := 0.0
	var neck_point := Vector3.INF
	var head_clearance := 0.0
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
## The scene the act found: the player, her and the bed, so the rejoin starts in reach.
var _scene_saved := false
var _start_player := Transform3D.IDENTITY
var _start_pony := Transform3D.IDENTITY
var _start_bed := Transform3D.IDENTITY
var _start_camera: Camera3D = null
var _start_camera_transform := Transform3D.IDENTITY
var _start_bed_saved := false
## The game's desktop presentation, parked for a bed act and given back at the end.
var _presentation: Node = null
var _presentation_enabled := true
var _presentation_processing := true
## The player's own controls lock, taken for the act and restored exactly.
var _controls_saved := false
var _controls_by_frame := false


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
		_snapshot_scene(input, values)
		_lock_player(values)
		_apply_start(solved, input, values)
	else:
		_apply_plan(solved, values)
	_active = true
	_pose = input
	_plan = solved
	_publish(solved)
	return solved


## Re-solve the base for the new rig without replaying the entrance.
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
	_publish(solved)
	return solved


## Give the player back once, in the state the act found him in. A failed start runs the same end.
func end() -> void:
	if not _active:
		return
	_active = false
	_release_avatar()
	_unlock_player()
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
		plan.head_clearance = rig.head_clearance
		plan.act_body_transform = rig.act_body_transform
		return plan
	if rig.player_pony or rig.headset_view:
		return plan
	var target := base_target(rig)
	plan.root_transform = Transform3D(Basis.looking_at(rig.forward, Vector3.UP), target)
	plan.aim_pitch = aim_pitch_for(rig, target)
	plan.look_yaw = plan.yaw
	plan.look_pitch = plan.aim_pitch
	return plan


## The act stance's player root: her gap behind her, on his current floor height.
static func base_target(rig: Rig) -> Vector3:
	var target: Vector3 = rig.pony_position - rig.forward * rig.gap
	target.y = rig.player_position.y
	return target


static func yaw_for(forward: Vector3) -> float:
	return atan2(-forward.x, -forward.z)


## The base aim from the authored neck point, never her idle rig.
static func aim_pitch_for(rig: Rig, target: Vector3, eye: float = NAN) -> float:
	var at_eye := eye if not is_nan(eye) else (rig.eye if rig.eye > 0.0 else rig.base_eye)
	var eye_y := target.y + at_eye
	var neck := neck_for(rig)
	if not neck.is_finite():
		return 0.0
	var flat := Vector2(neck.x - target.x, neck.z - target.z).length()
	if flat < 0.001:
		return 0.0
	return clampf(atan2(neck.y - eye_y, flat), -1.0, 1.0)


## Her target neck line, in world space. The authored pose supplies it; a start without a
## skeleton falls back to her live eye line, which is a world height, never the local constant.
static func neck_for(rig: Rig) -> Vector3:
	if rig.neck_point.is_finite():
		return rig.neck_point
	var neck_y := rig.pony_position.y + rig.neck_height
	if is_finite(rig.her_eye):
		neck_y = rig.player_position.y + rig.her_eye
	return Vector3(rig.pony_position.x, neck_y, rig.pony_position.z)


## The scene values one live frame reads, before the stance measurement.
func scene_rig(_pose_input: PoseInput, form: Variant = null) -> Rig:
	var rig := Rig.new()
	rig.pony = host.pony if is_instance_valid(host.pony) else null
	rig.player = WORLD.player if is_instance_valid(WORLD.player) else null
	rig.bed = session.bed
	rig.stool = context.stool as STOOL.ACT
	rig.form = form if form != null else context.handover.form()
	rig.player_pony = session.player_pony
	rig.headset_view = WORLD.headset_view()
	rig.forward = forward_for(rig.pony, rig.player)
	rig.pony_position = rig.pony.global_position if is_instance_valid(rig.pony) else Vector3.ZERO
	rig.player_position = rig.player.global_position if is_instance_valid(rig.player) else Vector3.ZERO
	rig.size_name = context.camera.size_name()
	rig.size_scale = context.camera.size_scale()
	rig.anon_scale = context.camera.same_height_scale()
	rig.entrance = context.camera.entrance_offset_for(rig.form)
	rig.gaps = pose_gaps()
	rig.gap = gap_for(rig) + SETTINGS.gap_offset_m.get_num()
	rig.her_eye = context.camera.pony_eye_height()
	rig.head_clearance = context.camera.head_clearance_m()
	rig.neck_height = neck_height_for(rig.pony)
	return rig


## The scene values one start measures from: the scene plus the stance and her authored neck line.
func live_rig(pose_input: PoseInput, form: Variant = null) -> Rig:
	var rig := scene_rig(pose_input, form)
	_capture(rig, pose_input.family == "standing")
	rig.eye = stance_eye(rig)
	if pose_input.family == "standing" and not rig.player_pony and not rig.headset_view:
		_prepare_standing(rig)
	return rig


## Her standing gaps, from the pose config the act is running. A start without a built pose falls
## back to the shipped row.
func pose_gaps() -> Dictionary:
	if context != null and context.pose != null:
		var gaps: Variant = context.pose.pose_config.get("gaps", {})
		if gaps is Dictionary and not (gaps as Dictionary).is_empty():
			return gaps
	var row := SETTINGS.pose(session.pony_id, CATALOG.STANDING)
	return row.rows("gaps").raw()


## Her centre to Anon: the tuned gap, his height scale and the body's entrance offset.
static func gap_for(rig: Rig) -> float:
	var gaps: Dictionary = rig.gaps
	var size := rig.size_name
	if not gaps.has(size):
		size = "same height"
	var base: float = float(gaps.get(size, 0.0))
	return base * rig.anon_scale + rig.entrance.y


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
	return STANDING_NECK_HEIGHT_M * scale


## The authored target neck midpoint in world space; `INF` when the rig has no neck chain.
static func _neck_point(pony: Variant) -> Vector3:
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
	var reported := GAME.eye_height(player as Node3D)
	if not is_nan(reported):
		return reported
	if is_instance_valid(player) and player.get("_stand_eye") != null:
		return float(player.get("_stand_eye"))
	return 1.6


## The start's one measurement: put her in the authored target pose and read its neck line. The
## player is placed at the base gap by the placement; nothing on his animated body is read.
func _prepare_standing(rig: Rig) -> void:
	if not is_instance_valid(rig.player) or _stool_active(rig):
		return
	rig.eye = stance_eye(rig)
	if context.pose != null:
		context.pose.apply_target_once()
	rig.neck_point = _neck_point(rig.pony)


## The start placement.
func _apply_start(plan: PlayerPlan, pose_input: PoseInput, rig: Rig) -> void:
	if pose_input.family == "standing":
		_apply_standing(plan, rig)
		return
	_park_avatar()
	_place_act_body(plan)


## The standing start: Anon at her gap and forward, then his stance. A player-pony or headset act
## puts her in front of that rig instead, because she rides it.
func _apply_standing(plan: PlayerPlan, rig: Rig) -> void:
	var body: Node3D = rig.player
	if rig.player_pony or rig.headset_view or not is_instance_valid(body):
		var placed: Variant = _place_pony_front(rig)
		if placed is Transform3D:
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
		target = rig.stool.place(target, plan.yaw, floor_y)
	body.global_position = target
	if rig.stool != null and rig.stool.lifted and body.get("velocity") != null:
		GAME.set_velocity(body, Vector3.ZERO)
	plan.root_transform.origin = target
	_reset_pelvis()
	body.reset_physics_interpolation()
	_write_look(plan)
	context.view.begin_facing(plan.root_transform)
	_check_stool(plan, rig)
	LOG.debug("frame places Anon at=(%.4f, %.4f, %.4f) yaw=%.4f pitch=%.4f gap=%.3f eye=%.3f pony=(%.4f, %.4f, %.4f) fwd=(%.4f, %.4f, %.4f) neck=(%.4f, %.4f, %.4f)", [
		target.x, target.y, target.z, plan.yaw, plan.aim_pitch,
		plan.gap, plan.eye, rig.pony_position.x, rig.pony_position.y, rig.pony_position.z,
		rig.forward.x, rig.forward.y, rig.forward.z,
		rig.neck_point.x, rig.neck_point.y, rig.neck_point.z])


## Put her in front of the player along his view, at the act gap.
func _place_pony_front(rig: Rig) -> Variant:
	if not is_instance_valid(rig.pony):
		if _stool_active(rig):
			rig.stool.failed = true
		return null
	var forward := Vector3.FORWARD
	var view := WORLD.camera()
	if is_instance_valid(view):
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and is_instance_valid(rig.player):
		forward = -rig.player.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var at := rig.player_position + forward * rig.gap
	at.y = rig.player_position.y
	var placed := Transform3D(Basis.looking_at(forward, Vector3.UP), at)
	rig.pony.reset_motion(placed)
	rig.pony.reset_physics_interpolation()
	return placed


## The live standing gap for the offer and the suites, at the presented form.
func standing_gap(form: Variant = null) -> float:
	return scene_rig(pose("standing"), form).gap


## Drop the part's pelvis handshake after a new body or a fresh placement.
func reset_pelvis() -> void:
	_reset_pelvis()


## The replacement body must still clear the adult-mare gate. A host without the service (a suite
## or a lab) reads as allowed, so the handover can be driven without the world's eligibility graph.
func new_body_is_adult() -> bool:
	if not is_instance_valid(WORLD.game):
		return true
	var service: ELIGIBILITY = PONIES.eligibility
	if service == null:
		return true
	return service.eligible(host.pony, ELIGIBILITY.Target.ACT)


## The missionary act body's placement for this frame: the pose service owns the body and applies
## it at render time; the frame triggers the first placement before the act opens.
func _place_act_body(plan: PlayerPlan) -> void:
	var frame: Variant = context.pose.bed_frame
	if not frame is Transform3D:
		return
	var body_scale: Variant = host.pony.get("body_scale") if is_instance_valid(host.pony) else null
	context.pose.render_write(POSE_SESSION.RenderFrame.of(frame as Transform3D,
		float(body_scale) if body_scale != null else 1.0, context.facts.size_name))
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
		GAME.set_pitch(body, pitch)
	if eye > 0.0:
		GAME.set_stand_eye(body, eye)
		GAME.set_eye_height(body, eye)
		GAME.set_eye_y(body, eye)
	var view := WORLD.camera()
	if body.get("form_driver") == null and is_instance_valid(view):
		view.rotation.x = pitch


func _write_look(plan: PlayerPlan) -> void:
	if context == null or context.facts == null:
		return
	context.facts.write_look(plan.look_yaw, plan.look_pitch)
	context.facts.mark_camera_basis_ready()


## Publish the plan values the live view reads: the bed head clearance and the standing eye line.
func _publish(plan: PlayerPlan) -> void:
	if context == null or context.facts == null:
		return
	context.facts.head_clearance = plan.head_clearance
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
		GAME.set_stand_eye(_player, _saved_stand_eye)
		GAME.set_eye_height(_player, _saved_eye_height)
		GAME.set_eye_y(_player, _saved_stand_eye)
	if context != null and context.camera != null:
		context.camera.reset_lean_state()
	if _pose != null and _pose.family != "standing" and is_instance_valid(_player):
		_player.rotation.y = _saved_yaw
		GAME.set_pitch(_player, _saved_pitch)
		var view := WORLD.camera()
		if _player.get("form_driver") == null and is_instance_valid(view):
			view.rotation.x = _saved_pitch


## Take the player's own controls for the act; `end()` gives the exact prior value back.
func _lock_player(rig: Rig) -> void:
	if rig.player_pony or rig.headset_view:
		return
	var body: Node3D = WORLD.player
	if not is_instance_valid(body):
		return
	if not _controls_by_frame:
		var held: Variant = body.get("controls_locked")
		_controls_saved = bool(held) if held != null else false
		_controls_by_frame = true
	GAME.set_controls_locked(body, true)


func _unlock_player() -> void:
	if not _controls_by_frame:
		return
	_controls_by_frame = false
	var body: Node3D = WORLD.player
	if is_instance_valid(body):
		GAME.set_controls_locked(body, _controls_saved)


## Park the game's desktop presentation for a bed act: it would otherwise show and drive his body
## from the player rig, and the act's own body is posed over it.
func _park_avatar() -> void:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return
	if is_instance_valid(_presentation):
		if _presentation_enabled and bool(_presentation.get("_enabled")) == true:
			GAME.set_presentation_enabled(_presentation, false)
		return
	var presentation: Variant = WORLD.game.get("desktop_presentation")
	if not is_instance_valid(presentation):
		return
	_presentation = presentation as Node
	var enabled: Variant = presentation.get("_enabled")
	_presentation_enabled = bool(enabled) if enabled != null else true
	if _presentation_enabled:
		GAME.set_presentation_enabled(_presentation, false)
	# `set_enabled(false)` only hides his body; `advance()` keeps running and re-hides it every
	# frame. Park the presentation's process too, so the act owns the avatar wholly.
	_presentation_processing = presentation.is_processing()
	presentation.set_process(false)


func _release_avatar() -> void:
	if is_instance_valid(_presentation):
		_presentation.set_process(_presentation_processing)
		if _presentation_enabled:
			GAME.set_presentation_enabled(_presentation, true)
	_presentation = null
	_presentation_enabled = true
	_presentation_processing = true


## Remember the player, her and the bed at the act's start, so the bed rejoin starts in reach.
func _snapshot_scene(pose_input: PoseInput, rig: Rig) -> void:
	if pose_input.family == "standing" or not is_instance_valid(rig.pony):
		return
	snapshot_scene()


## Capture the scene token. A moving bed carries the whole scene with it, so the restore applies
## the bed's rigid delta since this capture.
func snapshot_scene() -> void:
	_scene_saved = false
	_start_bed_saved = false
	if not is_instance_valid(host.pony) or not is_instance_valid(WORLD.player):
		return
	_start_camera = WORLD.camera()
	if is_instance_valid(_start_camera):
		_start_camera_transform = _start_camera.global_transform
	_start_player = WORLD.player.global_transform
	_start_pony = host.pony.global_transform
	_start_bed_saved = is_instance_valid(session.bed)
	if _start_bed_saved:
		_start_bed = (session.bed as Node3D).global_transform
	_scene_saved = true


## Refresh the token once the act is fully posed: `begin()` captures while Anon is still standing up
## from the bed, so his eye height is the reclined one.
func resnapshot() -> void:
	if not is_instance_valid(host.pony) or not is_instance_valid(WORLD.player):
		return
	_start_player = WORLD.player.global_transform
	_start_camera = WORLD.camera()
	if is_instance_valid(_start_camera):
		_start_camera_transform = _start_camera.global_transform
	_start_pony = host.pony.global_transform
	_start_bed_saved = is_instance_valid(session.bed)
	if _start_bed_saved:
		_start_bed = (session.bed as Node3D).global_transform
	_scene_saved = true


## Put the player, her and the camera back relative to the bed as the act found them; the runtime's
## bed cuddle rejoin starts from this restored standing spot.
func restore_scene() -> void:
	if not _scene_saved or not is_instance_valid(host.pony) \
			or not is_instance_valid(WORLD.player):
		return
	var delta := Transform3D.IDENTITY
	var bed_shift := 0.0
	if is_instance_valid(session.bed) and _start_bed_saved:
		delta = (session.bed as Node3D).global_transform * _start_bed.affine_inverse()
		bed_shift = (session.bed as Node3D).global_position.distance_to(_start_bed.origin)
	# Player/pony first, camera last: setting the player yaw rotates a child camera, so the snapshot
	# camera transform must be applied after the rig is back in place.
	WORLD.player.global_transform = delta * _start_player
	host.pony.global_transform = delta * _start_pony
	host.pony.reset_physics_interpolation()
	if is_instance_valid(_start_camera):
		_start_camera.global_transform = delta * _start_camera_transform
		_start_camera.make_current()
	LOG.debug("frame restore: bed_shift=%.2f camera=%s player=%s pony=%s", [
		bed_shift, str((delta * _start_camera_transform).origin),
		str((delta * _start_player).origin), str((delta * _start_pony).origin)])


func _check_stool(plan: PlayerPlan, rig: Rig) -> void:
	if rig.stool != null and rig.stool.failed:
		plan.valid = false


static func _stool_active(rig: Rig) -> bool:
	return rig.stool != null and rig.stool.active


static func _floor_y_at(rig: Rig, at: Vector3, body: Node3D) -> float:
	if rig.stool != null:
		return rig.stool.floor_y_at(at, body)
	return NAN


func _reset_pelvis() -> void:
	var service := PONIES.anatomy as ANATOMY
	if service != null:
		service.player_reset_pelvis()
