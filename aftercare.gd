extends Node
## Ten seconds of post-sex body language: no wandering, no new act, tail held up and flicked.
## Created by the runtime after restore. Runs independently of the act state.

const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const DOCK_TAIL := preload("res://mods/unfplap/dock_tail_follow.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const DURATION := 10.0
const FADE := 0.6
const OWNER := "unfplap:aftercare"
## Aftercare keeps the tail raised straight (no aside), with smaller periodic flicks.
const TAIL_LIFT := 0.34
const TAIL_FLICK_AMPLITUDE := 0.55
const FLICK_MIN := 1.4
const FLICK_MAX := 2.4

var pony: Node3D
var runtime: Node
var body_language := true

var _left := DURATION
var _fade := 0.0
var _done := false
var _nav: Node
var _nav_owner := ""
var _nav_wander := true
var _tail: Node
var _dock: Node
var _flick_clock := 0.0


func _ready() -> void:
	process_physics_priority = 90
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	pony.set_meta("sex_aftercare", true)
	if body_language:
		var hair: Variant = pony.get("hair_skeleton")
		if hair is Skeleton3D:
			_tail = TAIL.new()
			_tail.name = "UnfplapAftercareTail"
			_tail.set("mare", pony)
			_tail.set("aside_angle", 0.0)
			_tail.set("lift_angle", TAIL_LIFT)
			_tail.set("flick_amplitude", TAIL_FLICK_AMPLITUDE)
			_tail.set("amount", 0.0)
			_tail.set("target_amount", 1.0)
			(hair as Skeleton3D).add_child(_tail)
			# The post-act tail lift and flicks are the same tail motion; carry the dock with
			# them too instead of dropping back to the rump-only dock.
			if TUNABLES.get_bool("features.dock_tail_follow"):
				_dock = DOCK_TAIL.new()
				_dock.name = "UnfplapAftercareDock"
				_dock.set("mare", pony)
				_dock.set("runtime", runtime)
				_dock.set("process_priority", 40)
				(hair as Skeleton3D).add_child(_dock)
			_flick_clock = randf_range(FLICK_MIN, FLICK_MAX)
	_nav = pony.get_node_or_null("Navigator")
	if _nav != null:
		_nav_owner = str(_nav.get("command_owner"))
		_nav_wander = bool(_nav.get("wander_enabled"))
		_nav.call("stay")
		_nav.set("command_owner", OWNER)
		_nav.set("wander_enabled", false)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		_finish()
		return
	if _fade > 0.0:
		_fade -= delta
		if _fade <= 0.0:
			_finish()
		return
	_hold_nav()
	_left -= delta
	_flick_clock -= delta
	if _flick_clock <= 0.0 and is_instance_valid(_tail):
		_tail.call("flick", 1)
		_flick_clock = randf_range(FLICK_MIN, FLICK_MAX)
	if _left <= 0.0:
		_fade = FADE
		if is_instance_valid(_tail):
			_tail.set("target_amount", 0.0)


func _hold_nav() -> void:
	if _nav == null or not is_instance_valid(_nav):
		return
	if str(_nav.get("command_owner")) != OWNER:
		_nav.call("stay")
		_nav.set("command_owner", OWNER)
		_nav.set("wander_enabled", false)


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(pony):
		pony.remove_meta("sex_aftercare")
	if _nav != null and is_instance_valid(_nav):
		if str(_nav.get("command_owner")) == OWNER:
			_nav.set("command_owner", _nav_owner)
			_nav.set("wander_enabled", _nav_wander)
	_nav = null
	if is_instance_valid(_dock):
		_dock.call("restore")
		_dock.queue_free()
	_dock = null
	if is_instance_valid(_tail):
		_tail.queue_free()
	_tail = null
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
