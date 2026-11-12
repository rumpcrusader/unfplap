extends RefCounted
## Scene adapter: the only reader of the conversation director's authored-line queue. The facade
## never touches a director field. Every lookup is guarded: a game change that removes the queue
## makes the mod's lines stop instead of erroring.

const FACTS := preload("res://mods/unfplap/memory/facts.gd")
const TEXT := preload("res://mods/unfplap/memory/text.gd")


static func queue(game: Node, id: String, purpose: String, key: String,
		valid: Callable, finished: Callable) -> bool:
	var director := _queue_director(game)
	if director == null:
		return false
	return bool(director.call("queue_generated_intent", id, purpose, key, valid, finished,
		true, false))


static func cancel(game: Node, key: String) -> void:
	if key.is_empty():
		return
	var director := _line_director(game)
	if director != null:
		director.call("cancel_authored_line", key)


## What the director currently holds for one mod-owned key, as a `FACTS.LineState` value.
static func state(game: Node, key: String) -> int:
	if key.is_empty():
		return FACTS.LineState.UNKNOWN
	var director := _line_director(game)
	if director == null:
		return FACTS.LineState.UNKNOWN
	var raw: Variant = director.get("_authored_lines")
	if not raw is Dictionary:
		return FACTS.LineState.UNKNOWN
	var lines: Dictionary = raw
	if not lines.has(key):
		return FACTS.LineState.ABSENT
	var value: Variant = lines[key]
	if not value is Dictionary:
		return FACTS.LineState.ABSENT
	var row: Dictionary = value
	if bool(row.get("delivered", false)):
		return FACTS.LineState.DELIVERED
	if not bool(row.get("started", false)):
		return FACTS.LineState.QUEUED
	if str(director.get("_authored_active")) != key:
		return FACTS.LineState.QUEUED
	if str(director.get("state")) == "speaking":
		return FACTS.LineState.SPEAKING
	var heard: Variant = row.get("heard", [])
	if heard is Array and not (heard as Array).is_empty() \
			and str(director.get("state")) == "rendering":
		# A multi-sentence line between beats: it already played audio, so do not cut the rest.
		return FACTS.LineState.SPEAKING
	return FACTS.LineState.GENERATING


## Cancel every mod-owned line of one act, keeping a line that has started speaking.
static func cancel_prefix(game: Node, prefix: String, keep_speaking: bool) -> int:
	if prefix.is_empty():
		return 0
	var director := _line_director(game)
	if director == null:
		return 0
	var raw: Variant = director.get("_authored_lines")
	if not raw is Dictionary:
		return 0
	var lines: Dictionary = raw
	var active := str(director.get("_authored_active"))
	var cancelled := 0
	for key_value: Variant in lines.keys():
		var key := str(key_value)
		if not key.begins_with(prefix):
			continue
		if TEXT.keep_active(state(game, key), key, active, keep_speaking):
			continue
		director.call("cancel_authored_line", key)
		cancelled += 1
	return cancelled


static func _queue_director(game: Node) -> Node:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return null
	var found: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if found == null or not found.has_method("queue_generated_intent"):
		return null
	return found


static func _line_director(game: Node) -> Node:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return null
	var found: Node = game.get_tree().get_first_node_in_group("conversation_director")
	if found == null or not found.has_method("cancel_authored_line"):
		return null
	return found
