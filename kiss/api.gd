extends Node
## Scope: pony
## Missionary and standing kiss. The runtime owns the act state; this controller owns the base
## AffectionPose bridge, the custom mouth aim, the foreleg pin and the kiss lean.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const KISS_LEGS := preload("res://mods/unfplap/kiss/legs.gd")
const POSES := preload("res://mods/unfplap/poses/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const KISS_FADE_IN := 0.35
const KISS_FADE_OUT := 0.45
const KISS_SOUND_MIN := 2.0
const KISS_SOUND_MAX := 3.4
const KISS_LEAN_M := 0.27
const KISS_LEAN_SIDE_M := 0.18
const KISS_LEAN_DROP_M := 0.035
const KISS_CAMERA_YAW_DEG := 10.0
const KISS_LEAN_SECONDS := 0.35
const KISS_PONY_SIDE_SIGN := 1.0
const KISS_RESTART_COOLDOWN_MS := 500
## The stock pose's side hold: effectively forever, so its own side switch cannot fire mid-kiss.
const KISS_SIDE_HOLD_S := 9999.0
const STANDING_KISS_LEAN := 0.90
## The side lean alone would drag the kiss along, so W is required too.
const MISSIONARY_KISS_LEAN := 0.90

var facts: ACT_FACTS
var pony: Node3D
var _presentation_cfg: Dictionary = {}
var _pose_cfg: Dictionary = {}
## The last pose-change profile the hook saw, so a steady tick does nothing.
var _hook_family := ""
var _hook_profile := ""
var _hook_seen := false

var _kiss_amount := 0.0
var _kiss_lean := 0.0
var _kiss_sound_clock := 0.0
var _custom_kiss_active := false
var _base_kiss_active := false
var _base_kiss_releasing := false
var _lean_kiss_active := false
var _lean_kiss_used := false
var _lean_kiss_ready_at := 0
## Latched for the whole kiss (including the Affection release) so rock noise cannot flip sides.
var _kiss_camera_side := 0.0
var _kiss_pony_side := 0.0
var _kiss_diag_clock := 0.0
var _base_kiss_affection: Node
var _base_kiss_pose: SkeletonModifier3D
var _base_kiss_pose_index := -1
var _base_kiss_excitement: Node
var _kiss_forelegs_planted := false
var _kiss_saved_rear := 1.0
var _kiss_saved_hooves := 1.0
var _kiss_leg_pin: KISS_LEGS = null


## The pose read model. A missing view reads as no family outside an act.
func _pose_view() -> POSE_VIEW:
	if facts == null:
		return null
	var handle: Variant = facts.pose_view
	return handle as POSE_VIEW


## The pose family from the pose view: `bed` for missionary, `standing` for standing.
func _pose_family() -> String:
	var view := _pose_view()
	return view.family if view != null else ""


## The presentation kiss profile, `missionary` or `standing`.
func _kiss_profile() -> String:
	var view := _pose_view()
	return str(view.presentation.get("kiss", "")) if view != null else ""


## The pose-change hook: the live config and the base kiss profile follow the view, but a running
## kiss is never ended by the change itself. A shared keep is a cheap no-op.
func pose_changed(view: POSE_VIEW) -> void:
	if view == null:
		return
	var family := view.family
	var profile := str(view.presentation.get("kiss", ""))
	var cfg_value: Variant = view.from_config
	if not cfg_value is Dictionary or (cfg_value as Dictionary).is_empty():
		cfg_value = view.pose_config
	if _hook_seen and family == _hook_family and profile == _hook_profile \
			and is_same(cfg_value, _pose_cfg):
		return
	_hook_seen = true
	_hook_family = family
	_hook_profile = profile
	_pose_cfg = cfg_value as Dictionary if cfg_value is Dictionary else {}


func _apply_kiss_forelegs() -> void:
	if _pose_family() != "standing":
		return
	if _kiss_forelegs_planted:
		return
	var settings := WORLD.affection().kiss_settings()
	_kiss_saved_rear = float(settings.get("rear", 1.0))
	_kiss_saved_hooves = float(settings.get("hooves", 1.0))
	settings["rear"] = 0.0
	settings["hooves"] = 0.0
	_kiss_forelegs_planted = true
	LOG.debug("kiss forelegs planted")


func _restore_kiss_forelegs() -> void:
	if not _kiss_forelegs_planted:
		return
	var settings := WORLD.affection().kiss_settings()
	settings["rear"] = _kiss_saved_rear
	settings["hooves"] = _kiss_saved_hooves
	_kiss_forelegs_planted = false


## The base kiss's chest flex runs after body_sway's upper-arm pin. This extra modifier runs
## last and brings the visible hoof tips back to where they were before the kiss.
func _start_kiss_leg_pin() -> void:
	if _pose_family() != "standing":
		return
	if is_instance_valid(_kiss_leg_pin) or not is_instance_valid(pony):
		return
	var skeleton := WORLD.pony(pony).skeleton()
	if skeleton == null:
		return
	_kiss_leg_pin = KISS_LEGS.new()
	_kiss_leg_pin.name = "UnfplapKissLegPin"
	_kiss_leg_pin.mare = pony
	skeleton.add_child(_kiss_leg_pin)
	skeleton.move_child(_kiss_leg_pin, skeleton.get_child_count() - 1)
	_kiss_leg_pin.capture()
	LOG.debug("kiss foreleg pin captured")


func _stop_kiss_leg_pin() -> void:
	if is_instance_valid(_kiss_leg_pin):
		_kiss_leg_pin.queue_free()
	_kiss_leg_pin = null


## Reuse the game's own kiss in standing; the pose modifier is moved last so its IK layers on top.
## Its eligibility checks read `controls_locked`, so unlock for that one call only.
func _start_base_kiss() -> bool:
	# The stock kiss is authored standing: on the bed it lifts her chest off the mattress and
	# turns her head across it, so missionary uses the act's own head aim instead.
	if _pose_family() == "bed":
		return false
	if not is_instance_valid(pony) or not WORLD.ready() \
			or not is_instance_valid(WORLD.player_rig()):
		return false
	var affection := pony.get_node_or_null("Affection")
	var affection_view := WORLD.affection()
	var kisser := affection_view.kisser()
	if not is_instance_valid(affection) or not is_instance_valid(kisser):
		return false
	if not str(affection.get("kind")).is_empty():
		return false
	var anon := WORLD.anon()
	var was_locked := anon.controls_locked()
	anon.set_controls_locked(false)
	var begun := affection_view.begin_from_pony(pony)
	anon.set_controls_locked(was_locked)
	if not begun:
		return false
	_apply_kiss_forelegs()
	_base_kiss_active = true
	_base_kiss_releasing = false
	_base_kiss_affection = affection
	_suppress_base_kiss_excitement()
	var pose_node: Variant = affection.get("pose")
	var skeleton := WORLD.pony(pony).skeleton()
	if pose_node is SkeletonModifier3D and skeleton != null:
		var index := skeleton.get_children().find(pose_node)
		if index >= 0:
			_base_kiss_pose = pose_node as SkeletonModifier3D
			_base_kiss_pose_index = index
			skeleton.move_child(_base_kiss_pose, skeleton.get_child_count() - 1)
			_pin_base_side()
	_start_kiss_leg_pin()
	LOG.debug("base kiss start pony=%s", [str(facts.pony_id)])
	return true


func _end_base_kiss() -> void:
	if not _base_kiss_active:
		return
	_base_kiss_active = false
	_restore_base_kiss_excitement()
	var affection := _base_kiss_affection
	if is_instance_valid(affection):
		var affection_view := WORLD.affection()
		if str(affection.get("kind")) == "kiss":
			affection_view.end(affection)
		# Even if the affection already ended itself, clear its 60 s stare afterglow.
		affection_view.cancel_afterglow(affection)
	if is_instance_valid(WORLD.world_root()):
		WORLD.affection().clear_kisser()
	if is_instance_valid(WORLD.player_rig()) \
			and int(facts.state) in [STATE_ACTIVE, STATE_CLIMAX]:
		WORLD.player_rig().set_meta("kiss_hold", true)
	_base_kiss_releasing = is_instance_valid(_base_kiss_pose)
	if not _base_kiss_releasing:
		_base_kiss_affection = null
		_restore_kiss_forelegs()
		_stop_kiss_leg_pin()


## Keep the AffectionPose last while its own 0.6 s release eases out, then restore the child order.
func _restore_base_kiss_pose() -> void:
	_restore_kiss_forelegs()
	_stop_kiss_leg_pin()
	if is_instance_valid(_base_kiss_pose):
		WORLD.affection().release_side(_base_kiss_pose)
	_base_kiss_releasing = false
	if is_instance_valid(_base_kiss_pose) and is_instance_valid(pony):
		var skeleton := WORLD.pony(pony).skeleton()
		if skeleton != null:
			var index := clampi(_base_kiss_pose_index, 0, skeleton.get_child_count() - 1)
			skeleton.move_child(_base_kiss_pose, index)
	_base_kiss_pose = null
	_base_kiss_pose_index = -1
	_base_kiss_affection = null
	_restore_base_kiss_excitement()


## A base kiss otherwise plays the stock horn sparkle, which reads as spellcasting.
## Hold the shared act-level Beat instead; the runtime restores it after the last holder.
func _suppress_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_excitement) or not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	_base_kiss_excitement = excitement as Node
	if facts != null:
		facts.hold_beat("kiss")
	WORLD.affection().settle_excitement(_base_kiss_excitement)


func _restore_base_kiss_excitement() -> void:
	if facts != null:
		facts.release_beat("kiss")
	_base_kiss_excitement = null


func _kiss_visible() -> bool:
	if _base_kiss_active:
		return true
	return _lean_kiss_active and _custom_kiss_active


## Standing kiss controls. Missionary keeps the fixed constants.
func _kiss_controls() -> Dictionary:
	if _pose_family() != "standing":
		return {}
	var kiss: Variant = _presentation_cfg.get("kiss", {})
	return kiss if kiss is Dictionary else {}


func _kiss_mouth_offset() -> Vector3:
	var kiss := _kiss_controls()
	var scale: float = float(facts.anon_height_scale)
	return Vector3(
		float(kiss.get("mouth_right", 0.0)),
		-float(kiss.get("mouth_drop", 0.07)),
		-float(kiss.get("mouth_forward", 0.02))) * scale


func _kiss_camera_yaw_deg() -> float:
	return float(_kiss_controls().get("camera_yaw_deg", KISS_CAMERA_YAW_DEG))


func _kiss_lean_side() -> float:
	return float(_kiss_controls().get("lean_side", KISS_LEAN_SIDE_M)) * float(facts.anon_height_scale)


func _kiss_lean_forward() -> float:
	return float(_kiss_controls().get("lean_forward", KISS_LEAN_M)) * float(facts.anon_height_scale)


func _kiss_lean_drop() -> float:
	return float(_kiss_controls().get("lean_drop", KISS_LEAN_DROP_M)) * float(facts.anon_height_scale)


func _kiss_lean_distance() -> float:
	return _kiss_lean_forward() * _kiss_lean


## The act kiss follows the side Anon leaned to; outside a latched kiss fall back to live input.
func _side() -> float:
	if absf(_kiss_camera_side) > 0.5:
		return _kiss_camera_side
	if absf(float(facts.lean_view_side)) > 0.01:
		return signf(float(facts.lean_view_side))
	if absf(float(facts.lean_action_side)) > 0.01:
		return signf(float(facts.lean_action_side))
	return 0.0


## `AffectionPose` wants the opposite sign: she must lean toward the same world side Anon moved to.
static func kiss_pony_side(lean_side: float) -> float:
	if absf(lean_side) <= 0.001:
		return 0.0
	return KISS_PONY_SIDE_SIGN * signf(lean_side)


## Lateral travel: hand the lean offset over to the kiss offset as the kiss blends in.
## Adding both overshoots her neck reach, and the clearance pass then pushes her muzzle back.
static func kiss_lateral_offset(lean_side: float, kiss_side: float, kiss_lean: float,
		size_scale := 1.0) -> float:
	var blend := clampf(kiss_lean, 0.0, 1.0)
	var lean := MOTION.LEAN_SIDE_M * lean_side * size_scale
	var kiss := KISS_LEAN_SIDE_M * kiss_side
	return lerpf(lean, kiss, blend)


func _kiss_lateral_offset(lean_side: float, kiss_side: float, kiss_lean: float,
		size_scale := 1.0) -> float:
	var blend := clampf(kiss_lean, 0.0, 1.0)
	var lean := MOTION.LEAN_SIDE_M * lean_side * size_scale
	var kiss := _kiss_lean_side() * kiss_side
	return lerpf(lean, kiss, blend)


func lateral_offset(lean_scale: float) -> float:
	return _kiss_lateral_offset(float(facts.lean_view_side), _side(), _kiss_lean, lean_scale)


func _latch_side(side: float = NAN) -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0
	# Latch the requested lean, not the inertia-smoothed view: switching sides and pressing F
	# immediately must not keep the previous side for the whole kiss.
	var lean := float(facts.lean_side) if is_nan(side) else side
	if absf(lean) <= 0.01:
		lean = float(facts.lean_action_side)
	if absf(lean) <= 0.01:
		lean = float(facts.lean_view_side)
	if absf(lean) <= 0.01:
		return
	_kiss_camera_side = signf(lean)
	_kiss_pony_side = kiss_pony_side(_kiss_camera_side)


func _clear_side() -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0


## Pin the game's AffectionPose to the side Anon leaned to, so their heads interlock.
## The stock kiss switches sides on its own; a renamed field skips this quietly.
func _pin_base_side() -> void:
	if not _base_kiss_active or not is_instance_valid(_base_kiss_pose):
		return
	if absf(_kiss_pony_side) <= 0.5:
		return
	var affection_view := WORLD.affection()
	if not affection_view.side_known(_base_kiss_pose):
		return
	affection_view.pin_side(_base_kiss_pose, _kiss_pony_side, KISS_SIDE_HOLD_S)


## Her mouth stays at Anon's lips while the kiss channel is held, with a soft repeat sound.
func _kiss_tick(delta: float) -> void:
	var holding := _kiss_visible()
	if _base_kiss_releasing:
		var releasing_affection := _base_kiss_affection
		if is_instance_valid(releasing_affection) and float(releasing_affection.get("amount")) > 0.2:
			holding = true
	_kiss_lean = move_toward(_kiss_lean, 1.0 if holding else 0.0, delta / KISS_LEAN_SECONDS)
	if _kiss_lean <= 0.0001 and not holding:
		_clear_side()
	if _base_kiss_releasing:
		var affection := _base_kiss_affection
		if not is_instance_valid(affection) or float(affection.get("amount")) <= 0.001:
			_restore_base_kiss_pose()
	if _base_kiss_active:
		_kiss_diag_clock -= delta
		if _kiss_diag_clock <= 0.0:
			_kiss_diag_clock = 1.0
			_kiss_diag()
		_update_base_kiss(delta)
		_kiss_amount = move_toward(_kiss_amount, 0.0, delta / KISS_FADE_OUT)
		return
	var active := _lean_kiss_active and _custom_kiss_active
	var target := 1.0 if active else 0.0
	var seconds := KISS_FADE_IN if target > _kiss_amount else KISS_FADE_OUT
	_kiss_amount = move_toward(_kiss_amount, target, delta / maxf(seconds, 0.001))
	if _kiss_amount <= 0.0001:
		_kiss_amount = 0.0
		return
	if not is_instance_valid(pony):
		return
	var face_view := WORLD.face(pony)
	if face_view.controller() != null:
		face_view.touch("affection", 0.25 * _kiss_amount, (1.0 - 0.05) * _kiss_amount)
	face_view.set_expression("pout", 0.18 * _kiss_amount)
	face_view.set_expression("open_soft", 0.025 * _kiss_amount)
	if not active:
		return
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		facts.call_value(facts.play_mouth_kiss)
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


## The player kisser is paused for the whole act, so it cannot write these itself. Feed the base
## kiss the live mouth/eye/face and its repeat sound, exactly as pony_kisser would.
func _update_base_kiss(delta: float) -> void:
	var affection := _base_kiss_affection
	if is_instance_valid(affection):
		var view := _mouth_view()
		if is_instance_valid(view):
			WORLD.affection().feed(affection, _target(view), view.global_position,
				view.global_basis.orthonormalized())
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		facts.call_value(facts.play_mouth_kiss)
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


## Once a second while a base kiss runs: confirms she is on the latched side and whether any
## remaining clip is a joint limit, a reach miss, or Anon's eye clearance pushing her back.
func _kiss_diag() -> void:
	var affection := _base_kiss_affection
	if not is_instance_valid(affection):
		return
	var pose: Variant = affection.get("pose")
	var pose_side := 0.0
	var limited := 0.0
	var miss := 0.0
	var cleared := ""
	if pose != null:
		pose_side = float(pose.get("_side_now"))
		limited = rad_to_deg(float(pose.get("limited")))
		miss = float(pose.get("miss"))
		cleared = str(pose.get("cleared_by"))
	var cam_roll := 0.0
	var head_roll := 0.0
	var skull_lateral := 0.0
	var mouth_gap := -1.0
	var view := _mouth_view()
	if is_instance_valid(view):
		var target := _target(view)
		var right := view.global_basis.x.normalized()
		var mouth := WORLD.pony(pony).mouth_point(affection)
		if mouth.is_finite():
			mouth_gap = mouth.distance_to(target)
		var skull := WORLD.pony(pony).skull_world() if is_instance_valid(pony) else Vector3.INF
		if skull.is_finite():
			skull_lateral = (skull - target).dot(right)
		var camera: Camera3D = facts.camera
		cam_roll = rad_to_deg(camera.rotation.z) if is_instance_valid(camera) else 0.0
		var skeleton := WORLD.pony(pony).skeleton() if is_instance_valid(pony) else null
		if skeleton != null:
			var head_bone := skeleton.find_bone("pony_head")
			if head_bone >= 0:
				var head_t := skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
				var up := head_t.basis.y.normalized()
				var view_up := view.global_basis.y.normalized()
				head_roll = rad_to_deg(up.signed_angle_to(view_up, -view.global_basis.z.normalized()))
	LOG.debug("kiss diag base=%s custom=%s amount=%.2f lean=%.2f cam_side=%.2f pony_side=%.2f pose_side=%.2f cam_roll=%.1f head_roll=%.1f skull_lat=%.3f gap=%.3f limited=%.1fdeg miss=%.3fm clear=%s lateral=%.3f", [
		str(_base_kiss_active), str(_custom_kiss_active),
		float(affection.get("amount")), _kiss_lean, _kiss_camera_side, _kiss_pony_side,
		pose_side, cam_roll, head_roll, skull_lateral, mouth_gap,
		limited, miss, cleared,
		lateral_offset(float(facts.standing_lean_scale)) if _pose_family() == "standing" else 0.0])


func _target(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	# Missionary's Anon is the authored body on the bed, not the standing player rig the game camera
	# still belongs to: aim her at his posed mouth, never at that camera.
	if _pose_family() == "bed":
		var raw: Variant = facts.missionary_body()
		var body := raw as POSES.PoseActBody
		if body != null and body.live():
			var mouth := body.mouth_point()
			if mouth.is_finite():
				return mouth
	var point: Vector3 = view.global_position + view.global_basis \
		* (Vector3(0.0, -0.07, -0.02) * float(facts.anon_height_scale))
	if _pose_family() == "standing":
		point = view.global_position + view.global_basis * _kiss_mouth_offset()
	return point


## Anon's actual mouth camera. Missionary frames the shot through a separate view, so using that as
## the kiss target aimed her at the camera instead of at him.
func _mouth_view() -> Camera3D:
	if is_instance_valid(WORLD.world_root()):
		var view: Camera3D = WORLD.camera()
		if is_instance_valid(view):
			return view
	return facts.camera as Camera3D


func _release_kiss_face() -> void:
	if not is_instance_valid(pony):
		return
	var face_view := WORLD.face(pony)
	if face_view.controller() != null:
		face_view.release_touch("affection")
	face_view.set_expression("pout", 0.0)
	face_view.set_expression("open_soft", 0.0)


## Shared shoulder touch point. The lean reach and the full-lean caress must use exactly the
## same point so their hands coincide.

static func standing_kiss_wanted(key_down: bool, lean: float) -> bool:
	return key_down and absf(lean) >= STANDING_KISS_LEAN


func end_lean_kiss() -> void:
	if not _lean_kiss_active:
		return
	_lean_kiss_active = false
	_lean_kiss_used = false
	_lean_kiss_ready_at = Time.get_ticks_msec() + KISS_RESTART_COOLDOWN_MS
	_end_base_kiss()
	_custom_kiss_active = false
	_release_kiss_face()
	# Releasing the kiss must not leave the shoulder reach's forced over-the-shoulder glance
	# latched while F is still held.
	facts.write_forced_glance("")
	var cam: Variant = facts.view_controller()
	cam.clear_glance()
	LOG.debug("standing kiss stop")


## Read the live scene handles and configs from the typed act view. The runtime rewrites the
## view before it hands the controller out, so this is a copy, not a read of the runtime node.
func _sync() -> void:
	if facts == null:
		pony = null
		_presentation_cfg = {}
		_pose_cfg = {}
		return
	pony = facts.pony
	var cfg: Variant = facts.presentation_config
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var view := _pose_view()
	var pose_cfg: Variant = view.from_config if view != null else null
	if not pose_cfg is Dictionary or (pose_cfg as Dictionary).is_empty():
		pose_cfg = view.pose_config if view != null else null
	_pose_cfg = pose_cfg if pose_cfg is Dictionary else {}


func _init(facts_context: ACT_FACTS = null) -> void:
	facts = facts_context


func tick(delta: float) -> void:
	_sync()
	_kiss_tick(delta)
	_pin_base_side()


func reset() -> void:
	end_lean_kiss()
	_end_base_kiss()
	_custom_kiss_active = false
	_clear_side()
	_release_kiss_face()
	_restore_base_kiss_pose()


func eyes_active() -> bool:
	return _base_kiss_active or _base_kiss_releasing or _lean_kiss_active \
		or _kiss_amount > 0.05


func leaning_close() -> bool:
	return _kiss_amount > 0.05 or _base_kiss_active or _base_kiss_releasing \
		or _lean_kiss_active


func base_active() -> bool:
	return _base_kiss_active or _base_kiss_releasing


func standing_active() -> bool:
	return _lean_kiss_active


func custom_visible() -> bool:
	return _kiss_amount > 0.001 and not _base_kiss_active


func amount() -> float:
	return _kiss_amount


func lean() -> float:
	return _kiss_lean


func side() -> float:
	return _side()


func lean_distance() -> float:
	return _kiss_lean_distance()


func lean_drop() -> float:
	return _kiss_lean_drop()


func camera_yaw_deg() -> float:
	return _kiss_camera_yaw_deg()


func mouth_view() -> Camera3D:
	return _mouth_view()


func target(view: Camera3D) -> Vector3:
	return _target(view)


func apply_live_settings() -> void:
	_sync()
	if _base_kiss_active:
		_apply_kiss_forelegs()
	elif _kiss_forelegs_planted:
		_restore_kiss_forelegs()
		_stop_kiss_leg_pin()


func restore_forelegs() -> void:
	_restore_kiss_forelegs()
	_stop_kiss_leg_pin()


## F held at a full lean kisses: a shoulder lean in standing, a front lean in missionary. Called
## every physics tick by the runtime for both poses.
func lean_kiss_tick() -> void:
	_sync()
	var phase := _kiss_profile()
	if not bool(facts.call_value(facts.act_actions_allowed, false)) \
			or _pose_family() not in ["bed", "standing"]:
		_lean_kiss_used = false
		end_lean_kiss()
		return
	var f_held := Input.is_physical_key_pressed(KEY_F) \
		and not bool(facts.call_value(facts.auto_panel_open, false))
	var want := false
	if phase == "standing":
		want = standing_kiss_wanted(f_held, float(facts.lean_side))
	else:
		# The lean map folds a side press into the forward target, so the forward lean alone cannot
		# tell a side-only lean from a real one; the explicit key keeps a side lean from kissing.
		want = f_held and Input.is_action_pressed("move_forward") \
			and float(facts.lean_forward) >= MISSIONARY_KISS_LEAN
	if not want:
		_lean_kiss_used = false
		end_lean_kiss()
		return
	if _lean_kiss_active:
		if _base_kiss_active:
			var affection := _base_kiss_affection
			if not is_instance_valid(affection) or str(affection.get("kind")) != "kiss":
				end_lean_kiss()
		elif not _custom_kiss_active:
			end_lean_kiss()
		return
	if _lean_kiss_used or Time.get_ticks_msec() < _lean_kiss_ready_at:
		return
	_lean_kiss_used = true
	_lean_kiss_active = true
	facts.write_forced_glance("")
	_latch_side(float(facts.lean_side))
	_custom_kiss_active = not _start_base_kiss()
	if _custom_kiss_active:
		facts.call_value(facts.play_mouth_kiss)
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
	facts.touch("kiss")
	LOG.debug("lean kiss start pose=%s forward=%.2f side=%.2f pony_side=%.2f lateral=%.3f base=%s", [
		phase, float(facts.lean_forward), float(facts.lean_side),
		_kiss_pony_side, lateral_offset(float(facts.standing_lean_scale)),
		str(_base_kiss_active)])


