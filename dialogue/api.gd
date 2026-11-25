extends Node
## Scope: pony
## The per-act dialogue facade: admission, prompt notes, the one director slot, reactions and
## bystanders.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const PROMPTS := preload("res://mods/unfplap/dialogue/prompts.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")
const UTTERANCE := preload("res://mods/unfplap/dialogue/utterance.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/dialogue/utterance_scheduler.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const RECENT_LINES := 8

## The act values one prompt note carries; the session fills one instance per note.
class ActValues extends RefCounted:
	var state := 0
	var pony_id := ""
	var event_id := ""
	var warm := false
	var beat := ""
	var caressing := false
	var leaning := false
	var missionary := false
	var form_source := false
	var form_name := ""
	var form_borrowed := false


## The seven cue-pacing values; the settings snapshot fills one per act and per live edit.
class Pacing extends RefCounted:
	var base_stable := 0.0
	var override_stable := 0.0
	var utterance_gap := 0.0
	var demand_gap := 0.0
	var demand_repeat := 0.0
	var max_age := 0.0
	var release_hold := 0.0


## The plain values one normal prompt note carries; the act view fills one per note.
class PromptValues extends RefCounted:
	var state := 0
	var warm := false
	var history := ""
	var beat := ""
	var relation := ""
	var caressing := false
	var leaning := false
	var missionary := false
	var form_source := false
	var form_name := ""
	var form_borrowed := false

	## The pure note's own shape; the wording stays in `dialogue/prompts.gd`.
	func to_dict() -> Dictionary:
		return {
			"state": state, "warm": warm, "history": history, "beat": beat,
			"relation": relation, "caressing": caressing, "leaning": leaning,
			"missionary": missionary, "form_source": form_source, "form_name": form_name,
			"form_borrowed": form_borrowed,
		}


## One reaction line's validity window. The memory channel re-asks `test` when it delivers, so the
## rule stays with the caller and a bare `Callable` never crosses the facade.
class Validity extends RefCounted:
	var test: Callable = Callable()

	static func of(rule: Callable) -> Validity:
		var out := Validity.new()
		out.test = rule
		return out


const ANGLES_REMEMBERED := 7
const SPEECH_ROUGHNESS := {"soft": 0.1, "firm": 0.5, "rough": 1.0}
const SPEECH_FULL_PACE := 3.0
const BYSTANDER_FIRST_S := 12.0
const BYSTANDER_GAP_S := 20.0
const BYSTANDER_CHANCE := 0.7
const BYSTANDER_MAX := 3

const STATE_IDLE := ACT_STATE.State.IDLE
const STATE_POSING_IN := ACT_STATE.State.POSING_IN
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX

var facts: ACT_FACTS = null
## The world memory the line channel writes; the runtime wires it once.
var memory: MEMORY = null

var _scheduler: UTTERANCE_SCHEDULER = null
var _serial := 0
var _delivered_key := ""
var _used_angles: Array[String] = []
var _used_memory_ids: Array[String] = []
var _bystander_event := ""
var _bystander_spoken: Array[String] = []
var _bystander_wait := 0.0
var _history_turn := -1
var _history_scan := 0.0
var _history_reminder_at := -1000.0
var _last_cue_log_text := ""
var _last_cue_log_reason := ""
## The last queued climax line, read by its own validity window after the queue call.
var _climax_key := ""


func _init(facts_context: ACT_FACTS = null) -> void:
	facts = facts_context


## Hand the line channel to the facade; the runtime's composition is the only caller.
func wire(memory_in: MEMORY) -> void:
	memory = memory_in


## Push the debug talk/cue pacing settings into the pure scheduler. `reset()` keeps these fields.
func configure(pacing: Pacing) -> void:
	var lines := scheduler()
	lines.base_stable_s = pacing.base_stable
	lines.override_stable_s = pacing.override_stable
	lines.utterance_gap_s = pacing.utterance_gap
	lines.demand_gap_s = pacing.demand_gap
	lines.demand_repeat_s = pacing.demand_repeat
	lines.max_age_s = pacing.max_age
	lines.release_hold_s = pacing.release_hold


func scheduler() -> UTTERANCE_SCHEDULER:
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
	if demand and lines.demand_blocked(facts.cue, now):
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
		LOG.debug("cue text=\"%s\" admit=%s reason=%s override=%s", [
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
		line = memory.line_state(key)
	if line == MEMORY.LineState.ABSENT:
		LOG.debug("utterance absent key=%s", [key])
		lines.drop_pending()
		return
	if line == MEMORY.LineState.DELIVERED:
		# A released line keeps this state until speech stops and the hold passes. Log it once.
		if key != _delivered_key:
			_delivered_key = key
			LOG.debug("utterance delivered key=%s age=%.1f", [
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
	if facts == null or facts.state != STATE_ACTIVE or not _game_ok():
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
	var seen: Array = memory.observers(facts.pony) \
		.filter(func(row: MEMORY.Observer) -> bool:
			return not str(row.id) in _bystander_spoken and str(row.id) != facts.pony_id)
	if seen.is_empty():
		return
	var row: MEMORY.Observer = seen.pick_random()
	var observer: Node3D = row.node
	var event_id: String = facts.event_id
	var valid := Validity.of(func() -> bool:
		return is_instance_valid(observer) and is_instance_valid(facts.pony) \
			and facts.event_id == event_id \
			and facts.state in [STATE_ACTIVE, STATE_CLIMAX])
	var indoors := false
	if is_instance_valid(facts.pony) and facts.pony.is_inside_tree():
		indoors = WORLD.house_at(facts.pony.global_position) != null
	var settings: Dictionary = DEFAULTS_DATA.prompts_block("act.bystander_setting")
	var setting_key := "indoors" if indoors else "outdoors"
	var purpose := PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("act.bystander"), {
		"name": facts.display_name, "setting": str(settings.get(setting_key, ""))})
	purpose += ACT_FACE.prompt_note("bystander")
	if _bystander_line(str(row.id), event_id, purpose, valid):
		_bystander_spoken.append(str(row.id))
		LOG.debug("bystander line from %s", [row.id])


## Idle-only: the apology repair and the one pending reminder line; this module reads the scene
## values it needs, and the runtime passes only the pony, its id, the event and the clock.
func history_tick(delta: float, pony: Node3D, pony_id: String, event_id: String, now: float) -> void:
	if facts == null:
		return
	if not WORLD.ready() or not is_instance_valid(WORLD.player_rig()):
		return
	if not is_instance_valid(pony):
		return
	if _paused():
		return
	var director := _director()
	if director == null:
		return
	var turn := int(director.get("_turn_id"))
	if _history_turn < 0:
		_history_turn = turn
	elif turn != _history_turn:
		_history_turn = turn
		var text := str(director.get("_player_text")).strip_edges()
		var body: Variant = WORLD.player_body()
		var target: Variant = pony.get("conversation_target")
		if not text.is_empty() and PREFERENCES.apology_intent(text) \
				and (target == WORLD.player_rig() or target == body):
			if ACT_HISTORY.apology_repair(WORLD.mods().state(ACT_HISTORY.MOD_ID).rows,
					pony_id, ACT_HISTORY.day_now()):
				WORLD.mods().save()
				memory.note(MEMORY.NoteKind.APOLOGY, pony_id, event_id)
				LOG.debug("history apology id=%s", [pony_id])
	_history_scan += delta
	if _history_scan < 1.0:
		return
	_history_scan = 0.0
	if now - _history_reminder_at < 15.0 or _speech_busy():
		return
	if str(director.get("state")) != "idle":
		return
	if WORLD.player_rig().global_position.distance_to(pony.global_position) > 5.0:
		return
	var current := ACT_HISTORY.effective_row(WORLD.mods().state(ACT_HISTORY.MOD_ID).rows,
		pony_id, ACT_HISTORY.day_now())
	var kind := ACT_HISTORY.pending_line(current)
	if kind.is_empty():
		return
	if Time.get_unix_time_from_system() - float(current.get("last_at", 0.0)) < 45.0:
		return
	var line_event := "history_%s_%d" % [pony_id, Time.get_ticks_usec()]
	var valid := Validity.of(func() -> bool:
		if not is_instance_valid(pony):
			return false
		return facts != null and facts.state == STATE_IDLE)
	var reaction := MEMORY.Reaction.HISTORY_REMINDER if kind == "reminder" \
		else MEMORY.Reaction.HISTORY_COMPLAINT
	var key: String = reaction_line(reaction, line_event,
		ACT_HISTORY.line_purpose(current, kind), valid)
	if key.is_empty():
		return
	ACT_HISTORY.mark_announced(WORLD.mods().state(ACT_HISTORY.MOD_ID).rows, pony_id, kind)
	WORLD.mods().save()
	_history_reminder_at = now
	LOG.debug("history line kind=%s key=%s", [kind, key])


func _queue_utterance(kind: String, prompt_key: String, key_suffix: String) -> String:
	if facts.state != STATE_ACTIVE or not _game_ok():
		return ""
	# integration: her mouth is busy during oral. A face contact (the bed face-sit) is not a mouth
	# contact, so that pose still queues and speaks.
	if facts.pose_view != null and str(facts.pose_view.contact_kind) == "mouth":
		return ""
	if _director() == null:
		return ""
	var prompt: Variant = _prompt_node(prompt_key)
	if prompt == null:
		LOG.debug("utterance missing prompt kind=%s", [kind])
		return ""
	var face_note := ""
	if kind == "cue":
		# The cue prompt itself states the act's default voice; the hint only picks an expression.
		face_note = ACT_FACE.prompt_note("cue", facts.mood)
	var pose := str(facts.pose_view.id) if facts.pose_view != null else ""
	var values := {
		"state": UTTERANCE.state_line(
			pose, facts.mood, facts.last_intensity, facts.last_pattern,
			facts.last_touch, facts.last_talk, facts.act_seconds, facts.pony_climaxes),
		"preferences": PREFERENCES.describe(facts.preferences),
		"taste": PREFERENCES.describe(facts.preferences),
		"cue": facts.cue,
		"recent": recent_lines(),
		"face_note": face_note,
	}
	var memory_id := ""
	if kind == "cue":
		var mem: Variant = memory
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
	var purpose := PROMPT_TEXT.render(prompt, values)
	if kind == "cue":
		if not face_note.is_empty() and not purpose.contains("[face"):
			purpose += face_note
		# integration: optional speech feel, independent of the always-on line angles.
		if SETTINGS.act_speech_feel.get_bool():
			purpose += _speech_feel_note()
		purpose += _line_variety()
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
		LOG.debug("utterance queue failed kind=%s text=\"%s\"", [kind, facts.cue])
		return ""
	if not memory_id.is_empty():
		_used_memory_ids.append(memory_id)
	LOG.debug("utterance kind=%s text=\"%s\" key=%s", [kind, facts.cue, queued])
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
		line = memory.line_state(key)
	var director := _director()
	var director_state := str(director.get("state")) if director != null else "?"
	lines.drop_pending()
	if key.is_empty():
		return
	LOG.debug("utterance cancel reason=%s key=%s text=\"%s\" age=%.1f line=%s director=%s speech=%s", [
		reason if not reason.is_empty() else "manual", key, pending_cue, age,
		_line_state_name(line), director_state, str(_speech_busy())])
	if _game_ok():
		memory.cancel_line(key)


## Cancel the act's queued and generating lines; a line already speaking may finish, so a
## delayed line cannot start after the boundary.
func end_act(event_id: String, keep_speaking := true) -> void:
	if _game_ok():
		var cancelled: int = memory.cancel_act(event_id, keep_speaking)
		if cancelled > 0:
			LOG.debug("act lines cancelled=%d", [cancelled])
	scheduler().drop_pending()


## Queue one settings-driven reaction line. Returns the director key, or "" when it was not queued.
func reaction_line(reaction: int, event_id: String, fallback: String, valid: Validity) -> String:
	if facts == null or not _game_ok():
		return ""
	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.REACTION
	request.id = facts.pony_id
	request.event_id = event_id
	request.purpose = fallback
	request.reaction = reaction
	request.valid = valid.test if valid != null else Callable()
	var line: MEMORY.Line = memory.line(request)
	return line.key if line.queued else ""


## Reserve the shared utterance slot for an already queued reaction.
func note_reaction(key: String, cue_text: String, until: float) -> void:
	scheduler().note_reaction_queued(_now(), key, cue_text, until)


## One generated climax line, or none when her mouth is busy or the roll is silent. The act view
## supplies the identity the validity window re-reads when the line is delivered.
func climax_line(mouth_busy: bool, cue: String, act_id: String, count: int, max_age: float) -> String:
	if mouth_busy or facts == null or not _game_ok():
		return ""
	var climax_id := "%s:pony_climax:%d" % [act_id, count]
	var expires := _now() + max_age
	var valid := Validity.of(func() -> bool:
		if not is_instance_valid(facts.pony) or str(facts.event_id) != act_id \
				or int(facts.pony_climaxes) != count:
			return false
		if _now() <= expires:
			return true
		return memory.line_state(_climax_key) == MEMORY.LineState.SPEAKING)
	var prompt := PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("act.climax"), {})
	_climax_key = reaction_line(MEMORY.Reaction.CLIMAX, climax_id, prompt, valid)
	if _climax_key.is_empty():
		return ""
	note_reaction(_climax_key, cue, _now() + max_age)
	LOG.debug("utterance kind=reaction key=%s", [_climax_key])
	return _climax_key


## Interrupt the director only if this mare owns its turn, so a bystander's line is not cut.
func stop_oral_turn(pony_id: String) -> void:
	var director := _director()
	if director == null or not director.has_method("interrupt"):
		return
	if str(director.get("state")) == "idle":
		return
	if str(director.get("_current")) != pony_id:
		return
	WORLD.director().interrupt()


## The stored-history note for a hurt pony.
func history_note(pony_id: String) -> String:
	var row := ACT_HISTORY.effective_row(WORLD.mods().state(ACT_HISTORY.MOD_ID).rows,
		pony_id, ACT_HISTORY.day_now())
	return ACT_HISTORY.prompt_note(row)


## Short private relationship facts for normal dialogue. Empty outside a relationship runtime.
func relationship_note(pony_id: String, event_id: String) -> String:
	if not _game_ok():
		return ""
	return RELATIONSHIP_CUE.note(memory.cue_facts(pony_id, event_id).to_dict())


## The facade entry for the pure note assembly; the wording and precedence stay in the prompts
## module.
func act_prompt(values: ActValues) -> String:
	var note := PromptValues.new()
	note.state = values.state
	note.warm = values.warm
	note.history = history_note(values.pony_id)
	note.beat = values.beat
	note.relation = relationship_note(values.pony_id, values.event_id)
	note.caressing = values.caressing
	note.leaning = values.leaning
	note.missionary = values.missionary
	note.form_source = values.form_source
	note.form_name = values.form_name
	note.form_borrowed = values.form_borrowed
	return prompt_note(note)


## Unlike `channel_free`, this ignores our own pending key, so a queued line can tell "still
## talking" from "stuck".
func busy() -> bool:
	return _speech_busy()


## True when no mod line owns the slot and the director/pony are not already speaking.
func channel_free() -> bool:
	return scheduler().channel_free() and not _speech_busy()


## The normal dialogue prompt note. Every value is plain data, supplied by the runtime, so the
## wording and the precedence are testable without a scene.
func prompt_note(values: PromptValues) -> String:
	return PROMPTS.note(values.to_dict())


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
	var limit := RECENT_LINES
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
	var line: MEMORY.Line = memory.line(request)
	return line.key if line.queued else ""


## Queue one bystander line. The act owns it, so its end cancels it.
func _bystander_line(id: String, event_id: String, purpose: String,
		valid: Validity) -> bool:
	if not _game_ok():
		return false
	var request := MEMORY.LineRequest.new()
	request.kind = MEMORY.LineKind.BYSTANDER
	request.id = id
	request.event_id = event_id
	request.purpose = purpose
	request.valid = valid.test
	return memory.line(request).queued


## The shipped prompt node for that line kind, or the utterance node when the id is absent.
func _prompt_node(key: String) -> Variant:
	var node: Dictionary = DEFAULTS_DATA.prompts_block("act." + key)
	if node.is_empty():
		node = DEFAULTS_DATA.prompts_block("act.utterance")
	return node if not node.is_empty() else null


## integration: without a fresh angle she answers the same prompt the same way.
func _line_variety() -> String:
	var act: Dictionary = DEFAULTS_DATA.prompts_block("act")
	var angles: Array = act.get("angles", []) if act.get("angles", []) is Array else []
	if angles.is_empty():
		return ""
	var open: Array = angles.filter(func(angle: String) -> bool:
		return not angle in _used_angles)
	if open.is_empty():
		_used_angles.clear()
		open = angles.duplicate()
	var angle: String = open.pick_random()
	_used_angles.append(angle)
	if _used_angles.size() > ANGLES_REMEMBERED:
		_used_angles.remove_at(0)
	return " " + PROMPT_TEXT.render(angle, {})


## integration: tells the line how the current strokes break up her speech.
func _speech_feel_note() -> String:
	if facts.last_intensity.is_empty():
		return ""
	var pace := maxf(float(facts.thrust_pace), 0.0)
	var level := 0.5 * float(SPEECH_ROUGHNESS.get(facts.last_intensity, 0.5)) \
		+ 0.5 * clampf(pace / SPEECH_FULL_PACE, 0.0, 1.0)
	var band := "heavy"
	if level < 0.25:
		band = "sparse"
	elif level < 0.5:
		band = "light"
	elif level < 0.75:
		band = "steady"
	var bands: Dictionary = DEFAULTS_DATA.prompts_block("act.speech_feel_frequency")
	var text := PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("act.speech_feel"), {
		"intensity": facts.last_intensity,
		"pattern": facts.last_pattern if not facts.last_pattern.is_empty() else "steady",
		"pace": "%.1f" % pace,
		"frequency": str(bands.get(band, "")),
	})
	return "" if text.is_empty() else " " + text


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


func _director() -> Node:
	if facts == null or not facts.director.is_valid():
		return null
	var node: Variant = facts.director.call()
	return node if node is Node else null


func _speech_busy() -> bool:
	if WORLD.director().speaking():
		return true
	if facts != null and WORLD.pony(facts.pony).speaking():
		return true
	return false


func _game_ok() -> bool:
	return is_instance_valid(WORLD.world_root())


## True while the game's tree is paused; the idle scan queues no line into a menu.
func _paused() -> bool:
	return WORLD.paused()


func _now() -> float:
	return facts.clock() if facts != null else 0.0


## The start's generated-vocal preparation: the director prepares her voice cache for the act.
func prepare_vocal(pony_id: String) -> void:
	WORLD.director().prepare_vocal(pony_id)
