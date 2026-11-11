extends RefCounted
## AI context and impression writes. Every text is short and non-graphic. A witness text is a
## perception, never a conclusion: the game's per-pony story summary forms her memory from it.
## The event id makes both world_context.record and impressions.commit idempotent.
##
## Event text also appears in the profile's Recent activities. The profile rewrites only a
## leading "You and Anon " into "You and <name>", so the rest of an event line must not use
## second-person pronouns for the pony. The private impression thought stays first-person.

const HOUSE := preload("res://world/buildings/house_interior.gd")
const AWARENESS := preload("res://world/ai/pony_awareness.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const ACT_FACE := preload("res://mods/unfplap/act_face.gd")


static func cancel_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "Anon stopped before the act reached a climax.", [id, "player"], [id, "player"], event_id + ":cancel")


static func climax_event(game: Node, id: String, name: String, event_id: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("intimacy", "You and Anon made love, and she came.",
		[id, "player"], [id, "player"], event_id + ":pony_climax")


## One spoken reaction to a named act event. Custom prompts override the fallback; there is no
## probability gate any more. Every mod-owned director key is prefixed so the act owns its lines.
## Returns the director key on acceptance, or "" when nothing was queued.
static func reaction_for(game: Node, id: String, event: String, event_id: String, fallback: String, valid: Callable) -> String:
	var custom := SETTINGS.event_prompt(id, event)
	if not is_instance_valid(game) or not game.is_inside_tree():
		return ""
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return ""
	var purpose := custom if not custom.is_empty() else fallback
	if event == "climax":
		purpose += " Include a private first-person [thought: ...] impression of this moment in your reply."
	if SETTINGS.act_faces.get_bool() and not purpose.contains("[face"):
		purpose += ACT_FACE.prompt_note(event)
	var key := mod_key(event_id, "reply", event)
	var queued := bool(director.call("queue_generated_intent", id, purpose, key, valid, Callable(), true))
	return key if queued else ""


## One on-demand act utterance. The caller supplies the already-formatted private purpose and a
## `valid` guard tied to the act/event. Delivery is asynchronous, so a pending line is the
## runtime's responsibility. Returns the full director key on acceptance.
static func utterance_for(game: Node, id: String, event_id: String, key: String, purpose: String, valid: Callable, finished: Callable) -> String:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return ""
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return ""
	var director_key := mod_key(event_id, "line", key)
	var queued := bool(director.call("queue_generated_intent", id, purpose, director_key, valid, finished, true, false))
	return director_key if queued else ""


## Cancel one mod-owned authored line by its full director key. A queued row is erased; an active
## row is also interrupted by the director, so the caller must only use this on queued or
## generating rows and must not cut a speaking line.
static func cancel_line(game: Node, key: String) -> void:
	if key.is_empty() or not is_instance_valid(game) or not game.is_inside_tree():
		return
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director != null and director.has_method("cancel_authored_line"):
		director.call("cancel_authored_line", key)


## What the director currently holds for one mod-owned key.
##   absent     the row was erased (cancelled or never accepted)
##   queued     accepted, not claimed yet; safe to erase
##   generating claimed and thinking/rendering; safe to erase, no audio yet
##   speaking   audio is playing or a sentence of a multi-sentence line was already heard
##   delivered  the final sentence was delivered; the slot may release
##   unknown    the director or its queue is not readable; fall back to the age
static func line_state(game: Node, key: String) -> String:
	if key.is_empty() or not is_instance_valid(game) or not game.is_inside_tree():
		return "unknown"
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("cancel_authored_line"):
		return "unknown"
	var raw: Variant = director.get("_authored_lines")
	if not raw is Dictionary:
		return "unknown"
	var lines: Dictionary = raw
	if not lines.has(key):
		return "absent"
	var value: Variant = lines[key]
	if not value is Dictionary:
		return "absent"
	var row: Dictionary = value
	if bool(row.get("delivered", false)):
		return "delivered"
	if not bool(row.get("started", false)):
		return "queued"
	if str(director.get("_authored_active")) != key:
		return "queued"
	if str(director.get("state")) == "speaking":
		return "speaking"
	var heard: Variant = row.get("heard", [])
	if heard is Array and not (heard as Array).is_empty() \
			and str(director.get("state")) == "rendering":
		# A multi-sentence line between beats: it already played audio, so do not cut the rest.
		return "speaking"
	return "generating"


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


## The standing afterglow close reward. A positive act gets a small romance gain and a happy
## mood; after a bad act, staying close is a repair beat with a private thought but no romance.
static func stay_close_reward(game: Node, id: String, event_id: String, caressed: bool,
		positive := true) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions):
		return
	var thought := "He stayed close after; I felt cared for."
	var data: Dictionary = {}
	if positive:
		data["mood"] = "happy"
		if caressed:
			thought = "He stayed close and caressed me after; I felt cared for."
			data["romance"] = 1
	else:
		thought = "He stayed close after, even though I was hurt; it helped a little."
	data["thought"] = thought
	impressions.commit(id, data, event_id + ":stay_close_gain")


static func stop_event(game: Node, id: String, name: String, event_id: String, reason: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "The act stopped."
	match reason:
		"unwilling":
			text = "The act stopped because she no longer wanted it."
		"picked up":
			text = "Anon picked up, so the act stopped."
		"interrupted":
			text = "The act was interrupted."
		"form change":
			text = "Anon changed form, so the act stopped."
		"world close":
			text = "The world closed during the act."
		"withdrew":
			text = "Anon kept doing something she does not like, so the act stopped."
	ctx.record("intimacy", text, [id, "player"], [id, "player"], event_id + ":stop:" + reason)


## An act attempt she turned down. The game's mood is the impression note, not a scripted feeling:
## `angry` blocks kisses (`docs/eligibility.md`) and is `bonds.anger()` 70 for the note's 300 s
## freshness; `annoyed` is 40, which still blocks relationship offers and resting closeness.
## A buck is the stronger moment, so it commits the stronger mood.
static func refusal_event(game: Node, id: String, name: String, event_id: String,
		bucked: bool) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var text := "She turned Anon away when he wanted more."
	var thought := "He wanted more than I did. I said no and turned him away."
	if bucked:
		text = "She turned Anon away and bucked him when he would not stop."
		thought = "He kept pushing after I said no, so I bucked him off. I need space."
	ctx.record("intimacy", text, [id, "player"], [id, "player"], event_id)
	var impressions: Variant = ctx.get("impressions")
	if impressions == null or not is_instance_valid(impressions):
		return
	impressions.commit(id, {"mood": "angry" if bucked else "annoyed", "thought": thought},
		event_id + ":mood")


## Grade-aware act impression. A good act gives romance +2 and a happy mood, a neutral one +1,
## and a bad one -1 with a sad or annoyed mood. The summary text is also kept as a relationship
## event so a later prompt can recall the specific act.
static func commit_act(game: Node, id: String, name: String, event_id: String,
		outcome: Dictionary, early := false) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	var impressions: Variant = ctx.get("impressions")
	if impressions != null and is_instance_valid(impressions):
		var data: Dictionary = {"mood": str(outcome.get("mood", "relaxed"))}
		var romance := int(outcome.get("romance", 0))
		if romance != 0:
			data["romance"] = romance
		var thought := str(outcome.get("thought", "")).strip_edges()
		if not thought.is_empty():
			data["thought"] = thought.left(240)
		impressions.commit(id, data, event_id + (":summary" if early else ":gain"))
	var text := str(outcome.get("text", "")).strip_edges()
	if not text.is_empty():
		ctx.record("relationship", text, [id, "player"], [id, "player"], event_id + ":summary")


## A sincere apology outside an act. The repair itself lives in act_history; this only keeps the
## moment in her story memory.
static func history_apology(game: Node, id: String, _text: String) -> void:
	var ctx = _context(game)
	if ctx == null:
		return
	ctx.record("relationship", "Anon apologized for last time.",
		[id, "player"], [id, "player"], "apology:%s:%d" % [id, Time.get_ticks_usec()])


## integration: adult ponies who can perceive the act right now, using the modern witness rules.
## This is a read-only observer list; it commits no memory. Young ponies are never included.
static func perceived_adults(game: Node, partner: Node3D) -> Array:
	var out: Array = []
	if not is_instance_valid(partner) or not is_instance_valid(game) or not partner.is_inside_tree():
		return out
	if PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree())):
		return out
	var list: Variant = game.get("mares")
	if not list is Array:
		return out
	var awareness := AWARENESS.new()
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner or not observer.is_inside_tree():
			continue
		if bool(observer.get("sleeping")):
			continue
		var identity: Variant = observer.get("identity")
		if not FACTS.adult_pony_identity(identity, false):
			continue
		var observer_id := str(observer.get_meta("relationship_id", ""))
		if observer_id.is_empty():
			observer_id = str(identity.get("id"))
		if observer_id.is_empty():
			continue
		var seen := awareness.visible(observer, partner)
		var heard := false if seen else awareness.can_hear(observer, partner, AWARENESS.HEARING_RANGE)
		if not seen and not heard:
			continue
		out.append({"id": observer_id, "node": observer, "sense": "sight" if seen else "sound",
			"indoors": HOUSE.at(observer.get_tree(), observer.global_position) != null})
	return out


## integration: one line from a pony watching the act. Owned by the act, so its end cancels it.
static func bystander_line(game: Node, id: String, event_id: String, purpose: String,
		valid: Callable) -> bool:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return false
	var director: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if director == null or not director.has_method("queue_generated_intent"):
		return false
	return bool(director.call("queue_generated_intent", id, purpose,
		mod_key(event_id, "bystander", id), valid, Callable(), true))



## One event per observer, private to her (`witnesses = [observer_id]`). Adults are told what it
## was; fillies and colts get a perception with the place they saw it from, and the game's story
## summary infers a memory they could actually hold. Returns one debug row per recorded witness.
static func witnesses(game: Node, partner_id: String, partner_name: String, serial: int, partner: Node3D) -> Array:
	var ctx = _context(game)
	if ctx == null or not is_instance_valid(partner) or not is_instance_valid(game):
		return []
	if not partner.is_inside_tree():
		return []
	var list: Variant = game.get("mares")
	if not list is Array:
		return []
	var young_player: bool = PLAYER_FORM.is_young(PLAYER_FORM.active(partner.get_tree()))
	if young_player:
		return []
	var rows: Array = []
	var awareness := AWARENESS.new()
	for node: Variant in list:
		if not is_instance_valid(node):
			continue
		var observer: Node3D = node as Node3D
		if observer == null or observer == partner or not observer.is_inside_tree():
			continue
		if bool(observer.get("sleeping")):
			continue
		var identity: Variant = observer.get("identity")
		if identity == null:
			continue
		var observer_id := str(observer.get_meta("relationship_id", ""))
		if observer_id.is_empty():
			observer_id = str(identity.get("id"))
		if observer_id.is_empty():
			continue
		var young := FACTS.young_identity(identity)
		if not young and not FACTS.adult_pony_identity(identity, false):
			continue
		var seen := awareness.visible(observer, partner)
		var heard := false
		if not seen:
			heard = awareness.can_hear(observer, partner, AWARENESS.HEARING_RANGE)
		if not seen and not heard:
			continue
		var indoors: bool = HOUSE.at(observer.get_tree(), observer.global_position) != null
		var place := str(AWARENESS.place_at(observer.global_position).get("id", ""))
		var text := witness_text(partner_name, young, indoors, serial)
		var event_id := "witness_%s_%s_%d" % [observer_id, partner_id, serial]
		ctx.record(witness_kind(young), text, [observer_id], [partner_id, "player"], event_id, place)
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions):
			impressions.commit(observer_id, witness_impression(partner_name, young, indoors), event_id + ":gain")
		rows.append({
			"id": observer_id,
			"young": young,
			"sense": "sight" if seen else "sound",
			"indoors": indoors,
			"distance": observer.global_position.distance_to(partner.global_position),
			"place": place,
			"text": text,
		})
	return rows


static func witness_kind(young: bool) -> String:
	return "witnessed_scene" if young else "witnessed_intimacy"


static func witness_scene_prefix(partner_name: String, indoors: bool) -> String:
	if indoors:
		return "She walked in on Anon and %s." % partner_name
	return "She saw Anon and %s out in the open." % partner_name


## Perception plus uncertainty, never a conclusion. Each act picks a different one so repeated
## memories and retold gossip do not read the same.
const WITNESS_TAILS := [
	" They were moving about together and making happy sounds, and she could not tell what they were doing.",
	" They seemed to be playing some game, and she was not sure what the game was.",
	" They were busy together and giggling, and she could not tell what it was about.",
]


static func witness_text(partner_name: String, young: bool, indoors: bool, serial: int) -> String:
	if not young:
		return "She saw Anon and %s having sex." % partner_name
	var index := posmod(serial, WITNESS_TAILS.size())
	return witness_scene_prefix(partner_name, indoors) + str(WITNESS_TAILS[index])


static func witness_thought(partner_name: String, young: bool, indoors: bool) -> String:
	if young:
		return ""
	if indoors:
		return "I walked in on Anon and %s having sex." % partner_name
	return "I saw Anon and %s having sex out in the open." % partner_name


static func witness_impression(partner_name: String, young: bool, indoors: bool) -> Dictionary:
	var out: Dictionary = {"mood": "amused"} if young else {"mood": "surprised"}
	var thought := witness_thought(partner_name, young, indoors)
	if not thought.is_empty():
		out["thought"] = thought
	return out


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
	var ctx := _context(game)
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
		var impressions: Variant = ctx.get("impressions")
		if impressions is Node and is_instance_valid(impressions) and impressions.has_method("profile"):
			var profile: Variant = impressions.call("profile", id)
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
