extends "res://mods/unfplap/integrations/provider.gd"
## Idle Life stretch bridge. When the act feature is on, Idle Life is active this launch, the
## pose is standing and the act pose node is bound, this provider asks the act pose node to run
## in stretch mode. The pose session owns the external script; this provider never touches Idle
## Life's files or any scene node beyond the one binding it sets.

const ACTION := preload("res://mods/unfplap/integrations/action.gd")
const FEATURE := "idle_life_stretch"

var _start_stretch := ACTION.set_value("pose", "stretch", true)


func available(context: RefCounted) -> bool:
	if not context.feature(FEATURE):
		return false
	if str(context.get("pose_id")) != "standing":
		return false
	if not bool(context.get("mod_active")):
		return false
	return context.binding("pose")


func start_actions(_context: RefCounted, out: Array) -> void:
	out.append(_start_stretch)