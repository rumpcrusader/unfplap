extends RefCounted
## Missionary and standing kiss. The runtime owns the act state; this controller owns the base
## AffectionPose bridge, the custom mouth aim, the foreleg pin and the kiss lean.

const AFFECTION_POSE := preload("res://world/relationships/affection_pose.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const KISS_LEGS := preload("res://mods/unfplap/kiss_legs.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
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
const STANDING_KISS_LEAN := 0.90
## Front lean needed in missionary. W must be held too, because `lean_targets` adds `|side|` to the
## forward lean, and a pure side lean must not pull the kiss.
const MISSIONARY_KISS_LEAN := 0.90

var runtime: Node
var pony: Variant
var main: Variant
var _presentation_cfg: Dictionary = {}
var _pose_cfg: Dictionary = {}

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
var _base_kiss_beat: Timer
var _base_kiss_beat_paused := false
var _kiss_forelegs_planted := false
var _kiss_saved_rear := 1.0
var _kiss_saved_hooves := 1.0
var _kiss_leg_pin: Node

func _apply_kiss_forelegs() -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING:
		return
	if _kiss_forelegs_planted:
		return
	var settings := AFFECTION_POSE.kiss_settings()
	_kiss_saved_rear = float(settings.get("rear", 1.0))
	_kiss_saved_hooves = float(settings.get("hooves", 1.0))
	settings["rear"] = 0.0
	settings["hooves"] = 0.0
	_kiss_forelegs_planted = true
	_log("kiss forelegs planted")


func _restore_kiss_forelegs() -> void:
	if not _kiss_forelegs_planted:
		return
	var settings := AFFECTION_POSE.kiss_settings()
	settings["rear"] = _kiss_saved_rear
	settings["hooves"] = _kiss_saved_hooves
	_kiss_forelegs_planted = false


## The base kiss's chest flex runs after body_sway's upper-arm pin. This extra modifier runs
## last and brings the visible hoof tips back to where they were before the kiss.
func _start_kiss_leg_pin() -> void:
	if str(runtime.get("pose_id")) != CATALOG.STANDING:
		return
	if is_instance_valid(_kiss_leg_pin) or not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	_kiss_leg_pin = KISS_LEGS.new()
	_kiss_leg_pin.name = "UnfplapKissLegPin"
	_kiss_leg_pin.set("mare", pony)
	_kiss_leg_pin.set("runtime", runtime)
	skeleton.add_child(_kiss_leg_pin)
	skeleton.move_child(_kiss_leg_pin, skeleton.get_child_count() - 1)
	_kiss_leg_pin.call("capture")
	_log("kiss foreleg pin captured")


func _stop_kiss_leg_pin() -> void:
	if is_instance_valid(_kiss_leg_pin):
		_kiss_leg_pin.queue_free()
	_kiss_leg_pin = null


## Reuse the game's own kiss in standing. `pony_kisser.begin_from_pony()` runs the same eligibility
## checks as a normal Ponese kiss, including `controls_locked`, so unlock for that one call only.
## The AffectionPose modifier is moved to the end of the skeleton chain so its kiss IK layers on
## top of the act pose instead of being overwritten by it. Missionary always returns false here.
func _start_base_kiss() -> bool:
	# The stock kiss pose is authored for a standing pony. On the bed its chest/neck give lifts
	# the lying body off the mattress and turns her head across it, so missionary uses the act's own
	# head aim instead.
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(main) \
			or not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	var affection: Variant = pony.get_node_or_null("Affection")
	var kisser: Variant = main.game.get("kisser")
	if not is_instance_valid(affection) or not is_instance_valid(kisser):
		return false
	if not str(affection.get("kind")).is_empty():
		return false
	var body: Node = main.player
	var was_locked: bool = body.get("controls_locked") == true
	body.set("controls_locked", false)
	var begun := bool(kisser.call("begin_from_pony", pony))
	body.set("controls_locked", was_locked)
	if not begun:
		return false
	_apply_kiss_forelegs()
	_base_kiss_active = true
	_base_kiss_releasing = false
	_base_kiss_affection = affection
	_suppress_base_kiss_excitement()
	var pose_node: Variant = affection.get("pose")
	var sk: Variant = pony.get("skeleton")
	if pose_node is SkeletonModifier3D and sk is Skeleton3D:
		var index := (sk as Skeleton3D).get_children().find(pose_node)
		if index >= 0:
			_base_kiss_pose = pose_node as SkeletonModifier3D
			_base_kiss_pose_index = index
			(sk as Skeleton3D).move_child(_base_kiss_pose, (sk as Skeleton3D).get_child_count() - 1)
			_pin_base_side()
	_start_kiss_leg_pin()
	_log("base kiss start pony=%s" % str(runtime.get("_id")))
	return true


func _end_base_kiss() -> void:
	if not _base_kiss_active:
		return
	_base_kiss_active = false
	_restore_base_kiss_excitement()
	var affection: Variant = _base_kiss_affection
	if is_instance_valid(affection):
		if str(affection.get("kind")) == "kiss":
			affection.call("end")
		# Even if the affection already ended itself, clear its 60 s stare afterglow.
		affection.call("cancel_afterglow")
	if is_instance_valid(main) and is_instance_valid(main.game):
		var kisser: Variant = main.game.get("kisser")
		if is_instance_valid(kisser):
			kisser.set("_active", null)
			kisser.set("_her_kiss", false)
			kisser.set("_used_hold", false)
	if is_instance_valid(main) and is_instance_valid(main.player) \
			and int(runtime.get("state")) in [STATE_ACTIVE, STATE_CLIMAX]:
		main.player.set_meta("kiss_hold", true)
	_base_kiss_releasing = is_instance_valid(_base_kiss_pose)
	if not _base_kiss_releasing:
		_base_kiss_affection = null
		_restore_kiss_forelegs()
		_stop_kiss_leg_pin()


## Keep the AffectionPose last while its own 0.6 s release eases out, then restore the child order.
func _restore_base_kiss_pose() -> void:
	_restore_kiss_forelegs()
	_stop_kiss_leg_pin()
	if is_instance_valid(_base_kiss_pose) and _base_kiss_pose.get("_side_wait") != null:
		_base_kiss_pose.set("_side_wait", 0.0)
	_base_kiss_releasing = false
	if is_instance_valid(_base_kiss_pose) and is_instance_valid(pony):
		var sk: Variant = pony.get("skeleton")
		if sk is Skeleton3D:
			var skeleton := sk as Skeleton3D
			var index := clampi(_base_kiss_pose_index, 0, skeleton.get_child_count() - 1)
			skeleton.move_child(_base_kiss_pose, index)
	_base_kiss_pose = null
	_base_kiss_pose_index = -1
	_base_kiss_affection = null
	_restore_base_kiss_excitement()
	runtime.call("_keep_chin_last")


## A base kiss otherwise triggers the stock unicorn horn sparkle and flutter beat. Keep the beat
## paused for the kiss so a kiss does not read as spellcasting.
func _suppress_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_excitement) or not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	_base_kiss_excitement = excitement as Node
	var beat: Variant = _base_kiss_excitement.get_node_or_null("Beat")
	if beat is Timer:
		_base_kiss_beat = beat as Timer
		_base_kiss_beat_paused = _base_kiss_beat.paused
		_base_kiss_beat.paused = true
	_base_kiss_excitement.set("_until", 0.0)


func _restore_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_beat):
		_base_kiss_beat.paused = _base_kiss_beat_paused
	_base_kiss_beat = null
	_base_kiss_excitement = null
	_base_kiss_beat_paused = false


func _kiss_visible() -> bool:
	if _base_kiss_active:
		return true
	return _lean_kiss_active and _custom_kiss_active


## Standing kiss controls. Missionary keeps the fixed constants.
func _kiss_controls() -> Dictionary:
	if str(runtime.get("pose_id")) != CATALOG.STANDING:
		return {}
	var kiss: Variant = _presentation_cfg.get("kiss", {})
	return kiss if kiss is Dictionary else {}


func _kiss_mouth_offset() -> Vector3:
	var kiss := _kiss_controls()
	var scale: float = float(runtime.call("_anon_height_scale"))
	return Vector3(
		float(kiss.get("mouth_right", 0.0)),
		-float(kiss.get("mouth_drop", 0.07)),
		-float(kiss.get("mouth_forward", 0.02))) * scale


func _kiss_camera_yaw_deg() -> float:
	return float(_kiss_controls().get("camera_yaw_deg", KISS_CAMERA_YAW_DEG))


func _kiss_lean_side() -> float:
	return float(_kiss_controls().get("lean_side", KISS_LEAN_SIDE_M)) * runtime.call("_anon_height_scale")


func _kiss_lean_forward() -> float:
	return float(_kiss_controls().get("lean_forward", KISS_LEAN_M)) * runtime.call("_anon_height_scale")


func _kiss_lean_drop() -> float:
	return float(_kiss_controls().get("lean_drop", KISS_LEAN_DROP_M)) * runtime.call("_anon_height_scale")


func _kiss_lean_distance() -> float:
	return _kiss_lean_forward() * _kiss_lean


## The act kiss follows the side Anon leaned to; outside a latched kiss fall back to live input.
func _side() -> float:
	if absf(_kiss_camera_side) > 0.5:
		return _kiss_camera_side
	if absf(float(runtime.get("_lean_view_side"))) > 0.01:
		return signf(float(runtime.get("_lean_view_side")))
	if absf(float(runtime.get("_lean_action_side"))) > 0.01:
		return signf(float(runtime.get("_lean_action_side")))
	return 0.0


## `AffectionPose` wants the opposite sign: she must lean toward the same world side Anon moved to.
static func kiss_pony_side(lean_side: float) -> float:
	if absf(lean_side) <= 0.001:
		return 0.0
	return KISS_PONY_SIDE_SIGN * signf(lean_side)


## Lateral shot/hip travel. The lean offset hands over to the single kiss offset as the kiss
## blends in, instead of adding both (0.18 m + 0.18 m is further sideways than her neck reaches,
## and the clearance pass then pushed her muzzle back into him).
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
	return _kiss_lateral_offset(float(runtime.get("_lean_view_side")), _side(), _kiss_lean, lean_scale)


func _latch_side(side: float = NAN) -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0
	# Latch the requested lean, not the inertia-smoothed view: switching sides and pressing F
	# immediately must not keep the previous side for the whole kiss.
	var lean := float(runtime.get("_lean_side")) if is_nan(side) else side
	if absf(lean) <= 0.01:
		lean = float(runtime.get("_lean_action_side"))
	if absf(lean) <= 0.01:
		lean = float(runtime.get("_lean_view_side"))
	if absf(lean) <= 0.01:
		return
	_kiss_camera_side = signf(lean)
	_kiss_pony_side = kiss_pony_side(_kiss_camera_side)


func _clear_side() -> void:
	_kiss_camera_side = 0.0
	_kiss_pony_side = 0.0
	_kiss_diag_clock = 0.0


## Pin the game's AffectionPose to the side Anon leaned to. The stock kiss picks and switches
## sides on its own; the act keeps her on the complementary side so their heads interlock.
## Private AffectionPose fields are the only side switch the script exposes, so this is done
## from the mod and quietly skipped if a future game update renames them.
func _pin_base_side() -> void:
	if not _base_kiss_active or not is_instance_valid(_base_kiss_pose):
		return
	if absf(_kiss_pony_side) <= 0.5:
		return
	if _base_kiss_pose.get("_side") == null:
		return
	_base_kiss_pose.set("_side", _kiss_pony_side)
	_base_kiss_pose.set("_side_now", _kiss_pony_side)
	_base_kiss_pose.set("_side_wait", 9999.0)


## Her mouth stays at Anon's lips while the kiss channel is held, with a soft repeat sound.
func _kiss_tick(delta: float) -> void:
	var holding := _kiss_visible()
	if _base_kiss_releasing:
		var releasing_affection: Variant = _base_kiss_affection
		if is_instance_valid(releasing_affection) and float(releasing_affection.get("amount")) > 0.2:
			holding = true
	_kiss_lean = move_toward(_kiss_lean, 1.0 if holding else 0.0, delta / KISS_LEAN_SECONDS)
	if _kiss_lean <= 0.0001 and not holding:
		_clear_side()
	if _base_kiss_releasing:
		var affection: Variant = _base_kiss_affection
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
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("touch"):
		expressions.call("touch", "affection", 0.25 * _kiss_amount,
			(1.0 - 0.05) * _kiss_amount)
	var head: Variant = pony.get("head")
	var mouth: Variant = head.get("mouth") if head != null else null
	if mouth != null:
		mouth.call("set_expression", "pout", 0.18 * _kiss_amount)
		mouth.call("set_expression", "open_soft", 0.025 * _kiss_amount)
	if not active:
		return
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		runtime.call("_play_mouth_kiss")
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


## The player kisser is paused for the whole act, so it cannot write these itself. Feed the base
## kiss the live mouth/eye/face and its repeat sound, exactly as pony_kisser would.
func _update_base_kiss(delta: float) -> void:
	var affection: Variant = _base_kiss_affection
	if is_instance_valid(affection):
		var view := _mouth_view()
		if is_instance_valid(view):
			affection.set("target", _target(view))
			affection.set("eye", view.global_position)
			affection.set("face", view.global_basis.orthonormalized())
	_kiss_sound_clock -= delta
	if _kiss_sound_clock <= 0.0:
		runtime.call("_play_mouth_kiss")
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)


## Once a second while a base kiss runs: confirms she is on the latched side and whether any
## remaining clip is a joint limit, a reach miss, or Anon's eye clearance pushing her back.
func _kiss_diag() -> void:
	var affection: Variant = _base_kiss_affection
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
		if affection.has_method("mouth_point"):
			var mouth: Variant = affection.call("mouth_point")
			if mouth is Vector3 and (mouth as Vector3).is_finite():
				mouth_gap = (mouth as Vector3).distance_to(target)
		var boop: Variant = pony.get("boop_node") if is_instance_valid(pony) else null
		if boop != null and boop.has_method("skull_world"):
			var skull: Variant = boop.call("skull_world")
			if skull is Vector3:
				skull_lateral = ((skull as Vector3) - target).dot(right)
		var camera: Variant = runtime.get("_camera")
		cam_roll = rad_to_deg(camera.rotation.z) if is_instance_valid(camera) else 0.0
		var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
		if sk is Skeleton3D:
			var skeleton := sk as Skeleton3D
			var head_bone := skeleton.find_bone("pony_head")
			if head_bone >= 0:
				var head_t := skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
				var up := head_t.basis.y.normalized()
				var view_up := view.global_basis.y.normalized()
				head_roll = rad_to_deg(up.signed_angle_to(view_up, -view.global_basis.z.normalized()))
	_log("kiss diag base=%s custom=%s amount=%.2f lean=%.2f cam_side=%.2f pony_side=%.2f pose_side=%.2f cam_roll=%.1f head_roll=%.1f skull_lat=%.3f gap=%.3f limited=%.1fdeg miss=%.3fm clear=%s lateral=%.3f" % [
		str(_base_kiss_active), str(_custom_kiss_active),
		float(affection.get("amount")), _kiss_lean, _kiss_camera_side, _kiss_pony_side,
		pose_side, cam_roll, head_roll, skull_lateral, mouth_gap,
		limited, miss, cleared,
		lateral_offset(float(runtime.call("_standing_lean_scale"))) if str(runtime.get("pose_id")) == CATALOG.STANDING else 0.0])


func _target(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	# Missionary's Anon is the authored body on the bed, not the standing player rig the game camera
	# still belongs to: aim her at his posed mouth, never at that camera.
	if str(runtime.get("pose_id")) == CATALOG.MISSIONARY:
		var body: Variant = runtime.call("missionary_anon_body")
		if body != null and bool(body.get("active")):
			var mouth: Variant = body.call("mouth_point")
			if mouth is Vector3 and (mouth as Vector3).is_finite():
				return mouth
	var point: Vector3 = view.global_position + view.global_basis \
		* (Vector3(0.0, -0.07, -0.02) * runtime.call("_anon_height_scale"))
	if str(runtime.get("pose_id")) == CATALOG.STANDING:
		point = view.global_position + view.global_basis * _kiss_mouth_offset()
	return point


## Anon's actual mouth camera. Missionary frames the shot through a separate view, so using that as
## the kiss target aimed her at the camera instead of at him.
func _mouth_view() -> Camera3D:
	if is_instance_valid(main):
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			return view
	return runtime.get("_camera") as Camera3D



func _release_kiss_face() -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("release_touch"):
		expressions.call("release_touch", "affection")
	var head: Variant = pony.get("head")
	var mouth: Variant = head.get("mouth") if head != null else null
	if mouth != null:
		mouth.call("set_expression", "pout", 0.0)
		mouth.call("set_expression", "open_soft", 0.0)


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
	runtime.set("_forced_glance", "")
	var cam: Variant = runtime.call("_standing_camera_controller")
	cam.clear_glance()
	_log("standing kiss stop")




func _sync() -> void:
	pony = runtime.get("pony") if is_instance_valid(runtime) else null
	main = runtime.get("main") if is_instance_valid(runtime) else null
	var cfg: Variant = runtime.get("_presentation_cfg") if is_instance_valid(runtime) else null
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var pose_cfg: Variant = runtime.get("_pose_cfg") if is_instance_valid(runtime) else null
	_pose_cfg = pose_cfg if pose_cfg is Dictionary else {}


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


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
	var phase := str(runtime.get("pose_id"))
	if not bool(runtime.call("_act_actions_allowed")) \
			or phase not in [CATALOG.STANDING, CATALOG.MISSIONARY]:
		_lean_kiss_used = false
		end_lean_kiss()
		return
	var f_held := Input.is_physical_key_pressed(KEY_F) \
		and not (runtime.has_method("auto_panel_open") and bool(runtime.call("auto_panel_open")))
	var want := false
	if phase == CATALOG.STANDING:
		want = standing_kiss_wanted(f_held, float(runtime.get("_lean_side")))
	else:
		want = f_held and Input.is_action_pressed("move_forward") \
			and float(runtime.get("_lean_forward")) >= MISSIONARY_KISS_LEAN
	if not want:
		_lean_kiss_used = false
		end_lean_kiss()
		return
	if _lean_kiss_active:
		if _base_kiss_active:
			var affection: Variant = _base_kiss_affection
			if not is_instance_valid(affection) or str(affection.get("kind")) != "kiss":
				end_lean_kiss()
		elif not _custom_kiss_active:
			end_lean_kiss()
		return
	if _lean_kiss_used or Time.get_ticks_msec() < _lean_kiss_ready_at:
		return
	_lean_kiss_used = true
	_lean_kiss_active = true
	runtime.set("_forced_glance", "")
	_latch_side(float(runtime.get("_lean_side")))
	_custom_kiss_active = not _start_base_kiss()
	if _custom_kiss_active:
		runtime.call("_play_mouth_kiss")
		_kiss_sound_clock = randf_range(KISS_SOUND_MIN, KISS_SOUND_MAX)
	runtime.call("_on_touch", "kiss")
	_log("lean kiss start pose=%s forward=%.2f side=%.2f pony_side=%.2f lateral=%.3f base=%s" % [
		phase, float(runtime.get("_lean_forward")), float(runtime.get("_lean_side")),
		_kiss_pony_side, lateral_offset(float(runtime.call("_standing_lean_scale"))),
		str(_base_kiss_active)])


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
