extends RefCounted
## The act's dialogue lines: cue admission, prompt assembly, the shared utterance slot, reaction
## lines and the bystander line. The runtime keeps the act state machine and passes its typed
## `act_facts.gd` view; this system owns the scheduler, the recent-line memory and the line text.
##
## It reads the mod's own line channel through `main.memory` and the conversation director from
## the act facts. See `docs/lines.md`.

const PROMPTS := preload("res://mods/unfplap/act_lines/prompts.gd")
const UTTERANCE := preload("res://mods/unfplap/utterance.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/utterance_scheduler.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/relationship_cue.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")

const CUE_REACTION_NOTE := "\nDo not turn the private moment into a repeated command; say it as your own reaction or preference."
const RECENT_LINES := 8
const ANGLES_REMEMBERED := 7
const LINE_ANGLES := [
	"say something about a thing you two talked about earlier.",
	"tease him.",
	"tell him exactly what you want next.",
	"say his name, and little else.",
	"mention where you are right now.",
	"tell him something you have never said out loud.",
	"sound surprised at yourself.",
	"say something tender, in the middle of all this.",
	"let him see how much you trust him.",
	"make a joke, in your usual voice.",
	"complain playfully about something he is doing.",
	"bring up how you feel about him lately.",
	"say something only you would say, true to your personality.",
]
const SPEECH_ROUGHNESS := {"soft": 0.1, "firm": 0.5, "rough": 1.0}
const SPEECH_FULL_PACE := 3.0
const BYSTANDER_FIRST_S := 12.0
const BYSTANDER_GAP_S := 20.0
const BYSTANDER_CHANCE := 0.7
const BYSTANDER_MAX := 3
const BYSTANDER_PROMPT := "You can see Anon and %s having sex right in front of you, %s Say ONE short line in your own voice, at most 14 words, aloud to them or to yourself. Begin with [happy], [surprised] or [calm]. Ponies have much less shame about this than humans do, so react the way a pony would: amused, teasing, curious, nosy, a little flustered, or mildly put out, but never horrified, panicked or disgusted. Mention where they are doing it if that is what stands out. Do not join in, do not describe anatomy, and do not ask a question that needs an answer."
const BYSTANDER_OUTDOORS := "out in the open where anypony could walk past."
const BYSTANDER_INDOORS := "indoors, in a house you are also in."

const STATE_IDLE := 0
const STATE_POSING_IN := 1
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

var main: Node
var facts: Variant

var _scheduler
var _serial := 0
var _delivered_key := ""
var _used_angles: Array[String] = []
var _used_memory_ids: Array[String] = []
var _bystander_event := ""
var _bystander_spoken: Array[String] = []
var _bystander_wait := 0.0
var _last_cue_log_text := ""
var _last_cue_log_reason := ""


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


func setup(main_node: Node) -> void:
	main = main_node


## Push the debug talk/cue pacing settings into the pure scheduler. `reset()` keeps these fields.
func configure(pacing: Dictionary) -> void:
	var lines = scheduler()
	lines.base_stable_s = float(pacing.get("base_stable", lines.base_stable_s))
	lines.override_stable_s = float(pacing.get("override_stable", lines.override_stable_s))
	lines.utterance_gap_s = float(pacing.get("utterance_gap", lines.utterance_gap_s))
	lines.demand_gap_s = float(pacing.get("demand_gap", lines.demand_gap_s))
	lines.demand_repeat_s = float(pacing.get("demand_repeat", lines.demand_repeat_s))
	lines.max_age_s = float(pacing.get("max_age", lines.max_age_s))
	lines.release_hold_s = float(pacing.get("release_hold", lines.release_hold_s))


func scheduler():
	if _scheduler == null:
		_scheduler = UTTERANCE_SCHEDULER.new()
	return _scheduler


## Start a fresh act's line state. The pacing configuration survives.
func reset(now: float, gap: float) -> void:
	scheduler().reset(now, gap)
	_serial = 0
	_delivered_key = ""
	_used_angles.clear()
	_used_memory_ids.clear()
	_bystander_event = ""
	_bystander_spoken.clear()
	_bystander_wait = 0.0
	_last_cue_log_text = ""
	_last_cue_log_reason = ""


## One cue decision per tick. Returns the queued director key, or "".
func admit_cue(now: float) -> String:
	if facts == null:
		return ""
	var lines = scheduler()
	lines.observe_cue(now, facts.cue)
	var demand := UTTERANCE.is_demand(facts.cue)
	var is_override := bool(facts.cue_override)
	var admit := false
	var reason := ""
	if not _feature("act_lines", true):
		reason = "act_lines_off"
	elif demand and lines.demand_blocked(facts.cue, now):
		reason = "demand"
	elif not channel_free():
		reason = "channel" if not lines.channel_free() else "speech"
	else:
		admit = lines.admit_cue(now, facts.cue, is_override)
		if not admit:
			reason = lines.last_reason
	var decision := reason if not admit else "admit"
	if facts.cue != _last_cue_log_text or decision != _last_cue_log_reason:
		_last_cue_log_text = facts.cue
		_last_cue_log_reason = decision
		_log("cue text=\"%s\" admit=%s reason=%s override=%s" % [
			facts.cue, "yes" if admit else "no", decision, str(is_override)])
	if not admit:
		return ""
	var key := _queue_utterance("cue", "cue", "cue")
	if not key.is_empty():
		lines.note_cue_queued(now, key, facts.cue, demand, is_override)
	return key


## Free a delivered line after its release hold, drop a row the director erased, and expire a
## queued or generating line at its max age. A line that already reached audio is never cut here.
func tick() -> void:
	if facts == null or facts.state in [STATE_IDLE, STATE_POSING_IN]:
		return
	_release_finished_utterance()
	var lines = scheduler()
	var key: String = lines.pending_key()
	if key.is_empty():
		_delivered_key = ""
		return
	var at := _now()
	var line: int = MEMORY.LineState.UNKNOWN
	if _game_ok():
		line = main.memory.line_state(key)
	if line == MEMORY.LineState.ABSENT:
		_log("utterance absent key=%s" % key)
		lines.drop_pending()
		return
	if line == MEMORY.LineState.DELIVERED:
		# A released line keeps this state until speech stops and the hold passes. Log it once.
		if key != _delivered_key:
			_delivered_key = key
			_log("utterance delivered key=%s age=%.1f" % [
				key, maxf(0.0, at - lines.pending_since())])
		lines.note_finished(at, key)
		_release_finished_utterance()
		return
	if line == MEMORY.LineState.SPEAKING:
		return
	if lines.pending_override() and (not bool(facts.cue_override) or facts.cue != lines.pending_cue()) \
			and not (line == MEMORY.LineState.UNKNOWN and busy()):
		_cancel_pending_utterance("override")
		return
	if line == MEMORY.LineState.UNKNOWN and busy():
		return
	if at > lines.pending_until():
		_cancel_pending_utterance("age")


## integration: one adult observer may say a short line, using the modern witness perception.
func bystander_tick(delta: float) -> void:
	if facts == null or not _feature("act_bystanders", true) \
			or facts.state != STATE_ACTIVE or not _game_ok():
		return
	if _bystander_event != facts.event_id:
		_bystander_event = facts.event_id
		_bystander_spoken.clear()
		_bystander_wait = BYSTANDER_FIRST_S
	_bystander_wait -= delta
	if _bystander_wait > 0.0 or _bystander_spoken.size() >= BYSTANDER_MAX:
		return
	_bystander_wait = BYSTANDER_GAP_S
	if randf() > BYSTANDER_CHANCE:
		return
	var seen: Array = main.memory.observers(facts.pony) \
		.filter(func(row: MEMORY.Observer) -> bool:
			return not str(row.id) in _bystander_spoken and str(row.id) != facts.pony_id)
	if seen.is_empty():
		return
	var row: MEMORY.Observer = seen.pick_random()
	var observer: Node3D = row.node
	var event_id: String = facts.event_id
	var valid := func() -> bool:
		return is_instance_valid(observer) and is_instance_valid(facts.pony) \
			and facts.event_id == event_id \
			and facts.state in [STATE_ACTIVE, STATE_CLIMAX]
	var indoors := false
	if is_instance_valid(facts.pony) and facts.pony.is_inside_tree():
		indoors = HOUSE.at(facts.pony.get_tree(), facts.pony.global_position) != null
	var purpose := BYSTANDER_PROMPT % [facts.display_name,
		BYSTANDER_INDOORS if indoors else BYSTANDER_OUTDOORS]
	if _feature("act_faces", true):
		purpose += ACT_FACE.prompt_note("bystander")
	if _bystander_line(str(row.id), event_id, purpose, valid):
		_bystander_spoken.append(str(row.id))
		_log("bystander line from %s" % row.id)


func _queue_utterance(kind: String, prompt_key: String, key_suffix: String) -> String:
	if facts.state != STATE_ACTIVE or not _game_ok():
		return ""
	# integration: her mouth is busy during oral.
	if bool(facts.oral_active):
		return ""
	if _director() == null:
		return ""
	var template := str(facts.act_prompts.get(prompt_key, ""))
	if template.strip_edges().is_empty():
		template = str(facts.act_prompts.get("utterance", ""))
	if template.strip_edges().is_empty():
		_log("utterance missing prompt kind=%s" % kind)
		return ""
	var face_note := ""
	if kind == "cue" and _feature("act_faces", true):
		face_note = ACT_FACE.prompt_note("cue", facts.mood)
	var values := {
		"state": UTTERANCE.state_line(
			facts.pose_id, facts.mood, facts.last_intensity, facts.last_pattern,
			facts.last_touch, facts.last_talk, facts.act_seconds, facts.pony_climaxes),
		"preferences": PREFERENCES.describe(facts.preferences),
		"taste": PREFERENCES.describe(facts.preferences),
		"cue": facts.cue,
		"recent": recent_lines(),
		"face_note": face_note,
	}
	var memory_id := ""
	if kind == "cue":
		var mem: Variant = main.memory
		var cue_facts: MEMORY.CueFacts = mem.cue_facts(facts.pony_id, facts.event_id)
		var facts_dict := cue_facts.to_dict()
		var tone_name := RELATIONSHIP_CUE.tone(facts_dict)
		var relationship_note := RELATIONSHIP_CUE.note(facts_dict)
		values["relationship"] = relationship_note
		values["tone"] = RELATIONSHIP_CUE.tone_line(tone_name) \
			if not relationship_note.is_empty() else ""
		values["seed"] = UTTERANCE.line_seed({
			"mood": facts.mood,
			"intensity": facts.last_intensity,
			"pattern": facts.last_pattern,
			"wanted_intensity": str(facts.preferences.get("intensity", "firm")),
			"wanted_pattern": str(facts.preferences.get("pattern", "steady")),
			"last_touch": facts.last_touch,
			"last_talk": facts.last_talk,
			"touch_likes": facts.preferences.get("touch", []),
			"touch_dislikes": facts.preferences.get("dislikes", []),
			"talk_likes": facts.preferences.get("talk", []),
		})
		var memory: MEMORY.MemoryHit = mem.shared_memory(
			facts.pony_id, facts.cue, facts.event_id, _used_memory_ids)
		values["memory"] = RELATIONSHIP_CUE.memory_line(memory.text)
		memory_id = memory.id
	var purpose := UTTERANCE.format(template, values)
	if kind == "cue":
		if not face_note.is_empty() and not template.contains("{face_note}") \
				and not purpose.contains("[face"):
			purpose += face_note
		purpose += UTTERANCE.context_note(template, values)
		purpose += CUE_REACTION_NOTE
		# integration: optional line angles and speech feel, independent of each other.
		if _feature("act_speech_feel", false):
			purpose += _speech_feel_note()
		if _feature("act_line_angles", true):
			purpose += _line_variety(values.recent)
	_serial += 1
	var suffix := "%s:%d" % [key_suffix, _serial]
	var act_id: String = facts.event_id
	var valid := func() -> bool:
		# Deliberately independent of the act state: cancelling the act must not invalidate
		# a line that is already being generated or spoken. Explicit `end_act` calls still
		# cancel it at climax/afterglow boundaries.
		return is_instance_valid(facts.pony) and facts.event_id == act_id
	var finished := func(key: String) -> void:
		_utterance_done(key)
	var queued := _utterance_line(act_id, suffix, purpose, valid, finished)
	if queued.is_empty():
		_log("utterance queue failed kind=%s text=\"%s\"" % [kind, facts.cue])
		return ""
	if not memory_id.is_empty():
		_used_memory_ids.append(memory_id)
	_log("utterance kind=%s text=\"%s\" key=%s" % [kind, facts.cue, queued])
	return queued


func _utterance_done(key: String) -> void:
	scheduler().note_finished(_now(), key)
	_release_finished_utterance()


## The director can report a line finished before its final voice chunk has stopped. Keep the
## slot reserved until `busy()` is false, otherwise the next line can cut it off.
func _release_finished_utterance() -> void:
	if _speech_busy():
		return
	var lines = scheduler()
	if not lines.release_ready(_now()):
		return
	lines.release()


func _cancel_pending_utterance(reason := "") -> void:
	var lines = scheduler()
	var key: String = lines.pending_key()
	var pending_cue: String = str(lines.pending_cue())
	var age: float = maxf(0.0, _now() - float(lines.pending_since()))
	var line: int = MEMORY.LineState.UNKNOWN
	if not key.is_empty() and _game_ok():
		line = main.memory.line_state(key)
	var director := _director()
	var director_state := str(director.get("state")) if director != null else "?"
	lines.drop_pending()
	if key.is_empty():
		return
	_log("utterance cancel reason=%s key=%s text=\"%s\" age=%.1f line=%s director=%s speech=%s" % [
		reason if not reason.is_empty() else "manual", key, pending_cue, age,
		_line_state_name(line), director_state, str(_speech_busy())])
	if _game_ok():
		main.memory.cancel_line(key)


## Drop all act lines that have not started speaking. A line that is already speaking may
## finish; one that is only queued or still being generated is cancelled. This runs at every
## climax/afterglow boundary and every act end, so a delayed line cannot start afterward.
func end_act(event_id: String, keep_speaking := true) -> void:
	if _game_ok():
		var cancelled: int = main.memory.cancel_act(event_id, keep_speaking)
		if cancelled > 0:
			_log("act lines cancelled=%d" % cancelled)
	scheduler().drop_pending()


## Queue one settings-driven reaction line. Returns the director key, or "" when it was not queued.
func reaction_line(reaction: int, event_id: String, fallback: String, valid: Callable) -> String:
	if facts == null or not _game_ok():
		return ""
	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.REACTION
	request.id = facts.pony_id
	request.event_id = event_id
	request.purpose = fallback
	request.reaction = reaction
	request.valid = valid
	var line: MEMORY.Line = main.memory.line(request)
	return line.key if line.queued else ""


## Reserve the shared utterance slot for an already queued reaction.
func note_reaction(key: String, cue_text: String, until: float) -> void:
	scheduler().note_reaction_queued(_now(), key, cue_text, until)


## True while the director or the pony is actually speaking. Unlike `channel_free`, this ignores
## our own pending key, so a queued line can tell the difference between "still talking" and
## "stuck".
func busy() -> bool:
	return _speech_busy()


## True when no mod line owns the slot and the director/pony are not already speaking.
func channel_free() -> bool:
	return scheduler().channel_free() and not _speech_busy()


## The normal dialogue prompt note. Every value is plain data, supplied by the runtime, so the
## wording and the precedence are testable without a scene.
func prompt_note(values: Dictionary) -> String:
	return PROMPTS.note(values)


## The lover-bond prompt note. The runtime keeps the bond/act/sleep gates; the wording is here.
func lover_prompt_note(stored_bond: bool) -> String:
	return RELATIONSHIP_CUE.lover_note(stored_bond)


func recent_lines() -> String:
	var director := _director()
	if director == null or facts == null or not is_instance_valid(facts.pony):
		return ""
	var characters: Variant = director.get("characters")
	if not characters is Dictionary or not (characters as Dictionary).has(facts.pony_id):
		return ""
	var entry: Variant = (characters as Dictionary)[facts.pony_id]
	if not entry is Dictionary:
		return ""
	var spoken: Variant = (entry as Dictionary).get("spoken", [])
	if not spoken is Array or (spoken as Array).is_empty():
		return ""
	var recent: Array[String] = []
	var limit := RECENT_LINES if _feature("act_line_angles", true) else 4
	var start := maxi(0, (spoken as Array).size() - limit)
	for index in range(start, (spoken as Array).size()):
		recent.append(str((spoken as Array)[index]))
	return " | ".join(recent)


func last_spoken_line() -> String:
	var recent := recent_lines()
	if recent.is_empty():
		return ""
	var parts := recent.split(" | ")
	return parts[parts.size() - 1].strip_edges() if not parts.is_empty() else ""


## When she last actually spoke, so a peak memory does not quote a pre-act line as an answer.
func last_spoken_at() -> float:
	var director := _director()
	if director == null or facts == null:
		return -1e9
	var characters: Variant = director.get("characters")
	if not characters is Dictionary or not (characters as Dictionary).has(facts.pony_id):
		return -1e9
	var entry: Variant = (characters as Dictionary)[facts.pony_id]
	if not entry is Dictionary:
		return -1e9
	return float((entry as Dictionary).get("last_spoken_at", -1e9))


func _utterance_line(event_id: String, suffix: String, purpose: String,
		valid: Callable, finished: Callable) -> String:
	if not _game_ok():
		return ""
	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.UTTERANCE
	request.id = facts.pony_id
	request.event_id = event_id
	request.suffix = suffix
	request.purpose = purpose
	request.valid = valid
	request.finished = finished
	var line: MEMORY.Line = main.memory.line(request)
	return line.key if line.queued else ""


## Queue one bystander line. The act owns it, so its end cancels it.
func _bystander_line(id: String, event_id: String, purpose: String,
		valid: Callable) -> bool:
	if not _game_ok():
		return false
	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.BYSTANDER
	request.id = id
	request.event_id = event_id
	request.purpose = purpose
	request.valid = valid
	return main.memory.line(request).queued


## integration: without a fresh angle she answers the same prompt the same way.
func _line_variety(recent: Variant) -> String:
	var open: Array = LINE_ANGLES.filter(func(angle: String) -> bool:
		return not angle in _used_angles)
	if open.is_empty():
		_used_angles.clear()
		open = LINE_ANGLES.duplicate()
	var angle: String = open.pick_random()
	_used_angles.append(angle)
	if _used_angles.size() > ANGLES_REMEMBERED:
		_used_angles.remove_at(0)
	var note := " This time, %s Bring in something you two actually said, did or know from today if it fits." % angle
	if not str(recent).is_empty():
		note += " Your recent lines were: %s. Do not reuse their wording, their opening word or their idea." % recent
	return note


## integration: tells the line how the current strokes break up her speech.
func _speech_feel_note() -> String:
	if facts.last_intensity.is_empty():
		return ""
	var pace := maxf(float(facts.thrust_pace), 0.0)
	var hole := ""
	if bool(facts.anal_active):
		hole = " Anon is in your ass right now, not your pussy."
	var level := 0.5 * float(SPEECH_ROUGHNESS.get(facts.last_intensity, 0.5)) \
		+ 0.5 * clampf(pace / SPEECH_FULL_PACE, 0.0, 1.0)
	var frequency := "Put one after almost every word or two, so your speech keeps breaking apart."
	if level < 0.25:
		frequency = "Use only one, quiet and breathy."
	elif level < 0.5:
		frequency = "Use one or two."
	elif level < 0.75:
		frequency = "Put one after every few words."
	return hole + " Right now Anon's strokes are %s and %s, about %.1f a second. Break up your speech with exclamations between words, such as \"Ah!\", \"Hah!\", \"FUCK!\", \"Ah...\", \"Buck...\", \"Nngh...\" and similar ones in your own voice. %s They do not count toward your word limit." % [
		facts.last_intensity, facts.last_pattern if not facts.last_pattern.is_empty() else "steady",
		pace, frequency]


## The debug name for a typed line state. The enum stays the only comparison in the code.
func _line_state_name(state: int) -> String:
	match state:
		MEMORY.LineState.ABSENT:
			return "absent"
		MEMORY.LineState.QUEUED:
			return "queued"
		MEMORY.LineState.GENERATING:
			return "generating"
		MEMORY.LineState.SPEAKING:
			return "speaking"
		MEMORY.LineState.DELIVERED:
			return "delivered"
		_:
			return "unknown"


func _feature(name: String, fallback: bool) -> bool:
	if facts == null:
		return fallback
	return bool(facts.features.get(name, fallback))


func _director() -> Node:
	if facts == null or not facts.director.is_valid():
		return null
	var node: Variant = facts.director.call()
	return node if node is Node else null


func _speech_busy() -> bool:
	var director := _director()
	if director != null and str(director.get("state")) != "idle":
		return true
	if facts != null and is_instance_valid(facts.pony) and facts.pony.has_method("is_speaking") \
			and bool(facts.pony.call("is_speaking")):
		return true
	return false


func _game_ok() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.get("game"))


func _now() -> float:
	return facts.clock() if facts != null else 0.0


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
