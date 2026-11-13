extends RefCounted
## The act's summary, long-term history and neglect tolerance. The runtime owns the act state,
## the scene stop executor and the line/face presentation; this system owns the scoring trigger,
## the grade-aware commit, the peak-memory record, the idle history scan's decisions and the
## tolerance meter. See docs/history.md.

const ACT_SUMMARY := preload("res://mods/unfplap/history/summary.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const ACT_TOLERANCE := preload("res://mods/unfplap/history/tolerance.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")

## The committed summary, empty until one is written.
var summary: Dictionary = {}
var summary_done := false
var peak_recorded := false
## The pure tolerance meter for the current act.
var tolerance
var debug_request := ""

var _turn := -1
var _scan_clock := 0.0
var _reminder_at := -1000.0

## Host boundary. A missing callable is a no-op.
var log := Callable()
## Queue one mod reaction line: `(reaction, event_id, fallback, valid) -> String`.
var reaction_line := Callable()
## True while the runtime is IDLE. Used by the queued line's validity closure.
var idle := Callable()


## Start a fresh act: clear the summary, the peak flag, the debug request and the tolerance meter.
## The pacing and history-scan clocks persist because they belong to the mare, not one act.
func reset_act(profile: Dictionary) -> void:
	summary = {}
	summary_done = false
	peak_recorded = false
	debug_request = ""
	tolerance_controller().reset(profile)


func tolerance_controller():
	if tolerance == null:
		tolerance = ACT_TOLERANCE.new()
	return tolerance


func tolerance_tick(delta: float) -> void:
	if tolerance == null:
		return
	tolerance.tick(delta)


func observe_dislike(kind: String) -> Dictionary:
	return tolerance_controller().observe_dislike(kind)


func observe_like(kind: String) -> void:
	if tolerance != null:
		tolerance.observe_like(kind)


## The tolerance event the runtime should present, or nothing when there is no meter yet.
func tolerance_decision(event: Dictionary) -> Dictionary:
	if event.is_empty() or tolerance == null:
		return {}
	return event


func distress() -> float:
	return float(tolerance.distress) if tolerance != null else 0.0


func last_dislike() -> String:
	return str(tolerance.last_dislike) if tolerance != null else ""


## Debug actions run from the paused settings page; the request is consumed on the next frame.
func request_debug(kind: String) -> void:
	debug_request = kind


## Take and clear one pending debug request.
func take_debug() -> String:
	var action := debug_request
	debug_request = ""
	return action


## The summary inputs the pure scorer reads. The runtime gathers its act counters and the scene
## values; the facade owns the shape `history/summary.gd` scores, so a new input lands in one place.
func summary_inputs(context: Dictionary) -> Dictionary:
	var preference_value: Variant = context.get("preferences", {})
	var preferences: Dictionary = preference_value if preference_value is Dictionary else {}
	var dislike_value: Variant = context.get("touch_dislikes", {})
	var touch_dislikes: Dictionary = dislike_value if dislike_value is Dictionary else {}
	return {
		"preferences": preferences,
		"seconds": float(context.get("seconds", 0.0)),
		"thrusts": int(context.get("thrusts", 0)),
		"pony_climaxes": int(context.get("pony_climaxes", 0)),
		"talk_liked": int(context.get("talk_liked", 0)),
		"talk_dislikes": int(context.get("talk_dislikes", 0)),
		"touches_liked": int(context.get("touches_liked", 0)),
		"touch_dislikes": touch_dislikes.duplicate(true),
		"player_lines": int(context.get("player_lines", 0)),
		"intensity_total": int(context.get("intensity_total", 0)),
		"intensity_right": int(context.get("intensity_right", 0)),
		"pattern_total": int(context.get("pattern_total", 0)),
		"pattern_right": int(context.get("pattern_right", 0)),
		"ended_early": bool(context.get("ended_early", false)),
		"stopped_by_her": bool(context.get("stopped_by_her", false)),
		"tolerance": str(preferences.get("tolerance", "normal")),
		"forced": bool(context.get("forced", false)),
	}


## The context `commit_summary()` takes: the scene handles plus the inputs above.
func summary_context(context: Dictionary) -> Dictionary:
	return {
		"main": context.get("main"),
		"pony_id": str(context.get("pony_id", "")),
		"event_id": str(context.get("event_id", "")),
		"inputs": summary_inputs(context),
	}


## One summary per act. It is scored from the action counters, stored in the world's module
## state, and written to the game's impression once. Forced stops never call it.
func commit_summary(real_act: bool, context: Dictionary) -> void:
	if summary_done:
		return
	summary_done = true
	var main: Variant = context.get("main")
	if not ACT_HISTORY.enabled() or not _game_ok(main):
		return
	var inputs: Dictionary = context.get("inputs", {})
	var outcome: Dictionary = ACT_SUMMARY.evaluate(inputs, ACT_SUMMARY.rules())
	if bool(outcome.get("skip", false)):
		_write_log("summary skip reasons=%s seconds=%.1f thrusts=%d" % [
			_reasons(outcome), float(inputs.get("seconds", 0.0)),
			int(inputs.get("thrusts", 0))])
		return
	summary = outcome
	var id := str(context.get("pony_id", ""))
	var event_id := str(context.get("event_id", ""))
	var result: Dictionary = ACT_HISTORY.commit(ACT_HISTORY.section(), id, outcome,
		ACT_HISTORY.day_now())
	ACT_HISTORY.save()
	var impression := MEMORY.Impression.new()
	impression.id = id
	impression.event_id = event_id
	impression.slot = MEMORY.ImpressionSlot.ACT if real_act else MEMORY.ImpressionSlot.ACT_EARLY
	impression.mood = str(outcome.get("mood", "relaxed"))
	impression.romance = int(outcome.get("romance", 0))
	impression.thought = str(outcome.get("thought", ""))
	impression.event_text = str(outcome.get("text", ""))
	main.memory.commit(impression)
	var row: Dictionary = result.get("row", {})
	var events: PackedStringArray = []
	var raw_events: Variant = result.get("events", [])
	if raw_events is Array:
		for item: Variant in raw_events:
			events.append(str(item))
	_write_log("summary grade=%s quality=%.2f checks=%d/%d reasons=%s tier=%s hurt=%d comfort=%d events=%s" % [
		str(outcome.get("grade", "neutral")), float(outcome.get("quality", 0.0)),
		int(outcome.get("right", 0)), int(outcome.get("total", 0)),
		_reasons(outcome), ACT_HISTORY.tier_name(row),
		int(row.get("hurt", 0)), int(row.get("comfort", 0)), ",".join(events)])


## Store the strongest clean act per mare. The exchange is the useful part: a later cue can
## infer that she liked it without any name-specific instruction.
func record_peak_memory(context: Dictionary, act_spoken_at: float) -> void:
	if peak_recorded:
		return
	peak_recorded = true
	var main: Variant = context.get("main")
	if not _game_ok(main):
		return
	if not summary.is_empty() and not bool(summary.get("positive", false)):
		return
	var peak_satisfaction := float(context.get("satisfaction", 0.0))
	var both := int(context.get("both_matches", 0))
	var dislikes := int(context.get("dislikes", 0))
	if not RELATIONSHIP_CUE.peak_eligible(peak_satisfaction, both, dislikes):
		return
	var player := str(context.get("player_talk", "")).strip_edges()
	var her := ""
	if float(context.get("her_at", -1e9)) > act_spoken_at:
		her = str(context.get("her_line", "")).strip_edges()
	if player.length() > 160:
		player = player.left(160).strip_edges()
	if her.length() > 160:
		her = her.left(160).strip_edges()
	var text := ""
	if not player.is_empty():
		text = "Anon said: \"%s\"." % player
		if not her.is_empty():
			text += " You answered: \"%s\"." % her
	else:
		text = "Anon made you feel completely wanted."
	var score := RELATIONSHIP_CUE.peak_score(peak_satisfaction, both,
		int(context.get("liked_touch", 0)), int(context.get("liked_talk", 0)), dislikes)
	var peak := MEMORY.Peak.new()
	peak.id = str(context.get("pony_id", ""))
	peak.event_id = str(context.get("event_id", ""))
	peak.text = text
	peak.score = score
	main.memory.record_peak(peak)


## Idle-only: a sincere apology repairs once per in-game day, and a pending reminder or
## complaint becomes one short line in a quiet moment.
func tick_idle(delta: float, context: Dictionary) -> void:
	if not ACT_HISTORY.enabled():
		return
	var main: Variant = context.get("main")
	var pony: Variant = context.get("pony")
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return
	if bool(context.get("paused", false)):
		return
	var director: Variant = context.get("director")
	if director == null:
		return
	var now := float(context.get("now", 0.0))
	var turn := int(context.get("turn", 0))
	var text := str(context.get("text", "")).strip_edges()
	if _turn < 0:
		_turn = turn
	elif turn != _turn:
		_turn = turn
		if not text.is_empty() and PREFERENCES.apology_intent(text) \
				and bool(context.get("target_is_player", false)):
			var id := str(context.get("pony_id", ""))
			if ACT_HISTORY.apology_repair(ACT_HISTORY.section(), id, ACT_HISTORY.day_now()):
				ACT_HISTORY.save()
				if is_instance_valid(main.game):
					main.memory.note(MEMORY.NoteKind.APOLOGY, id,
						str(context.get("event_id", "")))
				_write_log("history apology id=%s" % id)
	_scan_clock += delta
	if _scan_clock < 1.0:
		return
	_scan_clock = 0.0
	if now - _reminder_at < 15.0 or bool(context.get("speech_busy", false)):
		return
	if str(context.get("director_state", "")) != "idle":
		return
	if float(context.get("distance", 0.0)) > 5.0:
		return
	var id := str(context.get("pony_id", ""))
	var current := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var kind := ACT_HISTORY.pending_line(current)
	if kind.is_empty():
		return
	if Time.get_unix_time_from_system() - float(current.get("last_at", 0.0)) < 45.0:
		return
	if not reaction_line.is_valid():
		return
	var event_id := "history_%s_%d" % [id, Time.get_ticks_usec()]
	var valid := func() -> bool:
		if not is_instance_valid(pony):
			return false
		if idle.is_valid() and not bool(idle.call()):
			return false
		return true
	var reaction := MEMORY.Reaction.HISTORY_REMINDER if kind == "reminder" \
		else MEMORY.Reaction.HISTORY_COMPLAINT
	var key: String = reaction_line.call(reaction, event_id,
		ACT_HISTORY.line_purpose(current, kind), valid)
	if key.is_empty():
		return
	ACT_HISTORY.mark_announced(ACT_HISTORY.section(), id, kind)
	ACT_HISTORY.save()
	_reminder_at = now
	_write_log("history line kind=%s key=%s" % [kind, key])


func _reasons(outcome: Dictionary) -> String:
	var parts: PackedStringArray = []
	var raw: Variant = outcome.get("reasons", [])
	if raw is Array:
		for item: Variant in raw:
			parts.append(str(item))
	return ",".join(parts)


func _game_ok(main: Variant) -> bool:
	return is_instance_valid(main) and is_instance_valid(main.get("game"))


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
