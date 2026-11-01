extends Node
## Ten seconds of post-sex body language: head and tail lower, no wandering, no new act.
## Created by the runtime after restore. Runs independently of the act state.

const POSE := preload("res://mods/unfunfunf/aftercare_pose.gd")
const DURATION := 10.0
const FADE := 0.6
const OWNER := "unfunfunf:aftercare"

var pony: Node3D
var runtime: Node
var body_language := true

var _left := DURATION
var _fade := 0.0
var _done := false
var _nav: Node
var _nav_owner := ""
var _nav_wander := true
var _body: Node
var _tail: Node


func _ready() -> void:
	process_physics_priority = 90
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	pony.set_meta("sex_aftercare", true)
	if body_language:
		var skeleton: Variant = pony.get("skeleton")
		if skeleton is Skeleton3D:
			_body = POSE.new()
			_body.name = "UnfunfunfAftercareBody"
			_body.set("pony", pony)
			_body.set("mode", "body")
			(skeleton as Skeleton3D).add_child(_body)
		var hair: Variant = pony.get("hair_skeleton")
		if hair is Skeleton3D:
			_tail = POSE.new()
			_tail.name = "UnfunfunfAftercareTail"
			_tail.set("pony", pony)
			_tail.set("mode", "tail")
			(hair as Skeleton3D).add_child(_tail)
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
	if _left <= 0.0:
		_fade = FADE
		if is_instance_valid(_body):
			_body.set("target_amount", 0.0)
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
	if is_instance_valid(_body):
		_body.queue_free()
		_body = null
	if is_instance_valid(_tail):
		_tail.queue_free()
		_tail = null
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
