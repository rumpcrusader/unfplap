extends Node
## Scope: pony
## Scores one finished act and commits its lasting consequences; the act holds the verdict.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ACT_SUMMARY := preload("res://mods/unfplap/summary/score.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const ACT_METER := preload("res://mods/unfplap/shared/act_meter.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The world memory the commit writes to; the runtime wires it once.
var _memory: MEMORY = null


## The act as it ended, assembled once by the act at its verdict. The identity and the ending are
## required; every other value comes from the act's own facts and one readiness read.
class ActSnapshot extends RefCounted:
	## The act's ending: exactly one of these, from the route that ended the act.
	enum Ending { COMPLETE, EARLY, STOPPED }

	var pony_id: String
	var event_id: String
	var seconds: float
	var act_spoken_at: float
	var ending: Ending
	## The player's stored preference document. It stays a dictionary because the game saves it and
	## the pure scorer reads it by key; a missing key reads as no opinion.
	var preferences: Dictionary
	var form_reveal: bool
	var meter: ACT_METER

	func _init(pony_id_in: String, event_id_in: String, ending_in: Ending) -> void:
		pony_id = pony_id_in
		event_id = event_id_in
		ending = ending_in


## Her last spoken line and when, taken by the act at commit time. The pair means nothing apart,
## which is why it is one value and not two arguments.
class Exchange extends RefCounted:
	var at: float
	var line: String

	func _init(at_in: float, line_in: String) -> void:
		at = at_in
		line = line_in


## The act's verdict, frozen once scored; only `score()` builds one. The record stays a dictionary
## because it is the pure scorer's own output, read by the face, the afterglow beat and the history
## store; it is empty on a skip, and `skipped` is what a caller tests.
class ActScore extends RefCounted:
	var pony_id: String
	var event_id: String
	var act_spoken_at: float
	var skipped: bool
	var outcome: Dictionary
	var meter: ACT_METER


## Hand the facade its peer; the runtime's composition is the only caller.
func wire(memory: MEMORY) -> void:
	_memory = memory


## Score one act from its snapshot. Nothing is written and no peer is read, so a caller may shape an
## act before a world exists; the rules come from the live settings the scorer already reads.
func score(snapshot: ActSnapshot) -> ActScore:
	var out := ActScore.new()
	out.pony_id = snapshot.pony_id
	out.event_id = snapshot.event_id
	out.act_spoken_at = snapshot.act_spoken_at
	out.meter = snapshot.meter
	var inputs := _scorer_dict(snapshot)
	var scored: Dictionary = ACT_SUMMARY.evaluate(inputs, ACT_SUMMARY.rules())
	out.skipped = bool(scored.get("skip", false))
	if out.skipped:
		# The scorer's reasons exist only in the record, and a skipped act does not keep one.
		LOG.debug("summary skip reasons=%s seconds=%.1f thrusts=%d", [
			_reasons(scored), float(inputs["seconds"]), int(inputs["thrusts"])])
		return out
	out.outcome = scored
	return out


## Commit one scored act: its history row and save, her impression and the act's peak. A skipped
## act writes nothing, so the route that ended it keeps its own fallback note.
func commit(score: ActScore, exchange: Exchange) -> void:
	if score == null or score.skipped or score.outcome.is_empty():
		return
	if not _game_ok() or not is_instance_valid(_memory):
		return
	var outcome := score.outcome
	var id := score.pony_id
	var result: Dictionary = ACT_HISTORY.commit(
		WORLD.mods().state(ACT_HISTORY.MOD_ID).rows, id, outcome, ACT_HISTORY.day_now())
	WORLD.mods().save()
	# The base game reads her lasting mood from this note for 300 s, and the same note gates resting
	# closeness, hand feeding and her unprompted approaches. The world event is the profile-safe,
	# renamable line; the thought is her private first person.
	var impression := MEMORY.Impression.new()
	impression.id = id
	impression.event_id = score.event_id
	impression.slot = MEMORY.ImpressionSlot.ACT_EARLY if _ended_early(outcome) \
		else MEMORY.ImpressionSlot.ACT
	impression.mood = str(outcome.get("mood", "relaxed"))
	impression.romance = int(outcome.get("romance", 0))
	impression.thought = str(outcome.get("thought", ""))
	impression.event_text = str(outcome.get("text", ""))
	_memory.commit(impression)
	_record_peak(score, exchange)
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


## The pure scorer's input. The act's identity is not its business; her tolerance is her stored
## preference, read by key here so the scorer needs no settings handle of its own.
func _scorer_dict(snapshot: ActSnapshot) -> Dictionary:
	var meter := snapshot.meter
	return {
		"preferences": snapshot.preferences,
		"seconds": snapshot.seconds,
		"thrusts": meter.thrusts,
		"pony_climaxes": meter.pony_climaxes,
		"talk_liked": meter.talk_liked,
		"talk_dislikes": meter.talk_dislikes,
		"touches_liked": meter.touches_liked,
		"touch_dislikes": meter.touch_dislikes.duplicate(true),
		"player_lines": meter.player_lines,
		"intensity_total": meter.intensity_total,
		"intensity_right": meter.intensity_right,
		"pattern_total": meter.pattern_total,
		"pattern_right": meter.pattern_right,
		"ended_early": snapshot.ending == ActSnapshot.Ending.EARLY,
		"stopped_by_her": snapshot.ending == ActSnapshot.Ending.STOPPED,
		"form_reveal": snapshot.form_reveal,
		"tolerance": str(snapshot.preferences.get("tolerance", "normal")),
	}


## True when the act ended before its afterglow, by the player or by her: the early impression slot
## keeps the base game from reading a full act's mood.
func _ended_early(outcome: Dictionary) -> bool:
	return bool(outcome.get("early", false)) or bool(outcome.get("stopped", false))


## Keep the strongest clean act per mare as a peak. The exchange is the useful part: a later cue
## can infer that she liked it without any name-specific instruction.
func _record_peak(score: ActScore, exchange: Exchange) -> void:
	if not bool(score.outcome.get("positive", false)):
		return
	var meter := score.meter
	if not RELATIONSHIP_CUE.peak_eligible(meter.peak_satisfaction, meter.both_matches,
			meter.dislikes):
		return
	var player := meter.player_talk.strip_edges()
	var her := ""
	if exchange != null and exchange.at > score.act_spoken_at:
		her = exchange.line.strip_edges()
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
	var peak := MEMORY.Peak.new()
	peak.id = score.pony_id
	peak.event_id = score.event_id
	peak.text = text
	peak.score = RELATIONSHIP_CUE.peak_score(meter.peak_satisfaction, meter.both_matches,
		meter.liked_touch, meter.liked_talk, meter.dislikes)
	_memory.record_peak(peak)


func _reasons(outcome: Dictionary) -> String:
	var parts: PackedStringArray = []
	var raw: Variant = outcome.get("reasons", [])
	if raw is Array:
		for item: Variant in raw:
			parts.append(str(item))
	return ",".join(parts)


func _game_ok() -> bool:
	return is_instance_valid(WORLD.world_root())
