extends RefCounted
## The act's kiss, standing only: the game's own kiss, and the legs that must not slide under it.
## Her bed kiss is a gaze the camera aims and a face the face system animates; her score is the
## act's call site. It holds no copy of the act: her body and the act's facts are read at the call,
## so a body swap is followed with no rebind.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const KISS_LEGS := preload("res://mods/unfplap/act/kiss_legs.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
## The standing mouth offset the presentation may override, in metres at Anon's reference height.
const KISS_MOUTH_DROP_M := 0.07
const KISS_MOUTH_FORWARD_M := 0.02
## The stock pose's side hold: effectively forever, so its own side switch cannot fire mid-kiss.
const KISS_SIDE_HOLD_S := 9999.0

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var _base_kiss_active := false
var _base_kiss_releasing := false
## Latched for the whole kiss (including the Affection release) so rock noise cannot flip sides.
var _kiss_pony_side := 0.0
var _kiss_diag_clock := 0.0
var _base_kiss_affection: Node
var _base_kiss_pose: SkeletonModifier3D
var _base_kiss_pose_index := -1
var _base_kiss_excitement: Node
var _kiss_forelegs_planted := false
var _kiss_leg_pin: KISS_LEGS = null
## The game's own kiss rows, as the player left them, captured by the first zeroing and put back by
## `reset()` or `restore_rows()`. Static because the rows outlive the act that lifted them.
static var _saved_rear := NAN
static var _saved_hooves := NAN


## The runtime's wiring, once per act: the body owner and the act facts the stock kiss feeds.
func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Her body, read at the call so a body swap needs no rebind.
func _pony() -> Node3D:
	if host == null or not is_instance_valid(host.pony):
		return null
	return host.pony as Node3D


## The live pose family from the pose view; empty outside a built pose.
func _pose_family() -> String:
	var pose_view: Variant = context.pose.view() if context != null and context.pose != null else null
	return str(pose_view.family) if pose_view != null else ""


## A kiss the act asked for; false when the game refused, so the act can tell and score nothing.
## Latches `side` (already in the pony's sign) and captures both hoof tips before the pose bends.
func start(side: float) -> bool:
	if _base_kiss_active or _base_kiss_releasing:
		return false
	_kiss_pony_side = side
	_kiss_diag_clock = 0.0
	return _start_base_kiss()


## One frame: feed the paused stock kisser his mouth and face, hold the side pin, finish a release.
func tick() -> void:
	if _base_kiss_releasing:
		var releasing := _base_kiss_affection
		if not is_instance_valid(releasing) or float(releasing.get("amount")) <= 0.001:
			_restore_base_kiss_pose()
	if not _base_kiss_active:
		return
	var delta := float(context.facts.physics_delta)
	_kiss_diag_clock -= delta
	if _kiss_diag_clock <= 0.0:
		_kiss_diag_clock = 1.0
		_kiss_diag()
	_update_base_kiss()
	_pin_base_side()


## The act ended the kiss; the stock pose eases out and the legs follow it.
func stop() -> void:
	_end_base_kiss()


## The act's live settings edit re-applied the global rows; zero them again while a kiss runs.
func refresh_rows() -> void:
	if _base_kiss_active:
		# The edit wrote the rows back, so take the edited pair as the one to restore.
		_saved_rear = NAN
		_saved_hooves = NAN
		_kiss_forelegs_planted = false
		_apply_kiss_forelegs()
	elif _kiss_forelegs_planted:
		_restore_kiss_forelegs()
		_stop_kiss_leg_pin()


## The act is over: stop the kiss and put back every global it changed.
func reset() -> void:
	stop()
	_kiss_pony_side = 0.0
	_restore_base_kiss_pose()


## The stock kiss rows are the game's globals and outlive any act; a world close puts them back.
static func restore_rows() -> void:
	if is_nan(_saved_rear):
		return
	var settings := WORLD.affection().kiss_settings()
	settings["rear"] = _saved_rear
	settings["hooves"] = _saved_hooves
	_saved_rear = NAN
	_saved_hooves = NAN


## The stock affection is running or easing out.
func active() -> bool:
	return _base_kiss_active or _base_kiss_releasing


## Anon's chosen height over the reference rig, the scale his mouth offset was tuned on.
func _kiss_height_scale() -> float:
	return float(context.facts.anon_height_scale) if context != null and context.facts != null else 1.0


## The standing kiss's mouth offset; the fixed constants outside the standing pose.
func _kiss_mouth_offset() -> Vector3:
	var drop := KISS_MOUTH_DROP_M
	var forward := KISS_MOUTH_FORWARD_M
	var right := 0.0
	if _pose_family() == "standing":
		drop = SETTINGS.mouth_drop.get_num()
		forward = SETTINGS.mouth_forward.get_num()
		right = SETTINGS.mouth_right.get_num()
	return Vector3(right, -drop, -forward) * _kiss_height_scale()


## The kiss's lateral distance at Anon's height; the fixed constant outside the standing pose.
func _kiss_side_m() -> float:
	var side := MOTION.KISS_LEAN_SIDE_M
	if _pose_family() == "standing":
		side = SETTINGS.lean_side.get_num()
	return side * _kiss_height_scale()


func _apply_kiss_forelegs() -> void:
	if _kiss_forelegs_planted:
		return
	var settings := WORLD.affection().kiss_settings()
	if is_nan(_saved_rear):
		_saved_rear = float(settings.get("rear", 1.0))
		_saved_hooves = float(settings.get("hooves", 1.0))
	settings["rear"] = 0.0
	settings["hooves"] = 0.0
	_kiss_forelegs_planted = true
	LOG.debug("kiss forelegs planted")


func _restore_kiss_forelegs() -> void:
	if not _kiss_forelegs_planted:
		return
	restore_rows()
	_kiss_forelegs_planted = false


## The base kiss's chest flex runs after body_sway's upper-arm pin. This extra modifier runs
## last and brings the visible hoof tips back to where they were before the kiss.
func _start_kiss_leg_pin() -> void:
	var pony := _pony()
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


## Reuse the game's own kiss; the pose modifier is moved last so its IK layers on top.
## Its eligibility checks read `controls_locked`, so unlock for that one call only.
func _start_base_kiss() -> bool:
	if context == null or context.facts == null:
		return false
	var pony := _pony()
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
	LOG.debug("base kiss start pony=%s", [str(context.facts.pony_id)])
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
	if is_instance_valid(WORLD.player_rig()) and context != null and context.facts != null \
			and int(context.facts.state) in [STATE_ACTIVE, STATE_CLIMAX]:
		WORLD.player_rig().set_meta("kiss_hold", true)
	_base_kiss_releasing = is_instance_valid(_base_kiss_pose)
	if not _base_kiss_releasing:
		_base_kiss_affection = null
		_kiss_pony_side = 0.0
		_restore_kiss_forelegs()
		_stop_kiss_leg_pin()


## Keep the AffectionPose last while its own 0.6 s release eases out, then restore the child order.
func _restore_base_kiss_pose() -> void:
	_restore_kiss_forelegs()
	_stop_kiss_leg_pin()
	if is_instance_valid(_base_kiss_pose):
		WORLD.affection().release_side(_base_kiss_pose)
	_base_kiss_releasing = false
	var pony := _pony()
	if is_instance_valid(_base_kiss_pose) and is_instance_valid(pony):
		var skeleton := WORLD.pony(pony).skeleton()
		if skeleton != null:
			var index := clampi(_base_kiss_pose_index, 0, skeleton.get_child_count() - 1)
			skeleton.move_child(_base_kiss_pose, index)
	_base_kiss_pose = null
	_base_kiss_pose_index = -1
	_base_kiss_affection = null
	_kiss_pony_side = 0.0
	_restore_base_kiss_excitement()


## A base kiss otherwise plays the stock horn sparkle, which reads as spellcasting.
## Hold the shared act-level Beat instead; the runtime restores it after the last holder.
func _suppress_base_kiss_excitement() -> void:
	if is_instance_valid(_base_kiss_excitement):
		return
	var pony := _pony()
	if not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	_base_kiss_excitement = excitement as Node
	if context != null and context.facts != null:
		context.facts.hold_beat("kiss")
	WORLD.affection().settle_excitement(_base_kiss_excitement)


func _restore_base_kiss_excitement() -> void:
	if context != null and context.facts != null:
		context.facts.release_beat("kiss")
	_base_kiss_excitement = null


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


## The player kisser is paused for the whole act, so it cannot write these itself. Feed the base
## kiss the live mouth and face, exactly as pony_kisser would.
func _update_base_kiss() -> void:
	var affection := _base_kiss_affection
	if not is_instance_valid(affection):
		return
	var view := _mouth_view()
	if not is_instance_valid(view):
		return
	WORLD.affection().feed(affection, _target(view), view.global_position,
		view.global_basis.orthonormalized())


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
	var pony := _pony()
	var view := _mouth_view()
	if is_instance_valid(view) and is_instance_valid(pony):
		var target := _target(view)
		var right := view.global_basis.x.normalized()
		var mouth := WORLD.pony(pony).mouth_point(affection)
		if mouth.is_finite():
			mouth_gap = mouth.distance_to(target)
		var skull := WORLD.pony(pony).skull_world()
		if skull.is_finite():
			skull_lateral = (skull - target).dot(right)
		var camera: Camera3D = context.facts.camera
		cam_roll = rad_to_deg(camera.rotation.z) if is_instance_valid(camera) else 0.0
		var skeleton := WORLD.pony(pony).skeleton()
		if skeleton != null:
			var head_bone := skeleton.find_bone("pony_head")
			if head_bone >= 0:
				var head_t := skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
				var up := head_t.basis.y.normalized()
				var view_up := view.global_basis.y.normalized()
				head_roll = rad_to_deg(up.signed_angle_to(view_up, -view.global_basis.z.normalized()))
	var lateral := MOTION.kiss_lateral_offset(float(context.facts.lean_view_side),
		float(context.facts.kiss_side), float(context.facts.kiss_amount),
		float(context.facts.standing_lean_scale), _kiss_side_m())
	LOG.debug("kiss diag base=%s pony_side=%.2f pose_side=%.2f cam_roll=%.1f head_roll=%.1f skull_lat=%.3f gap=%.3f limited=%.1fdeg miss=%.3fm clear=%s lateral=%.3f", [
		str(_base_kiss_active), _kiss_pony_side, pose_side, cam_roll, head_roll,
		skull_lateral, mouth_gap, limited, miss, cleared, lateral])


func _target(view: Camera3D) -> Vector3:
	if not is_instance_valid(view):
		return Vector3.INF
	return view.global_position + view.global_basis * _kiss_mouth_offset()


## Anon's actual mouth camera. A bed act frames the shot through a separate view, so the game
## camera is the one his mouth belongs to.
func _mouth_view() -> Camera3D:
	if is_instance_valid(WORLD.world_root()):
		var view: Camera3D = WORLD.camera()
		if is_instance_valid(view):
			return view
	return context.facts.camera as Camera3D
