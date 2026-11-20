extends RefCounted
## The closed `start.setup` adapter set: the bed stand-up, the bed keep-lying and the standing
## place. It never selects on a pose id; a new pose row adds its setup name and data, not a branch
## here. A missing or unknown name is a data error after the gate passed.
##
## See `docs/runtime.md` and `docs/poses.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_VIEW := preload("res://mods/unfplap/act/view.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const REST := preload("res://mods/unfplap/rest/control.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
var view: ACT_VIEW = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		view_in: ACT_VIEW) -> void:
	host = host_in
	context = context_in
	session = session_in
	view = view_in


## Dispatch the spec's setup name. `run()` in the start ledger aborts the partial act on false.
func run(setup: String) -> bool:
	match setup:
		"bed_stand_up":
			return bed_stand_up()
		"bed_keep_lying":
			return bed_keep_lying()
		"standing_place":
			return standing_place()
		_:
			LOG.debug("start blocked setup=%s source=%s pony=%s", [
				setup if not setup.is_empty() else "missing", session.source, host.pony_name()])
			return false


## The bed stand-up start: Anon leaves the mattress before the player snapshot and the lock, and
## she leaves the game's lying state. The bed rest/cradle release already ran in the prelude.
func bed_stand_up() -> bool:
	if session.bed == null:
		return false
	if not session.player_pony:
		var body: Variant = WORLD.player
		if body != null and body.has_method("force_stand_up"):
			body.call("force_stand_up")
	if session.source == "cradle":
		context.rest.bind(host.pony, session.bed)
		context.rest.place_on_start()
	else:
		host.pony.reset_physics_interpolation()
	if host.pony.get("posture") != null:
		host.pony.request_posture("stand")
	return true


## The bed lying start: Anon does not stand up, and the authored act body takes over her pose.
## The riding pose is the first intended consumer; no shipped row uses this setup yet.
func bed_keep_lying() -> bool:
	if session.bed == null:
		return false
	if session.source == "dialogue" and not REST.release_managed(host.pony):
		return false
	host.pony.reset_physics_interpolation()
	if host.pony.get("posture") != null:
		host.pony.request_posture("stand")
	return true


## The standing start: keep her where she stands. The player frame places Anon, takes the stool
## and begins the facing lock after this adapter returns.
func standing_place() -> bool:
	host.pony.request_posture("stand")
	return true
