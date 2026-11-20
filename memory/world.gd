extends RefCounted
## The world-context and impression reads behind the facade.

const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const STORE := preload("res://mods/unfplap/memory/store.gd")
const MemoryHit = FACTS.MemoryHit


static func context(game: Node) -> Node:
	return GAME.world_context(game)


static func impressions(game: Node) -> Node:
	return GAME.impressions_of(context(game))


## One world-context event. `place` is the region id for a witnessed event and empty otherwise.
static func record(game: Node, kind: String, text: String, witnesses: Array, subjects: Array,
		event_id: String, place := "") -> void:
	var ctx := context(game)
	if ctx == null:
		return
	if place.is_empty():
		ctx.record(kind, text, witnesses, subjects, event_id)
	else:
		ctx.record(kind, text, witnesses, subjects, event_id, place)


static func commit_impression(game: Node, id: String, data: Dictionary,
		event_id: String) -> void:
	var target := impressions(game)
	if target == null:
		return
	target.commit(id, data, event_id)


## Private facts for the cue prompt. No raw scores or counts leave this function.
static func cue_facts(game: Node, id: String, event_id: String) -> Dictionary:
	var out: Dictionary = {}
	if game == null:
		return out
	var runtime := _relationship_runtime(game)
	if runtime == null:
		return out
	var ladder: Variant = runtime.ladder(id) if runtime.has_method("ladder") else {}
	if ladder is Dictionary:
		var friend: Variant = (ladder as Dictionary).get("friendship", {})
		var love: Variant = (ladder as Dictionary).get("love", {})
		if friend is Dictionary:
			out["friendship"] = str((friend as Dictionary).get("name", ""))
			out["friendship_level"] = int((friend as Dictionary).get("level", -1))
		if love is Dictionary:
			out["love"] = str((love as Dictionary).get("name", ""))
			out["love_level"] = int((love as Dictionary).get("level", -1))
	var bonds := runtime.get("bonds") as Object
	if is_instance_valid(bonds):
		var record := GAME.bond_record_for(bonds, id)
		out["stage"] = record.stage
		out["anger"] = float(record.rows.get("anger", 0.0))
	var prior := 0
	var ctx := context(game)
	if ctx != null:
		for row: Dictionary in GAME.world_events(ctx, id, 64):
			if str(row.get("kind", "")) != "intimacy":
				continue
			var eid := str(row.get("id", ""))
			if eid == event_id or eid.begins_with(event_id + ":"):
				continue
			prior += 1
		var stored := GAME.impressions_of(ctx)
		if stored != null:
			out["mood"] = GAME.impression_mood(stored, id, "")
	var acts := ACT_HISTORY.stored_acts(ACT_HISTORY.section(), id)
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
	var story := _story_memory(ctx, id, cue, used_ids)
	if story.found():
		return story
	return _event_memory(ctx, id, event_id, used_ids)


static func _story_memory(ctx: Node, id: String, cue: String,
		used_ids: Array[String]) -> MemoryHit:
	var story := _story(ctx)
	if story == null or not story.has_method("is_open") or not story.has_method("line_text") \
			or not bool(story.is_open()):
		return MemoryHit.new()
	var store := _store(story)
	if store == null or not store.has_method("last_line_id") \
			or not store.has_method("search") or not store.has_method("witnessed"):
		return MemoryHit.new()
	var before := int(store.last_line_id()) + 1
	for row: Variant in store.search(id, _memory_words(cue), before, 8):
		if row is Dictionary and _memory_ok(row, id, used_ids):
			return _hit("story:" + str((row as Dictionary).get("id", "")),
				str(story.line_text(row, id, true)))
	var recent: Array = store.witnessed(id, 24, 0, ["say"])
	for index in range(recent.size() - 1, -1, -1):
		var row: Variant = recent[index]
		if row is Dictionary and _memory_ok(row, id, used_ids):
			return _hit("story:" + str((row as Dictionary).get("id", "")),
				str(story.line_text(row, id, true)))
	return MemoryHit.new()


static func _event_memory(ctx: Node, id: String, event_id: String,
		used_ids: Array[String]) -> MemoryHit:
	var events := GAME.world_events(ctx, id, 64)
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


static func _memory_ok(row: Dictionary, id: String, used_ids: Array[String]) -> bool:
	var kind := str(row.get("kind", ""))
	if kind in ["intimacy", "brain"]:
		return false
	if str(row.get("text", "")).strip_edges().is_empty():
		return false
	var key := "story:" + str(row.get("id", ""))
	if key in used_ids:
		return false
	if kind == "say":
		var speaker := str(row.get("speaker", ""))
		var listener := str(row.get("listener", ""))
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


static func _relationship_runtime(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var rel: Variant = game.get("relationship_runtime")
	if rel is Node and is_instance_valid(rel):
		return rel
	return null


static func _story(ctx: Node) -> Object:
	if not is_instance_valid(ctx):
		return null
	var story: Variant = ctx.get("story")
	if story is Object and is_instance_valid(story):
		return story
	return null


static func _store(story: Object) -> Object:
	if not is_instance_valid(story):
		return null
	var store: Variant = story.get("store")
	if store is Object and is_instance_valid(store):
		return store
	return null
