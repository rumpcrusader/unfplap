extends RefCounted
## The world-context and impression reads behind the facade.

const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const STORE := preload("res://mods/unfplap/memory/store.gd")
const MemoryHit = FACTS.MemoryHit


static func context(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	return WORLD.director().world_context()


static func impressions(game: Node) -> Node:
	return WORLD.director().impressions() if is_instance_valid(game) else null


## One world-context event. `place` is the region id for a witnessed event and empty otherwise.
static func record(game: Node, kind: String, text: String, witnesses: Array, subjects: Array,
		event_id: String, place := "") -> void:
	if not is_instance_valid(game):
		return
	WORLD.director().record_event(kind, text, _strings(witnesses), _strings(subjects), event_id,
		place)


static func commit_impression(game: Node, id: String, mood: String, romance: int,
		thought: String, event_id: String) -> void:
	if not is_instance_valid(game):
		return
	WORLD.director().commit_impression(id, mood, romance, thought, event_id)


## Private facts for the cue prompt. No raw scores or counts leave this function.
static func cue_facts(game: Node, id: String, event_id: String) -> Dictionary:
	var out: Dictionary = {}
	if game == null:
		return out
	var runtime := WORLD.relationship().runtime()
	if runtime == null:
		return out
	var ladder := WORLD.relationship().ladder(id)
	if ladder.friendship_found:
		out["friendship"] = ladder.friendship_name
		out["friendship_level"] = ladder.friendship_level
	if ladder.love_found:
		out["love"] = ladder.love_name
		out["love_level"] = ladder.love_level
	var bonds := WORLD.relationship().bonds()
	if bonds != null:
		var record := WORLD.relationship().record(bonds, id)
		out["stage"] = record.stage
		out["anger"] = record.anger
	var prior := 0
	var ctx := context(game)
	if ctx != null:
		for row: Dictionary in WORLD.story().events(id, 64):
			if str(row.get("kind", "")) != "intimacy":
				continue
			var eid := str(row.get("id", ""))
			if eid == event_id or eid.begins_with(event_id + ":"):
				continue
			prior += 1
		if is_instance_valid(WORLD.director().impressions()):
			out["mood"] = WORLD.director().impression_mood(id, "")
	var acts := ACT_HISTORY.stored_acts(WORLD.mods().state(ACT_HISTORY.MOD_ID).rows, id)
	out["first_time"] = prior == 0 and acts == 0
	out["careful"] = str(out.get("mood", "")) == "annoyed" \
		or float(out.get("anger", 0.0)) > 0.0
	return out


## One unused shared memory for the cue prompt. The story journal is preferred because it keeps
## the actual exchange; the older world-context events are the fallback.
static func shared_memory(game: Node, id: String, cue: String, event_id: String,
		used_ids: Array[String]) -> MemoryHit:
	var peak := STORE.peak(id)
	if not peak.is_empty():
		var peak_id := "peak:" + id
		var peak_text := str(peak.get("text", "")).strip_edges()
		if not (peak_id in used_ids) and not peak_text.is_empty():
			return _hit(peak_id, peak_text)
	var ctx := context(game)
	if ctx == null:
		return MemoryHit.new()
	var story := _story_memory(id, cue, used_ids)
	if story.found():
		return story
	return _event_memory(id, event_id, used_ids)


static func _story_memory(id: String, cue: String,
		used_ids: Array[String]) -> MemoryHit:
	var story := WORLD.story()
	if not story.open():
		return MemoryHit.new()
	if story.store() == null:
		return MemoryHit.new()
	var before := story.last_line_id() + 1
	if before <= 0:
		return MemoryHit.new()
	for row in story.search(id, _memory_words(cue), before, 8):
		if _memory_ok(row.kind, row.text, row.id, row.speaker, row.listener, id, used_ids):
			return _hit("story:" + row.id, story.line_text(row, id, true))
	var kinds: Array[String] = ["say"]
	var recent := story.witnessed(id, 24, 0, kinds)
	for index in range(recent.size() - 1, -1, -1):
		var row = recent[index]
		if _memory_ok(row.kind, row.text, row.id, row.speaker, row.listener, id, used_ids):
			return _hit("story:" + row.id, story.line_text(row, id, true))
	return MemoryHit.new()


static func _event_memory(id: String, event_id: String,
		used_ids: Array[String]) -> MemoryHit:
	var events := WORLD.story().events(id, 64)
	for index in range(events.size() - 1, -1, -1):
		var row: Dictionary = events[index]
		var kind := str(row.get("kind", ""))
		if kind in ["intimacy", "brain"]:
			continue
		var eid := str(row.get("id", ""))
		if eid == event_id or eid.begins_with(event_id + ":"):
			continue
		var key := "event:" + eid
		if key in used_ids:
			continue
		var text := str(row.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		return _hit(key, ("Anon: " if kind == "heard_speech" else "") + text)
	return MemoryHit.new()


static func _memory_ok(kind: String, text: String, row_id: String, speaker: String,
		listener: String, id: String, used_ids: Array[String]) -> bool:
	if kind in ["intimacy", "brain"]:
		return false
	if text.strip_edges().is_empty():
		return false
	var key := "story:" + row_id
	if key in used_ids:
		return false
	if kind == "say":
		return (speaker == "player" and listener == id) or (speaker == id and listener == "player")
	return true


static func _memory_words(cue: String) -> Array[String]:
	var words: Array[String] = ["anon"]
	var clean := cue.to_lower().replace("'", " ").replace("’", " ")
	for word: String in clean.split(" ", false):
		if word.length() >= 5 and word not in ["there", "about", "would", "could", "should",
				"really", "maybe", "right", "where", "which", "these", "those", "going", "doing"]:
			words.append(word)
	var out: Array[String] = []
	for index in range(mini(words.size(), 8)):
		out.append(words[index])
	return out


static func _hit(id: String, text: String) -> MemoryHit:
	var out := MemoryHit.new()
	out.id = id
	out.text = text
	return out


static func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(str(value))
	return out
