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
const WORLD := preload("res://mods/unfplap/world/service.gd")


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
	var eye := 0.0
	var entrance := Vector2.ZERO
	var neck_height := 0.0
	var opening := Vector3.INF
	var rear := Vector3.INF
	var part_root := Vector3.INF
	var shaft_length := 0.0
	var floor_y := NAN
	var act_body_transform := Transform3D.IDENTITY


var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null

var _active := false
var _pose: PoseInput = null
var _plan: PlayerPlan = null


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
	if solved.family == "standing":
		context.placement.bind_act(session.placement_values(form))
		var standing: Variant = context.placement.reanchor_act(session.pose_family())
		if standing is Transform3D:
			solved.root_transform = standing
			context.standing_camera.begin_facing(standing)
	else:
		_place_act_body(solved)
	_plan = solved
	return solved


## Give the player back once. Returns only after the act's own borrows have been released.
func end() -> void:
	if not _active:
		return
	_active = false
	_plan = null
	_pose = null


## The pure solve: one pose and one rig record in, one player-only plan out.
func solve(pose_input: PoseInput, rig: Rig) -> PlayerPlan:
	var plan := PlayerPlan.new()
	plan.family = pose_input.family
	plan.gap = rig.gap
	plan.eye = rig.eye if rig.eye > 0.0 else rig.base_eye
	plan.stand_eye = plan.eye
	plan.eye_height = plan.eye
	plan.yaw = yaw_for(rig.forward)
	if pose_input.family != "standing":
		plan.act_body_transform = rig.act_body_transform
		return plan
	if rig.player_pony or rig.headset_view:
		return plan
	var target: Vector3 = rig.pony_position - rig.forward * rig.gap
	target.y = rig.player_position.y
	plan.fit = fit_offset(rig)
	target += plan.fit
	plan.root_transform = Transform3D(Basis.looking_at(rig.forward, Vector3.UP), target)
	plan.aim_pitch = aim_pitch_for(rig, target)
	plan.look_yaw = plan.yaw
	plan.look_pitch = plan.aim_pitch
	return plan


## The whole-body fit: the part's natural pivot starts one shaft behind her entrance. The shift is
## horizontal and bounded; a stale or unreadable pivot fits nothing.
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


## The act base aim: her neck line in the authored stance, never her idle neck or the pre-act look.
static func aim_pitch_for(rig: Rig, target: Vector3) -> float:
	var eye := target.y + rig.eye
	var flat := Vector2(rig.pony_position.x - target.x, rig.pony_position.z - target.z).length()
	if flat < 0.001:
		return 0.0
	return clampf(atan2(rig.neck_height - eye, flat), -1.0, 1.0)


## The scene values one live frame reads. The pose and the rig supply the rest.
func live_rig(_pose_input: PoseInput, form: Variant = null) -> Rig:
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


## The start placement. The placement handle still owns the scene math for the first cut; the
## solve's plan records it.
func _apply_start(plan: PlayerPlan, pose_input: PoseInput, rig: Rig) -> void:
	if pose_input.family == "standing":
		context.placement.bind_act(session.placement_values(rig.form))
		var standing: Transform3D = context.placement.begin_act()
		plan.root_transform = standing
		var stool_act: Variant = session.stool()
		if stool_act != null and bool(stool_act.call("has_failed")):
			plan.valid = false
		return
	_place_act_body(plan)


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


## Apply a hand-made rig's plan (the pure solve path). The start path keeps the placement handle's
## scene passes until the solve owns them.
func _apply_plan(plan: PlayerPlan, rig: Rig) -> void:
	var player: Node3D = rig.player
	if not is_instance_valid(player) or plan.family != "standing":
		return
	if rig.player_pony or rig.headset_view:
		return
	player.global_position = plan.root_transform.origin
	player.rotation.y = plan.yaw
