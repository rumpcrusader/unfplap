extends Node
## After sex, keep a relaxed/satisfied face and a light blush for as long as the game's happy
## mood stays fresh (300 s). It does not hold the navigator and does not block another act.

const DURATION := 300.0
const FACE := "relaxed"
const BLUSH := 0.35

var pony: Node3D
var runtime: Node

var _left := DURATION
var _done := false
var _applied_face := false


func _ready() -> void:
	process_physics_priority = 85
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	pony.set_meta("unfplap_satisfied", true)
	_apply_face()


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		_finish()
		return
	_left -= delta
	if _left <= 0.0:
		_finish()
		return
	_apply_face()
	_apply_blush()


## The director owns line faces. Use the relaxed face only while no line face is active, so a
## spoken expression still wins and the satisfied face returns after it clears.
func _apply_face() -> void:
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions):
		return
	if not expressions.has_method("set_dialogue"):
		return
	if str(expressions.get("dialogue_face")) == "":
		expressions.call("set_dialogue", FACE)
		_applied_face = true


func _apply_blush() -> void:
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", BLUSH)


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_satisfied")
		var expressions: Variant = pony.get("expressions")
		if expressions != null and is_instance_valid(expressions) and _applied_face \
				and str(expressions.get("dialogue_face")) == FACE \
				and expressions.has_method("clear_dialogue"):
			expressions.call("clear_dialogue")
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
