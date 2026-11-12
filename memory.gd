extends RefCounted
## The memory system's entry point: the mod's act memory and its own dialogue lines. Every
## event text is short and non-graphic. A witness text is a perception, never a conclusion: the
## game's per-pony story summary forms her memory from it. The event id makes both
## world_context.record and impressions.commit idempotent.
##
## This is the only file another system may preload or call. `main.gd` creates it and exposes it
## as `main.memory`. It reads `main.game` and `main.eligibility` per call and stores nothing;
## `memory/store.gd` owns the only persisted value, the per-world peak memories.
##
## The boundary is deliberately small: three writes (`commit`, `note`, `record_peak`), four
## calls on the mod's own line channel, four reads, and `setup`. Variants live in the typed
## objects in `memory/facts.gd`, never in extra functions. See `docs/memory.md`.

const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const TEXT := preload("res://mods/unfplap/memory/text.gd")
const DIALOGUE := preload("res://mods/unfplap/memory/dialogue.gd")
const WORLD := preload("res://mods/unfplap/memory/world.gd")
const PERCEPTION := preload("res://mods/unfplap/memory/perception.gd")
const STORE := preload("res://mods/unfplap/memory/store.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")

const LineState = FACTS.LineState
const LineKind = FACTS.LineKind
const Reaction = FACTS.Reaction
const NoteKind = FACTS.NoteKind
const StopReason = FACTS.StopReason
const ImpressionSlot = FACTS.ImpressionSlot
const Sense = FACTS.Sense
const Impression = FACTS.Impression
const Peak = FACTS.Peak
const Witness = FACTS.Witness
const Observer = FACTS.Observer
const CueFacts = FACTS.CueFacts
const MemoryHit = FACTS.MemoryHit
const Line = FACTS.Line
const LineRequest = FACTS.LineRequest

var main: Node


func setup(main_node: Node) -> void:
	main = main_node


## Write one impression and, when its slot carries a world event, that event.
func commit(impression: Impression) -> void:
	if impression == null or impression.id.is_empty():
		return
	var game := _game()
	if game == null:
		return
	var mood := impression.mood
	var romance := impression.romance
	var thought := impression.thought.strip_edges()
	var text := impression.event_text.strip_edges()
	if impression.slot == ImpressionSlot.REFUSAL:
		var bucked := mood == "angry"
		text = TEXT.refusal_text(bucked)
		if thought.is_empty():
			thought = TEXT.refusal_thought(bucked)
	elif impression.slot == ImpressionSlot.STAY_CLOSE:
		thought = TEXT.stay_close_thought(romance > 0, mood == "happy")
	var data: Dictionary = {}
	if not mood.is_empty():
		data["mood"] = mood
	if romance != 0:
		data["romance"] = romance
	if not thought.is_empty():
		data["thought"] = thought.left(240)
	WORLD.commit_impression(game, impression.id, data,
		impression.event_id + TEXT.impression_suffix(impression.slot))
	if not text.is_empty():
		WORLD.record(game, TEXT.event_kind(impression.slot), text,
			[impression.id, "player"], [impression.id, "player"],
			impression.event_id + TEXT.event_suffix(impression.slot))


## Write one fixed-wording world event.
func note(kind: int, id: String, event_id: String, reason := 0) -> void:
	if id.is_empty() or event_id.is_empty():
		return
	var game := _game()
	if game == null:
		return
	var witnesses: Array = [id, "player"]
	var subjects: Array = [id, "player"]
	match kind:
		NoteKind.CANCELLED:
			WORLD.record(game, "intimacy", TEXT.cancel_text(), witnesses, subjects,
				event_id + ":cancel")
		NoteKind.CLIMAXED:
			WORLD.record(game, "intimacy", TEXT.climax_text(), witnesses, subjects,
				event_id + ":pony_climax")
		NoteKind.STOPPED:
			WORLD.record(game, "intimacy", TEXT.stop_text(reason), witnesses, subjects,
				event_id + ":stop:" + TEXT.stop_name(reason))
		NoteKind.APOLOGY:
			WORLD.record(game, "relationship", TEXT.apology_text(), witnesses, subjects,
				"apology:%s:%d" % [id, Time.get_ticks_usec()])


## Keep the strongest clean act per mare. `memory/store.gd` owns the record and its save.
func record_peak(peak: Peak) -> void:
	if peak == null:
		return
	STORE.record(peak.id, peak.event_id, peak.text, peak.score)


## Queue one of the mod's own lines. `Line.key` always names it; `Line.queued` says whether the
## director accepted it.
func line(request: LineRequest) -> Line:
	var out := Line.new()
	if request == null or request.id.is_empty():
		return out
	var game := _game()
	if game == null:
		return out
	match request.kind:
		LineKind.REACTION:
			var name := TEXT.reaction_name(request.reaction)
			var custom := SETTINGS.event_prompt(request.id, name)
			var purpose := custom if not custom.is_empty() else request.purpose
			if request.reaction == Reaction.CLIMAX:
				purpose += " Include a private first-person [thought: ...] impression of this moment in your reply."
			if SETTINGS.act_faces.get_bool() and not purpose.contains("[face"):
				purpose += ACT_FACE.prompt_note(name)
			out.key = TEXT.key(request.event_id, "reply", name)
			out.queued = DIALOGUE.queue(game, request.id, purpose, out.key, request.valid,
				Callable())
		LineKind.BYSTANDER:
			out.key = TEXT.key(request.event_id, "bystander", request.id)
			out.queued = DIALOGUE.queue(game, request.id, request.purpose, out.key,
				request.valid, Callable())
		_:
			out.key = TEXT.key(request.event_id, "line", request.suffix)
			var line_key := out.key
			var finished := Callable()
			if request.finished.is_valid():
				finished = func() -> void: request.finished.call(line_key)
			out.queued = DIALOGUE.queue(game, request.id, request.purpose, line_key,
				request.valid, finished)
	return out


## What the director currently holds for one mod-owned key, as a `LineState` value.
func line_state(key: String) -> LineState:
	return DIALOGUE.state(_game(), key) as LineState


func cancel_line(key: String) -> void:
	DIALOGUE.cancel(_game(), key)


## Drop every mod-owned line for one act, keeping a line that has started speaking.
func cancel_act(event_id: String, keep_speaking := true) -> int:
	return DIALOGUE.cancel_prefix(_game(), TEXT.key_prefix(event_id), keep_speaking)


## The private relationship facts for a cue prompt.
func cue_facts(id: String, event_id: String) -> CueFacts:
	var out := CueFacts.new()
	if id.is_empty():
		return out
	var data := WORLD.cue_facts(_game(), id, event_id)
	out.friendship = str(data.get("friendship", ""))
	out.friendship_level = int(data.get("friendship_level", -1))
	out.love = str(data.get("love", ""))
	out.love_level = int(data.get("love_level", -1))
	out.stage = str(data.get("stage", ""))
	out.anger = float(data.get("anger", 0.0))
	out.mood = str(data.get("mood", ""))
	out.first_time = bool(data.get("first_time", false))
	out.careful = bool(data.get("careful", false))
	return out


## One unused shared memory for the cue prompt, or a hit with `found()` false.
func shared_memory(id: String, cue: String, event_id: String, used: Array) -> MemoryHit:
	var out := MemoryHit.new()
	if id.is_empty():
		return out
	var data := WORLD.shared_memory(_game(), id, cue, event_id, used)
	out.id = str(data.get("id", ""))
	out.text = str(data.get("text", ""))
	return out


## Adult ponies who can perceive the act right now. Read-only; nothing is committed.
func observers(partner: Node3D) -> Array[Observer]:
	var out: Array[Observer] = []
	for row: Variant in PERCEPTION.observers(_game(), _eligibility(), partner):
		if row is Observer:
			out.append(row)
	return out


## Commit one private, age-appropriate memory per observer. Returns the rows for the debug log.
func witnesses(partner_id: String, name: String, serial: int,
		partner: Node3D) -> Array[Witness]:
	var out: Array[Witness] = []
	for row: Variant in PERCEPTION.witnesses(_game(), _eligibility(), partner_id, name,
			serial, partner):
		if row is Witness:
			out.append(row)
	return out


## The game node for the current world, or null outside one.
func _game() -> Node:
	if not is_instance_valid(main):
		return null
	var node: Variant = main.get("game")
	if node is Node and is_instance_valid(node):
		return node
	return null


## The eligibility service, or null before it exists. This is the one-way capability read.
func _eligibility() -> ELIGIBILITY:
	if not is_instance_valid(main):
		return null
	var service: Variant = main.get("eligibility")
	return service if service is ELIGIBILITY and is_instance_valid(service) else null
