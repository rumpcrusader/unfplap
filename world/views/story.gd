extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## The world context's story journal, its line store and its event list, bound to the context node.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _context: Node


func _init(context: Node) -> void:
	_context = context


func _bound() -> Node:
	return _context


## The context's story journal; null when it has none.
func journal() -> Object:
	return GAME.story_of(_context)


## The journal's line store; null when it has none.
func store() -> Object:
	return GAME.story_store(journal())


## True while the journal can answer lines.
func open() -> bool:
	return GAME.story_open(journal())


## The newest line id the store holds; -1 without the reader.
func last_line_id() -> int:
	return GAME.story_last_line_id(store())


## The store's matching lines, newest first; a typed copy, empty without the reader.
func search(pony: String, words: Array[String], before: int, limit: int) -> Array[GAME.StoryRow]:
	return GAME.story_search(store(), pony, words, before, limit)


## The store's recent witnessed lines; a typed copy, empty without the reader.
func witnessed(pony: String, limit: int, before: int, kinds: Array[String]) -> Array[GAME.StoryRow]:
	return GAME.story_witnessed(store(), pony, limit, before, kinds)


## One stored line's text through the journal's own reader.
func line_text(row: GAME.StoryRow, pony: String, with_day: bool) -> String:
	return GAME.story_line_text(journal(), row, pony, with_day)


## The context's recent events for one pony; empty without the reader.
func events(id: String, limit: int) -> Array[Dictionary]:
	return GAME.world_events(_context, id, limit)
