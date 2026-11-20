extends RefCounted
## The idle side of the frame schedule; `act/tick.gd` still owns the ordered tick and calls in
## after its early return.
##
## See `docs/runtime.md` and `docs/perf.md`.

const HUD := preload("res://mods/unfplap/hud/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

var host: ACT_NODE = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## One idle physics tick: the standing presentation, then the history scan.
func tick(delta: float) -> void:
	# Last-resort safety: a missed exit path must not leave the quick slots hidden.
	if is_instance_valid(HUD.instance):
		HUD.instance.ensure_act_inventory_visible(PONIES.active())
	PERF.begin("runtime_presentation")
	context.presentation.physics(delta)
	PERF.end("runtime_presentation")
	PERF.begin("runtime_history")
	history_tick(delta)
	PERF.end("runtime_history")


## Idle-only history scan. `dialogue/service.gd` reads the scene and owns the decisions and the
## line queueing.
func history_tick(delta: float) -> void:
	context.dialogue.history_tick(delta, host.pony as Node3D, session.pony_id, session.event_id,
		session.clock_s())
