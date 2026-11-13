extends RefCounted
## Wing hold, spread, flutter and afterglow fold. The runtime owns the act state; this controller
## only drives the pony's wing node and the wing-sweep skeleton modifier.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const WING_SWEEP := preload("res://mods/unfplap/wing_sweep.gd")

const READINESS_MAX := 100.0
const WING_FADE_SECONDS := 2.20
const WING_FLICK_DECAY := 1.80
const WING_FLICK_MIN := 0.10
const WING_FLICK_MAX := 0.24
const WING_SPREAD_SECONDS := 8.0
const WING_DROOP_SECONDS := 40.0
const WING_DROOP_AMOUNT := 0.35
const WING_JITTER_AMOUNT := 0.04
const WING_JITTER_MIN := 1.6
const WING_JITTER_MAX := 4.0
const WING_JITTER_FADE := 0.8
const WING_STANDING_HOLD := 0.65
const WING_STANDING_SPREAD := 0.25
const WING_AFTERGLOW_RETURN_SECONDS := 6.0
const WING_FLUTTER_COOLDOWN_S := 1.80
const WING_SWEEP_DEG := 10.0

## The typed act view: her node and the act clock. The perf/log hooks stay callbacks.
var facts: Variant
var log := Callable()

var _winged := false
var _wing_clock := 0.0
var _flutter_clock := 0.0
var _wing_hold := false
var _wing_flick := 0.0
var _wing_hold_value := 1.0
var _wing_hold_started := false
var _wing_jitter := 0.0
var _wing_jitter_goal := 0.0
var _wing_jitter_clock := 0.0
var _last_wing_flutter := -1000.0
var _wings_node: Node
var _wing_sweep: SkeletonModifier3D
var _wing_returning := false
var _wing_return_done := false
var _wing_return_node: Node
var _wing_return_progress := 0.0
var _wing_return_from_tuck := 0.0
var _wing_return_from_half := 0.0


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


func reset() -> void:
	var pony: Variant = facts.pony if facts != null else null
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	_winged = identity != null and identity.has_method("has_wings") \
		and bool(identity.call("has_wings"))
	_wing_clock = 0.0
	_flutter_clock = randf_range(1.0, 3.0)
	_wing_hold = false
	_wing_flick = 0.0
	_wing_hold_value = 1.0
	_wing_hold_started = false
	_wing_jitter = 0.0
	_wing_jitter_goal = 0.0
	_wing_jitter_clock = 0.0
	_last_wing_flutter = -1000.0
	_wing_returning = false
	_wing_return_done = false
	_wing_return_node = null
	_wing_return_progress = 0.0
	_clear_wing_sweep()
	_wings_node = null


## Per-tick wing presentation. The runtime still owns the blush, face and act clock.
func tick(delta: float, pose_id: String, satisfaction: float, act_seconds: float) -> void:
	if not _winged:
		return
	var pony: Variant = facts.pony if facts != null else null
	if not is_instance_valid(pony):
		return
	if _wing_returning:
		_wing_return_tick(delta)
		return
	var excitement: Variant = pony.get("excitement")
	if excitement == null:
		return
	_wing_flick = move_toward(_wing_flick, 0.0, delta / WING_FLICK_DECAY)
	if not _wing_hold:
		var wings: Variant = excitement.call("_wings") if excitement.has_method("_wings") else null
		if wings is Node and (wings as Node).has_method("hold_at"):
			_wings_node = wings as Node
			_wing_hold = bool(_wings_node.call("hold_at", "unfplap", 1.0))
	if _wing_hold and is_instance_valid(_wings_node):
		var level := sqrt(clampf(satisfaction / READINESS_MAX, 0.0, 1.0))
		var spread_t := smoothstep(0.0, 1.0, clampf(act_seconds / WING_SPREAD_SECONDS, 0.0, 1.0))
		var base_target := 1.0 - spread_t
		if pose_id != CATALOG.MISSIONARY:
			base_target = clampf(WING_STANDING_HOLD - level * spread_t * WING_STANDING_SPREAD,
				0.0, 1.0)
		var droop := clampf(act_seconds / WING_DROOP_SECONDS, 0.0, 1.0) * WING_DROOP_AMOUNT
		_wing_jitter_clock -= delta
		if _wing_jitter_clock <= 0.0:
			_wing_jitter_goal = randf_range(-WING_JITTER_AMOUNT, WING_JITTER_AMOUNT)
			_wing_jitter_clock = randf_range(WING_JITTER_MIN, WING_JITTER_MAX)
		_wing_jitter = move_toward(_wing_jitter, _wing_jitter_goal, delta / WING_JITTER_FADE)
		var target_hold := clampf(base_target + droop + _wing_flick + _wing_jitter, 0.0, 1.0)
		if not _wing_hold_started:
			_wing_hold_value = 1.0
			_wing_hold_started = true
		_wing_hold_value = move_toward(_wing_hold_value, target_hold, delta / WING_FADE_SECONDS)
		_wings_node.call("hold_at", "unfplap", _wing_hold_value)
		_ensure_wing_sweep(pose_id)
		return
	# Fallback when the half-open wing pose is unavailable.
	if satisfaction >= READINESS_MAX * 0.75:
		_wing_clock -= delta
		if _wing_clock <= 0.0:
			_wing_clock = 2.0
			excitement.call("spread", 4.0)
		return
	_flutter_clock -= delta
	if _flutter_clock <= 0.0 and excitement.has_method("flutter"):
		var now: float = facts.clock() if facts != null else 0.0
		if now - _last_wing_flutter >= WING_FLUTTER_COOLDOWN_S:
			excitement.call("flutter")
			_last_wing_flutter = now
		_flutter_clock = randf_range(4.8, 9.2)


## A thrust sets the wing flick and occasionally flutters them. Keeping this here means the
## runtime thrust handler does not need to know about wing state.
func on_thrust(impact: float) -> void:
	_wing_flick = lerpf(WING_FLICK_MIN, WING_FLICK_MAX, impact)
	if not _winged or _wing_hold:
		return
	var now: float = facts.clock() if facts != null else 0.0
	if now - _last_wing_flutter < WING_FLUTTER_COOLDOWN_S:
		return
	var pony: Variant = facts.pony if facts != null else null
	var excitement: Variant = pony.get("excitement") if is_instance_valid(pony) else null
	if excitement != null and excitement.has_method("flutter"):
		excitement.call("flutter")
		_last_wing_flutter = now


func release() -> void:
	if _wing_returning:
		if is_instance_valid(_wing_return_node):
			_wing_return_node.set_process(true)
		_wing_returning = false
		_wing_return_done = false
		_wing_return_node = null
		_wing_return_progress = 0.0
		_clear_wing_sweep()
		_wing_hold = false
		_wing_hold_started = false
		_wings_node = null
		return
	if _wing_hold and is_instance_valid(_wings_node) and _wings_node.has_method("release_hold"):
		_wings_node.call("release_hold", "unfplap")
	_clear_wing_sweep()
	_wing_hold = false
	_wing_hold_started = false
	_wings_node = null


## Afterglow: clear the act's wing hold, then drive the same WingTuck blend to a full fold
## over WING_AFTERGLOW_RETURN_SECONDS. The game's own release path only takes 0.3 s.
func begin_afterglow() -> void:
	if not _winged or not is_instance_valid(_wings_node) \
			or not _wings_node.has_method("release_hold"):
		return
	var wings: Node = _wings_node
	_clear_wing_sweep()
	wings.call("release_hold", "unfplap")
	wings.call("set_open", false)
	var tuck_value: Variant = wings.get("tuck")
	var half_value: Variant = wings.get("half")
	_wing_return_from_tuck = float(tuck_value) if tuck_value != null else 0.0
	_wing_return_from_half = float(half_value) if half_value != null else 0.0
	_wing_return_node = wings
	_wing_return_progress = 0.0
	_wing_return_done = false
	_wing_returning = true
	wings.set("opened", false)
	wings.set_process(false)
	_wing_hold = false
	_wing_hold_started = false
	_log("wing afterglow return %.1fs from tuck=%.2f half=%.2f" % [
		WING_AFTERGLOW_RETURN_SECONDS, _wing_return_from_tuck, _wing_return_from_half])


func _wing_return_tick(delta: float) -> void:
	if not is_instance_valid(_wing_return_node):
		_wing_returning = false
		_wing_return_done = false
		_wing_return_node = null
		return
	if _wing_return_done:
		return
	_wing_return_progress = minf(1.0,
		_wing_return_progress + delta / maxf(WING_AFTERGLOW_RETURN_SECONDS, 0.001))
	var eased := smoothstep(0.0, 1.0, _wing_return_progress)
	_wing_return_node.set("tuck", lerpf(_wing_return_from_tuck, 1.0, eased))
	_wing_return_node.set("half", lerpf(_wing_return_from_half, 0.0, eased))
	_wing_return_node.set("opened", false)
	_wing_return_node.set_process(false)
	if _wing_return_progress >= 1.0:
		_wing_return_done = true
		# The wing node's own process finalizes the fold: hides the open meshes, shows folded.
		_wing_return_node.set_process(true)
		_log("wing afterglow return complete")


func _ensure_wing_sweep(pose_id: String) -> void:
	var pony: Variant = facts.pony if facts != null else null
	if pose_id != CATALOG.STANDING or not _wing_hold or not is_instance_valid(pony):
		_clear_wing_sweep()
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	if not is_instance_valid(_wing_sweep):
		var sweep: Node3D = WING_SWEEP.new()
		sweep.name = "UnfplapWingSweep"
		skeleton.add_child(sweep)
		sweep.call("setup", skeleton, WING_SWEEP_DEG)
		_wing_sweep = sweep as SkeletonModifier3D
		_log("wing sweep %.0f deg" % WING_SWEEP_DEG)
	var last := skeleton.get_child_count() - 1
	if _wing_sweep.get_index() != last:
		skeleton.move_child(_wing_sweep, last)
	_wing_sweep.set("amount", 1.0)


func _clear_wing_sweep() -> void:
	if is_instance_valid(_wing_sweep):
		_wing_sweep.queue_free()
	_wing_sweep = null


func _log(text: String) -> void:
	if log.is_valid():
		log.call(text)
