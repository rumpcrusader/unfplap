extends "res://mods/unfplap/shared/service.gd"
## Service: memory
## Contract: `docs/memory.md`
## The only file other systems preload or call; the peak store is the one persisted value.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const TEXT := preload("res://mods/unfplap/memory/text.gd")
const DIALOGUE := preload("res://mods/unfplap/memory/dialogue.gd")
const MEMORY_WORLD := preload("res://mods/unfplap/memory/world.gd")
const PERCEPTION := preload("res://mods/unfplap/memory/perception.gd")
const STORE := preload("res://mods/unfplap/memory/store.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

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

## The one memory service the entry built. A null instance makes every read a quiet no-op
## and lets a suite bind its own.
static var instance: Variant = null


## The act's typed stop reason for one stop text. The enum is the game-facing memory vocabulary;
## `runtime._stop()` reads this rather than owning the mapping.
static func stop_reason(text: String) -> int:
	match text:
		"unwilling":
			return FACTS.StopReason.UNWILLING
		"picked up":
			return FACTS.StopReason.PICKED_UP
		"interrupted":
			return FACTS.StopReason.INTERRUPTED
		"form change":
			return FACTS.StopReason.FORM_CHANGE
		"withdrew":
			return FACTS.StopReason.WITHDREW
		_:
			return FACTS.StopReason.NONE


## Write one impression, plus its world event when the slot has one.
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
	if impression.slot == ImpressionSlot.STAY_CLOSE:
		thought = TEXT.stay_close_thought(romance > 0, mood == "happy")
	MEMORY_WORLD.commit_impression(game, impression.id, mood, romance, thought,
		impression.event_id + TEXT.impression_suffix(impression.slot))
	if not text.is_empty():
		MEMORY_WORLD.record(game, "relationship", text,
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
			MEMORY_WORLD.record(game, "intimacy", TEXT.cancel_text(), witnesses, subjects,
				event_id + ":cancel")
		NoteKind.CLIMAXED:
			MEMORY_WORLD.record(game, "intimacy", TEXT.climax_text(), witnesses, subjects,
				event_id + ":pony_climax")
		NoteKind.STOPPED:
			MEMORY_WORLD.record(game, "intimacy", TEXT.stop_text(reason), witnesses, subjects,
				event_id + ":stop:" + TEXT.stop_name(reason))
		NoteKind.APOLOGY:
			MEMORY_WORLD.record(game, "relationship", TEXT.apology_text(), witnesses, subjects,
				"apology:%s:%d" % [id, Time.get_ticks_usec()])


## Keep the strongest clean act per mare. `memory/store.gd` owns the record and its save.
func record_peak(peak: Peak) -> void:
	if peak == null:
		return
	STORE.record(peak.id, peak.event_id, peak.text, peak.score)


## The exceptional player-requested reveal impression, with its fixed private and world wording.
## The runtime writes it once; `ImpressionSlot.FORM_REVEAL` keeps its own idempotent suffix.
func form_reveal_impression(id: String, event_id: String) -> Impression:
	var out := Impression.new()
	out.id = id
	out.event_id = event_id
	out.slot = ImpressionSlot.FORM_REVEAL
	out.mood = "happy"
	out.romance = 2
	out.thought = TEXT.form_reveal_thought()
	out.event_text = TEXT.form_reveal_text()
	return out


## The reveal's special peak, keyed to its own event.
func form_reveal_peak(id: String, event_id: String, score: float) -> Peak:
	var out := Peak.new()
	out.id = id
	out.event_id = event_id + ":form_reveal"
	out.text = TEXT.form_reveal_peak_text()
	out.score = score
	return out


## Fallback text for the climax and early-end reactions.
static func _reaction_base(reaction: int) -> String:
	match reaction:
		Reaction.CLIMAX:
			return PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("act.climax"), {})
		Reaction.END_EARLY:
			var row: Dictionary = DEFAULTS_DATA.prompts_block("act.end_early")
			return PROMPT_TEXT.render(str(row.get("normal", "")), {})
	return ""


## Queue one mod-owned line and report whether it was accepted.
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
			var purpose := request.purpose
			if purpose.strip_edges().is_empty():
				purpose = _reaction_base(request.reaction)
			if request.reaction == Reaction.CLIMAX:
				purpose += " Include a private first-person [thought: ...] impression of this moment in your reply."
			if not purpose.contains("[face"):
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
	var data := MEMORY_WORLD.cue_facts(_game(), id, event_id)
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
func shared_memory(id: String, cue: String, event_id: String, used: Array[String]) -> MemoryHit:
	if id.is_empty():
		return MemoryHit.new()
	return MEMORY_WORLD.shared_memory(_game(), id, cue, event_id, used)


## Adults perceiving the act now; the read commits nothing.
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
	var node: Variant = WORLD.game
	if node is Node and is_instance_valid(node):
		return node
	return null


## The eligibility service, or null before it exists. This is the one-way capability read.
func _eligibility() -> ELIGIBILITY:
	var service: ELIGIBILITY = PONIES.eligibility
	return service if is_instance_valid(service) else null


## True when this is her first act with the player.
func first_time(pony_id: String, event_id: String) -> bool:
	if not is_instance_valid(WORLD.game) or pony_id.is_empty():
		return false
	return cue_facts(pony_id, event_id).first_time
