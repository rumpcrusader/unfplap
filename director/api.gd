extends "res://mods/unfplap/shared/service.gd"
## Service: director
## Scope: world
## Contract: docs/director.md
## The conversation-director bridge and the one model transport every route speaks through.

const BRIDGE := preload("res://mods/unfplap/director/bridge.gd")

## One bounded completion: the caller's instruction, its JSON-safe payload, the scope and the one
## reply. A bare `Callable` or payload dictionary never crosses the facade.
class Call:
	var system := ""
	var payload: Dictionary = {}
	var scope := ""
	var reply: Callable = Callable()

	static func of(system_in: String, payload_in: Dictionary, scope_in: String,
			reply_in: Callable) -> Call:
		var out := Call.new()
		out.system = system_in
		out.payload = payload_in
		out.scope = scope_in
		out.reply = reply_in
		return out


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
## The bounded classifier node the Proactive service owns, or null. Not this service's to import.
var _classifier: Node = null


func _ready() -> void:
	_bridge.owner = self
	_bridge.hook()


func _process(delta: float) -> void:
	_bridge.process(delta)


## The Proactive service hands over its bounded classifier; every call runs on it.
func attach_classifier(node: Node) -> void:
	_classifier = node


## True while a model call can be made; the Anon-offer watch asks it before it forms anything.
func model_available() -> bool:
	return is_instance_valid(_classifier) and _classifier.has_method("available") \
		and bool(_classifier.available())


## One raw bounded completion. The caller owns the schema and parses the reply.
func complete_raw(call: Call) -> bool:
	if call == null or not call.reply.is_valid() or call.scope.is_empty():
		return false
	if not is_instance_valid(_classifier) or not _classifier.has_method("complete_raw"):
		return false
	return _classifier.complete_raw(call.system, call.payload, call.scope, call.reply)


## Watch the target's next spoken line; the baseline is this service's job, not the caller's.
func await_answer(pony: Node, scope: String, sink: Reply) -> bool:
	if sink == null:
		return false
	return _bridge.await_answer(pony, scope, sink.done)


## Cancel one model scope: its answer watch here and the classifier request behind it.
func cancel_scope(scope: String) -> void:
	if scope.is_empty():
		return
	_bridge.cancel_watch(scope)
	if is_instance_valid(_classifier) and _classifier.has_method("cancel_scope"):
		_classifier.cancel_scope(scope)


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
	_classifier = null
