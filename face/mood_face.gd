extends Node
## Holds one base-game expression face after an act, matching the fresh impression mood. It yields
## to any spoken line face and ends after the mood's 300 s freshness. The runtime owns the start
## and the warm prompt note; this node only keeps the face and the light blush.

const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const DURATION := 300.0
const MOOD_FACES := ACT_FACE.MOOD_FACES
const MOOD_CHECK_SECONDS := 0.5

signal finished(reason: String)

var pony: Node3D
## The scene handle the freshness check reads, and the debug log. Both are optional.
var main: Variant = null
var log := Callable()
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
			or not ACT_FACE.valid_face(face):
		queue_free()
		return
	pony.set_meta("unfplap_mood_face", true)
	_apply_face()
	_apply_blush()
	_log("mood face start mood=%s face=%s blush=%.2f" % [mood, face, blush])


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
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions):
		return
	if not expressions.has_method("set_dialogue"):
		return
	if _dialogue_face(expressions).is_empty():
		expressions.call("set_dialogue", face)
		_applied_face = true


func _apply_blush() -> void:
	if blush <= 0.0:
		return
	var boop: Variant = pony.get("boop_node")
	if boop != null and boop.has_method("sustain_blush"):
		boop.call("sustain_blush", blush)


## Her AI can commit a newer mood in a later reply. The face must not outlive the note it shows.
func _mood_still_ours() -> bool:
	if mood.is_empty():
		return true
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		return true
	if not is_instance_valid(main):
		return true
	var game: Variant = main.get("game")
	if game == null or not is_instance_valid(game):
		return true
	var ctx: Variant = game.get("world_context")
	if ctx == null or not is_instance_valid(ctx):
		return true
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions) \
			or not impressions.has_method("profile"):
		return true
	var profile: Variant = impressions.call("profile", id)
	if not profile is Dictionary:
		return true
	return str((profile as Dictionary).get("mood", "neutral")) == mood


func _dialogue_face(expressions: Variant) -> String:
	var value: Variant = expressions.get("dialogue_face")
	if value is String:
		return value
	return ""


func _clear_face() -> void:
	if not _applied_face or not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions) \
			or not expressions.has_method("clear_dialogue"):
		return
	if _dialogue_face(expressions) == face:
		expressions.call("clear_dialogue")


func _finish(reason := "") -> void:
	if _done:
		return
	_done = true
	_clear_face()
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_mood_face")
	_log("mood face end reason=%s mood=%s face=%s" % [reason, mood, face])
	finished.emit(reason)
	queue_free()


func _log(text: String) -> void:
	if not SETTINGS.face_debug.get_bool():
		return
	if log.is_valid():
		log.call(text)


func _exit_tree() -> void:
	if _done:
		return
	_done = true
	_clear_face()
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_mood_face")
	finished.emit("exit")
