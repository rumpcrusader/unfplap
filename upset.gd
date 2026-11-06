extends Node
## Hold the hostile face that matches the game's impression mood after a refused advance or a
## consent stop. Mares have no mood -> face bridge of their own: the impression note stores
## `annoyed`/`angry` for 300 s but only the profile panel, her dialogue prompt and the willingness
## gates read it. This face makes the mood visible while the note is fresh. It yields to the
## director's line faces and ends as soon as a newer mood replaces ours.

const DURATION := 300.0
const MOOD_FACES := {"annoyed": "annoyed", "angry": "angry"}
## Checking the live impression every frame is unnecessary; half a second is enough.
const MOOD_CHECK_SECONDS := 0.5

var pony: Node3D
var runtime: Node
var mood := "annoyed"

var _left := DURATION
var _check_left := 0.0
var _done := false
var _applied_face := false
var _face := "annoyed"


func _ready() -> void:
	process_physics_priority = 85
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		queue_free()
		return
	_face = str(MOOD_FACES.get(mood, "annoyed"))
	pony.set_meta("unfplap_upset", true)
	_apply_face()


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		_finish()
		return
	_left -= delta
	_check_left -= delta
	if _left <= 0.0:
		_finish()
		return
	if _check_left <= 0.0:
		_check_left = MOOD_CHECK_SECONDS
		if not _mood_still_ours():
			_finish()
			return
	_apply_face()


## The director owns line faces. Use the mood face only while no line face is active, so a spoken
## expression still wins and the mood face returns after it clears.
func _apply_face() -> void:
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions):
		return
	if not expressions.has_method("set_dialogue"):
		return
	if str(expressions.get("dialogue_face")) == "":
		expressions.call("set_dialogue", _face)
		_applied_face = true


## Her AI can commit a newer mood in a later reply. The face must not outlive the note it shows.
func _mood_still_ours() -> bool:
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		return true
	if not is_instance_valid(runtime):
		return true
	var main: Variant = runtime.get("main")
	if main == null or not is_instance_valid(main):
		return true
	var game: Variant = main.get("game")
	if game == null or not is_instance_valid(game):
		return true
	var ctx: Variant = game.get("world_context")
	if ctx == null or not is_instance_valid(ctx):
		return true
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions) or not impressions.has_method("profile"):
		return true
	var profile: Variant = impressions.call("profile", id)
	if not profile is Dictionary:
		return true
	return str((profile as Dictionary).get("mood", "neutral")) == mood


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(pony):
		pony.remove_meta("unfplap_upset")
		var expressions: Variant = pony.get("expressions")
		if expressions != null and is_instance_valid(expressions) and _applied_face \
				and str(expressions.get("dialogue_face")) == _face \
				and expressions.has_method("clear_dialogue"):
			expressions.call("clear_dialogue")
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_finish()
