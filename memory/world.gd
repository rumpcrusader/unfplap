extends RefCounted
## Scene adapter: the only reader of `world_context` and `impressions`, and the only place that
## builds the private cue facts and the shared-memory hit. The facade passes plain values in.

const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const STORE := preload("res://mods/unfplap/memory/store.gd")


static func context(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var ctx: Variant = game.get("world_context")
	if ctx is Node and is_instance_valid(ctx):
		return ctx
	return null


static func impressions(game: Node) -> Node:
	var ctx := context(game)
	if ctx == null:
		return null
	var found: Variant = ctx.get("impressions")
	if found is Node and is_instance_valid(found):
		return found
	return null


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
	var rel: Variant = game.get("relationship_runtime")
	if rel == null or not rel is Node or not is_instance_valid(rel):
		return out
	var ladder: Variant = rel.call("ladder", id) if rel.has_method("ladder") else {}
	if ladder is Dictionary:
		var friend: Variant = (ladder as Dictionary).get("friendship", {})
		var love: Variant = (ladder as Dictionary).get("love", {})
		if friend is Dictionary:
			out["friendship"] = str((friend as Dictionary).get("name", ""))
			out["friendship_level"] = int((friend as Dictionary).get("level", -1))
		if love is Dictionary:
			out["love"] = str((love as Dictionary).get("name", ""))
			out["love_level"] = int((love as Dictionary).get("level", -1))
	var bonds: Variant = rel.get("bonds")
	if bonds is Node and is_instance_valid(bonds) and bonds.has_method("record_for"):
		var record: Variant = bonds.call("record_for", id)
		if record is Dictionary:
			out["stage"] = str((record as Dictionary).get("stage", ""))
			out["anger"] = float((record as Dictionary).get("anger", 0.0))
	var prior := 0
	var ctx := context(game)
	if ctx != null:
		if ctx.has_method("events_for"):
			for event: Variant in ctx.call("events_for", id, 64):
				if not event is Dictionary:
					continue
				var row: Dictionary = event
				if str(row.get("kind", "")) != "intimacy":
					continue
				var eid := str(row.get("id", ""))
				if eid == event_id or eid.begins_with(event_id + ":"):
					continue
				prior += 1
		var stored: Variant = ctx.get("impressions")
		if stored is Node and is_instance_valid(stored) and stored.has_method("profile"):
			var profile: Variant = stored.call("profile", id)
			if profile is Dictionary:
				out["mood"] = str((profile as Dictionary).get("mood", ""))
	var acts := ACT_HISTORY.stored_acts(ACT_HISTORY.section(), id)
	out["first_time"] = prior == 0 and acts == 0
	out["careful"] = str(out.get("mood", "")) == "annoyed" \
		or float(out.get("anger", 0.0)) > 0.0
	return out


## One unused shared memory for the cue prompt. The story journal is preferred because it keeps
## the actual exchange; the older world-context events are the fallback.
static func shared_memory(game: Node, id: String, cue: String, event_id: String,
		used_ids: Array) -> Dictionary:
	var peak := STORE.peak(id)
	if not peak.is_empty():
		var peak_id := "peak:" + id
		var peak_text := str(peak.get("text", "")).strip_edges()
		if not (peak_id in used_ids) and not peak_text.is_empty():
			return {"id": peak_id, "text": peak_text}
	var ctx := context(game)
	if ctx == null:
		return {}
	var story := _story_memory(ctx, id, cue, used_ids)
	if not story.is_empty():
		return story
	return _event_memory(ctx, id, event_id, used_ids)


static func _story_memory(ctx: Node, id: String, cue: String, used_ids: Array) -> Dictionary:
	var story: Variant = ctx.get("story")
	if story == null or not story.has_method("is_open") or not bool(story.call("is_open")):
		return {}
	var store: Variant = story.get("store")
	if store == null or not store.has_method("search") or not store.has_method("witnessed"):
		return {}
	var before := int(store.call("last_line_id")) + 1
	for row: Variant in store.call("search", id, _memory_words(cue), before, 8):
		if row is Dictionary and _memory_ok(row, id, used_ids):
			return {"id": "story:" + str((row as Dictionary).get("id", "")),
				"text": str(story.call("line_text", row, id, true))}
	var recent: Array = store.call("witnessed", id, 24, 0, ["say"])
	for index in range(recent.size() - 1, -1, -1):
		var row: Variant = recent[index]
		if row is Dictionary and _memory_ok(row, id, used_ids):
			return {"id": "story:" + str((row as Dictionary).get("id", "")),
				"text": str(story.call("line_text", row, id, true))}
	return {}


static func _event_memory(ctx: Node, id: String, event_id: String,
		used_ids: Array) -> Dictionary:
	var events: Array = ctx.call("events_for", id, 64)
	for index in range(events.size() - 1, -1, -1):
		var event: Variant = events[index]
		if not event is Dictionary:
			continue
		var row: Dictionary = event
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
		return {"id": key, "text": ("Anon: " if kind == "heard_speech" else "") + text}
	return {}


static func _memory_ok(row: Dictionary, id: String, used_ids: Array) -> bool:
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


static func _memory_words(cue: String) -> Array:
	var words: Array = ["anon"]
	var clean := cue.to_lower().replace("'", " ").replace("’", " ")
	for word: String in clean.split(" ", false):
		if word.length() >= 5 and word not in ["there", "about", "would", "could", "should",
				"really", "maybe", "right", "where", "which", "these", "those", "going", "doing"]:
			words.append(word)
	return words.slice(0, 8)
