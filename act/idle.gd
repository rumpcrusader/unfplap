extends RefCounted
## The idle side of the runtime's physics tick. The runtime keeps the ordered tick; this module
## runs the idle-only work after the early return: the inventory safety, the standing
## presentation's physics and the dialogue history scan.
##
## See `docs/runtime.md` and `docs/perf.md`.

const HUD := preload("res://mods/unfplap/hud/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")

var host: ACT_NODE = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## One idle physics tick. `idle_perf` is the runtime's cached probe gate; the chunk labels and the
## clock calls stay identical to the inline schedule this replaces.
func tick(delta: float, idle_perf: bool) -> void:
	# Last-resort safety: a missed exit path must not leave the quick slots hidden.
	if is_instance_valid(HUD.instance):
		HUD.instance.ensure_act_inventory_visible(PONIES.active())
	var presentation_started := Time.get_ticks_usec() if idle_perf else 0
	context.presentation.physics(delta)
	if idle_perf:
		host.perf_note("runtime_presentation", Time.get_ticks_usec() - presentation_started)
	var history_started := Time.get_ticks_usec() if idle_perf else 0
	history_tick(delta)
	if idle_perf:
		host.perf_note("runtime_history", Time.get_ticks_usec() - history_started)


## Idle-only history scan. `dialogue/service.gd` reads the scene and owns the decisions and the
## line queueing.
func history_tick(delta: float) -> void:
	var values: ACT_CONTEXT.Values = context.values
	context.dialogue.history_tick(delta, host.pony as Node3D, values.pony_id, values.event_id,
		session._clock_s)
