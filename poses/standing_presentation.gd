extends RefCounted
## Idle standing invitation and request face. This is not the act: no camera, player lock,
## HUD or sex_active. The runtime only forwards the public calls.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")
const IDLE_STRETCH := preload("res://mods/unfplap/poses/idle_stretch.gd")

const PRESENT_TURN_RATE := 2.4
const PRESENT_FACE_TURN_RATE := 1.5
const PRESENT_TURN_TIMEOUT_S := 4.0
const PRESENT_TURN_STALL_S := 1.5
## The navigator's face_point target, the same 4 m the base-game idle fidget uses.
const PRESENT_TURN_POINT_M := 4.0
## "Away enough": the stepping turn settles within this of directly away, rather than demanding
## an exact 180-degree turn.
const PRESENT_AWAY_RAD := deg_to_rad(45.0)
const TURN_NAVIGATOR := "navigator"
const TURN_FACE := "face"
const TURN_YAW := "yaw"
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
var _present_turn_nav: Node = null
var _present_turn_point := Vector3.INF
var _present_turn_mode := ""
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
## The full presentation hold. The ask is always the normal standing pose; the stretch starts
## once she has accepted and turned. The stored variant and side carry into the act.
var _present_stretch: Variant = null

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
	# No pre-turn offer gate here: she has faced Anon for the ask line, so the rump-sensitive
	# gate can fail while she is still in front of him. The invite/start gate is rechecked after
	# the turn, once she is in position.
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
	_begin_present_turn()
	_log("present standing target_yaw=%.2f turn=%s" % [_present_target_yaw, _present_turn_mode])
	return true


## Create the idle pose and tail once she has finished turning. Doing this before the turn
## let the spread/bow pose fight the planted hooves and twisted the legs.

func _attach_present_pose() -> void:
	if not is_instance_valid(pony):
		return
	_finish_present_stretch(false)
	_pose_cfg = SETTINGS.pose(str(facts.pony_id), CATALOG.STANDING)
	# The act stance bows and bends the forelegs for the thrust; seen from behind it reads as her
	# front legs tucked between her hind. The invitation is a natural stand with the rump
	# presented, so the act-only bow, foreleg bend and wide hind stance are removed.
	_pose_cfg["bow"] = 0.0
	_pose_cfg["foreleg"] = 0.0
	_pose_cfg["foreleg_spread"] = 0.172
	_pose_cfg["hind_spread"] = 0.0
	var presentation_cfg: Dictionary = SETTINGS.act_snapshot(CATALOG.STANDING).presentation
	_pose_cfg["chin_up_deg"] = float(presentation_cfg.get("chin_up_deg", 30.0))
	_pose_cfg["neck_down_deg"] = float(presentation_cfg.get("neck_down_deg", 15.0))
	var tail_cfg: Variant = presentation_cfg.get("tail", {})
	if tail_cfg is Dictionary:
		_pose_cfg["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary).get("yaw_deg", 31.5)))
		_pose_cfg["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary).get("pitch_deg", 24.1)))
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		var holder: Variant = null
		if _stretch_enabled():
			holder = IDLE_STRETCH.new()
			if not bool(holder.call("begin", pony, true)):
				holder = null
		_present_pose = POSE.new()
		_present_pose.name = "UnfplapPresentPose"
		_present_pose.mare = pony
		_present_pose.mode = "standing"
		_present_pose.pose_config = _pose_cfg
		_present_pose.look_point = _present_look_point
		_present_pose.amount = 0.0
		_present_pose.target_amount = 1.0
		_present_pose.stretch = holder != null
		(skeleton as Skeleton3D).add_child(_present_pose)
		if holder != null:
			_present_stretch = holder
			holder.call("place_before", _present_pose)
		facts.call_value(facts.keep_chin_last)
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_present_tail = TAIL.new()
		_present_tail.name = "UnfplapPresentTail"
		_present_tail.mare = pony
		_present_tail.facts = facts
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



## Put the game's own stepping turn in charge of her body. The navigator's `face_point` walks
## her legs round exactly as it does for the base-game conversation circle and idle fidget; a
## direct `face_direction` call loses to the navigator's own facing every tick.
func _begin_present_turn() -> void:
	_present_turning = true
	_present_turn_nav = null
	_present_turn_point = Vector3.INF
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null and "face_point" in nav:
		_present_turn_mode = TURN_NAVIGATOR
		_present_turn_nav = nav
		_present_turn_point = pony.global_position + _present_face_direction * PRESENT_TURN_POINT_M
		if nav.has_method("stay"):
			# A pending route would keep the navigator out of its face_point branch.
			nav.call("stay")
		_set_turn_nav_facing()
		_raise_present_turn_rate()
		return
	if pony.has_method("face_direction"):
		_present_turn_mode = TURN_FACE
		_raise_present_turn_rate()
		pony.call("face_direction", _present_face_direction)
		return
	# Unusual actor without the game's locomotion turn: rotate before the pose attaches, never
	# after it.
	_present_turn_mode = TURN_YAW
	_present_yaw = pony.rotation.y


## Re-assert the navigator's face point and keep conversation facing from taking the body back.
func _set_turn_nav_facing() -> void:
	if not is_instance_valid(_present_turn_nav) or not _present_turn_point.is_finite():
		return
	if "face_point" in _present_turn_nav:
		_present_turn_nav.set("face_point", _present_turn_point)
	if _present_turn_nav.has_method("set_conversation_target"):
		_present_turn_nav.call("set_conversation_target", null, false)


func _raise_present_turn_rate() -> void:
	if _present_turn_rate_owned or not is_instance_valid(pony):
		return
	var rate: Variant = pony.get("face_turn_rate")
	if rate == null:
		return
	_present_turn_rate_saved = float(rate)
	_present_turn_rate_owned = true
	pony.set("face_turn_rate", maxf(_present_turn_rate_saved, PRESENT_FACE_TURN_RATE))


func _restore_present_turn_rate() -> void:
	if _present_turn_rate_owned and is_instance_valid(pony):
		pony.set("face_turn_rate", _present_turn_rate_saved)
	_present_turn_rate_owned = false
	_present_turn_rate_saved = -1.0


## Release every facing request the turn owned. No stale face_point may survive a settle or a
## cancel.
func _end_present_turn() -> void:
	if is_instance_valid(_present_turn_nav):
		var face: Variant = _present_turn_nav.get("face_point") if "face_point" in _present_turn_nav else null
		if face is Vector3 and _present_turn_point.is_finite() and (face as Vector3) == _present_turn_point:
			_present_turn_nav.set("face_point", Vector3.INF)
		if _present_turn_nav.has_method("set_conversation_target"):
			_present_turn_nav.call("set_conversation_target", null, false)
	_present_turn_nav = null
	_present_turn_point = Vector3.INF
	_present_turn_mode = ""
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", Vector3.ZERO)
	_restore_present_turn_rate()
	_present_turning = false
	_present_turn_still = 0.0


## The away threshold is reached. Hold the yaw the stepping turn actually reached: never snap
## the body, and attach the pose only now, so no turn happens under the planted pose.
func _finish_present_turn() -> void:
	var mode := _present_turn_mode
	var target := _present_target_yaw
	var elapsed: float = facts.clock() - _present_turn_started
	var error := 0.0
	if is_instance_valid(pony):
		error = absf(wrapf(pony.rotation.y - target, -PI, PI))
	_end_present_turn()
	if is_instance_valid(pony):
		_present_yaw = pony.rotation.y
		_present_target_yaw = _present_yaw
		_log("present standing turn settled mode=%s error=%.2f yaw=%.2f target=%.2f t=%.2f" % [
			mode, error, _present_yaw, target, elapsed])
	if not _presenting:
		_attach_present_pose()
	facts.pause_face(true)


## No pose attaches on an abort: the service sees the presentation inactive and either
## re-presents or closes the offer.
func _abort_present_turn(reason: String) -> void:
	var mode := _present_turn_mode
	var target := _present_target_yaw
	var elapsed: float = facts.clock() - _present_turn_started
	var yaw := 0.0
	var error := 0.0
	if is_instance_valid(pony):
		yaw = pony.rotation.y
		error = absf(wrapf(yaw - target, -PI, PI))
	_log("present standing turn aborted mode=%s error=%.2f yaw=%.2f target=%.2f t=%.2f reason=%s" % [
		mode, error, yaw, target, elapsed, reason])
	_end_present_turn()
	clear_presentation()



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
	# Preserve the episode choice: an act started from this presentation reuses the same variant
	# and side. A cancel clears it through `clear_stretch_offer()` before this runs.
	_finish_present_stretch(false)
	if _present_turning:
		_end_present_turn()
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


## Turn her with the game's supported stepping turn, which steps the hooves. The navigator's
## face_point owns the turn exactly as it does for the base-game conversation circle; the pose
## attaches only after she is away enough, so nothing rotates under planted feet.

func _presentation_turn_physics(delta: float) -> void:
	if not _presentation_turn_valid():
		_abort_present_turn("turn invalid")
		return
	match _present_turn_mode:
		TURN_NAVIGATOR:
			_set_turn_nav_facing()
		TURN_FACE:
			if is_instance_valid(pony) and pony.has_method("face_direction"):
				pony.call("face_direction", _present_face_direction)
		TURN_YAW:
			_present_yaw = rotate_toward(_present_yaw, _present_target_yaw,
				PRESENT_TURN_RATE * delta)
			var t: Transform3D = pony.global_transform
			var scale := t.basis.get_scale()
			t.basis = Basis(Vector3.UP, _present_yaw).scaled(scale)
			pony.global_transform = t
	var yaw: float = pony.rotation.y
	if absf(wrapf(yaw - _present_turn_last_yaw, -PI, PI)) < 0.0005:
		_present_turn_still += delta
	else:
		_present_turn_still = 0.0
		_present_turn_last_yaw = yaw
	var error := absf(wrapf(yaw - _present_target_yaw, -PI, PI))
	if error <= PRESENT_AWAY_RAD:
		_finish_present_turn()
		return
	if _present_turn_still >= PRESENT_TURN_STALL_S:
		_abort_present_turn("turn stalled error=%.2f" % error)
		return
	if facts.clock() - _present_turn_started >= PRESENT_TURN_TIMEOUT_S:
		_abort_present_turn("turn timeout error=%.2f" % error)



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


## A cancel or close drops the presentation holder and the stored episode choice. The Y-start
## handoff does not call this, so the act reuses the presentation's variant and side.
func clear_stretch_offer() -> void:
	_sync()
	_finish_present_stretch(true)


## Re-read the setting and the external mod after a settings edit. Only a live presentation is
## touched; the act's holder is the pose session's, and the ask is never stretched.
func apply_live_settings() -> void:
	_sync()
	var enabled := _stretch_enabled()
	if _present_stretch != null and not enabled:
		_finish_present_stretch(false)
		if is_instance_valid(_present_pose):
			_present_pose.set("stretch", false)
	if not enabled:
		return
	if _presenting and not _present_turning and _present_stretch == null:
		_attach_present_stretch()


## Whether the player turned the setting on and Idle Life is active in this launch. Read at the
## presentation attach and on live settings edits, never per frame.
func _stretch_enabled() -> bool:
	if not bool(SETTINGS.idle_life_stretch.get_bool()):
		return false
	if facts == null:
		return false
	return bool(facts.mod_active("idle_life"))


func _attach_present_stretch() -> void:
	if _present_stretch != null or not is_instance_valid(pony) \
			or not is_instance_valid(_present_pose):
		return
	var holder: Variant = IDLE_STRETCH.new()
	if not bool(holder.call("begin", pony, true)):
		return
	_present_stretch = holder
	_present_pose.set("stretch", true)
	holder.call("place_before", _present_pose)
	facts.call_value(facts.keep_chin_last)


func _finish_present_stretch(clear: bool) -> void:
	if _present_stretch != null:
		_present_stretch.call("finish", clear)
		_present_stretch = null
	elif clear and is_instance_valid(pony):
		IDLE_STRETCH.clear_choice(pony)


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
	# the away facing so the next navigation step keeps turning her back.
	match _present_turn_mode:
		TURN_NAVIGATOR:
			_set_turn_nav_facing()
		TURN_FACE:
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
