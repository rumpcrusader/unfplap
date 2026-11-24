extends Node
## Scope: pony
## The act hand layer: caress, shoulder reach, smack and palm-on-coat contact.

const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const CONTROLLER := preload("res://mods/unfplap/hands/controller.gd")
const SELF := preload("res://mods/unfplap/hands/api.gd")

## A hand side; NONE is the smack hand's “no preference” sentinel.
enum Side { NONE, LEFT, RIGHT }

var _controller: CONTROLLER = null


func _init(facts: ACT_FACTS = null) -> void:
	_controller = CONTROLLER.new(facts)


## Drop the controller and its module graph at runtime exit; the runtime calls it once.
func _release() -> void:
	if _controller != null:
		_controller._release()
		_controller = null


## One frame: settle a released reach; when `actionable`, also advance the
## caress and the smack. `actionable` false drops input-driven contact.
func tick(delta: float, actionable: bool) -> void:
	_controller.tick(delta, actionable)


## Retarget on a pose or contact change; the standing ↔ oral pair keeps holds.
func pose_changed(view: POSE_VIEW) -> void:
	_controller.pose_changed(view)


## LEFT/RIGHT start or hold the shoulder reach; NONE releases it.
func set_reach(side: SELF.Side) -> void:
	_controller.set_reach(_side(side))


## True while a shoulder reach still owns a hand.
func reach_active() -> bool:
	return _controller.reach_active()


## Swing one smack from the act input route.
func smack() -> void:
	_controller.smack()


## Idempotent per-act reset; the exit, a fresh act and a body swap call it.
func reset() -> void:
	_controller.reset()


## True while either hand holds a caress.
func any_active() -> bool:
	return _controller.any_active()


func _side(side: SELF.Side) -> MODEL.Side:
	match side:
		Side.LEFT:
			return MODEL.Side.LEFT
		Side.RIGHT:
			return MODEL.Side.RIGHT
		_:
			return MODEL.Side.NONE
