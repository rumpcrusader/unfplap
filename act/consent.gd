extends RefCounted
## The act's consent response. One frame asks `readiness/service.gd` for the meter's decision and
## turns it into the act's cue, face beat and one generated line; a stop decision is reported to
## the runtime, which ends the act through the one exit. The meter's math and tiers stay in
## `readiness/tolerance.gd`.
##
## See `docs/runtime.md` and `docs/readiness.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")

const State := ACT_STATE.State

## One frame's verdict. Only `STOP` is a verb for the runtime; `WARN` presented itself.
const NONE := 0
const WARN := 1
const STOP := 2

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
## The queued warning line, so a later warning or a stop can cancel it. Consent owns its one line.
var warning_key := ""
## The reason text of the last stop decision (`smack`, `debug`, ...).
var stop_kind := ""


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in


## A new act: no line from the last one can still be owned.
func reset() -> void:
	warning_key = ""
	stop_kind = ""


## One meter frame in POSING_IN/ACTIVE. A forced debug warning or stop is consumed here so it lands
## on the next frame after the Debug panel closes.
func tick(delta: float) -> int:
	if session.state not in [State.POSING_IN, State.ACTIVE]:
		return NONE
	var action: String = context.readiness.take_debug()
	if not action.is_empty():
		if action == "warning":
			warn(1)
			return WARN
		stop_kind = "debug"
		return STOP
	context.readiness.tolerance_tick(delta)
	var decision: Dictionary = context.readiness.take_tolerance_decision()
	if decision.is_empty() or session.stopped_by_her:
		return NONE
	var warning := int(decision.get("warning", 0))
	if warning > 0:
		warn(warning)
		return WARN
	if bool(decision.get("stopped", false)) or bool(decision.get("stop", false)):
		stop_kind = str(decision.get("kind", ""))
		return STOP
	return NONE


## Present one warning: the cue, the face beat, one generated line and the log.
func warn(level: int) -> void:
	var cue := "She doesn't like that." if level <= 1 else "She is warning you."
	context.readiness.set_cue_override(cue, 4.0)
	context.face.ensure_bound(host.pony, host.node)
	context.face.act_beat("warning", _face_context(), session.feature("face_debug"))
	queue_warning(level)
	host.log("neglect warning=%d tier=%s distress=%.1f kind=%s" % [
		level, str(session.preferences.get("tolerance", "normal")),
		context.readiness.distress(), context.readiness.last_dislike()])


## The consent beat's act values: the same two the face table reads at every act moment.
func _face_context() -> Dictionary:
	return {
		"first_time": session.first_time,
		"tolerance": str(session.preferences.get("tolerance", "normal")),
	}


## Queue the warning line. A previous one is cancelled first, so one warning owns one line.
func queue_warning(level: int) -> void:
	if not is_instance_valid(WORLD.game):
		return
	if not warning_key.is_empty():
		MEMORY.instance.cancel_line(warning_key)
	var act_id := session.event_id
	var event_id := "%s:tolerance_warning:%d" % [session.event_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(host.pony) and session.state in [State.POSING_IN, State.ACTIVE] \
			and session.event_id == act_id
	var fallback := ("Don't do that." if level <= 1 else "I said stop that.") \
		+ " Begin with [annoyed] or [calm]."
	warning_key = context.dialogue.reaction_line(
		MEMORY.Reaction.TOLERANCE_WARNING, event_id, fallback, valid)


## The line a stop supersedes must not speak after it.
func cancel_warning() -> void:
	if not warning_key.is_empty() and is_instance_valid(WORLD.game):
		MEMORY.instance.cancel_line(warning_key)
	warning_key = ""


## Open a real consent stop. Returns `{}` when this is not a live act or she already stopped;
## otherwise the preference facts the runtime's stop route applies.
func begin_stop(reason: String) -> Dictionary:
	if session.stopped_by_her or session.state not in [State.POSING_IN, State.ACTIVE]:
		return {}
	session.stopped_by_her = true
	stop_kind = reason
	cancel_warning()
	return {
		"strict": str(session.preferences.get("tolerance", "normal")) == "strict",
		"distress": context.readiness.distress(),
		"tolerance": str(session.preferences.get("tolerance", "normal")),
	}


## The stop's presentation after the exit has run: only Strict asks for space and bucks, and the
## summary owns the impression while the post-act face carries it.
func finish_stop(strict: bool, upset: bool) -> void:
	if strict:
		request_space()
		context.gate.buck_or_push()
	if upset:
		context.face.start_upset("angry" if strict else "annoyed")
	queue_stop_line(strict)


## Strict only: withdraw the bond's standing invitation. A body without the relationship runtime
## is a quiet no-op.
func request_space() -> void:
	if not is_instance_valid(host.pony):
		return
	var rel: Variant = host.pony.get_meta("relationship_runtime") \
		if host.pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("request_space"):
		bonds.call("request_space", session.pony_id)


## One post-act line, presented once the act is IDLE. The summary already says why she stopped.
func queue_stop_line(strict: bool) -> void:
	if not is_instance_valid(WORLD.game):
		return
	var fallback := "Stop. I don't want to continue. Not now. Begin with [angry] or [sad]."
	if strict:
		fallback = "I told you to stop. Get off me and give me space. Begin with [angry] or [sad]."
	var event_id := "tolerance_stop_%s_%d" % [session.pony_id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		return is_instance_valid(host.pony) and session.state == State.IDLE
	context.dialogue.reaction_line(MEMORY.Reaction.TOLERANCE_STOP, event_id, fallback, valid)


## Debug actions run from the paused settings page; the request is consumed on the next frame.
func force(kind: String) -> bool:
	if session.state not in [State.POSING_IN, State.ACTIVE]:
		return false
	context.readiness.request_debug(kind)
	return true
