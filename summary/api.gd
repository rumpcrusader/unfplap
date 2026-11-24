extends Node
## Scope: pony
## Owns the scoring trigger, the grade-aware commit and the peak-memory record.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The world memory the summary commits to; the runtime wires it once.
var memory: MEMORY = null
## The readiness meter and the dialogue the peak reads; the runtime wires them once.
var readiness: READINESS = null
var dialogue: DIALOGUE = null


## Hand the facade its peers; the runtime's composition is the only caller.
func wire(memory_in: MEMORY, readiness_in: READINESS, dialogue_in: DIALOGUE) -> void:
	memory = memory_in
	readiness = readiness_in
	dialogue = dialogue_in

## The scorer's input for one act. The readiness meter owns the counters; `from_dict` is the edge
## that reads the flat snapshot and `to_dict` is the pure scorer's own shape.
class Inputs extends RefCounted:
	var pony_id := ""
	var event_id := ""
	var preferences: Dictionary = {}
	var seconds := 0.0
	var thrusts := 0
	var pony_climaxes := 0
	var talk_liked := 0
	var talk_dislikes := 0
	var touches_liked := 0
	var touch_dislikes: Dictionary = {}
	var player_lines := 0
	var intensity_total := 0
	var intensity_right := 0
	var pattern_total := 0
	var pattern_right := 0
	var ended_early := false
	var stopped_by_her := false
	var form_reveal := false
	var tolerance := "normal"
	var forced := false

	## The edge: the act's flat snapshot document.
	static func from_dict(context: Dictionary) -> Inputs:
		var out := Inputs.new()
		out.pony_id = str(context.get("pony_id", ""))
		out.event_id = str(context.get("event_id", ""))
		var preference_value: Variant = context.get("preferences", {})
		if preference_value is Dictionary:
			out.preferences = preference_value
		var dislike_value: Variant = context.get("touch_dislikes", {})
		if dislike_value is Dictionary:
			out.touch_dislikes = dislike_value
		out.seconds = float(context.get("seconds", 0.0))
		out.thrusts = int(context.get("thrusts", 0))
		out.pony_climaxes = int(context.get("pony_climaxes", 0))
		out.talk_liked = int(context.get("talk_liked", 0))
		out.talk_dislikes = int(context.get("talk_dislikes", 0))
		out.touches_liked = int(context.get("touches_liked", 0))
		out.player_lines = int(context.get("player_lines", 0))
		out.intensity_total = int(context.get("intensity_total", 0))
		out.intensity_right = int(context.get("intensity_right", 0))
		out.pattern_total = int(context.get("pattern_total", 0))
		out.pattern_right = int(context.get("pattern_right", 0))
		out.ended_early = bool(context.get("ended_early", false))
		out.stopped_by_her = bool(context.get("stopped_by_her", false))
		out.form_reveal = bool(context.get("form_reveal", false))
		out.forced = bool(context.get("forced", false))
		return out

	## The pure scorer's shape: no identity, a detached dislike map and the derived tolerance.
	func to_dict() -> Dictionary:
		return {
			"preferences": preferences,
			"seconds": seconds,
			"thrusts": thrusts,
			"pony_climaxes": pony_climaxes,
			"talk_liked": talk_liked,
			"talk_dislikes": talk_dislikes,
			"touches_liked": touches_liked,
			"touch_dislikes": touch_dislikes.duplicate(true),
			"player_lines": player_lines,
			"intensity_total": intensity_total,
			"intensity_right": intensity_right,
			"pattern_total": pattern_total,
			"pattern_right": pattern_right,
			"ended_early": ended_early,
			"stopped_by_her": stopped_by_her,
			"form_reveal": form_reveal,
			"tolerance": tolerance,
			"forced": forced,
		}


## One act's committed summary or peak record: who it belongs to, the scorer's input and the peak
## counters. The session fills one at each commit boundary.
class Context extends RefCounted:
	var pony_id := ""
	var event_id := ""
	var inputs: Inputs = null
	var satisfaction := 0.0
	var both_matches := 0
	var dislikes := 0
	var liked_touch := 0
	var liked_talk := 0
	var player_talk := ""
	var her_at := -1e9
	var her_line := ""

	static func of(inputs: Inputs) -> Context:
		var out := Context.new()
		if inputs != null:
			out.pony_id = inputs.pony_id
			out.event_id = inputs.event_id
			out.inputs = inputs
		return out


## The act values one summary records. The session fills one at each commit boundary; the
## readiness and dialogue facades supply the action counters and the spoken line.
class ActInput extends RefCounted:
	var pony_id := ""
	var event_id := ""
	var preferences: Dictionary = {}
	var seconds := 0.0
	var ended_early := false
	var stopped_by_her := false
	var form_reveal := false
	var act_spoken_at := -1e9

	## The scorer's input for this act. The readiness meter owns the counters.
	func as_inputs(readiness: READINESS) -> Inputs:
		var out := Inputs.new()
		out.pony_id = pony_id
		out.event_id = event_id
		out.preferences = preferences
		out.seconds = seconds
		out.thrusts = readiness.act_thrusts
		out.pony_climaxes = readiness.pony_climaxes
		out.talk_liked = readiness.act_liked_talk
		out.talk_dislikes = readiness.act_talk_dislikes
		out.touches_liked = readiness.act_liked_touch
		out.touch_dislikes = readiness.act_touch_dislikes
		out.player_lines = readiness.act_player_lines
		out.intensity_total = readiness.act_intensity_total
		out.intensity_right = readiness.act_intensity_right
		out.pattern_total = readiness.act_pattern_total
		out.pattern_right = readiness.act_pattern_right
		out.ended_early = ended_early
		out.stopped_by_her = stopped_by_her
		out.form_reveal = form_reveal
		return out


## The committed summary, empty until one is written.
var summary: Dictionary = {}
var summary_done := false
var peak_recorded := false


## Start a fresh act: clear the summary and the peak flag.
func reset_act() -> void:
	summary = {}
	summary_done = false
	peak_recorded = false


## The summary inputs the pure scorer reads. The runtime gathers its act counters and the scene
## values; the facade owns the shape `summary/score.gd` scores, so a new input lands in one place.
func summary_inputs(context: Inputs) -> Inputs:
	var out := Inputs.new()
	out.pony_id = context.pony_id
	out.event_id = context.event_id
	out.preferences = context.preferences
	out.seconds = context.seconds
	out.thrusts = context.thrusts
	out.pony_climaxes = context.pony_climaxes
	out.talk_liked = context.talk_liked
	out.talk_dislikes = context.talk_dislikes
	out.touches_liked = context.touches_liked
	out.touch_dislikes = context.touch_dislikes.duplicate(true)
	out.player_lines = context.player_lines
	out.intensity_total = context.intensity_total
	out.intensity_right = context.intensity_right
	out.pattern_total = context.pattern_total
	out.pattern_right = context.pattern_right
	out.ended_early = context.ended_early
	out.stopped_by_her = context.stopped_by_her
	out.form_reveal = context.form_reveal
	out.tolerance = str(out.preferences.get("tolerance", "normal"))
	out.forced = context.forced
	return out


## The context `commit_summary()` takes: the ids plus the normalised inputs above.
func summary_context(context: Inputs) -> Context:
	var out := Context.of(summary_inputs(context))
	if not context.pony_id.is_empty():
		out.pony_id = context.pony_id
	if not context.event_id.is_empty():
		out.event_id = context.event_id
	return out


## Score one act from its typed input. The readiness meter owns the counters.
func commit_act(values: ActInput, real_act: bool) -> void:
	commit_summary(real_act, summary_context(values.as_inputs(readiness)))


## Store the strongest clean act per mare from the typed input and the last spoken line.
func record_act_peak(values: ActInput) -> void:
	var context := summary_context(values.as_inputs(readiness))
	context.satisfaction = readiness.peak_satisfaction
	context.both_matches = readiness.act_both_matches
	context.dislikes = readiness.act_dislikes
	context.liked_touch = readiness.act_liked_touch
	context.liked_talk = readiness.act_liked_talk
	context.player_talk = readiness.last_player_talk
	context.her_at = dialogue.last_spoken_at()
	context.her_line = dialogue.last_spoken_line()
	record_peak_memory(context, values.act_spoken_at)


## The after-act record in one place: the summary, the peak and the witness pass.
func commit_after_act(values: ActInput, pony_name: String, serial: int, pony: Node) -> void:
	commit_act(values, true)
	record_act_peak(values)
	if not is_instance_valid(WORLD.world_root()):
		return
	for row: MEMORY.Witness in memory.witnesses(values.pony_id, pony_name, serial, pony):
		LOG.debug("witness %s", [row.to_dict()])


## One summary per act. It is scored from the action counters, stored in the world's module
## state, and written to the game's impression once. Forced stops never call it.
func commit_summary(real_act: bool, context: Context) -> void:
	if summary_done:
		return
	summary_done = true
	if not _game_ok():
		return
	var inputs: Dictionary = context.inputs.to_dict()
	var outcome: Dictionary = ACT_SUMMARY.evaluate(inputs, ACT_SUMMARY.rules())
	if bool(outcome.get("skip", false)):
		LOG.debug("summary skip reasons=%s seconds=%.1f thrusts=%d", [
			_reasons(outcome), float(inputs.get("seconds", 0.0)),
			int(inputs.get("thrusts", 0))])
		return
	summary = outcome
	var id := context.pony_id
	var event_id := context.event_id
	var result: Dictionary = ACT_HISTORY.commit(
		WORLD.mods().state(ACT_HISTORY.MOD_ID).rows, id, outcome, ACT_HISTORY.day_now())
	WORLD.mods().save()
	var impression := MEMORY.Impression.new()
	impression.id = id
	impression.event_id = event_id
	impression.slot = MEMORY.ImpressionSlot.ACT if real_act else MEMORY.ImpressionSlot.ACT_EARLY
	impression.mood = str(outcome.get("mood", "relaxed"))
	impression.romance = int(outcome.get("romance", 0))
	impression.thought = str(outcome.get("thought", ""))
	impression.event_text = str(outcome.get("text", ""))
	memory.commit(impression)
	var row: Dictionary = result.get("row", {})
	var events: PackedStringArray = []
	var raw_events: Variant = result.get("events", [])
	if raw_events is Array:
		for item: Variant in raw_events:
			events.append(str(item))
	LOG.debug("summary grade=%s quality=%.2f checks=%d/%d reasons=%s tier=%s hurt=%d comfort=%d events=%s", [
		str(outcome.get("grade", "neutral")), float(outcome.get("quality", 0.0)),
		int(outcome.get("right", 0)), int(outcome.get("total", 0)),
		_reasons(outcome), ACT_HISTORY.tier_name(row),
		int(row.get("hurt", 0)), int(row.get("comfort", 0)), ",".join(events)])


## Store the strongest clean act per mare. The exchange is the useful part: a later cue can
## infer that she liked it without any name-specific instruction.
func record_peak_memory(context: Context, act_spoken_at: float) -> void:
	if peak_recorded:
		return
	peak_recorded = true
	if not _game_ok():
		return
	if not summary.is_empty() and not bool(summary.get("positive", false)):
		return
	var peak_satisfaction := context.satisfaction
	var both := context.both_matches
	var dislikes := context.dislikes
	if not RELATIONSHIP_CUE.peak_eligible(peak_satisfaction, both, dislikes):
		return
	var player := context.player_talk.strip_edges()
	var her := ""
	if context.her_at > act_spoken_at:
		her = context.her_line.strip_edges()
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
		context.liked_touch, context.liked_talk, dislikes)
	var peak := MEMORY.Peak.new()
	peak.id = context.pony_id
	peak.event_id = context.event_id
	peak.text = text
	peak.score = score
	memory.record_peak(peak)


func _reasons(outcome: Dictionary) -> String:
	var parts: PackedStringArray = []
	var raw: Variant = outcome.get("reasons", [])
	if raw is Array:
		for item: Variant in raw:
			parts.append(str(item))
	return ",".join(parts)


func _game_ok() -> bool:
	return is_instance_valid(WORLD.world_root())


