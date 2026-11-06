extends Node
## Short post-stop posture: a tucked tail for 20 seconds. It owns no navigator and no
## aftercare state, so the pony can stand, walk or talk normally while it fades.

const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const DURATION := 20.0
const FADE := 0.8
const TUCK_LIFT := -0.34

var pony: Node3D
var runtime: Node

var _left := DURATION
var _fade := 0.0
var _done := false
var _tail: Node


func _ready() -> void:
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		_tail = TAIL.new()
		_tail.name = "UnfplapTuckedTail"
		_tail.set("mare", pony)
		_tail.set("aside_angle", 0.0)
		_tail.set("lift_angle", TUCK_LIFT)
		_tail.set("flick_amplitude", 0.0)
		_tail.set("amount", 0.0)
		_tail.set("target_amount", 1.0)
		(hair as Skeleton3D).add_child(_tail)


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
	_left -= delta
	if _left <= 0.0:
		_fade = 1.0
		if is_instance_valid(_tail):
			_tail.set("target_amount", 0.0)


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_tail):
		_tail.queue_free()
		_tail = null
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
