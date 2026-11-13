extends RefCounted
## Service: summary. The act's grade and its post-act record. The runtime owns the act state, the
## scene stop executor and the line/face presentation; this system owns the scoring trigger, the
## grade-aware commit and the peak-memory record. The idle apology/reminder scan is lines and the
## neglect meter is readiness. See docs/summary.md.

const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")

## The committed summary, empty until one is written.
var summary: Dictionary = {}
var summary_done := false
var peak_recorded := false

## Host boundary. A missing callable is a no-op.
var log := Callable()


## Start a fresh act: clear the summary and the peak flag.
func reset_act() -> void:
	summary = {}
	summary_done = false
	peak_recorded = false


## The summary inputs the pure scorer reads. The runtime gathers its act counters and the scene
## values; the facade owns the shape `summary/score.gd` scores, so a new input lands in one place.
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
