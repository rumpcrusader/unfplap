extends Node
## Ten seconds of post-sex body language: no wandering, no new act, tail held up and flicked.
## Created by the runtime after restore. Runs independently of the act state.

const GAME := preload("res://mods/unfplap/world/game.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")
const DURATION := 10.0
const FADE := 0.6
const OWNER := "unfplap:aftercare"
## Aftercare keeps the tail raised straight (no aside), with smaller periodic flicks.
const TAIL_LIFT := 0.34
const TAIL_FLICK_AMPLITUDE := 0.55
const FLICK_MIN := 1.4
const FLICK_MAX := 2.4

var pony: Node3D = null
var body_language := true

var _left := DURATION
var _fade := 0.0
var _done := false
var _nav: Node = null
var _nav_owner := ""
var _nav_wander := true
var _tail: TAIL = null
var _flick_clock := 0.0


func _ready() -> void:
	process_physics_priority = 90
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	pony.set_meta("sex_aftercare", true)
	if body_language:
		var hair := WORLD.pony(pony).hair_skeleton()
		if hair != null:
			_tail = TAIL.new()
			_tail.name = "UnfplapAftercareTail"
			_tail.mare = pony
			_tail.aside_angle = 0.0
			_tail.lift_angle = TAIL_LIFT
			_tail.flick_amplitude = TAIL_FLICK_AMPLITUDE
			_tail.amount = 0.0
			_tail.target_amount = 1.0
			hair.add_child(_tail)
			_flick_clock = randf_range(FLICK_MIN, FLICK_MAX)
	_nav = GAME.navigator_of(pony)
	if _nav != null:
		var lease := WORLD.navigator(pony)
		_nav_owner = lease.owner()
		_nav_wander = lease.wander()
		lease.stay()
		lease.set_owner(OWNER)
		lease.set_wander(false)


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
		_tail.flick(1)
		_flick_clock = randf_range(FLICK_MIN, FLICK_MAX)
	if _left <= 0.0:
		_fade = FADE
		if is_instance_valid(_tail):
			_tail.target_amount = 0.0


func _hold_nav() -> void:
	if _nav == null or not is_instance_valid(_nav):
		return
	var lease := WORLD.navigator(pony)
	if lease.owner() != OWNER:
		lease.stay()
		lease.set_owner(OWNER)
		lease.set_wander(false)


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(pony):
		pony.remove_meta("sex_aftercare")
	if _nav != null and is_instance_valid(_nav):
		var lease := WORLD.navigator(pony)
		if lease.owner() == OWNER:
			lease.set_owner(_nav_owner)
			lease.set_wander(_nav_wander)
	_nav = null
	if is_instance_valid(_tail):
		_tail.queue_free()
		_tail = null
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
