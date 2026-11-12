extends RefCounted
## Idle standing invitation and request face. This is not the act: no camera, player lock,
## HUD or sex_active. The runtime only forwards the public calls.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")

const PRESENT_TURN_RATE := 2.4
const PRESENT_FACE_TURN_RATE := 1.5
const PRESENT_TURN_SETTLE_RAD := 0.06
const PRESENT_TURN_TIMEOUT_S := 4.0
const PRESENT_TURN_STALL_S := 0.75
## Safety cap: the invitation owns her body, so no missed end path may leave the pose on forever.
## Longer than the invite wait plus the turn.
const PRESENT_MAX_SECONDS := 75.0
const REQUEST_LIDS := 0.45
const REQUEST_BLUSH := 1.0
const STATE_IDLE := 0

var facts: Variant
var main: Variant
var pony: Variant
var _pose_cfg: Dictionary = {}

var _presenting := false
var _present_turning := false
var _present_turn_started := 0.0
var _present_turn_last_yaw := 0.0
var _present_turn_still := 0.0
var _present_turn_rate_saved := -1.0
var _present_turn_rate_owned := false
var _present_pose
var _present_glance_back := false
var _present_glance_sign := 1.0
var _present_glance_sign_set := false
var _present_tail
var _present_started := 0.0
var _present_yaw := 0.0
var _present_target_yaw := 0.0
var _present_look_point := Vector3.ZERO
var _present_face_direction := Vector3.ZERO
var _request_face := false
var _request_claimed_affection := false

func present_standing() -> bool:
	_sync()
	if _presenting or _present_turning:
		return true
	if int(facts.state) != STATE_IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or bool(facts.call_value(facts.cuddle_active, false)):
		return false
	if not bool(facts.call_value(facts.free_of_affection, true)):
		return false
	var service: ELIGIBILITY = main.get("eligibility") if is_instance_valid(main) else null
	if service == null or not service.eligible(pony, ELIGIBILITY.Target.ACT):
		return false
	if not facts.offer_allowed(CATALOG.STANDING, ""):
		return false
	if not _request_face:
		set_request_face(true)
	var player: Variant = main.player
	var view: Camera3D = main.camera()
	var target: Vector3 = pony.global_position - Vector3.FORWARD
	if is_instance_valid(view):
		target = view.global_position
	elif is_instance_valid(player):
		target = player.global_position
	var away: Vector3 = pony.global_position - target
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = pony.global_basis.z
	away = away.normalized()
	_present_target_yaw = atan2(-away.x, -away.z)
	_present_yaw = pony.rotation.y
	_present_look_point = target
	_present_face_direction = away
	if pony.has_method("request_posture") and str(pony.posture_status().get("requested", "")) != "stand":
		pony.request_posture("stand")
	_present_turn_started = facts.clock()
	_present_started = _present_turn_started
	_present_turn_last_yaw = pony.rotation.y
	_present_turn_still = 0.0
	if pony.has_method("face_direction") and pony.get("face_turn_rate") != null:
		_present_turning = true
		_begin_present_turn()
	else:
		# Unusual actor without the locomotion turn: keep the old direct-rotation fallback.
		_present_turning = false
		_attach_present_pose()
		facts.pause_face(true)
	_log("present standing target_yaw=%.2f turn=%s" % [
		_present_target_yaw, "stepping" if _present_turning else "direct"])
	return true


## Create the idle pose and tail once she has finished turning. Doing this before the turn
## let the spread/bow pose fight the planted hooves and twisted the legs.

func _attach_present_pose() -> void:
	if not is_instance_valid(pony):
		return
	_pose_cfg = SETTINGS.pose(str(facts.pony_id), CATALOG.STANDING)
	# The act stance bows and bends the forelegs for the thrust; seen from behind it reads as her
	# front legs tucked between her hind. The invitation is a natural stand with the rump
	# presented, so the act-only bow, foreleg bend and wide hind stance are removed.
	_pose_cfg["bow"] = 0.0
	_pose_cfg["foreleg"] = 0.0
	_pose_cfg["foreleg_spread"] = 0.172
	_pose_cfg["hind_spread"] = 0.0
	var presentation_cfg: Dictionary = SETTINGS.block("presentation.standing.")
	_pose_cfg["chin_up_deg"] = float(presentation_cfg.get("chin_up_deg", 30.0))
	_pose_cfg["neck_down_deg"] = float(presentation_cfg.get("neck_down_deg", 15.0))
	var tail_cfg: Variant = presentation_cfg.get("tail", {})
	if tail_cfg is Dictionary:
		_pose_cfg["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary).get("yaw_deg", 31.5)))
		_pose_cfg["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary).get("pitch_deg", 24.1)))
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_present_pose = POSE.new()
		_present_pose.name = "UnfplapPresentPose"
		_present_pose.mare = pony
		_present_pose.mode = "standing"
		_present_pose.pose_config = _pose_cfg
		_present_pose.look_point = _present_look_point
		_present_pose.amount = 0.0
		_present_pose.target_amount = 1.0
		(skeleton as Skeleton3D).add_child(_present_pose)
		facts.call_value(facts.keep_chin_last)
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_present_tail = TAIL.new()
		_present_tail.name = "UnfplapPresentTail"
		_present_tail.mare = pony
		_present_tail.runtime = self
		_present_tail.aside_angle = float(_pose_cfg.get("tail_aside", 0.55))
		_present_tail.lift_angle = float(_pose_cfg.get("tail_lift", 0.42))
		_present_tail.amount = 0.0
		_present_tail.target_amount = 1.0
		var side_anchor := Vector3.INF
		var main_v: Variant = facts.main if facts != null else null
		if main_v != null and main_v.has_method("camera"):
			var view: Variant = main_v.call("camera")
			if view is Camera3D:
				side_anchor = (view as Camera3D).global_position
		_present_tail.call("choose_side", side_anchor)
		(hair as Skeleton3D).add_child(_present_tail)
	_presenting = true
	_present_glance_back = true
	_present_glance_sign_set = false



func _begin_present_turn() -> void:
	if not is_instance_valid(pony) or not pony.has_method("face_direction"):
		return
	var rate: Variant = pony.get("face_turn_rate")
	if rate != null:
		_present_turn_rate_saved = float(rate)
		_present_turn_rate_owned = true
		pony.set("face_turn_rate", maxf(_present_turn_rate_saved, PRESENT_FACE_TURN_RATE))
	pony.call("face_direction", _present_face_direction)



func _restore_present_turn_rate() -> void:
	if _present_turn_rate_owned and is_instance_valid(pony):
		pony.set("face_turn_rate", _present_turn_rate_saved)
	_present_turn_rate_owned = false
	_present_turn_rate_saved = -1.0



func _finish_present_turn() -> void:
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", Vector3.ZERO)
	_restore_present_turn_rate()
	_present_turning = false
	if is_instance_valid(pony):
		var error := absf(wrapf(pony.rotation.y - _present_target_yaw, -PI, PI))
		if error > PRESENT_TURN_SETTLE_RAD:
			# The stepping turn could not finish (blocked feet, touch, wall). Snap once here
			# rather than letting the old static-lock path rotate the body under planted feet.
			var t: Transform3D = pony.global_transform
			var scale := t.basis.get_scale()
			t.basis = Basis(Vector3.UP, _present_target_yaw).scaled(scale)
			pony.global_transform = t
			_present_yaw = _present_target_yaw
			_log("present standing turn snap error=%.2f target=%.2f" % [error, _present_target_yaw])
		else:
			_present_yaw = pony.rotation.y
			_present_target_yaw = _present_yaw
			_log("present standing turn settled yaw=%.2f" % _present_yaw)
	if not _presenting:
		_attach_present_pose()
	facts.pause_face(true)



func presentation_active() -> bool:
	return _presenting or _present_turning


## True once the stepping turn is done and the idle pose is attached. The post-accept line
## waits for this so she comments after taking the position, not while still turning into it.

func presentation_settled() -> bool:
	if not _presenting or _present_turning:
		return false
	return absf(wrapf(_present_yaw - _present_target_yaw, -PI, PI)) <= 0.05



func clear_presentation() -> void:
	_sync()
	if _present_turning:
		if is_instance_valid(pony) and pony.has_method("face_direction"):
			pony.call("face_direction", Vector3.ZERO)
		_restore_present_turn_rate()
		_present_turning = false
	if is_instance_valid(_present_pose):
		_present_pose.queue_free()
	_present_pose = null
	if is_instance_valid(_present_tail):
		_present_tail.queue_free()
	_present_tail = null
	_presenting = false
	_present_glance_back = false
	_present_glance_sign_set = false
	facts.restore_face()



func _presentation_valid() -> bool:
	if not _presenting or int(facts.state) != STATE_IDLE:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or pony.has_meta("seated"):
		return false
	if bool(facts.call_value(facts.cuddle_active, false)) or not bool(facts.call_value(facts.free_of_affection, true)):
		return false
	if not pony.grounded():
		return false
	var status: Dictionary = pony.posture_status()
	if str(status.get("requested", "")) != "stand":
		return false
	if float(pony.actual_speed) > 0.10:
		return false
	var player: Variant = main.player
	if is_instance_valid(player) and player.global_position.distance_to(pony.global_position) > 8.0:
		return false
	return true


## Turn her away in place and stop conversation facing from taking the body back. Runs late in
## physics, after the navigator and locomotion, like the act's standing facing lock.

func _presentation_physics(delta: float) -> void:
	if _present_turning:
		_presentation_turn_physics(delta)
		return
	if not _presentation_valid():
		clear_presentation()
		return
	_present_yaw = rotate_toward(_present_yaw, _present_target_yaw, PRESENT_TURN_RATE * delta)
	var t: Transform3D = pony.global_transform
	var scale := t.basis.get_scale()
	t.basis = Basis(Vector3.UP, _present_yaw).scaled(scale)
	pony.global_transform = t
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)
	facts.pause_face(true)


## Turn her with the game's supported standing turn, which steps the hooves. The direct
## transform write used to rotate the body under planted feet and twisted her legs.

func _presentation_turn_physics(delta: float) -> void:
	if not _presentation_turn_valid():
		clear_presentation()
		return
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		if "face_point" in nav:
			nav.set("face_point", Vector3.INF)
		if nav.has_method("set_conversation_target"):
			nav.call("set_conversation_target", null, false)
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", _present_face_direction)
	var yaw: float = pony.rotation.y
	if absf(wrapf(yaw - _present_turn_last_yaw, -PI, PI)) < 0.0005:
		_present_turn_still += delta
	else:
		_present_turn_still = 0.0
		_present_turn_last_yaw = yaw
	var error := absf(wrapf(yaw - _present_target_yaw, -PI, PI))
	if error <= PRESENT_TURN_SETTLE_RAD \
			or _present_turn_still >= PRESENT_TURN_STALL_S \
			or facts.clock() - _present_turn_started >= PRESENT_TURN_TIMEOUT_S:
		_finish_present_turn()



func _presentation_turn_valid() -> bool:
	if not _present_turning or int(facts.state) != STATE_IDLE:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if pony.is_held() or pony.sleeping or pony.has_meta("seated"):
		return false
	if bool(facts.call_value(facts.cuddle_active, false)) or not bool(facts.call_value(facts.free_of_affection, true)):
		return false
	if not pony.grounded():
		return false
	var status: Dictionary = pony.posture_status()
	if str(status.get("requested", "")) != "stand":
		return false
	var player: Variant = main.player
	if is_instance_valid(player) and player.global_position.distance_to(pony.global_position) > 8.0:
		return false
	return true


## Idle request face and action hold. `affection_active` is the game's existing "physical
## affection owns her" flag; it blocks AI approach/follow actions while she asks and presents.

func set_request_face(on: bool) -> void:
	_sync()
	if not is_instance_valid(pony):
		return
	if on:
		_request_face = true
		if not pony.has_meta("affection_active"):
			pony.set_meta("affection_active", true)
			_request_claimed_affection = true
		return
	_request_face = false
	if _request_claimed_affection:
		pony.remove_meta("affection_active")
		_request_claimed_affection = false
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("stare"):
		expressions.call("stare", false)



func request_face_active() -> bool:
	return _request_face



func _request_face_process() -> void:
	if not _request_face or not is_instance_valid(pony):
		return
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", REQUEST_BLUSH)
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("stare"):
		expressions.call("stare", true, REQUEST_LIDS)



func _present_turn_process() -> void:
	if not _present_turning or not is_instance_valid(pony):
		return
	# Conversation facing can write a target in process after our late physics tick. Reassert
	# the away direction in process so the next locomotion step keeps turning her back.
	if pony.has_method("face_direction"):
		pony.call("face_direction", _present_face_direction)



func _presentation_process() -> void:
	if not _presentation_valid():
		clear_presentation()
		return
	var view: Camera3D = main.camera() if is_instance_valid(main) else null
	if is_instance_valid(_present_pose) and is_instance_valid(view):
		_present_pose.look_point = view.global_position
		_present_pose.head_back = 0.0
	_present_glance_back = true
	var secondary: Variant = pony.get("secondary")
	if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
		secondary.call("look_toward", _present_glance_angles(), 0.45)
	_present_aim_eyes()



func _present_glance_angles() -> Vector3:
	var head: Vector3 = pony.global_position + Vector3.UP
	if pony.has_method("listen_point"):
		head = pony.call("listen_point")
	var target: Vector3 = head
	if is_instance_valid(main) and is_instance_valid(main.player):
		var view: Camera3D = main.camera()
		if is_instance_valid(view):
			target = view.global_position
	var local: Vector3 = pony.global_basis.inverse() * (target - head)
	var raw := atan2(-local.x, -local.z)
	if not _present_glance_sign_set:
		_present_glance_sign = signf(raw) if absf(raw) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
		_present_glance_sign_set = true
	var yaw: float = _present_glance_sign * absf(raw)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	if _present_glance_back:
		var back_pitch := float(_pose_cfg.get("glance_back_pitch", 1.2)) * 1.2
		return Vector3(clampf(pitch + back_pitch, -0.25, 1.44),
			clampf(yaw, -MOTION.GLANCE_BACK_YAW, MOTION.GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg.get("glance_yaw", 3.0))
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)



func _present_aim_eyes() -> void:
	if not is_instance_valid(pony):
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	var view: Camera3D = main.camera() if is_instance_valid(main) else null
	var target: Vector3 = view.global_position if is_instance_valid(view) else pony.global_position
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)




## Read the live scene handles and pose config from the typed act view. The runtime rewrites
## the view before it hands the controller out, so this is a copy, not a read of the runtime node.
func _sync() -> void:
	if facts == null:
		main = null
		pony = null
		_pose_cfg = {}
		return
	main = facts.main
	pony = facts.pony
	var cfg: Variant = facts.pose_config
	_pose_cfg = cfg if cfg is Dictionary else {}


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


func process() -> void:
	_sync()
	if _present_turning:
		_present_turn_process()
	elif _presenting:
		_presentation_process()
	if _request_face:
		_request_face_process()


func physics(delta: float) -> void:
	_sync()
	if not (_present_turning or _presenting):
		return
	if facts.clock() - _present_started >= PRESENT_MAX_SECONDS:
		_log("present standing expired after %.0f s" % PRESENT_MAX_SECONDS)
		set_request_face(false)
		clear_presentation()
		return
	_presentation_physics(delta)


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
