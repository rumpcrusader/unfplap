extends "res://mods/unfplap/shared/service.gd"
## Service: director
## Scope: world
## Contract: docs/director.md
## The conversation-director bridge: the quiet gate, the lines, the situations and the two watches.

const BRIDGE := preload("res://mods/unfplap/director/bridge.gd")

## One answer or completion sink: the text and the provider error, called once.
class Reply:
	var done: Callable = Callable()

	static func of(handler: Callable) -> Reply:
		var out := Reply.new()
		out.done = handler
		return out


## One new player line's sink: the text alone.
class Line:
	var on_line: Callable = Callable()

	static func of(handler: Callable) -> Line:
		var out := Line.new()
		out.on_line = handler
		return out


## One queued line's validity rule; the queue re-asks it when the line delivers.
class Validity:
	var test: Callable = Callable()

	static func of(rule: Callable) -> Validity:
		var out := Validity.new()
		out.test = rule
		return out


## The live director reads, the player-line baselines and the two watches. Created with the service.
var _bridge := BRIDGE.new()


func _ready() -> void:
	_bridge.owner = self
	_bridge.hook()


func _process(delta: float) -> void:
	_bridge.process(delta)


## Watch the target's next spoken line; the baseline is this service's job, not the caller's.
func await_answer(pony: Node, scope: String, sink: Reply) -> bool:
	if sink == null:
		return false
	return _bridge.await_answer(pony, scope, sink.done)


## Cancel one answer watch by its scope.
func cancel_scope(scope: String) -> void:
	if scope.is_empty():
		return
	_bridge.cancel_watch(scope)


## True when the automatic scan may begin now; the reason names are `quiet_reason`'s.
func quiet(chat_gap_s: float) -> bool:
	return _bridge.quiet(chat_gap_s)


## Why the automatic scan may not begin now, or "" when it may.
func quiet_reason(chat_gap_s: float) -> String:
	return _bridge.quiet_reason(chat_gap_s)


## True while the director is idle.
func idle() -> bool:
	return _bridge.idle()


## Open one authored greeting line; false when the director refuses it.
func begin_greeting(id: String, context: String) -> bool:
	return _bridge.begin_greeting(id, context)


## Queue one authored line with its validity rule; false when the director refuses it.
func queue(id: String, purpose: String, key: String, valid: Validity, priority: bool) -> bool:
	return _bridge.queue(id, purpose, key, valid.test if valid != null else Callable(), priority)


## Record one situation event for the director's world context.
func record_situation(text: String, ids: Array[String], key: String) -> void:
	_bridge.record_situation(text, ids, key)


## Watch the first new player line; the service arms it only while nothing owns the field.
func watch_player(sink: Line) -> void:
	if sink == null:
		return
	_bridge.watch_player(sink.on_line)


## Stop the global player-line watch without touching an answer watch.
func unwatch_player() -> void:
	_bridge.unwatch_player()


## A world entered: hook the new director's transcript; the previous world's watch is gone.
func on_world(_host: Node) -> void:
	_bridge.reset()
	_bridge.hook()


## A world close: the watches and the hook go before the director node does.
func on_world_closed() -> void:
	_bridge.reset()
	_bridge.unhook()


## The entry is leaving.
func shutdown() -> void:
	on_world_closed()
