extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## The scene's conversation director and its world context: TTS, voice, impressions and the lines.

const GAME := preload("res://mods/unfplap/world/game.gd")
const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")

var _director: Node
## The scene the director belongs to: the world context and its impressions are that scene's reads.
var _world: Node


func _init(director: Node, world: Node) -> void:
	_director = director
	_world = world


func _bound() -> Node:
	return _director


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The game's settings autoload, read at the root so a suite runtime without one answers false.
func _settings() -> Node:
	var tree := _tree()
	return tree.root.get_node_or_null("Settings") if tree != null else null


## True while the director is doing anything but idling.
func speaking() -> bool:
	return GAME.director_speaking(_director)


## Cut the director's current line; a director without the op is left alone.
func interrupt() -> void:
	GAME.interrupt_director(_director)


## The director's own clock in seconds; NAN when it has none.
func clock() -> float:
	return GAME.director_now(_director)


## Whether an approach or a group exchange reports itself active; the subsystem is not the receiver.
func subsystem_active(node: Object) -> bool:
	return GAME.subsystem_active(node)


## The director's authored-line host: the greeting, the queue and the cancel.
func lines() -> GAME.DirectorLines:
	return GAME.director_lines(_director)


## The director's live model configuration, typed for the classifier's own setup.
func llm_config() -> GAME.LlmConfig:
	return GAME.llm_config(_director)


## Prepare her generated voice cache for the act; absent when the director has no voice loop.
func prepare_vocal(pony_id: String) -> void:
	GAME.prepare_vocal(_director, pony_id)


## Record one world-context event with its kind and text; `place` is empty for an unwitnessed one.
func record_event(kind: String, text: String, witnesses: Array[String], subjects: Array[String],
		event_id: String, place: String = "") -> void:
	GAME.world_record(world_context(), kind, text, witnesses, subjects, event_id, place)


## Record one replaceable situation event; `ids` is the subject list and `key` the event key.
func record_situation(text: String, ids: Array[String], key: String) -> void:
	GAME.record_situation(world_context(), text, ids, key)


## The game's own TTS switch; false without a settings autoload.
func tts_enabled() -> bool:
	return GAME.tts_enabled(_settings())


## The director's TTS node; null when it has none.
func tts() -> Node:
	return GAME.tts_of(_director)


## True while this TTS node reports a running speech server; the node is not the receiver.
func tts_running(tts: Node) -> bool:
	return GAME.tts_has_server(tts)


## Play one line through the game's own vocal node; false without the op.
func play_vocal(vocal: Node, id: String, gender: String, pony: Node3D, db: float) -> bool:
	return GAME.vocal_play(vocal, id, gender, pony, db)


## One kiss sound through her own boop node; false without the op.
func play_kiss(boop: Node, db: float, loop: bool) -> bool:
	return GAME.play_kiss(boop, db, loop)


## The scene's world-context node; null outside a world.
func world_context() -> Node:
	return GAME.world_context(_world)


## The world context's impressions store; null when it has none.
func impressions() -> Node:
	return GAME.impressions_of(world_context())


## One pony's committed mood; `absent` when the store has a profile without a mood.
func impression_mood(id: String, absent: String = "neutral") -> String:
	return GAME.impression_mood(impressions(), id, absent)


## Write one mood change; false without a store or a commit op.
func set_impression_mood(id: String, mood: String, key: String) -> bool:
	return GAME.impression_set_mood(impressions(), id, mood, key)


## Commit one impression row through the store's own writer; false without the op.
func commit_impression(id: String, mood: String, romance: int, thought: String,
		event_id: String) -> bool:
	return GAME.impression_commit(impressions(), id, mood, romance, thought, event_id)


## The store's one-line standing note; empty without the op.
func standing_line(id: String) -> String:
	return GAME.impression_standing_line(impressions(), id)


## The live voice routing facts for one stable id, so the classifier itself reads no game node.
func voice_facts(id: String) -> VOICE.Facts:
	var out := VOICE.Facts.new()
	var route := GAME.voice_route(_director, id)
	out.profile = route.profile
	out.global_mode = route.mode
	out.server = route.server
	out.tts_enabled = tts_enabled()
	out.ponese = route.ponese
	out.chatter = route.chatter
	return out
