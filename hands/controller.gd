extends "res://mods/unfplap/hands/port.gd"
## Composition root for the per-hand actions; it never places a palm.

const POSES := preload("res://mods/unfplap/poses/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const PATH_SELECTOR := preload("res://mods/unfplap/hands/path_selector.gd")
const CARESS := preload("res://mods/unfplap/hands/caress.gd")
const REACH := preload("res://mods/unfplap/hands/reach.gd")
const SMACK := preload("res://mods/unfplap/hands/smack.gd")
const SMACK_TARGET := preload("res://mods/unfplap/hands/smack_target.gd")

const SMACK_ZONE_RADIUS_M := 0.035

var facts: ACT_FACTS = null
var _pony: Node3D = null
var _presentation_cfg: Dictionary = {}
var _profile: Dictionary = {}
var _flank: Node = null
## The last pose-change path and contact the hook saw, so a steady tick does nothing.
var _hook_path := ""
var _hook_contact := ""
var _hook_seen := false

var _engine: PLACEMENT = null
var _selector: PATH_SELECTOR = null
var _caress: CARESS = null
var _reach: REACH = null
var _smack: SMACK = null
var _target: SMACK_TARGET = null


func _init(facts_context: ACT_FACTS = null) -> void:
	facts = facts_context
	_engine = PLACEMENT.new()
	_selector = PATH_SELECTOR.new()
	_caress = CARESS.new(self, facts)
	_reach = REACH.new(self, facts)
	_smack = SMACK.new(self)
	_target = SMACK_TARGET.new(self)


## Drop every peer and action module at runtime exit; the hands service calls it once. No module
## points back here strongly, so dropping these links frees the whole graph.
func _release() -> void:
	facts = null
	_pony = null
	_flank = null
	_engine = null
	_selector = null
	_caress = null
	_reach = null
	_smack = null
	_target = null


## One frame: settle a released reach; when `actionable`, also advance the caress and smack.
func tick(delta: float, actionable: bool) -> void:
	if facts == null:
		return
	_sync()
	_reach.tick()
	if not actionable:
		_caress.end()
		_smack.cancel()
		return
	_caress.tick(delta)
	_smack.tick(delta)


## Retarget on a pose or contact change; the standing ↔ oral pair keeps holds.
func pose_changed(view: POSE_VIEW) -> void:
	if view == null:
		return
	var path := str(view.hands.get("path", ""))
	var contact := str(view.contact_kind)
	if _hook_seen and path == _hook_path and contact == _hook_contact:
		return
	var old_path := _hook_path
	var path_changed := _hook_seen and path != _hook_path
	_hook_seen = true
	_hook_path = path
	_hook_contact = contact
	if path_changed:
		_caress.warm_paths()
	# The standing ↔ oral pair is one contact-driven path: the mouth switch, not the request,
	# retargets the caress so the blend can capture the live hand frames.
	var contact_pair := (path == "oral" and old_path == "standing") \
		or (path == "standing" and old_path == "oral")
	if path_changed and not contact_pair:
		_caress.end()


## LEFT/RIGHT start or hold the shoulder reach; NONE releases it.
func set_reach(side: MODEL.Side) -> void:
	if facts == null:
		return
	_sync()
	if side == MODEL.Side.NONE:
		_reach.settle()
		return
	_reach.start(side)


## True while a shoulder reach still owns a hand.
func reach_active() -> bool:
	return _reach.active()


## Swing one smack from the act input route.
func smack() -> void:
	if facts == null:
		return
	if int(facts.state) not in [ACT_STATE.State.ACTIVE, ACT_STATE.State.CLIMAX]:
		return
	_sync()
	var now := Time.get_ticks_msec()
	if not _smack.can_start(now):
		return
	if not is_instance_valid(_flank) or not _flank.has_method("impact"):
		return
	var target := _target.target(_caress.active(MODEL.Side.LEFT),
		_caress.active(MODEL.Side.RIGHT), _reach.owns(MODEL.Side.LEFT),
		_reach.owns(MODEL.Side.RIGHT), float(facts.lean_side), _pose_family() == "standing")
	if target.valid and is_instance_valid(WORLD.player_rig()):
		# End the hold before the swing starts, so nothing is left to resume.
		if target.caressing:
			_caress.end_side(target.side)
		if target.reaching:
			_reach.cancel(target.side)
		_smack.begin(target.side, target.index, target.at, target.from_frame, target.target,
			target.normal, target.from_coat, target.standing, now)
		hold(target.side, target.from_frame)
		return
	_smack.instant(target.index, target.at)


## Idempotent per-act reset; the exit, a fresh act and a body swap call it.
func reset() -> void:
	_caress.reset()
	_smack.reset()
	_reach.reset()
	if _engine != null:
		_engine.reset()
	if _selector != null:
		_selector.reset()
	_hook_seen = false
	_hook_path = ""
	_hook_contact = ""


## True while either hand holds a caress.
func any_active() -> bool:
	return _caress.any_active()


func pony() -> Node3D:
	return _pony


func driver() -> Node:
	return _hand_driver()


func path() -> PATH_BASE:
	if _selector == null:
		return null
	return _selector.path(_pony, facts)


func engine() -> PLACEMENT:
	return _engine


func presentation() -> MODEL.SmackPresentation:
	return _smack_config()


func smack_zone_radius() -> float:
	return maxf(0.0, float(_profile.get("smack_zone_radius", SMACK_ZONE_RADIUS_M)))


func body_scale() -> float:
	if is_instance_valid(_pony) and _pony.get("body_scale") != null:
		return clampf(float(_pony.get("body_scale")), 0.5, 2.0)
	return 1.0


func frozen() -> bool:
	return facts != null and bool(facts.call_value(facts.auto_panel_open, false))


func debug() -> bool:
	return facts != null and facts.feature("caress_debug", false)


func smack_owns(side: MODEL.Side) -> bool:
	return _smack != null and _smack.owns_hand(side)


func hand_frame(side: MODEL.Side) -> Transform3D:
	var hand := _hand_driver()
	if not is_instance_valid(hand) or not hand.has_method("hand_frame"):
		return Transform3D(Basis(), Vector3.INF)
	return WORLD.anon().hand_frame(hand, MODEL.side_key(side))


func hold(side: MODEL.Side, frame: Transform3D) -> void:
	var hand := _hand_driver()
	if not is_instance_valid(hand) or not hand.has_method("set_hold_target"):
		return
	WORLD.anon().set_hold_target(hand, MODEL.side_key(side), frame, "rub")


func release_hold(side: MODEL.Side) -> void:
	var hand := _hand_driver()
	if not is_instance_valid(hand) or not hand.has_method("clear_hold_target"):
		return
	WORLD.anon().clear_hold_target(hand, MODEL.side_key(side))


func flank() -> Node:
	return _flank


func flank_impact(index: int, at: Vector3, strength: float) -> void:
	if not is_instance_valid(_flank):
		return
	WORLD.flank(_flank).impact(index, at, strength)


func touch(kind: String) -> void:
	if facts != null:
		facts.touch(kind)


func impact(strength: float) -> void:
	if facts != null:
		facts.smack_hit(strength)


## Internal seams the suites use to observe the typed modules without a reach-in field.
func caress() -> CARESS:
	return _caress


func reach() -> REACH:
	return _reach


func path_selector() -> PATH_SELECTOR:
	return _selector


func smack_action() -> SMACK:
	return _smack


func hook_path() -> String:
	return _hook_path


func hook_contact() -> String:
	return _hook_contact


## Read the live scene handles and configs from the typed act view.
func _sync() -> void:
	if facts == null:
		_pony = null
		_presentation_cfg = {}
		_profile = {}
		return
	_pony = facts.pony if facts.pony is Node3D else null
	var cfg: Variant = facts.presentation_config
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var profile: Variant = facts.profile
	_profile = profile if profile is Dictionary else {}
	if not is_instance_valid(_flank) and is_instance_valid(_pony):
		_flank = _pony.get_node_or_null("FlankTouch")


## The act camera position; the path anchors are chosen on the side it actually sees.
func _hand_driver() -> Node:
	if facts == null:
		return null
	if _pose_family() == "bed":
		var body := facts.missionary_body() as POSES.PoseActBody
		return body.node() if body != null and body.live() else null
	var driver: Variant = facts.pose_driver()
	if is_instance_valid(driver) and driver is Node:
		return driver as Node
	return null


func _pose_family() -> String:
	var view: Variant = facts.pose_view if facts != null else null
	return str(view.family) if view != null else ""


func _smack_config() -> MODEL.SmackPresentation:
	var smack: Variant = _presentation_cfg.get("smack", {})
	if smack is Dictionary:
		return MODEL.SmackPresentation.from_dict(smack)
	return MODEL.SmackPresentation.new()
