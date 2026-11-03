extends RefCounted
## AI context and impression writes. Every text is short and non-graphic; the event id makes
## both world_context.record and impressions.commit idempotent.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const WITNESS_RADIUS_M := 8.0


static func start_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "The player just started having sex with you.", [id, "player"], [id, "player"], event_id)


static func cancel_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "The player stopped having sex with you before you reached climax.", [id, "player"], [id, "player"], event_id + ":cancel")


static func climax_event(game: Node, id: String, name: String, event_id: String, count := 1) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "The player just had sex with you. You reached climax."
	if count > 1:
		text = "The player just had sex with you. You reached climax again."
	ctx.record("intimacy", text, [id, "player"], [id, "player"],
		"%s:pony_climax:%d" % [event_id, count])


## Pose 2 after the climax. Direct: she is told he came inside her.
static func inside_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "The player just came inside you.", [id, "player"], [id, "player"], event_id + ":inside")


## Normal dialogue resumes in the afterglow, but the moment is not socially over yet. This
## world-context event keeps that in view without queuing a scripted line.
static func afterglow_text(pose: String) -> String:
	var closeness := "lying close together" if pose != CATALOG.HORSE else "standing close together"
	return "You and Anon just had sex. You are still in the afterglow together, %s; the act has ended, but the moment is not finished yet." % closeness


static func afterglow_event(game: Node, id: String, name: String, event_id: String, pose: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", afterglow_text(pose), [id, "player"], [id, "player"], event_id + ":afterglow")


## One spoken reaction to a named act event. Custom prompts override the fallback; there is no
## probability gate any more. Every mod-owned director key is prefixed so the act owns its lines.
static func reaction_for(game: Node, id: String, event: String, event_id: String, fallback: String, valid: Callable) -> void:
	var custom := SETTINGS.event_prompt(id, event)
	if not is_instance_valid(game) or not game.is_inside_tree():
		return
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return
	var purpose := custom if not custom.is_empty() else fallback
	if event == "climax":
		purpose += " Include a private first-person [thought: ...] impression of this moment in your reply."
	director.call("queue_generated_intent", id, purpose, mod_key(event_id, "reply", event), valid, Callable(), true)


## One on-demand act utterance. The caller supplies the already-formatted private purpose and a
## `valid` guard tied to the act/event. Delivery is asynchronous, so a pending line is the
## runtime's responsibility.
static func utterance_for(game: Node, id: String, event_id: String, key: String, purpose: String, valid: Callable, finished: Callable) -> bool:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return false
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return false
	return bool(director.call("queue_generated_intent", id, purpose, mod_key(event_id, "line", key), valid, finished, true, false))


static func cancel_generated(game: Node, event_id: String, key: String) -> void:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director != null and director.has_method("cancel_authored_line"):
		director.call("cancel_authored_line", mod_key(event_id, "line", key))


static func mod_key(event_id: String, kind: String, key: String) -> String:
	return "unfplap:%s:%s:%s" % [event_id, kind, key]


## Keep only a line that has actually started speaking. A line that is merely queued or still
## being generated must not outlive the act.
static func keep_active_line(state: String, key: String, active: String, keep_speaking: bool) -> bool:
	return keep_speaking and state == "speaking" and not key.is_empty() and key == active


## Drop every mod-owned line for one act. Called at climax/afterglow boundaries and at every
## act end. Returns the number of cancelled lines.
static func cancel_act_lines(game: Node, event_id: String, keep_speaking := true) -> int:
	if not is_instance_valid(game) or not game.is_inside_tree() or event_id.is_empty():
		return 0
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("cancel_authored_line"):
		return 0
	var raw: Variant = director.get("_authored_lines")
	if not raw is Dictionary:
		return 0
	var lines: Dictionary = raw
	var active := str(director.get("_authored_active"))
	var state := str(director.get("state"))
	var prefix := "unfplap:%s:" % event_id
	var cancelled := 0
	for key_value: Variant in lines.keys():
		var key := str(key_value)
		if not key.begins_with(prefix):
			continue
		if keep_active_line(state, key, active, keep_speaking):
			continue
		director.call("cancel_authored_line", key)
		cancelled += 1
	return cancelled


## The horse afterglow close reward. Staying and caressing gets a small romance gain and a
## private thought; staying alone is a warm beat without the extra romance.
static func stay_close_reward(game: Node, id: String, event_id: String, caressed: bool) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "After sex, Anon stayed close and held you for a while."
	if caressed:
		text = "After sex, Anon stayed close, held you and caressed you for a while. You felt cared for."
	ctx.record("intimacy", text, [id, "player"], [id, "player"], event_id + ":stay_close")
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions):
		return
	var thought := "He stayed close after; I felt cared for."
	if caressed:
		thought = "He stayed close and caressed me after; I felt cared for."
	var data := {"mood": "happy", "thought": thought}
	if caressed:
		data["romance"] = 1
	impressions.commit(id, data, event_id + ":stay_close_gain")


static func stop_event(game: Node, id: String, name: String, event_id: String, reason: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "The player stopped having sex with you."
	match reason:
		"unwilling":
			text = "You stopped having sex with the player because you no longer wanted to."
		"picked up":
			text = "The player picked you up, so you stopped having sex."
		"interrupted":
			text = "Your sex with the player was interrupted."
		"form change":
			text = "The player changed form, so the sex stopped."
		"world close":
			text = "The world closed during sex with the player."
	ctx.record("intimacy", text, [id, "player"], [id, "player"], event_id + ":stop:" + reason)


static func commit_climax(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions):
		return
	impressions.commit(id, {
		"romance": 2,
		"mood": "happy"
	}, event_id + ":gain")


static func witnesses(game: Node, partner_id: String, partner_name: String, serial: int, partner: Node3D) -> void:
	var ctx = _context(game)
	if ctx == null or not is_instance_valid(partner) or not is_instance_valid(game):
		return
	var list: Variant = game.get("mares")
	if not list is Array:
		return
	var here: Node3D = HOUSE.at(partner.get_tree(), partner.global_position)
	var young_player: bool = PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree()))
	if young_player:
		return
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner:
			continue
		if observer.global_position.distance_to(partner.global_position) > WITNESS_RADIUS_M:
			continue
		if bool(observer.get("sleeping")):
			continue
		var identity: Variant = observer.get("identity")
		if identity == null or bool(identity.get("filly")):
			continue
		var observer_id := str(observer.get_meta("relationship_id", ""))
		if observer_id.is_empty():
			observer_id = str(identity.get("id"))
		if observer_id.is_empty():
			continue
		var runtime: Variant = observer.get_meta("relationship_runtime")
		if runtime == null or not is_instance_valid(runtime):
			continue
		if not bool(runtime.bonds.adults.get(observer_id, false)):
			continue
		var their_house: Node3D = HOUSE.at(observer.get_tree(), observer.global_position)
		var same_house := here != null and their_house == here
		if not same_house and observer.global_position.distance_to(partner.global_position) > WITNESS_RADIUS_M:
			continue
		var event_id := "witness_%s_%s_%d" % [observer_id, partner_id, serial]
		ctx.record("witnessed_intimacy", "You saw Anon and %s having sex." % partner_name,
			[observer_id, "player", partner_id], [partner_id, "player"], event_id)
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions):
			impressions.commit(observer_id, {
				"mood": "surprised",
				"thought": "I walked in on Anon and %s." % partner_name
			}, event_id + ":gain")


## Private facts for the cue prompt. No raw scores or counts leave this function.
static func cue_facts(game: Node, id: String, event_id: String) -> Dictionary:
	var out: Dictionary = {}
	if not is_instance_valid(game):
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
		if love is Dictionary:
			out["love"] = str((love as Dictionary).get("name", ""))
			out["love_level"] = int((love as Dictionary).get("level", -1))
	var bonds: Variant = rel.get("bonds")
	if bonds is Node and is_instance_valid(bonds) and bonds.has_method("record_for"):
		var record: Variant = bonds.call("record_for", id)
		if record is Dictionary:
			out["stage"] = str((record as Dictionary).get("stage", ""))
			out["anger"] = float((record as Dictionary).get("anger", 0.0))
	var ctx := _context(game)
	if ctx != null:
		if ctx.has_method("events_for"):
			var prior := 0
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
			out["first_time"] = prior == 0
		var impressions: Variant = ctx.get("impressions")
		if impressions is Node and is_instance_valid(impressions) and impressions.has_method("profile"):
			var profile: Variant = impressions.call("profile", id)
			if profile is Dictionary:
				out["mood"] = str((profile as Dictionary).get("mood", ""))
	out["careful"] = str(out.get("mood", "")) == "annoyed" \
		or float(out.get("anger", 0.0)) > 0.0
	return out


## One unused shared memory for the cue prompt. The story journal is preferred because it keeps
## the actual exchange; the older world-context events are the fallback.
static func shared_memory(game: Node, id: String, cue: String, event_id: String,
		used_ids: Array) -> Dictionary:
	var peak := peak_memory(id)
	if not peak.is_empty():
		var peak_id := "peak:" + id
		var peak_text := str(peak.get("text", "")).strip_edges()
		if not (peak_id in used_ids) and not peak_text.is_empty():
			return {"id": peak_id, "text": peak_text}
	var ctx := _context(game)
	if ctx == null:
		return {}
	var story := _story_memory(ctx, id, cue, used_ids)
	if not story.is_empty():
		return story
	return _event_memory(ctx, id, event_id, used_ids)


## The strongest peak act is a mod-owned, per-world record. It is separate from the story
## summary so a compressed summary cannot lose the exchange that mattered.
static func peak_memory(id: String) -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	var state: Variant = mods.call("state", "unfplap")
	if not state is Dictionary:
		return {}
	var rows: Variant = (state as Dictionary).get("peak_memories", {})
	if not rows is Dictionary:
		return {}
	var row: Variant = (rows as Dictionary).get(id, {})
	return (row as Dictionary).duplicate(true) if row is Dictionary else {}


static func record_peak_memory(id: String, event_id: String, text: String, score: float) -> void:
	var mods := _mods()
	if mods == null:
		return
	var state: Variant = mods.call("state", "unfplap")
	if not state is Dictionary:
		return
	var rows: Variant = (state as Dictionary).get("peak_memories", {})
	if not rows is Dictionary:
		rows = {}
	var old: Variant = (rows as Dictionary).get(id, {})
	if old is Dictionary and float((old as Dictionary).get("score", -1.0)) >= score:
		return
	(rows as Dictionary)[id] = {
		"text": text,
		"score": score,
		"event_id": event_id,
		"at": Time.get_unix_time_from_system(),
	}
	(state as Dictionary)["peak_memories"] = rows
	if mods.has_method("save_changed"):
		mods.call("save_changed")


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")


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


static func _event_memory(ctx: Node, id: String, event_id: String, used_ids: Array) -> Dictionary:
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


static func _context(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var ctx: Variant = game.get("world_context")
	if ctx is Node and is_instance_valid(ctx):
		return ctx
	return null
