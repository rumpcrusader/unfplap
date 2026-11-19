extends RefCounted
## The standing act presentation: the invitation turn and face the act-owned start waits for. It
## is not the act: no camera, player lock, HUD or sex_active. The runtime only forwards the public
## calls.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")

const PRESENT_TURN_RATE := 2.4
const PRESENT_FACE_TURN_RATE := 1.5
const PRESENT_TURN_TIMEOUT_S := 4.0
const PRESENT_TURN_STALL_S := 1.5
## The navigator's face_point target, the same 4 m the base-game idle fidget uses.
const PRESENT_TURN_POINT_M := 4.0
## "Away enough": the stepping turn settles within this of directly away, rather than demanding
## an exact 180-degree turn. She ends about 120 degrees from Anon, leaving the head room for an
## over-the-shoulder glance.
const PRESENT_AWAY_RAD := deg_to_rad(60.0)
## One stronger look-back right after the pose settles, then the softer over-the-shoulder hold.
const PRESENT_GLANCE_BACK_S := 1.5
## The base game's approved bedroom face: heavy lids, dilated pupils, full blush and hearts.
const PRESENT_FACE := "affectionate"
## The presentation's own nose blush, sustained while she holds the pose.
const PRESENT_BLUSH := 1.0
const TURN_NAVIGATOR := "navigator"
const TURN_FACE := "face"
const TURN_YAW := "yaw"
## Safety cap: the invitation owns her body, so no missed end path may leave the pose on forever.
## Longer than the invite wait plus the turn.
const PRESENT_MAX_SECONDS := 75.0
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_IDLE := ACT_STATE.State.IDLE

var facts: Variant
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
var _present_glance_until := 0.0
var _present_glance_sign := 1.0
var _present_glance_sign_set := false
## Set when this controller applied `PRESENT_FACE`, so close only clears its own face.
var _present_face_owned := false
var _present_tail
var _present_started := 0.0
var _present_yaw := 0.0
var _present_target_yaw := 0.0
var _present_look_point := Vector3.ZERO
var _present_face_direction := Vector3.ZERO
## The presentation's own affection hold: it blocks AI approach/follow through the turn.
var _present_hold := false
var _present_claimed_affection := false
## Bring her into the presentation hold: the ask is always the normal standing pose, and the
## stored variant and side carry into the act once she has accepted and turned.
func present_standing() -> bool:
	_sync()
	if _presenting or _present_turning:
		return true
	if int(facts.state) != STATE_IDLE or not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return false
	if pony.is_held() or pony.sleeping or bool(facts.call_value(facts.cuddle_active, false)):
		return false
	if not bool(facts.call_value(facts.free_of_affection, true)):
		return false
	var service: ELIGIBILITY = PONIES.eligibility
	if service == null or not service.eligible(pony, ELIGIBILITY.Target.ACT):
		return false
	# No pre-turn offer gate here: she has faced Anon for the ask line, so the rump-sensitive
	# gate can fail while she is still in front of him. The invite/start gate is rechecked after
	# the turn, once she is in position.
	if not _present_hold:
		_set_presentation_hold(true)
	var player: Variant = WORLD.player
	var view: Camera3D = WORLD.camera()
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
	_pose_cfg = SETTINGS.pose(str(facts.pony_id), CATALOG.STANDING)
	# The act stance bows and bends the forelegs for the thrust; seen from behind it reads as her
	# front legs tucked between her hind. The invitation is a natural stand with the rump
	# presented, so the act-only bow, foreleg bend and wide hind stance are removed.
	_pose_cfg["bow"] = 0.0
	_pose_cfg["foreleg"] = 0.0
	_pose_cfg["foreleg_spread"] = 0.172
	_pose_cfg["hind_spread"] = 0.0
	var presentation_cfg: Dictionary = SETTINGS.act_snapshot(CATALOG.STANDING).presentation
	_pose_cfg["chin_up_deg"] = float(presentation_cfg["chin_up_deg"])
	_pose_cfg["neck_down_deg"] = float(presentation_cfg["neck_down_deg"])
	var tail_cfg: Variant = presentation_cfg["tail"]
	if tail_cfg is Dictionary:
		_pose_cfg["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary)["yaw_deg"]))
		_pose_cfg["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary)["pitch_deg"]))
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D:
		_present_pose = POSE.new()
		_present_pose.name = "UnfplapPresentPose"
		_present_pose.mare = pony
		_present_pose.pose_config = _pose_cfg
		_present_pose.set_pose(POSE.STANDING_PATH, POSE.STANDING_PATH, "", "", _pose_cfg, _pose_cfg)
		_present_pose.set_weight(1.0)
		_present_pose.look_point = _present_look_point
		_present_pose.amount = 0.0
		_present_pose.target_amount = 1.0
		(skeleton as Skeleton3D).add_child(_present_pose)
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_present_tail = TAIL.new()
		_present_tail.name = "UnfplapPresentTail"
		_present_tail.mare = pony
		_present_tail.facts = facts
		_present_tail.aside_angle = float(_pose_cfg["tail_aside"])
		_present_tail.lift_angle = float(_pose_cfg["tail_lift"])
		_present_tail.amount = 0.0
		_present_tail.target_amount = 1.0
		var side_anchor := Vector3.INF
		var view: Camera3D = WORLD.camera()
		if is_instance_valid(view):
			side_anchor = view.global_position
		_present_tail.call("choose_side", side_anchor)
		(hair as Skeleton3D).add_child(_present_tail)
	_presenting = true
	_present_glance_back = true
	_present_glance_until = facts.clock() + PRESENT_GLANCE_BACK_S
	_present_glance_sign_set = false
	# The ask and turn half-lid gives way to the affectionate face's own sculpted lids.
	_apply_present_face()



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
	# and side.
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
	_present_glance_until = 0.0
	_present_glance_sign_set = false
	_end_presentation_hold()
	_clear_present_face()
	facts.restore_face()



func _presentation_valid() -> bool:
	if not _presenting or int(facts.state) != STATE_IDLE:
		return false
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
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
	var player: Variant = WORLD.player
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
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
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
	var player: Variant = WORLD.player
	if is_instance_valid(player) and player.global_position.distance_to(pony.global_position) > 8.0:
		return false
	return true


## The presentation's own action hold. `affection_active` is the game's existing "physical
## affection owns her" flag; it blocks AI approach/follow actions while she turns and presents.
## The negotiation hold sets the same flag; the presentation only clears the one it set.
func _set_presentation_hold(on: bool) -> void:
	_sync()
	if not is_instance_valid(pony):
		return
	if on:
		_present_hold = true
		if not pony.has_meta("affection_active"):
			pony.set_meta("affection_active", true)
			_present_claimed_affection = true
		return
	_present_hold = false
	if _present_claimed_affection:
		pony.remove_meta("affection_active")
		_present_claimed_affection = false


## Re-read the live settings after an edit. The presentation has no act-time values of its own;
## the pose config is read when the hold starts.
func apply_live_settings() -> void:
	_sync()


## Release the presentation's hold when the turn ends for any reason.
func _end_presentation_hold() -> void:
	_set_presentation_hold(false)


## Hold the approved affectionate face after the turn. A spoken line's own face wins while it
## owns the expression; the held face returns once the line clears.
## The held pose keeps the nose blush at full; the face's own blush is the display layer.
func _sustain_present_blush() -> void:
	if not is_instance_valid(pony):
		return
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", PRESENT_BLUSH)


func _apply_present_face() -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not expressions.has_method("set_dialogue"):
		return
	if not str(expressions.get("dialogue_face")).is_empty():
		return
	expressions.call("set_dialogue", PRESENT_FACE)
	_present_face_owned = true


## Clear only the face this controller applied; never another system's spoken line face.
func _clear_present_face() -> void:
	if not _present_face_owned:
		return
	_present_face_owned = false
	var expressions: Variant = pony.get("expressions") if is_instance_valid(pony) else null
	if expressions == null or not expressions.has_method("clear_dialogue"):
		return
	if str(expressions.get("dialogue_face")) == PRESENT_FACE:
		expressions.call("clear_dialogue")



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
	var view: Camera3D = WORLD.camera() if is_instance_valid(WORLD.game) else null
	if is_instance_valid(_present_pose) and is_instance_valid(view):
		_present_pose.look_point = view.global_position
		_present_pose.head_back = 0.0
	if _present_glance_back and facts.clock() >= _present_glance_until:
		_present_glance_back = false
	var secondary: Variant = pony.get("secondary")
	if secondary != null and is_instance_valid(secondary) and secondary.has_method("look_toward"):
		secondary.call("look_toward", _present_glance_angles(), 0.45)
	_present_aim_eyes()
	_sustain_present_blush()
	_apply_present_face()



func _present_glance_angles() -> Vector3:
	var head: Vector3 = pony.global_position + Vector3.UP
	if pony.has_method("listen_point"):
		head = pony.call("listen_point")
	var target: Vector3 = head
	if is_instance_valid(WORLD.player):
		var view: Camera3D = WORLD.camera()
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
		var back_pitch := float(_pose_cfg["glance_back_pitch"]) * 1.2
		return Vector3(clampf(pitch + back_pitch, -0.25, 1.44),
			clampf(yaw, -MOTION.GLANCE_BACK_YAW, MOTION.GLANCE_BACK_YAW), 0.0)
	var yaw_limit := float(_pose_cfg["glance_yaw"])
	return Vector3(clampf(pitch, -0.35, 0.55), clampf(yaw, -yaw_limit, yaw_limit), 0.0)



func _present_aim_eyes() -> void:
	if not is_instance_valid(pony):
		return
	var eye_motion: Variant = pony.get("eye_motion")
	if eye_motion == null or not is_instance_valid(eye_motion):
		return
	var view: Camera3D = WORLD.camera() if is_instance_valid(WORLD.game) else null
	var target: Vector3 = view.global_position if is_instance_valid(view) else pony.global_position
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)




## Read the live scene handles and pose config from the typed act view. The runtime rewrites
## the view before it hands the controller out, so this is a copy, not a read of the runtime node.
func _sync() -> void:
	if facts == null:
		pony = null
		_pose_cfg = {}
		return
	pony = facts.pony
	var view: Variant = facts.pose_view
	var cfg: Variant = view.pose_config if view != null else null
	# The idle presentation builds its own config before any pose session exists; an empty view
	# config must not erase it on the next process frame.
	if cfg is Dictionary and not (cfg as Dictionary).is_empty():
		_pose_cfg = cfg


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


func process() -> void:
	_sync()
	if _present_turning:
		_present_turn_process()
	elif _presenting:
		_presentation_process()


func physics(delta: float) -> void:
	_sync()
	if not (_present_turning or _presenting):
		return
	if facts.clock() - _present_started >= PRESENT_MAX_SECONDS:
		_log("present standing expired after %.0f s" % PRESENT_MAX_SECONDS)
		clear_presentation()
		return
	_presentation_physics(delta)


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
