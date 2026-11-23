extends RefCounted
## Picks a provider by contact kind and keeps one cached per body.

const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const PATH_BASE := preload("res://mods/unfplap/hands/path_base.gd")
const FLANK_PATH := preload("res://mods/unfplap/hands/paths/standing.gd")
const MISSIONARY_PATH := preload("res://mods/unfplap/hands/paths/missionary.gd")
const ORAL_PATH := preload("res://mods/unfplap/hands/paths/oral.gd")

var _missionary_path: MISSIONARY_PATH = null
var _flank_path: FLANK_PATH = null
var _oral_path: ORAL_PATH = null


## The current pose's path provider; the contact kind chooses the oral head path.
func path(pony: Node3D, facts: ACT_FACTS) -> PATH_BASE:
	if facts == null or not is_instance_valid(pony):
		return null
	var view: Variant = facts.pose_view
	if view == null:
		return null
	var path_id := str(view.hands.get("path", ""))
	if path_id == "missionary":
		if _missionary_path == null:
			_missionary_path = MISSIONARY_PATH.new()
		if _missionary_path.pony != pony:
			_missionary_path.setup(pony, facts)
			_missionary_path.reset()
		return _missionary_path
	if path_id not in ["standing", "oral"]:
		return null
	if str(view.contact_kind) == "mouth":
		if _oral_path == null:
			_oral_path = ORAL_PATH.new()
		if _oral_path.pony != pony:
			_oral_path.setup(pony, facts)
			_oral_path.reset()
		return _oral_path
	if _flank_path == null:
		_flank_path = FLANK_PATH.new()
	if _flank_path.pony != pony:
		_flank_path.setup(pony, facts)
		_flank_path.reset()
	return _flank_path


func reset() -> void:
	if _missionary_path != null:
		_missionary_path.reset()
	if _flank_path != null:
		_flank_path.reset()
	if _oral_path != null:
		_oral_path.reset()
