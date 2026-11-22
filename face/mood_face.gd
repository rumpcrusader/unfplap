extends Node
## The held post-act face node: it yields to a spoken line and ends when the mood's freshness
## does. The facade starts it.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const DURATION := 300.0
const MOOD_FACES := ACT_FACE.MOOD_FACES
const MOOD_CHECK_SECONDS := 0.5

signal finished(reason: String)

var pony: Node3D = null
var mood := ""
var face := ""
var blush := 0.0

var _left := DURATION
var _check_left := 0.0
var _done := false
var _applied_face := false


func _ready() -> void:
	process_physics_priority = 85
	if not is_instance_valid(pony) or not pony.is_inside_tree() or face.is_empty() \
			or not ACT_FACE.valid_face(face, WORLD.face(pony).line_faces()):
		queue_free()
		return
	pony.set_meta("unfplap_mood_face", true)
	_apply_face()
	_apply_blush()
	if SETTINGS.face_debug.get_bool():
		LOG.debug("mood face start mood=%s face=%s blush=%.2f", [mood, face, blush])


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		_finish("invalid")
		return
	_left -= delta
	_check_left -= delta
	if _left <= 0.0:
		_finish("duration")
		return
	if _check_left <= 0.0:
		_check_left = MOOD_CHECK_SECONDS
		if not _mood_still_ours():
			_finish("mood")
			return
	_apply_face()
	_apply_blush()


func _apply_face() -> void:
	var face_view := WORLD.face(pony)
	var controller := face_view.controller()
	if controller == null or not is_instance_valid(controller):
		return
	if not controller.has_method("set_dialogue"):
		return
	if face_view.dialogue_face().is_empty():
		face_view.set_dialogue(face)
		_applied_face = true


func _apply_blush() -> void:
	if blush <= 0.0:
		return
	WORLD.face(pony).sustain_blush(blush)


## Her AI can commit a newer mood in a later reply. The face must not outlive the note it shows.
func _mood_still_ours() -> bool:
	if mood.is_empty():
		return true
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		return true
	var committed := WORLD.director().impression_mood(id)
	if committed.is_empty():
		return true
	return committed == mood


func _clear_face() -> void:
	if not _applied_face or not is_instance_valid(pony):
		return
	var face_view := WORLD.face(pony)
	var controller := face_view.controller()
	if controller == null or not is_instance_valid(controller) \
			or not controller.has_method("clear_dialogue"):
		return
	if face_view.dialogue_face() == face:
		face_view.clear_dialogue()


func _finish(reason := "") -> void:
	if _done:
		return
	_done = true
	_clear_face()
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_mood_face")
	if SETTINGS.face_debug.get_bool():
		LOG.debug("mood face end reason=%s mood=%s face=%s", [reason, mood, face])
	finished.emit(reason)
	queue_free()


func _exit_tree() -> void:
	if _done:
		return
	_done = true
	_clear_face()
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_mood_face")
	finished.emit("exit")
